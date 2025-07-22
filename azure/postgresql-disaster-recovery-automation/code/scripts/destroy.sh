#!/bin/bash

# =============================================================================
# Cleanup Azure PostgreSQL Disaster Recovery Solution
# =============================================================================
# This script safely removes all Azure resources created by the PostgreSQL
# disaster recovery deployment, including read replicas, backup vaults,
# monitoring, automation, and storage resources.
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# =============================================================================
# Configuration and Constants
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DRY_RUN=false
FORCE_CLEANUP=false
SKIP_CONFIRMATION=false
PARALLEL_CLEANUP=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" >&2
            echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
            ;;
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE"
            ;;
    esac
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup Azure PostgreSQL Disaster Recovery Solution

OPTIONS:
    -g, --resource-group NAME       Primary resource group name (required)
    -n, --postgres-name NAME        PostgreSQL server name prefix
    --dry-run                       Show what would be deleted without making changes
    --force                         Force deletion without confirmation prompts
    --skip-confirmation             Skip all confirmation prompts
    --parallel                      Delete resources in parallel (faster but less safe)
    -h, --help                      Show this help message
    -v, --verbose                   Enable verbose logging

Examples:
    $0 -g mygroup
    $0 -g mygroup --dry-run
    $0 -g mygroup --force --parallel
    $0 --resource-group mygroup --postgres-name mypostgres

WARNING: This script will permanently delete all resources in the specified
resource groups. This action cannot be undone.

EOF
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log "ERROR" "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log "ERROR" "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log "INFO" "Prerequisites check completed"
}

validate_parameters() {
    log "INFO" "Validating cleanup parameters..."
    
    # Check required parameters
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log "ERROR" "Resource group name is required. Use -g or --resource-group."
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "WARN" "Primary resource group '$RESOURCE_GROUP' does not exist."
        log "INFO" "Checking secondary resource group..."
        
        local secondary_rg="${RESOURCE_GROUP}-secondary"
        if ! az group show --name "$secondary_rg" &> /dev/null; then
            log "WARN" "Secondary resource group '$secondary_rg' does not exist either."
            log "INFO" "No resources to clean up."
            exit 0
        fi
    fi
    
    log "INFO" "Parameter validation completed"
}

confirm_cleanup() {
    if [[ "$SKIP_CONFIRMATION" == "true" || "$FORCE_CLEANUP" == "true" ]]; then
        return 0
    fi
    
    echo
    log "WARN" "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    log "WARN" "This will permanently delete ALL resources in:"
    log "WARN" "  - Resource Group: $RESOURCE_GROUP"
    log "WARN" "  - Resource Group: ${RESOURCE_GROUP}-secondary"
    log "WARN" ""
    log "WARN" "Resources to be deleted include:"
    log "WARN" "  - PostgreSQL Flexible Server and Read Replica"
    log "WARN" "  - All databases and data"
    log "WARN" "  - Backup vaults and stored backups"
    log "WARN" "  - Storage accounts and containers"
    log "WARN" "  - Monitoring and alerting configuration"
    log "WARN" "  - Automation accounts and runbooks"
    log "WARN" ""
    log "WARN" "💥 THIS ACTION CANNOT BE UNDONE 💥"
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "INFO" "Cleanup cancelled by user."
        exit 0
    fi
    
    echo
    read -p "Final confirmation - Type the resource group name to proceed: " rg_confirmation
    
    if [[ "$rg_confirmation" != "$RESOURCE_GROUP" ]]; then
        log "ERROR" "Resource group name mismatch. Cleanup cancelled."
        exit 1
    fi
    
    log "INFO" "Cleanup confirmed. Proceeding..."
}

list_resources() {
    log "INFO" "Listing resources to be deleted..."
    
    local resource_groups=("$RESOURCE_GROUP" "${RESOURCE_GROUP}-secondary")
    
    for rg in "${resource_groups[@]}"; do
        if az group show --name "$rg" &> /dev/null; then
            log "INFO" "Resources in $rg:"
            az resource list --resource-group "$rg" --query "[].{Name:name,Type:type,Location:location}" --output table || true
        else
            log "INFO" "Resource group $rg does not exist"
        fi
    done
}

