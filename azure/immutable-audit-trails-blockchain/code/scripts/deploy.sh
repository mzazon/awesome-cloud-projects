#!/bin/bash

# Deploy Azure Confidential Ledger and Logic Apps Audit Trail Solution
# This script deploys a tamper-proof audit trail system using Azure Confidential Ledger,
# Logic Apps, Key Vault, and Event Hub for secure, immutable audit logging.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly REQUIRED_CLI_VERSION="2.50.0"
readonly DEPLOYMENT_TIMEOUT=1800  # 30 minutes

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] ${message}${NC}" | tee -a "${LOG_FILE}"
}

print_info() { print_status "${BLUE}" "INFO: $1"; }
print_success() { print_status "${GREEN}" "SUCCESS: $1"; }
print_warning() { print_status "${YELLOW}" "WARNING: $1"; }
print_error() { print_status "${RED}" "ERROR: $1"; }

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to compare version numbers
version_compare() {
    if [[ $1 == $2 ]]; then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2
        fi
    done
    return 0
}

# Function to cleanup on script exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        print_error "Script failed with exit code $exit_code"
        print_info "Check the log file for details: ${LOG_FILE}"
        print_info "To clean up partial deployment, run: ./destroy.sh"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if running on supported OS
    if [[ "$OSTYPE" != "linux-gnu"* && "$OSTYPE" != "darwin"* ]]; then
        print_error "This script requires Linux or macOS"
        exit 1
    fi
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        print_error "Azure CLI is not installed. Please install it first."
        print_info "Installation guide: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --output tsv --query '"azure-cli"')
    version_compare "$az_version" "$REQUIRED_CLI_VERSION"
    case $? in
        2)
            print_error "Azure CLI version $az_version is too old. Required: $REQUIRED_CLI_VERSION or later"
            exit 1
            ;;
        0|1)
            print_success "Azure CLI version $az_version meets requirements"
            ;;
    esac
    
    # Check if required tools are available
    local required_tools=("openssl" "jq" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            print_error "Required tool '$tool' is not installed"
            exit 1
        fi
    done
    
    # Check if logged into Azure
    if ! az account show >/dev/null 2>&1; then
        print_error "Not logged into Azure. Please run 'az login' first"
        exit 1
    fi
    
    # Check if user has necessary permissions
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    print_info "Using subscription: $subscription_id"
    
    print_success "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    print_info "Setting environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    print_info "Generated random suffix: $RANDOM_SUFFIX"
    
    # Set Azure configuration
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set resource names
    export RESOURCE_GROUP="rg-audit-trail-${RANDOM_SUFFIX}"
    export LEDGER_NAME="acl-${RANDOM_SUFFIX}"
    export KEYVAULT_NAME="kv-audit-${RANDOM_SUFFIX}"
    export LOGIC_APP_NAME="la-audit-${RANDOM_SUFFIX}"
    export EVENT_HUB_NAMESPACE="eh-audit-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="staudit${RANDOM_SUFFIX}"
    
    print_success "Environment variables configured"
    print_info "Resource Group: $RESOURCE_GROUP"
    print_info "Location: $LOCATION"
}

# Function to create resource group
create_resource_group() {
    print_info "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=audit-trail environment=demo created-by=deploy-script
        
        print_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create Key Vault
create_key_vault() {
    print_info "Creating Key Vault: $KEYVAULT_NAME"
    
    if az keyvault show --name "$KEYVAULT_NAME" >/dev/null 2>&1; then
        print_warning "Key Vault $KEYVAULT_NAME already exists"
    else
        az keyvault create \
            --name "$KEYVAULT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku standard \
            --enable-soft-delete true \
            --enable-purge-protection true \
            --retention-days 90
        
        print_success "Key Vault created with enhanced security: $KEYVAULT_NAME"
    fi
}

# Function to deploy Confidential Ledger
deploy_confidential_ledger() {
    print_info "Deploying Azure Confidential Ledger: $LEDGER_NAME"
    
    if az confidentialledger show --name "$LEDGER_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_warning "Confidential Ledger $LEDGER_NAME already exists"
    else
        local user_id
        user_id=$(az ad signed-in-user show --query id --output tsv)
        
        print_info "Creating Confidential Ledger (this may take 5-10 minutes)..."
        az confidentialledger create \
            --name "$LEDGER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --ledger-type Public \
            --aad-based-security-principals \
                object-id="$user_id" \
                ledger-role-name="Administrator"
        
        print_info "Waiting for Confidential Ledger deployment..."
        if ! az confidentialledger wait \
            --name "$LEDGER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --created \
            --timeout "$DEPLOYMENT_TIMEOUT"; then
            print_error "Confidential Ledger deployment timed out"
            exit 1
        fi
        
        print_success "Confidential Ledger deployed successfully"
    fi
    
    # Get and store ledger endpoint
    export LEDGER_ENDPOINT
    LEDGER_ENDPOINT=$(az confidentialledger show \
        --name "$LEDGER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.ledgerUri --output tsv)
    
    print_info "Ledger endpoint: $LEDGER_ENDPOINT"
}

# Function to configure Event Hub
configure_event_hub() {
    print_info "Configuring Event Hub: $EVENT_HUB_NAMESPACE"
    
    # Create Event Hub namespace
    if az eventhubs namespace show --name "$EVENT_HUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_warning "Event Hub namespace $EVENT_HUB_NAMESPACE already exists"
    else
        az eventhubs namespace create \
            --name "$EVENT_HUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard \
            --capacity 1
        
        print_success "Event Hub namespace created"
    fi
    
    # Create Event Hub
    if az eventhubs eventhub show --name audit-events --namespace-name "$EVENT_HUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_warning "Event Hub audit-events already exists"
    else
        az eventhubs eventhub create \
            --name audit-events \
            --namespace-name "$EVENT_HUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --partition-count 4 \
            --retention-time 1
        
        print_success "Event Hub created with 4 partitions"
    fi
    
    # Create consumer group
    if az eventhubs eventhub consumer-group show \
        --name logic-apps-consumer \
        --eventhub-name audit-events \
        --namespace-name "$EVENT_HUB_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_warning "Consumer group logic-apps-consumer already exists"
    else
        az eventhubs eventhub consumer-group create \
            --name logic-apps-consumer \
            --eventhub-name audit-events \
            --namespace-name "$EVENT_HUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP"
        
        print_success "Consumer group created for Logic Apps"
    fi
}

# Function to create storage account
create_storage_account() {
    print_info "Creating Storage Account: $STORAGE_ACCOUNT"
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_warning "Storage account $STORAGE_ACCOUNT already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --hierarchical-namespace true
        
        print_success "Storage account created with hierarchical namespace"
    fi
    
    # Create container
    if az storage container show \
        --name audit-archive \
        --account-name "$STORAGE_ACCOUNT" \
        --auth-mode login >/dev/null 2>&1; then
        print_warning "Container audit-archive already exists"
    else
        az storage container create \
            --name audit-archive \
            --account-name "$STORAGE_ACCOUNT" \
            --auth-mode login
        
        print_success "Audit archive container created"
    fi
    
    # Enable versioning
    az storage account blob-service-properties update \
        --account-name "$STORAGE_ACCOUNT" \
        --enable-versioning true
    
    print_success "Blob versioning enabled for additional protection"
}

# Function to deploy Logic App
deploy_logic_app() {
    print_info "Deploying Logic App: $LOGIC_APP_NAME"
    
    if az logic workflow show --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_warning "Logic App $LOGIC_APP_NAME already exists"
    else
        # Create Logic App with basic definition
        az logic workflow create \
            --name "$LOGIC_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --definition '{
                "definition": {
                    "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
                    "contentVersion": "1.0.0.0",
                    "triggers": {},
                    "actions": {},
                    "outputs": {}
                }
            }'
        
        print_success "Logic App created"
    fi
    
    # Enable managed identity
    az logic workflow identity assign \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP"
    
    # Get managed identity principal ID
    export LOGIC_APP_IDENTITY
    LOGIC_APP_IDENTITY=$(az logic workflow show \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query identity.principalId --output tsv)
    
    print_success "Logic App managed identity enabled: $LOGIC_APP_IDENTITY"
}

# Function to configure RBAC permissions
configure_rbac() {
    print_info "Configuring RBAC permissions..."
    
    # Grant Logic App access to Key Vault
    az keyvault set-policy \
        --name "$KEYVAULT_NAME" \
        --object-id "$LOGIC_APP_IDENTITY" \
        --secret-permissions get list
    
    print_success "Key Vault access granted to Logic App"
    
    # Grant Logic App access to Event Hub
    az role assignment create \
        --assignee "$LOGIC_APP_IDENTITY" \
        --role "Azure Event Hubs Data Receiver" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventHub/namespaces/$EVENT_HUB_NAMESPACE" \
        --output none
    
    print_success "Event Hub access granted to Logic App"
    
    # Grant Logic App access to Storage Account
    az role assignment create \
        --assignee "$LOGIC_APP_IDENTITY" \
        --role "Storage Blob Data Contributor" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT" \
        --output none
    
    print_success "Storage Account access granted to Logic App"
}

# Function to store connection information
store_connection_info() {
    print_info "Storing connection information in Key Vault..."
    
    # Store ledger endpoint
    az keyvault secret set \
        --vault-name "$KEYVAULT_NAME" \
        --name "ledger-endpoint" \
        --value "$LEDGER_ENDPOINT" \
        --output none
    
    print_success "Ledger endpoint stored in Key Vault"
    
    # Store Event Hub connection string
    local eh_connection
    eh_connection=$(az eventhubs namespace authorization-rule keys list \
        --resource-group "$RESOURCE_GROUP" \
        --namespace-name "$EVENT_HUB_NAMESPACE" \
        --name RootManageSharedAccessKey \
        --query primaryConnectionString --output tsv)
    
    az keyvault secret set \
        --vault-name "$KEYVAULT_NAME" \
        --name "eventhub-connection" \
        --value "$eh_connection" \
        --output none
    
    print_success "Event Hub connection string stored in Key Vault"
}

# Function to validate deployment
validate_deployment() {
    print_info "Validating deployment..."
    
    # Check Confidential Ledger status
    local ledger_status
    ledger_status=$(az confidentialledger show \
        --name "$LEDGER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.provisioningState --output tsv)
    
    if [[ "$ledger_status" != "Succeeded" ]]; then
        print_error "Confidential Ledger deployment failed. Status: $ledger_status"
        return 1
    fi
    
    # Test Key Vault access
    local stored_endpoint
    stored_endpoint=$(az keyvault secret show \
        --vault-name "$KEYVAULT_NAME" \
        --name "ledger-endpoint" \
        --query value --output tsv)
    
    if [[ "$stored_endpoint" != "$LEDGER_ENDPOINT" ]]; then
        print_error "Key Vault secret validation failed"
        return 1
    fi
    
    # Check Logic App status
    local logic_app_state
    logic_app_state=$(az logic workflow show \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.state --output tsv)
    
    if [[ "$logic_app_state" != "Enabled" ]]; then
        print_warning "Logic App is not enabled. State: $logic_app_state"
    fi
    
    print_success "Deployment validation completed"
}

# Function to print deployment summary
print_deployment_summary() {
    print_info "=== DEPLOYMENT SUMMARY ==="
    print_info "Resource Group: $RESOURCE_GROUP"
    print_info "Location: $LOCATION"
    print_info "Confidential Ledger: $LEDGER_NAME"
    print_info "Ledger Endpoint: $LEDGER_ENDPOINT"
    print_info "Key Vault: $KEYVAULT_NAME"
    print_info "Logic App: $LOGIC_APP_NAME"
    print_info "Event Hub Namespace: $EVENT_HUB_NAMESPACE"
    print_info "Storage Account: $STORAGE_ACCOUNT"
    print_info "=========================="
    print_success "Deployment completed successfully!"
    print_info "Log file: $LOG_FILE"
    print_info "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    local start_time
    start_time=$(date +%s)
    
    print_info "Starting deployment of Azure Confidential Ledger Audit Trail Solution"
    print_info "Script: $SCRIPT_NAME"
    print_info "Log file: $LOG_FILE"
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    # Execute deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_key_vault
    deploy_confidential_ledger
    configure_event_hub
    create_storage_account
    deploy_logic_app
    configure_rbac
    store_connection_info
    validate_deployment
    print_deployment_summary
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    print_success "Total deployment time: $duration seconds"
}

# Execute main function
main "$@"