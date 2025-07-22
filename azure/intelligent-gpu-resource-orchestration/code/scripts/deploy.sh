#!/bin/bash

#################################################################
# Azure GPU Orchestration Deployment Script
# Recipe: Orchestrating Dynamic GPU Resource Allocation with 
#         Azure Container Apps and Azure Batch
# 
# This script deploys the complete GPU orchestration solution
# including Container Apps, Batch pools, monitoring, and
# configuration management components.
#################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
    MIN_VERSION="2.57.0"
    if ! printf '%s\n' "$MIN_VERSION" "$AZ_VERSION" | sort -V -C; then
        log_error "Azure CLI version $AZ_VERSION is below minimum required version $MIN_VERSION"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is required for generating random suffixes."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Core resource configuration
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-gpu-orchestration}"
    export LOCATION="${LOCATION:-westus3}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
        log "Generated random suffix: $RANDOM_SUFFIX"
    fi
    
    # Set resource names with unique suffix
    export ACA_ENVIRONMENT="aca-env-${RANDOM_SUFFIX}"
    export ACA_APP="ml-inference-app"
    export BATCH_ACCOUNT="batch${RANDOM_SUFFIX}"
    export BATCH_POOL="gpu-pool"
    export KEY_VAULT="kv-gpu-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="storage${RANDOM_SUFFIX}"
    export LOG_WORKSPACE="logs-gpu-${RANDOM_SUFFIX}"
    export FUNCTION_APP="router-func-${RANDOM_SUFFIX}"
    
    # Validate location supports required services
    SUPPORTED_LOCATIONS=("westus3" "eastus" "westeurope" "australiaeast")
    if [[ ! " ${SUPPORTED_LOCATIONS[@]} " =~ " ${LOCATION} " ]]; then
        log_warning "Location $LOCATION may not support all GPU features. Recommended: ${SUPPORTED_LOCATIONS[*]}"
    fi
    
    log_success "Environment variables configured"
    log "Resource Group: $RESOURCE_GROUP"
    log "Location: $LOCATION"
    log "Random Suffix: $RANDOM_SUFFIX"
}

# Function to check quota and permissions
check_quotas() {
    log "Checking Azure quotas and permissions..."
    
    # Check GPU quota for Container Apps (this is informational as quota APIs are limited)
    log_warning "Please ensure you have requested GPU quota for Azure Container Apps and Batch"
    log_warning "GPU quota requests can be submitted through Azure Support"
    
    # Check if we can create resources in the subscription
    if ! az group list --query "[0].id" -o tsv &> /dev/null; then
        log_error "Insufficient permissions to list resource groups"
        exit 1
    fi
    
    log_success "Quota and permissions check completed"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=gpu-orchestration environment=demo \
            > /dev/null
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create Log Analytics workspace
create_log_analytics() {
    log "Creating Log Analytics workspace: $LOG_WORKSPACE..."
    
    if az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_WORKSPACE" &> /dev/null; then
        log_warning "Log Analytics workspace $LOG_WORKSPACE already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_WORKSPACE" \
            --location "$LOCATION" \
            > /dev/null
        
        log_success "Log Analytics workspace created: $LOG_WORKSPACE"
    fi
    
    # Get workspace ID for later use
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_WORKSPACE" \
        --query customerId --output tsv)
    
    log "Workspace ID: $WORKSPACE_ID"
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account: $STORAGE_ACCOUNT..."
    
    if az storage account show \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Storage account $STORAGE_ACCOUNT already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            > /dev/null
        
        log_success "Storage account created: $STORAGE_ACCOUNT"
    fi
    
    # Get connection string
    export STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
}

# Function to create Key Vault
create_key_vault() {
    log "Creating Key Vault: $KEY_VAULT..."
    
    if az keyvault show --name "$KEY_VAULT" &> /dev/null; then
        log_warning "Key Vault $KEY_VAULT already exists"
    else
        az keyvault create \
            --name "$KEY_VAULT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku standard \
            --enable-rbac-authorization true \
            > /dev/null
        
        log_success "Key Vault created: $KEY_VAULT"
    fi
    
    # Get current user's object ID for RBAC assignment
    USER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv)
    
    # Check if role assignment already exists
    VAULT_ID=$(az keyvault show --name "$KEY_VAULT" \
        --resource-group "$RESOURCE_GROUP" --query id --output tsv)
    
    if ! az role assignment list \
        --assignee "$USER_OBJECT_ID" \
        --scope "$VAULT_ID" \
        --role "Key Vault Secrets Officer" &> /dev/null; then
        
        az role assignment create \
            --role "Key Vault Secrets Officer" \
            --assignee "$USER_OBJECT_ID" \
            --scope "$VAULT_ID" \
            > /dev/null
        
        log_success "Key Vault RBAC assignment created"
    else
        log_warning "Key Vault RBAC assignment already exists"
    fi
}

# Function to create Azure Batch account and pool
create_batch_resources() {
    log "Creating Azure Batch account: $BATCH_ACCOUNT..."
    
    if az batch account show \
        --name "$BATCH_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Batch account $BATCH_ACCOUNT already exists"
    else
        az batch account create \
            --name "$BATCH_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --storage-account "$STORAGE_ACCOUNT" \
            > /dev/null
        
        log_success "Batch account created: $BATCH_ACCOUNT"
    fi
    
    # Set Batch account for subsequent commands
    az batch account set \
        --name "$BATCH_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP"
    
    log "Creating GPU pool: $BATCH_POOL..."
    
    # Check if pool already exists
    if az batch pool show --pool-id "$BATCH_POOL" &> /dev/null; then
        log_warning "Batch pool $BATCH_POOL already exists"
    else
        # Create GPU pool configuration
        cat > /tmp/batch-pool-config.json << EOF
{
    "id": "${BATCH_POOL}",
    "displayName": "GPU Processing Pool",
    "vmSize": "Standard_NC6s_v3",
    "virtualMachineConfiguration": {
        "imageReference": {
            "publisher": "microsoft-azure-batch",
            "offer": "ubuntu-server-container",
            "sku": "20-04-lts",
            "version": "latest"
        },
        "nodeAgentSkuId": "batch.node.ubuntu 20.04"
    },
    "targetDedicatedNodes": 0,
    "targetLowPriorityNodes": 2,
    "enableAutoScale": true,
    "autoScaleFormula": "\\$TargetDedicatedNodes = min(\\$PendingTasks.GetSample(180 * TimeInterval_Second, 70 * TimeInterval_Second), 4);",
    "autoScaleEvaluationInterval": "PT5M",
    "enableInterNodeCommunication": false,
    "taskSlotsPerNode": 1,
    "applicationPackageReferences": [],
    "startTask": {
        "commandLine": "apt-get update && apt-get install -y python3-pip && pip3 install azure-storage-queue torch torchvision",
        "userIdentity": {
            "autoUser": {
                "scope": "pool",
                "elevationLevel": "admin"
            }
        },
        "waitForSuccess": true
    }
}
EOF
        
        az batch pool create --json-file /tmp/batch-pool-config.json > /dev/null
        rm /tmp/batch-pool-config.json
        
        log_success "Batch GPU pool created with auto-scaling: $BATCH_POOL"
    fi
}

# Function to create Container Apps environment
create_container_apps_environment() {
    log "Creating Container Apps environment: $ACA_ENVIRONMENT..."
    
    if az containerapp env show \
        --name "$ACA_ENVIRONMENT" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Container Apps environment $ACA_ENVIRONMENT already exists"
    else
        # Get Log Analytics workspace key
        WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_WORKSPACE" \
            --query primarySharedKey --output tsv)
        
        az containerapp env create \
            --name "$ACA_ENVIRONMENT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --logs-workspace-id "$WORKSPACE_ID" \
            --logs-workspace-key "$WORKSPACE_KEY" \
            > /dev/null
        
        log_success "Container Apps environment created: $ACA_ENVIRONMENT"
    fi
    
    # Check GPU workload profile availability
    log "Checking GPU workload profile availability..."
    GPU_PROFILES=$(az containerapp env workload-profile list-supported \
        --location "$LOCATION" \
        --query "[?contains(category, 'GPU')].name" \
        --output tsv | wc -l)
    
    if [ "$GPU_PROFILES" -gt 0 ]; then
        log_success "GPU workload profiles available in $LOCATION"
    else
        log_warning "No GPU workload profiles found in $LOCATION"
    fi
}

# Function to deploy ML inference Container App
deploy_container_app() {
    log "Deploying ML inference Container App: $ACA_APP..."
    
    if az containerapp show \
        --name "$ACA_APP" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Container App $ACA_APP already exists"
    else
        az containerapp create \
            --name "$ACA_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --environment "$ACA_ENVIRONMENT" \
            --image "mcr.microsoft.com/azuredocs/aci-tutorial-app" \
            --target-port 80 \
            --ingress external \
            --cpu 2.0 \
            --memory 4Gi \
            --workload-profile-name "Consumption" \
            --min-replicas 0 \
            --max-replicas 10 \
            > /dev/null
        
        log_success "Container App created: $ACA_APP"
    fi
    
    # Update app configuration
    log "Updating Container App configuration..."
    az containerapp update \
        --name "$ACA_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --container-name "$ACA_APP" \
        --set-env-vars "MODEL_PATH=/models" "GPU_ENABLED=true" \
        --cpu 4.0 \
        --memory 8Gi \
        > /dev/null
    
    # Get the Container App URL
    export ACA_URL=$(az containerapp show \
        --name "$ACA_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.configuration.ingress.fqdn \
        --output tsv)
    
    log_success "ML inference Container App deployed: https://$ACA_URL"
}

# Function to create storage queues
create_storage_queues() {
    log "Creating storage queues for batch job management..."
    
    # Create storage queue for batch jobs
    if ! az storage queue show \
        --name "batch-inference-queue" \
        --connection-string "$STORAGE_CONNECTION_STRING" &> /dev/null; then
        
        az storage queue create \
            --name "batch-inference-queue" \
            --connection-string "$STORAGE_CONNECTION_STRING" \
            > /dev/null
        
        log_success "Created batch inference queue"
    else
        log_warning "Batch inference queue already exists"
    fi
    
    # Create dead letter queue for failed jobs
    if ! az storage queue show \
        --name "batch-inference-dlq" \
        --connection-string "$STORAGE_CONNECTION_STRING" &> /dev/null; then
        
        az storage queue create \
            --name "batch-inference-dlq" \
            --connection-string "$STORAGE_CONNECTION_STRING" \
            > /dev/null
        
        log_success "Created dead letter queue"
    else
        log_warning "Dead letter queue already exists"
    fi
    
    # Store connection string in Key Vault
    az keyvault secret set \
        --vault-name "$KEY_VAULT" \
        --name "storage-connection-string" \
        --value "$STORAGE_CONNECTION_STRING" \
        > /dev/null
    
    log_success "Storage connection string stored in Key Vault"
}

# Function to deploy Function App
deploy_function_app() {
    log "Deploying Function App: $FUNCTION_APP..."
    
    if az functionapp show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Function App $FUNCTION_APP already exists"
    else
        az functionapp create \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --storage-account "$STORAGE_ACCOUNT" \
            --consumption-plan-location "$LOCATION" \
            --runtime python \
            --runtime-version 3.11 \
            --functions-version 4 \
            --assign-identity [system] \
            > /dev/null
        
        log_success "Function App created: $FUNCTION_APP"
    fi
    
    # Get Function App managed identity
    FUNCTION_IDENTITY=$(az functionapp identity show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId --output tsv)
    
    # Grant Key Vault access to Function App
    VAULT_ID=$(az keyvault show --name "$KEY_VAULT" \
        --resource-group "$RESOURCE_GROUP" --query id --output tsv)
    
    if ! az role assignment list \
        --assignee "$FUNCTION_IDENTITY" \
        --scope "$VAULT_ID" \
        --role "Key Vault Secrets User" &> /dev/null; then
        
        az role assignment create \
            --role "Key Vault Secrets User" \
            --assignee "$FUNCTION_IDENTITY" \
            --scope "$VAULT_ID" \
            > /dev/null
        
        log_success "Key Vault access granted to Function App"
    else
        log_warning "Function App already has Key Vault access"
    fi
    
    # Configure Function App settings
    log "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
            "KEY_VAULT_URL=https://${KEY_VAULT}.vault.azure.net/" \
            "ACA_ENDPOINT=https://${ACA_URL}" \
            "BATCH_ACCOUNT_NAME=${BATCH_ACCOUNT}" \
            "BATCH_POOL_ID=${BATCH_POOL}" \
            "STORAGE_QUEUE_NAME=batch-inference-queue" \
            "LOG_ANALYTICS_WORKSPACE_ID=${WORKSPACE_ID}" \
        > /dev/null
    
    log_success "Function App configuration completed"
}

# Function to configure monitoring and alerts
configure_monitoring() {
    log "Configuring Azure Monitor metrics and alerts..."
    
    # Get Container App resource ID
    ACA_RESOURCE_ID=$(az containerapp show --name "$ACA_APP" \
        --resource-group "$RESOURCE_GROUP" --query id --output tsv)
    
    # Create alert for high GPU utilization
    if ! az monitor metrics alert show \
        --name "HighGPUUtilization" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        
        az monitor metrics alert create \
            --name "HighGPUUtilization" \
            --resource-group "$RESOURCE_GROUP" \
            --scopes "$ACA_RESOURCE_ID" \
            --condition "avg Requests > 50" \
            --description "High GPU utilization detected" \
            --evaluation-frequency 1m \
            --window-size 5m \
            --severity 2 \
            > /dev/null
        
        log_success "High GPU utilization alert created"
    else
        log_warning "High GPU utilization alert already exists"
    fi
    
    # Get Storage Account resource ID
    STORAGE_RESOURCE_ID=$(az storage account show --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" --query id --output tsv)
    
    # Create alert for batch queue depth
    if ! az monitor metrics alert show \
        --name "HighBatchQueueDepth" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        
        az monitor metrics alert create \
            --name "HighBatchQueueDepth" \
            --resource-group "$RESOURCE_GROUP" \
            --scopes "$STORAGE_RESOURCE_ID" \
            --condition "avg ApproximateMessageCount > 100" \
            --description "High batch queue depth detected" \
            --evaluation-frequency 1m \
            --window-size 5m \
            --severity 3 \
            > /dev/null
        
        log_success "High batch queue depth alert created"
    else
        log_warning "High batch queue depth alert already exists"
    fi
    
    # Create cost optimization alert
    if ! az monitor metrics alert show \
        --name "HighGPUCost" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        
        az monitor metrics alert create \
            --name "HighGPUCost" \
            --resource-group "$RESOURCE_GROUP" \
            --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
            --condition "avg Microsoft.Consumption/usageDetails > 100" \
            --description "GPU costs exceeding threshold" \
            --evaluation-frequency 1h \
            --window-size 6h \
            --severity 1 \
            > /dev/null
        
        log_success "High GPU cost alert created"
    else
        log_warning "High GPU cost alert already exists"
    fi
    
    log_success "Monitoring alerts configured for GPU optimization"
}

# Function to store configuration parameters
store_configuration() {
    log "Storing configuration parameters in Key Vault..."
    
    # Store routing configuration parameters
    az keyvault secret set \
        --vault-name "$KEY_VAULT" \
        --name "realtime-threshold-ms" \
        --value "2000" \
        > /dev/null
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT" \
        --name "batch-cost-threshold" \
        --value "0.50" \
        > /dev/null
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT" \
        --name "max-aca-replicas" \
        --value "10" \
        > /dev/null
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT" \
        --name "max-batch-nodes" \
        --value "4" \
        > /dev/null
    
    # Store ML model configuration
    az keyvault secret set \
        --vault-name "$KEY_VAULT" \
        --name "model-version" \
        --value "v1.0" \
        > /dev/null
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT" \
        --name "gpu-memory-limit" \
        --value "16384" \
        > /dev/null
    
    log_success "Configuration parameters stored in Key Vault"
}

# Function to display deployment summary
display_summary() {
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo ""
    log "Resource Summary:"
    log "├── Resource Group: $RESOURCE_GROUP"
    log "├── Container Apps Environment: $ACA_ENVIRONMENT"
    log "├── ML Inference App: $ACA_APP"
    log "├── App URL: https://$ACA_URL"
    log "├── Batch Account: $BATCH_ACCOUNT"
    log "├── GPU Pool: $BATCH_POOL"
    log "├── Key Vault: $KEY_VAULT"
    log "├── Storage Account: $STORAGE_ACCOUNT"
    log "├── Function App: $FUNCTION_APP"
    log "└── Log Analytics: $LOG_WORKSPACE"
    echo ""
    
    # Save deployment info for cleanup script
    cat > /tmp/azure-gpu-deployment-info.env << EOF
export RESOURCE_GROUP="$RESOURCE_GROUP"
export LOCATION="$LOCATION"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
export ACA_ENVIRONMENT="$ACA_ENVIRONMENT"
export ACA_APP="$ACA_APP"
export BATCH_ACCOUNT="$BATCH_ACCOUNT"
export BATCH_POOL="$BATCH_POOL"
export KEY_VAULT="$KEY_VAULT"
export STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
export LOG_WORKSPACE="$LOG_WORKSPACE"
export FUNCTION_APP="$FUNCTION_APP"
export ACA_URL="$ACA_URL"
EOF
    
    log_success "Deployment information saved to /tmp/azure-gpu-deployment-info.env"
    log_warning "Next steps:"
    log "1. Test the Container App endpoint: curl https://$ACA_URL"
    log "2. Monitor GPU utilization in Azure Monitor"
    log "3. Configure custom ML models in your container images"
    log "4. Set up Function App code for request routing logic"
    log ""
    log_warning "Remember to run the cleanup script when done to avoid ongoing charges!"
}

# Function to run validation tests
run_validation() {
    log "Running deployment validation tests..."
    
    # Test Container App endpoint
    if curl -s --max-time 30 "https://$ACA_URL" > /dev/null; then
        log_success "Container App endpoint is accessible"
    else
        log_warning "Container App endpoint test failed (may take time to warm up)"
    fi
    
    # Check Batch pool status
    POOL_STATE=$(az batch pool show \
        --pool-id "$BATCH_POOL" \
        --query "state" --output tsv 2>/dev/null || echo "unknown")
    
    if [ "$POOL_STATE" = "active" ]; then
        log_success "Batch pool is active"
    else
        log_warning "Batch pool state: $POOL_STATE (may still be initializing)"
    fi
    
    # Test Key Vault access
    if az keyvault secret show \
        --vault-name "$KEY_VAULT" \
        --name "realtime-threshold-ms" \
        --query value --output tsv > /dev/null 2>&1; then
        log_success "Key Vault access verified"
    else
        log_warning "Key Vault access test failed"
    fi
    
    log_success "Validation tests completed"
}

# Main deployment function
main() {
    log "=== Starting Azure GPU Orchestration Deployment ==="
    log "Timestamp: $(date)"
    
    # Check for dry run mode
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_warning "DRY RUN MODE - No resources will be created"
        return 0
    fi
    
    check_prerequisites
    setup_environment
    check_quotas
    
    log "=== Phase 1: Core Infrastructure ==="
    create_resource_group
    create_log_analytics
    create_storage_account
    
    log "=== Phase 2: Security and Configuration ==="
    create_key_vault
    store_configuration
    
    log "=== Phase 3: Compute Resources ==="
    create_batch_resources
    create_container_apps_environment
    deploy_container_app
    
    log "=== Phase 4: Integration Components ==="
    create_storage_queues
    deploy_function_app
    
    log "=== Phase 5: Monitoring and Alerts ==="
    configure_monitoring
    
    log "=== Phase 6: Validation ==="
    run_validation
    
    display_summary
    
    log_success "=== DEPLOYMENT COMPLETED ==="
}

# Handle script interruption
trap 'log_error "Deployment interrupted. Some resources may have been created."; exit 1' INT TERM

# Run main function
main "$@"