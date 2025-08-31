#!/bin/bash

# Azure Resource Cleanup Automation - Destroy Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
TEST_RESOURCES_FILE="${SCRIPT_DIR}/.test_resources"

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
    log_error "Destruction failed on line $1"
    log_error "Check ${LOG_FILE} for details"
    log_error "Some resources may still exist and need manual cleanup"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Configuration
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Get deployment configuration
get_deployment_config() {
    log_info "Retrieving deployment configuration..."
    
    # Try to get configuration from environment variables or prompt user
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        echo -n "Enter the Resource Group name to destroy: "
        read -r RESOURCE_GROUP
    fi
    
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        log_error "Resource Group name is required"
        exit 1
    fi
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    log_info "Configuration:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Subscription ID: ${SUBSCRIPTION_ID}"
}

# Validate resources exist
validate_resources() {
    log_info "Validating resources to destroy..."
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} does not exist"
        log_info "Nothing to destroy"
        exit 0
    fi
    
    # List resources in the group
    local resource_count
    resource_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query 'length(@)' --output tsv)
    
    log_info "Found ${resource_count} resources in resource group ${RESOURCE_GROUP}"
    
    if [[ ${resource_count} -gt 0 ]]; then
        log_info "Resources to be deleted:"
        az resource list --resource-group "${RESOURCE_GROUP}" --query '[].{Name:name, Type:type, Location:location}' --output table
    fi
}

# Confirmation prompt
confirm_destruction() {
    local force_mode="${1:-false}"
    
    if [[ "${force_mode}" != "true" ]]; then
        log_warning "This will permanently delete all resources in the resource group: ${RESOURCE_GROUP}"
        log_warning "This action cannot be undone!"
        echo ""
        echo -n "Are you sure you want to continue? (yes/no): "
        read -r confirmation
        
        if [[ "${confirmation}" != "yes" ]]; then
            log_info "Destruction cancelled by user"
            exit 0
        fi
    fi
    
    log_info "Proceeding with resource destruction..."
}

# Stop any running runbook jobs
stop_runbook_jobs() {
    log_info "Checking for running runbook jobs..."
    
    # Get automation account name from resource group
    local automation_accounts
    automation_accounts=$(az automation account list --resource-group "${RESOURCE_GROUP}" --query '[].name' --output tsv)
    
    for automation_account in ${automation_accounts}; do
        log_info "Checking jobs in automation account: ${automation_account}"
        
        # Get running jobs
        local running_jobs
        running_jobs=$(az automation job list \
            --automation-account-name "${automation_account}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query "[?status=='Running'].jobId" \
            --output tsv)
        
        for job_id in ${running_jobs}; do
            log_info "Stopping running job: ${job_id}"
            az automation job stop \
                --automation-account-name "${automation_account}" \
                --resource-group "${RESOURCE_GROUP}" \
                --job-id "${job_id}" \
                --output none || log_warning "Failed to stop job ${job_id}"
        done
    done
    
    if [[ -n "${automation_accounts}" ]]; then
        log_info "Waiting for jobs to stop..."
        sleep 10
    fi
}

# Clean up test resources
cleanup_test_resources() {
    log_info "Cleaning up test resources..."
    
    if [[ -f "${TEST_RESOURCES_FILE}" ]]; then
        local test_rg
        test_rg=$(cat "${TEST_RESOURCES_FILE}")
        
        if [[ -n "${test_rg}" ]] && az group show --name "${test_rg}" &> /dev/null; then
            log_info "Deleting test resource group: ${test_rg}"
            
            # Delete test resource group asynchronously
            az group delete \
                --name "${test_rg}" \
                --yes \
                --no-wait \
                --output none
            
            log_success "Test resource group deletion initiated: ${test_rg}"
        else
            log_warning "Test resource group not found or already deleted: ${test_rg}"
        fi
        
        # Remove the test resources file
        rm -f "${TEST_RESOURCES_FILE}"
    else
        log_info "No test resources file found, skipping test resource cleanup"
    fi
}

# Remove role assignments
cleanup_role_assignments() {
    log_info "Cleaning up role assignments..."
    
    # Get automation accounts in the resource group
    local automation_accounts
    automation_accounts=$(az automation account list --resource-group "${RESOURCE_GROUP}" --query '[].name' --output tsv)
    
    for automation_account in ${automation_accounts}; do
        log_info "Processing automation account: ${automation_account}"
        
        # Get managed identity principal ID
        local principal_id
        principal_id=$(az automation account show \
            --name "${automation_account}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query identity.principalId \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "${principal_id}" && "${principal_id}" != "null" ]]; then
            log_info "Removing role assignments for managed identity: ${principal_id}"
            
            # List and remove role assignments
            local role_assignments
            role_assignments=$(az role assignment list \
                --assignee "${principal_id}" \
                --query '[].id' \
                --output tsv 2>/dev/null || echo "")
            
            for assignment_id in ${role_assignments}; do
                log_info "Removing role assignment: ${assignment_id}"
                az role assignment delete --ids "${assignment_id}" --output none || log_warning "Failed to remove role assignment"
            done
        else
            log_warning "No managed identity found for automation account: ${automation_account}"
        fi
    done
}

# Delete main resource group
delete_resource_group() {
    log_info "Deleting main resource group: ${RESOURCE_GROUP}"
    
    # Delete the resource group (this will delete all contained resources)
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --output none
    
    log_success "Resource group deleted successfully: ${RESOURCE_GROUP}"
}

# Wait for deletions to complete
wait_for_cleanup() {
    log_info "Waiting for resource cleanup to complete..."
    
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    # Wait for main resource group to be deleted
    while az group show --name "${RESOURCE_GROUP}" &> /dev/null && [[ ${wait_time} -lt ${max_wait} ]]; do
        sleep 10
        wait_time=$((wait_time + 10))
        log_info "Waiting for resource group deletion... (${wait_time}s)"
    done
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group deletion is taking longer than expected"
        log_warning "You can check the deletion status in the Azure portal"
    else
        log_success "Resource group deletion completed"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove test resources file if it exists
    if [[ -f "${TEST_RESOURCES_FILE}" ]]; then
        rm -f "${TEST_RESOURCES_FILE}"
        log_info "Removed test resources tracking file"
    fi
    
    # Clean up any temporary files
    find "${SCRIPT_DIR}" -name "*.tmp" -delete 2>/dev/null || true
    
    log_success "Local file cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    # Check if main resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} still exists"
        log_warning "Deletion may still be in progress"
        
        # Show remaining resources
        local remaining_count
        remaining_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query 'length(@)' --output tsv 2>/dev/null || echo "0")
        
        if [[ ${remaining_count} -gt 0 ]]; then
            log_warning "Remaining resources (${remaining_count}):"
            az resource list --resource-group "${RESOURCE_GROUP}" --query '[].{Name:name, Type:type}' --output table || true
        fi
    else
        log_success "Resource group ${RESOURCE_GROUP} has been successfully deleted"
    fi
}

# Display cleanup summary
display_summary() {
    log_success "Cleanup process completed!"
    log_info ""
    log_info "Cleanup Summary:"
    log_info "==============="
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Subscription: ${SUBSCRIPTION_ID}"
    log_info ""
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Note: Some resources may still be in the process of being deleted"
        log_info "You can monitor the deletion progress in the Azure portal"
    else
        log_success "All resources have been successfully removed"
    fi
    
    log_info ""
    log_info "Log file: ${LOG_FILE}"
}

# Main execution
main() {
    local force_mode="${1:-false}"
    
    echo "Starting Azure Resource Cleanup Automation destruction..."
    echo "Log file: ${LOG_FILE}"
    echo ""
    
    # Clear previous log
    > "${LOG_FILE}"
    
    check_prerequisites
    get_deployment_config
    validate_resources
    confirm_destruction "${force_mode}"
    stop_runbook_jobs
    cleanup_test_resources
    cleanup_role_assignments
    delete_resource_group
    wait_for_cleanup
    cleanup_local_files
    verify_cleanup
    display_summary
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Azure Resource Cleanup Automation - Destroy Script"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Environment Variables:"
        echo "  RESOURCE_GROUP      - Name of the resource group to destroy"
        echo ""
        echo "Options:"
        echo "  -h, --help         - Show this help message"
        echo "  --force            - Skip confirmation prompts"
        echo ""
        echo "Example:"
        echo "  RESOURCE_GROUP=my-cleanup-rg $0"
        echo "  $0 --force"
        exit 0
        ;;
    --force)
        main "true"
        ;;
    *)
        main "false"
        ;;
esac