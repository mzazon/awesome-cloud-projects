#!/bin/bash

# Azure Cost Optimization Deployment Script
# This script deploys the complete Azure cost optimization solution with proper error handling

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" >&2
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_NAME="cost-optimization-deployment-$(date +%s)"
DEPLOYMENT_LOG="${SCRIPT_DIR}/deployment_$(date +%Y%m%d_%H%M%S).log"
CLEANUP_LOG="${SCRIPT_DIR}/cleanup_resources.log"

# Default values
DEFAULT_LOCATION="eastus"
DEFAULT_BUDGET_AMOUNT=1000
DEFAULT_TEAMS_WEBHOOK=""

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    log "Running in DRY-RUN mode - no resources will be created"
fi

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        warning "openssl not found. Using \$RANDOM for unique suffix generation."
    fi
    
    success "Prerequisites check completed"
}

# Function to get user input with defaults
get_user_input() {
    log "Gathering deployment configuration..."
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    TENANT_ID=$(az account show --query tenantId --output tsv)
    
    # Get location with default
    read -p "Enter Azure region [${DEFAULT_LOCATION}]: " LOCATION
    LOCATION=${LOCATION:-$DEFAULT_LOCATION}
    
    # Get budget amount with default
    read -p "Enter monthly budget amount in USD [${DEFAULT_BUDGET_AMOUNT}]: " BUDGET_AMOUNT
    BUDGET_AMOUNT=${BUDGET_AMOUNT:-$DEFAULT_BUDGET_AMOUNT}
    
    # Get Teams webhook URL (optional)
    read -p "Enter Teams webhook URL (optional): " TEAMS_WEBHOOK_URL
    TEAMS_WEBHOOK_URL=${TEAMS_WEBHOOK_URL:-$DEFAULT_TEAMS_WEBHOOK}
    
    # Generate unique suffix
    if command -v openssl &> /dev/null; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    else
        RANDOM_SUFFIX=$(printf "%06x" $RANDOM)
    fi
    
    # Set resource names
    RESOURCE_GROUP="rg-cost-optimization-${RANDOM_SUFFIX}"
    STORAGE_ACCOUNT="stcostopt${RANDOM_SUFFIX}"
    LOGIC_APP_NAME="la-cost-optimization-${RANDOM_SUFFIX}"
    LOG_ANALYTICS_WORKSPACE="law-cost-optimization-${RANDOM_SUFFIX}"
    BUDGET_NAME="budget-optimization-${RANDOM_SUFFIX}"
    
    # Display configuration
    log "Deployment Configuration:"
    echo "  Subscription ID: ${SUBSCRIPTION_ID}"
    echo "  Tenant ID: ${TENANT_ID}"
    echo "  Location: ${LOCATION}"
    echo "  Budget Amount: \$${BUDGET_AMOUNT}"
    echo "  Resource Group: ${RESOURCE_GROUP}"
    echo "  Storage Account: ${STORAGE_ACCOUNT}"
    echo "  Logic App: ${LOGIC_APP_NAME}"
    echo "  Log Analytics: ${LOG_ANALYTICS_WORKSPACE}"
    echo "  Budget Name: ${BUDGET_NAME}"
    echo "  Teams Webhook: ${TEAMS_WEBHOOK_URL:-'Not configured'}"
    
    # Save configuration for cleanup script
    cat > "${SCRIPT_DIR}/deployment_config.env" << EOF
SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
TENANT_ID="${TENANT_ID}"
LOCATION="${LOCATION}"
BUDGET_AMOUNT="${BUDGET_AMOUNT}"
RESOURCE_GROUP="${RESOURCE_GROUP}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT}"
LOGIC_APP_NAME="${LOGIC_APP_NAME}"
LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE}"
BUDGET_NAME="${BUDGET_NAME}"
TEAMS_WEBHOOK_URL="${TEAMS_WEBHOOK_URL}"
RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Configuration saved to deployment_config.env"
        return 0
    fi
    
    # Confirm deployment
    read -p "Proceed with deployment? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user."
        exit 0
    fi
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: ${RESOURCE_GROUP}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would create resource group ${RESOURCE_GROUP}"
        return 0
    fi
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=cost-optimization environment=production \
        --output none
    
    if [[ $? -eq 0 ]]; then
        success "Resource group created: ${RESOURCE_GROUP}"
        echo "RESOURCE_GROUP=${RESOURCE_GROUP}" >> "${CLEANUP_LOG}"
    else
        error "Failed to create resource group"
        exit 1
    fi
}

# Function to create Log Analytics workspace
create_log_analytics_workspace() {
    log "Creating Log Analytics workspace: ${LOG_ANALYTICS_WORKSPACE}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would create Log Analytics workspace ${LOG_ANALYTICS_WORKSPACE}"
        return 0
    fi
    
    az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
        --location "${LOCATION}" \
        --sku PerGB2018 \
        --output none
    
    if [[ $? -eq 0 ]]; then
        success "Log Analytics workspace created: ${LOG_ANALYTICS_WORKSPACE}"
        echo "LOG_ANALYTICS_WORKSPACE=${LOG_ANALYTICS_WORKSPACE}" >> "${CLEANUP_LOG}"
    else
        error "Failed to create Log Analytics workspace"
        exit 1
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account: ${STORAGE_ACCOUNT}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would create storage account ${STORAGE_ACCOUNT}"
        return 0
    fi
    
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --tags purpose=cost-data-export \
        --output none
    
    if [[ $? -eq 0 ]]; then
        success "Storage account created: ${STORAGE_ACCOUNT}"
        echo "STORAGE_ACCOUNT=${STORAGE_ACCOUNT}" >> "${CLEANUP_LOG}"
        
        # Get connection string
        STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query connectionString \
            --output tsv)
        
        # Create container for cost exports
        az storage container create \
            --name cost-exports \
            --connection-string "${STORAGE_CONNECTION_STRING}" \
            --public-access off \
            --output none
        
        success "Storage container 'cost-exports' created"
    else
        error "Failed to create storage account"
        exit 1
    fi
}

# Function to create budget
create_budget() {
    log "Creating budget: ${BUDGET_NAME}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would create budget ${BUDGET_NAME} with amount \$${BUDGET_AMOUNT}"
        return 0
    fi
    
    # Get current date for budget period
    START_DATE=$(date -u -d "$(date +%Y-%m-01)" +%Y-%m-%dT%H:%M:%S.%3NZ)
    END_DATE=$(date -u -d "$(date +%Y-%m-01) +1 month -1 day" +%Y-%m-%dT%H:%M:%S.%3NZ)
    
    az consumption budget create \
        --budget-name "${BUDGET_NAME}" \
        --amount "${BUDGET_AMOUNT}" \
        --category Cost \
        --start-date "${START_DATE}" \
        --end-date "${END_DATE}" \
        --time-grain Monthly \
        --time-period start-date="${START_DATE}" end-date="${END_DATE}" \
        --output none
    
    if [[ $? -eq 0 ]]; then
        success "Budget created: ${BUDGET_NAME}"
        echo "BUDGET_NAME=${BUDGET_NAME}" >> "${CLEANUP_LOG}"
    else
        error "Failed to create budget"
        exit 1
    fi
}

# Function to create Logic Apps
create_logic_apps() {
    log "Creating Logic Apps: ${LOGIC_APP_NAME}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would create Logic Apps ${LOGIC_APP_NAME}"
        return 0
    fi
    
    az logicapp create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${LOGIC_APP_NAME}" \
        --storage-account "${STORAGE_ACCOUNT}" \
        --location "${LOCATION}" \
        --sku Standard \
        --tags purpose=cost-optimization-automation \
        --output none
    
    if [[ $? -eq 0 ]]; then
        success "Logic Apps created: ${LOGIC_APP_NAME}"
        echo "LOGIC_APP_NAME=${LOGIC_APP_NAME}" >> "${CLEANUP_LOG}"
    else
        error "Failed to create Logic Apps"
        exit 1
    fi
}

# Function to create service principal
create_service_principal() {
    log "Creating service principal for Azure Advisor API access"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would create service principal for cost optimization"
        return 0
    fi
    
    SP_NAME="sp-cost-optimization-${RANDOM_SUFFIX}"
    SP_DETAILS=$(az ad sp create-for-rbac \
        --name "${SP_NAME}" \
        --role "Cost Management Reader" \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}" \
        --output json)
    
    if [[ $? -eq 0 ]]; then
        SP_APP_ID=$(echo "${SP_DETAILS}" | jq -r '.appId')
        SP_PASSWORD=$(echo "${SP_DETAILS}" | jq -r '.password')
        
        success "Service principal created: ${SP_NAME}"
        echo "SP_APP_ID=${SP_APP_ID}" >> "${CLEANUP_LOG}"
        
        # Configure Logic Apps application settings
        az logicapp config appsettings set \
            --name "${LOGIC_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --settings \
            "AZURE_CLIENT_ID=${SP_APP_ID}" \
            "AZURE_CLIENT_SECRET=${SP_PASSWORD}" \
            "AZURE_TENANT_ID=${TENANT_ID}" \
            "AZURE_SUBSCRIPTION_ID=${SUBSCRIPTION_ID}" \
            "TEAMS_WEBHOOK_URL=${TEAMS_WEBHOOK_URL}" \
            --output none
        
        success "Logic Apps application settings configured"
    else
        error "Failed to create service principal"
        exit 1
    fi
}

# Function to create cost anomaly alert
create_cost_anomaly_alert() {
    log "Creating cost anomaly detection alert"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would create cost anomaly alert"
        return 0
    fi
    
    ALERT_NAME="cost-anomaly-alert-${RANDOM_SUFFIX}"
    THRESHOLD=$(echo "scale=0; ${BUDGET_AMOUNT} * 0.8 / 1" | bc)
    
    az monitor metrics alert create \
        --name "${ALERT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}" \
        --condition "avg Microsoft.Consumption/budgets/ActualCost > ${THRESHOLD}" \
        --window-size 1h \
        --evaluation-frequency 1h \
        --severity 2 \
        --description "Alert when cost exceeds 80% of monthly budget" \
        --output none
    
    if [[ $? -eq 0 ]]; then
        success "Cost anomaly alert created: ${ALERT_NAME}"
        echo "ALERT_NAME=${ALERT_NAME}" >> "${CLEANUP_LOG}"
    else
        warning "Failed to create cost anomaly alert (may not be supported in all regions)"
    fi
}

# Function to create cost data export
create_cost_data_export() {
    log "Creating automated cost data export"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would create cost data export"
        return 0
    fi
    
    EXPORT_NAME="daily-cost-export-${RANDOM_SUFFIX}"
    STORAGE_ACCOUNT_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}"
    
    az consumption export create \
        --export-name "${EXPORT_NAME}" \
        --type ActualCost \
        --dataset-granularity Daily \
        --dataset-start-date "$(date -u -d '30 days ago' +%Y-%m-%d)" \
        --dataset-end-date "$(date -u +%Y-%m-%d)" \
        --storage-account-id "${STORAGE_ACCOUNT_ID}" \
        --storage-container cost-exports \
        --storage-root-folder-path exports/daily \
        --recurrence-type Daily \
        --recurrence-start-date "$(date -u +%Y-%m-%d)" \
        --output none
    
    if [[ $? -eq 0 ]]; then
        success "Cost data export created: ${EXPORT_NAME}"
        echo "EXPORT_NAME=${EXPORT_NAME}" >> "${CLEANUP_LOG}"
    else
        warning "Failed to create cost data export (may require additional permissions)"
    fi
}

# Function to create Action Group
create_action_group() {
    log "Creating Action Group for cost optimization alerts"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would create Action Group"
        return 0
    fi
    
    ACTION_GROUP_NAME="cost-optimization-alerts-${RANDOM_SUFFIX}"
    LOGIC_APP_ID=$(az logicapp show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${LOGIC_APP_NAME}" \
        --query id \
        --output tsv)
    
    az monitor action-group create \
        --name "${ACTION_GROUP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --short-name "CostOpt" \
        --action logic-app "Cost Optimization Workflow" "${LOGIC_APP_ID}" \
        --tags purpose=cost-optimization-alerts \
        --output none
    
    if [[ $? -eq 0 ]]; then
        success "Action Group created: ${ACTION_GROUP_NAME}"
        echo "ACTION_GROUP_NAME=${ACTION_GROUP_NAME}" >> "${CLEANUP_LOG}"
    else
        error "Failed to create Action Group"
        exit 1
    fi
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would validate deployment"
        return 0
    fi
    
    # Check if resource group exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        success "Resource group validation passed"
    else
        error "Resource group validation failed"
        exit 1
    fi
    
    # Check if storage account exists
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        success "Storage account validation passed"
    else
        error "Storage account validation failed"
        exit 1
    fi
    
    # Check if Logic Apps exists
    if az logicapp show --name "${LOGIC_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        success "Logic Apps validation passed"
    else
        error "Logic Apps validation failed"
        exit 1
    fi
    
    # Check if budget exists
    if az consumption budget show --budget-name "${BUDGET_NAME}" &> /dev/null; then
        success "Budget validation passed"
    else
        warning "Budget validation failed (may be normal for some subscription types)"
    fi
}

# Function to display deployment summary
display_deployment_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Storage Account: ${STORAGE_ACCOUNT}"
    echo "Logic Apps: ${LOGIC_APP_NAME}"
    echo "Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE}"
    echo "Budget: ${BUDGET_NAME} (\$${BUDGET_AMOUNT})"
    echo "Location: ${LOCATION}"
    echo "Subscription: ${SUBSCRIPTION_ID}"
    echo ""
    echo "Next Steps:"
    echo "1. Configure Teams webhook in Logic Apps if not already done"
    echo "2. Review and customize Logic Apps workflow"
    echo "3. Test budget alerts with small threshold changes"
    echo "4. Monitor cost data exports in storage account"
    echo "5. Review Azure Advisor recommendations regularly"
    echo ""
    echo "Configuration saved to: ${SCRIPT_DIR}/deployment_config.env"
    echo "Cleanup information saved to: ${CLEANUP_LOG}"
    echo ""
    success "Deployment completed successfully!"
}

# Function to cleanup on error
cleanup_on_error() {
    error "Deployment failed. Starting cleanup..."
    
    if [[ -f "${CLEANUP_LOG}" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^RESOURCE_GROUP= ]]; then
                RG_NAME="${line#RESOURCE_GROUP=}"
                if az group show --name "$RG_NAME" &> /dev/null; then
                    warning "Cleaning up resource group: $RG_NAME"
                    az group delete --name "$RG_NAME" --yes --no-wait
                fi
            fi
        done < "${CLEANUP_LOG}"
    fi
    
    error "Cleanup initiated. Check Azure portal for completion status."
}

# Trap to handle script interruption
trap cleanup_on_error ERR INT TERM

# Main deployment function
main() {
    log "Starting Azure Cost Optimization Deployment"
    log "=========================================="
    
    # Start deployment log
    exec 1> >(tee -a "${DEPLOYMENT_LOG}")
    exec 2> >(tee -a "${DEPLOYMENT_LOG}" >&2)
    
    check_prerequisites
    get_user_input
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN completed successfully!"
        exit 0
    fi
    
    create_resource_group
    create_log_analytics_workspace
    create_storage_account
    create_budget
    create_logic_apps
    create_service_principal
    create_cost_anomaly_alert
    create_cost_data_export
    create_action_group
    validate_deployment
    display_deployment_summary
    
    log "Deployment log saved to: ${DEPLOYMENT_LOG}"
}

# Run main function
main "$@"