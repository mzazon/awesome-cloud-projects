#!/bin/bash

# Azure Simple Todo API with Functions and Table Storage - Cleanup Script
# This script removes all resources created by the deployment script
# Following the recipe: Simple Todo API with Functions and Table Storage

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Azure CLI login status
check_azure_login() {
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it first."
        log_info "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI login
    check_azure_login
    
    log_success "Prerequisites validated successfully"
}

# Function to prompt for confirmation
confirm_deletion() {
    local resource_group="$1"
    
    echo
    log_warning "This will permanently delete the following resources:"
    echo "  - Resource Group: ${resource_group}"
    echo "  - All contained resources (Function App, Storage Account, Table data)"
    echo "  - All todo data stored in the application"
    echo
    
    # Check if running in non-interactive mode
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log_warning "FORCE_DELETE is set, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    case "${confirmation}" in
        yes|YES|y|Y)
            log_info "Proceeding with deletion..."
            return 0
            ;;
        *)
            log_info "Deletion cancelled by user"
            exit 0
            ;;
    esac
}

# Function to detect resources to delete
detect_resources() {
    log_info "Detecting resources to clean up..."
    
    # Try to get resource group from environment or prompt user
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log_info "Using resource group from environment: ${RESOURCE_GROUP}"
    else
        # Try to detect resource groups created by this recipe
        log_info "Searching for recipe-created resource groups..."
        
        local recipe_groups=$(az group list \
            --tag purpose=recipe \
            --query "[?tags.purpose=='recipe'].name" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "${recipe_groups}" ]]; then
            echo
            log_info "Found resource groups created by recipes:"
            echo "${recipe_groups}" | nl -w2 -s'. '
            echo
            read -p "Enter the number of the resource group to delete (or 'q' to quit): " selection
            
            if [[ "${selection}" == "q" ]] || [[ "${selection}" == "Q" ]]; then
                log_info "Cleanup cancelled by user"
                exit 0
            fi
            
            export RESOURCE_GROUP=$(echo "${recipe_groups}" | sed -n "${selection}p")
            
            if [[ -z "${RESOURCE_GROUP}" ]]; then
                log_error "Invalid selection"
                exit 1
            fi
            
            log_info "Selected resource group: ${RESOURCE_GROUP}"
        else
            echo
            read -p "Enter the resource group name to delete: " RESOURCE_GROUP
            
            if [[ -z "${RESOURCE_GROUP}" ]]; then
                log_error "Resource group name cannot be empty"
                exit 1
            fi
        fi
    fi
    
    # Verify the resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_error "Resource group '${RESOURCE_GROUP}' does not exist"
        exit 1
    fi
    
    log_success "Resource group '${RESOURCE_GROUP}' found"
}

# Function to list resources in the group
list_resources() {
    local resource_group="$1"
    
    log_info "Listing resources in group '${resource_group}'..."
    
    local resources=$(az resource list \
        --resource-group "${resource_group}" \
        --query "[].{Name:name, Type:type, Location:location}" \
        --output table 2>/dev/null || echo "")
    
    if [[ -n "${resources}" ]]; then
        echo
        echo "${resources}"
        echo
        
        local resource_count=$(az resource list \
            --resource-group "${resource_group}" \
            --query "length([])" \
            --output tsv 2>/dev/null || echo "0")
        
        log_info "Found ${resource_count} resources to delete"
    else
        log_warning "No resources found in resource group '${resource_group}'"
    fi
}

# Function to backup important data (optional)
backup_data() {
    local resource_group="$1"
    
    if [[ "${SKIP_BACKUP:-}" == "true" ]]; then
        log_info "Skipping data backup (SKIP_BACKUP=true)"
        return 0
    fi
    
    log_info "Checking for data to backup..."
    
    # Try to find storage accounts in the resource group
    local storage_accounts=$(az storage account list \
        --resource-group "${resource_group}" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${storage_accounts}" ]]; then
        echo
        read -p "Would you like to backup table data before deletion? (y/n): " backup_choice
        
        if [[ "${backup_choice}" == "y" ]] || [[ "${backup_choice}" == "Y" ]]; then
            log_info "Creating backup directory..."
            local backup_dir="./backup-$(date +%Y%m%d-%H%M%S)"
            mkdir -p "${backup_dir}"
            
            for storage_account in ${storage_accounts}; do
                log_info "Backing up data from storage account: ${storage_account}"
                
                # Get connection string
                local connection_string=$(az storage account show-connection-string \
                    --name "${storage_account}" \
                    --resource-group "${resource_group}" \
                    --query connectionString \
                    --output tsv 2>/dev/null || echo "")
                
                if [[ -n "${connection_string}" ]]; then
                    # List and backup tables
                    local tables=$(az storage table list \
                        --connection-string "${connection_string}" \
                        --query "[].name" \
                        --output tsv 2>/dev/null || echo "")
                    
                    for table in ${tables}; do
                        log_info "Exporting table: ${table}"
                        az storage entity query \
                            --table-name "${table}" \
                            --connection-string "${connection_string}" \
                            --output json > "${backup_dir}/${storage_account}_${table}.json" 2>/dev/null || true
                    done
                fi
            done
            
            log_success "Backup completed in directory: ${backup_dir}"
        else
            log_info "Skipping data backup"
        fi
    fi
}

# Function to delete individual resources (graceful cleanup)
delete_resources_gracefully() {
    local resource_group="$1"
    
    log_info "Attempting graceful resource deletion..."
    
    # Delete Function Apps first (they depend on storage accounts)
    local function_apps=$(az functionapp list \
        --resource-group "${resource_group}" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    for app in ${function_apps}; do
        log_info "Deleting Function App: ${app}"
        az functionapp delete \
            --name "${app}" \
            --resource-group "${resource_group}" \
            --yes >/dev/null 2>&1 || log_warning "Failed to delete Function App: ${app}"
        
        log_success "Function App deleted: ${app}"
    done
    
    # Delete storage accounts
    local storage_accounts=$(az storage account list \
        --resource-group "${resource_group}" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    for account in ${storage_accounts}; do
        log_info "Deleting Storage Account: ${account}"
        az storage account delete \
            --name "${account}" \
            --resource-group "${resource_group}" \
            --yes >/dev/null 2>&1 || log_warning "Failed to delete Storage Account: ${account}"
        
        log_success "Storage Account deleted: ${account}"
    done
    
    log_success "Graceful resource deletion completed"
}

# Function to delete the resource group
delete_resource_group() {
    local resource_group="$1"
    
    log_info "Deleting resource group: ${resource_group}"
    
    # Start the deletion process
    az group delete \
        --name "${resource_group}" \
        --yes \
        --no-wait \
        --output table
    
    log_success "Resource group deletion initiated: ${resource_group}"
    log_info "Note: Deletion may take several minutes to complete"
    
    # Optional: Wait for deletion to complete
    if [[ "${WAIT_FOR_COMPLETION:-}" == "true" ]]; then
        log_info "Waiting for deletion to complete..."
        
        local max_wait=1800  # 30 minutes
        local wait_time=0
        local check_interval=30
        
        while [[ ${wait_time} -lt ${max_wait} ]]; do
            if ! az group exists --name "${resource_group}" --output tsv | grep -q "true"; then
                log_success "Resource group successfully deleted"
                return 0
            fi
            
            log_info "Still deleting... (${wait_time}s elapsed)"
            sleep ${check_interval}
            wait_time=$((wait_time + check_interval))
        done
        
        log_warning "Deletion is taking longer than expected. Check Azure portal for status."
    fi
}

# Function to verify deletion
verify_deletion() {
    local resource_group="$1"
    
    log_info "Verifying resource deletion..."
    
    # Check if resource group still exists
    if az group exists --name "${resource_group}" --output tsv | grep -q "true"; then
        log_warning "Resource group still exists. Deletion may still be in progress."
        log_info "You can check the status in the Azure portal or run:"
        log_info "  az group exists --name ${resource_group}"
        return 1
    else
        log_success "Resource group successfully deleted: ${resource_group}"
        return 0
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local temporary files..."
    
    # Remove any backup directories older than 7 days
    find . -maxdepth 1 -name "backup-*" -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
    
    # Remove any temporary function projects
    rm -rf /tmp/todo-functions* 2>/dev/null || true
    
    log_success "Local cleanup completed"
}

# Function to display cleanup summary
display_summary() {
    local resource_group="$1"
    
    echo
    echo "========================================"
    echo "         CLEANUP SUMMARY"
    echo "========================================"
    echo "Resource Group:    ${resource_group}"
    echo "Status:            Deletion initiated"
    echo
    echo "The following resources have been removed:"
    echo "  ✓ Function App and all functions"
    echo "  ✓ Storage Account and all data"
    echo "  ✓ Table Storage and all todos"
    echo "  ✓ All associated resources"
    echo
    echo "Note: Resource deletion is asynchronous and may"
    echo "take several minutes to complete fully."
    echo
    echo "To verify deletion is complete, run:"
    echo "  az group exists --name ${resource_group}"
    echo "========================================"
}

# Main cleanup function
main() {
    log_info "Starting Azure Simple Todo API cleanup..."
    echo
    
    validate_prerequisites
    detect_resources
    list_resources "${RESOURCE_GROUP}"
    confirm_deletion "${RESOURCE_GROUP}"
    backup_data "${RESOURCE_GROUP}"
    delete_resources_gracefully "${RESOURCE_GROUP}"
    delete_resource_group "${RESOURCE_GROUP}"
    cleanup_local_files
    display_summary "${RESOURCE_GROUP}"
    
    log_success "Cleanup script completed successfully!"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -f, --force             Skip confirmation prompts"
    echo "  -w, --wait              Wait for deletion to complete"
    echo "  --skip-backup           Skip data backup option"
    echo "  --resource-group NAME   Specify resource group to delete"
    echo
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP          Resource group to delete"
    echo "  FORCE_DELETE=true       Skip confirmation prompts"
    echo "  WAIT_FOR_COMPLETION=true Wait for deletion to complete"
    echo "  SKIP_BACKUP=true        Skip data backup option"
    echo
    echo "Examples:"
    echo "  $0                      Interactive cleanup"
    echo "  $0 --force              Skip confirmations"
    echo "  $0 --resource-group rg-todo-api-123"
    echo "  FORCE_DELETE=true $0    Using environment variable"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -f|--force)
            export FORCE_DELETE=true
            shift
            ;;
        -w|--wait)
            export WAIT_FOR_COMPLETION=true
            shift
            ;;
        --skip-backup)
            export SKIP_BACKUP=true
            shift
            ;;
        --resource-group)
            export RESOURCE_GROUP="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi