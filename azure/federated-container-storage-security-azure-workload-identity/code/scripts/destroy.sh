#!/bin/bash

# =============================================================================
# Azure Workload Identity and Container Storage Cleanup Script
# =============================================================================
# 
# This script removes all Azure resources created by the deployment script,
# including AKS cluster, Key Vault, managed identity, and resource group.
#
# Prerequisites:
# - Azure CLI logged in
# - kubectl configured (if cleaning up Kubernetes resources)
# - Environment file from deployment (.env)
#
# Usage: ./destroy.sh [--force] [--keep-rg] [--debug]
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ENV_FILE="${SCRIPT_DIR}/.env"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Default values
FORCE=${FORCE:-false}
KEEP_RG=${KEEP_RG:-false}
DEBUG=${DEBUG:-false}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --keep-rg)
            KEEP_RG=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--force] [--keep-rg] [--debug]"
            echo "  --force     Skip confirmation prompts"
            echo "  --keep-rg   Keep the resource group (only delete contained resources)"
            echo "  --debug     Enable debug logging"
            echo ""
            echo "This script will remove all resources created by deploy.sh"
            echo "WARNING: This action cannot be undone!"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $1" | tee -a "$LOG_FILE"
    fi
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Check $LOG_FILE for details."
    exit 1
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables from deployment..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        error_exit "Environment file not found: $ENV_FILE. Cannot proceed with cleanup."
    fi
    
    # Source the environment file
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    
    # Validate required variables
    local required_vars=("RESOURCE_GROUP" "AKS_CLUSTER_NAME" "KEY_VAULT_NAME" "IDENTITY_NAME" "NAMESPACE")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error_exit "Required environment variable $var not found in $ENV_FILE"
        fi
        log_debug "$var: ${!var}"
    done
    
    log_success "Environment variables loaded successfully"
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check required commands
    local required_commands=("az")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            error_exit "Required command '$cmd' not found. Please install it first."
        fi
        log_debug "Found required command: $cmd"
    done
    
    # Verify Azure CLI login
    if ! az account show >/dev/null 2>&1; then
        error_exit "Not logged into Azure CLI. Please run 'az login' first."
    fi
    
    # Check if kubectl is available (optional for cleanup)
    if command_exists "kubectl"; then
        log_debug "kubectl is available for Kubernetes resource cleanup"
    else
        log_warning "kubectl not found. Kubernetes resources will be cleaned up with Azure resources."
    fi
    
    log_success "Prerequisites validation completed"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE" == "true" ]]; then
        log "Force flag enabled, skipping confirmation"
        return 0
    fi
    
    echo ""
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo "   - Resource Group: $RESOURCE_GROUP"
    echo "   - AKS Cluster: $AKS_CLUSTER_NAME"
    echo "   - Key Vault: $KEY_VAULT_NAME"
    echo "   - Managed Identity: $IDENTITY_NAME"
    echo "   - All associated Kubernetes resources"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "User confirmed deletion"
}

# Function to cleanup Kubernetes resources
cleanup_kubernetes_resources() {
    log "Cleaning up Kubernetes resources..."
    
    if ! command_exists "kubectl"; then
        log "kubectl not available, skipping Kubernetes cleanup"
        return 0
    fi
    
    # Check if we can connect to the cluster
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log "Cannot connect to Kubernetes cluster, skipping Kubernetes cleanup"
        return 0
    fi
    
    # Delete test workload
    if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log "Deleting test workload and namespace: $NAMESPACE"
        kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --timeout=300s
        log_success "Namespace deleted: $NAMESPACE"
    else
        log_debug "Namespace $NAMESPACE not found"
    fi
    
    # Delete storage class
    if kubectl get storageclass ephemeral-storage >/dev/null 2>&1; then
        log "Deleting storage class: ephemeral-storage"
        kubectl delete storageclass ephemeral-storage --ignore-not-found=true
        log_success "Storage class deleted"
    else
        log_debug "Storage class ephemeral-storage not found"
    fi
    
    # Delete storage pool
    if kubectl get storagepool ephemeral-pool -n acstor >/dev/null 2>&1; then
        log "Deleting storage pool: ephemeral-pool"
        kubectl delete storagepool ephemeral-pool -n acstor --ignore-not-found=true --timeout=300s
        log_success "Storage pool deleted"
    else
        log_debug "Storage pool ephemeral-pool not found"
    fi
    
    log_success "Kubernetes resources cleanup completed"
}

# Function to remove Azure Container Storage extension
remove_container_storage_extension() {
    log "Removing Azure Container Storage extension..."
    
    # Check if cluster exists
    if ! az aks show --name "$AKS_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "AKS cluster not found, skipping extension cleanup"
        return 0
    fi
    
    # Check if extension exists
    if az k8s-extension show \
        --cluster-name "$AKS_CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-type managedClusters \
        --name azure-container-storage >/dev/null 2>&1; then
        
        log "Removing Azure Container Storage extension..."
        az k8s-extension delete \
            --cluster-name "$AKS_CLUSTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --cluster-type managedClusters \
            --name azure-container-storage \
            --yes \
            --output none
        
        log_success "Azure Container Storage extension removed"
    else
        log_debug "Azure Container Storage extension not found"
    fi
}

# Function to delete federated credentials
delete_federated_credentials() {
    log "Deleting federated credentials..."
    
    # Check if managed identity exists
    if ! az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "Managed identity not found, skipping federated credential cleanup"
        return 0
    fi
    
    # Delete federated credential
    if az identity federated-credential show \
        --name "workload-identity-federation" \
        --identity-name "$IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        
        az identity federated-credential delete \
            --name "workload-identity-federation" \
            --identity-name "$IDENTITY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none
        
        log_success "Federated credential deleted"
    else
        log_debug "Federated credential not found"
    fi
}

# Function to remove role assignments
remove_role_assignments() {
    log "Removing role assignments..."
    
    # Get identity object ID if it exists
    local identity_object_id
    if identity_object_id=$(az identity show \
        --name "$IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId \
        --output tsv 2>/dev/null); then
        
        # Get Key Vault ID if it exists
        local key_vault_id
        if key_vault_id=$(az keyvault show \
            --name "$KEY_VAULT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query id \
            --output tsv 2>/dev/null); then
            
            # Remove role assignment
            log "Removing Key Vault role assignment..."
            az role assignment delete \
                --assignee "$identity_object_id" \
                --scope "$key_vault_id" \
                --output none >/dev/null 2>&1 || true
            
            log_success "Role assignments removed"
        else
            log_debug "Key Vault not found, skipping role assignment cleanup"
        fi
    else
        log_debug "Managed identity not found, skipping role assignment cleanup"
    fi
}

# Function to delete individual Azure resources
delete_azure_resources() {
    log "Deleting individual Azure resources..."
    
    # Delete managed identity
    if az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "Deleting managed identity: $IDENTITY_NAME"
        az identity delete \
            --name "$IDENTITY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --output none
        log_success "Managed identity deleted: $IDENTITY_NAME"
    else
        log_debug "Managed identity not found: $IDENTITY_NAME"
    fi
    
    # Delete Key Vault
    if az keyvault show --name "$KEY_VAULT_NAME" >/dev/null 2>&1; then
        log "Deleting Key Vault: $KEY_VAULT_NAME"
        az keyvault delete \
            --name "$KEY_VAULT_NAME" \
            --output none
        
        # Purge the Key Vault to completely remove it
        log "Purging Key Vault: $KEY_VAULT_NAME"
        az keyvault purge \
            --name "$KEY_VAULT_NAME" \
            --output none >/dev/null 2>&1 || true
        
        log_success "Key Vault deleted and purged: $KEY_VAULT_NAME"
    else
        log_debug "Key Vault not found: $KEY_VAULT_NAME"
    fi
    
    # Delete AKS cluster
    if az aks show --name "$AKS_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "Deleting AKS cluster: $AKS_CLUSTER_NAME (this may take several minutes)"
        az aks delete \
            --name "$AKS_CLUSTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none
        log_success "AKS cluster deleted: $AKS_CLUSTER_NAME"
    else
        log_debug "AKS cluster not found: $AKS_CLUSTER_NAME"
    fi
    
    log_success "Individual Azure resources cleanup completed"
}

# Function to delete resource group
delete_resource_group() {
    if [[ "$KEEP_RG" == "true" ]]; then
        log "Keeping resource group as requested: $RESOURCE_GROUP"
        return 0
    fi
    
    log "Deleting resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "Deleting resource group and all contained resources..."
        log "This operation may take several minutes to complete"
        
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            --output none
        
        log_success "Resource group deletion initiated: $RESOURCE_GROUP"
        log "Note: Deletion continues in the background and may take several minutes"
    else
        log_debug "Resource group not found: $RESOURCE_GROUP"
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f "$ENV_FILE" ]]; then
        rm -f "$ENV_FILE"
        log_success "Environment file removed: $ENV_FILE"
    fi
    
    # Remove kubectl configuration for the deleted cluster
    if command_exists "kubectl" && [[ -n "${AKS_CLUSTER_NAME:-}" ]]; then
        kubectl config delete-context "$AKS_CLUSTER_NAME" >/dev/null 2>&1 || true
        kubectl config delete-cluster "$AKS_CLUSTER_NAME" >/dev/null 2>&1 || true
        kubectl config unset "users.clusterUser_${RESOURCE_GROUP}_${AKS_CLUSTER_NAME}" >/dev/null 2>&1 || true
        log_debug "Kubectl configuration cleaned up"
    fi
    
    log_success "Local files cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=()
    
    # Check if resource group still exists (if we tried to delete it)
    if [[ "$KEEP_RG" != "true" ]]; then
        if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
            cleanup_issues+=("Resource group still exists (deletion may be in progress)")
        fi
    fi
    
    # Check individual resources if keeping resource group
    if [[ "$KEEP_RG" == "true" ]]; then
        if az aks show --name "$AKS_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
            cleanup_issues+=("AKS cluster still exists")
        fi
        
        if az keyvault show --name "$KEY_VAULT_NAME" >/dev/null 2>&1; then
            cleanup_issues+=("Key Vault still exists")
        fi
        
        if az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
            cleanup_issues+=("Managed identity still exists")
        fi
    fi
    
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        log_success "Cleanup verification completed - all resources removed"
    else
        log_warning "Some resources may still exist:"
        for issue in "${cleanup_issues[@]}"; do
            log_warning "  - $issue"
        done
        log "This is normal for resource group deletion as it occurs asynchronously"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "=== Cleanup Summary ==="
    log "Timestamp: $TIMESTAMP"
    
    if [[ "$KEEP_RG" == "true" ]]; then
        log "Resource group preserved: $RESOURCE_GROUP"
        log "Individual resources deleted from resource group"
    else
        log "Resource group deletion initiated: $RESOURCE_GROUP"
        log "All resources will be deleted when resource group deletion completes"
    fi
    
    log "Environment file removed: $ENV_FILE"
    log "Log file: $LOG_FILE"
    echo ""
    
    if [[ "$KEEP_RG" != "true" ]]; then
        log "Note: Resource group deletion occurs asynchronously and may take several minutes"
        log "You can check the status with: az group show --name $RESOURCE_GROUP"
    fi
    
    echo ""
    log_success "Cleanup process completed!"
}

# Main execution function
main() {
    log "=== Starting Azure Workload Identity and Container Storage Cleanup ==="
    log "Timestamp: $TIMESTAMP"
    log "Log file: $LOG_FILE"
    
    load_environment
    validate_prerequisites
    confirm_deletion
    
    # Perform cleanup in the correct order
    cleanup_kubernetes_resources
    remove_container_storage_extension
    delete_federated_credentials
    remove_role_assignments
    
    if [[ "$KEEP_RG" == "true" ]]; then
        delete_azure_resources
    else
        delete_resource_group
    fi
    
    cleanup_local_files
    verify_cleanup
    display_summary
}

# Handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Cleanup script interrupted or failed"
        log "Some resources may not have been deleted. Check Azure portal manually."
        log "Log file: $LOG_FILE"
    fi
}
trap cleanup_on_exit EXIT

# Execute main function
main "$@"