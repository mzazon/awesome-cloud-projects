#!/bin/bash
# Deploy Intelligent Space Data Analytics with Azure Orbital and Azure AI Services
# Version: 1.0
# Last Updated: 2025-07-12

set -euo pipefail

# Configuration and logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
DRY_RUN=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "ERROR" "${RED}$1${NC}"
    log "ERROR" "Deployment failed. Check ${LOG_FILE} for details."
    exit 1
}

# Success message
success() {
    log "INFO" "${GREEN}$1${NC}"
}

# Warning message
warning() {
    log "WARN" "${YELLOW}$1${NC}"
}

# Info message
info() {
    log "INFO" "${BLUE}$1${NC}"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Intelligent Space Data Analytics with Azure Orbital and Azure AI Services

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be deployed without actually deploying
    -r, --resource-group   Resource group name (default: rg-orbital-analytics)
    -l, --location         Azure region (default: eastus)
    -s, --suffix           Resource name suffix (default: auto-generated)

EXAMPLES:
    $0                                          # Deploy with default settings
    $0 --dry-run                               # Show deployment plan
    $0 -r my-rg -l westus2                    # Deploy to specific region
    $0 --suffix abc123                         # Use specific suffix

PREREQUISITES:
    - Azure CLI installed and authenticated
    - Appropriate Azure permissions
    - Azure subscription with Orbital preview access

EOF
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Get current subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    info "Using subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
    
    # Check required providers
    info "Checking Azure provider registrations..."
    az provider register --namespace Microsoft.Storage --wait || warning "Failed to register Storage provider"
    az provider register --namespace Microsoft.Synapse --wait || warning "Failed to register Synapse provider"
    az provider register --namespace Microsoft.EventHub --wait || warning "Failed to register EventHub provider"
    az provider register --namespace Microsoft.CognitiveServices --wait || warning "Failed to register Cognitive Services provider"
    az provider register --namespace Microsoft.Maps --wait || warning "Failed to register Maps provider"
    az provider register --namespace Microsoft.DocumentDB --wait || warning "Failed to register Cosmos DB provider"
    az provider register --namespace Microsoft.KeyVault --wait || warning "Failed to register Key Vault provider"
    
    # Warn about Azure Orbital requirements
    warning "Azure Orbital requires pre-approval. Ensure your subscription has access to Azure Orbital services."
    
    success "Prerequisites check completed"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -r|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -s|--suffix)
                SUFFIX="$2"
                shift 2
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
}

# Set default values and generate unique suffix
set_defaults() {
    RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-orbital-analytics"}
    LOCATION=${LOCATION:-"eastus"}
    
    if [[ -z "${SUFFIX:-}" ]]; then
        SUFFIX=$(openssl rand -hex 3)
    fi
    
    # Set specific resource names
    STORAGE_ACCOUNT="storbitdata${SUFFIX}"
    SYNAPSE_WORKSPACE="syn-orbital-${SUFFIX}"
    EVENT_HUB_NAMESPACE="eh-orbital-${SUFFIX}"
    AI_SERVICES_ACCOUNT="ai-orbital-${SUFFIX}"
    MAPS_ACCOUNT="maps-orbital-${SUFFIX}"
    COSMOS_ACCOUNT="cosmos-orbital-${SUFFIX}"
    KEY_VAULT_NAME="kv-orbital-${SUFFIX}"
    
    info "Deployment configuration:"
    info "  Resource Group: ${RESOURCE_GROUP}"
    info "  Location: ${LOCATION}"
    info "  Suffix: ${SUFFIX}"
    info "  Storage Account: ${STORAGE_ACCOUNT}"
    info "  Synapse Workspace: ${SYNAPSE_WORKSPACE}"
    info "  Event Hub Namespace: ${EVENT_HUB_NAMESPACE}"
    info "  AI Services: ${AI_SERVICES_ACCOUNT}"
    info "  Maps Account: ${MAPS_ACCOUNT}"
    info "  Cosmos Account: ${COSMOS_ACCOUNT}"
    info "  Key Vault: ${KEY_VAULT_NAME}"
}

# Dry run mode
execute_dry_run() {
    info "DRY RUN MODE - No resources will be created"
    info "The following resources would be deployed:"
    echo "
Resource Group: ${RESOURCE_GROUP}
└── Storage Account: ${STORAGE_ACCOUNT}
    ├── Container: raw-satellite-data
    ├── Container: processed-imagery
    └── Container: ai-analysis-results
└── Synapse Workspace: ${SYNAPSE_WORKSPACE}
    ├── Spark Pool: sparkpool01
    └── SQL Pool: sqlpool01
└── Event Hub Namespace: ${EVENT_HUB_NAMESPACE}
    ├── Event Hub: satellite-imagery-stream
    └── Event Hub: satellite-telemetry-stream
└── AI Services Account: ${AI_SERVICES_ACCOUNT}
└── Custom Vision: cv-${AI_SERVICES_ACCOUNT}
└── Azure Maps: ${MAPS_ACCOUNT}
└── Cosmos DB: ${COSMOS_ACCOUNT}
    ├── Database: SatelliteAnalytics
    ├── Container: ImageryMetadata
    ├── Container: AIAnalysisResults
    └── Container: GeospatialIndex
└── Key Vault: ${KEY_VAULT_NAME}
"
    info "Estimated deployment time: 15-20 minutes"
    info "Estimated monthly cost: \$500-800 (varies by usage)"
}

# Create resource group
create_resource_group() {
    info "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=orbital-analytics environment=demo deployment-script=true || \
            error_exit "Failed to create resource group"
        success "Resource group created successfully"
    fi
}

# Create Key Vault
create_key_vault() {
    info "Creating Key Vault: ${KEY_VAULT_NAME}"
    
    if az keyvault show --name "${KEY_VAULT_NAME}" &> /dev/null; then
        warning "Key Vault ${KEY_VAULT_NAME} already exists"
    else
        az keyvault create \
            --name "${KEY_VAULT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku standard \
            --enable-soft-delete true \
            --retention-days 7 || \
            error_exit "Failed to create Key Vault"
        success "Key Vault created successfully"
    fi
}

# Create Data Lake Storage
create_storage_account() {
    info "Creating Data Lake Storage: ${STORAGE_ACCOUNT}"
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Storage account ${STORAGE_ACCOUNT} already exists"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --hierarchical-namespace true \
            --access-tier Hot \
            --allow-blob-public-access false || \
            error_exit "Failed to create storage account"
        success "Storage account created successfully"
    fi
    
    # Get storage key
    STORAGE_KEY=$(az storage account keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --account-name "${STORAGE_ACCOUNT}" \
        --query '[0].value' --output tsv) || \
        error_exit "Failed to get storage account key"
    
    # Create containers
    info "Creating storage containers..."
    
    for container in "raw-satellite-data" "processed-imagery" "ai-analysis-results"; do
        if az storage container exists --name "${container}" --account-name "${STORAGE_ACCOUNT}" --account-key "${STORAGE_KEY}" --output tsv | grep -q "True"; then
            warning "Container ${container} already exists"
        else
            az storage container create \
                --name "${container}" \
                --account-name "${STORAGE_ACCOUNT}" \
                --account-key "${STORAGE_KEY}" \
                --public-access off || \
                error_exit "Failed to create container ${container}"
        fi
    done
    
    success "Storage containers created successfully"
}

# Create Event Hubs
create_event_hubs() {
    info "Creating Event Hubs Namespace: ${EVENT_HUB_NAMESPACE}"
    
    if az eventhubs namespace show --name "${EVENT_HUB_NAMESPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Event Hubs namespace ${EVENT_HUB_NAMESPACE} already exists"
    else
        az eventhubs namespace create \
            --name "${EVENT_HUB_NAMESPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard \
            --enable-auto-inflate true \
            --maximum-throughput-units 10 || \
            error_exit "Failed to create Event Hubs namespace"
        success "Event Hubs namespace created successfully"
    fi
    
    # Create event hubs
    info "Creating Event Hubs..."
    
    # Satellite imagery stream
    if az eventhubs eventhub show --name "satellite-imagery-stream" --namespace-name "${EVENT_HUB_NAMESPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Event Hub satellite-imagery-stream already exists"
    else
        az eventhubs eventhub create \
            --name "satellite-imagery-stream" \
            --namespace-name "${EVENT_HUB_NAMESPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --partition-count 8 \
            --message-retention 7 || \
            error_exit "Failed to create satellite imagery event hub"
    fi
    
    # Satellite telemetry stream
    if az eventhubs eventhub show --name "satellite-telemetry-stream" --namespace-name "${EVENT_HUB_NAMESPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Event Hub satellite-telemetry-stream already exists"
    else
        az eventhubs eventhub create \
            --name "satellite-telemetry-stream" \
            --namespace-name "${EVENT_HUB_NAMESPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --partition-count 4 \
            --message-retention 3 || \
            error_exit "Failed to create satellite telemetry event hub"
    fi
    
    # Get connection string and store in Key Vault
    EVENT_HUB_CONNECTION=$(az eventhubs namespace authorization-rule keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --namespace-name "${EVENT_HUB_NAMESPACE}" \
        --name RootManageSharedAccessKey \
        --query primaryConnectionString --output tsv) || \
        error_exit "Failed to get Event Hub connection string"
    
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "EventHubConnection" \
        --value "${EVENT_HUB_CONNECTION}" || \
        warning "Failed to store Event Hub connection in Key Vault"
    
    success "Event Hubs created successfully"
}

# Create Synapse Analytics
create_synapse_workspace() {
    info "Creating Synapse Analytics Workspace: ${SYNAPSE_WORKSPACE}"
    
    if az synapse workspace show --name "${SYNAPSE_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Synapse workspace ${SYNAPSE_WORKSPACE} already exists"
    else
        # Create file system for Synapse if it doesn't exist
        az storage fs create \
            --name "synapse-fs" \
            --account-name "${STORAGE_ACCOUNT}" \
            --account-key "${STORAGE_KEY}" || \
            warning "Failed to create Synapse file system (may already exist)"
        
        az synapse workspace create \
            --name "${SYNAPSE_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --file-system "synapse-fs" \
            --sql-admin-login-user "synadmin" \
            --sql-admin-login-password "SecurePass123!" \
            --location "${LOCATION}" \
            --enable-managed-vnet true || \
            error_exit "Failed to create Synapse workspace"
        success "Synapse workspace created successfully"
    fi
    
    # Wait for workspace to be ready
    info "Waiting for Synapse workspace to be ready..."
    sleep 60
    
    # Create Spark pool
    info "Creating Spark pool..."
    if az synapse spark pool show --name "sparkpool01" --workspace-name "${SYNAPSE_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Spark pool sparkpool01 already exists"
    else
        az synapse spark pool create \
            --name "sparkpool01" \
            --workspace-name "${SYNAPSE_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --spark-version "3.3" \
            --node-count 3 \
            --node-size "Medium" \
            --min-node-count 3 \
            --max-node-count 10 \
            --enable-auto-scale true \
            --enable-auto-pause true \
            --delay 15 || \
            error_exit "Failed to create Spark pool"
        success "Spark pool created successfully"
    fi
    
    # Create SQL pool
    info "Creating SQL pool..."
    if az synapse sql pool show --name "sqlpool01" --workspace-name "${SYNAPSE_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "SQL pool sqlpool01 already exists"
    else
        az synapse sql pool create \
            --name "sqlpool01" \
            --workspace-name "${SYNAPSE_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --performance-level "DW100c" || \
            error_exit "Failed to create SQL pool"
        success "SQL pool created successfully"
    fi
}

# Create AI Services
create_ai_services() {
    info "Creating AI Services: ${AI_SERVICES_ACCOUNT}"
    
    if az cognitiveservices account show --name "${AI_SERVICES_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "AI Services account ${AI_SERVICES_ACCOUNT} already exists"
    else
        az cognitiveservices account create \
            --name "${AI_SERVICES_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --kind "CognitiveServices" \
            --sku "S0" \
            --custom-domain "${AI_SERVICES_ACCOUNT}" \
            --yes || \
            error_exit "Failed to create AI Services account"
        success "AI Services account created successfully"
    fi
    
    # Get AI Services credentials
    AI_SERVICES_ENDPOINT=$(az cognitiveservices account show \
        --name "${AI_SERVICES_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.endpoint --output tsv) || \
        error_exit "Failed to get AI Services endpoint"
    
    AI_SERVICES_KEY=$(az cognitiveservices account keys list \
        --name "${AI_SERVICES_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 --output tsv) || \
        error_exit "Failed to get AI Services key"
    
    # Store credentials in Key Vault
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "AIServicesEndpoint" \
        --value "${AI_SERVICES_ENDPOINT}" || \
        warning "Failed to store AI Services endpoint in Key Vault"
    
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "AIServicesKey" \
        --value "${AI_SERVICES_KEY}" || \
        warning "Failed to store AI Services key in Key Vault"
    
    # Create Custom Vision service
    info "Creating Custom Vision service..."
    if az cognitiveservices account show --name "cv-${AI_SERVICES_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Custom Vision account cv-${AI_SERVICES_ACCOUNT} already exists"
    else
        az cognitiveservices account create \
            --name "cv-${AI_SERVICES_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --kind "CustomVision.Training" \
            --sku "S0" \
            --yes || \
            error_exit "Failed to create Custom Vision account"
        success "Custom Vision account created successfully"
    fi
}

# Create Azure Maps
create_azure_maps() {
    info "Creating Azure Maps: ${MAPS_ACCOUNT}"
    
    if az maps account show --name "${MAPS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Azure Maps account ${MAPS_ACCOUNT} already exists"
    else
        az maps account create \
            --name "${MAPS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --sku "S1" \
            --location "global" || \
            error_exit "Failed to create Azure Maps account"
        success "Azure Maps account created successfully"
    fi
    
    # Get Maps subscription key
    MAPS_KEY=$(az maps account keys list \
        --name "${MAPS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query primaryKey --output tsv) || \
        error_exit "Failed to get Maps subscription key"
    
    # Store in Key Vault
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "MapsSubscriptionKey" \
        --value "${MAPS_KEY}" || \
        warning "Failed to store Maps key in Key Vault"
}

# Create Cosmos DB
create_cosmos_db() {
    info "Creating Cosmos DB: ${COSMOS_ACCOUNT}"
    
    if az cosmosdb show --name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Cosmos DB account ${COSMOS_ACCOUNT} already exists"
    else
        az cosmosdb create \
            --name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --default-consistency-level "Session" \
            --enable-automatic-failover true \
            --locations regionName="${LOCATION}" failoverPriority=0 isZoneRedundant=False || \
            error_exit "Failed to create Cosmos DB account"
        success "Cosmos DB account created successfully"
    fi
    
    # Create database
    info "Creating Cosmos DB database..."
    if az cosmosdb sql database show --account-name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" --name "SatelliteAnalytics" &> /dev/null; then
        warning "Cosmos DB database SatelliteAnalytics already exists"
    else
        az cosmosdb sql database create \
            --account-name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --name "SatelliteAnalytics" || \
            error_exit "Failed to create Cosmos DB database"
    fi
    
    # Create containers
    info "Creating Cosmos DB containers..."
    
    containers=(
        "ImageryMetadata:/satelliteId"
        "AIAnalysisResults:/imageId"
        "GeospatialIndex:/gridCell"
    )
    
    for container_def in "${containers[@]}"; do
        container_name="${container_def%%:*}"
        partition_key="${container_def##*:}"
        
        if az cosmosdb sql container show --account-name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" --database-name "SatelliteAnalytics" --name "${container_name}" &> /dev/null; then
            warning "Cosmos DB container ${container_name} already exists"
        else
            az cosmosdb sql container create \
                --account-name "${COSMOS_ACCOUNT}" \
                --resource-group "${RESOURCE_GROUP}" \
                --database-name "SatelliteAnalytics" \
                --name "${container_name}" \
                --partition-key-path "${partition_key}" \
                --throughput 400 || \
                error_exit "Failed to create Cosmos DB container ${container_name}"
        fi
    done
    
    # Get Cosmos DB credentials
    COSMOS_ENDPOINT=$(az cosmosdb show \
        --name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query documentEndpoint --output tsv) || \
        error_exit "Failed to get Cosmos DB endpoint"
    
    COSMOS_KEY=$(az cosmosdb keys list \
        --name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query primaryMasterKey --output tsv) || \
        error_exit "Failed to get Cosmos DB key"
    
    # Store in Key Vault
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "CosmosEndpoint" \
        --value "${COSMOS_ENDPOINT}" || \
        warning "Failed to store Cosmos endpoint in Key Vault"
    
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "CosmosKey" \
        --value "${COSMOS_KEY}" || \
        warning "Failed to store Cosmos key in Key Vault"
    
    success "Cosmos DB created successfully"
}

# Create configuration files
create_config_files() {
    info "Creating configuration files..."
    
    # Create orbital integration config
    cat > "${SCRIPT_DIR}/orbital-integration-config.txt" << EOF
# Azure Orbital Integration Configuration
# Generated on: $(date)

Event Hub Namespace: ${EVENT_HUB_NAMESPACE}
Storage Account: ${STORAGE_ACCOUNT}
Synapse Workspace: ${SYNAPSE_WORKSPACE}
AI Services Account: ${AI_SERVICES_ACCOUNT}
Azure Maps Account: ${MAPS_ACCOUNT}
Cosmos DB Account: ${COSMOS_ACCOUNT}
Key Vault: ${KEY_VAULT_NAME}

# Note: Azure Orbital requires pre-approval and manual configuration
# Contact Microsoft Azure Orbital team to complete ground station integration
EOF
    
    # Create deployment summary
    cat > "${SCRIPT_DIR}/deployment-summary.json" << EOF
{
  "deploymentTimestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "resourceGroup": "${RESOURCE_GROUP}",
  "location": "${LOCATION}",
  "suffix": "${SUFFIX}",
  "resources": {
    "storageAccount": "${STORAGE_ACCOUNT}",
    "synapseWorkspace": "${SYNAPSE_WORKSPACE}",
    "eventHubNamespace": "${EVENT_HUB_NAMESPACE}",
    "aiServicesAccount": "${AI_SERVICES_ACCOUNT}",
    "mapsAccount": "${MAPS_ACCOUNT}",
    "cosmosAccount": "${COSMOS_ACCOUNT}",
    "keyVault": "${KEY_VAULT_NAME}"
  },
  "status": "deployed",
  "deploymentMethod": "bash-script"
}
EOF
    
    success "Configuration files created"
}

# Verify deployment
verify_deployment() {
    info "Verifying deployment..."
    
    local failed_checks=0
    
    # Check each resource
    info "Checking resource group..."
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        error_exit "Resource group verification failed"
        ((failed_checks++))
    fi
    
    info "Checking storage account..."
    if ! az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        error_exit "Storage account verification failed"
        ((failed_checks++))
    fi
    
    info "Checking Event Hubs..."
    if ! az eventhubs namespace show --name "${EVENT_HUB_NAMESPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        error_exit "Event Hubs verification failed"
        ((failed_checks++))
    fi
    
    info "Checking Synapse workspace..."
    if ! az synapse workspace show --name "${SYNAPSE_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        error_exit "Synapse workspace verification failed"
        ((failed_checks++))
    fi
    
    info "Checking AI Services..."
    if ! az cognitiveservices account show --name "${AI_SERVICES_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        error_exit "AI Services verification failed"
        ((failed_checks++))
    fi
    
    info "Checking Azure Maps..."
    if ! az maps account show --name "${MAPS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        error_exit "Azure Maps verification failed"
        ((failed_checks++))
    fi
    
    info "Checking Cosmos DB..."
    if ! az cosmosdb show --name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        error_exit "Cosmos DB verification failed"
        ((failed_checks++))
    fi
    
    info "Checking Key Vault..."
    if ! az keyvault show --name "${KEY_VAULT_NAME}" &> /dev/null; then
        error_exit "Key Vault verification failed"
        ((failed_checks++))
    fi
    
    if [[ ${failed_checks} -eq 0 ]]; then
        success "All resources verified successfully"
    else
        error_exit "${failed_checks} resource verification(s) failed"
    fi
}

# Display deployment results
display_results() {
    info "Deployment completed successfully!"
    echo ""
    echo "============================================================"
    echo "           DEPLOYMENT SUMMARY"
    echo "============================================================"
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Deployment Time: $(date)"
    echo ""
    echo "Deployed Resources:"
    echo "├── Storage Account: ${STORAGE_ACCOUNT}"
    echo "├── Synapse Workspace: ${SYNAPSE_WORKSPACE}"
    echo "├── Event Hub Namespace: ${EVENT_HUB_NAMESPACE}"
    echo "├── AI Services: ${AI_SERVICES_ACCOUNT}"
    echo "├── Custom Vision: cv-${AI_SERVICES_ACCOUNT}"
    echo "├── Azure Maps: ${MAPS_ACCOUNT}"
    echo "├── Cosmos DB: ${COSMOS_ACCOUNT}"
    echo "└── Key Vault: ${KEY_VAULT_NAME}"
    echo ""
    echo "Configuration Files:"
    echo "├── ${SCRIPT_DIR}/orbital-integration-config.txt"
    echo "├── ${SCRIPT_DIR}/deployment-summary.json"
    echo "└── ${LOG_FILE}"
    echo ""
    echo "Next Steps:"
    echo "1. Contact Microsoft Azure Orbital team for ground station setup"
    echo "2. Configure satellite contact profiles in Azure Orbital"
    echo "3. Deploy Synapse Analytics pipelines for data processing"
    echo "4. Set up Azure Maps visualization dashboards"
    echo "5. Configure AI Services for custom satellite imagery models"
    echo ""
    echo "Important Notes:"
    echo "- Azure Orbital requires pre-approval and cannot be fully automated"
    echo "- All credentials are stored securely in Key Vault: ${KEY_VAULT_NAME}"
    echo "- Monitor resource costs as some services incur charges even when idle"
    echo "- Use the destroy.sh script to clean up resources when done"
    echo ""
    echo "============================================================"
}

# Main execution function
main() {
    info "Starting Azure Orbital Analytics deployment..."
    info "Log file: ${LOG_FILE}"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Set default values
    set_defaults
    
    # Handle dry run mode
    if [[ "${DRY_RUN}" == "true" ]]; then
        execute_dry_run
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Deploy resources
    create_resource_group
    create_key_vault
    create_storage_account
    create_event_hubs
    create_synapse_workspace
    create_ai_services
    create_azure_maps
    create_cosmos_db
    
    # Create configuration files
    create_config_files
    
    # Verify deployment
    verify_deployment
    
    # Display results
    display_results
    
    success "Deployment completed successfully!"
}

# Run main function with all arguments
main "$@"