#!/bin/bash

# Azure Environmental Impact Dashboards Deployment Script
# This script deploys Azure Sustainability Manager and Power BI infrastructure
# for environmental impact tracking and reporting

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
RESOURCE_PREFIX="sustainability"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message function
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message function
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message function
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Check prerequisites function
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error_exit "Not logged into Azure. Please run 'az login' first"
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is required for generating random suffixes"
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
set_environment_variables() {
    info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RESOURCE_GROUP="rg-${RESOURCE_PREFIX}-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export POWERBI_WORKSPACE="${RESOURCE_PREFIX}-workspace"
    
    # Resource names
    export LOG_WORKSPACE="law-${RESOURCE_PREFIX}-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="st${RESOURCE_PREFIX}${RANDOM_SUFFIX}"
    export DATA_FACTORY="adf-${RESOURCE_PREFIX}-${RANDOM_SUFFIX}"
    export CONTAINER_NAME="${RESOURCE_PREFIX}-data"
    export FUNCTION_APP="func-${RESOURCE_PREFIX}-${RANDOM_SUFFIX}"
    export APP_SERVICE_PLAN="asp-powerbi-${RANDOM_SUFFIX}"
    export KEY_VAULT="kv-${RESOURCE_PREFIX:0:7}-${RANDOM_SUFFIX}"
    export LOGIC_APP="la-${RESOURCE_PREFIX}-${RANDOM_SUFFIX}"
    export APP_INSIGHTS="ai-${RESOURCE_PREFIX}-${RANDOM_SUFFIX}"
    
    success "Environment variables configured"
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Location: ${LOCATION}"
    log "Random Suffix: ${RANDOM_SUFFIX}"
}

# Create resource group
create_resource_group() {
    info "Creating resource group: ${RESOURCE_GROUP}..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=sustainability environment=production \
            || error_exit "Failed to create resource group"
        
        success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Create Log Analytics workspace
create_log_analytics_workspace() {
    info "Creating Log Analytics workspace: ${LOG_WORKSPACE}..."
    
    if az monitor log-analytics workspace show --resource-group "${RESOURCE_GROUP}" --workspace-name "${LOG_WORKSPACE}" &> /dev/null; then
        warning "Log Analytics workspace ${LOG_WORKSPACE} already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_WORKSPACE}" \
            --location "${LOCATION}" \
            --sku PerGB2018 \
            || error_exit "Failed to create Log Analytics workspace"
        
        success "Log Analytics workspace created: ${LOG_WORKSPACE}"
    fi
}

# Create storage account
create_storage_account() {
    info "Creating storage account: ${STORAGE_ACCOUNT}..."
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Storage account ${STORAGE_ACCOUNT} already exists"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            || error_exit "Failed to create storage account"
        
        success "Storage account created: ${STORAGE_ACCOUNT}"
    fi
}

# Create Data Factory
create_data_factory() {
    info "Creating Data Factory: ${DATA_FACTORY}..."
    
    if az datafactory show --resource-group "${RESOURCE_GROUP}" --name "${DATA_FACTORY}" &> /dev/null; then
        warning "Data Factory ${DATA_FACTORY} already exists"
    else
        az datafactory create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${DATA_FACTORY}" \
            --location "${LOCATION}" \
            || error_exit "Failed to create Data Factory"
        
        success "Data Factory created: ${DATA_FACTORY}"
    fi
}

# Create storage container
create_storage_container() {
    info "Creating storage container: ${CONTAINER_NAME}..."
    
    # Check if container exists
    if az storage container exists --name "${CONTAINER_NAME}" --account-name "${STORAGE_ACCOUNT}" --auth-mode login --query exists --output tsv | grep -q true; then
        warning "Storage container ${CONTAINER_NAME} already exists"
    else
        az storage container create \
            --name "${CONTAINER_NAME}" \
            --account-name "${STORAGE_ACCOUNT}" \
            --auth-mode login \
            || error_exit "Failed to create storage container"
        
        success "Storage container created: ${CONTAINER_NAME}"
    fi
}

# Create Function App
create_function_app() {
    info "Creating Function App: ${FUNCTION_APP}..."
    
    if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Function App ${FUNCTION_APP} already exists"
    else
        az functionapp create \
            --resource-group "${RESOURCE_GROUP}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime python \
            --runtime-version 3.11 \
            --name "${FUNCTION_APP}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --functions-version 4 \
            || error_exit "Failed to create Function App"
        
        # Configure application settings
        az functionapp config appsettings set \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --settings "EMISSIONS_FACTOR_SOURCE=EPA" \
                       "CALCULATION_METHOD=GHG_PROTOCOL" \
                       "STORAGE_CONNECTION_STRING=DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT};EndpointSuffix=core.windows.net" \
            || error_exit "Failed to configure Function App settings"
        
        success "Function App created and configured: ${FUNCTION_APP}"
    fi
}

# Create App Service Plan
create_app_service_plan() {
    info "Creating App Service Plan: ${APP_SERVICE_PLAN}..."
    
    if az appservice plan show --name "${APP_SERVICE_PLAN}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "App Service Plan ${APP_SERVICE_PLAN} already exists"
    else
        az appservice plan create \
            --name "${APP_SERVICE_PLAN}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku B1 \
            --is-linux \
            || error_exit "Failed to create App Service Plan"
        
        success "App Service Plan created: ${APP_SERVICE_PLAN}"
    fi
}

# Create Key Vault
create_key_vault() {
    info "Creating Key Vault: ${KEY_VAULT}..."
    
    if az keyvault show --name "${KEY_VAULT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Key Vault ${KEY_VAULT} already exists"
    else
        az keyvault create \
            --name "${KEY_VAULT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku standard \
            || error_exit "Failed to create Key Vault"
        
        success "Key Vault created: ${KEY_VAULT}"
    fi
}

# Create Logic App
create_logic_app() {
    info "Creating Logic App: ${LOGIC_APP}..."
    
    if az logic workflow show --resource-group "${RESOURCE_GROUP}" --name "${LOGIC_APP}" &> /dev/null; then
        warning "Logic App ${LOGIC_APP} already exists"
    else
        # Create Logic App with workflow definition
        cat > "/tmp/workflow_definition.json" << 'EOF'
{
    "definition": {
        "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
        "triggers": {
            "Recurrence": {
                "type": "Recurrence",
                "recurrence": {
                    "frequency": "Day",
                    "interval": 1,
                    "startTime": "2024-01-01T06:00:00Z"
                }
            }
        },
        "actions": {
            "RefreshDataset": {
                "type": "Http",
                "inputs": {
                    "method": "POST",
                    "uri": "https://api.powerbi.com/v1.0/myorg/datasets/refresh"
                }
            }
        }
    }
}
EOF
        
        az logic workflow create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${LOGIC_APP}" \
            --location "${LOCATION}" \
            --definition "@/tmp/workflow_definition.json" \
            || error_exit "Failed to create Logic App"
        
        rm -f "/tmp/workflow_definition.json"
        success "Logic App created: ${LOGIC_APP}"
    fi
}

# Create Application Insights
create_application_insights() {
    info "Creating Application Insights: ${APP_INSIGHTS}..."
    
    if az monitor app-insights component show --app "${APP_INSIGHTS}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Application Insights ${APP_INSIGHTS} already exists"
    else
        az monitor app-insights component create \
            --app "${APP_INSIGHTS}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --kind web \
            --application-type web \
            || error_exit "Failed to create Application Insights"
        
        success "Application Insights created: ${APP_INSIGHTS}"
    fi
}

# Create monitoring alerts
create_monitoring_alerts() {
    info "Creating monitoring alerts..."
    
    # Check if alert rule exists
    if az monitor metrics alert show --name "sustainability-data-processing-alert" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Alert rule already exists"
    else
        # Wait for Function App to be fully deployed
        sleep 30
        
        az monitor metrics alert create \
            --name "sustainability-data-processing-alert" \
            --resource-group "${RESOURCE_GROUP}" \
            --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/sites/${FUNCTION_APP}" \
            --condition "count 'FunctionExecutionCount' > 10" \
            --description "Alert when function execution count exceeds threshold" \
            --evaluation-frequency 5m \
            --window-size 15m \
            --severity 2 \
            || warning "Failed to create alert rule (Function App may not be ready)"
        
        success "Monitoring alerts configured"
    fi
}

# Save deployment configuration
save_deployment_config() {
    info "Saving deployment configuration..."
    
    cat > "${SCRIPT_DIR}/deployment_config.env" << EOF
# Azure Environmental Impact Dashboard Deployment Configuration
# Generated on $(date)

export RESOURCE_GROUP="${RESOURCE_GROUP}"
export LOCATION="${LOCATION}"
export SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
export POWERBI_WORKSPACE="${POWERBI_WORKSPACE}"
export LOG_WORKSPACE="${LOG_WORKSPACE}"
export STORAGE_ACCOUNT="${STORAGE_ACCOUNT}"
export DATA_FACTORY="${DATA_FACTORY}"
export CONTAINER_NAME="${CONTAINER_NAME}"
export FUNCTION_APP="${FUNCTION_APP}"
export APP_SERVICE_PLAN="${APP_SERVICE_PLAN}"
export KEY_VAULT="${KEY_VAULT}"
export LOGIC_APP="${LOGIC_APP}"
export APP_INSIGHTS="${APP_INSIGHTS}"
EOF
    
    success "Deployment configuration saved to deployment_config.env"
}

# Main deployment function
main() {
    echo -e "${BLUE}🚀 Starting Azure Environmental Impact Dashboard Deployment${NC}"
    log "Starting deployment process"
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_log_analytics_workspace
    create_storage_account
    create_data_factory
    create_storage_container
    create_function_app
    create_app_service_plan
    create_key_vault
    create_logic_app
    create_application_insights
    create_monitoring_alerts
    save_deployment_config
    
    echo ""
    echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Configure Microsoft Cloud for Sustainability through M365 admin center"
    echo "2. Set up Power BI workspace: ${POWERBI_WORKSPACE}"
    echo "3. Configure data sources in Data Factory: ${DATA_FACTORY}"
    echo "4. Test the automated data refresh Logic App: ${LOGIC_APP}"
    echo ""
    echo -e "${YELLOW}Manual Configuration Required:${NC}"
    echo "• Microsoft Cloud for Sustainability setup (requires M365 admin access)"
    echo "• Power BI workspace and dataset configuration"
    echo "• Data source connections in Azure Data Factory"
    echo "• Sustainability data import and mapping"
    echo ""
    echo -e "${BLUE}Resource Information:${NC}"
    echo "• Resource Group: ${RESOURCE_GROUP}"
    echo "• Location: ${LOCATION}"
    echo "• Storage Account: ${STORAGE_ACCOUNT}"
    echo "• Function App: ${FUNCTION_APP}"
    echo "• Key Vault: ${KEY_VAULT}"
    echo ""
    echo "Configuration saved to: ${SCRIPT_DIR}/deployment_config.env"
    
    log "Deployment process completed successfully"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi