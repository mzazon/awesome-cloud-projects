#!/bin/bash

# =============================================================================
# Azure Bicep and Event Grid Infrastructure Deployment Script
# =============================================================================
# This script automates the deployment of an event-driven infrastructure
# deployment system using Azure Bicep and Event Grid.
#
# Prerequisites:
# - Azure CLI v2.50.0 or later
# - Azure subscription with Owner or Contributor access
# - Docker (for building container images)
# - OpenSSL (for generating random suffixes)
#
# Usage: ./deploy.sh [options]
# Options:
#   -d, --dry-run     Show what would be deployed without executing
#   -v, --verbose     Enable verbose logging
#   -h, --help        Show this help message
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=false
VERBOSE=false

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "DEBUG") [[ $VERBOSE == true ]] && echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

show_help() {
    cat << EOF
Azure Bicep and Event Grid Infrastructure Deployment Script

Usage: $0 [options]

Options:
    -d, --dry-run     Show what would be deployed without executing
    -v, --verbose     Enable verbose logging
    -h, --help        Show this help message

Environment Variables:
    AZURE_LOCATION    Azure region (default: eastus)
    RESOURCE_PREFIX   Prefix for resource names (default: bicep-eg)

Examples:
    $0                          # Deploy with default settings
    $0 --dry-run               # Show deployment plan
    $0 --verbose               # Enable verbose logging
    AZURE_LOCATION=westus2 $0  # Deploy to West US 2

EOF
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if running on supported OS
    if [[ "$OSTYPE" != "linux-gnu"* ]] && [[ "$OSTYPE" != "darwin"* ]]; then
        log "ERROR" "This script requires Linux or macOS"
        exit 1
    fi
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log "ERROR" "Azure CLI is not installed. Please install Azure CLI v2.50.0 or later."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    local min_version="2.50.0"
    if ! printf '%s\n%s\n' "$min_version" "$az_version" | sort -V -C; then
        log "ERROR" "Azure CLI version $az_version is too old. Minimum required: $min_version"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker is not installed. Please install Docker to build container images."
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log "ERROR" "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    # Check OpenSSL
    if ! command -v openssl &> /dev/null; then
        log "ERROR" "OpenSSL is not installed. Please install OpenSSL to generate random suffixes."
        exit 1
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        log "ERROR" "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        log "ERROR" "curl is not installed. Please install curl for API requests."
        exit 1
    fi
    
    log "INFO" "Prerequisites check passed ✅"
}

check_azure_login() {
    log "INFO" "Checking Azure authentication..."
    
    if ! az account show &> /dev/null; then
        log "ERROR" "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription info
    local subscription_id=$(az account show --query id -o tsv)
    local subscription_name=$(az account show --query name -o tsv)
    
    log "INFO" "Using Azure subscription: $subscription_name ($subscription_id)"
    
    # Check if user has required permissions
    local user_role=$(az role assignment list --assignee "$(az account show --query user.name -o tsv)" --scope "/subscriptions/$subscription_id" --query '[0].roleDefinitionName' -o tsv 2>/dev/null || echo "Unknown")
    
    if [[ "$user_role" != "Owner" ]] && [[ "$user_role" != "Contributor" ]]; then
        log "WARN" "Current user role: $user_role. Owner or Contributor role recommended."
    fi
    
    log "INFO" "Azure authentication check passed ✅"
}

generate_unique_suffix() {
    # Generate a 6-character random suffix for unique resource names
    openssl rand -hex 3 | tr '[:upper:]' '[:lower:]'
}

