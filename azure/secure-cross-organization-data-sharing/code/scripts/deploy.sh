#!/bin/bash

# Azure Data Share and Service Fabric Deployment Script
# Recipe: Secure Cross-Organization Data Sharing with Data Share and Service Fabric
# Version: 1.0
# Last Updated: 2025-07-12

set -euo pipefail

# Enable debugging if DEBUG environment variable is set
if [[ "${DEBUG:-}" == "true" ]]; then
    set -x
fi

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${ERROR_LOG}" | tee -a "${LOG_FILE}"
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Script failed at line ${line_number} with exit code ${exit_code}"
    log_error "Check ${ERROR_LOG} for detailed error information"
    exit ${exit_code}
}

trap 'handle_error ${LINENO}' ERR

# Cleanup function for script interruption
cleanup_on_exit() {
    log_warning "Script interrupted. Partial resources may have been created."
    log_info "Run destroy.sh to clean up any created resources"
}

trap cleanup_on_exit SIGINT SIGTERM

# Configuration validation
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI v2.50.0 or later"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '."azure-cli"' -o tsv)
    log_info "Azure CLI version: ${az_version}"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Run 'az login' first"
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random suffixes"
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

# Environment setup
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP_PROVIDER="rg-data-share-provider-${RANDOM_SUFFIX}"
    export RESOURCE_GROUP_CONSUMER="rg-data-share-consumer-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_REGION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Resource names with unique suffix
    export DATA_SHARE_ACCOUNT="datashare${RANDOM_SUFFIX}"
    export SERVICE_FABRIC_CLUSTER="sf-governance-${RANDOM_SUFFIX}"
    export KEY_VAULT_PROVIDER="kv-provider-${RANDOM_SUFFIX}"
    export KEY_VAULT_CONSUMER="kv-consumer-${RANDOM_SUFFIX}"
    export STORAGE_PROVIDER="stprovider${RANDOM_SUFFIX}"
    export STORAGE_CONSUMER="stconsumer${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_WORKSPACE="law-datashare-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > "${SCRIPT_DIR}/deployment_vars.env" << EOF
RANDOM_SUFFIX=${RANDOM_SUFFIX}
RESOURCE_GROUP_PROVIDER=${RESOURCE_GROUP_PROVIDER}
RESOURCE_GROUP_CONSUMER=${RESOURCE_GROUP_CONSUMER}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
DATA_SHARE_ACCOUNT=${DATA_SHARE_ACCOUNT}
SERVICE_FABRIC_CLUSTER=${SERVICE_FABRIC_CLUSTER}
KEY_VAULT_PROVIDER=${KEY_VAULT_PROVIDER}
KEY_VAULT_CONSUMER=${KEY_VAULT_CONSUMER}
STORAGE_PROVIDER=${STORAGE_PROVIDER}
STORAGE_CONSUMER=${STORAGE_CONSUMER}
LOG_ANALYTICS_WORKSPACE=${LOG_ANALYTICS_WORKSPACE}
EOF
    
    log_success "Environment variables configured with suffix: ${RANDOM_SUFFIX}"
}

# Resource provider registration
register_providers() {
    log_info "Registering required Azure resource providers..."
    
    local providers=("Microsoft.DataShare" "Microsoft.ServiceFabric" "Microsoft.KeyVault" "Microsoft.OperationalInsights")
    
    for provider in "${providers[@]}"; do
        log_info "Registering provider: ${provider}"
        if az provider register --namespace "${provider}" --wait; then
            log_success "Provider ${provider} registered successfully"
        else
            log_warning "Provider ${provider} registration failed or was already registered"
        fi
    done
}

# Resource group creation
create_resource_groups() {
    log_info "Creating resource groups..."
    
    # Create provider resource group
    if az group create \
        --name "${RESOURCE_GROUP_PROVIDER}" \
        --location "${LOCATION}" \
        --tags purpose=data-share-demo environment=provider deployment=automated > /dev/null; then
        log_success "Provider resource group created: ${RESOURCE_GROUP_PROVIDER}"
    else
        log_error "Failed to create provider resource group"
        return 1
    fi
    
    # Create consumer resource group
    if az group create \
        --name "${RESOURCE_GROUP_CONSUMER}" \
        --location "${LOCATION}" \
        --tags purpose=data-share-demo environment=consumer deployment=automated > /dev/null; then
        log_success "Consumer resource group created: ${RESOURCE_GROUP_CONSUMER}"
    else
        log_error "Failed to create consumer resource group"
        return 1
    fi
}

