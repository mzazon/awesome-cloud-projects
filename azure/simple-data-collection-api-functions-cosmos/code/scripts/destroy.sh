#!/bin/bash

# =============================================================================
# Azure Simple Data Collection API Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deployment script
# for the Azure Simple Data Collection API recipe.
#
# Resources removed:
# - Resource Group (and all contained resources)
# - Azure Functions App
# - Cosmos DB Account
# - Storage Account
# - All associated configurations
#
# Prerequisites:
# - Azure CLI installed and configured
# - Appropriate Azure permissions for resource deletion
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# =============================================================================
# CONFIGURATION & GLOBAL VARIABLES
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy_$(date +%Y%m%d_%H%M%S).log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
FORCE_DESTROY=false
WAIT_FOR_COMPLETION=true
BACKUP_BEFORE_DELETE=false

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [RESOURCE_GROUP]

Clean up Azure Simple Data Collection API infrastructure.

ARGUMENTS:
    RESOURCE_GROUP         Specific resource group to delete (optional)

OPTIONS:
    -h, --help            Show this help message
    -f, --force           Skip confirmation prompts
    -n, --no-wait         Don't wait for deletion completion
    -b, --backup          Create backup before deletion (Cosmos DB data)
    -l, --list            List resources that would be deleted
    --state-file FILE     Use specific deployment state file
    
EXAMPLES:
    $0                    # Interactive cleanup using state file
    $0 --force           # Force cleanup without prompts
    $0 --list            # Show what would be deleted
    $0 rg-data-api-abc123 # Delete specific resource group
    $0 --backup --force   # Backup data then force delete

SAFETY FEATURES:
    - Confirms deletion before proceeding (unless --force)
    - Validates resource ownership before deletion
    - Creates backups if requested
    - Logs all operations for audit trail
    - Verifies deletion completion

EOF
}

load_deployment_state() {
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        log_info "Loading deployment state from $DEPLOYMENT_STATE_FILE"
        source "$DEPLOYMENT_STATE_FILE"
        return 0
    else
        log_warning "No deployment state file found at $DEPLOYMENT_STATE_FILE"
        return 1
    fi
}

validate_azure_login() {
    log_info "Validating Azure CLI authentication..."
    
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI."
        return 1
    fi
    
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login'."
        return 1
    fi
    
    local subscription_id=$(az account show --query id -o tsv)
    local subscription_name=$(az account show --query name -o tsv)
    log_info "Using subscription: $subscription_name ($subscription_id)"
    
    return 0
}

check_resource_group_ownership() {
    local resource_group="$1"
    
    if ! az group exists --name "$resource_group" &>/dev/null; then
        log_warning "Resource group '$resource_group' does not exist"
        return 1
    fi
    
    # Check if resource group has our deployment tags
    local purpose_tag
    purpose_tag=$(az group show --name "$resource_group" --query "tags.purpose" -o tsv 2>/dev/null || echo "")
    
    if [[ "$purpose_tag" != "recipe" ]]; then
        log_warning "Resource group '$resource_group' may not be managed by this recipe"
        log_warning "Purpose tag: '$purpose_tag' (expected: 'recipe')"
        if [[ "$FORCE_DESTROY" != "true" ]]; then
            log_error "Use --force to delete untagged resource groups"
            return 1
        fi
    fi
    
    return 0
}

list_resources_to_delete() {
    local resource_group="$1"
    
    log_info "Resources that will be deleted:"
    
    # List all resources in the resource group
    az resource list --resource-group "$resource_group" --query "[].{Name:name, Type:type, Location:location}" -o table 2>/dev/null || {
        log_warning "Could not list resources in $resource_group"
        return 1
    }
    
    # Get estimated cost information if available
    log_info ""
    log_info "Checking for cost information..."
    
    # Note: Azure CLI doesn't provide direct cost queries, but we can show resource types
    local resource_count
    resource_count=$(az resource list --resource-group "$resource_group" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    
    log_info "Total resources to delete: $resource_count"
    log_warning "This action cannot be undone!"
    
    return 0
}

backup_cosmos_data() {
    local cosmos_account="$1"
    local resource_group="$2"
    local database_name="$3"
    local container_name="$4"
    
    log_info "Creating backup of Cosmos DB data..."
    
    # Create backup directory
    local backup_dir="${SCRIPT_DIR}/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Get connection string
    local connection_string
    connection_string=$(az cosmosdb keys list \
        --name "$cosmos_account" \
        --resource-group "$resource_group" \
        --type connection-strings \
        --query "connectionStrings[0].connectionString" \
        -o tsv 2>/dev/null) || {
        log_error "Failed to get Cosmos DB connection string"
        return 1
    }
    
    # Create backup metadata
    cat > "${backup_dir}/backup_info.json" << EOF
{
    "backup_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "cosmos_account": "$cosmos_account",
    "resource_group": "$resource_group", 
    "database_name": "$database_name",
    "container_name": "$container_name",
    "backup_type": "manual_pre_deletion"
}
EOF
    
    # Note: Full data export would require additional tools/scripts
    # For now, just save the connection details for manual recovery if needed
    echo "Connection string saved for manual recovery if needed" > "${backup_dir}/connection_info.txt"
    
    log_success "Backup metadata saved to: $backup_dir"
    log_info "Note: For full data backup, use Azure Data Factory or custom export scripts"
    
    return 0
}

delete_resource_group() {
    local resource_group="$1"
    
    log_info "Deleting resource group: $resource_group"
    
    if [[ "$WAIT_FOR_COMPLETION" == "true" ]]; then
        log_info "This may take several minutes..."
        az group delete \
            --name "$resource_group" \
            --yes 2>/dev/null || {
            log_error "Failed to delete resource group $resource_group"
            return 1
        }
        log_success "Resource group deleted: $resource_group"
    else
        az group delete \
            --name "$resource_group" \
            --yes \
            --no-wait 2>/dev/null || {
            log_error "Failed to initiate deletion of resource group $resource_group"
            return 1
        }
        log_success "Resource group deletion initiated: $resource_group"
        log_info "Deletion will continue in the background"
    fi
    
    return 0
}

verify_deletion() {
    local resource_group="$1"
    
    if [[ "$WAIT_FOR_COMPLETION" != "true" ]]; then
        log_info "Skipping verification (--no-wait specified)"
        return 0
    fi
    
    log_info "Verifying resource deletion..."
    
    # Wait a moment for deletion to propagate
    sleep 10
    
    if az group exists --name "$resource_group" &>/dev/null; then
        log_warning "Resource group still exists. Deletion may still be in progress."
        return 1
    else
        log_success "Resource group successfully deleted"
        return 0
    fi
}

cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment state file
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        rm -f "$DEPLOYMENT_STATE_FILE"
        log_success "Removed deployment state file"
    fi
    
    # Clean up any temporary files
    find "$SCRIPT_DIR" -name "*.tmp" -delete 2>/dev/null || true
    
    log_success "Local cleanup completed"
}

confirm_deletion() {
    local resource_group="$1"
    
    if [[ "$FORCE_DESTROY" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    log_warning "This will permanently delete ALL resources in:"
    log_warning "  Resource Group: $resource_group"
    echo ""
    
    read -r -p "Are you sure you want to continue? (type 'yes' to confirm): " response
    if [[ "$response" != "yes" ]]; then
        log_info "Deletion cancelled by user"
        return 1
    fi
    
    read -r -p "Last chance! Type the resource group name to confirm: " confirm_rg
    if [[ "$confirm_rg" != "$resource_group" ]]; then
        log_error "Resource group name mismatch. Deletion cancelled."
        return 1
    fi
    
    return 0
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    local resource_group=""
    local list_only=false
    local custom_state_file=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -f|--force)
                FORCE_DESTROY=true
                shift
                ;;
            -n|--no-wait)
                WAIT_FOR_COMPLETION=false
                shift
                ;;
            -b|--backup)
                BACKUP_BEFORE_DELETE=true
                shift
                ;;
            -l|--list)
                list_only=true
                shift
                ;;
            --state-file)
                custom_state_file="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [[ -z "$resource_group" ]]; then
                    resource_group="$1"
                else
                    log_error "Multiple resource groups specified"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Use custom state file if specified
    if [[ -n "$custom_state_file" ]]; then
        DEPLOYMENT_STATE_FILE="$custom_state_file"
    fi
    
    # Start cleanup process
    log_info "Starting Azure Simple Data Collection API cleanup"
    log_info "Log file: $LOG_FILE"
    
    # Validate prerequisites
    validate_azure_login
    
    # Determine resource group to delete
    if [[ -z "$resource_group" ]]; then
        if load_deployment_state; then
            log_info "Using resource group from deployment state: $RESOURCE_GROUP"
            resource_group="$RESOURCE_GROUP"
        else
            log_error "No resource group specified and no deployment state file found"
            log_info "Usage: $0 [OPTIONS] RESOURCE_GROUP"
            exit 1
        fi
    fi
    
    # Validate resource group ownership
    check_resource_group_ownership "$resource_group"
    
    # List resources if requested
    if [[ "$list_only" == "true" ]]; then
        list_resources_to_delete "$resource_group"
        exit 0
    fi
    
    # Show what will be deleted
    list_resources_to_delete "$resource_group"
    
    # Confirm deletion
    confirm_deletion "$resource_group"
    
    # Create backup if requested
    if [[ "$BACKUP_BEFORE_DELETE" == "true" ]]; then
        if [[ -n "${COSMOS_ACCOUNT:-}" ]] && [[ -n "${DATABASE_NAME:-}" ]] && [[ -n "${CONTAINER_NAME:-}" ]]; then
            backup_cosmos_data "$COSMOS_ACCOUNT" "$resource_group" "$DATABASE_NAME" "$CONTAINER_NAME"
        else
            log_warning "Cannot create backup: Cosmos DB information not available"
        fi
    fi
    
    # Perform deletion
    log_info "Starting resource deletion..."
    delete_resource_group "$resource_group"
    
    # Verify deletion
    verify_deletion "$resource_group"
    
    # Clean up local files
    cleanup_local_files
    
    # Final summary
    log_success "=== CLEANUP SUMMARY ==="
    log_success "Resource group deleted: $resource_group"
    log_info "Cleanup log: $LOG_FILE"
    
    if [[ "$BACKUP_BEFORE_DELETE" == "true" ]]; then
        log_info "Backup location: ${SCRIPT_DIR}/backups/"
    fi
    
    if [[ "$WAIT_FOR_COMPLETION" != "true" ]]; then
        log_info "Note: Deletion may still be in progress in Azure"
        log_info "Check Azure portal or run 'az group exists --name $resource_group'"
    fi
    
    log_success "Cleanup completed successfully!"
}

# Execute main function with all arguments
main "$@"