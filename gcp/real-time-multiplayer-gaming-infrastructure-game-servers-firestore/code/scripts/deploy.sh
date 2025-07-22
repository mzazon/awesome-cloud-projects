#!/bin/bash

# Real-Time Multiplayer Gaming Infrastructure Deployment Script
# This script deploys a complete gaming infrastructure with Game Servers, Cloud Firestore, 
# Cloud Run matchmaking service, and global load balancing.

set -euo pipefail

# Configuration and Logging
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deployment-config"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "${BLUE}INFO${NC}" "$@"; }
warn() { log "${YELLOW}WARN${NC}" "$@"; }
error() { log "${RED}ERROR${NC}" "$@"; }
success() { log "${GREEN}SUCCESS${NC}" "$@"; }

# Error handling
cleanup_on_error() {
    error "Deployment failed. Check ${LOG_FILE} for details."
    error "To clean up partial deployment, run: ./destroy.sh"
    exit 1
}

trap cleanup_on_error ERR

# Configuration validation
validate_prerequisites() {
    info "Validating prerequisites..."
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        error "Helm is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    # Verify gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    success "Prerequisites validated successfully"
}

# Project setup and configuration
setup_environment() {
    info "Setting up environment variables..."
    
    # Generate or load configuration
    if [[ -f "${CONFIG_FILE}" ]]; then
        info "Loading existing configuration from ${CONFIG_FILE}"
        source "${CONFIG_FILE}"
    else
        info "Creating new deployment configuration..."
        
        # Set default values or prompt for input
        export PROJECT_ID="${PROJECT_ID:-gaming-project-$(date +%s)}"
        export REGION="${REGION:-us-central1}"
        export ZONE="${ZONE:-us-central1-a}"
        export CLUSTER_NAME="${CLUSTER_NAME:-game-cluster}"
        
        # Generate unique suffix for resource names
        local random_suffix=$(openssl rand -hex 3)
        export GAME_SERVER_CONFIG="game-config-${random_suffix}"
        export FIRESTORE_DATABASE="game-db-${random_suffix}"
        export CLOUD_RUN_SERVICE="matchmaking-api-${random_suffix}"
        
        # Save configuration for future use
        cat > "${CONFIG_FILE}" << EOF
# Gaming Infrastructure Deployment Configuration
# Generated on $(date)
export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export ZONE="${ZONE}"
export CLUSTER_NAME="${CLUSTER_NAME}"
export GAME_SERVER_CONFIG="${GAME_SERVER_CONFIG}"
export FIRESTORE_DATABASE="${FIRESTORE_DATABASE}"
export CLOUD_RUN_SERVICE="${CLOUD_RUN_SERVICE}"
EOF
        
        info "Configuration saved to ${CONFIG_FILE}"
    fi
    
    # Set gcloud configuration
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    info "Environment configured:"
    info "  Project ID: ${PROJECT_ID}"
    info "  Region: ${REGION}"
    info "  Zone: ${ZONE}"
    info "  Cluster Name: ${CLUSTER_NAME}"
    info "  Random Suffix: ${random_suffix:-loaded from config}"
}

# Enable required Google Cloud APIs
enable_apis() {
    info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "gameservices.googleapis.com"
        "container.googleapis.com"
        "run.googleapis.com"
        "firestore.googleapis.com"
        "compute.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        info "Enabling ${api}..."
        gcloud services enable "${api}" --quiet
    done
    
    # Wait for APIs to be fully enabled
    info "Waiting for APIs to be fully activated..."
    sleep 30
    
    success "All required APIs enabled successfully"
}

# Create GKE cluster with Agones optimization
create_gke_cluster() {
    info "Creating GKE cluster optimized for gaming workloads..."
    
    # Check if cluster already exists
    if gcloud container clusters describe "${CLUSTER_NAME}" --zone="${ZONE}" &>/dev/null; then
        warn "Cluster ${CLUSTER_NAME} already exists. Skipping creation."
        return 0
    fi
    
    gcloud container clusters create "${CLUSTER_NAME}" \
        --zone="${ZONE}" \
        --machine-type=e2-standard-4 \
        --num-nodes=3 \
        --enable-autoscaling \
        --min-nodes=1 \
        --max-nodes=10 \
        --enable-network-policy \
        --enable-ip-alias \
        --disk-size=50GB \
        --enable-autorepair \
        --enable-autoupgrade \
        --maintenance-window-start="2023-01-01T09:00:00Z" \
        --maintenance-window-end="2023-01-01T17:00:00Z" \
        --maintenance-window-recurrence="FREQ=WEEKLY;BYDAY=SA" \
        --quiet
    
    # Get cluster credentials
    gcloud container clusters get-credentials "${CLUSTER_NAME}" --zone="${ZONE}" --quiet
    
    # Verify cluster is running
    local max_attempts=30
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        if kubectl cluster-info &>/dev/null; then
            success "GKE cluster created and accessible"
            return 0
        fi
        
        info "Waiting for cluster to be ready (attempt ${attempt}/${max_attempts})..."
        sleep 10
        ((attempt++))
    done
    
    error "Cluster creation timed out"
    return 1
}

