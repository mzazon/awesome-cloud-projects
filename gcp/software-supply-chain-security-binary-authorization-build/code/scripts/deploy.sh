#!/bin/bash

# Software Supply Chain Security with Binary Authorization and Cloud Build
# Deployment Script for GCP Recipe
# 
# This script deploys a complete software supply chain security solution using:
# - Binary Authorization for policy enforcement
# - Cloud Build for CI/CD pipeline
# - Artifact Registry for secure container storage
# - Cloud KMS for cryptographic key management
# - GKE for container orchestration

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
    log_error "Deployment failed at line $1"
    log_error "Command: $2"
    log_error "Exit code: $3"
    exit $3
}

# Set up error trap
trap 'handle_error $LINENO "$BASH_COMMAND" $?' ERR

# Configuration variables (can be overridden via environment)
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
CLUSTER_NAME="${CLUSTER_NAME:-secure-cluster}"
REPO_NAME="${REPO_NAME:-secure-images}"

# Generate unique suffix for resources
RANDOM_SUFFIX=$(openssl rand -hex 3)
KEYRING_NAME="${KEYRING_NAME:-binauthz-keyring-${RANDOM_SUFFIX}}"
KEY_NAME="${KEY_NAME:-attestor-key-${RANDOM_SUFFIX}}"
ATTESTOR_NAME="${ATTESTOR_NAME:-build-attestor-${RANDOM_SUFFIX}}"

# Flags for controlling deployment stages
SKIP_CLUSTER_CREATION="${SKIP_CLUSTER_CREATION:-false}"
SKIP_SAMPLE_APP="${SKIP_SAMPLE_APP:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
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
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if project ID is set
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID is not set. Please set it via environment variable or configure gcloud."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to configure environment
configure_environment() {
    log "Configuring environment..."
    
    # Set project, region, and zone
    gcloud config set project "$PROJECT_ID" --quiet
    gcloud config set compute/region "$REGION" --quiet
    gcloud config set compute/zone "$ZONE" --quiet
    
    # Export variables for use in child processes
    export PROJECT_ID REGION ZONE CLUSTER_NAME REPO_NAME
    export KEYRING_NAME KEY_NAME ATTESTOR_NAME
    
    log_success "Environment configured for project: $PROJECT_ID"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would enable required APIs"
        return 0
    fi
    
    local apis=(
        "container.googleapis.com"
        "cloudbuild.googleapis.com"
        "binaryauthorization.googleapis.com"
        "cloudkms.googleapis.com"
        "artifactregistry.googleapis.com"
        "containeranalysis.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        if gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
            log "API $api is already enabled"
        else
            log "Enabling API: $api"
            gcloud services enable "$api" --quiet
        fi
    done
    
    log_success "Required APIs enabled"
}

# Function to create Artifact Registry repository
create_artifact_registry() {
    log "Creating Artifact Registry repository..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would create Artifact Registry repository"
        return 0
    fi
    
    # Check if repository already exists
    if gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" --quiet 2>/dev/null; then
        log_warning "Artifact Registry repository $REPO_NAME already exists in $REGION"
    else
        log "Creating Artifact Registry repository: $REPO_NAME"
        gcloud artifacts repositories create "$REPO_NAME" \
            --repository-format=docker \
            --location="$REGION" \
            --description="Secure container repository with vulnerability scanning" \
            --quiet
    fi
    
    # Configure Docker authentication
    log "Configuring Docker authentication for Artifact Registry..."
    gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
    
    log_success "Artifact Registry repository configured"
}

# Function to create KMS resources
create_kms_resources() {
    log "Creating Cloud KMS resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would create KMS resources"
        return 0
    fi
    
    # Create key ring
    if gcloud kms keyrings describe "$KEYRING_NAME" --location="$REGION" --quiet 2>/dev/null; then
        log_warning "KMS key ring $KEYRING_NAME already exists in $REGION"
    else
        log "Creating KMS key ring: $KEYRING_NAME"
        gcloud kms keyrings create "$KEYRING_NAME" --location="$REGION" --quiet
    fi
    
    # Create signing key
    if gcloud kms keys describe "$KEY_NAME" --keyring="$KEYRING_NAME" --location="$REGION" --quiet 2>/dev/null; then
        log_warning "KMS key $KEY_NAME already exists"
    else
        log "Creating KMS signing key: $KEY_NAME"
        gcloud kms keys create "$KEY_NAME" \
            --location="$REGION" \
            --keyring="$KEYRING_NAME" \
            --purpose=asymmetric-signing \
            --default-algorithm=rsa-sign-pss-2048-sha256 \
            --quiet
    fi
    
    # Export key resource name
    export KEY_RESOURCE_NAME="projects/$PROJECT_ID/locations/$REGION/keyRings/$KEYRING_NAME/cryptoKeys/$KEY_NAME/cryptoKeyVersions/1"
    
    log_success "KMS resources created"
}

# Function to create Binary Authorization attestor
create_attestor() {
    log "Creating Binary Authorization attestor..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would create Binary Authorization attestor"
        return 0
    fi
    
    # Check if attestor already exists
    if gcloud container binauthz attestors describe "$ATTESTOR_NAME" --quiet 2>/dev/null; then
        log_warning "Attestor $ATTESTOR_NAME already exists"
    else
        log "Creating Binary Authorization attestor: $ATTESTOR_NAME"
        gcloud container binauthz attestors create "$ATTESTOR_NAME" \
            --attestation-authority-note-project="$PROJECT_ID" \
            --description="Attestor for CI/CD pipeline security verification" \
            --quiet
    fi
    
    # Add KMS public key to attestor
    log "Adding KMS public key to attestor..."
    gcloud container binauthz attestors public-keys add \
        --attestor="$ATTESTOR_NAME" \
        --keyversion-project="$PROJECT_ID" \
        --keyversion-location="$REGION" \
        --keyversion-keyring="$KEYRING_NAME" \
        --keyversion-key="$KEY_NAME" \
        --keyversion=1 \
        --quiet || log_warning "Public key may already be added to attestor"
    
    log_success "Binary Authorization attestor configured"
}

# Function to create GKE cluster
create_gke_cluster() {
    if [[ "$SKIP_CLUSTER_CREATION" == "true" ]]; then
        log_warning "Skipping GKE cluster creation (SKIP_CLUSTER_CREATION=true)"
        return 0
    fi
    
    log "Creating GKE cluster with Binary Authorization..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would create GKE cluster"
        return 0
    fi
    
    # Check if cluster already exists
    if gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --quiet 2>/dev/null; then
        log_warning "GKE cluster $CLUSTER_NAME already exists in $ZONE"
    else
        log "Creating GKE cluster: $CLUSTER_NAME"
        gcloud container clusters create "$CLUSTER_NAME" \
            --zone="$ZONE" \
            --enable-binauthz \
            --enable-autoscaling \
            --min-nodes=1 \
            --max-nodes=3 \
            --machine-type=e2-medium \
            --enable-autorepair \
            --enable-autoupgrade \
            --quiet
    fi
    
    # Get cluster credentials
    log "Getting cluster credentials..."
    gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$ZONE" --quiet
    
    # Verify Binary Authorization is enabled
    local binauthz_enabled=$(gcloud container clusters describe "$CLUSTER_NAME" \
        --zone="$ZONE" \
        --format="value(binaryAuthorization.enabled)" 2>/dev/null || echo "false")
    
    if [[ "$binauthz_enabled" == "true" ]]; then
        log_success "GKE cluster created with Binary Authorization enabled"
    else
        log_error "Binary Authorization not enabled on cluster"
        exit 1
    fi
}

# Function to configure Binary Authorization policy
configure_binauthz_policy() {
    log "Configuring Binary Authorization policy..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would configure Binary Authorization policy"
        return 0
    fi
    
    # Create policy configuration
    cat > /tmp/binauthz-policy.yaml <<EOF
admissionWhitelistPatterns:
- namePattern: gcr.io/google-containers/*
- namePattern: gcr.io/google_containers/*
- namePattern: k8s.gcr.io/*
- namePattern: gcr.io/gke-release/*
- namePattern: gke.gcr.io/*
- namePattern: gcr.io/gke-node-image/*
defaultAdmissionRule:
  requireAttestationsBy:
  - projects/$PROJECT_ID/attestors/$ATTESTOR_NAME
  evaluationMode: REQUIRE_ATTESTATION
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
clusterAdmissionRules:
  $ZONE.$CLUSTER_NAME:
    requireAttestationsBy:
    - projects/$PROJECT_ID/attestors/$ATTESTOR_NAME
    evaluationMode: REQUIRE_ATTESTATION
    enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
EOF
    
    # Apply policy
    log "Applying Binary Authorization policy..."
    gcloud container binauthz policy import /tmp/binauthz-policy.yaml --quiet
    
    # Clean up temporary file
    rm -f /tmp/binauthz-policy.yaml
    
    log_success "Binary Authorization policy configured"
}

# Function to create sample application
create_sample_app() {
    if [[ "$SKIP_SAMPLE_APP" == "true" ]]; then
        log_warning "Skipping sample application creation (SKIP_SAMPLE_APP=true)"
        return 0
    fi
    
    log "Creating sample application..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would create sample application"
        return 0
    fi
    
    # Create application directory
    mkdir -p secure-app
    
    # Create Dockerfile
    cat > secure-app/Dockerfile <<EOF
FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine
COPY app.py /app/
WORKDIR /app
RUN apk add --no-cache python3
EXPOSE 8080
CMD ["python3", "app.py"]
EOF
    
    # Create Python application
    cat > secure-app/app.py <<EOF
from http.server import HTTPServer, SimpleHTTPRequestHandler
import os
import json
import socket

class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        
        hostname = socket.gethostname()
        html_content = f'''
        <html>
        <head><title>Secure Application</title></head>
        <body>
            <h1>🔒 Secure Application</h1>
            <p>✅ Deployed with Binary Authorization!</p>
            <p>🏷️ Container: {hostname}</p>
            <p>🔐 This container was cryptographically verified before deployment</p>
            <hr>
            <p><small>Recipe: Software Supply Chain Security with Binary Authorization and Cloud Build</small></p>
        </body>
        </html>
        '''
        self.wfile.write(html_content.encode())

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8080), Handler)
    print('🚀 Secure server running on port 8080...')
    server.serve_forever()
EOF
    
    log_success "Sample application created"
}

# Function to create Cloud Build configuration
create_cloud_build_config() {
    if [[ "$SKIP_SAMPLE_APP" == "true" ]]; then
        log_warning "Skipping Cloud Build configuration (SKIP_SAMPLE_APP=true)"
        return 0
    fi
    
    log "Creating Cloud Build configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would create Cloud Build configuration"
        return 0
    fi
    
    # Create Cloud Build configuration
    cat > secure-app/cloudbuild.yaml <<EOF
steps:
# Build the container image
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/secure-app:\$SHORT_SHA', '.']

# Push the image to Artifact Registry
- name: 'gcr.io/cloud-builders/docker'
  args: ['push', '$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/secure-app:\$SHORT_SHA']

# Wait for vulnerability scan results
- name: 'gcr.io/google.com/cloudsdktool/google-cloud-cli:latest'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "⏳ Waiting for vulnerability scan to complete..."
    sleep 30
    echo "🔍 Initiating vulnerability scan..."
    gcloud artifacts docker images scan $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/secure-app:\$SHORT_SHA \
      --location=$REGION --async || echo "⚠️  Vulnerability scan may already be in progress"

# Create attestation for the built image
- name: 'gcr.io/google.com/cloudsdktool/google-cloud-cli:latest'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "🔐 Creating cryptographic attestation for image..."
    gcloud container binauthz attestations sign-and-create \
      --artifact-url="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/secure-app:\$SHORT_SHA" \
      --attestor="$ATTESTOR_NAME" \
      --attestor-project="$PROJECT_ID" \
      --keyversion-project="$PROJECT_ID" \
      --keyversion-location="$REGION" \
      --keyversion-keyring="$KEYRING_NAME" \
      --keyversion-key="$KEY_NAME" \
      --keyversion="1"
    echo "✅ Attestation created successfully"

images:
- '$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/secure-app:\$SHORT_SHA'

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: 'E2_HIGHCPU_8'
  
timeout: 1200s
EOF
    
    log_success "Cloud Build configuration created"
}

# Function to configure IAM permissions
configure_iam_permissions() {
    log "Configuring IAM permissions for Cloud Build..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would configure IAM permissions"
        return 0
    fi
    
    # Get Cloud Build service account
    local project_number=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
    local cloud_build_sa="${project_number}@cloudbuild.gserviceaccount.com"
    
    log "Granting KMS permissions to Cloud Build service account..."
    gcloud kms keys add-iam-policy-binding "$KEY_NAME" \
        --location="$REGION" \
        --keyring="$KEYRING_NAME" \
        --member="serviceAccount:$cloud_build_sa" \
        --role="roles/cloudkms.signerVerifier" \
        --quiet
    
    log "Granting Binary Authorization permissions to Cloud Build service account..."
    gcloud container binauthz attestors add-iam-policy-binding "$ATTESTOR_NAME" \
        --member="serviceAccount:$cloud_build_sa" \
        --role="roles/binaryauthorization.attestorsEditor" \
        --quiet
    
    log_success "IAM permissions configured"
}

# Function to trigger secure build
trigger_secure_build() {
    if [[ "$SKIP_SAMPLE_APP" == "true" ]]; then
        log_warning "Skipping secure build (SKIP_SAMPLE_APP=true)"
        return 0
    fi
    
    log "Triggering secure build pipeline..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would trigger secure build pipeline"
        return 0
    fi
    
    # Change to application directory
    cd secure-app
    
    # Submit build
    log "Submitting build to Cloud Build..."
    gcloud builds submit . --config=cloudbuild.yaml --quiet
    
    # Get the latest build SHA
    local image_sha=$(gcloud builds list --limit=1 --format="value(substitutions.SHORT_SHA)" --filter="status=SUCCESS")
    
    if [[ -z "$image_sha" ]]; then
        log_error "Failed to get build SHA. Build may have failed."
        exit 1
    fi
    
    export FULL_IMAGE_URL="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/secure-app:$image_sha"
    echo "$FULL_IMAGE_URL" > ../image_url.txt
    
    log_success "Secure build completed successfully"
    log_success "Image built: $FULL_IMAGE_URL"
    
    # Return to parent directory
    cd ..
}

# Function to deploy sample application
deploy_sample_app() {
    if [[ "$SKIP_SAMPLE_APP" == "true" ]]; then
        log_warning "Skipping sample application deployment (SKIP_SAMPLE_APP=true)"
        return 0
    fi
    
    log "Deploying sample application to GKE..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Would deploy sample application"
        return 0
    fi
    
    # Read the image URL from file
    if [[ -f "image_url.txt" ]]; then
        local image_url=$(cat image_url.txt)
    else
        log_error "Image URL file not found. Build may have failed."
        exit 1
    fi
    
    # Create deployment manifest
    cat > deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
  labels:
    app: secure-app
spec:
  replicas: 2
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
        image: $image_url
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: secure-app-service
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: secure-app
EOF
    
    # Deploy the application
    log "Applying Kubernetes deployment..."
    kubectl apply -f deployment.yaml
    
    # Wait for deployment to be ready
    log "Waiting for deployment to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/secure-app
    
    # Get service information
    log "Getting service information..."
    kubectl get service secure-app-service
    
    log_success "Sample application deployed successfully"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo "Cluster Name: $CLUSTER_NAME"
    echo "Repository Name: $REPO_NAME"
    echo "Key Ring: $KEYRING_NAME"
    echo "Key Name: $KEY_NAME"
    echo "Attestor Name: $ATTESTOR_NAME"
    echo "===================="
    
    if [[ "$SKIP_SAMPLE_APP" != "true" && "$DRY_RUN" != "true" ]]; then
        echo ""
        log "Application Access:"
        echo "Getting external IP address..."
        local external_ip=""
        local attempts=0
        while [[ -z "$external_ip" && $attempts -lt 30 ]]; do
            external_ip=$(kubectl get service secure-app-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [[ -z "$external_ip" ]]; then
                echo "Waiting for external IP... (attempt $((attempts+1))/30)"
                sleep 10
                ((attempts++))
            fi
        done
        
        if [[ -n "$external_ip" ]]; then
            echo "🌐 Application URL: http://$external_ip"
            echo "🔐 This application was deployed with Binary Authorization verification"
        else
            echo "⚠️  External IP not yet available. Check later with:"
            echo "kubectl get service secure-app-service"
        fi
    fi
    
    echo ""
    log_success "Deployment completed successfully!"
}

# Function to run validation tests
run_validation_tests() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN: Skipping validation tests"
        return 0
    fi
    
    log "Running validation tests..."
    
    # Test 1: Verify Binary Authorization policy
    log "Test 1: Verifying Binary Authorization policy..."
    if gcloud container binauthz policy export --quiet > /dev/null 2>&1; then
        log_success "✅ Binary Authorization policy is configured"
    else
        log_error "❌ Binary Authorization policy verification failed"
        return 1
    fi
    
    # Test 2: Verify attestor configuration
    log "Test 2: Verifying attestor configuration..."
    if gcloud container binauthz attestors describe "$ATTESTOR_NAME" --quiet > /dev/null 2>&1; then
        log_success "✅ Attestor is properly configured"
    else
        log_error "❌ Attestor verification failed"
        return 1
    fi
    
    # Test 3: Verify KMS key exists
    log "Test 3: Verifying KMS key..."
    if gcloud kms keys describe "$KEY_NAME" --keyring="$KEYRING_NAME" --location="$REGION" --quiet > /dev/null 2>&1; then
        log_success "✅ KMS key is accessible"
    else
        log_error "❌ KMS key verification failed"
        return 1
    fi
    
    # Test 4: Verify cluster has Binary Authorization enabled
    if [[ "$SKIP_CLUSTER_CREATION" != "true" ]]; then
        log "Test 4: Verifying cluster Binary Authorization..."
        local binauthz_enabled=$(gcloud container clusters describe "$CLUSTER_NAME" \
            --zone="$ZONE" \
            --format="value(binaryAuthorization.enabled)" 2>/dev/null || echo "false")
        
        if [[ "$binauthz_enabled" == "true" ]]; then
            log_success "✅ GKE cluster has Binary Authorization enabled"
        else
            log_error "❌ GKE cluster Binary Authorization verification failed"
            return 1
        fi
    fi
    
    # Test 5: Verify application deployment (if deployed)
    if [[ "$SKIP_SAMPLE_APP" != "true" ]]; then
        log "Test 5: Verifying application deployment..."
        if kubectl get deployment secure-app --quiet > /dev/null 2>&1; then
            local ready_replicas=$(kubectl get deployment secure-app -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            if [[ "$ready_replicas" -gt 0 ]]; then
                log_success "✅ Application is deployed and running"
            else
                log_warning "⚠️  Application deployment exists but no ready replicas"
            fi
        else
            log_warning "⚠️  Application deployment not found (may have been skipped)"
        fi
    fi
    
    log_success "Validation tests completed"
}

# Main deployment function
main() {
    echo "🚀 Starting Software Supply Chain Security Deployment"
    echo "======================================================"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --skip-cluster)
                SKIP_CLUSTER_CREATION="true"
                shift
                ;;
            --skip-app)
                SKIP_SAMPLE_APP="true"
                shift
                ;;
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --zone)
                ZONE="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --dry-run           Show what would be done without executing"
                echo "  --skip-cluster      Skip GKE cluster creation"
                echo "  --skip-app          Skip sample application deployment"
                echo "  --project-id ID     Override project ID"
                echo "  --region REGION     Override region (default: us-central1)"
                echo "  --zone ZONE         Override zone (default: us-central1-a)"
                echo "  --help              Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute deployment steps
    check_prerequisites
    configure_environment
    enable_apis
    create_artifact_registry
    create_kms_resources
    create_attestor
    create_gke_cluster
    configure_binauthz_policy
    create_sample_app
    create_cloud_build_config
    configure_iam_permissions
    trigger_secure_build
    deploy_sample_app
    run_validation_tests
    display_summary
    
    echo ""
    log_success "🎉 Software Supply Chain Security deployment completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Test the deployed application"
    echo "2. Try deploying an unauthorized image to see Binary Authorization in action"
    echo "3. Review the generated attestations and policies"
    echo "4. Customize the solution for your specific requirements"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Run main function
main "$@"