#!/bin/bash

# =============================================================================
# Azure Automated Content Moderation with Content Safety and Logic Apps
# Cleanup/Destroy Script
# =============================================================================
# This script removes all Azure resources created for the automated content
# moderation solution to prevent ongoing charges.
#
# Prerequisites:
# - Azure CLI installed and logged in
# - Deployment state file (.deployment_state) from successful deployment
# - Appropriate Azure subscription permissions
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION AND VARIABLES
# =============================================================================

# Script metadata
readonly SCRIPT_NAME="destroy.sh"
readonly SCRIPT_VERSION="1.0"
readonly DEPLOYMENT_NAME="azure-content-moderation"

# Logging configuration
readonly LOG_FILE="cleanup_$(date +%Y%m%d_%H%M%S).log"
readonly LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Deployment state file
readonly STATE_FILE=".deployment_state"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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
    log "INFO" "$@"
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Cleanup failed with exit code $exit_code"
        log_info "Check log file: $LOG_FILE"
        log_info "Some resources may require manual cleanup in the Azure portal"
    fi
    exit $exit_code
}

trap cleanup_on_exit EXIT

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ ! -f "$STATE_FILE" ]]; then
        log_warning "Deployment state file '$STATE_FILE' not found"
        log_info "You can manually specify resource group name, or check for existing resource groups"
        
        # List resource groups that might contain content moderation resources
        local rg_candidates=$(az group list --query "[?contains(name, 'content-moderation')].name" -o tsv 2>/dev/null || echo "")
        
        if [[ -n "$rg_candidates" ]]; then
            log_info "Found potential content moderation resource groups:"
            echo "$rg_candidates" | while read -r rg; do
                log_info "  - $rg"
            done
            echo
            read -p "Enter resource group name to delete (or press Enter to exit): " manual_rg
            
            if [[ -n "$manual_rg" ]]; then
                export RESOURCE_GROUP="$manual_rg"
                export LOCATION="unknown"
                export RANDOM_SUFFIX="unknown"
                return 0
            else
                log_info "No resource group specified. Exiting."
                exit 0
            fi
        else
            log_info "No content moderation resource groups found."
            read -p "Enter resource group name to delete (or press Enter to exit): " manual_rg
            
            if [[ -n "$manual_rg" ]]; then
                export RESOURCE_GROUP="$manual_rg"
                export LOCATION="unknown"
                export RANDOM_SUFFIX="unknown"
                return 0
            else
                log_info "No resource group specified. Exiting."
                exit 0
            fi
        fi
    fi
    
    # Source the deployment state file
    source "$STATE_FILE"
    
    # Verify required variables are set
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_error "RESOURCE_GROUP not found in deployment state"
        exit 1
    fi
    
    log_info "Loaded deployment state:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Location: ${LOCATION:-unknown}"
    log_info "  Random Suffix: ${RANDOM_SUFFIX:-unknown}"
    
    # Reconstruct resource names based on state
    if [[ -n "${RANDOM_SUFFIX:-}" && "$RANDOM_SUFFIX" != "unknown" ]]; then
        export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stcontentmod${RANDOM_SUFFIX}}"
        export CONTENT_SAFETY_NAME="${CONTENT_SAFETY_NAME:-cs-content-safety-${RANDOM_SUFFIX}}"
        export LOGIC_APP_NAME="${LOGIC_APP_NAME:-la-content-workflow-${RANDOM_SUFFIX}}"
        export CONTAINER_NAME="${CONTAINER_NAME:-content-uploads}"
    fi
}

confirm_deletion() {
    log_warning "This will permanently delete the following resources:"
    log_warning "  Resource Group: $RESOURCE_GROUP"
    log_warning "  Location: ${LOCATION:-unknown}"
    
    # Try to list resources in the resource group
    log_info "Checking for resources in the resource group..."
    local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{name:name, type:type}" -o table 2>/dev/null || echo "Unable to list resources")
    
    if [[ "$resources" != "Unable to list resources" ]]; then
        echo
        echo "$resources"
        echo
    fi
    
    log_warning "All resources in this resource group will be permanently deleted!"
    log_warning "This action cannot be undone."
    echo
    
    # Double confirmation for safety
    read -p "Are you sure you want to delete resource group '$RESOURCE_GROUP'? (yes/no): " confirm1
    if [[ "$confirm1" != "yes" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    read -p "Type the resource group name to confirm: " confirm2
    if [[ "$confirm2" != "$RESOURCE_GROUP" ]]; then
        log_error "Resource group name doesn't match. Deletion cancelled for safety."
        exit 1
    fi
    
    log_info "Deletion confirmed. Proceeding with cleanup..."
}

wait_for_deletion() {
    local resource_group="$1"
    local max_attempts="${2:-60}"
    local sleep_interval="${3:-30}"
    
    log_info "Waiting for resource group deletion to complete..."
    log_info "This may take several minutes depending on the resources..."
    
    for ((i=1; i<=max_attempts; i++)); do
        if ! az group exists --name "$resource_group" 2>/dev/null; then
            log_success "Resource group '$resource_group' has been completely deleted"
            return 0
        fi
        
        log_info "Deletion in progress... attempt $i/$max_attempts (waiting ${sleep_interval}s)"
        sleep "$sleep_interval"
    done
    
    log_warning "Resource group deletion is taking longer than expected"
    log_info "Check Azure portal for deletion status: https://portal.azure.com"
    return 1
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

disable_logic_app() {
    if [[ -n "${LOGIC_APP_NAME:-}" && "$LOGIC_APP_NAME" != "unknown" ]]; then
        log_info "Disabling Logic App: $LOGIC_APP_NAME"
        
        if az logic workflow show --resource-group "$RESOURCE_GROUP" --name "$LOGIC_APP_NAME" &>/dev/null; then
            az logic workflow update \
                --resource-group "$RESOURCE_GROUP" \
                --name "$LOGIC_APP_NAME" \
                --state Disabled \
                --output none 2>/dev/null || log_warning "Could not disable Logic App"
            
            log_success "Logic App disabled (if it existed)"
        else
            log_info "Logic App not found or already deleted"
        fi
    fi
}

cleanup_storage_content() {
    if [[ -n "${STORAGE_ACCOUNT:-}" && "$STORAGE_ACCOUNT" != "unknown" ]]; then
        log_info "Cleaning up storage content in: $STORAGE_ACCOUNT"
        
        if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            # Delete all blobs in the container
            if [[ -n "${CONTAINER_NAME:-}" ]]; then
                log_info "Deleting blobs in container: $CONTAINER_NAME"
                az storage blob delete-batch \
                    --source "$CONTAINER_NAME" \
                    --account-name "$STORAGE_ACCOUNT" \
                    --auth-mode login \
                    --output none 2>/dev/null || log_warning "Could not delete all blobs"
            fi
            
            log_success "Storage content cleaned up"
        else
            log_info "Storage account not found or already deleted"
        fi
    fi
}

delete_resource_group() {
    log_info "Deleting resource group: $RESOURCE_GROUP"
    
    # Check if resource group exists
    if ! az group exists --name "$RESOURCE_GROUP" 2>/dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' does not exist"
        return 0
    fi
    
    # Delete the resource group (this will delete all contained resources)
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none
    
    if [[ $? -eq 0 ]]; then
        log_success "Resource group deletion initiated: $RESOURCE_GROUP"
        log_info "Deletion is running in the background..."
        
        # Optionally wait for completion
        read -p "Wait for deletion to complete? This may take 10-15 minutes (y/N): " wait_confirm
        if [[ "$wait_confirm" =~ ^[Yy]$ ]]; then
            wait_for_deletion "$RESOURCE_GROUP"
        else
            log_info "Deletion initiated. Check Azure portal for progress."
            log_info "Portal link: https://portal.azure.com/#blade/HubsExtension/ResourceGroupsListBlade"
        fi
    else
        log_error "Failed to initiate resource group deletion"
        exit 1
    fi
}

cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # List of files to clean up
    local files_to_remove=(
        "$STATE_FILE"
        "initial-workflow.json"
        "content-moderation-workflow.json"
        "test-file.txt"
        "safe-content.txt"
        "moderate-content.txt"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Removed file: $file"
        fi
    done
    
    # Remove any deployment log files older than current session
    local old_logs=$(find . -name "deployment_*.log" -type f -not -name "$LOG_FILE" 2>/dev/null || echo "")
    if [[ -n "$old_logs" ]]; then
        echo "$old_logs" | while read -r logfile; do
            rm -f "$logfile"
            log_info "Removed old log file: $logfile"
        done
    fi
    
    log_success "Local cleanup completed"
}

verify_cleanup() {
    log_info "Verifying cleanup..."
    
    # Check if resource group still exists
    if az group exists --name "$RESOURCE_GROUP" 2>/dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' still exists"
        log_info "Deletion may still be in progress. Check Azure portal for status."
        return 1
    else
        log_success "Resource group '$RESOURCE_GROUP' has been deleted"
    fi
    
    # Check for remaining local files
    local remaining_files=()
    local files_to_check=(
        "$STATE_FILE"
        "initial-workflow.json"
        "content-moderation-workflow.json"
    )
    
    for file in "${files_to_check[@]}"; do
        if [[ -f "$file" ]]; then
            remaining_files+=("$file")
        fi
    done
    
    if [[ ${#remaining_files[@]} -gt 0 ]]; then
        log_warning "Some local files remain:"
        for file in "${remaining_files[@]}"; do
            log_warning "  - $file"
        done
    else
        log_success "All local files cleaned up"
    fi
    
    log_success "Cleanup verification completed"
}

# =============================================================================
# MAIN CLEANUP FUNCTION
# =============================================================================

main() {
    log_info "Starting Azure Content Moderation cleanup"
    log_info "Script: $SCRIPT_NAME v$SCRIPT_VERSION"
    log_info "Timestamp: $(date)"
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment state
    load_deployment_state
    
    # Confirm deletion
    confirm_deletion
    
    # Perform cleanup steps
    log_info "Starting cleanup process..."
    
    # Disable Logic App first to stop processing
    disable_logic_app
    
    # Clean up storage content to avoid delays
    cleanup_storage_content
    
    # Delete the entire resource group (this deletes all resources)
    delete_resource_group
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    log_success "Cleanup completed!"
    log_info ""
    log_info "=== CLEANUP SUMMARY ==="
    log_info "Resource Group: $RESOURCE_GROUP (deletion initiated)"
    log_info "All resources in the resource group have been marked for deletion"
    log_info "Local files have been cleaned up"
    log_info ""
    log_info "Notes:"
    log_info "- Resource deletion may take 10-15 minutes to complete fully"
    log_info "- Check Azure portal to confirm all resources are deleted"
    log_info "- No ongoing charges should occur after deletion completes"
    log_info ""
    log_info "Azure Portal: https://portal.azure.com"
    log_info "Log file: $LOG_FILE"
    
    # Final verification prompt
    echo
    read -p "Open Azure portal to verify deletion? (y/N): " open_portal
    if [[ "$open_portal" =~ ^[Yy]$ ]]; then
        if command -v open &> /dev/null; then
            open "https://portal.azure.com/#blade/HubsExtension/ResourceGroupsListBlade"
        elif command -v xdg-open &> /dev/null; then
            xdg-open "https://portal.azure.com/#blade/HubsExtension/ResourceGroupsListBlade"
        else
            log_info "Please manually open: https://portal.azure.com"
        fi
    fi
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi