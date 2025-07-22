#!/bin/bash

# Azure MLOps Pipeline Deployment Script
# This script deploys the complete MLOps pipeline infrastructure including:
# - Azure Kubernetes Service (AKS)
# - Azure Machine Learning workspace
# - Azure Container Registry (ACR)
# - Azure Key Vault
# - Storage Account
# - Application Insights
# - Log Analytics workspace

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
    
    # Check if OpenSSL is installed (for random generation)
    if ! command_exists openssl; then
        log_error "OpenSSL is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show > /dev/null 2>&1; then
        log_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if ML extension is installed
    if ! az extension show --name ml > /dev/null 2>&1; then
        log "Installing Azure ML extension..."
        az extension add --name ml --yes
    fi
    
    log_success "Prerequisites validated successfully"
}

# Set default values if not provided
setup_environment() {
    log "Setting up environment variables..."
    
    # Set defaults
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-mlops-pipeline}"
    export LOCATION="${LOCATION:-eastus}"
    export WORKSPACE_NAME="${WORKSPACE_NAME:-mlw-mlops-demo}"
    export AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-aks-mlops-cluster}"
    export ACR_NAME="${ACR_NAME:-acrmlops$(openssl rand -hex 4)}"
    export KEYVAULT_NAME="${KEYVAULT_NAME:-kv-mlops-$(openssl rand -hex 4)}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stmlops$(openssl rand -hex 4)}"
    export DIAG_STORAGE_ACCOUNT="${DIAG_STORAGE_ACCOUNT:-${STORAGE_ACCOUNT}diag}"
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-mlops-logs}"
    export APP_INSIGHTS_NAME="${APP_INSIGHTS_NAME:-mlops-insights}"
    
    # Display configuration
    log "Configuration:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Location: ${LOCATION}"
    log "  ML Workspace: ${WORKSPACE_NAME}"
    log "  AKS Cluster: ${AKS_CLUSTER_NAME}"
    log "  Container Registry: ${ACR_NAME}"
    log "  Key Vault: ${KEYVAULT_NAME}"
    log "  Storage Account: ${STORAGE_ACCOUNT}"
    
    log_success "Environment variables configured"
}

# Create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists, skipping creation"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=mlops environment=demo
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Create storage account
create_storage_account() {
    log "Creating storage account..."
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_warning "Storage account ${STORAGE_ACCOUNT} already exists, skipping creation"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2
        log_success "Storage account created: ${STORAGE_ACCOUNT}"
    fi
}

# Create Azure Container Registry
create_container_registry() {
    log "Creating Azure Container Registry..."
    
    if az acr show --name "${ACR_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_warning "Container Registry ${ACR_NAME} already exists, skipping creation"
    else
        az acr create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${ACR_NAME}" \
            --sku Standard \
            --admin-enabled true
        log_success "Container Registry created: ${ACR_NAME}"
    fi
    
    # Get ACR credentials
    export ACR_LOGIN_SERVER=$(az acr show \
        --name "${ACR_NAME}" \
        --query loginServer \
        --output tsv)
    
    export ACR_USERNAME=$(az acr credential show \
        --name "${ACR_NAME}" \
        --query username \
        --output tsv)
    
    export ACR_PASSWORD=$(az acr credential show \
        --name "${ACR_NAME}" \
        --query passwords[0].value \
        --output tsv)
    
    log_success "Container Registry credentials retrieved"
}

# Create Azure Kubernetes Service
create_aks_cluster() {
    log "Creating AKS cluster (this may take 10-15 minutes)..."
    
    if az aks show --name "${AKS_CLUSTER_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_warning "AKS cluster ${AKS_CLUSTER_NAME} already exists, skipping creation"
    else
        # Create AKS cluster
        az aks create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${AKS_CLUSTER_NAME}" \
            --node-count 2 \
            --node-vm-size Standard_DS3_v2 \
            --enable-cluster-autoscaler \
            --min-count 2 \
            --max-count 5 \
            --generate-ssh-keys \
            --attach-acr "${ACR_NAME}" \
            --enable-addons monitoring \
            --enable-managed-identity
        
        log_success "AKS cluster created successfully"
    fi
    
    # Add ML workload node pool
    log "Adding ML workload node pool..."
    
    if az aks nodepool show --cluster-name "${AKS_CLUSTER_NAME}" --resource-group "${RESOURCE_GROUP}" --name mlpool > /dev/null 2>&1; then
        log_warning "ML node pool already exists, skipping creation"
    else
        az aks nodepool add \
            --resource-group "${RESOURCE_GROUP}" \
            --cluster-name "${AKS_CLUSTER_NAME}" \
            --name mlpool \
            --node-count 2 \
            --node-vm-size Standard_DS3_v2 \
            --enable-cluster-autoscaler \
            --min-count 1 \
            --max-count 4 \
            --mode User \
            --node-taints "workload=ml:NoSchedule"
        
        log_success "ML node pool added successfully"
    fi
    
    # Get AKS credentials
    log "Getting AKS credentials..."
    az aks get-credentials \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${AKS_CLUSTER_NAME}" \
        --overwrite-existing
    
    log_success "AKS credentials configured"
}

# Create supporting services
create_supporting_services() {
    log "Creating supporting services..."
    
    # Create Key Vault
    if az keyvault show --name "${KEYVAULT_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_warning "Key Vault ${KEYVAULT_NAME} already exists, skipping creation"
    else
        az keyvault create \
            --name "${KEYVAULT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --enable-soft-delete true \
            --retention-days 90
        log_success "Key Vault created: ${KEYVAULT_NAME}"
    fi
    
    # Create Application Insights
    if az monitor app-insights component show --app "${APP_INSIGHTS_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_warning "Application Insights ${APP_INSIGHTS_NAME} already exists, skipping creation"
    else
        az monitor app-insights component create \
            --app "${APP_INSIGHTS_NAME}" \
            --location "${LOCATION}" \
            --resource-group "${RESOURCE_GROUP}" \
            --application-type web
        log_success "Application Insights created: ${APP_INSIGHTS_NAME}"
    fi
    
    # Get Application Insights ID
    export APP_INSIGHTS_ID=$(az monitor app-insights component show \
        --app "${APP_INSIGHTS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id \
        --output tsv)
}

# Create ML workspace
create_ml_workspace() {
    log "Creating Azure Machine Learning workspace..."
    
    if az ml workspace show --name "${WORKSPACE_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_warning "ML workspace ${WORKSPACE_NAME} already exists, skipping creation"
    else
        az ml workspace create \
            --name "${WORKSPACE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --key-vault "${KEYVAULT_NAME}" \
            --app-insights "${APP_INSIGHTS_ID}" \
            --container-registry "${ACR_NAME}"
        
        log_success "ML workspace created: ${WORKSPACE_NAME}"
    fi
}

# Configure ML extension and compute
configure_ml_extension() {
    log "Installing ML extension on AKS (this may take 5-10 minutes)..."
    
    # Check if extension already exists
    if az k8s-extension show --name ml-extension --cluster-name "${AKS_CLUSTER_NAME}" --resource-group "${RESOURCE_GROUP}" --cluster-type managedClusters > /dev/null 2>&1; then
        log_warning "ML extension already installed, skipping installation"
    else
        az k8s-extension create \
            --name ml-extension \
            --cluster-name "${AKS_CLUSTER_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --extension-type Microsoft.AzureML.Kubernetes \
            --cluster-type managedClusters \
            --scope cluster \
            --auto-upgrade-minor-version true
        
        log_success "ML extension installed successfully"
    fi
    
    # Wait for extension to be ready
    log "Waiting for ML extension to be ready..."
    sleep 120  # Wait 2 minutes for extension to initialize
    
    # Check extension status
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if kubectl get pods -n azureml | grep -q "Running"; then
            log_success "ML extension is ready"
            break
        fi
        
        log "Waiting for ML extension pods to be ready... (attempt $((attempt + 1))/${max_attempts})"
        sleep 30
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        log_error "ML extension failed to become ready within expected time"
        exit 1
    fi
}

# Attach AKS to ML workspace
attach_aks_to_ml() {
    log "Attaching AKS cluster to ML workspace..."
    
    # Check if compute target already exists
    if az ml compute show --name aks-compute --resource-group "${RESOURCE_GROUP}" --workspace-name "${WORKSPACE_NAME}" > /dev/null 2>&1; then
        log_warning "AKS compute target already attached, skipping attachment"
    else
        # Get subscription ID
        local subscription_id=$(az account show --query id -o tsv)
        
        # Attach AKS to ML workspace
        az ml compute attach \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${WORKSPACE_NAME}" \
            --type Kubernetes \
            --name aks-compute \
            --resource-id "/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ContainerService/managedClusters/${AKS_CLUSTER_NAME}" \
            --identity-type SystemAssigned \
            --namespace azureml
        
        log_success "AKS cluster attached to ML workspace"
    fi
}

# Create instance types
create_instance_types() {
    log "Creating custom instance types..."
    
    # Create small instance type
    cat <<EOF > /tmp/small-instance-type.yaml
apiVersion: amlarc.azureml.com/v1alpha1
kind: InstanceType
metadata:
  name: small-cpu-model
  namespace: azureml
spec:
  resources:
    limits:
      cpu: "2"
      memory: "4Gi"
    requests:
      cpu: "1"
      memory: "2Gi"
  nodeSelector:
    agentpool: mlpool
  tolerations:
  - key: "workload"
    operator: "Equal"
    value: "ml"
    effect: "NoSchedule"
EOF
    
    # Create large instance type
    cat <<EOF > /tmp/large-instance-type.yaml
apiVersion: amlarc.azureml.com/v1alpha1
kind: InstanceType
metadata:
  name: large-cpu-model
  namespace: azureml
spec:
  resources:
    limits:
      cpu: "4"
      memory: "16Gi"
    requests:
      cpu: "2"
      memory: "8Gi"
  nodeSelector:
    agentpool: mlpool
  tolerations:
  - key: "workload"
    operator: "Equal"
    value: "ml"
    effect: "NoSchedule"
EOF
    
    # Apply instance types
    kubectl apply -f /tmp/small-instance-type.yaml
    kubectl apply -f /tmp/large-instance-type.yaml
    
    # Clean up temporary files
    rm -f /tmp/small-instance-type.yaml /tmp/large-instance-type.yaml
    
    log_success "Custom instance types created"
}

# Configure monitoring
configure_monitoring() {
    log "Configuring monitoring and diagnostics..."
    
    # Create diagnostic storage account
    if az storage account show --name "${DIAG_STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_warning "Diagnostic storage account already exists, skipping creation"
    else
        az storage account create \
            --name "${DIAG_STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS
        log_success "Diagnostic storage account created"
    fi
    
    # Create Log Analytics workspace
    if az monitor log-analytics workspace show --workspace-name "${LOG_ANALYTICS_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_warning "Log Analytics workspace already exists, skipping creation"
        export WORKSPACE_ID=$(az monitor log-analytics workspace show \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
            --query id -o tsv)
    else
        export WORKSPACE_ID=$(az monitor log-analytics workspace create \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
            --location "${LOCATION}" \
            --query id -o tsv)
        log_success "Log Analytics workspace created"
    fi
    
    # Get AKS resource ID
    local aks_resource_id=$(az aks show \
        --name "${AKS_CLUSTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id -o tsv)
    
    # Configure diagnostic settings
    if az monitor diagnostic-settings show --name aks-diagnostics --resource "${aks_resource_id}" > /dev/null 2>&1; then
        log_warning "Diagnostic settings already configured, skipping configuration"
    else
        az monitor diagnostic-settings create \
            --name aks-diagnostics \
            --resource "${aks_resource_id}" \
            --logs '[
              {
                "category": "kube-apiserver",
                "enabled": true,
                "retentionPolicy": {"enabled": true, "days": 30}
              },
              {
                "category": "kube-controller-manager",
                "enabled": true,
                "retentionPolicy": {"enabled": true, "days": 30}
              },
              {
                "category": "kube-scheduler",
                "enabled": true,
                "retentionPolicy": {"enabled": true, "days": 30}
              }
            ]' \
            --metrics '[
              {
                "category": "AllMetrics",
                "enabled": true,
                "retentionPolicy": {"enabled": true, "days": 30}
              }
            ]' \
            --workspace "${WORKSPACE_ID}"
        
        log_success "Diagnostic settings configured"
    fi
}

# Create sample files
create_sample_files() {
    log "Creating sample model files..."
    
    # Create sample scoring script
    cat <<EOF > score.py
import json
import numpy as np
import os
from azureml.core.model import Model

def init():
    global model
    # This is a placeholder - replace with your model loading logic
    model_path = os.path.join(os.getenv('AZUREML_MODEL_DIR'), 'model.pkl')
    print(f"Loading model from: {model_path}")
    # model = joblib.load(model_path)

def run(data):
    try:
        # Parse input data
        input_data = json.loads(data)
        # Placeholder prediction logic
        prediction = {"prediction": "sample_output", "confidence": 0.95}
        return json.dumps(prediction)
    except Exception as e:
        error = str(e)
        return json.dumps({"error": error})
EOF
    
    # Create deployment configuration
    cat <<EOF > deployment-config.yml
name: sample-model-deployment
endpoint_name: mlops-endpoint
model:
  name: sample-model
  version: 1
  path: ./model
code_configuration:
  code: ./
  scoring_script: score.py
environment:
  name: sklearn-env
  version: 1
  image: mcr.microsoft.com/azureml/sklearn-1.0-ubuntu20.04-py38-cpu:latest
instance_type: small-cpu-model
instance_count: 2
request_settings:
  request_timeout_ms: 3000
  max_concurrent_requests_per_instance: 2
liveness_probe:
  initial_delay: 30
  period: 10
  timeout: 2
  success_threshold: 1
  failure_threshold: 3
readiness_probe:
  initial_delay: 30
  period: 10
  timeout: 2
  success_threshold: 1
  failure_threshold: 3
EOF
    
    # Create Azure DevOps pipeline
    cat <<EOF > azure-pipelines.yml
trigger:
  branches:
    include:
    - main
  paths:
    include:
    - models/*
    - deployments/*

pool:
  vmImage: 'ubuntu-latest'

variables:
  azureServiceConnection: 'MLOps-ServiceConnection'
  resourceGroup: '${RESOURCE_GROUP}'
  workspaceName: '${WORKSPACE_NAME}'
  acrName: '${ACR_NAME}'
  modelName: 'production-model'

stages:
- stage: Build
  displayName: 'Build and Package Model'
  jobs:
  - job: BuildModel
    steps:
    - task: UsePythonVersion@0
      inputs:
        versionSpec: '3.8'
        addToPath: true
    
    - script: |
        pip install azureml-sdk azureml-mlflow
        echo "Dependencies installed"
      displayName: 'Install Dependencies'
    
    - task: AzureCLI@2
      inputs:
        azureSubscription: \$(azureServiceConnection)
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          az ml model create \
            --name \$(modelName) \
            --version \$BUILD_BUILDID \
            --path ./model \
            --resource-group \$(resourceGroup) \
            --workspace-name \$(workspaceName)
      displayName: 'Register Model'

- stage: Deploy
  displayName: 'Deploy to AKS'
  dependsOn: Build
  jobs:
  - deployment: DeployToAKS
    environment: 'Production'
    strategy:
      runOnce:
        deploy:
          steps:
          - task: AzureCLI@2
            inputs:
              azureSubscription: \$(azureServiceConnection)
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                # Create or update endpoint
                az ml online-endpoint create \
                  --name mlops-endpoint \
                  --resource-group \$(resourceGroup) \
                  --workspace-name \$(workspaceName) \
                  --auth-mode key
                
                # Deploy model
                az ml online-deployment create \
                  --name blue-deployment \
                  --endpoint mlops-endpoint \
                  --model \$(modelName):\$BUILD_BUILDID \
                  --instance-type small-cpu-model \
                  --instance-count 2 \
                  --resource-group \$(resourceGroup) \
                  --workspace-name \$(workspaceName) \
                  --file deployment-config.yml
            displayName: 'Deploy Model to AKS'

- stage: Test
  displayName: 'Test Deployment'
  dependsOn: Deploy
  jobs:
  - job: TestEndpoint
    steps:
    - task: AzureCLI@2
      inputs:
        azureSubscription: \$(azureServiceConnection)
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          # Get endpoint details
          ENDPOINT_URI=\$(az ml online-endpoint show \
            --name mlops-endpoint \
            --resource-group \$(resourceGroup) \
            --workspace-name \$(workspaceName) \
            --query scoring_uri -o tsv)
          
          ENDPOINT_KEY=\$(az ml online-endpoint get-credentials \
            --name mlops-endpoint \
            --resource-group \$(resourceGroup) \
            --workspace-name \$(workspaceName) \
            --query primaryKey -o tsv)
          
          # Test endpoint
          curl -X POST \$ENDPOINT_URI \
            -H "Authorization: Bearer \$ENDPOINT_KEY" \
            -H "Content-Type: application/json" \
            -d '{"data": [[1,2,3,4]]}'
      displayName: 'Test Model Endpoint'
EOF
    
    log_success "Sample files created successfully"
}

# Print deployment summary
print_summary() {
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    log ""
    log "Resource Summary:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Location: ${LOCATION}"
    log "  ML Workspace: ${WORKSPACE_NAME}"
    log "  AKS Cluster: ${AKS_CLUSTER_NAME}"
    log "  Container Registry: ${ACR_NAME}"
    log "  Key Vault: ${KEYVAULT_NAME}"
    log "  Storage Account: ${STORAGE_ACCOUNT}"
    log ""
    log "Next Steps:"
    log "  1. Review the created sample files: score.py, deployment-config.yml, azure-pipelines.yml"
    log "  2. Customize the model scoring script for your specific use case"
    log "  3. Set up Azure DevOps service connection for CI/CD"
    log "  4. Deploy your first model using the ML workspace"
    log ""
    log "To verify the deployment:"
    log "  kubectl get pods -n azureml"
    log "  az ml compute list --resource-group ${RESOURCE_GROUP} --workspace-name ${WORKSPACE_NAME}"
    log ""
    log "To clean up all resources, run: ./scripts/destroy.sh"
}

# Main execution
main() {
    log "Starting Azure MLOps Pipeline deployment..."
    
    # Run deployment steps
    validate_prerequisites
    setup_environment
    create_resource_group
    create_storage_account
    create_container_registry
    create_aks_cluster
    create_supporting_services
    create_ml_workspace
    configure_ml_extension
    attach_aks_to_ml
    create_instance_types
    configure_monitoring
    create_sample_files
    print_summary
    
    log_success "Azure MLOps Pipeline deployment completed successfully!"
}

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi