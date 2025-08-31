#!/bin/bash

# AI Assistant with Custom Functions using OpenAI and Functions - Cleanup Script
# This script safely removes all Azure resources created by the deployment script
#
# Author: Azure Recipe Generator
# Version: 1.0
# Last Updated: 2025-01-17

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[1;34m' # No Color

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate Azure CLI login
validate_azure_login() {
    log_info "Validating Azure CLI login..."
    if ! az account show &>/dev/null; then
        log_error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
    
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    local account_name
    account_name=$(az account show --query name --output tsv)
    
    log_success "Logged into Azure subscription: $account_name ($subscription_id)"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Python for assistant cleanup
    if ! command_exists python3; then
        log_warning "Python 3 is not installed. AI Assistant cleanup may fail."
    fi
    
    validate_azure_login
    log_success "Prerequisites validated"
}

# Function to load configuration
load_configuration() {
    log_info "Loading deployment configuration..."
    
    # Try to load from deployment-config.env if it exists
    if [[ -f "deployment-config.env" ]]; then
        log_info "Loading configuration from deployment-config.env"
        # shellcheck source=/dev/null
        source deployment-config.env
        log_success "Configuration loaded from file"
    else
        log_warning "deployment-config.env not found, using environment variables or prompting for values"
    fi
    
    # Prompt for required values if not set
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        read -p "Enter Resource Group name: " RESOURCE_GROUP
        export RESOURCE_GROUP
    fi
    
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        log_error "Resource Group name is required"
        exit 1
    fi
    
    log_info "Using Resource Group: $RESOURCE_GROUP"
}

# Function to confirm destruction
confirm_destruction() {
    echo
    log_warning "=========================================="
    log_warning "DESTRUCTIVE ACTION WARNING"
    log_warning "=========================================="
    log_warning "This script will permanently delete:"
    log_warning "  • Resource Group: ${RESOURCE_GROUP}"
    log_warning "  • All resources within the resource group"
    log_warning "  • AI Assistant and conversation data"
    log_warning "  • Azure Functions and their data"
    log_warning "  • Storage accounts and all blob data"
    log_warning "  • Azure OpenAI account and deployments"
    echo
    log_warning "This action CANNOT be undone!"
    echo
    
    if [[ "${FORCE_DESTROY:-false}" == "true" ]]; then
        log_warning "Force destroy mode enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    echo
    read -p "This is your last chance to cancel. Type 'DELETE' to proceed: " final_confirm
    if [[ "$final_confirm" != "DELETE" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource destruction..."
}

# Function to clean up AI Assistant
cleanup_ai_assistant() {
    log_info "Cleaning up AI Assistant resources..."
    
    if [[ -z "${ASSISTANT_ID:-}" || -z "${OPENAI_KEY:-}" || -z "${OPENAI_ENDPOINT:-}" ]]; then
        log_warning "AI Assistant configuration not found, skipping assistant cleanup"
        return 0
    fi
    
    if ! command_exists python3; then
        log_warning "Python 3 not available, skipping AI Assistant cleanup"
        return 0
    fi
    
    # Install required packages if not already installed
    if ! python3 -c "import openai" &>/dev/null; then
        log_info "Installing required Python packages for cleanup..."
        pip install openai --quiet || pip install openai --user --quiet || true
    fi
    
    # Create cleanup script
    cat > cleanup-assistant.py << 'EOF'
import os
import sys

try:
    from openai import AzureOpenAI
    
    # Initialize Azure OpenAI client
    client = AzureOpenAI(
        api_key=os.getenv("OPENAI_KEY"),
        api_version="2024-02-15-preview",
        azure_endpoint=os.getenv("OPENAI_ENDPOINT")
    )
    
    assistant_id = os.getenv("ASSISTANT_ID")
    if assistant_id:
        try:
            client.beta.assistants.delete(assistant_id)
            print(f"Assistant {assistant_id} deleted successfully")
        except Exception as e:
            print(f"Warning: Could not delete assistant {assistant_id}: {e}", file=sys.stderr)
    else:
        print("No assistant ID found")
        
except ImportError:
    print("OpenAI package not available, skipping assistant cleanup", file=sys.stderr)
except Exception as e:
    print(f"Error during assistant cleanup: {e}", file=sys.stderr)
EOF
    
    # Run assistant cleanup
    if ! python3 cleanup-assistant.py; then
        log_warning "AI Assistant cleanup completed with warnings"
    else
        log_success "AI Assistant resources cleaned up"
    fi
    
    # Clean up the temporary script
    rm -f cleanup-assistant.py
}

# Function to check if resource group exists
check_resource_group_exists() {
    if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' does not exist or is not accessible"
        return 1
    fi
    return 0
}

# Function to list resources in the resource group
list_resources() {
    log_info "Listing resources in resource group: $RESOURCE_GROUP"
    
    if ! check_resource_group_exists; then
        return 1
    fi
    
    local resources
    resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table 2>/dev/null || echo "")
    
    if [[ -n "$resources" ]]; then
        echo "$resources"
        
        # Count resources
        local resource_count
        resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
        log_info "Found $resource_count resources to delete"
    else
        log_info "No resources found in resource group"
    fi
}

# Function to delete individual resources with retries
delete_individual_resources() {
    log_info "Attempting to delete individual resources first..."
    
    if ! check_resource_group_exists; then
        return 0
    fi
    
    # Get list of resources
    local resource_ids
    resource_ids=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].id" --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$resource_ids" ]]; then
        log_info "No individual resources to delete"
        return 0
    fi
    
    # Delete resources one by one with error handling
    while IFS= read -r resource_id; do
        if [[ -n "$resource_id" ]]; then
            local resource_name
            resource_name=$(basename "$resource_id")
            
            log_info "Deleting resource: $resource_name"
            
            if az resource delete --ids "$resource_id" --output none 2>/dev/null; then
                log_success "Deleted: $resource_name"
            else
                log_warning "Could not delete: $resource_name (will be handled by resource group deletion)"
            fi
        fi
    done <<< "$resource_ids"
    
    log_info "Individual resource deletion completed"
}

# Function to delete the resource group
delete_resource_group() {
    log_info "Deleting resource group: $RESOURCE_GROUP"
    
    if ! check_resource_group_exists; then
        log_success "Resource group does not exist, nothing to delete"
        return 0
    fi
    
    # Start resource group deletion
    log_info "Starting resource group deletion (this may take several minutes)..."
    
    if [[ "${WAIT_FOR_DELETION:-true}" == "true" ]]; then
        # Synchronous deletion - wait for completion
        if az group delete --name "$RESOURCE_GROUP" --yes --output none; then
            log_success "Resource group deleted successfully: $RESOURCE_GROUP"
        else
            log_error "Failed to delete resource group: $RESOURCE_GROUP"
            return 1
        fi
    else
        # Asynchronous deletion - don't wait
        if az group delete --name "$RESOURCE_GROUP" --yes --no-wait --output none; then
            log_success "Resource group deletion initiated: $RESOURCE_GROUP"
            log_info "Deletion is running in the background and may take several minutes to complete"
        else
            log_error "Failed to initiate resource group deletion: $RESOURCE_GROUP"
            return 1
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "assistant-functions/"
        "create-assistant.py"
        "conversation-manager.py"
        "assistant_id.txt"
        "cleanup-assistant.py"
        "deployment-config.env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            if rm -rf "$file" 2>/dev/null; then
                log_success "Removed: $file"
            else
                log_warning "Could not remove: $file"
            fi
        fi
    done
    
    log_success "Local cleanup completed"
}

# Function to clear environment variables
clear_environment_variables() {
    log_info "Clearing environment variables..."
    
    local vars_to_unset=(
        "RESOURCE_GROUP"
        "LOCATION"
        "SUBSCRIPTION_ID"
        "RANDOM_SUFFIX"
        "OPENAI_ACCOUNT"
        "FUNCTION_APP"
        "STORAGE_ACCOUNT"
        "OPENAI_ENDPOINT"
        "OPENAI_KEY"
        "STORAGE_CONNECTION_STRING"
        "MODEL_DEPLOYMENT"
        "ASSISTANT_ID"
        "CUSTOMER_FUNCTION_URL"
        "ANALYTICS_FUNCTION_URL"
    )
    
    for var in "${vars_to_unset[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            unset "$var"
            log_info "Cleared: $var"
        fi
    done
    
    log_success "Environment variables cleared"
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    if check_resource_group_exists; then
        if [[ "${WAIT_FOR_DELETION:-true}" == "true" ]]; then
            log_warning "Resource group still exists after deletion attempt"
            
            # List remaining resources
            local remaining_resources
            remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
            
            if [[ "$remaining_resources" -gt 0 ]]; then
                log_warning "$remaining_resources resources still remain in the resource group"
                log_info "Listing remaining resources:"
                list_resources
            else
                log_info "Resource group exists but contains no resources"
            fi
        else
            log_info "Resource group deletion is running asynchronously"
            log_info "You can check the status in the Azure portal or run: az group show --name $RESOURCE_GROUP"
        fi
    else
        log_success "Resource group successfully deleted"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo
    log_success "=== CLEANUP COMPLETED ==="
    echo
    
    if [[ "${WAIT_FOR_DELETION:-true}" == "true" ]]; then
        log_info "Resource Group: $RESOURCE_GROUP - Deleted"
    else
        log_info "Resource Group: $RESOURCE_GROUP - Deletion initiated (running in background)"
    fi
    
    log_info "AI Assistant: Cleaned up"
    log_info "Local Files: Cleaned up"
    log_info "Environment Variables: Cleared"
    echo
    
    if [[ "${WAIT_FOR_DELETION:-true}" != "true" ]]; then
        log_warning "Note: Resource deletion is still in progress"
        log_info "Monitor deletion status: az group show --name $RESOURCE_GROUP"
        log_info "Check Azure portal for final confirmation"
    fi
    
    log_success "Azure AI Assistant cleanup completed successfully!"
}

# Function to handle script interruption
handle_interruption() {
    log_error "Cleanup interrupted by user"
    log_warning "Some resources may not have been deleted"
    log_info "You can run this script again to complete the cleanup"
    exit 130
}

# Main cleanup function
main() {
    echo "=========================================="
    echo "Azure AI Assistant Cleanup Script"
    echo "=========================================="
    echo
    
    # Handle command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE_DESTROY=true
                log_info "Force destroy mode enabled"
                shift
                ;;
            --async)
                export WAIT_FOR_DELETION=false
                log_info "Async deletion mode enabled"
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Options:"
                echo "  --force    Skip confirmation prompts"
                echo "  --async    Don't wait for resource deletion to complete"
                echo "  --help     Show this help message"
                echo
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                log_info "Run '$0 --help' for usage information"
                exit 1
                ;;
        esac
    done
    
    # Cleanup steps
    check_prerequisites
    load_configuration
    confirm_destruction
    list_resources
    cleanup_ai_assistant
    delete_individual_resources
    delete_resource_group
    cleanup_local_files
    clear_environment_variables
    verify_deletion
    display_cleanup_summary
    
    log_success "Azure AI Assistant cleanup completed successfully!"
}

# Set up signal handlers
trap handle_interruption INT TERM

# Run main function
main "$@"