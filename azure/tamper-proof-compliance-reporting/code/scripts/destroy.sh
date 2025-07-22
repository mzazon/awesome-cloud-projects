#!/bin/bash

# Azure Compliance Reporting Cleanup Script
# Destroys all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment-info.json"
ENV_FILE="${SCRIPT_DIR}/.env"
FORCE_DELETE=false
DRY_RUN=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    exit 1
}

# Success message
success() {
    log "${GREEN}✅ ${1}${NC}"
}

# Warning message
warning() {
    log "${YELLOW}⚠️  ${1}${NC}"
}

# Info message
info() {
    log "${BLUE}ℹ️  ${1}${NC}"
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -f, --force             Delete without confirmation prompts
    -d, --dry-run          Show what would be deleted without actually deleting
    -r, --resource-group RG Specify resource group name to delete
    -v, --verbose          Enable verbose logging

EXAMPLES:
    $0                                          # Interactive cleanup
    $0 --force                                 # Force delete without prompts
    $0 --dry-run                              # Preview what would be deleted
    $0 --resource-group rg-compliance-abc123  # Delete specific resource group

SAFETY FEATURES:
    - Interactive confirmation prompts (unless --force is used)
    - Dry-run mode to preview deletions
    - Detailed logging of all operations
    - Graceful handling of missing resources

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -r|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    success "Prerequisites check completed"
}

# Load deployment information
load_deployment_info() {
    info "Loading deployment information..."
    
    # Try to load from deployment info file
    if [[ -f "${DEPLOYMENT_INFO_FILE}" ]]; then
        info "Found deployment info file: ${DEPLOYMENT_INFO_FILE}"
        
        if command -v jq &> /dev/null; then
            RESOURCE_GROUP=$(jq -r '.resourceGroup' "${DEPLOYMENT_INFO_FILE}")
            SUBSCRIPTION_ID=$(jq -r '.subscriptionId' "${DEPLOYMENT_INFO_FILE}")
            LOCATION=$(jq -r '.location' "${DEPLOYMENT_INFO_FILE}")
            ACL_NAME=$(jq -r '.resources.confidentialLedger' "${DEPLOYMENT_INFO_FILE}")
            STORAGE_ACCOUNT=$(jq -r '.resources.storageAccount' "${DEPLOYMENT_INFO_FILE}")
            LOGIC_APP_NAME=$(jq -r '.resources.logicApp' "${DEPLOYMENT_INFO_FILE}")
            WORKSPACE_NAME=$(jq -r '.resources.logAnalyticsWorkspace' "${DEPLOYMENT_INFO_FILE}")
            ACTION_GROUP_NAME=$(jq -r '.resources.actionGroup' "${DEPLOYMENT_INFO_FILE}")
        else
            warning "jq not found. Reading deployment info manually..."
            RESOURCE_GROUP=$(grep -o '"resourceGroup": *"[^"]*"' "${DEPLOYMENT_INFO_FILE}" | cut -d'"' -f4)
            SUBSCRIPTION_ID=$(grep -o '"subscriptionId": *"[^"]*"' "${DEPLOYMENT_INFO_FILE}" | cut -d'"' -f4)
        fi
        
        info "Loaded deployment information:"
        info "  Resource Group: ${RESOURCE_GROUP:-not found}"
        info "  Subscription: ${SUBSCRIPTION_ID:-not found}"
        info "  Location: ${LOCATION:-not found}"
        
    elif [[ -f "${ENV_FILE}" ]]; then
        warning "Deployment info file not found, trying .env file..."
        source "${ENV_FILE}"
        
    else
        warning "No deployment info or .env file found."
        if [[ -z "${RESOURCE_GROUP:-}" ]]; then
            info "Please specify the resource group with --resource-group option"
            list_resource_groups
            exit 1
        fi
    fi
    
    # Validate resource group exists
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            success "Found resource group: ${RESOURCE_GROUP}"
        else
            error_exit "Resource group '${RESOURCE_GROUP}' not found"
        fi
    fi
}

# List available resource groups that might be compliance-related
list_resource_groups() {
    info "Available resource groups containing 'compliance':"
    az group list --query "[?contains(name, 'compliance')].name" --output table 2>/dev/null || true
    
    info "All resource groups:"
    az group list --query "[].name" --output table 2>/dev/null || true
}

# Get confirmation from user
confirm_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    log "This will DELETE the following resources:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  All contained resources including:"
    log "    - Azure Confidential Ledger: ${ACL_NAME:-unknown}"
    log "    - Storage Account: ${STORAGE_ACCOUNT:-unknown}"
    log "    - Logic App: ${LOGIC_APP_NAME:-unknown}"
    log "    - Log Analytics Workspace: ${WORKSPACE_NAME:-unknown}"
    log "    - Action Group: ${ACTION_GROUP_NAME:-unknown}"
    log "    - Alert Rules and other monitoring resources"
    echo ""
    warning "⚠️  THIS ACTION CANNOT BE UNDONE ⚠️"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " response
    if [[ "${response}" != "yes" ]]; then
        info "Deletion cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Please type the resource group name to confirm: " rg_confirm
    if [[ "${rg_confirm}" != "${RESOURCE_GROUP}" ]]; then
        error_exit "Resource group name confirmation failed"
    fi
    
    success "Deletion confirmed by user"
}

# Delete individual resources (optional, for granular cleanup)
delete_individual_resources() {
    info "Attempting to delete individual resources first..."
    
    # Delete alert rules
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        info "Deleting alert rules..."
        
        # Get and delete metric alert rules
        alert_rules=$(az monitor metrics alert list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || true)
        if [[ -n "${alert_rules}" ]]; then
            for rule in ${alert_rules}; do
                if [[ "${DRY_RUN}" == "false" ]]; then
                    az monitor metrics alert delete --name "${rule}" --resource-group "${RESOURCE_GROUP}" --yes &> /dev/null || true
                fi
                info "  Deleted metric alert rule: ${rule}"
            done
        fi
        
        # Get and delete scheduled query rules
        query_rules=$(az monitor scheduled-query rule list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || true)
        if [[ -n "${query_rules}" ]]; then
            for rule in ${query_rules}; do
                if [[ "${DRY_RUN}" == "false" ]]; then
                    az monitor scheduled-query rule delete --name "${rule}" --resource-group "${RESOURCE_GROUP}" --yes &> /dev/null || true
                fi
                info "  Deleted scheduled query rule: ${rule}"
            done
        fi
    fi
    
    # Delete Logic App workflow (to ensure proper cleanup)
    if [[ -n "${LOGIC_APP_NAME:-}" ]]; then
        info "Deleting Logic App: ${LOGIC_APP_NAME}"
        if [[ "${DRY_RUN}" == "false" ]]; then
            az logic workflow delete --name "${LOGIC_APP_NAME}" --resource-group "${RESOURCE_GROUP}" --yes &> /dev/null || true
        fi
    fi
    
    # Delete Confidential Ledger (may have dependencies)
    if [[ -n "${ACL_NAME:-}" ]]; then
        info "Deleting Confidential Ledger: ${ACL_NAME}"
        if [[ "${DRY_RUN}" == "false" ]]; then
            az confidentialledger delete --name "${ACL_NAME}" --resource-group "${RESOURCE_GROUP}" --yes &> /dev/null || true
        fi
    fi
    
    success "Individual resources cleanup completed"
}

# Delete the entire resource group
delete_resource_group() {
    info "Deleting resource group: ${RESOURCE_GROUP}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "DRY RUN: Would delete resource group and all contained resources"
        return 0
    fi
    
    # Delete resource group (this deletes all contained resources)
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    
    info "Resource group deletion initiated (running in background)"
    info "This may take several minutes to complete..."
    
    # Wait for deletion to complete (optional)
    if [[ "${FORCE_DELETE}" == "false" ]]; then
        read -p "Do you want to wait for deletion to complete? (y/N): " wait_response
        if [[ "${wait_response}" =~ ^[Yy]$ ]]; then
            info "Waiting for resource group deletion to complete..."
            
            # Monitor deletion progress
            while az group show --name "${RESOURCE_GROUP}" &> /dev/null; do
                info "Still deleting... (waiting 30 seconds)"
                sleep 30
            done
            
            success "Resource group deletion completed"
        else
            info "Deletion is running in background. You can check status with:"
            info "  az group show --name '${RESOURCE_GROUP}'"
        fi
    fi
}

# Verify deletion
verify_deletion() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    info "Verifying deletion..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Resource group still exists (deletion may be in progress)"
        return 0
    fi
    
    success "Resource group deletion verified"
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local deployment files..."
    
    files_to_clean=(
        "${DEPLOYMENT_INFO_FILE}"
        "${ENV_FILE}"
    )
    
    for file in "${files_to_clean[@]}"; do
        if [[ -f "${file}" ]]; then
            if [[ "${DRY_RUN}" == "false" ]]; then
                rm -f "${file}"
            fi
            info "  Removed: $(basename "${file}")"
        fi
    done
    
    success "Local files cleaned up"
}

# Main cleanup function
main() {
    # Initialize log file
    echo "=== Azure Compliance Reporting Cleanup Log ===" > "${LOG_FILE}"
    echo "Cleanup started at: $(date)" >> "${LOG_FILE}"
    
    info "Starting Azure Compliance Reporting cleanup..."
    
    # Parse command line arguments
    parse_args "$@"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "DRY RUN MODE - No resources will be deleted"
    fi
    
    # Execute cleanup steps
    check_prerequisites
    load_deployment_info
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        confirm_deletion
    fi
    
    delete_individual_resources
    delete_resource_group
    verify_deletion
    cleanup_local_files
    
    # Final success message
    echo ""
    if [[ "${DRY_RUN}" == "true" ]]; then
        success "=== DRY RUN COMPLETED ==="
        info "No resources were actually deleted"
    else
        success "=== CLEANUP COMPLETED SUCCESSFULLY ==="
        info "All compliance reporting resources have been deleted"
    fi
    
    echo ""
    info "Summary of deleted resources:"
    info "  Resource Group: ${RESOURCE_GROUP}"
    info "  All contained Azure resources"
    info "  Local deployment files"
    echo ""
    info "Log file: ${LOG_FILE}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        echo ""
        warning "If you created any manual integrations or external dependencies,"
        warning "please review and clean those up manually."
    fi
}

# Execute main function
main "$@"