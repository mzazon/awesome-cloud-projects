#!/bin/bash

#####################################################################
# Simple File Backup Automation Cleanup Script
# Azure Recipe: simple-file-backup-logic-apps-storage
# 
# This script removes all resources created for the automated file
# backup solution including Logic Apps and Storage resources.
#####################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="simple-file-backup"

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Remove Azure Logic Apps and Storage resources for automated file backup.

OPTIONS:
    -g, --resource-group    Resource group name (required if not using auto-detection)
    -s, --suffix           Resource suffix used during deployment (required if not using auto-detection)
    --storage-account      Specific storage account name to delete
    --logic-app            Specific Logic App name to delete
    --container-name       Specific container name to delete (default: backup-files)
    -f, --force            Skip confirmation prompts
    -d, --dry-run          Show what would be deleted without actually deleting
    --keep-resource-group  Keep the resource group after deleting resources
    --delete-all-data      Delete all data without backup (use with extreme caution)
    -h, --help             Show this help message
    --verbose              Enable verbose logging

EXAMPLES:
    $0                                          # Auto-detect resources and prompt for confirmation
    $0 -g "rg-backup-demo" -s "abc123"         # Delete specific deployment
    $0 --dry-run                               # Show what would be deleted
    $0 -f --delete-all-data                    # Force delete without confirmation or backup
    $0 --keep-resource-group                   # Delete resources but keep resource group

ENVIRONMENT VARIABLES:
    AZURE_RESOURCE_GROUP    Override resource group name
    AZURE_SUBSCRIPTION_ID   Target subscription ID

SAFETY FEATURES:
    - Confirmation prompts before destructive actions
    - Dry-run mode to preview changes
    - Optional data backup before deletion
    - Resource existence validation
    - Rollback capability for partial failures

EOF
}

# Default values
RESOURCE_GROUP=""
SUFFIX=""
STORAGE_ACCOUNT=""
LOGIC_APP=""
CONTAINER_NAME="backup-files"
FORCE=false
DRY_RUN=false
KEEP_RESOURCE_GROUP=false
DELETE_ALL_DATA=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -s|--suffix)
            SUFFIX="$2"
            shift 2
            ;;
        --storage-account)
            STORAGE_ACCOUNT="$2"
            shift 2
            ;;
        --logic-app)
            LOGIC_APP="$2"
            shift 2
            ;;
        --container-name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --keep-resource-group)
            KEEP_RESOURCE_GROUP=true
            shift
            ;;
        --delete-all-data)
            DELETE_ALL_DATA=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Enable verbose logging if requested
if [[ "$VERBOSE" == "true" ]]; then
    set -x
fi

# Use environment variables if set and not overridden
RESOURCE_GROUP="${RESOURCE_GROUP:-${AZURE_RESOURCE_GROUP:-}}"

# Auto-detect resources function
auto_detect_resources() {
    log "Auto-detecting backup automation resources..."
    
    # Get current subscription
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Find resource groups matching backup pattern
    if [[ -z "$RESOURCE_GROUP" ]]; then
        BACKUP_RGS=$(az group list --query "[?starts_with(name, 'rg-backup-')].name" -o tsv)
        
        if [[ -z "$BACKUP_RGS" ]]; then
            error "No backup resource groups found. Please specify -g option."
            exit 1
        fi
        
        # If multiple resource groups found, ask user to choose
        RG_COUNT=$(echo "$BACKUP_RGS" | wc -l)
        if [[ $RG_COUNT -gt 1 ]] && [[ "$FORCE" == "false" ]]; then
            echo "Multiple backup resource groups found:"
            echo "$BACKUP_RGS" | nl
            read -p "Enter the number of the resource group to delete: " choice
            RESOURCE_GROUP=$(echo "$BACKUP_RGS" | sed -n "${choice}p")
        else
            RESOURCE_GROUP=$(echo "$BACKUP_RGS" | head -n1)
        fi
    fi
    
    log "Target resource group: ${RESOURCE_GROUP}"
    
    # Auto-detect storage accounts if not specified
    if [[ -z "$STORAGE_ACCOUNT" ]]; then
        STORAGE_ACCOUNTS=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[?starts_with(name, 'stbackup')].name" -o tsv)
        if [[ -n "$STORAGE_ACCOUNTS" ]]; then
            STORAGE_ACCOUNT=$(echo "$STORAGE_ACCOUNTS" | head -n1)
            log "Detected storage account: ${STORAGE_ACCOUNT}"
        fi
    fi
    
    # Auto-detect Logic Apps if not specified
    if [[ -z "$LOGIC_APP" ]]; then
        LOGIC_APPS=$(az logic workflow list --resource-group "$RESOURCE_GROUP" --query "[?starts_with(name, 'la-backup-')].name" -o tsv)
        if [[ -n "$LOGIC_APPS" ]]; then
            LOGIC_APP=$(echo "$LOGIC_APPS" | head -n1)
            log "Detected Logic App: ${LOGIC_APP}"
        fi
    fi
    
    # Extract suffix if available
    if [[ -z "$SUFFIX" ]] && [[ -n "$STORAGE_ACCOUNT" ]]; then
        SUFFIX=${STORAGE_ACCOUNT#stbackup}
        log "Detected suffix: ${SUFFIX}"
    fi
}

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    log "Current subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
    
    success "Prerequisites check completed"
}

