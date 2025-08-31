#!/bin/bash

# Azure Resource Monitoring Dashboard Workbooks - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail  # Enhanced error handling

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

success() {
    echo -e "${GREEN}✅ $*${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}"
}

error() {
    echo -e "${RED}❌ $*${NC}"
}

# Script metadata
SCRIPT_NAME="Azure Resource Monitoring Dashboard Workbooks Cleanup"
SCRIPT_VERSION="1.0.0"
RECIPE_VERSION="1.1"

log "Starting $SCRIPT_NAME (v$SCRIPT_VERSION)"
log "Recipe Version: $RECIPE_VERSION"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to discover resource groups to clean up
discover_resource_groups() {
    log "Discovering monitoring resource groups..."
    
    # Look for resource groups with monitoring tags or naming pattern
    local resource_groups
    resource_groups=$(az group list \
        --query "[?tags.purpose=='monitoring' || contains(name, 'monitoring') || tags.recipe=='azure-workbooks-monitoring'].name" \
        --output tsv 2>/dev/null || true)
    
    if [[ -z "$resource_groups" ]]; then
        warning "No monitoring resource groups found with standard tags or naming patterns"
        return 1
    fi
    
    echo "Found monitoring resource groups:"
    for rg in $resource_groups; do
        echo "  - $rg"
    done
    
    return 0
}

# Function to get user confirmation for destructive operations
confirm_deletion() {
    local resource_group=$1
    
    echo ""
    warning "This will DELETE the following resource group and ALL its resources:"
    echo "  Resource Group: $resource_group"
    echo ""
    
    # Show resources in the group
    log "Resources that will be deleted:"
    az resource list --resource-group "$resource_group" \
        --query "[].{Name:name, Type:type, Location:location}" \
        --output table 2>/dev/null || true
    
    echo ""
    warning "This action is IRREVERSIBLE!"
    echo ""
    
    # Multiple confirmation prompts for safety
    read -p "Are you sure you want to delete resource group '$resource_group'? (yes/no): " confirm1
    if [[ "$confirm1" != "yes" ]]; then
        log "Operation cancelled by user"
        return 1
    fi
    
    read -p "Type the resource group name to confirm: " confirm2
    if [[ "$confirm2" != "$resource_group" ]]; then
        error "Resource group name mismatch. Operation cancelled."
        return 1
    fi
    
    warning "Final confirmation: This will DELETE ALL RESOURCES in '$resource_group'"
    read -p "Type 'DELETE' to proceed: " confirm3
    if [[ "$confirm3" != "DELETE" ]]; then
        log "Operation cancelled by user"
        return 1
    fi
    
    return 0
}

# Function to delete a resource group and all its resources
delete_resource_group() {
    local resource_group=$1
    
    log "Deleting resource group: $resource_group"
    
    # Check if resource group exists
    if ! az group show --name "$resource_group" &> /dev/null; then
        warning "Resource group '$resource_group' does not exist"
        return 0
    fi
    
    # Get confirmation before deletion
    if ! confirm_deletion "$resource_group"; then
        log "Skipping deletion of resource group: $resource_group"
        return 0
    fi
    
    log "Starting deletion of resource group: $resource_group"
    
    # Start the deletion (async)
    az group delete \
        --name "$resource_group" \
        --yes \
        --no-wait \
        --output none
    
    success "Resource group deletion initiated: $resource_group"
    log "Note: Azure resource deletion is asynchronous and may take several minutes"
    
    return 0
}

# Function to monitor deletion progress
monitor_deletion_progress() {
    local resource_group=$1
    local max_wait_time=600  # 10 minutes
    local wait_interval=30   # 30 seconds
    local elapsed_time=0
    
    log "Monitoring deletion progress for resource group: $resource_group"
    
    while [[ $elapsed_time -lt $max_wait_time ]]; do
        if ! az group exists --name "$resource_group" 2>/dev/null; then
            success "Resource group '$resource_group' has been successfully deleted"
            return 0
        fi
        
        log "Deletion in progress... (elapsed: ${elapsed_time}s/${max_wait_time}s)"
        sleep $wait_interval
        elapsed_time=$((elapsed_time + wait_interval))
    done
    
    warning "Deletion monitoring timed out after ${max_wait_time} seconds"
    log "The resource group may still be deleting in the background"
    log "You can check the status in the Azure portal or run: az group exists --name '$resource_group'"
    
    return 1
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local configuration files..."
    
    local files_to_remove=(
        "resource_health_query.kql"
        "performance_metrics_query.kql"
        "azure_metrics_query.txt"
        "cost_monitoring_query.kql"
    )
    
    local removed_count=0
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "Removed: $file"
            ((removed_count++))
        fi
    done
    
    if [[ $removed_count -gt 0 ]]; then
        success "Removed $removed_count local configuration files"
    else
        log "No local configuration files found to remove"
    fi
    
    # Clean up environment variables if they exist
    local env_vars=(
        "RESOURCE_GROUP" "LOCATION" "SUBSCRIPTION_ID" "RANDOM_SUFFIX"
        "LOG_WORKSPACE" "STORAGE_ACCOUNT" "APP_SERVICE_PLAN" "WEB_APP"
        "WORKBOOK_NAME" "WORKBOOK_DESCRIPTION" "RG_RESOURCE_ID"
    )
    
    for var in "${env_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            unset "$var"
        fi
    done
    
    success "Environment variables cleared"
}

# Function to list Azure Monitor Workbooks that might need manual cleanup
list_workbooks_for_manual_cleanup() {
    log "Checking for Azure Monitor Workbooks that may need manual cleanup..."
    
    # Note: Azure CLI doesn't have direct commands for listing workbooks
    # Users need to check the Azure portal manually
    
    echo ""
    echo "=== MANUAL CLEANUP REQUIRED ==="
    echo "Azure Monitor Workbooks cannot be deleted via Azure CLI."
    echo "Please manually check and delete any workbooks in the Azure portal:"
    echo ""
    echo "1. Go to: https://portal.azure.com/#view/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/~/workbooks"
    echo "2. Look for workbooks with names containing 'Resource Monitoring Dashboard'"
    echo "3. Delete any workbooks that were created as part of this recipe"
    echo ""
    warning "Workbooks must be deleted manually from the Azure portal"
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "=== CLEANUP SUMMARY ==="
    echo "✅ Resource group deletion initiated"
    echo "✅ Local configuration files removed"
    echo "✅ Environment variables cleared"
    echo ""
    echo "=== IMPORTANT NOTES ==="
    echo "• Azure resource deletion is asynchronous and may take several minutes"
    echo "• Monitor progress in the Azure portal or use: az group exists --name <group-name>"
    echo "• Azure Monitor Workbooks require manual deletion from the portal"
    echo "• No charges will be incurred once all resources are deleted"
    echo ""
    echo "=== VERIFICATION ==="
    echo "To verify complete cleanup:"
    echo "1. Check Azure portal for remaining resources"
    echo "2. Verify no charges in Cost Management + Billing"
    echo "3. Confirm workbooks are deleted from Azure Monitor"
    echo ""
    success "Cleanup process completed"
}

# Function to handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Cleanup script interrupted or failed with exit code $exit_code"
        warning "Some resources may not have been deleted"
        warning "Please check the Azure portal for remaining resources"
    fi
    exit $exit_code
}

# Set trap for cleanup on script exit
trap cleanup_on_exit EXIT INT TERM

# Interactive mode for selecting resource groups
interactive_cleanup() {
    log "Running interactive cleanup mode..."
    
    if ! discover_resource_groups; then
        log "Attempting to detect resource groups by naming pattern..."
        
        # Fallback: ask user to provide resource group name
        echo ""
        read -p "Enter the resource group name to delete (or 'quit' to exit): " user_rg
        
        if [[ "$user_rg" == "quit" ]] || [[ -z "$user_rg" ]]; then
            log "No resource group specified. Exiting."
            exit 0
        fi
        
        delete_resource_group "$user_rg"
        monitor_deletion_progress "$user_rg"
    else
        # Show discovered resource groups and let user select
        echo ""
        log "Select resource groups to delete (space-separated indices, or 'all' for all, or 'quit' to exit):"
        
        local rg_array
        readarray -t rg_array < <(az group list \
            --query "[?tags.purpose=='monitoring' || contains(name, 'monitoring') || tags.recipe=='azure-workbooks-monitoring'].name" \
            --output tsv 2>/dev/null)
        
        for i in "${!rg_array[@]}"; do
            echo "  $((i+1)). ${rg_array[i]}"
        done
        
        echo ""
        read -p "Enter selection: " selection
        
        if [[ "$selection" == "quit" ]]; then
            log "User cancelled operation"
            exit 0
        elif [[ "$selection" == "all" ]]; then
            for rg in "${rg_array[@]}"; do
                delete_resource_group "$rg"
            done
            
            # Monitor deletion of all groups
            for rg in "${rg_array[@]}"; do
                monitor_deletion_progress "$rg"
            done
        else
            # Parse space-separated indices
            for index in $selection; do
                if [[ "$index" =~ ^[0-9]+$ ]] && [[ $index -ge 1 ]] && [[ $index -le ${#rg_array[@]} ]]; then
                    local rg_index=$((index-1))
                    delete_resource_group "${rg_array[rg_index]}"
                    monitor_deletion_progress "${rg_array[rg_index]}"
                else
                    warning "Invalid selection: $index"
                fi
            done
        fi
    fi
}

# Main cleanup function
main() {
    log "Starting Azure Resource Monitoring Dashboard Workbooks cleanup..."
    
    # Parse command line arguments
    local force_mode=false
    local resource_group=""
    local monitor_progress=true
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                resource_group="$2"
                shift 2
                ;;
            --force)
                force_mode=true
                shift
                ;;
            --no-monitor)
                monitor_progress=false
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --resource-group NAME    Specify resource group to delete"
                echo "  --force                  Skip confirmation prompts (dangerous!)"
                echo "  --no-monitor            Don't monitor deletion progress"
                echo "  --help, -h              Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                                    # Interactive mode"
                echo "  $0 --resource-group my-monitoring-rg # Delete specific resource group"
                echo "  $0 --force --resource-group my-rg    # Force delete without confirmation"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Execute cleanup steps
    check_prerequisites
    
    if [[ -n "$resource_group" ]]; then
        # Direct resource group deletion mode
        log "Direct deletion mode for resource group: $resource_group"
        
        if [[ "$force_mode" == "true" ]]; then
            warning "Force mode enabled - skipping confirmation prompts"
            az group delete --name "$resource_group" --yes --no-wait --output none
            success "Resource group deletion initiated: $resource_group"
        else
            delete_resource_group "$resource_group"
        fi
        
        if [[ "$monitor_progress" == "true" ]]; then
            monitor_deletion_progress "$resource_group"
        fi
    else
        # Interactive mode
        interactive_cleanup
    fi
    
    # Always clean up local files and show workbook cleanup info
    cleanup_local_files
    list_workbooks_for_manual_cleanup
    display_cleanup_summary
}

# Execute main function with all arguments
main "$@"