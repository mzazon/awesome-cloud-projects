#!/bin/bash

#################################################################
# Azure Intelligent Video Content Moderation - Cleanup Script
#################################################################
# This script safely removes all Azure resources created for the
# video content moderation solution
#################################################################

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failure

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

# Function to validate Azure CLI login
validate_azure_login() {
    log_info "Validating Azure CLI authentication..."
    if ! az account show >/dev/null 2>&1; then
        log_error "Azure CLI is not authenticated. Please run 'az login' first."
        exit 1
    fi
    
    local subscription=$(az account show --query name -o tsv)
    log_success "Authenticated to Azure subscription: $subscription"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Validate Azure authentication
    validate_azure_login
    
    log_success "Prerequisites check completed"
}

# Function to prompt for confirmation
confirm_deletion() {
    local resource_group="$1"
    
    echo
    log_warning "=== DESTRUCTIVE OPERATION WARNING ==="
    log_warning "This will permanently delete the following:"
    log_warning "  • Resource Group: $resource_group"
    log_warning "  • All contained Azure resources"
    log_warning "  • All stored data and configurations"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    echo
    log_warning "Final confirmation required!"
    read -p "Type the resource group name to confirm deletion: " typed_name
    
    if [ "$typed_name" != "$resource_group" ]; then
        log_error "Resource group name mismatch. Operation cancelled for safety."
        exit 1
    fi
    
    log_warning "Proceeding with resource deletion..."
}

# Function to get resource group by pattern
find_resource_group() {
    log_info "Searching for video moderation resource groups..."
    
    # If a specific resource group is provided as argument, use it
    if [ -n "$1" ]; then
        echo "$1"
        return
    fi
    
    # Search for resource groups matching the naming pattern
    local resource_groups=$(az group list --query "[?starts_with(name, 'rg-video-moderation-')].name" -o tsv)
    
    if [ -z "$resource_groups" ]; then
        log_error "No video moderation resource groups found matching pattern 'rg-video-moderation-*'"
        log_info "If you have a resource group with a different name, please provide it as an argument:"
        log_info "  ./destroy.sh <resource-group-name>"
        exit 1
    fi
    
    # If multiple resource groups found, let user choose
    local group_count=$(echo "$resource_groups" | wc -l | tr -d ' ')
    if [ "$group_count" -gt 1 ]; then
        log_warning "Multiple video moderation resource groups found:"
        echo "$resource_groups" | nl
        echo
        read -p "Enter the number of the resource group to delete (or 'all' for all): " selection
        
        if [ "$selection" = "all" ]; then
            echo "$resource_groups"
        else
            echo "$resource_groups" | sed -n "${selection}p"
        fi
    else
        echo "$resource_groups"
    fi
}

# Function to stop Stream Analytics job
stop_stream_analytics_job() {
    local resource_group="$1"
    
    log_info "Stopping Stream Analytics jobs in resource group: $resource_group"
    
    local sa_jobs=$(az stream-analytics job list \
        --resource-group "$resource_group" \
        --query "[].name" -o tsv 2>/dev/null || true)
    
    if [ -n "$sa_jobs" ]; then
        while IFS= read -r job_name; do
            if [ -n "$job_name" ]; then
                log_info "Stopping Stream Analytics job: $job_name"
                local job_state=$(az stream-analytics job show \
                    --name "$job_name" \
                    --resource-group "$resource_group" \
                    --query "jobState" -o tsv 2>/dev/null || echo "Unknown")
                
                if [ "$job_state" = "Running" ]; then
                    az stream-analytics job stop \
                        --name "$job_name" \
                        --resource-group "$resource_group" 2>/dev/null || log_warning "Failed to stop job: $job_name"
                    log_success "Stream Analytics job stopped: $job_name"
                else
                    log_info "Stream Analytics job already stopped: $job_name (state: $job_state)"
                fi
            fi
        done <<< "$sa_jobs"
    else
        log_info "No Stream Analytics jobs found in resource group"
    fi
}

# Function to list resources before deletion
list_resources() {
    local resource_group="$1"
    
    log_info "Listing resources in resource group: $resource_group"
    
    if ! az group show --name "$resource_group" >/dev/null 2>&1; then
        log_warning "Resource group '$resource_group' does not exist"
        return 1
    fi
    
    local resources=$(az resource list --resource-group "$resource_group" --query "[].{Name:name, Type:type}" -o table 2>/dev/null)
    
    if [ -n "$resources" ]; then
        echo "$resources"
        echo
        local resource_count=$(az resource list --resource-group "$resource_group" --query "length([])" -o tsv 2>/dev/null)
        log_info "Total resources to be deleted: $resource_count"
    else
        log_info "No resources found in resource group"
    fi
    
    return 0
}

# Function to delete resource group
delete_resource_group() {
    local resource_group="$1"
    
    log_info "Initiating deletion of resource group: $resource_group"
    
    # Check if resource group exists
    if ! az group show --name "$resource_group" >/dev/null 2>&1; then
        log_warning "Resource group '$resource_group' does not exist or has already been deleted"
        return 0
    fi
    
    # Stop Stream Analytics jobs first (they need to be stopped before deletion)
    stop_stream_analytics_job "$resource_group"
    
    # List resources before deletion
    list_resources "$resource_group"
    
    # Delete the resource group and all its resources
    log_info "Deleting resource group and all contained resources..."
    log_warning "This may take several minutes..."
    
    az group delete \
        --name "$resource_group" \
        --yes \
        --no-wait
    
    log_success "Resource group deletion initiated: $resource_group"
    log_info "Deletion is running in the background and may take several minutes to complete"
}

# Function to verify deletion
verify_deletion() {
    local resource_group="$1"
    local max_attempts=30
    local attempt=1
    
    log_info "Monitoring deletion progress..."
    
    while [ $attempt -le $max_attempts ]; do
        if ! az group show --name "$resource_group" >/dev/null 2>&1; then
            log_success "Resource group has been successfully deleted: $resource_group"
            return 0
        fi
        
        log_info "Deletion in progress... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    log_warning "Deletion is still in progress after $((max_attempts * 10)) seconds"
    log_info "You can check the status in the Azure portal or run:"
    log_info "  az group show --name $resource_group"
    
    return 1
}

# Function to clean up multiple resource groups
cleanup_multiple_groups() {
    local resource_groups="$1"
    
    while IFS= read -r resource_group; do
        if [ -n "$resource_group" ]; then
            echo
            log_info "=== Processing Resource Group: $resource_group ==="
            
            # Confirm deletion for each resource group
            confirm_deletion "$resource_group"
            
            # Delete the resource group
            delete_resource_group "$resource_group"
        fi
    done <<< "$resource_groups"
    
    echo
    log_info "=== All Resource Group Deletions Initiated ==="
    log_info "Deletions are running in the background"
    log_info "You can monitor progress in the Azure portal"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "=== CLEANUP PROCESS COMPLETED ==="
    echo
    log_info "Summary:"
    log_info "  • Resource group deletion(s) initiated"
    log_info "  • Stream Analytics jobs stopped"
    log_info "  • All associated resources will be removed"
    echo
    log_info "Note:"
    log_info "  • Deletion continues in the background"
    log_info "  • Complete deletion may take several minutes"
    log_info "  • No further charges will be incurred once deletion completes"
    echo
    log_info "You can verify deletion completion by checking the Azure portal"
    log_info "or running: az group list --query \"[?contains(name, 'video-moderation')]\""
}

# Function to handle script interruption
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        log_error "Cleanup process encountered an error"
        log_info "Some resources may still exist and continue to incur charges"
        log_info "Please check the Azure portal and manually delete any remaining resources"
    fi
}

# Set trap for cleanup on exit
trap cleanup_on_exit EXIT

# Function to show usage
show_usage() {
    echo "Usage: $0 [resource-group-name]"
    echo
    echo "Examples:"
    echo "  $0                           # Interactive mode - search for resource groups"
    echo "  $0 rg-video-moderation-abc   # Delete specific resource group"
    echo "  $0 --help                    # Show this help message"
    echo
    echo "This script will safely delete Azure resources created for video content moderation."
}

# Main cleanup function
main() {
    # Handle help flag
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        show_usage
        exit 0
    fi
    
    log_info "=== Azure Intelligent Video Content Moderation - Cleanup ==="
    log_info "Starting cleanup process..."
    echo
    
    check_prerequisites
    
    # Find resource groups to delete
    local resource_groups=$(find_resource_group "$1")
    
    if [ -z "$resource_groups" ]; then
        log_error "No resource groups found to delete"
        exit 1
    fi
    
    # Process single or multiple resource groups
    local group_count=$(echo "$resource_groups" | wc -l | tr -d ' ')
    
    if [ "$group_count" -eq 1 ]; then
        log_info "=== Single Resource Group Cleanup ==="
        confirm_deletion "$resource_groups"
        delete_resource_group "$resource_groups"
        
        # Optionally wait for verification
        read -p "Wait for deletion verification? (y/n): " wait_verification
        if [ "$wait_verification" = "y" ] || [ "$wait_verification" = "yes" ]; then
            verify_deletion "$resource_groups"
        fi
    else
        log_info "=== Multiple Resource Groups Cleanup ==="
        cleanup_multiple_groups "$resource_groups"
    fi
    
    display_cleanup_summary
}

# Execute main function
main "$@"