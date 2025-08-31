#!/bin/bash

# Azure Basic Network Setup - Cleanup Script
# This script removes all resources created by the deployment script
# Based on recipe: Basic Network Setup with Virtual Network and Subnets

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    success "Prerequisites check passed"
}

# List resource groups matching the pattern
list_matching_resource_groups() {
    log "Scanning for basic network setup resource groups..."
    
    # Look for resource groups with the naming pattern
    local matching_groups=$(az group list --query "[?starts_with(name, 'rg-basic-network-')].{Name:name, Location:location, Tags:tags}" -o table 2>/dev/null || echo "")
    
    if [[ -n "$matching_groups" && "$matching_groups" != "Name    Location    Tags" ]]; then
        echo
        echo "📋 Found resource groups that appear to be from this recipe:"
        echo "$matching_groups"
        echo
        return 0
    else
        log "No resource groups found matching pattern 'rg-basic-network-*'"
        return 1
    fi
}

# Get resource group from user input or environment
get_resource_group() {
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log "Using resource group from environment: $RESOURCE_GROUP"
        return 0
    fi
    
    # Try to list matching resource groups
    if list_matching_resource_groups; then
        echo -n "Enter the resource group name to delete: "
        read -r RESOURCE_GROUP
        
        if [[ -z "$RESOURCE_GROUP" ]]; then
            error "Resource group name cannot be empty"
        fi
    else
        echo -n "Enter the resource group name to delete: "
        read -r RESOURCE_GROUP
        
        if [[ -z "$RESOURCE_GROUP" ]]; then
            error "Resource group name cannot be empty"
        fi
    fi
    
    export RESOURCE_GROUP
}

# Verify resource group exists and show contents
verify_resource_group() {
    log "Verifying resource group: $RESOURCE_GROUP"
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group '$RESOURCE_GROUP' does not exist or you don't have access to it"
    fi
    
    # Show resource group details
    local rg_info=$(az group show --name "$RESOURCE_GROUP" --query "{Name:name, Location:location, Tags:tags}" -o table 2>/dev/null)
    echo
    echo "📋 Resource Group Details:"
    echo "$rg_info"
    echo
    
    # List resources in the group
    local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" -o table 2>/dev/null || echo "No resources found")
    echo "📦 Resources in this group:"
    echo "$resources"
    echo
    
    success "Resource group verification completed"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "${FORCE:-false}" == "true" ]]; then
        warning "FORCE mode enabled - skipping confirmation"
        return 0
    fi
    
    echo "⚠️  WARNING: This action will permanently delete the following:"
    echo "   • Resource Group: $RESOURCE_GROUP"
    echo "   • All resources within the resource group"
    echo "   • Virtual Network and all subnets"
    echo "   • Network Security Groups and rules"
    echo "   • All associated metadata and configurations"
    echo
    echo "💀 THIS ACTION CANNOT BE UNDONE!"
    echo
    
    echo -n "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: "
    read -r confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    echo
    echo -n "Final confirmation - delete resource group '$RESOURCE_GROUP'? (yes/no): "
    read -r final_confirmation
    
    if [[ "$final_confirmation" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    success "Deletion confirmed by user"
}

# Delete resource group and all contained resources
delete_resource_group() {
    log "Initiating deletion of resource group: $RESOURCE_GROUP"
    
    # Check if resource group still exists before deletion
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group '$RESOURCE_GROUP' no longer exists. Nothing to delete."
        return 0
    fi
    
    # Delete the resource group (this will delete all contained resources)
    log "Deleting resource group and all contained resources..."
    
    if [[ "${NO_WAIT:-false}" == "true" ]]; then
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            --output none
        
        success "Resource group deletion initiated (running in background)"
        warning "Note: Deletion may take several minutes to complete"
        log "Check deletion status with: az group show --name '$RESOURCE_GROUP' --query 'properties.provisioningState' -o tsv"
    else
        log "This may take several minutes. Please wait..."
        
        # Show progress during deletion
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --output none
        
        success "Resource group deleted successfully: $RESOURCE_GROUP"
    fi
}

# Verify deletion completion
verify_deletion() {
    if [[ "${NO_WAIT:-false}" == "true" ]]; then
        log "Skipping deletion verification (no-wait mode)"
        return 0
    fi
    
    log "Verifying deletion completion..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group still exists. Deletion may have failed."
    else
        success "Deletion verification passed - resource group no longer exists"
    fi
}

# Clean up environment variables
cleanup_environment() {
    log "Cleaning up environment variables..."
    
    # List of variables to unset
    local vars_to_unset=(
        "RESOURCE_GROUP"
        "LOCATION"
        "SUBSCRIPTION_ID"
        "VNET_NAME"
        "VNET_ADDRESS_SPACE"
        "FRONTEND_SUBNET_NAME"
        "BACKEND_SUBNET_NAME"
        "DATABASE_SUBNET_NAME"
    )
    
    for var in "${vars_to_unset[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            unset "$var"
        fi
    done
    
    success "Environment variables cleared"
}

# Display cleanup summary
display_summary() {
    echo
    echo "=========================================="
    echo "🧹 CLEANUP COMPLETED SUCCESSFULLY"
    echo "=========================================="
    echo
    echo "📋 Cleanup Summary:"
    echo "  ✅ Resource group deleted: $RESOURCE_GROUP"
    echo "  ✅ Virtual Network and subnets removed"
    echo "  ✅ Network Security Groups removed"
    echo "  ✅ All associated resources cleaned up"
    echo "  ✅ Environment variables cleared"
    echo
    echo "💰 Cost Impact: All billable resources have been removed"
    echo
    echo "📚 To redeploy the infrastructure, run: ./deploy.sh"
    echo "=========================================="
    echo
}

# Show help information
show_help() {
    echo "Azure Basic Network Setup - Cleanup Script"
    echo "==========================================="
    echo
    echo "This script removes all resources created by the deploy.sh script."
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --resource-group NAME  Specify resource group to delete"
    echo "  --force               Skip confirmation prompts (dangerous!)"
    echo "  --no-wait             Don't wait for deletion to complete"
    echo "  --list-only           Only list matching resource groups"
    echo "  --help, -h            Show this help message"
    echo
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP        Resource group name to delete"
    echo "  FORCE                 Set to 'true' to skip confirmations"
    echo "  NO_WAIT               Set to 'true' to run deletion in background"
    echo
    echo "Examples:"
    echo "  $0                                    # Interactive mode"
    echo "  $0 --resource-group rg-basic-network-abc123"
    echo "  $0 --force --no-wait                # Quick deletion without prompts"
    echo "  $0 --list-only                      # Just show matching resource groups"
    echo
}

# Main execution function
main() {
    echo "🧹 Starting Azure Basic Network Setup Cleanup"
    echo "=============================================="
    echo
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --no-wait)
                NO_WAIT=true
                shift
                ;;
            --list-only)
                LIST_ONLY=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
    
    check_prerequisites
    
    # If only listing, do that and exit
    if [[ "${LIST_ONLY:-false}" == "true" ]]; then
        list_matching_resource_groups || log "No matching resource groups found"
        exit 0
    fi
    
    get_resource_group
    verify_resource_group
    confirm_deletion
    delete_resource_group
    verify_deletion
    cleanup_environment
    display_summary
}

# Error handling
trap 'error "Script failed at line $LINENO. Exit code: $?"' ERR

# Execute main function
main "$@"