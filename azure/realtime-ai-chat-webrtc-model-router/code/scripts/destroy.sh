#!/bin/bash

# =============================================================================
# Azure Real-time AI Chat with WebRTC and Model Router - Cleanup Script
# =============================================================================
# This script safely removes all Azure resources created by the deployment
# script for the real-time AI chat application with intelligent model routing.
#
# Version: 1.0
# Last Updated: 2025-07-12
# =============================================================================

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/cleanup.log"
readonly ERROR_LOG="${SCRIPT_DIR}/cleanup_error.log"
readonly DEPLOYMENT_INFO="${SCRIPT_DIR}/deployment_info.env"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables for tracking cleanup progress
RESOURCES_TO_DELETE=()
DELETION_ERRORS=()

# =============================================================================
# Logging and Output Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)
            echo -e "${GREEN}[INFO]${NC} ${message}"
            echo "[${timestamp}] [INFO] ${message}" >> "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} ${message}"
            echo "[${timestamp}] [WARN] ${message}" >> "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} ${message}" >&2
            echo "[${timestamp}] [ERROR] ${message}" >> "$ERROR_LOG"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} ${message}"
            echo "[${timestamp}] [SUCCESS] ${message}" >> "$LOG_FILE"
            ;;
        *)
            echo -e "${BLUE}[DEBUG]${NC} ${message}"
            echo "[${timestamp}] [DEBUG] ${message}" >> "$LOG_FILE"
            ;;
    esac
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup Azure Real-time AI Chat with WebRTC and Model Router resources

OPTIONS:
    -r, --resource-group    Resource group name (auto-detected if deployment_info.env exists)
    -f, --force             Skip all confirmation prompts
    -d, --dry-run           Show what would be deleted without executing
    -k, --keep-rg           Keep the resource group (delete individual resources only)
    -s, --skip-logs         Don't delete log analytics and monitoring resources
    -h, --help              Show this help message
    --delete-deployments    Also delete deployment history

EXAMPLES:
    $0                          # Interactive cleanup with confirmations
    $0 -f                       # Force cleanup without prompts
    $0 -d                       # Preview what would be deleted
    $0 -r my-rg -f              # Force cleanup of specific resource group
    $0 --keep-rg                # Delete resources but keep resource group

EOF
}

# =============================================================================
# Prerequisites and Validation Functions
# =============================================================================

check_prerequisites() {
    log INFO "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log ERROR "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log ERROR "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Verify subscription access
    local subscription_id=$(az account show --query id --output tsv 2>/dev/null)
    local subscription_name=$(az account show --query name --output tsv 2>/dev/null)
    log INFO "Using subscription: ${subscription_name} (${subscription_id})"
    
    log SUCCESS "Prerequisites check completed"
}

load_deployment_info() {
    if [[ -f "$DEPLOYMENT_INFO" ]]; then
        log INFO "Loading deployment information from ${DEPLOYMENT_INFO}"
        source "$DEPLOYMENT_INFO"
        
        log INFO "Loaded deployment information:"
        log INFO "  Resource Group: ${RESOURCE_GROUP:-not set}"
        log INFO "  Location: ${LOCATION:-not set}"
        log INFO "  Deployment Date: ${DEPLOYMENT_DATE:-not set}"
        
        return 0
    else
        log WARN "Deployment info file not found: ${DEPLOYMENT_INFO}"
        log WARN "You may need to specify resource group manually with -r option"
        return 1
    fi
}

validate_resource_group() {
    local rg_name="$1"
    
    if [[ -z "$rg_name" ]]; then
        log ERROR "Resource group name is required"
        log INFO "Either provide -r option or ensure deployment_info.env exists"
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group show --name "$rg_name" &> /dev/null; then
        log WARN "Resource group '${rg_name}' does not exist or is not accessible"
        log INFO "It may have already been deleted or you may not have permissions"
        return 1
    fi
    
    log SUCCESS "Resource group '${rg_name}' found and accessible"
    return 0
}

# =============================================================================
# Resource Discovery Functions
# =============================================================================

discover_resources() {
    local rg_name="$1"
    
    log INFO "Discovering resources in resource group: ${rg_name}"
    
    # Get all resources in the resource group
    local resources=$(az resource list \
        --resource-group "$rg_name" \
        --query "[].{name:name,type:type,id:id}" \
        --output json 2>/dev/null || echo "[]")
    
    if [[ "$resources" == "[]" || -z "$resources" ]]; then
        log WARN "No resources found in resource group ${rg_name}"
        return 0
    fi
    
    # Parse resources and categorize them
    local function_apps=$(echo "$resources" | jq -r '.[] | select(.type=="Microsoft.Web/sites") | .name' 2>/dev/null || true)
    local storage_accounts=$(echo "$resources" | jq -r '.[] | select(.type=="Microsoft.Storage/storageAccounts") | .name' 2>/dev/null || true)
    local signalr_services=$(echo "$resources" | jq -r '.[] | select(.type=="Microsoft.SignalRService/SignalR") | .name' 2>/dev/null || true)
    local openai_services=$(echo "$resources" | jq -r '.[] | select(.type=="Microsoft.CognitiveServices/accounts") | .name' 2>/dev/null || true)
    local app_insights=$(echo "$resources" | jq -r '.[] | select(.type=="Microsoft.Insights/components") | .name' 2>/dev/null || true)
    
    # Log discovered resources
    log INFO "Discovered resources:"
    
    if [[ -n "$function_apps" ]]; then
        log INFO "  Function Apps: $(echo "$function_apps" | tr '\n' ' ')"
        while IFS= read -r app; do
            [[ -n "$app" ]] && RESOURCES_TO_DELETE+=("FUNCTION:${app}")
        done <<< "$function_apps"
    fi
    
    if [[ -n "$storage_accounts" ]]; then
        log INFO "  Storage Accounts: $(echo "$storage_accounts" | tr '\n' ' ')"
        while IFS= read -r storage; do
            [[ -n "$storage" ]] && RESOURCES_TO_DELETE+=("STORAGE:${storage}")
        done <<< "$storage_accounts"
    fi
    
    if [[ -n "$signalr_services" ]]; then
        log INFO "  SignalR Services: $(echo "$signalr_services" | tr '\n' ' ')"
        while IFS= read -r signalr; do
            [[ -n "$signalr" ]] && RESOURCES_TO_DELETE+=("SIGNALR:${signalr}")
        done <<< "$signalr_services"
    fi
    
    if [[ -n "$openai_services" ]]; then
        log INFO "  OpenAI Services: $(echo "$openai_services" | tr '\n' ' ')"
        while IFS= read -r openai; do
            [[ -n "$openai" ]] && RESOURCES_TO_DELETE+=("OPENAI:${openai}")
        done <<< "$openai_services"
    fi
    
    if [[ -n "$app_insights" ]]; then
        log INFO "  Application Insights: $(echo "$app_insights" | tr '\n' ' ')"
        while IFS= read -r insights; do
            [[ -n "$insights" ]] && RESOURCES_TO_DELETE+=("INSIGHTS:${insights}")
        done <<< "$app_insights"
    fi
    
    local total_resources=${#RESOURCES_TO_DELETE[@]}
    log INFO "Total resources to delete: ${total_resources}"
    
    if [[ $total_resources -eq 0 ]]; then
        log WARN "No resources found to delete"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Resource Deletion Functions
# =============================================================================

delete_function_apps() {
    local rg_name="$1"
    
    log INFO "Deleting Function Apps..."
    
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" =~ ^FUNCTION: ]]; then
            local app_name="${resource#FUNCTION:}"
            
            log INFO "Deleting Function App: ${app_name}"
            
            if az functionapp delete \
                --name "$app_name" \
                --resource-group "$rg_name" \
                --output none 2>/dev/null; then
                log SUCCESS "Function App ${app_name} deleted successfully"
            else
                log ERROR "Failed to delete Function App: ${app_name}"
                DELETION_ERRORS+=("Function App: ${app_name}")
            fi
        fi
    done
}

delete_storage_accounts() {
    local rg_name="$1"
    
    log INFO "Deleting Storage Accounts..."
    
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" =~ ^STORAGE: ]]; then
            local storage_name="${resource#STORAGE:}"
            
            log INFO "Deleting Storage Account: ${storage_name}"
            
            # First, try to delete with soft delete protection disabled
            if az storage account delete \
                --name "$storage_name" \
                --resource-group "$rg_name" \
                --yes \
                --output none 2>/dev/null; then
                log SUCCESS "Storage Account ${storage_name} deleted successfully"
            else
                log ERROR "Failed to delete Storage Account: ${storage_name}"
                DELETION_ERRORS+=("Storage Account: ${storage_name}")
            fi
        fi
    done
}

delete_signalr_services() {
    local rg_name="$1"
    
    log INFO "Deleting SignalR Services..."
    
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" =~ ^SIGNALR: ]]; then
            local signalr_name="${resource#SIGNALR:}"
            
            log INFO "Deleting SignalR Service: ${signalr_name}"
            
            if az signalr delete \
                --name "$signalr_name" \
                --resource-group "$rg_name" \
                --yes \
                --output none 2>/dev/null; then
                log SUCCESS "SignalR Service ${signalr_name} deleted successfully"
            else
                log ERROR "Failed to delete SignalR Service: ${signalr_name}"
                DELETION_ERRORS+=("SignalR Service: ${signalr_name}")
            fi
        fi
    done
}

delete_openai_services() {
    local rg_name="$1"
    
    log INFO "Deleting Azure OpenAI Services..."
    
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" =~ ^OPENAI: ]]; then
            local openai_name="${resource#OPENAI:}"
            
            log INFO "Deleting Azure OpenAI Service: ${openai_name}"
            
            # First delete all model deployments
            log INFO "Deleting model deployments for ${openai_name}..."
            local deployments=$(az cognitiveservices account deployment list \
                --name "$openai_name" \
                --resource-group "$rg_name" \
                --query "[].name" \
                --output tsv 2>/dev/null || true)
            
            if [[ -n "$deployments" ]]; then
                while IFS= read -r deployment; do
                    if [[ -n "$deployment" ]]; then
                        log INFO "Deleting deployment: ${deployment}"
                        az cognitiveservices account deployment delete \
                            --name "$openai_name" \
                            --resource-group "$rg_name" \
                            --deployment-name "$deployment" \
                            --output none 2>/dev/null || true
                    fi
                done <<< "$deployments"
            fi
            
            # Wait a moment for deployments to be fully deleted
            sleep 10
            
            # Delete the OpenAI service
            if az cognitiveservices account delete \
                --name "$openai_name" \
                --resource-group "$rg_name" \
                --output none 2>/dev/null; then
                log SUCCESS "Azure OpenAI Service ${openai_name} deleted successfully"
            else
                log ERROR "Failed to delete Azure OpenAI Service: ${openai_name}"
                DELETION_ERRORS+=("Azure OpenAI Service: ${openai_name}")
            fi
        fi
    done
}

delete_insights_components() {
    local rg_name="$1"
    
    log INFO "Deleting Application Insights components..."
    
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" =~ ^INSIGHTS: ]]; then
            local insights_name="${resource#INSIGHTS:}"
            
            log INFO "Deleting Application Insights: ${insights_name}"
            
            if az monitor app-insights component delete \
                --app "$insights_name" \
                --resource-group "$rg_name" \
                --output none 2>/dev/null; then
                log SUCCESS "Application Insights ${insights_name} deleted successfully"
            else
                log ERROR "Failed to delete Application Insights: ${insights_name}"
                DELETION_ERRORS+=("Application Insights: ${insights_name}")
            fi
        fi
    done
}

delete_deployment_history() {
    local rg_name="$1"
    
    log INFO "Deleting deployment history..."
    
    # Get all deployments in the resource group
    local deployments=$(az deployment group list \
        --resource-group "$rg_name" \
        --query "[].name" \
        --output tsv 2>/dev/null || true)
    
    if [[ -n "$deployments" ]]; then
        log INFO "Found deployment history to clean up"
        while IFS= read -r deployment; do
            if [[ -n "$deployment" ]]; then
                log INFO "Deleting deployment: ${deployment}"
                az deployment group delete \
                    --resource-group "$rg_name" \
                    --name "$deployment" \
                    --output none 2>/dev/null || true
            fi
        done <<< "$deployments"
        log SUCCESS "Deployment history cleaned up"
    else
        log INFO "No deployment history found"
    fi
}

delete_resource_group() {
    local rg_name="$1"
    
    log INFO "Deleting resource group: ${rg_name}"
    
    if az group delete \
        --name "$rg_name" \
        --yes \
        --no-wait \
        --output none 2>/dev/null; then
        log SUCCESS "Resource group deletion initiated: ${rg_name}"
        log INFO "Resource group deletion is running in the background"
        log INFO "This may take several minutes to complete"
    else
        log ERROR "Failed to delete resource group: ${rg_name}"
        DELETION_ERRORS+=("Resource Group: ${rg_name}")
    fi
}

# =============================================================================
# Main Cleanup Logic
# =============================================================================

perform_cleanup() {
    local rg_name="$1"
    local keep_rg="$2"
    local skip_logs="$3"
    local delete_deployments_flag="$4"
    
    log INFO "Starting cleanup process..."
    log INFO "Resource Group: ${rg_name}"
    log INFO "Keep Resource Group: ${keep_rg}"
    log INFO "Skip Logs: ${skip_logs}"
    
    # Discover resources to delete
    if ! discover_resources "$rg_name"; then
        log WARN "No resources found to delete"
        return 0
    fi
    
    # Delete resources in the correct order to handle dependencies
    delete_function_apps "$rg_name"
    
    # Wait for Function Apps to be fully deleted before deleting storage
    log INFO "Waiting for Function Apps to be fully deleted..."
    sleep 30
    
    delete_storage_accounts "$rg_name"
    delete_signalr_services "$rg_name"
    delete_openai_services "$rg_name"
    
    if [[ "$skip_logs" != "true" ]]; then
        delete_insights_components "$rg_name"
    fi
    
    if [[ "$delete_deployments_flag" == "true" ]]; then
        delete_deployment_history "$rg_name"
    fi
    
    # Delete resource group if requested
    if [[ "$keep_rg" != "true" ]]; then
        # Wait a bit for all resources to be fully deleted
        log INFO "Waiting for resources to be fully deleted before removing resource group..."
        sleep 60
        delete_resource_group "$rg_name"
    fi
    
    # Report results
    local total_errors=${#DELETION_ERRORS[@]}
    
    if [[ $total_errors -eq 0 ]]; then
        log SUCCESS "Cleanup completed successfully!"
    else
        log WARN "Cleanup completed with ${total_errors} errors:"
        for error in "${DELETION_ERRORS[@]}"; do
            log ERROR "  - ${error}"
        done
        log WARN "You may need to manually delete the failed resources"
    fi
    
    # Clean up deployment info file
    if [[ -f "$DEPLOYMENT_INFO" && "$keep_rg" != "true" ]]; then
        rm -f "$DEPLOYMENT_INFO"
        log INFO "Deployment info file removed"
    fi
    
    log INFO "Cleanup process completed"
}

show_dry_run() {
    local rg_name="$1"
    local keep_rg="$2"
    local skip_logs="$3"
    local delete_deployments_flag="$4"
    
    log INFO "=== DRY RUN MODE ==="
    log INFO "The following actions would be performed:"
    log INFO ""
    
    if discover_resources "$rg_name"; then
        log INFO "Resources that would be deleted:"
        
        for resource in "${RESOURCES_TO_DELETE[@]}"; do
            local type="${resource%%:*}"
            local name="${resource#*:}"
            
            case "$type" in
                FUNCTION)
                    log INFO "  - Function App: ${name}"
                    ;;
                STORAGE)
                    log INFO "  - Storage Account: ${name}"
                    ;;
                SIGNALR)
                    log INFO "  - SignalR Service: ${name}"
                    ;;
                OPENAI)
                    log INFO "  - Azure OpenAI Service: ${name} (including model deployments)"
                    ;;
                INSIGHTS)
                    if [[ "$skip_logs" != "true" ]]; then
                        log INFO "  - Application Insights: ${name}"
                    else
                        log INFO "  - Application Insights: ${name} (SKIPPED - logs preserved)"
                    fi
                    ;;
            esac
        done
        
        if [[ "$delete_deployments_flag" == "true" ]]; then
            log INFO "  - Deployment history in resource group"
        fi
        
        if [[ "$keep_rg" != "true" ]]; then
            log INFO "  - Resource Group: ${rg_name}"
        else
            log INFO "  - Resource Group: ${rg_name} (PRESERVED)"
        fi
    else
        log INFO "No resources found to delete in resource group: ${rg_name}"
    fi
    
    log INFO ""
    log INFO "Run without --dry-run to execute the cleanup"
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    # Set default values
    local resource_group=""
    local force=false
    local dry_run=false
    local keep_rg=false
    local skip_logs=false
    local delete_deployments_flag=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--resource-group)
                resource_group="$2"
                shift 2
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -k|--keep-rg)
                keep_rg=true
                shift
                ;;
            -s|--skip-logs)
                skip_logs=true
                shift
                ;;
            --delete-deployments)
                delete_deployments_flag=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "=== Cleanup started at $(date) ===" > "$LOG_FILE"
    echo "=== Cleanup error log started at $(date) ===" > "$ERROR_LOG"
    
    log INFO "Azure Real-time AI Chat with WebRTC Cleanup Script"
    log INFO "Script version: 1.0"
    log INFO ""
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment info if available and resource group not specified
    if [[ -z "$resource_group" ]]; then
        if load_deployment_info; then
            resource_group="$RESOURCE_GROUP"
        fi
    fi
    
    # Validate resource group
    if ! validate_resource_group "$resource_group"; then
        exit 1
    fi
    
    # Show dry run information
    if [[ "$dry_run" == "true" ]]; then
        show_dry_run "$resource_group" "$keep_rg" "$skip_logs" "$delete_deployments_flag"
        exit 0
    fi
    
    # Show warning and get confirmation unless force mode
    if [[ "$force" != "true" ]]; then
        log WARN "This will delete Azure resources and cannot be undone!"
        log INFO "Resource Group: ${resource_group}"
        
        if [[ "$keep_rg" == "true" ]]; then
            log INFO "Resource group will be preserved"
        else
            log INFO "Resource group will be deleted"
        fi
        
        if [[ "$skip_logs" == "true" ]]; then
            log INFO "Log resources will be preserved"
        fi
        
        echo
        read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
        if [[ ! $REPLY == "yes" ]]; then
            log INFO "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Perform cleanup
    perform_cleanup "$resource_group" "$keep_rg" "$skip_logs" "$delete_deployments_flag"
    
    # Final message
    log INFO ""
    if [[ "$keep_rg" == "true" ]]; then
        log SUCCESS "Cleanup completed. Resource group '${resource_group}' was preserved."
    else
        log SUCCESS "Cleanup completed. Resource group '${resource_group}' deletion initiated."
        log INFO "Check the Azure portal to confirm all resources have been removed."
    fi
}

# Run main function with all arguments
main "$@"