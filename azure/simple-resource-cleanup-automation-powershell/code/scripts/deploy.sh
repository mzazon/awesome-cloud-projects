#!/bin/bash

# Azure Resource Cleanup Automation - Deployment Script
# This script deploys Azure Automation Account with PowerShell runbook for automated resource cleanup

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
RUNBOOK_FILE="${SCRIPT_DIR}/../terraform/cleanup-runbook.ps1"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

# Error handling
handle_error() {
    log_error "Deployment failed on line $1"
    log_error "Check ${LOG_FILE} for details"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Configuration
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        log_error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if PowerShell runbook file exists
    if [[ ! -f "${RUNBOOK_FILE}" ]]; then
        log_error "PowerShell runbook file not found at: ${RUNBOOK_FILE}"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Set default configuration
configure_deployment() {
    log_info "Configuring deployment parameters..."
    
    # Set default values or use environment variables
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-cleanup-demo-$(openssl rand -hex 3)}"
    export LOCATION="${LOCATION:-eastus}"
    export AUTOMATION_ACCOUNT="${AUTOMATION_ACCOUNT:-aa-cleanup-$(openssl rand -hex 3)}"
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    log_info "Configuration:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Location: ${LOCATION}"
    log_info "  Automation Account: ${AUTOMATION_ACCOUNT}"
    log_info "  Subscription ID: ${SUBSCRIPTION_ID}"
}

# Validate Azure region and quota
validate_azure_environment() {
    log_info "Validating Azure environment..."
    
    # Check if location is valid
    if ! az account list-locations --query "[?name=='${LOCATION}']" --output tsv | grep -q "${LOCATION}"; then
        log_error "Invalid Azure location: ${LOCATION}"
        log_info "Available locations: $(az account list-locations --query '[].name' --output tsv | tr '\n' ' ')"
        exit 1
    fi
    
    # Check if Automation Account name is available
    if az automation account show --name "${AUTOMATION_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Automation Account ${AUTOMATION_ACCOUNT} already exists"
    fi
    
    log_success "Azure environment validation completed"
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
            --tags purpose=automation environment=demo project=resource-cleanup \
            --output none
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Create Azure Automation Account
create_automation_account() {
    log_info "Creating Azure Automation Account: ${AUTOMATION_ACCOUNT}"
    
    if az automation account show --name "${AUTOMATION_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Automation Account ${AUTOMATION_ACCOUNT} already exists"
    else
        az automation account create \
            --name "${AUTOMATION_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --assign-identity \
            --tags environment=demo purpose=cleanup \
            --output none
        
        log_success "Automation Account created: ${AUTOMATION_ACCOUNT}"
        
        # Wait for the automation account to be fully provisioned
        log_info "Waiting for Automation Account to be ready..."
        sleep 30
    fi
}

# Configure permissions
configure_permissions() {
    log_info "Configuring permissions for Managed Identity..."
    
    # Get the managed identity principal ID
    local principal_id
    principal_id=$(az automation account show \
        --name "${AUTOMATION_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query identity.principalId \
        --output tsv)
    
    if [[ -z "${principal_id}" || "${principal_id}" == "null" ]]; then
        log_error "Failed to get managed identity principal ID"
        exit 1
    fi
    
    log_info "Managed Identity Principal ID: ${principal_id}"
    
    # Check if role assignment already exists
    if az role assignment list \
        --assignee "${principal_id}" \
        --role "Contributor" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}" \
        --query '[0].id' \
        --output tsv | grep -q "/"; then
        log_warning "Contributor role already assigned to managed identity"
    else
        # Assign Contributor role at subscription level
        az role assignment create \
            --assignee "${principal_id}" \
            --role "Contributor" \
            --scope "/subscriptions/${SUBSCRIPTION_ID}" \
            --output none
        
        log_success "Contributor permissions assigned to managed identity"
    fi
}

# Create and publish runbook
deploy_runbook() {
    log_info "Deploying PowerShell runbook..."
    
    # Check if runbook already exists
    if az automation runbook show \
        --automation-account-name "${AUTOMATION_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name "ResourceCleanupRunbook" &> /dev/null; then
        log_warning "Runbook ResourceCleanupRunbook already exists"
    else
        # Create the runbook
        az automation runbook create \
            --automation-account-name "${AUTOMATION_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --name "ResourceCleanupRunbook" \
            --type "PowerShell" \
            --description "Automated cleanup of old Azure resources" \
            --output none
        
        log_success "PowerShell runbook created"
    fi
    
    # Upload runbook content
    log_info "Uploading runbook content..."
    az automation runbook replace-content \
        --automation-account-name "${AUTOMATION_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name "ResourceCleanupRunbook" \
        --content "@${RUNBOOK_FILE}" \
        --output none
    
    # Publish the runbook
    log_info "Publishing runbook..."
    az automation runbook publish \
        --automation-account-name "${AUTOMATION_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name "ResourceCleanupRunbook" \
        --output none
    
    log_success "Runbook published and ready for execution"
}

# Create test resources
create_test_resources() {
    log_info "Creating test resources for validation..."
    
    local test_rg="rg-cleanup-test-$(openssl rand -hex 3)"
    local test_storage="sttest$(openssl rand -hex 3)"
    local protected_storage="stprotected$(openssl rand -hex 3)"
    
    # Create test resource group
    az group create \
        --name "${test_rg}" \
        --location "${LOCATION}" \
        --tags Environment=dev AutoCleanup=true Project=testing CreatedBy=automation \
        --output none
    
    # Create test storage account (will be cleaned up)
    az storage account create \
        --name "${test_storage}" \
        --resource-group "${test_rg}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --tags Environment=dev AutoCleanup=true Purpose=testing \
        --output none
    
    # Create protected storage account (will NOT be cleaned up)
    az storage account create \
        --name "${protected_storage}" \
        --resource-group "${test_rg}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --tags Environment=dev DoNotDelete=true Purpose=production \
        --output none
    
    log_success "Test resources created:"
    log_info "  Test Resource Group: ${test_rg}"
    log_info "  Test Storage Account: ${test_storage} (will be cleaned up)"
    log_info "  Protected Storage Account: ${protected_storage} (protected from cleanup)"
    
    # Store test resource group name for cleanup
    echo "${test_rg}" > "${SCRIPT_DIR}/.test_resources"
}

# Test runbook execution
test_runbook() {
    log_info "Testing runbook in dry-run mode..."
    
    # Start the runbook with dry-run enabled
    local job_id
    job_id=$(az automation runbook start \
        --automation-account-name "${AUTOMATION_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name "ResourceCleanupRunbook" \
        --parameters DaysOld=0 Environment=dev DryRun=true \
        --query jobId \
        --output tsv)
    
    log_info "Runbook job started with ID: ${job_id}"
    
    # Wait for job completion
    local max_wait=120
    local wait_time=0
    local status="Running"
    
    while [[ "${status}" != "Completed" && "${status}" != "Failed" && ${wait_time} -lt ${max_wait} ]]; do
        sleep 10
        wait_time=$((wait_time + 10))
        status=$(az automation job show \
            --automation-account-name "${AUTOMATION_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --job-id "${job_id}" \
            --query status \
            --output tsv)
        log_info "Job status: ${status} (waited ${wait_time}s)"
    done
    
    if [[ "${status}" == "Completed" ]]; then
        log_success "Runbook test completed successfully"
        
        # Show job output
        log_info "Job output:"
        az automation job get-output \
            --automation-account-name "${AUTOMATION_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --job-id "${job_id}" \
            --stream-type "Output" \
            --output table || true
    else
        log_error "Runbook test failed or timed out. Status: ${status}"
        return 1
    fi
}

# Display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    log_info ""
    log_info "Deployment Summary:"
    log_info "=================="
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Automation Account: ${AUTOMATION_ACCOUNT}"
    log_info "Location: ${LOCATION}"
    log_info "Subscription: ${SUBSCRIPTION_ID}"
    log_info ""
    log_info "Next Steps:"
    log_info "1. Review the runbook test output above"
    log_info "2. Create a schedule for automated cleanup if needed"
    log_info "3. Customize the cleanup parameters as required"
    log_info "4. Monitor runbook execution through Azure portal"
    log_info ""
    log_info "Azure Portal URLs:"
    log_info "Automation Account: https://portal.azure.com/#@/resource/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/overview"
    log_info ""
    log_info "To clean up all resources, run: ./destroy.sh"
}

# Main execution
main() {
    echo "Starting Azure Resource Cleanup Automation deployment..."
    echo "Log file: ${LOG_FILE}"
    echo ""
    
    # Clear previous log
    > "${LOG_FILE}"
    
    check_prerequisites
    configure_deployment
    validate_azure_environment
    create_resource_group
    create_automation_account
    configure_permissions
    deploy_runbook
    create_test_resources
    test_runbook
    display_summary
}

# Check for help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Azure Resource Cleanup Automation - Deployment Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP      - Name of the resource group (default: auto-generated)"
    echo "  LOCATION           - Azure region (default: eastus)"
    echo "  AUTOMATION_ACCOUNT - Name of the automation account (default: auto-generated)"
    echo ""
    echo "Options:"
    echo "  -h, --help         - Show this help message"
    echo ""
    echo "Example:"
    echo "  RESOURCE_GROUP=my-cleanup-rg LOCATION=westus2 $0"
    exit 0
fi

# Run main function
main "$@"