#!/bin/bash

# =============================================================================
# Multi-Environment Application Deployment with Cloud Deploy and Cloud Build
# Deploy Script
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" "$ERROR_LOG"
            ;;
        "DEBUG")
            if [[ "${DEBUG:-}" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            fi
            ;;
    esac
}

log_step() {
    local step="$1"
    shift
    local message="$*"
    echo -e "\n${BLUE}=== Step $step: $message ===${NC}" | tee -a "$LOG_FILE"
}

# =============================================================================
# Error Handling
# =============================================================================

cleanup_on_error() {
    log "ERROR" "Deployment failed. Check logs at: $LOG_FILE and $ERROR_LOG"
    log "ERROR" "You may need to manually clean up resources to avoid charges"
    exit 1
}

trap cleanup_on_error ERR

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    log_step "0" "Checking Prerequisites"
    
    # Check if required tools are installed
    local required_tools=("gcloud" "kubectl" "docker" "openssl" "jq")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log "ERROR" "Missing required tools: ${missing_tools[*]}"
        log "ERROR" "Please install the missing tools and try again"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log "ERROR" "gcloud is not authenticated. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        log "ERROR" "Docker is not running. Please start Docker and try again"
        exit 1
    fi
    
    log "INFO" "All prerequisites are met"
}

# =============================================================================
# Environment Setup
# =============================================================================

setup_environment() {
    log_step "1" "Setting up Environment Variables"
    
    # Set environment variables for GCP resources
    export PROJECT_ID="${PROJECT_ID:-deploy-demo-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
        export RANDOM_SUFFIX
    fi
    
    # Set project-specific variables
    export CLUSTER_DEV="${CLUSTER_DEV:-dev-cluster-${RANDOM_SUFFIX}}"
    export CLUSTER_STAGE="${CLUSTER_STAGE:-staging-cluster-${RANDOM_SUFFIX}}"
    export CLUSTER_PROD="${CLUSTER_PROD:-prod-cluster-${RANDOM_SUFFIX}}"
    export REPO_NAME="${REPO_NAME:-app-repo-${RANDOM_SUFFIX}}"
    export PIPELINE_NAME="${PIPELINE_NAME:-app-pipeline-${RANDOM_SUFFIX}}"
    export BUCKET_NAME="${BUCKET_NAME:-deploy-artifacts-${PROJECT_ID}-${RANDOM_SUFFIX}}"
    
    # Save environment variables to file for later use
    cat > "${SCRIPT_DIR}/.env" << EOF
PROJECT_ID=$PROJECT_ID
REGION=$REGION
ZONE=$ZONE
RANDOM_SUFFIX=$RANDOM_SUFFIX
CLUSTER_DEV=$CLUSTER_DEV
CLUSTER_STAGE=$CLUSTER_STAGE
CLUSTER_PROD=$CLUSTER_PROD
REPO_NAME=$REPO_NAME
PIPELINE_NAME=$PIPELINE_NAME
BUCKET_NAME=$BUCKET_NAME
EOF
    
    log "INFO" "Environment variables configured:"
    log "INFO" "  PROJECT_ID: $PROJECT_ID"
    log "INFO" "  REGION: $REGION"
    log "INFO" "  ZONE: $ZONE"
    log "INFO" "  RANDOM_SUFFIX: $RANDOM_SUFFIX"
}

# =============================================================================
# GCP Project Configuration
# =============================================================================

configure_gcp_project() {
    log_step "2" "Configuring GCP Project"
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Enable required APIs
    local required_apis=(
        "compute.googleapis.com"
        "container.googleapis.com"
        "clouddeploy.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    log "INFO" "Enabling required APIs..."
    for api in "${required_apis[@]}"; do
        log "DEBUG" "Enabling $api..."
        gcloud services enable "$api" --quiet
    done
    
    # Wait for APIs to be fully enabled
    log "INFO" "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log "INFO" "Project configured: $PROJECT_ID"
    log "INFO" "APIs enabled for Cloud Deploy and Cloud Build"
}

# =============================================================================
# Artifact Registry Setup
# =============================================================================

create_artifact_registry() {
    log_step "3" "Creating Artifact Registry Repository"
    
    # Check if repository already exists
    if gcloud artifacts repositories describe "$REPO_NAME" \
        --location="$REGION" &> /dev/null; then
        log "WARN" "Artifact Registry repository $REPO_NAME already exists"
    else
        log "INFO" "Creating Artifact Registry repository..."
        gcloud artifacts repositories create "$REPO_NAME" \
            --repository-format=docker \
            --location="$REGION" \
            --description="Repository for multi-environment deployment demo"
    fi
    
    # Configure Docker authentication
    log "INFO" "Configuring Docker authentication..."
    gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
    
    log "INFO" "Artifact Registry repository created: $REPO_NAME"
}

# =============================================================================
# GKE Clusters Creation
# =============================================================================

create_gke_clusters() {
    log_step "4" "Creating GKE Clusters"
    
    # Function to create a GKE cluster
    create_cluster() {
        local cluster_name="$1"
        local environment="$2"
        local nodes="$3"
        local machine_type="$4"
        
        if gcloud container clusters describe "$cluster_name" --zone="$ZONE" &> /dev/null; then
            log "WARN" "GKE cluster $cluster_name already exists"
            return 0
        fi
        
        log "INFO" "Creating $environment GKE cluster: $cluster_name"
        gcloud container clusters create "$cluster_name" \
            --zone="$ZONE" \
            --num-nodes="$nodes" \
            --machine-type="$machine_type" \
            --enable-autorepair \
            --enable-autoupgrade \
            --labels="environment=$environment" \
            --quiet
        
        # Wait for cluster to be ready
        log "INFO" "Waiting for cluster $cluster_name to be ready..."
        gcloud container clusters get-credentials "$cluster_name" --zone="$ZONE"
        
        # Verify cluster is ready
        kubectl cluster-info --context="gke_${PROJECT_ID}_${ZONE}_${cluster_name}"
        
        log "INFO" "GKE cluster $cluster_name created successfully"
    }
    
    # Create development cluster
    create_cluster "$CLUSTER_DEV" "development" "2" "e2-standard-2"
    
    # Create staging cluster
    create_cluster "$CLUSTER_STAGE" "staging" "2" "e2-standard-2"
    
    # Create production cluster
    create_cluster "$CLUSTER_PROD" "production" "3" "e2-standard-4"
    
    log "INFO" "All GKE clusters created successfully"
}

# =============================================================================
# Cloud Storage Setup
# =============================================================================

create_cloud_storage() {
    log_step "5" "Creating Cloud Storage Bucket"
    
    # Check if bucket already exists
    if gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
        log "WARN" "Cloud Storage bucket $BUCKET_NAME already exists"
    else
        log "INFO" "Creating Cloud Storage bucket..."
        gsutil mb -p "$PROJECT_ID" \
            -c STANDARD \
            -l "$REGION" \
            "gs://$BUCKET_NAME"
        
        # Enable versioning for artifact tracking
        gsutil versioning set on "gs://$BUCKET_NAME"
    fi
    
    # Set appropriate IAM permissions for Cloud Deploy
    local compute_sa
    compute_sa=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")-compute@developer.gserviceaccount.com
    
    log "INFO" "Setting IAM permissions for Cloud Deploy..."
    gsutil iam ch "serviceAccount:$compute_sa:objectAdmin" "gs://$BUCKET_NAME"
    
    log "INFO" "Cloud Storage bucket created: $BUCKET_NAME"
}

# =============================================================================
# Application Source Code Setup
# =============================================================================

create_application_source() {
    log_step "6" "Creating Application Source Code"
    
    # Create application directory structure
    local app_dir="${SCRIPT_DIR}/../app-source"
    mkdir -p "$app_dir"/{k8s/{dev,staging,prod},skaffold}
    
    # Create simple web application
    cat > "$app_dir/app.py" << 'EOF'
from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/')
def hello():
    env = os.environ.get('ENVIRONMENT', 'unknown')
    version = os.environ.get('VERSION', '1.0.0')
    return f'Hello from {env} environment! Version: {version}'

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'environment': os.environ.get('ENVIRONMENT', 'unknown'),
        'version': os.environ.get('VERSION', '1.0.0')
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF
    
    # Create Dockerfile
    cat > "$app_dir/Dockerfile" << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# Copy requirements first for better layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app.py .

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run application
CMD ["python", "app.py"]
EOF
    
    # Create requirements.txt
    cat > "$app_dir/requirements.txt" << 'EOF'
Flask==2.3.3
gunicorn==21.2.0
requests==2.31.0
EOF
    
    log "INFO" "Application source code created"
}

# =============================================================================
# Kubernetes Manifests Creation
# =============================================================================

create_kubernetes_manifests() {
    log_step "7" "Creating Kubernetes Manifests"
    
    local app_dir="${SCRIPT_DIR}/../app-source"
    
    # Create development environment manifest
    cat > "$app_dir/k8s/dev/deployment.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  labels:
    app: sample-app
    environment: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
        environment: dev
    spec:
      containers:
      - name: app
        image: sample-app
        ports:
        - containerPort: 8080
        env:
        - name: ENVIRONMENT
          value: "development"
        - name: VERSION
          value: "1.0.0"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: sample-app-service
  labels:
    app: sample-app
spec:
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: sample-app
  type: LoadBalancer
EOF

    # Create staging environment manifest
    cat > "$app_dir/k8s/staging/deployment.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  labels:
    app: sample-app
    environment: staging
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
        environment: staging
    spec:
      containers:
      - name: app
        image: sample-app
        ports:
        - containerPort: 8080
        env:
        - name: ENVIRONMENT
          value: "staging"
        - name: VERSION
          value: "1.0.0"
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "400m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: sample-app-service
  labels:
    app: sample-app
spec:
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: sample-app
  type: LoadBalancer
EOF

    # Create production environment manifest
    cat > "$app_dir/k8s/prod/deployment.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  labels:
    app: sample-app
    environment: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
        environment: production
    spec:
      containers:
      - name: app
        image: sample-app
        ports:
        - containerPort: 8080
        env:
        - name: ENVIRONMENT
          value: "production"
        - name: VERSION
          value: "1.0.0"
        resources:
          requests:
            memory: "512Mi"
            cpu: "400m"
          limits:
            memory: "1Gi"
            cpu: "800m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: sample-app-service
  labels:
    app: sample-app
spec:
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: sample-app
  type: LoadBalancer
EOF
    
    log "INFO" "Kubernetes manifests created for all environments"
}

# =============================================================================
# Skaffold Configuration
# =============================================================================

create_skaffold_config() {
    log_step "8" "Creating Skaffold Configuration"
    
    local app_dir="${SCRIPT_DIR}/../app-source"
    
    cat > "$app_dir/skaffold.yaml" << EOF
apiVersion: skaffold/v4beta7
kind: Config
metadata:
  name: sample-app
build:
  artifacts:
  - image: sample-app
    docker:
      dockerfile: Dockerfile
  googleCloudBuild:
    projectId: ${PROJECT_ID}
profiles:
- name: dev
  deploy:
    kubectl:
      manifests:
      - k8s/dev/*.yaml
- name: staging
  deploy:
    kubectl:
      manifests:
      - k8s/staging/*.yaml
- name: prod
  deploy:
    kubectl:
      manifests:
      - k8s/prod/*.yaml
EOF
    
    log "INFO" "Skaffold configuration created"
}

# =============================================================================
# Cloud Deploy Pipeline Configuration
# =============================================================================

create_cloud_deploy_config() {
    log_step "9" "Creating Cloud Deploy Pipeline Configuration"
    
    local app_dir="${SCRIPT_DIR}/../app-source"
    
    cat > "$app_dir/clouddeploy.yaml" << EOF
apiVersion: deploy.cloud.google.com/v1
kind: DeliveryPipeline
metadata:
  name: ${PIPELINE_NAME}
description: Multi-environment deployment pipeline for sample application
serialPipeline:
  stages:
  - targetId: dev-target
    profiles: [dev]
  - targetId: staging-target
    profiles: [staging]
  - targetId: prod-target
    profiles: [prod]
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: dev-target
description: Development environment
gke:
  cluster: projects/${PROJECT_ID}/locations/${ZONE}/clusters/${CLUSTER_DEV}
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: staging-target
description: Staging environment
gke:
  cluster: projects/${PROJECT_ID}/locations/${ZONE}/clusters/${CLUSTER_STAGE}
requireApproval: false
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: prod-target
description: Production environment
gke:
  cluster: projects/${PROJECT_ID}/locations/${ZONE}/clusters/${CLUSTER_PROD}
requireApproval: true
EOF
    
    log "INFO" "Cloud Deploy pipeline configuration created"
}

# =============================================================================
# Cloud Build Configuration
# =============================================================================

create_cloud_build_config() {
    log_step "10" "Creating Cloud Build Configuration"
    
    local app_dir="${SCRIPT_DIR}/../app-source"
    
    cat > "$app_dir/cloudbuild.yaml" << EOF
steps:
# Build and push container image
- name: 'gcr.io/cloud-builders/docker'
  args:
  - 'build'
  - '-t'
  - '${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/sample-app:\${SHORT_SHA}'
  - '-t'
  - '${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/sample-app:latest'
  - '.'

# Push images to Artifact Registry
- name: 'gcr.io/cloud-builders/docker'
  args:
  - 'push'
  - '--all-tags'
  - '${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/sample-app'

# Create Cloud Deploy release
- name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
  entrypoint: 'gcloud'
  args:
  - 'deploy'
  - 'releases'
  - 'create'
  - 'release-\${SHORT_SHA}'
  - '--delivery-pipeline=${PIPELINE_NAME}'
  - '--region=${REGION}'
  - '--images=sample-app=${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/sample-app:\${SHORT_SHA}'

# Store build artifacts in Cloud Storage
artifacts:
  objects:
    location: 'gs://${BUCKET_NAME}/builds/\${SHORT_SHA}'
    paths:
    - 'skaffold.yaml'
    - 'clouddeploy.yaml'

substitutions:
  _REGION: '${REGION}'
  _REPO_NAME: '${REPO_NAME}'
  _PIPELINE_NAME: '${PIPELINE_NAME}'
  _BUCKET_NAME: '${BUCKET_NAME}'

options:
  logging: CLOUD_LOGGING_ONLY
EOF
    
    log "INFO" "Cloud Build configuration created"
}

# =============================================================================
# Pipeline Registration
# =============================================================================

register_pipeline() {
    log_step "11" "Registering Cloud Deploy Pipeline"
    
    local app_dir="${SCRIPT_DIR}/../app-source"
    
    # Register the delivery pipeline and targets with Cloud Deploy
    gcloud deploy apply \
        --file="$app_dir/clouddeploy.yaml" \
        --region="$REGION" \
        --project="$PROJECT_ID"
    
    # Wait for pipeline to be ready
    log "INFO" "Waiting for pipeline to be ready..."
    sleep 10
    
    # Verify pipeline registration
    gcloud deploy delivery-pipelines describe "$PIPELINE_NAME" \
        --region="$REGION" \
        --format="value(condition.state)" | grep -q "CONDITION_SUCCEEDED"
    
    log "INFO" "Cloud Deploy pipeline registered: $PIPELINE_NAME"
}

# =============================================================================
# Initial Deployment
# =============================================================================

deploy_initial_release() {
    log_step "12" "Creating Initial Release and Deployment"
    
    local app_dir="${SCRIPT_DIR}/../app-source"
    
    # Change to application directory
    cd "$app_dir"
    
    # Build and push initial container image
    log "INFO" "Building and pushing initial container image..."
    docker build -t "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/sample-app:v1.0.0" .
    docker push "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/sample-app:v1.0.0"
    
    # Create Cloud Deploy release
    log "INFO" "Creating Cloud Deploy release..."
    gcloud deploy releases create release-v1-0-0 \
        --delivery-pipeline="$PIPELINE_NAME" \
        --region="$REGION" \
        --images="sample-app=${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/sample-app:v1.0.0"
    
    # Wait for deployment to complete
    log "INFO" "Waiting for deployment to complete..."
    sleep 30
    
    # Check deployment status
    local rollout_status
    rollout_status=$(gcloud deploy rollouts list \
        --delivery-pipeline="$PIPELINE_NAME" \
        --region="$REGION" \
        --format="value(state)" \
        --limit=1)
    
    if [[ "$rollout_status" == "SUCCEEDED" ]]; then
        log "INFO" "Initial deployment completed successfully"
    else
        log "WARN" "Initial deployment status: $rollout_status"
    fi
    
    # Return to script directory
    cd "$SCRIPT_DIR"
}

# =============================================================================
# Validation
# =============================================================================

validate_deployment() {
    log_step "13" "Validating Deployment"
    
    # Check GKE cluster status
    log "INFO" "Checking GKE cluster status..."
    gcloud container clusters list \
        --filter="name:($CLUSTER_DEV OR $CLUSTER_STAGE OR $CLUSTER_PROD)" \
        --format="table(name,status,currentNodeCount,location)"
    
    # Check development deployment
    log "INFO" "Checking development deployment..."
    gcloud container clusters get-credentials "$CLUSTER_DEV" --zone="$ZONE" --quiet
    
    # Wait for load balancer IP
    log "INFO" "Waiting for load balancer IP in development..."
    local timeout=300
    local elapsed=0
    local dev_ip=""
    
    while [[ $elapsed -lt $timeout ]]; do
        dev_ip=$(kubectl get service sample-app-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [[ -n "$dev_ip" && "$dev_ip" != "null" ]]; then
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    if [[ -n "$dev_ip" && "$dev_ip" != "null" ]]; then
        log "INFO" "Development environment accessible at: http://$dev_ip"
        
        # Test application endpoint
        if curl -s -f "http://$dev_ip/" > /dev/null; then
            log "INFO" "Application is responding successfully"
        else
            log "WARN" "Application is not yet responding (may still be starting)"
        fi
    else
        log "WARN" "Load balancer IP not yet available"
    fi
    
    # Check Cloud Deploy pipeline status
    log "INFO" "Checking Cloud Deploy pipeline status..."
    gcloud deploy delivery-pipelines describe "$PIPELINE_NAME" \
        --region="$REGION" \
        --format="value(condition.state)"
    
    log "INFO" "Deployment validation completed"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    log "INFO" "Starting Multi-Environment Application Deployment"
    log "INFO" "Script started at: $(date)"
    
    # Initialize log files
    > "$LOG_FILE"
    > "$ERROR_LOG"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    configure_gcp_project
    create_artifact_registry
    create_gke_clusters
    create_cloud_storage
    create_application_source
    create_kubernetes_manifests
    create_skaffold_config
    create_cloud_deploy_config
    create_cloud_build_config
    register_pipeline
    deploy_initial_release
    validate_deployment
    
    log "INFO" "Deployment completed successfully!"
    log "INFO" "Environment variables saved to: ${SCRIPT_DIR}/.env"
    log "INFO" "Application source code created at: ${SCRIPT_DIR}/../app-source"
    log "INFO" "Deployment logs saved to: $LOG_FILE"
    
    # Display next steps
    echo -e "\n${GREEN}=== Deployment Complete ===${NC}"
    echo -e "${GREEN}Your multi-environment deployment pipeline is now ready!${NC}"
    echo -e "\n${BLUE}Next steps:${NC}"
    echo -e "1. Test your application in the development environment"
    echo -e "2. Promote to staging using Cloud Deploy console or CLI"
    echo -e "3. Review and approve production deployment"
    echo -e "\n${BLUE}Useful commands:${NC}"
    echo -e "  View pipeline: gcloud deploy delivery-pipelines describe $PIPELINE_NAME --region=$REGION"
    echo -e "  List releases: gcloud deploy releases list --delivery-pipeline=$PIPELINE_NAME --region=$REGION"
    echo -e "  Promote release: gcloud deploy releases promote --release=RELEASE_NAME --delivery-pipeline=$PIPELINE_NAME --region=$REGION"
    echo -e "\n${YELLOW}Remember to run ./destroy.sh when you're done to avoid ongoing charges!${NC}"
}

# Execute main function
main "$@"