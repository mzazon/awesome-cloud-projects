#!/bin/bash

# Azure Arc-enabled Data Services Cleanup Script
# This script removes all resources created by the deployment script
# to avoid ongoing charges and clean up the environment

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command_exists kubectl; then
        error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show >/dev/null 2>&1; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if arcdata extension is installed
    if ! az extension list --query "[?name=='arcdata']" -o tsv | grep -q arcdata; then
        warn "Azure Arc data services extension not found. Installing..."
        az extension add --name arcdata --yes
    fi
    
    log "Prerequisites check completed"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warn "This script will DELETE ALL Azure Arc-enabled Data Services resources"
    warn "This action is IRREVERSIBLE and will result in DATA LOSS"
    echo ""
    
    # If running in CI/CD or with --force flag, skip confirmation
    if [[ "${CI:-false}" == "true" || "$1" == "--force" ]]; then
        warn "Running in automated mode, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    read -p "Please type 'DELETE' to confirm resource deletion: " confirmation
    if [[ "$confirmation" != "DELETE" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed, proceeding with cleanup..."
}

# Function to discover and set environment variables
discover_resources() {
    log "Discovering existing resources..."
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        error "Could not retrieve subscription ID"
        exit 1
    fi
    
    # Try to find resource groups with arc data services
    local resource_groups=($(az group list --query "[?tags.purpose=='arc-data-services'].name" -o tsv))
    
    if [[ ${#resource_groups[@]} -eq 0 ]]; then
        # Check for any Arc data controllers
        local arc_controllers=($(az arcdata dc list --query "[].name" -o tsv 2>/dev/null || echo ""))
        
        if [[ -z "$arc_controllers" ]]; then
            warn "No Arc data services resources found"
            info "If you have resources with different tags, please set these environment variables:"
            info "export RESOURCE_GROUP='your-resource-group'"
            info "export ARC_DATA_CONTROLLER_NAME='your-arc-controller'"
            info "export SQL_MI_NAME='your-sql-mi'"
            exit 1
        fi
        
        # Use first Arc controller found
        export ARC_DATA_CONTROLLER_NAME="${arc_controllers[0]}"
        export RESOURCE_GROUP=$(az arcdata dc show --name "$ARC_DATA_CONTROLLER_NAME" --query resourceGroup -o tsv)
    else
        # Use first resource group found
        export RESOURCE_GROUP="${resource_groups[0]}"
        
        # Find Arc data controller in this resource group
        local arc_controllers=($(az arcdata dc list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo ""))
        if [[ ${#arc_controllers[@]} -gt 0 ]]; then
            export ARC_DATA_CONTROLLER_NAME="${arc_controllers[0]}"
        fi
    fi
    
    # Find SQL Managed Instances
    if [[ -n "$RESOURCE_GROUP" ]]; then
        local sql_instances=($(az sql mi-arc list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo ""))
        if [[ ${#sql_instances[@]} -gt 0 ]]; then
            export SQL_MI_NAME="${sql_instances[0]}"
        fi
    fi
    
    # Find Log Analytics workspaces
    if [[ -n "$RESOURCE_GROUP" ]]; then
        local workspaces=($(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo ""))
        if [[ ${#workspaces[@]} -gt 0 ]]; then
            export LOG_ANALYTICS_WORKSPACE="${workspaces[0]}"
        fi
    fi
    
    # Allow environment variable override
    export RESOURCE_GROUP="${RESOURCE_GROUP:-}"
    export ARC_DATA_CONTROLLER_NAME="${ARC_DATA_CONTROLLER_NAME:-}"
    export SQL_MI_NAME="${SQL_MI_NAME:-}"
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-}"
    
    info "Resource Group: ${RESOURCE_GROUP:-Not found}"
    info "Arc Data Controller: ${ARC_DATA_CONTROLLER_NAME:-Not found}"
    info "SQL Managed Instance: ${SQL_MI_NAME:-Not found}"
    info "Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE:-Not found}"
}

# Function to delete SQL Managed Instance
delete_sql_managed_instance() {
    if [[ -z "$SQL_MI_NAME" || -z "$RESOURCE_GROUP" ]]; then
        warn "SQL Managed Instance name or resource group not found, skipping SQL MI deletion"
        return 0
    fi
    
    log "Deleting SQL Managed Instance: $SQL_MI_NAME"
    
    # Check if SQL MI exists
    if ! az sql mi-arc show --resource-group "$RESOURCE_GROUP" --name "$SQL_MI_NAME" >/dev/null 2>&1; then
        info "SQL Managed Instance $SQL_MI_NAME not found, skipping deletion"
        return 0
    fi
    
    # Delete SQL Managed Instance
    if az sql mi-arc delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SQL_MI_NAME" \
        --yes \
        --no-wait; then
        log "SQL Managed Instance deletion initiated"
        
        # Wait for deletion to complete
        local timeout=300
        local count=0
        
        while [[ $count -lt $timeout ]]; do
            if ! az sql mi-arc show --resource-group "$RESOURCE_GROUP" --name "$SQL_MI_NAME" >/dev/null 2>&1; then
                log "SQL Managed Instance deleted successfully"
                break
            fi
            
            count=$((count + 10))
            info "Waiting for SQL MI deletion... ($count/$timeout seconds)"
            sleep 10
        done
        
        if [[ $count -ge $timeout ]]; then
            warn "Timeout waiting for SQL MI deletion, continuing with cleanup"
        fi
    else
        error "Failed to delete SQL Managed Instance, continuing with cleanup"
    fi
    
    # Delete SQL login secret
    if kubectl get secret sql-login-secret -n arc >/dev/null 2>&1; then
        kubectl delete secret sql-login-secret -n arc
        info "SQL login secret deleted"
    fi
}

# Function to delete Arc Data Controller
delete_arc_data_controller() {
    if [[ -z "$ARC_DATA_CONTROLLER_NAME" || -z "$RESOURCE_GROUP" ]]; then
        warn "Arc Data Controller name or resource group not found, skipping controller deletion"
        return 0
    fi
    
    log "Deleting Azure Arc Data Controller: $ARC_DATA_CONTROLLER_NAME"
    
    # Check if Arc Data Controller exists
    if ! az arcdata dc show --resource-group "$RESOURCE_GROUP" --name "$ARC_DATA_CONTROLLER_NAME" >/dev/null 2>&1; then
        info "Arc Data Controller $ARC_DATA_CONTROLLER_NAME not found, skipping deletion"
        return 0
    fi
    
    # Delete Arc Data Controller
    if az arcdata dc delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ARC_DATA_CONTROLLER_NAME" \
        --yes \
        --no-wait; then
        log "Arc Data Controller deletion initiated"
        
        # Wait for deletion to complete
        local timeout=300
        local count=0
        
        while [[ $count -lt $timeout ]]; do
            if ! az arcdata dc show --resource-group "$RESOURCE_GROUP" --name "$ARC_DATA_CONTROLLER_NAME" >/dev/null 2>&1; then
                log "Arc Data Controller deleted successfully"
                break
            fi
            
            count=$((count + 10))
            info "Waiting for Arc Data Controller deletion... ($count/$timeout seconds)"
            sleep 10
        done
        
        if [[ $count -ge $timeout ]]; then
            warn "Timeout waiting for Arc Data Controller deletion, continuing with cleanup"
        fi
    else
        error "Failed to delete Arc Data Controller, continuing with cleanup"
    fi
}

# Function to clean up Kubernetes resources
cleanup_kubernetes_resources() {
    log "Cleaning up Kubernetes resources..."
    
    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info >/dev/null 2>&1; then
        warn "Cannot connect to Kubernetes cluster, skipping Kubernetes cleanup"
        return 0
    fi
    
    # Delete arc namespace and all resources within it
    if kubectl get namespace arc >/dev/null 2>&1; then
        log "Deleting Kubernetes namespace 'arc'..."
        kubectl delete namespace arc --timeout=300s
        
        # Wait for namespace deletion
        local timeout=300
        local count=0
        
        while [[ $count -lt $timeout ]]; do
            if ! kubectl get namespace arc >/dev/null 2>&1; then
                log "Kubernetes namespace 'arc' deleted successfully"
                break
            fi
            
            count=$((count + 10))
            info "Waiting for namespace deletion... ($count/$timeout seconds)"
            sleep 10
        done
        
        if [[ $count -ge $timeout ]]; then
            warn "Timeout waiting for namespace deletion"
            
            # Force delete namespace if stuck
            warn "Attempting to force delete namespace..."
            kubectl patch namespace arc -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
        fi
    else
        info "Kubernetes namespace 'arc' not found, skipping deletion"
    fi
    
    # Clean up any remaining Arc-related resources
    local arc_resources=($(kubectl get all --all-namespaces -l app.kubernetes.io/component=arc-data-controller -o name 2>/dev/null || echo ""))
    if [[ ${#arc_resources[@]} -gt 0 ]]; then
        warn "Found remaining Arc resources, attempting cleanup..."
        for resource in "${arc_resources[@]}"; do
            kubectl delete "$resource" --timeout=60s 2>/dev/null || true
        done
    fi
}

# Function to delete monitoring and alerts
delete_monitoring_alerts() {
    if [[ -z "$RESOURCE_GROUP" ]]; then
        warn "Resource group not found, skipping monitoring cleanup"
        return 0
    fi
    
    log "Deleting monitoring and alerts..."
    
    # Delete metric alerts
    local alerts=("arc-sql-high-cpu" "arc-sql-low-storage")
    for alert in "${alerts[@]}"; do
        if az monitor metrics alert show --resource-group "$RESOURCE_GROUP" --name "$alert" >/dev/null 2>&1; then
            az monitor metrics alert delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$alert" \
                --yes
            info "Deleted alert: $alert"
        fi
    done
    
    # Delete action group
    if az monitor action-group show --resource-group "$RESOURCE_GROUP" --name "arc-sql-alerts" >/dev/null 2>&1; then
        az monitor action-group delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "arc-sql-alerts" \
            --yes
        info "Deleted action group: arc-sql-alerts"
    fi
    
    # Delete workbook
    if az monitor app-insights workbook show --resource-group "$RESOURCE_GROUP" --name "arc-sql-monitoring" >/dev/null 2>&1; then
        az monitor app-insights workbook delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "arc-sql-monitoring" \
            --yes
        info "Deleted workbook: arc-sql-monitoring"
    fi
}

# Function to delete policy assignments
delete_policy_assignments() {
    if [[ -z "$RESOURCE_GROUP" || -z "$SUBSCRIPTION_ID" ]]; then
        warn "Resource group or subscription ID not found, skipping policy cleanup"
        return 0
    fi
    
    log "Deleting policy assignments..."
    
    local policy_assignment_name="arc-sql-security-policy"
    local scope="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
    
    if az policy assignment show --name "$policy_assignment_name" --scope "$scope" >/dev/null 2>&1; then
        az policy assignment delete \
            --name "$policy_assignment_name" \
            --scope "$scope"
        info "Deleted policy assignment: $policy_assignment_name"
    fi
}

# Function to delete Log Analytics workspace
delete_log_analytics_workspace() {
    if [[ -z "$LOG_ANALYTICS_WORKSPACE" || -z "$RESOURCE_GROUP" ]]; then
        warn "Log Analytics workspace name or resource group not found, skipping workspace deletion"
        return 0
    fi
    
    log "Deleting Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
    
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_WORKSPACE" >/dev/null 2>&1; then
        az monitor log-analytics workspace delete \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --yes \
            --force
        log "Log Analytics workspace deleted successfully"
    else
        info "Log Analytics workspace not found, skipping deletion"
    fi
}

# Function to delete entire resource group
delete_resource_group() {
    if [[ -z "$RESOURCE_GROUP" ]]; then
        warn "Resource group not found, skipping resource group deletion"
        return 0
    fi
    
    log "Deleting resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        log "Resource group deletion initiated: $RESOURCE_GROUP"
        info "Resource group deletion is running in the background"
        info "This may take several minutes to complete"
    else
        info "Resource group not found, skipping deletion"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local configuration files..."
    
    # Remove configuration directory
    if [[ -d "./custom-config" ]]; then
        rm -rf ./custom-config
        info "Removed custom-config directory"
    fi
    
    # Remove workbook template
    if [[ -f "arc-sql-workbook.json" ]]; then
        rm -f arc-sql-workbook.json
        info "Removed arc-sql-workbook.json"
    fi
    
    # Remove any other temporary files
    local temp_files=("*.tmp" "*.log" ".arc-*")
    for pattern in "${temp_files[@]}"; do
        if ls $pattern >/dev/null 2>&1; then
            rm -f $pattern
            info "Removed temporary files: $pattern"
        fi
    done
    
    log "Local cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local cleanup_successful=true
    
    # Check if Arc Data Controller still exists
    if [[ -n "$ARC_DATA_CONTROLLER_NAME" && -n "$RESOURCE_GROUP" ]]; then
        if az arcdata dc show --resource-group "$RESOURCE_GROUP" --name "$ARC_DATA_CONTROLLER_NAME" >/dev/null 2>&1; then
            warn "Arc Data Controller still exists: $ARC_DATA_CONTROLLER_NAME"
            cleanup_successful=false
        fi
    fi
    
    # Check if SQL MI still exists
    if [[ -n "$SQL_MI_NAME" && -n "$RESOURCE_GROUP" ]]; then
        if az sql mi-arc show --resource-group "$RESOURCE_GROUP" --name "$SQL_MI_NAME" >/dev/null 2>&1; then
            warn "SQL Managed Instance still exists: $SQL_MI_NAME"
            cleanup_successful=false
        fi
    fi
    
    # Check if Kubernetes namespace still exists
    if kubectl cluster-info >/dev/null 2>&1; then
        if kubectl get namespace arc >/dev/null 2>&1; then
            warn "Kubernetes namespace 'arc' still exists"
            cleanup_successful=false
        fi
    fi
    
    # Check if resource group still exists (only if we're not doing background deletion)
    if [[ -n "$RESOURCE_GROUP" ]]; then
        if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
            info "Resource group still exists (deletion may be in progress): $RESOURCE_GROUP"
        fi
    fi
    
    if [[ "$cleanup_successful" == "true" ]]; then
        log "Cleanup verification passed"
    else
        warn "Some resources may still exist. Please check manually."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "============================================"
    echo "Cleaned up resources:"
    echo "- Resource Group: ${RESOURCE_GROUP:-Not found}"
    echo "- Arc Data Controller: ${ARC_DATA_CONTROLLER_NAME:-Not found}"
    echo "- SQL Managed Instance: ${SQL_MI_NAME:-Not found}"
    echo "- Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE:-Not found}"
    echo "- Kubernetes namespace: arc"
    echo "- Monitoring alerts and dashboards"
    echo "- Policy assignments"
    echo "- Local configuration files"
    echo "============================================"
    echo ""
    echo "Important Notes:"
    echo "- Resource group deletion may take several minutes to complete"
    echo "- Some resources may have soft-delete enabled and require additional cleanup"
    echo "- Check your Azure portal to verify all resources have been removed"
    echo "- Any data stored in the SQL Managed Instance has been permanently deleted"
}

# Main execution function
main() {
    log "Starting Azure Arc-enabled Data Services cleanup..."
    
    # Run cleanup steps
    check_prerequisites
    confirm_deletion "$@"
    discover_resources
    delete_sql_managed_instance
    delete_arc_data_controller
    cleanup_kubernetes_resources
    delete_monitoring_alerts
    delete_policy_assignments
    delete_log_analytics_workspace
    delete_resource_group
    cleanup_local_files
    verify_cleanup
    display_cleanup_summary
    
    log "Cleanup completed successfully!"
    log "Please verify in the Azure portal that all resources have been removed."
}

# Handle script interruption
trap 'error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"