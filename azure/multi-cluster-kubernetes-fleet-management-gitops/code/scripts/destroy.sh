#!/bin/bash

# Multi-Cluster Kubernetes Fleet Management with GitOps
# Destroy Script - Safely removes all deployed infrastructure

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Default values
FORCE_DESTROY=false
SKIP_CONFIRMATION=false
CLEANUP_ONLY=false

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

# Warning function
warn() {
    log "${YELLOW}WARNING: $1${NC}"
}

# Success function
success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

# Info function
info() {
    log "${BLUE}INFO: $1${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get deployment state
get_deployment_state() {
    local key="$1"
    local default="${2:-}"
    
    if [ ! -f "$DEPLOYMENT_STATE_FILE" ]; then
        echo "$default"
        return
    fi
    
    jq -r --arg key "$key" '.[$key] // empty' "$DEPLOYMENT_STATE_FILE" 2>/dev/null | grep -v "^$" || echo "$default"
}

# Update deployment state
update_deployment_state() {
    local key="$1"
    local value="$2"
    
    if [ ! -f "$DEPLOYMENT_STATE_FILE" ]; then
        echo "{}" > "$DEPLOYMENT_STATE_FILE"
    fi
    
    jq --arg key "$key" --arg value "$value" '.[$key] = $value' "$DEPLOYMENT_STATE_FILE" > "${DEPLOYMENT_STATE_FILE}.tmp" && \
        mv "${DEPLOYMENT_STATE_FILE}.tmp" "$DEPLOYMENT_STATE_FILE"
}

# Wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    local timeout="${4:-1800}"  # 30 minutes default
    local interval="${5:-30}"   # 30 seconds default
    
    info "Waiting for ${resource_type} ${resource_name} to be deleted..."
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        case $resource_type in
            "resource-group")
                if ! az group exists --name "$resource_group" 2>/dev/null; then
                    success "Resource group $resource_group deleted"
                    return 0
                fi
                ;;
            "fleet")
                if ! az fleet show --resource-group "$resource_group" --name "$resource_name" >/dev/null 2>&1; then
                    success "Fleet $resource_name deleted"
                    return 0
                fi
                ;;
            "aks")
                if ! az aks show --resource-group "$resource_group" --name "$resource_name" >/dev/null 2>&1; then
                    success "AKS cluster $resource_name deleted"
                    return 0
                fi
                ;;
            "service-principal")
                if ! az ad sp show --id "$resource_name" >/dev/null 2>&1; then
                    success "Service principal $resource_name deleted"
                    return 0
                fi
                ;;
            *)
                error_exit "Unknown resource type: $resource_type"
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    warn "Timeout waiting for ${resource_type} ${resource_name} to be deleted"
    return 1
}

# Confirmation prompt
confirm_destruction() {
    if [ "$SKIP_CONFIRMATION" = true ]; then
        return 0
    fi
    
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    warn "This will permanently delete the following resources:"
    
    local resource_group=$(get_deployment_state "RESOURCE_GROUP")
    local fleet_name=$(get_deployment_state "FLEET_NAME")
    local aso_client_id=$(get_deployment_state "ASO_CLIENT_ID")
    
    if [ -n "$resource_group" ]; then
        warn "  • Resource Group: $resource_group"
        warn "  • All resources within the resource group including:"
        warn "    - Fleet Manager: $fleet_name"
        warn "    - AKS Clusters: aks-fleet-1, aks-fleet-2, aks-fleet-3"
        warn "    - Container Registry: $(get_deployment_state "ACR_NAME")"
        warn "    - Key Vault: $(get_deployment_state "KV_NAME")"
        warn "    - Storage Accounts and other resources"
    fi
    
    if [ -n "$aso_client_id" ]; then
        warn "  • Service Principal: $(get_deployment_state "ASO_SP_NAME")"
    fi
    
    warn "  • Local deployment state file: $DEPLOYMENT_STATE_FILE"
    
    echo ""
    warn "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    echo ""
    info "Destruction confirmed. Proceeding with cleanup..."
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check required commands
    local required_commands=("az" "kubectl" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            error_exit "Required command '$cmd' is not installed"
        fi
    done
    
    # Check Azure CLI login
    if ! az account show >/dev/null 2>&1; then
        error_exit "Azure CLI not logged in. Please run 'az login'"
    fi
    
    # Check if deployment state file exists
    if [ ! -f "$DEPLOYMENT_STATE_FILE" ]; then
        warn "Deployment state file not found: $DEPLOYMENT_STATE_FILE"
        warn "This may indicate no resources were deployed or state was lost"
        if [ "$FORCE_DESTROY" = false ]; then
            warn "Use --force to proceed without deployment state"
            exit 1
        fi
    fi
    
    success "Prerequisites check completed"
}

# Load environment from state
load_environment() {
    info "Loading environment from deployment state..."
    
    if [ ! -f "$DEPLOYMENT_STATE_FILE" ]; then
        warn "No deployment state file found, using default values"
        return
    fi
    
    export RESOURCE_GROUP=$(get_deployment_state "RESOURCE_GROUP" "rg-fleet-demo")
    export LOCATION=$(get_deployment_state "LOCATION" "eastus")
    export FLEET_NAME=$(get_deployment_state "FLEET_NAME" "multicluster-fleet")
    export SUBSCRIPTION_ID=$(get_deployment_state "SUBSCRIPTION_ID")
    export RANDOM_SUFFIX=$(get_deployment_state "RANDOM_SUFFIX")
    export ACR_NAME=$(get_deployment_state "ACR_NAME")
    export KV_NAME=$(get_deployment_state "KV_NAME")
    export ASO_SP_NAME=$(get_deployment_state "ASO_SP_NAME")
    export ASO_CLIENT_ID=$(get_deployment_state "ASO_CLIENT_ID")
    
    info "Environment loaded:"
    info "  RESOURCE_GROUP: $RESOURCE_GROUP"
    info "  FLEET_NAME: $FLEET_NAME"
    info "  LOCATION: $LOCATION"
    
    success "Environment loaded from deployment state"
}

# Clean up Kubernetes resources
cleanup_kubernetes_resources() {
    info "Cleaning up Kubernetes resources..."
    
    # Define regions
    local regions=("eastus" "westus2" "centralus")
    
    # Clean up fleet-app namespace across clusters
    for i in ${!regions[@]}; do
        local cluster_name="aks-fleet-$((i+1))"
        
        info "Cleaning up resources on $cluster_name..."
        
        # Try to get credentials (may fail if cluster is already deleted)
        if az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$cluster_name" --overwrite-existing >/dev/null 2>&1; then
            # Set context
            if kubectl config use-context "$cluster_name" >/dev/null 2>&1; then
                # Delete fleet-app namespace
                kubectl delete namespace fleet-app --ignore-not-found=true --timeout=300s || \
                    warn "Failed to delete fleet-app namespace on $cluster_name"
                
                # Delete azure-resources namespace
                kubectl delete namespace azure-resources --ignore-not-found=true --timeout=300s || \
                    warn "Failed to delete azure-resources namespace on $cluster_name"
                
                # Uninstall Azure Service Operator
                if command_exists helm; then
                    helm uninstall aso2 --namespace azureserviceoperator-system --ignore-not-found || \
                        warn "Failed to uninstall ASO from $cluster_name"
                    
                    # Delete ASO namespace
                    kubectl delete namespace azureserviceoperator-system --ignore-not-found=true --timeout=300s || \
                        warn "Failed to delete ASO namespace on $cluster_name"
                fi
                
                # Delete cert-manager
                kubectl delete -f https://github.com/jetstack/cert-manager/releases/download/v1.14.1/cert-manager.yaml --ignore-not-found=true || \
                    warn "Failed to delete cert-manager from $cluster_name"
                
                success "Cleaned up resources on $cluster_name"
            else
                warn "Could not set context for $cluster_name"
            fi
        else
            info "$cluster_name is not accessible or already deleted"
        fi
    done
    
    success "Kubernetes resources cleanup completed"
}

# Remove fleet members
remove_fleet_members() {
    info "Removing fleet members..."
    
    # Check if fleet exists
    if ! az fleet show --resource-group "$RESOURCE_GROUP" --name "$FLEET_NAME" >/dev/null 2>&1; then
        info "Fleet $FLEET_NAME not found, skipping member removal"
        return
    fi
    
    # Remove fleet members
    for i in {1..3}; do
        local member_name="member-$i"
        
        info "Removing fleet member: $member_name"
        
        if az fleet member show --resource-group "$RESOURCE_GROUP" --fleet-name "$FLEET_NAME" --name "$member_name" >/dev/null 2>&1; then
            az fleet member delete \
                --resource-group "$RESOURCE_GROUP" \
                --fleet-name "$FLEET_NAME" \
                --name "$member_name" \
                --yes || \
                warn "Failed to remove fleet member $member_name"
        else
            info "Fleet member $member_name not found"
        fi
    done
    
    success "Fleet members removal completed"
}

# Delete AKS clusters
delete_aks_clusters() {
    info "Deleting AKS clusters..."
    
    # Delete AKS clusters
    for i in {1..3}; do
        local cluster_name="aks-fleet-$i"
        
        info "Deleting AKS cluster: $cluster_name"
        
        if az aks show --resource-group "$RESOURCE_GROUP" --name "$cluster_name" >/dev/null 2>&1; then
            az aks delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$cluster_name" \
                --yes \
                --no-wait || \
                warn "Failed to initiate deletion of AKS cluster $cluster_name"
        else
            info "AKS cluster $cluster_name not found"
        fi
    done
    
    # Wait for cluster deletions to complete
    for i in {1..3}; do
        local cluster_name="aks-fleet-$i"
        wait_for_deletion "aks" "$cluster_name" "$RESOURCE_GROUP" 1800 60 || \
            warn "Timeout waiting for $cluster_name deletion"
    done
    
    success "AKS clusters deletion completed"
}

# Delete Fleet Manager
delete_fleet_manager() {
    info "Deleting Fleet Manager..."
    
    if az fleet show --resource-group "$RESOURCE_GROUP" --name "$FLEET_NAME" >/dev/null 2>&1; then
        az fleet delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$FLEET_NAME" \
            --yes || \
            warn "Failed to delete Fleet Manager $FLEET_NAME"
        
        wait_for_deletion "fleet" "$FLEET_NAME" "$RESOURCE_GROUP" 600 30 || \
            warn "Timeout waiting for Fleet Manager deletion"
    else
        info "Fleet Manager $FLEET_NAME not found"
    fi
    
    success "Fleet Manager deletion completed"
}

# Delete Service Principal
delete_service_principal() {
    info "Deleting Service Principal..."
    
    if [ -n "$ASO_CLIENT_ID" ]; then
        if az ad sp show --id "$ASO_CLIENT_ID" >/dev/null 2>&1; then
            az ad sp delete --id "$ASO_CLIENT_ID" || \
                warn "Failed to delete Service Principal $ASO_CLIENT_ID"
            
            wait_for_deletion "service-principal" "$ASO_CLIENT_ID" "" 300 10 || \
                warn "Timeout waiting for Service Principal deletion"
        else
            info "Service Principal $ASO_CLIENT_ID not found"
        fi
    else
        info "Service Principal ID not found in deployment state"
    fi
    
    success "Service Principal deletion completed"
}

# Delete resource group
delete_resource_group() {
    info "Deleting resource group..."
    
    if az group exists --name "$RESOURCE_GROUP" 2>/dev/null; then
        info "Deleting resource group: $RESOURCE_GROUP"
        info "This may take several minutes..."
        
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait || \
            warn "Failed to initiate resource group deletion"
        
        wait_for_deletion "resource-group" "$RESOURCE_GROUP" "$RESOURCE_GROUP" 1800 60 || \
            warn "Timeout waiting for resource group deletion"
    else
        info "Resource group $RESOURCE_GROUP not found"
    fi
    
    success "Resource group deletion completed"
}

# Clean up local state
cleanup_local_state() {
    info "Cleaning up local state..."
    
    # Remove kubectl contexts
    local regions=("eastus" "westus2" "centralus")
    for i in ${!regions[@]}; do
        local cluster_name="aks-fleet-$((i+1))"
        kubectl config delete-context "$cluster_name" >/dev/null 2>&1 || true
        kubectl config delete-cluster "$cluster_name" >/dev/null 2>&1 || true
    done
    
    # Remove deployment state file
    if [ -f "$DEPLOYMENT_STATE_FILE" ]; then
        rm -f "$DEPLOYMENT_STATE_FILE"
        success "Deployment state file removed"
    fi
    
    # Remove any temporary files
    rm -f "${DEPLOYMENT_STATE_FILE}.tmp"
    
    success "Local state cleanup completed"
}

# Cleanup only mode
cleanup_only_mode() {
    info "Running cleanup-only mode..."
    
    cleanup_kubernetes_resources
    cleanup_local_state
    
    success "Cleanup-only mode completed"
}

# Main destroy function
main() {
    # Initialize log file
    echo "=== Azure Kubernetes Fleet Manager Destruction Started at $(date) ===" > "$LOG_FILE"
    
    info "Starting Azure Kubernetes Fleet Manager destruction..."
    
    # Handle cleanup-only mode
    if [ "$CLEANUP_ONLY" = true ]; then
        cleanup_only_mode
        return
    fi
    
    # Run destroy steps
    check_prerequisites
    load_environment
    confirm_destruction
    
    info "Beginning destruction process..."
    
    # Clean up in reverse order of creation
    cleanup_kubernetes_resources
    remove_fleet_members
    delete_aks_clusters
    delete_fleet_manager
    delete_service_principal
    delete_resource_group
    cleanup_local_state
    
    success "=== Destruction completed successfully! ==="
    info "All resources have been removed"
    info "Full destruction log available at: $LOG_FILE"
    
    echo ""
    success "✅ Cleanup completed successfully!"
    info "All Azure resources have been deleted"
    info "Local state has been cleaned up"
    info "You will no longer be charged for these resources"
}

# Handle script interruption
cleanup_on_exit() {
    warn "Destruction interrupted. Some resources may still exist."
    warn "Re-run this script to complete the cleanup process."
    warn "Check the Azure portal to verify resource deletion."
}

trap cleanup_on_exit EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Safely destroys all Azure Kubernetes Fleet Manager resources."
            echo ""
            echo "Options:"
            echo "  -h, --help              Show this help message"
            echo "  -f, --force             Force destruction without deployment state"
            echo "  -y, --yes               Skip confirmation prompts"
            echo "  --cleanup-only          Only cleanup local state and Kubernetes resources"
            echo ""
            echo "Examples:"
            echo "  $0                      Interactive destruction with confirmations"
            echo "  $0 -y                   Destroy without confirmation prompts"
            echo "  $0 --cleanup-only       Only cleanup local state"
            echo "  $0 -f -y                Force destroy without state file"
            echo ""
            echo "Safety Features:"
            echo "  • Requires typing 'DELETE' to confirm destruction"
            echo "  • Waits for resources to be fully deleted"
            echo "  • Logs all operations for troubleshooting"
            echo "  • Cleanup continues even if some operations fail"
            exit 0
            ;;
        -f|--force)
            FORCE_DESTROY=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --cleanup-only)
            CLEANUP_ONLY=true
            shift
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

# Run main destruction
main