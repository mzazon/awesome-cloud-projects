#!/bin/bash

# =============================================================================
# Azure Bicep and Event Grid Infrastructure Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deployment script
# for the Azure Bicep and Event Grid recipe.
#
# Prerequisites:
# - Azure CLI v2.50.0 or later
# - Azure subscription with appropriate permissions
# - Resources created by the deploy.sh script
#
# Usage: ./destroy.sh [options]
# Options:
#   -f, --force       Skip confirmation prompts
#   -d, --dry-run     Show what would be deleted without executing
#   -v, --verbose     Enable verbose logging
#   -h, --help        Show this help message
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
FORCE=false
DRY_RUN=false
VERBOSE=false

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "DEBUG") [[ $VERBOSE == true ]] && echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

show_help() {
    cat << EOF
Azure Bicep and Event Grid Infrastructure Cleanup Script

Usage: $0 [options]

Options:
    -f, --force       Skip confirmation prompts
    -d, --dry-run     Show what would be deleted without executing
    -v, --verbose     Enable verbose logging
    -h, --help        Show this help message

Environment Variables:
    RESOURCE_GROUP    Name of the resource group to delete (auto-detected if not set)
    AZURE_LOCATION    Azure region (used for resource discovery)

Examples:
    $0                           # Interactive cleanup with confirmations
    $0 --force                   # Force cleanup without prompts
    $0 --dry-run                 # Show what would be deleted
    $0 --verbose                 # Enable verbose logging
    RESOURCE_GROUP=my-rg $0      # Delete specific resource group

Safety Features:
    - Confirmation prompts for destructive operations
    - Dry-run mode to preview deletions
    - Automatic resource discovery and validation
    - Graceful handling of missing resources
    - Detailed logging of all operations

EOF
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if running on supported OS
    if [[ "$OSTYPE" != "linux-gnu"* ]] && [[ "$OSTYPE" != "darwin"* ]]; then
        log "ERROR" "This script requires Linux or macOS"
        exit 1
    fi
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log "ERROR" "Azure CLI is not installed. Please install Azure CLI v2.50.0 or later."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    local min_version="2.50.0"
    if ! printf '%s\n%s\n' "$min_version" "$az_version" | sort -V -C; then
        log "ERROR" "Azure CLI version $az_version is too old. Minimum required: $min_version"
        exit 1
    fi
    
    log "INFO" "Prerequisites check passed ✅"
}

check_azure_login() {
    log "INFO" "Checking Azure authentication..."
    
    if ! az account show &> /dev/null; then
        log "ERROR" "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription info
    local subscription_id=$(az account show --query id -o tsv)
    local subscription_name=$(az account show --query name -o tsv)
    
    log "INFO" "Using Azure subscription: $subscription_name ($subscription_id)"
    
    log "INFO" "Azure authentication check passed ✅"
}

discover_resources() {
    log "INFO" "Discovering resources to delete..."
    
    # If RESOURCE_GROUP is not set, try to find it automatically
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log "INFO" "Auto-discovering resource groups..."
        
        # Look for resource groups with the recipe tags
        local discovered_groups=$(az group list \
            --query "[?tags.purpose=='recipe'].name" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -z "$discovered_groups" ]]; then
            log "ERROR" "No resource groups found with recipe tags. Please set RESOURCE_GROUP environment variable."
            exit 1
        fi
        
        # If multiple groups found, show them and exit
        local group_count=$(echo "$discovered_groups" | wc -l)
        if [[ $group_count -gt 1 ]]; then
            log "ERROR" "Multiple resource groups found:"
            echo "$discovered_groups"
            log "ERROR" "Please set RESOURCE_GROUP environment variable to specify which one to delete."
            exit 1
        fi
        
        export RESOURCE_GROUP="$discovered_groups"
        log "INFO" "Auto-discovered resource group: $RESOURCE_GROUP"
    fi
    
    # Verify resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "ERROR" "Resource group '$RESOURCE_GROUP' not found."
        exit 1
    fi
    
    # Get resource group location
    export AZURE_LOCATION=$(az group show \
        --name "$RESOURCE_GROUP" \
        --query location -o tsv)
    
    log "INFO" "Resource discovery completed ✅"
}

list_resources() {
    log "INFO" "Listing resources in resource group: $RESOURCE_GROUP"
    
    # Get all resources in the resource group
    local resources=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].{Name:name, Type:type, Location:location}" \
        --output table 2>/dev/null || echo "No resources found")
    
    if [[ "$resources" == "No resources found" ]]; then
        log "WARN" "No resources found in resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    echo ""
    echo "Resources to be deleted:"
    echo "======================="
    echo "$resources"
    echo ""
    
    # Count resources
    local resource_count=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "length(@)" -o tsv 2>/dev/null || echo "0")
    
    log "INFO" "Found $resource_count resources to delete"
}

confirm_deletion() {
    if [[ $FORCE == true ]]; then
        log "INFO" "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "Dry run mode - no resources will be deleted"
        return 0
    fi
    
    echo ""
    echo -e "${RED}WARNING: This action will permanently delete all resources in the resource group!${NC}"
    echo -e "${RED}This operation cannot be undone!${NC}"
    echo ""
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $AZURE_LOCATION"
    echo ""
    
    read -p "Are you sure you want to continue? (Type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "INFO" "Deletion cancelled by user"
        exit 0
    fi
    
    log "INFO" "Deletion confirmed by user"
}

delete_event_grid_subscriptions() {
    log "INFO" "Deleting Event Grid subscriptions..."
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "[DRY RUN] Would delete Event Grid subscriptions"
        return 0
    fi
    
    # Find Event Grid topics in the resource group
    local topics=$(az eventgrid topic list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$topics" ]]; then
        log "INFO" "No Event Grid topics found"
        return 0
    fi
    
    # Delete subscriptions for each topic
    while IFS= read -r topic_name; do
        if [[ -n "$topic_name" ]]; then
            log "INFO" "Deleting subscriptions for topic: $topic_name"
            
            # List and delete subscriptions
            local subscriptions=$(az eventgrid event-subscription list \
                --source-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventGrid/topics/$topic_name" \
                --query "[].name" -o tsv 2>/dev/null || echo "")
            
            while IFS= read -r subscription_name; do
                if [[ -n "$subscription_name" ]]; then
                    log "INFO" "Deleting subscription: $subscription_name"
                    az eventgrid event-subscription delete \
                        --name "$subscription_name" \
                        --source-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventGrid/topics/$topic_name" \
                        --only-show-errors || log "WARN" "Failed to delete subscription: $subscription_name"
                fi
            done <<< "$subscriptions"
        fi
    done <<< "$topics"
    
    log "INFO" "Event Grid subscriptions cleanup completed ✅"
}

delete_container_images() {
    log "INFO" "Deleting container images..."
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "[DRY RUN] Would delete container images"
        return 0
    fi
    
    # Find Container Registries in the resource group
    local registries=$(az acr list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$registries" ]]; then
        log "INFO" "No Container Registries found"
        return 0
    fi
    
    # Delete images from each registry
    while IFS= read -r registry_name; do
        if [[ -n "$registry_name" ]]; then
            log "INFO" "Cleaning up images in registry: $registry_name"
            
            # List and delete repositories
            local repositories=$(az acr repository list \
                --name "$registry_name" \
                --query "[]" -o tsv 2>/dev/null || echo "")
            
            while IFS= read -r repository_name; do
                if [[ -n "$repository_name" ]]; then
                    log "INFO" "Deleting repository: $repository_name"
                    az acr repository delete \
                        --name "$registry_name" \
                        --repository "$repository_name" \
                        --yes \
                        --only-show-errors || log "WARN" "Failed to delete repository: $repository_name"
                fi
            done <<< "$repositories"
        fi
    done <<< "$registries"
    
    log "INFO" "Container images cleanup completed ✅"
}

delete_storage_blobs() {
    log "INFO" "Deleting storage blobs..."
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "[DRY RUN] Would delete storage blobs"
        return 0
    fi
    
    # Find Storage Accounts in the resource group
    local storage_accounts=$(az storage account list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$storage_accounts" ]]; then
        log "INFO" "No Storage Accounts found"
        return 0
    fi
    
    # Delete blobs from each storage account
    while IFS= read -r storage_name; do
        if [[ -n "$storage_name" ]]; then
            log "INFO" "Cleaning up blobs in storage account: $storage_name"
            
            # List and delete containers
            local containers=$(az storage container list \
                --account-name "$storage_name" \
                --auth-mode login \
                --query "[].name" -o tsv 2>/dev/null || echo "")
            
            while IFS= read -r container_name; do
                if [[ -n "$container_name" ]]; then
                    log "INFO" "Deleting container: $container_name"
                    az storage container delete \
                        --name "$container_name" \
                        --account-name "$storage_name" \
                        --auth-mode login \
                        --only-show-errors || log "WARN" "Failed to delete container: $container_name"
                fi
            done <<< "$containers"
        fi
    done <<< "$storage_accounts"
    
    log "INFO" "Storage blobs cleanup completed ✅"
}

delete_function_apps() {
    log "INFO" "Stopping Function Apps..."
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "[DRY RUN] Would stop Function Apps"
        return 0
    fi
    
    # Find Function Apps in the resource group
    local function_apps=$(az functionapp list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$function_apps" ]]; then
        log "INFO" "No Function Apps found"
        return 0
    fi
    
    # Stop each Function App
    while IFS= read -r function_name; do
        if [[ -n "$function_name" ]]; then
            log "INFO" "Stopping Function App: $function_name"
            az functionapp stop \
                --name "$function_name" \
                --resource-group "$RESOURCE_GROUP" \
                --only-show-errors || log "WARN" "Failed to stop Function App: $function_name"
        fi
    done <<< "$function_apps"
    
    log "INFO" "Function Apps stopped ✅"
}

delete_resource_group() {
    log "INFO" "Deleting resource group: $RESOURCE_GROUP"
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    # Delete the resource group
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --only-show-errors
    
    log "INFO" "Resource group deletion initiated ✅"
    log "INFO" "Note: Deletion may take 5-10 minutes to complete"
}

verify_deletion() {
    log "INFO" "Verifying resource deletion..."
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "[DRY RUN] Would verify resource deletion"
        return 0
    fi
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "INFO" "Resource group still exists (deletion in progress)"
        
        # Wait for deletion to complete (max 10 minutes)
        local max_wait=600
        local wait_time=0
        
        while az group show --name "$RESOURCE_GROUP" &> /dev/null && [[ $wait_time -lt $max_wait ]]; do
            log "INFO" "Waiting for deletion to complete... ($wait_time/$max_wait seconds)"
            sleep 30
            wait_time=$((wait_time + 30))
        done
        
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log "WARN" "Resource group still exists after $max_wait seconds"
            log "WARN" "Deletion may still be in progress"
        else
            log "INFO" "Resource group deletion completed ✅"
        fi
    else
        log "INFO" "Resource group successfully deleted ✅"
    fi
}

cleanup_local_files() {
    log "INFO" "Cleaning up local files..."
    
    local files_to_clean=(
        "Dockerfile"
        "deploy.sh"
        "storage-account.bicep"
        "event-handler.json"
        "*.log"
    )
    
    for file_pattern in "${files_to_clean[@]}"; do
        if [[ $DRY_RUN == true ]]; then
            log "INFO" "[DRY RUN] Would remove: $file_pattern"
        else
            rm -f "$file_pattern" 2>/dev/null || true
        fi
    done
    
    log "INFO" "Local files cleanup completed ✅"
}

display_cleanup_summary() {
    log "INFO" "Cleanup Summary:"
    log "INFO" "================"
    log "INFO" "Resource Group: $RESOURCE_GROUP"
    log "INFO" "Location: $AZURE_LOCATION"
    log "INFO" ""
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "DRY RUN MODE - No resources were deleted"
    else
        log "INFO" "All resources have been deleted or scheduled for deletion"
        log "INFO" "Azure will complete the deletion process in the background"
    fi
    
    log "INFO" ""
    log "INFO" "You can verify deletion completion by running:"
    log "INFO" "az group show --name $RESOURCE_GROUP"
    log "INFO" "(This should return 'ResourceGroupNotFound' when complete)"
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "Cleanup started at $(date)" > "$LOG_FILE"
    
    log "INFO" "Starting Azure Bicep and Event Grid infrastructure cleanup..."
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "DRY RUN MODE - No resources will be deleted"
    fi
    
    # Execute cleanup steps
    check_prerequisites
    check_azure_login
    discover_resources
    list_resources
    confirm_deletion
    delete_event_grid_subscriptions
    delete_container_images
    delete_storage_blobs
    delete_function_apps
    delete_resource_group
    verify_deletion
    cleanup_local_files
    display_cleanup_summary
    
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "DRY RUN completed successfully"
    else
        log "INFO" "Cleanup completed successfully! 🎉"
    fi
}

# Handle script interruption
trap 'log "ERROR" "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"