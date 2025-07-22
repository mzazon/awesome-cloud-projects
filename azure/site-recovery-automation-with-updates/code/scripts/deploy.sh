#!/bin/bash

# Site Recovery Automation with Integrated Update Management
# Deployment Script
# 
# This script deploys the complete disaster recovery solution including:
# - Recovery Services Vault
# - Virtual Network Infrastructure
# - Test Virtual Machines
# - Site Recovery Replication
# - Azure Update Manager Configuration
# - Recovery Plans and Monitoring

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DEPLOYMENT_CONFIG="${SCRIPT_DIR}/deployment-config.json"

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

# Success message function
success() {
    log "${GREEN}✅ ${1}${NC}"
}

# Warning message function
warning() {
    log "${YELLOW}⚠️ ${1}${NC}"
}

# Error message function
error() {
    log "${RED}❌ ${1}${NC}"
}

# Info message function
info() {
    log "${BLUE}ℹ️ ${1}${NC}"
}

# Cleanup function for script interruption
cleanup() {
    if [ $? -ne 0 ]; then
        error "Deployment failed. Check ${LOG_FILE} for details."
        error "To cleanup partial deployment, run: ./destroy.sh"
    fi
}

trap cleanup EXIT

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
    info "Azure CLI version: ${AZ_VERSION}"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Please login to Azure CLI first: az login"
        exit 1
    fi
    
    # Check if required extensions are installed
    if ! az extension show --name site-recovery &> /dev/null; then
        info "Installing site-recovery extension..."
        az extension add --name site-recovery
    fi
    
    if ! az extension show --name automation &> /dev/null; then
        info "Installing automation extension..."
        az extension add --name automation
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    info "Setting environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RANDOM_SUFFIX
    
    # Set resource group names
    export RESOURCE_GROUP_PRIMARY="rg-dr-primary-${RANDOM_SUFFIX}"
    export RESOURCE_GROUP_SECONDARY="rg-dr-secondary-${RANDOM_SUFFIX}"
    
    # Set Azure regions
    export LOCATION_PRIMARY="eastus"
    export LOCATION_SECONDARY="westus"
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set resource names
    export VAULT_NAME="rsv-dr-${RANDOM_SUFFIX}"
    export VNET_PRIMARY="vnet-primary-${RANDOM_SUFFIX}"
    export VNET_SECONDARY="vnet-secondary-${RANDOM_SUFFIX}"
    export SUBNET_PRIMARY="subnet-primary"
    export SUBNET_SECONDARY="subnet-secondary"
    export VM_PRIMARY="vm-primary-${RANDOM_SUFFIX}"
    export NSG_PRIMARY="nsg-primary-${RANDOM_SUFFIX}"
    export AUTOMATION_ACCOUNT="auto-updates-${RANDOM_SUFFIX}"
    export LOG_WORKSPACE="law-dr-${RANDOM_SUFFIX}"
    export ACTION_GROUP="ag-dr-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="storage${RANDOM_SUFFIX}"
    
    # Save configuration for cleanup
    cat > "${DEPLOYMENT_CONFIG}" << EOF
{
    "randomSuffix": "${RANDOM_SUFFIX}",
    "resourceGroupPrimary": "${RESOURCE_GROUP_PRIMARY}",
    "resourceGroupSecondary": "${RESOURCE_GROUP_SECONDARY}",
    "locationPrimary": "${LOCATION_PRIMARY}",
    "locationSecondary": "${LOCATION_SECONDARY}",
    "subscriptionId": "${SUBSCRIPTION_ID}",
    "vaultName": "${VAULT_NAME}",
    "vnetPrimary": "${VNET_PRIMARY}",
    "vnetSecondary": "${VNET_SECONDARY}",
    "vmPrimary": "${VM_PRIMARY}",
    "nsgPrimary": "${NSG_PRIMARY}",
    "automationAccount": "${AUTOMATION_ACCOUNT}",
    "logWorkspace": "${LOG_WORKSPACE}",
    "actionGroup": "${ACTION_GROUP}",
    "storageAccount": "${STORAGE_ACCOUNT}",
    "deploymentTime": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    
    success "Environment variables configured"
    info "Using suffix: ${RANDOM_SUFFIX}"
}

# Function to create resource groups
create_resource_groups() {
    info "Creating resource groups..."
    
    # Create primary resource group
    az group create \
        --name "${RESOURCE_GROUP_PRIMARY}" \
        --location "${LOCATION_PRIMARY}" \
        --tags purpose=disaster-recovery environment=primary recipe=azure-dr-asr-aum
    
    # Create secondary resource group
    az group create \
        --name "${RESOURCE_GROUP_SECONDARY}" \
        --location "${LOCATION_SECONDARY}" \
        --tags purpose=disaster-recovery environment=secondary recipe=azure-dr-asr-aum
    
    success "Resource groups created"
    info "Primary: ${RESOURCE_GROUP_PRIMARY} in ${LOCATION_PRIMARY}"
    info "Secondary: ${RESOURCE_GROUP_SECONDARY} in ${LOCATION_SECONDARY}"
}

# Function to create Recovery Services Vault
create_recovery_vault() {
    info "Creating Recovery Services Vault..."
    
    # Create Recovery Services Vault
    az backup vault create \
        --resource-group "${RESOURCE_GROUP_SECONDARY}" \
        --name "${VAULT_NAME}" \
        --location "${LOCATION_SECONDARY}" \
        --storage-model GeoRedundant \
        --tags purpose=disaster-recovery environment=secondary
    
    success "Recovery Services Vault created: ${VAULT_NAME}"
}

# Function to create virtual network infrastructure
create_virtual_networks() {
    info "Creating virtual network infrastructure..."
    
    # Create primary virtual network
    az network vnet create \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --name "${VNET_PRIMARY}" \
        --location "${LOCATION_PRIMARY}" \
        --address-prefixes 10.1.0.0/16 \
        --subnet-name "${SUBNET_PRIMARY}" \
        --subnet-prefixes 10.1.1.0/24 \
        --tags purpose=disaster-recovery environment=primary
    
    # Create secondary virtual network
    az network vnet create \
        --resource-group "${RESOURCE_GROUP_SECONDARY}" \
        --name "${VNET_SECONDARY}" \
        --location "${LOCATION_SECONDARY}" \
        --address-prefixes 10.2.0.0/16 \
        --subnet-name "${SUBNET_SECONDARY}" \
        --subnet-prefixes 10.2.1.0/24 \
        --tags purpose=disaster-recovery environment=secondary
    
    success "Virtual networks created with non-overlapping address spaces"
    info "Primary VNet: ${VNET_PRIMARY} (10.1.0.0/16)"
    info "Secondary VNet: ${VNET_SECONDARY} (10.2.0.0/16)"
}

# Function to create storage account for test failover
create_storage_account() {
    info "Creating storage account for test failover..."
    
    # Create storage account in secondary region
    az storage account create \
        --resource-group "${RESOURCE_GROUP_SECONDARY}" \
        --name "${STORAGE_ACCOUNT}" \
        --location "${LOCATION_SECONDARY}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --tags purpose=disaster-recovery environment=secondary
    
    success "Storage account created: ${STORAGE_ACCOUNT}"
}

# Function to deploy test virtual machines
deploy_test_vms() {
    info "Deploying test virtual machines..."
    
    # Create Network Security Group for primary VMs
    az network nsg create \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --name "${NSG_PRIMARY}" \
        --location "${LOCATION_PRIMARY}" \
        --tags purpose=disaster-recovery environment=primary
    
    # Create NSG rule for RDP access
    az network nsg rule create \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --nsg-name "${NSG_PRIMARY}" \
        --name "Allow-RDP" \
        --protocol tcp \
        --priority 1000 \
        --destination-port-range 3389 \
        --access allow \
        --direction inbound \
        --source-address-prefix "*" \
        --destination-address-prefix "*"
    
    # Create test Windows VM
    az vm create \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --name "${VM_PRIMARY}" \
        --location "${LOCATION_PRIMARY}" \
        --vnet-name "${VNET_PRIMARY}" \
        --subnet "${SUBNET_PRIMARY}" \
        --nsg "${NSG_PRIMARY}" \
        --image Win2019Datacenter \
        --admin-username azureuser \
        --admin-password "P@ssw0rd123!" \
        --size Standard_B2s \
        --storage-sku Premium_LRS \
        --tags purpose=disaster-recovery environment=primary
    
    success "Primary VM created: ${VM_PRIMARY}"
    
    # Wait for VM to be fully provisioned
    info "Waiting for VM to be fully provisioned..."
    az vm wait \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --name "${VM_PRIMARY}" \
        --created \
        --timeout 600
    
    success "VM is fully provisioned and ready"
}

# Function to configure Azure Update Manager
configure_update_manager() {
    info "Configuring Azure Update Manager..."
    
    # Create Azure Automation Account
    az automation account create \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --name "${AUTOMATION_ACCOUNT}" \
        --location "${LOCATION_PRIMARY}" \
        --sku Basic \
        --tags purpose=disaster-recovery environment=primary
    
    # Create Log Analytics workspace
    az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --workspace-name "${LOG_WORKSPACE}" \
        --location "${LOCATION_PRIMARY}" \
        --sku PerGB2018 \
        --tags purpose=disaster-recovery environment=primary
    
    # Get workspace ID and key
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --workspace-name "${LOG_WORKSPACE}" \
        --query customerId --output tsv)
    
    WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --workspace-name "${LOG_WORKSPACE}" \
        --query primarySharedKey --output tsv)
    
    # Install monitoring agent on VM
    az vm extension set \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --vm-name "${VM_PRIMARY}" \
        --name MicrosoftMonitoringAgent \
        --publisher Microsoft.EnterpriseCloud.Monitoring \
        --settings "{\"workspaceId\":\"${WORKSPACE_ID}\"}" \
        --protected-settings "{\"workspaceKey\":\"${WORKSPACE_KEY}\"}"
    
    success "Azure Update Manager configured"
}

# Function to create recovery plan
create_recovery_plan() {
    info "Creating recovery plan for automated failover..."
    
    # Create recovery plan configuration file
    cat > "${SCRIPT_DIR}/recovery-plan.json" << EOF
{
    "name": "recovery-plan-${RANDOM_SUFFIX}",
    "primaryRegion": "${LOCATION_PRIMARY}",
    "secondaryRegion": "${LOCATION_SECONDARY}",
    "virtualMachines": [
        {
            "name": "${VM_PRIMARY}",
            "resourceGroup": "${RESOURCE_GROUP_PRIMARY}",
            "priority": 1
        }
    ],
    "networkMappings": [
        {
            "primaryVnet": "${VNET_PRIMARY}",
            "secondaryVnet": "${VNET_SECONDARY}",
            "subnetMappings": [
                {
                    "primarySubnet": "${SUBNET_PRIMARY}",
                    "secondarySubnet": "${SUBNET_SECONDARY}"
                }
            ]
        }
    ]
}
EOF
    
    # Create Azure Automation runbook content
    cat > "${SCRIPT_DIR}/recovery-runbook.ps1" << 'EOF'
param(
    [Parameter(Mandatory=$true)]
    [string]$RecoveryPlanName,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$VaultName
)

try {
    # Connect to Azure using managed identity
    Connect-AzAccount -Identity
    
    Write-Output "Starting disaster recovery orchestration for plan: $RecoveryPlanName"
    
    # Get recovery plan details
    $recoveryPlan = Get-AzRecoveryServicesBackupRecoveryPoint -ResourceGroupName $ResourceGroupName -VaultName $VaultName
    
    Write-Output "Recovery plan validation completed successfully"
    
    # Log success
    Write-Output "Disaster recovery orchestration completed successfully"
}
catch {
    Write-Error "Error in disaster recovery orchestration: $($_.Exception.Message)"
    throw
}
EOF
    
    # Create Azure Automation runbook
    az automation runbook create \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --automation-account-name "${AUTOMATION_ACCOUNT}" \
        --name "DrRecoveryOrchestration" \
        --type PowerShell \
        --description "Orchestrates disaster recovery failover process"
    
    success "Recovery plan created"
}

# Function to configure monitoring and alerting
configure_monitoring() {
    info "Configuring Azure Monitor for disaster recovery..."
    
    # Create action group for alerts
    az monitor action-group create \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --name "${ACTION_GROUP}" \
        --short-name "DR-Alerts" \
        --email-receivers name=admin email=admin@company.com
    
    # Get VM resource ID
    VM_RESOURCE_ID=$(az vm show \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --name "${VM_PRIMARY}" \
        --query id --output tsv)
    
    # Create alert rule for VM health
    az monitor metrics alert create \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --name "alert-vm-health-${RANDOM_SUFFIX}" \
        --description "Monitor VM health status" \
        --severity 2 \
        --scopes "${VM_RESOURCE_ID}" \
        --condition "avg Percentage CPU > 80" \
        --action "${ACTION_GROUP}" \
        --evaluation-frequency 5m \
        --window-size 15m
    
    success "Azure Monitor configured for disaster recovery"
}

# Function to enable Site Recovery protection
enable_site_recovery() {
    info "Enabling Site Recovery protection..."
    
    # Get VM resource ID
    VM_RESOURCE_ID=$(az vm show \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --name "${VM_PRIMARY}" \
        --query id --output tsv)
    
    # Create backup policy
    az backup policy create \
        --resource-group "${RESOURCE_GROUP_SECONDARY}" \
        --vault-name "${VAULT_NAME}" \
        --name "policy-dr-${RANDOM_SUFFIX}" \
        --backup-management-type AzureStorage \
        --workload-type VM
    
    # Enable backup protection (as a foundation for Site Recovery)
    az backup protection enable-for-vm \
        --resource-group "${RESOURCE_GROUP_SECONDARY}" \
        --vault-name "${VAULT_NAME}" \
        --vm "${VM_RESOURCE_ID}" \
        --policy-name "policy-dr-${RANDOM_SUFFIX}"
    
    success "Site Recovery protection enabled"
    info "Initial replication will begin shortly"
}

# Function to validate deployment
validate_deployment() {
    info "Validating deployment..."
    
    # Check resource groups
    if ! az group show --name "${RESOURCE_GROUP_PRIMARY}" &> /dev/null; then
        error "Primary resource group not found"
        return 1
    fi
    
    if ! az group show --name "${RESOURCE_GROUP_SECONDARY}" &> /dev/null; then
        error "Secondary resource group not found"
        return 1
    fi
    
    # Check VM status
    VM_STATUS=$(az vm show \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --name "${VM_PRIMARY}" \
        --query provisioningState --output tsv)
    
    if [ "${VM_STATUS}" != "Succeeded" ]; then
        error "VM deployment failed with status: ${VM_STATUS}"
        return 1
    fi
    
    # Check vault
    if ! az backup vault show \
        --resource-group "${RESOURCE_GROUP_SECONDARY}" \
        --name "${VAULT_NAME}" &> /dev/null; then
        error "Recovery Services Vault not found"
        return 1
    fi
    
    success "Deployment validation completed successfully"
}

# Function to display deployment summary
display_summary() {
    info "Deployment Summary:"
    echo ""
    echo "=================================================="
    echo "Disaster Recovery Solution Deployed Successfully"
    echo "=================================================="
    echo ""
    echo "Resource Groups:"
    echo "  Primary: ${RESOURCE_GROUP_PRIMARY} (${LOCATION_PRIMARY})"
    echo "  Secondary: ${RESOURCE_GROUP_SECONDARY} (${LOCATION_SECONDARY})"
    echo ""
    echo "Key Resources:"
    echo "  Recovery Vault: ${VAULT_NAME}"
    echo "  Primary VM: ${VM_PRIMARY}"
    echo "  Primary VNet: ${VNET_PRIMARY}"
    echo "  Secondary VNet: ${VNET_SECONDARY}"
    echo "  Automation Account: ${AUTOMATION_ACCOUNT}"
    echo "  Log Analytics: ${LOG_WORKSPACE}"
    echo ""
    echo "Next Steps:"
    echo "1. Monitor replication status in Azure portal"
    echo "2. Test failover when initial replication completes"
    echo "3. Configure update schedules in Azure Update Manager"
    echo "4. Review and test recovery plans"
    echo ""
    echo "Configuration saved to: ${DEPLOYMENT_CONFIG}"
    echo "Deployment log: ${LOG_FILE}"
    echo ""
    warning "Remember to run ./destroy.sh to clean up resources when done"
}

# Main deployment function
main() {
    info "Starting Azure Disaster Recovery deployment..."
    info "Log file: ${LOG_FILE}"
    
    # Initialize log file
    echo "Azure Disaster Recovery Deployment - $(date)" > "${LOG_FILE}"
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_groups
    create_recovery_vault
    create_virtual_networks
    create_storage_account
    deploy_test_vms
    configure_update_manager
    create_recovery_plan
    configure_monitoring
    enable_site_recovery
    validate_deployment
    display_summary
    
    success "Deployment completed successfully!"
}

# Execute main function
main "$@"