#!/bin/bash

# Azure Real-Time Collaborative Dashboard Cleanup Script
# This script removes all resources created for the real-time monitoring dashboard

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment_info.json"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

error_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "${ERROR_LOG}" >&2
}

success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "${LOG_FILE}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "${LOG_FILE}"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "${ERROR_LOG}"
}

# Load deployment information
load_deployment_info() {
    if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
        info "Loading deployment information from: $DEPLOYMENT_INFO_FILE"
        
        # Extract values from deployment info JSON
        export RESOURCE_GROUP=$(jq -r '.resource_group' "$DEPLOYMENT_INFO_FILE" 2>/dev/null || echo "")
        export LOCATION=$(jq -r '.location' "$DEPLOYMENT_INFO_FILE" 2>/dev/null || echo "")
        export RANDOM_SUFFIX=$(jq -r '.random_suffix' "$DEPLOYMENT_INFO_FILE" 2>/dev/null || echo "")
        export WEBPUBSUB_NAME=$(jq -r '.resources.webpubsub_name' "$DEPLOYMENT_INFO_FILE" 2>/dev/null || echo "")
        export STATIC_APP_NAME=$(jq -r '.resources.static_app_name' "$DEPLOYMENT_INFO_FILE" 2>/dev/null || echo "")
        export FUNCTION_APP_NAME=$(jq -r '.resources.function_app_name' "$DEPLOYMENT_INFO_FILE" 2>/dev/null || echo "")
        export STORAGE_NAME=$(jq -r '.resources.storage_name' "$DEPLOYMENT_INFO_FILE" 2>/dev/null || echo "")
        export APP_INSIGHTS_NAME=$(jq -r '.resources.app_insights_name' "$DEPLOYMENT_INFO_FILE" 2>/dev/null || echo "")
        export LOG_ANALYTICS_NAME=$(jq -r '.resources.log_analytics_name' "$DEPLOYMENT_INFO_FILE" 2>/dev/null || echo "")
        
        success "Deployment information loaded"
    else
        warning "Deployment info file not found. Using environment variables or defaults."
    fi
}

# Set default values and environment variables
set_environment_variables() {
    info "Setting environment variables..."
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-collab-dashboard}"
    export LOCATION="${LOCATION:-eastus}"
    export RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3 2>/dev/null || echo "unknown")}"
    export WEBPUBSUB_NAME="${WEBPUBSUB_NAME:-wps-dashboard-${RANDOM_SUFFIX}}"
    export STATIC_APP_NAME="${STATIC_APP_NAME:-swa-dashboard-${RANDOM_SUFFIX}}"
    export FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-dashboard-${RANDOM_SUFFIX}}"
    export STORAGE_NAME="${STORAGE_NAME:-stdashboard${RANDOM_SUFFIX}}"
    export APP_INSIGHTS_NAME="${APP_INSIGHTS_NAME:-appi-dashboard-${RANDOM_SUFFIX}}"
    export LOG_ANALYTICS_NAME="${LOG_ANALYTICS_NAME:-log-dashboard-${RANDOM_SUFFIX}}"
    
    # Display configuration
    info "Cleanup configuration:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Location: $LOCATION"
    info "  Random Suffix: $RANDOM_SUFFIX"
    
    success "Environment variables configured"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check for jq if deployment info exists
    if [[ -f "$DEPLOYMENT_INFO_FILE" ]] && ! command -v jq &> /dev/null; then
        warning "jq not found. Will use environment variables instead of deployment info."
    fi
    
    success "Prerequisites check completed"
}

# Confirm deletion with user
confirm_deletion() {
    info "Resources to be deleted:"
    
    # Check which resources exist
    local resources_found=false
    
    # Check resource group
    if az group exists --name "$RESOURCE_GROUP" --output tsv | grep -q "true"; then
        info "  ✓ Resource Group: $RESOURCE_GROUP"
        resources_found=true
        
        # List resources in the group
        info "  Resources in group:"
        az resource list --resource-group "$RESOURCE_GROUP" --output table --query "[].{Name:name, Type:type, Location:location}" 2>/dev/null || true
    else
        warning "  ✗ Resource Group not found: $RESOURCE_GROUP"
    fi
    
    if [[ "$resources_found" == "false" ]]; then
        info "No resources found to delete."
        return 1
    fi
    
    echo ""
    warning "⚠️  This action will permanently delete ALL resources in the resource group!"
    warning "⚠️  This includes any data stored in these resources!"
    echo ""
    
    # Check for --force flag to skip confirmation
    if [[ "${1:-}" == "--force" ]]; then
        warning "Force flag detected. Skipping confirmation."
        return 0
    fi
    
    # Interactive confirmation
    local confirmation
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        info "Deletion cancelled by user."
        exit 0
    fi
    
    success "Deletion confirmed"
    return 0
}

# Delete individual resources with retries
delete_resource_with_retry() {
    local resource_type="$1"
    local resource_name="$2"
    local delete_command="$3"
    local max_attempts=3
    local attempt=1
    
    info "Deleting $resource_type: $resource_name"
    
    while [[ $attempt -le $max_attempts ]]; do
        if eval "$delete_command" 2>/dev/null; then
            success "Deleted $resource_type: $resource_name"
            return 0
        else
            warning "Attempt $attempt/$max_attempts failed for $resource_type: $resource_name"
            if [[ $attempt -lt $max_attempts ]]; then
                sleep 10
            fi
            ((attempt++))
        fi
    done
    
    error "Failed to delete $resource_type: $resource_name after $max_attempts attempts"
    return 1
}

# Delete Static Web App
delete_static_web_app() {
    info "Checking for Static Web App..."
    
    if az staticwebapp show --name "$STATIC_APP_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        delete_resource_with_retry \
            "Static Web App" \
            "$STATIC_APP_NAME" \
            "az staticwebapp delete --name '$STATIC_APP_NAME' --resource-group '$RESOURCE_GROUP' --yes"
    else
        warning "Static Web App not found: $STATIC_APP_NAME"
    fi
}

# Delete Function App
delete_function_app() {
    info "Checking for Function App..."
    
    if az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        delete_resource_with_retry \
            "Function App" \
            "$FUNCTION_APP_NAME" \
            "az functionapp delete --name '$FUNCTION_APP_NAME' --resource-group '$RESOURCE_GROUP' --yes"
    else
        warning "Function App not found: $FUNCTION_APP_NAME"
    fi
}

# Delete Web PubSub
delete_webpubsub() {
    info "Checking for Web PubSub service..."
    
    if az webpubsub show --name "$WEBPUBSUB_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        delete_resource_with_retry \
            "Web PubSub" \
            "$WEBPUBSUB_NAME" \
            "az webpubsub delete --name '$WEBPUBSUB_NAME' --resource-group '$RESOURCE_GROUP' --yes"
    else
        warning "Web PubSub service not found: $WEBPUBSUB_NAME"
    fi
}

# Delete Application Insights
delete_application_insights() {
    info "Checking for Application Insights..."
    
    if az monitor app-insights component show --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        delete_resource_with_retry \
            "Application Insights" \
            "$APP_INSIGHTS_NAME" \
            "az monitor app-insights component delete --app '$APP_INSIGHTS_NAME' --resource-group '$RESOURCE_GROUP' --yes"
    else
        warning "Application Insights not found: $APP_INSIGHTS_NAME"
    fi
}

# Delete Log Analytics workspace
delete_log_analytics() {
    info "Checking for Log Analytics workspace..."
    
    if az monitor log-analytics workspace show --workspace-name "$LOG_ANALYTICS_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        delete_resource_with_retry \
            "Log Analytics Workspace" \
            "$LOG_ANALYTICS_NAME" \
            "az monitor log-analytics workspace delete --workspace-name '$LOG_ANALYTICS_NAME' --resource-group '$RESOURCE_GROUP' --yes --force"
    else
        warning "Log Analytics workspace not found: $LOG_ANALYTICS_NAME"
    fi
}

# Delete Storage Account
delete_storage_account() {
    info "Checking for Storage Account..."
    
    if az storage account show --name "$STORAGE_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        delete_resource_with_retry \
            "Storage Account" \
            "$STORAGE_NAME" \
            "az storage account delete --name '$STORAGE_NAME' --resource-group '$RESOURCE_GROUP' --yes"
    else
        warning "Storage Account not found: $STORAGE_NAME"
    fi
}

# Delete metric alerts
delete_metric_alerts() {
    info "Checking for metric alerts..."
    
    local alerts
    alerts=$(az monitor metrics alert list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$alerts" ]]; then
        while IFS= read -r alert_name; do
            if [[ -n "$alert_name" ]]; then
                delete_resource_with_retry \
                    "Metric Alert" \
                    "$alert_name" \
                    "az monitor metrics alert delete --name '$alert_name' --resource-group '$RESOURCE_GROUP' --yes"
            fi
        done <<< "$alerts"
    else
        info "No metric alerts found to delete"
    fi
}

# Delete entire resource group
delete_resource_group() {
    info "Checking if resource group exists..."
    
    if az group exists --name "$RESOURCE_GROUP" --output tsv | grep -q "true"; then
        info "Deleting entire resource group: $RESOURCE_GROUP"
        info "This will remove all remaining resources..."
        
        # Delete resource group with no-wait to avoid timeout
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        
        # Wait for deletion to complete
        info "Waiting for resource group deletion to complete..."
        local max_wait=600 # 10 minutes
        local wait_time=0
        local interval=30
        
        while [[ $wait_time -lt $max_wait ]]; do
            if ! az group exists --name "$RESOURCE_GROUP" --output tsv | grep -q "true"; then
                success "Resource group deleted successfully: $RESOURCE_GROUP"
                return 0
            fi
            
            info "Resource group still exists... waiting $interval seconds ($wait_time/$max_wait)"
            sleep $interval
            ((wait_time += interval))
        done
        
        warning "Resource group deletion is taking longer than expected"
        warning "Check Azure portal for deletion status: $RESOURCE_GROUP"
        return 1
    else
        info "Resource group does not exist: $RESOURCE_GROUP"
        return 0
    fi
}

# Verify cleanup completion
verify_cleanup() {
    info "Verifying cleanup completion..."
    
    # Check if resource group still exists
    if az group exists --name "$RESOURCE_GROUP" --output tsv | grep -q "true"; then
        warning "Resource group still exists: $RESOURCE_GROUP"
        
        # List remaining resources
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$remaining_resources" ]]; then
            warning "Remaining resources:"
            while IFS= read -r resource_name; do
                if [[ -n "$resource_name" ]]; then
                    warning "  - $resource_name"
                fi
            done <<< "$remaining_resources"
        fi
        
        return 1
    else
        success "All resources have been successfully deleted"
        return 0
    fi
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove deployment info file
    if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
        rm -f "$DEPLOYMENT_INFO_FILE"
        success "Removed deployment info file"
    fi
    
    # Clean up any local development directories if they exist
    local dirs_to_clean=("dashboard-functions" "dashboard-frontend")
    for dir in "${dirs_to_clean[@]}"; do
        if [[ -d "$SCRIPT_DIR/../$dir" ]]; then
            rm -rf "$SCRIPT_DIR/../$dir"
            success "Removed local directory: $dir"
        fi
    done
    
    success "Local cleanup completed"
}

# Main cleanup function
main() {
    local force_flag="${1:-}"
    
    info "Starting Azure Real-Time Collaborative Dashboard cleanup..."
    
    # Initialize logging
    > "$LOG_FILE"
    > "$ERROR_LOG"
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_info
    set_environment_variables
    
    # Confirm deletion (unless forced)
    if ! confirm_deletion "$force_flag"; then
        exit 0
    fi
    
    # Delete resources individually first (for better error handling)
    delete_metric_alerts
    delete_static_web_app
    delete_function_app
    delete_webpubsub
    delete_application_insights
    delete_storage_account
    delete_log_analytics
    
    # Delete entire resource group to catch any remaining resources
    delete_resource_group
    
    # Verify cleanup
    if verify_cleanup; then
        cleanup_local_files
        
        echo ""
        success "🎉 Cleanup completed successfully!"
        echo ""
        info "All resources have been removed from Azure"
        info "Local files have been cleaned up"
        echo ""
        info "Cleanup logs saved to: $LOG_FILE"
        if [[ -s "$ERROR_LOG" ]]; then
            warning "Some errors occurred during cleanup. Check: $ERROR_LOG"
        fi
    else
        error "Cleanup may not be complete. Check Azure portal and logs."
        exit 1
    fi
}

# Usage information
usage() {
    echo "Usage: $0 [--force]"
    echo ""
    echo "Options:"
    echo "  --force    Skip confirmation prompt and delete resources immediately"
    echo ""
    echo "This script will delete ALL resources created by the deploy.sh script."
    echo "Make sure you have backed up any important data before running this script."
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    --force)
        main "--force"
        ;;
    "")
        main
        ;;
    *)
        error "Unknown argument: $1"
        usage
        exit 1
        ;;
esac