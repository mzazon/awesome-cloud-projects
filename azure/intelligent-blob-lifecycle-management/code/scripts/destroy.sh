#!/bin/bash

# Azure Blob Storage Lifecycle Management - Cleanup Script
# This script removes all resources created for the blob storage lifecycle management demo

set -e
set -u
set -o pipefail

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/azure-lifecycle-destroy-$(date +%Y%m%d-%H%M%S).log"
readonly BLUE='\033[0;34m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color

# Configuration with defaults
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-lifecycle-demo}"
FORCE_DELETE="${FORCE_DELETE:-false}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# Functions
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Remove Azure Blob Storage Lifecycle Management infrastructure.

Options:
    -g, --resource-group NAME    Resource group name (default: rg-lifecycle-demo)
    -f, --force                  Force deletion without confirmation prompts
    -y, --yes                    Skip confirmation prompts
    --dry-run                    Show what would be deleted without removing resources
    -h, --help                   Show this help message

Environment Variables:
    RESOURCE_GROUP              Resource group name
    FORCE_DELETE                Force deletion without confirmation (true/false)
    DRY_RUN                     Enable dry run mode (true/false)
    SKIP_CONFIRMATION           Skip confirmation prompts (true/false)

Examples:
    $0                                              # Interactive cleanup with prompts
    $0 -g my-rg                                    # Clean up specific resource group
    $0 --dry-run                                   # Show what would be deleted
    $0 -f                                          # Force delete without prompts
    $0 -y                                          # Skip confirmation prompts

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://aka.ms/installazurecli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription info
    local subscription_name
    local subscription_id
    subscription_name=$(az account show --query name -o tsv)
    subscription_id=$(az account show --query id -o tsv)
    log_info "Current subscription: $subscription_name ($subscription_id)"
    
    log_success "Prerequisites check completed successfully"
}

validate_parameters() {
    log_info "Validating parameters..."
    
    # Validate resource group name
    if [[ ! "$RESOURCE_GROUP" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_error "Invalid resource group name. Must contain only alphanumeric characters, periods, underscores, and hyphens."
        exit 1
    fi
    
    log_success "Parameter validation completed successfully"
}

check_resource_group_exists() {
    log_info "Checking if resource group exists..."
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' does not exist"
        return 1
    fi
    
    log_info "Resource group '$RESOURCE_GROUP' found"
    return 0
}

list_resources() {
    log_info "Listing resources in resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would list resources in resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    local resources
    resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].{Name:name,Type:type,Location:location}' --output table)
    
    if [[ -z "$resources" ]]; then
        log_warning "No resources found in resource group '$RESOURCE_GROUP'"
        return 1
    fi
    
    echo "$resources"
    return 0
}

get_resource_count() {
    local count
    count=$(az resource list --resource-group "$RESOURCE_GROUP" --query 'length(@)' --output tsv 2>/dev/null || echo "0")
    echo "$count"
}

confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]] || [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    local resource_count
    resource_count=$(get_resource_count)
    
    log_warning "This will permanently delete the following:"
    log_warning "- Resource group: $RESOURCE_GROUP"
    log_warning "- All $resource_count resources within the resource group"
    log_warning "- All data stored in the storage account"
    log_warning "- All monitoring data and alerts"
    
    echo
    read -p "Are you sure you want to proceed? (Type 'yes' to confirm): " -r
    echo
    
    if [[ ! "$REPLY" == "yes" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_info "Deletion confirmed by user"
}

remove_metric_alerts() {
    log_info "Removing metric alerts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove metric alerts"
        return 0
    fi
    
    local alerts
    alerts=$(az monitor metrics alert list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$alerts" ]]; then
        while read -r alert; do
            if [[ -n "$alert" ]]; then
                log_info "Removing alert: $alert"
                az monitor metrics alert delete \
                    --name "$alert" \
                    --resource-group "$RESOURCE_GROUP" \
                    --output none 2>/dev/null || log_warning "Failed to remove alert: $alert"
            fi
        done <<< "$alerts"
    else
        log_info "No metric alerts found to remove"
    fi
    
    log_success "Metric alerts removal completed"
}

remove_action_groups() {
    log_info "Removing action groups..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove action groups"
        return 0
    fi
    
    local action_groups
    action_groups=$(az monitor action-group list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$action_groups" ]]; then
        while read -r group; do
            if [[ -n "$group" ]]; then
                log_info "Removing action group: $group"
                az monitor action-group delete \
                    --name "$group" \
                    --resource-group "$RESOURCE_GROUP" \
                    --output none 2>/dev/null || log_warning "Failed to remove action group: $group"
            fi
        done <<< "$action_groups"
    else
        log_info "No action groups found to remove"
    fi
    
    log_success "Action groups removal completed"
}

remove_diagnostic_settings() {
    log_info "Removing diagnostic settings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove diagnostic settings"
        return 0
    fi
    
    # Get all storage accounts in the resource group
    local storage_accounts
    storage_accounts=$(az storage account list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$storage_accounts" ]]; then
        while read -r account; do
            if [[ -n "$account" ]]; then
                log_info "Removing diagnostic settings for storage account: $account"
                
                # Get storage account resource ID
                local storage_account_id
                storage_account_id=$(az storage account show --name "$account" --resource-group "$RESOURCE_GROUP" --query id --output tsv 2>/dev/null || echo "")
                
                if [[ -n "$storage_account_id" ]]; then
                    # Remove diagnostic settings for blob service
                    az monitor diagnostic-settings delete \
                        --resource "${storage_account_id}/blobServices/default" \
                        --name "BlobStorageMonitoring" \
                        --output none 2>/dev/null || log_warning "Failed to remove diagnostic settings for $account"
                fi
            fi
        done <<< "$storage_accounts"
    else
        log_info "No storage accounts found for diagnostic settings removal"
    fi
    
    log_success "Diagnostic settings removal completed"
}

remove_storage_data() {
    log_info "Removing storage account data..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove storage account data"
        return 0
    fi
    
    # Get all storage accounts in the resource group
    local storage_accounts
    storage_accounts=$(az storage account list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$storage_accounts" ]]; then
        while read -r account; do
            if [[ -n "$account" ]]; then
                log_info "Removing data from storage account: $account"
                
                # Get storage account key
                local storage_key
                storage_key=$(az storage account keys list \
                    --account-name "$account" \
                    --resource-group "$RESOURCE_GROUP" \
                    --query '[0].value' --output tsv 2>/dev/null || echo "")
                
                if [[ -n "$storage_key" ]]; then
                    # List and delete all containers
                    local containers
                    containers=$(az storage container list \
                        --account-name "$account" \
                        --account-key "$storage_key" \
                        --query '[].name' --output tsv 2>/dev/null || echo "")
                    
                    if [[ -n "$containers" ]]; then
                        while read -r container; do
                            if [[ -n "$container" ]]; then
                                log_info "Removing container: $container"
                                az storage container delete \
                                    --name "$container" \
                                    --account-name "$account" \
                                    --account-key "$storage_key" \
                                    --output none 2>/dev/null || log_warning "Failed to remove container: $container"
                            fi
                        done <<< "$containers"
                    fi
                fi
            fi
        done <<< "$storage_accounts"
    else
        log_info "No storage accounts found for data removal"
    fi
    
    log_success "Storage account data removal completed"
}

remove_lifecycle_policies() {
    log_info "Removing lifecycle management policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove lifecycle management policies"
        return 0
    fi
    
    # Get all storage accounts in the resource group
    local storage_accounts
    storage_accounts=$(az storage account list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$storage_accounts" ]]; then
        while read -r account; do
            if [[ -n "$account" ]]; then
                log_info "Removing lifecycle policy for storage account: $account"
                
                # Check if lifecycle policy exists
                if az storage account management-policy show \
                    --account-name "$account" \
                    --resource-group "$RESOURCE_GROUP" \
                    --output none 2>/dev/null; then
                    
                    az storage account management-policy delete \
                        --account-name "$account" \
                        --resource-group "$RESOURCE_GROUP" \
                        --output none 2>/dev/null || log_warning "Failed to remove lifecycle policy for $account"
                else
                    log_info "No lifecycle policy found for storage account: $account"
                fi
            fi
        done <<< "$storage_accounts"
    else
        log_info "No storage accounts found for lifecycle policy removal"
    fi
    
    log_success "Lifecycle policies removal completed"
}

remove_resource_group() {
    log_info "Removing resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    # Delete resource group (this will delete all resources within it)
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none
    
    log_success "Resource group deletion initiated: $RESOURCE_GROUP"
    log_info "Note: Resource group deletion may take several minutes to complete"
}

wait_for_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log_info "Waiting for resource group deletion to complete..."
    
    local max_wait=300  # 5 minutes maximum wait
    local wait_time=0
    local check_interval=10
    
    while [[ $wait_time -lt $max_wait ]]; do
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log_success "Resource group '$RESOURCE_GROUP' has been completely deleted"
            return 0
        fi
        
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
        log_info "Still waiting for deletion... ($wait_time/$max_wait seconds)"
    done
    
    log_warning "Resource group deletion is taking longer than expected"
    log_info "Check the Azure portal to verify deletion status"
}

validate_cleanup() {
    log_info "Validating cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate cleanup"
        return 0
    fi
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' still exists"
        log_info "Deletion may still be in progress. Check Azure portal for status."
        return 1
    fi
    
    log_success "Cleanup validation completed successfully"
    return 0
}

show_cleanup_summary() {
    log_info "Cleanup Summary"
    echo "===================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Deletion Status: $(if [[ "$DRY_RUN" == "true" ]]; then echo "DRY RUN - No changes made"; else echo "Initiated"; fi)"
    echo "Log File: $LOG_FILE"
    echo "===================="
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "All resources in resource group '$RESOURCE_GROUP' have been scheduled for deletion"
        log_info "Monitor deletion progress at: https://portal.azure.com"
    fi
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_DELETE="true"
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            -h|--help)
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
    
    # Initialize logging
    log_info "Starting Azure Blob Storage Lifecycle Management cleanup"
    log_info "Log file: $LOG_FILE"
    
    # Execute cleanup steps
    check_prerequisites
    validate_parameters
    
    if ! check_resource_group_exists; then
        log_info "Nothing to clean up - resource group does not exist"
        exit 0
    fi
    
    # List resources before deletion
    if ! list_resources; then
        log_info "No resources found to clean up"
        exit 0
    fi
    
    # Confirm deletion
    confirm_deletion
    
    # Remove resources in reverse order of creation
    log_info "Starting resource cleanup..."
    
    remove_metric_alerts
    remove_action_groups
    remove_diagnostic_settings
    remove_lifecycle_policies
    remove_storage_data
    remove_resource_group
    
    if [[ "$DRY_RUN" != "true" ]]; then
        wait_for_deletion
        validate_cleanup
    fi
    
    show_cleanup_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run completed successfully. No resources were deleted."
    else
        log_success "Cleanup completed successfully!"
    fi
}

# Error handling
trap 'log_error "Cleanup failed at line $LINENO. Check $LOG_FILE for details."' ERR

# Run main function
main "$@"