#!/bin/bash

# Enterprise Identity Federation Workflows with Cloud IAM and Service Directory
# Deployment Script for GCP
# 
# This script automates the deployment of an enterprise identity federation system
# using Google Cloud's Workload Identity Federation, Service Directory, Secret Manager,
# and Cloud Functions for automated provisioning workflows.

set -euo pipefail

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -1 >/dev/null 2>&1; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if curl is available (for function testing)
    if ! command_exists curl; then
        log_warning "curl is not available. Function testing will be skipped."
    fi
    
    # Check if openssl is available (for random suffix generation)
    if ! command_exists openssl; then
        log_error "openssl is required for generating random suffixes"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Prompt for project ID if not set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        read -p "Enter your Google Cloud Project ID: " PROJECT_ID
        export PROJECT_ID
    fi
    
    # Set default region and zone
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RANDOM_SUFFIX
    
    # Set identity federation specific variables
    export WI_POOL_ID="enterprise-pool-${RANDOM_SUFFIX}"
    export WI_PROVIDER_ID="oidc-provider-${RANDOM_SUFFIX}"
    export SERVICE_ACCOUNT_NAME="federation-sa-${RANDOM_SUFFIX}"
    export NAMESPACE_NAME="enterprise-services-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="identity-provisioner-${RANDOM_SUFFIX}"
    
    # Configure gcloud defaults
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_info "Environment configured for project: ${PROJECT_ID}"
    log_info "Region: ${REGION}, Zone: ${ZONE}"
    log_info "Random suffix: ${RANDOM_SUFFIX}"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "iamcredentials.googleapis.com"
        "sts.googleapis.com"
        "servicedirectory.googleapis.com"
        "cloudfunctions.googleapis.com"
        "secretmanager.googleapis.com"
        "cloudbuild.googleapis.com"
        "dns.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling API: ${api}"
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled API: ${api}"
        else
            log_error "Failed to enable API: ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    sleep 10
    log_success "All required APIs enabled"
}

# Function to create workload identity pool
create_workload_identity_pool() {
    log_info "Creating Workload Identity Pool..."
    
    if gcloud iam workload-identity-pools create "${WI_POOL_ID}" \
        --location="global" \
        --description="Enterprise identity federation pool" \
        --display-name="Enterprise Pool" \
        --quiet; then
        
        # Get the pool resource name
        export POOL_RESOURCE_NAME=$(gcloud iam workload-identity-pools \
            describe "${WI_POOL_ID}" \
            --location="global" \
            --format="value(name)")
        
        log_success "Workload Identity Pool created: ${POOL_RESOURCE_NAME}"
    else
        log_error "Failed to create Workload Identity Pool"
        exit 1
    fi
}

# Function to configure OIDC provider
configure_oidc_provider() {
    log_info "Configuring OIDC Provider..."
    
    if gcloud iam workload-identity-pools providers create-oidc \
        "${WI_PROVIDER_ID}" \
        --workload-identity-pool="${WI_POOL_ID}" \
        --location="global" \
        --issuer-uri="https://token.actions.githubusercontent.com" \
        --allowed-audiences="sts.googleapis.com" \
        --attribute-mapping="google.subject=assertion.sub" \
        --attribute-mapping="attribute.repository=assertion.repository" \
        --attribute-mapping="attribute.actor=assertion.actor" \
        --quiet; then
        
        # Get provider resource name
        export PROVIDER_RESOURCE_NAME=$(gcloud iam workload-identity-pools \
            providers describe "${WI_PROVIDER_ID}" \
            --workload-identity-pool="${WI_POOL_ID}" \
            --location="global" \
            --format="value(name)")
        
        log_success "OIDC Provider configured: ${PROVIDER_RESOURCE_NAME}"
    else
        log_error "Failed to configure OIDC Provider"
        exit 1
    fi
}

# Function to create service accounts
create_service_accounts() {
    log_info "Creating service accounts..."
    
    # Create main service account for federated access
    if gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
        --description="Service account for identity federation" \
        --display-name="Federation Service Account" \
        --quiet; then
        
        export SA_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
        log_success "Main service account created: ${SA_EMAIL}"
    else
        log_error "Failed to create main service account"
        exit 1
    fi
    
    # Create additional service accounts for different access levels
    local additional_accounts=("read-only-sa-${RANDOM_SUFFIX}" "admin-sa-${RANDOM_SUFFIX}")
    
    for account in "${additional_accounts[@]}"; do
        if gcloud iam service-accounts create "${account}" \
            --description="Service account for ${account} access" \
            --quiet; then
            log_success "Created service account: ${account}"
        else
            log_warning "Failed to create service account: ${account}, continuing..."
        fi
    done
}

# Function to configure IAM bindings
configure_iam_bindings() {
    log_info "Configuring IAM bindings for Workload Identity Federation..."
    
    # Allow federated identities to impersonate service account
    if gcloud iam service-accounts add-iam-policy-binding \
        "${SA_EMAIL}" \
        --role="roles/iam.workloadIdentityUser" \
        --member="principalSet://iam.googleapis.com/${POOL_RESOURCE_NAME}/attribute.repository/${PROJECT_ID}" \
        --quiet; then
        log_success "Configured workload identity user binding"
    else
        log_error "Failed to configure workload identity user binding"
        exit 1
    fi
    
    # Grant service account permissions to access resources
    local roles=("roles/servicedirectory.editor" "roles/secretmanager.secretAccessor")
    
    for role in "${roles[@]}"; do
        if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${SA_EMAIL}" \
            --role="${role}" \
            --quiet; then
            log_success "Granted role ${role} to service account"
        else
            log_error "Failed to grant role ${role}"
            exit 1
        fi
    done
}

# Function to create Service Directory resources
create_service_directory() {
    log_info "Creating Service Directory namespace and services..."
    
    # Create Service Directory namespace
    if gcloud service-directory namespaces create "${NAMESPACE_NAME}" \
        --location="${REGION}" \
        --description="Enterprise services namespace" \
        --quiet; then
        log_success "Service Directory namespace created: ${NAMESPACE_NAME}"
    else
        log_error "Failed to create Service Directory namespace"
        exit 1
    fi
    
    # Create services in the namespace
    local services=("user-management" "identity-provider" "resource-manager")
    
    for service in "${services[@]}"; do
        if gcloud service-directory services create "${service}" \
            --namespace="${NAMESPACE_NAME}" \
            --location="${REGION}" \
            --metadata="version=v1,environment=production" \
            --quiet; then
            log_success "Created service: ${service}"
        else
            log_warning "Failed to create service: ${service}, continuing..."
        fi
    done
}

# Function to store configuration secrets
store_secrets() {
    log_info "Storing configuration secrets in Secret Manager..."
    
    # Create federation configuration secret
    local federation_config="{
        \"pool_id\": \"${WI_POOL_ID}\",
        \"provider_id\": \"${WI_PROVIDER_ID}\",
        \"service_account_email\": \"${SA_EMAIL}\",
        \"namespace\": \"${NAMESPACE_NAME}\"
    }"
    
    if echo "${federation_config}" | gcloud secrets create "federation-config-${RANDOM_SUFFIX}" \
        --data-file=- \
        --quiet; then
        log_success "Federation configuration secret created"
    else
        log_error "Failed to create federation configuration secret"
        exit 1
    fi
    
    # Create IdP configuration secret
    local idp_config="{
        \"issuer_url\": \"https://token.actions.githubusercontent.com\",
        \"audience\": \"sts.googleapis.com\",
        \"allowed_repos\": [\"${PROJECT_ID}\"]
    }"
    
    if echo "${idp_config}" | gcloud secrets create "idp-config-${RANDOM_SUFFIX}" \
        --data-file=- \
        --quiet; then
        log_success "IdP configuration secret created"
    else
        log_error "Failed to create IdP configuration secret"
        exit 1
    fi
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    log_info "Deploying Cloud Function for automated identity provisioning..."
    
    # Create temporary directory for function source
    local function_dir="./identity-provisioner-${RANDOM_SUFFIX}"
    mkdir -p "${function_dir}"
    
    # Create main.py for the Cloud Function
    cat > "${function_dir}/main.py" << 'EOF'
import json
import logging
import os
from datetime import datetime
from google.cloud import secretmanager
from google.cloud import servicedirectory
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def provision_identity(request):
    """Automated identity provisioning workflow"""
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return {'error': 'Invalid request format'}, 400
        
        user_identity = request_json.get('identity')
        service_name = request_json.get('service')
        access_level = request_json.get('access_level', 'read-only')
        
        if not user_identity or not service_name:
            return {'error': 'Missing required fields: identity and service'}, 400
        
        # Initialize clients
        secret_client = secretmanager.SecretManagerServiceClient()
        service_client = servicedirectory.ServiceDirectoryServiceClient()
        
        # Retrieve federation configuration
        project_id = os.environ.get('GCP_PROJECT')
        region = os.environ.get('REGION')
        
        logger.info(f"Provisioning identity for user: {user_identity}")
        logger.info(f"Service: {service_name}, Access Level: {access_level}")
        
        # Simulate service registration (actual implementation would register endpoints)
        response_data = {
            'status': 'success',
            'user_identity': user_identity,
            'service': service_name,
            'access_level': access_level,
            'provisioned_at': datetime.utcnow().isoformat(),
            'project_id': project_id,
            'region': region
        }
        
        logger.info("Identity provisioning completed successfully")
        return response_data, 200
        
    except Exception as e:
        logger.error(f"Provisioning failed: {str(e)}")
        return {'error': str(e)}, 500
EOF
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
google-cloud-secret-manager==2.16.4
google-cloud-service-directory==1.8.1
google-cloud-iam==2.12.1
functions-framework==3.4.0
EOF
    
    # Deploy the Cloud Function
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source "${function_dir}" \
        --entry-point provision_identity \
        --memory 256MB \
        --timeout 60s \
        --set-env-vars "GCP_PROJECT=${PROJECT_ID},REGION=${REGION}" \
        --quiet; then
        
        log_success "Cloud Function deployed: ${FUNCTION_NAME}"
        
        # Get function URL
        export FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
            --format="value(httpsTrigger.url)")
        log_info "Function URL: ${FUNCTION_URL}"
    else
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi
    
    # Clean up temporary directory
    rm -rf "${function_dir}"
}

# Function to configure DNS integration
configure_dns_integration() {
    log_info "Configuring DNS integration for service discovery..."
    
    # Create DNS zone for service discovery
    if gcloud dns managed-zones create "enterprise-services-${RANDOM_SUFFIX}" \
        --dns-name="services.${PROJECT_ID}.internal." \
        --description="DNS zone for enterprise service discovery" \
        --visibility=private \
        --networks=default \
        --quiet; then
        log_success "DNS zone created for service discovery"
    else
        log_warning "Failed to create DNS zone, continuing without DNS integration..."
        return 0
    fi
    
    # Configure Service Directory DNS integration
    if gcloud service-directory namespaces update "${NAMESPACE_NAME}" \
        --location="${REGION}" \
        --dns-zone="projects/${PROJECT_ID}/managedZones/enterprise-services-${RANDOM_SUFFIX}" \
        --quiet; then
        log_success "Service Directory DNS integration configured"
    else
        log_warning "Failed to configure DNS integration, continuing..."
    fi
}

# Function to run validation tests
run_validation() {
    log_info "Running validation tests..."
    
    # Check workload identity pool status
    if gcloud iam workload-identity-pools describe "${WI_POOL_ID}" \
        --location="global" \
        --format="value(state)" | grep -q "ACTIVE"; then
        log_success "Workload Identity Pool is active"
    else
        log_warning "Workload Identity Pool may not be fully active yet"
    fi
    
    # Check service directory services
    local service_count=$(gcloud service-directory services list \
        --namespace="${NAMESPACE_NAME}" \
        --location="${REGION}" \
        --format="value(name)" | wc -l)
    
    if [[ ${service_count} -gt 0 ]]; then
        log_success "Service Directory contains ${service_count} services"
    else
        log_warning "No services found in Service Directory"
    fi
    
    # Test Cloud Function if curl is available
    if command_exists curl && [[ -n "${FUNCTION_URL:-}" ]]; then
        log_info "Testing Cloud Function..."
        if curl -s -X POST "${FUNCTION_URL}" \
            -H "Content-Type: application/json" \
            -d '{"identity":"test-user@example.com","service":"user-management","access_level":"read-only"}' \
            | grep -q "success"; then
            log_success "Cloud Function test passed"
        else
            log_warning "Cloud Function test failed or returned unexpected result"
        fi
    fi
}

# Function to save deployment information
save_deployment_info() {
    local info_file="deployment-info-${RANDOM_SUFFIX}.txt"
    
    cat > "${info_file}" << EOF
Enterprise Identity Federation Deployment Information
=====================================================
Deployment Date: $(date)
Project ID: ${PROJECT_ID}
Region: ${REGION}
Random Suffix: ${RANDOM_SUFFIX}

Resources Created:
- Workload Identity Pool: ${WI_POOL_ID}
- OIDC Provider: ${WI_PROVIDER_ID}
- Service Account: ${SERVICE_ACCOUNT_NAME}
- Service Directory Namespace: ${NAMESPACE_NAME}
- Cloud Function: ${FUNCTION_NAME}
- DNS Zone: enterprise-services-${RANDOM_SUFFIX}

Resource Names:
- Pool Resource: ${POOL_RESOURCE_NAME:-}
- Provider Resource: ${PROVIDER_RESOURCE_NAME:-}
- Service Account Email: ${SA_EMAIL:-}
- Function URL: ${FUNCTION_URL:-}

Secrets Created:
- federation-config-${RANDOM_SUFFIX}
- idp-config-${RANDOM_SUFFIX}

Cleanup Command:
./destroy.sh ${RANDOM_SUFFIX}
EOF
    
    log_success "Deployment information saved to: ${info_file}"
    log_info "Keep this file for cleanup reference"
}

# Main deployment function
main() {
    log_info "Starting Enterprise Identity Federation deployment..."
    
    check_prerequisites
    setup_environment
    enable_apis
    create_workload_identity_pool
    configure_oidc_provider
    create_service_accounts
    configure_iam_bindings
    create_service_directory
    store_secrets
    deploy_cloud_function
    configure_dns_integration
    run_validation
    save_deployment_info
    
    log_success "========================================="
    log_success "Enterprise Identity Federation deployment completed successfully!"
    log_success "========================================="
    log_info "Project: ${PROJECT_ID}"
    log_info "Random Suffix: ${RANDOM_SUFFIX}"
    log_info "Workload Identity Pool: ${WI_POOL_ID}"
    log_info "Service Account: ${SA_EMAIL}"
    log_info "Cloud Function: ${FUNCTION_NAME}"
    if [[ -n "${FUNCTION_URL:-}" ]]; then
        log_info "Function URL: ${FUNCTION_URL}"
    fi
    log_warning "Remember to save the random suffix (${RANDOM_SUFFIX}) for cleanup!"
}

# Trap to handle script interruption
trap 'log_error "Script interrupted. Some resources may have been created."; exit 1' INT TERM

# Run main function
main "$@"