# Install Agones game server controller
install_agones() {
    info "Installing Agones game server controller..."
    
    # Create namespace if it doesn't exist
    kubectl create namespace agones-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Add Agones Helm repository
    helm repo add agones https://agones.dev/chart/stable
    helm repo update
    
    # Check if Agones is already installed
    if helm list -n agones-system | grep -q agones; then
        warn "Agones is already installed. Skipping installation."
    else
        # Install Agones with gaming-optimized settings
        helm install agones agones/agones \
            --namespace agones-system \
            --set "gameservers.minPort=7000" \
            --set "gameservers.maxPort=8000" \
            --set "gameservers.podPreserveUnknownFields=false" \
            --wait \
            --timeout=10m
    fi
    
    # Wait for Agones to be ready
    info "Waiting for Agones controller to be ready..."
    kubectl wait --for=condition=available deployment \
        --all --namespace=agones-system --timeout=300s
    
    success "Agones controller installed and ready"
}

# Create Cloud Firestore database
create_firestore_database() {
    info "Creating Cloud Firestore database for real-time state management..."
    
    # Check if database already exists
    if gcloud firestore databases describe --database="${FIRESTORE_DATABASE}" &>/dev/null; then
        warn "Firestore database ${FIRESTORE_DATABASE} already exists. Skipping creation."
        return 0
    fi
    
    # Create Firestore database in native mode
    gcloud firestore databases create \
        --location="${REGION}" \
        --database="${FIRESTORE_DATABASE}" \
        --quiet
    
    # Create initial game collections structure
    cat > "${SCRIPT_DIR}/game-schema.json" << 'EOF'
{
  "games": {
    "game-session-id": {
      "players": {},
      "gameState": {},
      "metadata": {
        "created": "timestamp",
        "lastUpdated": "timestamp",
        "status": "waiting|active|completed"
      }
    }
  },
  "players": {
    "player-id": {
      "currentGame": "game-session-id",
      "profile": {},
      "stats": {}
    }
  }
}
EOF
    
    success "Firestore database created with gaming schema"
}

# Deploy game server fleet
deploy_game_server_fleet() {
    info "Deploying game server fleet configuration..."
    
    # Create game server fleet manifest
    cat > "${SCRIPT_DIR}/gameserver-fleet.yaml" << 'EOF'
apiVersion: "agones.dev/v1"
kind: Fleet
metadata:
  name: simple-game-server-fleet
spec:
  replicas: 2
  template:
    spec:
      ports:
      - name: default
        containerPort: 7654
        protocol: UDP
      health:
        disabled: false
        initialDelaySeconds: 5
        periodSeconds: 5
        failureThreshold: 3
      template:
        spec:
          containers:
          - name: simple-game-server
            image: gcr.io/agones-images/simple-game-server:0.12
            resources:
              requests:
                memory: "64Mi"
                cpu: "20m"
              limits:
                memory: "128Mi"
                cpu: "50m"
EOF
    
    # Deploy the fleet
    kubectl apply -f "${SCRIPT_DIR}/gameserver-fleet.yaml"
    
    # Wait for fleet to be ready
    info "Waiting for game server fleet to be ready..."
    kubectl wait --for=condition=ready fleet/simple-game-server-fleet --timeout=300s
    
    success "Game server fleet deployed and ready"
}

# Create and deploy Cloud Run matchmaking service
deploy_matchmaking_service() {
    info "Creating and deploying Cloud Run matchmaking service..."
    
    # Create matchmaking service directory
    local service_dir="${SCRIPT_DIR}/matchmaking-service"
    mkdir -p "${service_dir}"
    
    # Create package.json
    cat > "${service_dir}/package.json" << 'EOF'
{
  "name": "matchmaking-service",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "express": "^4.18.2",
    "@google-cloud/firestore": "^7.1.0",
    "kubernetes-client": "^12.0.0"
  }
}
EOF
    
    # Create matchmaking logic
    cat > "${service_dir}/index.js" << 'EOF'
const express = require('express');
const { Firestore } = require('@google-cloud/firestore');
const k8s = require('kubernetes-client');

const app = express();
const port = process.env.PORT || 8080;
const firestore = new Firestore();

app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.post('/matchmake', async (req, res) => {
  try {
    const { playerId, gameMode } = req.body;
    
    if (!playerId || !gameMode) {
      return res.status(400).json({ error: 'playerId and gameMode are required' });
    }
    
    // Find or create game session
    const gameSession = await findOrCreateGameSession(gameMode);
    
    // Add player to session
    await addPlayerToSession(gameSession, playerId);
    
    res.json({ 
      gameSessionId: gameSession.id,
      serverEndpoint: gameSession.serverEndpoint,
      status: 'matched'
    });
  } catch (error) {
    console.error('Matchmaking error:', error);
    res.status(500).json({ error: error.message });
  }
});

async function findOrCreateGameSession(gameMode) {
  const gamesRef = firestore.collection('games');
  const availableGames = await gamesRef
    .where('status', '==', 'waiting')
    .where('gameMode', '==', gameMode)
    .limit(1)
    .get();

  if (!availableGames.empty) {
    return availableGames.docs[0];
  }

  // Create new game session
  const newGame = await gamesRef.add({
    gameMode,
    status: 'waiting',
    players: [],
    created: new Date(),
    maxPlayers: 4
  });

  return { id: newGame.id };
}

async function addPlayerToSession(gameSession, playerId) {
  await firestore.collection('games').doc(gameSession.id).update({
    players: firestore.FieldValue.arrayUnion(playerId),
    lastUpdated: new Date()
  });
}

app.listen(port, () => {
  console.log(`Matchmaking service running on port ${port}`);
});
EOF
    
    # Create Dockerfile
    cat > "${service_dir}/Dockerfile" << 'EOF'
FROM node:18-slim

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy application code
COPY . .

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Start the application
CMD ["node", "index.js"]
EOF
    
    # Build and deploy to Cloud Run
    info "Building and deploying matchmaking service to Cloud Run..."
    
    (cd "${service_dir}" && gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${CLOUD_RUN_SERVICE}" --quiet)
    
    gcloud run deploy "${CLOUD_RUN_SERVICE}" \
        --image "gcr.io/${PROJECT_ID}/${CLOUD_RUN_SERVICE}" \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --memory 512Mi \
        --cpu 1000m \
        --max-instances 100 \
        --concurrency 80 \
        --timeout 300 \
        --quiet
    
    # Get service URL
    export MATCHMAKING_URL=$(gcloud run services describe "${CLOUD_RUN_SERVICE}" \
        --platform managed \
        --region "${REGION}" \
        --format 'value(status.url)')
    
    # Add to config file
    echo "export MATCHMAKING_URL=\"${MATCHMAKING_URL}\"" >> "${CONFIG_FILE}"
    
    success "Matchmaking service deployed at: ${MATCHMAKING_URL}"
}

# Configure global load balancing
configure_load_balancing() {
    info "Configuring Cloud Load Balancing for global distribution..."
    
    # Check if backend service already exists
    if gcloud compute backend-services describe game-backend --global &>/dev/null; then
        warn "Load balancer backend service already exists. Skipping creation."
    else
        # Create backend service for Cloud Run
        gcloud compute backend-services create game-backend \
            --global \
            --protocol=HTTP \
            --port-name=http \
            --timeout=30s \
            --enable-cdn \
            --quiet
        
        # Add Cloud Run service as backend
        gcloud compute backend-services add-backend game-backend \
            --global \
            --serverless-deployment-type=run \
            --serverless-service="${CLOUD_RUN_SERVICE}" \
            --serverless-region="${REGION}" \
            --quiet
    fi
    
    # Create URL map for routing
    if ! gcloud compute url-maps describe game-loadbalancer --global &>/dev/null; then
        gcloud compute url-maps create game-loadbalancer \
            --default-service=game-backend \
            --global \
            --quiet
    fi
    
    # Create HTTP(S) proxy
    if ! gcloud compute target-http-proxies describe game-proxy --global &>/dev/null; then
        gcloud compute target-http-proxies create game-proxy \
            --url-map=game-loadbalancer \
            --global \
            --quiet
    fi
    
    # Create global forwarding rule
    if ! gcloud compute forwarding-rules describe game-forwarding-rule --global &>/dev/null; then
        gcloud compute forwarding-rules create game-forwarding-rule \
            --global \
            --target-http-proxy=game-proxy \
            --ports=80 \
            --quiet
    fi
    
    # Get load balancer IP
    export LB_IP=$(gcloud compute forwarding-rules describe game-forwarding-rule \
        --global \
        --format='value(IPAddress)')
    
    # Add to config file
    echo "export LB_IP=\"${LB_IP}\"" >> "${CONFIG_FILE}"
    
    success "Global load balancer configured at IP: ${LB_IP}"
}

# Setup real-time synchronization
setup_realtime_sync() {
    info "Setting up real-time game state synchronization..."
    
    # Create real-time sync configuration
    cat > "${SCRIPT_DIR}/sync-config.js" << 'EOF'
const { Firestore } = require('@google-cloud/firestore');

class GameStateSyncer {
  constructor(gameSessionId) {
    this.firestore = new Firestore();
    this.gameSessionId = gameSessionId;
    this.gameRef = this.firestore.collection('games').doc(gameSessionId);
  }

  // Listen for real-time game state changes
  subscribeToGameUpdates(callback) {
    return this.gameRef.onSnapshot((doc) => {
      if (doc.exists) {
        callback(doc.data());
      }
    }, (error) => {
      console.error('Real-time sync error:', error);
    });
  }

  // Update game state with atomic operations
  async updateGameState(playerAction) {
    const batch = this.firestore.batch();
    
    // Update game state atomically
    batch.update(this.gameRef, {
      gameState: playerAction.newState,
      lastUpdated: new Date(),
      lastAction: playerAction
    });

    // Update player stats
    const playerRef = this.firestore.collection('players').doc(playerAction.playerId);
    batch.update(playerRef, {
      lastAction: new Date(),
      actionsCount: this.firestore.FieldValue.increment(1)
    });

    await batch.commit();
  }

  // Handle player disconnection
  async handlePlayerDisconnect(playerId) {
    await this.gameRef.update({
      players: this.firestore.FieldValue.arrayRemove(playerId),
      lastUpdated: new Date()
    });
  }
}

module.exports = GameStateSyncer;
EOF
    
    # Create Firestore security rules
    cat > "${SCRIPT_DIR}/firestore.rules" << 'EOF'
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /games/{gameId} {
      allow read, write: if resource.data.players.hasAny([request.auth.uid]);
    }
    match /players/{playerId} {
      allow read, write: if request.auth.uid == playerId;
    }
  }
}
EOF
    
    # Deploy security rules
    gcloud firestore rules deploy "${SCRIPT_DIR}/firestore.rules" \
        --database="${FIRESTORE_DATABASE}" \
        --quiet
    
    success "Real-time synchronization configured with security rules"
}

# Validate deployment
validate_deployment() {
    info "Validating deployment..."
    
    # Check GKE cluster
    if ! kubectl cluster-info &>/dev/null; then
        error "GKE cluster is not accessible"
        return 1
    fi
    
    # Check Agones installation
    if ! kubectl get deployment -n agones-system | grep -q agones; then
        error "Agones is not properly installed"
        return 1
    fi
    
    # Check game server fleet
    if ! kubectl get fleet simple-game-server-fleet &>/dev/null; then
        error "Game server fleet is not deployed"
        return 1
    fi
    
    # Check Cloud Run service
    if ! gcloud run services describe "${CLOUD_RUN_SERVICE}" --region="${REGION}" &>/dev/null; then
        error "Cloud Run service is not deployed"
        return 1
    fi
    
    # Check load balancer
    if ! gcloud compute forwarding-rules describe game-forwarding-rule --global &>/dev/null; then
        error "Load balancer is not configured"
        return 1
    fi
    
    success "Deployment validation completed successfully"
}

# Main deployment function
main() {
    info "Starting Real-Time Multiplayer Gaming Infrastructure deployment..."
    info "Deployment log: ${LOG_FILE}"
    
    validate_prerequisites
    setup_environment
    enable_apis
    create_gke_cluster
    install_agones
    create_firestore_database
    deploy_game_server_fleet
    deploy_matchmaking_service
    configure_load_balancing
    setup_realtime_sync
    validate_deployment
    
    success "🎮 Gaming infrastructure deployment completed successfully!"
    info ""
    info "📋 Deployment Summary:"
    info "  Project ID: ${PROJECT_ID}"
    info "  GKE Cluster: ${CLUSTER_NAME} (${ZONE})"
    info "  Firestore Database: ${FIRESTORE_DATABASE}"
    info "  Matchmaking Service: ${MATCHMAKING_URL}"
    info "  Load Balancer IP: ${LB_IP}"
    info ""
    info "🔧 Next Steps:"
    info "  1. Test the matchmaking service: curl -X POST ${MATCHMAKING_URL}/matchmake -H 'Content-Type: application/json' -d '{\"playerId\": \"test123\", \"gameMode\": \"battle-royale\"}'"
    info "  2. Monitor game servers: kubectl get fleet,gameservers"
    info "  3. Check logs: kubectl logs -n agones-system -l app=agones-controller"
    info ""
    info "📄 Configuration saved to: ${CONFIG_FILE}"
    info "📋 To clean up resources, run: ./destroy.sh"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi