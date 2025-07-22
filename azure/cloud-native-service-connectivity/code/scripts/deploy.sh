#!/bin/bash

# Deploy Azure Cloud-Native Service Connectivity with Application Gateway for Containers and Service Connector
# This script deploys the complete infrastructure for cloud-native service connectivity

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="cloud-native-connectivity"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${SCRIPT_DIR}/deployment_${TIMESTAMP}.log"

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
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is not installed. Please install it first."
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --output tsv --query '"azure-cli"')
    info "Azure CLI version: ${az_version}"
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "You are not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if required extensions are available
    info "Checking Azure CLI extensions..."
    
    # List required extensions
    local required_extensions=("serviceconnector-passwordless" "alb")
    for ext in "${required_extensions[@]}"; do
        if ! az extension show --name "${ext}" &> /dev/null; then
            info "Installing Azure CLI extension: ${ext}"
            az extension add --name "${ext}" --upgrade || error_exit "Failed to install extension: ${ext}"
        fi
    done
    
    success "Prerequisites check completed"
}

# Set environment variables
set_environment_variables() {
    info "Setting environment variables..."
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-${PROJECT_NAME}}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    
    # Generate unique suffix for resource names
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    export CLUSTER_NAME="aks-connectivity-${RANDOM_SUFFIX}"
    export AGC_NAME="agc-connectivity-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="storage${RANDOM_SUFFIX}"
    export SQL_SERVER="sqlserver-${RANDOM_SUFFIX}"
    export KEY_VAULT="kv-${RANDOM_SUFFIX}"
    export WORKLOAD_IDENTITY_NAME="wi-connectivity-${RANDOM_SUFFIX}"
    
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

# Enable required Azure features
enable_azure_features() {
    info "Enabling required Azure features..."
    
    # Enable required feature flags
    local features=(
        "Microsoft.ContainerService/AKS-ExtensionManager"
        "Microsoft.ContainerService/AKS-Dapr"
        "Microsoft.ContainerService/EnableWorkloadIdentityPreview"
    )
    
    for feature in "${features[@]}"; do
        info "Registering feature: ${feature}"
        az feature register --namespace "${feature%/*}" --name "${feature#*/}" || warning "Failed to register feature: ${feature}"
    done
    
    success "Azure features enabled"
}

# Create resource group
create_resource_group() {
    info "Creating resource group..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        info "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=cloud-native-connectivity environment=demo \
            || error_exit "Failed to create resource group"
        
        success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Create AKS cluster
create_aks_cluster() {
    info "Creating AKS cluster..."
    
    if az aks show --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER_NAME}" &> /dev/null; then
        info "AKS cluster ${CLUSTER_NAME} already exists"
    else
        az aks create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${CLUSTER_NAME}" \
            --location "${LOCATION}" \
            --node-count 3 \
            --node-vm-size Standard_D2s_v3 \
            --enable-workload-identity \
            --enable-oidc-issuer \
            --enable-addons monitoring \
            --generate-ssh-keys \
            --network-plugin azure \
            --network-policy azure \
            --tags purpose=cloud-native-connectivity \
            || error_exit "Failed to create AKS cluster"
        
        success "AKS cluster created: ${CLUSTER_NAME}"
    fi
    
    # Get AKS credentials
    info "Getting AKS credentials..."
    az aks get-credentials \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${CLUSTER_NAME}" \
        --overwrite-existing \
        || error_exit "Failed to get AKS credentials"
    
    # Get OIDC issuer URL
    export OIDC_ISSUER=$(az aks show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${CLUSTER_NAME}" \
        --query "oidcIssuerProfile.issuerUrl" \
        --output tsv)
    
    info "OIDC Issuer: ${OIDC_ISSUER}"
    success "AKS cluster configured with workload identity"
}

# Install Application Gateway for Containers
install_application_gateway() {
    info "Installing Application Gateway for Containers..."
    
    # Enable Application Gateway for Containers addon
    az aks enable-addons \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${CLUSTER_NAME}" \
        --addons application-gateway-for-containers \
        || error_exit "Failed to enable Application Gateway for Containers addon"
    
    # Wait for addon to be ready
    info "Waiting for Application Gateway for Containers addon to be ready..."
    sleep 30
    
    # Verify installation
    kubectl get pods -n azure-alb-system || warning "Application Gateway for Containers pods not found"
    
    # Create Application Gateway for Containers resource
    if az network application-gateway for-containers show --resource-group "${RESOURCE_GROUP}" --name "${AGC_NAME}" &> /dev/null; then
        info "Application Gateway for Containers ${AGC_NAME} already exists"
    else
        az network application-gateway for-containers create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${AGC_NAME}" \
            --location "${LOCATION}" \
            --frontend-configurations '[{
                "name": "frontend-config",
                "port": 80,
                "protocol": "Http"
            }]' \
            || error_exit "Failed to create Application Gateway for Containers"
        
        success "Application Gateway for Containers created: ${AGC_NAME}"
    fi
    
    # Get Application Gateway for Containers resource ID
    export AGC_ID=$(az network application-gateway for-containers show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${AGC_NAME}" \
        --query id \
        --output tsv)
    
    info "AGC Resource ID: ${AGC_ID}"
    success "Application Gateway for Containers installed and configured"
}

# Create Azure services for Service Connector
create_azure_services() {
    info "Creating Azure services for Service Connector integration..."
    
    # Create Azure Storage Account
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "Storage account ${STORAGE_ACCOUNT} already exists"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --allow-blob-public-access false \
            --min-tls-version TLS1_2 \
            || error_exit "Failed to create storage account"
        
        success "Storage account created: ${STORAGE_ACCOUNT}"
    fi
    
    # Create SQL Server and Database
    if az sql server show --name "${SQL_SERVER}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "SQL Server ${SQL_SERVER} already exists"
    else
        az sql server create \
            --name "${SQL_SERVER}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --admin-user cloudadmin \
            --admin-password "SecurePassword123!" \
            --enable-ad-only-auth false \
            || error_exit "Failed to create SQL Server"
        
        success "SQL Server created: ${SQL_SERVER}"
    fi
    
    # Create SQL Database
    if az sql db show --resource-group "${RESOURCE_GROUP}" --server "${SQL_SERVER}" --name application-db &> /dev/null; then
        info "SQL Database application-db already exists"
    else
        az sql db create \
            --resource-group "${RESOURCE_GROUP}" \
            --server "${SQL_SERVER}" \
            --name application-db \
            --edition Basic \
            --compute-model Serverless \
            --auto-pause-delay 60 \
            || error_exit "Failed to create SQL Database"
        
        success "SQL Database created: application-db"
    fi
    
    # Create Key Vault
    if az keyvault show --name "${KEY_VAULT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "Key Vault ${KEY_VAULT} already exists"
    else
        az keyvault create \
            --name "${KEY_VAULT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku standard \
            --enable-rbac-authorization true \
            || error_exit "Failed to create Key Vault"
        
        success "Key Vault created: ${KEY_VAULT}"
    fi
    
    # Add sample secrets to Key Vault
    az keyvault secret set \
        --vault-name "${KEY_VAULT}" \
        --name "database-connection-timeout" \
        --value "30" \
        || warning "Failed to set secret: database-connection-timeout"
    
    az keyvault secret set \
        --vault-name "${KEY_VAULT}" \
        --name "api-rate-limit" \
        --value "1000" \
        || warning "Failed to set secret: api-rate-limit"
    
    success "Azure services created for Service Connector integration"
}

# Configure Azure Workload Identity
configure_workload_identity() {
    info "Configuring Azure Workload Identity..."
    
    # Create user-assigned managed identity
    if az identity show --resource-group "${RESOURCE_GROUP}" --name "${WORKLOAD_IDENTITY_NAME}" &> /dev/null; then
        info "Managed identity ${WORKLOAD_IDENTITY_NAME} already exists"
    else
        az identity create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${WORKLOAD_IDENTITY_NAME}" \
            --location "${LOCATION}" \
            || error_exit "Failed to create managed identity"
        
        success "Managed identity created: ${WORKLOAD_IDENTITY_NAME}"
    fi
    
    # Get managed identity details
    export USER_ASSIGNED_CLIENT_ID=$(az identity show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${WORKLOAD_IDENTITY_NAME}" \
        --query 'clientId' \
        --output tsv)
    
    export USER_ASSIGNED_OBJECT_ID=$(az identity show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${WORKLOAD_IDENTITY_NAME}" \
        --query 'principalId' \
        --output tsv)
    
    info "Client ID: ${USER_ASSIGNED_CLIENT_ID}"
    info "Object ID: ${USER_ASSIGNED_OBJECT_ID}"
    
    # Create Kubernetes namespace and service account
    kubectl create namespace cloud-native-app --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl create serviceaccount workload-identity-sa \
        --namespace cloud-native-app \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Annotate service account with managed identity
    kubectl annotate serviceaccount workload-identity-sa \
        --namespace cloud-native-app \
        azure.workload.identity/client-id="${USER_ASSIGNED_CLIENT_ID}" \
        --overwrite
    
    # Create federated identity credential
    local fed_cred_name="aks-federated-credential"
    if az identity federated-credential show \
        --name "${fed_cred_name}" \
        --identity-name "${WORKLOAD_IDENTITY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "Federated identity credential ${fed_cred_name} already exists"
    else
        az identity federated-credential create \
            --name "${fed_cred_name}" \
            --identity-name "${WORKLOAD_IDENTITY_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --issuer "${OIDC_ISSUER}" \
            --subject "system:serviceaccount:cloud-native-app:workload-identity-sa" \
            || error_exit "Failed to create federated identity credential"
        
        success "Federated identity credential created: ${fed_cred_name}"
    fi
    
    success "Azure Workload Identity configured"
}

# Grant permissions to managed identity
grant_permissions() {
    info "Granting managed identity permissions to Azure services..."
    
    # Grant Storage Blob Data Contributor role
    az role assignment create \
        --role "Storage Blob Data Contributor" \
        --assignee-object-id "${USER_ASSIGNED_OBJECT_ID}" \
        --assignee-principal-type ServicePrincipal \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
        || warning "Failed to grant Storage Blob Data Contributor role"
    
    # Grant SQL DB Contributor role
    az role assignment create \
        --role "SQL DB Contributor" \
        --assignee-object-id "${USER_ASSIGNED_OBJECT_ID}" \
        --assignee-principal-type ServicePrincipal \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Sql/servers/${SQL_SERVER}/databases/application-db" \
        || warning "Failed to grant SQL DB Contributor role"
    
    # Grant Key Vault Secrets User role
    az role assignment create \
        --role "Key Vault Secrets User" \
        --assignee-object-id "${USER_ASSIGNED_OBJECT_ID}" \
        --assignee-principal-type ServicePrincipal \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT}" \
        || warning "Failed to grant Key Vault Secrets User role"
    
    success "Managed identity permissions granted"
}

# Deploy sample applications
deploy_applications() {
    info "Deploying sample applications with Service Connector integration..."
    
    # Deploy frontend application
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-app
  namespace: cloud-native-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend-app
  template:
    metadata:
      labels:
        app: frontend-app
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: workload-identity-sa
      containers:
      - name: frontend
        image: nginx:latest
        ports:
        - containerPort: 80
        env:
        - name: AZURE_CLIENT_ID
          value: ${USER_ASSIGNED_CLIENT_ID}
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: cloud-native-app
spec:
  selector:
    app: frontend-app
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF
    
    # Deploy API service
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-service
  namespace: cloud-native-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-service
  template:
    metadata:
      labels:
        app: api-service
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: workload-identity-sa
      containers:
      - name: api
        image: mcr.microsoft.com/dotnet/samples:aspnetapp
        ports:
        - containerPort: 8080
        env:
        - name: AZURE_CLIENT_ID
          value: ${USER_ASSIGNED_CLIENT_ID}
        - name: STORAGE_ACCOUNT_NAME
          value: ${STORAGE_ACCOUNT}
        - name: KEY_VAULT_NAME
          value: ${KEY_VAULT}
---
apiVersion: v1
kind: Service
metadata:
  name: api-service
  namespace: cloud-native-app
spec:
  selector:
    app: api-service
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
EOF
    
    # Deploy data service
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: data-service
  namespace: cloud-native-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: data-service
  template:
    metadata:
      labels:
        app: data-service
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: workload-identity-sa
      containers:
      - name: data
        image: mcr.microsoft.com/dotnet/samples:aspnetapp
        ports:
        - containerPort: 8080
        env:
        - name: AZURE_CLIENT_ID
          value: ${USER_ASSIGNED_CLIENT_ID}
        - name: SQL_SERVER_NAME
          value: ${SQL_SERVER}
---
apiVersion: v1
kind: Service
metadata:
  name: data-service
  namespace: cloud-native-app
spec:
  selector:
    app: data-service
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
EOF
    
    success "Sample applications deployed"
}

# Configure Gateway API resources
configure_gateway_api() {
    info "Configuring Gateway API resources..."
    
    # Create Gateway resource
    cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: cloud-native-gateway
  namespace: cloud-native-app
  annotations:
    alb.networking.azure.io/alb-id: ${AGC_ID}
spec:
  gatewayClassName: azure-alb
  listeners:
  - name: http-listener
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: Same
EOF
    
    # Create HTTPRoute for frontend
    cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: frontend-route
  namespace: cloud-native-app
spec:
  parentRefs:
  - name: cloud-native-gateway
    sectionName: http-listener
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: frontend-service
      port: 80
      weight: 100
EOF
    
    # Create HTTPRoute for API service
    cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: api-route
  namespace: cloud-native-app
spec:
  parentRefs:
  - name: cloud-native-gateway
    sectionName: http-listener
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
    backendRefs:
    - name: api-service
      port: 8080
      weight: 100
EOF
    
    # Create HTTPRoute for data service
    cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: data-route
  namespace: cloud-native-app
spec:
  parentRefs:
  - name: cloud-native-gateway
    sectionName: http-listener
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /data
    backendRefs:
    - name: data-service
      port: 8080
      weight: 100
EOF
    
    success "Gateway API resources configured"
}

# Verify deployment
verify_deployment() {
    info "Verifying deployment..."
    
    # Check Application Gateway for Containers
    info "Checking Application Gateway for Containers status..."
    az network application-gateway for-containers show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${AGC_NAME}" \
        --query '{name:name,provisioningState:provisioningState,location:location}' \
        --output table
    
    # Check Gateway API resources
    info "Checking Gateway API resources..."
    kubectl get gateway -n cloud-native-app
    kubectl get httproute -n cloud-native-app
    
    # Check application pods
    info "Checking application pods..."
    kubectl get pods -n cloud-native-app
    
    # Check workload identity
    info "Checking workload identity configuration..."
    kubectl describe serviceaccount workload-identity-sa -n cloud-native-app
    
    success "Deployment verification completed"
}

# Save deployment information
save_deployment_info() {
    info "Saving deployment information..."
    
    local info_file="${SCRIPT_DIR}/deployment_info_${TIMESTAMP}.txt"
    
    cat > "${info_file}" <<EOF
Deployment Information
======================
Date: $(date)
Resource Group: ${RESOURCE_GROUP}
Location: ${LOCATION}
Subscription ID: ${SUBSCRIPTION_ID}
Random Suffix: ${RANDOM_SUFFIX}

Resources Created:
- AKS Cluster: ${CLUSTER_NAME}
- Application Gateway for Containers: ${AGC_NAME}
- Storage Account: ${STORAGE_ACCOUNT}
- SQL Server: ${SQL_SERVER}
- Key Vault: ${KEY_VAULT}
- Workload Identity: ${WORKLOAD_IDENTITY_NAME}

OIDC Issuer: ${OIDC_ISSUER}
Client ID: ${USER_ASSIGNED_CLIENT_ID}
Object ID: ${USER_ASSIGNED_OBJECT_ID}
AGC Resource ID: ${AGC_ID}

Cleanup Command:
${SCRIPT_DIR}/destroy.sh
EOF
    
    success "Deployment information saved to: ${info_file}"
}

# Main deployment function
main() {
    log "Starting deployment of Azure Cloud-Native Service Connectivity..."
    log "Timestamp: $(date)"
    log "Script: ${0}"
    log "Log file: ${LOG_FILE}"
    
    check_prerequisites
    set_environment_variables
    enable_azure_features
    create_resource_group
    create_aks_cluster
    install_application_gateway
    create_azure_services
    configure_workload_identity
    grant_permissions
    deploy_applications
    configure_gateway_api
    verify_deployment
    save_deployment_info
    
    success "Deployment completed successfully!"
    info "Resources have been created in resource group: ${RESOURCE_GROUP}"
    info "Run '${SCRIPT_DIR}/destroy.sh' to clean up resources"
}

# Run main function
main "$@"