#!/bin/bash

# Azure Simple Configuration Management Cleanup Script
# This script removes all resources created by the deployment script
# Recipe: Simple Configuration Management with App Configuration and App Service

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

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

# Help function
show_help() {
    cat << EOF
Azure Simple Configuration Management Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -r, --resource-group    Resource group name to delete (required if not using --auto-discover)
    -a, --auto-discover     Automatically discover and list resource groups with recipe tags
    -f, --force             Skip confirmation prompts (dangerous!)
    --dry-run               Show what would be deleted without actually deleting
    --keep-rg               Keep the resource group, only delete resources within it
    --cleanup-local         Clean up local application directories

EXAMPLES:
    $0 -r "rg-config-demo-abc123"          # Delete specific resource group
    $0 -a                                  # Auto-discover and select from recipe resource groups
    $0 -r "my-rg" --keep-rg               # Delete resources but keep resource group
    $0 --dry-run -r "my-rg"               # Preview what would be deleted
    $0 -f -r "my-rg"                      # Force delete without confirmation

DESCRIPTION:
    This script safely removes all resources created by the configuration management
    deployment script, including:
    - Azure App Service and App Service Plan
    - Azure App Configuration store
    - Resource Group (unless --keep-rg is specified)
    - Local application files (if --cleanup-local is specified)
    - Role assignments and managed identities

    The script includes safety checks and confirmation prompts to prevent
    accidental deletion of resources.

SAFETY FEATURES:
    - Confirmation prompts before deletion (unless --force is used)
    - Dry-run mode to preview deletions
    - Auto-discovery of recipe-tagged resources
    - Graceful handling of already-deleted resources
    - Detailed logging of all operations
EOF
}

# Default values
RESOURCE_GROUP=""
AUTO_DISCOVER=false
FORCE=false
DRY_RUN=false
KEEP_RG=false
CLEANUP_LOCAL=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -a|--auto-discover)
            AUTO_DISCOVER=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --keep-rg)
            KEEP_RG=true
            shift
            ;;
        --cleanup-local)
            CLEANUP_LOCAL=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites met"
}

# Function to auto-discover resource groups
auto_discover_resource_groups() {
    log_info "Auto-discovering resource groups with recipe tags..."
    
    # Find resource groups with recipe tags
    local rg_list
    rg_list=$(az group list \
        --tag purpose=recipe \
        --query "[?tags.purpose=='recipe' && contains(name, 'config-demo')].{Name:name,Location:location,Tags:tags}" \
        --output json 2>/dev/null || echo "[]")
    
    if [[ "$rg_list" == "[]" || -z "$rg_list" ]]; then
        log_warning "No resource groups found with recipe tags matching 'config-demo'"
        echo ""
        log_info "You can specify a resource group manually with: $0 -r <resource-group-name>"
        exit 1
    fi
    
    # Display discovered resource groups
    log_info "Found the following recipe resource groups:"
    echo ""
    echo "$rg_list" | jq -r '.[] | "  \(.Name) (Location: \(.Location))"'
    echo ""
    
    # Prompt user to select resource group
    read -p "Enter the resource group name to delete: " selected_rg
    
    # Validate selection
    if echo "$rg_list" | jq -e --arg name "$selected_rg" '.[] | select(.Name == $name)' > /dev/null; then
        RESOURCE_GROUP="$selected_rg"
        log_success "Selected resource group: $RESOURCE_GROUP"
    else
        log_error "Invalid resource group selection: $selected_rg"
        exit 1
    fi
}

# Function to validate resource group
validate_resource_group() {
    if [[ -z "$RESOURCE_GROUP" ]]; then
        if [[ "$AUTO_DISCOVER" == true ]]; then
            auto_discover_resource_groups
        else
            log_error "Resource group name is required. Use -r <resource-group> or -a for auto-discovery."
            echo "Use --help for usage information."
            exit 1
        fi
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Resource group '$RESOURCE_GROUP' does not exist"
        exit 1
    fi
    
    log_info "Validated resource group: $RESOURCE_GROUP"
}

# Function to discover resources in resource group
discover_resources() {
    log_info "Discovering resources in resource group: $RESOURCE_GROUP"
    
    # Get all resources in the resource group
    local resources
    resources=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].{Name:name,Type:type,Location:location}" \
        --output json)
    
    if [[ "$resources" == "[]" ]]; then
        log_warning "No resources found in resource group: $RESOURCE_GROUP"
        return
    fi
    
    log_info "Found the following resources:"
    echo "$resources" | jq -r '.[] | "  \(.Name) (\(.Type))"'
    
    # Store resource info for later use
    export DISCOVERED_RESOURCES="$resources"
}

# Function to get confirmation from user
get_confirmation() {
    if [[ "$FORCE" == true ]]; then
        log_warning "Force mode enabled - skipping confirmation prompts"
        return 0
    fi
    
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "This will permanently delete the following:"
    echo "  - Resource Group: $RESOURCE_GROUP"
    if [[ "$KEEP_RG" == true ]]; then
        echo "    (Resource group will be kept, only resources inside will be deleted)"
    fi
    echo "  - All resources within the resource group"
    echo "  - All data and configurations"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    log_warning "Confirmed. Proceeding with deletion..."
}

# Function to delete App Service resources
delete_app_service_resources() {
    log_info "Deleting App Service resources..."
    
    # Find App Service apps in the resource group
    local webapps
    webapps=$(az webapp list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || true)
    
    if [[ -n "$webapps" ]]; then
        while IFS= read -r webapp; do
            if [[ -n "$webapp" ]]; then
                log_info "Deleting Web App: $webapp"
                
                if [[ "$DRY_RUN" == true ]]; then
                    log_info "[DRY RUN] Would delete Web App: $webapp"
                else
                    # Delete web app (this also removes managed identity and role assignments)
                    if az webapp delete \
                        --name "$webapp" \
                        --resource-group "$RESOURCE_GROUP" \
                        --output none 2>/dev/null; then
                        log_success "Deleted Web App: $webapp"
                    else
                        log_warning "Failed to delete Web App: $webapp (may not exist)"
                    fi
                fi
            fi
        done <<< "$webapps"
    fi
    
    # Find App Service plans in the resource group
    local plans
    plans=$(az appservice plan list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || true)
    
    if [[ -n "$plans" ]]; then
        while IFS= read -r plan; do
            if [[ -n "$plan" ]]; then
                log_info "Deleting App Service Plan: $plan"
                
                if [[ "$DRY_RUN" == true ]]; then
                    log_info "[DRY RUN] Would delete App Service Plan: $plan"
                else
                    if az appservice plan delete \
                        --name "$plan" \
                        --resource-group "$RESOURCE_GROUP" \
                        --yes \
                        --output none 2>/dev/null; then
                        log_success "Deleted App Service Plan: $plan"
                    else
                        log_warning "Failed to delete App Service Plan: $plan (may not exist)"
                    fi
                fi
            fi
        done <<< "$plans"
    fi
}

# Function to delete App Configuration resources
delete_app_configuration_resources() {
    log_info "Deleting App Configuration resources..."
    
    # Find App Configuration stores in the resource group
    local appconfigs
    appconfigs=$(az appconfig list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || true)
    
    if [[ -n "$appconfigs" ]]; then
        while IFS= read -r appconfig; do
            if [[ -n "$appconfig" ]]; then
                log_info "Deleting App Configuration: $appconfig"
                
                if [[ "$DRY_RUN" == true ]]; then
                    log_info "[DRY RUN] Would delete App Configuration: $appconfig"
                else
                    if az appconfig delete \
                        --name "$appconfig" \
                        --resource-group "$RESOURCE_GROUP" \
                        --yes \
                        --output none 2>/dev/null; then
                        log_success "Deleted App Configuration: $appconfig"
                    else
                        log_warning "Failed to delete App Configuration: $appconfig (may not exist)"
                    fi
                fi
            fi
        done <<< "$appconfigs"
    fi
}

# Function to clean up role assignments
cleanup_role_assignments() {
    log_info "Cleaning up role assignments..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would clean up role assignments"
        return
    fi
    
    # Find and delete role assignments related to the resource group
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    local scope="/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}"
    
    # List role assignments for the resource group scope
    local assignments
    assignments=$(az role assignment list \
        --scope "$scope" \
        --query "[].{principalId:principalId,roleDefinitionName:roleDefinitionName}" \
        --output json 2>/dev/null || echo "[]")
    
    if [[ "$assignments" != "[]" ]] && [[ -n "$assignments" ]]; then
        log_info "Found role assignments to clean up"
        echo "$assignments" | jq -r '.[] | "  Principal: \(.principalId), Role: \(.roleDefinitionName)"'
        
        # Delete role assignments
        az role assignment delete --scope "$scope" --output none 2>/dev/null || true
        log_success "Cleaned up role assignments"
    fi
}

# Function to delete resource group
delete_resource_group() {
    if [[ "$KEEP_RG" == true ]]; then
        log_info "Keeping resource group as requested (--keep-rg flag)"
        return
    fi
    
    log_info "Deleting resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return
    fi
    
    # Delete the resource group (this will delete all remaining resources)
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none
    
    log_success "Initiated deletion of resource group: $RESOURCE_GROUP"
    log_info "Deletion is running in the background and may take several minutes to complete"
}

# Function to clean up local files
cleanup_local_files() {
    if [[ "$CLEANUP_LOCAL" == false ]]; then
        return
    fi
    
    log_info "Cleaning up local application files..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would clean up local files matching pattern: config-demo-app-*"
        return
    fi
    
    # Find and remove local application directories
    local app_dirs
    app_dirs=$(find . -maxdepth 1 -type d -name "config-demo-app-*" 2>/dev/null || true)
    
    if [[ -n "$app_dirs" ]]; then
        while IFS= read -r dir; do
            if [[ -n "$dir" && -d "$dir" ]]; then
                log_info "Removing local directory: $dir"
                rm -rf "$dir"
                log_success "Removed: $dir"
            fi
        done <<< "$app_dirs"
    else
        log_info "No local application directories found to clean up"
    fi
    
    # Clean up any deployment zip files
    local zip_files
    zip_files=$(find . -maxdepth 1 -name "deploy*.zip" 2>/dev/null || true)
    
    if [[ -n "$zip_files" ]]; then
        while IFS= read -r zipfile; do
            if [[ -n "$zipfile" && -f "$zipfile" ]]; then
                log_info "Removing deployment zip: $zipfile"
                rm -f "$zipfile"
                log_success "Removed: $zipfile"
            fi
        done <<< "$zip_files"
    fi
}

# Function to verify deletion
verify_deletion() {
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Verification skipped in dry-run mode"
        return
    fi
    
    log_info "Verifying deletion..."
    
    if [[ "$KEEP_RG" == true ]]; then
        # Check if resources are gone from the resource group
        local remaining_resources
        remaining_resources=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query "length(@)" \
            --output tsv 2>/dev/null || echo "0")
        
        if [[ "$remaining_resources" == "0" ]]; then
            log_success "All resources deleted from resource group: $RESOURCE_GROUP"
        else
            log_warning "$remaining_resources resources still remain in resource group"
        fi
    else
        # Check if resource group is gone
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log_warning "Resource group still exists (deletion may be in progress)"
        else
            log_success "Resource group deleted: $RESOURCE_GROUP"
        fi
    fi
}

# Function to display cleanup summary
show_summary() {
    log_info "Cleanup Summary"
    echo "======================================"
    echo "Resource Group: $RESOURCE_GROUP"
    if [[ "$KEEP_RG" == true ]]; then
        echo "Action: Resources deleted, resource group kept"
    else
        echo "Action: Complete resource group deletion"
    fi
    echo "Dry Run: $DRY_RUN"
    echo "Local Cleanup: $CLEANUP_LOCAL"
    echo "======================================"
    
    if [[ "$DRY_RUN" == false ]]; then
        log_success "Cleanup completed!"
        
        if [[ "$KEEP_RG" == false ]]; then
            echo ""
            log_info "Note: Resource group deletion may take several minutes to complete."
            log_info "You can check the status in the Azure portal or with:"
            echo "  az group show --name $RESOURCE_GROUP"
        fi
    else
        log_info "Dry run completed. No resources were actually deleted."
    fi
}

# Function to handle cleanup on script interruption
cleanup_on_interrupt() {
    log_warning "Script interrupted. No partial cleanup performed."
    exit 130
}

# Main execution function
main() {
    # Set up interrupt handler
    trap cleanup_on_interrupt INT TERM
    
    log_info "Starting Azure Simple Configuration Management cleanup"
    
    # Execute cleanup steps
    check_prerequisites
    validate_resource_group
    discover_resources
    get_confirmation
    
    # Start actual cleanup
    delete_app_service_resources
    delete_app_configuration_resources
    cleanup_role_assignments
    cleanup_local_files
    delete_resource_group
    
    # Verify and summarize
    verify_deletion
    show_summary
}

# Execute main function
main "$@"