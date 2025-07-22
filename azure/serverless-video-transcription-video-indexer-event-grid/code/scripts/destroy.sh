#!/bin/bash

# Azure Serverless Video Transcription - Cleanup Script
# Recipe: Serverless Video Transcription with Video Indexer and Event Grid
# This script removes all resources created for the serverless video transcription pipeline

set -euo pipefail

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

# Error handler
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Some resources may still exist."
    exit 1
}

# Display banner
display_banner() {
    echo -e "${RED}"
    echo "=================================================="
    echo "  Azure Serverless Video Transcription Pipeline"
    echo "  Cleanup Script v1.0"
    echo "=================================================="
    echo -e "${NC}"
    echo -e "${YELLOW}WARNING: This will delete ALL resources created by the deployment script!${NC}"
    echo ""
}

# Load deployment variables
load_deployment_variables() {
    log_info "Loading deployment variables..."
    
    if [[ ! -f ".deployment_vars" ]]; then
        log_error ".deployment_vars file not found"
        echo "This file is created by the deploy.sh script and contains resource names."
        echo ""
        echo "Manual cleanup option:"
        echo "1. Identify your resource group (format: rg-video-indexer-XXXXXX)"
        echo "2. Run: az group delete --name <resource-group-name> --yes"
        echo ""
        error_exit "Cannot proceed without deployment variables"
    fi
    
    # Source the variables file
    source .deployment_vars
    
    # Verify required variables are set
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        error_exit "RESOURCE_GROUP variable not found in .deployment_vars"
    fi
    
    log_success "Deployment variables loaded successfully"
    log_info "Resource Group: ${RESOURCE_GROUP}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI and try again."
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' and try again."
    fi
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} does not exist or has already been deleted"
        return 1
    fi
    
    log_success "Prerequisites check completed"
    return 0
}

# Confirmation prompt
confirm_deletion() {
    echo ""
    log_warning "You are about to delete the following resources:"
    echo "• Resource Group: ${RESOURCE_GROUP}"
    echo "• Storage Account: ${STORAGE_ACCOUNT:-unknown}"
    echo "• Function App: ${FUNCTION_APP:-unknown}"
    echo "• Cosmos DB Account: ${COSMOS_ACCOUNT:-unknown}"
    echo "• Event Grid Topic: ${EVENT_GRID_TOPIC:-unknown}"
    echo ""
    log_warning "This action is IRREVERSIBLE. All data will be lost!"
    echo ""
    
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        log_warning "Force delete mode enabled. Skipping confirmation."
        return 0
    fi
    
    echo -n "Type 'DELETE' to confirm resource deletion: "
    read -r confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "Deletion confirmed. Proceeding with cleanup..."
}

# Remove Event Grid subscriptions
remove_event_subscriptions() {
    log_info "Removing Event Grid subscriptions..."
    
    # Check if storage account exists
    if az storage account show --name "${STORAGE_ACCOUNT:-}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        # Remove blob storage event subscription
        if az eventgrid event-subscription show \
            --name video-upload-subscription \
            --source-resource-id $(az storage account show \
                --name "${STORAGE_ACCOUNT}" \
                --resource-group "${RESOURCE_GROUP}" \
                --query id --output tsv) &> /dev/null; then
            
            az eventgrid event-subscription delete \
                --name video-upload-subscription \
                --source-resource-id $(az storage account show \
                    --name "${STORAGE_ACCOUNT}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --query id --output tsv) \
                --output none || log_warning "Failed to delete blob event subscription"
            
            log_success "Blob storage event subscription removed"
        else
            log_warning "Blob storage event subscription not found"
        fi
    else
        log_warning "Storage account not found, skipping blob subscription cleanup"
    fi
    
    # Remove Event Grid topic subscriptions
    if az eventgrid topic show --name "${EVENT_GRID_TOPIC:-}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        # List and remove all subscriptions for the topic
        local subscriptions=$(az eventgrid event-subscription list \
            --source-resource-id $(az eventgrid topic show \
                --name "${EVENT_GRID_TOPIC}" \
                --resource-group "${RESOURCE_GROUP}" \
                --query id --output tsv) \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$subscriptions" ]]; then
            while IFS= read -r subscription; do
                if [[ -n "$subscription" ]]; then
                    az eventgrid event-subscription delete \
                        --name "$subscription" \
                        --source-resource-id $(az eventgrid topic show \
                            --name "${EVENT_GRID_TOPIC}" \
                            --resource-group "${RESOURCE_GROUP}" \
                            --query id --output tsv) \
                        --output none || log_warning "Failed to delete subscription: $subscription"
                    
                    log_success "Event Grid subscription removed: $subscription"
                fi
            done <<< "$subscriptions"
        else
            log_warning "No Event Grid subscriptions found"
        fi
    else
        log_warning "Event Grid topic not found"
    fi
}

# Remove individual resources (if resource group deletion fails)
remove_individual_resources() {
    log_info "Attempting to remove individual resources..."
    
    # Remove Function App
    if [[ -n "${FUNCTION_APP:-}" ]] && az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Removing Function App: ${FUNCTION_APP}"
        az functionapp delete \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none || log_warning "Failed to delete Function App"
        log_success "Function App removed"
    fi
    
    # Remove Event Grid Topic
    if [[ -n "${EVENT_GRID_TOPIC:-}" ]] && az eventgrid topic show --name "${EVENT_GRID_TOPIC}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Removing Event Grid Topic: ${EVENT_GRID_TOPIC}"
        az eventgrid topic delete \
            --name "${EVENT_GRID_TOPIC}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none || log_warning "Failed to delete Event Grid Topic"
        log_success "Event Grid Topic removed"
    fi
    
    # Remove Cosmos DB Account
    if [[ -n "${COSMOS_ACCOUNT:-}" ]] && az cosmosdb show --name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Removing Cosmos DB Account: ${COSMOS_ACCOUNT}"
        az cosmosdb delete \
            --name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --output none || log_warning "Failed to delete Cosmos DB Account"
        log_success "Cosmos DB Account removed"
    fi
    
    # Remove Storage Account
    if [[ -n "${STORAGE_ACCOUNT:-}" ]] && az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Removing Storage Account: ${STORAGE_ACCOUNT}"
        az storage account delete \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --output none || log_warning "Failed to delete Storage Account"
        log_success "Storage Account removed"
    fi
}

# Remove resource group (preferred method)
remove_resource_group() {
    log_info "Removing resource group: ${RESOURCE_GROUP}"
    
    # First try to remove event subscriptions
    remove_event_subscriptions
    
    # Attempt resource group deletion
    if az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        --output none; then
        
        log_success "Resource group deletion initiated"
        log_info "Waiting for resource group deletion to complete..."
        
        # Wait for deletion with timeout
        local timeout=1800  # 30 minutes
        local elapsed=0
        local interval=30
        
        while az group show --name "${RESOURCE_GROUP}" &> /dev/null; do
            if [ $elapsed -ge $timeout ]; then
                log_warning "Resource group deletion timeout reached"
                log_info "Deletion may still be in progress. Check Azure portal for status."
                return 1
            fi
            
            echo -n "."
            sleep $interval
            elapsed=$((elapsed + interval))
        done
        
        echo ""
        log_success "Resource group deleted successfully"
        return 0
    else
        log_warning "Resource group deletion failed, attempting individual resource cleanup"
        remove_individual_resources
        return 1
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group still exists"
        
        # List remaining resources
        local remaining_resources=$(az resource list \
            --resource-group "${RESOURCE_GROUP}" \
            --query "[].{Name:name, Type:type}" \
            --output table 2>/dev/null || echo "Unable to list resources")
        
        if [[ "$remaining_resources" != "Unable to list resources" ]] && [[ -n "$remaining_resources" ]]; then
            log_warning "Remaining resources found:"
            echo "$remaining_resources"
            echo ""
            log_warning "Manual cleanup may be required. Check the Azure portal."
        fi
        
        return 1
    else
        log_success "Resource group successfully deleted"
        return 0
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment variables file
    if [[ -f ".deployment_vars" ]]; then
        rm -f .deployment_vars
        log_success "Deployment variables file removed"
    fi
    
    # Remove any other temporary files created during deployment
    if [[ -f "video-functions.zip" ]]; then
        rm -f video-functions.zip
        log_success "Function deployment package removed"
    fi
    
    # Clean up any function directories if they exist
    if [[ -d "video-functions" ]]; then
        log_warning "Function project directory found: video-functions"
        echo -n "Remove local function project directory? (y/N): "
        read -r remove_functions
        if [[ "$remove_functions" =~ ^[Yy]$ ]]; then
            rm -rf video-functions
            log_success "Function project directory removed"
        fi
    fi
}

# Display final summary
display_summary() {
    echo ""
    log_success "Cleanup completed!"
    echo ""
    echo -e "${BLUE}=== Cleanup Summary ===${NC}"
    echo "• Resource group deletion: ${RESOURCE_GROUP}"
    echo "• Local files cleaned up"
    echo ""
    echo -e "${BLUE}=== Manual Steps Required ===${NC}"
    echo "1. Check Azure portal to confirm all resources are deleted"
    echo "2. Review Azure Video Indexer account (if no longer needed):"
    echo "   - Navigate to https://www.videoindexer.ai/"
    echo "   - Remove the account if it was created only for testing"
    echo "3. Check your Azure subscription for any unexpected charges"
    echo ""
    if [[ "${VIDEO_INDEXER_CLEANUP:-}" == "prompt" ]]; then
        echo -e "${YELLOW}Note:${NC} Video Indexer account cleanup was not automated"
        echo "Please manually review your Video Indexer account settings"
    fi
}

# Handle Video Indexer account cleanup prompt
prompt_video_indexer_cleanup() {
    echo ""
    log_info "Video Indexer Account Cleanup"
    echo "The Azure Video Indexer account is not automatically deleted by this script."
    echo ""
    echo "If you created a Video Indexer account specifically for this demo:"
    echo "1. Navigate to https://www.videoindexer.ai/"
    echo "2. Sign in with your Azure account"
    echo "3. Delete the account if no longer needed"
    echo ""
    echo "Video Indexer accounts have a free tier with 10 hours per month."
    echo "Review your account usage and delete if appropriate."
    echo ""
    export VIDEO_INDEXER_CLEANUP="prompt"
}

# Main cleanup function
main() {
    display_banner
    
    # Check for force delete mode
    if [[ "${1:-}" == "--force" ]]; then
        log_warning "Force delete mode enabled"
        export FORCE_DELETE="true"
    fi
    
    # Check for dry run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log_info "Running in dry-run mode"
        if load_deployment_variables; then
            log_info "Would delete resource group: ${RESOURCE_GROUP}"
            log_info "Would remove local files: .deployment_vars"
            log_info "Would prompt for Video Indexer cleanup"
        fi
        log_success "Dry run completed"
        return
    fi
    
    # Load deployment variables
    if ! load_deployment_variables; then
        exit 1
    fi
    
    # Check prerequisites
    if ! check_prerequisites; then
        log_info "Resource group already deleted or does not exist"
        cleanup_local_files
        log_success "Cleanup completed (resources already removed)"
        exit 0
    fi
    
    # Confirm deletion
    confirm_deletion
    
    # Execute cleanup
    if remove_resource_group; then
        log_success "Resource group cleanup completed successfully"
    else
        log_warning "Resource group cleanup completed with warnings"
    fi
    
    # Verify cleanup
    verify_cleanup
    
    # Clean up local files
    cleanup_local_files
    
    # Prompt for Video Indexer cleanup
    prompt_video_indexer_cleanup
    
    # Display summary
    display_summary
}

# Run main function with all arguments
main "$@"