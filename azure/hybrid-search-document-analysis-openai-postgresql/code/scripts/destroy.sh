#!/bin/bash

# Destroy script for Intelligent Document Analysis with Hybrid Search
# Recipe: implementing-intelligent-document-analysis-with-hybrid-search-using-azure-openai-service-and-postgresql
# Version: 1.0
# Provider: Azure

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Color codes for output
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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
CONFIG_FILE="${SCRIPT_DIR}/../.env"

# Function to load configuration
load_configuration() {
    log_info "Loading configuration..."
    
    if [[ -f "${CONFIG_FILE}" ]]; then
        # Source the configuration file
        source "${CONFIG_FILE}"
        log_success "Configuration loaded from: ${CONFIG_FILE}"
        
        # Validate required variables
        local required_vars=("RESOURCE_GROUP" "LOCATION" "OPENAI_ACCOUNT" "POSTGRES_SERVER" "SEARCH_SERVICE" "FUNCTION_APP" "STORAGE_ACCOUNT")
        for var in "${required_vars[@]}"; do
            if [[ -z "${!var:-}" ]]; then
                log_error "Required variable ${var} not found in configuration"
                return 1
            fi
        done
    else
        log_error "Configuration file not found: ${CONFIG_FILE}"
        log_error "Please ensure the deploy script has been run first"
        return 1
    fi
}

# Function to validate Azure CLI
validate_azure_cli() {
    log_info "Validating Azure CLI..."
    
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Azure CLI validation complete"
}

# Function to confirm deletion
confirm_deletion() {
    log_warning "===========================================" 
    log_warning "  RESOURCE DELETION CONFIRMATION"
    log_warning "===========================================" 
    echo
    log_warning "This script will DELETE the following resources:"
    log_warning "- Resource Group: ${RESOURCE_GROUP}"
    log_warning "- Azure OpenAI Service: ${OPENAI_ACCOUNT}"
    log_warning "- PostgreSQL Server: ${POSTGRES_SERVER}"
    log_warning "- Azure AI Search: ${SEARCH_SERVICE}"
    log_warning "- Function App: ${FUNCTION_APP}"
    log_warning "- Storage Account: ${STORAGE_ACCOUNT}"
    log_warning "- All associated data and configurations"
    echo
    log_error "THIS ACTION CANNOT BE UNDONE!"
    echo
    
    # Allow bypassing confirmation with --force flag
    if [[ "${1:-}" == "--force" ]]; then
        log_info "Force flag detected, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_info "Deletion confirmed. Proceeding with resource cleanup..."
}

# Function to check resource existence
check_resource_existence() {
    log_info "Checking resource existence..."
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} not found. It may have already been deleted."
        return 1
    fi
    
    log_success "Resource group exists and will be deleted"
    return 0
}

# Function to delete Function App
delete_function_app() {
    log_info "Deleting Function App: ${FUNCTION_APP}"
    
    if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        az functionapp delete \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --slot production \
            --yes
        
        log_success "Function App deleted: ${FUNCTION_APP}"
    else
        log_warning "Function App not found: ${FUNCTION_APP}"
    fi
}

# Function to delete Azure AI Search service
delete_search_service() {
    log_info "Deleting Azure AI Search service: ${SEARCH_SERVICE}"
    
    if az search service show --name "${SEARCH_SERVICE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        az search service delete \
            --name "${SEARCH_SERVICE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes
        
        log_success "Azure AI Search service deleted: ${SEARCH_SERVICE}"
    else
        log_warning "Azure AI Search service not found: ${SEARCH_SERVICE}"
    fi
}

# Function to delete PostgreSQL server
delete_postgresql_server() {
    log_info "Deleting PostgreSQL server: ${POSTGRES_SERVER}"
    
    if az postgres flexible-server show --name "${POSTGRES_SERVER}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        az postgres flexible-server delete \
            --name "${POSTGRES_SERVER}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes
        
        log_success "PostgreSQL server deleted: ${POSTGRES_SERVER}"
    else
        log_warning "PostgreSQL server not found: ${POSTGRES_SERVER}"
    fi
}

# Function to delete Azure OpenAI service
delete_openai_service() {
    log_info "Deleting Azure OpenAI service: ${OPENAI_ACCOUNT}"
    
    if az cognitiveservices account show --name "${OPENAI_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        # Delete model deployment first
        log_info "Deleting OpenAI model deployment..."
        az cognitiveservices account deployment delete \
            --name "${OPENAI_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --deployment-name text-embedding-ada-002 \
            --yes 2>/dev/null || log_warning "Model deployment may not exist"
        
        # Delete OpenAI service
        az cognitiveservices account delete \
            --name "${OPENAI_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}"
        
        log_success "Azure OpenAI service deleted: ${OPENAI_ACCOUNT}"
    else
        log_warning "Azure OpenAI service not found: ${OPENAI_ACCOUNT}"
    fi
}

# Function to delete storage account
delete_storage_account() {
    log_info "Deleting storage account: ${STORAGE_ACCOUNT}"
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        az storage account delete \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes
        
        log_success "Storage account deleted: ${STORAGE_ACCOUNT}"
    else
        log_warning "Storage account not found: ${STORAGE_ACCOUNT}"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log_info "Deleting resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait
        
        log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        log_info "Note: Complete deletion may take several minutes"
        
        # Wait for deletion to complete (with timeout)
        log_info "Waiting for resource group deletion to complete..."
        local timeout=300  # 5 minutes timeout
        local elapsed=0
        
        while az group show --name "${RESOURCE_GROUP}" &> /dev/null && [[ $elapsed -lt $timeout ]]; do
            sleep 10
            elapsed=$((elapsed + 10))
            log_info "Waiting... (${elapsed}s/${timeout}s)"
        done
        
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            log_warning "Resource group deletion is taking longer than expected"
            log_info "You can check the status in the Azure portal"
        else
            log_success "Resource group successfully deleted: ${RESOURCE_GROUP}"
        fi
    else
        log_warning "Resource group not found: ${RESOURCE_GROUP}"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove generated files
    local files_to_remove=(
        "${SCRIPT_DIR}/init_db.sql"
        "${SCRIPT_DIR}/search_index.json"
        "${CONFIG_FILE}"
        "${LOG_FILE}"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "Removed: $file"
        fi
    done
    
    log_success "Local file cleanup complete"
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group still exists (deletion may be in progress)"
        return 1
    fi
    
    log_success "Resource deletion verification complete"
    return 0
}

# Function to display destruction summary
display_destruction_summary() {
    log_success "===========================================" 
    log_success "  RESOURCE CLEANUP COMPLETED"
    log_success "===========================================" 
    echo
    log_info "The following resources have been deleted:"
    log_info "- Resource Group: ${RESOURCE_GROUP}"
    log_info "- Azure OpenAI Service: ${OPENAI_ACCOUNT}"
    log_info "- PostgreSQL Server: ${POSTGRES_SERVER}"
    log_info "- Azure AI Search: ${SEARCH_SERVICE}"
    log_info "- Function App: ${FUNCTION_APP}"
    log_info "- Storage Account: ${STORAGE_ACCOUNT}"
    echo
    log_info "All local configuration files have been removed"
    echo
    log_success "Cleanup completed successfully!"
    echo
    log_info "Note: Some resources may take additional time to be completely removed"
    log_info "You can verify deletion status in the Azure portal"
    echo
}

# Function to handle errors during deletion
handle_deletion_error() {
    log_error "Error occurred during resource deletion"
    log_error "Some resources may not have been deleted successfully"
    log_info "Please check the Azure portal and manually delete any remaining resources"
    log_info "Resource group: ${RESOURCE_GROUP}"
    exit 1
}

# Main destruction function
main() {
    log_info "Starting Azure Intelligent Document Analysis resource cleanup..."
    log_info "Timestamp: $(date)"
    
    # Initialize log file
    echo "Azure Intelligent Document Analysis Destruction Log" > "${LOG_FILE}"
    echo "Started: $(date)" >> "${LOG_FILE}"
    
    # Set error handler
    trap handle_deletion_error ERR
    
    # Execute destruction steps
    validate_azure_cli
    load_configuration
    confirm_deletion "$@"
    
    if check_resource_existence; then
        log_info "Proceeding with individual resource deletion..."
        delete_function_app
        delete_search_service
        delete_postgresql_server
        delete_openai_service
        delete_storage_account
        
        log_info "Proceeding with resource group deletion..."
        delete_resource_group
        
        verify_deletion
    else
        log_info "Resource group not found, proceeding with local cleanup only"
    fi
    
    cleanup_local_files
    display_destruction_summary
    
    log_success "Cleanup completed successfully!"
    echo "Completed: $(date)" >> "${LOG_FILE}"
}

# Script execution with help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --force     Skip confirmation prompt"
    echo "  --help      Show this help message"
    echo
    echo "Examples:"
    echo "  $0                    # Interactive deletion with confirmation"
    echo "  $0 --force           # Skip confirmation prompt"
    echo
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --force)
        main --force
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown option: $1"
        show_help
        exit 1
        ;;
esac