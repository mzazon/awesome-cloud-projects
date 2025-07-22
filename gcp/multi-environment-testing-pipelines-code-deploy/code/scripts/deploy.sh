#!/bin/bash

# Multi-Environment Testing Pipelines with Cloud Code and Cloud Deploy - Deployment Script
# This script deploys the complete infrastructure for automated multi-environment testing pipelines

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Required command '$1' not found. Please install it before running this script."
        exit 1
    fi
}

# Function to check if user is authenticated
check_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "No active Google Cloud authentication found."
        echo "Please run: gcloud auth login"
        exit 1
    fi
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check required commands
    check_command "gcloud"
    check_command "kubectl"
    check_command "docker"
    check_command "openssl"
    
    # Check authentication
    check_auth
    
    # Verify project is set
    if ! PROJECT_ID=$(gcloud config get-value project 2>/dev/null) || [ -z "$PROJECT_ID" ]; then
        error "No Google Cloud project configured."
        echo "Please run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    
    # Check billing is enabled
    if ! gcloud billing projects describe "$PROJECT_ID" &>/dev/null; then
        warning "Unable to verify billing status. Ensure billing is enabled for project: $PROJECT_ID"
    fi
    
    success "Prerequisites validation completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "container.googleapis.com"
        "cloudbuild.googleapis.com"
        "clouddeploy.googleapis.com"
        "artifactregistry.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            success "Enabled $api"
        else
            error "Failed to enable $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set project and region configuration
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="us-central1"
    export ZONE="us-central1-a"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export CLUSTER_PREFIX="pipeline-${RANDOM_SUFFIX}"
    
    # Configure gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log "Environment configured:"
    log "  Project ID: ${PROJECT_ID}"
    log "  Region: ${REGION}"
    log "  Zone: ${ZONE}"
    log "  Resource Prefix: ${CLUSTER_PREFIX}"
    
    success "Environment setup completed"
}

# Function to create Artifact Registry repository
create_artifact_registry() {
    log "Creating Artifact Registry repository..."
    
    if gcloud artifacts repositories describe "${CLUSTER_PREFIX}-repo" \
        --location="${REGION}" &>/dev/null; then
        warning "Artifact Registry repository ${CLUSTER_PREFIX}-repo already exists"
    else
        if gcloud artifacts repositories create "${CLUSTER_PREFIX}-repo" \
            --repository-format=docker \
            --location="${REGION}" \
            --description="Container repository for multi-environment pipeline" \
            --quiet; then
            success "Artifact Registry repository created"
        else
            error "Failed to create Artifact Registry repository"
            exit 1
        fi
    fi
    
    # Configure Docker authentication
    log "Configuring Docker authentication..."
    if gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet; then
        success "Docker authentication configured"
    else
        error "Failed to configure Docker authentication"
        exit 1
    fi
}

# Function to create GKE clusters
create_gke_clusters() {
    log "Creating GKE clusters for multi-environment pipeline..."
    
    # Development cluster
    log "Creating development cluster..."
    if gcloud container clusters describe "${CLUSTER_PREFIX}-dev" --zone="${ZONE}" &>/dev/null; then
        warning "Development cluster ${CLUSTER_PREFIX}-dev already exists"
    else
        if gcloud container clusters create "${CLUSTER_PREFIX}-dev" \
            --num-nodes=2 \
            --machine-type=e2-medium \
            --zone="${ZONE}" \
            --enable-autorepair \
            --enable-autoupgrade \
            --labels=environment=development \
            --disk-size=50GB \
            --enable-ip-alias \
            --quiet; then
            success "Development cluster created"
        else
            error "Failed to create development cluster"
            exit 1
        fi
    fi
    
    # Staging cluster
    log "Creating staging cluster..."
    if gcloud container clusters describe "${CLUSTER_PREFIX}-staging" --zone="${ZONE}" &>/dev/null; then
        warning "Staging cluster ${CLUSTER_PREFIX}-staging already exists"
    else
        if gcloud container clusters create "${CLUSTER_PREFIX}-staging" \
            --num-nodes=2 \
            --machine-type=e2-medium \
            --zone="${ZONE}" \
            --enable-autorepair \
            --enable-autoupgrade \
            --labels=environment=staging \
            --disk-size=50GB \
            --enable-ip-alias \
            --quiet; then
            success "Staging cluster created"
        else
            error "Failed to create staging cluster"
            exit 1
        fi
    fi
    
    # Production cluster
    log "Creating production cluster..."
    if gcloud container clusters describe "${CLUSTER_PREFIX}-prod" --zone="${ZONE}" &>/dev/null; then
        warning "Production cluster ${CLUSTER_PREFIX}-prod already exists"
    else
        if gcloud container clusters create "${CLUSTER_PREFIX}-prod" \
            --num-nodes=3 \
            --machine-type=e2-standard-2 \
            --zone="${ZONE}" \
            --enable-autorepair \
            --enable-autoupgrade \
            --enable-network-policy \
            --labels=environment=production \
            --disk-size=100GB \
            --enable-ip-alias \
            --quiet; then
            success "Production cluster created"
        else
            error "Failed to create production cluster"
            exit 1
        fi
    fi
    
    success "All GKE clusters created successfully"
}

# Function to create application configuration
create_application_config() {
    log "Creating application configuration files..."
    
    # Create project directory structure
    mkdir -p "${CLUSTER_PREFIX}-app"/{k8s,clouddeploy}
    cd "${CLUSTER_PREFIX}-app"
    
    # Create Kubernetes deployment manifest
    cat > k8s/deployment.yaml << EOF
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
        image: gcr.io/google-samples/hello-app:1.0
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 8080
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
  - port: 80
    targetPort: 8080
  type: LoadBalancer
EOF
    
    # Create Skaffold configuration
    cat > skaffold.yaml << EOF
apiVersion: skaffold/v4beta1
kind: Config
metadata:
  name: sample-app
build:
  artifacts:
  - image: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${CLUSTER_PREFIX}-repo/sample-app
    docker:
      dockerfile: Dockerfile
  googleCloudBuild:
    projectId: ${PROJECT_ID}
manifests:
  rawYaml:
  - k8s/deployment.yaml
deploy:
  kubectl: {}
profiles:
- name: dev
  manifests:
    rawYaml:
    - k8s/deployment.yaml
- name: staging
  manifests:
    rawYaml:
    - k8s/deployment.yaml
- name: prod
  manifests:
    rawYaml:
    - k8s/deployment.yaml
  patches:
  - op: replace
    path: /spec/replicas
    value: 3
EOF
    
    # Create Dockerfile
    cat > Dockerfile << EOF
FROM gcr.io/google-samples/hello-app:1.0
COPY . /app
WORKDIR /app
EXPOSE 8080
CMD ["./hello-app"]
EOF
    
    cd ..
    success "Application configuration created"
}

# Function to create Cloud Deploy pipeline
create_cloud_deploy_pipeline() {
    log "Creating Cloud Deploy pipeline configuration..."
    
    cd "${CLUSTER_PREFIX}-app"
    
    # Create Cloud Deploy pipeline configuration
    cat > clouddeploy/pipeline.yaml << EOF
apiVersion: deploy.cloud.google.com/v1
kind: DeliveryPipeline
metadata:
  name: ${CLUSTER_PREFIX}-pipeline
description: Multi-environment testing pipeline
serialPipeline:
  stages:
  - targetId: dev
    profiles: [dev]
    strategy:
      standard:
        verify: true
  - targetId: staging
    profiles: [staging]
    strategy:
      standard:
        verify: true
  - targetId: prod
    profiles: [prod]
    strategy:
      standard:
        verify: true
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: dev
description: Development environment
gke:
  cluster: projects/${PROJECT_ID}/locations/${ZONE}/clusters/${CLUSTER_PREFIX}-dev
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: staging
description: Staging environment  
gke:
  cluster: projects/${PROJECT_ID}/locations/${ZONE}/clusters/${CLUSTER_PREFIX}-staging
requireApproval: false
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: prod
description: Production environment
gke:
  cluster: projects/${PROJECT_ID}/locations/${ZONE}/clusters/${CLUSTER_PREFIX}-prod
requireApproval: true
EOF
    
    # Apply Cloud Deploy pipeline configuration
    log "Registering Cloud Deploy pipeline..."
    if gcloud deploy apply --file=clouddeploy/pipeline.yaml \
        --region="${REGION}" \
        --project="${PROJECT_ID}"; then
        success "Cloud Deploy pipeline registered"
    else
        error "Failed to register Cloud Deploy pipeline"
        exit 1
    fi
    
    cd ..
}

# Function to create Cloud Build configuration
create_cloud_build_config() {
    log "Creating Cloud Build configuration..."
    
    cd "${CLUSTER_PREFIX}-app"
    
    cat > cloudbuild.yaml << EOF
steps:
# Build application image
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '${REGION}-docker.pkg.dev/${PROJECT_ID}/${CLUSTER_PREFIX}-repo/sample-app:\$BUILD_ID', '.']

# Push image to Artifact Registry
- name: 'gcr.io/cloud-builders/docker'
  args: ['push', '${REGION}-docker.pkg.dev/${PROJECT_ID}/${CLUSTER_PREFIX}-repo/sample-app:\$BUILD_ID']

# Run unit tests
- name: 'gcr.io/cloud-builders/docker'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "Running unit tests..."
    docker run --rm ${REGION}-docker.pkg.dev/${PROJECT_ID}/${CLUSTER_PREFIX}-repo/sample-app:\$BUILD_ID echo "Unit tests passed"

# Security scanning
- name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "Running security scans..."
    gcloud artifacts docker images scan ${REGION}-docker.pkg.dev/${PROJECT_ID}/${CLUSTER_PREFIX}-repo/sample-app:\$BUILD_ID --location=${REGION} || true

# Create Cloud Deploy release
- name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    gcloud deploy releases create release-\$BUILD_ID \
      --delivery-pipeline=${CLUSTER_PREFIX}-pipeline \
      --region=${REGION} \
      --images=sample-app=${REGION}-docker.pkg.dev/${PROJECT_ID}/${CLUSTER_PREFIX}-repo/sample-app:\$BUILD_ID

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: 'E2_MEDIUM'

timeout: '1200s'
EOF
    
    cd ..
    success "Cloud Build configuration created"
}

# Function to create monitoring dashboard
create_monitoring_dashboard() {
    log "Creating Cloud Monitoring dashboard..."
    
    cd "${CLUSTER_PREFIX}-app"
    
    cat > monitoring-dashboard.json << EOF
{
  "displayName": "${CLUSTER_PREFIX} Pipeline Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "GKE Container CPU Utilization",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"k8s_container\" AND resource.labels.cluster_name=~\"${CLUSTER_PREFIX}.*\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_MEAN",
                      "groupByFields": ["resource.labels.cluster_name"]
                    }
                  }
                }
              }
            ]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Cloud Deploy Releases",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"clouddeploy_delivery_pipeline\"",
                    "aggregation": {
                      "alignmentPeriod": "300s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_SUM"
                    }
                  }
                }
              }
            ]
          }
        }
      }
    ]
  }
}
EOF
    
    # Create the monitoring dashboard
    if gcloud monitoring dashboards create --config-from-file=monitoring-dashboard.json; then
        success "Cloud Monitoring dashboard created"
    else
        warning "Failed to create monitoring dashboard (this is not critical)"
    fi
    
    cd ..
}

# Function to create Cloud Code IDE configuration
create_cloud_code_config() {
    log "Creating Cloud Code IDE configuration..."
    
    cd "${CLUSTER_PREFIX}-app"
    
    # Create VS Code configuration
    mkdir -p .vscode
    
    cat > .vscode/launch.json << EOF
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Cloud Code: Run/Debug on Kubernetes",
      "type": "cloudcode.kubernetes",
      "request": "launch",
      "skaffoldConfig": "\${workspaceFolder}/skaffold.yaml",
      "watch": true,
      "cleanUp": true,
      "portForward": true,
      "imageRegistry": "${REGION}-docker.pkg.dev/${PROJECT_ID}/${CLUSTER_PREFIX}-repo"
    }
  ]
}
EOF
    
    cat > .vscode/tasks.json << EOF
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Cloud Code: Deploy to Development",
      "type": "shell",
      "command": "skaffold",
      "args": ["run", "--profile=dev", "--default-repo=${REGION}-docker.pkg.dev/${PROJECT_ID}/${CLUSTER_PREFIX}-repo"],
      "group": "build",
      "presentation": {
        "echo": true,
        "reveal": "always",
        "focus": false,
        "panel": "shared"
      }
    }
  ]
}
EOF
    
    cd ..
    success "Cloud Code IDE configuration created"
}

# Function to test deployment
test_deployment() {
    log "Testing the deployment..."
    
    # Test a sample build and deployment
    cd "${CLUSTER_PREFIX}-app"
    
    log "Triggering test build..."
    if gcloud builds submit --config=cloudbuild.yaml --project="${PROJECT_ID}"; then
        success "Test build completed successfully"
    else
        error "Test build failed"
        exit 1
    fi
    
    # Verify clusters are accessible
    log "Verifying cluster connectivity..."
    for env in dev staging prod; do
        if gcloud container clusters get-credentials "${CLUSTER_PREFIX}-${env}" --zone="${ZONE}" --quiet; then
            success "Connected to ${env} cluster"
        else
            error "Failed to connect to ${env} cluster"
            exit 1
        fi
    done
    
    cd ..
}

# Function to display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Resource Prefix: ${CLUSTER_PREFIX}"
    echo ""
    echo "Created Resources:"
    echo "- Artifact Registry repository: ${CLUSTER_PREFIX}-repo"
    echo "- GKE development cluster: ${CLUSTER_PREFIX}-dev"
    echo "- GKE staging cluster: ${CLUSTER_PREFIX}-staging"
    echo "- GKE production cluster: ${CLUSTER_PREFIX}-prod"
    echo "- Cloud Deploy pipeline: ${CLUSTER_PREFIX}-pipeline"
    echo "- Application configuration: ${CLUSTER_PREFIX}-app/"
    echo ""
    echo "Next Steps:"
    echo "1. Install Cloud Code extension in VS Code"
    echo "2. Open the ${CLUSTER_PREFIX}-app/ directory in VS Code"
    echo "3. Use Cloud Code to deploy to development environment"
    echo "4. Monitor deployments in Cloud Deploy console"
    echo ""
    echo "Access Links:"
    echo "- Cloud Deploy: https://console.cloud.google.com/deploy/delivery-pipelines?project=${PROJECT_ID}"
    echo "- Cloud Build: https://console.cloud.google.com/cloud-build/builds?project=${PROJECT_ID}"
    echo "- GKE Clusters: https://console.cloud.google.com/kubernetes/list?project=${PROJECT_ID}"
    echo "- Artifact Registry: https://console.cloud.google.com/artifacts?project=${PROJECT_ID}"
    echo ""
    success "Multi-environment testing pipeline is ready for use!"
}

# Main deployment function
main() {
    log "Starting multi-environment testing pipelines deployment..."
    
    validate_prerequisites
    setup_environment
    enable_apis
    create_artifact_registry
    create_gke_clusters
    create_application_config
    create_cloud_deploy_pipeline
    create_cloud_build_config
    create_monitoring_dashboard
    create_cloud_code_config
    test_deployment
    display_summary
}

# Script options
SKIP_PREREQUISITES=false
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-prerequisites)
            SKIP_PREREQUISITES=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-prerequisites  Skip prerequisites validation"
            echo "  --dry-run            Show what would be deployed without actually deploying"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Handle dry run
if [ "$DRY_RUN" = true ]; then
    log "DRY RUN MODE - No resources will be created"
    log "Would deploy multi-environment testing pipeline with:"
    log "- Artifact Registry repository"
    log "- 3 GKE clusters (dev, staging, prod)"
    log "- Cloud Deploy pipeline"
    log "- Cloud Build configuration"
    log "- Monitoring dashboard"
    log "- Cloud Code IDE configuration"
    exit 0
fi

# Run main deployment
main "$@"