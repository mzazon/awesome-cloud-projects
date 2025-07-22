#!/bin/bash

# =============================================================================
# Azure Multi-Tenant Database Architecture Cleanup Script
# =============================================================================
# This script removes all Azure resources created by the deployment script
# for the cost-optimized multi-tenant database architecture
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

# Logging functions
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
    log_error "Some resources may not have been deleted. Please check the Azure portal."
    exit "${error_code}"
}

# Set up error trap
trap 'handle_error ${LINENO} $?' ERR

# =============================================================================
# CONFIGURATION
# =============================================================================

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group NAME    Specify resource group name"
    echo "  -s, --suffix SUFFIX          Specify resource name suffix"
    echo "  -f, --force                  Skip confirmation prompts"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -g rg-multitenant-db-abc123"
    echo "  $0 --suffix abc123 --force"
    echo ""
    echo "If no options are provided, the script will search for resource groups"
    echo "matching the pattern 'rg-multitenant-db-*'"
}

# Parse command line arguments
parse_arguments() {
    RESOURCE_GROUP=""
    SUFFIX=""
    FORCE_MODE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -s|--suffix)
                SUFFIX="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_MODE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Auto-discover resource groups if not specified
discover_resources() {
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        log "Searching for multi-tenant database resource groups..."
        
        # Find resource groups matching the pattern
        local resource_groups
        resource_groups=$(az group list --query "[?starts_with(name, 'rg-multitenant-db-')].name" -o tsv)
        
        if [[ -z "${resource_groups}" ]]; then
            log_error "No resource groups found matching pattern 'rg-multitenant-db-*'"
            log_error "Please specify a resource group using -g option"
            exit 1
        fi
        
        # If multiple resource groups found, let user choose
        local group_array=($resource_groups)
        if [[ ${#group_array[@]} -eq 1 ]]; then
            RESOURCE_GROUP="${group_array[0]}"
            log "Found resource group: ${RESOURCE_GROUP}"
        else
            log "Multiple resource groups found:"
            for i in "${!group_array[@]}"; do
                echo "  $((i+1)). ${group_array[i]}"
            done
            
            if [[ "${FORCE_MODE}" == "true" ]]; then
                log_error "Multiple resource groups found and --force specified. Please use -g to specify exact resource group."
                exit 1
            fi
            
            read -p "Select resource group (1-${#group_array[@]}): " selection
            if [[ "${selection}" =~ ^[0-9]+$ ]] && [[ "${selection}" -ge 1 ]] && [[ "${selection}" -le ${#group_array[@]} ]]; then
                RESOURCE_GROUP="${group_array[$((selection-1))]}"
                log "Selected resource group: ${RESOURCE_GROUP}"
            else
                log_error "Invalid selection"
                exit 1
            fi
        fi
        
        # Extract suffix from resource group name
        SUFFIX="${RESOURCE_GROUP#rg-multitenant-db-}"
    fi
    
    # Validate resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "Resource group '${RESOURCE_GROUP}' not found"
        exit 1
    fi
    
    # Set derived resource names
    SQL_SERVER_NAME="sqlserver-mt-${SUFFIX}"
    ELASTIC_POOL_NAME="elasticpool-saas-${SUFFIX}"
    BACKUP_VAULT_NAME="bv-multitenant-${SUFFIX}"
    BUDGET_NAME="budget-multitenant-db-${SUFFIX}"
    LOG_ANALYTICS_WORKSPACE="law-multitenant-${SUFFIX}"
}

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
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
# RESOURCE DISCOVERY
# =============================================================================

discover_existing_resources() {
    log "Discovering existing resources in ${RESOURCE_GROUP}..."
    
    # Discover SQL databases
    local databases
    databases=$(az sql db list \
        --server "${SQL_SERVER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[?elasticPoolName=='${ELASTIC_POOL_NAME}'].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${databases}" ]]; then
        TENANT_DATABASES=(${databases})
        log "Found ${#TENANT_DATABASES[@]} tenant database(s)"
    else
        TENANT_DATABASES=()
        log_warning "No tenant databases found or SQL server doesn't exist"
    fi
    
    # Check if backup vault exists
    if az dataprotection backup-vault show --name "${BACKUP_VAULT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        BACKUP_VAULT_EXISTS=true
        log "Found backup vault: ${BACKUP_VAULT_NAME}"
    else
        BACKUP_VAULT_EXISTS=false
        log_warning "Backup vault not found"
    fi
    
    # Check if SQL server exists
    if az sql server show --name "${SQL_SERVER_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        SQL_SERVER_EXISTS=true
        log "Found SQL server: ${SQL_SERVER_NAME}"
    else
        SQL_SERVER_EXISTS=false
        log_warning "SQL server not found"
    fi
    
    # Check if Log Analytics workspace exists
    if az monitor log-analytics workspace show --workspace-name "${LOG_ANALYTICS_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        LOG_ANALYTICS_EXISTS=true
        log "Found Log Analytics workspace: ${LOG_ANALYTICS_WORKSPACE}"
    else
        LOG_ANALYTICS_EXISTS=false
        log_warning "Log Analytics workspace not found"
    fi
    
    # Check if budget exists
    if az consumption budget show --budget-name "${BUDGET_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        BUDGET_EXISTS=true
        log "Found budget: ${BUDGET_NAME}"
    else
        BUDGET_EXISTS=false
        log_warning "Budget not found"
    fi
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

show_cleanup_summary() {
    log "================================================================="
    log "🗑️  Cleanup Summary"
    log "================================================================="
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Location: $(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)"
    log ""
    log "Resources to be deleted:"
    
    if [[ ${#TENANT_DATABASES[@]} -gt 0 ]]; then
        log "  📊 Tenant Databases (${#TENANT_DATABASES[@]}):"
        for db in "${TENANT_DATABASES[@]}"; do
            log "    - ${db}"
        done
    fi
    
    if [[ "${SQL_SERVER_EXISTS}" == "true" ]]; then
        log "  🗄️  SQL Server: ${SQL_SERVER_NAME}"
        log "  🏊 Elastic Pool: ${ELASTIC_POOL_NAME}"
    fi
    
    if [[ "${BACKUP_VAULT_EXISTS}" == "true" ]]; then
        log "  🔒 Backup Vault: ${BACKUP_VAULT_NAME}"
    fi
    
    if [[ "${LOG_ANALYTICS_EXISTS}" == "true" ]]; then
        log "  📊 Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE}"
    fi
    
    if [[ "${BUDGET_EXISTS}" == "true" ]]; then
        log "  💰 Budget: ${BUDGET_NAME}"
    fi
    
    log "  📦 Action Groups and Monitoring Resources"
    log "  🏷️  Entire Resource Group: ${RESOURCE_GROUP}"
    log ""
    log "================================================================="
}

confirm_deletion() {
    if [[ "${FORCE_MODE}" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo
    log_warning "⚠️  WARNING: This will permanently delete all resources listed above!"
    log_warning "⚠️  This action cannot be undone."
    echo
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [[ "${confirmation}" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Last chance - are you absolutely sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

remove_tenant_databases() {
    if [[ ${#TENANT_DATABASES[@]} -eq 0 ]]; then
        log "No tenant databases to remove"
        return 0
    fi
    
    log "Removing tenant databases..."
    
    for db in "${TENANT_DATABASES[@]}"; do
        log "Deleting database: ${db}"
        
        if az sql db delete \
            --name "${db}" \
            --server "${SQL_SERVER_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes &> /dev/null; then
            log_success "Deleted database: ${db}"
        else
            log_warning "Failed to delete database: ${db} (may not exist)"
        fi
    done
    
    log_success "Tenant database cleanup completed"
}

remove_elastic_pool() {
    if [[ "${SQL_SERVER_EXISTS}" != "true" ]]; then
        log "SQL server doesn't exist, skipping elastic pool removal"
        return 0
    fi
    
    log "Removing elastic pool..."
    
    if az sql elastic-pool delete \
        --name "${ELASTIC_POOL_NAME}" \
        --server "${SQL_SERVER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_success "Deleted elastic pool: ${ELASTIC_POOL_NAME}"
    else
        log_warning "Failed to delete elastic pool (may not exist)"
    fi
}

remove_sql_server() {
    if [[ "${SQL_SERVER_EXISTS}" != "true" ]]; then
        log "SQL server doesn't exist, skipping removal"
        return 0
    fi
    
    log "Removing SQL server..."
    
    if az sql server delete \
        --name "${SQL_SERVER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --yes &> /dev/null; then
        log_success "Deleted SQL server: ${SQL_SERVER_NAME}"
    else
        log_warning "Failed to delete SQL server"
    fi
}

remove_backup_vault() {
    if [[ "${BACKUP_VAULT_EXISTS}" != "true" ]]; then
        log "Backup vault doesn't exist, skipping removal"
        return 0
    fi
    
    log "Removing backup vault..."
    
    # First, try to delete backup policies
    local policies
    policies=$(az dataprotection backup-policy list \
        --vault-name "${BACKUP_VAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${policies}" ]]; then
        log "Removing backup policies..."
        for policy in ${policies}; do
            if az dataprotection backup-policy delete \
                --name "${policy}" \
                --vault-name "${BACKUP_VAULT_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes &> /dev/null; then
                log_success "Deleted backup policy: ${policy}"
            else
                log_warning "Failed to delete backup policy: ${policy}"
            fi
        done
    fi
    
    # Delete the backup vault
    if az dataprotection backup-vault delete \
        --name "${BACKUP_VAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --yes &> /dev/null; then
        log_success "Deleted backup vault: ${BACKUP_VAULT_NAME}"
    else
        log_warning "Failed to delete backup vault"
    fi
}

remove_monitoring_resources() {
    log "Removing monitoring and cost management resources..."
    
    # Remove budget
    if [[ "${BUDGET_EXISTS}" == "true" ]]; then
        if az consumption budget delete \
            --budget-name "${BUDGET_NAME}" \
            --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log_success "Deleted budget: ${BUDGET_NAME}"
        else
            log_warning "Failed to delete budget"
        fi
    fi
    
    # Remove action groups
    local action_groups
    action_groups=$(az monitor action-group list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${action_groups}" ]]; then
        for ag in ${action_groups}; do
            if az monitor action-group delete \
                --name "${ag}" \
                --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
                log_success "Deleted action group: ${ag}"
            else
                log_warning "Failed to delete action group: ${ag}"
            fi
        done
    fi
    
    # Remove Log Analytics workspace
    if [[ "${LOG_ANALYTICS_EXISTS}" == "true" ]]; then
        if az monitor log-analytics workspace delete \
            --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes &> /dev/null; then
            log_success "Deleted Log Analytics workspace: ${LOG_ANALYTICS_WORKSPACE}"
        else
            log_warning "Failed to delete Log Analytics workspace"
        fi
    fi
}

remove_resource_group() {
    log "Removing resource group (this may take several minutes)..."
    
    # Double-check resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} does not exist"
        return 0
    fi
    
    # Delete the entire resource group
    if az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait; then
        log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        log "🕐 Note: Complete deletion may take 10-15 minutes"
        log "   You can monitor progress in the Azure portal"
    else
        log_error "Failed to initiate resource group deletion"
        return 1
    fi
}

# =============================================================================
# VERIFICATION
# =============================================================================

verify_cleanup() {
    log "Verifying cleanup..."
    
    # Wait a moment for deletions to propagate
    sleep 10
    
    # Check if resource group still exists (it should be in deletion state)
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        local provisioning_state
        provisioning_state=$(az group show --name "${RESOURCE_GROUP}" --query properties.provisioningState -o tsv)
        
        if [[ "${provisioning_state}" == "Deleting" ]]; then
            log_success "Resource group is in deletion state"
        else
            log_warning "Resource group still exists but not in deletion state"
        fi
    else
        log_success "Resource group has been completely removed"
    fi
}

# =============================================================================
# MAIN CLEANUP FLOW
# =============================================================================

main() {
    log "Starting Azure Multi-Tenant Database Architecture cleanup..."
    log "================================================================="
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Execute cleanup steps
    check_prerequisites
    discover_resources
    discover_existing_resources
    show_cleanup_summary
    confirm_deletion
    
    log "================================================================="
    log "🗑️  Starting cleanup process..."
    log "================================================================="
    
    # Remove resources in the correct order
    remove_tenant_databases
    remove_elastic_pool
    remove_sql_server
    remove_backup_vault
    remove_monitoring_resources
    remove_resource_group
    
    verify_cleanup
    
    # Display cleanup completion
    log "================================================================="
    log_success "Cleanup process completed!"
    log ""
    log "📋 Cleanup Summary:"
    log "  ✅ Tenant databases removed"
    log "  ✅ Elastic pool removed"
    log "  ✅ SQL server removed"
    log "  ✅ Backup vault and policies removed"
    log "  ✅ Monitoring resources removed"
    log "  ✅ Cost management resources removed"
    log "  ✅ Resource group deletion initiated"
    log ""
    log "🕐 Note: Resource group deletion may take 10-15 minutes to complete"
    log "   Monitor progress at: https://portal.azure.com/#blade/HubsExtension/ResourceGroupMapBlade"
    log ""
    log "💰 Cost Impact: All billable resources have been removed"
    log "================================================================="
}

# Execute main function with all arguments
main "$@"