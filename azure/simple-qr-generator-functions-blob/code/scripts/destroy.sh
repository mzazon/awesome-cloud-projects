#!/bin/bash

# Azure QR Code Generator - Cleanup Script
# This script removes all resources created by the deployment script
# Prerequisites: Azure CLI installed and authenticated

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load configuration
load_configuration() {
    log_info "Loading deployment configuration..."
    
    if [[ -f "./.azure-qr-config" ]]; then
        # Load configuration from deployment
        source ./.azure-qr-config
        log_success "Configuration loaded from .azure-qr-config"
        
        log_info "Resource Group: $RESOURCE_GROUP"
        log_info "Storage Account: $STORAGE_ACCOUNT"
        log_info "Function App: $FUNCTION_APP"
        log_info "Container Name: $CONTAINER_NAME"
    else
        log_warning "Configuration file .azure-qr-config not found"
        log_info "Attempting to load from environment variables..."
        
        # Try to load from environment variables
        if [[ -n "${RESOURCE_GROUP:-}" ]] && [[ -n "${STORAGE_ACCOUNT:-}" ]] && [[ -n "${FUNCTION_APP:-}" ]]; then
            log_success "Configuration loaded from environment variables"
        else
            log_error "No configuration found. Please provide resource names manually or run from deployment directory."
            show_manual_cleanup_instructions
            exit 1
        fi
    fi
}

# Function to show manual cleanup instructions
show_manual_cleanup_instructions() {
    cat << 'EOF'

Manual cleanup instructions:
1. List resource groups: az group list --output table
2. Find your QR generator resource group (starts with rg-qr-generator-)
3. Delete resource group: az group delete --name <resource-group-name> --yes --no-wait

Example:
az group delete --name rg-qr-generator-abc123 --yes --no-wait

EOF
}

# Function to confirm deletion
confirm_deletion() {
    echo
    log_warning "This will permanently delete the following resources:"
    echo "  - Resource Group: $RESOURCE_GROUP"
    echo "  - Storage Account: $STORAGE_ACCOUNT (and all QR code images)"
    echo "  - Function App: $FUNCTION_APP"
    echo "  - All associated resources and data"
    echo
    
    # Skip confirmation if --force flag is provided
    if [[ "${1:-}" == "--force" ]] || [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log_warning "Force flag detected, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? [y/N]: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource deletion..."
}

# Function to check if resource group exists
check_resource_group_exists() {
    if az group exists --name "$RESOURCE_GROUP" --output tsv | grep -q "true"; then
        return 0  # Resource group exists
    else
        return 1  # Resource group does not exist
    fi
}

# Function to list resources before deletion
list_resources() {
    log_info "Listing resources to be deleted..."
    
    if check_resource_group_exists; then
        echo
        echo "Resources in $RESOURCE_GROUP:"
        az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --output table \
            --query '[].{Name:name, Type:type, Location:location}' || log_warning "Could not list resources"
        echo
    else
        log_warning "Resource group $RESOURCE_GROUP does not exist"
    fi
}

# Function to backup QR codes (optional)
backup_qr_codes() {
    if [[ "${BACKUP_QR_CODES:-}" == "true" ]]; then
        log_info "Backing up QR codes before deletion..."
        
        local backup_dir="./qr-codes-backup-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        
        # Download all QR codes
        if az storage blob download-batch \
            --destination "$backup_dir" \
            --source "$CONTAINER_NAME" \
            --account-name "$STORAGE_ACCOUNT" \
            --connection-string "$STORAGE_CONNECTION" &> /dev/null; then
            log_success "QR codes backed up to: $backup_dir"
        else
            log_warning "Could not backup QR codes (storage account may not exist)"
            rmdir "$backup_dir" 2>/dev/null || true
        fi
    fi
}

# Function to delete individual resources (graceful approach)
delete_resources_gracefully() {
    log_info "Attempting graceful resource deletion..."
    
    # Delete Function App first
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Deleting Function App: $FUNCTION_APP"
        if az functionapp delete \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --output table; then
            log_success "Function App deleted: $FUNCTION_APP"
        else
            log_warning "Failed to delete Function App: $FUNCTION_APP"
        fi
    else
        log_info "Function App $FUNCTION_APP does not exist or already deleted"
    fi
    
    # Delete Storage Account
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Deleting Storage Account: $STORAGE_ACCOUNT"
        if az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output table; then
            log_success "Storage Account deleted: $STORAGE_ACCOUNT"
        else
            log_warning "Failed to delete Storage Account: $STORAGE_ACCOUNT"
        fi
    else
        log_info "Storage Account $STORAGE_ACCOUNT does not exist or already deleted"
    fi
}

# Function to delete resource group (complete cleanup)
delete_resource_group() {
    log_info "Deleting resource group: $RESOURCE_GROUP"
    
    if check_resource_group_exists; then
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            --output table
        
        log_success "Resource group deletion initiated: $RESOURCE_GROUP"
        log_info "Note: Complete deletion may take 2-5 minutes"
        
        # Wait for deletion if requested
        if [[ "${WAIT_FOR_DELETION:-}" == "true" ]]; then
            log_info "Waiting for resource group deletion to complete..."
            while check_resource_group_exists; do
                echo -n "."
                sleep 10
            done
            echo
            log_success "Resource group deletion completed"
        fi
    else
        log_warning "Resource group $RESOURCE_GROUP does not exist"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove configuration file
    if [[ -f "./.azure-qr-config" ]]; then
        rm -f "./.azure-qr-config"
        log_success "Removed configuration file: .azure-qr-config"
    fi
    
    # Remove any leftover function packages
    if [[ -f "./function-package.zip" ]]; then
        rm -f "./function-package.zip"
        log_success "Removed function package: function-package.zip"
    fi
    
    # Clear environment variables
    unset RESOURCE_GROUP STORAGE_ACCOUNT FUNCTION_APP CONTAINER_NAME \
          LOCATION RANDOM_SUFFIX SUBSCRIPTION_ID FUNCTION_URL \
          STORAGE_CONNECTION 2>/dev/null || true
    
    log_success "Environment variables cleared"
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    if check_resource_group_exists; then
        log_warning "Resource group still exists (deletion may be in progress)"
        
        # List remaining resources
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$remaining_resources" ]]; then
            log_warning "Remaining resources:"
            echo "$remaining_resources"
        fi
    else
        log_success "Resource group successfully deleted"
    fi
}

# Function to show cleanup summary
cleanup_summary() {
    echo
    log_info "=== CLEANUP SUMMARY ==="
    echo
    echo "The following resources have been deleted or marked for deletion:"
    echo "  - Resource Group: $RESOURCE_GROUP"
    echo "  - Storage Account: $STORAGE_ACCOUNT"
    echo "  - Function App: $FUNCTION_APP"
    echo "  - All QR code images in blob storage"
    echo
    
    if [[ "${WAIT_FOR_DELETION:-}" != "true" ]]; then
        echo "Note: Resource deletion was initiated asynchronously."
        echo "Complete deletion may take 2-5 minutes to finish."
        echo
        echo "To verify deletion status:"
        echo "az group exists --name $RESOURCE_GROUP"
        echo
    fi
    
    log_success "Cleanup completed successfully!"
}

# Function to handle different cleanup modes
handle_cleanup_mode() {
    local mode="${1:-complete}"
    
    case "$mode" in
        "graceful")
            log_info "Using graceful cleanup mode (individual resource deletion)"
            delete_resources_gracefully
            ;;
        "complete"|*)
            log_info "Using complete cleanup mode (resource group deletion)"
            delete_resource_group
            ;;
    esac
}

# Function to show usage information
show_usage() {
    cat << 'EOF'
Usage: ./destroy.sh [OPTIONS]

Options:
  --force           Skip confirmation prompt
  --mode=MODE       Cleanup mode: 'complete' (default) or 'graceful'
  --backup          Backup QR codes before deletion
  --wait            Wait for deletion to complete
  --help            Show this help message

Environment Variables:
  FORCE_DELETE=true        Same as --force flag
  BACKUP_QR_CODES=true     Same as --backup flag
  WAIT_FOR_DELETION=true   Same as --wait flag

Examples:
  ./destroy.sh                    # Interactive cleanup
  ./destroy.sh --force            # Skip confirmation
  ./destroy.sh --backup --wait    # Backup data and wait for completion
  ./destroy.sh --mode=graceful    # Delete resources individually

EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                export FORCE_DELETE=true
                shift
                ;;
            --mode=*)
                export CLEANUP_MODE="${1#*=}"
                shift
                ;;
            --backup)
                export BACKUP_QR_CODES=true
                shift
                ;;
            --wait)
                export WAIT_FOR_DELETION=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main cleanup function
main() {
    log_info "Starting Azure QR Code Generator cleanup..."
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Execute cleanup steps
    check_prerequisites
    load_configuration
    list_resources
    confirm_deletion "${FORCE_DELETE:-}"
    backup_qr_codes
    handle_cleanup_mode "${CLEANUP_MODE:-complete}"
    cleanup_local_files
    verify_deletion
    cleanup_summary
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi