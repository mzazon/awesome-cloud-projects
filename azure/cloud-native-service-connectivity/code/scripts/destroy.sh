#!/bin/bash

# Destroy Azure Cloud-Native Service Connectivity Infrastructure
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="cloud-native-connectivity"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${SCRIPT_DIR}/destroy_${TIMESTAMP}.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    exit 1
}

# Success message function
success() {
    log "${GREEN}✅ ${1}${NC}"
}

# Info message function
info() {
    log "${BLUE}ℹ️  ${1}${NC}"
}

# Warning message function
warning() {
    log "${YELLOW}⚠️  ${1}${NC}"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        error_exit "kubectl is not installed. Please install it first."
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "You are not logged in to Azure. Please run 'az login' first."
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
set_environment_variables() {
    info "Setting environment variables..."
    
    # Try to load from deployment info file if available
    local info_file=$(find "${SCRIPT_DIR}" -name "deployment_info_*.txt" -type f -exec ls -t {} \; | head -1)
    
    if [[ -f "${info_file}" ]]; then
        info "Loading deployment information from: ${info_file}"
        
        export RESOURCE_GROUP=$(grep "Resource Group:" "${info_file}" | cut -d' ' -f3)
        export LOCATION=$(grep "Location:" "${info_file}" | cut -d' ' -f2)
        export SUBSCRIPTION_ID=$(grep "Subscription ID:" "${info_file}" | cut -d' ' -f3)
        export RANDOM_SUFFIX=$(grep "Random Suffix:" "${info_file}" | cut -d' ' -f3)
        
        # Set resource names
        export CLUSTER_NAME="aks-connectivity-${RANDOM_SUFFIX}"
        export AGC_NAME="agc-connectivity-${RANDOM_SUFFIX}"
        export STORAGE_ACCOUNT="storage${RANDOM_SUFFIX}"
        export SQL_SERVER="sqlserver-${RANDOM_SUFFIX}"
        export KEY_VAULT="kv-${RANDOM_SUFFIX}"
        export WORKLOAD_IDENTITY_NAME="wi-connectivity-${RANDOM_SUFFIX}"
        
        info "Loaded deployment information successfully"
    else
        # Set default values if deployment info not found
        export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-${PROJECT_NAME}}"
        export LOCATION="${LOCATION:-eastus}"
        export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
        
        # Try to determine RANDOM_SUFFIX from existing resources
        if [ -z "${RANDOM_SUFFIX:-}" ]; then
            info "Trying to determine resource suffix from existing resources..."
            
            # Try to find AKS cluster with our naming pattern
            local clusters=$(az aks list --resource-group "${RESOURCE_GROUP}" --query "[?starts_with(name, 'aks-connectivity-')].name" --output tsv 2>/dev/null || echo "")
            
            if [[ -n "${clusters}" ]]; then
                local cluster_name=$(echo "${clusters}" | head -1)
                export RANDOM_SUFFIX="${cluster_name##*-}"
                info "Determined suffix from existing cluster: ${RANDOM_SUFFIX}"
            else
                error_exit "Could not determine resource suffix. Please set RANDOM_SUFFIX environment variable or ensure deployment info file exists."
            fi
        fi
        
        # Set resource names
        export CLUSTER_NAME="aks-connectivity-${RANDOM_SUFFIX}"
        export AGC_NAME="agc-connectivity-${RANDOM_SUFFIX}"
        export STORAGE_ACCOUNT="storage${RANDOM_SUFFIX}"
        export SQL_SERVER="sqlserver-${RANDOM_SUFFIX}"
        export KEY_VAULT="kv-${RANDOM_SUFFIX}"
        export WORKLOAD_IDENTITY_NAME="wi-connectivity-${RANDOM_SUFFIX}"
        
        warning "Using default/discovered values. If these are incorrect, set environment variables manually."
    fi
    
    # Log environment variables
    info "Environment variables set:"
    info "  RESOURCE_GROUP: ${RESOURCE_GROUP}"
    info "  LOCATION: ${LOCATION}"
    info "  SUBSCRIPTION_ID: ${SUBSCRIPTION_ID}"
    info "  RANDOM_SUFFIX: ${RANDOM_SUFFIX}"
    info "  CLUSTER_NAME: ${CLUSTER_NAME}"
    info "  AGC_NAME: ${AGC_NAME}"
    info "  STORAGE_ACCOUNT: ${STORAGE_ACCOUNT}"
    info "  SQL_SERVER: ${SQL_SERVER}"
    info "  KEY_VAULT: ${KEY_VAULT}"
    info "  WORKLOAD_IDENTITY_NAME: ${WORKLOAD_IDENTITY_NAME}"
    
    success "Environment variables configured"
}

# Confirm destruction
confirm_destruction() {
    info "This will destroy the following resources:"
    info "  - Resource Group: ${RESOURCE_GROUP}"
    info "  - AKS Cluster: ${CLUSTER_NAME}"
    info "  - Application Gateway for Containers: ${AGC_NAME}"
    info "  - Storage Account: ${STORAGE_ACCOUNT}"
    info "  - SQL Server: ${SQL_SERVER}"
    info "  - Key Vault: ${KEY_VAULT}"
    info "  - Workload Identity: ${WORKLOAD_IDENTITY_NAME}"
    
    warning "This action cannot be undone!"
    
    if [[ "${FORCE_DESTROY:-false}" == "true" ]]; then
        info "Force destroy mode enabled, skipping confirmation"
        return 0
    fi
    
    echo -n "Are you sure you want to continue? (yes/no): "
    read -r response
    
    if [[ "${response}" != "yes" ]]; then
        info "Destruction cancelled"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Remove Kubernetes resources
remove_kubernetes_resources() {
    info "Removing Kubernetes resources..."
    
    # Check if cluster exists and is accessible
    if ! az aks show --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER_NAME}" &> /dev/null; then
        warning "AKS cluster ${CLUSTER_NAME} not found, skipping Kubernetes resource cleanup"
        return 0
    fi
    
    # Get AKS credentials
    info "Getting AKS credentials..."
    if ! az aks get-credentials \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${CLUSTER_NAME}" \
        --overwrite-existing &> /dev/null; then
        warning "Failed to get AKS credentials, skipping Kubernetes resource cleanup"
        return 0
    fi
    
    # Remove Gateway API resources
    info "Removing Gateway API resources..."
    kubectl delete httproute --all -n cloud-native-app --ignore-not-found=true || warning "Failed to delete HTTPRoutes"
    kubectl delete gateway --all -n cloud-native-app --ignore-not-found=true || warning "Failed to delete Gateways"
    
    # Remove application deployments and services
    info "Removing application deployments and services..."
    kubectl delete deployment --all -n cloud-native-app --ignore-not-found=true || warning "Failed to delete deployments"
    kubectl delete service --all -n cloud-native-app --ignore-not-found=true || warning "Failed to delete services"
    
    # Remove service accounts
    info "Removing service accounts..."
    kubectl delete serviceaccount workload-identity-sa -n cloud-native-app --ignore-not-found=true || warning "Failed to delete service account"
    
    # Remove namespace
    info "Removing namespace..."
    kubectl delete namespace cloud-native-app --ignore-not-found=true || warning "Failed to delete namespace"
    
    success "Kubernetes resources removed"
}

# Remove Service Connector connections
remove_service_connector() {
    info "Removing Service Connector connections..."
    
    # List of connection names to remove
    local connections=("storage-connection" "sql-connection" "keyvault-connection")
    
    for connection in "${connections[@]}"; do
        info "Removing Service Connector: ${connection}"
        if az containerapp connection show \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${connection}" &> /dev/null; then
            
            az containerapp connection delete \
                --resource-group "${RESOURCE_GROUP}" \
                --name "${connection}" \
                --yes || warning "Failed to delete Service Connector: ${connection}"
        else
            info "Service Connector ${connection} not found, skipping"
        fi
    done
    
    success "Service Connector connections removed"
}

# Remove workload identity
remove_workload_identity() {
    info "Removing Azure Workload Identity..."
    
    # Remove federated identity credentials
    if az identity show --resource-group "${RESOURCE_GROUP}" --name "${WORKLOAD_IDENTITY_NAME}" &> /dev/null; then
        info "Removing federated identity credentials..."
        
        local fed_creds=$(az identity federated-credential list \
            --identity-name "${WORKLOAD_IDENTITY_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query "[].name" \
            --output tsv 2>/dev/null || echo "")
        
        for cred in ${fed_creds}; do
            info "Removing federated credential: ${cred}"
            az identity federated-credential delete \
                --name "${cred}" \
                --identity-name "${WORKLOAD_IDENTITY_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || warning "Failed to delete federated credential: ${cred}"
        done
        
        # Remove managed identity
        info "Removing managed identity: ${WORKLOAD_IDENTITY_NAME}"
        az identity delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${WORKLOAD_IDENTITY_NAME}" \
            || warning "Failed to delete managed identity: ${WORKLOAD_IDENTITY_NAME}"
    else
        info "Managed identity ${WORKLOAD_IDENTITY_NAME} not found, skipping"
    fi
    
    success "Azure Workload Identity removed"
}

# Remove Application Gateway for Containers
remove_application_gateway() {
    info "Removing Application Gateway for Containers..."
    
    # Remove Application Gateway for Containers resource
    if az network application-gateway for-containers show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${AGC_NAME}" &> /dev/null; then
        
        info "Removing Application Gateway for Containers: ${AGC_NAME}"
        az network application-gateway for-containers delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${AGC_NAME}" \
            --yes || warning "Failed to delete Application Gateway for Containers: ${AGC_NAME}"
    else
        info "Application Gateway for Containers ${AGC_NAME} not found, skipping"
    fi
    
    success "Application Gateway for Containers removed"
}

# Remove Azure services
remove_azure_services() {
    info "Removing Azure services..."
    
    # Remove Key Vault
    if az keyvault show --name "${KEY_VAULT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "Removing Key Vault: ${KEY_VAULT}"
        az keyvault delete \
            --name "${KEY_VAULT}" \
            --resource-group "${RESOURCE_GROUP}" \
            || warning "Failed to delete Key Vault: ${KEY_VAULT}"
        
        # Purge Key Vault (if soft delete is enabled)
        info "Purging Key Vault: ${KEY_VAULT}"
        az keyvault purge \
            --name "${KEY_VAULT}" \
            --location "${LOCATION}" \
            || warning "Failed to purge Key Vault: ${KEY_VAULT}"
    else
        info "Key Vault ${KEY_VAULT} not found, skipping"
    fi
    
    # Remove SQL Database and Server
    if az sql server show --name "${SQL_SERVER}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "Removing SQL Database: application-db"
        az sql db delete \
            --resource-group "${RESOURCE_GROUP}" \
            --server "${SQL_SERVER}" \
            --name application-db \
            --yes || warning "Failed to delete SQL Database: application-db"
        
        info "Removing SQL Server: ${SQL_SERVER}"
        az sql server delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${SQL_SERVER}" \
            --yes || warning "Failed to delete SQL Server: ${SQL_SERVER}"
    else
        info "SQL Server ${SQL_SERVER} not found, skipping"
    fi
    
    # Remove Storage Account
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "Removing Storage Account: ${STORAGE_ACCOUNT}"
        az storage account delete \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes || warning "Failed to delete Storage Account: ${STORAGE_ACCOUNT}"
    else
        info "Storage Account ${STORAGE_ACCOUNT} not found, skipping"
    fi
    
    success "Azure services removed"
}

# Remove AKS cluster
remove_aks_cluster() {
    info "Removing AKS cluster..."
    
    if az aks show --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER_NAME}" &> /dev/null; then
        info "Removing AKS cluster: ${CLUSTER_NAME}"
        az aks delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${CLUSTER_NAME}" \
            --yes \
            --no-wait || warning "Failed to delete AKS cluster: ${CLUSTER_NAME}"
        
        info "AKS cluster deletion initiated (running in background)"
    else
        info "AKS cluster ${CLUSTER_NAME} not found, skipping"
    fi
    
    success "AKS cluster removal initiated"
}

# Remove resource group
remove_resource_group() {
    info "Removing resource group..."
    
    if [[ "${REMOVE_RESOURCE_GROUP:-true}" == "true" ]]; then
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            info "Removing resource group: ${RESOURCE_GROUP}"
            az group delete \
                --name "${RESOURCE_GROUP}" \
                --yes \
                --no-wait || warning "Failed to delete resource group: ${RESOURCE_GROUP}"
            
            info "Resource group deletion initiated (running in background)"
        else
            info "Resource group ${RESOURCE_GROUP} not found, skipping"
        fi
    else
        info "Resource group removal skipped (REMOVE_RESOURCE_GROUP=false)"
    fi
    
    success "Resource group removal initiated"
}

# Wait for resource cleanup
wait_for_cleanup() {
    if [[ "${WAIT_FOR_COMPLETION:-false}" == "true" ]]; then
        info "Waiting for resource cleanup to complete..."
        
        # Wait for resource group deletion
        local max_wait=1800  # 30 minutes
        local wait_time=0
        
        while az group show --name "${RESOURCE_GROUP}" &> /dev/null && [ ${wait_time} -lt ${max_wait} ]; do
            info "Waiting for resource group deletion... (${wait_time}s elapsed)"
            sleep 30
            wait_time=$((wait_time + 30))
        done
        
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            warning "Resource group deletion is taking longer than expected"
        else
            success "Resource group deletion completed"
        fi
    else
        info "Resource cleanup is running in background"
        info "Check Azure portal or run 'az group show --name ${RESOURCE_GROUP}' to monitor progress"
    fi
}

# Cleanup local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove kubectl context
    if kubectl config get-contexts --no-headers | grep -q "${CLUSTER_NAME}"; then
        info "Removing kubectl context for cluster: ${CLUSTER_NAME}"
        kubectl config delete-context "${CLUSTER_NAME}" || warning "Failed to remove kubectl context"
    fi
    
    # Clean up any temporary files
    find "${SCRIPT_DIR}" -name "*.tmp" -type f -delete 2>/dev/null || true
    
    success "Local files cleaned up"
}

# Save destruction summary
save_destruction_summary() {
    info "Saving destruction summary..."
    
    local summary_file="${SCRIPT_DIR}/destruction_summary_${TIMESTAMP}.txt"
    
    cat > "${summary_file}" <<EOF
Destruction Summary
==================
Date: $(date)
Resource Group: ${RESOURCE_GROUP}
Location: ${LOCATION}
Subscription ID: ${SUBSCRIPTION_ID}
Random Suffix: ${RANDOM_SUFFIX}

Resources Removed:
- AKS Cluster: ${CLUSTER_NAME}
- Application Gateway for Containers: ${AGC_NAME}
- Storage Account: ${STORAGE_ACCOUNT}
- SQL Server: ${SQL_SERVER}
- Key Vault: ${KEY_VAULT}
- Workload Identity: ${WORKLOAD_IDENTITY_NAME}

Status: Destruction initiated
Log file: ${LOG_FILE}

Note: Some resources may still be deleting in the background.
Check Azure portal for current status.
EOF
    
    success "Destruction summary saved to: ${summary_file}"
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  -f, --force              Force destroy without confirmation
  -w, --wait               Wait for cleanup to complete
  -k, --keep-resource-group Keep resource group after cleanup
  -h, --help               Show this help message

Environment Variables:
  RESOURCE_GROUP           Resource group name (default: rg-cloud-native-connectivity)
  LOCATION                 Azure region (default: eastus)
  RANDOM_SUFFIX            Resource suffix (auto-detected or required)
  FORCE_DESTROY            Set to 'true' to skip confirmation
  WAIT_FOR_COMPLETION      Set to 'true' to wait for completion
  REMOVE_RESOURCE_GROUP    Set to 'false' to keep resource group

Examples:
  $0                       Interactive destroy
  $0 --force               Force destroy without confirmation
  $0 --wait                Wait for cleanup completion
  $0 --keep-resource-group Keep resource group after cleanup
EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                export FORCE_DESTROY=true
                shift
                ;;
            -w|--wait)
                export WAIT_FOR_COMPLETION=true
                shift
                ;;
            -k|--keep-resource-group)
                export REMOVE_RESOURCE_GROUP=false
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
}

# Main destruction function
main() {
    log "Starting destruction of Azure Cloud-Native Service Connectivity..."
    log "Timestamp: $(date)"
    log "Script: ${0}"
    log "Log file: ${LOG_FILE}"
    
    parse_arguments "$@"
    check_prerequisites
    set_environment_variables
    confirm_destruction
    
    remove_kubernetes_resources
    remove_service_connector
    remove_workload_identity
    remove_application_gateway
    remove_azure_services
    remove_aks_cluster
    remove_resource_group
    
    wait_for_cleanup
    cleanup_local_files
    save_destruction_summary
    
    success "Destruction completed successfully!"
    info "Resources have been removed from resource group: ${RESOURCE_GROUP}"
    
    if [[ "${WAIT_FOR_COMPLETION:-false}" == "false" ]]; then
        info "Some resources may still be deleting in the background"
        info "Check Azure portal for current status"
    fi
}

# Run main function
main "$@"