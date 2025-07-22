#!/bin/bash

# Azure Data Share and Purview Cross-Tenant Deployment Script
# This script deploys the complete infrastructure for cross-tenant data collaboration

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if Azure CLI is installed and logged in
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from https://aka.ms/InstallAzureCLI"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is required for random string generation. Please install it."
    fi
    
    log_success "Prerequisites check passed"
}

# Validate environment variables
validate_environment() {
    log_info "Validating environment variables..."
    
    # Check required environment variables
    local required_vars=(
        "PROVIDER_SUBSCRIPTION_ID"
        "CONSUMER_SUBSCRIPTION_ID"
        "LOCATION"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            error_exit "Environment variable $var is required but not set"
        fi
    done
    
    # Validate subscription IDs format (basic UUID format check)
    if [[ ! $PROVIDER_SUBSCRIPTION_ID =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        error_exit "PROVIDER_SUBSCRIPTION_ID must be a valid UUID format"
    fi
    
    if [[ ! $CONSUMER_SUBSCRIPTION_ID =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        error_exit "CONSUMER_SUBSCRIPTION_ID must be a valid UUID format"
    fi
    
    # Check if the specified location is valid
    if ! az account list-locations --query "[?name=='$LOCATION']" -o tsv | grep -q .; then
        error_exit "Location '$LOCATION' is not valid or not available"
    fi
    
    log_success "Environment validation passed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    export PROVIDER_RG="${PROVIDER_RG:-rg-datashare-provider}"
    export CONSUMER_RG="${CONSUMER_RG:-rg-datashare-consumer}"
    
    # Generate unique suffix for resource names
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    # Set resource names with unique suffix
    export PROVIDER_STORAGE="${PROVIDER_STORAGE:-stprovider${RANDOM_SUFFIX}}"
    export CONSUMER_STORAGE="${CONSUMER_STORAGE:-stconsumer${RANDOM_SUFFIX}}"
    export PROVIDER_SHARE="${PROVIDER_SHARE:-share-provider-${RANDOM_SUFFIX}}"
    export CONSUMER_SHARE="${CONSUMER_SHARE:-share-consumer-${RANDOM_SUFFIX}}"
    export PROVIDER_PURVIEW="${PROVIDER_PURVIEW:-purview-provider-${RANDOM_SUFFIX}}"
    export CONSUMER_PURVIEW="${CONSUMER_PURVIEW:-purview-consumer-${RANDOM_SUFFIX}}"
    
    # Log the configuration
    log_info "Configuration:"
    log_info "  Provider Subscription: $PROVIDER_SUBSCRIPTION_ID"
    log_info "  Consumer Subscription: $CONSUMER_SUBSCRIPTION_ID"
    log_info "  Location: $LOCATION"
    log_info "  Random Suffix: $RANDOM_SUFFIX"
    log_info "  Provider Resource Group: $PROVIDER_RG"
    log_info "  Consumer Resource Group: $CONSUMER_RG"
    
    log_success "Environment setup completed"
}

# Create provider infrastructure
create_provider_infrastructure() {
    log_info "Creating provider infrastructure..."
    
    # Set provider subscription
    az account set --subscription "${PROVIDER_SUBSCRIPTION_ID}"
    log_info "Switched to provider subscription: $PROVIDER_SUBSCRIPTION_ID"
    
    # Create provider resource group
    log_info "Creating provider resource group: $PROVIDER_RG"
    az group create \
        --name "${PROVIDER_RG}" \
        --location "${LOCATION}" \
        --tags purpose=datashare-demo environment=provider
    
    # Create provider storage account
    log_info "Creating provider storage account: $PROVIDER_STORAGE"
    az storage account create \
        --name "${PROVIDER_STORAGE}" \
        --resource-group "${PROVIDER_RG}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --hierarchical-namespace true \
        --https-only true \
        --min-tls-version TLS1_2
    
    # Wait for storage account to be ready
    sleep 30
    
    # Create container for shared data
    log_info "Creating shared-datasets container"
    az storage container create \
        --name shared-datasets \
        --account-name "${PROVIDER_STORAGE}" \
        --auth-mode login
    
    # Create Azure Data Share account
    log_info "Creating Azure Data Share account: $PROVIDER_SHARE"
    az datashare account create \
        --name "${PROVIDER_SHARE}" \
        --resource-group "${PROVIDER_RG}" \
        --location "${LOCATION}"
    
    log_success "Provider infrastructure created successfully"
}

# Deploy provider Purview instance
deploy_provider_purview() {
    log_info "Deploying provider Azure Purview instance..."
    
    # Create Purview account (this may take 5-10 minutes)
    log_info "Creating Purview account: $PROVIDER_PURVIEW (this may take 5-10 minutes)"
    az purview account create \
        --name "${PROVIDER_PURVIEW}" \
        --resource-group "${PROVIDER_RG}" \
        --location "${LOCATION}" \
        --sku Standard_4
    
    # Wait for Purview to be fully provisioned
    log_info "Waiting for Purview to be fully provisioned..."
    local timeout=600  # 10 minutes
    local elapsed=0
    local interval=30
    
    while [ $elapsed -lt $timeout ]; do
        local state=$(az purview account show \
            --name "${PROVIDER_PURVIEW}" \
            --resource-group "${PROVIDER_RG}" \
            --query provisioningState -o tsv 2>/dev/null || echo "NotFound")
        
        if [ "$state" = "Succeeded" ]; then
            log_success "Purview account is ready"
            break
        elif [ "$state" = "Failed" ]; then
            error_exit "Purview account creation failed"
        fi
        
        log_info "Purview state: $state. Waiting..."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    if [ $elapsed -ge $timeout ]; then
        error_exit "Timeout waiting for Purview account creation"
    fi
    
    # Get Purview managed identity
    log_info "Getting Purview managed identity"
    local provider_purview_identity=$(az purview account show \
        --name "${PROVIDER_PURVIEW}" \
        --resource-group "${PROVIDER_RG}" \
        --query identity.principalId -o tsv)
    
    if [ -z "$provider_purview_identity" ]; then
        error_exit "Failed to get Purview managed identity"
    fi
    
    # Grant Purview access to storage account
    log_info "Granting Purview access to storage account"
    az role assignment create \
        --role "Storage Blob Data Reader" \
        --assignee "${provider_purview_identity}" \
        --scope "/subscriptions/${PROVIDER_SUBSCRIPTION_ID}/resourceGroups/${PROVIDER_RG}/providers/Microsoft.Storage/storageAccounts/${PROVIDER_STORAGE}"
    
    log_success "Provider Purview instance deployed successfully"
}

# Configure consumer infrastructure
configure_consumer_infrastructure() {
    log_info "Configuring consumer infrastructure..."
    
    # Switch to consumer subscription
    az account set --subscription "${CONSUMER_SUBSCRIPTION_ID}"
    log_info "Switched to consumer subscription: $CONSUMER_SUBSCRIPTION_ID"
    
    # Create consumer resource group
    log_info "Creating consumer resource group: $CONSUMER_RG"
    az group create \
        --name "${CONSUMER_RG}" \
        --location "${LOCATION}" \
        --tags purpose=datashare-demo environment=consumer
    
    # Create consumer storage account
    log_info "Creating consumer storage account: $CONSUMER_STORAGE"
    az storage account create \
        --name "${CONSUMER_STORAGE}" \
        --resource-group "${CONSUMER_RG}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --hierarchical-namespace true \
        --https-only true \
        --min-tls-version TLS1_2
    
    # Create consumer Data Share account
    log_info "Creating consumer Data Share account: $CONSUMER_SHARE"
    az datashare account create \
        --name "${CONSUMER_SHARE}" \
        --resource-group "${CONSUMER_RG}" \
        --location "${LOCATION}"
    
    log_success "Consumer infrastructure configured successfully"
}

# Deploy consumer Purview instance
deploy_consumer_purview() {
    log_info "Deploying consumer Azure Purview instance..."
    
    # Create consumer Purview account
    log_info "Creating consumer Purview account: $CONSUMER_PURVIEW (this may take 5-10 minutes)"
    az purview account create \
        --name "${CONSUMER_PURVIEW}" \
        --resource-group "${CONSUMER_RG}" \
        --location "${LOCATION}" \
        --sku Standard_4
    
    # Wait for Purview to be fully provisioned
    log_info "Waiting for consumer Purview to be fully provisioned..."
    local timeout=600  # 10 minutes
    local elapsed=0
    local interval=30
    
    while [ $elapsed -lt $timeout ]; do
        local state=$(az purview account show \
            --name "${CONSUMER_PURVIEW}" \
            --resource-group "${CONSUMER_RG}" \
            --query provisioningState -o tsv 2>/dev/null || echo "NotFound")
        
        if [ "$state" = "Succeeded" ]; then
            log_success "Consumer Purview account is ready"
            break
        elif [ "$state" = "Failed" ]; then
            error_exit "Consumer Purview account creation failed"
        fi
        
        log_info "Consumer Purview state: $state. Waiting..."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    if [ $elapsed -ge $timeout ]; then
        error_exit "Timeout waiting for consumer Purview account creation"
    fi
    
    # Get consumer Purview managed identity
    log_info "Getting consumer Purview managed identity"
    local consumer_purview_identity=$(az purview account show \
        --name "${CONSUMER_PURVIEW}" \
        --resource-group "${CONSUMER_RG}" \
        --query identity.principalId -o tsv)
    
    if [ -z "$consumer_purview_identity" ]; then
        error_exit "Failed to get consumer Purview managed identity"
    fi
    
    # Grant Purview access to consumer storage
    log_info "Granting consumer Purview access to storage account"
    az role assignment create \
        --role "Storage Blob Data Reader" \
        --assignee "${consumer_purview_identity}" \
        --scope "/subscriptions/${CONSUMER_SUBSCRIPTION_ID}/resourceGroups/${CONSUMER_RG}/providers/Microsoft.Storage/storageAccounts/${CONSUMER_STORAGE}"
    
    log_success "Consumer Purview instance deployed successfully"
}

# Configure cross-tenant B2B collaboration
configure_cross_tenant_b2b() {
    log_info "Configuring cross-tenant B2B collaboration..."
    
    # Switch back to provider subscription
    az account set --subscription "${PROVIDER_SUBSCRIPTION_ID}"
    
    # Get provider tenant ID
    local provider_tenant_id=$(az account show --query tenantId -o tsv)
    
    # Get consumer tenant ID
    az account set --subscription "${CONSUMER_SUBSCRIPTION_ID}"
    local consumer_tenant_id=$(az account show --query tenantId -o tsv)
    
    log_info "Provider Tenant ID: $provider_tenant_id"
    log_info "Consumer Tenant ID: $consumer_tenant_id"
    
    log_warning "Manual step required for cross-tenant access configuration:"
    log_warning "1. Navigate to Azure Portal > Azure AD > External Identities"
    log_warning "2. Configure Cross-tenant access settings"
    log_warning "3. Add $consumer_tenant_id as allowed tenant"
    log_warning "4. Enable B2B collaboration for Data Share service"
    
    log_success "Cross-tenant B2B information displayed"
}

# Create and configure data share
create_data_share() {
    log_info "Creating and configuring data share..."
    
    # Switch to provider subscription
    az account set --subscription "${PROVIDER_SUBSCRIPTION_ID}"
    
    # Create a share in provider account
    log_info "Creating data share: cross-tenant-dataset"
    az datashare create \
        --account-name "${PROVIDER_SHARE}" \
        --resource-group "${PROVIDER_RG}" \
        --name "cross-tenant-dataset" \
        --description "Cross-tenant collaborative dataset" \
        --terms "Standard data sharing terms apply"
    
    # Create dataset in the share (pointing to blob container)
    log_info "Creating dataset in the share"
    az datashare dataset blob-container create \
        --account-name "${PROVIDER_SHARE}" \
        --resource-group "${PROVIDER_RG}" \
        --share-name "cross-tenant-dataset" \
        --name "shared-container-dataset" \
        --container-name "shared-datasets" \
        --storage-account-name "${PROVIDER_STORAGE}" \
        --resource-group "${PROVIDER_RG}"
    
    log_success "Data share created and configured successfully"
}

# Configure Purview data scanning
configure_purview_scanning() {
    log_info "Configuring Purview data scanning..."
    
    local provider_purview_endpoint="https://${PROVIDER_PURVIEW}.purview.azure.com"
    local consumer_purview_endpoint="https://${CONSUMER_PURVIEW}.purview.azure.com"
    
    log_warning "Manual configuration required in Purview Studio:"
    log_warning "1. Open Purview Studio for $PROVIDER_PURVIEW"
    log_warning "2. Navigate to Data Map > Sources"
    log_warning "3. Register $PROVIDER_STORAGE as a data source"
    log_warning "4. Create a scan with weekly schedule"
    log_warning "5. Enable automatic classification"
    log_warning ""
    log_warning "Provider Purview URL: $provider_purview_endpoint"
    log_warning "Consumer Purview URL: $consumer_purview_endpoint"
    
    log_success "Purview scanning configuration information displayed"
}

# Set up data lineage tracking
setup_data_lineage() {
    log_info "Setting up data lineage tracking..."
    
    local provider_purview_endpoint="https://${PROVIDER_PURVIEW}.purview.azure.com"
    local consumer_purview_endpoint="https://${CONSUMER_PURVIEW}.purview.azure.com"
    
    log_warning "To enable lineage tracking:"
    log_warning "1. In Provider Purview: Create lineage for source datasets"
    log_warning "2. In Consumer Purview: Create lineage for received datasets"
    log_warning "3. Use Purview REST API to link cross-tenant lineage"
    log_warning ""
    log_warning "REST API endpoint for lineage:"
    log_warning "Provider: $provider_purview_endpoint/catalog/api/atlas/v2/lineage"
    log_warning "Consumer: $consumer_purview_endpoint/catalog/api/atlas/v2/lineage"
    
    log_success "Data lineage tracking setup information displayed"
}

# Validation function
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check provider Data Share account
    az account set --subscription "${PROVIDER_SUBSCRIPTION_ID}"
    local provider_state=$(az datashare account show \
        --name "${PROVIDER_SHARE}" \
        --resource-group "${PROVIDER_RG}" \
        --query provisioningState -o tsv)
    
    if [ "$provider_state" != "Succeeded" ]; then
        error_exit "Provider Data Share account is not in succeeded state: $provider_state"
    fi
    
    # Check consumer Data Share account
    az account set --subscription "${CONSUMER_SUBSCRIPTION_ID}"
    local consumer_state=$(az datashare account show \
        --name "${CONSUMER_SHARE}" \
        --resource-group "${CONSUMER_RG}" \
        --query provisioningState -o tsv)
    
    if [ "$consumer_state" != "Succeeded" ]; then
        error_exit "Consumer Data Share account is not in succeeded state: $consumer_state"
    fi
    
    # Test Purview endpoints
    local provider_purview_endpoint="https://${PROVIDER_PURVIEW}.purview.azure.com"
    local consumer_purview_endpoint="https://${CONSUMER_PURVIEW}.purview.azure.com"
    
    log_info "Testing Purview endpoints..."
    local provider_response=$(curl -s -o /dev/null -w "%{http_code}" \
        "${provider_purview_endpoint}/catalog/api/atlas/v2/types/typedefs" || echo "000")
    local consumer_response=$(curl -s -o /dev/null -w "%{http_code}" \
        "${consumer_purview_endpoint}/catalog/api/atlas/v2/types/typedefs" || echo "000")
    
    if [ "$provider_response" != "401" ] && [ "$provider_response" != "200" ]; then
        log_warning "Provider Purview endpoint may not be accessible: HTTP $provider_response"
    fi
    
    if [ "$consumer_response" != "401" ] && [ "$consumer_response" != "200" ]; then
        log_warning "Consumer Purview endpoint may not be accessible: HTTP $consumer_response"
    fi
    
    log_success "Deployment validation completed"
}

# Main deployment function
main() {
    log_info "Starting Azure Data Share and Purview deployment..."
    log_info "This deployment may take 15-20 minutes due to Purview provisioning times"
    
    # Run all deployment steps
    check_prerequisites
    validate_environment
    setup_environment
    create_provider_infrastructure
    deploy_provider_purview
    configure_consumer_infrastructure
    deploy_consumer_purview
    configure_cross_tenant_b2b
    create_data_share
    configure_purview_scanning
    setup_data_lineage
    validate_deployment
    
    log_success "Deployment completed successfully!"
    log_info ""
    log_info "Next steps:"
    log_info "1. Configure cross-tenant access in Azure AD as indicated above"
    log_info "2. Set up Purview data scanning in both tenants"
    log_info "3. Configure data lineage tracking"
    log_info "4. Create and send data share invitations"
    log_info ""
    log_info "Resource Information:"
    log_info "  Provider Storage: $PROVIDER_STORAGE"
    log_info "  Consumer Storage: $CONSUMER_STORAGE"
    log_info "  Provider Data Share: $PROVIDER_SHARE"
    log_info "  Consumer Data Share: $CONSUMER_SHARE"
    log_info "  Provider Purview: https://${PROVIDER_PURVIEW}.purview.azure.com"
    log_info "  Consumer Purview: https://${CONSUMER_PURVIEW}.purview.azure.com"
}

# Dry run function
dry_run() {
    log_info "DRY RUN MODE - No resources will be created"
    log_info "This would deploy the following resources:"
    log_info "  Provider Resource Group: $PROVIDER_RG"
    log_info "  Consumer Resource Group: $CONSUMER_RG"
    log_info "  Provider Storage Account: $PROVIDER_STORAGE"
    log_info "  Consumer Storage Account: $CONSUMER_STORAGE"
    log_info "  Provider Data Share: $PROVIDER_SHARE"
    log_info "  Consumer Data Share: $CONSUMER_SHARE"
    log_info "  Provider Purview: $PROVIDER_PURVIEW"
    log_info "  Consumer Purview: $CONSUMER_PURVIEW"
    log_info "  Location: $LOCATION"
}

# Script usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -d, --dry-run       Show what would be deployed without creating resources"
    echo "  -v, --verbose       Enable verbose output"
    echo ""
    echo "Required environment variables:"
    echo "  PROVIDER_SUBSCRIPTION_ID    Azure subscription ID for the data provider"
    echo "  CONSUMER_SUBSCRIPTION_ID    Azure subscription ID for the data consumer"
    echo "  LOCATION                    Azure region for deployment (e.g., eastus)"
    echo ""
    echo "Optional environment variables:"
    echo "  PROVIDER_RG                 Provider resource group name (default: rg-datashare-provider)"
    echo "  CONSUMER_RG                 Consumer resource group name (default: rg-datashare-consumer)"
    echo "  RANDOM_SUFFIX               Custom suffix for resource names (default: auto-generated)"
    echo ""
    echo "Example:"
    echo "  export PROVIDER_SUBSCRIPTION_ID=12345678-1234-1234-1234-123456789012"
    echo "  export CONSUMER_SUBSCRIPTION_ID=87654321-4321-4321-4321-210987654321"
    echo "  export LOCATION=eastus"
    echo "  $0"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check if required environment variables are set
if [ -z "${PROVIDER_SUBSCRIPTION_ID:-}" ] || [ -z "${CONSUMER_SUBSCRIPTION_ID:-}" ] || [ -z "${LOCATION:-}" ]; then
    log_error "Required environment variables are not set"
    usage
    exit 1
fi

# Execute main function or dry run
if [ "${DRY_RUN:-false}" = "true" ]; then
    setup_environment
    dry_run
else
    main
fi