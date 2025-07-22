#!/bin/bash

# Azure Container Security Scanning Cleanup Script
# This script removes all resources created by the deployment script
# to avoid ongoing charges and cleanup the Azure subscription

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ENV_FILE="${SCRIPT_DIR}/.env"

# Colors for output
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

# Warning function
warn() {
    log "${YELLOW}WARNING: ${1}${NC}"
}

# Success function
success() {
    log "${GREEN}SUCCESS: ${1}${NC}"
}

# Info function
info() {
    log "${BLUE}INFO: ${1}${NC}"
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
        error_exit "Please log in to Azure using 'az login'"
    fi
    
    # Check if environment file exists
    if [ ! -f "${ENV_FILE}" ]; then
        error_exit "Environment file not found: ${ENV_FILE}. Please run deploy.sh first."
    fi
    
    success "Prerequisites check completed"
}

# Load environment variables
load_environment() {
    info "Loading environment variables from ${ENV_FILE}..."
    
    # Source the environment file
    set -a  # automatically export all variables
    source "${ENV_FILE}"
    set +a  # stop automatic export
    
    # Verify required variables are set
    if [ -z "${RESOURCE_GROUP:-}" ]; then
        error_exit "RESOURCE_GROUP not set in environment file"
    fi
    
    if [ -z "${ACR_NAME:-}" ]; then
        error_exit "ACR_NAME not set in environment file"
    fi
    
    info "Environment variables loaded successfully"
    info "Resource Group: ${RESOURCE_GROUP}"
    info "ACR Name: ${ACR_NAME}"
}

# Confirmation prompt
confirm_destruction() {
    local confirm
    
    warn "This will permanently delete the following resources:"
    warn "- Resource Group: ${RESOURCE_GROUP}"
    warn "- Azure Container Registry: ${ACR_NAME}"
    warn "- Log Analytics Workspace: ${WORKSPACE_NAME:-}"
    warn "- Service Principal: ${SP_NAME:-}"
    warn "- Azure Policy Assignments"
    warn "- Microsoft Defender for Containers (if enabled only for this deployment)"
    warn ""
    
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    case "${confirm}" in
        yes|YES|y|Y)
            info "Proceeding with resource deletion..."
            ;;
        *)
            info "Cleanup cancelled by user"
            exit 0
            ;;
    esac
}

# Remove policy assignments
remove_policy_assignments() {
    info "Removing policy assignments..."
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    
    # Remove vulnerability resolution policy
    if az policy assignment show \
        --name "require-vuln-resolution" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        &> /dev/null; then
        
        az policy assignment delete \
            --name "require-vuln-resolution" \
            --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
        
        success "Vulnerability resolution policy assignment removed"
    else
        warn "Vulnerability resolution policy assignment not found"
    fi
    
    # Remove anonymous pull policy (if ACR still exists)
    if [ -n "${ACR_ID:-}" ] && az acr show --name "${ACR_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        if az policy assignment show \
            --name "disable-anonymous-pull" \
            --scope "${ACR_ID}" \
            &> /dev/null; then
            
            az policy assignment delete \
                --name "disable-anonymous-pull" \
                --scope "${ACR_ID}"
            
            success "Anonymous pull policy assignment removed"
        else
            warn "Anonymous pull policy assignment not found"
        fi
    fi
}

# Remove monitoring alerts
remove_monitoring_alerts() {
    info "Removing monitoring alerts..."
    
    # Remove critical vulnerability alert
    if az monitor metrics alert show \
        --name "critical-vulnerability-alert" \
        --resource-group "${RESOURCE_GROUP}" \
        &> /dev/null; then
        
        az monitor metrics alert delete \
            --name "critical-vulnerability-alert" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes
        
        success "Critical vulnerability alert removed"
    else
        warn "Critical vulnerability alert not found"
    fi
}

# Remove service principal
remove_service_principal() {
    if [ -n "${SP_APP_ID:-}" ]; then
        info "Removing service principal: ${SP_APP_ID}"
        
        if az ad sp show --id "${SP_APP_ID}" &> /dev/null; then
            az ad sp delete --id "${SP_APP_ID}"
            success "Service principal deleted"
        else
            warn "Service principal not found or already deleted"
        fi
    else
        warn "Service principal App ID not found in environment"
    fi
}

# Remove container images
remove_container_images() {
    info "Removing container images from ACR..."
    
    # Check if ACR exists
    if ! az acr show --name "${ACR_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "ACR not found, skipping image cleanup"
        return
    fi
    
    # List and delete all repositories
    REPOSITORIES=$(az acr repository list --name "${ACR_NAME}" --query "[]" -o tsv 2>/dev/null || echo "")
    
    if [ -n "${REPOSITORIES}" ]; then
        for repo in ${REPOSITORIES}; do
            info "Deleting repository: ${repo}"
            az acr repository delete \
                --name "${ACR_NAME}" \
                --repository "${repo}" \
                --yes
        done
        success "Container images removed"
    else
        info "No container images found to remove"
    fi
}

# Remove resource group and all resources
remove_resource_group() {
    info "Removing resource group: ${RESOURCE_GROUP}"
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Resource group not found, may already be deleted"
        return
    fi
    
    # Delete resource group (this will delete all resources within it)
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    
    success "Resource group deletion initiated"
    info "Note: Complete deletion may take 5-10 minutes"
}

# Check Defender for Containers status
check_defender_status() {
    info "Checking Microsoft Defender for Containers status..."
    
    # Check if Defender is enabled
    DEFENDER_STATUS=$(az security pricing show \
        --name Containers \
        --query pricingTier -o tsv 2>/dev/null || echo "Free")
    
    if [ "${DEFENDER_STATUS}" = "Standard" ]; then
        warn "Microsoft Defender for Containers is still enabled (Standard tier)"
        warn "This may incur charges if you have other container resources"
        warn "To disable: az security pricing create --name Containers --tier Free"
        warn "To disable Container Registry scanning: az security pricing create --name ContainerRegistry --tier Free"
    else
        info "Microsoft Defender for Containers is in Free tier"
    fi
}

# Wait for resource group deletion
wait_for_deletion() {
    local max_wait=600  # 10 minutes
    local wait_time=0
    local check_interval=30  # 30 seconds
    
    info "Waiting for resource group deletion to complete..."
    
    while [ ${wait_time} -lt ${max_wait} ]; do
        if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            success "Resource group deleted successfully"
            return 0
        fi
        
        info "Still waiting... (${wait_time}s elapsed)"
        sleep ${check_interval}
        wait_time=$((wait_time + check_interval))
    done
    
    warn "Resource group deletion is taking longer than expected"
    warn "Please check the Azure portal for deletion status"
    return 1
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove environment file
    if [ -f "${ENV_FILE}" ]; then
        rm -f "${ENV_FILE}"
        success "Environment file removed"
    fi
    
    # Remove Azure Pipeline YAML file
    PIPELINE_FILE="${SCRIPT_DIR}/../azure-pipelines.yml"
    if [ -f "${PIPELINE_FILE}" ]; then
        rm -f "${PIPELINE_FILE}"
        success "Azure Pipeline YAML file removed"
    fi
    
    # Keep log file for reference
    info "Log file preserved at: ${LOG_FILE}"
}

# Validation function
validate_cleanup() {
    info "Validating cleanup..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Resource group still exists, deletion may still be in progress"
    else
        success "Resource group successfully deleted"
    fi
    
    # Check if service principal still exists
    if [ -n "${SP_APP_ID:-}" ]; then
        if az ad sp show --id "${SP_APP_ID}" &> /dev/null; then
            warn "Service principal still exists"
        else
            success "Service principal successfully deleted"
        fi
    fi
    
    success "Cleanup validation completed"
}

# Main cleanup function
main() {
    log "Starting Azure Container Security Scanning cleanup..."
    log "Cleanup started at: $(date)"
    
    check_prerequisites
    load_environment
    confirm_destruction
    remove_policy_assignments
    remove_monitoring_alerts
    remove_service_principal
    remove_container_images
    remove_resource_group
    check_defender_status
    
    # Wait for deletion to complete
    if wait_for_deletion; then
        cleanup_local_files
        validate_cleanup
    else
        warn "Cleanup may not be complete. Check Azure portal for status."
    fi
    
    success "Cleanup process completed!"
    
    # Display summary
    log ""
    log "=== CLEANUP SUMMARY ==="
    log "Resource Group: ${RESOURCE_GROUP} (deleted)"
    log "ACR Name: ${ACR_NAME} (deleted)"
    log "Service Principal: ${SP_APP_ID:-N/A} (deleted)"
    log "Log file: ${LOG_FILE}"
    log ""
    log "Important notes:"
    log "1. Microsoft Defender for Containers may still be enabled at subscription level"
    log "2. Any other container resources will continue to be protected and charged"
    log "3. To completely disable Defender, run:"
    log "   az security pricing create --name Containers --tier Free"
    log "   az security pricing create --name ContainerRegistry --tier Free"
    log ""
    log "Cleanup completed at: $(date)"
}

# Handle script interruption
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        error_exit "Cleanup failed. Check ${LOG_FILE} for details."
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"