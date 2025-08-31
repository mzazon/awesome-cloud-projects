#!/bin/bash

# Business Intelligence Query Assistant Cleanup Script
# This script removes all Azure resources created by the BI Query Assistant deployment
# Author: Generated for Azure recipes repository
# Version: 1.0

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_LOG="cleanup.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${CLEANUP_LOG}"
}

log_info() { log "INFO" "${BLUE}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }
log_warning() { log "WARNING" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Cleanup script failed at line ${line_number} with exit code ${exit_code}"
    log_error "Some resources may not have been deleted. Please check the Azure portal."
    exit ${exit_code}
}

trap 'handle_error $LINENO' ERR

# Load environment variables
load_environment() {
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ -f "${env_file}" ]]; then
        log_info "Loading environment variables from ${env_file}"
        source "${env_file}"
    else
        log_warning "Environment file not found at ${env_file}"
        log_info "Please provide resource details manually..."
        
        # Prompt for required variables if not found
        read -p "Enter Resource Group name: " RESOURCE_GROUP
        read -p "Enter SQL Server name (optional): " SQL_SERVER_NAME
        read -p "Enter Function App name (optional): " FUNCTION_APP_NAME
        read -p "Enter OpenAI Service name (optional): " OPENAI_SERVICE_NAME
        read -p "Enter Storage Account name (optional): " STORAGE_ACCOUNT_NAME
    fi
    
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_error "RESOURCE_GROUP is required but not set"
        exit 1
    fi
    
    log_info "Cleanup configuration:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    [[ -n "${SQL_SERVER_NAME:-}" ]] && log_info "  SQL Server: ${SQL_SERVER_NAME}"
    [[ -n "${FUNCTION_APP_NAME:-}" ]] && log_info "  Function App: ${FUNCTION_APP_NAME}"
    [[ -n "${OPENAI_SERVICE_NAME:-}" ]] && log_info "  OpenAI Service: ${OPENAI_SERVICE_NAME}"
    [[ -n "${STORAGE_ACCOUNT_NAME:-}" ]] && log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check Azure login status
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group exists --name "${RESOURCE_GROUP}" &>/dev/null; then
        log_warning "Resource group '${RESOURCE_GROUP}' does not exist. Nothing to clean up."
        exit 0
    fi
    
    log_success "Prerequisites check passed"
}

# Confirmation prompt
confirm_deletion() {
    log_warning "⚠️  This will permanently delete the following resources:"
    log_warning "   • Resource Group: ${RESOURCE_GROUP}"
    log_warning "   • All resources within the resource group"
    log_warning "   • All data stored in the SQL Database"
    log_warning "   • Function App code and configurations"
    log_warning ""
    
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log_info "Force delete enabled, skipping confirmation"
        return 0
    fi
    
    echo -n "Are you sure you want to continue? (yes/no): "
    read -r confirmation
    
    case "${confirmation}" in
        yes|YES|y|Y)
            log_info "Deletion confirmed by user"
            ;;
        *)
            log_info "Deletion cancelled by user"
            exit 0
            ;;
    esac
}

# List resources before deletion
list_resources() {
    log_info "Listing resources to be deleted..."
    
    # Get resources in the resource group
    local resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" --output table 2>/dev/null || echo "Unable to list resources")
    
    if [[ "${resources}" != "Unable to list resources" ]]; then
        echo "${resources}" | tee -a "${CLEANUP_LOG}"
    else
        log_warning "Could not list resources in resource group"
    fi
}

# Delete individual resources (if needed for controlled cleanup)
delete_function_app() {
    if [[ -n "${FUNCTION_APP_NAME:-}" ]]; then
        log_info "Deleting Function App: ${FUNCTION_APP_NAME}"
        
        if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
            az functionapp delete \
                --name "${FUNCTION_APP_NAME}" \
                --resource-group "${RESOURCE_GROUP}" || log_warning "Failed to delete Function App"
            log_success "Function App deleted: ${FUNCTION_APP_NAME}"
        else
            log_info "Function App not found, skipping: ${FUNCTION_APP_NAME}"
        fi
    fi
}

# Delete OpenAI Service
delete_openai_service() {
    if [[ -n "${OPENAI_SERVICE_NAME:-}" ]]; then
        log_info "Deleting Azure OpenAI Service: ${OPENAI_SERVICE_NAME}"
        
        if az cognitiveservices account show --name "${OPENAI_SERVICE_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
            az cognitiveservices account delete \
                --name "${OPENAI_SERVICE_NAME}" \
                --resource-group "${RESOURCE_GROUP}" || log_warning "Failed to delete OpenAI Service"
            log_success "Azure OpenAI Service deleted: ${OPENAI_SERVICE_NAME}"
        else
            log_info "OpenAI Service not found, skipping: ${OPENAI_SERVICE_NAME}"
        fi
    fi
}

# Delete SQL Database and Server
delete_sql_resources() {
    if [[ -n "${SQL_SERVER_NAME:-}" ]]; then
        log_info "Deleting SQL Database and Server: ${SQL_SERVER_NAME}"
        
        if az sql server show --name "${SQL_SERVER_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
            az sql server delete \
                --name "${SQL_SERVER_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || log_warning "Failed to delete SQL Server"
            log_success "SQL Database and Server deleted: ${SQL_SERVER_NAME}"
        else
            log_info "SQL Server not found, skipping: ${SQL_SERVER_NAME}"
        fi
    fi
}

# Delete Storage Account
delete_storage_account() {
    if [[ -n "${STORAGE_ACCOUNT_NAME:-}" ]]; then
        log_info "Deleting Storage Account: ${STORAGE_ACCOUNT_NAME}"
        
        if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
            az storage account delete \
                --name "${STORAGE_ACCOUNT_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || log_warning "Failed to delete Storage Account"
            log_success "Storage Account deleted: ${STORAGE_ACCOUNT_NAME}"
        else
            log_info "Storage Account not found, skipping: ${STORAGE_ACCOUNT_NAME}"
        fi
    fi
}

# Delete entire resource group (recommended approach)
delete_resource_group() {
    log_info "Deleting entire resource group: ${RESOURCE_GROUP}"
    log_info "This may take several minutes..."
    
    if [[ "${ASYNC_DELETE:-}" == "true" ]]; then
        # Asynchronous deletion
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait
        
        log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        log_info "Deletion is running in the background. Check Azure portal for status."
    else
        # Synchronous deletion
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes
        
        log_success "Resource group deleted successfully: ${RESOURCE_GROUP}"
    fi
}

# Cleanup local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove environment file
    local env_file="${SCRIPT_DIR}/.env"
    if [[ -f "${env_file}" ]]; then
        rm "${env_file}" || log_warning "Failed to remove environment file"
        log_success "Environment file removed: ${env_file}"
    fi
    
    # Remove any leftover function project directories
    local function_dir="${SCRIPT_DIR}/../../bi-function"
    if [[ -d "${function_dir}" ]]; then
        rm -rf "${function_dir}" || log_warning "Failed to remove function directory"
        log_success "Function project directory removed"
    fi
    
    # Remove any temporary files
    find "${SCRIPT_DIR}" -name "*.tmp" -delete 2>/dev/null || true
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    if az group exists --name "${RESOURCE_GROUP}" &>/dev/null; then
        log_warning "Resource group still exists. Deletion may be in progress."
        log_info "Check the Azure portal for deletion status: ${RESOURCE_GROUP}"
    else
        log_success "Resource group successfully deleted: ${RESOURCE_GROUP}"
    fi
}

# Display cost savings information
show_cost_savings() {
    log_info ""
    log_success "💰 Cost Savings Information:"
    log_info "By deleting these resources, you have stopped the following charges:"
    log_info "  • Azure OpenAI Service: ~$10-20/month (depending on usage)"
    log_info "  • Azure SQL Database Basic: ~$5/month"
    log_info "  • Azure Functions Consumption: Pay-per-execution (minimal when idle)"
    log_info "  • Storage Account: ~$1-2/month"
    log_info "  • Total estimated monthly savings: ~$15-25"
    log_info ""
}

# Handle different cleanup modes
cleanup_mode() {
    local mode="${1:-complete}"
    
    case "${mode}" in
        "individual")
            log_info "Running individual resource cleanup..."
            delete_function_app
            delete_openai_service
            delete_sql_resources
            delete_storage_account
            ;;
        "complete"|*)
            log_info "Running complete resource group cleanup..."
            delete_resource_group
            ;;
    esac
}

# Main cleanup function
main() {
    local cleanup_type="${1:-complete}"
    
    log_info "Starting Business Intelligence Query Assistant cleanup..."
    log_info "Cleanup log: ${CLEANUP_LOG}"
    
    load_environment
    check_prerequisites
    
    # Check if we should skip confirmation
    if [[ "${2:-}" == "--force" ]] || [[ "${FORCE_DELETE:-}" == "true" ]]; then
        export FORCE_DELETE="true"
    fi
    
    # Check if we should run async
    if [[ "${2:-}" == "--async" ]] || [[ "${3:-}" == "--async" ]]; then
        export ASYNC_DELETE="true"
    fi
    
    confirm_deletion
    list_resources
    cleanup_mode "${cleanup_type}"
    
    # Wait a moment if not async
    if [[ "${ASYNC_DELETE:-}" != "true" ]]; then
        sleep 5
        verify_cleanup
    fi
    
    cleanup_local_files
    show_cost_savings
    
    log_success "🧹 Business Intelligence Query Assistant cleanup completed!"
    log_info ""
    log_info "Cleanup Summary:"
    log_info "  Resource Group: ${RESOURCE_GROUP} - Deleted"
    log_info "  Local files: Cleaned up"
    log_info ""
    
    if [[ "${ASYNC_DELETE:-}" == "true" ]]; then
        log_info "Note: Resource deletion is running in the background."
        log_info "Check the Azure portal to confirm complete removal."
    fi
    
    log_info "Thank you for using the Business Intelligence Query Assistant recipe!"
}

# Usage information
usage() {
    echo "Usage: $0 [MODE] [OPTIONS]"
    echo ""
    echo "MODES:"
    echo "  complete    Delete entire resource group (default, recommended)"
    echo "  individual  Delete resources one by one"
    echo ""
    echo "OPTIONS:"
    echo "  --force     Skip confirmation prompts"
    echo "  --async     Run deletion asynchronously (background)"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                    # Interactive complete cleanup"
    echo "  $0 complete --force   # Force complete cleanup"
    echo "  $0 individual         # Individual resource cleanup"
    echo "  $0 complete --async   # Background deletion"
    echo ""
    echo "ENVIRONMENT VARIABLES:"
    echo "  FORCE_DELETE=true     Skip confirmation prompts"
    echo "  ASYNC_DELETE=true     Run deletion asynchronously"
    echo ""
}

# Handle help requests
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi