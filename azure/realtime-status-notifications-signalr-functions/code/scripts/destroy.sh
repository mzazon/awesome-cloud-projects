#!/bin/bash

# Real-time Status Notifications with SignalR and Functions - Cleanup Script
# This script removes all Azure resources created by the deploy.sh script

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load environment variables
load_environment_variables() {
    log_info "Loading environment variables..."
    
    if [ -f .env ]; then
        source .env
        log_success "Environment variables loaded from .env file"
        log_info "Resource Group: ${RESOURCE_GROUP:-Not set}"
        log_info "SignalR Service: ${SIGNALR_NAME:-Not set}"
        log_info "Function App: ${FUNCTION_APP_NAME:-Not set}"
        log_info "Storage Account: ${STORAGE_ACCOUNT:-Not set}"
    else
        log_warning ".env file not found. You will need to provide resource information manually."
        
        # Prompt for resource group name
        read -p "Enter Resource Group name to delete (or press Enter to cancel): " RESOURCE_GROUP
        
        if [ -z "$RESOURCE_GROUP" ]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
        
        # Set other variables to empty (will be cleaned up with resource group)
        export SIGNALR_NAME=""
        export FUNCTION_APP_NAME=""
        export STORAGE_ACCOUNT=""
    fi
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    log_warning "⚠️  WARNING: This will permanently delete the following Azure resources:"
    echo ""
    echo "  • Resource Group: ${RESOURCE_GROUP}"
    
    if [ -n "${SIGNALR_NAME:-}" ]; then
        echo "  • SignalR Service: ${SIGNALR_NAME}"
    fi
    
    if [ -n "${FUNCTION_APP_NAME:-}" ]; then
        echo "  • Function App: ${FUNCTION_APP_NAME}"
    fi
    
    if [ -n "${STORAGE_ACCOUNT:-}" ]; then
        echo "  • Storage Account: ${STORAGE_ACCOUNT}"
    fi
    
    echo "  • All associated resources in the resource group"
    echo ""
    log_warning "This action cannot be undone!"
    echo ""
    
    # Double confirmation for safety
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " CONFIRM1
    
    if [ "$CONFIRM1" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    read -p "Last chance! Type 'DELETE' to permanently remove all resources: " CONFIRM2
    
    if [ "$CONFIRM2" != "DELETE" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "User confirmed deletion. Proceeding with cleanup..."
}

# Function to check if resource group exists
check_resource_group_exists() {
    log_info "Checking if resource group exists..."
    
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_info "Resource group '${RESOURCE_GROUP}' found"
        return 0
    else
        log_warning "Resource group '${RESOURCE_GROUP}' not found"
        return 1
    fi
}

# Function to list resources in the group
list_resources() {
    log_info "Listing resources in resource group '${RESOURCE_GROUP}'..."
    
    local resources
    resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type, Location:location}" --output table 2>/dev/null || echo "")
    
    if [ -n "$resources" ]; then
        echo "$resources"
        echo ""
        
        # Count resources
        local resource_count
        resource_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" --output tsv 2>/dev/null || echo "0")
        log_info "Found ${resource_count} resources to delete"
    else
        log_info "No resources found in resource group"
    fi
}

# Function to delete individual resources (optional, more granular control)
delete_individual_resources() {
    log_info "Attempting to delete individual resources first..."
    
    # Delete Function App first (to stop any running functions)
    if [ -n "${FUNCTION_APP_NAME:-}" ]; then
        log_info "Deleting Function App: ${FUNCTION_APP_NAME}..."
        
        if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
            az functionapp delete \
                --name "${FUNCTION_APP_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes 2>/dev/null || log_warning "Failed to delete Function App (may not exist)"
            
            log_success "Function App deletion initiated"
        else
            log_warning "Function App '${FUNCTION_APP_NAME}' not found"
        fi
    fi
    
    # Delete SignalR Service
    if [ -n "${SIGNALR_NAME:-}" ]; then
        log_info "Deleting SignalR Service: ${SIGNALR_NAME}..."
        
        if az signalr show --name "${SIGNALR_NAME}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
            az signalr delete \
                --name "${SIGNALR_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes 2>/dev/null || log_warning "Failed to delete SignalR Service (may not exist)"
            
            log_success "SignalR Service deletion initiated"
        else
            log_warning "SignalR Service '${SIGNALR_NAME}' not found"
        fi
    fi
    
    # Delete Storage Account
    if [ -n "${STORAGE_ACCOUNT:-}" ]; then
        log_info "Deleting Storage Account: ${STORAGE_ACCOUNT}..."
        
        if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
            az storage account delete \
                --name "${STORAGE_ACCOUNT}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes 2>/dev/null || log_warning "Failed to delete Storage Account (may not exist)"
            
            log_success "Storage Account deletion initiated"
        else
            log_warning "Storage Account '${STORAGE_ACCOUNT}' not found"
        fi
    fi
    
    # Wait a moment for resources to start deleting
    log_info "Waiting for individual resource deletions to process..."
    sleep 10
}

# Function to delete resource group
delete_resource_group() {
    log_info "Deleting resource group: ${RESOURCE_GROUP}..."
    
    # Delete resource group (this will delete all contained resources)
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Note: Complete deletion may take several minutes to finish in the background"
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource group deletion..."
    
    # Wait a bit for deletion to start
    sleep 5
    
    # Check if resource group still exists
    local max_attempts=12
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ! az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
            log_success "Resource group '${RESOURCE_GROUP}' has been deleted"
            return 0
        fi
        
        log_info "Deletion in progress... (attempt ${attempt}/${max_attempts})"
        sleep 10
        ((attempt++))
    done
    
    log_warning "Resource group deletion is taking longer than expected"
    log_info "You can check the status in the Azure portal or run:"
    log_info "  az group show --name '${RESOURCE_GROUP}'"
    
    return 1
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(".env" "test-client.html")
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_success "Removed local file: $file"
        fi
    done
    
    # Remove any temporary directories or logs
    if [ -d "temp" ]; then
        rm -rf temp
        log_success "Removed temporary directory"
    fi
    
    log_success "Local cleanup completed"
}

# Function to display cleanup summary
display_summary() {
    echo ""
    log_success "=== CLEANUP SUMMARY ==="
    echo ""
    log_info "The following actions were performed:"
    echo "  ✅ Resource group deletion initiated: ${RESOURCE_GROUP}"
    echo "  ✅ All Azure resources scheduled for removal"
    echo "  ✅ Local files cleaned up"
    echo ""
    log_info "Notes:"
    echo "  • Azure resource deletion continues in the background"
    echo "  • It may take 5-10 minutes for all resources to be fully removed"
    echo "  • You can monitor progress in the Azure portal"
    echo "  • No further charges will be incurred once deletion completes"
    echo ""
    log_success "Cleanup process completed!"
}

# Function to handle errors gracefully
handle_error() {
    local exit_code=$?
    log_error "An error occurred during cleanup (exit code: $exit_code)"
    
    echo ""
    log_info "Troubleshooting tips:"
    echo "  1. Check if you're logged into the correct Azure subscription"
    echo "  2. Verify resource group name spelling"
    echo "  3. Ensure you have permissions to delete resources"
    echo "  4. Try running the script again"
    echo "  5. Delete resources manually in Azure portal if needed"
    echo ""
    
    exit $exit_code
}

# Function to show help
show_help() {
    echo "Azure SignalR and Functions Cleanup Script"
    echo ""
    echo "Usage:"
    echo "  ./destroy.sh              - Interactive cleanup using .env file"
    echo "  ./destroy.sh --help       - Show this help message"
    echo "  ./destroy.sh --force      - Skip confirmation prompts (use with caution)"
    echo ""
    echo "This script will:"
    echo "  1. Load resource information from .env file"
    echo "  2. Confirm deletion with user"
    echo "  3. Delete all Azure resources"
    echo "  4. Clean up local files"
    echo ""
    echo "Requirements:"
    echo "  - Azure CLI installed and authenticated"
    echo "  - .env file from deployment (or manual resource group name)"
    echo ""
}

# Main cleanup function
main() {
    local force_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --force|-f)
                force_mode=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log_info "Starting Azure resources cleanup..."
    
    check_prerequisites
    load_environment_variables
    
    # Check if resource group exists
    if ! check_resource_group_exists; then
        log_info "Resource group not found - nothing to clean up"
        cleanup_local_files
        exit 0
    fi
    
    list_resources
    
    # Skip confirmation in force mode
    if [ "$force_mode" = false ]; then
        confirm_deletion
    else
        log_warning "Force mode enabled - skipping confirmation"
    fi
    
    delete_individual_resources
    delete_resource_group
    
    # Verify deletion unless in force mode (to speed up CI/CD)
    if [ "$force_mode" = false ]; then
        verify_deletion
    fi
    
    cleanup_local_files
    display_summary
    
    log_success "Cleanup completed successfully!"
}

# Handle script interruption
trap 'log_error "Cleanup interrupted"; exit 1' INT TERM

# Set error handler
trap 'handle_error' ERR

# Run main function
main "$@"