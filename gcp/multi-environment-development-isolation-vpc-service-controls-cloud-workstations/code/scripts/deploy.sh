#!/bin/bash

#############################################################################
# Deployment Script for Multi-Environment Development Isolation
# with VPC Service Controls and Cloud Workstations
#
# This script creates secure, isolated development environments using:
# - VPC Service Controls for security perimeters
# - Cloud Workstations for managed development environments
# - Cloud Filestore for shared storage
# - Identity-Aware Proxy for secure access
#############################################################################

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

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup on script termination
cleanup() {
    if [[ -f "internal_users_spec.yaml" ]]; then
        rm -f internal_users_spec.yaml
    fi
    if [[ -f "dev-workstation-config.yaml" ]]; then
        rm -f dev-workstation-config.yaml
    fi
    if [[ -f "test-workstation-config.yaml" ]]; then
        rm -f test-workstation-config.yaml
    fi
    if [[ -f "prod-workstation-config.yaml" ]]; then
        rm -f prod-workstation-config.yaml
    fi
}
trap cleanup EXIT

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment_$(date +%Y%m%d_%H%M%S).log"

# Default values
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
DEFAULT_DOMAIN="yourdomain.com"

echo "================================================"
echo "Multi-Environment Development Isolation Deployment"
echo "================================================"
echo

# Check if running in interactive mode
if [[ -t 0 ]]; then
    INTERACTIVE=true
else
    INTERACTIVE=false
fi

# Function to prompt for input with default value
prompt_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    if [[ "$INTERACTIVE" == true ]]; then
        read -p "${prompt} [${default}]: " input
        if [[ -z "$input" ]]; then
            declare -g "${var_name}=${default}"
        else
            declare -g "${var_name}=${input}"
        fi
    else
        declare -g "${var_name}=${default}"
        log_info "Using default value for ${var_name}: ${default}"
    fi
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        error_exit "Please authenticate with 'gcloud auth login' first."
    fi
    
    # Check for required APIs (will be enabled during deployment)
    log_info "Google Cloud CLI found and authenticated."
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is required for random string generation."
    fi
    
    log_success "Prerequisites check completed."
}

# Get user inputs
get_configuration() {
    log_info "Gathering configuration..."
    
    # Get organization ID
    if [[ "$INTERACTIVE" == true ]]; then
        echo "Please provide your Google Cloud Organization ID:"
        read -p "Organization ID: " ORGANIZATION_ID
        if [[ -z "$ORGANIZATION_ID" ]]; then
            error_exit "Organization ID is required for VPC Service Controls."
        fi
    else
        # Try to detect organization ID
        ORGANIZATION_ID=$(gcloud organizations list --format="value(name)" | head -n1)
        if [[ -z "$ORGANIZATION_ID" ]]; then
            error_exit "Could not detect Organization ID. Please run with manual configuration."
        fi
        log_info "Detected Organization ID: $ORGANIZATION_ID"
    fi
    
    # Get billing account ID
    if [[ "$INTERACTIVE" == true ]]; then
        echo "Please provide your Billing Account ID:"
        read -p "Billing Account ID: " BILLING_ACCOUNT_ID
        if [[ -z "$BILLING_ACCOUNT_ID" ]]; then
            error_exit "Billing Account ID is required."
        fi
    else
        # Try to detect billing account
        BILLING_ACCOUNT_ID=$(gcloud billing accounts list --format="value(name)" | head -n1)
        if [[ -z "$BILLING_ACCOUNT_ID" ]]; then
            error_exit "Could not detect Billing Account ID. Please run with manual configuration."
        fi
        log_info "Detected Billing Account ID: $BILLING_ACCOUNT_ID"
    fi
    
    # Other configuration
    prompt_input "Enter the region for resources" "$DEFAULT_REGION" "REGION"
    prompt_input "Enter the zone for resources" "$DEFAULT_ZONE" "ZONE"
    prompt_input "Enter your domain for IAP configuration" "$DEFAULT_DOMAIN" "DOMAIN"
    
    # Generate project names
    PROJECT_SUFFIX="$(date +%s)-$(openssl rand -hex 3)"
    export PROJECT_ID="secure-dev-environments-${PROJECT_SUFFIX}"
    export DEV_PROJECT_ID="${PROJECT_ID}-dev"
    export TEST_PROJECT_ID="${PROJECT_ID}-test"
    export PROD_PROJECT_ID="${PROJECT_ID}-prod"
    
    log_info "Configuration completed:"
    log_info "  Organization ID: $ORGANIZATION_ID"
    log_info "  Billing Account: $BILLING_ACCOUNT_ID"
    log_info "  Region: $REGION"
    log_info "  Zone: $ZONE"
    log_info "  Domain: $DOMAIN"
    log_info "  Dev Project: $DEV_PROJECT_ID"
    log_info "  Test Project: $TEST_PROJECT_ID"
    log_info "  Prod Project: $PROD_PROJECT_ID"
}

# Create projects
create_projects() {
    log_info "Creating Google Cloud projects..."
    
    # Create projects
    for PROJECT_ENV in "dev" "test" "prod"; do
        PROJECT_NAME="${PROJECT_ID}-${PROJECT_ENV}"
        ENV_DISPLAY_NAME=$(echo "$PROJECT_ENV" | sed 's/./\U&/')
        
        log_info "Creating project: $PROJECT_NAME"
        if gcloud projects create "$PROJECT_NAME" \
            --organization="$ORGANIZATION_ID" \
            --name="${ENV_DISPLAY_NAME} Environment" 2>> "$LOG_FILE"; then
            log_success "Created project: $PROJECT_NAME"
        else
            error_exit "Failed to create project: $PROJECT_NAME"
        fi
        
        # Link billing account
        log_info "Linking billing account to $PROJECT_NAME"
        if gcloud billing projects link "$PROJECT_NAME" \
            --billing-account="$BILLING_ACCOUNT_ID" 2>> "$LOG_FILE"; then
            log_success "Linked billing account to $PROJECT_NAME"
        else
            error_exit "Failed to link billing account to $PROJECT_NAME"
        fi
    done
    
    log_success "All projects created and billing linked."
}

# Enable APIs
enable_apis() {
    log_info "Enabling required APIs for all projects..."
    
    local apis=(
        "compute.googleapis.com"
        "workstations.googleapis.com"
        "file.googleapis.com"
        "iap.googleapis.com"
        "accesscontextmanager.googleapis.com"
        "sourcerepo.googleapis.com"
    )
    
    for PROJECT in "$DEV_PROJECT_ID" "$TEST_PROJECT_ID" "$PROD_PROJECT_ID"; do
        log_info "Enabling APIs for $PROJECT"
        for api in "${apis[@]}"; do
            if gcloud services enable "$api" --project="$PROJECT" 2>> "$LOG_FILE"; then
                log_info "  Enabled: $api"
            else
                log_warn "  Failed to enable: $api (may already be enabled)"
            fi
        done
    done
    
    log_success "API enablement completed."
}

# Create Access Context Manager policy
create_access_policy() {
    log_info "Creating Access Context Manager policy..."
    
    # Create access context manager policy
    if gcloud access-context-manager policies create \
        --organization="$ORGANIZATION_ID" \
        --title="Multi-Environment Security Policy" 2>> "$LOG_FILE"; then
        log_success "Created Access Context Manager policy"
    else
        error_exit "Failed to create Access Context Manager policy"
    fi
    
    # Get the policy ID
    POLICY_ID=$(gcloud access-context-manager policies list \
        --organization="$ORGANIZATION_ID" \
        --format="value(name)" \
        --filter="title:'Multi-Environment Security Policy'")
    
    if [[ -z "$POLICY_ID" ]]; then
        error_exit "Failed to retrieve policy ID"
    fi
    
    log_info "Policy ID: $POLICY_ID"
    
    # Create access level specification file
    cat > internal_users_spec.yaml << EOF
conditions:
- members:
  - user:dev-team@${DOMAIN}
  - user:admin@${DOMAIN}
EOF
    
    # Create access level
    log_info "Creating access level for internal users..."
    if gcloud access-context-manager levels create internal_users \
        --policy="$POLICY_ID" \
        --title="Internal Users Access Level" \
        --basic-level-spec=internal_users_spec.yaml 2>> "$LOG_FILE"; then
        log_success "Created internal users access level"
    else
        error_exit "Failed to create access level"
    fi
    
    export POLICY_ID
}

# Create VPC networks
create_vpc_networks() {
    log_info "Creating VPC networks for each environment..."
    
    for PROJECT_ENV in "dev" "test" "prod"; do
        PROJECT_NAME="${PROJECT_ID}-${PROJECT_ENV}"
        VPC_NAME="${PROJECT_ENV}-vpc"
        SUBNET_NAME="${PROJECT_ENV}-subnet"
        
        # IP ranges for each environment
        case $PROJECT_ENV in
            "dev") SUBNET_RANGE="10.1.0.0/24" ;;
            "test") SUBNET_RANGE="10.2.0.0/24" ;;
            "prod") SUBNET_RANGE="10.3.0.0/24" ;;
        esac
        
        log_info "Creating VPC network: $VPC_NAME in $PROJECT_NAME"
        if gcloud compute networks create "$VPC_NAME" \
            --subnet-mode=regional \
            --project="$PROJECT_NAME" 2>> "$LOG_FILE"; then
            log_success "Created VPC: $VPC_NAME"
        else
            error_exit "Failed to create VPC: $VPC_NAME"
        fi
        
        log_info "Creating subnet: $SUBNET_NAME"
        if gcloud compute networks subnets create "$SUBNET_NAME" \
            --network="$VPC_NAME" \
            --range="$SUBNET_RANGE" \
            --region="$REGION" \
            --project="$PROJECT_NAME" 2>> "$LOG_FILE"; then
            log_success "Created subnet: $SUBNET_NAME"
        else
            error_exit "Failed to create subnet: $SUBNET_NAME"
        fi
        
        # Enable Private Google Access
        log_info "Enabling Private Google Access for $SUBNET_NAME"
        if gcloud compute networks subnets update "$SUBNET_NAME" \
            --region="$REGION" \
            --enable-private-ip-google-access \
            --project="$PROJECT_NAME" 2>> "$LOG_FILE"; then
            log_success "Enabled Private Google Access for $SUBNET_NAME"
        else
            log_warn "Failed to enable Private Google Access for $SUBNET_NAME"
        fi
    done
    
    log_success "VPC networks and subnets created for all environments."
}

# Create VPC Service Controls perimeters
create_service_perimeters() {
    log_info "Creating VPC Service Controls perimeters..."
    
    local restricted_services="storage.googleapis.com,compute.googleapis.com,workstations.googleapis.com,file.googleapis.com"
    local access_level="accessPolicies/${POLICY_ID}/accessLevels/internal_users"
    
    for PROJECT_ENV in "dev" "test" "prod"; do
        PROJECT_NAME="${PROJECT_ID}-${PROJECT_ENV}"
        PERIMETER_NAME="${PROJECT_ENV}-perimeter"
        
        log_info "Creating service perimeter: $PERIMETER_NAME"
        if gcloud access-context-manager perimeters create "$PERIMETER_NAME" \
            --policy="$POLICY_ID" \
            --title="${PROJECT_ENV^} Environment Perimeter" \
            --perimeter-type=regular \
            --resources="projects/$PROJECT_NAME" \
            --restricted-services="$restricted_services" \
            --access-levels="$access_level" 2>> "$LOG_FILE"; then
            log_success "Created service perimeter: $PERIMETER_NAME"
        else
            error_exit "Failed to create service perimeter: $PERIMETER_NAME"
        fi
    done
    
    log_success "VPC Service Controls perimeters created for all environments."
}

# Create Cloud Filestore instances
create_filestore_instances() {
    log_info "Creating Cloud Filestore instances..."
    
    for PROJECT_ENV in "dev" "test" "prod"; do
        PROJECT_NAME="${PROJECT_ID}-${PROJECT_ENV}"
        FILESTORE_NAME="${PROJECT_ENV}-filestore"
        VPC_NAME="${PROJECT_ENV}-vpc"
        SHARE_NAME="${PROJECT_ENV}_share"
        
        log_info "Creating Filestore instance: $FILESTORE_NAME"
        if gcloud filestore instances create "$FILESTORE_NAME" \
            --location="$ZONE" \
            --tier=BASIC_SSD \
            --file-share=name="$SHARE_NAME",capacity=1TB \
            --network=name="$VPC_NAME" \
            --project="$PROJECT_NAME" 2>> "$LOG_FILE"; then
            log_success "Created Filestore instance: $FILESTORE_NAME"
        else
            error_exit "Failed to create Filestore instance: $FILESTORE_NAME"
        fi
    done
    
    # Get IP addresses
    log_info "Retrieving Filestore IP addresses..."
    DEV_FILESTORE_IP=$(gcloud filestore instances describe dev-filestore \
        --location="$ZONE" \
        --project="$DEV_PROJECT_ID" \
        --format="value(networks.ipAddresses[0])")
    
    TEST_FILESTORE_IP=$(gcloud filestore instances describe test-filestore \
        --location="$ZONE" \
        --project="$TEST_PROJECT_ID" \
        --format="value(networks.ipAddresses[0])")
    
    PROD_FILESTORE_IP=$(gcloud filestore instances describe prod-filestore \
        --location="$ZONE" \
        --project="$PROD_PROJECT_ID" \
        --format="value(networks.ipAddresses[0])")
    
    log_info "Filestore IP addresses:"
    log_info "  Development: $DEV_FILESTORE_IP"
    log_info "  Testing: $TEST_FILESTORE_IP"
    log_info "  Production: $PROD_FILESTORE_IP"
    
    export DEV_FILESTORE_IP TEST_FILESTORE_IP PROD_FILESTORE_IP
}

# Create Cloud Source Repositories
create_source_repositories() {
    log_info "Creating Cloud Source Repositories..."
    
    for PROJECT_ENV in "dev" "test" "prod"; do
        PROJECT_NAME="${PROJECT_ID}-${PROJECT_ENV}"
        REPO_NAME="${PROJECT_ENV}-repo"
        
        log_info "Creating source repository: $REPO_NAME"
        if gcloud source repos create "$REPO_NAME" \
            --project="$PROJECT_NAME" 2>> "$LOG_FILE"; then
            log_success "Created source repository: $REPO_NAME"
        else
            error_exit "Failed to create source repository: $REPO_NAME"
        fi
    done
    
    log_success "Cloud Source Repositories created for all environments."
}

# Create Cloud Workstations clusters and configurations
create_workstations() {
    log_info "Creating Cloud Workstations clusters and configurations..."
    
    for PROJECT_ENV in "dev" "test" "prod"; do
        PROJECT_NAME="${PROJECT_ID}-${PROJECT_ENV}"
        CLUSTER_NAME="${PROJECT_ENV}-cluster"
        CONFIG_NAME="${PROJECT_ENV}-workstation-config"
        VPC_NAME="${PROJECT_ENV}-vpc"
        SUBNET_NAME="${PROJECT_ENV}-subnet"
        
        # Get the Filestore IP for this environment
        case $PROJECT_ENV in
            "dev") FILESTORE_IP="$DEV_FILESTORE_IP" ;;
            "test") FILESTORE_IP="$TEST_FILESTORE_IP" ;;
            "prod") FILESTORE_IP="$PROD_FILESTORE_IP" ;;
        esac
        
        log_info "Creating workstation cluster: $CLUSTER_NAME"
        if gcloud workstations clusters create "$CLUSTER_NAME" \
            --location="$REGION" \
            --network="projects/$PROJECT_NAME/global/networks/$VPC_NAME" \
            --subnetwork="projects/$PROJECT_NAME/regions/$REGION/subnetworks/$SUBNET_NAME" \
            --project="$PROJECT_NAME" 2>> "$LOG_FILE"; then
            log_success "Created workstation cluster: $CLUSTER_NAME"
        else
            error_exit "Failed to create workstation cluster: $CLUSTER_NAME"
        fi
    done
    
    # Wait for clusters to be ready
    log_info "Waiting for workstation clusters to be ready..."
    sleep 60
    
    # Create workstation configurations
    for PROJECT_ENV in "dev" "test" "prod"; do
        PROJECT_NAME="${PROJECT_ID}-${PROJECT_ENV}"
        CLUSTER_NAME="${PROJECT_ENV}-cluster"
        CONFIG_NAME="${PROJECT_ENV}-workstation-config"
        
        # Get the Filestore IP for this environment
        case $PROJECT_ENV in
            "dev") FILESTORE_IP="$DEV_FILESTORE_IP" ;;
            "test") FILESTORE_IP="$TEST_FILESTORE_IP" ;;
            "prod") FILESTORE_IP="$PROD_FILESTORE_IP" ;;
        esac
        
        # Create workstation configuration file
        cat > "${PROJECT_ENV}-workstation-config.yaml" << EOF
name: ${CONFIG_NAME}
container:
  image: us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest
  env:
    FILESTORE_IP: "${FILESTORE_IP}"
persistentDirectories:
  - gcePersistentDisk:
      sizeGb: 50
      fsType: ext4
    mountPath: /home
host:
  gceInstance:
    machineType: e2-standard-4
    bootDiskSizeGb: 50
EOF
        
        log_info "Creating workstation configuration: $CONFIG_NAME"
        if gcloud workstations configs create "$CONFIG_NAME" \
            --location="$REGION" \
            --cluster="$CLUSTER_NAME" \
            --config-file="${PROJECT_ENV}-workstation-config.yaml" \
            --project="$PROJECT_NAME" 2>> "$LOG_FILE"; then
            log_success "Created workstation configuration: $CONFIG_NAME"
        else
            error_exit "Failed to create workstation configuration: $CONFIG_NAME"
        fi
    done
    
    log_success "Cloud Workstations clusters and configurations created."
}

# Configure Identity-Aware Proxy
configure_iap() {
    log_info "Configuring Identity-Aware Proxy..."
    
    for PROJECT in "$DEV_PROJECT_ID" "$TEST_PROJECT_ID" "$PROD_PROJECT_ID"; do
        log_info "Configuring IAP for $PROJECT"
        
        # Grant IAP access to development team
        if gcloud projects add-iam-policy-binding "$PROJECT" \
            --member="user:dev-team@$DOMAIN" \
            --role="roles/iap.httpsResourceAccessor" 2>> "$LOG_FILE"; then
            log_info "  Granted IAP access to dev-team@$DOMAIN"
        else
            log_warn "  Failed to grant IAP access to dev-team@$DOMAIN"
        fi
        
        if gcloud projects add-iam-policy-binding "$PROJECT" \
            --member="user:admin@$DOMAIN" \
            --role="roles/iap.httpsResourceAccessor" 2>> "$LOG_FILE"; then
            log_info "  Granted IAP access to admin@$DOMAIN"
        else
            log_warn "  Failed to grant IAP access to admin@$DOMAIN"
        fi
    done
    
    log_success "Identity-Aware Proxy configured for all environments."
}

# Create sample workstations
create_sample_workstations() {
    log_info "Creating sample workstations..."
    
    for PROJECT_ENV in "dev" "test" "prod"; do
        PROJECT_NAME="${PROJECT_ID}-${PROJECT_ENV}"
        CLUSTER_NAME="${PROJECT_ENV}-cluster"
        CONFIG_NAME="${PROJECT_ENV}-workstation-config"
        WORKSTATION_NAME="${PROJECT_ENV}-workstation-1"
        
        log_info "Creating workstation: $WORKSTATION_NAME"
        if gcloud workstations create "$WORKSTATION_NAME" \
            --location="$REGION" \
            --cluster="$CLUSTER_NAME" \
            --config="$CONFIG_NAME" \
            --project="$PROJECT_NAME" 2>> "$LOG_FILE"; then
            log_success "Created workstation: $WORKSTATION_NAME"
        else
            log_warn "Failed to create workstation: $WORKSTATION_NAME"
        fi
    done
    
    log_success "Sample workstations created for all environments."
}

# Save deployment information
save_deployment_info() {
    local info_file="${SCRIPT_DIR}/deployment_info.txt"
    
    cat > "$info_file" << EOF
Multi-Environment Development Isolation Deployment Information
============================================================

Deployment Date: $(date)
Organization ID: $ORGANIZATION_ID
Billing Account: $BILLING_ACCOUNT_ID
Region: $REGION
Zone: $ZONE
Domain: $DOMAIN

Projects:
- Development: $DEV_PROJECT_ID
- Testing: $TEST_PROJECT_ID
- Production: $PROD_PROJECT_ID

Policy ID: $POLICY_ID

Filestore IP Addresses:
- Development: $DEV_FILESTORE_IP
- Testing: $TEST_FILESTORE_IP
- Production: $PROD_FILESTORE_IP

Access Instructions:
==================

1. Access workstations via Google Cloud Console:
   https://console.cloud.google.com/workstations

2. Or use gcloud CLI:
   gcloud workstations ssh dev-workstation-1 \\
     --location=$REGION \\
     --cluster=dev-cluster \\
     --config=dev-workstation-config \\
     --project=$DEV_PROJECT_ID

3. Mount Filestore in workstation:
   sudo mount -t nfs $DEV_FILESTORE_IP:/dev_share /mnt/filestore

Important Notes:
===============
- VPC Service Controls perimeters are active and preventing data exfiltration
- IAP is configured for secure access
- Each environment is completely isolated
- Cleanup script is available at: ${SCRIPT_DIR}/destroy.sh

EOF
    
    log_success "Deployment information saved to: $info_file"
}

# Main execution
main() {
    echo "Starting deployment at $(date)" >> "$LOG_FILE"
    
    check_prerequisites
    get_configuration
    
    log_info "Starting deployment of multi-environment development isolation..."
    
    create_projects
    enable_apis
    create_access_policy
    create_vpc_networks
    create_service_perimeters
    create_filestore_instances
    create_source_repositories
    create_workstations
    configure_iap
    create_sample_workstations
    save_deployment_info
    
    echo
    log_success "============================================"
    log_success "Deployment completed successfully!"
    log_success "============================================"
    echo
    log_info "Key Information:"
    log_info "  Development Project: $DEV_PROJECT_ID"
    log_info "  Testing Project: $TEST_PROJECT_ID"
    log_info "  Production Project: $PROD_PROJECT_ID"
    log_info "  Policy ID: $POLICY_ID"
    echo
    log_info "Next Steps:"
    log_info "  1. Access workstations via Google Cloud Console"
    log_info "  2. Configure your development environment"
    log_info "  3. Test environment isolation"
    echo
    log_info "For cleanup, run: ${SCRIPT_DIR}/destroy.sh"
    log_info "Deployment log: $LOG_FILE"
    log_info "Deployment info: ${SCRIPT_DIR}/deployment_info.txt"
}

# Run main function
main "$@"