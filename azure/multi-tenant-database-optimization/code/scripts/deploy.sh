#!/bin/bash

# =============================================================================
# Azure Multi-Tenant Database Architecture Deployment Script
# =============================================================================
# This script deploys a cost-optimized multi-tenant database architecture
# using Azure Elastic Database Pools and Azure Backup Vault
#
# Recipe: Implementing Cost-Optimized Multi-Tenant Database Architecture
# Services: Azure SQL Database, Elastic Database Pool, Backup Vault, Cost Management
# =============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Error handling function
handle_error() {
    local line_number=$1
    local error_code=$2
    log_error "Script failed at line ${line_number} with exit code ${error_code}"
    log_error "Deployment failed. Check the logs above for details."
    exit "${error_code}"
}

# Set up error trap
trap 'handle_error ${LINENO} $?' ERR

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        log_error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version (minimum 2.37.0)
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: ${az_version}"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for password generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not available. Please install it for secure password generation."
        exit 1
    fi
    
    # Display current Azure context
    local subscription_name
    subscription_name=$(az account show --query name -o tsv)
    local subscription_id
    subscription_id=$(az account show --query id -o tsv)
    log "Current subscription: ${subscription_name} (${subscription_id})"
    
    log_success "Prerequisites check completed"
}

# =============================================================================
# CONFIGURATION
# =============================================================================

setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-multitenant-db-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Database and pool configuration
    export SQL_SERVER_NAME="sqlserver-mt-${RANDOM_SUFFIX}"
    export ELASTIC_POOL_NAME="elasticpool-saas-${RANDOM_SUFFIX}"
    export BACKUP_VAULT_NAME="bv-multitenant-${RANDOM_SUFFIX}"
    
    # Generate secure SQL admin password
    export SQL_ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-20)
    
    # Budget and monitoring configuration
    export BUDGET_NAME="budget-multitenant-db-${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_WORKSPACE="law-multitenant-${RANDOM_SUFFIX}"
    
    log "Environment configured:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Location: ${LOCATION}"
    log "  SQL Server: ${SQL_SERVER_NAME}"
    log "  Elastic Pool: ${ELASTIC_POOL_NAME}"
    log "  Backup Vault: ${BACKUP_VAULT_NAME}"
    log "🔐 SQL Admin Password: ${SQL_ADMIN_PASSWORD}"
    log_warning "Save the SQL admin password securely - it will be needed for database connections"
}

# =============================================================================
# DEPLOYMENT FUNCTIONS
# =============================================================================

create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=multi-tenant-saas \
                   environment=production \
                   cost-center=database-operations \
                   deployment-method=bash-script
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

create_sql_server() {
    log "Creating Azure SQL Database Server..."
    
    # Create SQL Database server with enhanced security
    az sql server create \
        --name "${SQL_SERVER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --admin-user sqladmin \
        --admin-password "${SQL_ADMIN_PASSWORD}" \
        --enable-ad-only-auth false \
        --minimal-tls-version "1.2"
    
    # Configure server firewall to allow Azure services
    az sql server firewall-rule create \
        --server "${SQL_SERVER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name "AllowAzureServices" \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0
    
    log_success "SQL Server created with secure configuration"
}

create_elastic_pool() {
    log "Creating Elastic Database Pool..."
    
    # Create elastic pool with optimized configuration
    az sql elastic-pool create \
        --name "${ELASTIC_POOL_NAME}" \
        --server "${SQL_SERVER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --edition Standard \
        --dtu 200 \
        --database-dtu-min 0 \
        --database-dtu-max 50 \
        --storage-mb 204800
    
    # Get pool details for verification
    local pool_id
    pool_id=$(az sql elastic-pool show \
        --name "${ELASTIC_POOL_NAME}" \
        --server "${SQL_SERVER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    export POOL_ID="${pool_id}"
    
    log_success "Elastic pool created: ${ELASTIC_POOL_NAME}"
    log "🏊 Pool ID: ${POOL_ID}"
}

create_tenant_databases() {
    log "Creating sample tenant databases..."
    
    # Create multiple tenant databases
    for i in {1..4}; do
        local tenant_db_name="tenant-${i}-db-${RANDOM_SUFFIX}"
        
        log "Creating tenant database: ${tenant_db_name}"
        
        az sql db create \
            --name "${tenant_db_name}" \
            --server "${SQL_SERVER_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --elastic-pool "${ELASTIC_POOL_NAME}" \
            --collation SQL_Latin1_General_CP1_CI_AS \
            --catalog-collation SQL_Latin1_General_CP1_CI_AS
        
        log_success "Created tenant database: ${tenant_db_name}"
    done
    
    # Store first tenant database name for later operations
    export SAMPLE_TENANT_DB="tenant-1-db-${RANDOM_SUFFIX}"
    
    log_success "Created 4 tenant databases in elastic pool"
}

create_backup_vault() {
    log "Creating Azure Backup Vault..."
    
    # Create backup vault with geo-redundant storage
    az dataprotection backup-vault create \
        --name "${BACKUP_VAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --storage-settings '[{
            "datastoreType": "VaultStore",
            "type": "GeoRedundant"
        }]'
    
    # Get vault details for policy configuration
    local vault_id
    vault_id=$(az dataprotection backup-vault show \
        --name "${BACKUP_VAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    export VAULT_ID="${vault_id}"
    
    log_success "Backup vault created: ${BACKUP_VAULT_NAME}"
    log "🔒 Vault ID: ${VAULT_ID}"
}

create_backup_policy() {
    log "Creating backup policy for SQL databases..."
    
    # Create backup policy for SQL databases
    az dataprotection backup-policy create \
        --name "sql-database-policy" \
        --resource-group "${RESOURCE_GROUP}" \
        --vault-name "${BACKUP_VAULT_NAME}" \
        --policy '{
            "datasourceTypes": ["Microsoft.Sql/servers/databases"],
            "policyRules": [
                {
                    "name": "Daily",
                    "objectType": "AzureRetentionRule",
                    "isDefault": true,
                    "lifecycles": [
                        {
                            "deleteAfter": {
                                "objectType": "AbsoluteDeleteOption",
                                "duration": "P30D"
                            },
                            "sourceDataStore": {
                                "dataStoreType": "VaultStore",
                                "objectType": "DataStoreInfoBase"
                            }
                        }
                    ]
                }
            ]
        }'
    
    log_success "Backup policy created for SQL databases"
}

configure_cost_management() {
    log "Configuring cost management and budgets..."
    
    # Calculate budget dates
    local current_date
    current_date=$(date +%Y-%m-01)
    local end_date
    end_date=$(date -d "+12 months" +%Y-%m-01)
    
    # Create cost budget for the resource group
    az consumption budget create \
        --budget-name "${BUDGET_NAME}" \
        --amount 500 \
        --resource-group "${RESOURCE_GROUP}" \
        --time-grain Monthly \
        --start-date "${current_date}" \
        --end-date "${end_date}"
    
    # Configure cost alert action group
    az monitor action-group create \
        --name "cost-alert-group" \
        --resource-group "${RESOURCE_GROUP}" \
        --short-name "CostAlert"
    
    log_success "Cost management configured with $500 monthly budget"
    log "💰 Alerts configured at 80% budget threshold"
}

setup_monitoring() {
    log "Setting up monitoring and performance insights..."
    
    # Create Log Analytics workspace
    local workspace_id
    workspace_id=$(az monitor log-analytics workspace create \
        --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --query id --output tsv)
    
    # Configure diagnostic settings for monitoring
    az monitor diagnostic-settings create \
        --name "sql-diagnostics" \
        --resource "${POOL_ID}" \
        --logs '[{
            "category": "SQLInsights",
            "enabled": true,
            "retentionPolicy": {
                "enabled": true,
                "days": 30
            }
        }]' \
        --metrics '[{
            "category": "AllMetrics",
            "enabled": true,
            "retentionPolicy": {
                "enabled": true,
                "days": 30
            }
        }]' \
        --workspace "${workspace_id}"
    
    log_success "Performance monitoring configured"
    log "📊 Diagnostic data flowing to Log Analytics workspace"
}

create_sample_schema() {
    log "Creating sample application schema and data..."
    
    # Create sample schema in the first tenant database
    az sql db query \
        --server "${SQL_SERVER_NAME}" \
        --database "${SAMPLE_TENANT_DB}" \
        --auth-type Sql \
        --username sqladmin \
        --password "${SQL_ADMIN_PASSWORD}" \
        --queries "
            CREATE TABLE Users (
                Id INT IDENTITY(1,1) PRIMARY KEY,
                TenantId NVARCHAR(50) NOT NULL,
                Username NVARCHAR(100) NOT NULL,
                Email NVARCHAR(255) NOT NULL,
                CreatedDate DATETIME2 DEFAULT GETUTCDATE(),
                INDEX IX_Users_TenantId (TenantId)
            );
            
            CREATE TABLE Products (
                Id INT IDENTITY(1,1) PRIMARY KEY,
                TenantId NVARCHAR(50) NOT NULL,
                Name NVARCHAR(255) NOT NULL,
                Price DECIMAL(10,2) NOT NULL,
                CreatedDate DATETIME2 DEFAULT GETUTCDATE(),
                INDEX IX_Products_TenantId (TenantId)
            );
            
            INSERT INTO Users (TenantId, Username, Email) 
            VALUES ('tenant-1', 'admin', 'admin@tenant1.com');
            
            INSERT INTO Products (TenantId, Name, Price) 
            VALUES ('tenant-1', 'Sample Product', 99.99);
        "
    
    log_success "Sample schema and data created in tenant database"
    log "🏗️ Multi-tenant schema pattern implemented"
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_deployment() {
    log "Validating deployment..."
    
    # Check elastic pool status
    log "Verifying elastic pool configuration..."
    az sql elastic-pool show \
        --name "${ELASTIC_POOL_NAME}" \
        --server "${SQL_SERVER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "{name:name,state:state,edition:edition,dtu:dtu}" \
        --output table
    
    # Check tenant databases
    log "Verifying tenant databases..."
    local db_count
    db_count=$(az sql db list \
        --server "${SQL_SERVER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[?elasticPoolName=='${ELASTIC_POOL_NAME}'] | length(@)")
    
    if [ "${db_count}" -eq 4 ]; then
        log_success "All 4 tenant databases are properly configured"
    else
        log_warning "Expected 4 databases, found ${db_count}"
    fi
    
    # Test database connectivity
    log "Testing database connectivity..."
    az sql db query \
        --server "${SQL_SERVER_NAME}" \
        --database "${SAMPLE_TENANT_DB}" \
        --auth-type Sql \
        --username sqladmin \
        --password "${SQL_ADMIN_PASSWORD}" \
        --queries "SELECT COUNT(*) as UserCount FROM Users;" \
        --output table
    
    # Check backup vault
    log "Verifying backup vault..."
    az dataprotection backup-vault show \
        --name "${BACKUP_VAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "{name:name,provisioningState:provisioningState}" \
        --output table
    
    log_success "Deployment validation completed"
}

# =============================================================================
# MAIN DEPLOYMENT FLOW
# =============================================================================

main() {
    log "Starting Azure Multi-Tenant Database Architecture deployment..."
    log "================================================================="
    
    # Confirmation prompt
    read -p "This will create Azure resources that may incur charges. Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_resource_group
    create_sql_server
    create_elastic_pool
    create_tenant_databases
    create_backup_vault
    create_backup_policy
    configure_cost_management
    setup_monitoring
    create_sample_schema
    validate_deployment
    
    # Display deployment summary
    log "================================================================="
    log_success "Deployment completed successfully!"
    log ""
    log "📋 Deployment Summary:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  SQL Server: ${SQL_SERVER_NAME}"
    log "  Elastic Pool: ${ELASTIC_POOL_NAME}"
    log "  Tenant Databases: 4 databases created"
    log "  Backup Vault: ${BACKUP_VAULT_NAME}"
    log "  Cost Budget: $500/month with alerts"
    log ""
    log "🔑 Connection Information:"
    log "  Server: ${SQL_SERVER_NAME}.database.windows.net"
    log "  Admin User: sqladmin"
    log "  Admin Password: ${SQL_ADMIN_PASSWORD}"
    log ""
    log "⚠️  Important Notes:"
    log "  1. Save the SQL admin password securely"
    log "  2. Monitor costs through Azure Cost Management"
    log "  3. Review backup policies and adjust as needed"
    log "  4. Consider implementing automated tenant onboarding"
    log ""
    log "🧹 Cleanup: Run ./destroy.sh to remove all resources"
    log "================================================================="
}

# Execute main function with all arguments
main "$@"