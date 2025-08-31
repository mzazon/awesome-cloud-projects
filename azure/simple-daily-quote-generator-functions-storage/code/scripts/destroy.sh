#!/bin/bash

# Simple Daily Quote Generator - Azure Cleanup Script
# This script removes all Azure resources created by the deployment script

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Azure CLI login status
check_azure_login() {
    if ! az account show >/dev/null 2>&1; then
        log_error "Azure CLI not logged in. Please run 'az login' first."
        exit 1
    fi
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check Azure CLI
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in
    check_azure_login
    
    # Check subscription
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    log_info "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    
    log_success "Prerequisites validation completed"
}

# Function to discover resources
discover_resources() {
    log_info "Discovering quote generator resources..."
    
    # Find resource groups with quote generator pattern
    RESOURCE_GROUPS=$(az group list \
        --query "[?starts_with(name, 'rg-quote-generator-')].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$RESOURCE_GROUPS" ]]; then
        log_warning "No quote generator resource groups found matching pattern 'rg-quote-generator-*'"
        
        # Check for manually specified resource group
        if [[ -n "${RESOURCE_GROUP:-}" ]]; then
            if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
                RESOURCE_GROUPS="$RESOURCE_GROUP"
                log_info "Using manually specified resource group: $RESOURCE_GROUP"
            else
                log_error "Manually specified resource group '$RESOURCE_GROUP' not found"
                exit 1
            fi
        else
            log_info "No resources to clean up"
            exit 0
        fi
    fi
    
    log_info "Found resource groups to evaluate:"
    echo "$RESOURCE_GROUPS" | while read -r rg; do
        echo "  - $rg"
    done
}

# Function to confirm deletion
confirm_deletion() {
    local resource_groups="$1"
    
    echo ""
    log_warning "This will permanently delete the following resources:"
    
    echo "$resource_groups" | while read -r rg; do
        if [[ -n "$rg" ]]; then
            echo ""
            log_info "Resource Group: $rg"
            
            # List resources in the group
            RESOURCES=$(az resource list \
                --resource-group "$rg" \
                --query "[].{Name:name,Type:type}" \
                --output table 2>/dev/null || echo "Unable to list resources")
            
            if [[ "$RESOURCES" != "Unable to list resources" ]]; then
                echo "$RESOURCES" | tail -n +3 | while read -r line; do
                    if [[ -n "$line" ]]; then
                        echo "    $line"
                    fi
                done
            else
                echo "    Unable to enumerate resources in this group"
            fi
        fi
    done
    
    echo ""
    log_warning "THIS ACTION CANNOT BE UNDONE!"
    echo ""
    
    # Skip confirmation if --force flag is provided
    if [[ "${1:-}" == "--force" ]] || [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log_warning "Force delete enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to delete these resources? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
}

# Function to delete individual resources (graceful approach)
delete_resources_gracefully() {
    local resource_group="$1"
    
    log_info "Attempting graceful deletion of resources in $resource_group..."
    
    # Get Function Apps in the resource group
    FUNCTION_APPS=$(az functionapp list \
        --resource-group "$resource_group" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    # Delete Function Apps first
    if [[ -n "$FUNCTION_APPS" ]]; then
        echo "$FUNCTION_APPS" | while read -r app; do
            if [[ -n "$app" ]]; then
                log_info "Deleting Function App: $app"
                if az functionapp delete \
                    --resource-group "$resource_group" \
                    --name "$app" \
                    --slot production 2>/dev/null; then
                    log_success "Function App deleted: $app"
                else
                    log_warning "Failed to delete Function App: $app (will be cleaned up with resource group)"
                fi
            fi
        done
    fi
    
    # Get Storage Accounts in the resource group
    STORAGE_ACCOUNTS=$(az storage account list \
        --resource-group "$resource_group" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    # Delete Storage Accounts
    if [[ -n "$STORAGE_ACCOUNTS" ]]; then
        echo "$STORAGE_ACCOUNTS" | while read -r account; do
            if [[ -n "$account" ]]; then
                log_info "Deleting Storage Account: $account"
                if az storage account delete \
                    --resource-group "$resource_group" \
                    --name "$account" \
                    --yes 2>/dev/null; then
                    log_success "Storage Account deleted: $account"
                else
                    log_warning "Failed to delete Storage Account: $account (will be cleaned up with resource group)"
                fi
            fi
        done
    fi
    
    # Wait a moment for Azure to process deletions
    sleep 5
}

# Function to delete resource group
delete_resource_group() {
    local resource_group="$1"
    
    log_info "Deleting resource group: $resource_group"
    
    # Attempt graceful deletion first
    delete_resources_gracefully "$resource_group"
    
    # Delete the resource group (this will clean up any remaining resources)
    if az group delete \
        --name "$resource_group" \
        --yes \
        --no-wait 2>/dev/null; then
        log_success "Resource group deletion initiated: $resource_group"
        
        # Check if we should wait for completion
        if [[ "${WAIT_FOR_COMPLETION:-}" == "true" ]]; then
            log_info "Waiting for resource group deletion to complete..."
            
            # Wait for deletion to complete (check every 30 seconds, max 10 minutes)
            local wait_count=0
            local max_wait=20  # 20 * 30 seconds = 10 minutes
            
            while [[ $wait_count -lt $max_wait ]]; do
                if ! az group exists --name "$resource_group" 2>/dev/null; then
                    log_success "Resource group deletion completed: $resource_group"
                    return 0
                fi
                
                log_info "Still waiting for deletion... (${wait_count}/${max_wait})"
                sleep 30
                ((wait_count++))
            done
            
            log_warning "Deletion is taking longer than expected. Check Azure portal for status."
        else
            log_info "Resource group deletion initiated. This may take several minutes to complete."
        fi
    else
        log_error "Failed to initiate resource group deletion: $resource_group"
        return 1
    fi
}

# Function to verify deletion
verify_deletion() {
    local resource_groups="$1"
    
    log_info "Verifying resource deletion..."
    
    local remaining_groups=""
    echo "$resource_groups" | while read -r rg; do
        if [[ -n "$rg" ]]; then
            if az group exists --name "$rg" 2>/dev/null; then
                remaining_groups="${remaining_groups}${rg}\n"
            fi
        fi
    done
    
    if [[ -n "$remaining_groups" ]]; then
        log_warning "The following resource groups are still being deleted:"
        echo -e "$remaining_groups" | while read -r rg; do
            if [[ -n "$rg" ]]; then
                echo "  - $rg"
            fi
        done
        log_info "Check deletion status with: az group list --query \"[?starts_with(name, 'rg-quote-generator-')].name\" -o table"
    else
        log_success "All quote generator resource groups have been deleted"
    fi
}

# Function to clean up local environment
cleanup_local_environment() {
    log_info "Cleaning up local environment..."
    
    # Clear common environment variables that might have been set
    unset RESOURCE_GROUP 2>/dev/null || true
    unset LOCATION 2>/dev/null || true
    unset STORAGE_ACCOUNT 2>/dev/null || true
    unset FUNCTION_APP 2>/dev/null || true
    unset STORAGE_CONNECTION 2>/dev/null || true
    unset RANDOM_SUFFIX 2>/dev/null || true
    unset SUBSCRIPTION_ID 2>/dev/null || true
    
    # Remove any temporary function files if they exist
    if [[ -d "quote-function" ]]; then
        rm -rf quote-function
        log_info "Removed local quote-function directory"
    fi
    
    if [[ -f "quote-function.zip" ]]; then
        rm -f quote-function.zip
        log_info "Removed local quote-function.zip file"
    fi
    
    log_success "Local environment cleanup completed"
}

# Function to display cleanup summary
display_summary() {
    echo ""
    log_success "=== CLEANUP COMPLETED ==="
    echo ""
    log_info "All quote generator resources have been removed or are being removed."
    log_info "Note: Resource deletion in Azure may take several minutes to complete fully."
    echo ""
    log_info "You can verify complete deletion with:"
    echo "  az group list --query \"[?starts_with(name, 'rg-quote-generator-')].name\" -o table"
    echo ""
    log_info "If you need to deploy again, run: ./deploy.sh"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force                 Skip confirmation prompt"
    echo "  --wait                  Wait for deletion to complete"
    echo "  --resource-group RG     Specify a specific resource group to delete"
    echo "  --help                  Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  FORCE_DELETE=true       Same as --force flag"
    echo "  WAIT_FOR_COMPLETION=true Same as --wait flag"
    echo "  RESOURCE_GROUP          Same as --resource-group parameter"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive deletion"
    echo "  $0 --force                           # Skip confirmation"
    echo "  $0 --wait                            # Wait for completion"
    echo "  $0 --resource-group rg-quote-generator-abc123"
    echo "  FORCE_DELETE=true $0                 # Using environment variable"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE_DELETE="true"
                shift
                ;;
            --wait)
                export WAIT_FOR_COMPLETION="true"
                shift
                ;;
            --resource-group)
                export RESOURCE_GROUP="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main execution function
main() {
    log_info "Starting Azure Simple Daily Quote Generator cleanup..."
    echo ""
    
    validate_prerequisites
    discover_resources
    
    # Store discovered resource groups
    local resource_groups_to_delete="$RESOURCE_GROUPS"
    
    if [[ -z "$resource_groups_to_delete" ]]; then
        log_info "No resources found to clean up"
        exit 0
    fi
    
    confirm_deletion "$resource_groups_to_delete"
    
    # Delete each resource group
    local deletion_errors=0
    echo "$resource_groups_to_delete" | while read -r rg; do
        if [[ -n "$rg" ]]; then
            if ! delete_resource_group "$rg"; then
                ((deletion_errors++))
            fi
        fi
    done
    
    if [[ $deletion_errors -gt 0 ]]; then
        log_warning "Some resource group deletions may have failed. Check Azure portal for status."
    fi
    
    verify_deletion "$resource_groups_to_delete"
    cleanup_local_environment
    display_summary
    
    log_success "Cleanup process completed!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    main
fi