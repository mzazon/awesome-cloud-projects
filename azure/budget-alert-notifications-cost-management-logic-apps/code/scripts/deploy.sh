#!/bin/bash

# Budget Alert Notifications with Cost Management and Logic Apps - Deployment Script
# This script deploys Azure resources for automated budget monitoring and email notifications

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Banner
echo "=============================================="
echo "  Azure Budget Alert Notifications Deployment"
echo "=============================================="
echo ""

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if OpenSSL is available for generating random values
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed. Required for generating random values."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Set environment variables
set_environment_variables() {
    log_info "Setting environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Core configuration
    export RESOURCE_GROUP="rg-budget-alerts-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Resource names with unique suffix
    export LOGIC_APP_NAME="la-budget-alerts-${RANDOM_SUFFIX}"
    export ACTION_GROUP_NAME="ag-budget-${RANDOM_SUFFIX}"
    export BUDGET_NAME="budget-demo-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="st${RANDOM_SUFFIX}"
    
    # Budget configuration
    export BUDGET_AMOUNT="${BUDGET_AMOUNT:-100}"
    export ALERT_EMAIL="${ALERT_EMAIL:-}"
    
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Subscription ID: ${SUBSCRIPTION_ID}"
    log_info "Random Suffix: ${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured"
}

# Validate configuration
validate_configuration() {
    log_info "Validating configuration..."
    
    # Check if location is valid
    if ! az account list-locations --query "[?name=='${LOCATION}']" --output tsv | grep -q "${LOCATION}"; then
        log_error "Invalid Azure location: ${LOCATION}"
        log_info "Available locations can be listed with: az account list-locations --output table"
        exit 1
    fi
    
    # Validate storage account name (must be 3-24 characters, lowercase letters and numbers only)
    if [[ ! "${STORAGE_ACCOUNT_NAME}" =~ ^[a-z0-9]{3,24}$ ]]; then
        log_error "Invalid storage account name: ${STORAGE_ACCOUNT_NAME}"
        log_error "Storage account names must be 3-24 characters, lowercase letters and numbers only"
        exit 1
    fi
    
    # Validate budget amount
    if ! [[ "${BUDGET_AMOUNT}" =~ ^[0-9]+$ ]] || [ "${BUDGET_AMOUNT}" -lt 1 ]; then
        log_error "Budget amount must be a positive integer: ${BUDGET_AMOUNT}"
        exit 1
    fi
    
    log_success "Configuration validation passed"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=budget-monitoring environment=demo \
            --output none
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Create storage account
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT_NAME}"
    
    if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Storage account ${STORAGE_ACCOUNT_NAME} already exists"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --tags component=storage purpose=logic-app \
            --output none
        
        # Wait for storage account to be fully provisioned
        log_info "Waiting for storage account to be ready..."
        while [ "$(az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" --query provisioningState --output tsv)" != "Succeeded" ]; do
            sleep 5
            echo -n "."
        done
        echo ""
        
        log_success "Storage account created: ${STORAGE_ACCOUNT_NAME}"
    fi
}

# Create Logic App
create_logic_app() {
    log_info "Creating Logic App: ${LOGIC_APP_NAME}"
    
    if az logicapp show --name "${LOGIC_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Logic App ${LOGIC_APP_NAME} already exists"
    else
        az logicapp create \
            --name "${LOGIC_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT_NAME}" \
            --location "${LOCATION}" \
            --tags component=automation purpose=budget-alerts \
            --output none
        
        # Wait for Logic App to be fully provisioned
        log_info "Waiting for Logic App to be ready..."
        while [ "$(az logicapp show --name "${LOGIC_APP_NAME}" --resource-group "${RESOURCE_GROUP}" --query state --output tsv)" != "Running" ]; do
            sleep 10
            echo -n "."
        done
        echo ""
        
        log_success "Logic App created: ${LOGIC_APP_NAME}"
    fi
}

# Create Action Group
create_action_group() {
    log_info "Creating Action Group: ${ACTION_GROUP_NAME}"
    
    if az monitor action-group show --name "${ACTION_GROUP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Action Group ${ACTION_GROUP_NAME} already exists"
    else
        # Get Logic App resource ID
        local logic_app_id=$(az logicapp show \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${LOGIC_APP_NAME}" \
            --query id --output tsv)
        
        # Create Action Group with Logic App receiver
        az monitor action-group create \
            --name "${ACTION_GROUP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --short-name "BudgetAlert" \
            --logic-app-receivers name="BudgetLogicApp" \
                resource-id="${logic_app_id}" \
                callback-url="" \
                use-common-alert-schema=true \
            --tags purpose=budget-monitoring \
            --output none
        
        export ACTION_GROUP_ID=$(az monitor action-group show \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${ACTION_GROUP_NAME}" \
            --query id --output tsv)
        
        log_success "Action Group created: ${ACTION_GROUP_NAME}"
        log_info "Action Group ID: ${ACTION_GROUP_ID}"
    fi
}

# Create budget
create_budget() {
    log_info "Creating budget: ${BUDGET_NAME} with amount: \$${BUDGET_AMOUNT}"
    
    # Get Action Group ID if not already set
    if [ -z "${ACTION_GROUP_ID:-}" ]; then
        export ACTION_GROUP_ID=$(az monitor action-group show \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${ACTION_GROUP_NAME}" \
            --query id --output tsv)
    fi
    
    if az consumption budget show --budget-name "${BUDGET_NAME}" &> /dev/null; then
        log_warning "Budget ${BUDGET_NAME} already exists"
    else
        # Create monthly budget with alert thresholds
        az consumption budget create \
            --budget-name "${BUDGET_NAME}" \
            --amount "${BUDGET_AMOUNT}" \
            --category Cost \
            --time-grain Monthly \
            --start-date "2025-01-01" \
            --end-date "2025-12-31" \
            --notifications "{
                \"actual-80\": {
                    \"enabled\": true,
                    \"operator\": \"GreaterThan\",
                    \"threshold\": 80,
                    \"contactEmails\": [],
                    \"contactGroups\": [\"${ACTION_GROUP_ID}\"]
                },
                \"forecasted-100\": {
                    \"enabled\": true,
                    \"operator\": \"GreaterThan\",
                    \"threshold\": 100,
                    \"contactEmails\": [],
                    \"contactGroups\": [\"${ACTION_GROUP_ID}\"]
                }
            }" \
            --output none
        
        log_success "Budget created: ${BUDGET_NAME}"
        log_info "Alert thresholds: 80% actual, 100% forecasted"
    fi
}

# Display configuration instructions
display_configuration_instructions() {
    log_info "Deployment completed successfully!"
    echo ""
    echo "=============================================="
    echo "  Next Steps: Configure Logic App Workflow"
    echo "=============================================="
    echo ""
    echo "Complete the Logic App workflow configuration in Azure Portal:"
    echo ""
    echo "1. Navigate to: https://portal.azure.com"
    echo "2. Go to Resource Groups > ${RESOURCE_GROUP} > ${LOGIC_APP_NAME}"
    echo "3. Create a new workflow with these components:"
    echo "   a. HTTP Request trigger (When a HTTP request is received)"
    echo "   b. Parse JSON action to extract budget alert data"
    echo "   c. Office 365 Outlook - Send an email action"
    echo ""
    echo "4. Configure the HTTP trigger to accept POST requests"
    echo "5. Set up email template with dynamic content from the parsed JSON"
    echo "6. Save and enable the workflow"
    echo ""
    echo "=============================================="
    echo "  Deployment Summary"
    echo "=============================================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "Logic App: ${LOGIC_APP_NAME}"
    echo "Action Group: ${ACTION_GROUP_NAME}"
    echo "Budget: ${BUDGET_NAME} (\$${BUDGET_AMOUNT})"
    echo "Location: ${LOCATION}"
    echo ""
    echo "Monitor your deployment:"
    echo "az group show --name ${RESOURCE_GROUP} --output table"
    echo ""
}

# Cleanup function for failed deployments
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    
    # Delete budget if it exists
    if az consumption budget show --budget-name "${BUDGET_NAME}" &> /dev/null; then
        az consumption budget delete --budget-name "${BUDGET_NAME}" || true
        log_info "Deleted budget: ${BUDGET_NAME}"
    fi
    
    # Delete resource group if it exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait || true
        log_info "Initiated deletion of resource group: ${RESOURCE_GROUP}"
    fi
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Main execution
main() {
    check_prerequisites
    set_environment_variables
    validate_configuration
    
    create_resource_group
    create_storage_account
    create_logic_app
    create_action_group
    create_budget
    
    display_configuration_instructions
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"