#!/bin/bash

# Container Security Pipeline with Binary Authorization and Cloud Deploy - Deployment Script
# This script deploys the complete container security pipeline infrastructure

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in dry-run mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    log "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
    else
        eval "$cmd"
    fi
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install it first."
    fi
    
    # Check if gpg is installed
    if ! command -v gpg &> /dev/null; then
        error "gpg is not installed. Please install it first."
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        error "curl is not installed. Please install it first."
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
    fi
    
    success "Prerequisites check passed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate project ID with timestamp if not set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="container-security-$(date +%s)"
        warning "PROJECT_ID not set, using: $PROJECT_ID"
    fi
    
    # Set default region and zone
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set repository URL
    export REPO_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/secure-apps-repo"
    
    # Set attestor and note names
    export ATTESTOR_NAME="build-attestor-${RANDOM_SUFFIX}"
    export NOTE_ID="build-note-${RANDOM_SUFFIX}"
    
    log "Environment variables set:"
    log "  PROJECT_ID: $PROJECT_ID"
    log "  REGION: $REGION"
    log "  ZONE: $ZONE"
    log "  RANDOM_SUFFIX: $RANDOM_SUFFIX"
    log "  REPO_URL: $REPO_URL"
    log "  ATTESTOR_NAME: $ATTESTOR_NAME"
    log "  NOTE_ID: $NOTE_ID"
}

# Configure GCP project
configure_project() {
    log "Configuring GCP project..."
    
    # Create project if it doesn't exist
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        execute_cmd "gcloud projects create $PROJECT_ID" "Creating project $PROJECT_ID"
    else
        log "Project $PROJECT_ID already exists"
    fi
    
    # Set default project and region
    execute_cmd "gcloud config set project $PROJECT_ID" "Setting default project"
    execute_cmd "gcloud config set compute/region $REGION" "Setting default region"
    execute_cmd "gcloud config set compute/zone $ZONE" "Setting default zone"
    
    # Enable billing account (user must set this manually)
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Checking if billing is enabled..."
        if ! gcloud billing projects describe "$PROJECT_ID" &>/dev/null; then
            warning "Billing not enabled for project $PROJECT_ID"
            warning "Please enable billing in the Google Cloud Console before continuing"
            read -p "Press Enter after enabling billing to continue..."
        fi
    fi
    
    success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log "Enabling required APIs..."
    
    local apis=(
        "container.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
        "binaryauthorization.googleapis.com"
        "clouddeploy.googleapis.com"
        "containeranalysis.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        execute_cmd "gcloud services enable $api" "Enabling $api"
    done
    
    success "APIs enabled successfully"
}

# Create Artifact Registry repository
create_artifact_registry() {
    log "Creating Artifact Registry repository..."
    
    # Create repository
    execute_cmd "gcloud artifacts repositories create secure-apps-repo \
        --repository-format=docker \
        --location=$REGION \
        --description='Secure container repository with scanning'" "Creating Artifact Registry repository"
    
    # Configure Docker authentication
    execute_cmd "gcloud auth configure-docker ${REGION}-docker.pkg.dev" "Configuring Docker authentication"
    
    success "Artifact Registry repository created: $REPO_URL"
}

# Create GKE clusters
create_gke_clusters() {
    log "Creating GKE clusters..."
    
    # Create staging cluster
    execute_cmd "gcloud container clusters create staging-cluster-${RANDOM_SUFFIX} \
        --zone=$ZONE \
        --num-nodes=2 \
        --machine-type=e2-standard-2 \
        --enable-binauthz \
        --enable-network-policy \
        --enable-autorepair \
        --enable-autoupgrade \
        --enable-logging \
        --enable-monitoring" "Creating staging cluster"
    
    # Create production cluster
    execute_cmd "gcloud container clusters create prod-cluster-${RANDOM_SUFFIX} \
        --zone=$ZONE \
        --num-nodes=3 \
        --machine-type=e2-standard-2 \
        --enable-binauthz \
        --enable-network-policy \
        --enable-autorepair \
        --enable-autoupgrade \
        --enable-logging \
        --enable-monitoring" "Creating production cluster"
    
    success "GKE clusters created successfully"
}

# Configure Binary Authorization
configure_binary_authorization() {
    log "Configuring Binary Authorization..."
    
    # Create attestation note
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > note.json <<EOF
{
  "name": "projects/${PROJECT_ID}/notes/${NOTE_ID}",
  "attestationAuthority": {
    "hint": {
      "humanReadableName": "Build verification attestor"
    }
  }
}
EOF
    fi
    
    # Create attestation note via API
    execute_cmd "curl -X POST \
        -H 'Content-Type: application/json' \
        -H 'Authorization: Bearer \$(gcloud auth print-access-token)' \
        -d @note.json \
        'https://containeranalysis.googleapis.com/v1beta1/projects/${PROJECT_ID}/notes?noteId=${NOTE_ID}'" "Creating attestation note"
    
    # Generate PGP key for signing
    execute_cmd "gpg --batch --quick-generate-key \
        --yes \
        --passphrase='' \
        'Build Attestor <build@${PROJECT_ID}.example.com>'" "Generating PGP key"
    
    # Export public key
    execute_cmd "gpg --armor --export 'Build Attestor <build@${PROJECT_ID}.example.com>' > attestor-key.pub" "Exporting public key"
    
    # Create Binary Authorization attestor
    execute_cmd "gcloud container binauthz attestors create $ATTESTOR_NAME \
        --attestation-authority-note=$NOTE_ID \
        --attestation-authority-note-project=$PROJECT_ID" "Creating Binary Authorization attestor"
    
    # Add public key to attestor
    execute_cmd "gcloud container binauthz attestors public-keys add \
        --attestor=$ATTESTOR_NAME \
        --pgp-public-key-file=attestor-key.pub" "Adding public key to attestor"
    
    success "Binary Authorization attestor configured"
}

# Create Binary Authorization policy
create_binauthz_policy() {
    log "Creating Binary Authorization policy..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > binauthz-policy.yaml <<EOF
admissionWhitelistPatterns:
- namePattern: gcr.io/distroless/*
- namePattern: gcr.io/gke-release/*
defaultAdmissionRule:
  requireAttestationsBy:
  - projects/${PROJECT_ID}/attestors/${ATTESTOR_NAME}
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
clusterAdmissionRules:
  ${ZONE}.staging-cluster-${RANDOM_SUFFIX}:
    requireAttestationsBy: []
    enforcementMode: DRYRUN_AUDIT_LOG_ONLY
  ${ZONE}.prod-cluster-${RANDOM_SUFFIX}:
    requireAttestationsBy:
    - projects/${PROJECT_ID}/attestors/${ATTESTOR_NAME}
    enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
EOF
    fi
    
    # Import the policy
    execute_cmd "gcloud container binauthz policy import binauthz-policy.yaml" "Importing Binary Authorization policy"
    
    success "Binary Authorization policy configured"
}

# Build and attest sample application
build_sample_app() {
    log "Building and attesting sample application..."
    
    # Create sample application directory
    execute_cmd "mkdir -p sample-app" "Creating sample application directory"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create Flask application
        cat > sample-app/app.py <<EOF
from flask import Flask
import os

app = Flask(__name__)

@app.route('/')
def hello():
    version = os.environ.get('VERSION', 'v1.0.0')
    return f'Hello from secure app version {version}!'

@app.route('/health')
def health():
    return {'status': 'healthy', 'version': os.environ.get('VERSION', 'v1.0.0')}

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF
        
        # Create Dockerfile
        cat > sample-app/Dockerfile <<EOF
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY app.py .
EXPOSE 8080
ENV VERSION=v1.0.0
CMD ["python", "app.py"]
EOF
        
        # Create requirements file
        echo "Flask==2.3.3" > sample-app/requirements.txt
        
        # Create Cloud Build configuration
        cat > sample-app/cloudbuild.yaml <<EOF
steps:
# Build container image
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '${REPO_URL}/secure-app:v1.0.0', '.']

# Push to Artifact Registry
- name: 'gcr.io/cloud-builders/docker'
  args: ['push', '${REPO_URL}/secure-app:v1.0.0']

# Create attestation after successful build
- name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    # Get image digest
    IMAGE_DIGEST=\$(gcloud artifacts docker images describe ${REPO_URL}/secure-app:v1.0.0 --format='value(image_summary.digest)')
    IMAGE_URL="${REPO_URL}/secure-app@\$IMAGE_DIGEST"
    
    # Create attestation payload
    cat > /tmp/payload.json <<EOL
    {
      "critical": {
        "identity": {
          "docker-reference": "\$IMAGE_URL"
        },
        "image": {
          "docker-manifest-digest": "\$IMAGE_DIGEST"
        },
        "type": "Google Cloud Build"
      },
      "non-critical": {
        "build": {
          "build-id": "\$BUILD_ID",
          "project-id": "${PROJECT_ID}",
          "build-timestamp": "\$(date -Iseconds)"
        }
      }
    }
    EOL
    
    # Sign payload and create attestation
    gcloud container binauthz attestations sign-and-create \
        --artifact-url="\$IMAGE_URL" \
        --attestor=${ATTESTOR_NAME} \
        --attestor-project=${PROJECT_ID} \
        --payload-file=/tmp/payload.json
images:
- '${REPO_URL}/secure-app:v1.0.0'
EOF
    fi
    
    # Submit build
    execute_cmd "cd sample-app && gcloud builds submit --config=cloudbuild.yaml . && cd .." "Building and attesting container image"
    
    success "Sample application built and attested"
}

# Configure Cloud Deploy pipeline
configure_cloud_deploy() {
    log "Configuring Cloud Deploy pipeline..."
    
    # Create Kubernetes manifests directory
    execute_cmd "mkdir -p k8s-manifests" "Creating Kubernetes manifests directory"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create deployment manifest
        cat > k8s-manifests/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
  labels:
    app: secure-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: secure-app
  template:
    metadata:
      labels:
        app: secure-app
    spec:
      containers:
      - name: secure-app
        image: ${REPO_URL}/secure-app:v1.0.0
        ports:
        - containerPort: 8080
        env:
        - name: VERSION
          value: "v1.0.0"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: secure-app-service
spec:
  selector:
    app: secure-app
  ports:
  - port: 80
    targetPort: 8080
  type: LoadBalancer
EOF
        
        # Create skaffold configuration
        cat > k8s-manifests/skaffold.yaml <<EOF
apiVersion: skaffold/v4beta6
kind: Config
metadata:
  name: secure-app
build:
  artifacts:
  - image: secure-app
    docker:
      dockerfile: Dockerfile
manifests:
  rawYaml:
  - deployment.yaml
deploy:
  kubectl: {}
EOF
        
        # Create Cloud Deploy pipeline configuration
        cat > clouddeploy.yaml <<EOF
apiVersion: deploy.cloud.google.com/v1
kind: DeliveryPipeline
metadata:
  name: secure-app-pipeline
description: Secure deployment pipeline with Binary Authorization
serialPipeline:
  stages:
  - targetId: staging
    profiles: []
  - targetId: production
    profiles: []
    strategy:
      canary:
        runtimeConfig:
          kubernetes:
            serviceNetworking:
              service: "secure-app-service"
              deployment: "secure-app"
        canaryDeployment:
          percentages: [20, 50, 80]
          verify: false
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: staging
description: Staging environment for security validation
gke:
  cluster: projects/${PROJECT_ID}/locations/${ZONE}/clusters/staging-cluster-${RANDOM_SUFFIX}
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: production
description: Production environment with canary deployment
gke:
  cluster: projects/${PROJECT_ID}/locations/${ZONE}/clusters/prod-cluster-${RANDOM_SUFFIX}
EOF
    fi
    
    # Register the pipeline
    execute_cmd "gcloud deploy apply --file=clouddeploy.yaml --region=$REGION" "Registering Cloud Deploy pipeline"
    
    success "Cloud Deploy pipeline configured"
}

# Deploy application
deploy_application() {
    log "Deploying application through secure pipeline..."
    
    # Get cluster credentials
    execute_cmd "gcloud container clusters get-credentials staging-cluster-${RANDOM_SUFFIX} --zone=$ZONE" "Getting staging cluster credentials"
    execute_cmd "gcloud container clusters get-credentials prod-cluster-${RANDOM_SUFFIX} --zone=$ZONE" "Getting production cluster credentials"
    
    # Create release through Cloud Deploy
    execute_cmd "cd k8s-manifests && gcloud deploy releases create secure-app-v1-0-0 \
        --delivery-pipeline=secure-app-pipeline \
        --region=$REGION \
        --source=. && cd .." "Creating Cloud Deploy release"
    
    log "Deployment initiated. Monitor progress at:"
    log "https://console.cloud.google.com/deploy/delivery-pipelines?project=$PROJECT_ID"
    
    success "Application deployment started"
}

# Save deployment state
save_deployment_state() {
    log "Saving deployment state..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > deployment-state.json <<EOF
{
  "project_id": "$PROJECT_ID",
  "region": "$REGION",
  "zone": "$ZONE",
  "random_suffix": "$RANDOM_SUFFIX",
  "repo_url": "$REPO_URL",
  "attestor_name": "$ATTESTOR_NAME",
  "note_id": "$NOTE_ID",
  "staging_cluster": "staging-cluster-${RANDOM_SUFFIX}",
  "prod_cluster": "prod-cluster-${RANDOM_SUFFIX}",
  "deployment_time": "$(date -Iseconds)"
}
EOF
    fi
    
    success "Deployment state saved to deployment-state.json"
}

# Main deployment function
main() {
    log "Starting Container Security Pipeline deployment..."
    
    check_prerequisites
    setup_environment
    configure_project
    enable_apis
    create_artifact_registry
    create_gke_clusters
    configure_binary_authorization
    create_binauthz_policy
    build_sample_app
    configure_cloud_deploy
    deploy_application
    save_deployment_state
    
    success "Container Security Pipeline deployment completed successfully!"
    
    log "Next steps:"
    log "1. Monitor the deployment in the Cloud Console"
    log "2. Run validation tests to verify security policies"
    log "3. Test canary deployment functionality"
    log "4. Review Binary Authorization policies and attestations"
    
    log "To clean up resources, run: ./destroy.sh"
}

# Run main function
main "$@"