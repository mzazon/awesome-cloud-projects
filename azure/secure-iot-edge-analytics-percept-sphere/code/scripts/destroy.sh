#!/bin/bash

# destroy.sh - Cleanup Azure IoT Edge Analytics resources
# This script safely removes all resources created by the deployment script including:
# - Azure Stream Analytics job
# - Azure IoT Hub and devices
# - Azure Storage account and containers
# - Azure Monitor alerts and action groups
# - Resource group and all contained resources

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly LOCK_FILE="${SCRIPT_DIR}/destroy.lock"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default values
DEFAULT_RESOURCE_GROUP="rg-iot-edge-analytics"
DEFAULT_LOCATION="eastus"

# Environment variables with defaults
RESOURCE_GROUP="${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}"
LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
FORCE_DELETE="${FORCE_DELETE:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# Function to log messages
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to log error messages
error() {
    echo -e "${RED}ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

# Function to log success messages
success() {
    echo -e "${GREEN}SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

# Function to log warning messages
warning() {
    echo -e "${YELLOW}WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

# Function to log info messages
info() {
    echo -e "${BLUE}INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}⚠️  WARNING: This will permanently delete all resources in the resource group: $RESOURCE_GROUP${NC}"
    echo -e "${YELLOW}🔥 This action cannot be undone and will remove:${NC}"
    echo -e "${YELLOW}   - Azure IoT Hub and all devices${NC}"
    echo -e "${YELLOW}   - Azure Stream Analytics job${NC}"
    echo -e "${YELLOW}   - Azure Storage account and all data${NC}"
    echo -e "${YELLOW}   - Azure Monitor alerts and action groups${NC}"
    echo -e "${YELLOW}   - All other resources in the resource group${NC}"
    echo ""
    read -p "Are you sure you want to continue? (Type 'DELETE' to confirm): " -r
    echo ""
    
    if [[ "$REPLY" != "DELETE" ]]; then
        info "Deletion cancelled by user. Resource group preserved."
        exit 0
    fi
    
    info "Deletion confirmed. Proceeding with cleanup..."
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it first."
        error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        return 1
    fi
    
    # Check if logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        error "Not logged in to Azure. Please run 'az login' first."
        return 1
    fi
    
    # Get current subscription
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    info "Using Azure subscription: $subscription_id"
    
    success "Prerequisites check completed"
}

# Function to check if resource group exists
check_resource_group() {
    info "Checking if resource group exists: $RESOURCE_GROUP"
    
    if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warning "Resource group '$RESOURCE_GROUP' does not exist"
        return 1
    fi
    
    success "Resource group found: $RESOURCE_GROUP"
    return 0
}

# Function to list resources in resource group
list_resources() {
    info "Listing resources in resource group: $RESOURCE_GROUP"
    
    local resources
    resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].{Name:name, Type:type, Location:location}' --output table)
    
    if [[ -n "$resources" ]]; then
        echo ""
        echo "📋 Resources to be deleted:"
        echo "$resources"
        echo ""
    else
        info "No resources found in resource group"
    fi
}

# Function to stop Stream Analytics job
stop_stream_analytics() {
    info "🛑 Stopping Stream Analytics jobs..."
    
    local jobs
    jobs=$(az stream-analytics job list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv)
    
    if [[ -n "$jobs" ]]; then
        while IFS= read -r job_name; do
            if [[ -n "$job_name" ]]; then
                info "Stopping Stream Analytics job: $job_name"
                
                # Check if job is running
                local job_state
                job_state=$(az stream-analytics job show --resource-group "$RESOURCE_GROUP" --name "$job_name" --query 'jobState' --output tsv)
                
                if [[ "$job_state" == "Running" ]]; then
                    az stream-analytics job stop \
                        --resource-group "$RESOURCE_GROUP" \
                        --name "$job_name" \
                        --output none
                    
                    # Wait for job to stop
                    info "Waiting for job to stop..."
                    local timeout=60
                    local count=0
                    while [[ $count -lt $timeout ]]; do
                        job_state=$(az stream-analytics job show --resource-group "$RESOURCE_GROUP" --name "$job_name" --query 'jobState' --output tsv)
                        if [[ "$job_state" == "Stopped" ]]; then
                            break
                        fi
                        sleep 2
                        ((count++))
                    done
                    
                    if [[ "$job_state" == "Stopped" ]]; then
                        success "Stream Analytics job stopped: $job_name"
                    else
                        warning "Stream Analytics job did not stop within timeout: $job_name"
                    fi
                else
                    info "Stream Analytics job is not running: $job_name"
                fi
            fi
        done <<< "$jobs"
    else
        info "No Stream Analytics jobs found"
    fi
}

# Function to delete IoT Hub devices
delete_iot_devices() {
    info "🔌 Deleting IoT Hub devices..."
    
    local iot_hubs
    iot_hubs=$(az iot hub list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv)
    
    if [[ -n "$iot_hubs" ]]; then
        while IFS= read -r hub_name; do
            if [[ -n "$hub_name" ]]; then
                info "Processing IoT Hub: $hub_name"
                
                # List devices in IoT Hub
                local devices
                devices=$(az iot hub device-identity list --hub-name "$hub_name" --resource-group "$RESOURCE_GROUP" --query '[].deviceId' --output tsv 2>/dev/null || true)
                
                if [[ -n "$devices" ]]; then
                    while IFS= read -r device_id; do
                        if [[ -n "$device_id" ]]; then
                            info "Deleting device: $device_id"
                            az iot hub device-identity delete \
                                --hub-name "$hub_name" \
                                --device-id "$device_id" \
                                --resource-group "$RESOURCE_GROUP" \
                                --output none
                            success "Device deleted: $device_id"
                        fi
                    done <<< "$devices"
                else
                    info "No devices found in IoT Hub: $hub_name"
                fi
            fi
        done <<< "$iot_hubs"
    else
        info "No IoT Hubs found"
    fi
}

# Function to delete Azure Monitor alerts
delete_monitor_alerts() {
    info "📊 Deleting Azure Monitor alerts..."
    
    # Delete metric alerts
    local metric_alerts
    metric_alerts=$(az monitor metrics alert list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv)
    
    if [[ -n "$metric_alerts" ]]; then
        while IFS= read -r alert_name; do
            if [[ -n "$alert_name" ]]; then
                info "Deleting metric alert: $alert_name"
                az monitor metrics alert delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$alert_name" \
                    --output none
                success "Metric alert deleted: $alert_name"
            fi
        done <<< "$metric_alerts"
    else
        info "No metric alerts found"
    fi
    
    # Delete action groups
    local action_groups
    action_groups=$(az monitor action-group list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv)
    
    if [[ -n "$action_groups" ]]; then
        while IFS= read -r group_name; do
            if [[ -n "$group_name" ]]; then
                info "Deleting action group: $group_name"
                az monitor action-group delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$group_name" \
                    --output none
                success "Action group deleted: $group_name"
            fi
        done <<< "$action_groups"
    else
        info "No action groups found"
    fi
}

# Function to delete storage account contents
delete_storage_contents() {
    info "💾 Deleting storage account contents..."
    
    local storage_accounts
    storage_accounts=$(az storage account list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv)
    
    if [[ -n "$storage_accounts" ]]; then
        while IFS= read -r account_name; do
            if [[ -n "$account_name" ]]; then
                info "Processing storage account: $account_name"
                
                # Get storage account key
                local storage_key
                storage_key=$(az storage account keys list \
                    --resource-group "$RESOURCE_GROUP" \
                    --account-name "$account_name" \
                    --query '[0].value' --output tsv)
                
                # List and delete containers
                local containers
                containers=$(az storage container list \
                    --account-name "$account_name" \
                    --account-key "$storage_key" \
                    --query '[].name' --output tsv 2>/dev/null || true)
                
                if [[ -n "$containers" ]]; then
                    while IFS= read -r container_name; do
                        if [[ -n "$container_name" ]]; then
                            info "Deleting container: $container_name"
                            az storage container delete \
                                --name "$container_name" \
                                --account-name "$account_name" \
                                --account-key "$storage_key" \
                                --output none
                            success "Container deleted: $container_name"
                        fi
                    done <<< "$containers"
                else
                    info "No containers found in storage account: $account_name"
                fi
            fi
        done <<< "$storage_accounts"
    else
        info "No storage accounts found"
    fi
}

# Function to delete resource group
delete_resource_group() {
    info "🗂️  Deleting resource group: $RESOURCE_GROUP"
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        info "Force deletion enabled - deleting without waiting"
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            --output none
        success "Resource group deletion initiated: $RESOURCE_GROUP"
        warning "Deletion is running in background. It may take several minutes to complete."
    else
        info "Deleting resource group and waiting for completion..."
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --output none
        success "Resource group deleted: $RESOURCE_GROUP"
    fi
}

# Function to verify deletion
verify_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        info "Skipping verification due to force deletion mode"
        return 0
    fi
    
    info "✅ Verifying resource group deletion..."
    
    local timeout=120
    local count=0
    while [[ $count -lt $timeout ]]; do
        if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
            success "Resource group successfully deleted: $RESOURCE_GROUP"
            return 0
        fi
        sleep 5
        ((count++))
    done
    
    warning "Resource group deletion verification timed out"
    info "You can check the deletion status manually with: az group show --name $RESOURCE_GROUP"
    return 1
}

# Function to cleanup local files
cleanup_local_files() {
    info "🧹 Cleaning up local files..."
    
    local files_to_delete=(
        "${SCRIPT_DIR}/sphere-device-cert.json"
        "${SCRIPT_DIR}/edge-config.json"
        "${SCRIPT_DIR}/deploy.log"
    )
    
    for file in "${files_to_delete[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            info "Deleted local file: $(basename "$file")"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to cleanup on exit
cleanup() {
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "🔥 Destroy Azure IoT Edge Analytics resources"
    echo ""
    echo "This script will safely remove all resources created by the deployment script:"
    echo "  • Azure IoT Hub and all devices"
    echo "  • Azure Stream Analytics job"
    echo "  • Azure Storage account and all data"
    echo "  • Azure Monitor alerts and action groups"
    echo "  • The entire resource group"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group NAME    Resource group name to delete"
    echo "  -f, --force                  Force deletion without waiting for completion"
    echo "  -y, --yes                    Skip confirmation prompt"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  RESOURCE_GROUP               Resource group name to delete"
    echo "  FORCE_DELETE                 Set to 'true' for force deletion"
    echo "  SKIP_CONFIRMATION            Set to 'true' to skip confirmation"
    echo ""
    echo "Examples:"
    echo "  $0 -g my-iot-rg"
    echo "  $0 -g my-iot-rg -f -y"
    echo "  RESOURCE_GROUP=my-iot-rg FORCE_DELETE=true $0"
    echo ""
    echo "⚠️  Safety features:"
    echo "  • Stops running Stream Analytics jobs before deletion"
    echo "  • Deletes IoT devices before deleting IoT Hub"
    echo "  • Cleans up storage containers before deleting storage account"
    echo "  • Removes Azure Monitor alerts and action groups"
    echo "  • Provides confirmation prompt (unless -y is used)"
    echo "  • Verifies deletion completion (unless -f is used)"
    echo ""
    echo "🔒 Security note: This script requires confirmation by typing 'DELETE'"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_DELETE="true"
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION="true"
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    # Check for lock file
    if [[ -f "$LOCK_FILE" ]]; then
        error "Another cleanup operation is already in progress. Remove $LOCK_FILE if this is not the case."
        exit 1
    fi
    
    # Create lock file
    touch "$LOCK_FILE"
    
    # Set trap to cleanup on exit
    trap cleanup EXIT
    
    # Start cleanup
    info "🚀 Starting cleanup of Azure IoT Edge Analytics resources"
    info "📝 Log file: $LOG_FILE"
    
    # Execute cleanup steps
    check_prerequisites
    
    if ! check_resource_group; then
        info "✅ Resource group does not exist. Nothing to clean up."
        exit 0
    fi
    
    list_resources
    confirm_deletion
    
    info "🔄 Beginning cleanup process..."
    stop_stream_analytics
    delete_iot_devices
    delete_monitor_alerts
    delete_storage_contents
    delete_resource_group
    
    if [[ "$FORCE_DELETE" != "true" ]]; then
        verify_deletion
    fi
    
    cleanup_local_files
    
    # Remove lock file
    rm -f "$LOCK_FILE"
    
    echo ""
    echo "🎉 =================================="
    echo "✅ Cleanup completed successfully!"
    echo "🧹 All Azure IoT Edge Analytics resources have been removed"
    echo "💰 No further charges will be incurred from these resources"
    echo "=================================="
    echo ""
    
    success "Cleanup completed successfully!"
}

# Execute main function
main "$@"