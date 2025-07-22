#!/bin/bash

# Multi-Cluster Kubernetes Fleet Management with GitOps
# Deployment Script - Automates the complete infrastructure deployment

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

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

# Wait for resource with timeout
wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    local timeout="${4:-1800}"  # 30 minutes default
    local interval="${5:-30}"   # 30 seconds default
    
    info "Waiting for ${resource_type} ${resource_name} to be ready..."
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        case $resource_type in
            "fleet")
                local state=$(az fleet show --resource-group "$resource_group" --name "$resource_name" --query provisioningState -o tsv 2>/dev/null || echo "NotFound")
                ;;
            "aks")
                local state=$(az aks show --resource-group "$resource_group" --name "$resource_name" --query provisioningState -o tsv 2>/dev/null || echo "NotFound")
                ;;
            "acr")
                local state=$(az acr show --name "$resource_name" --query provisioningState -o tsv 2>/dev/null || echo "NotFound")
                ;;
            "keyvault")
                local state=$(az keyvault show --name "$resource_name" --query provisioningState -o tsv 2>/dev/null || echo "NotFound")
                ;;
            *)
                error_exit "Unknown resource type: $resource_type"
                ;;
        esac
        
        if [ "$state" = "Succeeded" ]; then
            success "${resource_type} ${resource_name} is ready"
            return 0
        elif [ "$state" = "Failed" ]; then
            error_exit "${resource_type} ${resource_name} deployment failed"
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    error_exit "Timeout waiting for ${resource_type} ${resource_name} to be ready"
}

# Save deployment state
save_deployment_state() {
    local key="$1"
    local value="$2"
    
    if [ ! -f "$DEPLOYMENT_STATE_FILE" ]; then
        echo "{}" > "$DEPLOYMENT_STATE_FILE"
    fi
    
    # Use jq to update the state file
    jq --arg key "$key" --arg value "$value" '.[$key] = $value' "$DEPLOYMENT_STATE_FILE" > "${DEPLOYMENT_STATE_FILE}.tmp" && \
        mv "${DEPLOYMENT_STATE_FILE}.tmp" "$DEPLOYMENT_STATE_FILE"
}

# Get deployment state
get_deployment_state() {
    local key="$1"
    local default="${2:-}"
    
    if [ ! -f "$DEPLOYMENT_STATE_FILE" ]; then
        echo "$default"
        return
    fi
    
    jq -r --arg key "$key" '.[$key] // empty' "$DEPLOYMENT_STATE_FILE" | grep -v "^$" || echo "$default"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check required commands
    local required_commands=("az" "kubectl" "helm" "jq" "openssl")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            error_exit "Required command '$cmd' is not installed"
        fi
    done
    
    # Check Azure CLI login
    if ! az account show >/dev/null 2>&1; then
        error_exit "Azure CLI not logged in. Please run 'az login'"
    fi
    
    # Check kubectl version
    local kubectl_version=$(kubectl version --client -o yaml | grep gitVersion | cut -d'"' -f2)
    info "kubectl version: $kubectl_version"
    
    # Check Helm version
    local helm_version=$(helm version --template='{{.Version}}')
    info "Helm version: $helm_version"
    
    success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-fleet-demo}"
    export LOCATION="${LOCATION:-eastus}"
    export FLEET_NAME="${FLEET_NAME:-multicluster-fleet}"
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    
    # Generate unique suffixes for global resources
    local existing_suffix=$(get_deployment_state "RANDOM_SUFFIX")
    if [ -n "$existing_suffix" ]; then
        export RANDOM_SUFFIX="$existing_suffix"
        info "Using existing random suffix: $RANDOM_SUFFIX"
    else
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
        save_deployment_state "RANDOM_SUFFIX" "$RANDOM_SUFFIX"
        info "Generated new random suffix: $RANDOM_SUFFIX"
    fi
    
    export ACR_NAME="acrfleet${RANDOM_SUFFIX}"
    export KV_NAME="kv-fleet-${RANDOM_SUFFIX}"
    export ASO_SP_NAME="sp-aso-fleet-${RANDOM_SUFFIX}"
    
    # Define regions for multi-region deployment
    export REGIONS=("eastus" "westus2" "centralus")
    
    info "Environment variables configured:"
    info "  RESOURCE_GROUP: $RESOURCE_GROUP"
    info "  LOCATION: $LOCATION"
    info "  FLEET_NAME: $FLEET_NAME"
    info "  SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
    info "  RANDOM_SUFFIX: $RANDOM_SUFFIX"
    info "  ACR_NAME: $ACR_NAME"
    info "  KV_NAME: $KV_NAME"
    info "  ASO_SP_NAME: $ASO_SP_NAME"
    
    # Save environment variables to state
    save_deployment_state "RESOURCE_GROUP" "$RESOURCE_GROUP"
    save_deployment_state "LOCATION" "$LOCATION"
    save_deployment_state "FLEET_NAME" "$FLEET_NAME"
    save_deployment_state "SUBSCRIPTION_ID" "$SUBSCRIPTION_ID"
    save_deployment_state "ACR_NAME" "$ACR_NAME"
    save_deployment_state "KV_NAME" "$KV_NAME"
    save_deployment_state "ASO_SP_NAME" "$ASO_SP_NAME"
    
    success "Environment setup completed"
}

