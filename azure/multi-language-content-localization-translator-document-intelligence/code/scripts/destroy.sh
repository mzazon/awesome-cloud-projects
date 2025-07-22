#!/bin/bash

# Azure Multi-Language Content Localization Workflow Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error

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

# Check if running in dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in dry-run mode - no resources will be deleted"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    log "Executing: $cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would execute: $cmd"
        return 0
    else
        eval "$cmd"
        return $?
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Please log in to Azure CLI using 'az login'"
        exit 1
    fi
    
    success "Prerequisites verified"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Set default values if not already set
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-localization-workflow}"
    export LOCATION="${LOCATION:-eastus}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-}"
    export TRANSLATOR_NAME="${TRANSLATOR_NAME:-}"
    export DOC_INTELLIGENCE_NAME="${DOC_INTELLIGENCE_NAME:-}"
    export LOGIC_APP_NAME="${LOGIC_APP_NAME:-}"
    
    # If resource names are not set, try to discover them
    if [[ -z "$STORAGE_ACCOUNT" || -z "$TRANSLATOR_NAME" || -z "$DOC_INTELLIGENCE_NAME" || -z "$LOGIC_APP_NAME" ]]; then
        warning "Resource names not provided. Attempting to discover resources in resource group: $RESOURCE_GROUP"
        discover_resources
    fi
    
    # Display configuration
    log "Configuration:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Storage Account: $STORAGE_ACCOUNT"
    log "  Translator Name: $TRANSLATOR_NAME"
    log "  Document Intelligence Name: $DOC_INTELLIGENCE_NAME"
    log "  Logic App Name: $LOGIC_APP_NAME"
}

# Function to discover resources in the resource group
discover_resources() {
    log "Discovering resources in resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Check if resource group exists
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            error "Resource group $RESOURCE_GROUP does not exist"
            exit 1
        fi
        
        # Discover storage account
        if [[ -z "$STORAGE_ACCOUNT" ]]; then
            STORAGE_ACCOUNT=$(az storage account list \
                --resource-group "$RESOURCE_GROUP" \
                --query '[0].name' --output tsv 2>/dev/null)
        fi
        
        # Discover Translator service
        if [[ -z "$TRANSLATOR_NAME" ]]; then
            TRANSLATOR_NAME=$(az cognitiveservices account list \
                --resource-group "$RESOURCE_GROUP" \
                --query '[?kind==`TextTranslation`].name | [0]' --output tsv 2>/dev/null)
        fi
        
        # Discover Document Intelligence service
        if [[ -z "$DOC_INTELLIGENCE_NAME" ]]; then
            DOC_INTELLIGENCE_NAME=$(az cognitiveservices account list \
                --resource-group "$RESOURCE_GROUP" \
                --query '[?kind==`FormRecognizer`].name | [0]' --output tsv 2>/dev/null)
        fi
        
        # Discover Logic App
        if [[ -z "$LOGIC_APP_NAME" ]]; then
            LOGIC_APP_NAME=$(az logic workflow list \
                --resource-group "$RESOURCE_GROUP" \
                --query '[0].name' --output tsv 2>/dev/null)
        fi
    fi
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "- Resource Group: $RESOURCE_GROUP"
    echo "- Storage Account: $STORAGE_ACCOUNT (and all data)"
    echo "- Translator Service: $TRANSLATOR_NAME"
    echo "- Document Intelligence Service: $DOC_INTELLIGENCE_NAME"
    echo "- Logic App: $LOGIC_APP_NAME"
    echo "- All associated storage containers and data"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Please type the resource group name '$RESOURCE_GROUP' to confirm: " rg_confirmation
    
    if [[ "$rg_confirmation" != "$RESOURCE_GROUP" ]]; then
        error "Resource group name does not match. Deletion cancelled."
        exit 1
    fi
    
    log "Deletion confirmed. Proceeding with cleanup..."
}

# Function to disable Logic App
disable_logic_app() {
    log "Disabling Logic App..."
    
    if [[ -n "$LOGIC_APP_NAME" ]]; then
        execute_command "az logic workflow disable \
            --name $LOGIC_APP_NAME \
            --resource-group $RESOURCE_GROUP"
        
        if [[ $? -eq 0 ]]; then
            success "Logic App disabled: $LOGIC_APP_NAME"
        else
            warning "Failed to disable Logic App or Logic App not found"
        fi
    else
        warning "Logic App name not found, skipping disable"
    fi
}

# Function to delete Logic App
delete_logic_app() {
    log "Deleting Logic App..."
    
    if [[ -n "$LOGIC_APP_NAME" ]]; then
        execute_command "az logic workflow delete \
            --name $LOGIC_APP_NAME \
            --resource-group $RESOURCE_GROUP \
            --yes"
        
        if [[ $? -eq 0 ]]; then
            success "Logic App deleted: $LOGIC_APP_NAME"
        else
            warning "Failed to delete Logic App or Logic App not found"
        fi
    else
        warning "Logic App name not found, skipping deletion"
    fi
}

# Function to delete API connections
delete_api_connections() {
    log "Deleting API connections..."
    
    connections=("azureblob-connection" "cognitiveservices-connection")
    
    for connection in "${connections[@]}"; do
        execute_command "az resource delete \
            --resource-group $RESOURCE_GROUP \
            --resource-type Microsoft.Web/connections \
            --name $connection"
        
        if [[ $? -eq 0 ]]; then
            success "API connection deleted: $connection"
        else
            warning "Failed to delete API connection or connection not found: $connection"
        fi
    done
}

# Function to delete Document Intelligence service
delete_document_intelligence() {
    log "Deleting Document Intelligence service..."
    
    if [[ -n "$DOC_INTELLIGENCE_NAME" ]]; then
        execute_command "az cognitiveservices account delete \
            --name $DOC_INTELLIGENCE_NAME \
            --resource-group $RESOURCE_GROUP"
        
        if [[ $? -eq 0 ]]; then
            success "Document Intelligence service deleted: $DOC_INTELLIGENCE_NAME"
        else
            warning "Failed to delete Document Intelligence service or service not found"
        fi
    else
        warning "Document Intelligence service name not found, skipping deletion"
    fi
}

# Function to delete Translator service
delete_translator_service() {
    log "Deleting Translator service..."
    
    if [[ -n "$TRANSLATOR_NAME" ]]; then
        execute_command "az cognitiveservices account delete \
            --name $TRANSLATOR_NAME \
            --resource-group $RESOURCE_GROUP"
        
        if [[ $? -eq 0 ]]; then
            success "Translator service deleted: $TRANSLATOR_NAME"
        else
            warning "Failed to delete Translator service or service not found"
        fi
    else
        warning "Translator service name not found, skipping deletion"
    fi
}

# Function to delete storage containers
delete_storage_containers() {
    log "Deleting storage containers..."
    
    if [[ -n "$STORAGE_ACCOUNT" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            # Get storage account key
            STORAGE_KEY=$(az storage account keys list \
                --resource-group $RESOURCE_GROUP \
                --account-name $STORAGE_ACCOUNT \
                --query '[0].value' --output tsv 2>/dev/null)
            
            if [[ -n "$STORAGE_KEY" ]]; then
                containers=("source-documents" "processing-workspace" "localized-output" "workflow-logs")
                
                for container in "${containers[@]}"; do
                    execute_command "az storage container delete \
                        --name $container \
                        --account-name $STORAGE_ACCOUNT \
                        --account-key $STORAGE_KEY"
                    
                    if [[ $? -eq 0 ]]; then
                        success "Storage container deleted: $container"
                    else
                        warning "Failed to delete storage container or container not found: $container"
                    fi
                done
            else
                warning "Could not retrieve storage account key, skipping container deletion"
            fi
        else
            log "[DRY-RUN] Would delete storage containers"
        fi
    else
        warning "Storage account name not found, skipping container deletion"
    fi
}

# Function to delete storage account
delete_storage_account() {
    log "Deleting storage account..."
    
    if [[ -n "$STORAGE_ACCOUNT" ]]; then
        execute_command "az storage account delete \
            --name $STORAGE_ACCOUNT \
            --resource-group $RESOURCE_GROUP \
            --yes"
        
        if [[ $? -eq 0 ]]; then
            success "Storage account deleted: $STORAGE_ACCOUNT"
        else
            warning "Failed to delete storage account or storage account not found"
        fi
    else
        warning "Storage account name not found, skipping deletion"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group..."
    
    execute_command "az group delete \
        --name $RESOURCE_GROUP \
        --yes \
        --no-wait"
    
    if [[ $? -eq 0 ]]; then
        success "Resource group deletion initiated: $RESOURCE_GROUP"
        log "Note: Complete deletion may take several minutes"
    else
        error "Failed to delete resource group"
        exit 1
    fi
}

# Function to verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait a moment for deletion to propagate
        sleep 5
        
        # Check if resource group still exists
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            warning "Resource group still exists. Deletion may still be in progress."
            log "You can check the status in the Azure portal or run 'az group show --name $RESOURCE_GROUP'"
        else
            success "Resource group successfully deleted"
        fi
    else
        log "[DRY-RUN] Would verify deletion"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "================"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "Translator Service: $TRANSLATOR_NAME"
    echo "Document Intelligence: $DOC_INTELLIGENCE_NAME"
    echo "Logic App: $LOGIC_APP_NAME"
    echo ""
    echo "All resources have been deleted or deletion has been initiated."
    echo "You can verify the deletion in the Azure portal."
    echo ""
    echo "Thank you for using the Azure Multi-Language Content Localization Workflow!"
}

# Function to handle partial cleanup
handle_partial_cleanup() {
    log "Performing partial cleanup (individual resources)..."
    
    disable_logic_app
    delete_logic_app
    delete_api_connections
    delete_document_intelligence
    delete_translator_service
    delete_storage_containers
    delete_storage_account
    
    log "Partial cleanup completed. Resource group cleanup will be performed separately."
}

# Function to handle full cleanup
handle_full_cleanup() {
    log "Performing full cleanup (entire resource group)..."
    
    disable_logic_app
    delete_resource_group
    
    log "Full cleanup initiated. All resources will be deleted with the resource group."
}

# Main cleanup function
main() {
    log "Starting Azure Multi-Language Content Localization Workflow cleanup..."
    
    check_prerequisites
    set_environment_variables
    confirm_deletion
    
    # Ask user for cleanup preference
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        echo "Choose cleanup method:"
        echo "1. Full cleanup (delete entire resource group) - Recommended"
        echo "2. Partial cleanup (delete individual resources, keep resource group)"
        echo ""
        read -p "Enter your choice (1 or 2): " cleanup_choice
        
        case $cleanup_choice in
            1)
                handle_full_cleanup
                ;;
            2)
                handle_partial_cleanup
                ;;
            *)
                error "Invalid choice. Please run the script again and choose 1 or 2."
                exit 1
                ;;
        esac
    else
        log "[DRY-RUN] Would perform cleanup based on user choice"
    fi
    
    verify_deletion
    success "Cleanup completed successfully!"
    display_summary
}

# Handle script interruption
cleanup_on_error() {
    error "Cleanup interrupted. Some resources may still exist."
    exit 1
}

# Set up signal handlers
trap cleanup_on_error INT TERM

# Run main function
main "$@"