#!/bin/bash
set -e

# =============================================================================
# Azure Serverless AI Agents with OpenAI Service and Container Instances
# Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deployment script
# Prerequisites: Azure CLI installed and authenticated

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# =============================================================================
# Prerequisites Check
# =============================================================================

log "Starting Azure Serverless AI Agents cleanup..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it first: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error "Please log in to Azure CLI first: az login"
fi

log "Prerequisites check passed ✅"

# =============================================================================
# Configuration
# =============================================================================

# Default resource group pattern
DEFAULT_RESOURCE_GROUP_PATTERN="rg-ai-agents-*"

# Allow override of resource group
RESOURCE_GROUP="${RESOURCE_GROUP:-}"

# If no resource group specified, try to find one
if [[ -z "${RESOURCE_GROUP}" ]]; then
    info "No resource group specified, searching for AI agents resource groups..."
    
    # Find resource groups matching the pattern
    RESOURCE_GROUPS=$(az group list --query "[?starts_with(name, 'rg-ai-agents-')].name" --output tsv)
    
    if [[ -z "${RESOURCE_GROUPS}" ]]; then
        error "No AI agents resource groups found. Please specify RESOURCE_GROUP environment variable."
    fi
    
    # If multiple resource groups found, ask user to choose
    if [[ $(echo "${RESOURCE_GROUPS}" | wc -l) -gt 1 ]]; then
        warn "Multiple AI agents resource groups found:"
        echo "${RESOURCE_GROUPS}" | nl
        echo ""
        read -p "Please enter the number of the resource group to delete (or press Ctrl+C to cancel): " selection
        
        RESOURCE_GROUP=$(echo "${RESOURCE_GROUPS}" | sed -n "${selection}p")
        
        if [[ -z "${RESOURCE_GROUP}" ]]; then
            error "Invalid selection. Exiting."
        fi
    else
        RESOURCE_GROUP="${RESOURCE_GROUPS}"
    fi
fi

info "Target resource group: ${RESOURCE_GROUP}"

# =============================================================================
# Safety Functions
# =============================================================================

confirm_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    
    warn "About to delete ${resource_type}: ${resource_name}"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        info "Deletion cancelled by user."
        exit 0
    fi
}

check_resource_group_exists() {
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Resource group '${RESOURCE_GROUP}' not found. It may have already been deleted."
        exit 0
    fi
}

list_resources() {
    log "Listing resources in resource group: ${RESOURCE_GROUP}"
    
    local resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type, Location:location}" --output table)
    
    if [[ -z "${resources}" ]]; then
        warn "No resources found in resource group ${RESOURCE_GROUP}"
        return 1
    fi
    
    echo "${resources}"
    return 0
}

# =============================================================================
# Resource Cleanup Functions
# =============================================================================

cleanup_container_instances() {
    log "Cleaning up Container Instances..."
    
    local container_groups=$(az container list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null)
    
    if [[ -n "${container_groups}" ]]; then
        for container_group in ${container_groups}; do
            info "Deleting container group: ${container_group}"
            az container delete \
                --name "${container_group}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes
        done
        log "Container instances cleaned up ✅"
    else
        info "No container instances found"
    fi
}

cleanup_function_apps() {
    log "Cleaning up Function Apps..."
    
    local function_apps=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null)
    
    if [[ -n "${function_apps}" ]]; then
        for function_app in ${function_apps}; do
            info "Deleting function app: ${function_app}"
            az functionapp delete \
                --name "${function_app}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes
        done
        log "Function apps cleaned up ✅"
    else
        info "No function apps found"
    fi
}

cleanup_app_service_plans() {
    log "Cleaning up App Service Plans..."
    
    local app_service_plans=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null)
    
    if [[ -n "${app_service_plans}" ]]; then
        for plan in ${app_service_plans}; do
            info "Deleting app service plan: ${plan}"
            az appservice plan delete \
                --name "${plan}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes
        done
        log "App service plans cleaned up ✅"
    else
        info "No app service plans found"
    fi
}

cleanup_container_registries() {
    log "Cleaning up Container Registries..."
    
    local registries=$(az acr list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null)
    
    if [[ -n "${registries}" ]]; then
        for registry in ${registries}; do
            info "Deleting container registry: ${registry}"
            az acr delete \
                --name "${registry}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes
        done
        log "Container registries cleaned up ✅"
    else
        info "No container registries found"
    fi
}

cleanup_openai_resources() {
    log "Cleaning up Azure OpenAI resources..."
    
    local openai_resources=$(az cognitiveservices account list --resource-group "${RESOURCE_GROUP}" --query "[?kind=='OpenAI'].name" --output tsv 2>/dev/null)
    
    if [[ -n "${openai_resources}" ]]; then
        for openai_resource in ${openai_resources}; do
            info "Deleting OpenAI resource: ${openai_resource}"
            az cognitiveservices account delete \
                --name "${openai_resource}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes
        done
        log "OpenAI resources cleaned up ✅"
    else
        info "No OpenAI resources found"
    fi
}

cleanup_eventgrid_topics() {
    log "Cleaning up Event Grid topics..."
    
    local eventgrid_topics=$(az eventgrid topic list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null)
    
    if [[ -n "${eventgrid_topics}" ]]; then
        for topic in ${eventgrid_topics}; do
            info "Deleting Event Grid topic: ${topic}"
            az eventgrid topic delete \
                --name "${topic}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes
        done
        log "Event Grid topics cleaned up ✅"
    else
        info "No Event Grid topics found"
    fi
}

cleanup_application_insights() {
    log "Cleaning up Application Insights..."
    
    local insights_resources=$(az monitor app-insights component list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null)
    
    if [[ -n "${insights_resources}" ]]; then
        for insights in ${insights_resources}; do
            info "Deleting Application Insights: ${insights}"
            az monitor app-insights component delete \
                --app "${insights}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes
        done
        log "Application Insights cleaned up ✅"
    else
        info "No Application Insights found"
    fi
}

cleanup_logic_apps() {
    log "Cleaning up Logic Apps..."
    
    local logic_apps=$(az logic workflow list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null)
    
    if [[ -n "${logic_apps}" ]]; then
        for logic_app in ${logic_apps}; do
            info "Deleting Logic App: ${logic_app}"
            az logic workflow delete \
                --name "${logic_app}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes
        done
        log "Logic Apps cleaned up ✅"
    else
        info "No Logic Apps found"
    fi
}

cleanup_storage_accounts() {
    log "Cleaning up Storage Accounts..."
    
    local storage_accounts=$(az storage account list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null)
    
    if [[ -n "${storage_accounts}" ]]; then
        for storage_account in ${storage_accounts}; do
            info "Deleting storage account: ${storage_account}"
            az storage account delete \
                --name "${storage_account}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes
        done
        log "Storage accounts cleaned up ✅"
    else
        info "No storage accounts found"
    fi
}

cleanup_resource_group() {
    log "Cleaning up Resource Group: ${RESOURCE_GROUP}"
    
    # Final confirmation for resource group deletion
    warn "This will delete the entire resource group and ALL resources within it."
    confirm_deletion "resource group" "${RESOURCE_GROUP}"
    
    info "Deleting resource group: ${RESOURCE_GROUP}"
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    
    log "Resource group deletion initiated ✅"
    info "Note: Resource group deletion may take several minutes to complete"
}

wait_for_deletion() {
    log "Waiting for resource group deletion to complete..."
    
    local max_wait=300  # 5 minutes maximum wait
    local wait_time=0
    local check_interval=10
    
    while az group show --name "${RESOURCE_GROUP}" &> /dev/null; do
        if [[ ${wait_time} -ge ${max_wait} ]]; then
            warn "Resource group deletion is taking longer than expected"
            info "You can check the status with: az group show --name ${RESOURCE_GROUP}"
            break
        fi
        
        info "Still deleting... (${wait_time}s elapsed)"
        sleep ${check_interval}
        wait_time=$((wait_time + check_interval))
    done
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log "Resource group deletion completed ✅"
    fi
}

# =============================================================================
# Main Cleanup Flow
# =============================================================================

cleanup_individual_resources() {
    log "Starting individual resource cleanup..."
    
    # Clean up resources in reverse order of dependencies
    cleanup_container_instances
    cleanup_function_apps
    cleanup_app_service_plans
    cleanup_logic_apps
    cleanup_eventgrid_topics
    cleanup_application_insights
    cleanup_container_registries
    cleanup_openai_resources
    cleanup_storage_accounts
    
    log "Individual resource cleanup completed ✅"
}

main() {
    log "Starting cleanup process..."
    
    # Check if resource group exists
    check_resource_group_exists
    
    # List resources before cleanup
    if ! list_resources; then
        info "No resources found to clean up"
        exit 0
    fi
    
    echo ""
    confirm_deletion "all resources in resource group" "${RESOURCE_GROUP}"
    
    # Choose cleanup method
    echo ""
    info "Cleanup options:"
    info "1. Quick cleanup (delete entire resource group)"
    info "2. Detailed cleanup (delete resources individually, then resource group)"
    echo ""
    read -p "Please choose an option (1-2): " cleanup_option
    
    case "${cleanup_option}" in
        1)
            log "Performing quick cleanup..."
            cleanup_resource_group
            wait_for_deletion
            ;;
        2)
            log "Performing detailed cleanup..."
            cleanup_individual_resources
            cleanup_resource_group
            wait_for_deletion
            ;;
        *)
            error "Invalid option selected. Exiting."
            ;;
    esac
    
    log "==================================="
    log "Cleanup completed successfully! ✅"
    log "==================================="
    
    info "All resources have been deleted"
    info "Resource group: ${RESOURCE_GROUP}"
    info ""
    info "To verify deletion:"
    info "az group show --name ${RESOURCE_GROUP}"
    info ""
    info "Expected result: ResourceGroupNotFound error"
}

# =============================================================================
# Additional Utility Functions
# =============================================================================

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Clean up Azure Serverless AI Agents infrastructure"
    echo ""
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  --list-only          List resources without deleting"
    echo "  --force              Skip confirmation prompts (use with caution)"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP       Specific resource group to delete"
    echo ""
    echo "Examples:"
    echo "  ./destroy.sh"
    echo "  ./destroy.sh --list-only"
    echo "  RESOURCE_GROUP=rg-ai-agents-abc123 ./destroy.sh"
    echo "  RESOURCE_GROUP=rg-ai-agents-abc123 ./destroy.sh --force"
    echo ""
    echo "Safety Features:"
    echo "  - Confirmation prompts for destructive actions"
    echo "  - Resource listing before deletion"
    echo "  - Individual resource cleanup option"
    echo "  - Automatic resource group detection"
}

list_only() {
    log "Listing resources only (no deletion)"
    
    check_resource_group_exists
    
    if list_resources; then
        info "Use './destroy.sh' to delete these resources"
    else
        info "No resources found to delete"
    fi
}

force_cleanup() {
    log "Force cleanup enabled - skipping confirmations"
    
    check_resource_group_exists
    
    if ! list_resources; then
        info "No resources found to clean up"
        exit 0
    fi
    
    cleanup_resource_group
    wait_for_deletion
    
    log "Force cleanup completed ✅"
}

# =============================================================================
# Script Execution
# =============================================================================

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --list-only)
            list_only
            exit 0
            ;;
        --force)
            force_cleanup
            exit 0
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
    shift
done

# Run main cleanup
main "$@"