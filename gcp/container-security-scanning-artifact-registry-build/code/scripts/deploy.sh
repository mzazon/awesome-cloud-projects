#!/bin/bash

# Container Security Scanning with Artifact Registry and Cloud Build - Deployment Script
# This script deploys the complete container security scanning infrastructure
# including Artifact Registry, Cloud Build, Binary Authorization, and GKE cluster

set -euo pipefail

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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/secure-container-deployment"
DRY_RUN=${DRY_RUN:-false}

# Cleanup function for script interruption
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Deployment failed. Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"
    fi
    exit $exit_code
}
trap cleanup EXIT

# Help function
show_help() {
    cat << EOF
Container Security Scanning Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud project ID (required)
    -r, --region REGION           Deployment region (default: us-central1)
    -z, --zone ZONE              Deployment zone (default: us-central1-a)
    -n, --name-suffix SUFFIX     Resource name suffix (default: random)
    --dry-run                    Show what would be deployed without executing
    -h, --help                   Show this help message

EXAMPLES:
    $0 --project-id my-project
    $0 --project-id my-project --region us-east1 --zone us-east1-a
    DRY_RUN=true $0 --project-id my-project

PREREQUISITES:
    - gcloud CLI installed and authenticated
    - Project billing enabled
    - Appropriate IAM permissions
    - Docker installed (for testing)

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -n|--name-suffix)
                NAME_SUFFIX="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi

    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        log_warning "Docker is not installed. You may need it for local testing."
    fi

    # Validate project ID
    if [ -z "${PROJECT_ID:-}" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -z "$PROJECT_ID" ]; then
            log_error "Project ID not specified and no default project configured."
            log_error "Use --project-id option or run 'gcloud config set project PROJECT_ID'"
            exit 1
        fi
        log_info "Using default project: $PROJECT_ID"
    fi

    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project '$PROJECT_ID' not found or not accessible."
        exit 1
    fi

    # Check if billing is enabled
    if ! gcloud billing projects describe "$PROJECT_ID" --format="value(billingEnabled)" 2>/dev/null | grep -q "True"; then
        log_error "Billing is not enabled for project '$PROJECT_ID'."
        log_error "Please enable billing in the Google Cloud Console."
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Execute command with dry-run support
execute_command() {
    local cmd="$1"
    local description="${2:-Executing command}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] $description"
        log_info "[DRY RUN] Command: $cmd"
        return 0
    else
        log_info "$description"
        eval "$cmd"
    fi
}

# Wait for operation to complete
wait_for_operation() {
    local operation_name="$1"
    local operation_type="${2:-regional}"
    local max_wait="${3:-300}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would wait for operation: $operation_name"
        return 0
    fi

    log_info "Waiting for operation to complete: $operation_name"
    local count=0
    while [ $count -lt $max_wait ]; do
        local status
        if [ "$operation_type" = "global" ]; then
            status=$(gcloud compute operations describe "$operation_name" --global --format="value(status)" 2>/dev/null || echo "RUNNING")
        else
            status=$(gcloud compute operations describe "$operation_name" --region="$REGION" --format="value(status)" 2>/dev/null || echo "RUNNING")
        fi
        
        if [ "$status" = "DONE" ]; then
            log_success "Operation completed: $operation_name"
            return 0
        fi
        
        echo -n "."
        sleep 5
        count=$((count + 5))
    done
    
    log_error "Operation timed out: $operation_name"
    return 1
}

# Set default values and generate unique identifiers
set_defaults() {
    REGION="${REGION:-us-central1}"
    ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix if not provided
    if [ -z "${NAME_SUFFIX:-}" ]; then
        NAME_SUFFIX=$(openssl rand -hex 3 2>/dev/null || date +%s | tail -c 6)
    fi
    
    # Resource names
    REPO_NAME="secure-app-${NAME_SUFFIX}"
    CLUSTER_NAME="security-cluster-${NAME_SUFFIX}"
    SERVICE_ACCOUNT_NAME="security-scanner-${NAME_SUFFIX}"
    KEYRING_NAME="security-keyring"
    KEY_NAME="security-signing-key"
    ATTESTOR_NAME="security-attestor"
    
    log_info "Deployment configuration:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Zone: $ZONE"
    log_info "  Repository: $REPO_NAME"
    log_info "  Cluster: $CLUSTER_NAME"
    log_info "  Service Account: $SERVICE_ACCOUNT_NAME"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "artifactregistry.googleapis.com"
        "cloudbuild.googleapis.com"
        "container.googleapis.com"
        "binaryauthorization.googleapis.com"
        "containeranalysis.googleapis.com"
        "securitycenter.googleapis.com"
        "cloudkms.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        execute_command \
            "gcloud services enable $api --project=$PROJECT_ID" \
            "Enabling API: $api"
    done
    
    log_success "All required APIs enabled"
}

# Set gcloud configuration
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    execute_command \
        "gcloud config set project $PROJECT_ID" \
        "Setting default project"
    
    execute_command \
        "gcloud config set compute/region $REGION" \
        "Setting default region"
    
    execute_command \
        "gcloud config set compute/zone $ZONE" \
        "Setting default zone"
    
    log_success "gcloud configuration updated"
}

# Create Artifact Registry repository
create_artifact_registry() {
    log_info "Creating Artifact Registry repository with vulnerability scanning..."
    
    # Create repository
    execute_command \
        "gcloud artifacts repositories create $REPO_NAME \
            --repository-format=docker \
            --location=$REGION \
            --description='Secure container repository with vulnerability scanning' \
            --project=$PROJECT_ID" \
        "Creating Artifact Registry repository"
    
    # Enable vulnerability scanning
    execute_command \
        "gcloud artifacts repositories update $REPO_NAME \
            --location=$REGION \
            --enable-vulnerability-scanning \
            --project=$PROJECT_ID" \
        "Enabling vulnerability scanning"
    
    # Configure Docker authentication
    execute_command \
        "gcloud auth configure-docker ${REGION}-docker.pkg.dev" \
        "Configuring Docker authentication"
    
    log_success "Artifact Registry repository created and configured"
}

# Create service account for automation
create_service_account() {
    log_info "Creating service account for security automation..."
    
    # Create service account
    execute_command \
        "gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
            --display-name='Security Scanner Service Account' \
            --description='Service account for automated security scanning and attestation' \
            --project=$PROJECT_ID" \
        "Creating service account"
    
    # Grant necessary permissions
    local roles=(
        "roles/binaryauthorization.attestorsAdmin"
        "roles/containeranalysis.notes.editor"
        "roles/cloudkms.cryptoKeyVersions.useToSign"
        "roles/cloudkms.viewer"
    )
    
    for role in "${roles[@]}"; do
        execute_command \
            "gcloud projects add-iam-policy-binding $PROJECT_ID \
                --member='serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com' \
                --role='$role'" \
            "Granting role: $role"
    done
    
    # Grant Cloud Build service account permission to use the security service account
    local cloud_build_sa="${PROJECT_ID}@cloudbuild.gserviceaccount.com"
    execute_command \
        "gcloud iam service-accounts add-iam-policy-binding \
            ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
            --member='serviceAccount:${cloud_build_sa}' \
            --role='roles/iam.serviceAccountTokenCreator' \
            --project=$PROJECT_ID" \
        "Granting Cloud Build access to service account"
    
    log_success "Service account created with appropriate permissions"
}

# Create KMS resources
create_kms_resources() {
    log_info "Creating KMS keyring and signing key..."
    
    # Create keyring
    execute_command \
        "gcloud kms keyrings create $KEYRING_NAME \
            --location=$REGION \
            --project=$PROJECT_ID" \
        "Creating KMS keyring"
    
    # Create signing key
    execute_command \
        "gcloud kms keys create $KEY_NAME \
            --location=$REGION \
            --keyring=$KEYRING_NAME \
            --purpose=asymmetric-signing \
            --default-algorithm=rsa-sign-pkcs1-4096-sha512 \
            --project=$PROJECT_ID" \
        "Creating asymmetric signing key"
    
    log_success "KMS resources created"
}

# Create Binary Authorization attestor
create_attestor() {
    log_info "Creating Binary Authorization attestor..."
    
    # Create temp directory for configuration files
    mkdir -p "$TEMP_DIR"
    
    # Create attestor note configuration
    cat > "$TEMP_DIR/attestor-note.json" << EOF
{
  "name": "projects/${PROJECT_ID}/notes/security-attestor-note",
  "attestation": {
    "hint": {
      "human_readable_name": "Security vulnerability scan attestor"
    }
  }
}
EOF
    
    # Create the attestor note
    if [ "$DRY_RUN" != true ]; then
        local access_token
        access_token=$(gcloud auth print-access-token)
        
        curl -X POST \
            -H "Authorization: Bearer $access_token" \
            -H "Content-Type: application/json" \
            --data-binary "@$TEMP_DIR/attestor-note.json" \
            "https://containeranalysis.googleapis.com/v1/projects/${PROJECT_ID}/notes?noteId=security-attestor-note" \
            --fail --silent --show-error
        
        log_success "Attestor note created"
    else
        log_info "[DRY RUN] Would create attestor note via Container Analysis API"
    fi
    
    # Create the Binary Authorization attestor
    execute_command \
        "gcloud container binauthz attestors create $ATTESTOR_NAME \
            --attestation-authority-note=security-attestor-note \
            --attestation-authority-note-project=$PROJECT_ID \
            --project=$PROJECT_ID" \
        "Creating Binary Authorization attestor"
    
    # Add KMS key to attestor
    execute_command \
        "gcloud container binauthz attestors public-keys add \
            --attestor=$ATTESTOR_NAME \
            --keyversion-project=$PROJECT_ID \
            --keyversion-location=$REGION \
            --keyversion-keyring=$KEYRING_NAME \
            --keyversion-key=$KEY_NAME \
            --keyversion=1 \
            --project=$PROJECT_ID" \
        "Adding KMS key to attestor"
    
    log_success "Binary Authorization attestor created and configured"
}

# Configure Binary Authorization policy
configure_binauthz_policy() {
    log_info "Configuring Binary Authorization policy..."
    
    # Create policy configuration
    cat > "$TEMP_DIR/binauthz-policy.yaml" << EOF
defaultAdmissionRule:
  requireAttestationsBy:
  - projects/${PROJECT_ID}/attestors/${ATTESTOR_NAME}
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
globalPolicyEvaluationMode: ENABLE
admissionWhitelistPatterns:
- namePattern: gcr.io/gke-release/*
- namePattern: gcr.io/google-containers/*
- namePattern: k8s.gcr.io/*
- namePattern: gke.gcr.io/*
clusterAdmissionRules:
  ${ZONE}.${CLUSTER_NAME}:
    requireAttestationsBy:
    - projects/${PROJECT_ID}/attestors/${ATTESTOR_NAME}
    enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
EOF
    
    # Import the policy
    execute_command \
        "gcloud container binauthz policy import $TEMP_DIR/binauthz-policy.yaml \
            --project=$PROJECT_ID" \
        "Importing Binary Authorization policy"
    
    log_success "Binary Authorization policy configured"
}

# Create GKE cluster
create_gke_cluster() {
    log_info "Creating GKE cluster with Binary Authorization..."
    
    execute_command \
        "gcloud container clusters create $CLUSTER_NAME \
            --zone=$ZONE \
            --enable-binauthz \
            --enable-autorepair \
            --enable-autoupgrade \
            --num-nodes=2 \
            --machine-type=e2-medium \
            --disk-size=30GB \
            --enable-shielded-nodes \
            --project=$PROJECT_ID" \
        "Creating GKE cluster"
    
    # Get cluster credentials
    execute_command \
        "gcloud container clusters get-credentials $CLUSTER_NAME \
            --zone=$ZONE \
            --project=$PROJECT_ID" \
        "Configuring kubectl credentials"
    
    log_success "GKE cluster created and configured"
}

# Create sample application and Cloud Build configuration
create_sample_application() {
    log_info "Creating sample application and Cloud Build configuration..."
    
    # Create application directory
    local app_dir="$TEMP_DIR/secure-app"
    mkdir -p "$app_dir"
    
    # Create Python Flask application
    cat > "$app_dir/app.py" << 'EOF'
from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/')
def hello():
    return f"Secure Application Running! Environment: {os.getenv('ENV', 'development')}"

@app.route('/health')
def health():
    return jsonify({
        "status": "healthy",
        "version": "1.0.0",
        "security_scanned": True
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF
    
    # Create requirements file
    cat > "$app_dir/requirements.txt" << 'EOF'
Flask==2.3.3
Werkzeug==2.3.7
EOF
    
    # Create Dockerfile
    cat > "$app_dir/Dockerfile" << 'EOF'
FROM python:3.11-slim

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash app

WORKDIR /app

# Copy and install requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app.py .

# Change ownership to app user
RUN chown -R app:app /app
USER app

EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["python", "app.py"]
EOF
    
    # Create Cloud Build configuration
    cat > "$app_dir/cloudbuild.yaml" << EOF
steps:
# Build the container image
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/secure-app:\$SHORT_SHA', '.']

# Push image to Artifact Registry
- name: 'gcr.io/cloud-builders/docker'
  args: ['push', '${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/secure-app:\$SHORT_SHA']

# Wait for vulnerability scanning to complete
- name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "Waiting for vulnerability scan to complete..."
    for i in {1..30}; do
      SCAN_STATUS=\$(gcloud artifacts docker images scan ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/secure-app:\$SHORT_SHA --format="value(status)" 2>/dev/null || echo "SCANNING")
      if [[ "\$SCAN_STATUS" == "FINISHED" ]]; then
        echo "Vulnerability scan completed"
        break
      fi
      echo "Scan in progress... (\$i/30)"
      sleep 10
    done

# Check vulnerability scan results
- name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "Checking vulnerability scan results..."
    CRITICAL_VULNS=\$(gcloud artifacts docker images list-vulnerabilities ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/secure-app:\$SHORT_SHA --format="value(vulnerability.severity)" --filter="vulnerability.severity=CRITICAL" 2>/dev/null | wc -l)
    HIGH_VULNS=\$(gcloud artifacts docker images list-vulnerabilities ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/secure-app:\$SHORT_SHA --format="value(vulnerability.severity)" --filter="vulnerability.severity=HIGH" 2>/dev/null | wc -l)
    
    echo "Critical vulnerabilities: \$CRITICAL_VULNS"
    echo "High vulnerabilities: \$HIGH_VULNS"
    
    if [[ \$CRITICAL_VULNS -gt 0 ]]; then
      echo "FAIL: Critical vulnerabilities found. Deployment blocked."
      exit 1
    fi
    
    if [[ \$HIGH_VULNS -gt 5 ]]; then
      echo "FAIL: Too many high-severity vulnerabilities (\$HIGH_VULNS > 5). Deployment blocked."
      exit 1
    fi
    
    echo "PASS: Image meets security requirements"

# Create security attestation
- name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "Creating security attestation..."
    
    # Get image digest
    IMAGE_DIGEST=\$(gcloud artifacts docker images describe ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/secure-app:\$SHORT_SHA --format="value(image_summary.digest)")
    IMAGE_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/secure-app@\$IMAGE_DIGEST"
    
    # Create attestation payload
    TIMESTAMP=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
    PAYLOAD='{"timestamp":"'\$TIMESTAMP'","vulnerabilities_checked":true,"policy_compliant":true}'
    
    # Sign the payload using KMS
    echo -n "\$PAYLOAD" > /tmp/payload.json
    
    # Create the attestation
    gcloud container binauthz attestations create \
      --artifact-url="\$IMAGE_URL" \
      --attestor=${ATTESTOR_NAME} \
      --signature-file=<(gcloud kms asymmetric-sign \
        --key=${KEY_NAME} \
        --keyring=${KEYRING_NAME} \
        --location=${REGION} \
        --digest-algorithm=sha512 \
        --input-file=/tmp/payload.json \
        --format="value(signature)") \
      --project=${PROJECT_ID}
    
    echo "✅ Security attestation created for image"

images:
- '${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/secure-app:\$SHORT_SHA'

serviceAccount: 'projects/${PROJECT_ID}/serviceAccounts/${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com'

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: 'E2_HIGHCPU_8'
EOF
    
    log_success "Sample application and Cloud Build configuration created"
    log_info "Application files created in: $app_dir"
}

# Display deployment information
display_deployment_info() {
    log_success "Container Security Scanning infrastructure deployed successfully!"
    
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo ""
    echo "Resources Created:"
    echo "  • Artifact Registry Repository: $REPO_NAME"
    echo "  • GKE Cluster: $CLUSTER_NAME"
    echo "  • Service Account: $SERVICE_ACCOUNT_NAME"
    echo "  • KMS Keyring: $KEYRING_NAME"
    echo "  • KMS Key: $KEY_NAME"
    echo "  • Binary Authorization Attestor: $ATTESTOR_NAME"
    echo ""
    echo "Sample Application:"
    echo "  • Location: $TEMP_DIR/secure-app"
    echo "  • Build Command: cd $TEMP_DIR/secure-app && gcloud builds submit --config=cloudbuild.yaml"
    echo ""
    echo "Next Steps:"
    echo "  1. Review the sample application code in $TEMP_DIR/secure-app"
    echo "  2. Submit a build to test the security pipeline:"
    echo "     cd $TEMP_DIR/secure-app"
    echo "     gcloud builds submit --config=cloudbuild.yaml"
    echo "  3. Monitor the build process in Cloud Build console"
    echo "  4. Deploy the attested image to your GKE cluster"
    echo ""
    echo "Useful Commands:"
    echo "  • View repository: gcloud artifacts repositories describe $REPO_NAME --location=$REGION"
    echo "  • Check cluster: kubectl get nodes"
    echo "  • View policy: gcloud container binauthz policy export"
    echo "  • List attestors: gcloud container binauthz attestors list"
    echo ""
    echo "Web Console Links:"
    echo "  • Artifact Registry: https://console.cloud.google.com/artifacts/browse/$PROJECT_ID"
    echo "  • Cloud Build: https://console.cloud.google.com/cloud-build/builds?project=$PROJECT_ID"
    echo "  • GKE Clusters: https://console.cloud.google.com/kubernetes/list/overview?project=$PROJECT_ID"
    echo "  • Binary Authorization: https://console.cloud.google.com/security/binary-authorization?project=$PROJECT_ID"
    echo ""
}

# Main deployment function
main() {
    log_info "Starting Container Security Scanning deployment..."
    
    # Parse arguments
    parse_args "$@"
    
    # Set defaults and validate
    set_defaults
    check_prerequisites
    
    # Show dry-run banner
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE - No resources will be created"
        echo ""
    fi
    
    # Execute deployment steps
    configure_gcloud
    enable_apis
    create_artifact_registry
    create_service_account
    create_kms_resources
    create_attestor
    configure_binauthz_policy
    create_gke_cluster
    create_sample_application
    
    # Display results
    if [ "$DRY_RUN" != true ]; then
        display_deployment_info
    else
        log_info "DRY RUN completed - review the commands above"
    fi
    
    log_success "Deployment script completed successfully!"
}

# Run main function with all arguments
main "$@"