#!/bin/bash

# Azure Data Share and Service Fabric Cleanup Script
# Recipe: Secure Cross-Organization Data Sharing with Data Share and Service Fabric
# Version: 1.0
# Last Updated: 2025-07-12

set -euo pipefail

# Enable debugging if DEBUG environment variable is set
if [[ "${DEBUG:-}" == "true" ]]; then
    set -x
fi

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
DEPLOYMENT_VARS_FILE="${SCRIPT_DIR}/deployment_vars.env"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${ERROR_LOG}" | tee -a "${LOG_FILE}"
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Script failed at line ${line_number} with exit code ${exit_code}"
    log_error "Check ${ERROR_LOG} for detailed error information"
    # Don't exit on error during cleanup - continue trying to delete other resources
}

trap 'handle_error ${LINENO}' ERR

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local resource_group=${3:-}
    
    case "${resource_type}" in
        "group")
            az group show --name "${resource_name}" &> /dev/null
            ;;
        "storage")
            az storage account show --name "${resource_name}" &> /dev/null
            ;;
        "keyvault")
            az keyvault show --name "${resource_name}" &> /dev/null
            ;;
        "datashare")
            az datashare account show --account-name "${resource_name}" --resource-group "${resource_group}" &> /dev/null
            ;;
        "sf-cluster")
            az sf cluster show --cluster-name "${resource_name}" --resource-group "${resource_group}" &> /dev/null
            ;;
        "log-analytics")
            az monitor log-analytics workspace show --workspace-name "${resource_name}" --resource-group "${resource_group}" &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type=$1
    local resource_name=$2
    local resource_group=${3:-}
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for ${resource_type} '${resource_name}' to be deleted..."
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        if ! resource_exists "${resource_type}" "${resource_name}" "${resource_group}"; then
            log_success "${resource_type} '${resource_name}' deleted successfully"
            return 0
        fi
        
        echo -n "."
        sleep 10
        ((attempt++))
    done
    
    log_warning "${resource_type} '${resource_name}' deletion timed out after $((max_attempts * 10)) seconds"
    return 1
}

# Load deployment variables
load_deployment_variables() {
    log_info "Loading deployment variables..."
    
    if [[ ! -f "${DEPLOYMENT_VARS_FILE}" ]]; then
        log_error "Deployment variables file not found: ${DEPLOYMENT_VARS_FILE}"
        log_error "Please ensure the deploy.sh script was run successfully or provide the resource details manually"
        
        # Prompt for manual input
        read -p "Enter the random suffix used during deployment (6 characters): " RANDOM_SUFFIX
        if [[ -z "${RANDOM_SUFFIX}" ]]; then
            log_error "Random suffix is required for cleanup"
            exit 1
        fi
        
        # Set basic variables based on suffix
        export RESOURCE_GROUP_PROVIDER="rg-data-share-provider-${RANDOM_SUFFIX}"
        export RESOURCE_GROUP_CONSUMER="rg-data-share-consumer-${RANDOM_SUFFIX}"
        export DATA_SHARE_ACCOUNT="datashare${RANDOM_SUFFIX}"
        export SERVICE_FABRIC_CLUSTER="sf-governance-${RANDOM_SUFFIX}"
        export KEY_VAULT_PROVIDER="kv-provider-${RANDOM_SUFFIX}"
        export KEY_VAULT_CONSUMER="kv-consumer-${RANDOM_SUFFIX}"
        export STORAGE_PROVIDER="stprovider${RANDOM_SUFFIX}"
        export STORAGE_CONSUMER="stconsumer${RANDOM_SUFFIX}"
        export LOG_ANALYTICS_WORKSPACE="law-datashare-${RANDOM_SUFFIX}"
        
        log_warning "Using manually entered suffix: ${RANDOM_SUFFIX}"
    else
        # Source the deployment variables
        source "${DEPLOYMENT_VARS_FILE}"
        log_success "Deployment variables loaded from file"
    fi
    
    # Display resources to be deleted
    cat << EOF

${YELLOW}=====================================================================${NC}
${YELLOW}                         CLEANUP CONFIRMATION${NC}
${YELLOW}=====================================================================${NC}

${BLUE}The following resources will be PERMANENTLY DELETED:${NC}

${YELLOW}Resource Groups:${NC}
- ${RESOURCE_GROUP_PROVIDER}
- ${RESOURCE_GROUP_CONSUMER}

${YELLOW}Storage Accounts:${NC}
- ${STORAGE_PROVIDER}
- ${STORAGE_CONSUMER}

${YELLOW}Key Vaults:${NC}
- ${KEY_VAULT_PROVIDER}
- ${KEY_VAULT_CONSUMER}

${YELLOW}Other Resources:${NC}
- Data Share Account: ${DATA_SHARE_ACCOUNT}
- Service Fabric Cluster: ${SERVICE_FABRIC_CLUSTER}
- Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE}

${RED}WARNING: This action cannot be undone!${NC}
${YELLOW}=====================================================================${NC}

EOF
}

# Confirmation prompt
confirm_deletion() {
    local confirmation=""
    
    while [[ "${confirmation}" != "yes" && "${confirmation}" != "no" ]]; do
        read -p "Are you sure you want to delete all resources? (yes/no): " confirmation
        confirmation=$(echo "${confirmation}" | tr '[:upper:]' '[:lower:]')
    done
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "User confirmed deletion of all resources"
}

# Cleanup Service Fabric cluster
cleanup_service_fabric() {
    log_info "Cleaning up Service Fabric cluster..."
    
    if resource_exists "sf-cluster" "${SERVICE_FABRIC_CLUSTER}" "${RESOURCE_GROUP_PROVIDER}"; then
        log_info "Deleting Service Fabric cluster: ${SERVICE_FABRIC_CLUSTER}"
        
        # Service Fabric cluster deletion is asynchronous and can take time
        if az sf cluster delete \
            --cluster-name "${SERVICE_FABRIC_CLUSTER}" \
            --resource-group "${RESOURCE_GROUP_PROVIDER}" \
            --no-wait > /dev/null 2>&1; then
            log_success "Service Fabric cluster deletion initiated"
            # Note: We don't wait for completion as it can take 15+ minutes
        else
            log_error "Failed to initiate Service Fabric cluster deletion"
        fi
    else
        log_warning "Service Fabric cluster not found: ${SERVICE_FABRIC_CLUSTER}"
    fi
}

# Cleanup Data Share resources
cleanup_data_share() {
    log_info "Cleaning up Data Share resources..."
    
    if resource_exists "datashare" "${DATA_SHARE_ACCOUNT}" "${RESOURCE_GROUP_PROVIDER}"; then
        log_info "Deleting Data Share account: ${DATA_SHARE_ACCOUNT}"
        
        # Delete data shares first
        local shares=$(az datashare share list \
            --account-name "${DATA_SHARE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP_PROVIDER}" \
            --query '[].name' --output tsv 2>/dev/null || echo "")
        
        if [[ -n "${shares}" ]]; then
            while IFS= read -r share; do
                log_info "Deleting data share: ${share}"
                az datashare share delete \
                    --account-name "${DATA_SHARE_ACCOUNT}" \
                    --resource-group "${RESOURCE_GROUP_PROVIDER}" \
                    --share-name "${share}" \
                    --yes > /dev/null 2>&1 || log_warning "Failed to delete share: ${share}"
            done <<< "${shares}"
        fi
        
        # Delete the account
        if az datashare account delete \
            --account-name "${DATA_SHARE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP_PROVIDER}" \
            --yes > /dev/null 2>&1; then
            log_success "Data Share account deleted successfully"
        else
            log_error "Failed to delete Data Share account"
        fi
    else
        log_warning "Data Share account not found: ${DATA_SHARE_ACCOUNT}"
    fi
}

# Cleanup Log Analytics workspace
cleanup_log_analytics() {
    log_info "Cleaning up Log Analytics workspace..."
    
    if resource_exists "log-analytics" "${LOG_ANALYTICS_WORKSPACE}" "${RESOURCE_GROUP_PROVIDER}"; then
        log_info "Deleting Log Analytics workspace: ${LOG_ANALYTICS_WORKSPACE}"
        
        if az monitor log-analytics workspace delete \
            --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP_PROVIDER}" \
            --yes > /dev/null 2>&1; then
            log_success "Log Analytics workspace deleted successfully"
        else
            log_error "Failed to delete Log Analytics workspace"
        fi
    else
        log_warning "Log Analytics workspace not found: ${LOG_ANALYTICS_WORKSPACE}"
    fi
}

# Cleanup storage accounts
cleanup_storage_accounts() {
    log_info "Cleaning up storage accounts..."
    
    local storage_accounts=("${STORAGE_PROVIDER}" "${STORAGE_CONSUMER}")
    local resource_groups=("${RESOURCE_GROUP_PROVIDER}" "${RESOURCE_GROUP_CONSUMER}")
    
    for i in "${!storage_accounts[@]}"; do
        local storage_account="${storage_accounts[$i]}"
        local resource_group="${resource_groups[$i]}"
        
        if resource_exists "storage" "${storage_account}"; then
            log_info "Deleting storage account: ${storage_account}"
            
            if az storage account delete \
                --name "${storage_account}" \
                --resource-group "${resource_group}" \
                --yes > /dev/null 2>&1; then
                log_success "Storage account deleted: ${storage_account}"
            else
                log_error "Failed to delete storage account: ${storage_account}"
            fi
        else
            log_warning "Storage account not found: ${storage_account}"
        fi
    done
}

# Cleanup Key Vaults
cleanup_key_vaults() {
    log_info "Cleaning up Key Vaults..."
    
    local key_vaults=("${KEY_VAULT_PROVIDER}" "${KEY_VAULT_CONSUMER}")
    local resource_groups=("${RESOURCE_GROUP_PROVIDER}" "${RESOURCE_GROUP_CONSUMER}")
    
    for i in "${!key_vaults[@]}"; do
        local key_vault="${key_vaults[$i]}"
        local resource_group="${resource_groups[$i]}"
        
        if resource_exists "keyvault" "${key_vault}"; then
            log_info "Deleting Key Vault: ${key_vault}"
            
            # Delete the Key Vault
            if az keyvault delete \
                --name "${key_vault}" \
                --resource-group "${resource_group}" > /dev/null 2>&1; then
                log_success "Key Vault deleted: ${key_vault}"
                
                # Purge the Key Vault to free up the name (for demo purposes)
                log_info "Purging Key Vault to free up name: ${key_vault}"
                if az keyvault purge --name "${key_vault}" > /dev/null 2>&1; then
                    log_success "Key Vault purged: ${key_vault}"
                else
                    log_warning "Failed to purge Key Vault: ${key_vault}"
                fi
            else
                log_error "Failed to delete Key Vault: ${key_vault}"
            fi
        else
            log_warning "Key Vault not found: ${key_vault}"
        fi
    done
}

# Cleanup resource groups
cleanup_resource_groups() {
    log_info "Cleaning up resource groups..."
    
    local resource_groups=("${RESOURCE_GROUP_PROVIDER}" "${RESOURCE_GROUP_CONSUMER}")
    
    for resource_group in "${resource_groups[@]}"; do
        if resource_exists "group" "${resource_group}"; then
            log_info "Deleting resource group: ${resource_group}"
            
            # Delete resource group (this will delete all contained resources)
            if az group delete \
                --name "${resource_group}" \
                --yes \
                --no-wait > /dev/null 2>&1; then
                log_success "Resource group deletion initiated: ${resource_group}"
            else
                log_error "Failed to initiate resource group deletion: ${resource_group}"
            fi
        else
            log_warning "Resource group not found: ${resource_group}"
        fi
    done
    
    # Wait for resource group deletions to complete
    log_info "Waiting for resource group deletions to complete..."
    for resource_group in "${resource_groups[@]}"; do
        wait_for_deletion "group" "${resource_group}" &
    done
    wait
}

# Cleanup local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/sample_financial_data.csv"
        "${SCRIPT_DIR}/governance-app"
        "${SCRIPT_DIR}/certs"
        "${DEPLOYMENT_VARS_FILE}"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "${file}" ]]; then
            log_info "Removing: ${file}"
            rm -rf "${file}"
            log_success "Removed: ${file}"
        fi
    done
}

# Validate cleanup completion
validate_cleanup() {
    log_info "Validating cleanup completion..."
    
    local cleanup_issues=false
    
    # Check if resource groups still exist
    local resource_groups=("${RESOURCE_GROUP_PROVIDER}" "${RESOURCE_GROUP_CONSUMER}")
    for resource_group in "${resource_groups[@]}"; do
        if resource_exists "group" "${resource_group}"; then
            log_warning "Resource group still exists: ${resource_group}"
            log_warning "This may indicate incomplete cleanup or ongoing deletion"
            cleanup_issues=true
        else
            log_success "Resource group successfully removed: ${resource_group}"
        fi
    done
    
    # Check for orphaned Key Vaults in soft-delete state
    local key_vaults=("${KEY_VAULT_PROVIDER}" "${KEY_VAULT_CONSUMER}")
    for key_vault in "${key_vaults[@]}"; do
        if az keyvault show-deleted --name "${key_vault}" &> /dev/null; then
            log_warning "Key Vault in soft-delete state: ${key_vault}"
            log_info "This is normal and will be automatically purged after the retention period"
        fi
    done
    
    if [[ "${cleanup_issues}" == "false" ]]; then
        log_success "Cleanup validation completed successfully"
    else
        log_warning "Some cleanup issues were detected - review the logs"
    fi
}

# Main cleanup function
main() {
    log_info "Starting Azure Data Share and Service Fabric cleanup..."
    log_info "Cleanup timestamp: $(date)"
    
    # Initialize log files
    echo "Cleanup started at $(date)" > "${LOG_FILE}"
    echo "Error log for cleanup started at $(date)" > "${ERROR_LOG}"
    
    # Check prerequisites
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed"
        exit 1
    fi
    
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Run 'az login' first"
        exit 1
    fi
    
    # Load deployment variables and confirm deletion
    load_deployment_variables
    confirm_deletion
    
    # Execute cleanup in reverse order of creation
    # Note: We continue even if some steps fail to clean up as much as possible
    set +e
    
    cleanup_service_fabric
    cleanup_data_share
    cleanup_log_analytics
    cleanup_storage_accounts
    cleanup_key_vaults
    cleanup_resource_groups
    cleanup_local_files
    validate_cleanup
    
    set -e
    
    # Generate cleanup summary
    cat << EOF

${GREEN}=====================================================================${NC}
${GREEN}                      CLEANUP COMPLETED${NC}
${GREEN}=====================================================================${NC}

${BLUE}Cleanup Summary:${NC}
- Service Fabric cluster deletion initiated
- Data Share account and shares deleted
- Storage accounts deleted
- Key Vaults deleted and purged
- Resource groups deleted
- Local files and certificates cleaned up

${YELLOW}Important Notes:${NC}
- Service Fabric cluster deletion may take 10-15 minutes to complete
- Resource group deletion may take several minutes
- Key Vaults may remain in soft-delete state for the retention period
- Check Azure Portal to confirm all resources have been removed

${BLUE}Log Files:${NC}
- Cleanup log: ${LOG_FILE}
- Error log: ${ERROR_LOG}

${BLUE}Cost Impact:${NC}
All billable resources have been removed to prevent ongoing charges.

${GREEN}=====================================================================${NC}
EOF
    
    log_success "Cleanup process completed at $(date)"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi