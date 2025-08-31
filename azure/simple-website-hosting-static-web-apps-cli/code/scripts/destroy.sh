#!/bin/bash

# ==============================================================================
# Azure Static Web Apps Cleanup Script
# Recipe: Simple Website Hosting with Static Web Apps and CLI
# ==============================================================================
# This script safely removes Azure Static Web App resources created by the
# deployment script, with proper confirmation and resource dependency handling.
# ==============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deploy-config"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ==============================================================================
# Utility Functions
# ==============================================================================

# Log function with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# Info message
info() {
    echo -e "${BLUE}ℹ️  $*${NC}" | tee -a "${LOG_FILE}"
}

# Success message
success() {
    echo -e "${GREEN}✅ $*${NC}" | tee -a "${LOG_FILE}"
}

# Warning message
warning() {
    echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "${LOG_FILE}"
}

# Error message
error() {
    echo -e "${RED}❌ $*${NC}" | tee -a "${LOG_FILE}" >&2
}

# Fatal error and exit
fatal() {
    error "$*"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely remove Azure Static Web App resources and cleanup local files.

OPTIONS:
    -n, --name NAME           Static Web App name (from config if available)
    -g, --resource-group RG   Resource group name (from config if available)
    -k, --keep-rg            Keep resource group (only delete Static Web App)
    -l, --keep-local         Keep local website files
    -c, --keep-cli           Keep Static Web Apps CLI installed
    -f, --force              Skip confirmation prompts
    -v, --verbose            Enable verbose logging
    -h, --help               Show this help message

EXAMPLES:
    $0                        # Interactive cleanup with confirmation
    $0 --force               # Force cleanup without prompts
    $0 --keep-rg             # Delete only Static Web App, keep resource group
    $0 --keep-local          # Keep local website files

SAFETY FEATURES:
    • Requires confirmation before deletion (unless --force)
    • Loads configuration from deployment if available
    • Validates resources exist before attempting deletion
    • Handles dependencies and cleanup order properly
    • Preserves logs for troubleshooting

EOF
}

# ==============================================================================
# Configuration Management
# ==============================================================================

# Load deployment configuration
load_config() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        # shellcheck source=/dev/null
        source "${CONFIG_FILE}"
        info "Loaded configuration from ${CONFIG_FILE}"
        return 0
    else
        warning "No deployment configuration found at ${CONFIG_FILE}"
        return 1
    fi
}

# Display configuration summary
show_config_summary() {
    echo "============================================"
    echo "RESOURCES TO BE DELETED:"
    echo "============================================"
    
    if [[ -n "${STATIC_WEB_APP_NAME:-}" ]]; then
        echo "Static Web App:    ${STATIC_WEB_APP_NAME}"
    fi
    
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        if [[ "${KEEP_RESOURCE_GROUP}" == "true" ]]; then
            echo "Resource Group:    ${RESOURCE_GROUP} (WILL BE KEPT)"
        else
            echo "Resource Group:    ${RESOURCE_GROUP} (WILL BE DELETED)"
        fi
    fi
    
    if [[ -n "${WEBSITE_DIR:-}" ]]; then
        if [[ "${KEEP_LOCAL_FILES}" == "true" ]]; then
            echo "Website Directory: ${WEBSITE_DIR} (WILL BE KEPT)"
        else
            echo "Website Directory: ${WEBSITE_DIR} (WILL BE DELETED)"
        fi
    fi
    
    if [[ "${KEEP_SWA_CLI}" == "true" ]]; then
        echo "SWA CLI:           WILL BE KEPT"
    else
        echo "SWA CLI:           WILL BE UNINSTALLED"
    fi
    
    echo "============================================"
    echo
}

# ==============================================================================
# Prerequisites and Authentication
# ==============================================================================

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command_exists az; then
        fatal "Azure CLI is not installed"
    fi
    
    success "Prerequisites check completed"
}

# Check Azure authentication
check_azure_auth() {
    info "Checking Azure authentication..."
    
    if ! az account show >/dev/null 2>&1; then
        info "Not logged into Azure. Initiating login..."
        az login || fatal "Azure login failed"
    fi
    
    # Get subscription info
    local subscription_id subscription_name
    subscription_id=$(az account show --query id --output tsv)
    subscription_name=$(az account show --query name --output tsv)
    
    info "Using subscription: $subscription_name ($subscription_id)"
    success "Azure authentication verified"
}

# ==============================================================================
# Resource Discovery and Validation
# ==============================================================================

# Discover resources interactively
discover_resources() {
    info "Discovering Azure Static Web App resources..."
    
    # List all Static Web Apps in subscription
    local static_web_apps
    static_web_apps=$(az staticwebapp list --query "[].{name:name,resourceGroup:resourceGroup,location:location}" -o table 2>/dev/null)
    
    if [[ -z "$static_web_apps" ]] || [[ "$static_web_apps" == "[]" ]]; then
        warning "No Static Web Apps found in current subscription"
        return 1
    fi
    
    echo "Available Static Web Apps:"
    echo "$static_web_apps"
    echo
    
    # Interactive selection if not provided
    if [[ -z "${STATIC_WEB_APP_NAME:-}" ]]; then
        read -p "Enter Static Web App name to delete: " STATIC_WEB_APP_NAME
        if [[ -z "$STATIC_WEB_APP_NAME" ]]; then
            fatal "Static Web App name is required"
        fi
    fi
    
    # Get resource group if not provided
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        RESOURCE_GROUP=$(az staticwebapp show --name "$STATIC_WEB_APP_NAME" --query "resourceGroup" -o tsv 2>/dev/null || echo "")
        if [[ -z "$RESOURCE_GROUP" ]]; then
            fatal "Could not determine resource group for Static Web App: $STATIC_WEB_APP_NAME"
        fi
    fi
    
    success "Resources discovered successfully"
}

# Validate resources exist
validate_resources() {
    info "Validating resources exist..."
    
    # Check Static Web App exists
    if [[ -n "${STATIC_WEB_APP_NAME:-}" ]]; then
        if az staticwebapp show --name "$STATIC_WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
            success "Static Web App found: $STATIC_WEB_APP_NAME"
        else
            warning "Static Web App not found: $STATIC_WEB_APP_NAME"
            STATIC_WEB_APP_NAME=""
        fi
    fi
    
    # Check Resource Group exists
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
            success "Resource Group found: $RESOURCE_GROUP"
        else
            warning "Resource Group not found: $RESOURCE_GROUP"
            RESOURCE_GROUP=""
        fi
    fi
    
    # Check if any resources were found
    if [[ -z "${STATIC_WEB_APP_NAME:-}" ]] && [[ -z "${RESOURCE_GROUP:-}" ]]; then
        warning "No Azure resources found to delete"
        return 1
    fi
    
    return 0
}

# ==============================================================================
# Resource Cleanup Functions
# ==============================================================================

# Delete Static Web App
delete_static_web_app() {
    if [[ -z "${STATIC_WEB_APP_NAME:-}" ]] || [[ -z "${RESOURCE_GROUP:-}" ]]; then
        info "No Static Web App to delete"
        return 0
    fi
    
    info "Deleting Static Web App: $STATIC_WEB_APP_NAME"
    
    # Get Static Web App details before deletion
    local app_url
    app_url=$(az staticwebapp show \
        --name "$STATIC_WEB_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "defaultHostname" -o tsv 2>/dev/null || echo "unknown")
    
    # Delete Static Web App
    if az staticwebapp delete \
        --name "$STATIC_WEB_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --yes >/dev/null 2>&1; then
        success "Static Web App deleted: $STATIC_WEB_APP_NAME"
        [[ "$app_url" != "unknown" ]] && info "Former URL: https://$app_url (no longer accessible)"
    else
        error "Failed to delete Static Web App: $STATIC_WEB_APP_NAME"
        return 1
    fi
}

# Delete Resource Group
delete_resource_group() {
    if [[ "${KEEP_RESOURCE_GROUP}" == "true" ]] || [[ -z "${RESOURCE_GROUP:-}" ]]; then
        info "Keeping resource group: ${RESOURCE_GROUP:-N/A}"
        return 0
    fi
    
    info "Deleting resource group: $RESOURCE_GROUP"
    
    # Check if resource group has other resources
    local other_resources
    other_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    
    if [[ "$other_resources" -gt 0 ]]; then
        warning "Resource group contains $other_resources other resources"
        if [[ "${FORCE_CLEANUP}" != "true" ]]; then
            read -p "Delete resource group and ALL contained resources? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                info "Keeping resource group: $RESOURCE_GROUP"
                return 0
            fi
        fi
    fi
    
    # Delete resource group
    if az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait >/dev/null 2>&1; then
        success "Resource group deletion initiated: $RESOURCE_GROUP"
        info "Note: Deletion may take several minutes to complete"
    else
        error "Failed to delete resource group: $RESOURCE_GROUP"
        return 1
    fi
}

# Clean up local files
cleanup_local_files() {
    if [[ "${KEEP_LOCAL_FILES}" == "true" ]]; then
        info "Keeping local website files"
        return 0
    fi
    
    # Clean up website directory
    if [[ -n "${WEBSITE_DIR:-}" ]] && [[ -d "$WEBSITE_DIR" ]]; then
        info "Removing local website directory: $WEBSITE_DIR"
        
        if [[ "${FORCE_CLEANUP}" != "true" ]]; then
            read -p "Delete local website files in $WEBSITE_DIR? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                info "Keeping local website files: $WEBSITE_DIR"
                return 0
            fi
        fi
        
        if rm -rf "$WEBSITE_DIR"; then
            success "Local website directory removed: $WEBSITE_DIR"
        else
            warning "Failed to remove local website directory: $WEBSITE_DIR"
        fi
    fi
    
    # Clean up configuration file
    if [[ -f "$CONFIG_FILE" ]]; then
        info "Removing deployment configuration: $CONFIG_FILE"
        if rm -f "$CONFIG_FILE"; then
            success "Configuration file removed"
        else
            warning "Failed to remove configuration file: $CONFIG_FILE"
        fi
    fi
}

# Uninstall Static Web Apps CLI
uninstall_swa_cli() {
    if [[ "${KEEP_SWA_CLI}" == "true" ]]; then
        info "Keeping Static Web Apps CLI installed"
        return 0
    fi
    
    if command_exists swa; then
        info "Uninstalling Azure Static Web Apps CLI..."
        
        if [[ "${FORCE_CLEANUP}" != "true" ]]; then
            read -p "Uninstall Static Web Apps CLI? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                info "Keeping Static Web Apps CLI installed"
                return 0
            fi
        fi
        
        if npm uninstall -g @azure/static-web-apps-cli >/dev/null 2>&1; then
            success "Static Web Apps CLI uninstalled"
        else
            warning "Failed to uninstall Static Web Apps CLI"
        fi
    else
        info "Static Web Apps CLI not found (already uninstalled)"
    fi
}

# ==============================================================================
# Main Cleanup Function
# ==============================================================================

# Confirm deletion
confirm_deletion() {
    if [[ "${FORCE_CLEANUP}" == "true" ]]; then
        warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo
    warning "This action will permanently delete the selected resources!"
    warning "This operation cannot be undone!"
    echo
    
    read -p "Are you absolutely sure you want to proceed? (yes/NO): " -r
    echo
    
    if [[ "$REPLY" != "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Deletion confirmed by user"
}

# Main cleanup process
cleanup() {
    log "Starting Azure Static Web App cleanup"
    log "Cleanup started at: $(date)"
    
    # Check prerequisites
    check_prerequisites
    check_azure_auth
    
    # Load configuration or discover resources
    if ! load_config; then
        discover_resources
    fi
    
    # Override with command line arguments if provided
    [[ -n "${ARG_STATIC_WEB_APP_NAME:-}" ]] && STATIC_WEB_APP_NAME="$ARG_STATIC_WEB_APP_NAME"
    [[ -n "${ARG_RESOURCE_GROUP:-}" ]] && RESOURCE_GROUP="$ARG_RESOURCE_GROUP"
    
    # Validate resources exist
    if ! validate_resources; then
        warning "No resources found to clean up"
        info "Checking for local files to clean up..."
        cleanup_local_files
        uninstall_swa_cli
        success "Local cleanup completed"
        exit 0
    fi
    
    # Show what will be deleted
    show_config_summary
    
    # Confirm deletion
    confirm_deletion
    
    # Perform cleanup in proper order
    info "Starting resource cleanup..."
    
    # Delete Azure resources (in order)
    delete_static_web_app
    delete_resource_group
    
    # Clean up local files
    cleanup_local_files
    
    # Uninstall CLI if requested
    uninstall_swa_cli
    
    # Final summary
    log "Cleanup completed successfully!"
    echo
    success "=== CLEANUP SUMMARY ==="
    
    if [[ -n "${STATIC_WEB_APP_NAME:-}" ]]; then
        echo "Static Web App:    ${STATIC_WEB_APP_NAME} - DELETED"
    fi
    
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        if [[ "${KEEP_RESOURCE_GROUP}" == "true" ]]; then
            echo "Resource Group:    ${RESOURCE_GROUP} - KEPT"
        else
            echo "Resource Group:    ${RESOURCE_GROUP} - DELETION INITIATED"
        fi
    fi
    
    if [[ -n "${WEBSITE_DIR:-}" ]]; then
        if [[ "${KEEP_LOCAL_FILES}" == "true" ]]; then
            echo "Local Files:       ${WEBSITE_DIR} - KEPT"
        else
            echo "Local Files:       REMOVED"
        fi
    fi
    
    if [[ "${KEEP_SWA_CLI}" == "true" ]]; then
        echo "SWA CLI:           KEPT"
    else
        echo "SWA CLI:           UNINSTALLED"
    fi
    
    echo "Log File:          $LOG_FILE"
    echo
    
    success "Azure Static Web App cleanup completed!"
    info "All specified resources have been removed"
    
    if [[ "${KEEP_RESOURCE_GROUP}" != "true" ]] && [[ -n "${RESOURCE_GROUP:-}" ]]; then
        info "Resource group deletion is asynchronous - check Azure portal for completion status"
    fi
}

# ==============================================================================
# Script Entry Point
# ==============================================================================

# Parse command line arguments
parse_arguments() {
    KEEP_RESOURCE_GROUP="false"
    KEEP_LOCAL_FILES="false"
    KEEP_SWA_CLI="false"
    FORCE_CLEANUP="false"
    VERBOSE="false"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                ARG_STATIC_WEB_APP_NAME="$2"
                shift 2
                ;;
            -g|--resource-group)
                ARG_RESOURCE_GROUP="$2"
                shift 2
                ;;
            -k|--keep-rg)
                KEEP_RESOURCE_GROUP="true"
                shift
                ;;
            -l|--keep-local)
                KEEP_LOCAL_FILES="true"
                shift
                ;;
            -c|--keep-cli)
                KEEP_SWA_CLI="true"
                shift
                ;;
            -f|--force)
                FORCE_CLEANUP="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Main execution
main() {
    # Initialize log file
    mkdir -p "$(dirname "${LOG_FILE}")"
    touch "${LOG_FILE}"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Display banner
    echo "=================================================="
    echo "Azure Static Web Apps Cleanup Script"
    echo "=================================================="
    echo
    
    # Run cleanup
    cleanup
}

# Execute main function with all arguments
main "$@"