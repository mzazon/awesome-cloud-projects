#!/bin/bash

# Enterprise Deployment Pipeline Deployment Script
# This script deploys a complete enterprise CI/CD pipeline using Cloud Build, Cloud Deploy, and Service Catalog

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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

# Function to check if required tools are installed
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if git is installed
    if ! command -v git &> /dev/null; then
        log_error "Git is not installed. Please install it first."
        exit 1
    fi
    
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get current project if not set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "No Google Cloud project set. Please set PROJECT_ID environment variable or configure default project."
            exit 1
        fi
    fi
    
    # Set default values for environment variables
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export CLUSTER_NAME="${CLUSTER_NAME:-enterprise-gke-${RANDOM_SUFFIX}}"
    export REPO_NAME="${REPO_NAME:-enterprise-apps}"
    export SERVICE_CATALOG_NAME="${SERVICE_CATALOG_NAME:-enterprise-templates}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Environment configured for project: ${PROJECT_ID}"
    log_info "Using region: ${REGION}, zone: ${ZONE}"
    log_info "Cluster name: ${CLUSTER_NAME}"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudbuild.googleapis.com"
        "clouddeploy.googleapis.com"
        "servicecatalog.googleapis.com"
        "container.googleapis.com"
        "artifactregistry.googleapis.com"
        "sourcerepo.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling API: ${api}"
        if gcloud services enable "${api}" --quiet; then
            log_success "API enabled: ${api}"
        else
            log_error "Failed to enable API: ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully activated..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create GKE clusters
create_gke_clusters() {
    log_info "Creating GKE clusters for multi-environment deployment..."
    
    local environments=("dev" "staging" "prod")
    
    for env in "${environments[@]}"; do
        local cluster_name="${CLUSTER_NAME}-${env}"
        log_info "Creating ${env} cluster: ${cluster_name}"
        
        local additional_flags=""
        if [[ "${env}" == "prod" ]]; then
            additional_flags="--enable-shielded-nodes"
        fi
        
        if gcloud container clusters create-auto "${cluster_name}" \
            --region="${REGION}" \
            --enable-network-policy \
            --enable-ip-alias \
            ${additional_flags} \
            --quiet; then
            log_success "Created ${env} cluster: ${cluster_name}"
        else
            log_error "Failed to create ${env} cluster: ${cluster_name}"
            exit 1
        fi
    done
    
    log_success "All GKE clusters created successfully"
}

# Function to create Artifact Registry repository
create_artifact_registry() {
    log_info "Creating Artifact Registry repository..."
    
    if gcloud artifacts repositories create "${REPO_NAME}" \
        --repository-format=docker \
        --location="${REGION}" \
        --description="Enterprise application container images" \
        --quiet; then
        log_success "Artifact Registry repository created: ${REPO_NAME}"
    else
        log_error "Failed to create Artifact Registry repository"
        exit 1
    fi
    
    # Configure Docker authentication
    log_info "Configuring Docker authentication..."
    if gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet; then
        log_success "Docker authentication configured"
    else
        log_warning "Docker authentication configuration may have failed"
    fi
}

# Function to create source repositories
create_source_repositories() {
    log_info "Creating Cloud Source Repositories..."
    
    local repos=("pipeline-templates" "sample-app")
    
    for repo in "${repos[@]}"; do
        log_info "Creating repository: ${repo}"
        if gcloud source repos create "${repo}" --quiet; then
            log_success "Repository created: ${repo}"
        else
            log_error "Failed to create repository: ${repo}"
            exit 1
        fi
    done
    
    # Clone repositories locally
    log_info "Cloning repositories locally..."
    for repo in "${repos[@]}"; do
        if [[ -d "./${repo}" ]]; then
            log_warning "Directory ${repo} already exists, removing..."
            rm -rf "./${repo}"
        fi
        
        if gcloud source repos clone "${repo}" "./${repo}"; then
            log_success "Repository cloned: ${repo}"
        else
            log_error "Failed to clone repository: ${repo}"
            exit 1
        fi
    done
}

# Function to create Cloud Deploy configuration
create_cloud_deploy_config() {
    log_info "Creating Cloud Deploy configuration..."
    
    cd "./pipeline-templates" || exit 1
    
    cat > clouddeploy.yaml << EOF
apiVersion: deploy.cloud.google.com/v1
kind: DeliveryPipeline
metadata:
  name: enterprise-pipeline
description: Enterprise deployment pipeline for applications
serialPipeline:
  stages:
  - targetId: dev-target
    profiles: []
  - targetId: staging-target
    profiles: []
  - targetId: prod-target
    profiles: []
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: dev-target
description: Development environment target
gke:
  cluster: projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_NAME}-dev
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: staging-target
description: Staging environment target
gke:
  cluster: projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_NAME}-staging
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: prod-target
description: Production environment target
gke:
  cluster: projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_NAME}-prod
EOF
    
    # Apply the Cloud Deploy configuration
    log_info "Applying Cloud Deploy configuration..."
    if gcloud deploy apply --file=clouddeploy.yaml --region="${REGION}" --quiet; then
        log_success "Cloud Deploy pipeline configured"
    else
        log_error "Failed to configure Cloud Deploy pipeline"
        exit 1
    fi
    
    cd ..
}

# Function to create Cloud Build template
create_cloud_build_template() {
    log_info "Creating Cloud Build template..."
    
    cd "./pipeline-templates" || exit 1
    
    cat > cloudbuild-template.yaml << EOF
steps:
# Build the container image
- name: 'gcr.io/cloud-builders/docker'
  args: 
  - 'build'
  - '-t'
  - '${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/\${_SERVICE_NAME}:\${SHORT_SHA}'
  - '.'

# Push the container image to Artifact Registry
- name: 'gcr.io/cloud-builders/docker'
  args:
  - 'push'
  - '${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/\${_SERVICE_NAME}:\${SHORT_SHA}'

# Create Kubernetes manifests
- name: 'gcr.io/cloud-builders/gke-deploy'
  args:
  - 'prepare'
  - '--filename=k8s/'
  - '--image=${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/\${_SERVICE_NAME}:\${SHORT_SHA}'
  - '--app=\${_SERVICE_NAME}'
  - '--version=\${SHORT_SHA}'
  - '--namespace=\${_NAMESPACE}'
  - '--output=output'

# Create Cloud Deploy release
- name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
  entrypoint: 'gcloud'
  args:
  - 'deploy'
  - 'releases'
  - 'create'
  - 'release-\${SHORT_SHA}'
  - '--delivery-pipeline=enterprise-pipeline'
  - '--region=${REGION}'
  - '--source=output'

substitutions:
  _SERVICE_NAME: 'sample-app'
  _NAMESPACE: 'default'

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: 'E2_STANDARD_4'
EOF
    
    log_success "Cloud Build template created"
    cd ..
}

# Function to create sample application
create_sample_application() {
    log_info "Creating sample application..."
    
    cd "./sample-app" || exit 1
    
    # Create Node.js application
    cat > app.js << 'EOF'
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.json({
    message: 'Enterprise Sample Application',
    environment: process.env.NODE_ENV || 'development',
    version: process.env.APP_VERSION || '1.0.0'
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy' });
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
EOF
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "enterprise-sample-app",
  "version": "1.0.0",
  "description": "Sample application for enterprise deployment pipeline",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.18.0"
  }
}
EOF
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
USER node
CMD ["npm", "start"]
EOF
    
    log_success "Sample application created"
    cd ..
}

# Function to create Kubernetes manifests
create_kubernetes_manifests() {
    log_info "Creating Kubernetes manifests..."
    
    cd "./sample-app" || exit 1
    mkdir -p k8s
    
    cat > k8s/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  labels:
    app: sample-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
    spec:
      containers:
      - name: app
        image: PLACEHOLDER_IMAGE
        ports:
        - containerPort: 3000
        env:
        - name: NODE_ENV
          value: "production"
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
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: sample-app-service
spec:
  selector:
    app: sample-app
  ports:
  - protocol: TCP
    port: 80
    targetPort: 3000
  type: ClusterIP
EOF
    
    log_success "Kubernetes manifests created"
    cd ..
}

# Function to configure IAM permissions
configure_iam_permissions() {
    log_info "Configuring IAM permissions..."
    
    # Create service account for Cloud Build
    log_info "Creating Cloud Build service account..."
    if gcloud iam service-accounts create cloudbuild-deploy \
        --display-name="Cloud Build Deploy Service Account" \
        --quiet; then
        log_success "Service account created: cloudbuild-deploy"
    else
        log_warning "Service account may already exist or creation failed"
    fi
    
    # Grant necessary permissions
    local service_account="cloudbuild-deploy@${PROJECT_ID}.iam.gserviceaccount.com"
    local roles=(
        "roles/clouddeploy.operator"
        "roles/container.clusterAdmin"
        "roles/artifactregistry.writer"
    )
    
    for role in "${roles[@]}"; do
        log_info "Granting role ${role} to service account..."
        if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${service_account}" \
            --role="${role}" \
            --quiet; then
            log_success "Role granted: ${role}"
        else
            log_error "Failed to grant role: ${role}"
            exit 1
        fi
    done
    
    # Configure Cloud Build to use the service account
    log_info "Configuring Cloud Build service account usage..."
    if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${PROJECT_ID}@cloudbuild.gserviceaccount.com" \
        --role="roles/iam.serviceAccountUser" \
        --quiet; then
        log_success "Cloud Build service account configured"
    else
        log_error "Failed to configure Cloud Build service account"
        exit 1
    fi
}

# Function to commit code and create build triggers
setup_build_triggers() {
    log_info "Setting up build triggers..."
    
    # Commit pipeline templates
    cd "./pipeline-templates" || exit 1
    git add .
    git commit -m "Initial pipeline templates and configurations"
    git push origin main
    cd ..
    
    # Commit sample application
    cd "./sample-app" || exit 1
    git add .
    git commit -m "Initial sample application"
    git push origin main
    cd ..
    
    # Create Cloud Build trigger
    log_info "Creating Cloud Build trigger..."
    if gcloud builds triggers create cloud-source-repositories \
        --repo=sample-app \
        --branch-pattern="main" \
        --build-config=cloudbuild-template.yaml \
        --description="Enterprise deployment pipeline trigger" \
        --quiet; then
        log_success "Build trigger created"
    else
        log_error "Failed to create build trigger"
        exit 1
    fi
}

# Function to test the deployment pipeline
test_deployment_pipeline() {
    log_info "Testing the deployment pipeline..."
    
    cd "./sample-app" || exit 1
    
    # Make a test change
    echo "console.log('Pipeline test - $(date)');" >> app.js
    git add app.js
    git commit -m "Test pipeline deployment - $(date)"
    git push origin main
    
    log_success "Test commit pushed - pipeline should trigger automatically"
    log_info "Monitor progress in Cloud Console:"
    log_info "  Cloud Build: https://console.cloud.google.com/cloud-build/builds?project=${PROJECT_ID}"
    log_info "  Cloud Deploy: https://console.cloud.google.com/deploy/delivery-pipelines?project=${PROJECT_ID}"
    
    cd ..
}

# Function to display deployment information
display_deployment_info() {
    log_success "Enterprise deployment pipeline deployed successfully!"
    echo
    log_info "Deployment Summary:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  GKE Clusters: ${CLUSTER_NAME}-{dev,staging,prod}"
    echo "  Artifact Registry: ${REPO_NAME}"
    echo "  Source Repositories: pipeline-templates, sample-app"
    echo
    log_info "Useful Commands:"
    echo "  # Monitor builds:"
    echo "  gcloud builds list --ongoing"
    echo
    echo "  # Check delivery pipeline:"
    echo "  gcloud deploy delivery-pipelines describe enterprise-pipeline --region=${REGION}"
    echo
    echo "  # Connect to development cluster:"
    echo "  gcloud container clusters get-credentials ${CLUSTER_NAME}-dev --region=${REGION}"
    echo
    log_info "Next Steps:"
    echo "  1. Monitor the initial build in Cloud Console"
    echo "  2. Approve deployments through Cloud Deploy"
    echo "  3. Customize pipeline templates for your applications"
    echo "  4. Create Service Catalog entries for team self-service"
    echo
    log_warning "Remember to run ./destroy.sh when you're done to avoid ongoing charges"
}

# Main deployment function
main() {
    log_info "Starting enterprise deployment pipeline deployment..."
    
    check_prerequisites
    setup_environment
    enable_apis
    create_gke_clusters
    create_artifact_registry
    create_source_repositories
    create_cloud_deploy_config
    create_cloud_build_template
    create_sample_application
    create_kubernetes_manifests
    configure_iam_permissions
    setup_build_triggers
    test_deployment_pipeline
    display_deployment_info
    
    log_success "Deployment completed successfully!"
}

# Handle script interruption
cleanup_on_exit() {
    log_warning "Script interrupted. Some resources may have been created."
    log_info "Run ./destroy.sh to clean up any created resources."
    exit 1
}

# Set up signal handlers
trap cleanup_on_exit INT TERM

# Run main function
main "$@"