#!/bin/bash

# Smart Model Selection with AI Foundry and Functions - Cleanup Script
# This script removes all resources created by the deployment script

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites met"
}

# Function to load environment variables
load_environment() {
    log_info "Loading deployment variables..."
    
    if [ -f ".deployment_vars" ]; then
        source .deployment_vars
        log_success "Loaded variables from .deployment_vars"
        log_info "  Resource Group: ${RESOURCE_GROUP}"
        log_info "  AI Foundry: ${AI_FOUNDRY_NAME}"
        log_info "  Function App: ${FUNCTION_APP_NAME}"
        log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
        log_info "  Application Insights: ${APP_INSIGHTS_NAME}"
    else
        log_warning ".deployment_vars file not found. Manual resource specification required."
        echo ""
        echo "Please provide the resource group name to clean up:"
        read -p "Resource Group: " RESOURCE_GROUP
        
        if [ -z "$RESOURCE_GROUP" ]; then
            log_error "Resource group name is required for cleanup"
            exit 1
        fi
        
        # Try to discover resources in the group
        discover_resources
    fi
}

# Function to discover resources if deployment vars are not available
discover_resources() {
    log_info "Discovering resources in resource group: ${RESOURCE_GROUP}"
    
    # Check if resource group exists
    if ! az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        log_error "Resource group ${RESOURCE_GROUP} does not exist"
        exit 1
    fi
    
    # Try to find resources by tags or naming patterns
    AI_FOUNDRY_NAME=$(az cognitiveservices account list \
        --resource-group ${RESOURCE_GROUP} \
        --query "[0].name" \
        --output tsv 2>/dev/null || echo "")
    
    FUNCTION_APP_NAME=$(az functionapp list \
        --resource-group ${RESOURCE_GROUP} \
        --query "[0].name" \
        --output tsv 2>/dev/null || echo "")
    
    STORAGE_ACCOUNT_NAME=$(az storage account list \
        --resource-group ${RESOURCE_GROUP} \
        --query "[0].name" \
        --output tsv 2>/dev/null || echo "")
    
    APP_INSIGHTS_NAME=$(az monitor app-insights component list \
        --resource-group ${RESOURCE_GROUP} \
        --query "[0].name" \
        --output tsv 2>/dev/null || echo "")
    
    log_info "Discovered resources:"
    log_info "  AI Foundry: ${AI_FOUNDRY_NAME:-'Not found'}"
    log_info "  Function App: ${FUNCTION_APP_NAME:-'Not found'}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME:-'Not found'}"
    log_info "  Application Insights: ${APP_INSIGHTS_NAME:-'Not found'}"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    log_warning "This will permanently delete the following resources:"
    echo "  - Resource Group: ${RESOURCE_GROUP}"
    echo "  - All resources within the resource group"
    echo ""
    log_warning "This action cannot be undone!"
    echo ""
    
    # Prompt for confirmation
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    log_info "Proceeding with resource cleanup..."
}

# Function to stop Function App
stop_function_app() {
    if [ -n "${FUNCTION_APP_NAME:-}" ]; then
        log_info "Stopping Function App: ${FUNCTION_APP_NAME}"
        
        if az functionapp show --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
            az functionapp stop \
                --name ${FUNCTION_APP_NAME} \
                --resource-group ${RESOURCE_GROUP} \
                --output none 2>/dev/null || true
            
            log_success "Function App stopped"
        else
            log_warning "Function App ${FUNCTION_APP_NAME} not found"
        fi
    fi
}

# Function to delete Function App
delete_function_app() {
    if [ -n "${FUNCTION_APP_NAME:-}" ]; then
        log_info "Deleting Function App: ${FUNCTION_APP_NAME}"
        
        if az functionapp show --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
            az functionapp delete \
                --name ${FUNCTION_APP_NAME} \
                --resource-group ${RESOURCE_GROUP} \
                --output none
            
            # Wait a moment for deletion to propagate
            sleep 10
            log_success "Function App deleted"
        else
            log_warning "Function App ${FUNCTION_APP_NAME} not found"
        fi
    fi
}

# Function to delete AI Services resource
delete_ai_services() {
    if [ -n "${AI_FOUNDRY_NAME:-}" ]; then
        log_info "Deleting AI Services resource: ${AI_FOUNDRY_NAME}"
        
        if az cognitiveservices account show --name ${AI_FOUNDRY_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
            # First delete any deployments
            log_info "Checking for Model Router deployment..."
            if az cognitiveservices account deployment show \
                --name ${AI_FOUNDRY_NAME} \
                --resource-group ${RESOURCE_GROUP} \
                --deployment-name "model-router" &> /dev/null; then
                
                log_info "Deleting Model Router deployment..."
                az cognitiveservices account deployment delete \
                    --name ${AI_FOUNDRY_NAME} \
                    --resource-group ${RESOURCE_GROUP} \
                    --deployment-name "model-router" \
                    --output none
                
                # Wait for deployment deletion
                sleep 15
                log_success "Model Router deployment deleted"
            fi
            
            # Delete the AI services account
            az cognitiveservices account delete \
                --name ${AI_FOUNDRY_NAME} \
                --resource-group ${RESOURCE_GROUP} \
                --output none
            
            log_success "AI Services resource deleted"
        else
            log_warning "AI Services resource ${AI_FOUNDRY_NAME} not found"
        fi
    fi
}

# Function to delete Storage Account
delete_storage_account() {
    if [ -n "${STORAGE_ACCOUNT_NAME:-}" ]; then
        log_info "Deleting Storage Account: ${STORAGE_ACCOUNT_NAME}"
        
        if az storage account show --name ${STORAGE_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
            az storage account delete \
                --name ${STORAGE_ACCOUNT_NAME} \
                --resource-group ${RESOURCE_GROUP} \
                --yes \
                --output none
            
            log_success "Storage Account deleted"
        else
            log_warning "Storage Account ${STORAGE_ACCOUNT_NAME} not found"
        fi
    fi
}

# Function to delete Application Insights
delete_app_insights() {
    if [ -n "${APP_INSIGHTS_NAME:-}" ]; then
        log_info "Deleting Application Insights: ${APP_INSIGHTS_NAME}"
        
        if az monitor app-insights component show --app ${APP_INSIGHTS_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
            az monitor app-insights component delete \
                --app ${APP_INSIGHTS_NAME} \
                --resource-group ${RESOURCE_GROUP} \
                --output none
            
            log_success "Application Insights deleted"
        else
            log_warning "Application Insights ${APP_INSIGHTS_NAME} not found"
        fi
    fi
}

# Function to delete remaining resources in resource group
delete_remaining_resources() {
    log_info "Checking for any remaining resources in resource group..."
    
    # List remaining resources
    REMAINING_RESOURCES=$(az resource list --resource-group ${RESOURCE_GROUP} --query "length([?type != 'Microsoft.Web/serverfarms'])" --output tsv)
    
    if [ "$REMAINING_RESOURCES" -gt 0 ]; then
        log_info "Found ${REMAINING_RESOURCES} remaining resources. Listing them:"
        az resource list --resource-group ${RESOURCE_GROUP} --output table
        
        echo ""
        read -p "Delete these remaining resources? (type 'yes' to confirm): " DELETE_REMAINING
        
        if [ "$DELETE_REMAINING" = "yes" ]; then
            log_info "Deleting remaining resources..."
            
            # Delete all resources in the resource group (except service plans which are deleted automatically)
            az resource list --resource-group ${RESOURCE_GROUP} --query "[?type != 'Microsoft.Web/serverfarms'].id" --output tsv | \
            while read resource_id; do
                if [ -n "$resource_id" ]; then
                    log_info "Deleting resource: $resource_id"
                    az resource delete --ids "$resource_id" --output none 2>/dev/null || true
                fi
            done
            
            log_success "Remaining resources deleted"
        else
            log_warning "Some resources will remain in the resource group"
        fi
    else
        log_info "No additional resources found"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log_info "Deleting Resource Group: ${RESOURCE_GROUP}"
    
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        echo ""
        log_warning "Final confirmation: Delete resource group ${RESOURCE_GROUP}?"
        read -p "Type the resource group name to confirm: " CONFIRM_RG
        
        if [ "$CONFIRM_RG" = "$RESOURCE_GROUP" ]; then
            az group delete \
                --name ${RESOURCE_GROUP} \
                --yes \
                --no-wait \
                --output none
            
            log_success "Resource group deletion initiated"
            log_info "Note: Complete deletion may take several minutes"
        else
            log_warning "Resource group name did not match. Skipping resource group deletion."
            log_info "You can manually delete the resource group later using:"
            log_info "  az group delete --name ${RESOURCE_GROUP} --yes"
        fi
    else
        log_warning "Resource group ${RESOURCE_GROUP} not found"
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    if [ -f ".deployment_vars" ]; then
        rm -f .deployment_vars
        log_success "Removed .deployment_vars file"
    fi
    
    # Remove any temporary function code directories
    if [ -d "smart-model-function" ]; then
        rm -rf smart-model-function
        log_success "Removed temporary function code directory"
    fi
}

# Function to display cleanup summary
display_summary() {
    echo ""
    echo "======================================"
    echo "CLEANUP SUMMARY"
    echo "======================================"
    echo ""
    
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} still exists"
        log_info "Check the Azure portal to monitor deletion progress"
    else
        log_success "Resource group ${RESOURCE_GROUP} has been deleted"
    fi
    
    echo ""
    log_info "Cleanup completed. All local files have been removed."
    echo ""
    
    # Check if there are any remaining resources with similar names
    log_info "Checking for any remaining resources with similar names..."
    
    SIMILAR_RESOURCES=$(az resource list --query "[?contains(name, 'smart-model')].{Name:name, Type:type, ResourceGroup:resourceGroup}" --output table 2>/dev/null || echo "")
    
    if [ -n "$SIMILAR_RESOURCES" ] && [ "$SIMILAR_RESOURCES" != "Name    Type    ResourceGroup" ]; then
        log_warning "Found potentially related resources:"
        echo "$SIMILAR_RESOURCES"
        log_info "Please review these resources manually if needed"
    else
        log_success "No similar resources found"
    fi
}

# Function to handle interruption
cleanup_on_interrupt() {
    echo ""
    log_warning "Cleanup interrupted by user"
    echo ""
    log_info "Partial cleanup may have occurred. You may need to:"
    log_info "1. Re-run this script to complete cleanup"
    log_info "2. Manually check the Azure portal for remaining resources"
    echo ""
    exit 1
}

# Trap interruption signals
trap cleanup_on_interrupt SIGINT SIGTERM

# Main execution flow
main() {
    echo "======================================"
    echo "Smart Model Selection Cleanup"
    echo "======================================"
    echo ""
    
    check_prerequisites
    load_environment
    confirm_deletion
    
    # Delete resources in reverse order of creation
    stop_function_app
    delete_function_app
    delete_ai_services
    delete_storage_account
    delete_app_insights
    delete_remaining_resources
    delete_resource_group
    cleanup_local_files
    display_summary
}

# Run the main function
main "$@"