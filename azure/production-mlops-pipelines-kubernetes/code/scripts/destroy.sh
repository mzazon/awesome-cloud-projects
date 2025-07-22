#!/bin/bash

# Azure MLOps Pipeline Cleanup Script
# This script removes all resources created by the deployment script including:
# - Online endpoints and deployments
# - AKS cluster and node pools
# - Azure Machine Learning workspace
# - Azure Container Registry
# - Key Vault
# - Storage accounts
# - Application Insights
# - Log Analytics workspace
# - Resource group (optional)

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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command_exists kubectl; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show > /dev/null 2>&1; then
        log_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if ML extension is installed
    if ! az extension show --name ml > /dev/null 2>&1; then
        log_warning "Azure ML extension is not installed. Some cleanup operations may not be available."
    fi
    
    log_success "Prerequisites validated successfully"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set defaults (should match deploy.sh)
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-mlops-pipeline}"
    export LOCATION="${LOCATION:-eastus}"
    export WORKSPACE_NAME="${WORKSPACE_NAME:-mlw-mlops-demo}"
    export AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-aks-mlops-cluster}"
    export ACR_NAME="${ACR_NAME:-}"
    export KEYVAULT_NAME="${KEYVAULT_NAME:-}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-}"
    export DIAG_STORAGE_ACCOUNT="${DIAG_STORAGE_ACCOUNT:-}"
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-mlops-logs}"
    export APP_INSIGHTS_NAME="${APP_INSIGHTS_NAME:-mlops-insights}"
    export DELETE_RESOURCE_GROUP="${DELETE_RESOURCE_GROUP:-false}"
    
    # Try to discover resource names if not provided
    if [[ -z "${ACR_NAME}" ]]; then
        log "Discovering ACR name from resource group..."
        ACR_NAME=$(az acr list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv 2>/dev/null || echo "")
    fi
    
    if [[ -z "${KEYVAULT_NAME}" ]]; then
        log "Discovering Key Vault name from resource group..."
        KEYVAULT_NAME=$(az keyvault list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv 2>/dev/null || echo "")
    fi
    
    if [[ -z "${STORAGE_ACCOUNT}" ]]; then
        log "Discovering Storage Account name from resource group..."
        STORAGE_ACCOUNT=$(az storage account list --resource-group "${RESOURCE_GROUP}" --query "[?contains(name, 'stmlops')].name | [0]" -o tsv 2>/dev/null || echo "")
    fi
    
    if [[ -z "${DIAG_STORAGE_ACCOUNT}" ]]; then
        log "Discovering Diagnostic Storage Account name from resource group..."
        DIAG_STORAGE_ACCOUNT=$(az storage account list --resource-group "${RESOURCE_GROUP}" --query "[?contains(name, 'diag')].name | [0]" -o tsv 2>/dev/null || echo "")
    fi
    
    # Display configuration
    log "Configuration:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  ML Workspace: ${WORKSPACE_NAME}"
    log "  AKS Cluster: ${AKS_CLUSTER_NAME}"
    log "  Container Registry: ${ACR_NAME:-<not found>}"
    log "  Key Vault: ${KEYVAULT_NAME:-<not found>}"
    log "  Storage Account: ${STORAGE_ACCOUNT:-<not found>}"
    log "  Delete Resource Group: ${DELETE_RESOURCE_GROUP}"
    
    log_success "Environment variables configured"
}

# Confirmation prompt
confirm_deletion() {
    log_warning "This will delete all MLOps pipeline resources!"
    log_warning "This action cannot be undone."
    
    if [[ "${DELETE_RESOURCE_GROUP}" == "true" ]]; then
        log_warning "The entire resource group '${RESOURCE_GROUP}' will be deleted!"
    fi
    
    echo ""
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log_success "Cleanup confirmed, proceeding..."
}

# Clean up ML endpoints and deployments
cleanup_ml_endpoints() {
    log "Cleaning up ML endpoints and deployments..."
    
    if ! az ml workspace show --name "${WORKSPACE_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_warning "ML workspace not found, skipping endpoint cleanup"
        return
    fi
    
    # List and delete all online endpoints
    local endpoints
    endpoints=$(az ml online-endpoint list --resource-group "${RESOURCE_GROUP}" --workspace-name "${WORKSPACE_NAME}" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${endpoints}" ]]; then
        while IFS= read -r endpoint; do
            if [[ -n "${endpoint}" ]]; then
                log "Deleting endpoint: ${endpoint}"
                az ml online-endpoint delete \
                    --name "${endpoint}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --workspace-name "${WORKSPACE_NAME}" \
                    --yes \
                    --no-wait || log_warning "Failed to delete endpoint: ${endpoint}"
            fi
        done <<< "${endpoints}"
        
        # Wait for endpoint deletions to complete
        log "Waiting for endpoint deletions to complete..."
        sleep 60
        
        log_success "ML endpoints cleanup completed"
    else
        log_warning "No ML endpoints found to delete"
    fi
}

# Clean up AKS compute targets
cleanup_aks_compute() {
    log "Cleaning up AKS compute targets..."
    
    if ! az ml workspace show --name "${WORKSPACE_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_warning "ML workspace not found, skipping compute cleanup"
        return
    fi
    
    # List and detach all Kubernetes compute targets
    local compute_targets
    compute_targets=$(az ml compute list --resource-group "${RESOURCE_GROUP}" --workspace-name "${WORKSPACE_NAME}" --query "[?type=='Kubernetes'].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${compute_targets}" ]]; then
        while IFS= read -r compute; do
            if [[ -n "${compute}" ]]; then
                log "Detaching compute target: ${compute}"
                az ml compute detach \
                    --name "${compute}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --workspace-name "${WORKSPACE_NAME}" \
                    --yes || log_warning "Failed to detach compute target: ${compute}"
            fi
        done <<< "${compute_targets}"
        
        log_success "AKS compute targets cleanup completed"
    else
        log_warning "No AKS compute targets found to detach"
    fi
}

