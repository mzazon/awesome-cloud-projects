#!/bin/bash

# ==============================================================================
# Azure Secure GitOps CI/CD Cleanup Script
# Recipe: Secure GitOps CI/CD with Workload Identity and ArgoCD
# ==============================================================================

set -euo pipefail

# Configuration
SCRIPT_NAME="destroy.sh"
LOG_FILE="/tmp/azure-gitops-destroy-$(date +%Y%m%d-%H%M%S).log"
CLEANUP_START_TIME=$(date +%s)

# Default values (can be overridden by environment variables or config file)
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-gitops-demo}"
LOCATION="${LOCATION:-eastus}"
CLUSTER_NAME="${CLUSTER_NAME:-aks-gitops-cluster}"
KEY_VAULT_NAME="${KEY_VAULT_NAME:-}"
MANAGED_IDENTITY_NAME="${MANAGED_IDENTITY_NAME:-}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"
DRY_RUN="${DRY_RUN:-false}"
FORCE_DELETE="${FORCE_DELETE:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==============================================================================
# Utility Functions
# ==============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

show_progress() {
    local current=$1
    local total=$2
    local description="$3"
    local percentage=$((current * 100 / total))
    
    printf "\r${BLUE}[%d/%d] (%d%%) %s${NC}" "$current" "$total" "$percentage" "$description"
    
    if [[ $current -eq $total ]]; then
        printf "\n"
    fi
}

confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]] || [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    local resource_type="$1"
    local resource_name="$2"
    
    echo -e "${YELLOW}⚠️  WARNING: This will permanently delete the following ${resource_type}:${NC}"
    echo -e "${RED}   ${resource_name}${NC}"
    echo ""
    
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log INFO "Deletion cancelled by user"
        exit 0
    fi
}

load_configuration() {
    log INFO "Loading deployment configuration..."
    
    # Try to load configuration from saved file
    local config_file="/tmp/azure-gitops-config.env"
    
    if [[ -f "$config_file" ]]; then
        log INFO "Loading configuration from: $config_file"
        source "$config_file"
        log INFO "Configuration loaded successfully ✅"
    else
        log WARN "No configuration file found at: $config_file"
        log INFO "Using environment variables or defaults"
    fi
    
    # Validate required variables are set
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log ERROR "RESOURCE_GROUP is not set. Please provide it via environment variable or --resource-group option"
        exit 1
    fi
    
    # Get subscription ID if not set
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query id --output tsv 2>/dev/null || echo "")
    fi
    
    # Auto-discover resource names if not provided
    if [[ -z "$KEY_VAULT_NAME" ]] || [[ -z "$MANAGED_IDENTITY_NAME" ]]; then
        log INFO "Auto-discovering resource names..."
        discover_resource_names
    fi
}

discover_resource_names() {
    log INFO "Discovering resources in resource group: $RESOURCE_GROUP"
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Resource group $RESOURCE_GROUP does not exist"
        return 0
    fi
    
    # Discover Key Vault
    if [[ -z "$KEY_VAULT_NAME" ]]; then
        KEY_VAULT_NAME=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query "[?tags.purpose=='gitops-demo'].name | [0]" --output tsv 2>/dev/null || echo "")
        if [[ -n "$KEY_VAULT_NAME" ]]; then
            log INFO "Discovered Key Vault: $KEY_VAULT_NAME"
        fi
    fi
    
    # Discover Managed Identity
    if [[ -z "$MANAGED_IDENTITY_NAME" ]]; then
        MANAGED_IDENTITY_NAME=$(az identity list --resource-group "$RESOURCE_GROUP" --query "[?tags.purpose=='gitops-demo'].name | [0]" --output tsv 2>/dev/null || echo "")
        if [[ -n "$MANAGED_IDENTITY_NAME" ]]; then
            log INFO "Discovered Managed Identity: $MANAGED_IDENTITY_NAME"
        fi
    fi
    
    # Discover AKS cluster
    local discovered_cluster=$(az aks list --resource-group "$RESOURCE_GROUP" --query "[?tags.purpose=='gitops-demo'].name | [0]" --output tsv 2>/dev/null || echo "")
    if [[ -n "$discovered_cluster" ]]; then
        CLUSTER_NAME="$discovered_cluster"
        log INFO "Discovered AKS Cluster: $CLUSTER_NAME"
    fi
}

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log ERROR "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed (optional for cleanup)
    if ! command -v kubectl &> /dev/null; then
        log WARN "kubectl is not installed. Some Kubernetes-specific cleanup may be skipped."
    fi
    
    # Check Azure CLI login status
    if ! az account show &> /dev/null; then
        log ERROR "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    log INFO "Prerequisites check completed ✅"
}

# ==============================================================================
# Cleanup Functions
# ==============================================================================

cleanup_argocd_applications() {
    log INFO "Cleaning up ArgoCD applications..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete ArgoCD applications and sample resources"
        return 0
    fi
    
    # Check if kubectl is available and cluster is accessible
    if ! command -v kubectl &> /dev/null; then
        log WARN "kubectl not available, skipping Kubernetes resource cleanup"
        return 0
    fi
    
    # Try to get cluster credentials
    if [[ -n "$CLUSTER_NAME" ]]; then
        az aks get-credentials \
            --resource-group "$RESOURCE_GROUP" \
            --name "$CLUSTER_NAME" \
            --overwrite-existing \
            --output none 2>/dev/null || {
            log WARN "Could not access AKS cluster, skipping Kubernetes cleanup"
            return 0
        }
    fi
    
    # Delete ArgoCD applications
    if kubectl get application sample-app-gitops -n argocd &> /dev/null; then
        log INFO "Deleting ArgoCD application..."
        kubectl delete application sample-app-gitops -n argocd --ignore-not-found=true
    fi
    
    # Delete sample application namespace and resources
    if kubectl get namespace sample-app &> /dev/null; then
        log INFO "Deleting sample application namespace..."
        kubectl delete namespace sample-app --ignore-not-found=true
    fi
    
    log INFO "ArgoCD applications cleanup completed ✅"
}

remove_argocd_extension() {
    log INFO "Removing ArgoCD extension..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete ArgoCD extension"
        return 0
    fi
    
    # Check if extension exists
    if az k8s-extension show --resource-group "$RESOURCE_GROUP" --cluster-name "$CLUSTER_NAME" --cluster-type managedClusters --name argocd &> /dev/null; then
        log INFO "Deleting ArgoCD extension (this may take 5-10 minutes)..."
        
        az k8s-extension delete \
            --resource-group "$RESOURCE_GROUP" \
            --cluster-name "$CLUSTER_NAME" \
            --cluster-type managedClusters \
            --name argocd \
            --yes \
            --output none
    else
        log INFO "ArgoCD extension not found, skipping"
    fi
    
    log INFO "ArgoCD extension removal completed ✅"
}

delete_federated_credentials() {
    log INFO "Deleting federated identity credentials..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete federated identity credentials"
        return 0
    fi
    
    if [[ -z "$MANAGED_IDENTITY_NAME" ]]; then
        log WARN "Managed identity name not specified, skipping federated credential cleanup"
        return 0
    fi
    
    # Delete federated identity credentials
    local credentials=("argocd-application-controller" "argocd-server" "sample-app")
    
    for credential in "${credentials[@]}"; do
        if az identity federated-credential show \
            --name "$credential" \
            --identity-name "$MANAGED_IDENTITY_NAME" \
            --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            
            log INFO "Deleting federated credential: $credential"
            az identity federated-credential delete \
                --name "$credential" \
                --identity-name "$MANAGED_IDENTITY_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none
        fi
    done
    
    log INFO "Federated identity credentials deleted ✅"
}

delete_key_vault() {
    log INFO "Deleting Key Vault..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete Key Vault: $KEY_VAULT_NAME"
        return 0
    fi
    
    if [[ -z "$KEY_VAULT_NAME" ]]; then
        log WARN "Key Vault name not specified, skipping Key Vault cleanup"
        return 0
    fi
    
    # Check if Key Vault exists
    if az keyvault show --name "$KEY_VAULT_NAME" &> /dev/null; then
        log INFO "Deleting Key Vault: $KEY_VAULT_NAME"
        
        # Enable soft-delete purge protection bypass if needed
        az keyvault delete \
            --name "$KEY_VAULT_NAME" \
            --output none
        
        # Purge the Key Vault to completely remove it
        log INFO "Purging Key Vault to ensure complete removal..."
        az keyvault purge \
            --name "$KEY_VAULT_NAME" \
            --output none 2>/dev/null || log WARN "Could not purge Key Vault (may require manual cleanup)"
    else
        log INFO "Key Vault $KEY_VAULT_NAME not found, skipping"
    fi
    
    log INFO "Key Vault deletion completed ✅"
}

delete_managed_identity() {
    log INFO "Deleting managed identity..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete managed identity: $MANAGED_IDENTITY_NAME"
        return 0
    fi
    
    if [[ -z "$MANAGED_IDENTITY_NAME" ]]; then
        log WARN "Managed identity name not specified, skipping managed identity cleanup"
        return 0
    fi
    
    # Check if managed identity exists
    if az identity show --resource-group "$RESOURCE_GROUP" --name "$MANAGED_IDENTITY_NAME" &> /dev/null; then
        log INFO "Deleting managed identity: $MANAGED_IDENTITY_NAME"
        
        az identity delete \
            --name "$MANAGED_IDENTITY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --output none
    else
        log INFO "Managed identity $MANAGED_IDENTITY_NAME not found, skipping"
    fi
    
    log INFO "Managed identity deletion completed ✅"
}

delete_aks_cluster() {
    log INFO "Deleting AKS cluster..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete AKS cluster: $CLUSTER_NAME"
        return 0
    fi
    
    # Check if cluster exists
    if az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" &> /dev/null; then
        log INFO "Deleting AKS cluster: $CLUSTER_NAME (this may take 10-15 minutes)..."
        
        az aks delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$CLUSTER_NAME" \
            --yes \
            --output none
    else
        log INFO "AKS cluster $CLUSTER_NAME not found, skipping"
    fi
    
    log INFO "AKS cluster deletion completed ✅"
}

delete_resource_group() {
    log INFO "Deleting resource group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log INFO "Deleting resource group: $RESOURCE_GROUP (this may take 15-20 minutes)..."
        
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            --output none
        
        log INFO "Resource group deletion initiated ✅"
        log INFO "Note: Complete deletion may take 15-20 minutes"
    else
        log INFO "Resource group $RESOURCE_GROUP not found, skipping"
    fi
}

cleanup_local_files() {
    log INFO "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would clean up local configuration files"
        return 0
    fi
    
    # Remove configuration file
    local config_file="/tmp/azure-gitops-config.env"
    if [[ -f "$config_file" ]]; then
        rm -f "$config_file"
        log INFO "Removed configuration file: $config_file"
    fi
    
    # Clean up kubectl context if it exists
    if command -v kubectl &> /dev/null; then
        kubectl config delete-context "$CLUSTER_NAME" 2>/dev/null || true
        kubectl config delete-cluster "$CLUSTER_NAME" 2>/dev/null || true
    fi
    
    log INFO "Local files cleanup completed ✅"
}

# ==============================================================================
# Main Cleanup Flow
# ==============================================================================

main() {
    local total_steps=8
    local current_step=0
    
    log INFO "Starting Azure Secure GitOps CI/CD cleanup..."
    log INFO "Log file: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "🔍 DRY RUN MODE - No resources will be deleted"
    fi
    
    # Prerequisites and configuration
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Checking prerequisites..."
    check_prerequisites
    
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Loading configuration..."
    load_configuration
    
    # Display what will be deleted
    log INFO ""
    log INFO "🗑️  Resources to be deleted:"
    log INFO "  Resource Group: $RESOURCE_GROUP"
    log INFO "  AKS Cluster: $CLUSTER_NAME"
    log INFO "  Key Vault: ${KEY_VAULT_NAME:-'(not specified)'}"
    log INFO "  Managed Identity: ${MANAGED_IDENTITY_NAME:-'(not specified)'}"
    log INFO ""
    
    # Confirmation prompt
    if [[ "$FORCE_DELETE" == "false" ]] && [[ "$DRY_RUN" == "false" ]]; then
        confirm_deletion "Azure resources" "$RESOURCE_GROUP and all contained resources"
    fi
    
    # Cleanup in reverse order of creation
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Cleaning up ArgoCD applications..."
    cleanup_argocd_applications
    
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Removing ArgoCD extension..."
    remove_argocd_extension
    
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Deleting federated credentials..."
    delete_federated_credentials
    
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Deleting managed identity..."
    delete_managed_identity
    
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Deleting Key Vault..."
    delete_key_vault
    
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Deleting AKS cluster..."
    delete_aks_cluster
    
    # Option to delete entire resource group or individual resources
    if [[ "$FORCE_DELETE" == "true" ]] || [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        delete_resource_group
    else
        log INFO ""
        echo -e "${YELLOW}Do you want to delete the entire resource group? This will remove ALL resources in the group.${NC}"
        read -p "Delete resource group $RESOURCE_GROUP? (y/N): " -n 1 -r
        echo ""
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            delete_resource_group
        else
            log INFO "Resource group $RESOURCE_GROUP preserved"
        fi
    fi
    
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Cleaning up local files..."
    cleanup_local_files
    
    # Cleanup completion
    local cleanup_end_time=$(date +%s)
    local cleanup_duration=$((cleanup_end_time - CLEANUP_START_TIME))
    
    log INFO ""
    log INFO "🎉 Cleanup completed successfully!"
    log INFO "⏱️  Total cleanup time: $((cleanup_duration / 60)) minutes and $((cleanup_duration % 60)) seconds"
    log INFO ""
    log INFO "📋 Cleanup Summary:"
    log INFO "  ✅ ArgoCD applications and extensions removed"
    log INFO "  ✅ Federated identity credentials deleted"
    log INFO "  ✅ Managed identity removed"
    log INFO "  ✅ Key Vault deleted and purged"
    log INFO "  ✅ AKS cluster deleted"
    if [[ "$FORCE_DELETE" == "true" ]] || [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        log INFO "  ✅ Resource group deletion initiated"
    fi
    log INFO "  ✅ Local configuration files cleaned up"
    log INFO ""
    log INFO "📝 Log file saved: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log INFO ""
        log INFO "💡 Note: Some Azure resources may take additional time to be fully removed."
        log INFO "   You can check the Azure portal to verify complete deletion."
    fi
}

# ==============================================================================
# Script Entry Point
# ==============================================================================

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DELETE=true
            SKIP_CONFIRMATION=true
            shift
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --key-vault-name)
            KEY_VAULT_NAME="$2"
            shift 2
            ;;
        --managed-identity-name)
            MANAGED_IDENTITY_NAME="$2"
            shift 2
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --help|-h)
            echo "Azure Secure GitOps CI/CD Cleanup Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run                          Show what would be deleted without removing resources"
            echo "  --force                            Force deletion without confirmation prompts"
            echo "  --skip-confirmation                Skip confirmation prompts but preserve safety checks"
            echo "  --resource-group RG_NAME           Resource group name (default: rg-gitops-demo)"
            echo "  --cluster-name CLUSTER_NAME        AKS cluster name (default: aks-gitops-cluster)"
            echo "  --key-vault-name KV_NAME           Key Vault name (auto-discovered if not specified)"
            echo "  --managed-identity-name MI_NAME    Managed identity name (auto-discovered if not specified)"
            echo "  --help, -h                         Show this help message"
            echo ""
            echo "Environment variables can also be used to override defaults:"
            echo "  RESOURCE_GROUP, CLUSTER_NAME, KEY_VAULT_NAME, MANAGED_IDENTITY_NAME"
            echo ""
            echo "Configuration file:"
            echo "  The script will attempt to load configuration from /tmp/azure-gitops-config.env"
            echo "  if it exists (created by the deploy.sh script)."
            echo ""
            exit 0
            ;;
        *)
            log ERROR "Unknown option: $1"
            log INFO "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Trap for cleanup on script exit
trap 'log INFO "Script interrupted. Check log file: $LOG_FILE"' INT TERM

# Run main cleanup
main

exit 0