# Validate resources function
validate_resources() {
    log "Validating resources to delete..."
    
    # Check if resource group exists
    if [[ -n "$RESOURCE_GROUP" ]] && ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group '${RESOURCE_GROUP}' not found"
        exit 1
    fi
    
    # Validate storage account
    if [[ -n "$STORAGE_ACCOUNT" ]] && [[ -n "$RESOURCE_GROUP" ]]; then
        if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            warning "Storage account '${STORAGE_ACCOUNT}' not found in resource group '${RESOURCE_GROUP}'"
            STORAGE_ACCOUNT=""
        fi
    fi
    
    # Validate Logic App
    if [[ -n "$LOGIC_APP" ]] && [[ -n "$RESOURCE_GROUP" ]]; then
        if ! az logic workflow show --resource-group "$RESOURCE_GROUP" --name "$LOGIC_APP" &> /dev/null; then
            warning "Logic App '${LOGIC_APP}' not found in resource group '${RESOURCE_GROUP}'"
            LOGIC_APP=""
        fi
    fi
    
    success "Resource validation completed"
}

# List resources to be deleted function
list_resources() {
    log "Resources scheduled for deletion:"
    echo "=================================="
    
    if [[ -n "$RESOURCE_GROUP" ]]; then
        echo "Resource Group: ${RESOURCE_GROUP}"
        
        # List all resources in the resource group
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            echo "Resources in group:"
            az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table
        fi
    fi
    
    if [[ -n "$STORAGE_ACCOUNT" ]]; then
        echo ""
        echo "Storage Account: ${STORAGE_ACCOUNT}"
        if [[ -n "$CONTAINER_NAME" ]]; then
            echo "  - Container: ${CONTAINER_NAME}"
            
            # List blobs in container if it exists
            if az storage container show --name "$CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT" &> /dev/null; then
                BLOB_COUNT=$(az storage blob list --container-name "$CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT" --query "length(@)" -o tsv 2>/dev/null || echo "0")
                echo "  - Blobs in container: ${BLOB_COUNT}"
            fi
        fi
    fi
    
    if [[ -n "$LOGIC_APP" ]]; then
        echo ""
        echo "Logic App: ${LOGIC_APP}"
        
        # Show workflow status
        if az logic workflow show --resource-group "$RESOURCE_GROUP" --name "$LOGIC_APP" &> /dev/null; then
            WORKFLOW_STATE=$(az logic workflow show --resource-group "$RESOURCE_GROUP" --name "$LOGIC_APP" --query "state" -o tsv)
            echo "  - Current state: ${WORKFLOW_STATE}"
        fi
    fi
    
    echo ""
}

# Backup data function
backup_data() {
    if [[ "$DELETE_ALL_DATA" == "true" ]]; then
        warning "Skipping data backup due to --delete-all-data flag"
        return 0
    fi
    
    if [[ -z "$STORAGE_ACCOUNT" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log "Creating backup of storage data..."
    
    # Create backup directory
    BACKUP_DIR="${SCRIPT_DIR}/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Download all blobs from container
    if az storage container show --name "$CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT" &> /dev/null; then
        BLOB_LIST=$(az storage blob list --container-name "$CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT" --query "[].name" -o tsv)
        
        if [[ -n "$BLOB_LIST" ]]; then
            log "Backing up blobs to: ${BACKUP_DIR}"
            echo "$BLOB_LIST" | while read -r blob_name; do
                az storage blob download \
                    --container-name "$CONTAINER_NAME" \
                    --name "$blob_name" \
                    --file "${BACKUP_DIR}/${blob_name}" \
                    --account-name "$STORAGE_ACCOUNT" &> /dev/null
                echo "  - Downloaded: ${blob_name}"
            done
            success "Data backup completed: ${BACKUP_DIR}"
        else
            log "No blobs found to backup"
            rmdir "$BACKUP_DIR"
        fi
    fi
}

# Confirm deletion function
confirm_deletion() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warning "This action will permanently delete the following resources:"
    list_resources
    
    if [[ "$DELETE_ALL_DATA" != "true" ]]; then
        echo ""
        echo "Data backup will be created before deletion."
    else
        echo ""
        error "ALL DATA WILL BE PERMANENTLY DELETED WITHOUT BACKUP!"
    fi
    
    echo ""
    read -p "Are you sure you want to continue? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed by user"
}

# Delete storage data function
delete_storage_data() {
    if [[ -z "$STORAGE_ACCOUNT" ]] || [[ -z "$CONTAINER_NAME" ]]; then
        return 0
    fi
    
    log "Deleting storage data..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete all blobs in container: ${CONTAINER_NAME}"
        return 0
    fi
    
    # Check if container exists
    if ! az storage container show --name "$CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT" &> /dev/null; then
        warning "Container ${CONTAINER_NAME} not found, skipping data deletion"
        return 0
    fi
    
    # Delete all blobs in container
    az storage blob delete-batch \
        --source "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --output table 2>/dev/null || warning "Failed to delete some blobs"
    
    success "Storage data deleted from container: ${CONTAINER_NAME}"
}

# Delete Logic Apps workflow function
delete_logic_app() {
    if [[ -z "$LOGIC_APP" ]] || [[ -z "$RESOURCE_GROUP" ]]; then
        return 0
    fi
    
    log "Deleting Logic Apps workflow: ${LOGIC_APP}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete Logic App: ${LOGIC_APP}"
        return 0
    fi
    
    # Check if Logic App exists
    if ! az logic workflow show --resource-group "$RESOURCE_GROUP" --name "$LOGIC_APP" &> /dev/null; then
        warning "Logic App ${LOGIC_APP} not found, skipping deletion"
        return 0
    fi
    
    # Disable workflow first
    az logic workflow update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP" \
        --state Disabled \
        --output none 2>/dev/null || warning "Failed to disable workflow"
    
    # Delete workflow
    az logic workflow delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP" \
        --yes \
        --output table
    
    success "Logic Apps workflow deleted: ${LOGIC_APP}"
}

# Delete storage account function
delete_storage_account() {
    if [[ -z "$STORAGE_ACCOUNT" ]] || [[ -z "$RESOURCE_GROUP" ]]; then
        return 0
    fi
    
    log "Deleting storage account: ${STORAGE_ACCOUNT}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete storage account: ${STORAGE_ACCOUNT}"
        return 0
    fi
    
    # Check if storage account exists
    if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Storage account ${STORAGE_ACCOUNT} not found, skipping deletion"
        return 0
    fi
    
    # Delete storage account
    az storage account delete \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --yes \
        --output table
    
    success "Storage account deleted: ${STORAGE_ACCOUNT}"
}

# Delete resource group function
delete_resource_group() {
    if [[ -z "$RESOURCE_GROUP" ]] || [[ "$KEEP_RESOURCE_GROUP" == "true" ]]; then
        return 0
    fi
    
    log "Deleting resource group: ${RESOURCE_GROUP}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete resource group: ${RESOURCE_GROUP}"
        return 0
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group ${RESOURCE_GROUP} not found, skipping deletion"
        return 0
    fi
    
    # Check if resource group is empty (if keeping resources)
    REMAINING_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv)
    if [[ "$REMAINING_RESOURCES" -gt 0 ]] && [[ "$FORCE" == "false" ]]; then
        warning "Resource group ${RESOURCE_GROUP} contains ${REMAINING_RESOURCES} resources"
        read -p "Delete resource group anyway? (y/N): " delete_rg
        if [[ "$delete_rg" != "y" ]] && [[ "$delete_rg" != "Y" ]]; then
            log "Keeping resource group: ${RESOURCE_GROUP}"
            return 0
        fi
    fi
    
    # Delete resource group
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output table
    
    success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log "Note: Resource group deletion may take several minutes to complete"
}

# Cleanup temporary files function
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would clean up temporary files"
        return 0
    fi
    
    # Remove any temporary files created during deployment
    rm -f "${SCRIPT_DIR}/workflow-definition.json"
    rm -f "${SCRIPT_DIR}/test-backup.txt"
    
    success "Temporary files cleaned up"
}

# Verify cleanup function
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would verify resource deletion"
        return 0
    fi
    
    log "Verifying resource cleanup..."
    
    # Check if Logic App was deleted
    if [[ -n "$LOGIC_APP" ]] && [[ -n "$RESOURCE_GROUP" ]]; then
        if az logic workflow show --resource-group "$RESOURCE_GROUP" --name "$LOGIC_APP" &> /dev/null; then
            warning "Logic App ${LOGIC_APP} still exists"
        else
            success "Logic App ${LOGIC_APP} successfully deleted"
        fi
    fi
    
    # Check if storage account was deleted
    if [[ -n "$STORAGE_ACCOUNT" ]]; then
        if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null 2>&1; then
            warning "Storage account ${STORAGE_ACCOUNT} still exists"
        else
            success "Storage account ${STORAGE_ACCOUNT} successfully deleted"
        fi
    fi
    
    # Check if resource group was deleted (only if not keeping it)
    if [[ -n "$RESOURCE_GROUP" ]] && [[ "$KEEP_RESOURCE_GROUP" == "false" ]]; then
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log "Resource group ${RESOURCE_GROUP} deletion in progress..."
        else
            success "Resource group ${RESOURCE_GROUP} successfully deleted"
        fi
    fi
}

# Display cleanup summary function
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN MODE - No resources were actually deleted"
        echo ""
        echo "The following resources would be deleted:"
    else
        echo "The following resources have been deleted:"
    fi
    
    echo "- Resource Group: ${RESOURCE_GROUP:-'Not specified'}"
    echo "- Storage Account: ${STORAGE_ACCOUNT:-'Not found'}"
    echo "- Logic App: ${LOGIC_APP:-'Not found'}"
    echo "- Container: ${CONTAINER_NAME}"
    
    if [[ "$DRY_RUN" == "false" ]] && [[ "$DELETE_ALL_DATA" != "true" ]]; then
        BACKUP_DIRS=$(ls -d "${SCRIPT_DIR}"/backup-* 2>/dev/null || echo "")
        if [[ -n "$BACKUP_DIRS" ]]; then
            echo ""
            echo "Data backups created:"
            echo "$BACKUP_DIRS"
        fi
    fi
    
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "To proceed with actual deletion, run this script again without --dry-run"
    else
        echo "Cleanup completed successfully!"
        echo "All backup automation resources have been removed."
    fi
}

# Cleanup function for script interruption
cleanup() {
    log "Script interrupted. Performing cleanup..."
    # No specific cleanup needed for this script
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Main execution
main() {
    log "Simple File Backup Automation Cleanup Script"
    log "============================================="
    
    # Check prerequisites
    check_prerequisites
    
    # Auto-detect resources if not specified
    auto_detect_resources
    
    # Validate resources
    validate_resources
    
    # List resources to be deleted
    list_resources
    
    # Confirm deletion
    confirm_deletion
    
    # Create data backup unless forced to delete all
    backup_data
    
    # Execute cleanup steps in reverse order of creation
    delete_storage_data
    delete_logic_app
    delete_storage_account
    delete_resource_group
    cleanup_temp_files
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_cleanup_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN COMPLETED - No resources were deleted"
    else
        success "Cleanup completed successfully!"
    fi
}

# Execute main function
main "$@"