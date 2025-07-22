#!/bin/bash

# Deploy Azure Container Apps Dynamic Sessions with Event Grid
# This script implements secure code execution workflows using Azure Container Apps Dynamic Sessions and Azure Event Grid

set -euo pipefail

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running in debug mode
DEBUG=${DEBUG:-false}
if [[ "${DEBUG}" == "true" ]]; then
    set -x
fi

# Configuration
LOCATION="${LOCATION:-eastus}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-secure-code-execution}"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version (minimum 2.62.0)
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    local min_version="2.62.0"
    if [[ "$(printf '%s\n' "$min_version" "$az_version" | sort -V | head -n1)" != "$min_version" ]]; then
        log_error "Azure CLI version $az_version is below minimum required version $min_version"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Container Apps extension is available
    log "Checking Container Apps extension..."
    if ! az extension show --name containerapp &> /dev/null; then
        log "Installing Container Apps extension..."
        az extension add --name containerapp --yes
    else
        log "Updating Container Apps extension..."
        az extension update --name containerapp
    fi
    
    log_success "Prerequisites check completed"
}

# Generate unique suffix
generate_suffix() {
    if command -v openssl &> /dev/null; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    else
        RANDOM_SUFFIX=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 6 | head -n 1)
    fi
    echo $RANDOM_SUFFIX
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(generate_suffix)
    
    # Set specific resource names
    export CONTAINERAPPS_ENVIRONMENT="cae-code-exec-${RANDOM_SUFFIX}"
    export SESSION_POOL_NAME="pool-code-exec-${RANDOM_SUFFIX}"
    export EVENT_GRID_TOPIC="egt-code-exec-${RANDOM_SUFFIX}"
    export KEY_VAULT_NAME="kv-code-exec-${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_WORKSPACE="law-code-exec-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stcodeexec${RANDOM_SUFFIX}"
    export FUNCTION_APP_NAME="func-session-mgmt-${RANDOM_SUFFIX}"
    export APP_INSIGHTS_NAME="ai-code-exec-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured with suffix: ${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
LOCATION=${LOCATION}
RESOURCE_GROUP=${RESOURCE_GROUP}
CONTAINERAPPS_ENVIRONMENT=${CONTAINERAPPS_ENVIRONMENT}
SESSION_POOL_NAME=${SESSION_POOL_NAME}
EVENT_GRID_TOPIC=${EVENT_GRID_TOPIC}
KEY_VAULT_NAME=${KEY_VAULT_NAME}
LOG_ANALYTICS_WORKSPACE=${LOG_ANALYTICS_WORKSPACE}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME}
APP_INSIGHTS_NAME=${APP_INSIGHTS_NAME}
DEPLOYMENT_DATE=$(date +'%Y-%m-%d %H:%M:%S')
EOF
    
    log_success "Environment variables saved to .env file"
}

# Create resource group
create_resource_group() {
    log "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --tags purpose=recipe environment=demo deployment-script=true
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Create Log Analytics workspace
create_log_analytics() {
    log "Creating Log Analytics workspace: ${LOG_ANALYTICS_WORKSPACE}"
    
    if az monitor log-analytics workspace show \
        --resource-group ${RESOURCE_GROUP} \
        --workspace-name ${LOG_ANALYTICS_WORKSPACE} &> /dev/null; then
        log_warning "Log Analytics workspace ${LOG_ANALYTICS_WORKSPACE} already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group ${RESOURCE_GROUP} \
            --workspace-name ${LOG_ANALYTICS_WORKSPACE} \
            --location ${LOCATION} \
            --tags purpose=recipe environment=demo
        
        log_success "Log Analytics workspace created: ${LOG_ANALYTICS_WORKSPACE}"
    fi
}

# Create Key Vault
create_key_vault() {
    log "Creating Key Vault: ${KEY_VAULT_NAME}"
    
    if az keyvault show --name ${KEY_VAULT_NAME} &> /dev/null; then
        log_warning "Key Vault ${KEY_VAULT_NAME} already exists"
    else
        az keyvault create \
            --name ${KEY_VAULT_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --sku standard \
            --enable-rbac-authorization \
            --tags purpose=recipe environment=demo
        
        log_success "Key Vault created: ${KEY_VAULT_NAME}"
    fi
}

# Create Container Apps Environment
create_container_apps_environment() {
    log "Creating Container Apps Environment: ${CONTAINERAPPS_ENVIRONMENT}"
    
    if az containerapp env show \
        --name ${CONTAINERAPPS_ENVIRONMENT} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log_warning "Container Apps Environment ${CONTAINERAPPS_ENVIRONMENT} already exists"
    else
        # Get Log Analytics workspace details
        local workspace_id=$(az monitor log-analytics workspace show \
            --resource-group ${RESOURCE_GROUP} \
            --workspace-name ${LOG_ANALYTICS_WORKSPACE} \
            --query customerId --output tsv)
        
        local workspace_key=$(az monitor log-analytics workspace \
            get-shared-keys --resource-group ${RESOURCE_GROUP} \
            --workspace-name ${LOG_ANALYTICS_WORKSPACE} \
            --query primarySharedKey --output tsv)
        
        az containerapp env create \
            --name ${CONTAINERAPPS_ENVIRONMENT} \
            --resource-group ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --logs-workspace-id ${workspace_id} \
            --logs-workspace-key ${workspace_key} \
            --tags purpose=recipe environment=demo
        
        log_success "Container Apps Environment created: ${CONTAINERAPPS_ENVIRONMENT}"
    fi
}

# Create Dynamic Session Pool
create_session_pool() {
    log "Creating Dynamic Session Pool: ${SESSION_POOL_NAME}"
    
    if az containerapp sessionpool show \
        --name ${SESSION_POOL_NAME} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log_warning "Session Pool ${SESSION_POOL_NAME} already exists"
    else
        az containerapp sessionpool create \
            --name ${SESSION_POOL_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --environment ${CONTAINERAPPS_ENVIRONMENT} \
            --container-type PythonLTS \
            --max-sessions 20 \
            --ready-sessions 5 \
            --cooldown-period 300 \
            --network-status EgressDisabled \
            --tags purpose=recipe environment=demo
        
        log_success "Session Pool created: ${SESSION_POOL_NAME}"
    fi
}

# Create Event Grid Topic
create_event_grid_topic() {
    log "Creating Event Grid Topic: ${EVENT_GRID_TOPIC}"
    
    if az eventgrid topic show \
        --name ${EVENT_GRID_TOPIC} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log_warning "Event Grid Topic ${EVENT_GRID_TOPIC} already exists"
    else
        az eventgrid topic create \
            --name ${EVENT_GRID_TOPIC} \
            --resource-group ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --tags purpose=code-execution environment=demo
        
        log_success "Event Grid Topic created: ${EVENT_GRID_TOPIC}"
    fi
    
    # Get topic endpoint and key
    export TOPIC_ENDPOINT=$(az eventgrid topic show \
        --name ${EVENT_GRID_TOPIC} \
        --resource-group ${RESOURCE_GROUP} \
        --query endpoint --output tsv)
    
    export TOPIC_KEY=$(az eventgrid topic key list \
        --name ${EVENT_GRID_TOPIC} \
        --resource-group ${RESOURCE_GROUP} \
        --query key1 --output tsv)
    
    log_success "Event Grid Topic endpoint and key retrieved"
}

# Create Storage Account
create_storage_account() {
    log "Creating Storage Account: ${STORAGE_ACCOUNT}"
    
    if az storage account show \
        --name ${STORAGE_ACCOUNT} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log_warning "Storage Account ${STORAGE_ACCOUNT} already exists"
    else
        az storage account create \
            --name ${STORAGE_ACCOUNT} \
            --resource-group ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            --https-only true \
            --min-tls-version TLS1_2 \
            --tags purpose=recipe environment=demo
        
        log_success "Storage Account created: ${STORAGE_ACCOUNT}"
    fi
    
    # Create containers
    log "Creating storage containers..."
    
    if ! az storage container show \
        --name execution-results \
        --account-name ${STORAGE_ACCOUNT} \
        --auth-mode login &> /dev/null; then
        az storage container create \
            --name execution-results \
            --account-name ${STORAGE_ACCOUNT} \
            --auth-mode login
        log_success "Created execution-results container"
    fi
    
    if ! az storage container show \
        --name execution-logs \
        --account-name ${STORAGE_ACCOUNT} \
        --auth-mode login &> /dev/null; then
        az storage container create \
            --name execution-logs \
            --account-name ${STORAGE_ACCOUNT} \
            --auth-mode login
        log_success "Created execution-logs container"
    fi
}

# Create Function App
create_function_app() {
    log "Creating Function App: ${FUNCTION_APP_NAME}"
    
    if az functionapp show \
        --name ${FUNCTION_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log_warning "Function App ${FUNCTION_APP_NAME} already exists"
    else
        az functionapp create \
            --name ${FUNCTION_APP_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --storage-account ${STORAGE_ACCOUNT} \
            --consumption-plan-location ${LOCATION} \
            --runtime python \
            --runtime-version 3.11 \
            --functions-version 4 \
            --os-type Linux \
            --tags purpose=recipe environment=demo
        
        log_success "Function App created: ${FUNCTION_APP_NAME}"
    fi
    
    # Configure app settings
    log "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name ${FUNCTION_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --settings \
            "SESSION_POOL_ENDPOINT=https://${SESSION_POOL_NAME}.${LOCATION}.azurecontainerapps.io" \
            "KEY_VAULT_URL=https://${KEY_VAULT_NAME}.vault.azure.net/" \
            "STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT}"
    
    log_success "Function App settings configured"
}

# Configure Key Vault Integration
configure_key_vault_integration() {
    log "Configuring Key Vault integration..."
    
    # Enable managed identity for Function App
    az functionapp identity assign \
        --name ${FUNCTION_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} > /dev/null
    
    # Get Function App principal ID
    export FUNCTION_PRINCIPAL_ID=$(az functionapp identity show \
        --name ${FUNCTION_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query principalId --output tsv)
    
    # Assign Key Vault permissions
    az keyvault set-policy \
        --name ${KEY_VAULT_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --object-id ${FUNCTION_PRINCIPAL_ID} \
        --secret-permissions get list
    
    # Store session pool access token in Key Vault
    local access_token=$(az account get-access-token \
        --resource https://management.azure.com \
        --query accessToken --output tsv)
    
    az keyvault secret set \
        --vault-name ${KEY_VAULT_NAME} \
        --name session-pool-token \
        --value "${access_token}" > /dev/null
    
    log_success "Key Vault integration configured"
}

# Create Application Insights
create_application_insights() {
    log "Creating Application Insights: ${APP_INSIGHTS_NAME}"
    
    if az monitor app-insights component show \
        --app ${APP_INSIGHTS_NAME} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log_warning "Application Insights ${APP_INSIGHTS_NAME} already exists"
    else
        local workspace_id=$(az monitor log-analytics workspace show \
            --resource-group ${RESOURCE_GROUP} \
            --workspace-name ${LOG_ANALYTICS_WORKSPACE} \
            --query id --output tsv)
        
        az monitor app-insights component create \
            --app ${APP_INSIGHTS_NAME} \
            --location ${LOCATION} \
            --resource-group ${RESOURCE_GROUP} \
            --workspace ${workspace_id} \
            --tags purpose=recipe environment=demo
        
        log_success "Application Insights created: ${APP_INSIGHTS_NAME}"
    fi
    
    # Configure Function App to use Application Insights
    local instrumentation_key=$(az monitor app-insights component show \
        --app ${APP_INSIGHTS_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query instrumentationKey --output tsv)
    
    az functionapp config appsettings set \
        --name ${FUNCTION_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --settings \
            "APPINSIGHTS_INSTRUMENTATIONKEY=${instrumentation_key}"
    
    log_success "Function App configured with Application Insights"
}

# Create Event Grid Subscription
create_event_grid_subscription() {
    log "Creating Event Grid Subscription..."
    
    # Note: This is a placeholder as we would need an actual Function App endpoint
    # In a real deployment, you would deploy the function code first
    log_warning "Event Grid subscription creation skipped - requires Function App deployment"
    log "To complete setup, deploy your function code and create the subscription manually:"
    echo "az eventgrid event-subscription create \\"
    echo "    --name code-execution-subscription \\"
    echo "    --source-resource-id \$(az eventgrid topic show --name ${EVENT_GRID_TOPIC} --resource-group ${RESOURCE_GROUP} --query id --output tsv) \\"
    echo "    --endpoint-type azurefunction \\"
    echo "    --endpoint <FUNCTION_ENDPOINT> \\"
    echo "    --subject-begins-with \"code-execution\" \\"
    echo "    --included-event-types \"Microsoft.EventGrid.ExecuteCode\""
}

# Validation
validate_deployment() {
    log "Validating deployment..."
    
    local errors=0
    
    # Check session pool status
    if az containerapp sessionpool show \
        --name ${SESSION_POOL_NAME} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log_success "Session pool validation passed"
    else
        log_error "Session pool validation failed"
        ((errors++))
    fi
    
    # Check Event Grid topic
    if az eventgrid topic show \
        --name ${EVENT_GRID_TOPIC} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log_success "Event Grid topic validation passed"
    else
        log_error "Event Grid topic validation failed"
        ((errors++))
    fi
    
    # Check Key Vault
    if az keyvault show --name ${KEY_VAULT_NAME} &> /dev/null; then
        log_success "Key Vault validation passed"
    else
        log_error "Key Vault validation failed"
        ((errors++))
    fi
    
    # Check Function App
    if az functionapp show \
        --name ${FUNCTION_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log_success "Function App validation passed"
    else
        log_error "Function App validation failed"
        ((errors++))
    fi
    
    if [[ ${errors} -eq 0 ]]; then
        log_success "All validations passed"
        return 0
    else
        log_error "Validation failed with ${errors} errors"
        return 1
    fi
}

# Display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "==================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Container Apps Environment: ${CONTAINERAPPS_ENVIRONMENT}"
    echo "Session Pool: ${SESSION_POOL_NAME}"
    echo "Event Grid Topic: ${EVENT_GRID_TOPIC}"
    echo "Key Vault: ${KEY_VAULT_NAME}"
    echo "Storage Account: ${STORAGE_ACCOUNT}"
    echo "Function App: ${FUNCTION_APP_NAME}"
    echo "Application Insights: ${APP_INSIGHTS_NAME}"
    echo "Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE}"
    echo "==================="
    echo "Event Grid Topic Endpoint: ${TOPIC_ENDPOINT:-Not available}"
    echo "Event Grid Topic Key: ${TOPIC_KEY:-Not available}"
    echo "==================="
    echo "Environment file saved as: .env"
    echo "Use this file with the destroy.sh script for cleanup"
}

# Cleanup on error
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial deployment..."
    if [[ -f .env ]]; then
        source .env
        ./destroy.sh --force --quiet
    fi
}

# Main deployment function
main() {
    log "Starting Azure Container Apps Dynamic Sessions deployment..."
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    check_prerequisites
    setup_environment
    create_resource_group
    create_log_analytics
    create_key_vault
    create_container_apps_environment
    create_session_pool
    create_event_grid_topic
    create_storage_account
    create_function_app
    configure_key_vault_integration
    create_application_insights
    create_event_grid_subscription
    
    if validate_deployment; then
        display_summary
        log_success "Deployment completed successfully!"
        echo ""
        echo "Next steps:"
        echo "1. Deploy your Function App code for session management"
        echo "2. Create the Event Grid subscription"
        echo "3. Test the secure code execution workflow"
        echo ""
        echo "Estimated monthly cost: \$50-100 for development/testing workloads"
    else
        log_error "Deployment validation failed"
        exit 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Deploy Azure Container Apps Dynamic Sessions with Event Grid"
            echo ""
            echo "Options:"
            echo "  --help, -h           Show this help message"
            echo "  --location LOCATION  Azure region (default: eastus)"
            echo "  --resource-group RG  Resource group name (default: rg-secure-code-execution)"
            echo "  --debug              Enable debug mode"
            echo ""
            echo "Environment variables:"
            echo "  LOCATION             Azure region override"
            echo "  RESOURCE_GROUP       Resource group name override"
            echo "  DEBUG                Enable debug mode (true/false)"
            exit 0
            ;;
        --location)
            LOCATION="$2"
            shift 2
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"