terminate_database_connections() {
    log "INFO" "Terminating database connections..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would terminate active database connections"
        return 0
    fi
    
    # Get PostgreSQL server FQDN if it exists
    local pg_fqdn
    if pg_fqdn=$(az postgres flexible-server show \
        --name "${PG_SERVER_NAME}" \
        --resource-group "$RESOURCE_GROUP" \
        --query fullyQualifiedDomainName \
        --output tsv 2>/dev/null); then
        
        log "INFO" "Terminating connections to PostgreSQL server..."
        
        # Only attempt connection termination if psql is available
        if command -v psql &> /dev/null && [[ -n "${PG_ADMIN_PASSWORD:-}" ]]; then
            PGPASSWORD="$PG_ADMIN_PASSWORD" psql \
                --host="$pg_fqdn" \
                --port=5432 \
                --username="${PG_ADMIN_USER:-pgadmin}" \
                --dbname=postgres \
                --command="SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'production_db';" \
                --quiet || log "WARN" "Could not terminate database connections"
        else
            log "WARN" "psql not available or password not provided. Skipping connection termination."
        fi
    else
        log "INFO" "PostgreSQL server not found or already deleted"
    fi
    
    log "INFO" "✅ Database connections terminated"
}

delete_alert_rules() {
    log "INFO" "Deleting alert rules and monitoring..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete alert rules and action groups"
        return 0
    fi
    
    # List of alert rules to delete
    local alert_rules=(
        "PostgreSQL-ConnectionFailures"
        "PostgreSQL-ReplicationLag"
        "PostgreSQL-BackupFailures"
    )
    
    # Delete alert rules
    for rule in "${alert_rules[@]}"; do
        if az monitor metrics alert show --name "$rule" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log "INFO" "Deleting alert rule: $rule"
            az monitor metrics alert delete \
                --name "$rule" \
                --resource-group "$RESOURCE_GROUP" \
                --only-show-errors || log "WARN" "Failed to delete alert rule: $rule"
        fi
    done
    
    # Delete action group
    if az monitor action-group show --name "DisasterRecoveryAlerts" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "INFO" "Deleting action group: DisasterRecoveryAlerts"
        az monitor action-group delete \
            --name "DisasterRecoveryAlerts" \
            --resource-group "$RESOURCE_GROUP" \
            --only-show-errors || log "WARN" "Failed to delete action group"
    fi
    
    log "INFO" "✅ Alert rules and monitoring deleted"
}

delete_automation_account() {
    log "INFO" "Deleting automation account..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete automation account: ${AUTOMATION_ACCOUNT}"
        return 0
    fi
    
    if az automation account show --name "${AUTOMATION_ACCOUNT}" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "INFO" "Deleting automation account: ${AUTOMATION_ACCOUNT}"
        az automation account delete \
            --name "${AUTOMATION_ACCOUNT}" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --only-show-errors || log "WARN" "Failed to delete automation account"
    else
        log "INFO" "Automation account not found or already deleted"
    fi
    
    log "INFO" "✅ Automation account deleted"
}

delete_backup_vaults() {
    log "INFO" "Deleting backup vaults..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete backup vaults"
        return 0
    fi
    
    local backup_vaults=(
        "${BACKUP_VAULT_NAME}:${RESOURCE_GROUP}"
        "${BACKUP_VAULT_SECONDARY}:${RESOURCE_GROUP}-secondary"
    )
    
    for vault_info in "${backup_vaults[@]}"; do
        local vault_name="${vault_info%%:*}"
        local vault_rg="${vault_info##*:}"
        
        if az dataprotection backup-vault show --name "$vault_name" --resource-group "$vault_rg" &> /dev/null; then
            log "INFO" "Deleting backup vault: $vault_name"
            az dataprotection backup-vault delete \
                --name "$vault_name" \
                --resource-group "$vault_rg" \
                --yes \
                --only-show-errors || log "WARN" "Failed to delete backup vault: $vault_name"
        else
            log "INFO" "Backup vault $vault_name not found or already deleted"
        fi
    done
    
    log "INFO" "✅ Backup vaults deleted"
}

delete_storage_account() {
    log "INFO" "Deleting storage account..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete storage account: ${STORAGE_ACCOUNT_NAME}"
        return 0
    fi
    
    if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "INFO" "Deleting storage account: ${STORAGE_ACCOUNT_NAME}"
        az storage account delete \
            --name "${STORAGE_ACCOUNT_NAME}" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --only-show-errors || log "WARN" "Failed to delete storage account"
    else
        log "INFO" "Storage account not found or already deleted"
    fi
    
    log "INFO" "✅ Storage account deleted"
}

delete_postgresql_resources() {
    log "INFO" "Deleting PostgreSQL resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete PostgreSQL servers"
        return 0
    fi
    
    # Delete read replica first
    local secondary_rg="${RESOURCE_GROUP}-secondary"
    if az postgres flexible-server show --name "${PG_REPLICA_NAME}" --resource-group "$secondary_rg" &> /dev/null; then
        log "INFO" "Deleting read replica: ${PG_REPLICA_NAME}"
        az postgres flexible-server delete \
            --name "${PG_REPLICA_NAME}" \
            --resource-group "$secondary_rg" \
            --yes \
            --only-show-errors || log "WARN" "Failed to delete read replica"
    else
        log "INFO" "Read replica not found or already deleted"
    fi
    
    # Wait a moment for replica deletion to complete
    sleep 10
    
    # Delete primary PostgreSQL server
    if az postgres flexible-server show --name "${PG_SERVER_NAME}" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "INFO" "Deleting primary PostgreSQL server: ${PG_SERVER_NAME}"
        az postgres flexible-server delete \
            --name "${PG_SERVER_NAME}" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --only-show-errors || log "WARN" "Failed to delete primary PostgreSQL server"
    else
        log "INFO" "Primary PostgreSQL server not found or already deleted"
    fi
    
    log "INFO" "✅ PostgreSQL resources deleted"
}

delete_log_analytics() {
    log "INFO" "Deleting Log Analytics workspace..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete Log Analytics workspace: ${LOG_ANALYTICS_WORKSPACE}"
        return 0
    fi
    
    if az monitor log-analytics workspace show --workspace-name "${LOG_ANALYTICS_WORKSPACE}" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "INFO" "Deleting Log Analytics workspace: ${LOG_ANALYTICS_WORKSPACE}"
        az monitor log-analytics workspace delete \
            --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --only-show-errors || log "WARN" "Failed to delete Log Analytics workspace"
    else
        log "INFO" "Log Analytics workspace not found or already deleted"
    fi
    
    log "INFO" "✅ Log Analytics workspace deleted"
}

delete_resource_groups() {
    log "INFO" "Deleting resource groups..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete resource groups"
        return 0
    fi
    
    local resource_groups=("$RESOURCE_GROUP" "${RESOURCE_GROUP}-secondary")
    
    for rg in "${resource_groups[@]}"; do
        if az group show --name "$rg" &> /dev/null; then
            log "INFO" "Deleting resource group: $rg"
            
            if [[ "$PARALLEL_CLEANUP" == "true" ]]; then
                az group delete \
                    --name "$rg" \
                    --yes \
                    --no-wait \
                    --only-show-errors &
            else
                az group delete \
                    --name "$rg" \
                    --yes \
                    --only-show-errors || log "WARN" "Failed to delete resource group: $rg"
            fi
        else
            log "INFO" "Resource group $rg does not exist"
        fi
    done
    
    if [[ "$PARALLEL_CLEANUP" == "true" ]]; then
        log "INFO" "Waiting for parallel resource group deletions to complete..."
        wait
    fi
    
    log "INFO" "✅ Resource groups deleted"
}

wait_for_completion() {
    if [[ "$PARALLEL_CLEANUP" == "true" ]]; then
        log "INFO" "Waiting for all cleanup operations to complete..."
        wait
    fi
}

verify_cleanup() {
    log "INFO" "Verifying cleanup completion..."
    
    local resource_groups=("$RESOURCE_GROUP" "${RESOURCE_GROUP}-secondary")
    local cleanup_success=true
    
    for rg in "${resource_groups[@]}"; do
        if az group show --name "$rg" &> /dev/null; then
            log "WARN" "Resource group $rg still exists"
            cleanup_success=false
        else
            log "INFO" "✅ Resource group $rg successfully deleted"
        fi
    done
    
    if [[ "$cleanup_success" == "true" ]]; then
        log "INFO" "🎉 Cleanup completed successfully!"
    else
        log "WARN" "Some resources may still exist. Check the Azure portal."
    fi
}

discover_resource_names() {
    log "INFO" "Discovering resource names..."
    
    # Try to discover PostgreSQL server name
    if [[ -z "${PG_SERVER_NAME:-}" ]]; then
        local postgres_servers
        postgres_servers=$(az postgres flexible-server list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$postgres_servers" ]]; then
            PG_SERVER_NAME=$(echo "$postgres_servers" | head -n1)
            log "INFO" "Discovered PostgreSQL server: $PG_SERVER_NAME"
        fi
    fi
    
    # Try to discover replica name
    if [[ -z "${PG_REPLICA_NAME:-}" ]]; then
        local replica_servers
        replica_servers=$(az postgres flexible-server list --resource-group "${RESOURCE_GROUP}-secondary" --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$replica_servers" ]]; then
            PG_REPLICA_NAME=$(echo "$replica_servers" | head -n1)
            log "INFO" "Discovered read replica: $PG_REPLICA_NAME"
        fi
    fi
    
    # Try to discover other resource names
    if [[ -z "${BACKUP_VAULT_NAME:-}" ]]; then
        local backup_vaults
        backup_vaults=$(az dataprotection backup-vault list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$backup_vaults" ]]; then
            BACKUP_VAULT_NAME=$(echo "$backup_vaults" | head -n1)
            log "INFO" "Discovered backup vault: $BACKUP_VAULT_NAME"
        fi
    fi
    
    # Set default names if not discovered
    PG_SERVER_NAME="${PG_SERVER_NAME:-pg-primary}"
    PG_REPLICA_NAME="${PG_REPLICA_NAME:-pg-replica}"
    BACKUP_VAULT_NAME="${BACKUP_VAULT_NAME:-bv-postgres}"
    BACKUP_VAULT_SECONDARY="${BACKUP_VAULT_SECONDARY:-bv-postgres-sec}"
    STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-stpostgres}"
    LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-postgres}"
    AUTOMATION_ACCOUNT="${AUTOMATION_ACCOUNT:-aa-postgres}"
}

main() {
    # Initialize logging
    echo "Cleanup started at $(date)" > "$LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -n|--postgres-name)
                PG_SERVER_NAME="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_CLEANUP=true
                shift
                ;;
            --skip-confirmation)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --parallel)
                PARALLEL_CLEANUP=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Run cleanup steps
    check_prerequisites
    validate_parameters
    discover_resource_names
    
    log "INFO" "Starting Azure PostgreSQL Disaster Recovery cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "DRY RUN MODE - No resources will be deleted"
        list_resources
        return 0
    fi
    
    # Show what will be deleted
    list_resources
    
    # Confirm cleanup
    confirm_cleanup
    
    # Execute cleanup steps in proper order
    terminate_database_connections
    delete_alert_rules
    delete_automation_account
    delete_backup_vaults
    delete_storage_account
    delete_postgresql_resources
    delete_log_analytics
    
    # Wait for background operations
    wait_for_completion
    
    # Delete resource groups last
    delete_resource_groups
    
    # Verify cleanup
    verify_cleanup
    
    log "INFO" "Cleanup process completed"
}

# =============================================================================
# Error handling
# =============================================================================

cleanup_on_error() {
    local exit_code=$?
    log "ERROR" "Cleanup failed with exit code $exit_code"
    log "INFO" "Check the log file for details: $LOG_FILE"
    log "INFO" "Some resources may still exist. Check the Azure portal."
    exit $exit_code
}

trap cleanup_on_error ERR

# =============================================================================
# Main execution
# =============================================================================

main "$@"