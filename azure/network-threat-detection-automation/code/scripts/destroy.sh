#!/bin/bash

# Azure Network Threat Detection Cleanup Script
# This script removes all resources created by the deployment script
# for the Azure Network Threat Detection solution

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [ "$DRY_RUN" = "true" ]; then
    log_warning "Running in DRY RUN mode - no resources will be deleted"
    AZURE_CMD="echo [DRY RUN] az"
else
    AZURE_CMD="az"
fi

# Configuration variables
RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-network-threat-detection"}
FORCE_DELETE=${FORCE_DELETE:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group exists --name "$RESOURCE_GROUP" --output tsv | grep -q "true"; then
        log_warning "Resource group '$RESOURCE_GROUP' does not exist. Nothing to clean up."
        exit 0
    fi
    
    # Get subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    log "Current subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    
    log_success "Prerequisites check completed"
}

# Function to confirm deletion
confirm_deletion() {
    if [ "$SKIP_CONFIRMATION" = "true" ]; then
        log_warning "Skipping confirmation due to SKIP_CONFIRMATION=true"
        return 0
    fi
    
    log_warning "This will delete ALL resources in the resource group: $RESOURCE_GROUP"
    log_warning "This action cannot be undone!"
    
    # List resources that will be deleted
    log "The following resources will be deleted:"
    az resource list --resource-group "$RESOURCE_GROUP" --output table 2>/dev/null || log_warning "Could not list resources"
    
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log_success "Deletion confirmed"
}

# Function to load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    # Check if deployment info file exists
    if [ -f "/tmp/deployment-info.json" ]; then
        log "Found deployment info file"
        
        # Extract resource names from deployment info
        STORAGE_ACCOUNT=$(cat /tmp/deployment-info.json | grep -o '"storage_account": "[^"]*' | cut -d'"' -f4 || echo "")
        LOG_ANALYTICS_WORKSPACE=$(cat /tmp/deployment-info.json | grep -o '"log_analytics_workspace": "[^"]*' | cut -d'"' -f4 || echo "")
        LOGIC_APP_NAME=$(cat /tmp/deployment-info.json | grep -o '"logic_app": "[^"]*' | cut -d'"' -f4 || echo "")
        FLOW_LOG_NAME=$(cat /tmp/deployment-info.json | grep -o '"flow_log_name": "[^"]*' | cut -d'"' -f4 || echo "")
        DASHBOARD_NAME=$(cat /tmp/deployment-info.json | grep -o '"dashboard_name": "[^"]*' | cut -d'"' -f4 || echo "")
        
        log "Loaded resource names from deployment info"
    else
        log_warning "Deployment info file not found. Will attempt to discover resources."
        
        # Try to discover resources by listing them
        discover_resources
    fi
    
    log_success "Deployment information loaded"
}

# Function to discover resources
discover_resources() {
    log "Discovering resources in resource group..."
    
    # Discover storage accounts
    STORAGE_ACCOUNT=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'sanetworklogs')].name" --output tsv | head -1 || echo "")
    
    # Discover Log Analytics workspaces
    LOG_ANALYTICS_WORKSPACE=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'law-threat-detection')].name" --output tsv | head -1 || echo "")
    
    # Discover Logic Apps
    LOGIC_APP_NAME=$(az logic workflow list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'la-threat-response')].name" --output tsv | head -1 || echo "")
    
    # Discover flow logs (these are in NetworkWatcherRG)
    FLOW_LOG_NAME=$(az network watcher flow-log list --resource-group NetworkWatcherRG --query "[?contains(name, 'fl-')].name" --output tsv | head -1 || echo "")
    
    # Dashboard name is fixed
    DASHBOARD_NAME="Network-Threat-Detection-Dashboard"
    
    log_success "Resource discovery completed"
}

# Function to delete Logic Apps workflow
delete_logic_apps_workflow() {
    if [ -n "$LOGIC_APP_NAME" ]; then
        log "Deleting Logic Apps workflow: $LOGIC_APP_NAME..."
        
        $AZURE_CMD logic workflow delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$LOGIC_APP_NAME" \
            --yes || log_warning "Failed to delete Logic Apps workflow"
        
        log_success "Logic Apps workflow deleted"
    else
        log_warning "No Logic Apps workflow found to delete"
    fi
}

# Function to delete alert rules
delete_alert_rules() {
    log "Deleting alert rules..."
    
    # Delete port scanning alert rule
    $AZURE_CMD monitor scheduled-query delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "Port-Scanning-Alert" \
        --yes || log_warning "Failed to delete Port-Scanning-Alert"
    
    # Delete data exfiltration alert rule
    $AZURE_CMD monitor scheduled-query delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "Data-Exfiltration-Alert" \
        --yes || log_warning "Failed to delete Data-Exfiltration-Alert"
    
    log_success "Alert rules deleted"
}

# Function to delete monitoring dashboard
delete_monitoring_dashboard() {
    if [ -n "$DASHBOARD_NAME" ]; then
        log "Deleting monitoring dashboard: $DASHBOARD_NAME..."
        
        $AZURE_CMD monitor workbook delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$DASHBOARD_NAME" \
            --yes || log_warning "Failed to delete monitoring dashboard"
        
        log_success "Monitoring dashboard deleted"
    else
        log_warning "No monitoring dashboard found to delete"
    fi
}

# Function to disable NSG Flow Logs
disable_nsg_flow_logs() {
    if [ -n "$FLOW_LOG_NAME" ]; then
        log "Disabling NSG Flow Logs: $FLOW_LOG_NAME..."
        
        $AZURE_CMD network watcher flow-log delete \
            --resource-group NetworkWatcherRG \
            --name "$FLOW_LOG_NAME" \
            --yes || log_warning "Failed to disable NSG Flow Logs"
        
        log_success "NSG Flow Logs disabled"
    else
        log_warning "No NSG Flow Logs found to disable"
    fi
}

# Function to delete Log Analytics workspace
delete_log_analytics_workspace() {
    if [ -n "$LOG_ANALYTICS_WORKSPACE" ]; then
        log "Deleting Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE..."
        
        $AZURE_CMD monitor log-analytics workspace delete \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --yes || log_warning "Failed to delete Log Analytics workspace"
        
        log_success "Log Analytics workspace deleted"
    else
        log_warning "No Log Analytics workspace found to delete"
    fi
}

# Function to delete storage account
delete_storage_account() {
    if [ -n "$STORAGE_ACCOUNT" ]; then
        log "Deleting storage account: $STORAGE_ACCOUNT..."
        
        $AZURE_CMD storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes || log_warning "Failed to delete storage account"
        
        log_success "Storage account deleted"
    else
        log_warning "No storage account found to delete"
    fi
}

# Function to delete any remaining resources
delete_remaining_resources() {
    log "Checking for any remaining resources..."
    
    # List any remaining resources
    REMAINING_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [ -n "$REMAINING_RESOURCES" ]; then
        log_warning "Found remaining resources:"
        echo "$REMAINING_RESOURCES"
        
        if [ "$FORCE_DELETE" = "true" ]; then
            log "Force deleting remaining resources..."
            
            # Delete all remaining resources
            az resource list --resource-group "$RESOURCE_GROUP" --query "[].id" --output tsv 2>/dev/null | while read -r resource_id; do
                if [ -n "$resource_id" ]; then
                    $AZURE_CMD resource delete --ids "$resource_id" --yes || log_warning "Failed to delete resource: $resource_id"
                fi
            done
            
            log_success "Remaining resources deleted"
        else
            log_warning "Use FORCE_DELETE=true to force delete remaining resources"
        fi
    else
        log_success "No remaining resources found"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group: $RESOURCE_GROUP..."
    
    # Final confirmation for resource group deletion
    if [ "$SKIP_CONFIRMATION" != "true" ]; then
        echo ""
        read -p "Delete the entire resource group '$RESOURCE_GROUP'? (type 'yes' to confirm): " final_confirmation
        
        if [ "$final_confirmation" != "yes" ]; then
            log "Resource group deletion cancelled by user"
            return 0
        fi
    fi
    
    $AZURE_CMD group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    log_success "Resource group deletion initiated: $RESOURCE_GROUP"
    log_warning "Note: Deletion may take several minutes to complete"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary files if they exist
    [ -f "/tmp/deployment-info.json" ] && rm -f "/tmp/deployment-info.json"
    [ -f "/tmp/threat-detection-queries.kql" ] && rm -f "/tmp/threat-detection-queries.kql"
    [ -f "/tmp/logic-app-definition.json" ] && rm -f "/tmp/logic-app-definition.json"
    [ -f "/tmp/threat-monitoring-dashboard.json" ] && rm -f "/tmp/threat-monitoring-dashboard.json"
    
    log_success "Temporary files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check if resource group still exists
    if az group exists --name "$RESOURCE_GROUP" --output tsv | grep -q "true"; then
        log_warning "Resource group '$RESOURCE_GROUP' still exists. Deletion may be in progress."
        
        # Check if there are any resources left
        RESOURCE_COUNT=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
        
        if [ "$RESOURCE_COUNT" -eq 0 ]; then
            log_success "Resource group is empty. Full cleanup completed."
        else
            log_warning "Resource group contains $RESOURCE_COUNT resources. Cleanup may be incomplete."
        fi
    else
        log_success "Resource group '$RESOURCE_GROUP' has been deleted. Full cleanup completed."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "=================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Logic App: ${LOGIC_APP_NAME:-'Not found'}"
    echo "Storage Account: ${STORAGE_ACCOUNT:-'Not found'}"
    echo "Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE:-'Not found'}"
    echo "Flow Log: ${FLOW_LOG_NAME:-'Not found'}"
    echo "Dashboard: ${DASHBOARD_NAME:-'Not found'}"
    echo "=================================="
    log_success "Azure Network Threat Detection cleanup completed!"
    echo ""
    echo "All resources have been deleted or scheduled for deletion."
    echo "Note: Some resources may take a few minutes to fully delete."
}

# Function to handle partial cleanup
handle_partial_cleanup() {
    log "Performing partial cleanup (individual resources only)..."
    
    delete_logic_apps_workflow
    delete_alert_rules
    delete_monitoring_dashboard
    disable_nsg_flow_logs
    delete_log_analytics_workspace
    delete_storage_account
    delete_remaining_resources
    cleanup_temp_files
    
    log_success "Partial cleanup completed. Resource group preserved."
}

# Function to handle full cleanup
handle_full_cleanup() {
    log "Performing full cleanup (including resource group)..."
    
    delete_logic_apps_workflow
    delete_alert_rules
    delete_monitoring_dashboard
    disable_nsg_flow_logs
    delete_log_analytics_workspace
    delete_storage_account
    delete_remaining_resources
    delete_resource_group
    cleanup_temp_files
    
    log_success "Full cleanup completed."
}

# Main cleanup function
main() {
    log "Starting Azure Network Threat Detection cleanup..."
    
    # Check command line arguments
    PARTIAL_CLEANUP=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --partial)
                PARTIAL_CLEANUP=true
                shift
                ;;
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --skip-confirmation)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --partial           Delete individual resources but keep resource group"
                echo "  --force             Force delete remaining resources"
                echo "  --skip-confirmation Skip confirmation prompts"
                echo "  --help              Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Run cleanup steps
    check_prerequisites
    confirm_deletion
    load_deployment_info
    
    if [ "$PARTIAL_CLEANUP" = "true" ]; then
        handle_partial_cleanup
    else
        handle_full_cleanup
    fi
    
    verify_cleanup
    display_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Handle script interruption
trap 'log_error "Cleanup interrupted! Some resources may not have been deleted."; exit 1' INT TERM

# Run main function
main "$@"