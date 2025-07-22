#!/bin/bash

# Azure Document Verification System Cleanup Script
# This script removes all resources created by the deployment script
# to avoid ongoing charges for Azure services

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/cleanup.log"
readonly VARS_FILE="${SCRIPT_DIR}/deployment-vars.env"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Cleanup failed. Check $LOG_FILE for details."
    exit 1
}

# Confirmation prompt
confirm_action() {
    local message="$1"
    local default_response="${2:-n}"
    
    while true; do
        if [[ "$default_response" == "y" ]]; then
            read -p "$message (Y/n): " response
            response=${response:-y}
        else
            read -p "$message (y/N): " response
            response=${response:-n}
        fi
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Display script header
display_header() {
    echo ""
    echo "================================================================"
    echo "Azure Document Verification System Cleanup"
    echo "================================================================"
    echo "This script will remove all resources created by the deployment:"
    echo "- Azure Document Intelligence (Form Recognizer)"
    echo "- Azure Computer Vision"
    echo "- Azure Functions App"
    echo "- Azure Storage Account"
    echo "- Azure Cosmos DB"
    echo "- Azure Logic Apps"
    echo "- Azure API Management"
    echo "- Resource Group (if empty after cleanup)"
    echo "================================================================"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if deployment variables file exists
    if [[ ! -f "$VARS_FILE" ]]; then
        log "WARN" "Deployment variables file not found: $VARS_FILE"
        log "WARN" "You may need to specify resource names manually"
        return 1
    fi
    
    log "INFO" "Prerequisites check completed successfully."
    return 0
}

# Load deployment variables
load_variables() {
    log "INFO" "Loading deployment variables..."
    
    if [[ -f "$VARS_FILE" ]]; then
        # Source the variables file
        source "$VARS_FILE"
        
        log "INFO" "Loaded variables from: $VARS_FILE"
        log "INFO" "  Resource Group: $RESOURCE_GROUP"
        log "INFO" "  Location: $LOCATION"
        log "INFO" "  Random Suffix: $RANDOM_SUFFIX"
    else
        log "WARN" "Variables file not found. Using interactive mode."
        
        # Prompt for resource group
        read -p "Enter the resource group name: " RESOURCE_GROUP
        
        if [[ -z "$RESOURCE_GROUP" ]]; then
            error_exit "Resource group name is required"
        fi
        
        # Check if resource group exists
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            error_exit "Resource group '$RESOURCE_GROUP' does not exist"
        fi
        
        log "INFO" "Using resource group: $RESOURCE_GROUP"
    fi
}

# List resources to be deleted
list_resources() {
    log "INFO" "Listing resources to be deleted..."
    
    local resources
    resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output table 2>/dev/null)
    
    if [[ -z "$resources" ]]; then
        log "WARN" "No resources found in resource group: $RESOURCE_GROUP"
        return 1
    fi
    
    echo ""
    echo "Resources to be deleted:"
    echo "$resources"
    echo ""
    
    return 0
}

# Delete API Management service
delete_api_management() {
    if [[ -n "$APIM_NAME" ]]; then
        log "INFO" "Deleting API Management service: $APIM_NAME"
        
        if az apim show --name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az apim delete \
                --name "$APIM_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --no-wait \
                || log "WARN" "Failed to delete API Management service: $APIM_NAME"
            
            log "INFO" "API Management service deletion initiated (background)"
        else
            log "WARN" "API Management service not found: $APIM_NAME"
        fi
    else
        log "INFO" "Searching for API Management services..."
        
        local apim_services
        apim_services=$(az apim list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
        
        if [[ -n "$apim_services" ]]; then
            for service in $apim_services; do
                log "INFO" "Deleting API Management service: $service"
                az apim delete \
                    --name "$service" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes \
                    --no-wait \
                    || log "WARN" "Failed to delete API Management service: $service"
            done
        fi
    fi
}

# Delete Logic App
delete_logic_app() {
    if [[ -n "$LOGIC_APP_NAME" ]]; then
        log "INFO" "Deleting Logic App: $LOGIC_APP_NAME"
        
        if az logic workflow show --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az logic workflow delete \
                --name "$LOGIC_APP_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                || log "WARN" "Failed to delete Logic App: $LOGIC_APP_NAME"
            
            log "INFO" "Logic App deleted successfully: $LOGIC_APP_NAME"
        else
            log "WARN" "Logic App not found: $LOGIC_APP_NAME"
        fi
    else
        log "INFO" "Searching for Logic Apps..."
        
        local logic_apps
        logic_apps=$(az logic workflow list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
        
        if [[ -n "$logic_apps" ]]; then
            for app in $logic_apps; do
                log "INFO" "Deleting Logic App: $app"
                az logic workflow delete \
                    --name "$app" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes \
                    || log "WARN" "Failed to delete Logic App: $app"
            done
        fi
    fi
}

# Delete Function App
delete_function_app() {
    if [[ -n "$FUNCTION_APP_NAME" ]]; then
        log "INFO" "Deleting Function App: $FUNCTION_APP_NAME"
        
        if az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az functionapp delete \
                --name "$FUNCTION_APP_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                || log "WARN" "Failed to delete Function App: $FUNCTION_APP_NAME"
            
            log "INFO" "Function App deleted successfully: $FUNCTION_APP_NAME"
        else
            log "WARN" "Function App not found: $FUNCTION_APP_NAME"
        fi
    else
        log "INFO" "Searching for Function Apps..."
        
        local function_apps
        function_apps=$(az functionapp list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
        
        if [[ -n "$function_apps" ]]; then
            for app in $function_apps; do
                log "INFO" "Deleting Function App: $app"
                az functionapp delete \
                    --name "$app" \
                    --resource-group "$RESOURCE_GROUP" \
                    || log "WARN" "Failed to delete Function App: $app"
            done
        fi
    fi
}

# Delete Cosmos DB
delete_cosmos_db() {
    if [[ -n "$COSMOS_ACCOUNT_NAME" ]]; then
        log "INFO" "Deleting Cosmos DB account: $COSMOS_ACCOUNT_NAME"
        
        if az cosmosdb show --name "$COSMOS_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az cosmosdb delete \
                --name "$COSMOS_ACCOUNT_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                || log "WARN" "Failed to delete Cosmos DB account: $COSMOS_ACCOUNT_NAME"
            
            log "INFO" "Cosmos DB account deleted successfully: $COSMOS_ACCOUNT_NAME"
        else
            log "WARN" "Cosmos DB account not found: $COSMOS_ACCOUNT_NAME"
        fi
    else
        log "INFO" "Searching for Cosmos DB accounts..."
        
        local cosmos_accounts
        cosmos_accounts=$(az cosmosdb list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
        
        if [[ -n "$cosmos_accounts" ]]; then
            for account in $cosmos_accounts; do
                log "INFO" "Deleting Cosmos DB account: $account"
                az cosmosdb delete \
                    --name "$account" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes \
                    || log "WARN" "Failed to delete Cosmos DB account: $account"
            done
        fi
    fi
}

# Delete AI Services
delete_ai_services() {
    # Delete Document Intelligence service
    if [[ -n "$DOC_INTELLIGENCE_NAME" ]]; then
        log "INFO" "Deleting Document Intelligence service: $DOC_INTELLIGENCE_NAME"
        
        if az cognitiveservices account show --name "$DOC_INTELLIGENCE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az cognitiveservices account delete \
                --name "$DOC_INTELLIGENCE_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                || log "WARN" "Failed to delete Document Intelligence service: $DOC_INTELLIGENCE_NAME"
            
            log "INFO" "Document Intelligence service deleted successfully: $DOC_INTELLIGENCE_NAME"
        else
            log "WARN" "Document Intelligence service not found: $DOC_INTELLIGENCE_NAME"
        fi
    fi
    
    # Delete Computer Vision service
    if [[ -n "$VISION_NAME" ]]; then
        log "INFO" "Deleting Computer Vision service: $VISION_NAME"
        
        if az cognitiveservices account show --name "$VISION_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az cognitiveservices account delete \
                --name "$VISION_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                || log "WARN" "Failed to delete Computer Vision service: $VISION_NAME"
            
            log "INFO" "Computer Vision service deleted successfully: $VISION_NAME"
        else
            log "WARN" "Computer Vision service not found: $VISION_NAME"
        fi
    fi
    
    # Search for any remaining Cognitive Services
    if [[ -z "$DOC_INTELLIGENCE_NAME" ]] || [[ -z "$VISION_NAME" ]]; then
        log "INFO" "Searching for Cognitive Services..."
        
        local cognitive_services
        cognitive_services=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
        
        if [[ -n "$cognitive_services" ]]; then
            for service in $cognitive_services; do
                log "INFO" "Deleting Cognitive Service: $service"
                az cognitiveservices account delete \
                    --name "$service" \
                    --resource-group "$RESOURCE_GROUP" \
                    || log "WARN" "Failed to delete Cognitive Service: $service"
            done
        fi
    fi
}

# Delete Storage Account
delete_storage_account() {
    if [[ -n "$STORAGE_ACCOUNT" ]]; then
        log "INFO" "Deleting Storage Account: $STORAGE_ACCOUNT"
        
        if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az storage account delete \
                --name "$STORAGE_ACCOUNT" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                || log "WARN" "Failed to delete Storage Account: $STORAGE_ACCOUNT"
            
            log "INFO" "Storage Account deleted successfully: $STORAGE_ACCOUNT"
        else
            log "WARN" "Storage Account not found: $STORAGE_ACCOUNT"
        fi
    else
        log "INFO" "Searching for Storage Accounts..."
        
        local storage_accounts
        storage_accounts=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
        
        if [[ -n "$storage_accounts" ]]; then
            for account in $storage_accounts; do
                log "INFO" "Deleting Storage Account: $account"
                az storage account delete \
                    --name "$account" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes \
                    || log "WARN" "Failed to delete Storage Account: $account"
            done
        fi
    fi
}

# Delete remaining resources
delete_remaining_resources() {
    log "INFO" "Checking for remaining resources..."
    
    local remaining_resources
    remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output tsv 2>/dev/null)
    
    if [[ -n "$remaining_resources" ]]; then
        log "WARN" "Found remaining resources:"
        echo "$remaining_resources"
        
        if confirm_action "Delete all remaining resources?"; then
            log "INFO" "Deleting all remaining resources..."
            
            # Get resource IDs and delete them
            local resource_ids
            resource_ids=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].id" --output tsv 2>/dev/null)
            
            if [[ -n "$resource_ids" ]]; then
                for resource_id in $resource_ids; do
                    log "INFO" "Deleting resource: $resource_id"
                    az resource delete --ids "$resource_id" --no-wait \
                        || log "WARN" "Failed to delete resource: $resource_id"
                done
            fi
        fi
    else
        log "INFO" "No remaining resources found"
    fi
}

# Delete Resource Group
delete_resource_group() {
    if [[ -n "$RESOURCE_GROUP" ]]; then
        log "INFO" "Checking if resource group is empty..."
        
        local resource_count
        resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null)
        
        if [[ "$resource_count" -eq 0 ]]; then
            log "INFO" "Resource group is empty"
            
            if confirm_action "Delete the resource group '$RESOURCE_GROUP'?"; then
                log "INFO" "Deleting resource group: $RESOURCE_GROUP"
                
                az group delete \
                    --name "$RESOURCE_GROUP" \
                    --yes \
                    --no-wait \
                    || log "WARN" "Failed to delete resource group: $RESOURCE_GROUP"
                
                log "INFO" "Resource group deletion initiated: $RESOURCE_GROUP"
            fi
        else
            log "WARN" "Resource group is not empty (contains $resource_count resources)"
            log "WARN" "Please remove remaining resources before deleting the resource group"
        fi
    fi
}

# Clean up deployment files
cleanup_deployment_files() {
    log "INFO" "Cleaning up deployment files..."
    
    if [[ -f "$VARS_FILE" ]]; then
        if confirm_action "Delete deployment variables file ($VARS_FILE)?"; then
            rm -f "$VARS_FILE"
            log "INFO" "Deployment variables file deleted: $VARS_FILE"
        fi
    fi
    
    # Remove deployment log if it exists
    local deployment_log="${SCRIPT_DIR}/deployment.log"
    if [[ -f "$deployment_log" ]]; then
        if confirm_action "Delete deployment log file ($deployment_log)?"; then
            rm -f "$deployment_log"
            log "INFO" "Deployment log file deleted: $deployment_log"
        fi
    fi
}

# Display cleanup summary
display_summary() {
    log "INFO" "Cleanup completed!"
    echo ""
    echo "================================================================"
    echo "Azure Document Verification System - Cleanup Summary"
    echo "================================================================"
    echo ""
    echo "The following resources have been deleted:"
    echo "- API Management Service"
    echo "- Logic App"
    echo "- Function App"
    echo "- Cosmos DB Account"
    echo "- Document Intelligence Service"
    echo "- Computer Vision Service"
    echo "- Storage Account"
    echo "- Resource Group (if empty)"
    echo ""
    echo "Note: Some resources may still be in the process of deletion."
    echo "This is normal for services like API Management which can take"
    echo "several minutes to fully delete."
    echo ""
    echo "Cleanup log: $LOG_FILE"
    echo "================================================================"
}

# Main cleanup function
main() {
    # Initialize log file
    echo "Cleanup started at $(date)" > "$LOG_FILE"
    
    display_header
    
    # Check if force mode
    local force_mode=false
    if [[ "${1:-}" == "--force" ]]; then
        force_mode=true
        log "INFO" "Force mode enabled - skipping confirmations"
    fi
    
    # Check if dry run
    if [[ "${1:-}" == "--dry-run" ]]; then
        log "INFO" "Dry run mode - no resources will be deleted"
        check_prerequisites
        load_variables
        list_resources
        return 0
    fi
    
    # Confirm cleanup unless in force mode
    if [[ "$force_mode" == false ]]; then
        if ! confirm_action "Are you sure you want to delete all Azure Document Verification resources?"; then
            log "INFO" "Cleanup cancelled by user"
            return 0
        fi
    fi
    
    # Execute cleanup steps
    check_prerequisites
    load_variables
    
    if [[ "$force_mode" == false ]]; then
        list_resources
        
        if ! confirm_action "Proceed with deletion of these resources?"; then
            log "INFO" "Cleanup cancelled by user"
            return 0
        fi
    fi
    
    # Delete resources in reverse order of creation
    delete_api_management
    delete_logic_app
    delete_function_app
    delete_cosmos_db
    delete_ai_services
    delete_storage_account
    delete_remaining_resources
    delete_resource_group
    
    if [[ "$force_mode" == false ]]; then
        cleanup_deployment_files
    fi
    
    display_summary
    
    log "INFO" "Cleanup completed successfully at $(date)"
}

# Run main function with all arguments
main "$@"