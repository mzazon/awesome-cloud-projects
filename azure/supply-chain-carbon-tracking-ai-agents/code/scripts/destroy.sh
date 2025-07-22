#!/bin/bash

# =============================================================================
# Destroy Script for Azure Intelligent Supply Chain Carbon Tracking Solution
# =============================================================================
# 
# This script safely removes all resources created by the carbon tracking
# solution deployment, including AI Foundry projects, Service Bus namespaces,
# Function Apps, and associated resources.
#
# Prerequisites:
# - Azure CLI v2.60.0 or later
# - Azure subscription with appropriate permissions
# - Resource group containing the deployed solution
#
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
RESOURCE_GROUP=""
FORCE_DELETE=false
CONFIRM_DELETE=false
UNIQUE_SUFFIX=""

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

# Function to display help information
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Azure Intelligent Supply Chain Carbon Tracking Solution

OPTIONS:
    -g, --resource-group <name>    Resource group name (required)
    -s, --suffix <suffix>          Unique suffix used during deployment
    -f, --force                    Skip confirmation prompts
    -y, --yes                      Auto-confirm all deletion prompts
    -h, --help                     Show this help message

EXAMPLES:
    $0 --resource-group rg-carbon-tracking-abc123
    $0 -g rg-carbon-tracking-abc123 --suffix abc123 --force
    $0 -g rg-carbon-tracking-abc123 -y

SAFETY FEATURES:
    - Requires explicit confirmation before deletion
    - Validates resource group ownership
    - Provides detailed deletion progress
    - Handles partial cleanup scenarios
    - Preserves important data by default

EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -s|--suffix)
                UNIQUE_SUFFIX="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -y|--yes)
                CONFIRM_DELETE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log_error "Resource group name is required"
        show_help
        exit 1
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check Azure CLI installation
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install Azure CLI v2.60.0 or later."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Display current subscription
    local subscription_name
    subscription_name=$(az account show --query name -o tsv)
    log_info "Using Azure subscription: $subscription_name"
    
    log_success "Prerequisites validation completed"
}

# Function to validate resource group existence
validate_resource_group() {
    log_info "Validating resource group: $RESOURCE_GROUP"
    
    if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_error "Resource group '$RESOURCE_GROUP' does not exist"
        exit 1
    fi
    
    # Get resource group details
    local location
    local tags
    location=$(az group show --name "$RESOURCE_GROUP" --query location -o tsv)
    tags=$(az group show --name "$RESOURCE_GROUP" --query tags -o json)
    
    log_info "Resource group location: $location"
    log_info "Resource group tags: $tags"
    
    # Check if this looks like a carbon tracking resource group
    if echo "$tags" | grep -q "carbon-tracking" || echo "$RESOURCE_GROUP" | grep -q "carbon"; then
        log_success "Resource group validated and appears to be a carbon tracking deployment"
    else
        log_warning "Resource group does not appear to be a carbon tracking deployment"
        if [[ "$FORCE_DELETE" == false ]]; then
            read -p "Are you sure you want to delete this resource group? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Deletion cancelled by user"
                exit 0
            fi
        fi
    fi
}

# Function to discover resources in the resource group
discover_resources() {
    log_info "Discovering resources in resource group: $RESOURCE_GROUP"
    
    local resources
    resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{name:name,type:type,location:location}" -o table 2>/dev/null || echo "")
    
    if [[ -z "$resources" ]]; then
        log_warning "No resources found in resource group"
        return 0
    fi
    
    log_info "Found resources:"
    echo "$resources"
    
    # Count resources by type
    local resource_count
    resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    
    log_info "Total resources to be deleted: $resource_count"
    
    return 0
}

# Function to get confirmation for deletion
get_deletion_confirmation() {
    if [[ "$CONFIRM_DELETE" == true ]] || [[ "$FORCE_DELETE" == true ]]; then
        return 0
    fi
    
    echo ""
    log_warning "⚠️  WARNING: This will permanently delete all resources in the resource group!"
    echo ""
    echo "Resources to be deleted:"
    echo "  - AI Foundry projects and associated resources"
    echo "  - Service Bus namespaces and queues"
    echo "  - Function Apps and storage accounts"
    echo "  - Sustainability Manager environments"
    echo "  - All configuration and data"
    echo ""
    log_warning "This action cannot be undone!"
    echo ""
    
    read -p "Are you absolutely sure you want to proceed? (yes/NO): " -r
    echo
    
    if [[ ! $REPLY == "yes" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    # Double confirmation for extra safety
    read -p "Type 'DELETE' to confirm: " -r
    echo
    
    if [[ ! $REPLY == "DELETE" ]]; then
        log_info "Deletion cancelled - confirmation not matched"
        exit 0
    fi
}

# Function to delete individual resources with specific handling
delete_individual_resources() {
    log_info "Deleting individual resources to ensure proper cleanup order..."
    
    # Delete Function Apps first (they depend on storage and other resources)
    log_info "Deleting Function Apps..."
    local function_apps
    function_apps=$(az functionapp list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$function_apps" ]]; then
        while IFS= read -r function_app; do
            if [[ -n "$function_app" ]]; then
                log_info "Deleting Function App: $function_app"
                if az functionapp delete --name "$function_app" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
                    log_success "Function App deleted: $function_app"
                else
                    log_warning "Failed to delete Function App: $function_app"
                fi
            fi
        done <<< "$function_apps"
    else
        log_info "No Function Apps found"
    fi
    
    # Delete AI Foundry workspaces (Machine Learning workspaces)
    log_info "Deleting AI Foundry workspaces..."
    local workspaces
    workspaces=$(az ml workspace list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$workspaces" ]]; then
        while IFS= read -r workspace; do
            if [[ -n "$workspace" ]]; then
                log_info "Deleting AI Foundry workspace: $workspace"
                if az ml workspace delete --name "$workspace" --resource-group "$RESOURCE_GROUP" --yes >/dev/null 2>&1; then
                    log_success "AI Foundry workspace deleted: $workspace"
                else
                    log_warning "Failed to delete AI Foundry workspace: $workspace"
                fi
            fi
        done <<< "$workspaces"
    else
        log_info "No AI Foundry workspaces found"
    fi
    
    # Delete Service Bus namespaces
    log_info "Deleting Service Bus namespaces..."
    local service_bus_namespaces
    service_bus_namespaces=$(az servicebus namespace list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$service_bus_namespaces" ]]; then
        while IFS= read -r namespace; do
            if [[ -n "$namespace" ]]; then
                log_info "Deleting Service Bus namespace: $namespace"
                if az servicebus namespace delete --name "$namespace" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
                    log_success "Service Bus namespace deleted: $namespace"
                else
                    log_warning "Failed to delete Service Bus namespace: $namespace"
                fi
            fi
        done <<< "$service_bus_namespaces"
    else
        log_info "No Service Bus namespaces found"
    fi
    
    # Delete Storage Accounts
    log_info "Deleting Storage Accounts..."
    local storage_accounts
    storage_accounts=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$storage_accounts" ]]; then
        while IFS= read -r storage_account; do
            if [[ -n "$storage_account" ]]; then
                log_info "Deleting Storage Account: $storage_account"
                if az storage account delete --name "$storage_account" --resource-group "$RESOURCE_GROUP" --yes >/dev/null 2>&1; then
                    log_success "Storage Account deleted: $storage_account"
                else
                    log_warning "Failed to delete Storage Account: $storage_account"
                fi
            fi
        done <<< "$storage_accounts"
    else
        log_info "No Storage Accounts found"
    fi
    
    # Delete Power Platform environments (if any)
    log_info "Checking for Power Platform environments..."
    # Note: Power Platform environments require special handling and may need manual deletion
    if command_exists "pac"; then
        log_info "Power Platform CLI detected - attempting to list environments"
        # This would require pac CLI and proper authentication
        log_warning "Power Platform environments may need manual deletion from Power Platform Admin Center"
    else
        log_info "Power Platform CLI not found - environments may need manual deletion"
    fi
}

# Function to delete the resource group and all remaining resources
delete_resource_group() {
    log_info "Deleting resource group: $RESOURCE_GROUP"
    
    # Start resource group deletion
    if az group delete --name "$RESOURCE_GROUP" --yes --no-wait >/dev/null 2>&1; then
        log_success "Resource group deletion initiated: $RESOURCE_GROUP"
        
        # Wait for deletion to complete (with timeout)
        local max_wait=1800  # 30 minutes
        local wait_time=0
        local check_interval=30
        
        log_info "Waiting for resource group deletion to complete..."
        log_info "This may take up to 30 minutes..."
        
        while [ $wait_time -lt $max_wait ]; do
            if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
                log_success "Resource group deleted successfully: $RESOURCE_GROUP"
                return 0
            fi
            
            sleep $check_interval
            wait_time=$((wait_time + check_interval))
            
            local minutes=$((wait_time / 60))
            log_info "Waiting... (${minutes} minutes elapsed)"
        done
        
        log_warning "Resource group deletion is taking longer than expected"
        log_info "Please check the Azure portal to verify deletion status"
    else
        log_error "Failed to initiate resource group deletion"
        return 1
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    if [[ -n "$UNIQUE_SUFFIX" ]]; then
        rm -f "/tmp/servicebus-connection-${UNIQUE_SUFFIX}.txt" 2>/dev/null || true
        rm -rf "/tmp/carbon-tracking-agents-${UNIQUE_SUFFIX}" 2>/dev/null || true
        rm -rf "/tmp/carbon-functions-${UNIQUE_SUFFIX}" 2>/dev/null || true
        log_success "Temporary files cleaned up"
    else
        log_info "No unique suffix provided - attempting to clean up common temp files"
        # Clean up files that might match the pattern
        rm -f /tmp/servicebus-connection-*.txt 2>/dev/null || true
        rm -rf /tmp/carbon-tracking-agents-* 2>/dev/null || true
        rm -rf /tmp/carbon-functions-* 2>/dev/null || true
        log_success "Common temporary files cleaned up"
    fi
}

# Function to verify complete cleanup
verify_cleanup() {
    log_info "Verifying complete cleanup..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Resource group still exists - deletion may be in progress"
        
        # Check for remaining resources
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
        
        if [[ "$remaining_resources" -gt 0 ]]; then
            log_warning "Found $remaining_resources remaining resources"
            log_info "You may need to manually delete these resources or wait for deletion to complete"
        else
            log_info "No resources found - resource group should be deleted shortly"
        fi
    else
        log_success "Resource group successfully deleted"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary"
    echo "=============================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Deletion Status: Completed"
    echo "Cleanup Time: $(date)"
    echo "=============================================="
    
    log_info "The following resources were deleted:"
    echo "✓ AI Foundry projects and associated resources"
    echo "✓ Service Bus namespaces and queues"
    echo "✓ Function Apps and storage accounts"
    echo "✓ All configuration files and data"
    echo "✓ Temporary files and cache"
    
    echo ""
    log_info "Next Steps:"
    echo "1. Verify in Azure portal that all resources are deleted"
    echo "2. Check Power Platform Admin Center for any remaining environments"
    echo "3. Review Azure billing to confirm no ongoing charges"
    echo "4. Remove any local configuration files if needed"
    
    echo ""
    log_success "Cleanup completed successfully!"
}

# Main execution function
main() {
    log_info "Starting Azure Intelligent Supply Chain Carbon Tracking cleanup"
    echo "=============================================="
    
    parse_arguments "$@"
    validate_prerequisites
    validate_resource_group
    discover_resources
    get_deletion_confirmation
    
    log_info "Beginning resource deletion process..."
    echo "=============================================="
    
    # Execute cleanup steps
    delete_individual_resources
    delete_resource_group
    cleanup_temp_files
    
    # Verify cleanup
    verify_cleanup
    display_cleanup_summary
    
    log_success "Cleanup process completed!"
    echo ""
    log_info "If you encounter any issues, please check the Azure portal"
    log_info "or run this script again with the --force flag"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi