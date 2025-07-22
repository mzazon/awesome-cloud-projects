#!/bin/bash

# destroy.sh - Azure IoT Edge Real-Time Anomaly Detection Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
error_exit() {
    log_error "Cleanup failed: $1"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        error_exit "Not logged into Azure. Please run 'az login' first"
    fi
    
    # Check for jq
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install it first"
    fi
    
    log_success "Prerequisites check passed"
}

# Function to confirm destruction
confirm_destruction() {
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log "Force delete enabled - skipping confirmation"
        return 0
    fi
    
    log_warning "This will DELETE ALL RESOURCES created by the deployment script"
    log_warning "This action is IRREVERSIBLE and will result in data loss"
    
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log "Resource group to be deleted: $RESOURCE_GROUP"
        
        # Show resources that will be deleted
        log "Resources that will be deleted:"
        az resource list --resource-group "$RESOURCE_GROUP" --output table 2>/dev/null || log_warning "Could not list resources in $RESOURCE_GROUP"
    fi
    
    read -p "Are you sure you want to continue? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log_success "Destruction confirmed"
}

# Function to find resource groups
find_resource_groups() {
    log "Finding resource groups created by deployment script..."
    
    # If RESOURCE_GROUP is already set, use it
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log_success "Using provided resource group: $RESOURCE_GROUP"
            return 0
        else
            log_warning "Provided resource group $RESOURCE_GROUP does not exist"
        fi
    fi
    
    # Find resource groups with our naming pattern
    local resource_groups=()
    while IFS= read -r rg; do
        if [[ -n "$rg" ]]; then
            resource_groups+=("$rg")
        fi
    done < <(az group list --query "[?starts_with(name, 'rg-anomaly-detection-')].name" --output tsv)
    
    if [[ ${#resource_groups[@]} -eq 0 ]]; then
        log_warning "No resource groups found matching pattern 'rg-anomaly-detection-*'"
        log "You may need to specify the resource group name manually:"
        log "  export RESOURCE_GROUP=your-resource-group-name"
        log "  ./destroy.sh"
        return 1
    elif [[ ${#resource_groups[@]} -eq 1 ]]; then
        export RESOURCE_GROUP="${resource_groups[0]}"
        log_success "Found resource group: $RESOURCE_GROUP"
        return 0
    else
        log "Multiple resource groups found:"
        for i in "${!resource_groups[@]}"; do
            echo "  $((i+1)). ${resource_groups[$i]}"
        done
        
        read -p "Select resource group to delete (1-${#resource_groups[@]}): " selection
        
        if [[ "$selection" -ge 1 && "$selection" -le ${#resource_groups[@]} ]]; then
            export RESOURCE_GROUP="${resource_groups[$((selection-1))]}"
            log_success "Selected resource group: $RESOURCE_GROUP"
            return 0
        else
            error_exit "Invalid selection"
        fi
    fi
}

# Function to extract resource names from resource group
extract_resource_names() {
    log "Extracting resource names from resource group..."
    
    # Get all resources in the resource group
    local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --output json)
    
    # Extract specific resource names
    export IOT_HUB_NAME=$(echo "$resources" | jq -r '.[] | select(.type=="Microsoft.Devices/IotHubs") | .name' | head -1)
    export STORAGE_ACCOUNT=$(echo "$resources" | jq -r '.[] | select(.type=="Microsoft.Storage/storageAccounts") | .name' | head -1)
    export ML_WORKSPACE=$(echo "$resources" | jq -r '.[] | select(.type=="Microsoft.MachineLearningServices/workspaces") | .name' | head -1)
    export ASA_JOB_NAME=$(echo "$resources" | jq -r '.[] | select(.type=="Microsoft.StreamAnalytics/streamingjobs") | .name' | head -1)
    export LOG_WORKSPACE=$(echo "$resources" | jq -r '.[] | select(.type=="Microsoft.OperationalInsights/workspaces") | .name' | head -1)
    
    log "Extracted resource names:"
    [[ -n "$IOT_HUB_NAME" ]] && log "  IoT Hub: $IOT_HUB_NAME"
    [[ -n "$STORAGE_ACCOUNT" ]] && log "  Storage Account: $STORAGE_ACCOUNT"
    [[ -n "$ML_WORKSPACE" ]] && log "  ML Workspace: $ML_WORKSPACE"
    [[ -n "$ASA_JOB_NAME" ]] && log "  Stream Analytics Job: $ASA_JOB_NAME"
    [[ -n "$LOG_WORKSPACE" ]] && log "  Log Analytics Workspace: $LOG_WORKSPACE"
}

# Function to stop running services
stop_running_services() {
    log "Stopping running services..."
    
    # Stop Stream Analytics job if it exists and is running
    if [[ -n "${ASA_JOB_NAME:-}" ]]; then
        local job_state=$(az stream-analytics job show --name "$ASA_JOB_NAME" --resource-group "$RESOURCE_GROUP" --query "jobState" --output tsv 2>/dev/null || echo "NotFound")
        
        if [[ "$job_state" == "Running" ]]; then
            log "Stopping Stream Analytics job: $ASA_JOB_NAME"
            az stream-analytics job stop --name "$ASA_JOB_NAME" --resource-group "$RESOURCE_GROUP" --output none
            
            # Wait for job to stop
            local max_attempts=30
            local attempt=0
            while [[ $attempt -lt $max_attempts ]]; do
                local current_state=$(az stream-analytics job show --name "$ASA_JOB_NAME" --resource-group "$RESOURCE_GROUP" --query "jobState" --output tsv 2>/dev/null || echo "NotFound")
                if [[ "$current_state" == "Stopped" ]]; then
                    log_success "Stream Analytics job stopped"
                    break
                fi
                log "Waiting for Stream Analytics job to stop... ($((attempt + 1))/$max_attempts)"
                sleep 10
                ((attempt++))
            done
        fi
    fi
    
    log_success "Services stopped"
}

# Function to remove IoT Edge deployments
remove_iot_edge_deployments() {
    log "Removing IoT Edge deployments..."
    
    if [[ -n "${IOT_HUB_NAME:-}" ]]; then
        # List all deployments
        local deployments=$(az iot edge deployment list --hub-name "$IOT_HUB_NAME" --query "[].id" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$deployments" ]]; then
            while IFS= read -r deployment_id; do
                if [[ -n "$deployment_id" ]]; then
                    log "Removing deployment: $deployment_id"
                    az iot edge deployment delete --deployment-id "$deployment_id" --hub-name "$IOT_HUB_NAME" --output none || log_warning "Failed to remove deployment $deployment_id"
                fi
            done <<< "$deployments"
        fi
        
        # Remove IoT Edge devices
        local devices=$(az iot hub device-identity list --hub-name "$IOT_HUB_NAME" --edge-enabled --query "[].deviceId" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$devices" ]]; then
            while IFS= read -r device_id; do
                if [[ -n "$device_id" ]]; then
                    log "Removing IoT Edge device: $device_id"
                    az iot hub device-identity delete --device-id "$device_id" --hub-name "$IOT_HUB_NAME" --output none || log_warning "Failed to remove device $device_id"
                fi
            done <<< "$devices"
        fi
    fi
    
    log_success "IoT Edge deployments removed"
}

# Function to clean up storage containers
cleanup_storage_containers() {
    log "Cleaning up storage containers..."
    
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        # Delete storage containers
        local containers=("ml-models" "anomaly-data")
        
        for container in "${containers[@]}"; do
            if az storage container exists --name "$container" --account-name "$STORAGE_ACCOUNT" --auth-mode login --output tsv 2>/dev/null | grep -q "True"; then
                log "Deleting storage container: $container"
                az storage container delete --name "$container" --account-name "$STORAGE_ACCOUNT" --auth-mode login --output none || log_warning "Failed to delete container $container"
            fi
        done
    fi
    
    log_success "Storage containers cleaned up"
}

# Function to remove ML compute resources
remove_ml_compute() {
    log "Removing ML compute resources..."
    
    if [[ -n "${ML_WORKSPACE:-}" ]]; then
        # List and delete compute instances
        local compute_instances=$(az ml compute list --resource-group "$RESOURCE_GROUP" --workspace-name "$ML_WORKSPACE" --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$compute_instances" ]]; then
            while IFS= read -r compute_name; do
                if [[ -n "$compute_name" ]]; then
                    log "Deleting ML compute instance: $compute_name"
                    az ml compute delete --name "$compute_name" --resource-group "$RESOURCE_GROUP" --workspace-name "$ML_WORKSPACE" --yes --output none || log_warning "Failed to delete compute instance $compute_name"
                fi
            done <<< "$compute_instances"
        fi
    fi
    
    log_success "ML compute resources removed"
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group: $RESOURCE_GROUP"
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP does not exist"
        return 0
    fi
    
    # Delete resource group
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    
    log_success "Resource group deletion initiated: $RESOURCE_GROUP"
    log "Note: Complete deletion may take 10-15 minutes"
    
    # Optionally wait for deletion to complete
    if [[ "${WAIT_FOR_DELETION:-}" == "true" ]]; then
        log "Waiting for resource group deletion to complete..."
        
        local max_attempts=90  # 15 minutes
        local attempt=0
        
        while [[ $attempt -lt $max_attempts ]]; do
            if ! az group exists --name "$RESOURCE_GROUP"; then
                log_success "Resource group deletion completed"
                break
            fi
            
            log "Waiting for resource group deletion... ($((attempt + 1))/$max_attempts)"
            sleep 10
            ((attempt++))
        done
        
        if [[ $attempt -eq $max_attempts ]]; then
            log_warning "Resource group deletion is taking longer than expected"
            log "You can check the status in the Azure Portal"
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment artifacts
    local files_to_remove=(
        "deployment.json"
        "edge_device_connection_string.txt"
        "input_config.json"
        "output_config.json"
        "deployment_*.log"
    )
    
    for file_pattern in "${files_to_remove[@]}"; do
        if ls $file_pattern 1> /dev/null 2>&1; then
            log "Removing: $file_pattern"
            rm -f $file_pattern
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check if resource group still exists
    if az group exists --name "$RESOURCE_GROUP"; then
        log_warning "Resource group $RESOURCE_GROUP still exists (deletion may be in progress)"
        
        # List remaining resources
        local remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --output table 2>/dev/null || echo "")
        if [[ -n "$remaining_resources" ]]; then
            log "Remaining resources:"
            echo "$remaining_resources"
        fi
    else
        log_success "Resource group $RESOURCE_GROUP has been deleted"
    fi
    
    # Check for any remaining resource groups with our pattern
    local remaining_rgs=$(az group list --query "[?starts_with(name, 'rg-anomaly-detection-')].name" --output tsv)
    if [[ -n "$remaining_rgs" ]]; then
        log_warning "Other anomaly detection resource groups still exist:"
        echo "$remaining_rgs"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "===================="
    echo "Deleted Resource Group: $RESOURCE_GROUP"
    echo "Deleted Resources:"
    [[ -n "${IOT_HUB_NAME:-}" ]] && echo "  - IoT Hub: $IOT_HUB_NAME"
    [[ -n "${STORAGE_ACCOUNT:-}" ]] && echo "  - Storage Account: $STORAGE_ACCOUNT"
    [[ -n "${ML_WORKSPACE:-}" ]] && echo "  - ML Workspace: $ML_WORKSPACE"
    [[ -n "${ASA_JOB_NAME:-}" ]] && echo "  - Stream Analytics Job: $ASA_JOB_NAME"
    [[ -n "${LOG_WORKSPACE:-}" ]] && echo "  - Log Analytics Workspace: $LOG_WORKSPACE"
    echo "  - IoT Edge devices and deployments"
    echo "  - Storage containers and data"
    echo "  - ML compute instances"
    echo "===================="
    echo ""
    echo "All resources have been removed to prevent ongoing charges."
    echo "If you need to redeploy, run: ./deploy.sh"
}

# Main cleanup function
main() {
    log "Starting Azure IoT Edge Real-Time Anomaly Detection cleanup..."
    
    # Check if running in dry-run mode
    if [[ "${DRY_RUN:-}" == "true" ]]; then
        log "Running in DRY-RUN mode - no resources will be deleted"
        find_resource_groups
        extract_resource_names
        log "Would delete resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    check_prerequisites
    find_resource_groups
    extract_resource_names
    confirm_destruction
    stop_running_services
    remove_iot_edge_deployments
    cleanup_storage_containers
    remove_ml_compute
    delete_resource_group
    cleanup_local_files
    verify_cleanup
    display_cleanup_summary
    
    log_success "Cleanup completed successfully!"
    log "Total cleanup time: $SECONDS seconds"
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            export DRY_RUN=true
            shift
            ;;
        --force)
            export FORCE_DELETE=true
            shift
            ;;
        --wait)
            export WAIT_FOR_DELETION=true
            shift
            ;;
        --resource-group)
            export RESOURCE_GROUP="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run              Run in dry-run mode (no resources deleted)"
            echo "  --force                Skip confirmation prompts"
            echo "  --wait                 Wait for resource group deletion to complete"
            echo "  --resource-group NAME  Specify resource group name to delete"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

# Run main function
main "$@"