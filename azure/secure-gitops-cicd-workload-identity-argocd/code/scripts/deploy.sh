#!/bin/bash

# ==============================================================================
# Azure Secure GitOps CI/CD Deployment Script
# Recipe: Secure GitOps CI/CD with Workload Identity and ArgoCD
# ==============================================================================

set -euo pipefail

# Configuration
SCRIPT_NAME="deploy.sh"
LOG_FILE="/tmp/azure-gitops-deploy-$(date +%Y%m%d-%H%M%S).log"
DEPLOYMENT_START_TIME=$(date +%s)

# Default values (can be overridden by environment variables)
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-gitops-demo}"
LOCATION="${LOCATION:-eastus}"
CLUSTER_NAME="${CLUSTER_NAME:-aks-gitops-cluster}"
RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
KEY_VAULT_NAME="${KEY_VAULT_NAME:-kv-gitops-${RANDOM_SUFFIX}}"
MANAGED_IDENTITY_NAME="${MANAGED_IDENTITY_NAME:-mi-argocd-${RANDOM_SUFFIX}}"
NODE_COUNT="${NODE_COUNT:-3}"
DRY_RUN="${DRY_RUN:-false}"

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

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log ERROR "Azure CLI is not installed. Please install it first."
        log INFO "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log ERROR "kubectl is not installed. Please install it first."
        log INFO "Visit: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log ERROR "openssl is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI login status
    if ! az account show &> /dev/null; then
        log ERROR "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check Azure CLI version (minimum v2.47.0)
    local az_version=$(az version --output tsv --query '"azure-cli"' 2>/dev/null || echo "0.0.0")
    local min_version="2.47.0"
    
    if [[ "$(printf '%s\n' "$min_version" "$az_version" | sort -V | head -n1)" != "$min_version" ]]; then
        log WARN "Azure CLI version $az_version detected. Version $min_version or later is recommended."
    fi
    
    log INFO "Prerequisites check completed ✅"
}

validate_subscription() {
    log INFO "Validating Azure subscription..."
    
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        log ERROR "Could not determine Azure subscription ID"
        exit 1
    fi
    
    local subscription_name=$(az account show --query name --output tsv)
    log INFO "Using subscription: $subscription_name ($SUBSCRIPTION_ID)"
    
    # Check if required resource providers are registered
    local providers=("Microsoft.ContainerService" "Microsoft.KeyVault" "Microsoft.ManagedIdentity" "Microsoft.KubernetesConfiguration")
    
    for provider in "${providers[@]}"; do
        local status=$(az provider show --namespace "$provider" --query registrationState --output tsv 2>/dev/null || echo "NotRegistered")
        
        if [[ "$status" != "Registered" ]]; then
            log INFO "Registering provider: $provider"
            if [[ "$DRY_RUN" == "false" ]]; then
                az provider register --namespace "$provider" --wait
            fi
        fi
    done
    
    log INFO "Subscription validation completed ✅"
}

# ==============================================================================
# Deployment Functions
# ==============================================================================

create_resource_group() {
    log INFO "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create resource group in $LOCATION"
        return 0
    fi
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log INFO "Resource group $RESOURCE_GROUP already exists"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=gitops-demo environment=development \
        --output none
    
    log INFO "Resource group created successfully ✅"
}

create_aks_cluster() {
    log INFO "Creating AKS cluster: $CLUSTER_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create AKS cluster with workload identity"
        return 0
    fi
    
    # Check if cluster already exists
    if az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" &> /dev/null; then
        log INFO "AKS cluster $CLUSTER_NAME already exists"
    else
        log INFO "Creating AKS cluster with workload identity (this may take 10-15 minutes)..."
        
        az aks create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$CLUSTER_NAME" \
            --node-count "$NODE_COUNT" \
            --enable-managed-identity \
            --enable-oidc-issuer \
            --enable-workload-identity \
            --generate-ssh-keys \
            --tags purpose=gitops-demo \
            --output none
    fi
    
    # Get cluster credentials
    az aks get-credentials \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --overwrite-existing \
        --output none
    
    # Get OIDC issuer URL
    export AKS_OIDC_ISSUER=$(az aks show \
        --name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "oidcIssuerProfile.issuerUrl" \
        --output tsv)
    
    if [[ -z "$AKS_OIDC_ISSUER" ]]; then
        log ERROR "Failed to get OIDC issuer URL from AKS cluster"
        exit 1
    fi
    
    log INFO "AKS cluster created successfully ✅"
    log INFO "OIDC Issuer: $AKS_OIDC_ISSUER"
}

create_key_vault() {
    log INFO "Creating Key Vault: $KEY_VAULT_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create Key Vault with RBAC authorization"
        return 0
    fi
    
    # Check if Key Vault already exists
    if az keyvault show --name "$KEY_VAULT_NAME" &> /dev/null; then
        log INFO "Key Vault $KEY_VAULT_NAME already exists"
    else
        az keyvault create \
            --name "$KEY_VAULT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --enable-rbac-authorization \
            --tags purpose=gitops-demo \
            --output none
    fi
    
    # Store sample secrets
    log INFO "Storing sample secrets in Key Vault..."
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "database-connection-string" \
        --value "Server=myserver;Database=mydb;User=myuser;Password=mypass" \
        --output none
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "api-key" \
        --value "your-secure-api-key-here" \
        --output none
    
    log INFO "Key Vault created successfully ✅"
}

create_managed_identity() {
    log INFO "Creating managed identity: $MANAGED_IDENTITY_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create user-assigned managed identity"
        return 0
    fi
    
    # Check if managed identity already exists
    if az identity show --resource-group "$RESOURCE_GROUP" --name "$MANAGED_IDENTITY_NAME" &> /dev/null; then
        log INFO "Managed identity $MANAGED_IDENTITY_NAME already exists"
    else
        az identity create \
            --name "$MANAGED_IDENTITY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=gitops-demo \
            --output none
    fi
    
    # Get managed identity details
    export USER_ASSIGNED_CLIENT_ID=$(az identity show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$MANAGED_IDENTITY_NAME" \
        --query 'clientId' \
        --output tsv)
    
    export USER_ASSIGNED_PRINCIPAL_ID=$(az identity show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$MANAGED_IDENTITY_NAME" \
        --query 'principalId' \
        --output tsv)
    
    if [[ -z "$USER_ASSIGNED_CLIENT_ID" || -z "$USER_ASSIGNED_PRINCIPAL_ID" ]]; then
        log ERROR "Failed to get managed identity details"
        exit 1
    fi
    
    log INFO "Managed identity created successfully ✅"
    log INFO "Client ID: $USER_ASSIGNED_CLIENT_ID"
}

configure_key_vault_access() {
    log INFO "Configuring Key Vault access permissions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would assign Key Vault Secrets User role"
        return 0
    fi
    
    # Wait for managed identity to propagate
    log INFO "Waiting for managed identity to propagate..."
    sleep 30
    
    # Assign Key Vault Secrets User role
    local key_vault_scope="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}"
    
    az role assignment create \
        --role "Key Vault Secrets User" \
        --assignee "$USER_ASSIGNED_PRINCIPAL_ID" \
        --scope "$key_vault_scope" \
        --output none
    
    log INFO "Key Vault access configured successfully ✅"
}

install_argocd_extension() {
    log INFO "Installing ArgoCD extension..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would install ArgoCD extension with workload identity"
        return 0
    fi
    
    # Check if extension already exists
    if az k8s-extension show --resource-group "$RESOURCE_GROUP" --cluster-name "$CLUSTER_NAME" --cluster-type managedClusters --name argocd &> /dev/null; then
        log INFO "ArgoCD extension already exists"
        return 0
    fi
    
    log INFO "Installing ArgoCD extension (this may take 5-10 minutes)..."
    
    az k8s-extension create \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-name "$CLUSTER_NAME" \
        --cluster-type managedClusters \
        --name argocd \
        --extension-type Microsoft.ArgoCD \
        --auto-upgrade false \
        --release-train preview \
        --version 0.0.7-preview \
        --config workloadIdentity.enable=true \
        --config workloadIdentity.clientId="$USER_ASSIGNED_CLIENT_ID" \
        --config deployWithHighAvailability=false \
        --config namespaceInstall=false \
        --output none
    
    # Wait for ArgoCD to be ready
    log INFO "Waiting for ArgoCD pods to be ready..."
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-application-controller -n argocd --timeout=300s
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
    
    log INFO "ArgoCD extension installed successfully ✅"
}

create_federated_credentials() {
    log INFO "Creating federated identity credentials..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create federated identity credentials"
        return 0
    fi
    
    # Delete existing credentials if they exist
    az identity federated-credential delete \
        --name "argocd-application-controller" \
        --identity-name "$MANAGED_IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --yes 2>/dev/null || true
    
    az identity federated-credential delete \
        --name "argocd-server" \
        --identity-name "$MANAGED_IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --yes 2>/dev/null || true
    
    az identity federated-credential delete \
        --name "sample-app" \
        --identity-name "$MANAGED_IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --yes 2>/dev/null || true
    
    # Create federated identity credentials
    az identity federated-credential create \
        --name "argocd-application-controller" \
        --identity-name "$MANAGED_IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --issuer "$AKS_OIDC_ISSUER" \
        --subject "system:serviceaccount:argocd:argocd-application-controller" \
        --audience api://AzureADTokenExchange \
        --output none
    
    az identity federated-credential create \
        --name "argocd-server" \
        --identity-name "$MANAGED_IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --issuer "$AKS_OIDC_ISSUER" \
        --subject "system:serviceaccount:argocd:argocd-server" \
        --audience api://AzureADTokenExchange \
        --output none
    
    az identity federated-credential create \
        --name "sample-app" \
        --identity-name "$MANAGED_IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --issuer "$AKS_OIDC_ISSUER" \
        --subject "system:serviceaccount:sample-app:sample-app-sa" \
        --audience api://AzureADTokenExchange \
        --output none
    
    log INFO "Federated identity credentials created successfully ✅"
}

configure_service_accounts() {
    log INFO "Configuring ArgoCD service accounts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would configure service accounts with workload identity"
        return 0
    fi
    
    # Annotate and label ArgoCD service accounts
    kubectl annotate serviceaccount argocd-application-controller \
        -n argocd \
        azure.workload.identity/client-id="$USER_ASSIGNED_CLIENT_ID" \
        --overwrite
    
    kubectl annotate serviceaccount argocd-server \
        -n argocd \
        azure.workload.identity/client-id="$USER_ASSIGNED_CLIENT_ID" \
        --overwrite
    
    kubectl label serviceaccount argocd-application-controller \
        -n argocd \
        azure.workload.identity/use=true \
        --overwrite
    
    kubectl label serviceaccount argocd-server \
        -n argocd \
        azure.workload.identity/use=true \
        --overwrite
    
    log INFO "ArgoCD service accounts configured successfully ✅"
}

setup_sample_application() {
    log INFO "Setting up sample application..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would setup sample application with Key Vault integration"
        return 0
    fi
    
    # Enable Azure Key Vault Provider for Secrets Store CSI Driver
    az aks enable-addons \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --addons azure-keyvault-secrets-provider \
        --output none
    
    # Create namespace and service account for sample application
    kubectl create namespace sample-app --dry-run=client -o yaml | kubectl apply -f -
    kubectl create serviceaccount sample-app-sa -n sample-app --dry-run=client -o yaml | kubectl apply -f -
    
    # Configure service account with workload identity
    kubectl annotate serviceaccount sample-app-sa \
        -n sample-app \
        azure.workload.identity/client-id="$USER_ASSIGNED_CLIENT_ID" \
        --overwrite
    
    kubectl label serviceaccount sample-app-sa \
        -n sample-app \
        azure.workload.identity/use=true \
        --overwrite
    
    log INFO "Sample application setup completed successfully ✅"
}

deploy_sample_resources() {
    log INFO "Deploying sample application resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would deploy SecretProviderClass and sample application"
        return 0
    fi
    
    local tenant_id=$(az account show --query tenantId --output tsv)
    
    # Create SecretProviderClass
    cat <<EOF | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: sample-app-secrets
  namespace: sample-app
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "false"
    userAssignedIdentityID: $USER_ASSIGNED_CLIENT_ID
    keyvaultName: $KEY_VAULT_NAME
    tenantId: $tenant_id
    objects: |
      array:
        - |
          objectName: database-connection-string
          objectType: secret
          objectVersion: ""
        - |
          objectName: api-key
          objectType: secret
          objectVersion: ""
EOF
    
    # Create sample application deployment
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  namespace: sample-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: sample-app-sa
      containers:
      - name: sample-app
        image: nginx:latest
        ports:
        - containerPort: 80
        volumeMounts:
        - name: secrets-store
          mountPath: "/mnt/secrets"
          readOnly: true
        env:
        - name: DATABASE_CONNECTION_STRING
          valueFrom:
            secretKeyRef:
              name: sample-app-secrets
              key: database-connection-string
      volumes:
      - name: secrets-store
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: sample-app-secrets
EOF
    
    # Wait for deployment to be ready
    kubectl wait --for=condition=Available deployment/sample-app -n sample-app --timeout=300s
    
    log INFO "Sample application deployed successfully ✅"
}

create_argocd_application() {
    log INFO "Creating ArgoCD application..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create ArgoCD application for GitOps deployment"
        return 0
    fi
    
    # Create ArgoCD application
    cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-app-gitops
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Azure-Samples/aks-store-demo.git
    targetRevision: HEAD
    path: kustomize/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: sample-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
    
    # Wait for ArgoCD to sync the application
    log INFO "Waiting for ArgoCD to sync the application..."
    kubectl wait --for=condition=Synced application/sample-app-gitops -n argocd --timeout=300s || log WARN "ArgoCD sync may still be in progress"
    
    log INFO "ArgoCD application created successfully ✅"
}

# ==============================================================================
# Main Deployment Flow
# ==============================================================================

main() {
    local total_steps=11
    local current_step=0
    
    log INFO "Starting Azure Secure GitOps CI/CD deployment..."
    log INFO "Log file: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "🔍 DRY RUN MODE - No resources will be created"
    fi
    
    # Display configuration
    log INFO "Configuration:"
    log INFO "  Resource Group: $RESOURCE_GROUP"
    log INFO "  Location: $LOCATION"
    log INFO "  Cluster Name: $CLUSTER_NAME"
    log INFO "  Key Vault Name: $KEY_VAULT_NAME"
    log INFO "  Managed Identity: $MANAGED_IDENTITY_NAME"
    log INFO "  Node Count: $NODE_COUNT"
    
    # Prerequisites and validation
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Checking prerequisites..."
    check_prerequisites
    
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Validating subscription..."
    validate_subscription
    
    # Core resource creation
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Creating resource group..."
    create_resource_group
    
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Creating AKS cluster..."
    create_aks_cluster
    
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Creating Key Vault..."
    create_key_vault
    
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Creating managed identity..."
    create_managed_identity
    
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Configuring Key Vault access..."
    configure_key_vault_access
    
    # ArgoCD and workload identity setup
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Installing ArgoCD extension..."
    install_argocd_extension
    
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Creating federated credentials..."
    create_federated_credentials
    
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Configuring service accounts..."
    configure_service_accounts
    
    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "Setting up sample application..."
    setup_sample_application
    deploy_sample_resources
    create_argocd_application
    
    # Deployment completion
    local deployment_end_time=$(date +%s)
    local deployment_duration=$((deployment_end_time - DEPLOYMENT_START_TIME))
    
    log INFO ""
    log INFO "🎉 Deployment completed successfully!"
    log INFO "⏱️  Total deployment time: $((deployment_duration / 60)) minutes and $((deployment_duration % 60)) seconds"
    log INFO ""
    log INFO "📋 Deployment Summary:"
    log INFO "  ✅ Resource Group: $RESOURCE_GROUP"
    log INFO "  ✅ AKS Cluster: $CLUSTER_NAME"
    log INFO "  ✅ Key Vault: $KEY_VAULT_NAME"
    log INFO "  ✅ Managed Identity: $MANAGED_IDENTITY_NAME"
    log INFO "  ✅ ArgoCD Extension: Installed with workload identity"
    log INFO "  ✅ Sample Application: Deployed with Key Vault integration"
    log INFO ""
    log INFO "🔗 Next Steps:"
    log INFO "  1. Access ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:80"
    log INFO "  2. Get ArgoCD admin password: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
    log INFO "  3. Validate workload identity: kubectl exec -it deployment/sample-app -n sample-app -- ls -la /mnt/secrets"
    log INFO ""
    log INFO "📝 Log file saved: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Save deployment configuration
        cat > "/tmp/azure-gitops-config.env" <<EOF
# Azure GitOps Deployment Configuration
# Generated on $(date)
export RESOURCE_GROUP="$RESOURCE_GROUP"
export LOCATION="$LOCATION"
export CLUSTER_NAME="$CLUSTER_NAME"
export SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
export KEY_VAULT_NAME="$KEY_VAULT_NAME"
export MANAGED_IDENTITY_NAME="$MANAGED_IDENTITY_NAME"
export USER_ASSIGNED_CLIENT_ID="$USER_ASSIGNED_CLIENT_ID"
export AKS_OIDC_ISSUER="$AKS_OIDC_ISSUER"
EOF
        log INFO "💾 Configuration saved to: /tmp/azure-gitops-config.env"
        log INFO "   Source this file before running destroy.sh: source /tmp/azure-gitops-config.env"
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
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --location)
            LOCATION="$2"
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
        --node-count)
            NODE_COUNT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Azure Secure GitOps CI/CD Deployment Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run                    Show what would be deployed without creating resources"
            echo "  --resource-group RG_NAME     Resource group name (default: rg-gitops-demo)"
            echo "  --location LOCATION          Azure region (default: eastus)"
            echo "  --cluster-name CLUSTER_NAME  AKS cluster name (default: aks-gitops-cluster)"
            echo "  --key-vault-name KV_NAME     Key Vault name (default: auto-generated)"
            echo "  --node-count COUNT           AKS node count (default: 3)"
            echo "  --help, -h                   Show this help message"
            echo ""
            echo "Environment variables can also be used to override defaults:"
            echo "  RESOURCE_GROUP, LOCATION, CLUSTER_NAME, KEY_VAULT_NAME, NODE_COUNT"
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

# Run main deployment
main

exit 0