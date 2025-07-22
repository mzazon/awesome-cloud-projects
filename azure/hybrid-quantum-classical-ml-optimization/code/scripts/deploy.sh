#!/bin/bash

# Deploy script for Orchestrating Quantum-Enhanced Machine Learning Workflows
# This script deploys Azure Quantum workspace, Azure Machine Learning workspace,
# Azure Batch account, and supporting infrastructure for hybrid quantum-ML workflows

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Logging functions
log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$TIMESTAMP] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$TIMESTAMP] ✅ $1" | tee -a "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check $LOG_FILE for details."
    log "Run ./destroy.sh to clean up any partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# Start deployment
log "============================================"
log "Starting Azure Quantum-ML Workflow Deployment"
log "============================================"

# Prerequisites check
log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    log_error "Azure CLI is not installed. Please install Azure CLI first."
    exit 1
fi

# Check if logged into Azure
if ! az account show &> /dev/null; then
    log_error "Not logged into Azure. Please run 'az login' first."
    exit 1
fi

# Check if required extensions are installed
log "Checking Azure CLI extensions..."
if ! az extension list --query "[?name=='quantum']" -o tsv | grep -q quantum; then
    log "Installing Azure Quantum CLI extension..."
    az extension add --name quantum
fi

if ! az extension list --query "[?name=='ml']" -o tsv | grep -q ml; then
    log "Installing Azure ML CLI extension..."
    az extension add --name ml
fi

log_success "Prerequisites check completed"

# Environment variables with defaults
export AZURE_REGION="${AZURE_REGION:-eastus}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-quantum-ml-${RANDOM_SUFFIX}}"
export QUANTUM_WORKSPACE="${QUANTUM_WORKSPACE:-quantum-ml-ws-${RANDOM_SUFFIX}}"
export ML_WORKSPACE="${ML_WORKSPACE:-aml-quantum-ws-${RANDOM_SUFFIX}}"
export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stquantuml${RANDOM_SUFFIX}}"
export BATCH_ACCOUNT="${BATCH_ACCOUNT:-batchquantum${RANDOM_SUFFIX}}"
export KEY_VAULT="${KEY_VAULT:-kv-quantum-${RANDOM_SUFFIX}}"

# Validate resource names
log "Validating resource names..."
if [[ ${#STORAGE_ACCOUNT} -gt 24 ]]; then
    export STORAGE_ACCOUNT="stquantuml$(echo $RANDOM_SUFFIX | cut -c1-6)"
    log "Storage account name truncated to: $STORAGE_ACCOUNT"
fi

if [[ ${#KEY_VAULT} -gt 24 ]]; then
    export KEY_VAULT="kv-quantum-$(echo $RANDOM_SUFFIX | cut -c1-8)"
    log "Key Vault name truncated to: $KEY_VAULT"
fi

# Display configuration
log "Deployment Configuration:"
log "  Region: $AZURE_REGION"
log "  Resource Group: $RESOURCE_GROUP"
log "  Quantum Workspace: $QUANTUM_WORKSPACE"
log "  ML Workspace: $ML_WORKSPACE"
log "  Storage Account: $STORAGE_ACCOUNT"
log "  Batch Account: $BATCH_ACCOUNT"
log "  Key Vault: $KEY_VAULT"

# Save configuration for cleanup script
cat > "${SCRIPT_DIR}/deployment.conf" << EOF
AZURE_REGION=$AZURE_REGION
RESOURCE_GROUP=$RESOURCE_GROUP
QUANTUM_WORKSPACE=$QUANTUM_WORKSPACE
ML_WORKSPACE=$ML_WORKSPACE
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
BATCH_ACCOUNT=$BATCH_ACCOUNT
KEY_VAULT=$KEY_VAULT
RANDOM_SUFFIX=$RANDOM_SUFFIX
DEPLOYMENT_TIMESTAMP=$TIMESTAMP
EOF

log_success "Configuration saved to deployment.conf"

# Step 1: Create Resource Group
log "Creating resource group..."
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$AZURE_REGION" \
    --tags purpose="quantum-ml-demo" environment="development" creator="deploy-script" \
    --output table

log_success "Resource group created: $RESOURCE_GROUP"

# Step 2: Create Storage Account with Data Lake capabilities
log "Creating Azure Data Lake Storage account..."
az storage account create \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$AZURE_REGION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --hierarchical-namespace true \
    --tags purpose="quantum-ml-data" \
    --output table

# Wait for storage account to be ready
log "Waiting for storage account to be fully provisioned..."
sleep 30

log_success "Azure Data Lake Storage account created: $STORAGE_ACCOUNT"

# Step 3: Create Key Vault
log "Creating Azure Key Vault..."
az keyvault create \
    --name "$KEY_VAULT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$AZURE_REGION" \
    --sku standard \
    --tags purpose="quantum-ml-secrets" \
    --output table

log_success "Azure Key Vault created: $KEY_VAULT"

# Step 4: Create Azure Quantum Workspace
log "Creating Azure Quantum workspace..."
az quantum workspace create \
    --name "$QUANTUM_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$AZURE_REGION" \
    --sku Basic \
    --provider-sku-list ionq.simulator=free quantinuum.sim.h1-1sc=free microsoft.simulator=free \
    --tags purpose="quantum-computing" environment="development" \
    --output table

# Get quantum workspace connection details
QUANTUM_CONNECTION=$(az quantum workspace show \
    --name "$QUANTUM_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --query "id" -o tsv)

log_success "Azure Quantum workspace created with connection: $QUANTUM_CONNECTION"

# Step 5: Create Azure Machine Learning Workspace
log "Creating Azure Machine Learning workspace..."
az ml workspace create \
    --name "$ML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$AZURE_REGION" \
    --storage-account "$STORAGE_ACCOUNT" \
    --key-vault "$KEY_VAULT" \
    --tags purpose="quantum-enhanced-ml" \
    --output table

log_success "Azure ML workspace created: $ML_WORKSPACE"

# Step 6: Create ML Compute Resources
log "Creating Azure ML compute instance..."
az ml compute create \
    --name quantum-ml-compute \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$ML_WORKSPACE" \
    --type ComputeInstance \
    --size Standard_DS3_v2 \
    --output table

log "Creating Azure ML compute cluster..."
az ml compute create \
    --name quantum-ml-cluster \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$ML_WORKSPACE" \
    --type AmlCompute \
    --size Standard_DS3_v2 \
    --min-instances 0 \
    --max-instances 4 \
    --output table

log_success "Azure ML compute resources created"

# Step 7: Create Azure Batch Account
log "Creating Azure Batch account..."
az batch account create \
    --name "$BATCH_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$AZURE_REGION" \
    --storage-account "$STORAGE_ACCOUNT" \
    --tags purpose="quantum-job-orchestration" \
    --output table

# Get Batch account keys and store securely
log "Securing Batch account credentials..."
BATCH_KEY=$(az batch account keys list \
    --name "$BATCH_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query primary -o tsv)

az keyvault secret set \
    --vault-name "$KEY_VAULT" \
    --name "batch-account-key" \
    --value "$BATCH_KEY" \
    --output none

log_success "Azure Batch account created and credentials secured"

# Step 8: Create quantum development directory structure
log "Creating quantum development directory structure..."
mkdir -p "${SCRIPT_DIR}/../quantum-ml-pipeline/components/quantum-feature-map"
mkdir -p "${SCRIPT_DIR}/../quantum-ml-pipeline/components/quantum-hyperparam"
mkdir -p "${SCRIPT_DIR}/../quantum-ml-pipeline/deployment/inference"
mkdir -p "${SCRIPT_DIR}/../quantum-ml-pipeline/deployment/environment"

# Create sample Q# quantum feature mapping program
cat > "${SCRIPT_DIR}/../quantum-ml-pipeline/components/quantum-feature-map/QuantumFeatureMap.qs" << 'EOF'
namespace QuantumML {
    open Microsoft.Quantum.Canon;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Arrays;
    
    @EntryPoint()
    operation QuantumFeatureMap(data : Double[], depth : Int) : Double[] {
        let nQubits = 4;
        use qubits = Qubit[nQubits];
        
        // Encode classical data into quantum state
        for i in 0..Length(data)-1 {
            let angle = data[i] * PI();
            Ry(angle, qubits[i % nQubits]);
        }
        
        // Apply entangling layers
        for d in 0..depth-1 {
            ApplyToEach(H, qubits);
            for i in 0..nQubits-2 {
                CNOT(qubits[i], qubits[i+1]);
            }
        }
        
        // Measure and return quantum features
        mutable results = [];
        for qubit in qubits {
            set results += [IntAsDouble(ResultArrayAsInt([M(qubit)]))];
        }
        
        ResetAll(qubits);
        return results;
    }
}
EOF

log_success "Quantum development structure created"

# Step 9: Store deployment information in Key Vault
log "Storing deployment configuration in Key Vault..."
az keyvault secret set \
    --vault-name "$KEY_VAULT" \
    --name "quantum-workspace-id" \
    --value "$QUANTUM_CONNECTION" \
    --output none

az keyvault secret set \
    --vault-name "$KEY_VAULT" \
    --name "ml-workspace-name" \
    --value "$ML_WORKSPACE" \
    --output none

az keyvault secret set \
    --vault-name "$KEY_VAULT" \
    --name "deployment-config" \
    --value "$(cat ${SCRIPT_DIR}/deployment.conf)" \
    --output none

log_success "Deployment configuration secured in Key Vault"

# Step 10: Validation checks
log "Running deployment validation..."

# Check Quantum workspace status
QUANTUM_STATUS=$(az quantum workspace show \
    --name "$QUANTUM_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --query "provisioningState" -o tsv)

if [[ "$QUANTUM_STATUS" != "Succeeded" ]]; then
    log_error "Quantum workspace provisioning failed. Status: $QUANTUM_STATUS"
    exit 1
fi

# Check ML workspace status
ML_STATUS=$(az ml workspace show \
    --name "$ML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --query "provisioning_state" -o tsv)

if [[ "$ML_STATUS" != "Succeeded" ]]; then
    log_error "ML workspace provisioning failed. Status: $ML_STATUS"
    exit 1
fi

# List available quantum providers
log "Available quantum providers:"
az quantum target list \
    --workspace-name "$QUANTUM_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --output table

log_success "Deployment validation completed"

# Final summary
log "============================================"
log "DEPLOYMENT COMPLETED SUCCESSFULLY"
log "============================================"
log ""
log "Resource Summary:"
log "  Resource Group: $RESOURCE_GROUP"
log "  Azure Quantum Workspace: $QUANTUM_WORKSPACE"
log "  Azure ML Workspace: $ML_WORKSPACE"
log "  Storage Account: $STORAGE_ACCOUNT"
log "  Batch Account: $BATCH_ACCOUNT"
log "  Key Vault: $KEY_VAULT"
log ""
log "Next Steps:"
log "1. Access Azure ML Studio: https://ml.azure.com"
log "2. Access Azure Quantum workspace in Azure Portal"
log "3. Upload training data to the Data Lake Storage account"
log "4. Deploy the quantum-enhanced ML pipeline"
log ""
log "To clean up resources, run: ./destroy.sh"
log "Configuration saved in: deployment.conf"
log ""
log "Estimated monthly cost: ~$50-100 (varies with usage)"
log "Note: Free quantum simulator credits are included"

# Make the script executable (if not already)
chmod +x "$0"

log_success "Deployment script completed at $TIMESTAMP"