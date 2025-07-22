#!/bin/bash

# Deploy script for Creating Accessible AI-Powered Customer Service Bots
# with Azure Immersive Reader and Bot Framework
# Version: 1.0
# Provider: Azure

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Default configuration
DEFAULT_LOCATION="eastus"
DEFAULT_RESOURCE_GROUP_PREFIX="rg-accessible-bot"
DEFAULT_BOT_NAME="accessible-customer-bot"
DEFAULT_APP_SERVICE_PLAN="asp-accessible-bot"
DRY_RUN=false
SKIP_CONFIRMATION=false

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Immersive Reader and Bot Framework resources for accessible customer service.

OPTIONS:
    -h, --help                Show this help message
    -l, --location LOCATION   Azure region (default: $DEFAULT_LOCATION)
    -r, --resource-group RG   Resource group name (default: auto-generated)
    -b, --bot-name NAME       Bot name (default: $DEFAULT_BOT_NAME)
    -p, --plan-name NAME      App Service Plan name (default: $DEFAULT_APP_SERVICE_PLAN)
    -d, --dry-run            Show what would be deployed without creating resources
    -y, --yes                Skip confirmation prompts
    -v, --verbose            Enable verbose logging

EXAMPLES:
    $0                                    # Deploy with default settings
    $0 -l westus2 -r my-bot-rg           # Deploy to specific region and resource group
    $0 --dry-run                         # Preview deployment without creating resources
    $0 --yes                             # Deploy without confirmation prompts

EOF
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
        -r|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -b|--bot-name)
            BOT_NAME="$2"
            shift 2
            ;;
        -p|--plan-name)
            APP_SERVICE_PLAN="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Set default values if not provided
LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
BOT_NAME="${BOT_NAME:-$DEFAULT_BOT_NAME}"
APP_SERVICE_PLAN="${APP_SERVICE_PLAN:-$DEFAULT_APP_SERVICE_PLAN}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
RESOURCE_GROUP="${RESOURCE_GROUP:-${DEFAULT_RESOURCE_GROUP_PREFIX}-${RANDOM_SUFFIX}}"

# Derived resource names
IMMERSIVE_READER_NAME="immersive-reader-${RANDOM_SUFFIX}"
LUIS_APP_NAME="customer-service-luis-${RANDOM_SUFFIX}"
KEY_VAULT_NAME="kv-bot-${RANDOM_SUFFIX}"
STORAGE_ACCOUNT_NAME="stbot${RANDOM_SUFFIX}"
APP_SERVICE_NAME="app-accessible-bot-${RANDOM_SUFFIX}"

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is required but not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '\"azure-cli\"' -o tsv 2>/dev/null || echo "unknown")
    info "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get subscription information
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    info "Using subscription: $subscription_name ($subscription_id)"
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        warn "openssl not found. Using alternative random generation method."
    fi
    
    # Validate location
    if ! az account list-locations --query "[?name=='$LOCATION']" --output tsv | grep -q "$LOCATION"; then
        error "Invalid location: $LOCATION"
        exit 1
    fi
    
    # Check resource providers
    local providers=("Microsoft.CognitiveServices" "Microsoft.BotService" "Microsoft.KeyVault" "Microsoft.Storage" "Microsoft.Web" "Microsoft.Insights")
    for provider in "${providers[@]}"; do
        local state=$(az provider show --namespace "$provider" --query registrationState --output tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$state" != "Registered" ]]; then
            warn "Provider $provider is not registered. Registering..."
            if [[ "$DRY_RUN" == "false" ]]; then
                az provider register --namespace "$provider" --wait
            fi
        fi
    done
    
    log "Prerequisites check completed successfully"
}

# Display deployment plan
show_deployment_plan() {
    cat << EOF

${BLUE}=== DEPLOYMENT PLAN ===${NC}

Resource Group: $RESOURCE_GROUP
Location: $LOCATION
Random Suffix: $RANDOM_SUFFIX

Resources to be created:
├── Immersive Reader Service: $IMMERSIVE_READER_NAME
├── LUIS Authoring Service: $LUIS_APP_NAME
├── LUIS Runtime Service: ${LUIS_APP_NAME}-runtime
├── Key Vault: $KEY_VAULT_NAME
├── Storage Account: $STORAGE_ACCOUNT_NAME
├── App Service Plan: $APP_SERVICE_PLAN
├── Web App: $APP_SERVICE_NAME
├── Bot Registration: $BOT_NAME
└── Application Insights: $APP_SERVICE_NAME

Estimated monthly cost: \$15-30 (development tier)

EOF
}

# Confirmation prompt
confirm_deployment() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo -n "Do you want to proceed with the deployment? (y/N): "
    read -r response
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            info "Deployment cancelled by user"
            exit 0
            ;;
    esac
}

# Execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] $description"
        info "[DRY RUN] Command: $cmd"
        return 0
    fi
    
    info "$description"
    if eval "$cmd"; then
        log "✅ $description - Success"
        return 0
    else
        error "❌ $description - Failed"
        return 1
    fi
}

# Create resource group
create_resource_group() {
    local cmd="az group create --name '$RESOURCE_GROUP' --location '$LOCATION' --tags purpose=accessibility-demo environment=development compliance=accessibility"
    execute_cmd "$cmd" "Creating resource group: $RESOURCE_GROUP"
}

# Create Immersive Reader service
create_immersive_reader() {
    local cmd="az cognitiveservices account create --name '$IMMERSIVE_READER_NAME' --resource-group '$RESOURCE_GROUP' --location '$LOCATION' --kind ImmersiveReader --sku S0 --custom-domain '$IMMERSIVE_READER_NAME' --tags purpose=accessibility service=immersive-reader"
    execute_cmd "$cmd" "Creating Immersive Reader service: $IMMERSIVE_READER_NAME"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for service to be ready
        info "Waiting for Immersive Reader service to be ready..."
        local max_attempts=30
        local attempt=0
        while [[ $attempt -lt $max_attempts ]]; do
            local state=$(az cognitiveservices account show --name "$IMMERSIVE_READER_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.provisioningState" --output tsv 2>/dev/null || echo "Unknown")
            if [[ "$state" == "Succeeded" ]]; then
                log "Immersive Reader service is ready"
                break
            fi
            sleep 10
            ((attempt++))
        done
        
        if [[ $attempt -eq $max_attempts ]]; then
            error "Immersive Reader service failed to become ready within expected time"
            return 1
        fi
    fi
}

# Create LUIS services
create_luis_services() {
    local cmd1="az cognitiveservices account create --name '$LUIS_APP_NAME' --resource-group '$RESOURCE_GROUP' --location '$LOCATION' --kind LUIS.Authoring --sku F0 --tags purpose=language-understanding service=luis"
    execute_cmd "$cmd1" "Creating LUIS Authoring service: $LUIS_APP_NAME"
    
    local cmd2="az cognitiveservices account create --name '${LUIS_APP_NAME}-runtime' --resource-group '$RESOURCE_GROUP' --location '$LOCATION' --kind LUIS --sku S0 --tags purpose=language-understanding service=luis-runtime"
    execute_cmd "$cmd2" "Creating LUIS Runtime service: ${LUIS_APP_NAME}-runtime"
}

# Create Key Vault
create_key_vault() {
    local cmd="az keyvault create --name '$KEY_VAULT_NAME' --resource-group '$RESOURCE_GROUP' --location '$LOCATION' --sku standard --enable-rbac-authorization false --tags purpose=secure-configuration service=key-vault"
    execute_cmd "$cmd" "Creating Key Vault: $KEY_VAULT_NAME"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for Key Vault to be ready
        info "Waiting for Key Vault to be ready..."
        sleep 30
        
        # Store secrets
        local immersive_reader_key=$(az cognitiveservices account keys list --name "$IMMERSIVE_READER_NAME" --resource-group "$RESOURCE_GROUP" --query "key1" --output tsv)
        local immersive_reader_endpoint=$(az cognitiveservices account show --name "$IMMERSIVE_READER_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.endpoint" --output tsv)
        local luis_authoring_key=$(az cognitiveservices account keys list --name "$LUIS_APP_NAME" --resource-group "$RESOURCE_GROUP" --query "key1" --output tsv)
        local luis_authoring_endpoint=$(az cognitiveservices account show --name "$LUIS_APP_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.endpoint" --output tsv)
        
        info "Storing secrets in Key Vault..."
        az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "ImmersiveReaderKey" --value "$immersive_reader_key" > /dev/null
        az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "ImmersiveReaderEndpoint" --value "$immersive_reader_endpoint" > /dev/null
        az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "LuisAuthoringKey" --value "$luis_authoring_key" > /dev/null
        az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "LuisAuthoringEndpoint" --value "$luis_authoring_endpoint" > /dev/null
        
        log "✅ Secrets stored in Key Vault"
    fi
}

# Create Storage Account
create_storage_account() {
    local cmd="az storage account create --name '$STORAGE_ACCOUNT_NAME' --resource-group '$RESOURCE_GROUP' --location '$LOCATION' --sku Standard_LRS --kind StorageV2 --access-tier Hot --tags purpose=bot-state service=storage"
    execute_cmd "$cmd" "Creating Storage Account: $STORAGE_ACCOUNT_NAME"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Get storage connection string and store in Key Vault
        local storage_connection_string=$(az storage account show-connection-string --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" --query "connectionString" --output tsv)
        az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "StorageConnectionString" --value "$storage_connection_string" > /dev/null
        log "✅ Storage connection string stored in Key Vault"
    fi
}

# Create App Service Plan and Web App
create_app_service() {
    local cmd1="az appservice plan create --name '$APP_SERVICE_PLAN' --resource-group '$RESOURCE_GROUP' --location '$LOCATION' --sku B1 --is-linux --tags purpose=bot-hosting service=app-service"
    execute_cmd "$cmd1" "Creating App Service Plan: $APP_SERVICE_PLAN"
    
    local cmd2="az webapp create --name '$APP_SERVICE_NAME' --resource-group '$RESOURCE_GROUP' --plan '$APP_SERVICE_PLAN' --runtime 'NODE:18-lts' --tags purpose=accessible-bot service=web-app"
    execute_cmd "$cmd2" "Creating Web App: $APP_SERVICE_NAME"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Configure managed identity
        info "Configuring managed identity for Web App..."
        az webapp identity assign --name "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" > /dev/null
        
        # Get managed identity principal ID
        local principal_id=$(az webapp identity show --name "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" --query "principalId" --output tsv)
        
        # Grant Key Vault access
        az keyvault set-policy --name "$KEY_VAULT_NAME" --object-id "$principal_id" --secret-permissions get list > /dev/null
        log "✅ Key Vault access configured for Web App"
    fi
}

# Create Bot Framework registration
create_bot_registration() {
    local cmd="az bot create --name '$BOT_NAME' --resource-group '$RESOURCE_GROUP' --kind registration --endpoint 'https://${APP_SERVICE_NAME}.azurewebsites.net/api/messages' --msi-resource-group '$RESOURCE_GROUP' --tags purpose=accessible-bot service=bot-framework"
    execute_cmd "$cmd" "Creating Bot Framework registration: $BOT_NAME"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Get bot application ID and store in Key Vault
        local bot_app_id=$(az bot show --name "$BOT_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.msaAppId" --output tsv)
        az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "BotAppId" --value "$bot_app_id" > /dev/null
        log "✅ Bot credentials stored in Key Vault"
    fi
}

# Create Application Insights
create_application_insights() {
    local cmd="az monitor app-insights component create --app '$APP_SERVICE_NAME' --location '$LOCATION' --resource-group '$RESOURCE_GROUP' --tags purpose=monitoring service=app-insights"
    execute_cmd "$cmd" "Creating Application Insights: $APP_SERVICE_NAME"
}

# Configure Web App settings
configure_web_app_settings() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Configuring Web App settings with Key Vault references"
        return 0
    fi
    
    info "Configuring Web App settings with Key Vault references..."
    
    # Get Application Insights instrumentation key
    local appinsights_key=$(az monitor app-insights component show --app "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" --query "instrumentationKey" --output tsv)
    
    # Configure app settings
    az webapp config appsettings set \
        --name "$APP_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
        "MicrosoftAppId=@Microsoft.KeyVault(VaultName=${KEY_VAULT_NAME};SecretName=BotAppId)" \
        "ImmersiveReaderKey=@Microsoft.KeyVault(VaultName=${KEY_VAULT_NAME};SecretName=ImmersiveReaderKey)" \
        "ImmersiveReaderEndpoint=@Microsoft.KeyVault(VaultName=${KEY_VAULT_NAME};SecretName=ImmersiveReaderEndpoint)" \
        "LuisAuthoringKey=@Microsoft.KeyVault(VaultName=${KEY_VAULT_NAME};SecretName=LuisAuthoringKey)" \
        "LuisAuthoringEndpoint=@Microsoft.KeyVault(VaultName=${KEY_VAULT_NAME};SecretName=LuisAuthoringEndpoint)" \
        "StorageConnectionString=@Microsoft.KeyVault(VaultName=${KEY_VAULT_NAME};SecretName=StorageConnectionString)" \
        "APPINSIGHTS_INSTRUMENTATIONKEY=$appinsights_key" \
        "NODE_ENV=production" \
        > /dev/null
    
    log "✅ Web App settings configured with Key Vault integration"
}

# Validate deployment
validate_deployment() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Skipping validation"
        return 0
    fi
    
    log "Validating deployment..."
    
    # Check resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group validation failed"
        return 1
    fi
    
    # Check all resources exist
    local resources=("$IMMERSIVE_READER_NAME" "$LUIS_APP_NAME" "$KEY_VAULT_NAME" "$STORAGE_ACCOUNT_NAME" "$APP_SERVICE_NAME" "$BOT_NAME")
    for resource in "${resources[@]}"; do
        if ! az resource show --resource-group "$RESOURCE_GROUP" --name "$resource" &> /dev/null; then
            error "Resource validation failed for: $resource"
            return 1
        fi
    done
    
    # Check Key Vault secrets
    local secrets=("ImmersiveReaderKey" "ImmersiveReaderEndpoint" "LuisAuthoringKey" "LuisAuthoringEndpoint" "StorageConnectionString" "BotAppId")
    for secret in "${secrets[@]}"; do
        if ! az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$secret" &> /dev/null; then
            error "Secret validation failed for: $secret"
            return 1
        fi
    done
    
    log "✅ Deployment validation completed successfully"
}

# Display deployment summary
show_deployment_summary() {
    cat << EOF

${GREEN}=== DEPLOYMENT SUMMARY ===${NC}

Resource Group: $RESOURCE_GROUP
Location: $LOCATION

Resources Created:
├── Immersive Reader Service: $IMMERSIVE_READER_NAME
├── LUIS Authoring Service: $LUIS_APP_NAME
├── LUIS Runtime Service: ${LUIS_APP_NAME}-runtime
├── Key Vault: $KEY_VAULT_NAME
├── Storage Account: $STORAGE_ACCOUNT_NAME
├── App Service Plan: $APP_SERVICE_PLAN
├── Web App: $APP_SERVICE_NAME
├── Bot Registration: $BOT_NAME
└── Application Insights: $APP_SERVICE_NAME

Web App URL: https://$APP_SERVICE_NAME.azurewebsites.net
Bot Framework Endpoint: https://$APP_SERVICE_NAME.azurewebsites.net/api/messages

Next Steps:
1. Deploy your bot application code to the Web App
2. Configure LUIS model and intents
3. Test the bot accessibility features
4. Set up monitoring and alerts

To clean up resources, run: ./destroy.sh -r $RESOURCE_GROUP

EOF
}

# Main deployment function
main() {
    log "Starting deployment of Azure Immersive Reader Bot Framework solution..."
    
    # Check prerequisites
    check_prerequisites
    
    # Show deployment plan
    show_deployment_plan
    
    # Confirm deployment
    confirm_deployment
    
    # Execute deployment steps
    create_resource_group || exit 1
    create_immersive_reader || exit 1
    create_luis_services || exit 1
    create_key_vault || exit 1
    create_storage_account || exit 1
    create_app_service || exit 1
    create_bot_registration || exit 1
    create_application_insights || exit 1
    configure_web_app_settings || exit 1
    
    # Validate deployment
    validate_deployment || exit 1
    
    # Show summary
    show_deployment_summary
    
    log "Deployment completed successfully!"
}

# Error handling
trap 'error "Deployment failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"