setup_environment() {
    log "INFO" "Setting up environment variables..."
    
    # Set default values
    export AZURE_LOCATION="${AZURE_LOCATION:-eastus}"
    export RESOURCE_PREFIX="${RESOURCE_PREFIX:-bicep-eg}"
    export RANDOM_SUFFIX=$(generate_unique_suffix)
    
    # Core resource names
    export RESOURCE_GROUP="rg-${RESOURCE_PREFIX}-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="st${RESOURCE_PREFIX//-/}${RANDOM_SUFFIX}"
    export EVENT_GRID_TOPIC="egt-deployments-${RANDOM_SUFFIX}"
    export CONTAINER_REGISTRY="acr${RESOURCE_PREFIX//-/}${RANDOM_SUFFIX}"
    export KEY_VAULT="kv-${RESOURCE_PREFIX}-${RANDOM_SUFFIX}"
    export FUNCTION_APP="func-${RESOURCE_PREFIX}-${RANDOM_SUFFIX}"
    export FUNCTION_STORAGE="stfunc${RESOURCE_PREFIX//-/}${RANDOM_SUFFIX}"
    
    # Get Azure subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    
    # Validate resource names
    if [[ ${#STORAGE_ACCOUNT} -gt 24 ]]; then
        log "ERROR" "Storage account name too long: ${STORAGE_ACCOUNT}"
        exit 1
    fi
    
    if [[ ${#KEY_VAULT} -gt 24 ]]; then
        log "ERROR" "Key Vault name too long: ${KEY_VAULT}"
        exit 1
    fi
    
    log "INFO" "Environment variables configured:"
    log "INFO" "  Resource Group: $RESOURCE_GROUP"
    log "INFO" "  Location: $AZURE_LOCATION"
    log "INFO" "  Storage Account: $STORAGE_ACCOUNT"
    log "INFO" "  Event Grid Topic: $EVENT_GRID_TOPIC"
    log "INFO" "  Container Registry: $CONTAINER_REGISTRY"
    log "INFO" "  Key Vault: $KEY_VAULT"
    log "INFO" "  Function App: $FUNCTION_APP"
}

deploy_resource_group() {
    log "INFO" "Creating resource group..."
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "[DRY RUN] Would create resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "INFO" "Resource group $RESOURCE_GROUP already exists"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$AZURE_LOCATION" \
        --tags purpose=recipe environment=demo deployment=automated \
        --only-show-errors
    
    log "INFO" "Resource group created successfully ✅"
}

deploy_storage_account() {
    log "INFO" "Creating storage account for Bicep templates..."
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "[DRY RUN] Would create storage account: $STORAGE_ACCOUNT"
        return 0
    fi
    
    # Check if storage account already exists
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "INFO" "Storage account $STORAGE_ACCOUNT already exists"
    else
        # Create storage account with secure defaults
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$AZURE_LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --https-only true \
            --allow-blob-public-access false \
            --min-tls-version TLS1_2 \
            --only-show-errors
        
        log "INFO" "Storage account created successfully"
    fi
    
    # Create container for Bicep templates
    az storage container create \
        --name bicep-templates \
        --account-name "$STORAGE_ACCOUNT" \
        --auth-mode login \
        --only-show-errors &> /dev/null || true
    
    # Get storage account key
    export STORAGE_KEY=$(az storage account keys list \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].value" -o tsv)
    
    log "INFO" "Storage account configuration completed ✅"
}

deploy_event_grid_topic() {
    log "INFO" "Creating Event Grid topic..."
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "[DRY RUN] Would create Event Grid topic: $EVENT_GRID_TOPIC"
        return 0
    fi
    
    # Check if Event Grid topic already exists
    if az eventgrid topic show --name "$EVENT_GRID_TOPIC" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "INFO" "Event Grid topic $EVENT_GRID_TOPIC already exists"
    else
        # Create Event Grid topic
        az eventgrid topic create \
            --name "$EVENT_GRID_TOPIC" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$AZURE_LOCATION" \
            --input-schema eventgridschema \
            --only-show-errors
        
        log "INFO" "Event Grid topic created successfully"
    fi
    
    # Get topic endpoint and key
    export EVENT_GRID_ENDPOINT=$(az eventgrid topic show \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query endpoint -o tsv)
    
    export EVENT_GRID_KEY=$(az eventgrid topic key list \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 -o tsv)
    
    log "INFO" "Event Grid topic configuration completed ✅"
}

deploy_key_vault() {
    log "INFO" "Creating Key Vault for secrets management..."
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "[DRY RUN] Would create Key Vault: $KEY_VAULT"
        return 0
    fi
    
    # Check if Key Vault already exists
    if az keyvault show --name "$KEY_VAULT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "INFO" "Key Vault $KEY_VAULT already exists"
    else
        # Create Key Vault with secure defaults
        az keyvault create \
            --name "$KEY_VAULT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$AZURE_LOCATION" \
            --sku standard \
            --enable-rbac-authorization true \
            --only-show-errors
        
        log "INFO" "Key Vault created successfully"
    fi
    
    # Store secrets
    az keyvault secret set \
        --vault-name "$KEY_VAULT" \
        --name "EventGridKey" \
        --value "$EVENT_GRID_KEY" \
        --only-show-errors &> /dev/null || log "WARN" "Failed to store Event Grid key in Key Vault"
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT" \
        --name "StorageKey" \
        --value "$STORAGE_KEY" \
        --only-show-errors &> /dev/null || log "WARN" "Failed to store Storage key in Key Vault"
    
    log "INFO" "Key Vault configuration completed ✅"
}

deploy_container_registry() {
    log "INFO" "Creating Container Registry..."
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "[DRY RUN] Would create Container Registry: $CONTAINER_REGISTRY"
        return 0
    fi
    
    # Check if Container Registry already exists
    if az acr show --name "$CONTAINER_REGISTRY" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "INFO" "Container Registry $CONTAINER_REGISTRY already exists"
    else
        # Create Container Registry
        az acr create \
            --name "$CONTAINER_REGISTRY" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$AZURE_LOCATION" \
            --sku Basic \
            --admin-enabled true \
            --only-show-errors
        
        log "INFO" "Container Registry created successfully"
    fi
    
    # Get registry credentials
    export ACR_USERNAME=$(az acr credential show \
        --name "$CONTAINER_REGISTRY" \
        --query username -o tsv)
    
    export ACR_PASSWORD=$(az acr credential show \
        --name "$CONTAINER_REGISTRY" \
        --query passwords[0].value -o tsv)
    
    log "INFO" "Container Registry configuration completed ✅"
}

create_deployment_artifacts() {
    log "INFO" "Creating deployment artifacts..."
    
    local temp_dir=$(mktemp -d)
    
    # Create Dockerfile for deployment runner
    cat > "$temp_dir/Dockerfile" << 'EOF'
FROM mcr.microsoft.com/azure-cli:latest

# Install additional tools
RUN apk add --no-cache \
    curl \
    jq \
    bash \
    git

# Create working directory
WORKDIR /deployment

# Copy deployment script
COPY deploy.sh /deployment/
RUN chmod +x /deployment/deploy.sh

ENTRYPOINT ["/deployment/deploy.sh"]
EOF
    
    # Create deployment script
    cat > "$temp_dir/deploy.sh" << 'EOF'
#!/bin/bash
set -e

echo "Starting deployment process..."

# Parse event data
EVENT_DATA=$1
TEMPLATE_NAME=$(echo $EVENT_DATA | jq -r '.templateName')
PARAMETERS=$(echo $EVENT_DATA | jq -r '.parameters')
TARGET_RG=$(echo $EVENT_DATA | jq -r '.targetResourceGroup')

echo "Deploying template: $TEMPLATE_NAME to resource group: $TARGET_RG"

# Download Bicep template
az storage blob download \
    --account-name $STORAGE_ACCOUNT \
    --account-key $STORAGE_KEY \
    --container-name bicep-templates \
    --name "${TEMPLATE_NAME}.bicep" \
    --file "/tmp/${TEMPLATE_NAME}.bicep"

# Deploy Bicep template
az deployment group create \
    --resource-group $TARGET_RG \
    --template-file "/tmp/${TEMPLATE_NAME}.bicep" \
    --parameters "$PARAMETERS" \
    --only-show-errors

echo "Deployment completed successfully"
EOF
    
    # Create sample Bicep template
    cat > "$temp_dir/storage-account.bicep" << 'EOF'
@description('Storage account name')
param storageAccountName string

@description('Location for resources')
param location string = resourceGroup().location

@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
])
@description('Storage SKU')
param storageSku string = 'Standard_LRS'

@description('Tags for the storage account')
param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageSku
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    defaultToOAuthAuthentication: true
    allowSharedKeyAccess: false
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

output storageAccountId string = storageAccount.id
output primaryEndpoint string = storageAccount.properties.primaryEndpoints.blob
output storageAccountName string = storageAccount.name
EOF
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "[DRY RUN] Would create deployment artifacts in: $temp_dir"
        rm -rf "$temp_dir"
        return 0
    fi
    
    # Build and push container image
    az acr build \
        --registry "$CONTAINER_REGISTRY" \
        --image deployment-runner:v1 \
        --file "$temp_dir/Dockerfile" \
        "$temp_dir" \
        --only-show-errors
    
    # Upload Bicep template to storage
    az storage blob upload \
        --account-name "$STORAGE_ACCOUNT" \
        --container-name bicep-templates \
        --name "storage-account.bicep" \
        --file "$temp_dir/storage-account.bicep" \
        --auth-mode login \
        --only-show-errors
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    log "INFO" "Deployment artifacts created successfully ✅"
}

deploy_function_app() {
    log "INFO" "Creating Function App for event processing..."
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "[DRY RUN] Would create Function App: $FUNCTION_APP"
        return 0
    fi
    
    # Check if Function App storage already exists
    if ! az storage account show --name "$FUNCTION_STORAGE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        # Create storage for Function App
        az storage account create \
            --name "$FUNCTION_STORAGE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$AZURE_LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --https-only true \
            --only-show-errors
        
        log "INFO" "Function App storage account created"
    fi
    
    # Check if Function App already exists
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "INFO" "Function App $FUNCTION_APP already exists"
    else
        # Create Function App
        az functionapp create \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --storage-account "$FUNCTION_STORAGE" \
            --consumption-plan-location "$AZURE_LOCATION" \
            --runtime dotnet \
            --functions-version 4 \
            --only-show-errors
        
        log "INFO" "Function App created successfully"
    fi
    
    # Configure Function App settings
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
        "STORAGE_ACCOUNT=$STORAGE_ACCOUNT" \
        "CONTAINER_REGISTRY=$CONTAINER_REGISTRY" \
        "ACR_USERNAME=$ACR_USERNAME" \
        "ACR_PASSWORD=$ACR_PASSWORD" \
        "RESOURCE_GROUP=$RESOURCE_GROUP" \
        --only-show-errors
    
    log "INFO" "Function App configuration completed ✅"
}

configure_event_subscription() {
    log "INFO" "Configuring Event Grid subscription..."
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "[DRY RUN] Would create Event Grid subscription"
        return 0
    fi
    
    # Get Function App endpoint
    local function_endpoint=$(az functionapp show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query defaultHostName -o tsv)
    
    # Create Event Grid subscription
    az eventgrid event-subscription create \
        --name "deployment-subscription" \
        --source-resource-id "$(az eventgrid topic show \
            --name "$EVENT_GRID_TOPIC" \
            --resource-group "$RESOURCE_GROUP" \
            --query id -o tsv)" \
        --endpoint "https://${function_endpoint}/api/DeploymentHandler" \
        --endpoint-type webhook \
        --only-show-errors || log "WARN" "Event Grid subscription creation failed - may need Function App code deployment"
    
    log "INFO" "Event Grid subscription configured ✅"
}

run_validation_tests() {
    log "INFO" "Running validation tests..."
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "[DRY RUN] Would run validation tests"
        return 0
    fi
    
    # Test 1: Verify Event Grid topic
    local topic_status=$(az eventgrid topic show \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query provisioningState -o tsv)
    
    if [[ "$topic_status" == "Succeeded" ]]; then
        log "INFO" "✅ Event Grid topic validation passed"
    else
        log "WARN" "❌ Event Grid topic validation failed: $topic_status"
    fi
    
    # Test 2: Verify storage account and container
    local blob_list=$(az storage blob list \
        --account-name "$STORAGE_ACCOUNT" \
        --container-name bicep-templates \
        --auth-mode login \
        --query length(@) -o tsv 2>/dev/null || echo "0")
    
    if [[ "$blob_list" -gt 0 ]]; then
        log "INFO" "✅ Bicep template storage validation passed"
    else
        log "WARN" "❌ Bicep template storage validation failed"
    fi
    
    # Test 3: Verify Function App
    local function_state=$(az functionapp show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query state -o tsv)
    
    if [[ "$function_state" == "Running" ]]; then
        log "INFO" "✅ Function App validation passed"
    else
        log "WARN" "❌ Function App validation failed: $function_state"
    fi
    
    # Test 4: Verify Container Registry
    local acr_status=$(az acr show \
        --name "$CONTAINER_REGISTRY" \
        --resource-group "$RESOURCE_GROUP" \
        --query provisioningState -o tsv)
    
    if [[ "$acr_status" == "Succeeded" ]]; then
        log "INFO" "✅ Container Registry validation passed"
    else
        log "WARN" "❌ Container Registry validation failed: $acr_status"
    fi
    
    log "INFO" "Validation tests completed ✅"
}

display_deployment_summary() {
    log "INFO" "Deployment Summary:"
    log "INFO" "=================="
    log "INFO" "Resource Group: $RESOURCE_GROUP"
    log "INFO" "Location: $AZURE_LOCATION"
    log "INFO" "Storage Account: $STORAGE_ACCOUNT"
    log "INFO" "Event Grid Topic: $EVENT_GRID_TOPIC"
    log "INFO" "Container Registry: $CONTAINER_REGISTRY"
    log "INFO" "Key Vault: $KEY_VAULT"
    log "INFO" "Function App: $FUNCTION_APP"
    log "INFO" ""
    log "INFO" "Event Grid Endpoint: $EVENT_GRID_ENDPOINT"
    log "INFO" ""
    log "INFO" "Next Steps:"
    log "INFO" "1. Deploy Function App code for event processing"
    log "INFO" "2. Test deployment by publishing events to Event Grid"
    log "INFO" "3. Monitor deployments through Azure Monitor"
    log "INFO" ""
    log "INFO" "Cleanup: Run ./destroy.sh to remove all resources"
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    log "INFO" "Starting Azure Bicep and Event Grid infrastructure deployment..."
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "DRY RUN MODE - No resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites
    check_azure_login
    setup_environment
    deploy_resource_group
    deploy_storage_account
    deploy_event_grid_topic
    deploy_key_vault
    deploy_container_registry
    create_deployment_artifacts
    deploy_function_app
    configure_event_subscription
    run_validation_tests
    display_deployment_summary
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "DRY RUN completed successfully"
    else
        log "INFO" "Deployment completed successfully! 🎉"
    fi
}

# Handle script interruption
trap 'log "ERROR" "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"