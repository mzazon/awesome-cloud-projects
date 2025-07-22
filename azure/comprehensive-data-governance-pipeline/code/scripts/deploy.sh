#!/bin/bash

# Azure Purview and Data Lake Storage Governance Deployment Script
# Recipe: Comprehensive Data Governance Pipeline with Purview Discovery
# This script deploys a complete data governance solution using Azure Purview and Data Lake Storage Gen2

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first"
    fi
    
    # Check required tools
    if ! command -v openssl &> /dev/null; then
        error "openssl is required but not installed"
    fi
    
    if ! command -v curl &> /dev/null; then
        error "curl is required but not installed"
    fi
    
    log "✅ Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set default values or use existing environment variables
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-purview-governance-demo}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set unique resource names
    export PURVIEW_ACCOUNT="${PURVIEW_ACCOUNT:-purview-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-datalake${RANDOM_SUFFIX}}"
    export SYNAPSE_WORKSPACE="${SYNAPSE_WORKSPACE:-synapse-${RANDOM_SUFFIX}}"
    export KEY_VAULT="${KEY_VAULT:-kv-${RANDOM_SUFFIX}}"
    
    # Store configuration for cleanup script
    cat > .deployment_config << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
PURVIEW_ACCOUNT=${PURVIEW_ACCOUNT}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
SYNAPSE_WORKSPACE=${SYNAPSE_WORKSPACE}
KEY_VAULT=${KEY_VAULT}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
EOF
    
    info "Resource Group: ${RESOURCE_GROUP}"
    info "Purview Account: ${PURVIEW_ACCOUNT}"
    info "Storage Account: ${STORAGE_ACCOUNT}"
    info "Synapse Workspace: ${SYNAPSE_WORKSPACE}"
    info "Location: ${LOCATION}"
    
    log "✅ Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --tags purpose=data-governance environment=demo created-by=deploy-script
        log "✅ Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Function to register required providers
register_providers() {
    log "Registering required Azure resource providers..."
    
    local providers=("Microsoft.Purview" "Microsoft.Storage" "Microsoft.Synapse" "Microsoft.KeyVault")
    
    for provider in "${providers[@]}"; do
        info "Registering provider: $provider"
        az provider register --namespace $provider --wait
    done
    
    log "✅ Required resource providers registered"
}

# Function to create Data Lake Storage Gen2
create_storage_account() {
    log "Creating Azure Data Lake Storage Gen2 account..."
    
    if az storage account show --resource-group ${RESOURCE_GROUP} --name ${STORAGE_ACCOUNT} &> /dev/null; then
        warning "Storage account ${STORAGE_ACCOUNT} already exists"
    else
        az storage account create \
            --name ${STORAGE_ACCOUNT} \
            --resource-group ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --sku Standard_LRS \
            --kind StorageV2 \
            --hierarchical-namespace true \
            --enable-versioning true \
            --tags purpose=data-lake environment=demo created-by=deploy-script
        
        log "✅ Data Lake Storage Gen2 account created: ${STORAGE_ACCOUNT}"
    fi
    
    # Get storage account key
    export STORAGE_KEY=$(az storage account keys list \
        --resource-group ${RESOURCE_GROUP} \
        --account-name ${STORAGE_ACCOUNT} \
        --query '[0].value' --output tsv)
    
    # Store storage key in config file
    echo "STORAGE_KEY=${STORAGE_KEY}" >> .deployment_config
}

# Function to create containers and sample data
create_containers_and_data() {
    log "Creating containers and sample data..."
    
    # Create containers for different data domains
    local containers=("raw-data" "processed-data" "sensitive-data")
    
    for container in "${containers[@]}"; do
        info "Creating container: $container"
        az storage container create \
            --name $container \
            --account-name ${STORAGE_ACCOUNT} \
            --account-key ${STORAGE_KEY} \
            --auth-mode key || warning "Container $container might already exist"
    done
    
    # Create sample data files
    log "Creating sample data files..."
    
    cat > customers.csv << 'EOF'
customer_id,name,email,phone,address
1,John Doe,john@company.com,555-0123,123 Main St
2,Jane Smith,jane@company.com,555-0124,456 Oak Ave
3,Bob Johnson,bob@example.org,555-0125,789 Pine Rd
4,Alice Brown,alice@company.com,555-0126,321 Elm Dr
5,Charlie Davis,charlie@example.org,555-0127,654 Maple Ln
EOF
    
    cat > orders.csv << 'EOF'
order_id,customer_id,product,amount,date
101,1,Laptop,999.99,2024-01-15
102,2,Mouse,29.99,2024-01-16
103,3,Keyboard,79.99,2024-01-17
104,4,Monitor,299.99,2024-01-18
105,5,Webcam,89.99,2024-01-19
EOF
    
    cat > products.csv << 'EOF'
product_id,name,category,price,description
1,Laptop,Electronics,999.99,High-performance laptop
2,Mouse,Electronics,29.99,Wireless optical mouse
3,Keyboard,Electronics,79.99,Mechanical keyboard
4,Monitor,Electronics,299.99,24-inch LED monitor
5,Webcam,Electronics,89.99,HD webcam for video calls
EOF
    
    # Upload sample data files
    info "Uploading sample data files..."
    
    az storage blob upload \
        --file customers.csv \
        --container-name sensitive-data \
        --name customers/customers.csv \
        --account-name ${STORAGE_ACCOUNT} \
        --account-key ${STORAGE_KEY} \
        --overwrite || warning "Failed to upload customers.csv"
    
    az storage blob upload \
        --file orders.csv \
        --container-name raw-data \
        --name orders/orders.csv \
        --account-name ${STORAGE_ACCOUNT} \
        --account-key ${STORAGE_KEY} \
        --overwrite || warning "Failed to upload orders.csv"
    
    az storage blob upload \
        --file products.csv \
        --container-name raw-data \
        --name products/products.csv \
        --account-name ${STORAGE_ACCOUNT} \
        --account-key ${STORAGE_KEY} \
        --overwrite || warning "Failed to upload products.csv"
    
    log "✅ Data containers and sample files created"
}

# Function to create Azure Purview account
create_purview_account() {
    log "Creating Azure Purview account..."
    
    if az purview account show --resource-group ${RESOURCE_GROUP} --name ${PURVIEW_ACCOUNT} &> /dev/null; then
        warning "Purview account ${PURVIEW_ACCOUNT} already exists"
    else
        az purview account create \
            --resource-group ${RESOURCE_GROUP} \
            --name ${PURVIEW_ACCOUNT} \
            --location ${LOCATION} \
            --managed-resource-group-name "managed-rg-${PURVIEW_ACCOUNT}" \
            --tags purpose=data-governance environment=demo created-by=deploy-script
        
        # Wait for Purview account to be fully provisioned
        info "Waiting for Purview account provisioning..."
        az purview account wait \
            --resource-group ${RESOURCE_GROUP} \
            --name ${PURVIEW_ACCOUNT} \
            --created \
            --timeout 1800  # 30 minutes timeout
        
        log "✅ Azure Purview account created: ${PURVIEW_ACCOUNT}"
    fi
    
    # Get Purview account details
    export PURVIEW_ENDPOINT=$(az purview account show \
        --resource-group ${RESOURCE_GROUP} \
        --name ${PURVIEW_ACCOUNT} \
        --query 'properties.endpoints.catalog' \
        --output tsv)
    
    info "Purview Catalog Endpoint: ${PURVIEW_ENDPOINT}"
    echo "PURVIEW_ENDPOINT=${PURVIEW_ENDPOINT}" >> .deployment_config
}

# Function to configure data source permissions
configure_permissions() {
    log "Configuring data source permissions..."
    
    # Get current user's object ID for role assignment
    export USER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv)
    
    # Get storage account resource ID
    export STORAGE_RESOURCE_ID=$(az storage account show \
        --resource-group ${RESOURCE_GROUP} \
        --name ${STORAGE_ACCOUNT} \
        --query 'id' --output tsv)
    
    # Get Purview managed identity
    export PURVIEW_IDENTITY=$(az purview account show \
        --resource-group ${RESOURCE_GROUP} \
        --name ${PURVIEW_ACCOUNT} \
        --query 'identity.principalId' \
        --output tsv)
    
    # Assign Storage Blob Data Reader role to Purview managed identity
    info "Assigning Storage Blob Data Reader role to Purview managed identity..."
    az role assignment create \
        --assignee ${PURVIEW_IDENTITY} \
        --role "Storage Blob Data Reader" \
        --scope ${STORAGE_RESOURCE_ID} || warning "Role assignment might already exist"
    
    # Get Purview resource ID
    export PURVIEW_RESOURCE_ID=$(az purview account show \
        --resource-group ${RESOURCE_GROUP} \
        --name ${PURVIEW_ACCOUNT} \
        --query 'id' --output tsv)
    
    # Assign Purview Data Curator role to current user
    info "Assigning Purview Data Curator role to current user..."
    az role assignment create \
        --assignee ${USER_OBJECT_ID} \
        --role "Purview Data Curator" \
        --scope ${PURVIEW_RESOURCE_ID} || warning "Role assignment might already exist"
    
    # Store IDs in config file
    echo "USER_OBJECT_ID=${USER_OBJECT_ID}" >> .deployment_config
    echo "STORAGE_RESOURCE_ID=${STORAGE_RESOURCE_ID}" >> .deployment_config
    echo "PURVIEW_IDENTITY=${PURVIEW_IDENTITY}" >> .deployment_config
    echo "PURVIEW_RESOURCE_ID=${PURVIEW_RESOURCE_ID}" >> .deployment_config
    
    log "✅ Data source permissions configured"
}

# Function to create Synapse workspace
create_synapse_workspace() {
    log "Creating Azure Synapse Analytics workspace..."
    
    if az synapse workspace show --resource-group ${RESOURCE_GROUP} --name ${SYNAPSE_WORKSPACE} &> /dev/null; then
        warning "Synapse workspace ${SYNAPSE_WORKSPACE} already exists"
    else
        # Create synapse file system in storage account
        az storage container create \
            --name synapse \
            --account-name ${STORAGE_ACCOUNT} \
            --account-key ${STORAGE_KEY} \
            --auth-mode key || warning "Synapse container might already exist"
        
        az synapse workspace create \
            --name ${SYNAPSE_WORKSPACE} \
            --resource-group ${RESOURCE_GROUP} \
            --storage-account ${STORAGE_ACCOUNT} \
            --file-system synapse \
            --location ${LOCATION} \
            --sql-admin-login-user sqladminuser \
            --sql-admin-login-password "ComplexP@ssw0rd123!" \
            --tags purpose=analytics environment=demo created-by=deploy-script
        
        # Wait for workspace creation
        info "Waiting for Synapse workspace provisioning..."
        az synapse workspace wait \
            --resource-group ${RESOURCE_GROUP} \
            --workspace-name ${SYNAPSE_WORKSPACE} \
            --created \
            --timeout 1800  # 30 minutes timeout
        
        log "✅ Synapse workspace created: ${SYNAPSE_WORKSPACE}"
    fi
    
    # Get Synapse workspace details
    export SYNAPSE_ENDPOINT=$(az synapse workspace show \
        --resource-group ${RESOURCE_GROUP} \
        --name ${SYNAPSE_WORKSPACE} \
        --query 'connectivityEndpoints.web' \
        --output tsv)
    
    info "Synapse Studio URL: ${SYNAPSE_ENDPOINT}"
    echo "SYNAPSE_ENDPOINT=${SYNAPSE_ENDPOINT}" >> .deployment_config
}

# Function to configure firewall rules
configure_firewall_rules() {
    log "Configuring firewall rules for development access..."
    
    # Allow Azure services access to Synapse workspace
    az synapse workspace firewall-rule create \
        --name AllowAllWindowsAzureIps \
        --resource-group ${RESOURCE_GROUP} \
        --workspace-name ${SYNAPSE_WORKSPACE} \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0 || warning "Azure services firewall rule might already exist"
    
    # Get current public IP for client access
    export CURRENT_IP=$(curl -s https://api.ipify.org || echo "Unable to determine IP")
    
    if [[ ${CURRENT_IP} != "Unable to determine IP" ]]; then
        # Allow current IP access to Synapse workspace
        az synapse workspace firewall-rule create \
            --name AllowCurrentIP \
            --resource-group ${RESOURCE_GROUP} \
            --workspace-name ${SYNAPSE_WORKSPACE} \
            --start-ip-address ${CURRENT_IP} \
            --end-ip-address ${CURRENT_IP} || warning "Current IP firewall rule might already exist"
        
        info "Current IP allowed: ${CURRENT_IP}"
        echo "CURRENT_IP=${CURRENT_IP}" >> .deployment_config
    else
        warning "Could not determine current IP address. Manual firewall configuration may be required."
    fi
    
    log "✅ Firewall rules configured for development access"
}

# Function to create configuration files
create_configuration_files() {
    log "Creating configuration files..."
    
    # Create data pipeline definition
    cat > data-pipeline.json << 'EOF'
{
  "name": "GovernanceTestPipeline",
  "properties": {
    "activities": [
      {
        "name": "CopyRawToProcessed",
        "type": "Copy",
        "inputs": [
          {
            "referenceName": "RawDataSource",
            "type": "DatasetReference"
          }
        ],
        "outputs": [
          {
            "referenceName": "ProcessedDataSink",
            "type": "DatasetReference"
          }
        ],
        "typeProperties": {
          "source": {
            "type": "DelimitedTextSource"
          },
          "sink": {
            "type": "DelimitedTextSink"
          }
        }
      }
    ]
  }
}
EOF
    
    # Create linked service for Data Lake Storage
    cat > linked-service.json << EOF
{
  "name": "DataLakeLinkedService",
  "properties": {
    "type": "AzureBlobFS",
    "typeProperties": {
      "url": "https://${STORAGE_ACCOUNT}.dfs.core.windows.net/",
      "accountKey": {
        "type": "SecureString",
        "value": "${STORAGE_KEY}"
      }
    }
  }
}
EOF
    
    # Create classification rules configuration
    cat > classification-rules.json << 'EOF'
{
  "customClassificationRules": [
    {
      "name": "CustomerEmailClassification",
      "description": "Identifies customer email addresses",
      "classificationName": "Email Address",
      "ruleType": "Regex",
      "pattern": "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$",
      "columnNames": ["email", "email_address", "customer_email"],
      "severity": "High"
    },
    {
      "name": "CustomerPhoneClassification",
      "description": "Identifies customer phone numbers",
      "classificationName": "Phone Number",
      "ruleType": "Regex",
      "pattern": "^\\+?[1-9]\\d{1,14}$|^\\(?\\d{3}\\)?[-\\s.]?\\d{3}[-\\s.]?\\d{4}$",
      "columnNames": ["phone", "phone_number", "customer_phone"],
      "severity": "Medium"
    },
    {
      "name": "CustomerAddressClassification",
      "description": "Identifies customer addresses",
      "classificationName": "Address",
      "ruleType": "KeywordList",
      "keywords": ["address", "street", "city", "state", "zip"],
      "columnNames": ["address", "street_address", "mailing_address"],
      "severity": "Medium"
    }
  ]
}
EOF
    
    # Create sensitivity labels configuration
    cat > sensitivity-labels.json << 'EOF'
{
  "sensitivityLabels": [
    {
      "name": "Public",
      "description": "Data that can be shared publicly",
      "color": "#00FF00"
    },
    {
      "name": "Internal",
      "description": "Data for internal use only",
      "color": "#FFFF00"
    },
    {
      "name": "Confidential",
      "description": "Sensitive data requiring protection",
      "color": "#FFA500"
    },
    {
      "name": "Restricted",
      "description": "Highly sensitive data with strict access controls",
      "color": "#FF0000"
    }
  ]
}
EOF
    
    log "✅ Configuration files created"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check Purview account status
    info "Checking Purview account status..."
    az purview account show \
        --resource-group ${RESOURCE_GROUP} \
        --name ${PURVIEW_ACCOUNT} \
        --query '{name:name,state:properties.provisioningState,endpoint:properties.endpoints.catalog}' \
        --output table
    
    # List containers in storage account
    info "Checking storage containers..."
    az storage container list \
        --account-name ${STORAGE_ACCOUNT} \
        --account-key ${STORAGE_KEY} \
        --query '[].name' \
        --output table
    
    # Verify sample data files
    info "Checking sample data files..."
    az storage blob list \
        --container-name sensitive-data \
        --account-name ${STORAGE_ACCOUNT} \
        --account-key ${STORAGE_KEY} \
        --query '[].name' \
        --output table
    
    # Check Synapse workspace status
    info "Checking Synapse workspace status..."
    az synapse workspace show \
        --resource-group ${RESOURCE_GROUP} \
        --name ${SYNAPSE_WORKSPACE} \
        --query '{name:name,state:provisioningState,endpoint:connectivityEndpoints.web}' \
        --output table
    
    # Check role assignments
    info "Checking Purview managed identity permissions..."
    az role assignment list \
        --assignee ${PURVIEW_IDENTITY} \
        --scope ${STORAGE_RESOURCE_ID} \
        --query '[].{Role:roleDefinitionName,Scope:scope}' \
        --output table
    
    log "✅ Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "=== DEPLOYMENT SUMMARY ==="
    info "Resource Group: ${RESOURCE_GROUP}"
    info "Location: ${LOCATION}"
    info "Subscription ID: ${SUBSCRIPTION_ID}"
    echo ""
    info "Created Resources:"
    info "  • Purview Account: ${PURVIEW_ACCOUNT}"
    info "  • Storage Account: ${STORAGE_ACCOUNT}"
    info "  • Synapse Workspace: ${SYNAPSE_WORKSPACE}"
    echo ""
    info "Access URLs:"
    info "  • Purview Portal: https://web.purview.azure.com/resource/${PURVIEW_ACCOUNT}"
    info "  • Synapse Studio: ${SYNAPSE_ENDPOINT}"
    echo ""
    info "Next Steps:"
    info "  1. Access Azure Purview portal to register data sources"
    info "  2. Configure automated scans for data discovery"
    info "  3. Set up data classification rules and policies"
    info "  4. Monitor data governance through Purview insights"
    echo ""
    warning "Remember to run the destroy.sh script when finished to avoid ongoing charges!"
    echo ""
    log "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
}

# Main deployment function
main() {
    log "Starting Azure Purview and Data Lake Storage governance deployment..."
    
    check_prerequisites
    setup_environment
    create_resource_group
    register_providers
    create_storage_account
    create_containers_and_data
    create_purview_account
    configure_permissions
    create_synapse_workspace
    configure_firewall_rules
    create_configuration_files
    validate_deployment
    display_summary
    
    log "Deployment completed successfully! Configuration saved to .deployment_config"
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may have been created. Check Azure portal and run destroy.sh if needed."' INT TERM

# Execute main function
main "$@"