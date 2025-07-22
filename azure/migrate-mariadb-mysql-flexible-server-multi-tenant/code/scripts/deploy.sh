#!/bin/bash

# Azure MariaDB to MySQL Flexible Server Migration - Deployment Script
# This script deploys the complete infrastructure for migrating multi-tenant
# database workloads from Azure Database for MariaDB to MySQL Flexible Server

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if MySQL client is installed
    if ! command -v mysql &> /dev/null; then
        warning "MySQL client is not installed. Some validation steps may fail."
    fi
    
    # Check if MyDumper is installed
    if ! command -v mydumper &> /dev/null; then
        warning "MyDumper is not installed. Data migration will require manual installation."
    fi
    
    # Check Azure CLI login status
    if ! az account show &> /dev/null; then
        error "Not logged into Azure CLI. Please run 'az login' first."
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Core configuration
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-mariadb-migration}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    
    # Generate unique suffix for resource names
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
        log "Generated random suffix: ${RANDOM_SUFFIX}"
    fi
    
    # Source MariaDB server details
    export SOURCE_MARIADB_SERVER="${SOURCE_MARIADB_SERVER:-mariadb-source-${RANDOM_SUFFIX}}"
    export SOURCE_MARIADB_ADMIN="${SOURCE_MARIADB_ADMIN:-mariadbadmin}"
    export SOURCE_MARIADB_PASSWORD="${SOURCE_MARIADB_PASSWORD:-MariaDB123!}"
    
    # Target MySQL Flexible Server details
    export TARGET_MYSQL_SERVER="${TARGET_MYSQL_SERVER:-mysql-target-${RANDOM_SUFFIX}}"
    export TARGET_MYSQL_ADMIN="${TARGET_MYSQL_ADMIN:-mysqladmin}"
    export TARGET_MYSQL_PASSWORD="${TARGET_MYSQL_PASSWORD:-MySQL123!}"
    export TARGET_MYSQL_DB="${TARGET_MYSQL_DB:-mysql}"
    
    # Migration and monitoring resources
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-migrationst${RANDOM_SUFFIX}}"
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-migration-logs-${RANDOM_SUFFIX}}"
    export APPLICATION_INSIGHTS="${APPLICATION_INSIGHTS:-migration-insights-${RANDOM_SUFFIX}}"
    
    success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=migration environment=production
        success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account: ${STORAGE_ACCOUNT}"
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Storage account ${STORAGE_ACCOUNT} already exists"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2
        success "Storage account created for migration artifacts"
    fi
}

# Function to create MySQL Flexible Server
create_mysql_flexible_server() {
    log "Creating MySQL Flexible Server: ${TARGET_MYSQL_SERVER}"
    
    if az mysql flexible-server show --name "${TARGET_MYSQL_SERVER}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "MySQL Flexible Server ${TARGET_MYSQL_SERVER} already exists"
    else
        az mysql flexible-server create \
            --name "${TARGET_MYSQL_SERVER}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --admin-user "${TARGET_MYSQL_ADMIN}" \
            --admin-password "${TARGET_MYSQL_PASSWORD}" \
            --sku-name Standard_D2ds_v4 \
            --tier GeneralPurpose \
            --version 5.7 \
            --storage-size 128 \
            --high-availability ZoneRedundant \
            --backup-retention 35 \
            --storage-auto-grow Enabled
        
        success "MySQL Flexible Server created: ${TARGET_MYSQL_SERVER}"
    fi
    
    # Configure firewall rules
    log "Configuring firewall rules..."
    az mysql flexible-server firewall-rule create \
        --name "${TARGET_MYSQL_SERVER}" \
        --resource-group "${RESOURCE_GROUP}" \
        --rule-name AllowAzureServices \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0 \
        --output none || true
    
    # Get connection information
    export TARGET_MYSQL_FQDN=$(az mysql flexible-server show \
        --name "${TARGET_MYSQL_SERVER}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query fullyQualifiedDomainName \
        --output tsv)
    
    success "MySQL Flexible Server configured: ${TARGET_MYSQL_FQDN}"
}

# Function to set up monitoring infrastructure
setup_monitoring() {
    log "Setting up monitoring and logging infrastructure..."
    
    # Create Log Analytics workspace
    if az monitor log-analytics workspace show --workspace-name "${LOG_ANALYTICS_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Log Analytics workspace ${LOG_ANALYTICS_WORKSPACE} already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
            --location "${LOCATION}" \
            --sku PerGB2018
        success "Log Analytics workspace created"
    fi
    
    # Create Application Insights
    if az monitor app-insights component show --app "${APPLICATION_INSIGHTS}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Application Insights ${APPLICATION_INSIGHTS} already exists"
    else
        az monitor app-insights component create \
            --app "${APPLICATION_INSIGHTS}" \
            --location "${LOCATION}" \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace "${LOG_ANALYTICS_WORKSPACE}"
        success "Application Insights created"
    fi
    
    # Configure diagnostic settings for MySQL Flexible Server
    log "Configuring diagnostic settings..."
    az monitor diagnostic-settings create \
        --name mysql-diagnostics \
        --resource "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DBforMySQL/flexibleServers/${TARGET_MYSQL_SERVER}" \
        --workspace "${LOG_ANALYTICS_WORKSPACE}" \
        --logs '[{"category": "MySqlSlowLogs", "enabled": true}, {"category": "MySqlAuditLogs", "enabled": true}]' \
        --metrics '[{"category": "AllMetrics", "enabled": true}]' \
        --output none || true
    
    success "Monitoring infrastructure configured"
}

# Function to create read replica
create_read_replica() {
    log "Creating read replica for near-zero downtime migration..."
    
    local replica_name="${TARGET_MYSQL_SERVER}-replica"
    
    if az mysql flexible-server replica show --name "${replica_name}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Read replica ${replica_name} already exists"
    else
        az mysql flexible-server replica create \
            --name "${replica_name}" \
            --resource-group "${RESOURCE_GROUP}" \
            --source-server "${TARGET_MYSQL_SERVER}" \
            --location "${LOCATION}"
        success "Read replica created: ${replica_name}"
    fi
}

# Function to optimize MySQL performance
optimize_mysql_performance() {
    log "Configuring MySQL Flexible Server parameters for multi-tenant workloads..."
    
    # Configure parameters for multi-tenant workloads
    local params=(
        "max_connections:1000"
        "innodb_buffer_pool_size:1073741824"
        "query_cache_size:67108864"
        "slow_query_log:ON"
        "long_query_time:2"
    )
    
    for param in "${params[@]}"; do
        IFS=':' read -r param_name param_value <<< "$param"
        log "Setting parameter ${param_name} to ${param_value}"
        
        az mysql flexible-server parameter set \
            --name "${TARGET_MYSQL_SERVER}" \
            --resource-group "${RESOURCE_GROUP}" \
            --parameter-name "${param_name}" \
            --value "${param_value}" \
            --output none || warning "Failed to set parameter ${param_name}"
    done
    
    success "Performance optimization completed"
}

# Function to set up monitoring alerts
setup_monitoring_alerts() {
    log "Setting up automated monitoring and alerting..."
    
    local mysql_resource_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DBforMySQL/flexibleServers/${TARGET_MYSQL_SERVER}"
    
    # Create performance monitoring alerts
    local alerts=(
        "MySQL-CPU-High:cpu_percent:80:High CPU usage on MySQL Flexible Server"
        "MySQL-Connections-High:active_connections:800:High connection count on MySQL Flexible Server"
        "MySQL-Storage-High:storage_percent:85:High storage usage on MySQL Flexible Server"
    )
    
    for alert in "${alerts[@]}"; do
        IFS=':' read -r alert_name metric threshold description <<< "$alert"
        log "Creating alert: ${alert_name}"
        
        az monitor metrics alert create \
            --name "${alert_name}" \
            --resource-group "${RESOURCE_GROUP}" \
            --scopes "${mysql_resource_id}" \
            --condition "avg ${metric} > ${threshold}" \
            --window-size 5m \
            --evaluation-frequency 1m \
            --severity 2 \
            --description "${description}" \
            --output none || warning "Failed to create alert ${alert_name}"
    done
    
    success "Automated monitoring and alerting configured"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check if MySQL Flexible Server is running
    local server_state=$(az mysql flexible-server show \
        --name "${TARGET_MYSQL_SERVER}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query state \
        --output tsv)
    
    if [ "${server_state}" = "Ready" ]; then
        success "MySQL Flexible Server is ready: ${TARGET_MYSQL_SERVER}"
    else
        error "MySQL Flexible Server is not ready. Current state: ${server_state}"
    fi
    
    # Test connection if MySQL client is available
    if command -v mysql &> /dev/null; then
        log "Testing MySQL connection..."
        if mysql -h "${TARGET_MYSQL_FQDN}" -u "${TARGET_MYSQL_ADMIN}" -p"${TARGET_MYSQL_PASSWORD}" -e "SELECT VERSION();" &> /dev/null; then
            success "MySQL connection test successful"
        else
            warning "MySQL connection test failed. Check firewall rules and credentials."
        fi
    fi
    
    success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo ""
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "MySQL Flexible Server: ${TARGET_MYSQL_SERVER}"
    echo "MySQL FQDN: ${TARGET_MYSQL_FQDN}"
    echo "MySQL Admin User: ${TARGET_MYSQL_ADMIN}"
    echo "Storage Account: ${STORAGE_ACCOUNT}"
    echo "Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE}"
    echo "Application Insights: ${APPLICATION_INSIGHTS}"
    echo ""
    echo "Next Steps:"
    echo "1. Configure your source MariaDB server for migration"
    echo "2. Install MyDumper/MyLoader for data migration"
    echo "3. Run the migration process following the recipe steps"
    echo "4. Update application connection strings to point to MySQL Flexible Server"
    echo ""
    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting Azure MariaDB to MySQL Flexible Server migration deployment..."
    
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_storage_account
    create_mysql_flexible_server
    setup_monitoring
    create_read_replica
    optimize_mysql_performance
    setup_monitoring_alerts
    validate_deployment
    display_summary
    
    success "All deployment steps completed successfully!"
}

# Handle script interruption
trap 'error "Deployment interrupted. Check the logs and run cleanup if necessary."' INT TERM

# Run main function
main "$@"