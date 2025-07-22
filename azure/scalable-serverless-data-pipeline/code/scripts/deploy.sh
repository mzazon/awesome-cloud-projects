#!/bin/bash

# Azure Serverless Data Pipeline Deployment Script
# Recipe: Scalable Serverless Data Pipeline with Synapse and Data Factory
# Version: 1.0
# Last Updated: 2025-07-12

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if sqlcmd is installed
    if ! command_exists sqlcmd; then
        error "sqlcmd is not installed. Please install SQL Server command line tools."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command_exists openssl; then
        error "openssl is not installed. Please install openssl."
        exit 1
    fi
    
    # Check if curl is installed
    if ! command_exists curl; then
        error "curl is not installed. Please install curl."
        exit 1
    fi
    
    # Check Azure CLI login status
    if ! az account show >/dev/null 2>&1; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    log "Prerequisites check passed ✅"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Set default values or use existing environment variables
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-serverless-pipeline}"
    export LOCATION="${LOCATION:-eastus}"
    export RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stpipeline${RANDOM_SUFFIX}}"
    export SYNAPSE_WORKSPACE="${SYNAPSE_WORKSPACE:-syn-pipeline-${RANDOM_SUFFIX}}"
    export DATA_FACTORY="${DATA_FACTORY:-adf-pipeline-${RANDOM_SUFFIX}}"
    export KEY_VAULT="${KEY_VAULT:-kv-pipeline-${RANDOM_SUFFIX}}"
    export SQL_ADMIN_PASSWORD="${SQL_ADMIN_PASSWORD:-P@ssw0rd123!}"
    
    info "Resource Group: ${RESOURCE_GROUP}"
    info "Location: ${LOCATION}"
    info "Storage Account: ${STORAGE_ACCOUNT}"
    info "Synapse Workspace: ${SYNAPSE_WORKSPACE}"
    info "Data Factory: ${DATA_FACTORY}"
    info "Key Vault: ${KEY_VAULT}"
    
    log "Environment variables set ✅"
}

# Function to create foundation resources
create_foundation_resources() {
    log "Creating foundation resources..."
    
    # Create resource group
    if ! az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log "Creating resource group: ${RESOURCE_GROUP}"
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags environment=demo purpose=data-pipeline
    else
        warn "Resource group ${RESOURCE_GROUP} already exists"
    fi
    
    # Create storage account with hierarchical namespace
    if ! az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log "Creating storage account: ${STORAGE_ACCOUNT}"
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --hierarchical-namespace true \
            --enable-https-traffic-only true
    else
        warn "Storage account ${STORAGE_ACCOUNT} already exists"
    fi
    
    # Get storage account key
    export STORAGE_KEY=$(az storage account keys list \
        --account-name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query '[0].value' -o tsv)
    
    log "Foundation resources created ✅"
}

# Function to create Azure Key Vault
create_key_vault() {
    log "Creating Azure Key Vault..."
    
    if ! az keyvault show --name "${KEY_VAULT}" >/dev/null 2>&1; then
        log "Creating Key Vault: ${KEY_VAULT}"
        az keyvault create \
            --name "${KEY_VAULT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --enable-soft-delete true \
            --retention-days 7
    else
        warn "Key Vault ${KEY_VAULT} already exists"
    fi
    
    # Store storage account connection string
    CONNECTION_STRING=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString -o tsv)
    
    az keyvault secret set \
        --vault-name "${KEY_VAULT}" \
        --name "storage-connection-string" \
        --value "${CONNECTION_STRING}"
    
    log "Key Vault created with secure credential storage ✅"
}

# Function to deploy Azure Synapse Analytics
deploy_synapse_workspace() {
    log "Deploying Azure Synapse Analytics workspace..."
    
    if ! az synapse workspace show --name "${SYNAPSE_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log "Creating Synapse workspace: ${SYNAPSE_WORKSPACE}"
        az synapse workspace create \
            --name "${SYNAPSE_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --file-system "synapsefs" \
            --sql-admin-login-user "sqladmin" \
            --sql-admin-login-password "${SQL_ADMIN_PASSWORD}" \
            --location "${LOCATION}"
    else
        warn "Synapse workspace ${SYNAPSE_WORKSPACE} already exists"
    fi
    
    # Create firewall rule for client IP
    CLIENT_IP=$(curl -s https://api.ipify.org)
    az synapse workspace firewall-rule create \
        --name "AllowClientIP" \
        --workspace-name "${SYNAPSE_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --start-ip-address "${CLIENT_IP}" \
        --end-ip-address "${CLIENT_IP}" \
        --output none || warn "Firewall rule may already exist"
    
    log "Synapse workspace deployed with serverless SQL pool ✅"
}

# Function to configure Data Lake Storage structure
configure_data_lake_structure() {
    log "Configuring Data Lake Storage structure..."
    
    # Create data lake containers
    containers=("raw" "curated" "refined")
    for container in "${containers[@]}"; do
        if ! az storage container show --name "${container}" --account-name "${STORAGE_ACCOUNT}" --account-key "${STORAGE_KEY}" >/dev/null 2>&1; then
            log "Creating container: ${container}"
            az storage container create \
                --name "${container}" \
                --account-name "${STORAGE_ACCOUNT}" \
                --account-key "${STORAGE_KEY}"
        else
            warn "Container ${container} already exists"
        fi
    done
    
    # Create folder structure
    az storage fs directory create \
        --name "streaming-data" \
        --file-system "raw" \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${STORAGE_KEY}" \
        --output none || warn "Directory may already exist"
    
    log "Data lake structure created with medallion architecture ✅"
}

# Function to deploy Azure Data Factory
deploy_data_factory() {
    log "Deploying Azure Data Factory..."
    
    if ! az datafactory show --name "${DATA_FACTORY}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log "Creating Data Factory: ${DATA_FACTORY}"
        az datafactory create \
            --name "${DATA_FACTORY}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}"
    else
        warn "Data Factory ${DATA_FACTORY} already exists"
    fi
    
    # Enable managed identity and get principal ID
    FACTORY_IDENTITY=$(az datafactory show \
        --name "${DATA_FACTORY}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query identity.principalId -o tsv)
    
    # Grant Key Vault access to Data Factory
    az keyvault set-policy \
        --name "${KEY_VAULT}" \
        --object-id "${FACTORY_IDENTITY}" \
        --secret-permissions get list
    
    log "Data Factory deployed with managed identity configured ✅"
}

# Function to create linked services
create_linked_services() {
    log "Creating linked services for integration..."
    
    # Create Key Vault linked service
    az datafactory linked-service create \
        --resource-group "${RESOURCE_GROUP}" \
        --factory-name "${DATA_FACTORY}" \
        --name "ls_keyvault" \
        --properties '{
            "type": "AzureKeyVault",
            "typeProperties": {
                "baseUrl": "https://'${KEY_VAULT}'.vault.azure.net/"
            }
        }' --output none || warn "Key Vault linked service may already exist"
    
    # Create storage linked service
    az datafactory linked-service create \
        --resource-group "${RESOURCE_GROUP}" \
        --factory-name "${DATA_FACTORY}" \
        --name "ls_storage" \
        --properties '{
            "type": "AzureBlobFS",
            "typeProperties": {
                "url": "https://'${STORAGE_ACCOUNT}'.dfs.core.windows.net",
                "accountKey": {
                    "type": "AzureKeyVaultSecret",
                    "store": {
                        "referenceName": "ls_keyvault",
                        "type": "LinkedServiceReference"
                    },
                    "secretName": "storage-connection-string"
                }
            }
        }' --output none || warn "Storage linked service may already exist"
    
    log "Linked services created with secure credential management ✅"
}

# Function to configure Synapse external tables
configure_synapse_external_tables() {
    log "Configuring Synapse external tables..."
    
    SYNAPSE_ENDPOINT="${SYNAPSE_WORKSPACE}.sql.azuresynapse.net"
    
    # Wait for Synapse to be ready
    log "Waiting for Synapse workspace to be ready..."
    sleep 30
    
    # Create database in Synapse
    sqlcmd -S "${SYNAPSE_ENDPOINT}" -d master \
        -U sqladmin -P "${SQL_ADMIN_PASSWORD}" \
        -Q "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'StreamingAnalytics') CREATE DATABASE StreamingAnalytics" || warn "Database may already exist"
    
    # Create external data source
    sqlcmd -S "${SYNAPSE_ENDPOINT}" -d StreamingAnalytics \
        -U sqladmin -P "${SQL_ADMIN_PASSWORD}" \
        -Q "IF NOT EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'DataLakeStorage')
            CREATE EXTERNAL DATA SOURCE DataLakeStorage
            WITH (
                LOCATION = 'abfss://raw@${STORAGE_ACCOUNT}.dfs.core.windows.net',
                TYPE = HADOOP
            )" || warn "External data source may already exist"
    
    # Create external file format
    sqlcmd -S "${SYNAPSE_ENDPOINT}" -d StreamingAnalytics \
        -U sqladmin -P "${SQL_ADMIN_PASSWORD}" \
        -Q "IF NOT EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'ParquetFormat')
            CREATE EXTERNAL FILE FORMAT ParquetFormat
            WITH (
                FORMAT_TYPE = PARQUET,
                DATA_COMPRESSION = 'snappy'
            )" || warn "External file format may already exist"
    
    log "Synapse external tables configured for data lake access ✅"
}

# Function to create Data Factory pipeline components
create_data_factory_pipeline() {
    log "Creating Data Factory pipeline components..."
    
    # Create dataset for source data
    az datafactory dataset create \
        --resource-group "${RESOURCE_GROUP}" \
        --factory-name "${DATA_FACTORY}" \
        --name "ds_streaming_source" \
        --properties '{
            "linkedServiceName": {
                "referenceName": "ls_storage",
                "type": "LinkedServiceReference"
            },
            "type": "Json",
            "typeProperties": {
                "location": {
                    "type": "AzureBlobFSLocation",
                    "fileSystem": "raw",
                    "folderPath": "streaming-data"
                }
            }
        }' --output none || warn "Source dataset may already exist"
    
    # Create dataset for sink
    az datafactory dataset create \
        --resource-group "${RESOURCE_GROUP}" \
        --factory-name "${DATA_FACTORY}" \
        --name "ds_curated_sink" \
        --properties '{
            "linkedServiceName": {
                "referenceName": "ls_storage",
                "type": "LinkedServiceReference"
            },
            "type": "Parquet",
            "typeProperties": {
                "location": {
                    "type": "AzureBlobFSLocation",
                    "fileSystem": "curated",
                    "folderPath": "processed-data"
                }
            }
        }' --output none || warn "Sink dataset may already exist"
    
    log "Data Factory pipeline components created ✅"
}

# Function to configure monitoring and alerting
configure_monitoring() {
    log "Configuring monitoring and alerting..."
    
    # Enable diagnostic settings for Data Factory
    STORAGE_ID=$(az storage account show \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id -o tsv)
    
    az monitor diagnostic-settings create \
        --name "adf-diagnostics" \
        --resource $(az datafactory show \
            --name "${DATA_FACTORY}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query id -o tsv) \
        --storage-account "${STORAGE_ID}" \
        --logs '[{
            "category": "PipelineRuns",
            "enabled": true,
            "retentionPolicy": {"days": 30, "enabled": true}
        }]' --output none || warn "Diagnostic settings may already exist"
    
    # Create alert for pipeline failures
    az monitor metrics alert create \
        --name "pipeline-failure-alert" \
        --resource-group "${RESOURCE_GROUP}" \
        --scopes $(az datafactory show \
            --name "${DATA_FACTORY}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query id -o tsv) \
        --condition "count PipelineFailedRuns > 0" \
        --description "Alert when pipeline fails" \
        --output none || warn "Alert may already exist"
    
    log "Monitoring and alerting configured ✅"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check if all resources exist
    resources=("Microsoft.KeyVault/vaults" "Microsoft.Storage/storageAccounts" "Microsoft.Synapse/workspaces" "Microsoft.DataFactory/factories")
    for resource in "${resources[@]}"; do
        count=$(az resource list --resource-group "${RESOURCE_GROUP}" --resource-type "${resource}" --query "length(@)")
        if [ "$count" -eq 0 ]; then
            error "No resources of type ${resource} found in resource group ${RESOURCE_GROUP}"
            return 1
        fi
    done
    
    log "All resources validated successfully ✅"
    
    # Display resource information
    info "Deployment completed successfully!"
    info "Resource Group: ${RESOURCE_GROUP}"
    info "Storage Account: ${STORAGE_ACCOUNT}"
    info "Synapse Workspace: ${SYNAPSE_WORKSPACE}"
    info "Data Factory: ${DATA_FACTORY}"
    info "Key Vault: ${KEY_VAULT}"
    info "Synapse SQL Endpoint: ${SYNAPSE_WORKSPACE}.sql.azuresynapse.net"
    
    return 0
}

# Main deployment function
main() {
    log "Starting Azure Serverless Data Pipeline deployment..."
    
    # Check if running in dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        info "Running in dry-run mode. No resources will be created."
        set_environment_variables
        log "Dry-run completed. Use the following command to deploy:"
        log "./deploy.sh"
        exit 0
    fi
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    create_foundation_resources
    create_key_vault
    deploy_synapse_workspace
    configure_data_lake_structure
    deploy_data_factory
    create_linked_services
    configure_synapse_external_tables
    create_data_factory_pipeline
    configure_monitoring
    
    # Validate deployment
    if validate_deployment; then
        log "🎉 Deployment completed successfully!"
        info "You can now start building your serverless data pipeline."
        info "Remember to clean up resources when done to avoid unnecessary charges."
    else
        error "Deployment validation failed. Please check the logs above."
        exit 1
    fi
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may have been created."; exit 1' INT TERM

# Show usage if help is requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [--dry-run] [--help]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be deployed without actually creating resources"
    echo "  --help, -h   Show this help message"
    echo ""
    echo "Environment variables (optional):"
    echo "  RESOURCE_GROUP     Resource group name (default: rg-serverless-pipeline)"
    echo "  LOCATION           Azure region (default: eastus)"
    echo "  STORAGE_ACCOUNT    Storage account name (default: auto-generated)"
    echo "  SYNAPSE_WORKSPACE  Synapse workspace name (default: auto-generated)"
    echo "  DATA_FACTORY       Data factory name (default: auto-generated)"
    echo "  KEY_VAULT          Key vault name (default: auto-generated)"
    echo "  SQL_ADMIN_PASSWORD SQL admin password (default: P@ssw0rd123!)"
    exit 0
fi

# Run main function
main "$@"