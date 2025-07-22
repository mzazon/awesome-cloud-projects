#!/bin/bash

# Destroy Multi-Region API Gateway with Azure API Management and Cosmos DB
# This script safely removes all resources created by the deploy.sh script
# with proper confirmation prompts and error handling

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deploy_config"

# Colors for output
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

log_info() { 
    log "INFO" "${BLUE}$*${NC}"
}

log_success() { 
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() { 
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() { 
    log "ERROR" "${RED}$*${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup failed. Check ${LOG_FILE} for details."
    log_warning "Some resources may still exist and incur charges."
    log_info "You may need to manually clean up remaining resources in the Azure portal."
    exit 1
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed."
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show &>/dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if config file exists
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Configuration file not found: ${CONFIG_FILE}"
        log_error "This script requires configuration from a successful deployment."
        log_info "If resources exist, you can delete them manually or recreate the config file."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Load configuration
load_configuration() {
    log_info "Loading deployment configuration..."
    
    # Source the configuration file
    source "${CONFIG_FILE}"
    
    # Verify required variables are set
    local required_vars=(
        "RESOURCE_GROUP"
        "APIM_NAME"
        "COSMOS_ACCOUNT"
        "TRAFFIC_MANAGER"
        "WORKSPACE_NAME"
        "APP_INSIGHTS_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable ${var} not found in configuration"
            exit 1
        fi
    done
    
    log_info "Configuration loaded:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  API Management: ${APIM_NAME}"
    log_info "  Cosmos DB: ${COSMOS_ACCOUNT}"
    log_info "  Traffic Manager: ${TRAFFIC_MANAGER}"
    log_info "  Log Analytics: ${WORKSPACE_NAME}"
    log_info "  Application Insights: ${APP_INSIGHTS_NAME}"
}

# Confirmation prompt
confirm_destruction() {
    log_warning "⚠️  WARNING: This will permanently delete all resources!"
    log_warning "This includes:"
    log_warning "  • API Management instance in multiple regions"
    log_warning "  • Cosmos DB account with global replication"
    log_warning "  • Traffic Manager profile and endpoints"
    log_warning "  • Log Analytics workspace and Application Insights"
    log_warning "  • All monitoring alerts and diagnostic settings"
    log_warning "  • The entire resource group: ${RESOURCE_GROUP}"
    echo ""
    
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log_warning "FORCE_DELETE is set, skipping confirmation"
        return 0
    fi
    
    read -r -p "Are you sure you want to continue? Type 'yes' to confirm: " confirmation
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    echo ""
    log_info "🗑️  Proceeding with resource destruction..."
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="${3:-${RESOURCE_GROUP}}"
    
    case "${resource_type}" in
        "group")
            az group show --name "${resource_name}" &>/dev/null
            ;;
        "apim")
            az apim show --name "${resource_name}" --resource-group "${resource_group}" &>/dev/null
            ;;
        "cosmosdb")
            az cosmosdb show --name "${resource_name}" --resource-group "${resource_group}" &>/dev/null
            ;;
        "traffic-manager")
            az network traffic-manager profile show --name "${resource_name}" --resource-group "${resource_group}" &>/dev/null
            ;;
        "workspace")
            az monitor log-analytics workspace show --workspace-name "${resource_name}" --resource-group "${resource_group}" &>/dev/null
            ;;
        "app-insights")
            az monitor app-insights component show --app "${resource_name}" --resource-group "${resource_group}" &>/dev/null
            ;;
        *)
            log_error "Unknown resource type: ${resource_type}"
            return 1
            ;;
    esac
}

# Wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local max_attempts=60  # 10 minutes with 10-second intervals
    local attempt=1
    
    log_info "Waiting for ${resource_type} '${resource_name}' to be deleted..."
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        if ! resource_exists "${resource_type}" "${resource_name}"; then
            log_success "${resource_type} '${resource_name}' has been deleted"
            return 0
        fi
        
        if [[ $((attempt % 6)) -eq 0 ]]; then  # Log every minute
            log_info "Still waiting for ${resource_type} deletion... (${attempt}/${max_attempts})"
        fi
        
        sleep 10
        ((attempt++))
    done
    
    log_warning "${resource_type} '${resource_name}' deletion may still be in progress"
    return 1
}

# Remove Traffic Manager
remove_traffic_manager() {
    log_info "Removing Traffic Manager profile..."
    
    if resource_exists "traffic-manager" "${TRAFFIC_MANAGER}"; then
        log_info "Deleting Traffic Manager profile: ${TRAFFIC_MANAGER}"
        az network traffic-manager profile delete \
            --name "${TRAFFIC_MANAGER}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --output none
        
        log_success "Traffic Manager profile deletion initiated"
    else
        log_info "Traffic Manager profile '${TRAFFIC_MANAGER}' not found, skipping"
    fi
}

# Remove monitoring resources
remove_monitoring() {
    log_info "Removing monitoring resources..."
    
    # Remove Application Insights
    if resource_exists "app-insights" "${APP_INSIGHTS_NAME}"; then
        log_info "Deleting Application Insights: ${APP_INSIGHTS_NAME}"
        az monitor app-insights component delete \
            --app "${APP_INSIGHTS_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --output none
        
        log_success "Application Insights deleted: ${APP_INSIGHTS_NAME}"
    else
        log_info "Application Insights '${APP_INSIGHTS_NAME}' not found, skipping"
    fi
    
    # Remove metric alerts
    log_info "Removing metric alerts..."
    local alerts
    alerts=$(az monitor metrics alert list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" --output tsv 2>/dev/null || true)
    
    if [[ -n "${alerts}" ]]; then
        while IFS= read -r alert; do
            if [[ -n "${alert}" ]]; then
                log_info "Deleting alert: ${alert}"
                az monitor metrics alert delete \
                    --name "${alert}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --yes \
                    --output none || log_warning "Failed to delete alert: ${alert}"
            fi
        done <<< "${alerts}"
    fi
}

# Remove API Management
remove_api_management() {
    log_info "Removing API Management instance..."
    
    if resource_exists "apim" "${APIM_NAME}"; then
        log_warning "⏳ API Management deletion can take 30-45 minutes..."
        log_info "Deleting API Management instance: ${APIM_NAME}"
        
        # Start the deletion (this will remove all regions automatically)
        az apim delete \
            --name "${APIM_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --no-wait \
            --output none
        
        log_success "API Management deletion initiated (running in background)"
        log_info "Note: This operation will continue even if this script exits"
    else
        log_info "API Management instance '${APIM_NAME}' not found, skipping"
    fi
}

# Remove Cosmos DB
remove_cosmos_db() {
    log_info "Removing Cosmos DB account..."
    
    if resource_exists "cosmosdb" "${COSMOS_ACCOUNT}"; then
        log_info "Deleting Cosmos DB account: ${COSMOS_ACCOUNT}"
        az cosmosdb delete \
            --name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --output none
        
        log_success "Cosmos DB account deleted: ${COSMOS_ACCOUNT}"
    else
        log_info "Cosmos DB account '${COSMOS_ACCOUNT}' not found, skipping"
    fi
}

# Remove Log Analytics workspace
remove_log_analytics() {
    log_info "Removing Log Analytics workspace..."
    
    if resource_exists "workspace" "${WORKSPACE_NAME}"; then
        log_info "Deleting Log Analytics workspace: ${WORKSPACE_NAME}"
        az monitor log-analytics workspace delete \
            --workspace-name "${WORKSPACE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --force true \
            --output none
        
        log_success "Log Analytics workspace deleted: ${WORKSPACE_NAME}"
    else
        log_info "Log Analytics workspace '${WORKSPACE_NAME}' not found, skipping"
    fi
}

# Remove resource group
remove_resource_group() {
    log_info "Removing resource group..."
    
    if resource_exists "group" "${RESOURCE_GROUP}"; then
        log_warning "⏳ Resource group deletion may take several minutes..."
        log_info "Deleting resource group: ${RESOURCE_GROUP}"
        
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait \
            --output none
        
        log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        log_info "The resource group and all remaining resources will be deleted in the background"
    else
        log_info "Resource group '${RESOURCE_GROUP}' not found, skipping"
    fi
}

# Cleanup local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove generated files
    local files_to_remove=(
        "${SCRIPT_DIR}/sample-api.json"
        "${CONFIG_FILE}"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_info "Removed: $(basename "${file}")"
        fi
    done
    
    log_success "Local cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup status..."
    
    # Check if resource group still exists
    if resource_exists "group" "${RESOURCE_GROUP}"; then
        log_warning "Resource group '${RESOURCE_GROUP}' still exists"
        log_info "Deletion may still be in progress. Check Azure portal for status."
    else
        log_success "Resource group '${RESOURCE_GROUP}' has been deleted"
    fi
    
    # List any remaining resources (if resource group still exists)
    local remaining_resources
    remaining_resources=$(az resource list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].{Name:name,Type:type}" \
        --output table 2>/dev/null || echo "")
    
    if [[ -n "${remaining_resources}" && "${remaining_resources}" != "Name    Type" ]]; then
        log_warning "Some resources may still exist:"
        echo "${remaining_resources}"
        log_info "These will be deleted when the resource group deletion completes"
    fi
}

# Main cleanup function
main() {
    log_info "Starting multi-region API gateway cleanup..."
    log_info "Log file: ${LOG_FILE}"
    
    check_prerequisites
    load_configuration
    confirm_destruction
    
    # Remove resources in appropriate order
    remove_traffic_manager
    remove_monitoring
    remove_api_management
    remove_cosmos_db
    remove_log_analytics
    
    # Optional: Remove entire resource group (uncomment if desired)
    # This will remove any remaining resources but will also remove the resource group itself
    remove_resource_group
    
    cleanup_local_files
    verify_cleanup
    
    log_success "🎉 Cleanup process completed!"
    log_info "📋 Cleanup Summary:"
    log_info "  ✅ Traffic Manager profile removed"
    log_info "  ✅ Monitoring resources removed"
    log_info "  ⏳ API Management deletion initiated (may take up to 45 minutes)"
    log_info "  ✅ Cosmos DB account removed"
    log_info "  ✅ Log Analytics workspace removed"
    log_info "  ⏳ Resource group deletion initiated"
    log_info "  ✅ Local configuration files cleaned"
    log_info ""
    log_warning "⚠️  Note: Some deletions may still be running in the background"
    log_info "💰 Check the Azure portal to ensure all resources are deleted to avoid charges"
    log_info "📊 Monitor the Azure billing page for charge confirmation"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DELETE="true"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--force] [--help]"
            echo ""
            echo "Options:"
            echo "  --force    Skip confirmation prompts (use with caution)"
            echo "  --help     Show this help message"
            echo ""
            echo "This script removes all resources created by deploy.sh"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"