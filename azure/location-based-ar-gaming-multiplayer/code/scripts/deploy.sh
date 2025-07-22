#!/bin/bash

# Deploy Azure PlayFab and Spatial Anchors Gaming Infrastructure
# This script creates all necessary Azure resources for location-based AR gaming

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if running in debug mode
DEBUG=${DEBUG:-false}
if [[ "$DEBUG" == "true" ]]; then
    set -x
fi

# Configuration variables
RESOURCE_GROUP_PREFIX="rg-ar-gaming"
LOCATION="${LOCATION:-eastus}"
PLAYFAB_TITLE="${PLAYFAB_TITLE:-ARGaming}"
DEPLOYMENT_NAME="ar-gaming-deploy-$(date +%s)"

# Generate unique suffix for resources
RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
RESOURCE_GROUP="${RESOURCE_GROUP_PREFIX}-${RANDOM_SUFFIX}"

# Resource names
SPATIAL_ANCHORS_ACCOUNT="sa-${RANDOM_SUFFIX}"
STORAGE_ACCOUNT="st${RANDOM_SUFFIX}"
FUNCTION_APP="func-ar-gaming-${RANDOM_SUFFIX}"
AD_APP_NAME="ARGaming-MR-${RANDOM_SUFFIX}"

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first"
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        warning "openssl not found. Using fallback random generation"
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        warning "curl not found. Some API testing features may not work"
    fi
    
    # Verify Azure CLI version
    local cli_version=$(az --version | head -n 1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
    log "Using Azure CLI version: $cli_version"
    
    success "Prerequisites check completed"
}

# Initialize Azure resources
initialize_azure() {
    log "Initializing Azure resources..."
    
    # Get subscription information
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    log "Using subscription: $SUBSCRIPTION_ID"
    
    # Create resource group
    log "Creating resource group: $RESOURCE_GROUP"
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=recipe environment=demo project=ar-gaming \
        --output none
    
    if [[ $? -eq 0 ]]; then
        success "Resource group created: $RESOURCE_GROUP"
    else
        error "Failed to create resource group"
    fi
    
    # Store resource group name for cleanup
    echo "$RESOURCE_GROUP" > .resource_group_name
}

# Create Azure Spatial Anchors account
create_spatial_anchors() {
    log "Creating Azure Spatial Anchors account..."
    
    # Check if Mixed Reality provider is registered
    log "Registering Mixed Reality provider..."
    az provider register --namespace Microsoft.MixedReality --wait
    
    # Create Spatial Anchors account
    az spatialanchors-account create \
        --name "$SPATIAL_ANCHORS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --output none
    
    if [[ $? -eq 0 ]]; then
        success "Spatial Anchors account created: $SPATIAL_ANCHORS_ACCOUNT"
    else
        error "Failed to create Spatial Anchors account"
    fi
    
    # Get account details
    export ASA_ACCOUNT_ID=$(az spatialanchors-account show \
        --name "$SPATIAL_ANCHORS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query accountId --output tsv)
    
    export ASA_ACCOUNT_DOMAIN=$(az spatialanchors-account show \
        --name "$SPATIAL_ANCHORS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query accountDomain --output tsv)
    
    log "Spatial Anchors Account ID: $ASA_ACCOUNT_ID"
    log "Spatial Anchors Account Domain: $ASA_ACCOUNT_DOMAIN"
}

# Create storage account
create_storage_account() {
    log "Creating storage account..."
    
    # Create storage account
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        --min-tls-version TLS1_2 \
        --output none
    
    if [[ $? -eq 0 ]]; then
        success "Storage account created: $STORAGE_ACCOUNT"
    else
        error "Failed to create storage account"
    fi
    
    # Configure CORS for PlayFab integration
    log "Configuring CORS for PlayFab integration..."
    az storage cors add \
        --account-name "$STORAGE_ACCOUNT" \
        --services b \
        --methods GET POST PUT DELETE \
        --origins "https://*.playfab.com" \
        --allowed-headers "*" \
        --max-age 3600 \
        --output none
    
    success "CORS configuration completed"
}

# Create Azure Functions app
create_function_app() {
    log "Creating Azure Functions app..."
    
    # Create Function App
    az functionapp create \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --consumption-plan-location "$LOCATION" \
        --runtime dotnet-isolated \
        --functions-version 4 \
        --storage-account "$STORAGE_ACCOUNT" \
        --os-type Windows \
        --output none
    
    if [[ $? -eq 0 ]]; then
        success "Function App created: $FUNCTION_APP"
    else
        error "Failed to create Function App"
    fi
    
    # Wait for function app to be ready
    log "Waiting for Function App to be ready..."
    sleep 30
    
    # Configure Function App settings
    log "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
        "PlayFabTitleId=${PLAYFAB_TITLE_ID:-placeholder}" \
        "PlayFabSecretKey=${PLAYFAB_SECRET_KEY:-placeholder}" \
        "SpatialAnchorsAccountId=$ASA_ACCOUNT_ID" \
        "SpatialAnchorsAccountDomain=$ASA_ACCOUNT_DOMAIN" \
        "FUNCTIONS_WORKER_RUNTIME=dotnet-isolated" \
        --output none
    
    success "Function App settings configured"
}

# Create Azure AD application for Mixed Reality
create_ad_application() {
    log "Creating Azure AD application for Mixed Reality..."
    
    # Create Azure AD application
    local app_id=$(az ad app create \
        --display-name "$AD_APP_NAME" \
        --sign-in-audience AzureADMyOrg \
        --query appId --output tsv)
    
    if [[ $? -eq 0 ]]; then
        export MR_CLIENT_ID="$app_id"
        success "Azure AD application created: $MR_CLIENT_ID"
    else
        error "Failed to create Azure AD application"
    fi
    
    # Wait for AD application to propagate
    log "Waiting for AD application to propagate..."
    sleep 15
    
    # Create service principal
    log "Creating service principal..."
    az ad sp create --id "$MR_CLIENT_ID" --output none
    
    # Wait for service principal to be ready
    sleep 10
    
    # Configure Mixed Reality authentication
    log "Configuring Mixed Reality authentication..."
    az role assignment create \
        --assignee "$MR_CLIENT_ID" \
        --role "Spatial Anchors Account Reader" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.MixedReality/spatialAnchorsAccounts/$SPATIAL_ANCHORS_ACCOUNT" \
        --output none
    
    success "Mixed Reality authentication configured"
}

# Create Event Grid subscription
create_event_grid() {
    log "Creating Event Grid subscription..."
    
    # Register Event Grid provider
    az provider register --namespace Microsoft.EventGrid --wait
    
    # Create event subscription
    az eventgrid event-subscription create \
        --name "spatial-anchor-events" \
        --source-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.MixedReality/spatialAnchorsAccounts/$SPATIAL_ANCHORS_ACCOUNT" \
        --endpoint-type webhook \
        --endpoint "https://$FUNCTION_APP.azurewebsites.net/api/ProcessSpatialEvent" \
        --output none
    
    if [[ $? -eq 0 ]]; then
        success "Event Grid subscription created"
    else
        warning "Event Grid subscription creation failed - this is expected if the Function App endpoint is not ready"
    fi
}

# Generate configuration files
generate_config_files() {
    log "Generating configuration files..."
    
    # Create Unity configuration
    cat > unity-config.json << EOF
{
    "PlayFabSettings": {
        "TitleId": "${PLAYFAB_TITLE_ID:-placeholder}",
        "DeveloperSecretKey": "${PLAYFAB_SECRET_KEY:-placeholder}"
    },
    "SpatialAnchorsSettings": {
        "AccountId": "$ASA_ACCOUNT_ID",
        "AccountDomain": "$ASA_ACCOUNT_DOMAIN",
        "AccountKey": "$(az spatialanchors-account keys show --name $SPATIAL_ANCHORS_ACCOUNT --resource-group $RESOURCE_GROUP --query primaryKey --output tsv)"
    },
    "FunctionEndpoints": {
        "CreateAnchor": "https://$FUNCTION_APP.azurewebsites.net/api/CreateAnchor",
        "ConfigureLobby": "https://$FUNCTION_APP.azurewebsites.net/api/ConfigureLobby"
    },
    "AzureADSettings": {
        "ClientId": "$MR_CLIENT_ID",
        "TenantId": "$(az account show --query tenantId --output tsv)"
    }
}
EOF
    
    # Create lobby configuration
    cat > lobby-config.json << EOF
{
    "FunctionName": "ConfigureLobby",
    "FunctionVersion": "1.0",
    "Variables": {
        "MaxPlayersPerLocation": 8,
        "LocationRadius": 100,
        "RequiredARCapabilities": ["PlaneDetection", "LightEstimation"]
    },
    "CloudScriptRevision": 1
}
EOF
    
    # Create multiplayer settings
    cat > multiplayer-settings.json << EOF
{
    "BuildId": "ar-gaming-build-$RANDOM_SUFFIX",
    "VMSize": "Standard_D2as_v4",
    "RegionConfigurations": [
        {
            "Region": "EastUS",
            "StandbyServers": 2,
            "MaxServers": 10
        }
    ],
    "NetworkConfiguration": {
        "Ports": [
            {
                "Name": "game_port",
                "Number": 7777,
                "Protocol": "UDP"
            }
        ]
    },
    "SpatialSyncSettings": {
        "SyncFrequency": 30,
        "MaxSyncDistance": 100,
        "EnablePrediction": true
    }
}
EOF
    
    success "Configuration files generated"
}

# Validation and testing
validate_deployment() {
    log "Validating deployment..."
    
    # Test Spatial Anchors account
    log "Testing Spatial Anchors account..."
    local asa_status=$(az spatialanchors-account show \
        --name "$SPATIAL_ANCHORS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query provisioningState --output tsv)
    
    if [[ "$asa_status" == "Succeeded" ]]; then
        success "Spatial Anchors account is ready"
    else
        warning "Spatial Anchors account status: $asa_status"
    fi
    
    # Test Function App
    log "Testing Function App..."
    local func_state=$(az functionapp show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query state --output tsv)
    
    if [[ "$func_state" == "Running" ]]; then
        success "Function App is running"
    else
        warning "Function App state: $func_state"
    fi
    
    # Test storage account
    log "Testing storage account..."
    local storage_status=$(az storage account show \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query provisioningState --output tsv)
    
    if [[ "$storage_status" == "Succeeded" ]]; then
        success "Storage account is ready"
    else
        warning "Storage account status: $storage_status"
    fi
    
    success "Deployment validation completed"
}

# Display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Spatial Anchors Account: $SPATIAL_ANCHORS_ACCOUNT"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "Function App: $FUNCTION_APP"
    echo "AD Application: $AD_APP_NAME"
    echo "Client ID: $MR_CLIENT_ID"
    echo ""
    echo "Configuration Files:"
    echo "- unity-config.json"
    echo "- lobby-config.json"
    echo "- multiplayer-settings.json"
    echo ""
    echo "Next Steps:"
    echo "1. Configure PlayFab Title ID and Secret Key in unity-config.json"
    echo "2. Deploy function code to the Function App"
    echo "3. Set up PlayFab multiplayer configuration"
    echo "4. Test the Unity client integration"
    echo ""
    echo "Important Notes:"
    echo "- Save the resource group name for cleanup: $RESOURCE_GROUP"
    echo "- Function App URL: https://$FUNCTION_APP.azurewebsites.net"
    echo "- Spatial Anchors Account ID: $ASA_ACCOUNT_ID"
    echo ""
    success "Deployment completed successfully!"
}

# Error handling
cleanup_on_error() {
    error "Deployment failed. Cleaning up resources..."
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    fi
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Main execution
main() {
    log "Starting Azure PlayFab and Spatial Anchors deployment..."
    
    check_prerequisites
    initialize_azure
    create_spatial_anchors
    create_storage_account
    create_function_app
    create_ad_application
    create_event_grid
    generate_config_files
    validate_deployment
    display_summary
    
    log "Deployment process completed successfully!"
}

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy Azure PlayFab and Spatial Anchors Gaming Infrastructure"
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help                Show this help message"
    echo "  -l, --location LOCATION   Azure region (default: eastus)"
    echo "  -d, --debug               Enable debug mode"
    echo "  -f, --force               Force deployment even if resources exist"
    echo ""
    echo "ENVIRONMENT VARIABLES:"
    echo "  LOCATION                  Azure region"
    echo "  PLAYFAB_TITLE_ID         PlayFab Title ID"
    echo "  PLAYFAB_SECRET_KEY       PlayFab Secret Key"
    echo "  DEBUG                    Enable debug output (true/false)"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                       Deploy with default settings"
    echo "  $0 -l westus2           Deploy to West US 2 region"
    echo "  $0 -d                   Deploy with debug output"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main "$@"