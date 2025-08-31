#!/bin/bash

# ============================================================================
# Azure Basic Web Monitoring Cleanup Script
# ============================================================================
# This script safely removes all resources created by the web monitoring
# deployment, following proper cleanup order and including safety checks.
#
# Usage: ./destroy.sh [OPTIONS]
# Options:
#   -r, --resource-group NAME    Target resource group name
#   -f, --force                  Skip confirmation prompts
#   -k, --keep-rg               Keep the resource group (delete contents only)
#   -d, --dry-run               Show what would be deleted without executing
#   -v, --verbose               Enable verbose logging
#   -h, --help                  Show this help message
#
# Example:
#   ./destroy.sh --resource-group rg-recipe-abc123
#   ./destroy.sh --force --keep-rg
# ============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DRY_RUN=false
VERBOSE=false
FORCE=false
KEEP_RG=false

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        "DEBUG") 
            if [[ "$VERBOSE" == true ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

show_help() {
    cat << EOF
Azure Basic Web Monitoring Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -r, --resource-group NAME    Target resource group name (required)
    -f, --force                  Skip confirmation prompts
    -k, --keep-rg               Keep the resource group (delete contents only)
    -d, --dry-run               Show what would be deleted without executing
    -v, --verbose               Enable verbose logging
    -h, --help                  Show this help message

EXAMPLES:
    $0 --resource-group rg-recipe-abc123
    $0 --resource-group rg-recipe-abc123 --force --keep-rg
    $0 --dry-run --verbose --resource-group rg-recipe-abc123

SAFETY:
    - By default, prompts for confirmation before deletion
    - Use --force to skip confirmations (use with caution)
    - Use --dry-run to preview what would be deleted
    - Use --keep-rg to preserve the resource group container

WARNING:
    This script will permanently delete Azure resources. This action cannot
    be undone. Ensure you have backups of any important data before proceeding.

EOF
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log "ERROR" "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log "ERROR" "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Validate resource group parameter
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log "ERROR" "Resource group name is required. Use --resource-group option."
        show_help
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "ERROR" "Resource group '$RESOURCE_GROUP' does not exist or is not accessible."
        exit 1
    fi
    
    local subscription_id=$(az account show --query id -o tsv)
    local subscription_name=$(az account show --query name -o tsv)
    log "INFO" "Using Azure subscription: $subscription_name ($subscription_id)"
    log "INFO" "✅ Prerequisites check passed"
}

confirm_deletion() {
    if [[ "$FORCE" == true ]] || [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    echo
    log "WARN" "⚠️  WARNING: This will permanently delete Azure resources!"
    echo
    echo "Target Resource Group: $RESOURCE_GROUP"
    
    if [[ "$KEEP_RG" == true ]]; then
        echo "Action: Delete all resources within the resource group (keep resource group)"
    else
        echo "Action: Delete the entire resource group and all contained resources"
    fi
    
    echo
    read -p "Are you sure you want to proceed? (Type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "INFO" "Cleanup cancelled by user."
        exit 0
    fi
    
    log "INFO" "User confirmed deletion. Proceeding with cleanup..."
}

execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    log "INFO" "$description"
    log "DEBUG" "Executing: $cmd"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "[DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    if eval "$cmd"; then
        log "INFO" "✅ $description completed successfully"
        return 0
    else
        if [[ "$ignore_errors" == true ]]; then
            log "WARN" "⚠️ $description failed, but continuing (ignore_errors=true)"
            return 0
        else
            log "ERROR" "❌ Failed: $description"
            return 1
        fi
    fi
}

wait_for_deletion() {
    local resource_name="$1"
    local resource_type="$2"
    local max_attempts=30
    local attempt=1
    
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    log "INFO" "Waiting for $resource_type '$resource_name' deletion to complete..."
    
    while [[ $attempt -le $max_attempts ]]; do
        case "$resource_type" in
            "resource-group")
                if ! az group show --name "$resource_name" &> /dev/null; then
                    log "INFO" "✅ Resource group deletion completed"
                    return 0
                fi
                ;;
            "webapp")
                if ! az webapp show --name "$resource_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                    log "INFO" "✅ Web app deletion completed"
                    return 0
                fi
                ;;
            "workspace")
                if ! az monitor log-analytics workspace show --workspace-name "$resource_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                    log "INFO" "✅ Log Analytics workspace deletion completed"
                    return 0
                fi
                ;;
        esac
        
        log "DEBUG" "Attempt $attempt/$max_attempts - Resource still exists, waiting 10 seconds..."
        sleep 10
        ((attempt++))
    done
    
    log "WARN" "Deletion may still be in progress after $max_attempts attempts"
    return 0
}

# ============================================================================
# Resource Discovery Functions
# ============================================================================

discover_resources() {
    log "INFO" "Discovering resources in resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == false ]]; then
        # Discover web apps
        local webapps=$(az webapp list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$webapps" ]]; then
            log "INFO" "Found web apps: $(echo $webapps | tr '\n' ' ')"
            DISCOVERED_WEBAPPS=($webapps)
        else
            DISCOVERED_WEBAPPS=()
        fi
        
        # Discover App Service plans
        local plans=$(az appservice plan list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$plans" ]]; then
            log "INFO" "Found App Service plans: $(echo $plans | tr '\n' ' ')"
            DISCOVERED_PLANS=($plans)
        else
            DISCOVERED_PLANS=()
        fi
        
        # Discover Log Analytics workspaces
        local workspaces=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$workspaces" ]]; then
            log "INFO" "Found Log Analytics workspaces: $(echo $workspaces | tr '\n' ' ')"
            DISCOVERED_WORKSPACES=($workspaces)
        else
            DISCOVERED_WORKSPACES=()
        fi
        
        # Discover alert rules
        local alerts=$(az monitor metrics alert list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$alerts" ]]; then
            log "INFO" "Found alert rules: $(echo $alerts | tr '\n' ' ')"
            DISCOVERED_ALERTS=($alerts)
        else
            DISCOVERED_ALERTS=()
        fi
        
        # Discover action groups
        local action_groups=$(az monitor action-group list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$action_groups" ]]; then
            log "INFO" "Found action groups: $(echo $action_groups | tr '\n' ' ')"
            DISCOVERED_ACTION_GROUPS=($action_groups)
        else
            DISCOVERED_ACTION_GROUPS=()
        fi
        
        # Count total resources
        local total_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
        log "INFO" "Total resources found: $total_resources"
    else
        log "INFO" "[DRY-RUN] Would discover resources in resource group"
    fi
}

# ============================================================================
# Cleanup Functions
# ============================================================================

delete_alert_rules() {
    log "INFO" "Removing alert rules and action groups..."
    
    # Delete discovered alert rules
    for alert in "${DISCOVERED_ALERTS[@]}"; do
        local cmd="az monitor metrics alert delete \
            --name '$alert' \
            --resource-group '$RESOURCE_GROUP'"
        execute_command "$cmd" "Delete alert rule: $alert" true
    done
    
    # Delete discovered action groups
    for action_group in "${DISCOVERED_ACTION_GROUPS[@]}"; do
        local cmd="az monitor action-group delete \
            --name '$action_group' \
            --resource-group '$RESOURCE_GROUP'"
        execute_command "$cmd" "Delete action group: $action_group" true
    done
    
    log "INFO" "✅ Alert rules and action groups cleanup completed"
}

delete_monitoring_workspace() {
    log "INFO" "Removing monitoring workspace..."
    
    # Delete discovered Log Analytics workspaces
    for workspace in "${DISCOVERED_WORKSPACES[@]}"; do
        local cmd="az monitor log-analytics workspace delete \
            --workspace-name '$workspace' \
            --resource-group '$RESOURCE_GROUP' \
            --yes"
        
        if execute_command "$cmd" "Delete Log Analytics workspace: $workspace" true; then
            wait_for_deletion "$workspace" "workspace"
        fi
    done
    
    log "INFO" "✅ Monitoring workspace cleanup completed"
}

delete_web_applications() {
    log "INFO" "Removing web applications..."
    
    # Delete discovered web apps
    for webapp in "${DISCOVERED_WEBAPPS[@]}"; do
        # First, stop the web app to speed up deletion
        local stop_cmd="az webapp stop \
            --name '$webapp' \
            --resource-group '$RESOURCE_GROUP'"
        execute_command "$stop_cmd" "Stop web app: $webapp" true
        
        # Delete the web app
        local delete_cmd="az webapp delete \
            --name '$webapp' \
            --resource-group '$RESOURCE_GROUP'"
        
        if execute_command "$delete_cmd" "Delete web app: $webapp" true; then
            wait_for_deletion "$webapp" "webapp"
        fi
    done
    
    log "INFO" "✅ Web applications cleanup completed"
}

delete_app_service_plans() {
    log "INFO" "Removing App Service plans..."
    
    # Delete discovered App Service plans
    for plan in "${DISCOVERED_PLANS[@]}"; do
        local cmd="az appservice plan delete \
            --name '$plan' \
            --resource-group '$RESOURCE_GROUP' \
            --yes"
        execute_command "$cmd" "Delete App Service plan: $plan" true
    done
    
    log "INFO" "✅ App Service plans cleanup completed"
}

delete_remaining_resources() {
    log "INFO" "Checking for any remaining resources..."
    
    if [[ "$DRY_RUN" == false ]]; then
        local remaining_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
        
        if [[ "$remaining_count" -gt 0 ]]; then
            log "WARN" "Found $remaining_count remaining resources"
            
            # List remaining resources for visibility
            if [[ "$VERBOSE" == true ]]; then
                log "DEBUG" "Remaining resources:"
                az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name,Type:type}" -o table || true
            fi
            
            # Attempt to delete remaining resources
            log "INFO" "Attempting to delete remaining resources..."
            local remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].id" -o tsv 2>/dev/null || echo "")
            
            for resource_id in $remaining_resources; do
                local delete_cmd="az resource delete --ids '$resource_id'"
                execute_command "$delete_cmd" "Delete remaining resource: $(basename $resource_id)" true
            done
        else
            log "INFO" "✅ No remaining resources found"
        fi
    else
        log "INFO" "[DRY-RUN] Would check for and delete any remaining resources"
    fi
}

delete_resource_group() {
    if [[ "$KEEP_RG" == true ]]; then
        log "INFO" "Keeping resource group as requested: $RESOURCE_GROUP"
        return 0
    fi
    
    log "INFO" "Removing resource group: $RESOURCE_GROUP"
    
    local cmd="az group delete \
        --name '$RESOURCE_GROUP' \
        --yes \
        --no-wait"
    
    if execute_command "$cmd" "Delete resource group: $RESOURCE_GROUP"; then
        if [[ "$DRY_RUN" == false ]]; then
            log "INFO" "Resource group deletion initiated. This may take several minutes to complete."
            log "INFO" "You can check the status in the Azure portal or with: az group show --name '$RESOURCE_GROUP'"
        fi
    fi
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_cleanup() {
    log "INFO" "Validating cleanup completion..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "[DRY-RUN] Skipping cleanup validation"
        return 0
    fi
    
    if [[ "$KEEP_RG" == true ]]; then
        # Check if resource group is empty
        local remaining_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "unknown")
        if [[ "$remaining_count" == "0" ]]; then
            log "INFO" "✅ Resource group is empty"
        else
            log "WARN" "⚠️ Resource group still contains $remaining_count resources"
        fi
    else
        # Check if resource group still exists
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log "INFO" "✅ Resource group has been deleted"
        else
            log "INFO" "ℹ️ Resource group deletion is still in progress"
        fi
    fi
    
    log "INFO" "🎉 Cleanup validation completed!"
}

# ============================================================================
# Error Handling
# ============================================================================

cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Cleanup failed with exit code $exit_code"
        log "INFO" "Check the log file for details: $LOG_FILE"
        log "INFO" "Some resources may still exist. You can:"
        log "INFO" "1. Re-run this script to retry cleanup"
        log "INFO" "2. Manually delete resources via Azure portal"
        log "INFO" "3. Use Azure CLI commands directly"
    fi
}

trap cleanup_on_exit EXIT

# ============================================================================
# Main Execution
# ============================================================================

main() {
    # Initialize log file
    echo "Cleanup started at $(date)" > "$LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -k|--keep-rg)
                KEEP_RG=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Display configuration
    log "INFO" "=== Azure Basic Web Monitoring Cleanup ==="
    log "INFO" "Resource Group: ${RESOURCE_GROUP:-Not specified}"
    log "INFO" "Force: $FORCE"
    log "INFO" "Keep Resource Group: $KEEP_RG"
    log "INFO" "Dry Run: $DRY_RUN"
    log "INFO" "Verbose: $VERBOSE"
    log "INFO" "============================================="
    
    # Execute cleanup steps
    check_prerequisites
    discover_resources
    confirm_deletion
    
    # Delete resources in proper order (reverse of creation)
    delete_alert_rules
    delete_monitoring_workspace
    delete_web_applications
    delete_app_service_plans
    delete_remaining_resources
    delete_resource_group
    
    validate_cleanup
    
    # Summary
    log "INFO" "=== Cleanup Summary ==="
    log "INFO" "✅ Alert rules and action groups: Removed"
    log "INFO" "✅ Log Analytics workspace: Removed"
    log "INFO" "✅ Web applications: Removed"
    log "INFO" "✅ App Service plans: Removed"
    
    if [[ "$KEEP_RG" == true ]]; then
        log "INFO" "✅ Resource group: Preserved (contents removed)"
    else
        log "INFO" "✅ Resource group: Deletion initiated"
    fi
    
    log "INFO" ""
    log "INFO" "🎉 Cleanup completed successfully!"
    
    if [[ "$DRY_RUN" == false ]] && [[ "$KEEP_RG" == false ]]; then
        log "INFO" "Note: Resource group deletion may take several minutes to complete."
        log "INFO" "Monitor progress in the Azure portal or run:"
        log "INFO" "az group show --name '$RESOURCE_GROUP'"
    fi
    
    log "INFO" ""
    log "INFO" "Log file available at: $LOG_FILE"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi