#!/bin/bash

# =============================================================================
# Azure Invoice Processing Workflow Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deploy.sh script
# including:
# - Azure Resource Group and all contained resources
# - Storage accounts and containers
# - AI Document Intelligence service
# - Logic Apps and API connections
# - Service Bus namespace and queues
# - Function Apps and configurations
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# =============================================================================
# CONFIGURATION AND VALIDATION
# =============================================================================

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/cleanup.log"
readonly ENV_FILE="${SCRIPT_DIR}/.env"
readonly REQUIRED_TOOLS=("az" "jq")

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
cleanup_on_error() {
    error "Cleanup encountered an error. Check ${LOG_FILE} for details."
    warn "Some resources may still exist. Manual cleanup may be required."
    exit 1
}

trap cleanup_on_error ERR

# =============================================================================
# PREREQUISITES VALIDATION
# =============================================================================

validate_prerequisites() {
    info "Validating prerequisites for cleanup..."
    
    # Check required tools
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is required but not installed"
            exit 1
        fi
    done
    
    # Check Azure CLI authentication
    if ! az account show &> /dev/null; then
        error "Azure CLI not authenticated. Run 'az login' first."
        exit 1
    fi
    
    success "Prerequisites validation completed"
}

# =============================================================================
# ENVIRONMENT LOADING
# =============================================================================

load_environment() {
    info "Loading environment variables..."
    
    if [[ ! -f "${ENV_FILE}" ]]; then
        warn "Environment file not found: ${ENV_FILE}"
        warn "Attempting to discover resources by pattern..."
        discover_resources
        return
    fi
    
    # Source environment file
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
    
    # Validate required variables
    local required_vars=(
        "RESOURCE_GROUP"
        "STORAGE_ACCOUNT"
        "DOC_INTELLIGENCE_NAME"
        "LOGIC_APP_NAME"
        "SERVICE_BUS_NAMESPACE"
        "FUNCTION_APP_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            warn "Required variable ${var} not set in environment file"
        else
            info "${var}: ${!var}"
        fi
    done
    
    success "Environment variables loaded successfully"
}

discover_resources() {
    warn "Attempting to discover resources by pattern..."
    
    # Try to find resource groups with invoice-processing pattern
    local rg_list
    rg_list=$(az group list --query "[?contains(name, 'invoice-processing')].name" -o tsv)
    
    if [[ -n "${rg_list}" ]]; then
        info "Found resource groups matching pattern:"
        echo "${rg_list}"
        
        # Use the first match if only one exists
        local rg_count
        rg_count=$(echo "${rg_list}" | wc -l)
        
        if [[ ${rg_count} -eq 1 ]]; then
            export RESOURCE_GROUP="${rg_list}"
            warn "Using discovered resource group: ${RESOURCE_GROUP}"
        else
            error "Multiple resource groups found. Please specify manually."
            echo "Available resource groups:"
            echo "${rg_list}"
            exit 1
        fi
    else
        error "No resource groups found matching 'invoice-processing' pattern"
        error "Please provide the resource group name manually:"
        read -r -p "Resource Group Name: " RESOURCE_GROUP
        export RESOURCE_GROUP
    fi
}

# =============================================================================
# CONFIRMATION AND SAFETY CHECKS
# =============================================================================

confirm_deletion() {
    warn "==================================="
    warn "RESOURCE DELETION CONFIRMATION"
    warn "==================================="
    
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        warn "This will DELETE the following resource group and ALL resources within it:"
        warn "Resource Group: ${RESOURCE_GROUP}"
        
        # List resources in the group
        info "Resources to be deleted:"
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" -o table || true
        fi
    else
        error "No resource group specified for deletion"
        exit 1
    fi
    
    warn ""
    warn "THIS ACTION CANNOT BE UNDONE!"
    warn ""
    
    # Require explicit confirmation
    local confirmation
    while true; do
        read -r -p "Type 'DELETE' to confirm resource deletion: " confirmation
        case "${confirmation}" in
            DELETE)
                info "Deletion confirmed. Proceeding with cleanup..."
                break
                ;;
            *)
                warn "Invalid confirmation. Type 'DELETE' to proceed or Ctrl+C to cancel."
                ;;
        esac
    done
}

# =============================================================================
# RESOURCE CLEANUP FUNCTIONS
# =============================================================================

backup_important_data() {
    info "Checking for important data to backup..."
    
    if [[ -n "${STORAGE_ACCOUNT:-}" ]] && [[ -n "${RESOURCE_GROUP:-}" ]]; then
        # Check if storage account exists and has data
        if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            
            # Get storage key
            local storage_key
            if storage_key=$(az storage account keys list \
                --resource-group "${RESOURCE_GROUP}" \
                --account-name "${STORAGE_ACCOUNT}" \
                --query '[0].value' \
                --output tsv 2> /dev/null); then
                
                # Check if there are blobs to backup
                local blob_count
                if blob_count=$(az storage blob list \
                    --account-name "${STORAGE_ACCOUNT}" \
                    --account-key "${storage_key}" \
                    --container-name "${CONTAINER_NAME:-invoices}" \
                    --query "length(@)" \
                    --output tsv 2> /dev/null); then
                    
                    if [[ ${blob_count} -gt 0 ]]; then
                        warn "Found ${blob_count} files in storage account"
                        
                        local backup_choice
                        read -r -p "Do you want to backup the files before deletion? (y/N): " backup_choice
                        
                        if [[ "${backup_choice}" =~ ^[Yy]$ ]]; then
                            create_backup
                        else
                            warn "Skipping backup. Files will be permanently deleted."
                        fi
                    fi
                fi
            fi
        fi
    fi
}

create_backup() {
    info "Creating backup of storage account data..."
    
    local backup_dir="${SCRIPT_DIR}/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${backup_dir}"
    
    # Download all blobs
    if az storage blob download-batch \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${storage_key}" \
        --source "${CONTAINER_NAME:-invoices}" \
        --destination "${backup_dir}" \
        --pattern "*" 2> /dev/null; then
        
        success "Backup created at: ${backup_dir}"
    else
        warn "Backup creation failed or no files to backup"
    fi
}

cleanup_function_app() {
    if [[ -n "${FUNCTION_APP_NAME:-}" ]] && [[ -n "${RESOURCE_GROUP:-}" ]]; then
        info "Cleaning up Function App: ${FUNCTION_APP_NAME}"
        
        if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az functionapp delete \
                --name "${FUNCTION_APP_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output table
            
            success "Function App deleted: ${FUNCTION_APP_NAME}"
        else
            warn "Function App not found: ${FUNCTION_APP_NAME}"
        fi
    fi
}

cleanup_logic_app() {
    if [[ -n "${LOGIC_APP_NAME:-}" ]] && [[ -n "${RESOURCE_GROUP:-}" ]]; then
        info "Cleaning up Logic App: ${LOGIC_APP_NAME}"
        
        if az logic workflow show --name "${LOGIC_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            # First, disable the workflow to stop any running instances
            az logic workflow update \
                --name "${LOGIC_APP_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --state Disabled \
                --output table
            
            # Wait a moment for running instances to complete
            sleep 10
            
            # Delete the Logic App
            az logic workflow delete \
                --name "${LOGIC_APP_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output table
            
            success "Logic App deleted: ${LOGIC_APP_NAME}"
        else
            warn "Logic App not found: ${LOGIC_APP_NAME}"
        fi
    fi
}

cleanup_api_connections() {
    if [[ -n "${RESOURCE_GROUP:-}" ]] && [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        info "Cleaning up API connections..."
        
        # List and delete blob connections
        local connections
        connections=$(az resource list \
            --resource-group "${RESOURCE_GROUP}" \
            --resource-type Microsoft.Web/connections \
            --query "[?contains(name, 'blob-connection') || contains(name, 'servicebus-connection')].name" \
            -o tsv 2> /dev/null || true)
        
        if [[ -n "${connections}" ]]; then
            while IFS= read -r connection; do
                if [[ -n "${connection}" ]]; then
                    az resource delete \
                        --resource-group "${RESOURCE_GROUP}" \
                        --resource-type Microsoft.Web/connections \
                        --name "${connection}" \
                        --output table
                    
                    success "API connection deleted: ${connection}"
                fi
            done <<< "${connections}"
        else
            warn "No API connections found to delete"
        fi
    fi
}

cleanup_service_bus() {
    if [[ -n "${SERVICE_BUS_NAMESPACE:-}" ]] && [[ -n "${RESOURCE_GROUP:-}" ]]; then
        info "Cleaning up Service Bus namespace: ${SERVICE_BUS_NAMESPACE}"
        
        if az servicebus namespace show --name "${SERVICE_BUS_NAMESPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az servicebus namespace delete \
                --name "${SERVICE_BUS_NAMESPACE}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output table
            
            success "Service Bus namespace deleted: ${SERVICE_BUS_NAMESPACE}"
        else
            warn "Service Bus namespace not found: ${SERVICE_BUS_NAMESPACE}"
        fi
    fi
}

cleanup_document_intelligence() {
    if [[ -n "${DOC_INTELLIGENCE_NAME:-}" ]] && [[ -n "${RESOURCE_GROUP:-}" ]]; then
        info "Cleaning up AI Document Intelligence: ${DOC_INTELLIGENCE_NAME}"
        
        if az cognitiveservices account show --name "${DOC_INTELLIGENCE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az cognitiveservices account delete \
                --name "${DOC_INTELLIGENCE_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output table
            
            success "AI Document Intelligence service deleted: ${DOC_INTELLIGENCE_NAME}"
        else
            warn "AI Document Intelligence service not found: ${DOC_INTELLIGENCE_NAME}"
        fi
    fi
}

cleanup_storage_account() {
    if [[ -n "${STORAGE_ACCOUNT:-}" ]] && [[ -n "${RESOURCE_GROUP:-}" ]]; then
        info "Cleaning up Storage Account: ${STORAGE_ACCOUNT}"
        
        if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az storage account delete \
                --name "${STORAGE_ACCOUNT}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output table
            
            success "Storage Account deleted: ${STORAGE_ACCOUNT}"
        else
            warn "Storage Account not found: ${STORAGE_ACCOUNT}"
        fi
    fi
}

cleanup_event_grid() {
    if [[ -n "${RESOURCE_GROUP:-}" ]] && [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        info "Cleaning up Event Grid system topics..."
        
        local topics
        topics=$(az eventgrid system-topic list \
            --resource-group "${RESOURCE_GROUP}" \
            --query "[?contains(name, 'storage-events')].name" \
            -o tsv 2> /dev/null || true)
        
        if [[ -n "${topics}" ]]; then
            while IFS= read -r topic; do
                if [[ -n "${topic}" ]]; then
                    az eventgrid system-topic delete \
                        --name "${topic}" \
                        --resource-group "${RESOURCE_GROUP}" \
                        --output table
                    
                    success "Event Grid system topic deleted: ${topic}"
                fi
            done <<< "${topics}"
        else
            warn "No Event Grid system topics found to delete"
        fi
    fi
}

cleanup_resource_group() {
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        info "Cleaning up Resource Group: ${RESOURCE_GROUP}"
        
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            # Final confirmation before deleting resource group
            warn "About to delete resource group: ${RESOURCE_GROUP}"
            warn "This will remove ALL remaining resources in the group."
            
            local final_confirmation
            read -r -p "Proceed with resource group deletion? (y/N): " final_confirmation
            
            if [[ "${final_confirmation}" =~ ^[Yy]$ ]]; then
                az group delete \
                    --name "${RESOURCE_GROUP}" \
                    --yes \
                    --no-wait \
                    --output table
                
                success "Resource group deletion initiated: ${RESOURCE_GROUP}"
                info "Deletion is running in the background and may take several minutes to complete."
            else
                warn "Resource group deletion cancelled by user"
                warn "Note: Individual resources have been deleted, but the resource group remains"
            fi
        else
            warn "Resource group not found: ${RESOURCE_GROUP}"
        fi
    fi
}

cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f "${ENV_FILE}" ]]; then
        rm -f "${ENV_FILE}"
        success "Environment file removed: ${ENV_FILE}"
    fi
    
    # Remove test invoice file
    if [[ -f "${SCRIPT_DIR}/test-invoice.pdf" ]]; then
        rm -f "${SCRIPT_DIR}/test-invoice.pdf"
        success "Test invoice file removed"
    fi
    
    # Remove workflow definition file if it exists
    if [[ -f "${SCRIPT_DIR}/workflow-definition.json" ]]; then
        rm -f "${SCRIPT_DIR}/workflow-definition.json"
        success "Workflow definition file removed"
    fi
}

# =============================================================================
# VALIDATION AND VERIFICATION
# =============================================================================

verify_cleanup() {
    info "Verifying cleanup completion..."
    
    local cleanup_success=true
    
    # Check if resource group still exists
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            warn "Resource group still exists (deletion may be in progress): ${RESOURCE_GROUP}"
            
            # List any remaining resources
            local remaining_resources
            remaining_resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2> /dev/null || echo "0")
            
            if [[ ${remaining_resources} -gt 0 ]]; then
                warn "Found ${remaining_resources} remaining resources in the resource group"
                az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" -o table || true
                cleanup_success=false
            fi
        else
            success "Resource group successfully deleted: ${RESOURCE_GROUP}"
        fi
    fi
    
    if [[ "${cleanup_success}" == "true" ]]; then
        success "Cleanup verification completed successfully"
    else
        warn "Some resources may still exist. Manual cleanup may be required."
    fi
}

# =============================================================================
# MAIN CLEANUP FLOW
# =============================================================================

main() {
    info "Starting Azure Invoice Processing Workflow cleanup..."
    info "Log file: ${LOG_FILE}"
    
    # Cleanup steps
    validate_prerequisites
    load_environment
    confirm_deletion
    backup_important_data
    
    # Individual resource cleanup (in reverse order of creation)
    cleanup_api_connections
    cleanup_event_grid
    cleanup_logic_app
    cleanup_function_app
    cleanup_service_bus
    cleanup_document_intelligence
    cleanup_storage_account
    
    # Final cleanup
    cleanup_resource_group
    cleanup_local_files
    verify_cleanup
    
    # Cleanup summary
    success "==================================="
    success "CLEANUP COMPLETED"
    success "==================================="
    info ""
    info "Cleanup log: ${LOG_FILE}"
    
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        info "Resource group: ${RESOURCE_GROUP}"
        info ""
        info "Note: Resource group deletion runs in the background."
        info "Use 'az group show --name ${RESOURCE_GROUP}' to check status."
        info "The resource group will be fully removed when deletion completes."
    fi
    
    info ""
    success "All invoice processing workflow resources have been cleaned up"
    success "Cleanup completed in $((SECONDS / 60)) minutes and $((SECONDS % 60)) seconds"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi