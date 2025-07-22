#!/bin/bash

# Azure MariaDB to MySQL Flexible Server Migration - Cleanup Script
# This script safely removes all resources created during the migration process
# Use with caution as this will permanently delete resources and data

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

# Function to confirm destruction
confirm_destruction() {
    echo ""
    warning "⚠️  DANGER: This script will permanently delete the following resources:"
    echo "   - MySQL Flexible Server and all its databases"
    echo "   - Read replicas"
    echo "   - Monitoring alerts and diagnostic settings"
    echo "   - Log Analytics workspace and logs"
    echo "   - Application Insights"
    echo "   - Storage account and migration artifacts"
    echo "   - Resource group (if empty)"
    echo ""
    warning "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " confirmation
    
    if [ "${confirmation}" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    warning "Final confirmation required!"
    read -p "Type 'DELETE' to confirm permanent deletion: " final_confirmation
    
    if [ "${final_confirmation}" != "DELETE" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed. Starting cleanup process..."
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
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
    
    # Generate unique suffix for resource names (try to detect from existing resources)
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        # Try to detect suffix from existing resources
        local mysql_servers=$(az mysql flexible-server list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
        if [ -n "${mysql_servers}" ]; then
            for server in ${mysql_servers}; do
                if [[ "${server}" == mysql-target-* ]]; then
                    export RANDOM_SUFFIX="${server#mysql-target-}"
                    log "Detected random suffix from existing resources: ${RANDOM_SUFFIX}"
                    break
                fi
            done
        fi
        
        # If still not found, ask user
        if [ -z "${RANDOM_SUFFIX:-}" ]; then
            warning "Could not auto-detect resource suffix."
            read -p "Please enter the random suffix used during deployment (6 hex characters): " user_suffix
            export RANDOM_SUFFIX="${user_suffix}"
        fi
    fi
    
    # Source MariaDB server details
    export SOURCE_MARIADB_SERVER="${SOURCE_MARIADB_SERVER:-mariadb-source-${RANDOM_SUFFIX}}"
    
    # Target MySQL Flexible Server details
    export TARGET_MYSQL_SERVER="${TARGET_MYSQL_SERVER:-mysql-target-${RANDOM_SUFFIX}}"
    
    # Migration and monitoring resources
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-migrationst${RANDOM_SUFFIX}}"
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-migration-logs-${RANDOM_SUFFIX}}"
    export APPLICATION_INSIGHTS="${APPLICATION_INSIGHTS:-migration-insights-${RANDOM_SUFFIX}}"
    
    success "Environment variables configured"
}

# Function to remove monitoring alerts
remove_monitoring_alerts() {
    log "Removing monitoring alerts..."
    
    local alerts=(
        "MySQL-CPU-High"
        "MySQL-Connections-High"
        "MySQL-Storage-High"
    )
    
    for alert_name in "${alerts[@]}"; do
        if az monitor metrics alert show --name "${alert_name}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log "Removing alert: ${alert_name}"
            az monitor metrics alert delete \
                --name "${alert_name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none || warning "Failed to remove alert ${alert_name}"
            success "Alert removed: ${alert_name}"
        else
            log "Alert ${alert_name} not found or already removed"
        fi
    done
}

# Function to remove diagnostic settings
remove_diagnostic_settings() {
    log "Removing diagnostic settings..."
    
    local mysql_resource_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DBforMySQL/flexibleServers/${TARGET_MYSQL_SERVER}"
    
    # List and remove diagnostic settings
    local diagnostic_settings=$(az monitor diagnostic-settings list \
        --resource "${mysql_resource_id}" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    for setting in ${diagnostic_settings}; do
        log "Removing diagnostic setting: ${setting}"
        az monitor diagnostic-settings delete \
            --name "${setting}" \
            --resource "${mysql_resource_id}" \
            --output none || warning "Failed to remove diagnostic setting ${setting}"
        success "Diagnostic setting removed: ${setting}"
    done
}

# Function to remove read replicas
remove_read_replicas() {
    log "Removing read replicas..."
    
    local replica_name="${TARGET_MYSQL_SERVER}-replica"
    
    if az mysql flexible-server replica show --name "${replica_name}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log "Removing read replica: ${replica_name}"
        az mysql flexible-server replica delete \
            --name "${replica_name}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --output none
        success "Read replica removed: ${replica_name}"
    else
        log "Read replica ${replica_name} not found or already removed"
    fi
}

# Function to remove MySQL Flexible Server
remove_mysql_flexible_server() {
    log "Removing MySQL Flexible Server: ${TARGET_MYSQL_SERVER}"
    
    if az mysql flexible-server show --name "${TARGET_MYSQL_SERVER}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "⚠️  This will permanently delete the MySQL Flexible Server and ALL its data!"
        read -p "Type 'CONFIRM' to proceed with MySQL server deletion: " mysql_confirmation
        
        if [ "${mysql_confirmation}" != "CONFIRM" ]; then
            warning "MySQL server deletion skipped by user"
            return 0
        fi
        
        log "Deleting MySQL Flexible Server (this may take several minutes)..."
        az mysql flexible-server delete \
            --name "${TARGET_MYSQL_SERVER}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --output none
        success "MySQL Flexible Server removed: ${TARGET_MYSQL_SERVER}"
    else
        log "MySQL Flexible Server ${TARGET_MYSQL_SERVER} not found or already removed"
    fi
}

# Function to remove source MariaDB server (if exists and user confirms)
remove_source_mariadb_server() {
    log "Checking for source MariaDB server: ${SOURCE_MARIADB_SERVER}"
    
    if az mariadb server show --name "${SOURCE_MARIADB_SERVER}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "⚠️  Source MariaDB server found: ${SOURCE_MARIADB_SERVER}"
        warning "⚠️  This contains your original data! Only delete if migration is complete and verified!"
        echo ""
        read -p "Do you want to delete the source MariaDB server? Type 'DELETE_SOURCE' to confirm: " mariadb_confirmation
        
        if [ "${mariadb_confirmation}" = "DELETE_SOURCE" ]; then
            log "Deleting source MariaDB server (this may take several minutes)..."
            az mariadb server delete \
                --name "${SOURCE_MARIADB_SERVER}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none
            success "Source MariaDB server removed: ${SOURCE_MARIADB_SERVER}"
        else
            warning "Source MariaDB server deletion skipped - keeping original data safe"
        fi
    else
        log "Source MariaDB server ${SOURCE_MARIADB_SERVER} not found"
    fi
}

# Function to remove Application Insights
remove_application_insights() {
    log "Removing Application Insights: ${APPLICATION_INSIGHTS}"
    
    if az monitor app-insights component show --app "${APPLICATION_INSIGHTS}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        az monitor app-insights component delete \
            --app "${APPLICATION_INSIGHTS}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none
        success "Application Insights removed: ${APPLICATION_INSIGHTS}"
    else
        log "Application Insights ${APPLICATION_INSIGHTS} not found or already removed"
    fi
}

# Function to remove Log Analytics workspace
remove_log_analytics_workspace() {
    log "Removing Log Analytics workspace: ${LOG_ANALYTICS_WORKSPACE}"
    
    if az monitor log-analytics workspace show --workspace-name "${LOG_ANALYTICS_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "⚠️  This will permanently delete all logs and monitoring data!"
        read -p "Confirm Log Analytics workspace deletion (y/N): " logs_confirmation
        
        if [[ "${logs_confirmation}" =~ ^[Yy]$ ]]; then
            az monitor log-analytics workspace delete \
                --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none
            success "Log Analytics workspace removed: ${LOG_ANALYTICS_WORKSPACE}"
        else
            warning "Log Analytics workspace deletion skipped - preserving monitoring data"
        fi
    else
        log "Log Analytics workspace ${LOG_ANALYTICS_WORKSPACE} not found or already removed"
    fi
}

# Function to remove storage account
remove_storage_account() {
    log "Removing storage account: ${STORAGE_ACCOUNT}"
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "⚠️  This will permanently delete all migration artifacts and backups!"
        read -p "Confirm storage account deletion (y/N): " storage_confirmation
        
        if [[ "${storage_confirmation}" =~ ^[Yy]$ ]]; then
            az storage account delete \
                --name "${STORAGE_ACCOUNT}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none
            success "Storage account removed: ${STORAGE_ACCOUNT}"
        else
            warning "Storage account deletion skipped - preserving migration artifacts"
        fi
    else
        log "Storage account ${STORAGE_ACCOUNT} not found or already removed"
    fi
}

# Function to remove resource group (if empty)
remove_resource_group() {
    log "Checking if resource group can be removed: ${RESOURCE_GROUP}"
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log "Resource group ${RESOURCE_GROUP} not found"
        return 0
    fi
    
    # Check if resource group is empty
    local resource_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length([])" --output tsv)
    
    if [ "${resource_count}" -eq 0 ]; then
        log "Resource group is empty, removing: ${RESOURCE_GROUP}"
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --output none
        success "Empty resource group removed: ${RESOURCE_GROUP}"
    else
        warning "Resource group ${RESOURCE_GROUP} contains ${resource_count} resources - not removing"
        log "Run 'az resource list --resource-group ${RESOURCE_GROUP}' to see remaining resources"
    fi
}

# Function to clean up local artifacts
cleanup_local_artifacts() {
    log "Cleaning up local migration artifacts..."
    
    local cleanup_paths=(
        "${HOME}/migration-data"
        "${HOME}/migration-config.json"
        "./migration-data"
        "./migration-config.json"
    )
    
    for path in "${cleanup_paths[@]}"; do
        if [ -e "${path}" ]; then
            log "Removing local artifact: ${path}"
            rm -rf "${path}"
            success "Local artifact removed: ${path}"
        fi
    done
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo ""
    echo "The following resources have been processed:"
    echo "✓ Monitoring alerts removed"
    echo "✓ Diagnostic settings removed"
    echo "✓ Read replicas removed"
    echo "✓ MySQL Flexible Server processed"
    echo "✓ Source MariaDB server processed"
    echo "✓ Application Insights processed"
    echo "✓ Log Analytics workspace processed"
    echo "✓ Storage account processed"
    echo "✓ Resource group processed"
    echo "✓ Local artifacts cleaned"
    echo ""
    success "Cleanup process completed!"
    echo ""
    warning "Note: Some resources may have been skipped based on user confirmation"
    warning "Verify all resources are removed by checking the Azure portal"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    # Check if resource group still exists and what's in it
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        local remaining_resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length([])" --output tsv)
        if [ "${remaining_resources}" -gt 0 ]; then
            warning "${remaining_resources} resources remain in resource group ${RESOURCE_GROUP}"
            log "Run the following command to see remaining resources:"
            echo "az resource list --resource-group ${RESOURCE_GROUP} --output table"
        else
            success "Resource group ${RESOURCE_GROUP} is empty"
        fi
    else
        success "Resource group ${RESOURCE_GROUP} has been removed"
    fi
}

# Main cleanup function
main() {
    log "Starting Azure MariaDB to MySQL Flexible Server migration cleanup..."
    
    check_prerequisites
    confirm_destruction
    set_environment_variables
    remove_monitoring_alerts
    remove_diagnostic_settings
    remove_read_replicas
    remove_mysql_flexible_server
    remove_source_mariadb_server
    remove_application_insights
    remove_log_analytics_workspace
    remove_storage_account
    cleanup_local_artifacts
    remove_resource_group
    validate_cleanup
    display_cleanup_summary
    
    success "Cleanup process completed successfully!"
}

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may remain. Check Azure portal and re-run if needed."' INT TERM

# Run main function
main "$@"