# Create resource group
create_resource_group() {
    local existing_rg=$(get_deployment_state "RESOURCE_GROUP_CREATED")
    if [ "$existing_rg" = "true" ]; then
        info "Resource group already exists, skipping creation"
        return
    fi
    
    info "Creating resource group: $RESOURCE_GROUP"
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=fleet-demo environment=demo || \
        error_exit "Failed to create resource group"
    
    save_deployment_state "RESOURCE_GROUP_CREATED" "true"
    success "Resource group created: $RESOURCE_GROUP"
}

# Create service principal for Azure Service Operator
create_service_principal() {
    local existing_sp=$(get_deployment_state "SERVICE_PRINCIPAL_CREATED")
    if [ "$existing_sp" = "true" ]; then
        info "Service principal already exists, retrieving credentials"
        export ASO_CLIENT_ID=$(get_deployment_state "ASO_CLIENT_ID")
        export ASO_CLIENT_SECRET=$(get_deployment_state "ASO_CLIENT_SECRET")
        export ASO_TENANT_ID=$(get_deployment_state "ASO_TENANT_ID")
        return
    fi
    
    info "Creating Service Principal for Azure Service Operator: $ASO_SP_NAME"
    
    # Check if service principal already exists
    local existing_sp_id=$(az ad sp list --display-name "$ASO_SP_NAME" --query "[0].appId" -o tsv)
    if [ -n "$existing_sp_id" ] && [ "$existing_sp_id" != "null" ]; then
        warn "Service principal already exists, cleaning up before creating new one"
        az ad sp delete --id "$existing_sp_id" || warn "Failed to delete existing service principal"
    fi
    
    local sp_json=$(az ad sp create-for-rbac \
        --name "$ASO_SP_NAME" \
        --role contributor \
        --scopes "/subscriptions/$SUBSCRIPTION_ID" \
        --output json) || error_exit "Failed to create service principal"
    
    export ASO_CLIENT_ID=$(echo "$sp_json" | jq -r .appId)
    export ASO_CLIENT_SECRET=$(echo "$sp_json" | jq -r .password)
    export ASO_TENANT_ID=$(echo "$sp_json" | jq -r .tenant)
    
    # Save credentials to state
    save_deployment_state "ASO_CLIENT_ID" "$ASO_CLIENT_ID"
    save_deployment_state "ASO_CLIENT_SECRET" "$ASO_CLIENT_SECRET"
    save_deployment_state "ASO_TENANT_ID" "$ASO_TENANT_ID"
    save_deployment_state "SERVICE_PRINCIPAL_CREATED" "true"
    
    success "Service Principal created for Azure Service Operator"
}

# Create Azure Kubernetes Fleet Manager
create_fleet_manager() {
    local existing_fleet=$(get_deployment_state "FLEET_MANAGER_CREATED")
    if [ "$existing_fleet" = "true" ]; then
        info "Fleet Manager already exists, skipping creation"
        return
    fi
    
    info "Creating Azure Kubernetes Fleet Manager: $FLEET_NAME"
    
    az fleet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FLEET_NAME" \
        --location "$LOCATION" || \
        error_exit "Failed to create Fleet Manager"
    
    wait_for_resource "fleet" "$FLEET_NAME" "$RESOURCE_GROUP"
    
    save_deployment_state "FLEET_MANAGER_CREATED" "true"
    success "Fleet Manager created successfully"
}

# Create AKS clusters
create_aks_clusters() {
    local existing_clusters=$(get_deployment_state "AKS_CLUSTERS_CREATED")
    if [ "$existing_clusters" = "true" ]; then
        info "AKS clusters already exist, skipping creation"
        return
    fi
    
    info "Creating AKS clusters across regions..."
    
    for i in ${!REGIONS[@]}; do
        local cluster_name="aks-fleet-$((i+1))"
        local region="${REGIONS[$i]}"
        
        info "Creating AKS cluster $cluster_name in $region..."
        
        az aks create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$cluster_name" \
            --location "$region" \
            --node-count 2 \
            --node-vm-size Standard_DS2_v2 \
            --enable-managed-identity \
            --network-plugin azure \
            --network-policy azure \
            --generate-ssh-keys \
            --tags fleet=demo region="$region" \
            --no-wait || \
            error_exit "Failed to create AKS cluster $cluster_name"
        
        save_deployment_state "CLUSTER_${i}_NAME" "$cluster_name"
        save_deployment_state "CLUSTER_${i}_REGION" "$region"
    done
    
    # Wait for all clusters to be ready
    for i in ${!REGIONS[@]}; do
        local cluster_name="aks-fleet-$((i+1))"
        wait_for_resource "aks" "$cluster_name" "$RESOURCE_GROUP"
    done
    
    save_deployment_state "AKS_CLUSTERS_CREATED" "true"
    success "All AKS clusters created successfully"
}

# Join clusters to fleet
join_clusters_to_fleet() {
    local existing_members=$(get_deployment_state "FLEET_MEMBERS_JOINED")
    if [ "$existing_members" = "true" ]; then
        info "Clusters already joined to fleet, skipping"
        return
    fi
    
    info "Joining AKS clusters to Fleet Manager..."
    
    for i in ${!REGIONS[@]}; do
        local cluster_name="aks-fleet-$((i+1))"
        local member_name="member-$((i+1))"
        
        info "Joining $cluster_name to fleet as $member_name..."
        
        # Get AKS cluster resource ID
        local aks_id=$(az aks show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$cluster_name" \
            --query id -o tsv) || \
            error_exit "Failed to get AKS cluster ID for $cluster_name"
        
        # Create fleet member
        az fleet member create \
            --resource-group "$RESOURCE_GROUP" \
            --fleet-name "$FLEET_NAME" \
            --name "$member_name" \
            --member-cluster-id "$aks_id" || \
            error_exit "Failed to join $cluster_name to fleet"
        
        save_deployment_state "MEMBER_${i}_NAME" "$member_name"
        success "$cluster_name joined as $member_name"
    done
    
    save_deployment_state "FLEET_MEMBERS_JOINED" "true"
    success "All clusters joined to fleet successfully"
}

# Install Azure Service Operator
install_azure_service_operator() {
    local existing_aso=$(get_deployment_state "ASO_INSTALLED")
    if [ "$existing_aso" = "true" ]; then
        info "Azure Service Operator already installed, skipping"
        return
    fi
    
    info "Installing Azure Service Operator on all clusters..."
    
    # Install cert-manager first
    for i in ${!REGIONS[@]}; do
        local cluster_name="aks-fleet-$((i+1))"
        
        info "Installing cert-manager on $cluster_name..."
        
        # Get cluster credentials
        az aks get-credentials \
            --resource-group "$RESOURCE_GROUP" \
            --name "$cluster_name" \
            --overwrite-existing || \
            error_exit "Failed to get credentials for $cluster_name"
        
        # Install cert-manager
        kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.14.1/cert-manager.yaml || \
            error_exit "Failed to install cert-manager on $cluster_name"
        
        # Wait for cert-manager to be ready
        kubectl wait --for=condition=ready pod \
            --all -n cert-manager \
            --timeout=300s || \
            error_exit "cert-manager pods not ready on $cluster_name"
        
        success "cert-manager installed on $cluster_name"
    done
    
    # Install Azure Service Operator
    for i in ${!REGIONS[@]}; do
        local cluster_name="aks-fleet-$((i+1))"
        
        info "Installing Azure Service Operator on $cluster_name..."
        
        # Switch context
        kubectl config use-context "$cluster_name" || \
            error_exit "Failed to switch context to $cluster_name"
        
        # Add ASO Helm repository
        helm repo add aso2 https://raw.githubusercontent.com/Azure/azure-service-operator/main/v2/charts || \
            error_exit "Failed to add ASO Helm repository"
        
        helm repo update || \
            error_exit "Failed to update Helm repositories"
        
        # Install ASO with specific CRDs
        helm upgrade --install aso2 aso2/azure-service-operator \
            --create-namespace \
            --namespace=azureserviceoperator-system \
            --set azureSubscriptionID="$SUBSCRIPTION_ID" \
            --set azureTenantID="$ASO_TENANT_ID" \
            --set azureClientID="$ASO_CLIENT_ID" \
            --set azureClientSecret="$ASO_CLIENT_SECRET" \
            --set crdPattern='resources.azure.com/*;containerservice.azure.com/*;keyvault.azure.com/*;containerregistry.azure.com/*;storage.azure.com/*' \
            --timeout=600s || \
            error_exit "Failed to install ASO on $cluster_name"
        
        success "ASO installed on $cluster_name"
    done
    
    save_deployment_state "ASO_INSTALLED" "true"
    success "Azure Service Operator installed on all clusters"
}

# Deploy Azure resources via ASO
deploy_azure_resources() {
    local existing_resources=$(get_deployment_state "AZURE_RESOURCES_DEPLOYED")
    if [ "$existing_resources" = "true" ]; then
        info "Azure resources already deployed, skipping"
        return
    fi
    
    info "Deploying Azure resources via Azure Service Operator..."
    
    # Switch to first cluster
    kubectl config use-context "aks-fleet-1"
    
    # Create namespace for Azure resources
    kubectl create namespace azure-resources --dry-run=client -o yaml | kubectl apply -f - || \
        error_exit "Failed to create azure-resources namespace"
    
    # Create Container Registry via ASO
    info "Creating Container Registry via ASO..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: resources.azure.com/v1api20210701
kind: ResourceGroup
metadata:
  name: $RESOURCE_GROUP
  namespace: azure-resources
spec:
  location: $LOCATION
---
apiVersion: containerregistry.azure.com/v1api20210901
kind: Registry
metadata:
  name: $ACR_NAME
  namespace: azure-resources
spec:
  owner:
    name: $RESOURCE_GROUP
  location: $LOCATION
  sku:
    name: Standard
  adminUserEnabled: false
  policies:
    quarantinePolicy:
      status: disabled
    trustPolicy:
      type: Notary
      status: disabled
    retentionPolicy:
      days: 7
      status: disabled
EOF
    
    # Wait for ACR to be created
    info "Waiting for Container Registry creation..."
    kubectl wait --for=condition=ready registry/"$ACR_NAME" \
        -n azure-resources \
        --timeout=300s || \
        error_exit "Container Registry creation failed"
    
    # Create Key Vault via ASO
    info "Creating Key Vault via ASO..."
    
    # Switch to second cluster
    kubectl config use-context "aks-fleet-2"
    
    # Create namespace for Azure resources
    kubectl create namespace azure-resources --dry-run=client -o yaml | kubectl apply -f - || \
        error_exit "Failed to create azure-resources namespace on cluster 2"
    
    cat <<EOF | kubectl apply -f -
apiVersion: keyvault.azure.com/v1api20210401preview
kind: Vault
metadata:
  name: $KV_NAME
  namespace: azure-resources
spec:
  owner:
    name: $RESOURCE_GROUP
  location: $LOCATION
  properties:
    sku:
      family: A
      name: standard
    tenantID: $ASO_TENANT_ID
    accessPolicies: []
    enabledForDeployment: true
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
---
apiVersion: keyvault.azure.com/v1api20210401preview
kind: VaultsSecret
metadata:
  name: database-connection
  namespace: azure-resources
spec:
  owner:
    name: $KV_NAME
  properties:
    value: "Server=tcp:myserver.database.windows.net;Database=mydb;User ID=admin;Password=SecureP@ssw0rd!;Encrypt=true"
EOF
    
    # Wait for Key Vault to be created
    info "Waiting for Key Vault creation..."
    kubectl wait --for=condition=ready vault/"$KV_NAME" \
        -n azure-resources \
        --timeout=300s || \
        error_exit "Key Vault creation failed"
    
    save_deployment_state "AZURE_RESOURCES_DEPLOYED" "true"
    success "Azure resources deployed successfully"
}

# Deploy multi-cluster application
deploy_multi_cluster_application() {
    local existing_app=$(get_deployment_state "MULTI_CLUSTER_APP_DEPLOYED")
    if [ "$existing_app" = "true" ]; then
        info "Multi-cluster application already deployed, skipping"
        return
    fi
    
    info "Deploying multi-cluster application..."
    
    # Create fleet-wide application namespace
    for i in ${!REGIONS[@]}; do
        local cluster_name="aks-fleet-$((i+1))"
        kubectl config use-context "$cluster_name"
        kubectl create namespace fleet-app --dry-run=client -o yaml | kubectl apply -f - || \
            error_exit "Failed to create fleet-app namespace on $cluster_name"
    done
    
    # Deploy application with region-specific storage
    for i in ${!REGIONS[@]}; do
        local cluster_name="aks-fleet-$((i+1))"
        local region="${REGIONS[$i]}"
        local storage_account="stfleet${RANDOM_SUFFIX}${i}"
        
        info "Deploying application to $cluster_name with storage account $storage_account..."
        
        kubectl config use-context "$cluster_name"
        
        # Create region-specific storage via ASO
        cat <<EOF | kubectl apply -f -
apiVersion: storage.azure.com/v1api20210401
kind: StorageAccount
metadata:
  name: $storage_account
  namespace: fleet-app
spec:
  owner:
    name: $RESOURCE_GROUP
  location: $region
  kind: StorageV2
  sku:
    name: Standard_LRS
  properties:
    accessTier: Hot
    supportsHttpsTrafficOnly: true
    encryption:
      services:
        blob:
          enabled: true
        file:
          enabled: true
      keySource: Microsoft.Storage
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: regional-app
  namespace: fleet-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: regional-app
  template:
    metadata:
      labels:
        app: regional-app
    spec:
      containers:
      - name: app
        image: mcr.microsoft.com/azuredocs/aks-helloworld:v1
        env:
        - name: REGION
          value: $region
        - name: STORAGE_ACCOUNT
          value: $storage_account
        ports:
        - containerPort: 80
EOF
        
        success "Application deployed to $cluster_name"
    done
    
    save_deployment_state "MULTI_CLUSTER_APP_DEPLOYED" "true"
    success "Multi-cluster application deployed successfully"
}

# Main deployment function
main() {
    # Initialize log file
    echo "=== Azure Kubernetes Fleet Manager Deployment Started at $(date) ===" > "$LOG_FILE"
    
    info "Starting Azure Kubernetes Fleet Manager and Service Operator deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_resource_group
    create_service_principal
    create_fleet_manager
    create_aks_clusters
    join_clusters_to_fleet
    install_azure_service_operator
    deploy_azure_resources
    deploy_multi_cluster_application
    
    # Final validation
    info "Performing final validation..."
    
    # Check fleet status
    az fleet show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FLEET_NAME" \
        --output table
    
    # List all fleet members
    az fleet member list \
        --resource-group "$RESOURCE_GROUP" \
        --fleet-name "$FLEET_NAME" \
        --output table
    
    # Check ASO pods across clusters
    for i in ${!REGIONS[@]}; do
        local cluster_name="aks-fleet-$((i+1))"
        info "Checking ASO pods on $cluster_name..."
        kubectl config use-context "$cluster_name"
        kubectl get pods -n azureserviceoperator-system
    done
    
    # Mark deployment as complete
    save_deployment_state "DEPLOYMENT_COMPLETE" "true"
    save_deployment_state "DEPLOYMENT_TIMESTAMP" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    
    success "=== Deployment completed successfully! ==="
    info "Fleet Manager: $FLEET_NAME"
    info "Resource Group: $RESOURCE_GROUP"
    info "Container Registry: $ACR_NAME"
    info "Key Vault: $KV_NAME"
    info "Deployment state saved to: $DEPLOYMENT_STATE_FILE"
    info "Full deployment log available at: $LOG_FILE"
    
    echo ""
    info "Next steps:"
    info "1. Configure kubectl contexts for fleet clusters"
    info "2. Test multi-cluster application deployment"
    info "3. Set up monitoring and observability"
    info "4. Configure fleet-wide update policies"
    
    echo ""
    warn "Remember to run ./destroy.sh when you're done to clean up resources and avoid charges!"
}

# Handle script interruption
cleanup_on_exit() {
    warn "Deployment interrupted. Partial deployment state saved to $DEPLOYMENT_STATE_FILE"
    warn "You can re-run this script to continue from where it left off, or run ./destroy.sh to clean up"
}

trap cleanup_on_exit EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -h, --help              Show this help message"
            echo "  --resource-group NAME   Resource group name (default: rg-fleet-demo)"
            echo "  --location LOCATION     Azure region (default: eastus)"
            echo "  --fleet-name NAME       Fleet name (default: multicluster-fleet)"
            echo ""
            echo "Environment variables:"
            echo "  RESOURCE_GROUP          Resource group name"
            echo "  LOCATION                Azure region"
            echo "  FLEET_NAME              Fleet name"
            exit 0
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --location)
            LOCATION="$2"
            shift 2
            ;;
        --fleet-name)
            FLEET_NAME="$2"
            shift 2
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

# Run main deployment
main