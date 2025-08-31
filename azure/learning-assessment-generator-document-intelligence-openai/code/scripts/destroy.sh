#!/bin/bash

# Azure Learning Assessment Generator - Cleanup Script
# This script safely removes all Azure resources created for the 
# learning assessment generator solution.

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
CLEANUP_START_TIME=$(date +%s)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Cleanup failed with exit code ${exit_code}"
    log_info "Check the log file at: ${LOG_FILE}"
    log_warn "Some resources may still exist. Please check the Azure portal and clean up manually if needed."
    exit $exit_code
}

trap cleanup_on_error ERR

# Display banner
show_banner() {
    echo -e "${BLUE}"
    echo "=================================================================="
    echo "   Azure Learning Assessment Generator - Cleanup Script"
    echo "=================================================================="
    echo -e "${NC}"
    log_info "Starting cleanup of Learning Assessment Generator resources"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check Azure subscription
    local subscription_name=$(az account show --query name -o tsv 2>/dev/null || echo "Unknown")
    local subscription_id=$(az account show --query id -o tsv 2>/dev/null || echo "Unknown")
    log_success "Connected to Azure subscription: ${subscription_name} (${subscription_id})"
}

# Load deployment configuration
load_deployment_config() {
    local config_file="${SCRIPT_DIR}/deployment-config.json"
    
    if [[ -f "${config_file}" ]]; then
        log_info "Loading deployment configuration from: ${config_file}"
        
        # Check if jq is available for JSON parsing
        if command -v jq &> /dev/null; then
            export RESOURCE_GROUP=$(jq -r '.deploymentInfo.resourceGroup' "${config_file}")
            export LOCATION=$(jq -r '.deploymentInfo.location' "${config_file}")
            export RANDOM_SUFFIX=$(jq -r '.deploymentInfo.randomSuffix' "${config_file}")
            
            export STORAGE_ACCOUNT=$(jq -r '.resources.storageAccount' "${config_file}")
            export COSMOSDB_ACCOUNT=$(jq -r '.resources.cosmosdbAccount' "${config_file}")
            export FUNCTION_APP=$(jq -r '.resources.functionApp' "${config_file}")
            export DOCUMENT_INTELLIGENCE=$(jq -r '.resources.documentIntelligence' "${config_file}")
            export OPENAI_ACCOUNT=$(jq -r '.resources.openaiAccount' "${config_file}")
            export INSIGHTS_NAME=$(jq -r '.resources.applicationInsights' "${config_file}")
            
            log_success "Configuration loaded successfully"
        else
            log_warn "jq not available, using manual parsing"
            # Basic grep-based parsing as fallback
            export RESOURCE_GROUP=$(grep '"resourceGroup"' "${config_file}" | cut -d '"' -f 4)
            export LOCATION=$(grep '"location"' "${config_file}" | cut -d '"' -f 4)
        fi
    else
        log_warn "Deployment configuration file not found. Using environment variables or prompting for input."
    fi
}

# Set environment variables with fallbacks
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Use existing environment variables or prompt for required values
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        if [[ "${FORCE_MODE:-false}" == "true" ]]; then
            log_error "Resource group not specified and running in force mode"
            exit 1
        fi
        
        echo -n "Enter the resource group name to delete: "
        read -r RESOURCE_GROUP
        
        if [[ -z "${RESOURCE_GROUP}" ]]; then
            log_error "Resource group name is required"
            exit 1
        fi
    fi
    
    export RESOURCE_GROUP
    
    # Generate resource names using same pattern as deploy script if suffix is available
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-assessstorage${RANDOM_SUFFIX}}"
        export COSMOSDB_ACCOUNT="${COSMOSDB_ACCOUNT:-assess-cosmos-${RANDOM_SUFFIX}}"
        export FUNCTION_APP="${FUNCTION_APP:-assess-functions-${RANDOM_SUFFIX}}"
        export DOCUMENT_INTELLIGENCE="${DOCUMENT_INTELLIGENCE:-assess-doc-intel-${RANDOM_SUFFIX}}"
        export OPENAI_ACCOUNT="${OPENAI_ACCOUNT:-assess-openai-${RANDOM_SUFFIX}}"
        export INSIGHTS_NAME="${INSIGHTS_NAME:-${FUNCTION_APP}-insights}"
    fi
    
    log_success "Environment variables configured:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        log_info "  Random Suffix: ${RANDOM_SUFFIX}"
    fi
}

# Verify resource group exists
verify_resource_group() {
    log_info "Verifying resource group exists: ${RESOURCE_GROUP}"
    
    if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        log_warn "Resource group '${RESOURCE_GROUP}' does not exist or is not accessible"
        
        if [[ "${FORCE_MODE:-false}" == "true" ]]; then
            log_info "Force mode enabled, continuing anyway"
            return 0
        fi
        
        echo -n "Continue anyway? (y/N): "
        read -r response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    else
        log_success "Resource group found"
    fi
}

# List resources in the resource group
list_resources() {
    log_info "Listing resources in resource group: ${RESOURCE_GROUP}"
    
    local resources
    if resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query '[].{Name:name, Type:type, Location:location}' --output table 2>/dev/null); then
        if [[ -n "${resources}" && "${resources}" != "[]" ]]; then
            echo "${resources}" | tee -a "${LOG_FILE}"
            
            # Count resources
            local resource_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query 'length(@)' --output tsv 2>/dev/null || echo "0")
            log_info "Found ${resource_count} resources to delete"
        else
            log_warn "No resources found in resource group"
        fi
    else
        log_warn "Could not list resources (resource group may not exist)"
    fi
}

# Confirm deletion
confirm_deletion() {
    if [[ "${FORCE_MODE:-false}" == "true" ]]; then
        log_warn "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo -e "${RED}"
    echo "⚠️  WARNING: This will permanently delete all resources in the resource group!"
    echo "⚠️  This action CANNOT be undone!"
    echo -e "${NC}"
    echo "Resource group to delete: ${RESOURCE_GROUP}"
    echo ""
    
    # Require explicit confirmation
    echo -n "Type 'DELETE' (in capitals) to confirm deletion: "
    read -r confirmation
    
    if [[ "${confirmation}" != "DELETE" ]]; then
        log_info "Deletion cancelled by user (confirmation not provided)"
        exit 0
    fi
    
    log_warn "User confirmed deletion - proceeding with cleanup"
}

# Delete specific high-cost resources first
delete_high_cost_resources() {
    log_info "Deleting high-cost resources first to minimize charges..."
    
    # Delete Azure OpenAI deployments and account
    if [[ -n "${OPENAI_ACCOUNT:-}" ]]; then
        delete_openai_resources
    fi
    
    # Delete Document Intelligence service
    if [[ -n "${DOCUMENT_INTELLIGENCE:-}" ]]; then
        delete_document_intelligence
    fi
    
    # Delete Cosmos DB account
    if [[ -n "${COSMOSDB_ACCOUNT:-}" ]]; then
        delete_cosmos_db
    fi
    
    # Delete Function App
    if [[ -n "${FUNCTION_APP:-}" ]]; then
        delete_function_app
    fi
}

# Delete Azure OpenAI resources
delete_openai_resources() {
    log_info "Deleting Azure OpenAI resources..."
    
    # Check if OpenAI account exists
    if az cognitiveservices account show --name "${OPENAI_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        # Delete model deployments first
        log_info "Deleting GPT-4o model deployment..."
        if az cognitiveservices account deployment show \
            --name "${OPENAI_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --deployment-name "gpt-4o" &>/dev/null; then
            
            az cognitiveservices account deployment delete \
                --name "${OPENAI_ACCOUNT}" \
                --resource-group "${RESOURCE_GROUP}" \
                --deployment-name "gpt-4o" \
                --output none 2>/dev/null || log_warn "Failed to delete GPT-4o deployment"
            
            log_success "GPT-4o deployment deleted"
        fi
        
        # Delete OpenAI account
        log_info "Deleting Azure OpenAI account: ${OPENAI_ACCOUNT}"
        az cognitiveservices account delete \
            --name "${OPENAI_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none 2>/dev/null || log_warn "Failed to delete OpenAI account"
        
        log_success "Azure OpenAI account deleted"
    else
        log_warn "Azure OpenAI account '${OPENAI_ACCOUNT}' not found"
    fi
}

# Delete Document Intelligence service
delete_document_intelligence() {
    log_info "Deleting Document Intelligence service: ${DOCUMENT_INTELLIGENCE}"
    
    if az cognitiveservices account show --name "${DOCUMENT_INTELLIGENCE}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        az cognitiveservices account delete \
            --name "${DOCUMENT_INTELLIGENCE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none 2>/dev/null || log_warn "Failed to delete Document Intelligence service"
        
        log_success "Document Intelligence service deleted"
    else
        log_warn "Document Intelligence service '${DOCUMENT_INTELLIGENCE}' not found"
    fi
}

# Delete Cosmos DB
delete_cosmos_db() {
    log_info "Deleting Cosmos DB account: ${COSMOSDB_ACCOUNT}"
    
    if az cosmosdb show --name "${COSMOSDB_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        # Cosmos DB deletion can take a while, so we'll do it asynchronously
        az cosmosdb delete \
            --name "${COSMOSDB_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --no-wait \
            --output none 2>/dev/null || log_warn "Failed to initiate Cosmos DB deletion"
        
        log_success "Cosmos DB deletion initiated (this may take several minutes)"
    else
        log_warn "Cosmos DB account '${COSMOSDB_ACCOUNT}' not found"
    fi
}

# Delete Function App
delete_function_app() {
    log_info "Deleting Function App: ${FUNCTION_APP}"
    
    if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        az functionapp delete \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none 2>/dev/null || log_warn "Failed to delete Function App"
        
        log_success "Function App deleted"
    else
        log_warn "Function App '${FUNCTION_APP}' not found"
    fi
}

# Delete Application Insights
delete_application_insights() {
    if [[ -n "${INSIGHTS_NAME:-}" ]]; then
        log_info "Deleting Application Insights: ${INSIGHTS_NAME}"
        
        if az monitor app-insights component show --app "${INSIGHTS_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
            az monitor app-insights component delete \
                --app "${INSIGHTS_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output none 2>/dev/null || log_warn "Failed to delete Application Insights"
            
            log_success "Application Insights deleted"
        else
            log_warn "Application Insights '${INSIGHTS_NAME}' not found"
        fi
    fi
}

# Delete Storage Account
delete_storage_account() {
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        log_info "Deleting Storage Account: ${STORAGE_ACCOUNT}"
        
        if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
            az storage account delete \
                --name "${STORAGE_ACCOUNT}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none 2>/dev/null || log_warn "Failed to delete Storage Account"
            
            log_success "Storage Account deleted"
        else
            log_warn "Storage Account '${STORAGE_ACCOUNT}' not found"
        fi
    fi
}

# Delete remaining resources using resource group deletion
delete_resource_group() {
    log_info "Deleting resource group and all remaining resources: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        # Final check for resources
        local remaining_resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query 'length(@)' --output tsv 2>/dev/null || echo "0")
        
        if [[ "${remaining_resources}" -gt 0 ]]; then
            log_info "Deleting resource group with ${remaining_resources} remaining resources..."
            
            az group delete \
                --name "${RESOURCE_GROUP}" \
                --yes \
                --no-wait \
                --output none
            
            log_success "Resource group deletion initiated"
            log_info "Note: Complete deletion may take several minutes to complete"
        else
            log_info "No resources remaining, deleting empty resource group..."
            
            az group delete \
                --name "${RESOURCE_GROUP}" \
                --yes \
                --output none
            
            log_success "Empty resource group deleted"
        fi
    else
        log_warn "Resource group '${RESOURCE_GROUP}' not found or already deleted"
    fi
}

# Wait for critical deletions to complete
wait_for_deletions() {
    log_info "Waiting for critical resource deletions to complete..."
    
    # Check if resource group still exists
    local max_wait=300  # 5 minutes
    local wait_time=0
    local check_interval=15
    
    while [[ ${wait_time} -lt ${max_wait} ]]; do
        if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
            log_success "Resource group deletion completed"
            return 0
        fi
        
        log_info "Resource group still exists, waiting... (${wait_time}/${max_wait}s)"
        sleep ${check_interval}
        wait_time=$((wait_time + check_interval))
    done
    
    log_warn "Resource group deletion is taking longer than expected"
    log_info "You can check the status in the Azure portal or run: az group show --name '${RESOURCE_GROUP}'"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    local config_file="${SCRIPT_DIR}/deployment-config.json"
    local deploy_log="${SCRIPT_DIR}/deploy.log"
    
    # Ask user if they want to keep local files
    if [[ "${FORCE_MODE:-false}" != "true" ]]; then
        echo -n "Delete local configuration and log files? (y/N): "
        read -r response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            log_info "Keeping local configuration files"
            return 0
        fi
    fi
    
    # Remove configuration file
    if [[ -f "${config_file}" ]]; then
        rm -f "${config_file}"
        log_success "Removed deployment configuration file"
    fi
    
    # Keep deploy log but rename it
    if [[ -f "${deploy_log}" ]]; then
        local archived_log="${SCRIPT_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"
        mv "${deploy_log}" "${archived_log}" 2>/dev/null || true
        log_info "Archived deploy log to: $(basename "${archived_log}")"
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    local cleanup_time=$(($(date +%s) - CLEANUP_START_TIME))
    
    echo -e "${GREEN}"
    echo "=================================================================="
    echo "              CLEANUP COMPLETED SUCCESSFULLY!"
    echo "=================================================================="
    echo -e "${NC}"
    
    echo "🧹 Cleanup Summary:"
    echo "  • Resource Group: ${RESOURCE_GROUP}"
    echo "  • Cleanup Time: ${cleanup_time} seconds"
    echo ""
    echo "✅ Resources Deleted:"
    if [[ -n "${OPENAI_ACCOUNT:-}" ]]; then
        echo "  • Azure OpenAI Service: ${OPENAI_ACCOUNT}"
    fi
    if [[ -n "${DOCUMENT_INTELLIGENCE:-}" ]]; then
        echo "  • Document Intelligence: ${DOCUMENT_INTELLIGENCE}"
    fi
    if [[ -n "${COSMOSDB_ACCOUNT:-}" ]]; then
        echo "  • Cosmos DB: ${COSMOSDB_ACCOUNT}"
    fi
    if [[ -n "${FUNCTION_APP:-}" ]]; then
        echo "  • Function App: ${FUNCTION_APP}"
    fi
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        echo "  • Storage Account: ${STORAGE_ACCOUNT}"
    fi
    if [[ -n "${INSIGHTS_NAME:-}" ]]; then
        echo "  • Application Insights: ${INSIGHTS_NAME}"
    fi
    echo "  • Resource Group: ${RESOURCE_GROUP}"
    echo ""
    echo "📋 Next Steps:"
    echo "  • Verify deletion in Azure portal"
    echo "  • Check Azure billing to confirm no ongoing charges"
    echo "  • Review any archived log files in: ${SCRIPT_DIR}"
    echo ""
    echo "📝 Cleanup log: ${LOG_FILE}"
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
                FORCE_MODE=true
                shift
                ;;
            --keep-logs)
                KEEP_LOGS=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --resource-group NAME    Resource group name to delete"
                echo "  --force                  Skip confirmation prompts"
                echo "  --keep-logs             Keep local log files"
                echo "  --help, -h              Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                                    # Interactive mode"
                echo "  $0 --resource-group my-rg            # Specify resource group"
                echo "  $0 --resource-group my-rg --force    # Skip confirmations"
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                exit 1
                ;;
        esac
    done
}

# Main execution
main() {
    parse_arguments "$@"
    show_banner
    
    # Initialize log file
    echo "Azure Learning Assessment Generator Cleanup Log" > "${LOG_FILE}"
    echo "Started at: $(date)" >> "${LOG_FILE}"
    echo "=========================================" >> "${LOG_FILE}"
    
    check_prerequisites
    load_deployment_config
    set_environment_variables
    verify_resource_group
    list_resources
    confirm_deletion
    
    delete_high_cost_resources
    delete_application_insights
    delete_storage_account
    delete_resource_group
    
    if [[ "${FORCE_MODE:-false}" != "true" ]]; then
        wait_for_deletions
    fi
    
    if [[ "${KEEP_LOGS:-false}" != "true" ]]; then
        cleanup_local_files
    fi
    
    show_cleanup_summary
    
    log_success "Cleanup completed successfully in $(($(date +%s) - CLEANUP_START_TIME)) seconds"
}

# Run main function with all arguments
main "$@"