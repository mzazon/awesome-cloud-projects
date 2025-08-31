#!/bin/bash

# =============================================================================
# Azure Service Bus Message Queue Cleanup Script
# =============================================================================
# Description: Safely removes Azure Service Bus resources and test files
#              with confirmation prompts and comprehensive logging
# Recipe: Simple Message Queue with Service Bus
# Services: Azure Service Bus, Azure CLI
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# =============================================================================
# CONFIGURATION
# =============================================================================

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy-$(date +%Y%m%d-%H%M%S).log"

# Default values
FORCE_DELETE="${FORCE_DELETE:-false}"
KEEP_RESOURCE_GROUP="${KEEP_RESOURCE_GROUP:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# =============================================================================
# LOGGING AND UTILITY FUNCTIONS
# =============================================================================

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2
}

log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] ✅ $*" | tee -a "${LOG_FILE}"
}

show_usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Safely destroy Azure Service Bus resources created by the deployment script.

OPTIONS:
    -h, --help              Show this help message
    -g, --resource-group    Resource group name to delete
    -n, --namespace         Service Bus namespace name to delete
    --force                 Skip all confirmation prompts
    --keep-rg              Keep the resource group, only delete Service Bus resources
    --list                 List resources that would be deleted without deleting them
    --dry-run              Show what would be deleted without actually deleting

ENVIRONMENT VARIABLES:
    FORCE_DELETE           Skip confirmation prompts (true/false)
    KEEP_RESOURCE_GROUP    Keep resource group after cleanup (true/false)
    SKIP_CONFIRMATION      Skip interactive confirmations (true/false)

EXAMPLES:
    ${SCRIPT_NAME}                          # Interactive cleanup with prompts
    ${SCRIPT_NAME} --force                  # Delete without prompts
    ${SCRIPT_NAME} --list                   # Show what would be deleted
    ${SCRIPT_NAME} --dry-run                # Preview deletion
    ${SCRIPT_NAME} -g rg-servicebus-recipe-abc123  # Delete specific resource group

SAFETY FEATURES:
    - Interactive confirmation prompts
    - Resource verification before deletion
    - Comprehensive logging
    - Graceful error handling
    - Option to keep resource groups

EOF
}

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if logged in to Azure
    local account_check
    if ! account_check=$(az account show --query name --output tsv 2>/dev/null); then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    log_info "Logged in to Azure account: ${account_check}"
    
    # Get subscription information
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    log_info "Using subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
    
    log_success "Prerequisites check completed"
}

# =============================================================================
# RESOURCE DISCOVERY FUNCTIONS
# =============================================================================

discover_resources() {
    log_info "Discovering Service Bus resources..."
    
    # Find resource groups that match our naming pattern
    local resource_groups=()
    while IFS= read -r rg; do
        resource_groups+=("$rg")
    done < <(az group list --query "[?starts_with(name, 'rg-servicebus-recipe') || starts_with(name, 'rg-recipe')].name" --output tsv 2>/dev/null || true)
    
    if [[ ${#resource_groups[@]} -eq 0 ]]; then
        log_warn "No Service Bus recipe resource groups found matching naming patterns."
        log_info "Searched for groups starting with: 'rg-servicebus-recipe' or 'rg-recipe'"
        return 1
    fi
    
    log_info "Found ${#resource_groups[@]} potential resource group(s):"
    printf '%s\n' "${resource_groups[@]}" | while read -r rg; do
        log_info "  - ${rg}"
    done
    
    # If resource group was specified, validate it exists
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        if [[ ! " ${resource_groups[*]} " =~ " ${RESOURCE_GROUP} " ]]; then
            log_error "Specified resource group '${RESOURCE_GROUP}' not found or doesn't match expected patterns"
            exit 1
        fi
        DISCOVERED_RESOURCE_GROUPS=("${RESOURCE_GROUP}")
    else
        DISCOVERED_RESOURCE_GROUPS=("${resource_groups[@]}")
    fi
    
    return 0
}

list_resources_in_group() {
    local resource_group="$1"
    
    log_info "Resources in ${resource_group}:"
    
    # List Service Bus namespaces
    local namespaces
    namespaces=$(az servicebus namespace list --resource-group "${resource_group}" --query "[].{name:name, location:location, sku:sku.tier}" --output table 2>/dev/null || echo "None found")
    if [[ "${namespaces}" != "None found" ]]; then
        echo "  Service Bus Namespaces:"
        echo "${namespaces}" | sed 's/^/    /'
        
        # List queues in each namespace
        while IFS= read -r namespace; do
            if [[ -n "${namespace}" && "${namespace}" != "Name" && "${namespace}" != "----" ]]; then
                local namespace_name
                namespace_name=$(echo "${namespace}" | awk '{print $1}')
                log_info "  Queues in namespace '${namespace_name}':"
                local queues
                queues=$(az servicebus queue list --resource-group "${resource_group}" --namespace-name "${namespace_name}" --query "[].{name:name, status:status, messageCount:messageCount}" --output table 2>/dev/null || echo "    No queues found")
                echo "${queues}" | sed 's/^/      /'
            fi
        done < <(az servicebus namespace list --resource-group "${resource_group}" --query "[].name" --output tsv 2>/dev/null || true)
    else
        echo "  Service Bus Namespaces: None found"
    fi
    
    # List all other resources
    local other_resources
    other_resources=$(az resource list --resource-group "${resource_group}" --query "[?type!='Microsoft.ServiceBus/namespaces'].{name:name, type:type, location:location}" --output table 2>/dev/null || echo "None found")
    if [[ "${other_resources}" != "None found" ]]; then
        echo "  Other Resources:"
        echo "${other_resources}" | sed 's/^/    /'
    fi
}

confirm_deletion() {
    local resource_group="$1"
    
    if [[ "${SKIP_CONFIRMATION}" == "true" || "${FORCE_DELETE}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "⚠️  WARNING: This will permanently delete the following resource group and ALL its contents:"
    echo "   Resource Group: ${resource_group}"
    echo ""
    
    list_resources_in_group "${resource_group}"
    
    echo ""
    echo "💡 This action cannot be undone!"
    echo ""
    
    local response
    read -p "Are you sure you want to delete resource group '${resource_group}'? [y/N]: " response
    
    case "${response}" in
        [yY]|[yY][eE][sS])
            log_info "User confirmed deletion of ${resource_group}"
            return 0
            ;;
        *)
            log_info "User cancelled deletion of ${resource_group}"
            return 1
            ;;
    esac
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

cleanup_test_files() {
    log_info "Cleaning up test files..."
    
    local test_dir="${SCRIPT_DIR}/servicebus-test"
    
    if [[ -d "${test_dir}" ]]; then
        log_info "Removing test directory: ${test_dir}"
        rm -rf "${test_dir}"
        log_success "Test directory removed"
    else
        log_info "Test directory not found, skipping cleanup"
    fi
    
    # Clean up any deployment logs older than 7 days
    find "${SCRIPT_DIR}" -name "deploy-*.log" -mtime +7 -delete 2>/dev/null || true
    find "${SCRIPT_DIR}" -name "destroy-*.log" -mtime +7 -delete 2>/dev/null || true
    
    log_success "Test files cleanup completed"
}

delete_servicebus_resources() {
    local resource_group="$1"
    
    log_info "Deleting Service Bus resources in ${resource_group}..."
    
    # Get all Service Bus namespaces in the resource group
    local namespaces
    readarray -t namespaces < <(az servicebus namespace list --resource-group "${resource_group}" --query "[].name" --output tsv 2>/dev/null || true)
    
    if [[ ${#namespaces[@]} -eq 0 ]]; then
        log_info "No Service Bus namespaces found in ${resource_group}"
        return 0
    fi
    
    for namespace in "${namespaces[@]}"; do
        if [[ -n "${namespace}" ]]; then
            log_info "Deleting Service Bus namespace: ${namespace}"
            
            # Delete namespace (this will delete all queues, topics, and subscriptions within it)
            if az servicebus namespace delete \
                --resource-group "${resource_group}" \
                --name "${namespace}" \
                --no-wait \
                --output none 2>/dev/null; then
                log_success "Service Bus namespace deletion initiated: ${namespace}"
            else
                log_warn "Failed to delete Service Bus namespace: ${namespace} (may not exist)"
            fi
        fi
    done
    
    # Wait for namespace deletions to complete
    log_info "Waiting for Service Bus namespace deletions to complete..."
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    while [[ ${wait_time} -lt ${max_wait} ]]; do
        local remaining_namespaces
        remaining_namespaces=$(az servicebus namespace list --resource-group "${resource_group}" --query "length([?provisioningState!='Deleting'])" --output tsv 2>/dev/null || echo "0")
        
        if [[ "${remaining_namespaces}" == "0" ]]; then
            log_success "All Service Bus namespaces deleted successfully"
            break
        fi
        
        log_info "Waiting for namespace deletions... (${wait_time}s/${max_wait}s)"
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    if [[ ${wait_time} -ge ${max_wait} ]]; then
        log_warn "Timeout waiting for namespace deletions. Continuing with resource group deletion."
    fi
}

delete_resource_group() {
    local resource_group="$1"
    
    log_info "Deleting resource group: ${resource_group}"
    
    # Check if resource group exists before attempting deletion
    if ! az group show --name "${resource_group}" &>/dev/null; then
        log_warn "Resource group ${resource_group} does not exist or has already been deleted"
        return 0
    fi
    
    # Delete the resource group
    if az group delete \
        --name "${resource_group}" \
        --yes \
        --no-wait \
        --output none 2>/dev/null; then
        log_success "Resource group deletion initiated: ${resource_group}"
        
        # Monitor deletion progress
        log_info "Monitoring resource group deletion progress..."
        local max_wait=600  # 10 minutes
        local wait_time=0
        
        while [[ ${wait_time} -lt ${max_wait} ]]; do
            if ! az group exists --name "${resource_group}" --output tsv 2>/dev/null | grep -q "true"; then
                log_success "Resource group deleted successfully: ${resource_group}"
                return 0
            fi
            
            log_info "Resource group deletion in progress... (${wait_time}s/${max_wait}s)"
            sleep 15
            wait_time=$((wait_time + 15))
        done
        
        log_warn "Resource group deletion is taking longer than expected. It may complete in the background."
        log_info "You can check the status in the Azure portal or run: az group exists --name ${resource_group}"
        
    else
        log_error "Failed to initiate resource group deletion: ${resource_group}"
        return 1
    fi
}

# =============================================================================
# MAIN CLEANUP FUNCTION
# =============================================================================

cleanup_resources() {
    log_info "Starting Azure Service Bus resource cleanup..."
    log_info "Log file: ${LOG_FILE}"
    
    # Check prerequisites
    check_prerequisites
    
    # Discover resources to delete
    if ! discover_resources; then
        log_warn "No resources found to clean up"
        return 0
    fi
    
    # Clean up test files first
    cleanup_test_files
    
    # Process each discovered resource group
    for resource_group in "${DISCOVERED_RESOURCE_GROUPS[@]}"; do
        if [[ -n "${resource_group}" ]]; then
            log_info "Processing resource group: ${resource_group}"
            
            # Show what will be deleted and confirm
            if ! confirm_deletion "${resource_group}"; then
                log_info "Skipping deletion of ${resource_group}"
                continue
            fi
            
            if [[ "${KEEP_RESOURCE_GROUP}" == "true" ]]; then
                # Only delete Service Bus resources, keep the resource group
                delete_servicebus_resources "${resource_group}"
                log_success "Service Bus resources deleted from ${resource_group} (resource group preserved)"
            else
                # Delete the entire resource group
                delete_resource_group "${resource_group}"
            fi
        fi
    done
    
    log_success "Cleanup completed successfully!"
    
    # Display cleanup summary
    echo ""
    echo "======================================================================"
    echo "CLEANUP SUMMARY"
    echo "======================================================================"
    echo "Processed Resource Groups: ${#DISCOVERED_RESOURCE_GROUPS[@]}"
    for rg in "${DISCOVERED_RESOURCE_GROUPS[@]}"; do
        echo "  - ${rg}"
    done
    echo ""
    echo "Actions Performed:"
    echo "- Cleaned up test files and directories"
    if [[ "${KEEP_RESOURCE_GROUP}" == "true" ]]; then
        echo "- Deleted Service Bus namespaces and queues"
        echo "- Preserved resource groups"
    else
        echo "- Deleted resource groups and all contained resources"
    fi
    echo ""
    echo "Cost Impact:"
    echo "- Service Bus resources have been removed"
    echo "- No further charges will be incurred"
    echo "- Final billing cycle will include usage until deletion"
    echo ""
    echo "Next Steps:"
    echo "- Verify deletion in the Azure portal"
    echo "- Check your Azure billing to confirm charges have stopped"
    echo "- Remove any stored connection strings from applications"
    echo "======================================================================"
}

# =============================================================================
# COMMAND LINE ARGUMENT PARSING
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -n|--namespace)
                SERVICEBUS_NAMESPACE="$2"
                shift 2
                ;;
            --force)
                FORCE_DELETE="true"
                SKIP_CONFIRMATION="true"
                shift
                ;;
            --keep-rg)
                KEEP_RESOURCE_GROUP="true"
                shift
                ;;
            --list)
                log_info "LIST MODE - Showing resources that would be deleted"
                if discover_resources; then
                    for rg in "${DISCOVERED_RESOURCE_GROUPS[@]}"; do
                        echo ""
                        echo "Resource Group: ${rg}"
                        list_resources_in_group "${rg}"
                    done
                fi
                exit 0
                ;;
            --dry-run)
                log_info "DRY RUN MODE - No resources will be deleted"
                if discover_resources; then
                    log_info "Would delete ${#DISCOVERED_RESOURCE_GROUPS[@]} resource group(s)"
                    for rg in "${DISCOVERED_RESOURCE_GROUPS[@]}"; do
                        log_info "  - ${rg}"
                    done
                fi
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_info "Azure Service Bus Cleanup Script Starting..."
    log_info "Script: ${SCRIPT_NAME}"
    log_info "Version: 1.0"
    log_info "Date: $(date)"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Run cleanup
    cleanup_resources
    
    log_success "Script execution completed successfully!"
}

# Execute main function with all arguments
main "$@"