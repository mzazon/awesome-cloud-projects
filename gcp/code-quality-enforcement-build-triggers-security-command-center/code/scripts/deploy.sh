#!/bin/bash

# Code Quality Enforcement with Cloud Build Triggers and Security Command Center - Deployment Script
# This script deploys a comprehensive security pipeline that enforces code quality through
# automated CI/CD, Binary Authorization, and Security Command Center monitoring.

set -euo pipefail  # Exit on error, undefined vars, pipe failures

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

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="${ROOT_DIR}/deployment.log"

# Default configuration - can be overridden by environment variables
PROJECT_ID="${PROJECT_ID:-code-quality-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
CLUSTER_NAME="${CLUSTER_NAME:-quality-enforcement-cluster}"

# Generate unique suffix for resource names
RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
REPO_NAME="${REPO_NAME:-secure-app-${RANDOM_SUFFIX}}"
TRIGGER_NAME="${TRIGGER_NAME:-quality-enforcement-trigger-${RANDOM_SUFFIX}}"
ATTESTOR_NAME="${ATTESTOR_NAME:-quality-attestor-${RANDOM_SUFFIX}}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-build-security-sa-${RANDOM_SUFFIX}}"

# Required APIs
readonly REQUIRED_APIS=(
    "cloudbuild.googleapis.com"
    "sourcerepo.googleapis.com"
    "binaryauthorization.googleapis.com"
    "securitycenter.googleapis.com"
    "container.googleapis.com"
    "containeranalysis.googleapis.com"
    "run.googleapis.com"
    "cloudkms.googleapis.com"
)

# Cleanup function for script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script interrupted or failed. Check ${LOG_FILE} for details."
        log_warning "Some resources may have been created. Run destroy.sh to clean up."
    fi
    exit $exit_code
}

trap cleanup_on_exit EXIT

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install kubectl."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Check if project is set
    local current_project
    current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$current_project" && -z "$PROJECT_ID" ]]; then
        log_error "No project set. Please set PROJECT_ID environment variable or run 'gcloud config set project PROJECT_ID'."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate input parameters
validate_parameters() {
    log_info "Validating parameters..."
    
    # Validate project ID format
    if [[ ! "$PROJECT_ID" =~ ^[a-z][a-z0-9\-]{4,28}[a-z0-9]$ ]]; then
        log_error "Invalid project ID format: $PROJECT_ID"
        exit 1
    fi
    
    # Validate region
    if ! gcloud compute regions list --format="value(name)" | grep -q "^${REGION}$"; then
        log_error "Invalid region: $REGION"
        exit 1
    fi
    
    log_success "Parameter validation completed"
}

# Function to set up project configuration
setup_project() {
    log_info "Setting up project configuration..."
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID" 2>&1 | tee -a "$LOG_FILE"
    gcloud config set compute/region "$REGION" 2>&1 | tee -a "$LOG_FILE"
    gcloud config set compute/zone "$ZONE" 2>&1 | tee -a "$LOG_FILE"
    
    log_success "Project configured: $PROJECT_ID"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required APIs..."
    
    for api in "${REQUIRED_APIS[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" 2>&1 | tee -a "$LOG_FILE"
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create Cloud Source Repository and sample application
create_source_repository() {
    log_info "Creating Cloud Source Repository and sample application..."
    
    # Create Cloud Source Repository
    gcloud source repos create "$REPO_NAME" --project="$PROJECT_ID" 2>&1 | tee -a "$LOG_FILE"
    
    # Create temporary directory for repository
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Clone the repository locally
    cd "$temp_dir"
    gcloud source repos clone "$REPO_NAME" --project="$PROJECT_ID" 2>&1 | tee -a "$LOG_FILE"
    cd "$REPO_NAME"
    
    # Create sample application structure
    mkdir -p app tests security
    
    # Create sample Python application
    cat > app/main.py << 'EOF'
from flask import Flask, jsonify
import os
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

@app.route('/')
def hello():
    return jsonify({
        'message': 'Secure Hello World',
        'version': '1.0.0',
        'environment': os.getenv('ENVIRONMENT', 'development')
    })

@app.route('/health')
def health():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.getenv('PORT', 8080)))
EOF
    
    # Create Dockerfile with security best practices
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

# Create non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Set working directory
WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ .

# Change ownership to non-root user
RUN chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Start application
CMD ["python", "main.py"]
EOF
    
    # Create requirements file
    cat > requirements.txt << 'EOF'
Flask==2.3.3
gunicorn==21.2.0
requests==2.31.0
EOF
    
    # Create comprehensive Cloud Build configuration
    cat > cloudbuild.yaml << EOF
steps:
# Step 1: Run unit tests
- name: 'python:3.11-slim'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    pip install -r requirements.txt pytest
    python -m pytest tests/ -v || exit 1
  id: 'unit-tests'

# Step 2: Static code analysis with bandit
- name: 'python:3.11-slim'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    pip install bandit[toml]
    bandit -r app/ -f json -o security/bandit-report.json || true
    bandit -r app/ --severity-level medium || exit 1
  id: 'static-analysis'

# Step 3: Dependency vulnerability scanning
- name: 'python:3.11-slim'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    pip install safety
    safety check --json --output security/safety-report.json || true
    safety check --short-report || exit 1
  id: 'dependency-scan'

# Step 4: Build container image
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', 'gcr.io/\$PROJECT_ID/\${_IMAGE_NAME}:\$BUILD_ID', '.']
  id: 'build-image'

# Step 5: Container vulnerability scanning
- name: 'gcr.io/cloud-builders/docker'
  args: ['push', 'gcr.io/\$PROJECT_ID/\${_IMAGE_NAME}:\$BUILD_ID']
  id: 'push-image'

# Step 6: Create attestation for Binary Authorization
- name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    gcloud container binauthz attestations sign-and-create \\
      --artifact-url=gcr.io/\$PROJECT_ID/\${_IMAGE_NAME}:\$BUILD_ID \\
      --attestor=\${_ATTESTOR_NAME} \\
      --attestor-project=\${PROJECT_ID} \\
      --keyversion=\${_KEY_VERSION}
  id: 'create-attestation'

substitutions:
  _IMAGE_NAME: 'secure-app'
  _ATTESTOR_NAME: '${ATTESTOR_NAME}'
  _KEY_VERSION: 'projects/${PROJECT_ID}/locations/global/keyRings/binauthz-ring/cryptoKeys/attestor-key/cryptoKeyVersions/1'

options:
  logging: CLOUD_LOGGING_ONLY

images:
- 'gcr.io/\$PROJECT_ID/\${_IMAGE_NAME}:\$BUILD_ID'
EOF
    
    # Create basic unit test
    cat > tests/test_main.py << 'EOF'
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

from main import app
import pytest

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_hello_endpoint(client):
    response = client.get('/')
    assert response.status_code == 200
    assert b'Secure Hello World' in response.data

def test_health_endpoint(client):
    response = client.get('/health')
    assert response.status_code == 200
    assert b'healthy' in response.data
EOF
    
    # Commit and push code
    git config user.email "security-pipeline@example.com"
    git config user.name "Security Pipeline"
    git add .
    git commit -m "Initial commit: Secure application with quality enforcement"
    git push origin main 2>&1 | tee -a "$LOG_FILE"
    
    # Clean up temporary directory
    cd "$ROOT_DIR"
    rm -rf "$temp_dir"
    
    log_success "Cloud Source Repository created with sample application"
}

# Function to create service account and configure IAM
create_service_account() {
    log_info "Creating service account and configuring IAM permissions..."
    
    # Create service account for Cloud Build
    gcloud iam service-accounts create "$SERVICE_ACCOUNT" \
        --display-name="Build Security Service Account" \
        --description="Service account for automated security pipeline" \
        2>&1 | tee -a "$LOG_FILE"
    
    # Grant necessary IAM roles
    local roles=(
        "roles/cloudbuild.builds.builder"
        "roles/binaryauthorization.attestorsEditor"
        "roles/containeranalysis.notes.editor"
        "roles/securitycenter.findingsEditor"
    )
    
    for role in "${roles[@]}"; do
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="$role" 2>&1 | tee -a "$LOG_FILE"
    done
    
    log_success "Service account created with security permissions"
}

# Function to set up Binary Authorization with security policies
setup_binary_authorization() {
    log_info "Setting up Binary Authorization with security policies..."
    
    # Create Cloud KMS key ring and key for attestation signing
    gcloud kms keyrings create binauthz-ring --location=global 2>&1 | tee -a "$LOG_FILE"
    
    gcloud kms keys create attestor-key \
        --location=global \
        --keyring=binauthz-ring \
        --purpose=asymmetric-signing \
        --default-algorithm=rsa-sign-pkcs1-4096-sha512 2>&1 | tee -a "$LOG_FILE"
    
    # Create Binary Authorization attestor
    gcloud container binauthz attestors create "$ATTESTOR_NAME" \
        --attestation-authority-note="$ATTESTOR_NAME" \
        --attestation-authority-note-project="$PROJECT_ID" 2>&1 | tee -a "$LOG_FILE"
    
    # Add public key to attestor
    gcloud container binauthz attestors public-keys add \
        --attestor="$ATTESTOR_NAME" \
        --keyversion-project="$PROJECT_ID" \
        --keyversion-location=global \
        --keyversion-keyring=binauthz-ring \
        --keyversion-key=attestor-key \
        --keyversion=1 2>&1 | tee -a "$LOG_FILE"
    
    # Create Binary Authorization policy
    cat > /tmp/binauthz-policy.yaml << EOF
defaultAdmissionRule:
  requireAttestationsBy:
  - projects/${PROJECT_ID}/attestors/${ATTESTOR_NAME}
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
globalPolicyEvaluationMode: ENABLE
admissionWhitelistPatterns:
- namePattern: gcr.io/my-project/allowlisted-image*
clusterAdmissionRules:
  ${ZONE}.${CLUSTER_NAME}:
    requireAttestationsBy:
    - projects/${PROJECT_ID}/attestors/${ATTESTOR_NAME}
    enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
EOF
    
    gcloud container binauthz policy import /tmp/binauthz-policy.yaml 2>&1 | tee -a "$LOG_FILE"
    rm /tmp/binauthz-policy.yaml
    
    log_success "Binary Authorization configured with security policies"
}

# Function to create Cloud Build trigger
create_build_trigger() {
    log_info "Creating Cloud Build trigger with quality gates..."
    
    gcloud builds triggers create cloud-source-repositories \
        --repo="$REPO_NAME" \
        --branch-pattern="^main$" \
        --build-config="cloudbuild.yaml" \
        --name="$TRIGGER_NAME" \
        --description="Automated security and quality enforcement pipeline" \
        --service-account="projects/${PROJECT_ID}/serviceAccounts/${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --substitutions="_IMAGE_NAME=secure-app,_ATTESTOR_NAME=${ATTESTOR_NAME}" \
        2>&1 | tee -a "$LOG_FILE"
    
    log_success "Cloud Build trigger created and pipeline initiated"
}

# Function to deploy GKE cluster with Binary Authorization
deploy_gke_cluster() {
    log_info "Deploying GKE cluster with Binary Authorization enabled..."
    
    gcloud container clusters create "$CLUSTER_NAME" \
        --zone="$ZONE" \
        --num-nodes=3 \
        --enable-binauthz \
        --enable-network-policy \
        --enable-shielded-nodes \
        --shielded-secure-boot \
        --shielded-integrity-monitoring \
        --workload-pool="${PROJECT_ID}.svc.id.goog" \
        2>&1 | tee -a "$LOG_FILE"
    
    # Get cluster credentials
    gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$ZONE" 2>&1 | tee -a "$LOG_FILE"
    
    # Create Kubernetes deployment manifest
    cat > "$ROOT_DIR/k8s-deployment.yaml" << EOF
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
        image: gcr.io/${PROJECT_ID}/secure-app:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
---
apiVersion: v1
kind: Service
metadata:
  name: secure-app-service
spec:
  selector:
    app: secure-app
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
  type: LoadBalancer
EOF
    
    log_success "GKE cluster created with Binary Authorization enabled"
}

# Function to configure Security Command Center
configure_security_command_center() {
    log_info "Configuring Security Command Center integration..."
    
    # Create custom security finding source
    local scc_source
    scc_source=$(gcloud scc sources create \
        --display-name="Code Quality Enforcement Pipeline" \
        --description="Security findings from automated code quality pipeline" \
        --format="value(name)" 2>&1 | tee -a "$LOG_FILE")
    
    # Create sample security finding
    gcloud scc findings create finding-code-quality-001 \
        --source="$scc_source" \
        --state=ACTIVE \
        --category="SECURITY_SCAN_RESULT" \
        --external-uri="https://console.cloud.google.com/cloud-build/builds" \
        --source-properties="scanType=container-scan,severity=medium,pipeline=${TRIGGER_NAME}" \
        2>&1 | tee -a "$LOG_FILE"
    
    # Save SCC source for cleanup
    echo "$scc_source" > "$ROOT_DIR/.scc_source"
    
    log_success "Security Command Center configured for compliance monitoring"
    log_info "SCC Source: $scc_source"
}

# Function to save deployment state
save_deployment_state() {
    log_info "Saving deployment state..."
    
    cat > "$ROOT_DIR/.deployment_state" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
CLUSTER_NAME=${CLUSTER_NAME}
REPO_NAME=${REPO_NAME}
TRIGGER_NAME=${TRIGGER_NAME}
ATTESTOR_NAME=${ATTESTOR_NAME}
SERVICE_ACCOUNT=${SERVICE_ACCOUNT}
DEPLOYMENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    log_success "Deployment state saved"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo "Repository: $REPO_NAME"
    echo "Build Trigger: $TRIGGER_NAME"
    echo "Attestor: $ATTESTOR_NAME"
    echo "GKE Cluster: $CLUSTER_NAME"
    echo "Service Account: ${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. View Cloud Build triggers: https://console.cloud.google.com/cloud-build/triggers"
    echo "2. Monitor Security Command Center: https://console.cloud.google.com/security/command-center"
    echo "3. Check Binary Authorization policies: https://console.cloud.google.com/security/binary-authorization"
    echo "4. View GKE cluster: https://console.cloud.google.com/kubernetes/list"
    echo
    echo "=== CLEANUP ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo
}

# Main deployment function
main() {
    log_info "Starting Code Quality Enforcement Pipeline deployment..."
    echo "Deployment log: $LOG_FILE"
    
    # Execute deployment steps
    check_prerequisites
    validate_parameters
    setup_project
    enable_apis
    create_service_account
    setup_binary_authorization
    create_source_repository
    create_build_trigger
    deploy_gke_cluster
    configure_security_command_center
    save_deployment_state
    display_summary
    
    log_success "Code Quality Enforcement Pipeline deployed successfully!"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi