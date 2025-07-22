#!/bin/bash

# Azure Multi-Tenant SaaS Performance and Cost Analytics Cleanup Script
# Safely removes all resources created for the multi-tenant analytics solution

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Configuration and Global Variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deployment_config"
readonly BACKUP_DIR="${SCRIPT_DIR}/backups"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default values
FORCE_DELETE=false
SKIP_CONFIRMATION=false
CREATE_BACKUP=true

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "${LOG_FILE}"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "${LOG_FILE}"
}

# Usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely removes Azure Multi-Tenant SaaS Analytics resources.

OPTIONS:
    -f, --force              Force deletion without confirmation prompts
    -y, --yes               Skip all confirmation prompts (same as --force)
    -n, --no-backup         Skip creating backups of important data
    -c, --config FILE       Use custom configuration file
    -h, --help              Show this help message

EXAMPLES:
    $0                      Interactive cleanup with confirmations
    $0 --force              Force cleanup without prompts
    $0 --no-backup          Skip data backup during cleanup

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_DELETE=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            -y|--yes)
                FORCE_DELETE=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            -n|--no-backup)
                CREATE_BACKUP=false
                shift
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Load configuration
load_configuration() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Configuration file not found: ${CONFIG_FILE}"
        log_error "Please ensure the deployment was completed successfully"
        exit 1
    fi
    
    log "Loading configuration from: ${CONFIG_FILE}"
    source "${CONFIG_FILE}"
    
    # Validate required variables
    local required_vars=("RESOURCE_GROUP" "SUBSCRIPTION_ID")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            log_error "Required variable ${var} not found in configuration"
            exit 1
        fi
    done
    
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Subscription: ${SUBSCRIPTION_ID}"
}

# Prerequisites validation
check_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Verify subscription
    local current_subscription=$(az account show --query id -o tsv)
    if [[ "${current_subscription}" != "${SUBSCRIPTION_ID}" ]]; then
        log_warn "Current subscription (${current_subscription}) differs from deployment subscription (${SUBSCRIPTION_ID})"
        if [[ "${FORCE_DELETE}" == false ]]; then
            read -p "Do you want to switch to the deployment subscription? (y/n): " switch_sub
            if [[ "${switch_sub}" =~ ^[Yy]$ ]]; then
                az account set --subscription "${SUBSCRIPTION_ID}"
                log_info "Switched to subscription: ${SUBSCRIPTION_ID}"
            else
                log_error "Cleanup aborted due to subscription mismatch"
                exit 1
            fi
        fi
    fi
    
    log "Prerequisites validation completed"
}

# Create backup of important data
create_backup() {
    if [[ "${CREATE_BACKUP}" == false ]]; then
        log_warn "Skipping backup creation as requested"
        return 0
    fi
    
    log "Creating backup of important data..."
    
    # Create backup directory
    mkdir -p "${BACKUP_DIR}"
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${BACKUP_DIR}/backup_${backup_timestamp}"
    mkdir -p "${backup_path}"
    
    # Backup configuration
    cp "${CONFIG_FILE}" "${backup_path}/deployment_config.backup" 2>/dev/null || true
    
    # Backup Application Insights configuration
    if [[ -n "${APP_INSIGHTS_NAME}" ]] && [[ -n "${RESOURCE_GROUP}" ]]; then
        log_info "Backing up Application Insights configuration..."
        az monitor app-insights component show \
            --resource-group "${RESOURCE_GROUP}" \
            --app "${APP_INSIGHTS_NAME}" \
            --output json > "${backup_path}/app_insights_config.json" 2>/dev/null || true
    fi
    
    # Backup Log Analytics workspace configuration
    if [[ -n "${LOG_ANALYTICS_NAME}" ]] && [[ -n "${RESOURCE_GROUP}" ]]; then
        log_info "Backing up Log Analytics workspace configuration..."
        az monitor log-analytics workspace show \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_ANALYTICS_NAME}" \
            --output json > "${backup_path}/log_analytics_config.json" 2>/dev/null || true
    fi
    
    # Backup Data Explorer cluster configuration
    if [[ -n "${DATA_EXPLORER_CLUSTER}" ]] && [[ -n "${RESOURCE_GROUP}" ]]; then
        log_info "Backing up Data Explorer cluster configuration..."
        az kusto cluster show \
            --cluster-name "${DATA_EXPLORER_CLUSTER}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output json > "${backup_path}/data_explorer_config.json" 2>/dev/null || true
    fi
    
    # Backup sample queries if they exist
    for query_file in "${SCRIPT_DIR}"/*.kql; do
        if [[ -f "${query_file}" ]]; then
            cp "${query_file}" "${backup_path}/" 2>/dev/null || true
        fi
    done
    
    # Create backup summary
    cat > "${backup_path}/backup_summary.txt" << EOF
Azure Multi-Tenant SaaS Analytics Backup
Created: $(date)
Resource Group: ${RESOURCE_GROUP}
Subscription: ${SUBSCRIPTION_ID}

Files included:
- deployment_config.backup: Original deployment configuration
- app_insights_config.json: Application Insights configuration
- log_analytics_config.json: Log Analytics workspace configuration
- data_explorer_config.json: Data Explorer cluster configuration
- *.kql: Sample analytics queries

To restore from this backup, use the configuration files to recreate resources
with the same names and settings.
EOF
    
    log "✅ Backup created at: ${backup_path}"
}

# Confirmation prompts
confirm_deletion() {
    if [[ "${SKIP_CONFIRMATION}" == true ]]; then
        return 0
    fi
    
    log_warn "This operation will permanently delete the following resources:"
    log_warn "- Resource Group: ${RESOURCE_GROUP}"
    log_warn "- All contained resources including:"
    log_warn "  • Application Insights: ${APP_INSIGHTS_NAME:-Not found}"
    log_warn "  • Log Analytics Workspace: ${LOG_ANALYTICS_NAME:-Not found}"
    log_warn "  • Data Explorer Cluster: ${DATA_EXPLORER_CLUSTER:-Not found}"
    log_warn "  • Cost Management budgets and alerts"
    log_warn ""
    
    # Calculate potential cost savings
    log_info "This will stop charges for:"
    log_info "- Data Explorer cluster (~\$200-500/month)"
    log_info "- Application Insights data ingestion"
    log_info "- Log Analytics workspace storage"
    log_warn ""
    
    read -p "Are you absolutely sure you want to proceed? (type 'yes' to confirm): " confirmation
    if [[ "${confirmation}" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    read -p "Last chance: This action cannot be undone. Continue? (y/n): " final_confirm
    if [[ ! "${final_confirm}" =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Check if resources exist
check_resource_existence() {
    log "Checking resource existence..."
    
    # Check resource group
    if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        log_info "✅ Resource group exists: ${RESOURCE_GROUP}"
        RESOURCE_GROUP_EXISTS=true
    else
        log_warn "❌ Resource group not found: ${RESOURCE_GROUP}"
        RESOURCE_GROUP_EXISTS=false
    fi
    
    # Check individual resources if resource group exists
    if [[ "${RESOURCE_GROUP_EXISTS}" == true ]]; then
        # Check Application Insights
        if [[ -n "${APP_INSIGHTS_NAME}" ]] && az monitor app-insights component show --resource-group "${RESOURCE_GROUP}" --app "${APP_INSIGHTS_NAME}" &>/dev/null; then
            log_info "✅ Application Insights exists: ${APP_INSIGHTS_NAME}"
        else
            log_warn "❌ Application Insights not found: ${APP_INSIGHTS_NAME}"
        fi
        
        # Check Log Analytics workspace
        if [[ -n "${LOG_ANALYTICS_NAME}" ]] && az monitor log-analytics workspace show --resource-group "${RESOURCE_GROUP}" --workspace-name "${LOG_ANALYTICS_NAME}" &>/dev/null; then
            log_info "✅ Log Analytics workspace exists: ${LOG_ANALYTICS_NAME}"
        else
            log_warn "❌ Log Analytics workspace not found: ${LOG_ANALYTICS_NAME}"
        fi
        
        # Check Data Explorer cluster
        if [[ -n "${DATA_EXPLORER_CLUSTER}" ]] && az kusto cluster show --cluster-name "${DATA_EXPLORER_CLUSTER}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
            log_info "✅ Data Explorer cluster exists: ${DATA_EXPLORER_CLUSTER}"
        else
            log_warn "❌ Data Explorer cluster not found: ${DATA_EXPLORER_CLUSTER}"
        fi
    fi
}

# Delete individual resources (if partial cleanup is needed)
delete_individual_resources() {
    log "Starting individual resource deletion..."
    
    # Delete Data Explorer cluster first (takes longest)
    if [[ -n "${DATA_EXPLORER_CLUSTER}" ]]; then
        log "Deleting Data Explorer cluster: ${DATA_EXPLORER_CLUSTER}"
        log_warn "This operation may take 10-15 minutes..."
        
        if az kusto cluster delete \
            --cluster-name "${DATA_EXPLORER_CLUSTER}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --no-wait 2>/dev/null; then
            log "✅ Data Explorer cluster deletion initiated"
        else
            log_warn "⚠️ Data Explorer cluster deletion failed or resource not found"
        fi
    fi
    
    # Delete Application Insights
    if [[ -n "${APP_INSIGHTS_NAME}" ]]; then
        log "Deleting Application Insights: ${APP_INSIGHTS_NAME}"
        
        if az monitor app-insights component delete \
            --resource-group "${RESOURCE_GROUP}" \
            --app "${APP_INSIGHTS_NAME}" 2>/dev/null; then
            log "✅ Application Insights deleted"
        else
            log_warn "⚠️ Application Insights deletion failed or resource not found"
        fi
    fi
    
    # Delete Log Analytics workspace
    if [[ -n "${LOG_ANALYTICS_NAME}" ]]; then
        log "Deleting Log Analytics workspace: ${LOG_ANALYTICS_NAME}"
        
        if az monitor log-analytics workspace delete \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_ANALYTICS_NAME}" \
            --yes \
            --force true 2>/dev/null; then
            log "✅ Log Analytics workspace deleted"
        else
            log_warn "⚠️ Log Analytics workspace deletion failed or resource not found"
        fi
    fi
    
    # Delete cost management resources
    if [[ -n "${BUDGET_NAME}" ]]; then
        log "Deleting budget: ${BUDGET_NAME}"
        
        if az consumption budget delete \
            --resource-group "${RESOURCE_GROUP}" \
            --budget-name "${BUDGET_NAME}" 2>/dev/null; then
            log "✅ Budget deleted"
        else
            log_warn "⚠️ Budget deletion failed or resource not found"
        fi
    fi
    
    if [[ -n "${ACTION_GROUP_NAME}" ]]; then
        log "Deleting action group: ${ACTION_GROUP_NAME}"
        
        if az monitor action-group delete \
            --name "${ACTION_GROUP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" 2>/dev/null; then
            log "✅ Action group deleted"
        else
            log_warn "⚠️ Action group deletion failed or resource not found"
        fi
    fi
}

# Delete entire resource group
delete_resource_group() {
    if [[ "${RESOURCE_GROUP_EXISTS}" == false ]]; then
        log_warn "Resource group does not exist, skipping deletion"
        return 0
    fi
    
    log "Deleting entire resource group: ${RESOURCE_GROUP}"
    log_warn "This will delete ALL resources in the resource group..."
    
    # Use --no-wait for faster execution, but provide status updates
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    
    log "✅ Resource group deletion initiated"
    log_info "Deletion is running in the background and may take several minutes"
    
    # Optional: Wait for completion and provide status updates
    if [[ "${FORCE_DELETE}" == false ]]; then
        read -p "Do you want to wait for deletion to complete? (y/n): " wait_completion
        if [[ "${wait_completion}" =~ ^[Yy]$ ]]; then
            log "Waiting for resource group deletion to complete..."
            
            local max_wait=1800  # 30 minutes
            local elapsed=0
            local check_interval=30
            
            while [[ $elapsed -lt $max_wait ]]; do
                if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
                    log "✅ Resource group deletion completed successfully"
                    return 0
                fi
                
                log_info "Still deleting... (${elapsed}s elapsed)"
                sleep $check_interval
                elapsed=$((elapsed + check_interval))
            done
            
            log_warn "Deletion timeout reached. Resource group may still be deleting in the background."
        fi
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local configuration files..."
    
    # Remove configuration file
    if [[ -f "${CONFIG_FILE}" ]]; then
        if [[ "${FORCE_DELETE}" == true ]]; then
            rm -f "${CONFIG_FILE}"
            log "✅ Configuration file removed"
        else
            read -p "Remove local configuration file? (y/n): " remove_config
            if [[ "${remove_config}" =~ ^[Yy]$ ]]; then
                rm -f "${CONFIG_FILE}"
                log "✅ Configuration file removed"
            else
                log_info "Configuration file preserved: ${CONFIG_FILE}"
            fi
        fi
    fi
    
    # Clean up temporary files
    rm -f "${SCRIPT_DIR}"/*.tmp 2>/dev/null || true
    
    log "✅ Local cleanup completed"
}

# Final verification
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        log_warn "⚠️ Resource group still exists (deletion may be in progress)"
        log_info "You can check deletion status with: az group show --name '${RESOURCE_GROUP}'"
    else
        log "✅ Resource group successfully deleted"
    fi
    
    # Check for any remaining configuration files
    if [[ -f "${CONFIG_FILE}" ]]; then
        log_info "Configuration file preserved at: ${CONFIG_FILE}"
    fi
    
    log "✅ Cleanup verification completed"
}

# Display cleanup summary
display_summary() {
    log "=== CLEANUP SUMMARY ==="
    log_info "Resource Group: ${RESOURCE_GROUP} (deletion initiated)"
    log_info "Backup Location: ${BACKUP_DIR} (if created)"
    log_info "Cleanup Log: ${LOG_FILE}"
    log ""
    log_info "Resources that have been deleted:"
    log_info "- Application Insights: ${APP_INSIGHTS_NAME:-N/A}"
    log_info "- Log Analytics Workspace: ${LOG_ANALYTICS_NAME:-N/A}"
    log_info "- Data Explorer Cluster: ${DATA_EXPLORER_CLUSTER:-N/A}"
    log_info "- Cost Management budgets and alerts"
    log ""
    log_info "💰 This will stop all charges for these resources"
    log_info "📁 Backups (if created) are preserved in: ${BACKUP_DIR}"
    log ""
    log_warn "Note: Some resources may take additional time to fully delete"
    log_info "You can verify complete deletion in the Azure Portal"
}

# Main cleanup function
main() {
    log "Starting Azure Multi-Tenant SaaS Analytics cleanup..."
    log "Cleanup started at: $(date)"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Run cleanup steps
    load_configuration
    check_prerequisites
    check_resource_existence
    create_backup
    confirm_deletion
    
    # Choose deletion strategy
    if [[ "${RESOURCE_GROUP_EXISTS}" == true ]]; then
        if [[ "${FORCE_DELETE}" == true ]]; then
            # Fast deletion: remove entire resource group
            delete_resource_group
        else
            read -p "Delete entire resource group (faster) or individual resources (safer)? (group/individual): " deletion_type
            case $deletion_type in
                group|g)
                    delete_resource_group
                    ;;
                individual|i)
                    delete_individual_resources
                    sleep 5  # Wait a bit before attempting resource group deletion
                    delete_resource_group
                    ;;
                *)
                    log_warn "Invalid option. Defaulting to resource group deletion."
                    delete_resource_group
                    ;;
            esac
        fi
    else
        log_warn "Resource group does not exist. Nothing to delete."
    fi
    
    cleanup_local_files
    verify_cleanup
    display_summary
    
    log "✅ Cleanup completed successfully at: $(date)"
    log "Total cleanup time: $SECONDS seconds"
}

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi