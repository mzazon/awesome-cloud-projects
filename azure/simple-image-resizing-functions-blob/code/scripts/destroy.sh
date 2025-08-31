#!/bin/bash

#########################################################################
# Simple Image Resizing with Azure Functions and Blob Storage
# Cleanup/Destroy Script
#
# This script removes all resources created by the deployment script:
# - Function App
# - Storage Account (including all containers and data)
# - Resource Group
#
# WARNING: This will permanently delete all data including uploaded images
# and processed thumbnails. This action cannot be undone.
#
# Requirements:
# - Azure CLI 2.0.80+
# - Contributor permissions in Azure subscription
#########################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_NAME="${PROJECT_NAME:-image-resize}"
readonly FORCE_DELETE="${FORCE_DELETE:-false}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure login
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites met"
}

# Function to discover resources by project name
discover_resources() {
    log_info "Discovering resources for project: $PROJECT_NAME"
    
    # Find resource groups matching the pattern
    local resource_groups
    resource_groups=$(az group list --query "[?starts_with(name, '${PROJECT_NAME}-rg-')].name" -o tsv 2>/dev/null || true)
    
    if [[ -z "$resource_groups" ]]; then
        log_warning "No resource groups found matching pattern: ${PROJECT_NAME}-rg-*"
        return 1
    fi
    
    echo "$resource_groups"
}

# Function to display resources that will be deleted
display_resources_to_delete() {
    local resource_group="$1"
    
    log_info "Resources in $resource_group that will be deleted:"
    
    # List all resources in the resource group
    local resources
    resources=$(az resource list --resource-group "$resource_group" --query '[].{Name:name, Type:type, Location:location}' -o table 2>/dev/null || true)
    
    if [[ -n "$resources" ]]; then
        echo "$resources"
    else
        log_warning "No resources found in resource group (may already be empty)"
    fi
    
    echo
}

# Function to confirm deletion
confirm_deletion() {
    local resource_groups="$1"
    
    log_warning "=========================================="
    log_warning "DESTRUCTIVE OPERATION WARNING"
    log_warning "=========================================="
    echo
    log_warning "This will permanently delete the following resource groups and ALL their contents:"
    
    while IFS= read -r rg; do
        [[ -n "$rg" ]] || continue
        echo "  • $rg"
        display_resources_to_delete "$rg"
    done <<< "$resource_groups"
    
    log_warning "This includes:"
    echo "  • All uploaded images in blob storage"
    echo "  • All processed thumbnails and medium images"
    echo "  • Function app code and configuration"
    echo "  • Storage accounts and all data"
    echo "  • All associated resources"
    echo
    log_warning "THIS OPERATION CANNOT BE UNDONE!"
    echo
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_warning "Force delete enabled, proceeding without confirmation..."
        return 0
    fi
    
    # Confirmation prompt
    local confirmation
    read -p "$(echo -e "${RED}Type 'DELETE' to confirm resource deletion: ${NC}")" confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    # Double confirmation for extra safety
    echo
    read -p "$(echo -e "${RED}Are you absolutely sure? Type 'YES' to proceed: ${NC}")" confirmation
    
    if [[ "$confirmation" != "YES" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with deletion..."
}

# Function to backup storage account data (optional)
offer_backup() {
    local resource_groups="$1"
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo
    local backup_choice
    read -p "$(echo -e "${YELLOW}Would you like to backup storage account data before deletion? (y/N): ${NC}")" backup_choice
    
    if [[ "$backup_choice" =~ ^[Yy]$ ]]; then
        backup_storage_data "$resource_groups"
    fi
}

# Function to backup storage account data
backup_storage_data() {
    local resource_groups="$1"
    
    log_info "Creating backup of storage account data..."
    
    local backup_dir="./backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    while IFS= read -r rg; do
        [[ -n "$rg" ]] || continue
        
        log_info "Backing up data from resource group: $rg"
        
        # Find storage accounts in the resource group
        local storage_accounts
        storage_accounts=$(az storage account list --resource-group "$rg" --query '[].name' -o tsv 2>/dev/null || true)
        
        while IFS= read -r storage_account; do
            [[ -n "$storage_account" ]] || continue
            
            log_info "Backing up storage account: $storage_account"
            
            # Get storage connection string
            local connection_string
            if connection_string=$(az storage account show-connection-string \
                --name "$storage_account" \
                --resource-group "$rg" \
                --query connectionString -o tsv 2>/dev/null); then
                
                # List and backup containers
                local containers
                containers=$(az storage container list \
                    --connection-string "$connection_string" \
                    --query '[].name' -o tsv 2>/dev/null || true)
                
                while IFS= read -r container; do
                    [[ -n "$container" ]] || continue
                    
                    log_info "Backing up container: $container"
                    local container_dir="$backup_dir/$storage_account/$container"
                    mkdir -p "$container_dir"
                    
                    # Download all blobs in the container
                    if ! az storage blob download-batch \
                        --destination "$container_dir" \
                        --source "$container" \
                        --connection-string "$connection_string" \
                        --output none 2>/dev/null; then
                        log_warning "Failed to backup container: $container"
                    fi
                done <<< "$containers"
            else
                log_warning "Failed to get connection string for storage account: $storage_account"
            fi
        done <<< "$storage_accounts"
    done <<< "$resource_groups"
    
    if [[ -d "$backup_dir" && "$(ls -A "$backup_dir" 2>/dev/null)" ]]; then
        log_success "Backup completed: $backup_dir"
    else
        log_warning "No data was backed up (containers may be empty)"
        rmdir "$backup_dir" 2>/dev/null || true
    fi
}

# Function to delete resources with retries
delete_resource_group() {
    local resource_group="$1"
    local max_attempts=3
    local attempt=1
    
    log_info "Deleting resource group: $resource_group (attempt $attempt/$max_attempts)"
    
    while [[ $attempt -le $max_attempts ]]; do
        if az group delete \
            --name "$resource_group" \
            --yes \
            --no-wait \
            --output none 2>/dev/null; then
            log_success "Deletion initiated for resource group: $resource_group"
            return 0
        else
            log_warning "Attempt $attempt failed for resource group: $resource_group"
            ((attempt++))
            
            if [[ $attempt -le $max_attempts ]]; then
                log_info "Retrying in 10 seconds..."
                sleep 10
            fi
        fi
    done
    
    log_error "Failed to delete resource group after $max_attempts attempts: $resource_group"
    return 1
}

# Function to wait for deletion completion
wait_for_deletion() {
    local resource_groups="$1"
    local total_groups
    total_groups=$(echo "$resource_groups" | wc -l)
    
    log_info "Waiting for deletion of $total_groups resource group(s) to complete..."
    log_info "This may take several minutes..."
    
    local completed=0
    local max_wait=1800  # 30 minutes
    local elapsed=0
    
    while [[ $completed -lt $total_groups && $elapsed -lt $max_wait ]]; do
        local current_completed=0
        
        while IFS= read -r rg; do
            [[ -n "$rg" ]] || continue
            
            if ! az group show --name "$rg" --output none 2>/dev/null; then
                ((current_completed++))
            fi
        done <<< "$resource_groups"
        
        if [[ $current_completed -gt $completed ]]; then
            completed=$current_completed
            log_info "Progress: $completed/$total_groups resource groups deleted"
        fi
        
        if [[ $completed -lt $total_groups ]]; then
            sleep 30
            ((elapsed+=30))
        fi
    done
    
    if [[ $completed -eq $total_groups ]]; then
        log_success "All resource groups deleted successfully"
    else
        log_warning "Deletion may still be in progress. Check Azure portal for status."
        log_info "Remaining resource groups may take additional time to fully delete."
    fi
}

# Function to verify deletion
verify_deletion() {
    local resource_groups="$1"
    local remaining_groups=""
    
    log_info "Verifying deletion..."
    
    while IFS= read -r rg; do
        [[ -n "$rg" ]] || continue
        
        if az group show --name "$rg" --output none 2>/dev/null; then
            remaining_groups="$remaining_groups$rg\n"
        fi
    done <<< "$resource_groups"
    
    if [[ -n "$remaining_groups" ]]; then
        log_warning "The following resource groups still exist (deletion may be in progress):"
        echo -e "$remaining_groups"
        return 1
    else
        log_success "All resource groups have been deleted"
        return 0
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove any temporary files created during deployment
    local temp_files=(
        "./image-resize-function"
        "./test-image.jpg"
        "./.azure"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -e "$file" ]]; then
            rm -rf "$file"
            log_success "Removed: $file"
        fi
    done
}

# Main execution function
main() {
    log_info "Starting Azure Image Resizing Function cleanup..."
    echo
    
    check_prerequisites
    
    local resource_groups
    if ! resource_groups=$(discover_resources); then
        log_info "No resources found to delete. Cleanup complete."
        exit 0
    fi
    
    confirm_deletion "$resource_groups"
    offer_backup "$resource_groups"
    
    echo
    log_info "Starting deletion process..."
    
    # Delete all discovered resource groups
    local failed_deletions=""
    while IFS= read -r rg; do
        [[ -n "$rg" ]] || continue
        
        if ! delete_resource_group "$rg"; then
            failed_deletions="$failed_deletions$rg\n"
        fi
    done <<< "$resource_groups"
    
    if [[ -n "$failed_deletions" ]]; then
        log_error "Failed to initiate deletion for some resource groups:"
        echo -e "$failed_deletions"
        log_info "You may need to delete these manually in the Azure portal"
    fi
    
    # Wait for deletion to complete
    wait_for_deletion "$resource_groups"
    
    # Verify deletion
    if verify_deletion "$resource_groups"; then
        cleanup_local_files
        
        log_success "=========================================="
        log_success "CLEANUP COMPLETED SUCCESSFULLY"
        log_success "=========================================="
        echo
        log_info "All Azure resources have been deleted"
        log_info "Local temporary files have been cleaned up"
        echo
        log_info "If you had any backups created, they are preserved in ./backup-* directories"
        echo
    else
        log_warning "Some resources may still be in the process of deletion"
        log_info "Check the Azure portal to monitor deletion progress"
    fi
}

# Error handling
handle_error() {
    local exit_code=$?
    log_error "Cleanup failed with exit code: $exit_code"
    log_info "Some resources may still exist. Check the Azure portal for remaining resources."
    exit $exit_code
}

trap handle_error ERR

# Help function
show_help() {
    cat << EOF
Azure Image Resizing Function Cleanup Script

Usage: $0 [OPTIONS]

Options:
    --force         Skip confirmation prompts and force deletion
    --project-name  Specify project name (default: image-resize)
    --help          Show this help message

Environment Variables:
    PROJECT_NAME    Project name to use for resource discovery (default: image-resize)
    FORCE_DELETE    Set to 'true' to skip confirmation prompts

Examples:
    $0                                  # Interactive cleanup
    $0 --force                          # Force cleanup without prompts
    PROJECT_NAME=my-project $0          # Cleanup specific project
    $0 --project-name my-project        # Cleanup specific project (alternative)

WARNING: This script will permanently delete all resources and data.
Make sure to backup any important data before running this script.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE="true"
            shift
            ;;
        --project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi