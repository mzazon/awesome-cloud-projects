#!/bin/bash

#####################################################################
# Azure Basic File Storage with Blob Storage and Portal - Destroy Script
# Recipe: Basic File Storage with Blob Storage and Portal
# Version: 1.1
# Description: Clean up Azure Storage Account and related resources
#####################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Script usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up Azure Storage Account and related resources created by the deploy script.

OPTIONS:
    -r, --resource-group    Resource group name to delete
    -s, --storage-account   Storage account name to delete (optional - will be deleted with RG)
    -c, --containers-only   Delete only blob containers, keep storage account
    -b, --blobs-only       Delete only blobs, keep containers and storage account
    -f, --force            Skip confirmation prompts (use with caution)
    -d, --dry-run          Show what would be deleted without making changes
    -h, --help             Show this help message

EXAMPLES:
    $0 -r rg-storage-demo
    $0 --resource-group my-rg --storage-account mystorageaccount123
    $0 --containers-only -r my-rg -s mystorageaccount123
    $0 --blobs-only -r my-rg -s mystorageaccount123
    $0 --dry-run -r test-rg

SAFETY NOTES:
    - By default, this script will delete the entire resource group
    - Use --containers-only to preserve the storage account
    - Use --blobs-only to preserve containers and storage account
    - Always verify the resource group name before execution

EOF
}

# Parse command line arguments
parse_args() {
    CONTAINERS_ONLY=false
    BLOBS_ONLY=false
    FORCE=false
    DRY_RUN=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -s|--storage-account)
                STORAGE_ACCOUNT="$2"
                shift 2
                ;;
            -c|--containers-only)
                CONTAINERS_ONLY=true
                shift
                ;;
            -b|--blobs-only)
                BLOBS_ONLY=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription
    local subscription_name
    local subscription_id
    subscription_name=$(az account show --query name -o tsv)
    subscription_id=$(az account show --query id -o tsv)
    log_info "Using subscription: ${subscription_name} (${subscription_id})"
    
    # Validate required parameters
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_error "Resource group name is required. Use -r or --resource-group option."
        exit 1
    fi
    
    # Validate conflicting options
    if [[ "${CONTAINERS_ONLY}" == "true" && "${BLOBS_ONLY}" == "true" ]]; then
        log_error "Cannot use --containers-only and --blobs-only together."
        exit 1
    fi
    
    # For container or blob-only operations, storage account is required
    if [[ ("${CONTAINERS_ONLY}" == "true" || "${BLOBS_ONLY}" == "true") && -z "${STORAGE_ACCOUNT:-}" ]]; then
        log_error "Storage account name is required for --containers-only or --blobs-only operations."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Confirm deletion operation
confirm_deletion() {
    if [[ "${FORCE}" == "true" || "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    
    if [[ "${BLOBS_ONLY}" == "true" ]]; then
        echo "This will DELETE ALL BLOBS in the following storage account:"
        echo "  Resource Group: ${RESOURCE_GROUP}"
        echo "  Storage Account: ${STORAGE_ACCOUNT}"
        echo "  Containers: documents, images, backups (containers will be preserved)"
    elif [[ "${CONTAINERS_ONLY}" == "true" ]]; then
        echo "This will DELETE ALL CONTAINERS AND BLOBS in the following storage account:"
        echo "  Resource Group: ${RESOURCE_GROUP}"
        echo "  Storage Account: ${STORAGE_ACCOUNT}"
        echo "  Containers: documents, images, backups (storage account will be preserved)"
    else
        echo "This will DELETE THE ENTIRE RESOURCE GROUP and all its contents:"
        echo "  Resource Group: ${RESOURCE_GROUP}"
        echo "  This includes ALL storage accounts, containers, blobs, and other resources!"
    fi
    
    echo ""
    log_warning "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you absolutely sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    echo ""
    log_info "Proceeding with deletion..."
}

# Check if resource group exists
check_resource_group() {
    log_info "Checking if resource group exists: ${RESOURCE_GROUP}"
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group '${RESOURCE_GROUP}' does not exist or is not accessible"
        exit 0
    fi
    
    log_info "Resource group '${RESOURCE_GROUP}' found"
}

# Check if storage account exists
check_storage_account() {
    if [[ -z "${STORAGE_ACCOUNT:-}" ]]; then
        return 0
    fi
    
    log_info "Checking if storage account exists: ${STORAGE_ACCOUNT}"
    
    if ! az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Storage account '${STORAGE_ACCOUNT}' does not exist in resource group '${RESOURCE_GROUP}'"
        exit 0
    fi
    
    log_info "Storage account '${STORAGE_ACCOUNT}' found"
}

# Delete blobs only
delete_blobs_only() {
    log_info "Deleting all blobs from containers..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete all blobs from containers: documents, images, backups"
        return
    fi
    
    local containers=("documents" "images" "backups")
    
    for container in "${containers[@]}"; do
        log_info "Deleting blobs from container: ${container}"
        
        # Check if container exists
        local exists
        exists=$(az storage container exists \
            --name "${container}" \
            --account-name "${STORAGE_ACCOUNT}" \
            --auth-mode login \
            --query exists -o tsv 2>/dev/null || echo "false")
        
        if [[ "${exists}" != "true" ]]; then
            log_warning "Container '${container}' does not exist, skipping..."
            continue
        fi
        
        # Delete all blobs in container
        local blob_count
        blob_count=$(az storage blob list \
            --container-name "${container}" \
            --account-name "${STORAGE_ACCOUNT}" \
            --auth-mode login \
            --query length(@) -o tsv 2>/dev/null || echo "0")
        
        if [[ "${blob_count}" -eq 0 ]]; then
            log_info "No blobs found in container '${container}'"
        else
            log_info "Deleting ${blob_count} blob(s) from container '${container}'..."
            az storage blob delete-batch \
                --source "${container}" \
                --account-name "${STORAGE_ACCOUNT}" \
                --auth-mode login \
                --output none
            
            log_success "Deleted ${blob_count} blob(s) from container '${container}'"
        fi
    done
    
    log_success "All blobs deleted successfully"
}

# Delete containers only
delete_containers_only() {
    log_info "Deleting blob containers..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete containers: documents, images, backups"
        return
    fi
    
    local containers=("documents" "images" "backups")
    
    for container in "${containers[@]}"; do
        log_info "Deleting container: ${container}"
        
        # Check if container exists
        local exists
        exists=$(az storage container exists \
            --name "${container}" \
            --account-name "${STORAGE_ACCOUNT}" \
            --auth-mode login \
            --query exists -o tsv 2>/dev/null || echo "false")
        
        if [[ "${exists}" != "true" ]]; then
            log_warning "Container '${container}' does not exist, skipping..."
            continue
        fi
        
        # Delete container (this also deletes all blobs inside)
        az storage container delete \
            --name "${container}" \
            --account-name "${STORAGE_ACCOUNT}" \
            --auth-mode login \
            --output none
        
        log_success "Container '${container}' deleted successfully"
    done
    
    log_success "All containers deleted successfully"
}

# Delete entire resource group
delete_resource_group() {
    log_info "Deleting resource group: ${RESOURCE_GROUP}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete resource group '${RESOURCE_GROUP}' and all its contents"
        return
    fi
    
    # List resources in the resource group before deletion
    log_info "Listing resources to be deleted..."
    local resource_count
    resource_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query length(@) -o tsv)
    
    if [[ "${resource_count}" -eq 0 ]]; then
        log_warning "Resource group '${RESOURCE_GROUP}' is empty"
    else
        log_info "Found ${resource_count} resource(s) in resource group '${RESOURCE_GROUP}'"
        
        # Show resources that will be deleted (for logging purposes)
        az resource list --resource-group "${RESOURCE_GROUP}" \
            --query "[].{Name:name, Type:type, Location:location}" \
            --output table
    fi
    
    # Delete resource group
    log_info "Initiating resource group deletion (this may take several minutes)..."
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        --output none
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Note: Complete deletion may take 2-5 minutes to finish"
    
    # Optional: Wait for deletion completion
    if [[ "${FORCE}" != "true" ]]; then
        echo ""
        read -p "Wait for deletion to complete? (y/N): " wait_confirmation
        if [[ "${wait_confirmation}" =~ ^[Yy]$ ]]; then
            log_info "Waiting for resource group deletion to complete..."
            
            # Wait for resource group to be deleted (max 10 minutes)
            local max_wait=600
            local wait_time=0
            local sleep_interval=15
            
            while [[ ${wait_time} -lt ${max_wait} ]]; do
                if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
                    log_success "Resource group '${RESOURCE_GROUP}' has been completely deleted"
                    return
                fi
                
                log_info "Still deleting... (${wait_time}s elapsed)"
                sleep ${sleep_interval}
                wait_time=$((wait_time + sleep_interval))
            done
            
            log_warning "Deletion is taking longer than expected. Check Azure Portal for status."
        fi
    fi
}

# Clean up local environment
cleanup_local_environment() {
    log_info "Cleaning up local environment..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local sample files and environment variables"
        return
    fi
    
    # Remove any local sample files that might have been created
    local files_to_remove=("sample-document.txt" "config.json")
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_info "Removed local file: ${file}"
        fi
    done
    
    # Remove downloads directory if it exists
    if [[ -d "downloads" ]]; then
        rm -rf downloads/
        log_info "Removed downloads directory"
    fi
    
    log_success "Local environment cleaned up"
}

# Display cleanup summary
show_cleanup_summary() {
    echo ""
    log_info "Cleanup Summary:"
    echo "========================"
    
    if [[ "${BLOBS_ONLY}" == "true" ]]; then
        echo "Operation: Delete blobs only"
        echo "Resource Group: ${RESOURCE_GROUP} (preserved)"
        echo "Storage Account: ${STORAGE_ACCOUNT} (preserved)"
        echo "Containers: documents, images, backups (preserved, but emptied)"
    elif [[ "${CONTAINERS_ONLY}" == "true" ]]; then
        echo "Operation: Delete containers only"
        echo "Resource Group: ${RESOURCE_GROUP} (preserved)"
        echo "Storage Account: ${STORAGE_ACCOUNT} (preserved)"
        echo "Containers: documents, images, backups (deleted)"
    else
        echo "Operation: Delete resource group"
        echo "Resource Group: ${RESOURCE_GROUP} (deleted)"
        echo "All resources in the group: (deleted)"
    fi
    
    echo "========================"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Dry run completed - no resources were deleted"
    else
        log_success "Cleanup completed successfully!"
        
        if [[ "${BLOBS_ONLY}" != "true" && "${CONTAINERS_ONLY}" != "true" ]]; then
            echo ""
            log_info "💡 The resource group and all its resources have been deleted."
            log_info "You can now safely remove any local configuration files or scripts."
        else
            echo ""
            log_info "💡 Partial cleanup completed. Storage account and resource group are preserved."
            log_info "To completely remove all resources, run: $0 -r ${RESOURCE_GROUP}"
        fi
    fi
}

# Main execution function
main() {
    log_info "Starting Azure Basic File Storage cleanup..."
    
    # Parse command line arguments
    parse_args "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Check if resources exist
    check_resource_group
    
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        check_storage_account
    fi
    
    # Confirm deletion operation
    confirm_deletion
    
    # Execute cleanup based on options
    if [[ "${BLOBS_ONLY}" == "true" ]]; then
        delete_blobs_only
    elif [[ "${CONTAINERS_ONLY}" == "true" ]]; then
        delete_containers_only
    else
        delete_resource_group
    fi
    
    # Clean up local environment
    cleanup_local_environment
    
    # Show cleanup summary
    show_cleanup_summary
}

# Error handling
trap 'log_error "Cleanup failed at line $LINENO. Exit code: $?"' ERR

# Execute main function with all arguments
main "$@"