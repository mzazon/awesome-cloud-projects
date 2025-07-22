#!/bin/bash

# =============================================================================
# Azure Workload Identity and Container Storage Deployment Script
# =============================================================================
# 
# This script deploys Azure Kubernetes Service with Workload Identity and
# Azure Container Storage for secure ephemeral workload storage.
#
# Prerequisites:
# - Azure CLI v2.47.0 or later
# - kubectl command-line tool
# - Helm v3.0+
# - Appropriate Azure permissions
#
# Usage: ./deploy.sh [--debug] [--dry-run]
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Default values
DEBUG=${DEBUG:-false}
DRY_RUN=${DRY_RUN:-false}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--debug] [--dry-run]"
            echo "  --debug    Enable debug logging"
            echo "  --dry-run  Show what would be deployed without making changes"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
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

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check $LOG_FILE for details."
    exit 1
}

# Cleanup on script exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script exited with error code $exit_code"
        log "Deployment may be incomplete. Run destroy.sh to clean up resources."
    fi
}
trap cleanup EXIT

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check required commands
    local required_commands=("az" "kubectl" "helm" "openssl")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            error_exit "Required command '$cmd' not found. Please install it first."
        fi
        log_debug "Found required command: $cmd"
    done
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log_debug "Azure CLI version: $az_version"
    
    # Verify Azure CLI login
    if ! az account show >/dev/null 2>&1; then
        error_exit "Not logged into Azure CLI. Please run 'az login' first."
    fi
    
    # Check kubectl availability
    if ! kubectl version --client >/dev/null 2>&1; then
        error_exit "kubectl is not properly configured or accessible."
    fi
    
    log_success "Prerequisites validation completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Export environment variables
    export RESOURCE_GROUP="rg-workload-identity-${RANDOM_SUFFIX}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export AKS_CLUSTER_NAME="aks-workload-identity-${RANDOM_SUFFIX}"
    export KEY_VAULT_NAME="kv-workload-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="stworkload${RANDOM_SUFFIX}"
    export IDENTITY_NAME="workload-identity-${RANDOM_SUFFIX}"
    export NAMESPACE="workload-identity-demo"
    export SERVICE_ACCOUNT_NAME="workload-identity-sa"
    
    # Log environment variables
    log_debug "RESOURCE_GROUP: $RESOURCE_GROUP"
    log_debug "LOCATION: $LOCATION"
    log_debug "SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
    log_debug "AKS_CLUSTER_NAME: $AKS_CLUSTER_NAME"
    log_debug "KEY_VAULT_NAME: $KEY_VAULT_NAME"
    log_debug "IDENTITY_NAME: $IDENTITY_NAME"
    
    # Save environment to file for cleanup script
    cat > "${SCRIPT_DIR}/.env" <<EOF
RESOURCE_GROUP="$RESOURCE_GROUP"
LOCATION="$LOCATION"
SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
AKS_CLUSTER_NAME="$AKS_CLUSTER_NAME"
KEY_VAULT_NAME="$KEY_VAULT_NAME"
STORAGE_ACCOUNT_NAME="$STORAGE_ACCOUNT_NAME"
IDENTITY_NAME="$IDENTITY_NAME"
NAMESPACE="$NAMESPACE"
SERVICE_ACCOUNT_NAME="$SERVICE_ACCOUNT_NAME"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
EOF
    
    log_success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create resource group $RESOURCE_GROUP in $LOCATION"
        return 0
    fi
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=workload-identity-demo environment=test \
            --output none
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to register Azure providers
register_providers() {
    log "Registering required Azure providers..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would register Azure providers"
        return 0
    fi
    
    local providers=("Microsoft.ContainerService" "Microsoft.Storage" "Microsoft.KeyVault")
    
    for provider in "${providers[@]}"; do
        log_debug "Registering provider: $provider"
        az provider register --namespace "$provider" --output none
    done
    
    # Install required Azure CLI extensions
    log "Installing Azure CLI extensions..."
    az extension add --name aks-preview --upgrade --yes >/dev/null 2>&1 || true
    az extension add --name k8s-extension --upgrade --yes >/dev/null 2>&1 || true
    
    log_success "Azure providers registered and extensions installed"
}

# Function to create AKS cluster
create_aks_cluster() {
    log "Creating AKS cluster with Workload Identity: $AKS_CLUSTER_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create AKS cluster $AKS_CLUSTER_NAME"
        return 0
    fi
    
    # Check if cluster already exists
    if az aks show --name "$AKS_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "AKS cluster $AKS_CLUSTER_NAME already exists"
    else
        az aks create \
            --name "$AKS_CLUSTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --node-count 3 \
            --node-vm-size Standard_D2s_v3 \
            --enable-oidc-issuer \
            --enable-workload-identity \
            --enable-managed-identity \
            --generate-ssh-keys \
            --tags purpose=workload-identity-demo \
            --output none
        
        log_success "AKS cluster created: $AKS_CLUSTER_NAME"
    fi
    
    # Get cluster credentials
    log "Getting AKS cluster credentials..."
    az aks get-credentials \
        --name "$AKS_CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --overwrite-existing \
        --output none
    
    # Get OIDC issuer URL
    export OIDC_ISSUER
    OIDC_ISSUER=$(az aks show \
        --name "$AKS_CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "oidcIssuerProfile.issuerUrl" \
        --output tsv)
    
    log_debug "OIDC issuer URL: $OIDC_ISSUER"
    echo "OIDC_ISSUER=\"$OIDC_ISSUER\"" >> "${SCRIPT_DIR}/.env"
    
    log_success "AKS cluster configuration completed"
}

# Function to install Azure Container Storage
install_container_storage() {
    log "Installing Azure Container Storage extension..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would install Azure Container Storage extension"
        return 0
    fi
    
    # Check if extension already exists
    if az k8s-extension show \
        --cluster-name "$AKS_CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-type managedClusters \
        --name azure-container-storage >/dev/null 2>&1; then
        log "Azure Container Storage extension already exists"
    else
        az k8s-extension create \
            --cluster-name "$AKS_CLUSTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --cluster-type managedClusters \
            --extension-type microsoft.azurecontainerstorage \
            --name azure-container-storage \
            --release-namespace acstor \
            --auto-upgrade false \
            --output none
        
        # Wait for extension installation
        log "Waiting for Azure Container Storage extension installation..."
        az k8s-extension wait \
            --cluster-name "$AKS_CLUSTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --cluster-type managedClusters \
            --name azure-container-storage \
            --created \
            --timeout 600
    fi
    
    # Verify extension installation
    kubectl wait --for=condition=Ready pods -n acstor --all --timeout=300s
    
    log_success "Azure Container Storage extension installed successfully"
}

# Function to create Key Vault
create_key_vault() {
    log "Creating Azure Key Vault: $KEY_VAULT_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create Key Vault $KEY_VAULT_NAME"
        return 0
    fi
    
    # Check if Key Vault already exists
    if az keyvault show --name "$KEY_VAULT_NAME" >/dev/null 2>&1; then
        log "Key Vault $KEY_VAULT_NAME already exists"
    else
        az keyvault create \
            --name "$KEY_VAULT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --enable-rbac-authorization \
            --sku standard \
            --tags purpose=workload-identity-demo \
            --output none
        
        log_success "Key Vault created: $KEY_VAULT_NAME"
    fi
    
    # Create sample secret
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "storage-encryption-key" \
        --value "demo-encryption-key-value" \
        --output none >/dev/null 2>&1 || true
    
    # Get Key Vault resource ID
    export KEY_VAULT_ID
    KEY_VAULT_ID=$(az keyvault show \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id \
        --output tsv)
    
    echo "KEY_VAULT_ID=\"$KEY_VAULT_ID\"" >> "${SCRIPT_DIR}/.env"
    
    log_success "Key Vault configuration completed"
}

# Function to create managed identity
create_managed_identity() {
    log "Creating user-assigned managed identity: $IDENTITY_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create managed identity $IDENTITY_NAME"
        return 0
    fi
    
    # Check if identity already exists
    if az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "Managed identity $IDENTITY_NAME already exists"
    else
        az identity create \
            --name "$IDENTITY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=workload-identity-demo \
            --output none
        
        log_success "Managed identity created: $IDENTITY_NAME"
    fi
    
    # Get identity details
    export IDENTITY_CLIENT_ID
    IDENTITY_CLIENT_ID=$(az identity show \
        --name "$IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query clientId \
        --output tsv)
    
    export IDENTITY_OBJECT_ID
    IDENTITY_OBJECT_ID=$(az identity show \
        --name "$IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId \
        --output tsv)
    
    echo "IDENTITY_CLIENT_ID=\"$IDENTITY_CLIENT_ID\"" >> "${SCRIPT_DIR}/.env"
    echo "IDENTITY_OBJECT_ID=\"$IDENTITY_OBJECT_ID\"" >> "${SCRIPT_DIR}/.env"
    
    log_debug "Identity Client ID: $IDENTITY_CLIENT_ID"
    log_debug "Identity Object ID: $IDENTITY_OBJECT_ID"
    
    log_success "Managed identity configuration completed"
}

# Function to create storage pool
create_storage_pool() {
    log "Creating storage pool for ephemeral workloads..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create storage pool and storage class"
        return 0
    fi
    
    # Create storage pool
    kubectl apply -f - <<EOF
apiVersion: containerstorage.azure.com/v1
kind: StoragePool
metadata:
  name: ephemeral-pool
  namespace: acstor
spec:
  poolType:
    ephemeralDisk:
      diskType: temp
      diskSize: 100Gi
  nodePoolName: nodepool1
  reclaimPolicy: Delete
EOF
    
    # Wait for storage pool to be ready
    kubectl wait --for=condition=Ready storagepool/ephemeral-pool -n acstor --timeout=300s
    
    # Create storage class
    kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ephemeral-storage
provisioner: containerstorage.csi.azure.com
parameters:
  protocol: "nfs"
  storagePool: "ephemeral-pool"
  server: "ephemeral-pool.acstor.svc.cluster.local"
volumeBindingMode: Immediate
reclaimPolicy: Delete
EOF
    
    log_success "Storage pool and storage class created"
}

# Function to create Kubernetes resources
create_kubernetes_resources() {
    log "Creating Kubernetes service account and namespace..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create Kubernetes resources"
        return 0
    fi
    
    # Create namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create service account with workload identity
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $SERVICE_ACCOUNT_NAME
  namespace: $NAMESPACE
  annotations:
    azure.workload.identity/client-id: $IDENTITY_CLIENT_ID
  labels:
    azure.workload.identity/use: "true"
EOF
    
    log_success "Kubernetes resources created"
}

# Function to configure federated credentials
configure_federated_credentials() {
    log "Configuring federated credentials..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would configure federated credentials"
        return 0
    fi
    
    # Check if federated credential already exists
    if az identity federated-credential show \
        --name "workload-identity-federation" \
        --identity-name "$IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "Federated credential already exists"
    else
        az identity federated-credential create \
            --name "workload-identity-federation" \
            --identity-name "$IDENTITY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --issuer "$OIDC_ISSUER" \
            --subject "system:serviceaccount:$NAMESPACE:$SERVICE_ACCOUNT_NAME" \
            --audience api://AzureADTokenExchange \
            --output none
        
        log_success "Federated credential created"
    fi
}

# Function to grant Key Vault access
grant_key_vault_access() {
    log "Granting Key Vault access to managed identity..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would grant Key Vault access"
        return 0
    fi
    
    # Grant Key Vault Secrets User role
    az role assignment create \
        --role "Key Vault Secrets User" \
        --assignee "$IDENTITY_OBJECT_ID" \
        --scope "$KEY_VAULT_ID" \
        --output none >/dev/null 2>&1 || true
    
    log_success "Key Vault access granted to managed identity"
}

# Function to deploy test workload
deploy_test_workload() {
    log "Deploying test workload with ephemeral storage..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would deploy test workload"
        return 0
    fi
    
    # Deploy test workload
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-identity-test
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: workload-identity-test
  template:
    metadata:
      labels:
        app: workload-identity-test
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: $SERVICE_ACCOUNT_NAME
      containers:
      - name: test-container
        image: mcr.microsoft.com/azure-cli:latest
        command: ["/bin/bash"]
        args:
        - -c
        - |
          echo "Installing Azure Identity SDK..."
          pip install azure-identity azure-keyvault-secrets
          echo "Starting workload identity test..."
          while true; do
            echo "Testing Key Vault access with workload identity..."
            python3 -c "
          from azure.identity import DefaultAzureCredential
          from azure.keyvault.secrets import SecretClient
          import os
          
          # Use workload identity for authentication
          credential = DefaultAzureCredential()
          vault_url = 'https://$KEY_VAULT_NAME.vault.azure.net/'
          client = SecretClient(vault_url=vault_url, credential=credential)
          
          try:
              secret = client.get_secret('storage-encryption-key')
              print(f'Successfully retrieved secret: {secret.name}')
              
              # Test ephemeral storage access
              with open('/ephemeral-storage/test-file.txt', 'w') as f:
                  f.write('Workload identity test successful!')
              
              with open('/ephemeral-storage/test-file.txt', 'r') as f:
                  content = f.read()
              print(f'Ephemeral storage test: {content}')
              
          except Exception as e:
              print(f'Error: {e}')
            "
            echo "Test completed. Sleeping for 30 seconds..."
            sleep 30
          done
        volumeMounts:
        - name: ephemeral-storage
          mountPath: /ephemeral-storage
        env:
        - name: AZURE_CLIENT_ID
          value: $IDENTITY_CLIENT_ID
      volumes:
      - name: ephemeral-storage
        persistentVolumeClaim:
          claimName: ephemeral-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ephemeral-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
  storageClassName: ephemeral-storage
EOF
    
    log_success "Test workload deployed"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would validate deployment"
        return 0
    fi
    
    # Wait for pod to be ready
    log "Waiting for test pod to be ready..."
    kubectl wait --for=condition=Ready pod -l app=workload-identity-test -n "$NAMESPACE" --timeout=300s
    
    # Check pod logs for successful authentication
    log "Checking workload identity authentication..."
    sleep 30  # Allow time for initial authentication attempt
    
    local logs
    logs=$(kubectl logs -n "$NAMESPACE" -l app=workload-identity-test --tail=50 | grep -E "(Successfully retrieved secret|Workload identity test successful)" || true)
    
    if [[ -n "$logs" ]]; then
        log_success "Workload identity authentication validated"
        log_debug "Authentication logs: $logs"
    else
        log_error "Workload identity authentication may have failed. Check pod logs manually."
    fi
    
    # Verify storage pool status
    log "Checking storage pool status..."
    kubectl get storagepool -n acstor ephemeral-pool -o yaml | grep -A 5 "status:" || true
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "=== Deployment Summary ==="
    log "Resource Group: $RESOURCE_GROUP"
    log "AKS Cluster: $AKS_CLUSTER_NAME"
    log "Key Vault: $KEY_VAULT_NAME"
    log "Managed Identity: $IDENTITY_NAME"
    log "Namespace: $NAMESPACE"
    log "Service Account: $SERVICE_ACCOUNT_NAME"
    echo ""
    log "To view test workload logs:"
    log "kubectl logs -n $NAMESPACE -l app=workload-identity-test --follow"
    echo ""
    log "To check storage pool status:"
    log "kubectl get storagepool -n acstor"
    echo ""
    log "Environment variables saved to: ${SCRIPT_DIR}/.env"
    log "For cleanup, run: ./destroy.sh"
    echo ""
    log_success "Deployment completed successfully!"
}

# Main execution function
main() {
    log "=== Starting Azure Workload Identity and Container Storage Deployment ==="
    log "Timestamp: $TIMESTAMP"
    log "Log file: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Running in DRY RUN mode - no resources will be created"
    fi
    
    validate_prerequisites
    setup_environment
    create_resource_group
    register_providers
    create_aks_cluster
    install_container_storage
    create_key_vault
    create_managed_identity
    create_storage_pool
    create_kubernetes_resources
    configure_federated_credentials
    grant_key_vault_access
    deploy_test_workload
    
    if [[ "$DRY_RUN" != "true" ]]; then
        validate_deployment
    fi
    
    display_summary
}

# Execute main function
main "$@"