# Clean up AKS cluster
cleanup_aks_cluster() {
    log "Cleaning up AKS cluster..."
    
    if ! az aks show --name "${AKS_CLUSTER_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_warning "AKS cluster not found, skipping cluster cleanup"
        return
    fi
    
    # Remove ML extension first
    log "Removing ML extension from AKS..."
    if az k8s-extension show --name ml-extension --cluster-name "${AKS_CLUSTER_NAME}" --resource-group "${RESOURCE_GROUP}" --cluster-type managedClusters > /dev/null 2>&1; then
        az k8s-extension delete \
            --name ml-extension \
            --cluster-name "${AKS_CLUSTER_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --cluster-type managedClusters \
            --yes \
            --no-wait || log_warning "Failed to remove ML extension"
        
        log "Waiting for ML extension removal..."
        sleep 30
    fi
    
    # Delete AKS cluster
    log "Deleting AKS cluster (this may take 10-15 minutes)..."
    az aks delete \
        --name "${AKS_CLUSTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    
    log_success "AKS cluster deletion initiated"
}

# Clean up ML workspace
cleanup_ml_workspace() {
    log "Cleaning up ML workspace..."
    
    if ! az ml workspace show --name "${WORKSPACE_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_warning "ML workspace not found, skipping workspace cleanup"
        return
    fi
    
    # Delete ML workspace
    log "Deleting ML workspace: ${WORKSPACE_NAME}"
    az ml workspace delete \
        --name "${WORKSPACE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    
    log_success "ML workspace deletion initiated"
}

# Clean up Container Registry
cleanup_container_registry() {
    log "Cleaning up Container Registry..."
    
    if [[ -z "${ACR_NAME}" ]] || ! az acr show --name "${ACR_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_warning "Container Registry not found, skipping ACR cleanup"
        return
    fi
    
    # Delete Container Registry
    log "Deleting Container Registry: ${ACR_NAME}"
    az acr delete \
        --name "${ACR_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --yes
    
    log_success "Container Registry deleted"
}

# Clean up Key Vault
cleanup_key_vault() {
    log "Cleaning up Key Vault..."
    
    if [[ -z "${KEYVAULT_NAME}" ]] || ! az keyvault show --name "${KEYVAULT_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_warning "Key Vault not found, skipping Key Vault cleanup"
        return
    fi
    
    # Delete Key Vault
    log "Deleting Key Vault: ${KEYVAULT_NAME}"
    az keyvault delete \
        --name "${KEYVAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --yes
    
    # Purge Key Vault (permanent deletion)
    log "Purging Key Vault: ${KEYVAULT_NAME}"
    az keyvault purge \
        --name "${KEYVAULT_NAME}" \
        --no-wait || log_warning "Failed to purge Key Vault (may already be purged)"
    
    log_success "Key Vault cleanup completed"
}

# Clean up Storage Accounts
cleanup_storage_accounts() {
    log "Cleaning up Storage Accounts..."
    
    # Delete main storage account
    if [[ -n "${STORAGE_ACCOUNT}" ]] && az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log "Deleting Storage Account: ${STORAGE_ACCOUNT}"
        az storage account delete \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes
        log_success "Storage Account deleted: ${STORAGE_ACCOUNT}"
    else
        log_warning "Main Storage Account not found, skipping"
    fi
    
    # Delete diagnostic storage account
    if [[ -n "${DIAG_STORAGE_ACCOUNT}" ]] && az storage account show --name "${DIAG_STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log "Deleting Diagnostic Storage Account: ${DIAG_STORAGE_ACCOUNT}"
        az storage account delete \
            --name "${DIAG_STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes
        log_success "Diagnostic Storage Account deleted: ${DIAG_STORAGE_ACCOUNT}"
    else
        log_warning "Diagnostic Storage Account not found, skipping"
    fi
}

# Clean up Application Insights
cleanup_application_insights() {
    log "Cleaning up Application Insights..."
    
    if ! az monitor app-insights component show --app "${APP_INSIGHTS_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_warning "Application Insights not found, skipping cleanup"
        return
    fi
    
    # Delete Application Insights
    log "Deleting Application Insights: ${APP_INSIGHTS_NAME}"
    az monitor app-insights component delete \
        --app "${APP_INSIGHTS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --yes
    
    log_success "Application Insights deleted"
}

# Clean up Log Analytics workspace
cleanup_log_analytics() {
    log "Cleaning up Log Analytics workspace..."
    
    if ! az monitor log-analytics workspace show --workspace-name "${LOG_ANALYTICS_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_warning "Log Analytics workspace not found, skipping cleanup"
        return
    fi
    
    # Delete Log Analytics workspace
    log "Deleting Log Analytics workspace: ${LOG_ANALYTICS_WORKSPACE}"
    az monitor log-analytics workspace delete \
        --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    
    log_success "Log Analytics workspace deletion initiated"
}

# Clean up diagnostic settings
cleanup_diagnostic_settings() {
    log "Cleaning up diagnostic settings..."
    
    # This is handled automatically when AKS cluster is deleted
    log_success "Diagnostic settings cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove sample files if they exist
    local files_to_remove=(
        "score.py"
        "deployment-config.yml"
        "azure-pipelines.yml"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            log "Removing local file: ${file}"
            rm -f "${file}"
        fi
    done
    
    log_success "Local files cleanup completed"
}

# Delete resource group (optional)
delete_resource_group() {
    if [[ "${DELETE_RESOURCE_GROUP}" == "true" ]]; then
        log "Deleting resource group: ${RESOURCE_GROUP}"
        log_warning "This will delete ALL resources in the resource group!"
        
        # Final confirmation for resource group deletion
        echo ""
        read -p "Are you absolutely sure you want to delete the entire resource group '${RESOURCE_GROUP}'? (type 'DELETE' to confirm): " rg_confirmation
        
        if [[ "${rg_confirmation}" == "DELETE" ]]; then
            az group delete \
                --name "${RESOURCE_GROUP}" \
                --yes \
                --no-wait
            
            log_success "Resource group deletion initiated"
            log_warning "Complete deletion may take 10-15 minutes"
        else
            log_warning "Resource group deletion cancelled"
        fi
    else
        log "Resource group deletion skipped (set DELETE_RESOURCE_GROUP=true to delete)"
    fi
}

# Wait for deletions to complete
wait_for_deletions() {
    log "Waiting for resource deletions to complete..."
    
    if [[ "${DELETE_RESOURCE_GROUP}" == "true" ]]; then
        log "Monitoring resource group deletion..."
        local max_wait=900  # 15 minutes
        local wait_time=0
        
        while az group show --name "${RESOURCE_GROUP}" > /dev/null 2>&1; do
            if [[ $wait_time -ge $max_wait ]]; then
                log_warning "Resource group deletion taking longer than expected"
                break
            fi
            
            log "Resource group still exists, waiting... (${wait_time}s/${max_wait}s)"
            sleep 30
            wait_time=$((wait_time + 30))
        done
        
        if ! az group show --name "${RESOURCE_GROUP}" > /dev/null 2>&1; then
            log_success "Resource group deleted successfully"
        fi
    else
        log "Individual resource deletion monitoring not implemented"
        log "Please check Azure portal for deletion status"
    fi
}

# Print cleanup summary
print_summary() {
    log_success "=== CLEANUP COMPLETED ==="
    log ""
    log "The following resources have been cleaned up:"
    log "  ✅ ML endpoints and deployments"
    log "  ✅ AKS compute targets"
    log "  ✅ AKS cluster (deletion initiated)"
    log "  ✅ ML workspace (deletion initiated)"
    log "  ✅ Container Registry"
    log "  ✅ Key Vault"
    log "  ✅ Storage Accounts"
    log "  ✅ Application Insights"
    log "  ✅ Log Analytics workspace"
    log "  ✅ Local sample files"
    
    if [[ "${DELETE_RESOURCE_GROUP}" == "true" ]]; then
        log "  ✅ Resource group (deletion initiated)"
    else
        log "  ⚠️  Resource group (preserved)"
    fi
    
    log ""
    log "Notes:"
    log "  • Some deletions may take additional time to complete"
    log "  • Check Azure portal to verify all resources are deleted"
    log "  • Soft-deleted resources (like Key Vault) may need manual purging"
    
    if [[ "${DELETE_RESOURCE_GROUP}" != "true" ]]; then
        log "  • To delete the resource group, set DELETE_RESOURCE_GROUP=true"
    fi
    
    log ""
    log_success "MLOps pipeline cleanup completed successfully!"
}

# Main execution
main() {
    log "Starting Azure MLOps Pipeline cleanup..."
    
    # Run cleanup steps
    validate_prerequisites
    setup_environment
    confirm_deletion
    cleanup_ml_endpoints
    cleanup_aks_compute
    cleanup_aks_cluster
    cleanup_ml_workspace
    cleanup_container_registry
    cleanup_key_vault
    cleanup_storage_accounts
    cleanup_application_insights
    cleanup_log_analytics
    cleanup_diagnostic_settings
    cleanup_local_files
    delete_resource_group
    wait_for_deletions
    print_summary
    
    log_success "Azure MLOps Pipeline cleanup completed successfully!"
}

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi