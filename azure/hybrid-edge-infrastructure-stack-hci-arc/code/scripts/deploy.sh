#!/bin/bash

# Azure Edge Computing Infrastructure Deployment Script
# Recipe: Hybrid Edge Infrastructure with Stack HCI and Arc
# Version: 1.0
# Description: Deploys Azure Stack HCI cluster with Azure Arc integration

set -euo pipefail

# Enable strict error handling
trap 'echo "❌ Error occurred at line $LINENO. Exiting..." >&2; exit 1' ERR

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

# Banner
echo -e "${BLUE}"
echo "=================================================="
echo "Azure Edge Computing Infrastructure Deployment"
echo "Azure Stack HCI + Azure Arc Integration"
echo "=================================================="
echo -e "${NC}"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: $AZ_VERSION"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if kubectl is available (for AKS operations)
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl is not installed. AKS validation steps will be skipped."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random suffixes."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-edge-infrastructure}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export TENANT_ID=$(az account show --query tenantId --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export CLUSTER_NAME="hci-cluster-${RANDOM_SUFFIX}"
    export ARC_RESOURCE_NAME="arc-hci-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="edgestorage${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_WORKSPACE="la-edge-${RANDOM_SUFFIX}"
    
    log "Environment variables set:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Location: $LOCATION"
    log "  Subscription ID: $SUBSCRIPTION_ID"
    log "  Random Suffix: $RANDOM_SUFFIX"
    
    # Save variables to file for cleanup script
    cat > .env_vars << EOF
export RESOURCE_GROUP="$RESOURCE_GROUP"
export LOCATION="$LOCATION"
export SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
export TENANT_ID="$TENANT_ID"
export CLUSTER_NAME="$CLUSTER_NAME"
export ARC_RESOURCE_NAME="$ARC_RESOURCE_NAME"
export STORAGE_ACCOUNT_NAME="$STORAGE_ACCOUNT_NAME"
export LOG_ANALYTICS_WORKSPACE="$LOG_ANALYTICS_WORKSPACE"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
EOF
    
    log_success "Environment setup completed"
}

# Create foundational resources
create_foundational_resources() {
    log "Creating foundational Azure resources..."
    
    # Create resource group
    log "Creating resource group: $RESOURCE_GROUP"
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=edge-computing environment=production \
        --output none
    
    log_success "Resource group created: $RESOURCE_GROUP"
    
    # Create Log Analytics workspace
    log "Creating Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --location "$LOCATION" \
        --sku PerGB2018 \
        --output none
    
    log_success "Log Analytics workspace created: $LOG_ANALYTICS_WORKSPACE"
    
    # Create storage account
    log "Creating storage account: $STORAGE_ACCOUNT_NAME"
    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --hierarchical-namespace true \
        --output none
    
    log_success "Storage account created: $STORAGE_ACCOUNT_NAME"
    
    # Install required Azure CLI extensions
    log "Installing required Azure CLI extensions..."
    az extension add --name stack-hci --only-show-errors || true
    az extension add --name connectedmachine --only-show-errors || true
    az extension add --name k8s-extension --only-show-errors || true
    
    log_success "Foundational resources created successfully"
}

# Register resource providers
register_providers() {
    log "Registering Azure resource providers..."
    
    PROVIDERS=(
        "Microsoft.AzureStackHCI"
        "Microsoft.HybridCompute"
        "Microsoft.GuestConfiguration"
        "Microsoft.HybridConnectivity"
    )
    
    for provider in "${PROVIDERS[@]}"; do
        log "Registering provider: $provider"
        az provider register --namespace "$provider" --wait
        
        # Verify registration
        STATUS=$(az provider show --namespace "$provider" --query "registrationState" --output tsv)
        if [ "$STATUS" = "Registered" ]; then
            log_success "Provider registered: $provider"
        else
            log_warning "Provider registration pending: $provider (Status: $STATUS)"
        fi
    done
    
    log_success "Resource providers registration completed"
}

# Create Azure Stack HCI cluster
create_hci_cluster() {
    log "Creating Azure Stack HCI cluster resource..."
    
    # Create AAD application for HCI cluster
    log "Creating Azure AD application for HCI cluster..."
    AAD_APP_ID=$(az ad app create \
        --display-name "HCI-Cluster-${RANDOM_SUFFIX}" \
        --query appId --output tsv)
    
    log "AAD Application ID: $AAD_APP_ID"
    
    # Create Azure Stack HCI cluster resource
    log "Creating HCI cluster resource: $CLUSTER_NAME"
    az stack-hci cluster create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --location "$LOCATION" \
        --aad-client-id "$AAD_APP_ID" \
        --aad-tenant-id "$TENANT_ID" \
        --output none
    
    # Get cluster resource details
    CLUSTER_RESOURCE_ID=$(az stack-hci cluster show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query id --output tsv)
    
    echo "export AAD_APP_ID=\"$AAD_APP_ID\"" >> .env_vars
    echo "export CLUSTER_RESOURCE_ID=\"$CLUSTER_RESOURCE_ID\"" >> .env_vars
    
    log_success "Azure Stack HCI cluster resource created"
    log "Cluster Resource ID: $CLUSTER_RESOURCE_ID"
}

# Configure Azure Arc
configure_azure_arc() {
    log "Configuring Azure Arc for servers..."
    
    # Create service principal for Arc agent
    log "Creating service principal for Arc agent..."
    ARC_SP_CREDS=$(az ad sp create-for-rbac \
        --name "arc-servers-${RANDOM_SUFFIX}" \
        --role "Azure Connected Machine Onboarding" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        --output json)
    
    ARC_SP_ID=$(echo "$ARC_SP_CREDS" | jq -r '.appId')
    ARC_SP_SECRET=$(echo "$ARC_SP_CREDS" | jq -r '.password')
    
    log "Service Principal ID: $ARC_SP_ID"
    
    # Create Arc machine resource
    log "Creating Arc machine resource: $ARC_RESOURCE_NAME"
    az connectedmachine create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ARC_RESOURCE_NAME" \
        --location "$LOCATION" \
        --tags environment=edge role=hci-node \
        --output none
    
    echo "export ARC_SP_ID=\"$ARC_SP_ID\"" >> .env_vars
    echo "export ARC_SP_SECRET=\"$ARC_SP_SECRET\"" >> .env_vars
    
    log_success "Azure Arc configuration completed"
    log "Service Principal ID: $ARC_SP_ID"
}

# Deploy monitoring solution
deploy_monitoring() {
    log "Deploying Azure Monitor for edge infrastructure..."
    
    # Get Log Analytics workspace ID
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query customerId --output tsv)
    
    log "Log Analytics Workspace ID: $WORKSPACE_ID"
    
    # Create data collection rule for HCI monitoring
    log "Creating data collection rule for HCI monitoring..."
    az monitor data-collection rule create \
        --resource-group "$RESOURCE_GROUP" \
        --name "dcr-hci-${RANDOM_SUFFIX}" \
        --location "$LOCATION" \
        --data-flows '[{
            "streams": ["Microsoft-Event"],
            "destinations": ["'$LOG_ANALYTICS_WORKSPACE'"]
        }]' \
        --destinations '{
            "logAnalytics": [{
                "workspaceResourceId": "/subscriptions/'$SUBSCRIPTION_ID'/resourceGroups/'$RESOURCE_GROUP'/providers/Microsoft.OperationalInsights/workspaces/'$LOG_ANALYTICS_WORKSPACE'",
                "name": "'$LOG_ANALYTICS_WORKSPACE'"
            }]
        }' \
        --output none
    
    log_success "Data collection rule created"
    
    # Note: Azure Monitor agent extension for HCI clusters requires actual HCI hardware
    log_warning "Azure Monitor agent extension requires physical HCI cluster for deployment"
    
    echo "export WORKSPACE_ID=\"$WORKSPACE_ID\"" >> .env_vars
    
    log_success "Azure Monitor configuration completed"
}

# Configure governance policies
configure_governance() {
    log "Configuring Azure Policy for edge governance..."
    
    # Create custom policy for HCI compliance
    log "Creating custom HCI security policy..."
    az policy definition create \
        --name "HCI-Security-Baseline" \
        --display-name "Azure Stack HCI Security Baseline" \
        --description "Ensures HCI clusters meet security requirements" \
        --rules '{
            "if": {
                "allOf": [{
                    "field": "type",
                    "equals": "Microsoft.AzureStackHCI/clusters"
                }]
            },
            "then": {
                "effect": "audit"
            }
        }' \
        --params '{
            "effect": {
                "type": "String",
                "defaultValue": "Audit"
            }
        }' \
        --output none
    
    log_success "Custom policy created: HCI-Security-Baseline"
    
    # Assign policy to resource group
    log "Assigning HCI security policy..."
    az policy assignment create \
        --name "hci-security-assignment" \
        --display-name "HCI Security Compliance" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        --policy "HCI-Security-Baseline" \
        --output none
    
    log_success "Policy assigned: HCI Security Compliance"
    
    # Assign guest configuration policy for Arc machines
    log "Assigning guest configuration policy for Arc machines..."
    az policy assignment create \
        --name "arc-guest-config" \
        --display-name "Arc Guest Configuration" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        --policy "/providers/Microsoft.Authorization/policySetDefinitions/75714362-cae7-409e-9b99-a8e5075b7fad" \
        --output none
    
    log_success "Guest configuration policy assigned"
    
    log_success "Azure Policy configuration completed"
}

# Setup storage synchronization
setup_storage_sync() {
    log "Setting up edge storage synchronization..."
    
    # Create file share for edge synchronization
    log "Creating file share for edge synchronization..."
    az storage share create \
        --name "edge-sync" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --quota 1024 \
        --output none
    
    log_success "File share created: edge-sync"
    
    # Note: Storage Sync Service requires additional configuration for actual sync
    log_warning "Storage Sync Service requires physical servers for complete setup"
    
    # Get storage account connection string
    STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    echo "export STORAGE_CONNECTION=\"$STORAGE_CONNECTION\"" >> .env_vars
    
    log_success "Edge storage synchronization configured"
    log "Storage Account: $STORAGE_ACCOUNT_NAME"
}

# Deploy sample workloads (simulation)
deploy_sample_workloads() {
    log "Deploying sample edge workloads (simulation)..."
    
    # Note: AKS on Azure Stack HCI requires actual HCI hardware
    log_warning "AKS on Azure Stack HCI requires physical cluster for deployment"
    log "Creating simulation of edge workload deployment..."
    
    # Create a config map to simulate workload configuration
    cat > edge-workload-config.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: edge-workload-config
  namespace: edge-apps
data:
  config.yaml: |
    edge:
      cluster_name: "${CLUSTER_NAME}"
      location: "${LOCATION}"
      monitoring:
        enabled: true
        workspace_id: "${WORKSPACE_ID:-placeholder}"
    applications:
      - name: iot-processor
        type: data-processing
        replicas: 2
        resources:
          cpu: "500m"
          memory: "1Gi"
      - name: ai-inference
        type: ml-inference
        replicas: 1
        resources:
          cpu: "1000m"
          memory: "2Gi"
EOF
    
    log_success "Edge workload configuration created: edge-workload-config.yaml"
    log_success "Sample edge workloads deployment simulation completed"
}

# Validation function
validate_deployment() {
    log "Validating deployment..."
    
    # Check resource group
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_success "Resource group validation passed"
    else
        log_error "Resource group validation failed"
        return 1
    fi
    
    # Check HCI cluster
    CLUSTER_STATUS=$(az stack-hci cluster show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query "status" --output tsv 2>/dev/null || echo "NotFound")
    
    if [ "$CLUSTER_STATUS" != "NotFound" ]; then
        log_success "HCI cluster validation passed (Status: $CLUSTER_STATUS)"
    else
        log_error "HCI cluster validation failed"
        return 1
    fi
    
    # Check Arc resource
    if az connectedmachine show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ARC_RESOURCE_NAME" &> /dev/null; then
        log_success "Arc resource validation passed"
    else
        log_warning "Arc resource validation failed (expected for simulation)"
    fi
    
    # Check storage account
    if az storage account show \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_success "Storage account validation passed"
    else
        log_error "Storage account validation failed"
        return 1
    fi
    
    log_success "Deployment validation completed"
}

# Main deployment function
main() {
    local start_time=$(date +%s)
    
    echo
    log "Starting Azure Edge Computing Infrastructure deployment..."
    echo
    
    # Dry run check
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
        return 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_foundational_resources
    register_providers
    create_hci_cluster
    configure_azure_arc
    deploy_monitoring
    configure_governance
    setup_storage_sync
    deploy_sample_workloads
    validate_deployment
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo
    log_success "Deployment completed successfully!"
    log "Total deployment time: ${duration} seconds"
    echo
    log "Resource Summary:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  HCI Cluster: $CLUSTER_NAME"
    log "  Arc Resource: $ARC_RESOURCE_NAME"
    log "  Storage Account: $STORAGE_ACCOUNT_NAME"
    log "  Log Analytics: $LOG_ANALYTICS_WORKSPACE"
    echo
    log "Important Notes:"
    log "  - This deployment creates Azure resources for HCI cluster management"
    log "  - Physical Azure Stack HCI hardware is required for complete functionality"
    log "  - Review the edge-workload-config.yaml file for workload configuration"
    log "  - Environment variables saved to .env_vars for cleanup script"
    echo
    log "Next Steps:"
    log "  1. Configure physical Azure Stack HCI hardware"
    log "  2. Register physical cluster with Azure"
    log "  3. Deploy actual workloads using AKS on Azure Stack HCI"
    log "  4. Configure monitoring and governance policies"
    echo
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi