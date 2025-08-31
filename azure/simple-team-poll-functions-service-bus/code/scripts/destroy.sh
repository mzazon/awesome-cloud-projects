#!/bin/bash

set -euo pipefail

# Simple Team Poll System with Functions and Service Bus - Cleanup Script
# This script safely removes all resources created for the serverless polling system

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

# Error handling (continue on errors during cleanup)
set +e

# Configuration
SKIP_CONFIRMATION=false
FORCE_DELETE=false
DELETE_RESOURCE_GROUP=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-confirmation|-y)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --keep-resource-group)
            DELETE_RESOURCE_GROUP=false
            shift
            ;;
        --help|-h)
            echo "Azure Simple Team Poll System Cleanup Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -y, --skip-confirmation    Skip confirmation prompts"
            echo "  --force                    Force deletion even if resources are not found"
            echo "  --keep-resource-group      Keep the resource group (delete individual resources only)"
            echo "  -h, --help                 Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  RESOURCE_GROUP            Resource group name (required)"
            echo "  SERVICE_BUS_NAMESPACE     Service Bus namespace name"
            echo "  FUNCTION_APP_NAME         Function App name"
            echo "  STORAGE_ACCOUNT           Storage account name"
            echo ""
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Try to load from deployment info file first
    if [[ -f "./azure-poll-deployment-info.txt" ]]; then
        log_info "Found deployment info file, extracting resource names..."
        
        # Extract resource names from deployment info file
        if [[ -z "${RESOURCE_GROUP:-}" ]]; then
            RESOURCE_GROUP=$(grep "Resource Group:" "./azure-poll-deployment-info.txt" | cut -d' ' -f3)
        fi
        
        if [[ -z "${SERVICE_BUS_NAMESPACE:-}" ]]; then
            SERVICE_BUS_NAMESPACE=$(grep "Service Bus Namespace:" "./azure-poll-deployment-info.txt" | cut -d' ' -f4)
        fi
        
        if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
            FUNCTION_APP_NAME=$(grep "Function App Name:" "./azure-poll-deployment-info.txt" | cut -d' ' -f4)
        fi
        
        if [[ -z "${STORAGE_ACCOUNT:-}" ]]; then
            STORAGE_ACCOUNT=$(grep "Storage Account:" "./azure-poll-deployment-info.txt" | cut -d' ' -f3)
        fi
        
        log_success "Deployment information loaded from file"
    fi
    
    # Check if we have the minimum required information
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_error "RESOURCE_GROUP environment variable is not set and could not be loaded from deployment info."
        log_error "Please set the RESOURCE_GROUP environment variable or ensure the deployment info file exists."
        log_error ""
        log_error "Example: export RESOURCE_GROUP=\"rg-recipe-abc123\""
        exit 1
    fi
    
    log_info "Cleanup configuration:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Service Bus Namespace: ${SERVICE_BUS_NAMESPACE:-'(will auto-detect)'}"
    log_info "  Function App: ${FUNCTION_APP_NAME:-'(will auto-detect)'}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT:-'(will auto-detect)'}"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        log_warning "Skipping confirmation prompt (--skip-confirmation flag used)"
        return 0
    fi
    
    echo ""
    log_warning "⚠️  DANGER ZONE ⚠️"
    log_warning "This will permanently delete the following Azure resources:"
    log_warning "  • Resource Group: $RESOURCE_GROUP"
    log_warning "  • All contained resources (Function App, Service Bus, Storage Account)"
    log_warning "  • All data stored in these resources"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource cleanup..."
}

# Function to check if resource group exists
resource_group_exists() {
    az group show --name "$1" &> /dev/null
}

# Function to auto-detect resources in the resource group
auto_detect_resources() {
    log_info "Auto-detecting resources in resource group: $RESOURCE_GROUP"
    
    if ! resource_group_exists "$RESOURCE_GROUP"; then
        log_warning "Resource group $RESOURCE_GROUP does not exist"
        return 1
    fi
    
    # Auto-detect Service Bus namespace if not provided
    if [[ -z "${SERVICE_BUS_NAMESPACE:-}" ]]; then
        SERVICE_BUS_NAMESPACE=$(az servicebus namespace list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[?contains(name, 'sb-poll')].name" \
            --output tsv 2>/dev/null | head -1)
        
        if [[ -n "$SERVICE_BUS_NAMESPACE" ]]; then
            log_info "Auto-detected Service Bus namespace: $SERVICE_BUS_NAMESPACE"
        fi
    fi
    
    # Auto-detect Function App if not provided
    if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
        FUNCTION_APP_NAME=$(az functionapp list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[?contains(name, 'func-poll')].name" \
            --output tsv 2>/dev/null | head -1)
        
        if [[ -n "$FUNCTION_APP_NAME" ]]; then
            log_info "Auto-detected Function App: $FUNCTION_APP_NAME"
        fi
    fi
    
    # Auto-detect Storage Account if not provided
    if [[ -z "${STORAGE_ACCOUNT:-}" ]]; then
        STORAGE_ACCOUNT=$(az storage account list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[?contains(name, 'sapoll')].name" \
            --output tsv 2>/dev/null | head -1)
        
        if [[ -n "$STORAGE_ACCOUNT" ]]; then
            log_info "Auto-detected Storage Account: $STORAGE_ACCOUNT"
        fi
    fi
    
    log_success "Resource auto-detection completed"
}

# Function to delete individual resources (safer approach)
delete_individual_resources() {
    log_info "Deleting individual resources..."
    
    # Delete Function App first (to stop processing)
    if [[ -n "${FUNCTION_APP_NAME:-}" ]]; then
        log_info "Deleting Function App: $FUNCTION_APP_NAME"
        if az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az functionapp delete \
                --name "$FUNCTION_APP_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes &> /dev/null
            log_success "Function App deleted: $FUNCTION_APP_NAME"
        else
            log_warning "Function App not found: $FUNCTION_APP_NAME"
        fi
    fi
    
    # Delete Service Bus namespace and queues
    if [[ -n "${SERVICE_BUS_NAMESPACE:-}" ]]; then
        log_info "Deleting Service Bus namespace: $SERVICE_BUS_NAMESPACE"
        if az servicebus namespace show --name "$SERVICE_BUS_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            # Delete the queue first
            az servicebus queue delete \
                --name "votes" \
                --namespace-name "$SERVICE_BUS_NAMESPACE" \
                --resource-group "$RESOURCE_GROUP" &> /dev/null || true
            
            # Delete the namespace
            az servicebus namespace delete \
                --name "$SERVICE_BUS_NAMESPACE" \
                --resource-group "$RESOURCE_GROUP" &> /dev/null
            log_success "Service Bus namespace deleted: $SERVICE_BUS_NAMESPACE"
        else
            log_warning "Service Bus namespace not found: $SERVICE_BUS_NAMESPACE"
        fi
    fi
    
    # Delete Storage Account
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        log_info "Deleting Storage Account: $STORAGE_ACCOUNT"
        if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az storage account delete \
                --name "$STORAGE_ACCOUNT" \
                --resource-group "$RESOURCE_GROUP" \
                --yes &> /dev/null
            log_success "Storage Account deleted: $STORAGE_ACCOUNT"
        else
            log_warning "Storage Account not found: $STORAGE_ACCOUNT"
        fi
    fi
}

# Function to delete the entire resource group
delete_resource_group() {
    log_info "Deleting resource group: $RESOURCE_GROUP"
    
    if ! resource_group_exists "$RESOURCE_GROUP"; then
        log_warning "Resource group $RESOURCE_GROUP does not exist"
        return 0
    fi
    
    # List resources in the group before deletion
    log_info "Resources to be deleted:"
    az resource list --resource-group "$RESOURCE_GROUP" --output table 2>/dev/null || log_warning "Could not list resources"
    
    # Delete the resource group and all its resources
    log_info "Initiating resource group deletion (this may take several minutes)..."
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    log_success "Resource group deletion initiated: $RESOURCE_GROUP"
    log_info "Note: Deletion continues in the background and may take several minutes to complete"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    if resource_group_exists "$RESOURCE_GROUP"; then
        if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
            log_warning "Resource group still exists (deletion may be in progress)"
            
            # Check if resources still exist
            resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "unknown")
            if [[ "$resource_count" == "0" ]]; then
                log_success "All resources have been removed from the resource group"
            else
                log_warning "Some resources may still exist (count: $resource_count)"
            fi
        else
            log_info "Resource group preserved as requested (--keep-resource-group)"
        fi
    else
        log_success "Resource group has been completely removed"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment info file
    if [[ -f "./azure-poll-deployment-info.txt" ]]; then
        rm -f "./azure-poll-deployment-info.txt"
        log_success "Removed deployment info file"
    fi
    
    # Clean up any temporary files that might exist
    rm -f poll-functions.zip 2>/dev/null || true
    rm -rf /tmp/poll-functions* 2>/dev/null || true
    
    log_success "Local cleanup completed"
}

# Function to wait for resource group deletion (optional)
wait_for_deletion() {
    if [[ "$DELETE_RESOURCE_GROUP" != "true" ]]; then
        return 0
    fi
    
    read -p "Do you want to wait for the resource group deletion to complete? (y/N): " wait_choice
    
    if [[ "$wait_choice" =~ ^[Yy]$ ]]; then
        log_info "Waiting for resource group deletion to complete..."
        
        local max_wait=1800  # 30 minutes
        local wait_interval=30
        local elapsed=0
        
        while resource_group_exists "$RESOURCE_GROUP" && [[ $elapsed -lt $max_wait ]]; do
            log_info "Still waiting... (${elapsed}s elapsed)"
            sleep $wait_interval
            elapsed=$((elapsed + wait_interval))
        done
        
        if resource_group_exists "$RESOURCE_GROUP"; then
            log_warning "Resource group deletion is taking longer than expected"
            log_warning "You can check the status in the Azure portal or with: az group show --name $RESOURCE_GROUP"
        else
            log_success "Resource group deletion completed!"
        fi
    fi
}

# Main execution
main() {
    log_info "Starting Azure Simple Team Poll System cleanup..."
    log_info "=============================================="
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment information
    load_deployment_info
    
    # Auto-detect resources if needed
    auto_detect_resources
    
    # Confirm deletion
    confirm_deletion
    
    # Choose cleanup method
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        log_info "Using resource group deletion method (faster, recommended)"
        delete_resource_group
    else
        log_info "Using individual resource deletion method"
        delete_individual_resources
    fi
    
    # Wait for completion if requested
    wait_for_deletion
    
    # Verify cleanup
    verify_cleanup
    
    # Clean up local files
    cleanup_local_files
    
    log_success "=============================================="
    log_success "Cleanup completed!"
    log_info ""
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        log_info "All Azure resources have been removed or are being removed."
        log_info "You can verify complete deletion in the Azure portal."
    else
        log_info "Individual resources have been removed."
        log_info "The resource group '$RESOURCE_GROUP' has been preserved."
    fi
    log_info ""
    log_info "Thank you for using the Azure Simple Team Poll System!"
}

# Execute main function
main "$@"