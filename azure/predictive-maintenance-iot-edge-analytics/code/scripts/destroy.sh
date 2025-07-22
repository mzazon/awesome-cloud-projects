#!/bin/bash

# destroy.sh - Clean up Azure IoT Edge Predictive Maintenance Infrastructure
# This script removes all resources created by the deployment script

set -euo pipefail

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy_$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=false
FORCE=false
CONFIRM=true

# Default values
DEFAULT_RESOURCE_GROUP="rg-predictive-maintenance"

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up Azure IoT Edge Predictive Maintenance Infrastructure

OPTIONS:
    -g, --resource-group NAME    Resource group name to delete (default: ${DEFAULT_RESOURCE_GROUP})
    -d, --dry-run               Show what would be deleted without actually deleting
    -f, --force                 Force deletion without confirmation prompts
    -y, --yes                   Automatically answer yes to all prompts
    -h, --help                  Show this help message
    -v, --verbose               Enable verbose logging

EXAMPLES:
    $0                                    # Delete default resource group with confirmation
    $0 -g my-rg                          # Delete specific resource group
    $0 --dry-run                         # Show what would be deleted
    $0 --force --yes                     # Force deletion without any prompts

⚠️  WARNING: This script will DELETE ALL RESOURCES in the specified resource group!
    Make sure you have the correct resource group name before proceeding.

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -y|--yes)
                CONFIRM=false
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Verify account information
    local account_info=$(az account show --query '{subscriptionId:id,tenantId:tenantId,name:name}' -o json)
    local subscription_id=$(echo "$account_info" | jq -r '.subscriptionId' 2>/dev/null || echo "N/A")
    local tenant_id=$(echo "$account_info" | jq -r '.tenantId' 2>/dev/null || echo "N/A")
    local subscription_name=$(echo "$account_info" | jq -r '.name' 2>/dev/null || echo "N/A")
    
    log "INFO" "Using subscription: $subscription_name ($subscription_id)"
    log "INFO" "Tenant ID: $tenant_id"
}

# Check if resource group exists
check_resource_group() {
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "WARN" "Resource group '$RESOURCE_GROUP' does not exist"
        log "INFO" "Nothing to clean up"
        exit 0
    fi
    
    log "INFO" "Resource group '$RESOURCE_GROUP' exists and will be deleted"
}

# List resources in the resource group
list_resources() {
    log "INFO" "Listing resources in resource group '$RESOURCE_GROUP'..."
    
    local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].{Name:name,Type:type,Location:location}' --output table 2>/dev/null)
    
    if [[ -z "$resources" ]]; then
        log "INFO" "No resources found in resource group '$RESOURCE_GROUP'"
        return
    fi
    
    log "INFO" "Resources to be deleted:"
    echo "$resources" | tee -a "$LOG_FILE"
}

# Get resource count
get_resource_count() {
    local count=$(az resource list --resource-group "$RESOURCE_GROUP" --query 'length(@)' --output tsv 2>/dev/null || echo "0")
    echo "$count"
}

# Show cost estimate
show_cost_estimate() {
    log "INFO" "💰 Cost Impact:"
    log "INFO" "Deleting this resource group will stop all associated charges"
    log "INFO" "Estimated monthly savings: ~$50 (IoT Hub S1 + Storage + Stream Analytics)"
    log "INFO" ""
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$CONFIRM" == "false" ]] || [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    local resource_count=$(get_resource_count)
    
    echo ""
    log "WARN" "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    log "WARN" "This will permanently delete:"
    log "WARN" "  - Resource Group: $RESOURCE_GROUP"
    log "WARN" "  - All $resource_count resources within it"
    log "WARN" "  - All data stored in these resources"
    log "WARN" ""
    log "WARN" "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " -r
    echo
    
    if [[ "$REPLY" != "DELETE" ]]; then
        log "INFO" "Deletion cancelled by user"
        exit 0
    fi
    
    log "INFO" "Deletion confirmed. Proceeding..."
}

# Stop Stream Analytics jobs
stop_stream_analytics_jobs() {
    log "INFO" "Stopping Stream Analytics jobs in resource group '$RESOURCE_GROUP'..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would stop Stream Analytics jobs"
        return
    fi
    
    local jobs=$(az stream-analytics job list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$jobs" ]]; then
        log "INFO" "No Stream Analytics jobs found"
        return
    fi
    
    while IFS= read -r job_name; do
        if [[ -n "$job_name" ]]; then
            log "INFO" "Stopping Stream Analytics job: $job_name"
            az stream-analytics job stop \
                --name "$job_name" \
                --resource-group "$RESOURCE_GROUP" \
                --output none &
        fi
    done <<< "$jobs"
    
    # Wait for jobs to stop
    wait
    log "INFO" "✅ Stream Analytics jobs stopped"
}

# Delete IoT Edge deployments
delete_iot_edge_deployments() {
    log "INFO" "Deleting IoT Edge deployments..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete IoT Edge deployments"
        return
    fi
    
    # Find IoT Hubs in the resource group
    local iot_hubs=$(az iot hub list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$iot_hubs" ]]; then
        log "INFO" "No IoT Hubs found"
        return
    fi
    
    while IFS= read -r hub_name; do
        if [[ -n "$hub_name" ]]; then
            log "INFO" "Checking IoT Hub: $hub_name"
            
            # List and delete deployments
            local deployments=$(az iot edge deployment list --hub-name "$hub_name" --query '[].id' --output tsv 2>/dev/null || echo "")
            
            while IFS= read -r deployment_id; do
                if [[ -n "$deployment_id" ]]; then
                    log "INFO" "Deleting deployment: $deployment_id"
                    az iot edge deployment delete \
                        --deployment-id "$deployment_id" \
                        --hub-name "$hub_name" \
                        --output none || log "WARN" "Failed to delete deployment: $deployment_id"
                fi
            done <<< "$deployments"
            
            # Delete devices
            local devices=$(az iot hub device-identity list --hub-name "$hub_name" --query '[].deviceId' --output tsv 2>/dev/null || echo "")
            
            while IFS= read -r device_id; do
                if [[ -n "$device_id" ]]; then
                    log "INFO" "Deleting device: $device_id"
                    az iot hub device-identity delete \
                        --device-id "$device_id" \
                        --hub-name "$hub_name" \
                        --output none || log "WARN" "Failed to delete device: $device_id"
                fi
            done <<< "$devices"
        fi
    done <<< "$iot_hubs"
    
    log "INFO" "✅ IoT Edge deployments and devices deleted"
}

# Clear storage containers
clear_storage_containers() {
    log "INFO" "Clearing storage containers..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would clear storage containers"
        return
    fi
    
    # Find storage accounts in the resource group
    local storage_accounts=$(az storage account list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$storage_accounts" ]]; then
        log "INFO" "No storage accounts found"
        return
    fi
    
    while IFS= read -r storage_account; do
        if [[ -n "$storage_account" ]]; then
            log "INFO" "Clearing containers in storage account: $storage_account"
            
            # List containers
            local containers=$(az storage container list --account-name "$storage_account" --auth-mode login --query '[].name' --output tsv 2>/dev/null || echo "")
            
            while IFS= read -r container_name; do
                if [[ -n "$container_name" ]]; then
                    log "INFO" "Deleting container: $container_name"
                    az storage container delete \
                        --name "$container_name" \
                        --account-name "$storage_account" \
                        --auth-mode login \
                        --output none || log "WARN" "Failed to delete container: $container_name"
                fi
            done <<< "$containers"
        fi
    done <<< "$storage_accounts"
    
    log "INFO" "✅ Storage containers cleared"
}

# Delete alert rules
delete_alert_rules() {
    log "INFO" "Deleting alert rules..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete alert rules"
        return
    fi
    
    # Delete metric alert rules
    local alert_rules=$(az monitor metrics alert list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    while IFS= read -r rule_name; do
        if [[ -n "$rule_name" ]]; then
            log "INFO" "Deleting alert rule: $rule_name"
            az monitor metrics alert delete \
                --name "$rule_name" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none || log "WARN" "Failed to delete alert rule: $rule_name"
        fi
    done <<< "$alert_rules"
    
    # Delete action groups
    local action_groups=$(az monitor action-group list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    while IFS= read -r group_name; do
        if [[ -n "$group_name" ]]; then
            log "INFO" "Deleting action group: $group_name"
            az monitor action-group delete \
                --name "$group_name" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none || log "WARN" "Failed to delete action group: $group_name"
        fi
    done <<< "$action_groups"
    
    log "INFO" "✅ Alert rules and action groups deleted"
}

# Delete resource group
delete_resource_group() {
    log "INFO" "Deleting resource group '$RESOURCE_GROUP'..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return
    fi
    
    # Delete resource group (this will delete all resources within it)
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none
    
    if [[ $? -eq 0 ]]; then
        log "INFO" "✅ Resource group deletion initiated"
        log "INFO" "🕐 Deletion is running in the background and may take 5-10 minutes"
    else
        error_exit "Failed to delete resource group"
    fi
}

# Monitor deletion progress
monitor_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return
    fi
    
    log "INFO" "Monitoring deletion progress..."
    
    local max_wait=600  # 10 minutes
    local wait_interval=30
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log "INFO" "✅ Resource group '$RESOURCE_GROUP' has been completely deleted"
            return
        fi
        
        log "INFO" "🕐 Still deleting... (${elapsed}s elapsed)"
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    
    log "WARN" "⚠️  Deletion is taking longer than expected"
    log "INFO" "You can check the deletion status in the Azure portal"
}

# Validate cleanup
validate_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would validate cleanup"
        return
    fi
    
    log "INFO" "Validating cleanup..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "WARN" "Resource group '$RESOURCE_GROUP' still exists"
        log "INFO" "Deletion may still be in progress"
    else
        log "INFO" "✅ Resource group '$RESOURCE_GROUP' has been deleted"
    fi
}

# Print cleanup summary
print_summary() {
    log "INFO" "🧹 Cleanup Summary:"
    log "INFO" "  Resource Group: $RESOURCE_GROUP"
    log "INFO" "  Operation: ${DRY_RUN:+[DRY RUN] }Delete"
    log "INFO" ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "💰 Cost Impact: All charges for resources in this group have been stopped"
        log "INFO" "📊 Estimated monthly savings: ~$50"
        log "INFO" ""
        log "INFO" "⚠️  Data Recovery: Deleted resources cannot be recovered"
        log "INFO" "🔄 To redeploy: Run the deploy.sh script again"
    fi
}

# Main cleanup function
main() {
    log "INFO" "Starting Azure IoT Edge Predictive Maintenance cleanup..."
    log "INFO" "Log file: $LOG_FILE"
    
    # Set defaults
    RESOURCE_GROUP="${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Check if resource group exists
    check_resource_group
    
    # List resources
    list_resources
    
    # Show cost estimate
    show_cost_estimate
    
    # Confirm deletion
    confirm_deletion
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "🔍 DRY RUN MODE - No resources will be deleted"
        print_summary
        return
    fi
    
    # Perform cleanup operations
    log "INFO" "🧹 Starting cleanup operations..."
    
    # Stop services first
    stop_stream_analytics_jobs
    delete_iot_edge_deployments
    clear_storage_containers
    delete_alert_rules
    
    # Delete resource group (this will delete all remaining resources)
    delete_resource_group
    
    # Monitor deletion progress
    monitor_deletion
    
    # Validate cleanup
    validate_cleanup
    
    # Print summary
    print_summary
    
    log "INFO" "🎉 Cleanup completed successfully!"
    log "INFO" "📄 Check the log file for detailed information: $LOG_FILE"
}

# Handle script interruption
cleanup_on_exit() {
    log "WARN" "Script interrupted. Some resources may still be deleting..."
    log "INFO" "Check the Azure portal to monitor deletion progress"
    exit 130
}

# Set up signal handlers
trap cleanup_on_exit SIGINT SIGTERM

# Run main function
main "$@"