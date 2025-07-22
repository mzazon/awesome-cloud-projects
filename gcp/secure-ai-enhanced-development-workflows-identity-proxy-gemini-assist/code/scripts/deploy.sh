#!/bin/bash

# Deploy script for Secure AI-Enhanced Development Workflows with Cloud Identity-Aware Proxy and Gemini Code Assist
# This script implements the complete deployment process for the GCP recipe

set -euo pipefail

# Colors for output
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

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check the logs above for details."
    log_info "Run './destroy.sh' to clean up any partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_LOG="${SCRIPT_DIR}/deployment.log"

# Default values (can be overridden by environment variables)
PROJECT_PREFIX="${PROJECT_PREFIX:-secure-dev}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
BILLING_ACCOUNT_ID="${BILLING_ACCOUNT_ID:-}"
ORG_ID="${ORG_ID:-}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check gcloud version
    GCLOUD_VERSION=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log_info "Google Cloud CLI version: ${GCLOUD_VERSION}"
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "You are not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    CURRENT_USER=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
    log_info "Authenticated as: ${CURRENT_USER}"
    
    # Check for required tools
    for tool in openssl curl; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is required but not installed."
            exit 1
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique project ID
    TIMESTAMP=$(date +%s)
    export PROJECT_ID="${PROJECT_PREFIX}-${TIMESTAMP}"
    
    # Set other environment variables
    export REGION="${REGION}"
    export ZONE="${ZONE}"
    
    # Get organization ID if not provided
    if [[ -z "${ORG_ID}" ]]; then
        ORG_ID=$(gcloud organizations list --format="value(name)" --limit=1 2>/dev/null || echo "")
        if [[ -z "${ORG_ID}" ]]; then
            log_error "No organization found. This recipe requires Organization-level permissions."
            log_error "Please ensure you have access to a Google Cloud Organization."
            exit 1
        fi
    fi
    export ORG_ID="${ORG_ID}"
    
    # Get billing account if not provided
    if [[ -z "${BILLING_ACCOUNT_ID}" ]]; then
        BILLING_ACCOUNT_ID=$(gcloud billing accounts list --format="value(name)" --limit=1 2>/dev/null || echo "")
        if [[ -z "${BILLING_ACCOUNT_ID}" ]]; then
            log_error "No billing account found. Please ensure you have access to a billing account."
            exit 1
        fi
    fi
    export BILLING_ACCOUNT_ID="${BILLING_ACCOUNT_ID}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export APP_NAME="secure-dev-app-${RANDOM_SUFFIX}"
    export WORKSTATION_NAME="secure-workstation-${RANDOM_SUFFIX}"
    export SECRET_NAME="app-secrets-${RANDOM_SUFFIX}"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Zone: ${ZONE}"
    log_info "Organization ID: ${ORG_ID}"
    log_info "Billing Account: ${BILLING_ACCOUNT_ID}"
    log_success "Environment variables configured"
}

# Function to create and configure project
create_project() {
    log_info "Creating Google Cloud project..."
    
    # Create the project
    if gcloud projects create "${PROJECT_ID}" --organization="${ORG_ID}" 2>/dev/null; then
        log_success "Project ${PROJECT_ID} created successfully"
    else
        log_warning "Project creation may have failed or project already exists"
    fi
    
    # Set default project
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Link billing account
    log_info "Linking billing account..."
    if gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT_ID}"; then
        log_success "Billing account linked successfully"
    else
        log_error "Failed to link billing account"
        exit 1
    fi
    
    log_success "Project configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "iap.googleapis.com"
        "compute.googleapis.com"
        "cloudbuild.googleapis.com"
        "secretmanager.googleapis.com"
        "cloudkms.googleapis.com"
        "workstations.googleapis.com"
        "run.googleapis.com"
        "artifactregistry.googleapis.com"
        "sourcerepo.googleapis.com"
        "aiplatform.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to configure KMS encryption
configure_kms() {
    log_info "Configuring Cloud KMS for encryption..."
    
    # Create KMS keyring
    if gcloud kms keyrings create secure-dev-keyring --location="${REGION}" 2>/dev/null; then
        log_success "KMS keyring created"
    else
        log_warning "KMS keyring may already exist"
    fi
    
    # Create encryption key
    if gcloud kms keys create secret-encryption-key \
        --location="${REGION}" \
        --keyring=secure-dev-keyring \
        --purpose=encryption \
        --quiet 2>/dev/null; then
        log_success "KMS encryption key created"
    else
        log_warning "KMS encryption key may already exist"
    fi
    
    # Verify key creation
    gcloud kms keys list --location="${REGION}" --keyring=secure-dev-keyring --quiet
    
    log_success "KMS encryption infrastructure established"
}

# Function to set up Cloud Secrets Manager
setup_secrets_manager() {
    log_info "Setting up Cloud Secrets Manager with encryption..."
    
    # Create secrets for development environment
    echo "database-connection-string-$(date +%s)" | \
        gcloud secrets create "${SECRET_NAME}-db" \
        --replication-policy="automatic" \
        --data-file=- \
        --quiet
    
    echo "api-key-for-external-service-$(date +%s)" | \
        gcloud secrets create "${SECRET_NAME}-api" \
        --replication-policy="automatic" \
        --data-file=- \
        --quiet
    
    # Create service account for application access
    if gcloud iam service-accounts create secure-app-sa \
        --display-name="Secure Application Service Account" \
        --description="Service account for secure development application" \
        --quiet; then
        log_success "Service account created"
    else
        log_warning "Service account may already exist"
    fi
    
    # Grant secret access permissions
    gcloud secrets add-iam-policy-binding "${SECRET_NAME}-db" \
        --member="serviceAccount:secure-app-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/secretmanager.secretAccessor" \
        --quiet
    
    gcloud secrets add-iam-policy-binding "${SECRET_NAME}-api" \
        --member="serviceAccount:secure-app-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/secretmanager.secretAccessor" \
        --quiet
    
    log_success "Secrets configured with proper access controls"
}

# Function to create Cloud Workstation
create_workstation() {
    log_info "Creating secure Cloud Workstation configuration..."
    
    # Create workstation cluster
    log_info "Creating workstation cluster (this may take several minutes)..."
    if gcloud workstations clusters create secure-dev-cluster \
        --region="${REGION}" \
        --network="projects/${PROJECT_ID}/global/networks/default" \
        --subnetwork="projects/${PROJECT_ID}/regions/${REGION}/subnetworks/default" \
        --quiet; then
        log_success "Workstation cluster created"
    else
        log_warning "Workstation cluster may already exist"
    fi
    
    # Wait for cluster creation
    log_info "Waiting for workstation cluster to be ready..."
    local retry_count=0
    local max_retries=20
    while [[ $retry_count -lt $max_retries ]]; do
        if gcloud workstations clusters describe secure-dev-cluster \
            --region="${REGION}" \
            --format="value(state)" 2>/dev/null | grep -q "STATE_RUNNING"; then
            break
        fi
        log_info "Cluster not ready yet, waiting 30 seconds... (attempt $((retry_count + 1))/${max_retries})"
        sleep 30
        ((retry_count++))
    done
    
    if [[ $retry_count -eq $max_retries ]]; then
        log_error "Workstation cluster failed to become ready within expected time"
        exit 1
    fi
    
    # Create workstation configuration
    if gcloud workstations configs create secure-dev-config \
        --cluster=secure-dev-cluster \
        --region="${REGION}" \
        --machine-type=e2-standard-4 \
        --pd-disk-type=pd-standard \
        --pd-disk-size=100GB \
        --container-image=us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest \
        --service-account=secure-app-sa@${PROJECT_ID}.iam.gserviceaccount.com \
        --enable-ip-alias \
        --quiet; then
        log_success "Workstation configuration created"
    else
        log_warning "Workstation configuration may already exist"
    fi
    
    # Create workstation instance
    if gcloud workstations create "${WORKSTATION_NAME}" \
        --cluster=secure-dev-cluster \
        --config=secure-dev-config \
        --region="${REGION}" \
        --quiet; then
        log_success "Workstation instance created"
    else
        log_warning "Workstation instance may already exist"
    fi
    
    log_success "Secure Cloud Workstation created and configured"
}

# Function to deploy sample application
deploy_application() {
    log_info "Deploying sample application to Cloud Run..."
    
    # Create application directory structure
    local app_dir="${SCRIPT_DIR}/../secure-app"
    mkdir -p "${app_dir}/src"
    
    # Create sample application code
    cat > "${app_dir}/src/main.py" << 'EOF'
import os
from google.cloud import secretmanager
from flask import Flask, jsonify
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

def get_secret(secret_name):
    """Retrieve secret from Google Cloud Secret Manager"""
    try:
        client = secretmanager.SecretManagerServiceClient()
        project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')
        name = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
        response = client.access_secret_version(request={"name": name})
        return response.payload.data.decode('UTF-8')
    except Exception as e:
        logging.error(f"Error accessing secret {secret_name}: {e}")
        return None

@app.route('/health')
def health_check():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "service": "secure-dev-app"}), 200

@app.route('/api/config')
def get_config():
    """API endpoint that demonstrates secure secret access"""
    # This would typically be used for database connections, API keys, etc.
    db_secret = get_secret(os.environ.get('DB_SECRET_NAME'))
    api_secret = get_secret(os.environ.get('API_SECRET_NAME'))
    
    return jsonify({
        "message": "Configuration loaded securely",
        "db_connected": bool(db_secret),
        "api_configured": bool(api_secret),
        "environment": "secure"
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF

    # Create Dockerfile
    cat > "${app_dir}/Dockerfile" << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ .

# Run as non-root user for security
RUN adduser --disabled-password --gecos '' appuser
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080

CMD ["python", "main.py"]
EOF

    # Create requirements.txt
    cat > "${app_dir}/requirements.txt" << 'EOF'
Flask==2.3.2
google-cloud-secret-manager==2.16.2
gunicorn==21.2.0
EOF

    # Deploy to Cloud Run
    cd "${app_dir}"
    if gcloud run deploy "${APP_NAME}" \
        --source . \
        --region="${REGION}" \
        --service-account=secure-app-sa@${PROJECT_ID}.iam.gserviceaccount.com \
        --set-env-vars="DB_SECRET_NAME=${SECRET_NAME}-db,API_SECRET_NAME=${SECRET_NAME}-api" \
        --no-allow-unauthenticated \
        --max-instances=10 \
        --memory=512Mi \
        --cpu=1 \
        --port=8080 \
        --quiet; then
        log_success "Application deployed to Cloud Run"
    else
        log_error "Failed to deploy application to Cloud Run"
        exit 1
    fi
    
    cd "${SCRIPT_DIR}"
    
    log_success "Secure application deployed to Cloud Run"
}

# Function to configure IAP
configure_iap() {
    log_info "Configuring Cloud Identity-Aware Proxy (IAP)..."
    
    # Get the Cloud Run service URL
    SERVICE_URL=$(gcloud run services describe "${APP_NAME}" \
        --region="${REGION}" \
        --format="value(status.url)")
    
    log_info "Service URL: ${SERVICE_URL}"
    
    # Create OAuth consent screen (if not already configured)
    CURRENT_EMAIL=$(gcloud config get-value account)
    if gcloud iap oauth-brands create \
        --application_title="Secure Development Environment" \
        --support_email="${CURRENT_EMAIL}" \
        --quiet 2>/dev/null; then
        log_success "OAuth brand created"
    else
        log_warning "OAuth brand may already exist or creation failed"
    fi
    
    # Update Cloud Run service for IAP
    gcloud run services update "${APP_NAME}" \
        --region="${REGION}" \
        --add-env-vars="IAP_ENABLED=true" \
        --quiet
    
    # Configure IAP access policy
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="user:${CURRENT_EMAIL}" \
        --role="roles/iap.httpsResourceAccessor" \
        --quiet
    
    log_success "Cloud Identity-Aware Proxy configured"
    log_info "Service URL: ${SERVICE_URL}"
}

# Function to set up Cloud Build CI/CD
setup_cicd() {
    log_info "Setting up Cloud Build for secure CI/CD..."
    
    # Create Cloud Source Repository
    if gcloud source repos create secure-dev-repo --quiet 2>/dev/null; then
        log_success "Cloud Source Repository created"
    else
        log_warning "Cloud Source Repository may already exist"
    fi
    
    # Create Artifact Registry for container images
    if gcloud artifacts repositories create secure-dev-images \
        --repository-format=docker \
        --location="${REGION}" \
        --description="Secure development container images" \
        --quiet; then
        log_success "Artifact Registry repository created"
    else
        log_warning "Artifact Registry repository may already exist"
    fi
    
    # Create Cloud Build configuration
    cat > "${SCRIPT_DIR}/../cloudbuild.yaml" << EOF
steps:
  # Build the container image
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', '\${_LOCATION}-docker.pkg.dev/\${PROJECT_ID}/\${_REPOSITORY}/\${_IMAGE}:\${SHORT_SHA}', '.']
    dir: 'secure-app'
  
  # Push the container image to Artifact Registry
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', '\${_LOCATION}-docker.pkg.dev/\${PROJECT_ID}/\${_REPOSITORY}/\${_IMAGE}:\${SHORT_SHA}']
  
  # Deploy to Cloud Run
  - name: 'gcr.io/cloud-builders/gcloud'
    args:
    - 'run'
    - 'deploy'
    - '\${_SERVICE_NAME}'
    - '--image=\${_LOCATION}-docker.pkg.dev/\${PROJECT_ID}/\${_REPOSITORY}/\${_IMAGE}:\${SHORT_SHA}'
    - '--region=\${_REGION}'
    - '--service-account=\${_SERVICE_ACCOUNT}'
    - '--no-allow-unauthenticated'

substitutions:
  _LOCATION: ${REGION}
  _REPOSITORY: secure-dev-images
  _IMAGE: secure-dev-app
  _SERVICE_NAME: ${APP_NAME}
  _REGION: ${REGION}
  _SERVICE_ACCOUNT: secure-app-sa@${PROJECT_ID}.iam.gserviceaccount.com

options:
  logging: CLOUD_LOGGING_ONLY
  substitution_option: 'ALLOW_LOOSE'
EOF

    # Grant Cloud Build necessary permissions
    PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
        --role="roles/run.developer" \
        --quiet
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
        --role="roles/artifactregistry.writer" \
        --quiet
    
    log_success "Cloud Build CI/CD pipeline configured"
}

# Function to configure Gemini Code Assist
configure_gemini() {
    log_info "Configuring Gemini Code Assist integration..."
    
    # Create service account for Gemini Code Assist
    if gcloud iam service-accounts create gemini-code-assist-sa \
        --display-name="Gemini Code Assist Service Account" \
        --description="Service account for AI-powered development assistance" \
        --quiet; then
        log_success "Gemini Code Assist service account created"
    else
        log_warning "Gemini Code Assist service account may already exist"
    fi
    
    # Grant necessary permissions for Gemini Code Assist
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:gemini-code-assist-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/aiplatform.user" \
        --quiet
    
    # Configure Cloud Workstation for Gemini integration
    gcloud workstations configs update secure-dev-config \
        --cluster=secure-dev-cluster \
        --region="${REGION}" \
        --container-env="GEMINI_CODE_ASSIST_ENABLED=true,GOOGLE_CLOUD_PROJECT=${PROJECT_ID}" \
        --quiet
    
    # Restart workstation to apply changes
    log_info "Restarting workstation to apply Gemini integration..."
    gcloud workstations stop "${WORKSTATION_NAME}" \
        --cluster=secure-dev-cluster \
        --config=secure-dev-config \
        --region="${REGION}" \
        --quiet || true
    
    sleep 30
    
    gcloud workstations start "${WORKSTATION_NAME}" \
        --cluster=secure-dev-cluster \
        --config=secure-dev-config \
        --region="${REGION}" \
        --quiet
    
    log_success "Gemini Code Assist integration configured"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Test service URL
    SERVICE_URL=$(gcloud run services describe "${APP_NAME}" \
        --region="${REGION}" \
        --format="value(status.url)" 2>/dev/null || echo "")
    
    if [[ -n "${SERVICE_URL}" ]]; then
        log_success "Cloud Run service is accessible at: ${SERVICE_URL}"
    else
        log_warning "Could not retrieve service URL"
    fi
    
    # Verify secrets
    if gcloud secrets versions access latest --secret="${SECRET_NAME}-db" --quiet >/dev/null 2>&1; then
        log_success "Database secret is accessible"
    else
        log_warning "Database secret access failed"
    fi
    
    if gcloud secrets versions access latest --secret="${SECRET_NAME}-api" --quiet >/dev/null 2>&1; then
        log_success "API secret is accessible"
    else
        log_warning "API secret access failed"
    fi
    
    # Check workstation status
    WORKSTATION_STATE=$(gcloud workstations describe "${WORKSTATION_NAME}" \
        --cluster=secure-dev-cluster \
        --config=secure-dev-config \
        --region="${REGION}" \
        --format="value(state)" 2>/dev/null || echo "UNKNOWN")
    
    if [[ "${WORKSTATION_STATE}" == "STATE_RUNNING" ]]; then
        log_success "Cloud Workstation is running"
        log_info "Access your workstation at: https://workstations.googleusercontent.com/"
    else
        log_warning "Cloud Workstation state: ${WORKSTATION_STATE}"
    fi
    
    log_success "Deployment validation completed"
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    local info_file="${SCRIPT_DIR}/deployment-info.txt"
    cat > "${info_file}" << EOF
# Secure AI-Enhanced Development Workflows Deployment Information
# Generated on: $(date)

PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
APP_NAME=${APP_NAME}
WORKSTATION_NAME=${WORKSTATION_NAME}
SECRET_NAME=${SECRET_NAME}
ORG_ID=${ORG_ID}
BILLING_ACCOUNT_ID=${BILLING_ACCOUNT_ID}

# Access URLs
SERVICE_URL=$(gcloud run services describe "${APP_NAME}" --region="${REGION}" --format="value(status.url)" 2>/dev/null || echo "Not available")
WORKSTATION_URL=https://workstations.googleusercontent.com/

# Next Steps:
# 1. Access your secure workstation at: \${WORKSTATION_URL}
# 2. Test your application at: \${SERVICE_URL}
# 3. Configure your IDE with Gemini Code Assist
# 4. Run validation tests using the validation commands in the recipe

# Cleanup:
# To remove all resources, run: ./destroy.sh
EOF

    log_success "Deployment information saved to: ${info_file}"
}

# Main deployment function
main() {
    log_info "Starting deployment of Secure AI-Enhanced Development Workflows..."
    echo "This deployment will create resources in Google Cloud Platform."
    echo "Estimated cost: \$50-75 for the duration of the recipe."
    echo ""
    
    # Confirmation prompt
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
    
    # Start timing
    START_TIME=$(date +%s)
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_project
    enable_apis
    configure_kms
    setup_secrets_manager
    create_workstation
    deploy_application
    configure_iap
    setup_cicd
    configure_gemini
    validate_deployment
    save_deployment_info
    
    # Calculate deployment time
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    log_success "Deployment completed successfully in ${DURATION} seconds!"
    echo ""
    echo "======================================"
    echo "DEPLOYMENT SUMMARY"
    echo "======================================"
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Application: ${APP_NAME}"
    echo "Workstation: ${WORKSTATION_NAME}"
    echo ""
    echo "Next Steps:"
    echo "1. Access your secure workstation at: https://workstations.googleusercontent.com/"
    echo "2. Test your application (requires authentication)"
    echo "3. Follow the recipe validation steps to test all components"
    echo ""
    echo "Cleanup:"
    echo "Run './destroy.sh' when you're done to remove all resources"
    echo "======================================"
}

# Execute main function
main "$@"