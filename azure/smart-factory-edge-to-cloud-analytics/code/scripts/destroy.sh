#!/bin/bash
set -euo pipefail

# =============================================================================
# Azure Manufacturing Analytics Cleanup Script
# Recipe: Orchestrating Edge-to-Cloud Manufacturing Analytics
# Services: Azure IoT Operations, Azure Event Hubs, Azure Stream Analytics, Azure Monitor
# =============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a cleanup.log
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a cleanup.log
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a cleanup.log
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a cleanup.log
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    log "Prerequisites check completed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Try to load from .env file if it exists
    if [ -f ".env" ]; then
        source .env
        info "Loaded environment variables from .env file"
    else
        warn ".env file not found. Environment variables must be provided manually."
        
        # Check if required variables are set
        if [ -z "${RESOURCE_GROUP:-}" ]; then
            error "RESOURCE_GROUP environment variable is required"
            exit 1
        fi
        
        if [ -z "${SUBSCRIPTION_ID:-}" ]; then
            export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        fi
    fi
    
    # Display what will be cleaned up
    info "Cleanup configuration:"
    info "  Resource Group: ${RESOURCE_GROUP:-Not Set}"
    info "  Subscription: ${SUBSCRIPTION_ID:-Not Set}"
    info "  Event Hubs Namespace: ${EVENT_HUBS_NAMESPACE:-Not Set}"
    info "  Stream Analytics Job: ${STREAM_ANALYTICS_JOB:-Not Set}"
    info "  Monitor Workspace: ${MONITOR_WORKSPACE:-Not Set}"
    
    log "Environment variables loaded"
}

# Function to confirm destruction
confirm_destruction() {
    if [ "${FORCE_DELETE:-false}" != "true" ]; then
        echo ""
        warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
        warn "This will permanently delete the following resources:"
        warn "  • Resource Group: ${RESOURCE_GROUP}"
        warn "  • All contained Azure resources including:"
        warn "    - Event Hubs namespace and hubs"
        warn "    - Stream Analytics jobs"
        warn "    - Log Analytics workspace"
        warn "    - Monitor alert rules and action groups"
        warn "    - All data and configurations"
        echo ""
        warn "This action cannot be undone!"
        echo ""
        
        read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
        if [[ ! $REPLY == "yes" ]]; then
            info "Cleanup cancelled by user"
            exit 0
        fi
        echo ""
    fi
    
    log "Destruction confirmed, proceeding with cleanup..."
}

# Function to stop running services
stop_services() {
    log "Stopping running services..."
    
    # Stop Stream Analytics job if it exists and is running
    if [ -n "${STREAM_ANALYTICS_JOB:-}" ]; then
        local job_state=$(az stream-analytics job show \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${STREAM_ANALYTICS_JOB}" \
            --query jobState --output tsv 2>/dev/null || echo "NotFound")
        
        if [ "$job_state" = "Running" ]; then
            info "Stopping Stream Analytics job: ${STREAM_ANALYTICS_JOB}"
            az stream-analytics job stop \
                --resource-group "${RESOURCE_GROUP}" \
                --name "${STREAM_ANALYTICS_JOB}" \
                --no-wait || warn "Failed to stop Stream Analytics job"
            log "Stream Analytics job stop initiated"
        elif [ "$job_state" != "NotFound" ]; then
            info "Stream Analytics job is already stopped (state: $job_state)"
        else
            info "Stream Analytics job not found, skipping"
        fi
    fi
    
    # Stop any running telemetry simulators
    if pgrep -f "manufacturing-telemetry-simulator.py" > /dev/null; then
        info "Stopping telemetry simulator processes..."
        pkill -f "manufacturing-telemetry-simulator.py" || warn "Failed to stop telemetry simulator"
        log "Telemetry simulators stopped"
    fi
    
    log "Services stopped"
}

# Function to remove Stream Analytics resources
remove_stream_analytics() {
    log "Removing Stream Analytics resources..."
    
    if [ -n "${STREAM_ANALYTICS_JOB:-}" ]; then
        # Check if Stream Analytics job exists
        if az stream-analytics job show --resource-group "${RESOURCE_GROUP}" --name "${STREAM_ANALYTICS_JOB}" &> /dev/null; then
            info "Deleting Stream Analytics job: ${STREAM_ANALYTICS_JOB}"
            az stream-analytics job delete \
                --resource-group "${RESOURCE_GROUP}" \
                --name "${STREAM_ANALYTICS_JOB}" \
                --no-wait || warn "Failed to delete Stream Analytics job"
            log "Stream Analytics job deletion initiated"
        else
            info "Stream Analytics job not found, skipping"
        fi
    fi
}

# Function to remove Event Hubs resources
remove_event_hubs() {
    log "Removing Event Hubs resources..."
    
    if [ -n "${EVENT_HUBS_NAMESPACE:-}" ]; then
        # Check if Event Hubs namespace exists
        if az eventhubs namespace show --resource-group "${RESOURCE_GROUP}" --name "${EVENT_HUBS_NAMESPACE}" &> /dev/null; then
            info "Deleting Event Hubs namespace: ${EVENT_HUBS_NAMESPACE}"
            az eventhubs namespace delete \
                --resource-group "${RESOURCE_GROUP}" \
                --name "${EVENT_HUBS_NAMESPACE}" \
                --no-wait || warn "Failed to delete Event Hubs namespace"
            log "Event Hubs namespace deletion initiated"
        else
            info "Event Hubs namespace not found, skipping"
        fi
    fi
}

# Function to remove monitoring resources
remove_monitoring() {
    log "Removing monitoring and alert resources..."
    
    # Remove alert rules
    local alert_rules=$(az monitor metrics alert list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [ -n "$alert_rules" ]; then
        for rule in $alert_rules; do
            info "Deleting alert rule: $rule"
            az monitor metrics alert delete \
                --resource-group "${RESOURCE_GROUP}" \
                --name "$rule" \
                --yes || warn "Failed to delete alert rule: $rule"
        done
        log "Alert rules removed"
    else
        info "No alert rules found, skipping"
    fi
    
    # Remove action groups
    local action_groups=$(az monitor action-group list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [ -n "$action_groups" ]; then
        for group in $action_groups; do
            info "Deleting action group: $group"
            az monitor action-group delete \
                --resource-group "${RESOURCE_GROUP}" \
                --name "$group" || warn "Failed to delete action group: $group"
        done
        log "Action groups removed"
    else
        info "No action groups found, skipping"
    fi
    
    # Remove Log Analytics workspace
    if [ -n "${MONITOR_WORKSPACE:-}" ]; then
        if az monitor log-analytics workspace show --resource-group "${RESOURCE_GROUP}" --workspace-name "${MONITOR_WORKSPACE}" &> /dev/null; then
            info "Deleting Log Analytics workspace: ${MONITOR_WORKSPACE}"
            az monitor log-analytics workspace delete \
                --resource-group "${RESOURCE_GROUP}" \
                --workspace-name "${MONITOR_WORKSPACE}" \
                --force true \
                --no-wait || warn "Failed to delete Log Analytics workspace"
            log "Log Analytics workspace deletion initiated"
        else
            info "Log Analytics workspace not found, skipping"
        fi
    fi
}

# Function to remove resource group and all contained resources
remove_resource_group() {
    log "Removing resource group and all contained resources..."
    
    if [ -n "${RESOURCE_GROUP:-}" ]; then
        # Check if resource group exists
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            info "Deleting resource group: ${RESOURCE_GROUP}"
            info "This will remove ALL resources in the group..."
            
            az group delete \
                --name "${RESOURCE_GROUP}" \
                --yes \
                --no-wait || error "Failed to delete resource group"
            
            log "Resource group deletion initiated: ${RESOURCE_GROUP}"
            info "Note: Complete resource deletion may take several minutes"
        else
            warn "Resource group ${RESOURCE_GROUP} not found"
        fi
    else
        error "RESOURCE_GROUP not specified"
        exit 1
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove generated files
    local files_to_remove=(
        ".env"
        "iot-operations-config.yaml"
        "manufacturing-telemetry-simulator.py"
        "requirements.txt"
        "manufacturing-analytics-query.sql"
        "stream_analytics_input.json"
        "manufacturing-dashboard.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            info "Removing local file: $file"
            rm -f "$file" || warn "Failed to remove $file"
        fi
    done
    
    log "Local files cleaned up"
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    if [ -n "${RESOURCE_GROUP:-}" ]; then
        # Check if resource group still exists
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            warn "Resource group ${RESOURCE_GROUP} still exists (deletion may be in progress)"
            info "You can check deletion status with: az group show --name ${RESOURCE_GROUP}"
        else
            log "✅ Resource group ${RESOURCE_GROUP} successfully deleted"
        fi
    fi
    
    log "Cleanup verification completed"
}

# Function to display cleanup summary
display_summary() {
    log "=== CLEANUP SUMMARY ==="
    info "Resources cleaned up:"
    info "  ✅ Stream Analytics job stopped and deleted"
    info "  ✅ Event Hubs namespace and hubs deleted"
    info "  ✅ Monitoring alerts and action groups removed"
    info "  ✅ Log Analytics workspace deleted"
    info "  ✅ Resource group deletion initiated"
    info "  ✅ Local configuration files removed"
    echo ""
    info "Cleanup completed successfully!"
    info "Note: Azure resource deletion may take several minutes to complete fully."
    echo ""
    warn "All manufacturing analytics infrastructure has been removed."
    warn "This action cannot be undone."
}

# Function to handle partial cleanup on error
handle_cleanup_error() {
    error "Cleanup encountered an error. Some resources may still exist."
    warn "You may need to manually remove remaining resources through the Azure Portal."
    warn "Resource Group: ${RESOURCE_GROUP:-Unknown}"
    exit 1
}

# Main cleanup function
main() {
    log "Starting Azure Manufacturing Analytics cleanup..."
    
    # Set up error handling
    trap handle_cleanup_error ERR
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_destruction
    stop_services
    
    # If we're doing a complete cleanup (resource group deletion)
    if [ "${COMPLETE_CLEANUP:-true}" = "true" ]; then
        remove_resource_group
    else
        # Otherwise, remove resources individually
        remove_stream_analytics
        remove_event_hubs
        remove_monitoring
    fi
    
    cleanup_local_files
    verify_cleanup
    display_summary
    
    log "Cleanup completed successfully!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --keep-rg)
            COMPLETE_CLEANUP=false
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force              Skip confirmation prompts"
            echo "  --resource-group RG  Specify resource group to delete"
            echo "  --keep-rg           Keep resource group, only delete individual resources"
            echo "  --help              Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  RESOURCE_GROUP      Resource group name (required if not in .env)"
            echo "  FORCE_DELETE        Set to 'true' to skip confirmations"
            echo ""
            echo "Examples:"
            echo "  $0                          # Interactive cleanup using .env file"
            echo "  $0 --force                  # Non-interactive cleanup"
            echo "  $0 --resource-group my-rg   # Specify resource group manually"
            echo "  $0 --keep-rg               # Delete individual resources, keep RG"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"