# Storage account creation
create_storage_accounts() {
    log_info "Creating storage accounts..."
    
    # Create provider storage account
    log_info "Creating provider storage account: ${STORAGE_PROVIDER}"
    if az storage account create \
        --name "${STORAGE_PROVIDER}" \
        --resource-group "${RESOURCE_GROUP_PROVIDER}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        --allow-blob-public-access false \
        --tags purpose=data-sharing environment=provider > /dev/null; then
        log_success "Provider storage account created successfully"
    else
        log_error "Failed to create provider storage account"
        return 1
    fi
    
    # Create consumer storage account
    log_info "Creating consumer storage account: ${STORAGE_CONSUMER}"
    if az storage account create \
        --name "${STORAGE_CONSUMER}" \
        --resource-group "${RESOURCE_GROUP_CONSUMER}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        --allow-blob-public-access false \
        --tags purpose=data-sharing environment=consumer > /dev/null; then
        log_success "Consumer storage account created successfully"
    else
        log_error "Failed to create consumer storage account"
        return 1
    fi
}

# Key vault creation
create_key_vaults() {
    log_info "Creating Azure Key Vaults..."
    
    # Create provider Key Vault
    log_info "Creating provider Key Vault: ${KEY_VAULT_PROVIDER}"
    if az keyvault create \
        --name "${KEY_VAULT_PROVIDER}" \
        --resource-group "${RESOURCE_GROUP_PROVIDER}" \
        --location "${LOCATION}" \
        --sku standard \
        --enabled-for-deployment true \
        --enabled-for-template-deployment true \
        --enable-rbac-authorization false \
        --tags purpose=data-sharing environment=provider > /dev/null; then
        log_success "Provider Key Vault created successfully"
    else
        log_error "Failed to create provider Key Vault"
        return 1
    fi
    
    # Create consumer Key Vault
    log_info "Creating consumer Key Vault: ${KEY_VAULT_CONSUMER}"
    if az keyvault create \
        --name "${KEY_VAULT_CONSUMER}" \
        --resource-group "${RESOURCE_GROUP_CONSUMER}" \
        --location "${LOCATION}" \
        --sku standard \
        --enabled-for-deployment true \
        --enabled-for-template-deployment true \
        --enable-rbac-authorization false \
        --tags purpose=data-sharing environment=consumer > /dev/null; then
        log_success "Consumer Key Vault created successfully"
    else
        log_error "Failed to create consumer Key Vault"
        return 1
    fi
}

# Log Analytics workspace creation
create_log_analytics() {
    log_info "Creating Log Analytics workspace..."
    
    if az monitor log-analytics workspace create \
        --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP_PROVIDER}" \
        --location "${LOCATION}" \
        --sku PerGB2018 \
        --tags purpose=monitoring environment=shared > /dev/null; then
        
        local workspace_id=$(az monitor log-analytics workspace show \
            --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP_PROVIDER}" \
            --query customerId --output tsv)
        
        echo "WORKSPACE_ID=${workspace_id}" >> "${SCRIPT_DIR}/deployment_vars.env"
        log_success "Log Analytics workspace created with ID: ${workspace_id}"
    else
        log_error "Failed to create Log Analytics workspace"
        return 1
    fi
}

# Service Fabric cluster creation
create_service_fabric_cluster() {
    log_info "Creating Service Fabric cluster (this may take 10-15 minutes)..."
    
    # Create certificates directory
    mkdir -p "${SCRIPT_DIR}/certs"
    
    # Create Service Fabric cluster
    if az sf cluster create \
        --resource-group "${RESOURCE_GROUP_PROVIDER}" \
        --cluster-name "${SERVICE_FABRIC_CLUSTER}" \
        --location "${LOCATION}" \
        --certificate-output-folder "${SCRIPT_DIR}/certs" \
        --certificate-subject-name "CN=${SERVICE_FABRIC_CLUSTER}.${LOCATION}.cloudapp.azure.com" \
        --vault-name "${KEY_VAULT_PROVIDER}" \
        --vault-resource-group "${RESOURCE_GROUP_PROVIDER}" \
        --vm-size Standard_D2s_v3 \
        --vm-instance-count 5 \
        --os WindowsServer2019Datacenter \
        --cluster-size-os-disk 128 > /dev/null; then
        log_success "Service Fabric cluster created successfully"
    else
        log_error "Failed to create Service Fabric cluster"
        return 1
    fi
}

# Data Share account creation
create_data_share_account() {
    log_info "Creating Azure Data Share account..."
    
    if az datashare account create \
        --account-name "${DATA_SHARE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP_PROVIDER}" \
        --location "${LOCATION}" \
        --tags purpose=cross-org-collaboration governance=enabled > /dev/null; then
        
        local datashare_id=$(az datashare account show \
            --account-name "${DATA_SHARE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP_PROVIDER}" \
            --query id --output tsv)
        
        echo "DATASHARE_ACCOUNT_ID=${datashare_id}" >> "${SCRIPT_DIR}/deployment_vars.env"
        log_success "Data Share account created with ID: ${datashare_id}"
    else
        log_error "Failed to create Data Share account"
        return 1
    fi
}

# Sample dataset creation
create_sample_dataset() {
    log_info "Creating sample dataset for sharing..."
    
    # Get storage account key
    local storage_key=$(az storage account keys list \
        --account-name "${STORAGE_PROVIDER}" \
        --resource-group "${RESOURCE_GROUP_PROVIDER}" \
        --query '[0].value' --output tsv)
    
    # Create container for shared data
    if az storage container create \
        --name "shared-datasets" \
        --account-name "${STORAGE_PROVIDER}" \
        --account-key "${storage_key}" \
        --public-access off > /dev/null; then
        log_success "Storage container created for shared datasets"
    else
        log_error "Failed to create storage container"
        return 1
    fi
    
    # Create sample CSV data file
    cat > "${SCRIPT_DIR}/sample_financial_data.csv" << 'EOF'
transaction_id,date,amount,category,region
TXN001,2025-01-15,15000.00,corporate_loan,north_america
TXN002,2025-01-16,8500.50,consumer_credit,europe
TXN003,2025-01-17,22000.75,mortgage,asia_pacific
TXN004,2025-01-18,3200.25,small_business,north_america
TXN005,2025-01-19,45000.00,commercial_real_estate,europe
TXN006,2025-01-20,12750.30,auto_loan,north_america
TXN007,2025-01-21,7800.90,personal_loan,asia_pacific
TXN008,2025-01-22,33500.00,equipment_financing,europe
EOF
    
    # Upload sample data to storage
    if az storage blob upload \
        --file "${SCRIPT_DIR}/sample_financial_data.csv" \
        --container-name "shared-datasets" \
        --name "financial_transactions_2025.csv" \
        --account-name "${STORAGE_PROVIDER}" \
        --account-key "${storage_key}" \
        --overwrite > /dev/null; then
        log_success "Sample dataset uploaded successfully"
    else
        log_error "Failed to upload sample dataset"
        return 1
    fi
    
    # Save storage key to environment file (encrypted)
    echo "STORAGE_KEY=${storage_key}" >> "${SCRIPT_DIR}/deployment_vars.env"
}

# Data share creation
create_data_share() {
    log_info "Creating data share with sample dataset..."
    
    # Create data share
    if az datashare share create \
        --account-name "${DATA_SHARE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP_PROVIDER}" \
        --share-name "financial-collaboration-share" \
        --description "Cross-organization financial data sharing for analytics" \
        --terms-of-use "Data for internal use only. No redistribution allowed." > /dev/null; then
        log_success "Data share created successfully"
    else
        log_error "Failed to create data share"
        return 1
    fi
    
    # Add dataset to the share
    if az datashare dataset create \
        --account-name "${DATA_SHARE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP_PROVIDER}" \
        --share-name "financial-collaboration-share" \
        --dataset-name "financial-transactions" \
        --kind "Blob" \
        --storage-account-name "${STORAGE_PROVIDER}" \
        --resource-group "${RESOURCE_GROUP_PROVIDER}" \
        --container-name "shared-datasets" \
        --file-path "financial_transactions_2025.csv" > /dev/null; then
        log_success "Dataset added to data share successfully"
    else
        log_error "Failed to add dataset to data share"
        return 1
    fi
}

# Service Fabric application structure creation
create_governance_app_structure() {
    log_info "Creating Service Fabric governance application structure..."
    
    # Create application package structure
    mkdir -p "${SCRIPT_DIR}/governance-app"/{AccessGovernanceService,AuditTrailService,NotificationService}
    
    # Create Service Fabric application manifest
    cat > "${SCRIPT_DIR}/governance-app/ApplicationManifest.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<ApplicationManifest xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                     xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                     ApplicationTypeName="DataGovernanceApp"
                     ApplicationTypeVersion="1.0.0"
                     xmlns="http://schemas.microsoft.com/2011/01/fabric">
  <ServiceManifestImport>
    <ServiceManifestRef ServiceManifestName="AccessGovernanceService" ServiceManifestVersion="1.0.0" />
  </ServiceManifestImport>
  <ServiceManifestImport>
    <ServiceManifestRef ServiceManifestName="AuditTrailService" ServiceManifestVersion="1.0.0" />
  </ServiceManifestImport>
  <ServiceManifestImport>
    <ServiceManifestRef ServiceManifestName="NotificationService" ServiceManifestVersion="1.0.0" />
  </ServiceManifestImport>
  <DefaultServices>
    <Service Name="AccessGovernanceService">
      <StatefulService ServiceTypeName="AccessGovernanceServiceType" TargetReplicaSetSize="3" MinReplicaSetSize="2">
        <UniformInt64Partition PartitionCount="1" LowKey="0" HighKey="0" />
      </StatefulService>
    </Service>
    <Service Name="AuditTrailService">
      <StatefulService ServiceTypeName="AuditTrailServiceType" TargetReplicaSetSize="3" MinReplicaSetSize="2">
        <UniformInt64Partition PartitionCount="1" LowKey="0" HighKey="0" />
      </StatefulService>
    </Service>
    <Service Name="NotificationService">
      <StatelessService ServiceTypeName="NotificationServiceType" InstanceCount="3">
        <SingletonPartition />
      </StatelessService>
    </Service>
  </DefaultServices>
</ApplicationManifest>
EOF
    
    log_success "Service Fabric governance application structure created"
}

# Deployment validation
validate_deployment() {
    log_info "Validating deployment..."
    
    local validation_failed=false
    
    # Check Data Share account
    if az datashare account show \
        --account-name "${DATA_SHARE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP_PROVIDER}" > /dev/null 2>&1; then
        log_success "Data Share account validation: PASSED"
    else
        log_error "Data Share account validation: FAILED"
        validation_failed=true
    fi
    
    # Check Service Fabric cluster
    if az sf cluster show \
        --cluster-name "${SERVICE_FABRIC_CLUSTER}" \
        --resource-group "${RESOURCE_GROUP_PROVIDER}" > /dev/null 2>&1; then
        log_success "Service Fabric cluster validation: PASSED"
    else
        log_error "Service Fabric cluster validation: FAILED"
        validation_failed=true
    fi
    
    # Check storage accounts
    for storage in "${STORAGE_PROVIDER}" "${STORAGE_CONSUMER}"; do
        if az storage account show --name "${storage}" > /dev/null 2>&1; then
            log_success "Storage account ${storage} validation: PASSED"
        else
            log_error "Storage account ${storage} validation: FAILED"
            validation_failed=true
        fi
    done
    
    # Check Key Vaults
    for kv in "${KEY_VAULT_PROVIDER}" "${KEY_VAULT_CONSUMER}"; do
        if az keyvault show --name "${kv}" > /dev/null 2>&1; then
            log_success "Key Vault ${kv} validation: PASSED"
        else
            log_error "Key Vault ${kv} validation: FAILED"
            validation_failed=true
        fi
    done
    
    if [[ "${validation_failed}" == "true" ]]; then
        log_error "Deployment validation failed. Some resources may not have been created successfully."
        return 1
    else
        log_success "All deployment validations passed successfully"
    fi
}

# Main deployment function
main() {
    log_info "Starting Azure Data Share and Service Fabric deployment..."
    log_info "Deployment timestamp: $(date)"
    
    # Initialize log files
    echo "Deployment started at $(date)" > "${LOG_FILE}"
    echo "Error log for deployment started at $(date)" > "${ERROR_LOG}"
    
    # Execute deployment steps
    validate_prerequisites
    setup_environment
    register_providers
    create_resource_groups
    create_storage_accounts
    create_key_vaults
    create_log_analytics
    create_data_share_account
    create_sample_dataset
    create_data_share
    create_service_fabric_cluster
    create_governance_app_structure
    validate_deployment
    
    # Generate deployment summary
    cat << EOF

${GREEN}=====================================================================${NC}
${GREEN}                    DEPLOYMENT COMPLETED SUCCESSFULLY${NC}
${GREEN}=====================================================================${NC}

${BLUE}Deployment Summary:${NC}
- Provider Resource Group: ${RESOURCE_GROUP_PROVIDER}
- Consumer Resource Group: ${RESOURCE_GROUP_CONSUMER}
- Data Share Account: ${DATA_SHARE_ACCOUNT}
- Service Fabric Cluster: ${SERVICE_FABRIC_CLUSTER}
- Random Suffix: ${RANDOM_SUFFIX}

${BLUE}Next Steps:${NC}
1. Access the Service Fabric Explorer at: https://${SERVICE_FABRIC_CLUSTER}.${LOCATION}.cloudapp.azure.com:19080
2. Review the Data Share in Azure Portal
3. Test cross-organization data sharing workflows
4. Monitor audit trails in Log Analytics workspace: ${LOG_ANALYTICS_WORKSPACE}

${BLUE}Important Files:${NC}
- Deployment variables: ${SCRIPT_DIR}/deployment_vars.env
- Service Fabric certificates: ${SCRIPT_DIR}/certs/
- Deployment logs: ${LOG_FILE}
- Sample dataset: ${SCRIPT_DIR}/sample_financial_data.csv

${YELLOW}Security Note:${NC}
- Review and rotate the certificate in Key Vault for production use
- Configure appropriate access policies for cross-organization collaboration
- Enable additional monitoring and alerting as needed

${BLUE}Cleanup:${NC}
Run ./destroy.sh to remove all created resources when testing is complete.

${GREEN}=====================================================================${NC}
EOF
    
    log_success "Deployment completed successfully at $(date)"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi