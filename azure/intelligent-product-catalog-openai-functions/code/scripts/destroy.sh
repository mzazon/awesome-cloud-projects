#!/bin/bash

# Azure Intelligent Product Catalog Cleanup Script
# This script safely removes all resources created by the deployment script,
# including Azure Functions, Azure OpenAI Service, and Azure Blob Storage.

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ENV_FILE="${SCRIPT_DIR}/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() { log "INFO" "${BLUE}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }
log_warning() { log "WARNING" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }

# Confirmation prompt function
confirm_action() {
    local prompt="$1"
    local default="${2:-n}"
    
    while true; do
        if [ "$default" = "y" ]; then
            read -p "$prompt [Y/n]: " response
            response=${response:-y}
        else
            read -p "$prompt [y/N]: " response
            response=${response:-n}
        fi
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI login status
    if ! az account show &> /dev/null; then
        log_error "Please login to Azure CLI using 'az login'"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    if [ ! -f "${ENV_FILE}" ]; then
        log_error "Environment file not found: ${ENV_FILE}"
        log_error "This could mean the deployment was not completed or the environment file was deleted."
        log_error "You may need to manually clean up resources from the Azure portal."
        exit 1
    fi
    
    # Source the environment file
    source "${ENV_FILE}"
    
    # Validate required variables
    local required_vars=("RESOURCE_GROUP" "STORAGE_ACCOUNT" "FUNCTION_APP" "OPENAI_ACCOUNT")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            log_error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    log_info "Environment variables loaded:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT}"
    log_info "  Function App: ${FUNCTION_APP}"
    log_info "  OpenAI Account: ${OPENAI_ACCOUNT}"
    
    log_success "Environment variables loaded successfully"
}

# Check if resource group exists
check_resource_group() {
    log_info "Checking if resource group exists..."
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} does not exist or has already been deleted"
        return 1
    fi
    
    log_info "Resource group ${RESOURCE_GROUP} found"
    return 0
}

# List resources in the resource group
list_resources() {
    log_info "Listing resources to be deleted..."
    
    if ! check_resource_group; then
        return 0
    fi
    
    echo ""
    echo "Resources in ${RESOURCE_GROUP}:"
    echo "================================"
    
    az resource list \
        --resource-group "${RESOURCE_GROUP}" \
        --output table \
        --query "[].{Name:name, Type:type, Location:location}" || {
        log_warning "Could not list resources in resource group"
    }
    
    echo ""
}

# Backup critical data
backup_data() {
    if ! confirm_action "Do you want to backup catalog results before deletion?"; then
        log_info "Skipping data backup"
        return 0
    fi
    
    log_info "Creating backup of catalog results..."
    
    local backup_dir="${SCRIPT_DIR}/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${backup_dir}"
    
    # Check if storage account exists
    if ! az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Storage account ${STORAGE_ACCOUNT} not found. Skipping backup."
        return 0
    fi
    
    # Get connection string
    local connection_string
    connection_string=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "connectionString" --output tsv 2>/dev/null) || {
        log_warning "Could not retrieve storage connection string. Skipping backup."
        return 0
    }
    
    # Download catalog results
    log_info "Downloading catalog results..."
    az storage blob download-batch \
        --destination "${backup_dir}" \
        --source catalog-results \
        --connection-string "${connection_string}" \
        --pattern "*.json" || {
        log_warning "Could not download catalog results. Some files may not exist."
    }
    
    # Count downloaded files
    local file_count=$(find "${backup_dir}" -name "*.json" | wc -l)
    
    if [ "$file_count" -gt 0 ]; then
        log_success "Backup completed: ${file_count} files saved to ${backup_dir}"
    else
        log_info "No catalog results found to backup"
        rmdir "${backup_dir}" 2>/dev/null || true
    fi
}

# Stop function app to prevent new executions
stop_function_app() {
    log_info "Stopping Function App: ${FUNCTION_APP}"
    
    if ! az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Function App ${FUNCTION_APP} not found"
        return 0
    fi
    
    az functionapp stop \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" || {
        log_warning "Could not stop Function App ${FUNCTION_APP}"
    }
    
    log_success "Function App stopped"
}

# Remove individual resources with verification
remove_resources_individually() {
    log_info "Removing resources individually for safer cleanup..."
    
    # Remove Function App
    if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Deleting Function App: ${FUNCTION_APP}"
        az functionapp delete \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes || log_warning "Could not delete Function App ${FUNCTION_APP}"
        log_success "Function App deleted"
    else
        log_warning "Function App ${FUNCTION_APP} not found"
    fi
    
    # Remove OpenAI Service
    if az cognitiveservices account show --name "${OPENAI_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Deleting Azure OpenAI Service: ${OPENAI_ACCOUNT}"
        az cognitiveservices account delete \
            --name "${OPENAI_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes || log_warning "Could not delete OpenAI Service ${OPENAI_ACCOUNT}"
        log_success "Azure OpenAI Service deleted"
    else
        log_warning "Azure OpenAI Service ${OPENAI_ACCOUNT} not found"
    fi
    
    # Remove Storage Account
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Deleting Storage Account: ${STORAGE_ACCOUNT}"
        az storage account delete \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes || log_warning "Could not delete Storage Account ${STORAGE_ACCOUNT}"
        log_success "Storage Account deleted"
    else
        log_warning "Storage Account ${STORAGE_ACCOUNT} not found"
    fi
}

# Remove entire resource group
remove_resource_group() {
    if ! check_resource_group; then
        log_info "Resource group already deleted or does not exist"
        return 0
    fi
    
    log_info "Deleting resource group: ${RESOURCE_GROUP}"
    log_warning "This will delete ALL resources in the resource group"
    
    if ! confirm_action "Are you sure you want to delete the entire resource group?"; then
        log_info "Resource group deletion cancelled"
        return 0
    fi
    
    # Delete resource group
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    
    log_info "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Note: Deletion may take several minutes to complete in the background"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    # Wait a moment for deletions to propagate
    sleep 10
    
    # Check if resource group still exists
    if az group exists --name "${RESOURCE_GROUP}" 2>/dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} still exists (deletion may be in progress)"
        log_info "You can check the status in the Azure portal or run:"
        log_info "  az group show --name ${RESOURCE_GROUP}"
    else
        log_success "Resource group ${RESOURCE_GROUP} has been deleted"
    fi
    
    # Check individual resources if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Checking remaining resources..."
        
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length([])" --output tsv 2>/dev/null || echo "0")
        
        if [ "$remaining_resources" -eq 0 ]; then
            log_success "All resources have been deleted from the resource group"
        else
            log_warning "${remaining_resources} resources still remain in the resource group"
            log_info "Run the following command to see remaining resources:"
            log_info "  az resource list --resource-group ${RESOURCE_GROUP} --output table"
        fi
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    if confirm_action "Remove local environment file (.env)?"; then
        if [ -f "${ENV_FILE}" ]; then
            rm -f "${ENV_FILE}"
            log_success "Environment file removed: ${ENV_FILE}"
        else
            log_info "Environment file not found: ${ENV_FILE}"
        fi
    else
        log_info "Keeping environment file: ${ENV_FILE}"
    fi
    
    # Clean up any temporary function directories (if they exist)
    local temp_function_dirs=("azure-function" "temp-function")
    for dir in "${temp_function_dirs[@]}"; do
        if [ -d "${SCRIPT_DIR}/${dir}" ]; then
            if confirm_action "Remove temporary function directory ${dir}?"; then
                rm -rf "${SCRIPT_DIR}/${dir}"
                log_success "Removed directory: ${dir}"
            fi
        fi
    done
}

# Cost summary and final information
print_final_summary() {
    log_success "================================"
    log_success "CLEANUP COMPLETED"
    log_success "================================"
    log_info ""
    log_info "Summary:"
    log_info "- Resource Group: ${RESOURCE_GROUP} (deletion initiated)"
    log_info "- All associated resources are being removed"
    log_info "- Billing for these resources will stop once deletion completes"
    log_info ""
    log_info "Next Steps:"
    log_info "1. Verify deletion completion in the Azure portal"
    log_info "2. Check your Azure billing to confirm resource removal"
    log_info "3. Review any backup files created during cleanup"
    log_info ""
    log_info "If you need to redeploy:"
    log_info "1. Run ./deploy.sh to create new resources"
    log_info "2. New unique names will be generated automatically"
    log_info ""
    log_info "Cleanup log saved to: ${LOG_FILE}"
    
    # Show estimated cost savings
    log_info ""
    log_info "Estimated monthly cost savings: \$50-200 USD"
    log_info "(Actual savings depend on usage patterns and Azure pricing)"
}

# Interactive mode for safer cleanup
interactive_cleanup() {
    echo ""
    echo "Azure Intelligent Product Catalog - Resource Cleanup"
    echo "===================================================="
    echo ""
    echo "This script will help you safely remove all resources created"
    echo "by the deployment script. You can choose individual cleanup"
    echo "steps or remove everything at once."
    echo ""
    
    # Show current resources
    list_resources
    
    echo "Cleanup Options:"
    echo "1. Remove entire resource group (fastest, removes everything)"
    echo "2. Remove resources individually (safer, more control)"
    echo "3. Cancel cleanup"
    echo ""
    
    while true; do
        read -p "Choose an option (1-3): " choice
        case $choice in
            1)
                log_info "Selected: Remove entire resource group"
                backup_data
                remove_resource_group
                break
                ;;
            2)
                log_info "Selected: Remove resources individually"
                backup_data
                stop_function_app
                remove_resources_individually
                
                # Ask if user wants to remove the resource group after individual cleanup
                if confirm_action "Remove the now-empty resource group?"; then
                    remove_resource_group
                fi
                break
                ;;
            3)
                log_info "Cleanup cancelled by user"
                exit 0
                ;;
            *)
                echo "Invalid option. Please choose 1, 2, or 3."
                ;;
        esac
    done
}

# Force cleanup mode (non-interactive)
force_cleanup() {
    log_warning "Running in force cleanup mode (non-interactive)"
    
    backup_data
    remove_resource_group
}

# Main cleanup flow
main() {
    log_info "Starting Azure Intelligent Product Catalog cleanup..."
    log_info "Cleanup log: ${LOG_FILE}"
    
    check_prerequisites
    load_environment
    
    # Check for force flag
    if [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]]; then
        force_cleanup
    else
        interactive_cleanup
    fi
    
    verify_cleanup
    cleanup_local_files
    print_final_summary
    
    log_success "Cleanup process completed!"
}

# Help function
show_help() {
    echo "Azure Intelligent Product Catalog Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --force    Run cleanup without interactive prompts"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "This script safely removes all Azure resources created by"
    echo "the deployment script, including:"
    echo "- Azure Function App"
    echo "- Azure OpenAI Service"
    echo "- Azure Storage Account and containers"
    echo "- Resource Group (if empty)"
    echo ""
    echo "The script includes safety features:"
    echo "- Interactive confirmation prompts"
    echo "- Option to backup catalog results"
    echo "- Individual resource cleanup for more control"
    echo "- Verification of cleanup completion"
    echo ""
    echo "Examples:"
    echo "  $0                 # Interactive cleanup with prompts"
    echo "  $0 --force         # Non-interactive cleanup"
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac