#!/bin/bash

# Deploy script for Multi-Environment Application Deployment with Cloud Deploy and Cloud Build
# This script automates the deployment of a CI/CD pipeline using Google Cloud Deploy and Cloud Build

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
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

# Check if gcloud is installed and configured
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v git &> /dev/null; then
        log_error "git is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values or use existing environment variables
    export PROJECT_ID="${PROJECT_ID:-my-cicd-project-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export CLUSTER_PREFIX="${CLUSTER_PREFIX:-deploy-demo-${RANDOM_SUFFIX}}"
    export PIPELINE_NAME="${PIPELINE_NAME:-sample-app-pipeline}"
    export APP_NAME="${APP_NAME:-sample-webapp}"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Zone: ${ZONE}"
    log_info "Cluster Prefix: ${CLUSTER_PREFIX}"
    log_info "Pipeline Name: ${PIPELINE_NAME}"
    log_info "App Name: ${APP_NAME}"
    
    log_success "Environment variables configured"
}

# Create and configure GCP project
setup_project() {
    log_info "Setting up GCP project..."
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_warning "Project ${PROJECT_ID} already exists. Using existing project."
    else
        log_info "Creating new project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" --name="CI/CD Demo Project"
    fi
    
    # Set current project
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required APIs..."
    
    local apis=(
        "container.googleapis.com"
        "cloudbuild.googleapis.com"
        "clouddeploy.googleapis.com"
        "storage.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}"
    done
    
    log_success "Required APIs enabled"
}

# Create Cloud Storage bucket for build artifacts
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for build artifacts..."
    
    local bucket_name="${PROJECT_ID}-build-artifacts"
    
    if gsutil ls gs://"${bucket_name}" &> /dev/null; then
        log_warning "Bucket gs://${bucket_name} already exists. Using existing bucket."
    else
        gsutil mb gs://"${bucket_name}"
        log_success "Storage bucket created: gs://${bucket_name}"
    fi
}

# Create GKE clusters for all environments
create_gke_clusters() {
    log_info "Creating GKE clusters for all environments..."
    
    local environments=("dev" "staging" "prod")
    
    for env in "${environments[@]}"; do
        local cluster_name="${CLUSTER_PREFIX}-${env}"
        
        # Check if cluster already exists
        if gcloud container clusters describe "${cluster_name}" --region="${REGION}" &> /dev/null; then
            log_warning "Cluster ${cluster_name} already exists. Skipping creation."
            continue
        fi
        
        log_info "Creating ${env} cluster: ${cluster_name}"
        gcloud container clusters create-auto "${cluster_name}" \
            --region="${REGION}" \
            --release-channel=regular \
            --labels=env="${env}",app="${APP_NAME}" \
            --async
    done
    
    # Wait for all clusters to be ready
    log_info "Waiting for clusters to be ready..."
    for env in "${environments[@]}"; do
        local cluster_name="${CLUSTER_PREFIX}-${env}"
        gcloud container clusters describe "${cluster_name}" --region="${REGION}" --format="value(status)" | grep -q "RUNNING" || {
            log_info "Waiting for ${cluster_name} to be ready..."
            while [[ "$(gcloud container clusters describe "${cluster_name}" --region="${REGION}" --format="value(status)")" != "RUNNING" ]]; do
                sleep 30
            done
        }
        log_success "${env} cluster is ready: ${cluster_name}"
    done
}

# Configure kubectl contexts for all environments
configure_kubectl_contexts() {
    log_info "Configuring kubectl contexts for all environments..."
    
    local environments=("dev" "staging" "prod")
    
    for env in "${environments[@]}"; do
        local cluster_name="${CLUSTER_PREFIX}-${env}"
        
        # Get credentials
        gcloud container clusters get-credentials "${cluster_name}" --region="${REGION}"
        
        # Rename context for clarity
        local old_context="gke_${PROJECT_ID}_${REGION}_${cluster_name}"
        local new_context="${env}-context"
        
        if kubectl config get-contexts "${new_context}" &> /dev/null; then
            log_warning "Context ${new_context} already exists. Skipping rename."
        else
            kubectl config rename-context "${old_context}" "${new_context}"
            log_success "Context renamed to ${new_context}"
        fi
    done
    
    # Set development as default context
    kubectl config use-context dev-context
    log_success "kubectl contexts configured"
}

