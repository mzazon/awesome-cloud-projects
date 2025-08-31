#!/bin/bash

# GitOps Development Workflows with Cloud Workstations and Deploy - Deployment Script
# This script deploys the complete GitOps infrastructure described in the recipe

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
DRY_RUN=${DRY_RUN:-false}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[$timestamp] [$level] $*"
    echo -e "$message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Error handling
handle_error() {
    local line_number=$1
    log_error "Script failed at line $line_number. Check the logs for details."
    log_error "You may need to run the destroy script to clean up partial resources."
    exit 1
}

trap 'handle_error ${LINENO}' ERR

# Help function
show_help() {
    cat << EOF
GitOps Development Workflows Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deployed without making changes
    -p, --project-id    Override default project ID
    -r, --region        Override default region (default: us-central1)
    --skip-apis         Skip API enablement (use if APIs are already enabled)
    --workstation-only  Deploy only workstation components
    --pipeline-only     Deploy only CI/CD pipeline components

EXAMPLES:
    $0                                  # Standard deployment
    $0 --dry-run                       # Preview deployment without changes
    $0 --project-id my-project         # Deploy to specific project
    $0 --region us-west1               # Deploy to specific region

ENVIRONMENT VARIABLES:
    PROJECT_ID          Google Cloud project ID (required if not set via flag)
    REGION              Google Cloud region (default: us-central1)
    DRY_RUN            Set to 'true' for dry run mode

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            --skip-apis)
                SKIP_APIS=true
                shift
                ;;
            --workstation-only)
                WORKSTATION_ONLY=true
                shift
                ;;
            --pipeline-only)
                PIPELINE_ONLY=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud >/dev/null 2>&1; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl is not installed. Please install it from https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi
    
    # Check if git is installed
    if ! command -v git >/dev/null 2>&1; then
        log_error "git is not installed. Please install git"
        exit 1
    fi
    
    # Check if openssl is installed (for random suffix generation)
    if ! command -v openssl >/dev/null 2>&1; then
        log_error "openssl is not installed. Please install openssl"
        exit 1
    fi
    
    # Check if user is authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        log_error "You are not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Initialize environment variables
init_environment() {
    log_info "Initializing environment variables..."
    
    # Set default values
    REGION=${REGION:-"us-central1"}
    ZONE="${REGION}-a"
    SKIP_APIS=${SKIP_APIS:-false}
    WORKSTATION_ONLY=${WORKSTATION_ONLY:-false}
    PIPELINE_ONLY=${PIPELINE_ONLY:-false}
    
    # Generate project ID if not provided
    if [ -z "${PROJECT_ID:-}" ]; then
        PROJECT_ID="gitops-workflow-$(date +%s)"
        log_warning "No PROJECT_ID provided. Generated: $PROJECT_ID"
    fi
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    CLUSTER_NAME="gitops-cluster-${RANDOM_SUFFIX}"
    WORKSTATION_CONFIG="dev-config-${RANDOM_SUFFIX}"
    APP_REPO="hello-app-${RANDOM_SUFFIX}"
    ENV_REPO="hello-env-${RANDOM_SUFFIX}"
    
    # Export variables for use in functions
    export PROJECT_ID REGION ZONE CLUSTER_NAME WORKSTATION_CONFIG APP_REPO ENV_REPO
    
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Cluster Name: $CLUSTER_NAME"
    log_info "App Repository: $APP_REPO"
    log_info "Environment Repository: $ENV_REPO"
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE: No actual resources will be created"
    fi
}

# Execute command with dry run support
execute_command() {
    local cmd="$*"
    log_info "Executing: $cmd"
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY RUN] Would execute: $cmd"
        return 0
    fi
    
    if ! eval "$cmd"; then
        log_error "Command failed: $cmd"
        return 1
    fi
}

# Configure gcloud settings
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    execute_command "gcloud config set project $PROJECT_ID"
    execute_command "gcloud config set compute/region $REGION"
    execute_command "gcloud config set compute/zone $ZONE"
    
    log_success "gcloud configuration completed"
}

# Enable required APIs
enable_apis() {
    if [ "$SKIP_APIS" = true ]; then
        log_warning "Skipping API enablement as requested"
        return 0
    fi
    
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "container.googleapis.com"
        "cloudbuild.googleapis.com"
        "sourcerepo.googleapis.com"
        "artifactregistry.googleapis.com"
        "workstations.googleapis.com"
        "clouddeploy.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        execute_command "gcloud services enable $api"
    done
    
    log_success "Required APIs enabled"
    
    if [ "$DRY_RUN" = false ]; then
        log_info "Waiting 30 seconds for APIs to be fully activated..."
        sleep 30
    fi
}

# Create GKE clusters
create_gke_clusters() {
    if [ "$WORKSTATION_ONLY" = true ]; then
        log_warning "Skipping GKE cluster creation (workstation-only mode)"
        return 0
    fi
    
    log_info "Creating GKE Autopilot clusters for staging and production..."
    
    # Create staging cluster
    log_info "Creating staging cluster: ${CLUSTER_NAME}-staging"
    execute_command "gcloud container clusters create-auto ${CLUSTER_NAME}-staging \
        --region $REGION \
        --labels='env=staging,purpose=gitops'"
    
    # Create production cluster
    log_info "Creating production cluster: ${CLUSTER_NAME}-prod"
    execute_command "gcloud container clusters create-auto ${CLUSTER_NAME}-prod \
        --region $REGION \
        --labels='env=production,purpose=gitops'"
    
    if [ "$DRY_RUN" = false ]; then
        # Get cluster credentials
        log_info "Getting cluster credentials..."
        execute_command "gcloud container clusters get-credentials ${CLUSTER_NAME}-staging --region $REGION"
        execute_command "gcloud container clusters get-credentials ${CLUSTER_NAME}-prod --region $REGION"
    fi
    
    log_success "GKE clusters created successfully"
}

# Create Artifact Registry repository
create_artifact_registry() {
    if [ "$WORKSTATION_ONLY" = true ]; then
        log_warning "Skipping Artifact Registry creation (workstation-only mode)"
        return 0
    fi
    
    log_info "Creating Artifact Registry repository..."
    
    execute_command "gcloud artifacts repositories create $APP_REPO \
        --repository-format=docker \
        --location=$REGION \
        --description='GitOps application images'"
    
    if [ "$DRY_RUN" = false ]; then
        # Configure Docker authentication
        log_info "Configuring Docker authentication..."
        execute_command "gcloud auth configure-docker ${REGION}-docker.pkg.dev"
    fi
    
    log_success "Artifact Registry repository created"
}

# Create Cloud Source Repositories
create_source_repositories() {
    if [ "$WORKSTATION_ONLY" = true ]; then
        log_warning "Skipping Source Repositories creation (workstation-only mode)"
        return 0
    fi
    
    log_info "Creating Cloud Source Repositories..."
    
    execute_command "gcloud source repos create $APP_REPO"
    execute_command "gcloud source repos create $ENV_REPO"
    
    if [ "$DRY_RUN" = false ]; then
        # Clone sample application code
        log_info "Setting up sample application code..."
        cd ~
        if [ ! -d "kubernetes-engine-samples" ]; then
            execute_command "git clone https://github.com/GoogleCloudPlatform/kubernetes-engine-samples"
        fi
        cd kubernetes-engine-samples/hello-app
        
        # Configure remote repositories
        execute_command "git remote add app-origin 'https://source.developers.google.com/p/${PROJECT_ID}/r/${APP_REPO}'"
    fi
    
    log_success "Source repositories created and configured"
}

# Set up Cloud Workstations
setup_workstations() {
    if [ "$PIPELINE_ONLY" = true ]; then
        log_warning "Skipping Cloud Workstations setup (pipeline-only mode)"
        return 0
    fi
    
    log_info "Setting up Cloud Workstations..."
    
    # Create workstation cluster
    log_info "Creating workstation cluster..."
    execute_command "gcloud workstations clusters create ${WORKSTATION_CONFIG}-cluster \
        --region=$REGION \
        --network='projects/${PROJECT_ID}/global/networks/default' \
        --subnetwork='projects/${PROJECT_ID}/regions/${REGION}/subnetworks/default'"
    
    if [ "$DRY_RUN" = false ]; then
        log_info "Waiting for workstation cluster to be ready..."
        sleep 60
    fi
    
    # Create workstation configuration
    log_info "Creating workstation configuration..."
    execute_command "gcloud workstations configs create $WORKSTATION_CONFIG \
        --cluster=${WORKSTATION_CONFIG}-cluster \
        --cluster-region=$REGION \
        --machine-type=e2-standard-4 \
        --persistent-disk-size=100GB \
        --container-image=us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest"
    
    # Create workstation instance
    log_info "Creating workstation instance..."
    execute_command "gcloud workstations create dev-workstation \
        --config=$WORKSTATION_CONFIG \
        --cluster=${WORKSTATION_CONFIG}-cluster \
        --cluster-region=$REGION \
        --region=$REGION"
    
    log_success "Cloud Workstation created successfully"
}

# Create Cloud Build CI pipeline configuration
create_ci_pipeline() {
    if [ "$WORKSTATION_ONLY" = true ]; then
        log_warning "Skipping CI pipeline creation (workstation-only mode)"
        return 0
    fi
    
    log_info "Creating Cloud Build CI pipeline configuration..."
    
    if [ "$DRY_RUN" = false ]; then
        cat > ~/cloudbuild-ci.yaml << 'EOF'
steps:
# Build the container image
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_APP_REPO}/hello-app:${SHORT_SHA}', '.']

# Push the container image to Artifact Registry
- name: 'gcr.io/cloud-builders/docker'
  args: ['push', '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_APP_REPO}/hello-app:${SHORT_SHA}']

# Clone the env repository and update manifests
- name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    gcloud source repos clone ${_ENV_REPO} env-repo
    cd env-repo
    git config user.email "cloudbuild@${PROJECT_ID}.iam.gserviceaccount.com"
    git config user.name "Cloud Build"
    
    # Update the deployment manifest
    sed -i "s|image: .*|image: ${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_APP_REPO}/hello-app:${SHORT_SHA}|g" k8s/hello-app-deployment.yaml
    git add .
    git commit -m "Update image to ${SHORT_SHA}"
    git push origin main

substitutions:
  _REGION: '${REGION}'
  _APP_REPO: '${APP_REPO}'
  _ENV_REPO: '${ENV_REPO}'

options:
  logging: CLOUD_LOGGING_ONLY
EOF
    fi
    
    log_success "CI pipeline configuration created"
}

# Create Cloud Deploy delivery pipeline
create_deploy_pipeline() {
    if [ "$WORKSTATION_ONLY" = true ]; then
        log_warning "Skipping Deploy pipeline creation (workstation-only mode)"
        return 0
    fi
    
    log_info "Creating Cloud Deploy delivery pipeline..."
    
    if [ "$DRY_RUN" = false ]; then
        # Create environment configuration files
        mkdir -p ~/k8s
        
        # Create Kubernetes deployment manifest
        cat > ~/k8s/hello-app-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-app
  labels:
    app: hello-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hello-app
  template:
    metadata:
      labels:
        app: hello-app
    spec:
      containers:
      - name: hello-app
        image: us-central1-docker.pkg.dev/PROJECT_ID/APP_REPO/hello-app:latest
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: hello-app-service
spec:
  selector:
    app: hello-app
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
  type: LoadBalancer
EOF
        
        # Create Cloud Deploy configuration
        cat > ~/clouddeploy.yaml << EOF
apiVersion: deploy.cloud.google.com/v1
kind: DeliveryPipeline
metadata:
  name: gitops-pipeline
description: GitOps delivery pipeline
serialPipeline:
  stages:
  - targetId: staging
    profiles: []
  - targetId: production
    profiles: []
    strategy:
      standard:
        verify: false
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: staging
description: Staging environment
gke:
  cluster: projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_NAME}-staging
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: production
description: Production environment
gke:
  cluster: projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_NAME}-prod
EOF
        
        # Apply Cloud Deploy configuration
        execute_command "gcloud deploy apply --file=~/clouddeploy.yaml --region=$REGION"
    fi
    
    log_success "Cloud Deploy pipeline configured"
}

# Initialize environment repository
init_environment_repo() {
    if [ "$WORKSTATION_ONLY" = true ]; then
        log_warning "Skipping environment repository initialization (workstation-only mode)"
        return 0
    fi
    
    log_info "Initializing environment repository..."
    
    if [ "$DRY_RUN" = false ]; then
        cd ~
        mkdir -p "${ENV_REPO}-local"
        cd "${ENV_REPO}-local"
        
        execute_command "git init"
        execute_command "git remote add origin 'https://source.developers.google.com/p/${PROJECT_ID}/r/${ENV_REPO}'"
        
        # Create directory structure
        mkdir -p k8s
        
        # Copy deployment manifests
        cp ~/k8s/hello-app-deployment.yaml k8s/
        
        # Update manifest with correct project and repository
        sed -i "s/PROJECT_ID/${PROJECT_ID}/g" k8s/hello-app-deployment.yaml
        sed -i "s/APP_REPO/${APP_REPO}/g" k8s/hello-app-deployment.yaml
        
        # Configure Git and push initial commit
        execute_command "git config user.email 'admin@${PROJECT_ID}.iam.gserviceaccount.com'"
        execute_command "git config user.name 'GitOps Admin'"
        execute_command "git add ."
        execute_command "git commit -m 'Initial environment configuration'"
        execute_command "git push -u origin main"
    fi
    
    log_success "Environment repository initialized"
}

# Configure Cloud Build triggers
configure_build_triggers() {
    if [ "$WORKSTATION_ONLY" = true ]; then
        log_warning "Skipping build triggers configuration (workstation-only mode)"
        return 0
    fi
    
    log_info "Configuring Cloud Build triggers..."
    
    # Create CI trigger for app repository
    execute_command "gcloud builds triggers create cloud-source-repositories \
        --repo=$APP_REPO \
        --branch-pattern='^main$' \
        --build-config=cloudbuild-ci.yaml \
        --description='CI pipeline for application code'"
    
    if [ "$DRY_RUN" = false ]; then
        # Push application code to trigger initial build
        cd ~/kubernetes-engine-samples/hello-app
        cp ~/cloudbuild-ci.yaml .
        execute_command "git add ."
        execute_command "git commit -m 'Add CI/CD pipeline configuration'"
        execute_command "git push app-origin main"
    fi
    
    log_success "Build triggers configured and initial pipeline started"
}

# Verify deployment
verify_deployment() {
    if [ "$DRY_RUN" = true ]; then
        log_warning "Skipping verification in dry run mode"
        return 0
    fi
    
    log_info "Verifying deployment..."
    
    if [ "$WORKSTATION_ONLY" != true ]; then
        # Check GKE clusters
        log_info "Checking GKE clusters..."
        if gcloud container clusters list --filter="name~${CLUSTER_NAME}" --format="value(name)" | grep -q "${CLUSTER_NAME}"; then
            log_success "GKE clusters are running"
        else
            log_warning "GKE clusters not found or not running"
        fi
        
        # Check Cloud Deploy pipeline
        log_info "Checking Cloud Deploy pipeline..."
        if gcloud deploy delivery-pipelines list --region="$REGION" --format="value(name)" | grep -q "gitops-pipeline"; then
            log_success "Cloud Deploy pipeline is configured"
        else
            log_warning "Cloud Deploy pipeline not found"
        fi
        
        # Check Artifact Registry
        log_info "Checking Artifact Registry..."
        if gcloud artifacts repositories list --location="$REGION" --format="value(name)" | grep -q "$APP_REPO"; then
            log_success "Artifact Registry repository exists"
        else
            log_warning "Artifact Registry repository not found"
        fi
    fi
    
    if [ "$PIPELINE_ONLY" != true ]; then
        # Check Cloud Workstations
        log_info "Checking Cloud Workstations..."
        if gcloud workstations list --config="$WORKSTATION_CONFIG" --cluster="${WORKSTATION_CONFIG}-cluster" --cluster-region="$REGION" --region="$REGION" --format="value(name)" | grep -q "dev-workstation"; then
            log_success "Cloud Workstation is available"
        else
            log_warning "Cloud Workstation not found"
        fi
    fi
    
    log_success "Deployment verification completed"
}

# Generate deployment summary
generate_summary() {
    log_info "Generating deployment summary..."
    
    cat << EOF

========================================
DEPLOYMENT SUMMARY
========================================

Project ID: $PROJECT_ID
Region: $REGION
Mode: $([ "$DRY_RUN" = true ] && echo "DRY RUN" || echo "DEPLOYMENT")

Resources Created:
EOF

    if [ "$WORKSTATION_ONLY" != true ]; then
        cat << EOF
- GKE Clusters:
  * ${CLUSTER_NAME}-staging
  * ${CLUSTER_NAME}-prod
- Artifact Registry: $APP_REPO
- Source Repositories:
  * $APP_REPO
  * $ENV_REPO
- Cloud Deploy Pipeline: gitops-pipeline
- Cloud Build Triggers: CI pipeline for $APP_REPO
EOF
    fi

    if [ "$PIPELINE_ONLY" != true ]; then
        cat << EOF
- Cloud Workstations:
  * Cluster: ${WORKSTATION_CONFIG}-cluster
  * Config: $WORKSTATION_CONFIG
  * Instance: dev-workstation
EOF
    fi

    cat << EOF

Next Steps:
EOF

    if [ "$DRY_RUN" = true ]; then
        echo "- Run the script without --dry-run to create the resources"
    else
        if [ "$PIPELINE_ONLY" != true ]; then
            cat << EOF
- Access your Cloud Workstation through the Google Cloud Console
- Start the workstation: gcloud workstations start dev-workstation --config=$WORKSTATION_CONFIG --cluster=${WORKSTATION_CONFIG}-cluster --cluster-region=$REGION --region=$REGION
EOF
        fi
        if [ "$WORKSTATION_ONLY" != true ]; then
            cat << EOF
- Monitor your CI/CD pipelines in Cloud Build and Cloud Deploy
- Access your application endpoints once deployed
EOF
        fi
        echo "- Use the destroy.sh script to clean up resources when finished"
    fi

    cat << EOF

Cost Considerations:
- GKE Autopilot clusters: ~$73/month per cluster
- Cloud Workstations: ~$0.04-0.20/hour depending on usage
- Cloud Build: $0.003/build minute after free tier
- Artifact Registry: $0.10/GB/month for storage

========================================
EOF
}

# Main function
main() {
    log_info "Starting GitOps Development Workflows deployment..."
    log_info "Log file: $LOG_FILE"
    
    parse_args "$@"
    check_prerequisites
    init_environment
    configure_gcloud
    enable_apis
    create_gke_clusters
    create_artifact_registry
    create_source_repositories
    setup_workstations
    create_ci_pipeline
    create_deploy_pipeline
    init_environment_repo
    configure_build_triggers
    verify_deployment
    generate_summary
    
    if [ "$DRY_RUN" = true ]; then
        log_success "Dry run completed successfully. Review the planned changes above."
    else
        log_success "GitOps Development Workflows deployment completed successfully!"
    fi
}

# Run main function with all arguments
main "$@"