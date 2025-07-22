#!/bin/bash

# Voice-Driven Workflow Automation with Speech Recognition
# Cleanup/Destroy Script
# 
# This script removes all Azure resources created for the voice-enabled business process automation
# including Azure AI Speech Services, Logic Apps, Storage Account, and the resource group.
#
# Prerequisites:
# - Azure CLI v2.0 or later
# - Active Azure subscription with appropriate permissions
# - .deployment_state file from the deployment (or manual resource specification)
#
# Usage: ./destroy.sh [--resource-group <name>] [--force] [--keep-resource-group] [--dry-run]

set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_FILE="${SCRIPT_DIR}/destroy_errors.log"
STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Default values
RESOURCE_GROUP=""
FORCE_CLEANUP=false
KEEP_RESOURCE_GROUP=false
DRY_RUN=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${RED}ERROR: $1${NC}" | tee -a "$ERROR_FILE" >&2
}

log_warning() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${YELLOW}WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${GREEN}SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${BLUE}INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Load deployment state
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        log_info "Loading deployment state from $STATE_FILE"
        
        # Read state file and export variables
        while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                export "$key"="$value"
                log_info "Loaded: $key=$value"
            fi
        done < "$STATE_FILE"
    else
        log_warning "State file not found: $STATE_FILE"
        if [[ -z "$RESOURCE_GROUP" ]]; then
            error_exit "No state file found and no resource group specified. Use --resource-group option."
        fi
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI and try again."
    fi
    
    # Check Azure CLI login
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure CLI. Please run 'az login' and try again."
    fi
    
    # Check subscription
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    if [[ -z "$subscription_id" ]]; then
        error_exit "Unable to get subscription ID. Please check your Azure CLI login."
    fi
    
    log_success "Prerequisites check completed"
    log_info "Using subscription: $subscription_id"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --force)
                FORCE_CLEANUP=true
                shift
                ;;
            --keep-resource-group)
                KEEP_RESOURCE_GROUP=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
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
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Azure Voice-Enabled Business Process Automation infrastructure.

OPTIONS:
    --resource-group <name>    Resource group name to destroy
    --force                    Skip confirmation prompts
    --keep-resource-group      Keep the resource group (delete only resources)
    --dry-run                  Show what would be deleted without making changes
    --help, -h                 Show this help message

EXAMPLES:
    $0                                           # Use state file for resource names
    $0 --resource-group rg-voice-automation     # Specify resource group manually
    $0 --force --keep-resource-group            # Force delete resources but keep RG
    $0 --dry-run                                # Preview what would be deleted

NOTES:
    - Power Platform resources (Dataverse, Power Automate flows) must be cleaned up manually
    - Use --force to skip confirmation prompts (useful for automation)
    - Configuration files in ../config/ are preserved unless manually deleted

EOF
}

# Confirm destruction
confirm_destruction() {
    if [[ "$FORCE_CLEANUP" == "true" ]]; then
        log_info "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    log_warning "This will destroy the following Azure resources:"
    
    if [[ -n "${SPEECH_SERVICE_NAME:-}" ]]; then
        log_warning "  - Speech Service: $SPEECH_SERVICE_NAME"
    fi
    
    if [[ -n "${LOGIC_APP_NAME:-}" ]]; then
        log_warning "  - Logic App: $LOGIC_APP_NAME"
    fi
    
    if [[ -n "${STORAGE_ACCOUNT_NAME:-}" ]]; then
        log_warning "  - Storage Account: $STORAGE_ACCOUNT_NAME"
    fi
    
    if [[ "$KEEP_RESOURCE_GROUP" != "true" && -n "$RESOURCE_GROUP" ]]; then
        log_warning "  - Resource Group: $RESOURCE_GROUP"
    fi
    
    log_warning ""
    log_warning "Power Platform resources must be cleaned up manually:"
    log_warning "  - Dataverse tables (voice_automation_approvals, voice_automation_audit)"
    log_warning "  - Power Automate flows"
    log_warning "  - Power Apps applications"
    log_warning ""
    
    echo -n "Are you sure you want to proceed? (yes/no): "
    read -r response
    
    case "$response" in
        yes|YES|y|Y)
            log_info "Proceeding with resource destruction"
            ;;
        *)
            log_info "Operation cancelled by user"
            exit 0
            ;;
    esac
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    
    case "$resource_type" in
        "resource-group")
            az group show --name "$resource_name" &> /dev/null
            ;;
        "storage-account")
            az storage account show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "cognitive-service")
            az cognitiveservices account show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "logic-workflow")
            az logic workflow show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Delete Azure AI Speech Service
delete_speech_service() {
    if [[ -z "${SPEECH_SERVICE_NAME:-}" ]]; then
        log_warning "Speech Service name not found in state, skipping"
        return 0
    fi
    
    log_info "Deleting Azure AI Speech Service: $SPEECH_SERVICE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Speech Service: $SPEECH_SERVICE_NAME"
        return 0
    fi
    
    if resource_exists "cognitive-service" "$SPEECH_SERVICE_NAME" "$RESOURCE_GROUP"; then
        az cognitiveservices account delete \
            --name "$SPEECH_SERVICE_NAME" \
            --resource-group "$RESOURCE_GROUP" || \
            log_error "Failed to delete Speech Service: $SPEECH_SERVICE_NAME"
        
        # Wait for deletion to complete
        local retries=0
        while [[ $retries -lt 10 ]] && resource_exists "cognitive-service" "$SPEECH_SERVICE_NAME" "$RESOURCE_GROUP"; do
            log_info "Waiting for Speech Service deletion to complete... (attempt $((retries + 1))/10)"
            sleep 10
            ((retries++))
        done
        
        if resource_exists "cognitive-service" "$SPEECH_SERVICE_NAME" "$RESOURCE_GROUP"; then
            log_warning "Speech Service deletion did not complete within expected time"
        else
            log_success "Speech Service deleted: $SPEECH_SERVICE_NAME"
        fi
    else
        log_warning "Speech Service not found: $SPEECH_SERVICE_NAME"
    fi
}

# Delete Logic App
delete_logic_app() {
    if [[ -z "${LOGIC_APP_NAME:-}" ]]; then
        log_warning "Logic App name not found in state, skipping"
        return 0
    fi
    
    log_info "Deleting Logic App: $LOGIC_APP_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Logic App: $LOGIC_APP_NAME"
        return 0
    fi
    
    if resource_exists "logic-workflow" "$LOGIC_APP_NAME" "$RESOURCE_GROUP"; then
        az logic workflow delete \
            --name "$LOGIC_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes || \
            log_error "Failed to delete Logic App: $LOGIC_APP_NAME"
        
        log_success "Logic App deleted: $LOGIC_APP_NAME"
    else
        log_warning "Logic App not found: $LOGIC_APP_NAME"
    fi
}

# Delete Storage Account
delete_storage_account() {
    if [[ -z "${STORAGE_ACCOUNT_NAME:-}" ]]; then
        log_warning "Storage Account name not found in state, skipping"
        return 0
    fi
    
    log_info "Deleting Storage Account: $STORAGE_ACCOUNT_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Storage Account: $STORAGE_ACCOUNT_NAME"
        return 0
    fi
    
    if resource_exists "storage-account" "$STORAGE_ACCOUNT_NAME" "$RESOURCE_GROUP"; then
        az storage account delete \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes || \
            log_error "Failed to delete Storage Account: $STORAGE_ACCOUNT_NAME"
        
        log_success "Storage Account deleted: $STORAGE_ACCOUNT_NAME"
    else
        log_warning "Storage Account not found: $STORAGE_ACCOUNT_NAME"
    fi
}

# Delete Resource Group
delete_resource_group() {
    if [[ "$KEEP_RESOURCE_GROUP" == "true" ]]; then
        log_info "Keeping resource group as requested: $RESOURCE_GROUP"
        return 0
    fi
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log_warning "Resource Group name not specified, skipping"
        return 0
    fi
    
    log_info "Deleting Resource Group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Resource Group: $RESOURCE_GROUP"
        return 0
    fi
    
    if resource_exists "resource-group" "$RESOURCE_GROUP" ""; then
        # Check if resource group has any remaining resources
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query length(@))
        
        if [[ "$remaining_resources" -gt 0 ]]; then
            log_warning "Resource group contains $remaining_resources remaining resources"
            if [[ "$FORCE_CLEANUP" != "true" ]]; then
                echo -n "Force delete resource group with remaining resources? (yes/no): "
                read -r response
                case "$response" in
                    yes|YES|y|Y)
                        log_info "Proceeding with force deletion"
                        ;;
                    *)
                        log_info "Skipping resource group deletion"
                        return 0
                        ;;
                esac
            fi
        fi
        
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait || \
            log_error "Failed to initiate Resource Group deletion: $RESOURCE_GROUP"
        
        log_success "Resource Group deletion initiated: $RESOURCE_GROUP"
        log_info "Note: Resource group deletion is running in the background"
    else
        log_warning "Resource Group not found: $RESOURCE_GROUP"
    fi
}

# Cleanup local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local state files"
        return 0
    fi
    
    # Remove state file
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        log_success "Removed state file: $STATE_FILE"
    fi
    
    # Note about configuration files
    local config_dir="${SCRIPT_DIR}/../config"
    if [[ -d "$config_dir" ]]; then
        log_info "Configuration files preserved in: $config_dir"
        log_info "Remove manually if no longer needed"
    fi
}

# Display destruction summary
show_destruction_summary() {
    log_info "Destruction Summary"
    log_info "==================="
    log_info "The following Azure resources have been removed:"
    
    if [[ -n "${SPEECH_SERVICE_NAME:-}" ]]; then
        log_info "✓ Speech Service: $SPEECH_SERVICE_NAME"
    fi
    
    if [[ -n "${LOGIC_APP_NAME:-}" ]]; then
        log_info "✓ Logic App: $LOGIC_APP_NAME"
    fi
    
    if [[ -n "${STORAGE_ACCOUNT_NAME:-}" ]]; then
        log_info "✓ Storage Account: $STORAGE_ACCOUNT_NAME"
    fi
    
    if [[ "$KEEP_RESOURCE_GROUP" != "true" && -n "$RESOURCE_GROUP" ]]; then
        log_info "✓ Resource Group: $RESOURCE_GROUP (deletion in progress)"
    fi
    
    log_info ""
    log_warning "Manual cleanup required for:"
    log_warning "• Power Platform Dataverse tables"
    log_warning "• Power Automate flows"
    log_warning "• Power Apps applications"
    log_warning "• Any custom Speech Studio configurations"
    log_info ""
    log_info "Cleanup logs are available in: $LOG_FILE"
}

# Main destruction function
main() {
    # Initialize log files
    : > "$LOG_FILE"
    : > "$ERROR_FILE"
    
    log_info "Starting Voice-Enabled Business Process Automation cleanup"
    log_info "Script version: 1.0"
    log_info "Timestamp: $(date)"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment state
    load_state
    
    # Use provided resource group if specified
    if [[ -n "${1:-}" && "${1}" != --* ]]; then
        RESOURCE_GROUP="$1"
    fi
    
    # Ensure we have a resource group
    if [[ -z "$RESOURCE_GROUP" ]]; then
        error_exit "No resource group specified. Use --resource-group option or ensure state file exists."
    fi
    
    log_info "Target resource group: $RESOURCE_GROUP"
    
    # Verify resource group exists
    if ! resource_exists "resource-group" "$RESOURCE_GROUP" ""; then
        log_warning "Resource group $RESOURCE_GROUP does not exist"
        exit 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        log_info "Would delete resources in resource group: $RESOURCE_GROUP"
        
        # Show what would be deleted
        log_info "Resources that would be deleted:"
        az resource list --resource-group "$RESOURCE_GROUP" --query '[].{Name:name,Type:type}' --output table || true
        exit 0
    fi
    
    # Confirm destruction
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_logic_app
    delete_speech_service
    delete_storage_account
    delete_resource_group
    
    # Cleanup local files
    cleanup_local_files
    
    # Show summary
    show_destruction_summary
    
    log_success "Cleanup completed successfully!"
    log_info "Total cleanup time: $SECONDS seconds"
}

# Set script permissions and run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi