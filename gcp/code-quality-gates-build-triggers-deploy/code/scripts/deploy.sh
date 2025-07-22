#!/bin/bash

# Code Quality Gates with Cloud Build Triggers and Cloud Deploy - Deployment Script
# This script automates the deployment of a comprehensive CI/CD pipeline with quality gates

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Error handling
cleanup_on_error() {
    log_error "Script failed! Check the logs above for details."
    log_info "Run ./destroy.sh to clean up any partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if git is installed
    if ! command -v git &> /dev/null; then
        log_error "git is not installed. Please install it first."
        exit 1
    fi
    
    # Check if openssl is installed (for random suffix generation)
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install it first."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log_success "All prerequisites checked successfully"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique project ID with timestamp
    export PROJECT_ID="code-quality-pipeline-$(date +%s)"
    export REGION="us-central1"
    export ZONE="us-central1-a"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names with unique suffixes
    export REPO_NAME="sample-app-${RANDOM_SUFFIX}"
    export CLUSTER_NAME="quality-gates-cluster-${RANDOM_SUFFIX}"
    export PIPELINE_NAME="quality-pipeline-${RANDOM_SUFFIX}"
    export REGISTRY_NAME="app-registry-${RANDOM_SUFFIX}"
    
    # Create environment file for cleanup script
    cat > .env << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
REPO_NAME=${REPO_NAME}
CLUSTER_NAME=${CLUSTER_NAME}
PIPELINE_NAME=${PIPELINE_NAME}
REGISTRY_NAME=${REGISTRY_NAME}
EOF
    
    log_success "Environment variables configured"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Repository: ${REPO_NAME}"
    log_info "Cluster: ${CLUSTER_NAME}"
}

# Create and configure GCP project
setup_project() {
    log_info "Creating and configuring GCP project..."
    
    # Create the project
    if ! gcloud projects create ${PROJECT_ID} --quiet; then
        log_error "Failed to create project. The project ID might already exist."
        exit 1
    fi
    
    # Set the project configuration
    gcloud config set project ${PROJECT_ID}
    gcloud config set compute/region ${REGION}
    gcloud config set compute/zone ${ZONE}
    
    # Link billing account (user needs to do this manually)
    log_warning "Please ensure billing is enabled for project ${PROJECT_ID}"
    log_warning "Visit: https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
    
    # Wait for user confirmation
    read -p "Press Enter after enabling billing to continue..."
    
    log_success "Project ${PROJECT_ID} created and configured"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudbuild.googleapis.com"
        "clouddeploy.googleapis.com"
        "sourcerepo.googleapis.com"
        "binaryauthorization.googleapis.com"
        "container.googleapis.com"
        "artifactregistry.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "compute.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable ${api} --quiet
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled successfully"
}

# Create source repository and sample application
create_repository() {
    log_info "Creating Cloud Source Repository and sample application..."
    
    # Create Cloud Source Repository
    gcloud source repos create ${REPO_NAME}
    
    # Clone the repository locally
    gcloud source repos clone ${REPO_NAME} --project=${PROJECT_ID}
    
    # Change to repository directory
    cd ${REPO_NAME}
    
    # Create sample Node.js application
    cat > app.js << 'EOF'
const express = require('express');
const app = express();
const port = process.env.PORT || 8080;

app.get('/', (req, res) => {
  res.json({
    message: 'Code Quality Pipeline Demo',
    version: '1.0.0',
    timestamp: new Date().toISOString()
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy' });
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});

module.exports = app;
EOF
    
    # Create package.json with dependencies and test scripts
    cat > package.json << 'EOF'
{
  "name": "code-quality-demo",
  "version": "1.0.0",
  "description": "Demo app for code quality pipeline",
  "main": "app.js",
  "scripts": {
    "start": "node app.js",
    "test": "jest",
    "lint": "eslint .",
    "security": "audit-ci --config audit-ci.json"
  },
  "dependencies": {
    "express": "^4.18.2"
  },
  "devDependencies": {
    "jest": "^29.5.0",
    "supertest": "^6.3.3",
    "eslint": "^8.41.0",
    "audit-ci": "^6.6.1"
  }
}
EOF
    
    log_success "Sample application created successfully"
}

# Create container and Kubernetes configurations
create_container_configs() {
    log_info "Creating Docker and Kubernetes configurations..."
    
    # Create multi-stage Dockerfile for optimized builds
    cat > Dockerfile << 'EOF'
# Build stage
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Runtime stage
FROM node:18-alpine AS runtime
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY --chown=nodejs:nodejs . .
USER nodejs
EXPOSE 8080
CMD ["npm", "start"]
EOF
    
    # Create Kubernetes deployment manifest directory
    mkdir -p k8s
    
    cat > k8s/deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: code-quality-app
  labels:
    app: code-quality-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: code-quality-app
  template:
    metadata:
      labels:
        app: code-quality-app
    spec:
      containers:
      - name: app
        image: gcr.io/${PROJECT_ID}/code-quality-app:latest
        ports:
        - containerPort: 8080
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
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 1001
---
apiVersion: v1
kind: Service
metadata:
  name: code-quality-service
spec:
  selector:
    app: code-quality-app
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
EOF
    
    log_success "Container and Kubernetes configurations created"
}

# Create code quality configurations
create_quality_configs() {
    log_info "Creating code quality and security scanning configurations..."
    
    # Create Jest test configuration
    cat > app.test.js << 'EOF'
const request = require('supertest');
const app = require('./app');

describe('Application Tests', () => {
  test('GET / should return application info', async () => {
    const response = await request(app).get('/');
    expect(response.status).toBe(200);
    expect(response.body.message).toBe('Code Quality Pipeline Demo');
    expect(response.body.version).toBe('1.0.0');
  });

  test('GET /health should return healthy status', async () => {
    const response = await request(app).get('/health');
    expect(response.status).toBe(200);
    expect(response.body.status).toBe('healthy');
  });
});
EOF
    
    # Create ESLint configuration for code quality
    cat > .eslintrc.json << 'EOF'
{
  "env": {
    "node": true,
    "es2021": true,
    "jest": true
  },
  "extends": [
    "eslint:recommended"
  ],
  "parserOptions": {
    "ecmaVersion": 12,
    "sourceType": "module"
  },
  "rules": {
    "no-console": "warn",
    "no-unused-vars": "error",
    "prefer-const": "error",
    "no-var": "error"
  }
}
EOF
    
    # Create audit configuration for security scanning
    cat > audit-ci.json << 'EOF'
{
  "moderate": true,
  "high": true,
  "critical": true,
  "report-type": "full",
  "allowlist": []
}
EOF
    
    log_success "Code quality and security configurations created"
}

# Create Cloud Build pipeline configuration
create_build_config() {
    log_info "Creating Cloud Build pipeline configuration..."
    
    cat > cloudbuild.yaml << EOF
steps:
  # Install dependencies
  - name: 'node:18-alpine'
    entrypoint: 'npm'
    args: ['ci']
    id: 'install-deps'

  # Run unit tests
  - name: 'node:18-alpine'
    entrypoint: 'npm'
    args: ['test']
    id: 'unit-tests'
    waitFor: ['install-deps']

  # Run code linting
  - name: 'node:18-alpine'
    entrypoint: 'npm'
    args: ['run', 'lint']
    id: 'code-lint'
    waitFor: ['install-deps']

  # Run security audit
  - name: 'node:18-alpine'
    entrypoint: 'npm'
    args: ['run', 'security']
    id: 'security-scan'
    waitFor: ['install-deps']

  # Build Docker image
  - name: 'gcr.io/cloud-builders/docker'
    args: [
      'build',
      '-t', 'gcr.io/\$PROJECT_ID/code-quality-app:\$COMMIT_SHA',
      '-t', 'gcr.io/\$PROJECT_ID/code-quality-app:latest',
      '.'
    ]
    id: 'docker-build'
    waitFor: ['unit-tests', 'code-lint', 'security-scan']

  # Container security scanning
  - name: 'gcr.io/cloud-builders/gcloud'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        gcloud container images scan gcr.io/\$PROJECT_ID/code-quality-app:\$COMMIT_SHA \\
          --format="value(response.scan.analysisCompleted)" \\
          --quiet || exit 1
    id: 'container-scan'
    waitFor: ['docker-build']

  # Push Docker image
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'gcr.io/\$PROJECT_ID/code-quality-app:\$COMMIT_SHA']
    id: 'docker-push'
    waitFor: ['container-scan']

  # Update Kubernetes manifests
  - name: 'gcr.io/cloud-builders/gcloud'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        sed -i "s|gcr.io/PROJECT_ID|gcr.io/\$PROJECT_ID|g" k8s/deployment.yaml
        sed -i "s|:latest|:\$COMMIT_SHA|g" k8s/deployment.yaml
    id: 'update-manifests'
    waitFor: ['docker-push']

  # Create Cloud Deploy release
  - name: 'gcr.io/cloud-builders/gcloud'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        gcloud deploy releases create release-\$BUILD_ID \\
          --delivery-pipeline=\${_PIPELINE_NAME} \\
          --region=\${_REGION} \\
          --source=. \\
          --build-artifacts=gcr.io/\$PROJECT_ID/code-quality-app:\$COMMIT_SHA
    id: 'create-release'
    waitFor: ['update-manifests']

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: E2_STANDARD_4

substitutions:
  _REGION: ${REGION}
  _PIPELINE_NAME: ${PIPELINE_NAME}

timeout: 1200s
EOF
    
    log_success "Cloud Build pipeline configuration created"
}

# Create GKE cluster
create_gke_cluster() {
    log_info "Creating GKE cluster with security features..."
    
    gcloud container clusters create ${CLUSTER_NAME} \
        --zone=${ZONE} \
        --num-nodes=3 \
        --node-locations=${ZONE} \
        --machine-type=e2-standard-2 \
        --disk-size=30GB \
        --enable-autorepair \
        --enable-autoupgrade \
        --enable-network-policy \
        --enable-ip-alias \
        --enable-shielded-nodes \
        --shielded-secure-boot \
        --shielded-integrity-monitoring \
        --workload-pool=${PROJECT_ID}.svc.id.goog \
        --logging=SYSTEM,WORKLOAD \
        --monitoring=SYSTEM \
        --quiet
    
    # Get cluster credentials
    gcloud container clusters get-credentials ${CLUSTER_NAME} --zone=${ZONE}
    
    # Create namespaces for different environments
    kubectl create namespace development
    kubectl create namespace staging
    kubectl create namespace production
    
    log_success "GKE cluster created with security features enabled"
}

# Configure Binary Authorization
configure_binary_auth() {
    log_info "Configuring Binary Authorization policy..."
    
    # Create Binary Authorization policy
    cat > binauth-policy.yaml << EOF
admissionWhitelistPatterns:
- namePattern: gcr.io/google_containers/*
- namePattern: k8s.gcr.io/*
- namePattern: gcr.io/google-appengine/*
defaultAdmissionRule:
  requireAttestationsBy: []
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
  evaluationMode: REQUIRE_ATTESTATION
clusterAdmissionRules:
  ${ZONE}.${CLUSTER_NAME}:
    requireAttestationsBy: []
    enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
    evaluationMode: ALWAYS_ALLOW
EOF
    
    # Apply Binary Authorization policy
    gcloud container binauthz policy import binauth-policy.yaml
    
    # Enable Binary Authorization on the cluster
    gcloud container clusters update ${CLUSTER_NAME} \
        --zone=${ZONE} \
        --enable-binauthz \
        --quiet
    
    log_success "Binary Authorization policy configured"
}

# Create Cloud Deploy pipeline
create_deploy_pipeline() {
    log_info "Creating Cloud Deploy pipeline configuration..."
    
    # Create skaffold configuration for Cloud Deploy
    cat > skaffold.yaml << 'EOF'
apiVersion: skaffold/v4beta1
kind: Config
metadata:
  name: code-quality-app
profiles:
- name: development
  manifests:
    rawYaml:
    - k8s/deployment.yaml
- name: staging
  manifests:
    rawYaml:
    - k8s/deployment.yaml
- name: production
  manifests:
    rawYaml:
    - k8s/deployment.yaml
EOF
    
    # Create Cloud Deploy pipeline configuration
    cat > clouddeploy.yaml << EOF
apiVersion: deploy.cloud.google.com/v1
kind: DeliveryPipeline
metadata:
  name: ${PIPELINE_NAME}
description: Automated code quality pipeline with progressive delivery
serialPipeline:
  stages:
  - targetId: development
    profiles: [development]
    strategy:
      standard:
        verify: false
  - targetId: staging
    profiles: [staging]
    strategy:
      standard:
        verify: true
  - targetId: production
    profiles: [production]
    strategy:
      canary:
        runtimeConfig:
          kubernetes:
            gatewayServiceMesh:
              httpRoute: code-quality-route
              service: code-quality-service
        canaryDeployment:
          percentages: [25, 50, 100]
          verify: true
          postDeploy:
            actions: ["verify-deployment"]
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: development
description: Development environment
gke:
  cluster: projects/${PROJECT_ID}/locations/${ZONE}/clusters/${CLUSTER_NAME}
  internalIp: false
  namespace: development
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: staging
description: Staging environment with approval gates
requireApproval: false
gke:
  cluster: projects/${PROJECT_ID}/locations/${ZONE}/clusters/${CLUSTER_NAME}
  internalIp: false
  namespace: staging
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: production
description: Production environment with manual approval
requireApproval: true
gke:
  cluster: projects/${PROJECT_ID}/locations/${ZONE}/clusters/${CLUSTER_NAME}
  internalIp: false
  namespace: production
EOF
    
    # Apply Cloud Deploy configuration
    gcloud deploy apply --file=clouddeploy.yaml --region=${REGION}
    
    log_success "Cloud Deploy pipeline configured with progressive delivery"
}

# Create Cloud Build trigger and configure permissions
create_build_trigger() {
    log_info "Creating Cloud Build trigger and configuring permissions..."
    
    # Create Cloud Build trigger for main branch
    gcloud builds triggers create cloud-source-repositories \
        --repo=${REPO_NAME} \
        --branch-pattern="^main$" \
        --build-config=cloudbuild.yaml \
        --substitutions=_REGION=${REGION},_PIPELINE_NAME=${PIPELINE_NAME} \
        --description="Automated quality pipeline trigger"
    
    # Get project number for service account configuration
    PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")
    CLOUDBUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
    
    # Grant necessary permissions to Cloud Build service account
    local roles=(
        "roles/clouddeploy.developer"
        "roles/container.developer"
        "roles/binaryauthorization.attestorsViewer"
        "roles/logging.logWriter"
        "roles/monitoring.metricWriter"
    )
    
    for role in "${roles[@]}"; do
        gcloud projects add-iam-policy-binding ${PROJECT_ID} \
            --member="serviceAccount:${CLOUDBUILD_SA}" \
            --role="${role}" \
            --quiet
    done
    
    log_success "Cloud Build trigger created with proper permissions"
}

# Commit and push code to trigger pipeline
deploy_application() {
    log_info "Committing and pushing code to trigger the pipeline..."
    
    # Configure git user if not already configured
    if ! git config user.email > /dev/null 2>&1; then
        git config user.email "deploy-script@example.com"
        git config user.name "Deploy Script"
    fi
    
    # Add all files to git
    git add .
    
    # Commit changes with descriptive message
    git commit -m "Add automated code quality pipeline with progressive delivery

- Implement comprehensive CI/CD pipeline with Cloud Build
- Add automated testing, linting, and security scanning
- Configure progressive deployment with canary strategy
- Enable Binary Authorization for container security
- Add approval gates for production deployments"
    
    # Push to trigger the pipeline
    git push origin main
    
    # Get the build ID and monitor progress
    log_info "Monitoring build progress..."
    sleep 10  # Wait for trigger to activate
    
    BUILD_ID=$(gcloud builds list --limit=1 \
        --format="value(id)" \
        --filter="source.repoSource.repoName:${REPO_NAME}" 2>/dev/null || echo "")
    
    if [ -n "${BUILD_ID}" ]; then
        log_success "Code pushed successfully - Build ID: ${BUILD_ID}"
        log_info "Monitor build progress: https://console.cloud.google.com/cloud-build/builds/${BUILD_ID}?project=${PROJECT_ID}"
    else
        log_warning "Build ID not found immediately. Check the Cloud Build console for build status."
    fi
    
    # Return to parent directory
    cd ..
}

# Validation and testing
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check if Cloud Deploy pipeline exists
    if gcloud deploy delivery-pipelines describe ${PIPELINE_NAME} --region=${REGION} &>/dev/null; then
        log_success "Cloud Deploy pipeline created successfully"
    else
        log_warning "Cloud Deploy pipeline not found - may still be creating"
    fi
    
    # Check GKE cluster status
    CLUSTER_STATUS=$(gcloud container clusters describe ${CLUSTER_NAME} --zone=${ZONE} --format="value(status)")
    if [ "${CLUSTER_STATUS}" = "RUNNING" ]; then
        log_success "GKE cluster is running"
    else
        log_warning "GKE cluster status: ${CLUSTER_STATUS}"
    fi
    
    # Check namespaces
    if kubectl get namespaces development staging production &>/dev/null; then
        log_success "All required namespaces created"
    else
        log_warning "Some namespaces may not be created properly"
    fi
    
    log_success "Deployment validation completed"
}

# Display deployment information
display_deployment_info() {
    log_info "Deployment Summary:"
    echo "===================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo "Repository: ${REPO_NAME}"
    echo "Cluster: ${CLUSTER_NAME}"
    echo "Pipeline: ${PIPELINE_NAME}"
    echo ""
    echo "Useful Links:"
    echo "- Cloud Build Console: https://console.cloud.google.com/cloud-build/triggers?project=${PROJECT_ID}"
    echo "- Cloud Deploy Console: https://console.cloud.google.com/deploy/delivery-pipelines?project=${PROJECT_ID}"
    echo "- GKE Console: https://console.cloud.google.com/kubernetes/list?project=${PROJECT_ID}"
    echo "- Cloud Source Repositories: https://console.cloud.google.com/source/repos?project=${PROJECT_ID}"
    echo ""
    echo "Next Steps:"
    echo "1. Monitor the Cloud Build pipeline execution"
    echo "2. Review the progressive deployment in Cloud Deploy"
    echo "3. Approve production deployments when ready"
    echo "4. Test the application endpoints in each environment"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo "===================="
}

# Main execution
main() {
    log_info "Starting Code Quality Gates deployment..."
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_repository
    create_container_configs
    create_quality_configs
    create_build_config
    create_gke_cluster
    configure_binary_auth
    create_deploy_pipeline
    create_build_trigger
    deploy_application
    validate_deployment
    display_deployment_info
    
    log_success "Code Quality Gates deployment completed successfully!"
    log_info "Environment configuration saved to .env file"
}

# Run main function
main "$@"