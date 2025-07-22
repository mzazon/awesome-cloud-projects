#!/bin/bash

# Deploy script for Secure Remote Development Environments with Cloud Workstations and Cloud Build
# This script automates the deployment of a complete secure development environment

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling function
handle_error() {
    log_error "Script failed at line $1. Exit code: $2"
    log_error "Check the logs above for detailed error information."
    exit $2
}

# Set trap for error handling
trap 'handle_error $LINENO $?' ERR

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"

# Redirect all output to both console and log file
exec > >(tee -a "${LOG_FILE}")
exec 2>&1

log "Starting deployment of Secure Remote Development Environment"
log "Log file: ${LOG_FILE}"

# Prerequisites validation
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random strings"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Environment configuration
setup_environment() {
    log "Setting up environment variables..."
    
    # Set project ID (prompt if not configured)
    export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "${PROJECT_ID}" ]]; then
        read -p "Enter your Google Cloud Project ID: " PROJECT_ID
        gcloud config set project "${PROJECT_ID}"
    fi
    
    # Set default region and zone
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export WORKSTATION_CLUSTER="dev-cluster-${RANDOM_SUFFIX}"
    export WORKSTATION_CONFIG="secure-dev-config-${RANDOM_SUFFIX}"
    export BUILD_POOL="private-build-pool-${RANDOM_SUFFIX}"
    export REPO_NAME="secure-app-${RANDOM_SUFFIX}"
    
    # Set default configurations
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Save environment variables for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
WORKSTATION_CLUSTER=${WORKSTATION_CLUSTER}
WORKSTATION_CONFIG=${WORKSTATION_CONFIG}
BUILD_POOL=${BUILD_POOL}
REPO_NAME=${REPO_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment configured for project: ${PROJECT_ID}"
    log_success "Resources will be created with suffix: ${RANDOM_SUFFIX}"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "workstations.googleapis.com"
        "cloudbuild.googleapis.com"
        "sourcerepo.googleapis.com"
        "artifactregistry.googleapis.com"
        "compute.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        gcloud services enable "${api}" --quiet
    done
    
    log_success "All required APIs enabled"
}

# Create VPC network
create_vpc_network() {
    log "Creating VPC network for secure development environment..."
    
    # Create custom VPC network
    if ! gcloud compute networks describe dev-vpc &>/dev/null; then
        gcloud compute networks create dev-vpc \
            --subnet-mode regional \
            --description "Secure development environment VPC" \
            --quiet
        log_success "VPC network 'dev-vpc' created"
    else
        log_warning "VPC network 'dev-vpc' already exists"
    fi
    
    # Create subnet
    if ! gcloud compute networks subnets describe dev-subnet --region="${REGION}" &>/dev/null; then
        gcloud compute networks subnets create dev-subnet \
            --network dev-vpc \
            --range 10.0.0.0/24 \
            --region "${REGION}" \
            --enable-private-ip-google-access \
            --description "Subnet for Cloud Workstations and build pools" \
            --quiet
        log_success "Subnet 'dev-subnet' created in region ${REGION}"
    else
        log_warning "Subnet 'dev-subnet' already exists"
    fi
}

# Create Cloud Workstations cluster
create_workstation_cluster() {
    log "Creating Cloud Workstations cluster..."
    
    # Check if cluster already exists
    if gcloud workstations clusters describe "${WORKSTATION_CLUSTER}" --region="${REGION}" &>/dev/null; then
        log_warning "Workstation cluster '${WORKSTATION_CLUSTER}' already exists"
        return
    fi
    
    # Create workstations cluster
    gcloud workstations clusters create "${WORKSTATION_CLUSTER}" \
        --region "${REGION}" \
        --network "projects/${PROJECT_ID}/global/networks/dev-vpc" \
        --subnetwork "projects/${PROJECT_ID}/regions/${REGION}/subnetworks/dev-subnet" \
        --labels "environment=development,security=high" \
        --async \
        --quiet
    
    log "Waiting for workstation cluster creation to complete..."
    local max_attempts=60
    local attempt=0
    
    while [[ ${attempt} -lt ${max_attempts} ]]; do
        local state=$(gcloud workstations clusters describe "${WORKSTATION_CLUSTER}" \
            --region "${REGION}" \
            --format "value(state)" 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "${state}" == "STATE_RUNNING" ]]; then
            log_success "Cloud Workstations cluster '${WORKSTATION_CLUSTER}' is running"
            return
        elif [[ "${state}" == "STATE_CREATING" ]]; then
            log "Cluster creation in progress... (attempt ${attempt}/${max_attempts})"
            sleep 30
            ((attempt++))
        else
            log_error "Unexpected cluster state: ${state}"
            exit 1
        fi
    done
    
    log_error "Timeout waiting for cluster creation"
    exit 1
}

# Configure workstation template
configure_workstation() {
    log "Configuring secure workstation template..."
    
    # Check if configuration already exists
    if gcloud workstations configs describe "${WORKSTATION_CONFIG}" \
        --cluster "${WORKSTATION_CLUSTER}" \
        --region "${REGION}" &>/dev/null; then
        log_warning "Workstation configuration '${WORKSTATION_CONFIG}' already exists"
        return
    fi
    
    # Create workstation configuration
    gcloud workstations configs create "${WORKSTATION_CONFIG}" \
        --cluster "${WORKSTATION_CLUSTER}" \
        --region "${REGION}" \
        --machine-type "e2-standard-4" \
        --pd-disk-size 100 \
        --pd-disk-type pd-standard \
        --idle-timeout 7200s \
        --running-timeout 43200s \
        --disable-public-ip-addresses \
        --enable-audit-agent \
        --labels "security=high,team=development" \
        --quiet
    
    # Configure container image
    gcloud workstations configs update "${WORKSTATION_CONFIG}" \
        --cluster "${WORKSTATION_CLUSTER}" \
        --region "${REGION}" \
        --container-image "us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest" \
        --quiet
    
    log_success "Secure workstation configuration '${WORKSTATION_CONFIG}' created"
}

# Set up Cloud Source Repository
setup_source_repository() {
    log "Setting up Cloud Source Repository..."
    
    # Check if repository already exists
    if gcloud source repos describe "${REPO_NAME}" &>/dev/null; then
        log_warning "Source repository '${REPO_NAME}' already exists"
        return
    fi
    
    # Create source repository
    gcloud source repos create "${REPO_NAME}" \
        --project "${PROJECT_ID}" \
        --quiet
    
    # Get repository clone URL
    local repo_url="https://source.developers.google.com/p/${PROJECT_ID}/r/${REPO_NAME}"
    
    # Create temporary directory for repository initialization
    local temp_dir=$(mktemp -d)
    cd "${temp_dir}"
    
    # Initialize repository with sample application
    git init
    git config user.email "developer@example.com"
    git config user.name "Secure Developer"
    
    # Create sample application files
    cat > app.py << 'EOF'
from flask import Flask

app = Flask(__name__)

@app.route('/')
def hello():
    return "Hello from Secure Development Environment!"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF
    
    cat > requirements.txt << 'EOF'
Flask==2.3.3
gunicorn==21.2.0
EOF
    
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app"]
EOF
    
    cat > cloudbuild.yaml << EOF
steps:
# Build container image
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}-images/app:\$BUILD_ID', '.']

# Push image to Artifact Registry
- name: 'gcr.io/cloud-builders/docker'
  args: ['push', '${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}-images/app:\$BUILD_ID']

# Run security scan
- name: 'gcr.io/cloud-builders/gcloud'
  args: ['artifacts', 'docker', 'images', 'scan', '${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}-images/app:\$BUILD_ID', '--location=${REGION}']

images:
- '${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}-images/app:\$BUILD_ID'

options:
  pool:
    name: 'projects/${PROJECT_ID}/locations/${REGION}/workerPools/${BUILD_POOL}'
  logging: CLOUD_LOGGING_ONLY
EOF
    
    # Commit and push initial code
    git add .
    git commit -m "Initial secure application setup"
    git remote add origin "${repo_url}"
    
    # Configure Git credential helper for Google Cloud
    git config credential.helper gcloud.sh
    
    # Push to repository
    git push origin main
    
    # Clean up temporary directory
    cd "${SCRIPT_DIR}"
    rm -rf "${temp_dir}"
    
    log_success "Cloud Source Repository '${REPO_NAME}' created with sample application"
}

# Create Artifact Registry
create_artifact_registry() {
    log "Creating Artifact Registry for container images..."
    
    # Check if repository already exists
    if gcloud artifacts repositories describe "${REPO_NAME}-images" \
        --location="${REGION}" &>/dev/null; then
        log_warning "Artifact Registry '${REPO_NAME}-images' already exists"
        return
    fi
    
    # Create Artifact Registry repository
    gcloud artifacts repositories create "${REPO_NAME}-images" \
        --repository-format docker \
        --location "${REGION}" \
        --description "Secure container registry for development applications" \
        --quiet
    
    # Configure Docker authentication
    gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
    
    log_success "Artifact Registry '${REPO_NAME}-images' created"
}

# Set up private Cloud Build pool
setup_build_pool() {
    log "Setting up private Cloud Build pool..."
    
    # Check if build pool already exists
    if gcloud builds worker-pools describe "${BUILD_POOL}" \
        --region="${REGION}" &>/dev/null; then
        log_warning "Build pool '${BUILD_POOL}' already exists"
        return
    fi
    
    # Create private build pool configuration
    cat > "${SCRIPT_DIR}/private-pool.yaml" << EOF
name: projects/${PROJECT_ID}/locations/${REGION}/workerPools/${BUILD_POOL}
displayName: "Secure Development Build Pool"
machineType: e2-medium
diskSizeGb: 100
workerConfig:
  machineType: e2-medium
  diskSizeGb: 100
networkConfig:
  peeredNetwork: projects/${PROJECT_ID}/global/networks/dev-vpc
  peeredNetworkIpRange: 10.1.0.0/24
EOF
    
    # Create the private build pool
    gcloud builds worker-pools create "${BUILD_POOL}" \
        --region "${REGION}" \
        --config-from-file "${SCRIPT_DIR}/private-pool.yaml" \
        --quiet
    
    log_success "Private Cloud Build pool '${BUILD_POOL}' created"
}

# Configure Cloud Build trigger
configure_build_trigger() {
    log "Configuring Cloud Build trigger..."
    
    local trigger_name="secure-dev-trigger-${RANDOM_SUFFIX}"
    
    # Check if trigger already exists
    if gcloud builds triggers describe "${trigger_name}" --region="${REGION}" &>/dev/null; then
        log_warning "Build trigger '${trigger_name}' already exists"
        return
    fi
    
    # Create Cloud Build trigger
    gcloud builds triggers create cloud-source-repositories \
        --repo "${REPO_NAME}" \
        --branch-pattern "main" \
        --build-config cloudbuild.yaml \
        --name "${trigger_name}" \
        --description "Automated secure build trigger" \
        --worker-pool "projects/${PROJECT_ID}/locations/${REGION}/workerPools/${BUILD_POOL}" \
        --quiet
    
    log_success "Cloud Build trigger '${trigger_name}' configured"
}

# Create developer workstation
create_workstation() {
    log "Creating developer workstation instance..."
    
    local workstation_name="dev-workstation-01"
    
    # Check if workstation already exists
    if gcloud workstations describe "${workstation_name}" \
        --cluster "${WORKSTATION_CLUSTER}" \
        --config "${WORKSTATION_CONFIG}" \
        --region "${REGION}" &>/dev/null; then
        log_warning "Workstation '${workstation_name}' already exists"
        return
    fi
    
    # Create workstation instance
    gcloud workstations create "${workstation_name}" \
        --cluster "${WORKSTATION_CLUSTER}" \
        --config "${WORKSTATION_CONFIG}" \
        --region "${REGION}" \
        --labels "developer=team-lead,project=secure-development" \
        --quiet
    
    # Get workstation access URL
    local workstation_host=$(gcloud workstations describe "${workstation_name}" \
        --cluster "${WORKSTATION_CLUSTER}" \
        --config "${WORKSTATION_CONFIG}" \
        --region "${REGION}" \
        --format "value(host)" 2>/dev/null || echo "")
    
    if [[ -n "${workstation_host}" ]]; then
        log_success "Developer workstation '${workstation_name}' created"
        log_success "Access URL: https://${workstation_host}"
    else
        log_warning "Workstation created but access URL not available yet"
    fi
}

# Configure IAM security policies
configure_iam() {
    log "Configuring IAM security policies..."
    
    local service_account="workstation-dev-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "${service_account}" &>/dev/null; then
        log_warning "Service account 'workstation-dev-sa' already exists"
    else
        # Create service account
        gcloud iam service-accounts create workstation-dev-sa \
            --display-name "Workstation Development Service Account" \
            --description "Service account for secure development workstations" \
            --quiet
        log_success "Service account 'workstation-dev-sa' created"
    fi
    
    # Grant necessary permissions
    local roles=(
        "roles/source.developer"
        "roles/artifactregistry.reader"
        "roles/cloudbuild.builds.viewer"
    )
    
    for role in "${roles[@]}"; do
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member "serviceAccount:${service_account}" \
            --role "${role}" \
            --quiet
    done
    
    log_success "IAM security policies configured"
    log "To grant workstation access to developers, run:"
    log "gcloud projects add-iam-policy-binding ${PROJECT_ID} \\"
    log "    --member 'user:developer@yourdomain.com' \\"
    log "    --role 'roles/workstations.user'"
}

# Main deployment function
main() {
    log "=== Secure Remote Development Environment Deployment ==="
    
    check_prerequisites
    setup_environment
    enable_apis
    create_vpc_network
    create_workstation_cluster
    configure_workstation
    setup_source_repository
    create_artifact_registry
    setup_build_pool
    configure_build_trigger
    create_workstation
    configure_iam
    
    log_success "=== Deployment completed successfully! ==="
    log ""
    log "🔐 Your secure development environment is ready!"
    log ""
    log "📋 Summary of created resources:"
    log "   • Project: ${PROJECT_ID}"
    log "   • Region: ${REGION}"
    log "   • VPC Network: dev-vpc"
    log "   • Workstation Cluster: ${WORKSTATION_CLUSTER}"
    log "   • Workstation Config: ${WORKSTATION_CONFIG}"
    log "   • Source Repository: ${REPO_NAME}"
    log "   • Artifact Registry: ${REPO_NAME}-images"
    log "   • Build Pool: ${BUILD_POOL}"
    log ""
    log "🚀 Next steps:"
    log "   1. Access your workstation through the Google Cloud Console"
    log "   2. Clone the source repository in your workstation"
    log "   3. Make code changes and push to trigger automated builds"
    log "   4. Grant workstation access to your team members"
    log ""
    log "📁 Environment variables saved to: ${SCRIPT_DIR}/.env"
    log "📝 Detailed logs available at: ${LOG_FILE}"
}

# Run main function
main "$@"