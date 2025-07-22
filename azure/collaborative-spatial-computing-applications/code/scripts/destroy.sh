#!/bin/bash

# Destroy script for Azure Spatial Computing Application
# This script safely removes all Azure resources created for the spatial computing demo
# including Remote Rendering, Spatial Anchors, storage, and service principal

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEPLOYMENT_INFO_FILE="$SCRIPT_DIR/deployment-info.env"
CONFIG_FILE="$SCRIPT_DIR/deployment-config.env"

# Default values
FORCE_DELETE=false
DRY_RUN=false
SKIP_CONFIRMATION=false
VERBOSE=false

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Azure Spatial Computing Application infrastructure

OPTIONS:
    -g, --resource-group    Resource group name to delete
    -f, --force            Force deletion without confirmation prompts
    -d, --dry-run          Show what would be deleted without making changes
    -y, --yes              Skip confirmation prompts (same as --force)
    -v, --verbose          Enable verbose logging
    -h, --help             Show this help message
    --keep-resource-group  Delete resources but keep the resource group
    --delete-sp-only       Delete only the service principal
    --delete-storage-only  Delete only storage resources

Examples:
    $0                                    # Interactive deletion with confirmations
    $0 -f                                # Force delete all resources
    $0 -g rg-spatialcomputing-abc123     # Delete specific resource group
    $0 --dry-run                         # Preview what would be deleted
    $0 --delete-sp-only                  # Delete only service principal
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force|-y|--yes)
            FORCE_DELETE=true
            SKIP_CONFIRMATION=true
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
            usage
            exit 0
            ;;
        --keep-resource-group)
            KEEP_RESOURCE_GROUP=true
            shift
            ;;
        --delete-sp-only)
            DELETE_SP_ONLY=true
            shift
            ;;
        --delete-storage-only)
            DELETE_STORAGE_ONLY=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Function to load deployment information
load_deployment_info() {
    if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
        log "Loading deployment information from $DEPLOYMENT_INFO_FILE"
        source "$DEPLOYMENT_INFO_FILE"
    elif [[ -f "$CONFIG_FILE" ]]; then
        log "Loading configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        if [[ -z "$RESOURCE_GROUP" ]]; then
            error "No deployment information found and no resource group specified."
            error "Please provide resource group name with -g option or ensure deployment-info.env exists."
            exit 1
        fi
        warn "No deployment information file found. Using provided resource group: $RESOURCE_GROUP"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    # Check if logged in
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi

    # Get current subscription info
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    info "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

    log "Prerequisites check completed"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    echo ""
    warn "⚠️  This will permanently delete the following resources:"
    echo "   • Resource Group: ${RESOURCE_GROUP:-'Not specified'}"
    echo "   • Remote Rendering Account: ${ARR_ACCOUNT_NAME:-'Not specified'}"
    echo "   • Spatial Anchors Account: ${ASA_ACCOUNT_NAME:-'Not specified'}"
    echo "   • Storage Account: ${STORAGE_ACCOUNT:-'Not specified'}"
    echo "   • Service Principal: ${SP_NAME:-'Not specified'}"
    echo "   • All configuration files and sample data"
    echo ""
    
    if [[ "$DELETE_SP_ONLY" == "true" ]]; then
        echo "Only the service principal will be deleted."
    elif [[ "$DELETE_STORAGE_ONLY" == "true" ]]; then
        echo "Only storage resources will be deleted."
    elif [[ "$KEEP_RESOURCE_GROUP" == "true" ]]; then
        echo "The resource group will be preserved."
    fi
    
    echo ""
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
}

# Function to check if resource group exists
check_resource_group_exists() {
    if [[ -z "$RESOURCE_GROUP" ]]; then
        error "Resource group name is not specified"
        return 1
    fi

    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        return 0
    else
        warn "Resource group '$RESOURCE_GROUP' does not exist"
        return 1
    fi
}

# Function to delete Remote Rendering account
delete_remote_rendering_account() {
    if [[ -z "$ARR_ACCOUNT_NAME" ]]; then
        warn "Remote Rendering account name not specified, skipping"
        return 0
    fi

    log "Deleting Remote Rendering account: $ARR_ACCOUNT_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would delete Remote Rendering account: $ARR_ACCOUNT_NAME"
        return 0
    fi

    if az mixed-reality remote-rendering-account show --name "$ARR_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az mixed-reality remote-rendering-account delete \
            --name "$ARR_ACCOUNT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        info "Remote Rendering account deleted successfully"
    else
        warn "Remote Rendering account '$ARR_ACCOUNT_NAME' not found, skipping"
    fi
}

# Function to delete Spatial Anchors account
delete_spatial_anchors_account() {
    if [[ -z "$ASA_ACCOUNT_NAME" ]]; then
        warn "Spatial Anchors account name not specified, skipping"
        return 0
    fi

    log "Deleting Spatial Anchors account: $ASA_ACCOUNT_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would delete Spatial Anchors account: $ASA_ACCOUNT_NAME"
        return 0
    fi

    if az mixed-reality spatial-anchors-account show --name "$ASA_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az mixed-reality spatial-anchors-account delete \
            --name "$ASA_ACCOUNT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        info "Spatial Anchors account deleted successfully"
    else
        warn "Spatial Anchors account '$ASA_ACCOUNT_NAME' not found, skipping"
    fi
}

# Function to delete storage account
delete_storage_account() {
    if [[ -z "$STORAGE_ACCOUNT" ]]; then
        warn "Storage account name not specified, skipping"
        return 0
    fi

    log "Deleting storage account: $STORAGE_ACCOUNT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would delete storage account: $STORAGE_ACCOUNT"
        return 0
    fi

    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        # First, try to delete all blobs in the container
        if [[ -n "$BLOB_CONTAINER" ]]; then
            log "Clearing blob container: $BLOB_CONTAINER"
            STORAGE_KEY=$(az storage account keys list \
                --resource-group "$RESOURCE_GROUP" \
                --account-name "$STORAGE_ACCOUNT" \
                --query '[0].value' -o tsv 2>/dev/null || echo "")
            
            if [[ -n "$STORAGE_KEY" ]]; then
                az storage blob delete-batch \
                    --account-name "$STORAGE_ACCOUNT" \
                    --account-key "$STORAGE_KEY" \
                    --source "$BLOB_CONTAINER" \
                    --delete-snapshots include 2>/dev/null || true
            fi
        fi

        # Delete the storage account
        az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        info "Storage account deleted successfully"
    else
        warn "Storage account '$STORAGE_ACCOUNT' not found, skipping"
    fi
}

# Function to delete service principal
delete_service_principal() {
    if [[ -z "$SP_NAME" && -z "$SP_CLIENT_ID" ]]; then
        warn "Service principal name/ID not specified, skipping"
        return 0
    fi

    log "Deleting service principal: ${SP_NAME:-$SP_CLIENT_ID}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would delete service principal: ${SP_NAME:-$SP_CLIENT_ID}"
        return 0
    fi

    # Try to delete by client ID first, then by name
    if [[ -n "$SP_CLIENT_ID" ]]; then
        if az ad sp show --id "$SP_CLIENT_ID" &> /dev/null; then
            az ad sp delete --id "$SP_CLIENT_ID"
            info "Service principal deleted successfully (by client ID)"
            return 0
        fi
    fi

    if [[ -n "$SP_NAME" ]]; then
        # Find service principal by display name
        SP_OBJECT_ID=$(az ad sp list --display-name "$SP_NAME" --query "[0].id" -o tsv 2>/dev/null)
        if [[ -n "$SP_OBJECT_ID" && "$SP_OBJECT_ID" != "null" ]]; then
            az ad sp delete --id "$SP_OBJECT_ID"
            info "Service principal deleted successfully (by name)"
        else
            warn "Service principal '$SP_NAME' not found, skipping"
        fi
    fi
}

# Function to delete local configuration files
delete_configuration_files() {
    log "Cleaning up local configuration files"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would delete configuration files"
        return 0
    fi

    # List of files and directories to clean up
    local cleanup_items=(
        "$PROJECT_ROOT/unity-spatial-app"
        "$PROJECT_ROOT/spatial-sync-config.json"
        "$PROJECT_ROOT/conversion-settings.json"
        "$SCRIPT_DIR/deployment-info.env"
        "$SCRIPT_DIR/deployment-config.env"
    )

    for item in "${cleanup_items[@]}"; do
        if [[ -f "$item" ]]; then
            rm -f "$item"
            info "Deleted file: $item"
        elif [[ -d "$item" ]]; then
            rm -rf "$item"
            info "Deleted directory: $item"
        fi
    done
}

# Function to delete resource group
delete_resource_group() {
    if [[ "$KEEP_RESOURCE_GROUP" == "true" ]]; then
        info "Keeping resource group as requested"
        return 0
    fi

    log "Deleting resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would delete resource group: $RESOURCE_GROUP"
        return 0
    fi

    if check_resource_group_exists; then
        # Check if resource group has any remaining resources
        REMAINING_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
        
        if [[ "$REMAINING_RESOURCES" -gt 0 ]]; then
            warn "Resource group contains $REMAINING_RESOURCES resources. Deleting anyway..."
        fi

        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        info "Resource group deletion initiated (running in background)"
    else
        warn "Resource group '$RESOURCE_GROUP' not found, skipping"
    fi
}

# Function to verify deletion
verify_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    log "Verifying resource deletion..."
    
    # Check if resource group still exists
    if [[ "$KEEP_RESOURCE_GROUP" != "true" ]]; then
        if check_resource_group_exists; then
            warn "Resource group still exists (deletion may be in progress)"
        else
            info "Resource group successfully deleted"
        fi
    fi

    # Check individual resources if keeping resource group
    if [[ "$KEEP_RESOURCE_GROUP" == "true" ]]; then
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
        
        if [[ "$remaining_resources" -eq 0 ]]; then
            info "All resources successfully deleted from resource group"
        else
            warn "$remaining_resources resources still exist in resource group"
        fi
    fi
}

# Function to display post-deletion summary
display_post_deletion_summary() {
    log "Deletion process completed"
    
    echo ""
    echo "=== Deletion Summary ==="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "🔍 DRY RUN - No actual resources were deleted"
    else
        echo "✅ Deletion process completed successfully"
    fi
    
    if [[ "$DELETE_SP_ONLY" == "true" ]]; then
        echo "🔐 Only service principal was deleted"
    elif [[ "$DELETE_STORAGE_ONLY" == "true" ]]; then
        echo "💾 Only storage resources were deleted"
    elif [[ "$KEEP_RESOURCE_GROUP" == "true" ]]; then
        echo "📦 Resource group was preserved"
    else
        echo "🗑️  All resources and resource group were deleted"
    fi
    
    echo ""
    echo "=== Deleted Resources ==="
    [[ -n "$RESOURCE_GROUP" ]] && echo "Resource Group: $RESOURCE_GROUP"
    [[ -n "$ARR_ACCOUNT_NAME" ]] && echo "Remote Rendering: $ARR_ACCOUNT_NAME"
    [[ -n "$ASA_ACCOUNT_NAME" ]] && echo "Spatial Anchors: $ASA_ACCOUNT_NAME"
    [[ -n "$STORAGE_ACCOUNT" ]] && echo "Storage Account: $STORAGE_ACCOUNT"
    [[ -n "$SP_NAME" ]] && echo "Service Principal: $SP_NAME"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        echo "=== Important Notes ==="
        echo "💡 Resource group deletion may take several minutes to complete"
        echo "💡 Some resources may have soft-delete enabled and can be recovered"
        echo "💡 Check Azure portal to confirm all resources are deleted"
        echo "💡 Review your Azure bill to ensure no unexpected charges"
    fi
    
    echo ""
}

# Main deletion function
main() {
    log "Starting Azure Spatial Computing Application cleanup"
    
    # Load deployment information
    load_deployment_info
    
    # Check prerequisites
    check_prerequisites
    
    # Confirm deletion
    confirm_deletion
    
    # Handle specific deletion modes
    if [[ "$DELETE_SP_ONLY" == "true" ]]; then
        delete_service_principal
    elif [[ "$DELETE_STORAGE_ONLY" == "true" ]]; then
        delete_storage_account
    else
        # Standard deletion process
        delete_remote_rendering_account
        delete_spatial_anchors_account
        delete_storage_account
        delete_service_principal
        delete_configuration_files
        
        # Delete resource group last (unless keeping it)
        if [[ "$KEEP_RESOURCE_GROUP" != "true" ]]; then
            delete_resource_group
        fi
    fi
    
    # Verify deletion
    verify_deletion
    
    # Display summary
    display_post_deletion_summary
}

# Trap to handle script interruption
trap 'error "Deletion process interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function
main "$@"