# Create sample application and Kubernetes manifests
create_sample_application() {
    log_info "Creating sample application and Kubernetes manifests..."
    
    # Create application directory structure
    mkdir -p "${APP_NAME}"/{src,k8s/{base,overlays/{dev,staging,prod}}}
    
    # Create sample Node.js application
    cat > "${APP_NAME}/src/app.js" << 'EOF'
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;
const environment = process.env.NODE_ENV || 'development';

app.get('/', (req, res) => {
  res.json({
    message: 'Hello from Cloud Deploy!',
    environment: environment,
    timestamp: new Date().toISOString(),
    hostname: process.env.HOSTNAME || 'localhost'
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy' });
});

app.listen(port, () => {
  console.log(`Server running on port ${port} in ${environment} environment`);
});
EOF
    
    # Create package.json
    cat > "${APP_NAME}/src/package.json" << 'EOF'
{
  "name": "sample-webapp",
  "version": "1.0.0",
  "description": "Sample web application for Cloud Deploy demo",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF
    
    # Create Dockerfile
    cat > "${APP_NAME}/Dockerfile" << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY src/package.json .
RUN npm install
COPY src/ .
EXPOSE 3000
CMD ["npm", "start"]
EOF
    
    log_success "Sample application created"
}

# Create base Kubernetes manifests
create_kubernetes_manifests() {
    log_info "Creating base Kubernetes manifests..."
    
    # Create base deployment manifest
    cat > "${APP_NAME}/k8s/base/deployment.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  labels:
    app: ${APP_NAME}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
    spec:
      containers:
      - name: webapp
        image: gcr.io/${PROJECT_ID}/${APP_NAME}:latest
        ports:
        - containerPort: 3000
        env:
        - name: NODE_ENV
          value: "production"
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
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF
    
    # Create service manifest
    cat > "${APP_NAME}/k8s/base/service.yaml" << EOF
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}-service
  labels:
    app: ${APP_NAME}
spec:
  selector:
    app: ${APP_NAME}
  ports:
  - protocol: TCP
    port: 80
    targetPort: 3000
  type: LoadBalancer
EOF
    
    log_success "Base Kubernetes manifests created"
}

# Create environment-specific Kustomize overlays
create_kustomize_overlays() {
    log_info "Creating environment-specific Kustomize overlays..."
    
    # Create development overlay
    cat > "${APP_NAME}/k8s/overlays/dev/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../base

replicas:
- name: ${APP_NAME}
  count: 1

patches:
- target:
    kind: Deployment
    name: ${APP_NAME}
  patch: |-
    - op: replace
      path: /spec/template/spec/containers/0/env/0/value
      value: "development"
    - op: replace
      path: /spec/template/spec/containers/0/resources/requests/cpu
      value: "50m"
    - op: replace
      path: /spec/template/spec/containers/0/resources/limits/cpu
      value: "200m"

namePrefix: dev-
EOF
    
    # Create staging overlay
    cat > "${APP_NAME}/k8s/overlays/staging/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../base

replicas:
- name: ${APP_NAME}
  count: 2

patches:
- target:
    kind: Deployment
    name: ${APP_NAME}
  patch: |-
    - op: replace
      path: /spec/template/spec/containers/0/env/0/value
      value: "staging"

namePrefix: staging-
EOF
    
    # Create production overlay
    cat > "${APP_NAME}/k8s/overlays/prod/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../base

replicas:
- name: ${APP_NAME}
  count: 3

patches:
- target:
    kind: Deployment
    name: ${APP_NAME}
  patch: |-
    - op: replace
      path: /spec/template/spec/containers/0/env/0/value
      value: "production"
    - op: replace
      path: /spec/template/spec/containers/0/resources/requests/cpu
      value: "200m"
    - op: replace
      path: /spec/template/spec/containers/0/resources/limits/cpu
      value: "1000m"
    - op: replace
      path: /spec/template/spec/containers/0/resources/limits/memory
      value: "1Gi"

namePrefix: prod-
EOF
    
    log_success "Environment-specific Kustomize overlays created"
}

# Create Cloud Build configuration
create_cloud_build_config() {
    log_info "Creating Cloud Build configuration..."
    
    cat > "${APP_NAME}/cloudbuild.yaml" << EOF
steps:
# Build the container image
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', 'gcr.io/${PROJECT_ID}/${APP_NAME}:\$SHORT_SHA', '.']

# Push the image to Container Registry
- name: 'gcr.io/cloud-builders/docker'
  args: ['push', 'gcr.io/${PROJECT_ID}/${APP_NAME}:\$SHORT_SHA']

# Update image tag in manifests
- name: 'gcr.io/cloud-builders/gke-deploy'
  args:
  - prepare
  - --filename=k8s/overlays/dev
  - --image=gcr.io/${PROJECT_ID}/${APP_NAME}:\$SHORT_SHA
  - --app=${APP_NAME}
  - --version=\$SHORT_SHA
  - --namespace=default
  - --output=output

# Create release in Cloud Deploy
- name: 'gcr.io/cloud-builders/gcloud'
  args:
  - deploy
  - releases
  - create
  - release-\$SHORT_SHA
  - --delivery-pipeline=${PIPELINE_NAME}
  - --region=${REGION}
  - --source=output

images:
- 'gcr.io/${PROJECT_ID}/${APP_NAME}:\$SHORT_SHA'

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: 'E2_HIGHCPU_8'

timeout: 1200s
EOF
    
    log_success "Cloud Build configuration created"
}

# Create Cloud Deploy pipeline configuration
create_cloud_deploy_config() {
    log_info "Creating Cloud Deploy pipeline configuration..."
    
    cat > "${APP_NAME}/clouddeploy.yaml" << EOF
apiVersion: deploy.cloud.google.com/v1
kind: DeliveryPipeline
metadata:
  name: ${PIPELINE_NAME}
description: Multi-environment deployment pipeline for ${APP_NAME}
serialPipeline:
  stages:
  - targetId: dev-target
    profiles: []
    strategy:
      standard:
        verify: false
  - targetId: staging-target
    profiles: []
    strategy:
      standard:
        verify: true
  - targetId: prod-target
    profiles: []
    strategy:
      canary:
        runtimeConfig:
          kubernetes:
            serviceNetworking:
              service: prod-${APP_NAME}-service
              deployment: prod-${APP_NAME}
        canaryDeployment:
          percentages: [25, 50, 100]
          verify: true
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: dev-target
description: Development environment target
gke:
  cluster: projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_PREFIX}-dev
executionConfigs:
- usages:
  - RENDER
  - DEPLOY
  defaultPool:
    serviceAccount: \${_CLOUDDEPLOY_SA_EMAIL}
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: staging-target
description: Staging environment target
gke:
  cluster: projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_PREFIX}-staging
executionConfigs:
- usages:
  - RENDER
  - DEPLOY
  defaultPool:
    serviceAccount: \${_CLOUDDEPLOY_SA_EMAIL}
requireApproval: true
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: prod-target
description: Production environment target
gke:
  cluster: projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_PREFIX}-prod
executionConfigs:
- usages:
  - RENDER
  - DEPLOY
  defaultPool:
    serviceAccount: \${_CLOUDDEPLOY_SA_EMAIL}
requireApproval: true
EOF
    
    log_success "Cloud Deploy pipeline configuration created"
}

# Create and configure Cloud Deploy service account
setup_service_account() {
    log_info "Creating Cloud Deploy service account..."
    
    local sa_name="clouddeploy-sa"
    local sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "${sa_email}" &> /dev/null; then
        log_warning "Service account ${sa_email} already exists. Using existing account."
    else
        gcloud iam service-accounts create "${sa_name}" \
            --display-name="Cloud Deploy Service Account"
        log_success "Service account created: ${sa_email}"
    fi
    
    # Grant necessary permissions
    log_info "Granting necessary permissions to service account..."
    
    local roles=(
        "roles/container.clusterAdmin"
        "roles/clouddeploy.jobRunner"
    )
    
    for role in "${roles[@]}"; do
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${sa_email}" \
            --role="${role}"
    done
    
    # Export service account email for use in other functions
    export _CLOUDDEPLOY_SA_EMAIL="${sa_email}"
    
    log_success "Service account permissions configured"
}

# Apply Cloud Deploy pipeline
apply_cloud_deploy_pipeline() {
    log_info "Applying Cloud Deploy pipeline..."
    
    cd "${APP_NAME}"
    
    gcloud deploy apply \
        --file=clouddeploy.yaml \
        --region="${REGION}" \
        --project="${PROJECT_ID}"
    
    cd ..
    
    log_success "Cloud Deploy pipeline applied"
}

# Set up Cloud Build trigger and permissions
setup_cloud_build() {
    log_info "Setting up Cloud Build trigger and permissions..."
    
    cd "${APP_NAME}"
    
    # Initialize git repository
    if [ ! -d ".git" ]; then
        git init
        git add .
        git commit -m "Initial commit: Multi-environment deployment setup"
        log_success "Git repository initialized"
    else
        log_warning "Git repository already exists"
    fi
    
    # Create Cloud Build trigger (manual trigger for demo)
    if ! gcloud builds triggers describe "${APP_NAME}-trigger" --region="${REGION}" &> /dev/null; then
        gcloud builds triggers create manual \
            --name="${APP_NAME}-trigger" \
            --repo-type=CLOUD_SOURCE_REPOSITORIES \
            --branch-pattern="main" \
            --build-config="cloudbuild.yaml" \
            --substitutions=_CLOUDDEPLOY_SA_EMAIL="${_CLOUDDEPLOY_SA_EMAIL}"
        log_success "Cloud Build trigger created"
    else
        log_warning "Cloud Build trigger already exists"
    fi
    
    # Grant Cloud Build service account necessary permissions
    local project_number
    project_number=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
    local cb_sa="${project_number}@cloudbuild.gserviceaccount.com"
    
    local cb_roles=(
        "roles/clouddeploy.releaser"
        "roles/container.admin"
    )
    
    for role in "${cb_roles[@]}"; do
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${cb_sa}" \
            --role="${role}"
    done
    
    cd ..
    
    log_success "Cloud Build permissions configured"
}

# Execute initial build and deployment
execute_initial_build() {
    log_info "Executing initial build and deployment..."
    
    cd "${APP_NAME}"
    
    # Trigger initial build
    gcloud builds submit . \
        --config=cloudbuild.yaml \
        --substitutions=_CLOUDDEPLOY_SA_EMAIL="${_CLOUDDEPLOY_SA_EMAIL}"
    
    cd ..
    
    log_success "Initial build and deployment initiated"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check Cloud Deploy pipeline status
    local pipeline_status
    pipeline_status=$(gcloud deploy delivery-pipelines describe "${PIPELINE_NAME}" \
        --region="${REGION}" \
        --format="value(condition.pipelineReadyCondition.status)" 2>/dev/null || echo "UNKNOWN")
    
    if [ "${pipeline_status}" = "True" ]; then
        log_success "Cloud Deploy pipeline is ready"
    else
        log_warning "Cloud Deploy pipeline status: ${pipeline_status}"
    fi
    
    # List releases
    log_info "Listing Cloud Deploy releases..."
    gcloud deploy releases list \
        --delivery-pipeline="${PIPELINE_NAME}" \
        --region="${REGION}" \
        --format="table(name,createTime,deployState)" || true
    
    log_info "Deployment verification completed"
}

# Main deployment function
main() {
    log_info "Starting multi-environment application deployment..."
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage_bucket
    create_gke_clusters
    configure_kubectl_contexts
    create_sample_application
    create_kubernetes_manifests
    create_kustomize_overlays
    create_cloud_build_config
    create_cloud_deploy_config
    setup_service_account
    apply_cloud_deploy_pipeline
    setup_cloud_build
    execute_initial_build
    verify_deployment
    
    log_success "Multi-environment application deployment completed successfully!"
    log_info "Next steps:"
    log_info "1. Check the Cloud Deploy console for deployment progress"
    log_info "2. Monitor the Cloud Build logs for build status"
    log_info "3. Verify applications are running in all environments"
    log_info "4. Test the application endpoints when load balancers are ready"
}

# Run main function
main "$@"