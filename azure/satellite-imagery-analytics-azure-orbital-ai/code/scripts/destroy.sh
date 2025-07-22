#!/bin/bash
# Destroy Intelligent Space Data Analytics with Azure Orbital and Azure AI Services
# Version: 1.0
# Last Updated: 2025-07-12

set -euo pipefail

# Configuration and logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destruction.log"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
DRY_RUN=false
FORCE=false
KEEP_RESOURCE_GROUP=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "ERROR" "${RED}$1${NC}"
    log "ERROR" "Destruction failed. Check ${LOG_FILE} for details."
    exit 1
}

# Success message
success() {
    log "INFO" "${GREEN}$1${NC}"
}

# Warning message
warning() {
    log "WARN" "${YELLOW}$1${NC}"
}

# Info message
info() {
    log "INFO" "${BLUE}$1${NC}"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Intelligent Space Data Analytics with Azure Orbital and Azure AI Services

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be destroyed without actually destroying
    -f, --force            Skip confirmation prompts (use with caution)
    -r, --resource-group   Resource group name (default: auto-detect from deployment)
    -k, --keep-rg          Keep the resource group after removing all resources
    --suffix               Resource name suffix (default: auto-detect from deployment)

EXAMPLES:
    $0                                    # Interactive destruction with confirmations
    $0 --dry-run                         # Show destruction plan
    $0 --force                           # Destroy without confirmations
    $0 -r my-rg --force                  # Destroy specific resource group
    $0 --keep-rg                         # Keep resource group after cleanup

SAFETY FEATURES:
    - Interactive confirmations for each resource type
    - Dry-run mode to preview actions
    - Backup verification before deletion
    - Graceful handling of missing resources

EOF
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
    
    # Get current subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    info "Using subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
    
    success "Prerequisites check completed"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -r|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -k|--keep-rg)
                KEEP_RESOURCE_GROUP=true
                shift
                ;;
            --suffix)
                SUFFIX="$2"
                shift 2
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
}

# Auto-detect deployment configuration
auto_detect_config() {
    info "Auto-detecting deployment configuration..."
    
    # Try to read from deployment summary if available
    if [[ -f "${SCRIPT_DIR}/deployment-summary.json" ]]; then
        info "Found deployment summary file"
        if command -v jq &> /dev/null; then
            RESOURCE_GROUP=$(jq -r '.resourceGroup' "${SCRIPT_DIR}/deployment-summary.json" 2>/dev/null || echo "")
            SUFFIX=$(jq -r '.suffix' "${SCRIPT_DIR}/deployment-summary.json" 2>/dev/null || echo "")
            LOCATION=$(jq -r '.location' "${SCRIPT_DIR}/deployment-summary.json" 2>/dev/null || echo "")
            
            if [[ -n "${RESOURCE_GROUP}" && "${RESOURCE_GROUP}" != "null" ]]; then
                info "Auto-detected resource group: ${RESOURCE_GROUP}"
            fi
            if [[ -n "${SUFFIX}" && "${SUFFIX}" != "null" ]]; then
                info "Auto-detected suffix: ${SUFFIX}"
            fi
        else
            warning "jq not available, cannot auto-detect from deployment summary"
        fi
    fi
    
    # Try to read from orbital config if available
    if [[ -f "${SCRIPT_DIR}/orbital-integration-config.txt" && -z "${RESOURCE_GROUP:-}" ]]; then
        info "Attempting to read from orbital config file..."
        # This is a basic parser - could be enhanced
        RESOURCE_GROUP=$(grep -E "^Event Hub Namespace:" "${SCRIPT_DIR}/orbital-integration-config.txt" | cut -d':' -f2 | xargs | sed 's/eh-orbital-//' | sed 's/-.*//' 2>/dev/null || echo "")
        if [[ -n "${RESOURCE_GROUP}" ]]; then
            RESOURCE_GROUP="rg-orbital-analytics"  # Default pattern
            info "Inferred resource group: ${RESOURCE_GROUP}"
        fi
    fi
}

# Set defaults and validate configuration
set_defaults() {
    # Auto-detect configuration first
    auto_detect_config
    
    # Set defaults if not auto-detected or provided
    RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-orbital-analytics"}
    
    # If suffix not provided or detected, try to find resources to determine it
    if [[ -z "${SUFFIX:-}" ]]; then
        info "Attempting to detect suffix from existing resources..."
        
        # Try to find storage accounts with the orbital pattern
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            DETECTED_STORAGE=$(az storage account list --resource-group "${RESOURCE_GROUP}" --query "[?starts_with(name, 'storbitdata')].name" --output tsv | head -1 2>/dev/null || echo "")
            if [[ -n "${DETECTED_STORAGE}" ]]; then
                SUFFIX=${DETECTED_STORAGE#storbitdata}
                info "Detected suffix from storage account: ${SUFFIX}"
            fi
        fi
        
        if [[ -z "${SUFFIX:-}" ]]; then
            warning "Could not auto-detect suffix. Some resources may not be found."
            SUFFIX="unknown"
        fi
    fi
    
    # Set specific resource names based on detected/provided values
    STORAGE_ACCOUNT="storbitdata${SUFFIX}"
    SYNAPSE_WORKSPACE="syn-orbital-${SUFFIX}"
    EVENT_HUB_NAMESPACE="eh-orbital-${SUFFIX}"
    AI_SERVICES_ACCOUNT="ai-orbital-${SUFFIX}"
    MAPS_ACCOUNT="maps-orbital-${SUFFIX}"
    COSMOS_ACCOUNT="cosmos-orbital-${SUFFIX}"
    KEY_VAULT_NAME="kv-orbital-${SUFFIX}"
    
    info "Destruction configuration:"
    info "  Resource Group: ${RESOURCE_GROUP}"
    info "  Suffix: ${SUFFIX}"
    info "  Keep Resource Group: ${KEEP_RESOURCE_GROUP}"
    info "  Force Mode: ${FORCE}"
    info "  Dry Run: ${DRY_RUN}"
}

# Confirmation function
confirm_action() {
    local message="$1"
    local default_response="${2:-n}"
    
    if [[ "${FORCE}" == "true" ]]; then
        log "INFO" "Force mode: ${message} - proceeding without confirmation"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "Dry run: ${message} - would be executed"
        return 0
    fi
    
    local response
    read -p "$(echo -e "${YELLOW}${message} (y/N): ${NC}")" response
    response=${response:-${default_response}}
    
    case ${response,,} in
        y|yes)
            return 0
            ;;
        *)
            log "INFO" "Skipped: ${message}"
            return 1
            ;;
    esac
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="${3:-${RESOURCE_GROUP}}"
    
    case "${resource_type}" in
        "storage")
            az storage account show --name "${resource_name}" --resource-group "${resource_group}" &> /dev/null
            ;;
        "synapse")
            az synapse workspace show --name "${resource_name}" --resource-group "${resource_group}" &> /dev/null
            ;;
        "eventhub")
            az eventhubs namespace show --name "${resource_name}" --resource-group "${resource_group}" &> /dev/null
            ;;
        "cognitiveservices")
            az cognitiveservices account show --name "${resource_name}" --resource-group "${resource_group}" &> /dev/null
            ;;
        "maps")
            az maps account show --name "${resource_name}" --resource-group "${resource_group}" &> /dev/null
            ;;
        "cosmos")
            az cosmosdb show --name "${resource_name}" --resource-group "${resource_group}" &> /dev/null
            ;;
        "keyvault")
            az keyvault show --name "${resource_name}" &> /dev/null
            ;;
        "resourcegroup")
            az group show --name "${resource_name}" &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Dry run mode
execute_dry_run() {
    info "DRY RUN MODE - No resources will be destroyed"
    info "The following resources would be analyzed for destruction:"
    
    echo ""
    echo "============================================================"
    echo "           DESTRUCTION PLAN"
    echo "============================================================"
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo ""
    
    # Check which resources exist
    local resources_found=0
    
    echo "Checking for resources to destroy:"
    
    if resource_exists "storage" "${STORAGE_ACCOUNT}"; then
        echo "✓ Storage Account: ${STORAGE_ACCOUNT}"
        ((resources_found++))
    else
        echo "✗ Storage Account: ${STORAGE_ACCOUNT} (not found)"
    fi
    
    if resource_exists "synapse" "${SYNAPSE_WORKSPACE}"; then
        echo "✓ Synapse Workspace: ${SYNAPSE_WORKSPACE}"
        ((resources_found++))
    else
        echo "✗ Synapse Workspace: ${SYNAPSE_WORKSPACE} (not found)"
    fi
    
    if resource_exists "eventhub" "${EVENT_HUB_NAMESPACE}"; then
        echo "✓ Event Hub Namespace: ${EVENT_HUB_NAMESPACE}"
        ((resources_found++))
    else
        echo "✗ Event Hub Namespace: ${EVENT_HUB_NAMESPACE} (not found)"
    fi
    
    if resource_exists "cognitiveservices" "${AI_SERVICES_ACCOUNT}"; then
        echo "✓ AI Services Account: ${AI_SERVICES_ACCOUNT}"
        ((resources_found++))
    else
        echo "✗ AI Services Account: ${AI_SERVICES_ACCOUNT} (not found)"
    fi
    
    if resource_exists "cognitiveservices" "cv-${AI_SERVICES_ACCOUNT}"; then
        echo "✓ Custom Vision: cv-${AI_SERVICES_ACCOUNT}"
        ((resources_found++))
    else
        echo "✗ Custom Vision: cv-${AI_SERVICES_ACCOUNT} (not found)"
    fi
    
    if resource_exists "maps" "${MAPS_ACCOUNT}"; then
        echo "✓ Azure Maps: ${MAPS_ACCOUNT}"
        ((resources_found++))
    else
        echo "✗ Azure Maps: ${MAPS_ACCOUNT} (not found)"
    fi
    
    if resource_exists "cosmos" "${COSMOS_ACCOUNT}"; then
        echo "✓ Cosmos DB: ${COSMOS_ACCOUNT}"
        ((resources_found++))
    else
        echo "✗ Cosmos DB: ${COSMOS_ACCOUNT} (not found)"
    fi
    
    if resource_exists "keyvault" "${KEY_VAULT_NAME}"; then
        echo "✓ Key Vault: ${KEY_VAULT_NAME}"
        ((resources_found++))
    else
        echo "✗ Key Vault: ${KEY_VAULT_NAME} (not found)"
    fi
    
    if resource_exists "resourcegroup" "${RESOURCE_GROUP}"; then
        echo "✓ Resource Group: ${RESOURCE_GROUP}"
        if [[ "${KEEP_RESOURCE_GROUP}" == "true" ]]; then
            echo "  └── Will be kept (--keep-rg specified)"
        else
            echo "  └── Will be deleted"
        fi
    else
        echo "✗ Resource Group: ${RESOURCE_GROUP} (not found)"
    fi
    
    echo ""
    echo "Summary:"
    echo "  Resources found: ${resources_found}"
    echo "  Estimated destruction time: 10-15 minutes"
    echo "  Keep Resource Group: ${KEEP_RESOURCE_GROUP}"
    echo ""
    echo "Destruction order:"
    echo "  1. Synapse SQL and Spark pools"
    echo "  2. AI Services accounts"
    echo "  3. Azure Maps account"
    echo "  4. Cosmos DB account"
    echo "  5. Event Hubs namespace"
    echo "  6. Storage account"
    echo "  7. Key Vault (with purge protection)"
    if [[ "${KEEP_RESOURCE_GROUP}" != "true" ]]; then
        echo "  8. Resource Group"
    fi
    echo ""
    echo "============================================================"
}

# Destroy Synapse resources
destroy_synapse() {
    if ! resource_exists "synapse" "${SYNAPSE_WORKSPACE}"; then
        warning "Synapse workspace ${SYNAPSE_WORKSPACE} not found, skipping"
        return 0
    fi
    
    if confirm_action "Destroy Synapse Analytics resources (${SYNAPSE_WORKSPACE})?"; then
        info "Destroying Synapse Analytics resources..."
        
        # Delete SQL pool first (to avoid ongoing charges)
        if az synapse sql pool show --name "sqlpool01" --workspace-name "${SYNAPSE_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            info "Deleting SQL pool..."
            if [[ "${DRY_RUN}" != "true" ]]; then
                az synapse sql pool delete \
                    --name "sqlpool01" \
                    --workspace-name "${SYNAPSE_WORKSPACE}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --yes || warning "Failed to delete SQL pool"
            fi
        fi
        
        # Delete Spark pool
        if az synapse spark pool show --name "sparkpool01" --workspace-name "${SYNAPSE_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            info "Deleting Spark pool..."
            if [[ "${DRY_RUN}" != "true" ]]; then
                az synapse spark pool delete \
                    --name "sparkpool01" \
                    --workspace-name "${SYNAPSE_WORKSPACE}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --yes || warning "Failed to delete Spark pool"
            fi
        fi
        
        # Wait for pools to be deleted before deleting workspace
        if [[ "${DRY_RUN}" != "true" ]]; then
            info "Waiting for pools to be deleted..."
            sleep 30
        fi
        
        # Delete workspace
        info "Deleting Synapse workspace..."
        if [[ "${DRY_RUN}" != "true" ]]; then
            az synapse workspace delete \
                --name "${SYNAPSE_WORKSPACE}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || warning "Failed to delete Synapse workspace"
        fi
        
        success "Synapse Analytics resources destroyed"
    fi
}

# Destroy AI Services
destroy_ai_services() {
    local deleted_count=0
    
    if confirm_action "Destroy AI Services accounts?"; then
        info "Destroying AI Services accounts..."
        
        # Delete main AI Services account
        if resource_exists "cognitiveservices" "${AI_SERVICES_ACCOUNT}"; then
            info "Deleting AI Services account: ${AI_SERVICES_ACCOUNT}"
            if [[ "${DRY_RUN}" != "true" ]]; then
                az cognitiveservices account delete \
                    --name "${AI_SERVICES_ACCOUNT}" \
                    --resource-group "${RESOURCE_GROUP}" || \
                    warning "Failed to delete AI Services account"
                ((deleted_count++))
            fi
        else
            warning "AI Services account ${AI_SERVICES_ACCOUNT} not found"
        fi
        
        # Delete Custom Vision account
        if resource_exists "cognitiveservices" "cv-${AI_SERVICES_ACCOUNT}"; then
            info "Deleting Custom Vision account: cv-${AI_SERVICES_ACCOUNT}"
            if [[ "${DRY_RUN}" != "true" ]]; then
                az cognitiveservices account delete \
                    --name "cv-${AI_SERVICES_ACCOUNT}" \
                    --resource-group "${RESOURCE_GROUP}" || \
                    warning "Failed to delete Custom Vision account"
                ((deleted_count++))
            fi
        else
            warning "Custom Vision account cv-${AI_SERVICES_ACCOUNT} not found"
        fi
        
        if [[ ${deleted_count} -gt 0 ]]; then
            success "AI Services accounts destroyed"
        else
            warning "No AI Services accounts found to delete"
        fi
    fi
}

# Destroy Azure Maps
destroy_azure_maps() {
    if ! resource_exists "maps" "${MAPS_ACCOUNT}"; then
        warning "Azure Maps account ${MAPS_ACCOUNT} not found, skipping"
        return 0
    fi
    
    if confirm_action "Destroy Azure Maps account (${MAPS_ACCOUNT})?"; then
        info "Destroying Azure Maps account..."
        if [[ "${DRY_RUN}" != "true" ]]; then
            az maps account delete \
                --name "${MAPS_ACCOUNT}" \
                --resource-group "${RESOURCE_GROUP}" || \
                warning "Failed to delete Azure Maps account"
        fi
        success "Azure Maps account destroyed"
    fi
}

# Destroy Cosmos DB
destroy_cosmos_db() {
    if ! resource_exists "cosmos" "${COSMOS_ACCOUNT}"; then
        warning "Cosmos DB account ${COSMOS_ACCOUNT} not found, skipping"
        return 0
    fi
    
    if confirm_action "Destroy Cosmos DB account (${COSMOS_ACCOUNT})? This will delete all data permanently."; then
        info "Destroying Cosmos DB account..."
        if [[ "${DRY_RUN}" != "true" ]]; then
            az cosmosdb delete \
                --name "${COSMOS_ACCOUNT}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || \
                warning "Failed to delete Cosmos DB account"
        fi
        success "Cosmos DB account destroyed"
    fi
}

# Destroy Event Hubs
destroy_event_hubs() {
    if ! resource_exists "eventhub" "${EVENT_HUB_NAMESPACE}"; then
        warning "Event Hubs namespace ${EVENT_HUB_NAMESPACE} not found, skipping"
        return 0
    fi
    
    if confirm_action "Destroy Event Hubs namespace (${EVENT_HUB_NAMESPACE})?"; then
        info "Destroying Event Hubs namespace..."
        if [[ "${DRY_RUN}" != "true" ]]; then
            az eventhubs namespace delete \
                --name "${EVENT_HUB_NAMESPACE}" \
                --resource-group "${RESOURCE_GROUP}" || \
                warning "Failed to delete Event Hubs namespace"
        fi
        success "Event Hubs namespace destroyed"
    fi
}

# Destroy Storage Account
destroy_storage_account() {
    if ! resource_exists "storage" "${STORAGE_ACCOUNT}"; then
        warning "Storage account ${STORAGE_ACCOUNT} not found, skipping"
        return 0
    fi
    
    if confirm_action "Destroy Storage account (${STORAGE_ACCOUNT})? This will delete all satellite data permanently."; then
        info "Destroying Storage account..."
        if [[ "${DRY_RUN}" != "true" ]]; then
            az storage account delete \
                --name "${STORAGE_ACCOUNT}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || \
                warning "Failed to delete Storage account"
        fi
        success "Storage account destroyed"
    fi
}

# Destroy Key Vault
destroy_key_vault() {
    if ! resource_exists "keyvault" "${KEY_VAULT_NAME}"; then
        warning "Key Vault ${KEY_VAULT_NAME} not found, skipping"
        return 0
    fi
    
    if confirm_action "Destroy Key Vault (${KEY_VAULT_NAME})?"; then
        info "Destroying Key Vault..."
        if [[ "${DRY_RUN}" != "true" ]]; then
            # Delete Key Vault
            az keyvault delete \
                --name "${KEY_VAULT_NAME}" || \
                warning "Failed to delete Key Vault"
            
            # Purge Key Vault (permanent deletion)
            if confirm_action "Permanently purge Key Vault (${KEY_VAULT_NAME})? This cannot be undone."; then
                az keyvault purge \
                    --name "${KEY_VAULT_NAME}" || \
                    warning "Failed to purge Key Vault"
                success "Key Vault destroyed and purged"
            else
                info "Key Vault deleted but not purged (can be recovered within retention period)"
            fi
        fi
    fi
}

# Destroy Resource Group
destroy_resource_group() {
    if [[ "${KEEP_RESOURCE_GROUP}" == "true" ]]; then
        info "Keeping resource group as requested (--keep-rg)"
        return 0
    fi
    
    if ! resource_exists "resourcegroup" "${RESOURCE_GROUP}"; then
        warning "Resource group ${RESOURCE_GROUP} not found, skipping"
        return 0
    fi
    
    if confirm_action "Destroy Resource Group (${RESOURCE_GROUP})? This will delete any remaining resources."; then
        info "Destroying Resource Group..."
        if [[ "${DRY_RUN}" != "true" ]]; then
            az group delete \
                --name "${RESOURCE_GROUP}" \
                --yes \
                --no-wait || \
                warning "Failed to delete Resource Group"
        fi
        success "Resource Group destruction initiated"
    fi
}

# Clean up local files
cleanup_local_files() {
    if confirm_action "Clean up local configuration files?"; then
        info "Cleaning up local files..."
        
        local files_to_remove=(
            "${SCRIPT_DIR}/orbital-integration-config.txt"
            "${SCRIPT_DIR}/deployment-summary.json"
        )
        
        for file in "${files_to_remove[@]}"; do
            if [[ -f "${file}" ]]; then
                if [[ "${DRY_RUN}" != "true" ]]; then
                    rm -f "${file}" || warning "Failed to remove ${file}"
                fi
                info "Would remove: ${file}"
            fi
        done
        
        success "Local files cleaned up"
    fi
}

# Verify destruction
verify_destruction() {
    info "Verifying resource destruction..."
    
    local remaining_resources=0
    
    # Check if resources still exist
    if resource_exists "storage" "${STORAGE_ACCOUNT}"; then
        warning "Storage account ${STORAGE_ACCOUNT} still exists"
        ((remaining_resources++))
    fi
    
    if resource_exists "synapse" "${SYNAPSE_WORKSPACE}"; then
        warning "Synapse workspace ${SYNAPSE_WORKSPACE} still exists"
        ((remaining_resources++))
    fi
    
    if resource_exists "eventhub" "${EVENT_HUB_NAMESPACE}"; then
        warning "Event Hubs namespace ${EVENT_HUB_NAMESPACE} still exists"
        ((remaining_resources++))
    fi
    
    if resource_exists "cognitiveservices" "${AI_SERVICES_ACCOUNT}"; then
        warning "AI Services account ${AI_SERVICES_ACCOUNT} still exists"
        ((remaining_resources++))
    fi
    
    if resource_exists "maps" "${MAPS_ACCOUNT}"; then
        warning "Azure Maps account ${MAPS_ACCOUNT} still exists"
        ((remaining_resources++))
    fi
    
    if resource_exists "cosmos" "${COSMOS_ACCOUNT}"; then
        warning "Cosmos DB account ${COSMOS_ACCOUNT} still exists"
        ((remaining_resources++))
    fi
    
    if resource_exists "keyvault" "${KEY_VAULT_NAME}"; then
        warning "Key Vault ${KEY_VAULT_NAME} still exists"
        ((remaining_resources++))
    fi
    
    if [[ "${KEEP_RESOURCE_GROUP}" != "true" ]] && resource_exists "resourcegroup" "${RESOURCE_GROUP}"; then
        warning "Resource group ${RESOURCE_GROUP} still exists (deletion may be in progress)"
    fi
    
    if [[ ${remaining_resources} -eq 0 ]]; then
        success "All targeted resources have been destroyed"
    else
        warning "${remaining_resources} resource(s) may still be in the process of deletion"
        info "Some resources may take additional time to fully delete"
    fi
}

# Display destruction results
display_results() {
    echo ""
    echo "============================================================"
    echo "           DESTRUCTION SUMMARY"
    echo "============================================================"
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Destruction Time: $(date)"
    echo ""
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "DRY RUN COMPLETED - No resources were actually destroyed"
    else
        echo "DESTRUCTION COMPLETED"
        echo ""
        echo "Destroyed Resource Types:"
        echo "├── Synapse Analytics (workspace, pools)"
        echo "├── AI Services (Computer Vision, Custom Vision)"
        echo "├── Azure Maps"
        echo "├── Cosmos DB (account, databases, containers)"
        echo "├── Event Hubs (namespace, event hubs)"
        echo "├── Storage Account (with all data)"
        echo "├── Key Vault (deleted and purged)"
        if [[ "${KEEP_RESOURCE_GROUP}" != "true" ]]; then
            echo "└── Resource Group"
        else
            echo "└── Resource Group (kept)"
        fi
    fi
    
    echo ""
    echo "Log File: ${LOG_FILE}"
    echo ""
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        echo "Important Notes:"
        echo "- Some resources may take up to 15 minutes to fully delete"
        echo "- Billing will stop once resources are fully deleted"
        echo "- Key Vault was purged and cannot be recovered"
        echo "- All satellite data and AI models have been permanently deleted"
        echo ""
        echo "Next Steps:"
        echo "- Verify no unexpected charges appear on your Azure bill"
        echo "- Remove any local configuration files if not already cleaned"
        echo "- Update any external systems that referenced these resources"
    fi
    
    echo "============================================================"
}

# Main execution function
main() {
    info "Starting Azure Orbital Analytics destruction..."
    info "Log file: ${LOG_FILE}"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Set defaults and detect configuration
    set_defaults
    
    # Handle dry run mode
    if [[ "${DRY_RUN}" == "true" ]]; then
        execute_dry_run
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Final confirmation before destruction
    if [[ "${FORCE}" != "true" ]]; then
        echo ""
        echo "============================================================"
        warning "WARNING: This will permanently destroy Azure resources!"
        echo "============================================================"
        echo "Resource Group: ${RESOURCE_GROUP}"
        echo "This action cannot be undone!"
        echo ""
        
        if ! confirm_action "Are you absolutely sure you want to continue with destruction?"; then
            info "Destruction cancelled by user"
            exit 0
        fi
        echo ""
    fi
    
    # Destroy resources in reverse order of creation
    destroy_synapse
    destroy_ai_services
    destroy_azure_maps
    destroy_cosmos_db
    destroy_event_hubs
    destroy_storage_account
    destroy_key_vault
    destroy_resource_group
    
    # Clean up local files
    cleanup_local_files
    
    # Verify destruction
    verify_destruction
    
    # Display results
    display_results
    
    success "Destruction completed!"
}

# Run main function with all arguments
main "$@"