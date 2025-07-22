#!/bin/bash

# Application Debugging Workflows with Cloud Debugger and Cloud Workstations - Deploy Script
# This script deploys the complete debugging workflow infrastructure including:
# - Cloud Workstations cluster and configuration
# - Artifact Registry repository with custom debug container image
# - Sample Cloud Run application for debugging
# - Monitoring and logging configuration

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    log_info "Running in dry-run mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    log_info "$description"
    if eval "$cmd"; then
        log_success "$description completed"
        return 0
    else
        log_error "$description failed"
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project is set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID environment variable is not set"
        exit 1
    fi
    
    # Check if billing is enabled
    if ! gcloud billing accounts list --format="value(name)" | grep -q .; then
        log_warning "Unable to verify billing account. Please ensure billing is enabled for your project."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-debug-workflow-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    export WORKSTATION_CLUSTER="${WORKSTATION_CLUSTER:-debug-cluster-${RANDOM_SUFFIX}}"
    export WORKSTATION_CONFIG="${WORKSTATION_CONFIG:-debug-config-${RANDOM_SUFFIX}}"
    export REPOSITORY_NAME="${REPOSITORY_NAME:-debug-tools-${RANDOM_SUFFIX}}"
    export SERVICE_NAME="${SERVICE_NAME:-sample-app-${RANDOM_SUFFIX}}"
    export WORKSTATION_NAME="${WORKSTATION_NAME:-debug-workstation-${RANDOM_SUFFIX}}"
    
    # Set gcloud defaults
    execute_command "gcloud config set project ${PROJECT_ID}" "Setting default project"
    execute_command "gcloud config set compute/region ${REGION}" "Setting default region"
    execute_command "gcloud config set compute/zone ${ZONE}" "Setting default zone"
    
    log_success "Environment variables configured"
    log_info "PROJECT_ID: ${PROJECT_ID}"
    log_info "REGION: ${REGION}"
    log_info "WORKSTATION_CLUSTER: ${WORKSTATION_CLUSTER}"
    log_info "REPOSITORY_NAME: ${REPOSITORY_NAME}"
    log_info "SERVICE_NAME: ${SERVICE_NAME}"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "workstations.googleapis.com"
        "artifactregistry.googleapis.com"
        "run.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        execute_command "gcloud services enable ${api}" "Enabling ${api}"
    done
    
    log_success "All required APIs enabled"
}

# Function to create Artifact Registry repository
create_artifact_registry() {
    log_info "Creating Artifact Registry repository..."
    
    execute_command "gcloud artifacts repositories create ${REPOSITORY_NAME} \
        --repository-format=docker \
        --location=${REGION} \
        --description='Repository for debugging workflow containers'" \
        "Creating Artifact Registry repository"
    
    execute_command "gcloud auth configure-docker ${REGION}-docker.pkg.dev" \
        "Configuring Docker authentication for Artifact Registry"
    
    log_success "Artifact Registry repository created: ${REPOSITORY_NAME}"
}

# Function to build and push custom workstation image
build_custom_image() {
    log_info "Building custom workstation container image..."
    
    # Create temporary directory for build context
    local build_dir=$(mktemp -d)
    cd "$build_dir"
    
    # Create Dockerfile with debugging tools
    cat > Dockerfile << 'EOF'
FROM us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest

# Install additional debugging tools
USER root
RUN apt-get update && apt-get install -y \
    gdb \
    strace \
    tcpdump \
    htop \
    curl \
    jq \
    python3-pip \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Install Python debugging tools
RUN pip3 install debugpy pdb++ ipdb

# Install Node.js debugging tools
RUN npm install -g node-inspect

# Switch back to codeoss user
USER codeoss

# Install VS Code extensions for debugging
RUN code-server --install-extension ms-python.python \
    && code-server --install-extension ms-vscode.js-debug

EXPOSE 8080
EOF
    
    # Build and push image
    export IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}/debug-workstation:latest"
    
    execute_command "gcloud builds submit --tag ${IMAGE_URI} ." \
        "Building and pushing custom workstation image"
    
    # Clean up build directory
    cd - > /dev/null
    rm -rf "$build_dir"
    
    log_success "Custom workstation image built and pushed: ${IMAGE_URI}"
}

# Function to create Cloud Workstations cluster
create_workstations_cluster() {
    log_info "Creating Cloud Workstations cluster..."
    
    execute_command "gcloud workstations clusters create ${WORKSTATION_CLUSTER} \
        --location=${REGION} \
        --network='projects/${PROJECT_ID}/global/networks/default' \
        --subnetwork='projects/${PROJECT_ID}/regions/${REGION}/subnetworks/default'" \
        "Creating Cloud Workstations cluster"
    
    # Wait for cluster to be active
    log_info "Waiting for cluster to become active..."
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would check cluster state"
            break
        fi
        
        local state=$(gcloud workstations clusters describe ${WORKSTATION_CLUSTER} \
            --location=${REGION} \
            --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "$state" == "ACTIVE" ]]; then
            log_success "Cloud Workstations cluster is active"
            break
        fi
        
        log_info "Cluster state: $state (attempt $((attempt + 1))/$max_attempts)"
        sleep 30
        ((attempt++))
    done
    
    if [[ $attempt -eq $max_attempts && "$DRY_RUN" == "false" ]]; then
        log_error "Timeout waiting for cluster to become active"
        exit 1
    fi
}

# Function to create workstation configuration
create_workstation_config() {
    log_info "Creating workstation configuration..."
    
    execute_command "gcloud workstations configs create ${WORKSTATION_CONFIG} \
        --location=${REGION} \
        --cluster=${WORKSTATION_CLUSTER} \
        --machine-type=e2-standard-4 \
        --pd-disk-type=pd-standard \
        --pd-disk-size=200GB \
        --container-image=${IMAGE_URI} \
        --idle-timeout=7200s \
        --running-timeout=28800s" \
        "Creating workstation configuration"
    
    execute_command "gcloud workstations configs update ${WORKSTATION_CONFIG} \
        --location=${REGION} \
        --cluster=${WORKSTATION_CLUSTER} \
        --container-env='DEBUG_MODE=enabled,LOG_LEVEL=debug'" \
        "Updating workstation configuration with environment variables"
    
    log_success "Workstation configuration created: ${WORKSTATION_CONFIG}"
}

# Function to deploy sample application
deploy_sample_app() {
    log_info "Deploying sample application..."
    
    # Create temporary directory for sample app
    local app_dir=$(mktemp -d)
    cd "$app_dir"
    
    # Create sample Node.js application
    cat > app.js << 'EOF'
const express = require('express');
const app = express();
const port = process.env.PORT || 8080;

// Middleware for logging
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);
  next();
});

// Route with potential performance issue
app.get('/api/data', (req, res) => {
  const start = Date.now();
  
  // Simulate some processing that could cause issues
  const data = [];
  for (let i = 0; i < 100000; i++) {
    data.push({ id: i, value: Math.random() });
  }
  
  const processingTime = Date.now() - start;
  console.log(`Processing time: ${processingTime}ms`);
  
  res.json({
    message: 'Data processed successfully',
    count: data.length,
    processingTime: processingTime
  });
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
EOF
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "debug-sample-app",
  "version": "1.0.0",
  "description": "Sample application for debugging workflows",
  "main": "app.js",
  "scripts": {
    "start": "node app.js",
    "debug": "node --inspect=0.0.0.0:9229 app.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM node:18-slim
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 8080 9229
CMD ["npm", "start"]
EOF
    
    # Build and deploy to Cloud Run
    execute_command "gcloud builds submit --tag gcr.io/${PROJECT_ID}/${SERVICE_NAME}" \
        "Building sample application container"
    
    execute_command "gcloud run deploy ${SERVICE_NAME} \
        --image gcr.io/${PROJECT_ID}/${SERVICE_NAME} \
        --platform managed \
        --region ${REGION} \
        --allow-unauthenticated \
        --port 8080 \
        --memory 512Mi \
        --cpu 1" \
        "Deploying sample application to Cloud Run"
    
    # Get service URL
    if [[ "$DRY_RUN" == "false" ]]; then
        export SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
            --region=${REGION} \
            --format="value(status.url)")
        log_success "Sample application deployed: ${SERVICE_URL}"
    else
        log_info "[DRY-RUN] Would get service URL"
    fi
    
    # Clean up app directory
    cd - > /dev/null
    rm -rf "$app_dir"
}

# Function to create workstation instance
create_workstation_instance() {
    log_info "Creating workstation instance..."
    
    execute_command "gcloud workstations create ${WORKSTATION_NAME} \
        --location=${REGION} \
        --cluster=${WORKSTATION_CLUSTER} \
        --config=${WORKSTATION_CONFIG}" \
        "Creating workstation instance"
    
    # Wait for workstation to be running
    log_info "Waiting for workstation to be ready..."
    local max_attempts=20
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would check workstation state"
            break
        fi
        
        local state=$(gcloud workstations describe ${WORKSTATION_NAME} \
            --location=${REGION} \
            --cluster=${WORKSTATION_CLUSTER} \
            --config=${WORKSTATION_CONFIG} \
            --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "$state" == "RUNNING" ]]; then
            log_success "Workstation instance is running"
            break
        fi
        
        log_info "Workstation state: $state (attempt $((attempt + 1))/$max_attempts)"
        sleep 30
        ((attempt++))
    done
    
    if [[ $attempt -eq $max_attempts && "$DRY_RUN" == "false" ]]; then
        log_error "Timeout waiting for workstation to be running"
        exit 1
    fi
}

# Function to configure monitoring and logging
configure_monitoring() {
    log_info "Configuring monitoring and logging..."
    
    # Create Pub/Sub topic for logging sink (if it doesn't exist)
    if [[ "$DRY_RUN" == "false" ]]; then
        if ! gcloud pubsub topics describe debug-activities &>/dev/null; then
            execute_command "gcloud pubsub topics create debug-activities" \
                "Creating Pub/Sub topic for logging"
        fi
    fi
    
    # Create Cloud Logging sink
    execute_command "gcloud logging sinks create workstation-debug-sink \
        pubsub.googleapis.com/projects/${PROJECT_ID}/topics/debug-activities \
        --log-filter='resource.type=\"gce_instance\" AND resource.labels.instance_name:workstation'" \
        "Creating Cloud Logging sink"
    
    # Get workstation access URL
    if [[ "$DRY_RUN" == "false" ]]; then
        export WORKSTATION_URL=$(gcloud workstations describe ${WORKSTATION_NAME} \
            --location=${REGION} \
            --cluster=${WORKSTATION_CLUSTER} \
            --config=${WORKSTATION_CONFIG} \
            --format="value(host)" 2>/dev/null || echo "unavailable")
        log_success "Workstation access URL: https://${WORKSTATION_URL}"
    else
        log_info "[DRY-RUN] Would get workstation access URL"
    fi
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo ""
    echo "=== Deployment Summary ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Workstation Cluster: ${WORKSTATION_CLUSTER}"
    echo "Workstation Config: ${WORKSTATION_CONFIG}"
    echo "Workstation Instance: ${WORKSTATION_NAME}"
    echo "Artifact Registry: ${REPOSITORY_NAME}"
    echo "Sample App Service: ${SERVICE_NAME}"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        echo "=== Access Information ==="
        echo "Workstation URL: https://${WORKSTATION_URL:-unavailable}"
        echo "Sample App URL: ${SERVICE_URL:-unavailable}"
        echo ""
        echo "Next steps:"
        echo "1. Access your workstation at the URL above"
        echo "2. Test the sample application endpoints"
        echo "3. Begin debugging workflows using the integrated tools"
        echo ""
        echo "To clean up resources, run: ./destroy.sh"
    fi
}

# Function to save deployment state
save_deployment_state() {
    local state_file=".deployment_state"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > "$state_file" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
WORKSTATION_CLUSTER=${WORKSTATION_CLUSTER}
WORKSTATION_CONFIG=${WORKSTATION_CONFIG}
REPOSITORY_NAME=${REPOSITORY_NAME}
SERVICE_NAME=${SERVICE_NAME}
WORKSTATION_NAME=${WORKSTATION_NAME}
IMAGE_URI=${IMAGE_URI}
SERVICE_URL=${SERVICE_URL:-}
WORKSTATION_URL=${WORKSTATION_URL:-}
DEPLOYMENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
        log_success "Deployment state saved to $state_file"
    fi
}

# Main deployment function
main() {
    log_info "Starting Application Debugging Workflows deployment..."
    
    # Trap errors and cleanup
    trap 'log_error "Deployment failed. Check the logs above for details."' ERR
    
    check_prerequisites
    setup_environment
    enable_apis
    create_artifact_registry
    build_custom_image
    create_workstations_cluster
    create_workstation_config
    deploy_sample_app
    create_workstation_instance
    configure_monitoring
    save_deployment_state
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"