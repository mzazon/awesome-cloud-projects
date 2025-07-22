#!/bin/bash

# ==============================================================================
# Azure Container Apps and Key Vault Cleanup Script
# ==============================================================================
# This script safely removes all resources created by the deployment script
# for the Azure Container Apps and Key Vault recipe.
# ==============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# ==============================================================================
# Configuration and Variables
# ==============================================================================

# Script metadata
SCRIPT_VERSION="1.0"
SCRIPT_NAME="destroy.sh"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="destroy_$(date '+%Y%m%d_%H%M%S').log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Confirmation settings
SKIP_CONFIRMATION=false
DRY_RUN=false

# ==============================================================================
# Logging Functions
# ==============================================================================

log() {
    echo -e "${TIMESTAMP} [INFO] $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}❌ ERROR: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

log_warning() {
    echo -e "${YELLOW}⚠️  WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}ℹ️  INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# ==============================================================================
# Utility Functions
# ==============================================================================

print_banner() {
    echo -e "${BLUE}"
    echo "=============================================================="
    echo "  Azure Container Apps and Key Vault Cleanup Script"
    echo "  Version: $SCRIPT_VERSION"
    echo "  Started: $TIMESTAMP"
    echo "=============================================================="
    echo -e "${NC}"
}

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -y, --yes           Skip confirmation prompts"
    echo "  -d, --dry-run       Show what would be deleted without actually deleting"
    echo "  -h, --help          Show this help message"
    echo "  -g, --resource-group RESOURCE_GROUP"
    echo "                      Specify resource group to delete"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup"
    echo "  $0 -y                                 # Skip confirmations"
    echo "  $0 -d                                 # Dry run mode"
    echo "  $0 -g my-resource-group              # Specific resource group"
    echo ""
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Get subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    
    log_info "Azure CLI authenticated"
    log_info "Subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    
    log_success "Prerequisites check completed"
}

find_resource_groups() {
    log_info "Searching for recipe-related resource groups..."
    
    # Find resource groups created by the recipe
    RECIPE_RESOURCE_GROUPS=$(az group list \
        --query "[?tags.purpose=='recipe' && tags.owner=='container-apps-recipe'].name" \
        --output tsv)
    
    if [ -z "$RECIPE_RESOURCE_GROUPS" ]; then
        log_warning "No recipe-related resource groups found"
        return 1
    fi
    
    log_info "Found recipe resource groups:"
    echo "$RECIPE_RESOURCE_GROUPS" | while read -r rg; do
        log_info "  - $rg"
    done
    
    return 0
}

list_resources_in_group() {
    local resource_group=$1
    
    log_info "Resources in resource group '$resource_group':"
    
    # Get all resources in the resource group
    local resources=$(az resource list \
        --resource-group "$resource_group" \
        --query "[].{Name:name, Type:type, Location:location}" \
        --output table)
    
    if [ -n "$resources" ]; then
        echo "$resources" | tee -a "$LOG_FILE"
    else
        log_info "  No resources found in resource group"
    fi
    
    # Get resource group tags
    local tags=$(az group show \
        --name "$resource_group" \
        --query tags \
        --output json 2>/dev/null || echo "{}")
    
    if [ "$tags" != "{}" ] && [ "$tags" != "null" ]; then
        log_info "Resource group tags: $tags"
    fi
}

confirm_deletion() {
    local resource_group=$1
    
    if [ "$SKIP_CONFIRMATION" = true ]; then
        return 0
    fi
    
    echo
    echo -e "${YELLOW}⚠️  WARNING: This will permanently delete the resource group and ALL resources inside it!${NC}"
    echo
    echo "Resource Group: $resource_group"
    echo
    
    list_resources_in_group "$resource_group"
    
    echo
    echo -e "${RED}This action cannot be undone!${NC}"
    echo
    
    while true; do
        read -p "Are you sure you want to delete resource group '$resource_group'? (yes/no): " response
        case $response in
            [Yy]es|[Yy]|YES)
                log_info "User confirmed deletion of resource group '$resource_group'"
                return 0
                ;;
            [Nn]o|[Nn]|NO)
                log_info "User cancelled deletion of resource group '$resource_group'"
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

check_soft_deleted_key_vaults() {
    log_info "Checking for soft-deleted Key Vaults..."
    
    # List soft-deleted key vaults
    local soft_deleted_vaults=$(az keyvault list-deleted \
        --query "[?tags.purpose=='recipe' || contains(name, 'secure')].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [ -n "$soft_deleted_vaults" ]; then
        log_warning "Found soft-deleted Key Vaults that may need manual cleanup:"
        echo "$soft_deleted_vaults" | while read -r vault; do
            if [ -n "$vault" ]; then
                log_warning "  - $vault"
                if [ "$DRY_RUN" = false ]; then
                    log_info "Purging soft-deleted Key Vault: $vault"
                    az keyvault purge --name "$vault" --no-wait 2>/dev/null || log_warning "Failed to purge $vault (may require manual intervention)"
                fi
            fi
        done
    else
        log_info "No soft-deleted Key Vaults found"
    fi
}

wait_for_deletion() {
    local resource_group=$1
    local max_attempts=60
    local attempt=1
    
    log_info "Waiting for resource group deletion to complete..."
    
    while [ $attempt -le $max_attempts ]; do
        if ! az group exists --name "$resource_group" 2>/dev/null; then
            log_success "Resource group '$resource_group' successfully deleted"
            return 0
        fi
        
        if [ $((attempt % 10)) -eq 0 ]; then
            log_info "Still waiting... (attempt $attempt/$max_attempts)"
        else
            echo -n "."
        fi
        
        sleep 5
        ((attempt++))
    done
    
    log_warning "Resource group deletion is taking longer than expected"
    log_info "You can check the status in Azure Portal or run: az group show --name '$resource_group'"
}

delete_resource_group() {
    local resource_group=$1
    
    # Check if resource group exists
    if ! az group exists --name "$resource_group" 2>/dev/null; then
        log_warning "Resource group '$resource_group' does not exist"
        return 0
    fi
    
    log_info "Deleting resource group: $resource_group"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete resource group: $resource_group"
        list_resources_in_group "$resource_group"
        return 0
    fi
    
    # Confirm deletion
    if ! confirm_deletion "$resource_group"; then
        log_info "Skipping deletion of resource group: $resource_group"
        return 0
    fi
    
    # Delete the resource group
    log_info "Initiating resource group deletion..."
    az group delete \
        --name "$resource_group" \
        --yes \
        --no-wait
    
    # Wait for deletion to complete
    wait_for_deletion "$resource_group"
    
    log_success "Resource group '$resource_group' deletion completed"
}

cleanup_deployments() {
    log_info "Cleaning up deployment history..."
    
    # Get all deployments in the subscription
    local deployments=$(az deployment sub list \
        --query "[?contains(name, 'secure') || contains(name, 'container')].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [ -n "$deployments" ]; then
        log_info "Found related deployments to clean up:"
        echo "$deployments" | while read -r deployment; do
            if [ -n "$deployment" ]; then
                log_info "  - $deployment"
                if [ "$DRY_RUN" = false ]; then
                    az deployment sub delete --name "$deployment" --no-wait 2>/dev/null || true
                fi
            fi
        done
    else
        log_info "No related deployments found"
    fi
}

cleanup_role_assignments() {
    log_info "Cleaning up role assignments..."
    
    # Get current user/service principal
    local current_user=$(az account show --query user.name --output tsv)
    
    # Note: We don't automatically clean up role assignments as they might be needed
    # This is just informational
    log_info "Current user: $current_user"
    log_info "Note: Role assignments are not automatically cleaned up"
    log_info "Review role assignments in Azure Portal if needed"
}

display_cleanup_summary() {
    echo
    echo -e "${GREEN}=============================================================="
    echo "  Cleanup Summary"
    echo "==============================================================${NC}"
    echo
    echo "Cleanup completed at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY RUN MODE - No resources were actually deleted${NC}"
    else
        echo -e "${GREEN}All specified resources have been deleted${NC}"
    fi
    echo
    echo -e "${BLUE}Log file saved to: $LOG_FILE${NC}"
    echo
    echo -e "${YELLOW}Additional cleanup notes:${NC}"
    echo "1. Check for any remaining soft-deleted Key Vaults"
    echo "2. Verify no unexpected charges in billing"
    echo "3. Review role assignments if needed"
    echo "4. Clean up local environment variables"
    echo
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
    print_banner
    
    # Trap to handle script interruption
    trap 'log_error "Script interrupted by user"' INT TERM
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -g|--resource-group)
                SPECIFIC_RESOURCE_GROUP="$2"
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Show dry run mode
    if [ "$DRY_RUN" = true ]; then
        log_info "Running in DRY RUN mode - no resources will be deleted"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Handle specific resource group
    if [ -n "${SPECIFIC_RESOURCE_GROUP:-}" ]; then
        log_info "Cleaning up specific resource group: $SPECIFIC_RESOURCE_GROUP"
        delete_resource_group "$SPECIFIC_RESOURCE_GROUP"
    else
        # Find and delete all recipe-related resource groups
        if find_resource_groups; then
            echo "$RECIPE_RESOURCE_GROUPS" | while read -r rg; do
                if [ -n "$rg" ]; then
                    delete_resource_group "$rg"
                fi
            done
        else
            log_warning "No recipe-related resource groups found"
            echo
            echo "To manually specify a resource group to delete, use:"
            echo "  $0 -g <resource-group-name>"
            echo
        fi
    fi
    
    # Additional cleanup tasks
    check_soft_deleted_key_vaults
    cleanup_deployments
    cleanup_role_assignments
    
    # Display summary
    display_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi