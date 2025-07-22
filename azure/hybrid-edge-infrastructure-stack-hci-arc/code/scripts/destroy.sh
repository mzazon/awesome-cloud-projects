#!/bin/bash

# Azure Edge Computing Infrastructure Cleanup Script
# Recipe: Hybrid Edge Infrastructure with Stack HCI and Arc
# Version: 1.0
# Description: Safely removes all Azure Stack HCI and Azure Arc resources

set -euo pipefail

# Enable strict error handling
trap 'echo "❌ Error occurred at line $LINENO. Exiting..." >&2; exit 1' ERR

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

# Banner
echo -e "${RED}"
echo "=================================================="
echo "Azure Edge Computing Infrastructure Cleanup"
echo "Azure Stack HCI + Azure Arc Removal"
echo "=================================================="
echo -e "${NC}"

# Load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [[ -f ".env_vars" ]]; then
        source .env_vars
        log_success "Environment variables loaded from .env_vars"
        log "  Resource Group: ${RESOURCE_GROUP:-'Not set'}"
        log "  HCI Cluster: ${CLUSTER_NAME:-'Not set'}"
        log "  Arc Resource: ${ARC_RESOURCE_NAME:-'Not set'}"
        log "  Storage Account: ${STORAGE_ACCOUNT_NAME:-'Not set'}"
    else
        log_warning "Environment file .env_vars not found"
        log "Please set required environment variables manually:"
        
        # Fallback to environment variables or defaults
        export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-edge-infrastructure}"
        export LOCATION="${LOCATION:-eastus}"
        export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv 2>/dev/null || echo '')}"
        
        log "Using fallback values:"
        log "  Resource Group: $RESOURCE_GROUP"
        log "  Location: $LOCATION"
        
        if [[ -z "$SUBSCRIPTION_ID" ]]; then
            log_error "Cannot determine subscription ID. Please ensure Azure CLI is logged in."
            exit 1
        fi
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking cleanup prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' does not exist. It may have already been deleted."
        return 0
    fi
    
    log_success "Prerequisites check completed"
}

# Confirmation prompt
confirm_cleanup() {
    echo
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo
    log "This script will DELETE the following resources:"
    log "  🗂️  Resource Group: ${RESOURCE_GROUP}"
    log "  🖥️  HCI Cluster: ${CLUSTER_NAME:-'All clusters in resource group'}"
    log "  🔗 Arc Resources: ${ARC_RESOURCE_NAME:-'All Arc resources'}"
    log "  💾 Storage Account: ${STORAGE_ACCOUNT_NAME:-'All storage accounts'}"
    log "  📊 Log Analytics: ${LOG_ANALYTICS_WORKSPACE:-'All workspaces'}"
    log "  🛡️  Azure AD Applications and Service Principals"
    log "  📋 Policy Assignments and Definitions"
    echo
    
    # Check for --force flag
    if [[ "${FORCE_CLEANUP:-false}" == "true" ]]; then
        log_warning "Force cleanup enabled. Proceeding without confirmation..."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? This action cannot be undone. (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
    
    echo
    log "Proceeding with cleanup in 5 seconds... Press Ctrl+C to cancel"
    sleep 5
}

# Remove Kubernetes workloads
remove_kubernetes_workloads() {
    log "Removing Kubernetes workloads..."
    
    # Check if kubectl is available and configured
    if command -v kubectl &> /dev/null; then
        # Try to delete edge-apps namespace
        if kubectl get namespace edge-apps &> /dev/null; then
            log "Deleting edge-apps namespace..."
            kubectl delete namespace edge-apps --ignore-not-found=true --timeout=300s
            log_success "Edge-apps namespace deleted"
        else
            log_warning "Edge-apps namespace not found (may not exist)"
        fi
        
        # Try to delete AKS cluster if it exists
        if [[ -n "${CLUSTER_NAME:-}" ]]; then
            AKS_CLUSTER_NAME="aks-edge-${RANDOM_SUFFIX:-}"
            if az aksarc show --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" &> /dev/null; then
                log "Deleting AKS cluster: $AKS_CLUSTER_NAME"
                az aksarc delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$AKS_CLUSTER_NAME" \
                    --yes \
                    --no-wait
                log_success "AKS cluster deletion initiated"
            else
                log_warning "AKS cluster not found (may not have been created or already deleted)"
            fi
        fi
    else
        log_warning "kubectl not available, skipping Kubernetes cleanup"
    fi
    
    # Remove local configuration files
    if [[ -f "edge-workload-config.yaml" ]]; then
        rm -f edge-workload-config.yaml
        log_success "Removed edge-workload-config.yaml"
    fi
    
    log_success "Kubernetes workloads cleanup completed"
}

# Remove Azure Arc resources
remove_arc_resources() {
    log "Removing Azure Arc resources..."
    
    # Remove Arc-enabled machines
    if [[ -n "${ARC_RESOURCE_NAME:-}" ]]; then
        if az connectedmachine show --resource-group "$RESOURCE_GROUP" --name "$ARC_RESOURCE_NAME" &> /dev/null; then
            log "Deleting Arc machine: $ARC_RESOURCE_NAME"
            az connectedmachine delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$ARC_RESOURCE_NAME" \
                --yes
            log_success "Arc machine deleted: $ARC_RESOURCE_NAME"
        else
            log_warning "Arc machine not found: $ARC_RESOURCE_NAME"
        fi
    else
        # Try to find and delete all Arc machines in the resource group
        log "Searching for Arc machines in resource group..."
        ARC_MACHINES=$(az connectedmachine list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$ARC_MACHINES" ]]; then
            while IFS= read -r machine_name; do
                if [[ -n "$machine_name" ]]; then
                    log "Deleting Arc machine: $machine_name"
                    az connectedmachine delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --name "$machine_name" \
                        --yes
                    log_success "Arc machine deleted: $machine_name"
                fi
            done <<< "$ARC_MACHINES"
        else
            log_warning "No Arc machines found in resource group"
        fi
    fi
    
    # Delete service principal if created
    if [[ -n "${ARC_SP_ID:-}" ]]; then
        if az ad sp show --id "$ARC_SP_ID" &> /dev/null; then
            log "Deleting service principal: $ARC_SP_ID"
            az ad sp delete --id "$ARC_SP_ID"
            log_success "Service principal deleted: $ARC_SP_ID"
        else
            log_warning "Service principal not found: $ARC_SP_ID"
        fi
    else
        # Try to find service principals created for this deployment
        log "Searching for related service principals..."
        if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
            SP_DISPLAY_NAME="arc-servers-${RANDOM_SUFFIX}"
            SP_ID=$(az ad sp list --display-name "$SP_DISPLAY_NAME" --query "[0].appId" --output tsv 2>/dev/null || echo "")
            
            if [[ -n "$SP_ID" && "$SP_ID" != "null" ]]; then
                log "Deleting service principal: $SP_ID ($SP_DISPLAY_NAME)"
                az ad sp delete --id "$SP_ID"
                log_success "Service principal deleted: $SP_ID"
            else
                log_warning "Service principal not found: $SP_DISPLAY_NAME"
            fi
        fi
    fi
    
    log_success "Azure Arc resources cleanup completed"
}

# Remove Azure Stack HCI cluster
remove_hci_cluster() {
    log "Removing Azure Stack HCI cluster..."
    
    # Remove HCI cluster resource
    if [[ -n "${CLUSTER_NAME:-}" ]]; then
        if az stack-hci cluster show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" &> /dev/null; then
            log "Deleting HCI cluster: $CLUSTER_NAME"
            az stack-hci cluster delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$CLUSTER_NAME" \
                --yes
            log_success "HCI cluster deleted: $CLUSTER_NAME"
        else
            log_warning "HCI cluster not found: $CLUSTER_NAME"
        fi
    else
        # Try to find and delete all HCI clusters in the resource group
        log "Searching for HCI clusters in resource group..."
        HCI_CLUSTERS=$(az stack-hci cluster list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$HCI_CLUSTERS" ]]; then
            while IFS= read -r cluster_name; do
                if [[ -n "$cluster_name" ]]; then
                    log "Deleting HCI cluster: $cluster_name"
                    az stack-hci cluster delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --name "$cluster_name" \
                        --yes
                    log_success "HCI cluster deleted: $cluster_name"
                fi
            done <<< "$HCI_CLUSTERS"
        else
            log_warning "No HCI clusters found in resource group"
        fi
    fi
    
    # Delete associated AAD application
    if [[ -n "${AAD_APP_ID:-}" ]]; then
        if az ad app show --id "$AAD_APP_ID" &> /dev/null; then
            log "Deleting AAD application: $AAD_APP_ID"
            az ad app delete --id "$AAD_APP_ID"
            log_success "AAD application deleted: $AAD_APP_ID"
        else
            log_warning "AAD application not found: $AAD_APP_ID"
        fi
    else
        # Try to find AAD applications created for this deployment
        if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
            APP_DISPLAY_NAME="HCI-Cluster-${RANDOM_SUFFIX}"
            APP_ID=$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" --output tsv 2>/dev/null || echo "")
            
            if [[ -n "$APP_ID" && "$APP_ID" != "null" ]]; then
                log "Deleting AAD application: $APP_ID ($APP_DISPLAY_NAME)"
                az ad app delete --id "$APP_ID"
                log_success "AAD application deleted: $APP_ID"
            else
                log_warning "AAD application not found: $APP_DISPLAY_NAME"
            fi
        fi
    fi
    
    log_success "Azure Stack HCI cluster cleanup completed"
}

# Remove policy assignments and definitions
remove_policies() {
    log "Removing Azure Policy assignments and definitions..."
    
    # Remove policy assignments
    SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
    
    # Remove HCI security assignment
    if az policy assignment show --name "hci-security-assignment" --scope "$SCOPE" &> /dev/null; then
        log "Removing HCI security policy assignment..."
        az policy assignment delete --name "hci-security-assignment" --scope "$SCOPE"
        log_success "HCI security policy assignment removed"
    else
        log_warning "HCI security policy assignment not found"
    fi
    
    # Remove Arc guest configuration assignment
    if az policy assignment show --name "arc-guest-config" --scope "$SCOPE" &> /dev/null; then
        log "Removing Arc guest configuration policy assignment..."
        az policy assignment delete --name "arc-guest-config" --scope "$SCOPE"
        log_success "Arc guest configuration policy assignment removed"
    else
        log_warning "Arc guest configuration policy assignment not found"
    fi
    
    # Remove custom policy definition
    if az policy definition show --name "HCI-Security-Baseline" &> /dev/null; then
        log "Removing custom HCI security policy definition..."
        az policy definition delete --name "HCI-Security-Baseline"
        log_success "Custom HCI security policy definition removed"
    else
        log_warning "Custom HCI security policy definition not found"
    fi
    
    log_success "Azure Policy cleanup completed"
}

# Remove monitoring resources
remove_monitoring() {
    log "Removing monitoring resources..."
    
    # Remove data collection rules
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        DCR_NAME="dcr-hci-${RANDOM_SUFFIX}"
        if az monitor data-collection rule show --resource-group "$RESOURCE_GROUP" --name "$DCR_NAME" &> /dev/null; then
            log "Deleting data collection rule: $DCR_NAME"
            az monitor data-collection rule delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$DCR_NAME" \
                --yes
            log_success "Data collection rule deleted: $DCR_NAME"
        else
            log_warning "Data collection rule not found: $DCR_NAME"
        fi
    fi
    
    # Remove Log Analytics workspace
    if [[ -n "${LOG_ANALYTICS_WORKSPACE:-}" ]]; then
        if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_WORKSPACE" &> /dev/null; then
            log "Deleting Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
            az monitor log-analytics workspace delete \
                --resource-group "$RESOURCE_GROUP" \
                --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
                --yes \
                --force
            log_success "Log Analytics workspace deleted: $LOG_ANALYTICS_WORKSPACE"
        else
            log_warning "Log Analytics workspace not found: $LOG_ANALYTICS_WORKSPACE"
        fi
    else
        # Try to find and delete all Log Analytics workspaces in the resource group
        log "Searching for Log Analytics workspaces in resource group..."
        WORKSPACES=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$WORKSPACES" ]]; then
            while IFS= read -r workspace_name; do
                if [[ -n "$workspace_name" ]]; then
                    log "Deleting Log Analytics workspace: $workspace_name"
                    az monitor log-analytics workspace delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --workspace-name "$workspace_name" \
                        --yes \
                        --force
                    log_success "Log Analytics workspace deleted: $workspace_name"
                fi
            done <<< "$WORKSPACES"
        else
            log_warning "No Log Analytics workspaces found in resource group"
        fi
    fi
    
    log_success "Monitoring resources cleanup completed"
}

# Remove storage resources
remove_storage() {
    log "Removing storage resources..."
    
    # Remove storage account
    if [[ -n "${STORAGE_ACCOUNT_NAME:-}" ]]; then
        if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log "Deleting storage account: $STORAGE_ACCOUNT_NAME"
            az storage account delete \
                --name "$STORAGE_ACCOUNT_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
            log_success "Storage account deleted: $STORAGE_ACCOUNT_NAME"
        else
            log_warning "Storage account not found: $STORAGE_ACCOUNT_NAME"
        fi
    else
        # Try to find and delete all storage accounts in the resource group
        log "Searching for storage accounts in resource group..."
        STORAGE_ACCOUNTS=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$STORAGE_ACCOUNTS" ]]; then
            while IFS= read -r account_name; do
                if [[ -n "$account_name" ]]; then
                    log "Deleting storage account: $account_name"
                    az storage account delete \
                        --name "$account_name" \
                        --resource-group "$RESOURCE_GROUP" \
                        --yes
                    log_success "Storage account deleted: $account_name"
                fi
            done <<< "$STORAGE_ACCOUNTS"
        else
            log_warning "No storage accounts found in resource group"
        fi
    fi
    
    log_success "Storage resources cleanup completed"
}

# Remove resource group
remove_resource_group() {
    log "Removing resource group and all remaining resources..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting resource group: $RESOURCE_GROUP"
        log_warning "This will delete ALL resources in the resource group..."
        
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        
        log_success "Resource group deletion initiated: $RESOURCE_GROUP"
        log "Note: Resource group deletion is running in the background"
        log "You can check the status with: az group show --name $RESOURCE_GROUP"
    else
        log_warning "Resource group not found: $RESOURCE_GROUP (may have already been deleted)"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment variables file
    if [[ -f ".env_vars" ]]; then
        rm -f .env_vars
        log_success "Removed .env_vars file"
    fi
    
    # Remove any kubectl config contexts (if AKS cluster was created)
    if command -v kubectl &> /dev/null && [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        AKS_CONTEXT="aks-edge-${RANDOM_SUFFIX}"
        if kubectl config get-contexts "$AKS_CONTEXT" &> /dev/null; then
            log "Removing kubectl context: $AKS_CONTEXT"
            kubectl config delete-context "$AKS_CONTEXT" &> /dev/null || true
            kubectl config delete-cluster "$AKS_CONTEXT" &> /dev/null || true
            kubectl config delete-user "clusterUser_${RESOURCE_GROUP}_${AKS_CONTEXT}" &> /dev/null || true
            log_success "kubectl context removed: $AKS_CONTEXT"
        fi
    fi
    
    log_success "Local files cleanup completed"
}

# Validation function
validate_cleanup() {
    log "Validating cleanup completion..."
    
    local cleanup_success=true
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group still exists: $RESOURCE_GROUP (deletion may be in progress)"
        
        # Check remaining resources in the group
        REMAINING_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([*])" --output tsv 2>/dev/null || echo "0")
        log "Remaining resources in group: $REMAINING_RESOURCES"
        
        if [[ "$REMAINING_RESOURCES" -gt 0 ]]; then
            log_warning "Some resources may still be deleting. Check Azure portal for status."
            cleanup_success=false
        fi
    else
        log_success "Resource group successfully deleted: $RESOURCE_GROUP"
    fi
    
    # Check if local files were cleaned up
    if [[ -f ".env_vars" ]]; then
        log_warning "Local environment file still exists"
        cleanup_success=false
    fi
    
    if [[ "$cleanup_success" == true ]]; then
        log_success "Cleanup validation completed successfully"
    else
        log_warning "Cleanup validation completed with warnings"
    fi
}

# Main cleanup function
main() {
    local start_time=$(date +%s)
    
    echo
    log "Starting Azure Edge Computing Infrastructure cleanup..."
    echo
    
    # Execute cleanup steps
    load_environment
    check_prerequisites
    confirm_cleanup
    
    log "Beginning resource cleanup process..."
    echo
    
    remove_kubernetes_workloads
    remove_arc_resources
    remove_hci_cluster
    remove_policies
    remove_monitoring
    remove_storage
    remove_resource_group
    cleanup_local_files
    
    echo
    validate_cleanup
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo
    log_success "Cleanup process completed!"
    log "Total cleanup time: ${duration} seconds"
    echo
    log "Cleanup Summary:"
    log "  ✅ Kubernetes workloads removed"
    log "  ✅ Azure Arc resources removed"
    log "  ✅ Azure Stack HCI cluster removed"
    log "  ✅ Azure Policy assignments and definitions removed"
    log "  ✅ Monitoring resources removed"
    log "  ✅ Storage resources removed"
    log "  ✅ Resource group deletion initiated"
    log "  ✅ Local files cleaned up"
    echo
    log "Important Notes:"
    log "  - Resource group deletion may take several minutes to complete"
    log "  - Check Azure portal to confirm all resources are deleted"
    log "  - Some resources may have soft-delete enabled and require additional cleanup"
    log "  - Service principals and AAD applications have been removed"
    echo
    log_success "Azure Edge Computing Infrastructure cleanup completed successfully!"
    echo
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi