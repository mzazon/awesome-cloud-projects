#!/bin/bash

# Azure Simple Image Analysis Cleanup Script
# Recipe: Simple Image Analysis with Computer Vision and Functions
# Description: Clean up all resources created by the deployment script

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to load environment variables from deployment
load_environment() {
    if [ -f ".env.deploy" ]; then
        log_info "Loading environment from .env.deploy..."
        source .env.deploy
        log_success "Environment loaded from deployment file"
    else
        log_warning ".env.deploy file not found"
        log_info "You will need to provide resource names manually"
        
        # Prompt for required information
        read -p "Enter Resource Group name: " RESOURCE_GROUP
        read -p "Enter Function App name (optional): " FUNCTION_APP_NAME
        read -p "Enter Computer Vision name (optional): " COMPUTER_VISION_NAME
        read -p "Enter Storage Account name (optional): " STORAGE_ACCOUNT_NAME
        
        if [ -z "$RESOURCE_GROUP" ]; then
            log_error "Resource Group name is required"
            exit 1
        fi
        
        export RESOURCE_GROUP
        export FUNCTION_APP_NAME
        export COMPUTER_VISION_NAME
        export STORAGE_ACCOUNT_NAME
    fi
    
    log_info "Cleanup configuration:"
    log_info "  Resource Group: ${RESOURCE_GROUP:-<not set>}"
    log_info "  Function App: ${FUNCTION_APP_NAME:-<not set>}"
    log_info "  Computer Vision: ${COMPUTER_VISION_NAME:-<not set>}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME:-<not set>}"
}

# Function to check Azure CLI login status
check_azure_auth() {
    log_info "Checking Azure CLI authentication..."
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
    
    local subscription_name=$(az account show --query name --output tsv 2>/dev/null)
    local subscription_id=$(az account show --query id --output tsv 2>/dev/null)
    log_success "Authenticated to Azure subscription: $subscription_name ($subscription_id)"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    local az_version=$(az version --query '"azure-cli"' --output tsv 2>/dev/null)
    log_success "Azure CLI version $az_version installed"
}

# Function to prompt for confirmation
confirm_deletion() {
    local resource_group="$1"
    
    echo
    log_warning "=== DESTRUCTIVE OPERATION WARNING ==="
    log_warning "This script will permanently delete the following:"
    log_warning "  • Resource Group: $resource_group"
    log_warning "  • ALL resources within the resource group"
    log_warning "  • Function App code and configuration"
    log_warning "  • Computer Vision service and data"
    log_warning "  • Storage account and all data"
    log_warning "This action CANNOT be undone!"
    echo
    
    # Double confirmation for safety
    read -p "Type 'DELETE' to confirm resource deletion: " confirmation
    if [ "$confirmation" != "DELETE" ]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    read -p "Are you absolutely sure? Type 'YES' to proceed: " final_confirmation
    if [ "$final_confirmation" != "YES" ]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with deletion in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
}

# Function to check if resource group exists
check_resource_group() {
    local resource_group="$1"
    
    log_info "Checking if resource group exists: $resource_group"
    
    if ! az group show --name "$resource_group" >/dev/null 2>&1; then
        log_warning "Resource group '$resource_group' does not exist"
        return 1
    fi
    
    log_success "Resource group found: $resource_group"
    return 0
}

# Function to list resources in the resource group
list_resources() {
    local resource_group="$1"
    
    log_info "Listing resources in resource group: $resource_group"
    
    local resources=$(az resource list --resource-group "$resource_group" --query "[].{Name:name, Type:type}" --output table 2>/dev/null)
    
    if [ -n "$resources" ]; then
        echo
        log_info "Resources to be deleted:"
        echo "$resources"
        echo
    else
        log_info "No resources found in resource group"
    fi
}

# Function to stop Function App (if specified)
stop_function_app() {
    if [ -n "${FUNCTION_APP_NAME:-}" ]; then
        log_info "Stopping Function App: $FUNCTION_APP_NAME"
        
        if az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
            if az functionapp stop --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
                log_success "Function App stopped: $FUNCTION_APP_NAME"
            else
                log_warning "Failed to stop Function App: $FUNCTION_APP_NAME"
            fi
        else
            log_warning "Function App not found: $FUNCTION_APP_NAME"
        fi
    fi
}

# Function to delete individual resources (alternative to resource group deletion)
delete_individual_resources() {
    local resource_group="$1"
    local delete_rg="$2"
    
    # Delete Function App
    if [ -n "${FUNCTION_APP_NAME:-}" ]; then
        log_info "Deleting Function App: $FUNCTION_APP_NAME"
        if az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$resource_group" >/dev/null 2>&1; then
            if az functionapp delete --name "$FUNCTION_APP_NAME" --resource-group "$resource_group" >/dev/null 2>&1; then
                log_success "Function App deleted: $FUNCTION_APP_NAME"
            else
                log_error "Failed to delete Function App: $FUNCTION_APP_NAME"
            fi
        else
            log_warning "Function App not found: $FUNCTION_APP_NAME"
        fi
    fi
    
    # Delete Computer Vision service
    if [ -n "${COMPUTER_VISION_NAME:-}" ]; then
        log_info "Deleting Computer Vision service: $COMPUTER_VISION_NAME"
        if az cognitiveservices account show --name "$COMPUTER_VISION_NAME" --resource-group "$resource_group" >/dev/null 2>&1; then
            if az cognitiveservices account delete --name "$COMPUTER_VISION_NAME" --resource-group "$resource_group" >/dev/null 2>&1; then
                log_success "Computer Vision service deleted: $COMPUTER_VISION_NAME"
            else
                log_error "Failed to delete Computer Vision service: $COMPUTER_VISION_NAME"
            fi
        else
            log_warning "Computer Vision service not found: $COMPUTER_VISION_NAME"
        fi
    fi
    
    # Delete Storage Account
    if [ -n "${STORAGE_ACCOUNT_NAME:-}" ]; then
        log_info "Deleting Storage Account: $STORAGE_ACCOUNT_NAME"
        if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$resource_group" >/dev/null 2>&1; then
            if az storage account delete --name "$STORAGE_ACCOUNT_NAME" --resource-group "$resource_group" --yes >/dev/null 2>&1; then
                log_success "Storage Account deleted: $STORAGE_ACCOUNT_NAME"
            else
                log_error "Failed to delete Storage Account: $STORAGE_ACCOUNT_NAME"
            fi
        else
            log_warning "Storage Account not found: $STORAGE_ACCOUNT_NAME"
        fi
    fi
    
    # Delete Resource Group if requested
    if [ "$delete_rg" = "true" ]; then
        delete_resource_group "$resource_group"
    fi
}

# Function to delete resource group
delete_resource_group() {
    local resource_group="$1"
    
    log_info "Deleting resource group: $resource_group"
    log_warning "This will delete ALL resources in the resource group..."
    
    if az group delete --name "$resource_group" --yes --no-wait >/dev/null 2>&1; then
        log_success "Resource group deletion initiated: $resource_group"
        log_info "Deletion is running in the background and may take several minutes"
        
        # Wait for deletion to complete (optional)
        local wait_for_completion="${WAIT_FOR_COMPLETION:-false}"
        if [ "$wait_for_completion" = "true" ]; then
            log_info "Waiting for deletion to complete..."
            while az group show --name "$resource_group" >/dev/null 2>&1; do
                log_info "Still deleting... (checking again in 30 seconds)"
                sleep 30
            done
            log_success "Resource group deletion completed: $resource_group"
        fi
    else
        log_error "Failed to delete resource group: $resource_group"
        exit 1
    fi
}

# Function to verify deletion
verify_deletion() {
    local resource_group="$1"
    
    log_info "Verifying resource deletion..."
    
    # Check if resource group still exists
    if az group show --name "$resource_group" >/dev/null 2>&1; then
        log_warning "Resource group still exists (deletion may be in progress)"
        
        # List remaining resources
        local remaining_resources=$(az resource list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null)
        if [ -n "$remaining_resources" ]; then
            log_warning "Remaining resources:"
            echo "$remaining_resources"
        fi
    else
        log_success "Resource group successfully deleted: $resource_group"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment environment file
    if [ -f ".env.deploy" ]; then
        rm -f .env.deploy
        log_success "Removed .env.deploy file"
    fi
    
    # Remove Function project directory
    if [ -d "image-analysis-function" ]; then
        log_info "Removing local Function project directory..."
        rm -rf image-analysis-function
        log_success "Removed image-analysis-function directory"
    fi
    
    # Remove any test files
    local test_files=("test_image.py" "sample.jpg" "test_result.json")
    for file in "${test_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_success "Removed test file: $file"
        fi
    done
}

# Function to display cleanup summary
display_summary() {
    log_success "=== CLEANUP COMPLETED ==="
    echo
    log_info "Cleanup Summary:"
    log_info "  ✅ Azure resources deletion initiated"
    log_info "  ✅ Local project files removed"
    log_info "  ✅ Environment files cleaned up"
    echo
    log_info "Notes:"
    log_info "  • Resource deletion may take several minutes to complete"
    log_info "  • You can verify deletion status in the Azure portal"
    log_info "  • No ongoing charges should occur after deletion completes"
    echo
    log_success "Cleanup process completed successfully!"
}

# Function to handle different cleanup modes
cleanup_mode_menu() {
    echo
    log_info "Cleanup Options:"
    echo "1. Delete entire resource group (recommended - deletes all resources)"
    echo "2. Delete individual resources only (keeps resource group)"
    echo "3. Delete resource group and skip individual resource deletion"
    echo "4. Exit without deleting anything"
    echo
    
    read -p "Select cleanup mode (1-4): " mode
    
    case $mode in
        1)
            return 0  # Full cleanup
            ;;
        2)
            return 1  # Individual resources only
            ;;
        3)
            return 2  # Resource group only
            ;;
        4)
            log_info "Cleanup cancelled by user"
            exit 0
            ;;
        *)
            log_error "Invalid option selected"
            cleanup_mode_menu
            ;;
    esac
}

# Main cleanup function
main() {
    log_info "Starting Azure Image Analysis Function cleanup..."
    echo
    
    # Run prerequisite checks
    check_prerequisites
    check_azure_auth
    load_environment
    
    # Check if resource group exists
    if ! check_resource_group "$RESOURCE_GROUP"; then
        log_warning "Resource group does not exist, cleaning up local files only"
        cleanup_local_files
        log_success "Local cleanup completed"
        exit 0
    fi
    
    # List resources that will be deleted
    list_resources "$RESOURCE_GROUP"
    
    # Get cleanup mode preference
    cleanup_mode_menu
    local cleanup_mode=$?
    
    # Confirm deletion
    confirm_deletion "$RESOURCE_GROUP"
    
    # Stop Function App before deletion
    stop_function_app
    
    # Perform cleanup based on selected mode
    case $cleanup_mode in
        0)  # Full cleanup (resource group)
            delete_resource_group "$RESOURCE_GROUP"
            ;;
        1)  # Individual resources only
            delete_individual_resources "$RESOURCE_GROUP" "false"
            ;;
        2)  # Resource group only
            delete_resource_group "$RESOURCE_GROUP"
            ;;
    esac
    
    # Clean up local files
    cleanup_local_files
    
    # Verify deletion
    verify_deletion "$RESOURCE_GROUP"
    
    # Display summary
    display_summary
}

# Script help function
show_help() {
    echo "Azure Image Analysis Function Cleanup Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -f, --force             Skip confirmation prompts (USE WITH CAUTION)"
    echo "  -w, --wait              Wait for deletion to complete"
    echo "  --resource-group NAME   Specify resource group name"
    echo "  --local-only            Clean up local files only (no Azure resources)"
    echo
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP          Override resource group name"
    echo "  WAIT_FOR_COMPLETION     Set to 'true' to wait for deletion completion"
    echo
    echo "Examples:"
    echo "  $0                      Interactive cleanup with prompts"
    echo "  $0 --force              Force cleanup without confirmations"
    echo "  $0 --local-only         Clean up local files only"
    echo
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--force)
                export FORCE_DELETE="true"
                ;;
            -w|--wait)
                export WAIT_FOR_COMPLETION="true"
                ;;
            --resource-group)
                export RESOURCE_GROUP="$2"
                shift
                ;;
            --local-only)
                export LOCAL_ONLY="true"
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
}

# Handle local-only cleanup
handle_local_only() {
    if [ "${LOCAL_ONLY:-false}" = "true" ]; then
        log_info "Performing local-only cleanup..."
        cleanup_local_files
        log_success "Local cleanup completed"
        exit 0
    fi
}

# Override confirmation if force delete is enabled
override_confirmation() {
    if [ "${FORCE_DELETE:-false}" = "true" ]; then
        log_warning "Force delete enabled - skipping confirmation prompts"
        confirm_deletion() {
            log_warning "FORCE DELETE: Skipping confirmation for $1"
        }
    fi
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    parse_arguments "$@"
    handle_local_only
    override_confirmation
    main
fi