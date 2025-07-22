#!/bin/bash

# =============================================================================
# Azure Database Modernization Deployment Script
# =============================================================================
# This script deploys Azure Database Migration Service, Azure SQL Database,
# Azure Backup, and monitoring infrastructure for database modernization.
#
# Recipe: Orchestrating Database Modernization with Azure Database Migration 
#         Service and Azure Backup
# Version: 1.0
# =============================================================================

set -euo pipefail

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show >/dev/null 2>&1; then
        error_exit "Not logged into Azure. Please run 'az login' first."
    fi
    
    # Check if required extensions are available
    local extensions=("datamigration")
    for ext in "${extensions[@]}"; do
        if ! az extension show --name "$ext" >/dev/null 2>&1; then
            log_warning "Extension '$ext' not found. Installing..."
            az extension add --name "$ext" --yes
        fi
    done
    
    log_success "Prerequisites validated"
}

# Set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-db-migration-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set specific resource names
    export SQL_SERVER_NAME="sqlserver-${RANDOM_SUFFIX}"
    export SQL_DATABASE_NAME="modernized-db"
    export DMS_SERVICE_NAME="dms-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="stgmigration${RANDOM_SUFFIX}"
    export BACKUP_VAULT_NAME="rsv-backup-${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_NAME="la-monitoring-${RANDOM_SUFFIX}"
    
    # SQL admin credentials (use strong password)
    export SQL_ADMIN_USER="sqladmin"
    export SQL_ADMIN_PASSWORD="ComplexP@ssw0rd123!"
    
    # Display configuration
    log "Configuration:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Location: $LOCATION"
    log "  Subscription ID: $SUBSCRIPTION_ID"
    log "  SQL Server Name: $SQL_SERVER_NAME"
    log "  Storage Account: $STORAGE_ACCOUNT_NAME"
    
    log_success "Environment variables set"
}

# Create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Resource group '$RESOURCE_GROUP' already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=database-migration environment=demo \
            --output none
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Create Log Analytics workspace
create_log_analytics() {
    log "Creating Log Analytics workspace..."
    
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --location "$LOCATION" \
        --sku PerGB2018 \
        --output none
    
    log_success "Log Analytics workspace created: $LOG_ANALYTICS_NAME"
}

# Create Azure SQL Database
create_sql_database() {
    log "Creating Azure SQL Database..."
    
    # Create Azure SQL Server
    log "Creating Azure SQL Server..."
    az sql server create \
        --name "$SQL_SERVER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --admin-user "$SQL_ADMIN_USER" \
        --admin-password "$SQL_ADMIN_PASSWORD" \
        --enable-public-network true \
        --output none
    
    # Create Azure SQL Database
    log "Creating Azure SQL Database..."
    az sql db create \
        --resource-group "$RESOURCE_GROUP" \
        --server "$SQL_SERVER_NAME" \
        --name "$SQL_DATABASE_NAME" \
        --service-objective S2 \
        --backup-storage-redundancy Local \
        --output none
    
    # Configure firewall to allow Azure services
    log "Configuring firewall rules..."
    az sql server firewall-rule create \
        --resource-group "$RESOURCE_GROUP" \
        --server "$SQL_SERVER_NAME" \
        --name AllowAzureServices \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0 \
        --output none
    
    log_success "Azure SQL Database created and configured"
}

# Create storage account
create_storage_account() {
    log "Creating storage account for migration assets..."
    
    # Create storage account
    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        --output none
    
    # Create container for database backups
    az storage container create \
        --name database-backups \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --public-access off \
        --output none
    
    log_success "Storage account created: $STORAGE_ACCOUNT_NAME"
}

# Create Database Migration Service
create_dms_service() {
    log "Creating Database Migration Service..."
    
    # Create DMS service instance
    az dms create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DMS_SERVICE_NAME" \
        --location "$LOCATION" \
        --sku Premium_4vCores \
        --output none
    
    # Wait for DMS service to be ready
    log "Waiting for DMS service to be ready..."
    az dms wait \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DMS_SERVICE_NAME" \
        --created \
        --timeout 600
    
    log_success "Database Migration Service created: $DMS_SERVICE_NAME"
}

# Create Recovery Services Vault
create_backup_vault() {
    log "Creating Recovery Services Vault..."
    
    # Create Recovery Services Vault
    az backup vault create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$BACKUP_VAULT_NAME" \
        --location "$LOCATION" \
        --storage-model-type LocallyRedundant \
        --output none
    
    # Enable backup for Azure SQL Database
    log "Enabling backup for Azure SQL Database..."
    local sql_resource_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Sql/servers/${SQL_SERVER_NAME}/databases/${SQL_DATABASE_NAME}"
    
    az backup protection enable-for-azuresqldb \
        --resource-group "$RESOURCE_GROUP" \
        --vault-name "$BACKUP_VAULT_NAME" \
        --resource-id "$sql_resource_id" \
        --policy-name DefaultSQLPolicy \
        --output none
    
    log_success "Recovery Services Vault created and backup enabled"
}

# Create migration project
create_migration_project() {
    log "Creating migration project..."
    
    # Create migration project
    az dms project create \
        --resource-group "$RESOURCE_GROUP" \
        --service-name "$DMS_SERVICE_NAME" \
        --name "sqlserver-to-azuresql-migration" \
        --source-platform SQL \
        --target-platform SQLDB \
        --location "$LOCATION" \
        --output none
    
    log_success "Migration project created"
}

# Configure monitoring
configure_monitoring() {
    log "Configuring Azure Monitor..."
    
    # Create action group for alerts
    az monitor action-group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "migration-alerts" \
        --short-name "migration" \
        --output none
    
    # Create metric alert for migration failures
    local dms_resource_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DataMigration/services/${DMS_SERVICE_NAME}"
    
    az monitor metrics alert create \
        --resource-group "$RESOURCE_GROUP" \
        --name "migration-failure-alert" \
        --description "Alert for migration failures" \
        --scopes "$dms_resource_id" \
        --condition "count static > 0" \
        --action-group "migration-alerts" \
        --evaluation-frequency 1m \
        --window-size 5m \
        --output none
    
    # Enable diagnostic settings for DMS
    local workspace_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${LOG_ANALYTICS_NAME}"
    
    az monitor diagnostic-settings create \
        --resource "$dms_resource_id" \
        --name "dms-diagnostics" \
        --workspace "$workspace_id" \
        --logs '[{"category": "DataMigrationService", "enabled": true}]' \
        --metrics '[{"category": "AllMetrics", "enabled": true}]' \
        --output none
    
    log_success "Azure Monitor configured"
}

# Create custom backup policy
create_backup_policy() {
    log "Creating custom backup policy..."
    
    # Create backup policy JSON
    local policy_json=$(cat <<EOF
{
    "backupManagementType": "AzureSql",
    "workLoadType": "SQLDataBase",
    "settings": {
        "timeZone": "UTC",
        "issqlcompression": true,
        "isCompression": true
    },
    "subProtectionPolicy": [{
        "policyType": "Full",
        "schedulePolicy": {
            "schedulePolicyType": "SimpleSchedulePolicy",
            "scheduleRunFrequency": "Daily",
            "scheduleRunTimes": ["$(date -u +%Y-%m-%dT02:00:00Z)"]
        },
        "retentionPolicy": {
            "retentionPolicyType": "LongTermRetentionPolicy",
            "dailySchedule": {
                "retentionTimes": ["$(date -u +%Y-%m-%dT02:00:00Z)"],
                "retentionDuration": {
                    "count": 30,
                    "durationType": "Days"
                }
            }
        }
    }]
}
EOF
)
    
    # Create custom backup policy
    az backup policy create \
        --resource-group "$RESOURCE_GROUP" \
        --vault-name "$BACKUP_VAULT_NAME" \
        --name "CustomSQLBackupPolicy" \
        --policy "$policy_json" \
        --output none
    
    log_success "Custom backup policy created"
}

# Create monitoring dashboard
create_monitoring_dashboard() {
    log "Creating monitoring dashboard..."
    
    # Create dashboard JSON
    local dashboard_json=$(cat <<EOF
{
    "lenses": {
        "0": {
            "order": 0,
            "parts": {
                "0": {
                    "position": {"x": 0, "y": 0, "rowSpan": 4, "colSpan": 6},
                    "metadata": {
                        "inputs": [{
                            "name": "resourceId",
                            "value": "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DataMigration/services/${DMS_SERVICE_NAME}"
                        }],
                        "type": "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
                    }
                }
            }
        }
    }
}
EOF
)
    
    # Create dashboard
    echo "$dashboard_json" | az portal dashboard create \
        --resource-group "$RESOURCE_GROUP" \
        --name "database-migration-dashboard" \
        --input-path /dev/stdin \
        --output none
    
    # Create alert for backup failures
    local vault_resource_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.RecoveryServices/vaults/${BACKUP_VAULT_NAME}"
    
    az monitor metrics alert create \
        --resource-group "$RESOURCE_GROUP" \
        --name "backup-failure-alert" \
        --description "Alert for backup failures" \
        --scopes "$vault_resource_id" \
        --condition "count static > 0" \
        --action-group "migration-alerts" \
        --output none
    
    log_success "Monitoring dashboard and alerts configured"
}

# Display deployment summary
display_summary() {
    log "Deployment Summary:"
    log "=================="
    log "Resource Group: $RESOURCE_GROUP"
    log "Location: $LOCATION"
    log "SQL Server: $SQL_SERVER_NAME"
    log "SQL Database: $SQL_DATABASE_NAME"
    log "DMS Service: $DMS_SERVICE_NAME"
    log "Storage Account: $STORAGE_ACCOUNT_NAME"
    log "Backup Vault: $BACKUP_VAULT_NAME"
    log "Log Analytics: $LOG_ANALYTICS_NAME"
    log ""
    log "Next Steps:"
    log "1. Configure source database connection in DMS"
    log "2. Run migration assessment"
    log "3. Execute schema migration"
    log "4. Perform data migration"
    log "5. Validate migration results"
    log ""
    log "Access Azure Portal to monitor migration progress:"
    log "https://portal.azure.com/#@/resource/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/overview"
}

# Main deployment function
main() {
    log "Starting Azure Database Modernization deployment..."
    log "=================================================="
    
    # Validate prerequisites
    validate_prerequisites
    
    # Set environment variables
    set_environment_variables
    
    # Create resources
    create_resource_group
    create_log_analytics
    create_sql_database
    create_storage_account
    create_dms_service
    create_backup_vault
    create_migration_project
    configure_monitoring
    create_backup_policy
    create_monitoring_dashboard
    
    # Display summary
    display_summary
    
    log_success "Deployment completed successfully!"
    log "Total deployment time: $SECONDS seconds"
}

# Handle script interruption
trap 'error_exit "Script interrupted by user"' INT TERM

# Run main function
main "$@"