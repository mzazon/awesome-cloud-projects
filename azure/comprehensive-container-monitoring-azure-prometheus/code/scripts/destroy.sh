#!/bin/bash

# Destroy script for Comprehensive Container Monitoring with Azure Container Storage and Managed Prometheus
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_VARS_FILE="${SCRIPT_DIR}/deployment_vars.env"
DRY_RUN="${DRY_RUN:-false}"
FORCE_DELETE="${FORCE_DELETE:-false}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to load environment variables
load_environment_variables() {
    log "Loading environment variables..."
    
    # Check if deployment variables file exists
    if [[ ! -f "$DEPLOYMENT_VARS_FILE" ]]; then
        error "Deployment variables file not found: $DEPLOYMENT_VARS_FILE"
        error "Cannot proceed without deployment configuration."
        error "If you want to manually specify resource names, set them as environment variables."
        exit 1
    fi
    
    # Load variables from file
    source "$DEPLOYMENT_VARS_FILE"
    
    # Validate required variables
    local required_vars=(
        "RESOURCE_GROUP"
        "CONTAINER_APP_ENV"
        "CONTAINER_APP_NAME"
        "STORAGE_ACCOUNT"
        "MONITOR_WORKSPACE"
        "GRAFANA_INSTANCE"
        "LOG_ANALYTICS_WORKSPACE"
        "MONITORING_SIDECAR_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable $var is not set or empty"
            exit 1
        fi
    done
    
    # Log the configuration
    info "Loaded Configuration:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Container App Environment: $CONTAINER_APP_ENV"
    info "  Container App Name: $CONTAINER_APP_NAME"
    info "  Storage Account: $STORAGE_ACCOUNT"
    info "  Monitor Workspace: $MONITOR_WORKSPACE"
    info "  Grafana Instance: $GRAFANA_INSTANCE"
    info "  Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
    info "  Monitoring Sidecar: $MONITORING_SIDECAR_NAME"
    
    log "Environment variables loaded successfully"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log "Force delete enabled - skipping confirmation"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would prompt for deletion confirmation"
        return 0
    fi
    
    log "⚠️  WARNING: This will permanently delete all resources in Resource Group: $RESOURCE_GROUP"
    log "This action cannot be undone!"
    echo -n "Are you sure you want to continue? (type 'yes' to confirm): "
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed by user"
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    
    case "$resource_type" in
        "containerapp")
            az containerapp show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "containerapp-env")
            az containerapp env show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "storage-account")
            az storage account show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "monitor-account")
            az monitor account show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "grafana")
            az grafana show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "log-analytics")
            az monitor log-analytics workspace show --workspace-name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "resource-group")
            az group show --name "$resource_name" &> /dev/null
            ;;
        *)
            error "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}

# Function to delete Prometheus rule groups
delete_prometheus_rule_groups() {
    log "Deleting Prometheus rule groups..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete Prometheus rule groups"
        return 0
    fi
    
    local rule_groups=("stateful-workload-alerts" "stateful-app-metrics" "stateful-workload-recording-rules")
    
    for rule_group in "${rule_groups[@]}"; do
        if az monitor prometheus rule-group show \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$MONITOR_WORKSPACE" \
            --name "$rule_group" &> /dev/null; then
            
            log "Deleting Prometheus rule group: $rule_group"
            az monitor prometheus rule-group delete \
                --resource-group "$RESOURCE_GROUP" \
                --workspace-name "$MONITOR_WORKSPACE" \
                --name "$rule_group" \
                --yes
        else
            info "Prometheus rule group $rule_group does not exist or already deleted"
        fi
    done
    
    log "✅ Prometheus rule groups cleanup completed"
}

# Function to delete Container Apps
delete_container_apps() {
    log "Deleting Container Apps..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete Container Apps"
        return 0
    fi
    
    local apps=("$CONTAINER_APP_NAME" "$MONITORING_SIDECAR_NAME")
    
    for app in "${apps[@]}"; do
        if resource_exists "containerapp" "$app" "$RESOURCE_GROUP"; then
            log "Deleting Container App: $app"
            az containerapp delete \
                --name "$app" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
            
            # Wait for deletion to complete
            local timeout=300
            local elapsed=0
            while resource_exists "containerapp" "$app" "$RESOURCE_GROUP" && [[ $elapsed -lt $timeout ]]; do
                sleep 10
                elapsed=$((elapsed + 10))
                info "Waiting for Container App $app to be deleted... ($elapsed/$timeout seconds)"
            done
            
            if resource_exists "containerapp" "$app" "$RESOURCE_GROUP"; then
                error "Container App $app deletion timed out"
            else
                log "✅ Container App $app deleted successfully"
            fi
        else
            info "Container App $app does not exist or already deleted"
        fi
    done
}

# Function to delete Container Apps environment
delete_container_apps_environment() {
    log "Deleting Container Apps environment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete Container Apps environment $CONTAINER_APP_ENV"
        return 0
    fi
    
    if resource_exists "containerapp-env" "$CONTAINER_APP_ENV" "$RESOURCE_GROUP"; then
        log "Deleting Container Apps environment: $CONTAINER_APP_ENV"
        az containerapp env delete \
            --name "$CONTAINER_APP_ENV" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        
        # Wait for deletion to complete
        local timeout=600
        local elapsed=0
        while resource_exists "containerapp-env" "$CONTAINER_APP_ENV" "$RESOURCE_GROUP" && [[ $elapsed -lt $timeout ]]; do
            sleep 15
            elapsed=$((elapsed + 15))
            info "Waiting for Container Apps environment to be deleted... ($elapsed/$timeout seconds)"
        done
        
        if resource_exists "containerapp-env" "$CONTAINER_APP_ENV" "$RESOURCE_GROUP"; then
            error "Container Apps environment deletion timed out"
        else
            log "✅ Container Apps environment deleted successfully"
        fi
    else
        info "Container Apps environment $CONTAINER_APP_ENV does not exist or already deleted"
    fi
}

# Function to delete storage resources
delete_storage_resources() {
    log "Deleting storage resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete storage account $STORAGE_ACCOUNT"
        return 0
    fi
    
    if resource_exists "storage-account" "$STORAGE_ACCOUNT" "$RESOURCE_GROUP"; then
        log "Deleting storage account: $STORAGE_ACCOUNT"
        az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        
        log "✅ Storage account deleted: $STORAGE_ACCOUNT"
    else
        info "Storage account $STORAGE_ACCOUNT does not exist or already deleted"
    fi
}

# Function to delete Grafana instance
delete_grafana_instance() {
    log "Deleting Grafana instance..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete Grafana instance $GRAFANA_INSTANCE"
        return 0
    fi
    
    if resource_exists "grafana" "$GRAFANA_INSTANCE" "$RESOURCE_GROUP"; then
        log "Deleting Grafana instance: $GRAFANA_INSTANCE"
        az grafana delete \
            --name "$GRAFANA_INSTANCE" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        
        log "✅ Grafana instance deleted: $GRAFANA_INSTANCE"
    else
        info "Grafana instance $GRAFANA_INSTANCE does not exist or already deleted"
    fi
}

# Function to delete Azure Monitor workspace
delete_monitor_workspace() {
    log "Deleting Azure Monitor workspace..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete Azure Monitor workspace $MONITOR_WORKSPACE"
        return 0
    fi
    
    if resource_exists "monitor-account" "$MONITOR_WORKSPACE" "$RESOURCE_GROUP"; then
        log "Deleting Azure Monitor workspace: $MONITOR_WORKSPACE"
        az monitor account delete \
            --name "$MONITOR_WORKSPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        
        log "✅ Azure Monitor workspace deleted: $MONITOR_WORKSPACE"
    else
        info "Azure Monitor workspace $MONITOR_WORKSPACE does not exist or already deleted"
    fi
}

# Function to delete Log Analytics workspace
delete_log_analytics_workspace() {
    log "Deleting Log Analytics workspace..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete Log Analytics workspace $LOG_ANALYTICS_WORKSPACE"
        return 0
    fi
    
    if resource_exists "log-analytics" "$LOG_ANALYTICS_WORKSPACE" "$RESOURCE_GROUP"; then
        log "Deleting Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
        az monitor log-analytics workspace delete \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --yes
        
        log "✅ Log Analytics workspace deleted: $LOG_ANALYTICS_WORKSPACE"
    else
        info "Log Analytics workspace $LOG_ANALYTICS_WORKSPACE does not exist or already deleted"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete resource group $RESOURCE_GROUP"
        return 0
    fi
    
    if resource_exists "resource-group" "$RESOURCE_GROUP" ""; then
        log "Deleting resource group: $RESOURCE_GROUP"
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        
        log "✅ Resource group deletion initiated: $RESOURCE_GROUP"
        log "Note: Resource group deletion may take several minutes to complete"
        
        # Optional: Wait for resource group deletion
        if [[ "${WAIT_FOR_DELETION:-false}" == "true" ]]; then
            local timeout=1800  # 30 minutes
            local elapsed=0
            while resource_exists "resource-group" "$RESOURCE_GROUP" "" && [[ $elapsed -lt $timeout ]]; do
                sleep 30
                elapsed=$((elapsed + 30))
                info "Waiting for resource group deletion... ($elapsed/$timeout seconds)"
            done
            
            if resource_exists "resource-group" "$RESOURCE_GROUP" ""; then
                error "Resource group deletion timed out"
            else
                log "✅ Resource group deleted successfully"
            fi
        fi
    else
        info "Resource group $RESOURCE_GROUP does not exist or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would clean up local files"
        return 0
    fi
    
    local files_to_remove=(
        "${SCRIPT_DIR}/deployment_vars.env"
        "${SCRIPT_DIR}/prometheus-rules.json"
        "${SCRIPT_DIR}/alert-rules.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "Removed file: $file"
        fi
    done
    
    log "✅ Local files cleaned up"
}

# Function to validate resource deletion
validate_deletion() {
    log "Validating resource deletion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would validate resource deletion"
        return 0
    fi
    
    local validation_errors=0
    
    # Check if key resources still exist
    local resources_to_check=(
        "containerapp:$CONTAINER_APP_NAME"
        "containerapp:$MONITORING_SIDECAR_NAME"
        "containerapp-env:$CONTAINER_APP_ENV"
        "storage-account:$STORAGE_ACCOUNT"
        "grafana:$GRAFANA_INSTANCE"
        "monitor-account:$MONITOR_WORKSPACE"
        "log-analytics:$LOG_ANALYTICS_WORKSPACE"
    )
    
    for resource in "${resources_to_check[@]}"; do
        local type="${resource%:*}"
        local name="${resource#*:}"
        
        if resource_exists "$type" "$name" "$RESOURCE_GROUP"; then
            error "Resource still exists: $name (type: $type)"
            validation_errors=$((validation_errors + 1))
        else
            info "✅ Resource successfully deleted: $name"
        fi
    done
    
    if [[ $validation_errors -gt 0 ]]; then
        error "Validation found $validation_errors resources that were not properly deleted"
        return 1
    fi
    
    log "✅ Resource deletion validation completed successfully"
}

# Function to display destruction summary
display_destruction_summary() {
    log "Destruction Summary:"
    log "==================="
    log "Resource Group: $RESOURCE_GROUP"
    log "Container Apps Environment: $CONTAINER_APP_ENV"
    log "Stateful Application: $CONTAINER_APP_NAME"
    log "Monitoring Sidecar: $MONITORING_SIDECAR_NAME"
    log "Storage Account: $STORAGE_ACCOUNT"
    log "Monitor Workspace: $MONITOR_WORKSPACE"
    log "Grafana Instance: $GRAFANA_INSTANCE"
    log "Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
    log ""
    log "All resources have been successfully deleted."
    log "The resource group deletion may take additional time to complete."
    log ""
    log "Note: Some resources may have soft-delete enabled and can be recovered"
    log "within the retention period if needed."
}

# Main destruction function
main() {
    log "Starting destruction of Azure Stateful Workload Monitoring solution..."
    
    # Initialize log file
    echo "Destruction started at $(date)" > "$LOG_FILE"
    
    # Check if dry run is requested
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "Running in DRY RUN mode - no resources will be deleted"
    fi
    
    # Execute destruction steps
    check_prerequisites
    load_environment_variables
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_prometheus_rule_groups
    delete_container_apps
    delete_container_apps_environment
    delete_storage_resources
    delete_grafana_instance
    delete_monitor_workspace
    delete_log_analytics_workspace
    delete_resource_group
    
    # Only validate if not deleting resource group (since it will delete everything)
    if [[ "${DELETE_RESOURCE_GROUP:-true}" != "true" ]]; then
        validate_deletion
    fi
    
    cleanup_local_files
    display_destruction_summary
    
    log "🎉 Destruction completed successfully!"
    log "Check the log file for details: $LOG_FILE"
}

# Trap for cleanup on script exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Destruction failed with exit code $exit_code"
        error "Check the log file for details: $LOG_FILE"
        error "Some resources may not have been deleted and could incur charges"
    fi
}

trap cleanup EXIT

# Handle script arguments
case "${1:-}" in
    --dry-run)
        DRY_RUN=true
        ;;
    --force)
        FORCE_DELETE=true
        ;;
    --wait)
        WAIT_FOR_DELETION=true
        ;;
    --help)
        echo "Usage: $0 [--dry-run|--force|--wait|--help]"
        echo "  --dry-run: Show what would be deleted without actually removing resources"
        echo "  --force: Skip confirmation prompts and delete immediately"
        echo "  --wait: Wait for resource group deletion to complete before exiting"
        echo "  --help: Show this help message"
        exit 0
        ;;
    "")
        # No arguments, continue with normal execution
        ;;
    *)
        error "Unknown argument: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Run main function
main "$@"