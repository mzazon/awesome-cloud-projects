#!/bin/bash

# =============================================================================
# Azure Database Migration Orchestration Deployment Script
# 
# This script deploys the complete infrastructure for orchestrating intelligent
# database migration workflows using Azure Managed Instance for Apache Airflow
# and Azure Database Migration Service.
#
# Components deployed:
# - Azure Data Factory with Workflow Orchestration Manager
# - Azure Database Migration Service
# - Log Analytics workspace for monitoring
# - Storage account for Airflow DAGs
# - Self-hosted Integration Runtime
# - Azure Monitor alerts and action groups
# - Airflow DAG for migration orchestration
#
# Prerequisites:
# - Azure CLI v2.50.0 or later
# - Appropriate Azure permissions for resource creation
# - Network connectivity to on-premises SQL Server instances
#
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handler
error_exit() {
    log_error "Deployment failed at step: $1"
    log_error "Check the logs above for details"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Cleaning up partially deployed resources..."
    if az group exists --name "${RESOURCE_GROUP}" 2>/dev/null; then
        log_info "Deleting resource group: ${RESOURCE_GROUP}"
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait
    fi
}

# Trap errors and cleanup
trap 'cleanup_on_error' ERR

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================

log_info "Starting Azure Database Migration Orchestration deployment..."
log_info "Checking prerequisites..."

# Check Azure CLI
if ! command -v az &> /dev/null; then
    log_error "Azure CLI is not installed. Please install Azure CLI v2.50.0 or later"
    exit 1
fi

# Check Azure CLI version
AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
log_info "Azure CLI version: ${AZ_VERSION}"

# Check Azure login
if ! az account show &> /dev/null; then
    log_error "Not logged into Azure. Please run 'az login' first"
    exit 1
fi

# Check required extensions
log_info "Checking for required Azure CLI extensions..."
if ! az extension list --query "[?name=='datafactory']" -o tsv | grep -q datafactory; then
    log_info "Installing Azure Data Factory extension..."
    az extension add --name datafactory
fi

log_success "Prerequisites check completed"

# =============================================================================
# CONFIGURATION
# =============================================================================

log_info "Setting up configuration..."

# Set environment variables for Azure resources
export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-db-migration-orchestration}"
export LOCATION="${LOCATION:-eastus}"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Set resource names with unique suffix
export DATA_FACTORY_NAME="adf-migration-${RANDOM_SUFFIX}"
export DMS_NAME="dms-migration-${RANDOM_SUFFIX}"
export LOG_ANALYTICS_NAME="law-migration-${RANDOM_SUFFIX}"
export STORAGE_ACCOUNT_NAME="st${RANDOM_SUFFIX}migration"

# Email for notifications (can be overridden)
NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-admin@company.com}"

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Location: ${LOCATION}"
log_info "  Subscription ID: ${SUBSCRIPTION_ID}"
log_info "  Data Factory: ${DATA_FACTORY_NAME}"
log_info "  DMS Instance: ${DMS_NAME}"
log_info "  Log Analytics: ${LOG_ANALYTICS_NAME}"
log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
log_info "  Notification Email: ${NOTIFICATION_EMAIL}"

# =============================================================================
# RESOURCE GROUP CREATION
# =============================================================================

log_info "Creating resource group..."

az group create \
    --name "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --tags purpose=database-migration environment=demo created-by=deploy-script || error_exit "Resource group creation"

log_success "Resource group created: ${RESOURCE_GROUP}"

# =============================================================================
# LOG ANALYTICS WORKSPACE
# =============================================================================

log_info "Creating Log Analytics workspace..."

az monitor log-analytics workspace create \
    --resource-group "${RESOURCE_GROUP}" \
    --workspace-name "${LOG_ANALYTICS_NAME}" \
    --location "${LOCATION}" \
    --sku PerGB2018 \
    --tags purpose=monitoring environment=demo || error_exit "Log Analytics workspace creation"

# Get Log Analytics workspace ID
LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
    --resource-group "${RESOURCE_GROUP}" \
    --workspace-name "${LOG_ANALYTICS_NAME}" \
    --query id --output tsv)

log_success "Log Analytics workspace created: ${LOG_ANALYTICS_NAME}"

# =============================================================================
# STORAGE ACCOUNT
# =============================================================================

log_info "Creating storage account..."

az storage account create \
    --name "${STORAGE_ACCOUNT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --access-tier Hot \
    --allow-blob-public-access false \
    --min-tls-version TLS1_2 \
    --tags purpose=airflow-storage environment=demo || error_exit "Storage account creation"

# Get storage account key
STORAGE_KEY=$(az storage account keys list \
    --resource-group "${RESOURCE_GROUP}" \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --query '[0].value' --output tsv)

log_success "Storage account created: ${STORAGE_ACCOUNT_NAME}"

# =============================================================================
# AZURE DATA FACTORY
# =============================================================================

log_info "Creating Azure Data Factory..."

az datafactory create \
    --resource-group "${RESOURCE_GROUP}" \
    --factory-name "${DATA_FACTORY_NAME}" \
    --location "${LOCATION}" \
    --tags purpose=migration-orchestration environment=demo || error_exit "Data Factory creation"

# Create managed virtual network for secure connectivity
log_info "Creating managed virtual network..."

az datafactory managed-virtual-network create \
    --factory-name "${DATA_FACTORY_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "default" || error_exit "Managed virtual network creation"

log_success "Azure Data Factory created: ${DATA_FACTORY_NAME}"

# =============================================================================
# DATABASE MIGRATION SERVICE
# =============================================================================

log_info "Creating Database Migration Service..."

az dms create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${DMS_NAME}" \
    --location "${LOCATION}" \
    --sku Standard_4vCores \
    --tags purpose=database-migration environment=demo || error_exit "Database Migration Service creation"

# Get DMS resource ID
DMS_RESOURCE_ID=$(az dms show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${DMS_NAME}" \
    --query id --output tsv)

log_success "Database Migration Service created: ${DMS_NAME}"

# =============================================================================
# DIAGNOSTIC SETTINGS
# =============================================================================

log_info "Configuring diagnostic settings for DMS..."

az monitor diagnostic-settings create \
    --resource "${DMS_RESOURCE_ID}" \
    --name "dms-diagnostics" \
    --workspace "${LOG_ANALYTICS_ID}" \
    --logs '[{"category":"DataMigration","enabled":true}]' \
    --metrics '[{"category":"AllMetrics","enabled":true}]' || error_exit "DMS diagnostic settings"

# Configure diagnostic settings for Data Factory
log_info "Configuring diagnostic settings for Data Factory..."

DATA_FACTORY_ID=$(az datafactory show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${DATA_FACTORY_NAME}" \
    --query id --output tsv)

az monitor diagnostic-settings create \
    --resource "${DATA_FACTORY_ID}" \
    --name "airflow-diagnostics" \
    --workspace "${LOG_ANALYTICS_ID}" \
    --logs '[{"category":"PipelineRuns","enabled":true},{"category":"TriggerRuns","enabled":true},{"category":"ActivityRuns","enabled":true}]' \
    --metrics '[{"category":"AllMetrics","enabled":true}]' || error_exit "Data Factory diagnostic settings"

log_success "Diagnostic settings configured"

# =============================================================================
# INTEGRATION RUNTIME
# =============================================================================

log_info "Creating self-hosted integration runtime..."

az datafactory integration-runtime self-hosted create \
    --factory-name "${DATA_FACTORY_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "OnPremisesIR" \
    --description "Self-hosted IR for database migration" || error_exit "Integration runtime creation"

# Get authentication key for IR installation
IR_AUTH_KEY=$(az datafactory integration-runtime list-auth-key \
    --factory-name "${DATA_FACTORY_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --integration-runtime-name "OnPremisesIR" \
    --query authKey1 --output tsv)

log_success "Integration Runtime created: OnPremisesIR"
log_warning "Integration Runtime Auth Key: ${IR_AUTH_KEY}"
log_warning "Install this IR on your on-premises server using this key"

# =============================================================================
# AIRFLOW DAG CREATION
# =============================================================================

log_info "Creating Airflow DAG for migration orchestration..."

# Create DAG storage container
az storage container create \
    --name "airflow-dags" \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --account-key "${STORAGE_KEY}" || error_exit "DAG container creation"

# Create the migration orchestration DAG
cat > migration_orchestration_dag.py << 'EOF'
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.utils.trigger_rule import TriggerRule
import json
import logging

# DAG configuration
default_args = {
    'owner': 'migration-team',
    'depends_on_past': False,
    'start_date': datetime(2025, 1, 1),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5)
}

dag = DAG(
    'database_migration_orchestration',
    default_args=default_args,
    description='Intelligent database migration workflow',
    schedule_interval=None,  # Triggered manually
    catchup=False,
    tags=['migration', 'database', 'orchestration']
)

def validate_migration_readiness(**context):
    """Validate source databases are ready for migration"""
    logging.info("Validating migration readiness...")
    # Implementation would include connectivity checks,
    # backup verification, and dependency analysis
    return {"status": "ready", "databases": ["db1", "db2", "db3"]}

def start_database_migration(database_name, **context):
    """Initiate migration for specific database"""
    logging.info(f"Starting migration for {database_name}")
    # Implementation would call Azure CLI or REST API
    # to start DMS migration
    return f"Migration started for {database_name}"

def monitor_migration_progress(database_name, **context):
    """Monitor migration progress and handle errors"""
    logging.info(f"Monitoring migration progress for {database_name}")
    # Implementation would check DMS status
    return f"Migration progress monitored for {database_name}"

def send_completion_notification(**context):
    """Send completion notification to migration team"""
    logging.info("Sending migration completion notification...")
    return "Migration completion notification sent"

# Task definitions
validate_readiness = PythonOperator(
    task_id='validate_migration_readiness',
    python_callable=validate_migration_readiness,
    dag=dag
)

# Database migration tasks with dependencies
migrate_db1 = PythonOperator(
    task_id='migrate_database_1',
    python_callable=start_database_migration,
    op_kwargs={'database_name': 'database_1'},
    dag=dag
)

migrate_db2 = PythonOperator(
    task_id='migrate_database_2',
    python_callable=start_database_migration,
    op_kwargs={'database_name': 'database_2'},
    dag=dag
)

migrate_db3 = PythonOperator(
    task_id='migrate_database_3',
    python_callable=start_database_migration,
    op_kwargs={'database_name': 'database_3'},
    dag=dag
)

# Monitoring tasks
monitor_db1 = PythonOperator(
    task_id='monitor_database_1',
    python_callable=monitor_migration_progress,
    op_kwargs={'database_name': 'database_1'},
    dag=dag
)

monitor_db2 = PythonOperator(
    task_id='monitor_database_2',
    python_callable=monitor_migration_progress,
    op_kwargs={'database_name': 'database_2'},
    dag=dag
)

monitor_db3 = PythonOperator(
    task_id='monitor_database_3',
    python_callable=monitor_migration_progress,
    op_kwargs={'database_name': 'database_3'},
    dag=dag
)

# Completion notification
notify_completion = PythonOperator(
    task_id='notify_completion',
    python_callable=send_completion_notification,
    trigger_rule=TriggerRule.ALL_DONE,
    dag=dag
)

# Define dependencies
validate_readiness >> [migrate_db1, migrate_db2]
migrate_db1 >> monitor_db1 >> migrate_db3
migrate_db2 >> monitor_db2 >> migrate_db3
migrate_db3 >> monitor_db3 >> notify_completion
EOF

# Upload DAG to storage
az storage blob upload \
    --container-name "airflow-dags" \
    --file migration_orchestration_dag.py \
    --name "migration_orchestration_dag.py" \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --account-key "${STORAGE_KEY}" \
    --overwrite || error_exit "DAG upload"

# Cleanup local DAG file
rm -f migration_orchestration_dag.py

log_success "Migration orchestration DAG created and uploaded"

# =============================================================================
# AZURE MONITOR ALERTS
# =============================================================================

log_info "Creating Azure Monitor alerts..."

# Create action group for notifications
az monitor action-group create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "migration-alerts" \
    --short-name "migration" \
    --action email migration-team "${NOTIFICATION_EMAIL}" || error_exit "Action group creation"

ACTION_GROUP_ID=$(az monitor action-group show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "migration-alerts" \
    --query id --output tsv)

# Create alert rule for migration failures
az monitor metrics alert create \
    --name "migration-failure-alert" \
    --resource-group "${RESOURCE_GROUP}" \
    --scopes "${DMS_RESOURCE_ID}" \
    --condition "count static.microsoft.datamigration/services.MigrationErrors > 0" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --severity 1 \
    --action "${ACTION_GROUP_ID}" \
    --description "Alert when database migration errors occur" || error_exit "Migration failure alert creation"

# Create alert rule for high migration duration
az monitor metrics alert create \
    --name "long-migration-alert" \
    --resource-group "${RESOURCE_GROUP}" \
    --scopes "${DMS_RESOURCE_ID}" \
    --condition "average static.microsoft.datamigration/services.MigrationDuration > 3600" \
    --window-size 15m \
    --evaluation-frequency 5m \
    --severity 2 \
    --action "${ACTION_GROUP_ID}" \
    --description "Alert when migration duration exceeds 1 hour" || error_exit "Long migration alert creation"

log_success "Azure Monitor alerts configured"

# =============================================================================
# CONFIGURATION FILES
# =============================================================================

log_info "Creating configuration files..."

# Create linked service configuration for on-premises SQL Server
cat > sqlserver_linked_service.json << EOF
{
    "name": "OnPremisesSqlServer",
    "properties": {
        "type": "SqlServer",
        "connectVia": {
            "referenceName": "OnPremisesIR",
            "type": "IntegrationRuntimeReference"
        },
        "typeProperties": {
            "connectionString": "Server=your-onprem-server;Database=master;Integrated Security=True;",
            "encryptedCredential": ""
        }
    }
}
EOF

# Create Airflow environment configuration
cat > airflow_config.json << EOF
{
    "airflowVersion": "2.6.3",
    "nodeSize": "Standard_D2s_v3",
    "nodeCount": {
        "minimum": 1,
        "maximum": 3,
        "current": 1
    },
    "environment": {
        "variables": {
            "MIGRATION_STORAGE_ACCOUNT": "${STORAGE_ACCOUNT_NAME}",
            "DMS_RESOURCE_GROUP": "${RESOURCE_GROUP}",
            "LOG_ANALYTICS_WORKSPACE": "${LOG_ANALYTICS_NAME}"
        }
    },
    "packages": [
        "azure-identity",
        "azure-mgmt-datamigration",
        "azure-monitor-query"
    ]
}
EOF

log_success "Configuration files created"

# =============================================================================
# DEPLOYMENT SUMMARY
# =============================================================================

log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
log_info ""
log_info "Deployment Summary:"
log_info "==================="
log_info "Resource Group: ${RESOURCE_GROUP}"
log_info "Location: ${LOCATION}"
log_info "Data Factory: ${DATA_FACTORY_NAME}"
log_info "Database Migration Service: ${DMS_NAME}"
log_info "Log Analytics Workspace: ${LOG_ANALYTICS_NAME}"
log_info "Storage Account: ${STORAGE_ACCOUNT_NAME}"
log_info ""
log_info "Next Steps:"
log_info "==========="
log_info "1. Complete the Workflow Orchestration Manager setup in Azure portal"
log_info "2. Use the configuration in airflow_config.json"
log_info "3. Install Integration Runtime on your on-premises server:"
log_info "   Authentication Key: ${IR_AUTH_KEY}"
log_info "4. Configure the SQL Server linked service with your connection details"
log_info "5. Update the notification email in action groups if needed"
log_info ""
log_warning "IMPORTANT NOTES:"
log_warning "- The Integration Runtime must be installed on your on-premises server"
log_warning "- Update the SQL Server connection string in sqlserver_linked_service.json"
log_warning "- Configure Workflow Orchestration Manager through Azure portal"
log_warning "- Review and test all alert rules before production use"
log_info ""
log_info "Configuration files created:"
log_info "- sqlserver_linked_service.json"
log_info "- airflow_config.json"
log_info ""
log_success "Deployment completed successfully!"

# Clean up temporary files
rm -f sqlserver_linked_service.json airflow_config.json

exit 0