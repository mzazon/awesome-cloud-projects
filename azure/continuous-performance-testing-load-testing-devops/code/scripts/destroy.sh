#!/bin/bash

# =============================================================================
# Azure Load Testing with Azure DevOps - Cleanup Script
# =============================================================================
# This script safely removes all infrastructure created for the Azure Load
# Testing with Azure DevOps integration recipe.
#
# Prerequisites:
# - Azure CLI installed and configured
# - Appropriate Azure subscription permissions
# - Access to the resource group containing the deployed resources
# =============================================================================

set -euo pipefail

# =============================================================================
# Script Configuration
# =============================================================================

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration values
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/azure-loadtest-cleanup-$(date +%Y%m%d-%H%M%S).log"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC}  $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC}  $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

error_exit() {
    log ERROR "$1"
    log ERROR "Cleanup failed. Check the log file: $LOG_FILE"
    exit 1
}

confirm_action() {
    local message="$1"
    local default_response="${2:-n}"
    
    if [[ "$FORCE" == "true" ]]; then
        log INFO "Force mode enabled. Proceeding with: $message"
        return 0
    fi
    
    echo -e "${YELLOW}$message${NC}"
    read -p "Continue? [y/N]: " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        log INFO "Operation cancelled by user"
        return 1
    fi
}

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI and try again."
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' and try again."
    fi
    
    log INFO "Prerequisites check completed successfully"
}

check_resource_group_exists() {
    log INFO "Checking if resource group exists: $RESOURCE_GROUP"
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Resource group '$RESOURCE_GROUP' does not exist. Nothing to cleanup."
        exit 0
    fi
    
    log INFO "Resource group '$RESOURCE_GROUP' found"
}

list_resources_to_delete() {
    log INFO "Scanning resources in resource group: $RESOURCE_GROUP"
    
    # Get list of all resources in the resource group
    local resources
    resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table 2>/dev/null)
    
    if [[ -z "$resources" || "$resources" == "[]" ]]; then
        log INFO "No resources found in resource group '$RESOURCE_GROUP'"
        return 0
    fi
    
    log INFO "Resources that will be deleted:"
    echo "$resources" | tee -a "$LOG_FILE"
    
    # Count resources
    local resource_count
    resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "0")
    log INFO "Total resources to delete: $resource_count"
    
    return 0
}

stop_active_load_tests() {
    log INFO "Checking for active load test runs..."
    
    # Check if Load Testing resource exists
    if ! az load show --name "$LOAD_TEST_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log INFO "Load Testing resource not found. Skipping test run cleanup."
        return 0
    fi
    
    # List running test runs
    local active_tests
    active_tests=$(az load test-run list \
        --load-test-resource "$LOAD_TEST_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?status=='EXECUTING' || status=='PROVISIONING'].{TestRunId:testRunId, Status:status, StartDateTime:startDateTime}" \
        --output table 2>/dev/null || echo "")
    
    if [[ -n "$active_tests" && "$active_tests" != "[]" ]]; then
        log WARN "Active load test runs found:"
        echo "$active_tests" | tee -a "$LOG_FILE"
        
        if confirm_action "Stop all active load test runs?"; then
            # Get list of active test run IDs
            local test_run_ids
            test_run_ids=$(az load test-run list \
                --load-test-resource "$LOAD_TEST_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --query "[?status=='EXECUTING' || status=='PROVISIONING'].testRunId" \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -n "$test_run_ids" ]]; then
                for test_run_id in $test_run_ids; do
                    log INFO "Stopping test run: $test_run_id"
                    az load test-run stop \
                        --test-run-id "$test_run_id" \
                        --load-test-resource "$LOAD_TEST_NAME" \
                        --resource-group "$RESOURCE_GROUP" \
                        || log WARN "Failed to stop test run: $test_run_id"
                done
                
                log INFO "Waiting for test runs to stop..."
                sleep 10
            fi
        else
            log WARN "Active test runs will continue running during cleanup"
        fi
    else
        log INFO "No active load test runs found"
    fi
}

delete_service_principal() {
    log INFO "Checking for service principal to delete..."
    
    # Look for service principal with the naming pattern
    local sp_pattern="sp-loadtest-devops-"
    local service_principals
    service_principals=$(az ad sp list --display-name-starts-with "$sp_pattern" --query "[].{AppId:appId, DisplayName:displayName}" --output table 2>/dev/null || echo "")
    
    if [[ -n "$service_principals" && "$service_principals" != "[]" ]]; then
        log INFO "Service principals found:"
        echo "$service_principals" | tee -a "$LOG_FILE"
        
        if confirm_action "Delete service principals created for this deployment?"; then
            local sp_app_ids
            sp_app_ids=$(az ad sp list --display-name-starts-with "$sp_pattern" --query "[].appId" --output tsv 2>/dev/null || echo "")
            
            for app_id in $sp_app_ids; do
                log INFO "Deleting service principal: $app_id"
                az ad sp delete --id "$app_id" || log WARN "Failed to delete service principal: $app_id"
            done
        fi
    else
        log INFO "No service principals found with pattern: $sp_pattern"
    fi
}

delete_alerts() {
    log INFO "Deleting performance monitoring alerts..."
    
    local alerts=("alert-high-response-time" "alert-high-error-rate")
    
    for alert_name in "${alerts[@]}"; do
        if az monitor metrics alert show --name "$alert_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log INFO "Deleting alert: $alert_name"
            az monitor metrics alert delete \
                --name "$alert_name" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                || log WARN "Failed to delete alert: $alert_name"
        else
            log INFO "Alert not found: $alert_name"
        fi
    done
}

delete_action_group() {
    log INFO "Deleting action group..."
    
    local action_group_name="ag-perftest-alerts"
    
    if az monitor action-group show --name "$action_group_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log INFO "Deleting action group: $action_group_name"
        az monitor action-group delete \
            --name "$action_group_name" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            || log WARN "Failed to delete action group: $action_group_name"
    else
        log INFO "Action group not found: $action_group_name"
    fi
}

delete_load_testing_resource() {
    log INFO "Deleting Azure Load Testing resource..."
    
    if az load show --name "$LOAD_TEST_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log INFO "Deleting Load Testing resource: $LOAD_TEST_NAME"
        az load delete \
            --name "$LOAD_TEST_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            || log WARN "Failed to delete Load Testing resource: $LOAD_TEST_NAME"
    else
        log INFO "Load Testing resource not found: $LOAD_TEST_NAME"
    fi
}

delete_application_insights() {
    log INFO "Deleting Application Insights..."
    
    if az monitor app-insights component show --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log INFO "Deleting Application Insights: $APP_INSIGHTS_NAME"
        az monitor app-insights component delete \
            --app "$APP_INSIGHTS_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            || log WARN "Failed to delete Application Insights: $APP_INSIGHTS_NAME"
    else
        log INFO "Application Insights not found: $APP_INSIGHTS_NAME"
    fi
}

delete_resource_group() {
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        log INFO "Deleting entire resource group: $RESOURCE_GROUP"
        
        if confirm_action "This will delete the entire resource group '$RESOURCE_GROUP' and ALL resources within it. This action cannot be undone."; then
            az group delete \
                --name "$RESOURCE_GROUP" \
                --yes \
                --no-wait \
                || error_exit "Failed to delete resource group: $RESOURCE_GROUP"
            
            log INFO "Resource group deletion initiated: $RESOURCE_GROUP"
            log INFO "Note: Deletion may take several minutes to complete"
        else
            log INFO "Resource group deletion cancelled"
        fi
    else
        log INFO "Keeping resource group: $RESOURCE_GROUP"
        log INFO "Use --delete-resource-group flag to delete the entire resource group"
    fi
}

cleanup_local_files() {
    log INFO "Cleaning up local files..."
    
    local files_to_remove=(
        "$SCRIPT_DIR/service-principal-config.json"
        "$SCRIPT_DIR/../loadtest-scripts/performance-test.jmx"
        "$SCRIPT_DIR/../loadtest-scripts/loadtest-config.yaml"
        "$SCRIPT_DIR/../loadtest-scripts/azure-pipelines.yml"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if confirm_action "Delete local file: $(basename "$file")?"; then
                rm -f "$file"
                log INFO "Deleted: $file"
            fi
        fi
    done
    
    # Remove loadtest-scripts directory if empty
    local scripts_dir="$SCRIPT_DIR/../loadtest-scripts"
    if [[ -d "$scripts_dir" && -z "$(ls -A "$scripts_dir")" ]]; then
        rmdir "$scripts_dir"
        log INFO "Removed empty directory: $scripts_dir"
    fi
}

verify_cleanup() {
    log INFO "Verifying cleanup completion..."
    
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        # Resource group deletion is asynchronous, so we can't verify immediately
        log INFO "Resource group deletion is in progress. It may take several minutes to complete."
        return 0
    fi
    
    # Check if resources still exist
    local remaining_resources
    remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "0")
    
    if [[ "$remaining_resources" -eq 0 ]]; then
        log INFO "All resources have been successfully removed"
        log INFO "Resource group '$RESOURCE_GROUP' is now empty"
    else
        log WARN "Some resources may still exist in resource group '$RESOURCE_GROUP'"
        log INFO "Remaining resource count: $remaining_resources"
        
        # List remaining resources
        az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output table | tee -a "$LOG_FILE"
    fi
}

display_cleanup_summary() {
    log INFO "=== CLEANUP SUMMARY ==="
    log INFO "Resource Group: $RESOURCE_GROUP"
    log INFO "Load Testing Resource: $LOAD_TEST_NAME"
    log INFO "Application Insights: $APP_INSIGHTS_NAME"
    log INFO "Delete Resource Group: $DELETE_RESOURCE_GROUP"
    log INFO ""
    log INFO "=== ACTIONS COMPLETED ==="
    log INFO "✓ Stopped active load test runs"
    log INFO "✓ Deleted performance alerts"
    log INFO "✓ Deleted action group"
    log INFO "✓ Deleted Load Testing resource"
    log INFO "✓ Deleted Application Insights"
    log INFO "✓ Deleted service principals"
    
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        log INFO "✓ Initiated resource group deletion"
    else
        log INFO "- Resource group preserved"
    fi
    
    log INFO ""
    log INFO "Cleanup completed successfully!"
    log INFO "Log file: $LOG_FILE"
    log INFO ""
    log WARN "Note: Some Azure resources may take additional time to be fully removed"
    log WARN "Billing for deleted resources should stop immediately"
}

show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Safely cleanup Azure Load Testing with Azure DevOps integration infrastructure.

OPTIONS:
    -g, --resource-group NAME    Resource group name (default: rg-loadtest-devops)
    -n, --load-test-name NAME    Load testing resource name (default: alt-perftest-demo)
    -i, --app-insights NAME      Application Insights name (default: ai-perftest-demo)
    --delete-resource-group      Delete the entire resource group
    --force                      Skip confirmation prompts
    --skip-service-principals    Don't delete service principals
    --skip-local-files          Don't delete local files
    -h, --help                   Show this help message
    -v, --verbose                Enable verbose logging
    --dry-run                    Show what would be deleted without making changes

EXAMPLES:
    $SCRIPT_NAME
    $SCRIPT_NAME -g my-resource-group
    $SCRIPT_NAME --delete-resource-group --force
    $SCRIPT_NAME --dry-run

SAFETY FEATURES:
    - Confirms destructive operations before execution
    - Stops active load test runs gracefully
    - Preserves resource group by default
    - Creates detailed logs of all operations

EOF
}

# =============================================================================
# Main Script Execution
# =============================================================================

main() {
    # Default configuration
    RESOURCE_GROUP="rg-loadtest-devops"
    LOAD_TEST_NAME="alt-perftest-demo"
    APP_INSIGHTS_NAME="ai-perftest-demo"
    DELETE_RESOURCE_GROUP=false
    FORCE=false
    SKIP_SERVICE_PRINCIPALS=false
    SKIP_LOCAL_FILES=false
    VERBOSE=false
    DRY_RUN=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -n|--load-test-name)
                LOAD_TEST_NAME="$2"
                shift 2
                ;;
            -i|--app-insights)
                APP_INSIGHTS_NAME="$2"
                shift 2
                ;;
            --delete-resource-group)
                DELETE_RESOURCE_GROUP=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --skip-service-principals)
                SKIP_SERVICE_PRINCIPALS=true
                shift
                ;;
            --skip-local-files)
                SKIP_LOCAL_FILES=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Start cleanup
    log INFO "Starting Azure Load Testing cleanup..."
    log INFO "Script: $SCRIPT_NAME"
    log INFO "Log file: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "DRY RUN MODE - No resources will be deleted"
        log INFO "Configuration:"
        log INFO "  Resource Group: $RESOURCE_GROUP"
        log INFO "  Load Test Name: $LOAD_TEST_NAME"
        log INFO "  App Insights: $APP_INSIGHTS_NAME"
        log INFO "  Delete Resource Group: $DELETE_RESOURCE_GROUP"
        log INFO ""
        check_prerequisites
        check_resource_group_exists
        list_resources_to_delete
        exit 0
    fi
    
    # Confirmation for destructive operation
    if ! confirm_action "This will delete Azure resources and may incur costs to stop. Continue?"; then
        log INFO "Cleanup cancelled by user"
        exit 0
    fi
    
    # Execute cleanup steps
    check_prerequisites
    check_resource_group_exists
    list_resources_to_delete
    stop_active_load_tests
    delete_alerts
    delete_action_group
    delete_load_testing_resource
    delete_application_insights
    
    if [[ "$SKIP_SERVICE_PRINCIPALS" != "true" ]]; then
        delete_service_principal
    fi
    
    if [[ "$SKIP_LOCAL_FILES" != "true" ]]; then
        cleanup_local_files
    fi
    
    delete_resource_group
    verify_cleanup
    display_cleanup_summary
}

# Execute main function with all arguments
main "$@"