#!/bin/bash

# Destroy script for Fleet Tracking with Geospatial Analytics
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Please log in to Azure CLI using 'az login'"
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Resource configuration - use provided values or defaults
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-geospatial-analytics}"
    export LOCATION="${LOCATION:-eastus}"
    
    # If RANDOM_SUFFIX is not provided, try to determine it from existing resources
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        log "Attempting to determine RANDOM_SUFFIX from existing resources..."
        
        # Try to find existing resources and extract suffix
        local existing_storage=$(az storage account list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[?starts_with(name, 'stfleet')].name" \
            --output tsv 2>/dev/null | head -1)
        
        if [[ -n "$existing_storage" ]]; then
            export RANDOM_SUFFIX="${existing_storage#stfleet}"
            info "Detected RANDOM_SUFFIX: $RANDOM_SUFFIX"
        else
            warn "Could not determine RANDOM_SUFFIX. Will attempt to delete resource group entirely."
            export RANDOM_SUFFIX=""
        fi
    fi
    
    # Service-specific names (only if we have a suffix)
    if [[ -n "$RANDOM_SUFFIX" ]]; then
        export EVENTHUB_NAMESPACE="ehns-fleet-${RANDOM_SUFFIX}"
        export EVENTHUB_NAME="vehicle-locations"
        export STORAGE_ACCOUNT="stfleet${RANDOM_SUFFIX}"
        export ASA_JOB="asa-geospatial-${RANDOM_SUFFIX}"
        export COSMOS_ACCOUNT="cosmos-fleet-${RANDOM_SUFFIX}"
        export MAPS_ACCOUNT="maps-fleet-${RANDOM_SUFFIX}"
        
        info "Resource Group: $RESOURCE_GROUP"
        info "Random Suffix: $RANDOM_SUFFIX"
        info "Event Hub Namespace: $EVENTHUB_NAMESPACE"
        info "Storage Account: $STORAGE_ACCOUNT"
        info "Stream Analytics Job: $ASA_JOB"
        info "Cosmos Account: $COSMOS_ACCOUNT"
        info "Maps Account: $MAPS_ACCOUNT"
    else
        info "Resource Group: $RESOURCE_GROUP (will be deleted entirely)"
    fi
}

# Function to confirm destruction
confirm_destruction() {
    log "Destruction Confirmation Required"
    echo "=================================="
    echo "⚠️  This will permanently delete the following resources:"
    echo ""
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        echo "- Event Hub Namespace: $EVENTHUB_NAMESPACE"
        echo "- Event Hub: $EVENTHUB_NAME"
        echo "- Storage Account: $STORAGE_ACCOUNT (and all stored data)"
        echo "- Cosmos DB Account: $COSMOS_ACCOUNT (and all databases)"
        echo "- Azure Maps Account: $MAPS_ACCOUNT"
        echo "- Stream Analytics Job: $ASA_JOB"
        echo "- Monitoring alerts and diagnostic settings"
    else
        echo "- Entire Resource Group: $RESOURCE_GROUP"
        echo "- All resources contained within the resource group"
    fi
    
    echo ""
    echo "🔴 This action cannot be undone!"
    echo "🔴 All data will be permanently lost!"
    echo ""
    echo "=================================="
    
    if [[ "${FORCE_DESTROY:-false}" != "true" ]]; then
        read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
        if [[ ! $REPLY == "yes" ]]; then
            log "Destruction cancelled by user"
            exit 0
        fi
        
        # Double confirmation for production-looking names
        if [[ "$RESOURCE_GROUP" == *"prod"* || "$RESOURCE_GROUP" == *"production"* ]]; then
            echo ""
            warn "Resource group name contains 'prod' or 'production'"
            read -p "Are you ABSOLUTELY sure? Type 'DELETE_PRODUCTION' to confirm: " -r
            if [[ ! $REPLY == "DELETE_PRODUCTION" ]]; then
                log "Destruction cancelled by user"
                exit 0
            fi
        fi
    fi
    
    log "Destruction confirmed. Proceeding with resource deletion..."
}

# Function to stop Stream Analytics job
stop_stream_analytics_job() {
    if [[ -z "${ASA_JOB:-}" ]]; then
        warn "Stream Analytics job name not available, skipping stop"
        return 0
    fi
    
    log "Stopping Stream Analytics job..."
    
    if az stream-analytics job show --name "$ASA_JOB" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        local job_state=$(az stream-analytics job show \
            --name "$ASA_JOB" \
            --resource-group "$RESOURCE_GROUP" \
            --query jobState \
            --output tsv)
        
        if [[ "$job_state" == "Running" ]]; then
            az stream-analytics job stop \
                --name "$ASA_JOB" \
                --resource-group "$RESOURCE_GROUP" \
                --output none
            
            log "✅ Stream Analytics job stopped: $ASA_JOB"
            
            # Wait for job to stop
            info "Waiting for job to stop..."
            local max_attempts=30
            local attempt=1
            
            while [[ $attempt -le $max_attempts ]]; do
                local current_state=$(az stream-analytics job show \
                    --name "$ASA_JOB" \
                    --resource-group "$RESOURCE_GROUP" \
                    --query jobState \
                    --output tsv)
                
                if [[ "$current_state" == "Stopped" ]]; then
                    log "✅ Stream Analytics job is now stopped"
                    break
                fi
                
                info "Job state: $current_state (attempt $attempt/$max_attempts)"
                sleep 5
                ((attempt++))
            done
            
            if [[ $attempt -gt $max_attempts ]]; then
                warn "Job stop verification timed out, proceeding anyway"
            fi
        else
            info "Stream Analytics job is not running (state: $job_state)"
        fi
    else
        warn "Stream Analytics job $ASA_JOB not found"
    fi
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log "Deleting monitoring resources..."
    
    # Delete metric alerts
    local alerts=$(az monitor metrics alert list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$alerts" ]]; then
        while IFS= read -r alert; do
            if [[ -n "$alert" ]]; then
                az monitor metrics alert delete \
                    --name "$alert" \
                    --resource-group "$RESOURCE_GROUP" \
                    --output none 2>/dev/null || warn "Failed to delete alert: $alert"
                info "Deleted metric alert: $alert"
            fi
        done <<< "$alerts"
    fi
    
    # Delete action groups
    local action_groups=$(az monitor action-group list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$action_groups" ]]; then
        while IFS= read -r group; do
            if [[ -n "$group" ]]; then
                az monitor action-group delete \
                    --name "$group" \
                    --resource-group "$RESOURCE_GROUP" \
                    --output none 2>/dev/null || warn "Failed to delete action group: $group"
                info "Deleted action group: $group"
            fi
        done <<< "$action_groups"
    fi
    
    log "✅ Monitoring resources cleaned up"
}

# Function to delete Stream Analytics job
delete_stream_analytics_job() {
    if [[ -z "${ASA_JOB:-}" ]]; then
        warn "Stream Analytics job name not available, skipping deletion"
        return 0
    fi
    
    log "Deleting Stream Analytics job..."
    
    if az stream-analytics job show --name "$ASA_JOB" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az stream-analytics job delete \
            --name "$ASA_JOB" \
            --resource-group "$RESOURCE_GROUP" \
            --output none
        
        log "✅ Stream Analytics job deleted: $ASA_JOB"
    else
        warn "Stream Analytics job $ASA_JOB not found"
    fi
}

# Function to delete Azure Maps account
delete_azure_maps() {
    if [[ -z "${MAPS_ACCOUNT:-}" ]]; then
        warn "Azure Maps account name not available, skipping deletion"
        return 0
    fi
    
    log "Deleting Azure Maps account..."
    
    if az maps account show --name "$MAPS_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az maps account delete \
            --name "$MAPS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --output none
        
        log "✅ Azure Maps account deleted: $MAPS_ACCOUNT"
    else
        warn "Azure Maps account $MAPS_ACCOUNT not found"
    fi
}

# Function to delete Cosmos DB account
delete_cosmos_db() {
    if [[ -z "${COSMOS_ACCOUNT:-}" ]]; then
        warn "Cosmos DB account name not available, skipping deletion"
        return 0
    fi
    
    log "Deleting Cosmos DB account..."
    
    if az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az cosmosdb delete \
            --name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none
        
        log "✅ Cosmos DB account deleted: $COSMOS_ACCOUNT"
    else
        warn "Cosmos DB account $COSMOS_ACCOUNT not found"
    fi
}

# Function to delete Event Hub namespace
delete_event_hub() {
    if [[ -z "${EVENTHUB_NAMESPACE:-}" ]]; then
        warn "Event Hub namespace name not available, skipping deletion"
        return 0
    fi
    
    log "Deleting Event Hub namespace..."
    
    if az eventhubs namespace show --name "$EVENTHUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az eventhubs namespace delete \
            --name "$EVENTHUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --output none
        
        log "✅ Event Hub namespace deleted: $EVENTHUB_NAMESPACE"
    else
        warn "Event Hub namespace $EVENTHUB_NAMESPACE not found"
    fi
}

# Function to delete storage account
delete_storage_account() {
    if [[ -z "${STORAGE_ACCOUNT:-}" ]]; then
        warn "Storage account name not available, skipping deletion"
        return 0
    fi
    
    log "Deleting storage account..."
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none
        
        log "✅ Storage account deleted: $STORAGE_ACCOUNT"
    else
        warn "Storage account $STORAGE_ACCOUNT not found"
    fi
}

# Function to delete entire resource group
delete_resource_group() {
    log "Deleting resource group..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            --output none
        
        log "✅ Resource group deletion initiated: $RESOURCE_GROUP"
        info "Note: Complete deletion may take 5-10 minutes"
    else
        warn "Resource group $RESOURCE_GROUP not found"
    fi
}

# Function to verify resource deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group still exists (deletion may still be in progress)"
        
        # List remaining resources
        local remaining_resources=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].name" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$remaining_resources" ]]; then
            info "Remaining resources:"
            while IFS= read -r resource; do
                if [[ -n "$resource" ]]; then
                    info "  - $resource"
                fi
            done <<< "$remaining_resources"
        fi
    else
        log "✅ Resource group successfully deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove sample event file if it exists
    if [[ -f "sample-event.json" ]]; then
        rm -f sample-event.json
        log "✅ Removed sample-event.json"
    fi
    
    # Remove any temporary files
    rm -f /tmp/query.sql /tmp/input_config.json /tmp/cosmos_output.json /tmp/blob_output.json 2>/dev/null || true
    
    log "✅ Local cleanup completed"
}

# Function to display destruction summary
display_summary() {
    log "Destruction Summary"
    echo "=================================="
    echo "Resource Group: $RESOURCE_GROUP"
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        echo "Random Suffix: $RANDOM_SUFFIX"
        echo ""
        echo "Deleted Resources:"
        echo "- Event Hub Namespace: $EVENTHUB_NAMESPACE"
        echo "- Event Hub: $EVENTHUB_NAME"
        echo "- Storage Account: $STORAGE_ACCOUNT"
        echo "- Cosmos DB Account: $COSMOS_ACCOUNT"
        echo "- Azure Maps Account: $MAPS_ACCOUNT"
        echo "- Stream Analytics Job: $ASA_JOB"
        echo "- Monitoring alerts and diagnostic settings"
    else
        echo "- Entire Resource Group and all contained resources"
    fi
    
    echo ""
    echo "Status: All resources have been deleted or marked for deletion"
    echo "Note: Some resources may take additional time to fully delete"
    echo ""
    echo "To verify complete deletion, run:"
    echo "  az group exists --name $RESOURCE_GROUP"
    echo "=================================="
}

# Function to handle individual resource deletion
delete_individual_resources() {
    log "Deleting individual resources..."
    
    # Delete resources in reverse order of creation
    stop_stream_analytics_job
    delete_monitoring_resources
    delete_stream_analytics_job
    delete_azure_maps
    delete_cosmos_db
    delete_event_hub
    delete_storage_account
    
    # Finally delete the resource group
    delete_resource_group
}

# Main destruction function
main() {
    log "Starting destruction of Real-Time Geospatial Analytics solution..."
    
    # Check if running in interactive mode
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        # Script is being executed directly
        check_prerequisites
        set_environment_variables
        confirm_destruction
    fi
    
    # Choose deletion strategy
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        # We have specific resource names, delete individually
        delete_individual_resources
    else
        # No specific suffix, delete entire resource group
        delete_resource_group
    fi
    
    verify_deletion
    cleanup_local_files
    
    log "🎉 Destruction completed successfully!"
    display_summary
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -f, --force             Skip confirmation prompts"
    echo "  -g, --resource-group    Specify resource group name"
    echo "  -s, --suffix            Specify random suffix"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP          Resource group name (default: rg-geospatial-analytics)"
    echo "  RANDOM_SUFFIX           Random suffix for resource names"
    echo "  FORCE_DESTROY           Skip confirmation if set to 'true'"
    echo ""
    echo "Examples:"
    echo "  $0                      # Interactive destruction"
    echo "  $0 -f                   # Force destruction without prompts"
    echo "  $0 -g my-rg -s abc123   # Specify resource group and suffix"
    echo "  FORCE_DESTROY=true $0   # Skip confirmation via environment variable"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -f|--force)
            export FORCE_DESTROY=true
            shift
            ;;
        -g|--resource-group)
            export RESOURCE_GROUP="$2"
            shift 2
            ;;
        -s|--suffix)
            export RANDOM_SUFFIX="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi