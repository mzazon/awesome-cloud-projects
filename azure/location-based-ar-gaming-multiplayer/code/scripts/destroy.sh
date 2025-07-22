#!/bin/bash

# Destroy Azure PlayFab and Spatial Anchors Gaming Infrastructure
# This script safely removes all Azure resources created by the deployment

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running in debug mode
DEBUG=${DEBUG:-false}
if [[ "$DEBUG" == "true" ]]; then
    set -x
fi

# Configuration variables
FORCE=${FORCE:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}
RESOURCE_GROUP=""
PRESERVE_LOGS=${PRESERVE_LOGS:-false}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first"
    fi
    
    success "Prerequisites check completed"
}

# Discover resources to clean up
discover_resources() {
    log "Discovering resources to clean up..."
    
    # Try to read resource group from file
    if [[ -f ".resource_group_name" ]]; then
        RESOURCE_GROUP=$(cat .resource_group_name)
        log "Found resource group from deployment file: $RESOURCE_GROUP"
    fi
    
    # If not found, try to find by pattern
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log "Searching for AR Gaming resource groups..."
        local rg_list=$(az group list --query "[?starts_with(name, 'rg-ar-gaming-')].name" --output tsv)
        
        if [[ -n "$rg_list" ]]; then
            echo "Found the following AR Gaming resource groups:"
            echo "$rg_list"
            echo ""
            read -p "Enter the resource group name to delete: " RESOURCE_GROUP
        else
            error "No AR Gaming resource groups found. Please specify the resource group name with -g option"
        fi
    fi
    
    # Validate resource group exists
    if ! az group exists --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group '$RESOURCE_GROUP' does not exist"
    fi
    
    success "Target resource group: $RESOURCE_GROUP"
}

# List resources that will be deleted
list_resources() {
    log "Listing resources in resource group: $RESOURCE_GROUP"
    
    local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name,Type:type,Location:location}" --output table)
    
    if [[ -n "$resources" ]]; then
        echo "$resources"
        echo ""
        local resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv)
        warning "Found $resource_count resources that will be deleted"
    else
        warning "No resources found in resource group: $RESOURCE_GROUP"
    fi
}

# Get user confirmation
get_confirmation() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        log "Skipping confirmation due to SKIP_CONFIRMATION flag"
        return 0
    fi
    
    echo ""
    echo -e "${RED}WARNING: This action will permanently delete all resources in the resource group!${NC}"
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    
    if [[ "$FORCE" == "true" ]]; then
        warning "Force flag is set. Proceeding with deletion..."
        return 0
    fi
    
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    case "$confirmation" in
        yes|YES|y|Y)
            log "Proceeding with deletion..."
            ;;
        *)
            log "Deletion cancelled by user"
            exit 0
            ;;
    esac
}

# Backup configuration before deletion
backup_configuration() {
    if [[ "$PRESERVE_LOGS" == "true" ]]; then
        log "Creating backup of configuration files..."
        
        local backup_dir="backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        
        # Backup configuration files if they exist
        for config_file in unity-config.json lobby-config.json multiplayer-settings.json; do
            if [[ -f "$config_file" ]]; then
                cp "$config_file" "$backup_dir/"
                log "Backed up: $config_file"
            fi
        done
        
        # Backup resource group info
        az group show --name "$RESOURCE_GROUP" > "$backup_dir/resource-group-info.json" 2>/dev/null || true
        
        success "Configuration backed up to: $backup_dir"
    fi
}

# Remove Event Grid subscriptions
remove_event_grid() {
    log "Removing Event Grid subscriptions..."
    
    # Find and remove event subscriptions
    local subscriptions=$(az eventgrid event-subscription list --query "[?contains(name, 'spatial-anchor-events')].name" --output tsv)
    
    for subscription in $subscriptions; do
        log "Removing Event Grid subscription: $subscription"
        az eventgrid event-subscription delete --name "$subscription" --output none || {
            warning "Failed to remove Event Grid subscription: $subscription"
        }
    done
    
    success "Event Grid subscriptions removed"
}

# Remove Azure AD applications
remove_ad_applications() {
    log "Removing Azure AD applications..."
    
    # Find AD applications with AR Gaming prefix
    local ad_apps=$(az ad app list --display-name "ARGaming-MR-" --query "[].{appId:appId,displayName:displayName}" --output tsv)
    
    if [[ -n "$ad_apps" ]]; then
        while IFS=$'\t' read -r app_id display_name; do
            if [[ -n "$app_id" ]]; then
                log "Removing Azure AD application: $display_name ($app_id)"
                az ad app delete --id "$app_id" --output none || {
                    warning "Failed to remove Azure AD application: $display_name"
                }
            fi
        done <<< "$ad_apps"
    else
        log "No Azure AD applications found to remove"
    fi
    
    success "Azure AD applications removed"
}

# Remove Function App and related resources
remove_function_app() {
    log "Removing Function App resources..."
    
    # Find Function Apps in the resource group
    local function_apps=$(az functionapp list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    for func_app in $function_apps; do
        log "Removing Function App: $func_app"
        
        # Stop the function app first
        az functionapp stop --name "$func_app" --resource-group "$RESOURCE_GROUP" --output none || {
            warning "Failed to stop Function App: $func_app"
        }
        
        # Delete the function app
        az functionapp delete --name "$func_app" --resource-group "$RESOURCE_GROUP" --output none || {
            warning "Failed to delete Function App: $func_app"
        }
    done
    
    success "Function App resources removed"
}

# Remove Spatial Anchors accounts
remove_spatial_anchors() {
    log "Removing Spatial Anchors accounts..."
    
    # Find Spatial Anchors accounts in the resource group
    local sa_accounts=$(az spatialanchors-account list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    for sa_account in $sa_accounts; do
        log "Removing Spatial Anchors account: $sa_account"
        az spatialanchors-account delete --name "$sa_account" --resource-group "$RESOURCE_GROUP" --output none || {
            warning "Failed to remove Spatial Anchors account: $sa_account"
        }
    done
    
    success "Spatial Anchors accounts removed"
}

# Remove storage accounts
remove_storage_accounts() {
    log "Removing storage accounts..."
    
    # Find storage accounts in the resource group
    local storage_accounts=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    for storage_account in $storage_accounts; do
        log "Removing storage account: $storage_account"
        az storage account delete --name "$storage_account" --resource-group "$RESOURCE_GROUP" --yes --output none || {
            warning "Failed to remove storage account: $storage_account"
        }
    done
    
    success "Storage accounts removed"
}

# Remove role assignments
remove_role_assignments() {
    log "Removing role assignments..."
    
    # Get subscription ID
    local subscription_id=$(az account show --query id --output tsv)
    
    # Find role assignments for the resource group
    local role_assignments=$(az role assignment list --scope "/subscriptions/$subscription_id/resourceGroups/$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    for assignment in $role_assignments; do
        log "Removing role assignment: $assignment"
        az role assignment delete --ids "$assignment" --output none || {
            warning "Failed to remove role assignment: $assignment"
        }
    done
    
    success "Role assignments removed"
}

# Remove resource group
remove_resource_group() {
    log "Removing resource group: $RESOURCE_GROUP"
    
    # Double check before deletion
    if [[ "$SKIP_CONFIRMATION" != "true" && "$FORCE" != "true" ]]; then
        echo ""
        echo -e "${RED}FINAL WARNING: About to delete resource group '$RESOURCE_GROUP'${NC}"
        read -p "Type 'DELETE' to confirm: " final_confirmation
        if [[ "$final_confirmation" != "DELETE" ]]; then
            log "Deletion cancelled by user"
            exit 0
        fi
    fi
    
    # Delete the resource group
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait --output none
    
    success "Resource group deletion initiated: $RESOURCE_GROUP"
    log "Note: Resource group deletion may take several minutes to complete"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment tracking files
    local files_to_remove=(
        ".resource_group_name"
        "unity-config.json"
        "lobby-config.json"
        "multiplayer-settings.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$PRESERVE_LOGS" == "true" ]]; then
                log "Preserving file: $file"
            else
                rm -f "$file"
                log "Removed file: $file"
            fi
        fi
    done
    
    success "Local files cleanup completed"
}

# Monitor resource group deletion
monitor_deletion() {
    log "Monitoring resource group deletion..."
    
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if ! az group exists --name "$RESOURCE_GROUP" &> /dev/null; then
            success "Resource group '$RESOURCE_GROUP' has been completely deleted"
            return 0
        fi
        
        log "Deletion in progress... (attempt $((attempt + 1))/$max_attempts)"
        sleep 30
        ((attempt++))
    done
    
    warning "Resource group deletion is taking longer than expected"
    log "You can check the status manually with: az group show --name '$RESOURCE_GROUP'"
}

# Display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "=================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Status: Deletion initiated"
    echo ""
    echo "Cleaned up resources:"
    echo "- Event Grid subscriptions"
    echo "- Azure AD applications"
    echo "- Function Apps"
    echo "- Spatial Anchors accounts"
    echo "- Storage accounts"
    echo "- Role assignments"
    echo "- Resource group"
    echo ""
    if [[ "$PRESERVE_LOGS" == "true" ]]; then
        echo "Configuration files have been backed up"
    else
        echo "Local configuration files have been removed"
    fi
    echo ""
    success "Cleanup completed successfully!"
}

# Error handling
handle_error() {
    error "An error occurred during cleanup. Some resources may still exist."
    echo "You can:"
    echo "1. Run the script again with -f flag to force cleanup"
    echo "2. Manually delete the resource group: az group delete --name '$RESOURCE_GROUP'"
    echo "3. Check for remaining resources: az resource list --resource-group '$RESOURCE_GROUP'"
    exit 1
}

# Set up error handling
trap handle_error ERR

# Main execution
main() {
    log "Starting Azure PlayFab and Spatial Anchors cleanup..."
    
    check_prerequisites
    discover_resources
    list_resources
    get_confirmation
    backup_configuration
    
    # Remove resources in reverse order of creation
    remove_event_grid
    remove_ad_applications
    remove_function_app
    remove_spatial_anchors
    remove_storage_accounts
    remove_role_assignments
    remove_resource_group
    
    cleanup_local_files
    
    if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
        monitor_deletion
    fi
    
    display_summary
    
    log "Cleanup process completed successfully!"
}

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Destroy Azure PlayFab and Spatial Anchors Gaming Infrastructure"
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help                Show this help message"
    echo "  -g, --resource-group RG   Specify resource group name"
    echo "  -f, --force               Force deletion without confirmation"
    echo "  -s, --skip-confirmation   Skip all confirmation prompts"
    echo "  -p, --preserve-logs       Preserve configuration files and logs"
    echo "  -d, --debug               Enable debug mode"
    echo ""
    echo "ENVIRONMENT VARIABLES:"
    echo "  FORCE                     Force deletion (true/false)"
    echo "  SKIP_CONFIRMATION         Skip confirmations (true/false)"
    echo "  PRESERVE_LOGS             Preserve logs and config (true/false)"
    echo "  DEBUG                     Enable debug output (true/false)"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                        Interactive cleanup"
    echo "  $0 -g rg-ar-gaming-abc123 Clean up specific resource group"
    echo "  $0 -f                     Force cleanup without confirmation"
    echo "  $0 -p                     Preserve configuration files"
    echo ""
    echo "SAFETY FEATURES:"
    echo "  - Double confirmation for destructive actions"
    echo "  - Backup configuration files before deletion"
    echo "  - Graceful handling of missing resources"
    echo "  - Detailed logging of all operations"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -s|--skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -p|--preserve-logs)
            PRESERVE_LOGS=true
            shift
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main "$@"