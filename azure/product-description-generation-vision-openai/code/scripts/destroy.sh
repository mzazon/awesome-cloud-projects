#!/bin/bash

# Product Description Generation with AI Vision and OpenAI - Cleanup Script
# This script removes all Azure resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

# Script metadata
SCRIPT_NAME="Azure Product Description Generator Cleanup"
SCRIPT_VERSION="1.0"
CLEANUP_START_TIME=$(date)

log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
log_info "Cleanup initiated at: $CLEANUP_START_TIME"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Look for deployment info file
    DEPLOYMENT_INFO_FILE=""
    
    # Check for deployment info file in current directory
    for file in deployment-info-*.json; do
        if [ -f "$file" ]; then
            DEPLOYMENT_INFO_FILE="$file"
            break
        fi
    done
    
    if [ -n "$DEPLOYMENT_INFO_FILE" ] && [ -f "$DEPLOYMENT_INFO_FILE" ]; then
        log_info "Found deployment info file: $DEPLOYMENT_INFO_FILE"
        
        # Extract values from JSON file using basic shell commands
        if command -v jq &> /dev/null; then
            # Use jq if available
            RESOURCE_GROUP=$(jq -r '.resource_group' "$DEPLOYMENT_INFO_FILE")
            LOCATION=$(jq -r '.location' "$DEPLOYMENT_INFO_FILE")
            STORAGE_ACCOUNT=$(jq -r '.storage_account' "$DEPLOYMENT_INFO_FILE")
            FUNCTION_APP=$(jq -r '.function_app' "$DEPLOYMENT_INFO_FILE")
            AI_VISION_NAME=$(jq -r '.ai_vision_service' "$DEPLOYMENT_INFO_FILE")
            OPENAI_NAME=$(jq -r '.openai_service' "$DEPLOYMENT_INFO_FILE")
            RANDOM_SUFFIX=$(jq -r '.random_suffix' "$DEPLOYMENT_INFO_FILE")
        else
            # Fallback parsing without jq
            RESOURCE_GROUP=$(grep '"resource_group"' "$DEPLOYMENT_INFO_FILE" | cut -d'"' -f4)
            LOCATION=$(grep '"location"' "$DEPLOYMENT_INFO_FILE" | cut -d'"' -f4)
            STORAGE_ACCOUNT=$(grep '"storage_account"' "$DEPLOYMENT_INFO_FILE" | cut -d'"' -f4)
            FUNCTION_APP=$(grep '"function_app"' "$DEPLOYMENT_INFO_FILE" | cut -d'"' -f4)
            AI_VISION_NAME=$(grep '"ai_vision_service"' "$DEPLOYMENT_INFO_FILE" | cut -d'"' -f4)
            OPENAI_NAME=$(grep '"openai_service"' "$DEPLOYMENT_INFO_FILE" | cut -d'"' -f4)
            RANDOM_SUFFIX=$(grep '"random_suffix"' "$DEPLOYMENT_INFO_FILE" | cut -d'"' -f4)
        fi
        
        log_success "Deployment information loaded successfully"
    else
        log_warning "No deployment info file found. Using environment variables or defaults."
        
        # Use environment variables or defaults
        RESOURCE_GROUP="${RESOURCE_GROUP:-}"
        LOCATION="${LOCATION:-eastus}"
        STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-}"
        FUNCTION_APP="${FUNCTION_APP:-}"
        AI_VISION_NAME="${AI_VISION_NAME:-}"
        OPENAI_NAME="${OPENAI_NAME:-}"
        RANDOM_SUFFIX="${RANDOM_SUFFIX:-}"
    fi
}

# Set environment variables if not loaded from file
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # If no resource group specified, prompt user
    if [ -z "$RESOURCE_GROUP" ]; then
        echo ""
        echo "No resource group information found."
        echo "Please specify the resource group to delete."
        echo ""
        echo "Available resource groups:"
        az group list --query "[].name" --output table
        echo ""
        read -p "Enter resource group name: " RESOURCE_GROUP
        
        if [ -z "$RESOURCE_GROUP" ]; then
            log_error "Resource group name is required"
            exit 1
        fi
    fi
    
    # Set default values if not already set
    LOCATION="${LOCATION:-eastus}"
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    log_success "Environment variables configured"
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
}

# Verify resource group exists
verify_resource_group() {
    log_info "Verifying resource group exists..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_success "Resource group '$RESOURCE_GROUP' found"
        
        # List resources in the group
        log_info "Resources in group '$RESOURCE_GROUP':"
        az resource list --resource-group "$RESOURCE_GROUP" --output table
        echo ""
    else
        log_error "Resource group '$RESOURCE_GROUP' not found"
        echo ""
        echo "Available resource groups:"
        az group list --query "[].name" --output table
        exit 1
    fi
}

# Confirm deletion
confirm_deletion() {
    log_warning "This will permanently delete ALL resources in the resource group: $RESOURCE_GROUP"
    log_warning "This action cannot be undone!"
    echo ""
    
    if [ "$FORCE_DELETE" = true ]; then
        log_info "Force delete mode enabled. Skipping confirmation."
        return
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRMATION
    
    if [ "$CONFIRMATION" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    log_info "Proceeding with resource cleanup..."
}

# Remove Function App and Event Grid subscriptions
cleanup_function_resources() {
    log_info "Cleaning up Function App and Event Grid resources..."
    
    # Try to find and delete Function App if name is known
    if [ -n "$FUNCTION_APP" ]; then
        log_info "Attempting to delete Function App: $FUNCTION_APP"
        
        if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az functionapp delete \
                --name "$FUNCTION_APP" \
                --resource-group "$RESOURCE_GROUP" \
                --output none
            
            log_success "Function App '$FUNCTION_APP' deleted"
        else
            log_warning "Function App '$FUNCTION_APP' not found or already deleted"
        fi
    else
        log_info "Searching for Function Apps in resource group..."
        
        # Find all Function Apps in the resource group
        FUNCTION_APPS=$(az functionapp list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
        
        if [ -n "$FUNCTION_APPS" ]; then
            for app in $FUNCTION_APPS; do
                log_info "Deleting Function App: $app"
                az functionapp delete \
                    --name "$app" \
                    --resource-group "$RESOURCE_GROUP" \
                    --output none
                log_success "Function App '$app' deleted"
            done
        else
            log_info "No Function Apps found in resource group"
        fi
    fi
    
    # Clean up Event Grid subscriptions
    log_info "Cleaning up Event Grid subscriptions..."
    
    if [ -n "$STORAGE_ACCOUNT" ]; then
        # Try to delete specific Event Grid subscription
        STORAGE_RESOURCE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}"
        
        EVENT_SUBS=$(az eventgrid event-subscription list --source-resource-id "$STORAGE_RESOURCE_ID" --query "[].name" --output tsv 2>/dev/null || true)
        
        if [ -n "$EVENT_SUBS" ]; then
            for sub in $EVENT_SUBS; do
                log_info "Deleting Event Grid subscription: $sub"
                az eventgrid event-subscription delete \
                    --name "$sub" \
                    --source-resource-id "$STORAGE_RESOURCE_ID" \
                    --output none
                log_success "Event Grid subscription '$sub' deleted"
            done
        else
            log_info "No Event Grid subscriptions found for storage account"
        fi
    fi
}

# Remove AI Services
cleanup_ai_services() {
    log_info "Cleaning up AI Services..."
    
    # Remove OpenAI Service
    if [ -n "$OPENAI_NAME" ]; then
        log_info "Attempting to delete OpenAI service: $OPENAI_NAME"
        
        if az cognitiveservices account show --name "$OPENAI_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az cognitiveservices account delete \
                --name "$OPENAI_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --output none
            
            log_success "OpenAI service '$OPENAI_NAME' deleted"
        else
            log_warning "OpenAI service '$OPENAI_NAME' not found or already deleted"
        fi
    else
        log_info "Searching for OpenAI services in resource group..."
        
        # Find all OpenAI services in the resource group
        OPENAI_SERVICES=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?kind=='OpenAI'].name" --output tsv)
        
        if [ -n "$OPENAI_SERVICES" ]; then
            for service in $OPENAI_SERVICES; do
                log_info "Deleting OpenAI service: $service"
                az cognitiveservices account delete \
                    --name "$service" \
                    --resource-group "$RESOURCE_GROUP" \
                    --output none
                log_success "OpenAI service '$service' deleted"
            done
        else
            log_info "No OpenAI services found in resource group"
        fi
    fi
    
    # Remove AI Vision Service
    if [ -n "$AI_VISION_NAME" ]; then
        log_info "Attempting to delete AI Vision service: $AI_VISION_NAME"
        
        if az cognitiveservices account show --name "$AI_VISION_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az cognitiveservices account delete \
                --name "$AI_VISION_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --output none
            
            log_success "AI Vision service '$AI_VISION_NAME' deleted"
        else
            log_warning "AI Vision service '$AI_VISION_NAME' not found or already deleted"
        fi
    else
        log_info "Searching for Computer Vision services in resource group..."
        
        # Find all Computer Vision services in the resource group
        VISION_SERVICES=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?kind=='ComputerVision'].name" --output tsv)
        
        if [ -n "$VISION_SERVICES" ]; then
            for service in $VISION_SERVICES; do
                log_info "Deleting Computer Vision service: $service"
                az cognitiveservices account delete \
                    --name "$service" \
                    --resource-group "$RESOURCE_GROUP" \
                    --output none
                log_success "Computer Vision service '$service' deleted"
            done
        else
            log_info "No Computer Vision services found in resource group"
        fi
    fi
}

# Remove Storage Account
cleanup_storage_resources() {
    log_info "Cleaning up Storage Account..."
    
    if [ -n "$STORAGE_ACCOUNT" ]; then
        log_info "Attempting to delete Storage Account: $STORAGE_ACCOUNT"
        
        if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az storage account delete \
                --name "$STORAGE_ACCOUNT" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none
            
            log_success "Storage Account '$STORAGE_ACCOUNT' deleted"
        else
            log_warning "Storage Account '$STORAGE_ACCOUNT' not found or already deleted"
        fi
    else
        log_info "Searching for Storage Accounts in resource group..."
        
        # Find all storage accounts in the resource group
        STORAGE_ACCOUNTS=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
        
        if [ -n "$STORAGE_ACCOUNTS" ]; then
            for account in $STORAGE_ACCOUNTS; do
                log_info "Deleting Storage Account: $account"
                az storage account delete \
                    --name "$account" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes \
                    --output none
                log_success "Storage Account '$account' deleted"
            done
        else
            log_info "No Storage Accounts found in resource group"
        fi
    fi
}

# Delete entire resource group
delete_resource_group() {
    log_info "Deleting resource group..."
    
    # Final confirmation for resource group deletion
    if [ "$FORCE_DELETE" != true ]; then
        echo ""
        log_warning "Final confirmation: Delete resource group '$RESOURCE_GROUP' and ALL remaining resources?"
        read -p "Type 'DELETE' to confirm: " FINAL_CONFIRMATION
        
        if [ "$FINAL_CONFIRMATION" != "DELETE" ]; then
            log_info "Resource group deletion cancelled"
            return
        fi
    fi
    
    log_info "Deleting resource group '$RESOURCE_GROUP'..."
    
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none
    
    log_success "Resource group deletion initiated"
    log_info "Note: Complete deletion may take several minutes to complete in the background"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment info file
    if [ -n "$DEPLOYMENT_INFO_FILE" ] && [ -f "$DEPLOYMENT_INFO_FILE" ]; then
        rm -f "$DEPLOYMENT_INFO_FILE"
        log_success "Deployment info file removed: $DEPLOYMENT_INFO_FILE"
    fi
    
    # Remove any test files that might exist
    TEST_FILES=("test-product.jpg" "generated-description.json")
    for file in "${TEST_FILES[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_success "Test file removed: $file"
        fi
    done
    
    log_success "Local file cleanup completed"
}

# Display cleanup summary
display_summary() {
    log_info "Cleanup Summary:"
    echo "=================================="
    echo "Resource Group: $RESOURCE_GROUP (deleted)"
    echo "Location: $LOCATION"
    
    if [ -n "$STORAGE_ACCOUNT" ]; then
        echo "Storage Account: $STORAGE_ACCOUNT (deleted)"
    fi
    
    if [ -n "$FUNCTION_APP" ]; then
        echo "Function App: $FUNCTION_APP (deleted)"
    fi
    
    if [ -n "$AI_VISION_NAME" ]; then
        echo "AI Vision Service: $AI_VISION_NAME (deleted)"
    fi
    
    if [ -n "$OPENAI_NAME" ]; then
        echo "OpenAI Service: $OPENAI_NAME (deleted)"
    fi
    
    echo "=================================="
    echo ""
    
    log_success "Cleanup completed successfully!"
    echo ""
    echo "Important Notes:"
    echo "- All Azure resources have been deleted"
    echo "- You will no longer be charged for these resources"
    echo "- Deleted resources cannot be recovered"
    echo "- Some resources may take a few minutes to fully delete in Azure"
    echo ""
    echo "If you need to recreate the infrastructure, run: ./deploy.sh"
    echo ""
    
    CLEANUP_END_TIME=$(date)
    log_info "Cleanup completed at: $CLEANUP_END_TIME"
}

# Error handling function
handle_error() {
    log_error "Cleanup failed at step: $1"
    log_error "Error details: $2"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check Azure CLI authentication: az account show"
    echo "2. Verify resource group still exists: az group show --name $RESOURCE_GROUP"
    echo "3. Check for any remaining resources: az resource list --resource-group $RESOURCE_GROUP"
    echo "4. Try deleting specific resources manually through Azure Portal"
    echo ""
    echo "You can retry cleanup by running this script again"
    exit 1
}

# Comprehensive cleanup (alternative to resource group deletion)
comprehensive_cleanup() {
    log_info "Performing comprehensive resource cleanup..."
    
    cleanup_function_resources || log_warning "Function resources cleanup encountered issues"
    cleanup_ai_services || log_warning "AI services cleanup encountered issues"
    cleanup_storage_resources || log_warning "Storage resources cleanup encountered issues"
    
    # Check if resource group is now empty
    REMAINING_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv)
    
    if [ "$REMAINING_RESOURCES" -eq 0 ]; then
        log_info "All resources removed. Deleting empty resource group..."
        delete_resource_group
    else
        log_warning "Some resources remain in the resource group:"
        az resource list --resource-group "$RESOURCE_GROUP" --output table
        echo ""
        log_info "You may need to delete these resources manually or run the script again"
    fi
}

# Main cleanup workflow
main() {
    log_info "Initializing cleanup workflow..."
    
    # Set trap for error handling
    trap 'handle_error "Unknown step" "$?"' ERR
    
    check_prerequisites || handle_error "Prerequisites check" "$?"
    load_deployment_info || handle_error "Loading deployment info" "$?"
    set_environment_variables || handle_error "Environment setup" "$?"
    verify_resource_group || handle_error "Resource group verification" "$?"
    confirm_deletion || handle_error "User confirmation" "$?"
    
    if [ "$COMPREHENSIVE_CLEANUP" = true ]; then
        comprehensive_cleanup || handle_error "Comprehensive cleanup" "$?"
    else
        delete_resource_group || handle_error "Resource group deletion" "$?"
    fi
    
    cleanup_local_files || handle_error "Local file cleanup" "$?"
    display_summary
}

# Script options handling
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -g, --resource-group RG Specify resource group to delete"
    echo "  -f, --force             Skip confirmation prompts"
    echo "  --comprehensive         Delete resources individually before deleting resource group"
    echo "  --dry-run              Show what would be deleted without executing"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP         Resource group name to delete"
    echo "  FORCE_DELETE           Skip confirmation prompts (true/false)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup with prompts"
    echo "  $0 --resource-group my-rg            # Delete specific resource group"
    echo "  $0 --force                           # Skip all confirmation prompts"
    echo "  $0 --comprehensive                   # Delete resources individually first"
    echo ""
    echo "Safety Features:"
    echo "- Requires explicit confirmation before deletion"
    echo "- Shows all resources before deletion"
    echo "- Provides detailed logging of all operations"
    echo "- Supports dry-run mode to preview operations"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        --comprehensive)
            COMPREHENSIVE_CLEANUP=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Handle dry run mode
if [ "$DRY_RUN" = true ]; then
    log_info "DRY RUN MODE - No resources will be deleted"
    load_deployment_info
    set_environment_variables
    
    if [ -n "$RESOURCE_GROUP" ]; then
        verify_resource_group
    else
        echo "No resource group specified for dry run"
    fi
    
    echo ""
    echo "Resources that would be deleted:"
    echo "- Entire Resource Group: $RESOURCE_GROUP"
    echo "- All contained resources including:"
    echo "  - Storage Accounts and data"
    echo "  - Function Apps and code"
    echo "  - AI Vision services"
    echo "  - OpenAI services and model deployments"
    echo "  - Event Grid subscriptions"
    echo "- Local deployment info files"
    echo ""
    exit 0
fi

# Execute main cleanup
main "$@"