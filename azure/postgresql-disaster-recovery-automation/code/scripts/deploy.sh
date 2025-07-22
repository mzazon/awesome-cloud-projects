#!/bin/bash

# =============================================================================
# Deploy Azure PostgreSQL Disaster Recovery Solution
# =============================================================================
# This script deploys a comprehensive disaster recovery solution for Azure 
# Database for PostgreSQL Flexible Server with automated backup management,
# cross-region replication, and monitoring-driven recovery workflows.
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# =============================================================================
# Configuration and Constants
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=false
FORCE_DEPLOY=false
SKIP_PREREQUISITES=false

# Default configuration
DEFAULT_LOCATION="East US"
DEFAULT_SECONDARY_LOCATION="West US 2"
DEFAULT_PG_ADMIN_USER="pgadmin"
DEFAULT_BACKUP_RETENTION_DAYS=35
DEFAULT_STORAGE_SIZE_GB=128
DEFAULT_SKU_NAME="Standard_D4s_v3"

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

Deploy Azure PostgreSQL Disaster Recovery Solution

OPTIONS:
    -g, --resource-group NAME       Primary resource group name
    -l, --location LOCATION         Primary Azure region (default: ${DEFAULT_LOCATION})
    -s, --secondary-location REGION Secondary Azure region (default: ${DEFAULT_SECONDARY_LOCATION})
    -n, --postgres-name NAME        PostgreSQL server name prefix
    -u, --admin-user USERNAME       PostgreSQL admin username (default: ${DEFAULT_PG_ADMIN_USER})
    -p, --admin-password PASSWORD   PostgreSQL admin password (prompted if not provided)
    --backup-retention DAYS         Backup retention days (default: ${DEFAULT_BACKUP_RETENTION_DAYS})
    --storage-size SIZE_GB          Storage size in GB (default: ${DEFAULT_STORAGE_SIZE_GB})
    --sku-name SKU                  PostgreSQL SKU name (default: ${DEFAULT_SKU_NAME})
    --dry-run                       Show what would be deployed without making changes
    --force                         Force deployment even if resources exist
    --skip-prerequisites            Skip prerequisite checks
    -h, --help                      Show this help message
    -v, --verbose                   Enable verbose logging

Examples:
    $0 -g mygroup -n mypostgres
    $0 -g mygroup -l "East US" -s "West US 2" --dry-run
    $0 --resource-group mygroup --postgres-name mydb --force

EOF
}

check_prerequisites() {
    if [[ "$SKIP_PREREQUISITES" == "true" ]]; then
        log "INFO" "Skipping prerequisite checks"
        return 0
    fi
    
    log "INFO" "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log "ERROR" "Azure CLI is not installed. Please install it first."
        log "INFO" "Install instructions: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az --version | head -n 1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
    log "INFO" "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log "ERROR" "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if psql is available (for database operations)
    if ! command -v psql &> /dev/null; then
        log "WARN" "psql is not installed. Database operations may be limited."
        log "INFO" "Install PostgreSQL client tools if you need database access."
    fi
    
    # Check if required extensions are installed
    local required_extensions=("dataprotection" "automation")
    for ext in "${required_extensions[@]}"; do
        if ! az extension show --name "$ext" &> /dev/null; then
            log "INFO" "Installing Azure CLI extension: $ext"
            az extension add --name "$ext" --only-show-errors
        fi
    done
    
    log "INFO" "Prerequisites check completed"
}

generate_random_suffix() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 3
    else
        # Fallback to using /dev/urandom
        head -c 3 /dev/urandom | xxd -p
    fi
}

validate_parameters() {
    log "INFO" "Validating deployment parameters..."
    
    # Check required parameters
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log "ERROR" "Resource group name is required. Use -g or --resource-group."
        exit 1
    fi
    
    if [[ -z "${PG_SERVER_NAME:-}" ]]; then
        log "ERROR" "PostgreSQL server name is required. Use -n or --postgres-name."
        exit 1
    fi
    
    # Validate Azure regions
    local valid_regions
    valid_regions=$(az account list-locations --query "[].name" --output tsv 2>/dev/null) || {
        log "WARN" "Could not validate Azure regions. Proceeding with deployment..."
    }
    
    if [[ -n "$valid_regions" ]]; then
        if ! echo "$valid_regions" | grep -q "^${LOCATION}$"; then
            log "ERROR" "Invalid primary location: $LOCATION"
            exit 1
        fi
        
        if ! echo "$valid_regions" | grep -q "^${SECONDARY_LOCATION}$"; then
            log "ERROR" "Invalid secondary location: $SECONDARY_LOCATION"
            exit 1
        fi
    fi
    
    # Validate PostgreSQL admin password
    if [[ -z "${PG_ADMIN_PASSWORD:-}" ]]; then
        log "ERROR" "PostgreSQL admin password is required."
        exit 1
    fi
    
    # Validate password complexity
    if [[ ${#PG_ADMIN_PASSWORD} -lt 8 ]]; then
        log "ERROR" "PostgreSQL admin password must be at least 8 characters long."
        exit 1
    fi
    
    log "INFO" "Parameter validation completed"
}

prompt_for_password() {
    if [[ -z "${PG_ADMIN_PASSWORD:-}" ]]; then
        echo -n "Enter PostgreSQL admin password: "
        read -s PG_ADMIN_PASSWORD
        echo
        
        if [[ -z "$PG_ADMIN_PASSWORD" ]]; then
            log "ERROR" "Password cannot be empty"
            exit 1
        fi
    fi
}

create_resource_groups() {
    log "INFO" "Creating resource groups..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        log "INFO" "[DRY RUN] Would create resource group: ${RESOURCE_GROUP}-secondary in $SECONDARY_LOCATION"
        return 0
    fi
    
    # Create primary resource group
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        if [[ "$FORCE_DEPLOY" == "true" ]]; then
            log "INFO" "Resource group $RESOURCE_GROUP already exists. Continuing due to --force flag."
        else
            log "WARN" "Resource group $RESOURCE_GROUP already exists. Use --force to continue."
        fi
    else
        log "INFO" "Creating primary resource group: $RESOURCE_GROUP"
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=disaster-recovery environment=production \
            --only-show-errors
    fi
    
    # Create secondary resource group
    local secondary_rg="${RESOURCE_GROUP}-secondary"
    if az group show --name "$secondary_rg" &> /dev/null; then
        if [[ "$FORCE_DEPLOY" == "true" ]]; then
            log "INFO" "Resource group $secondary_rg already exists. Continuing due to --force flag."
        else
            log "WARN" "Resource group $secondary_rg already exists. Use --force to continue."
        fi
    else
        log "INFO" "Creating secondary resource group: $secondary_rg"
        az group create \
            --name "$secondary_rg" \
            --location "$SECONDARY_LOCATION" \
            --tags purpose=disaster-recovery environment=production \
            --only-show-errors
    fi
    
    log "INFO" "✅ Resource groups created successfully"
}

create_postgresql_server() {
    log "INFO" "Creating PostgreSQL Flexible Server with high availability..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create PostgreSQL server: $PG_SERVER_NAME"
        return 0
    fi
    
    # Check if server already exists
    if az postgres flexible-server show --name "$PG_SERVER_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        if [[ "$FORCE_DEPLOY" == "true" ]]; then
            log "INFO" "PostgreSQL server $PG_SERVER_NAME already exists. Continuing due to --force flag."
        else
            log "WARN" "PostgreSQL server $PG_SERVER_NAME already exists. Use --force to continue."
            return 0
        fi
    else
        log "INFO" "Creating PostgreSQL Flexible Server: $PG_SERVER_NAME"
        
        az postgres flexible-server create \
            --name "$PG_SERVER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --admin-user "$PG_ADMIN_USER" \
            --admin-password "$PG_ADMIN_PASSWORD" \
            --sku-name "$SKU_NAME" \
            --tier GeneralPurpose \
            --storage-size "$STORAGE_SIZE_GB" \
            --storage-auto-grow Enabled \
            --backup-retention "$BACKUP_RETENTION_DAYS" \
            --geo-redundant-backup Enabled \
            --high-availability ZoneRedundant \
            --tags environment=production purpose=primary \
            --only-show-errors
    fi
    
    # Configure firewall rules
    log "INFO" "Configuring firewall rules..."
    az postgres flexible-server firewall-rule create \
        --name "$PG_SERVER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --rule-name "AllowAzureServices" \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0 \
        --only-show-errors
    
    log "INFO" "✅ PostgreSQL server created with high availability"
}

create_read_replica() {
    log "INFO" "Creating cross-region read replica..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create read replica: $PG_REPLICA_NAME"
        return 0
    fi
    
    local secondary_rg="${RESOURCE_GROUP}-secondary"
    
    # Check if replica already exists
    if az postgres flexible-server show --name "$PG_REPLICA_NAME" --resource-group "$secondary_rg" &> /dev/null; then
        if [[ "$FORCE_DEPLOY" == "true" ]]; then
            log "INFO" "Read replica $PG_REPLICA_NAME already exists. Continuing due to --force flag."
        else
            log "WARN" "Read replica $PG_REPLICA_NAME already exists. Use --force to continue."
            return 0
        fi
    else
        log "INFO" "Creating read replica: $PG_REPLICA_NAME"
        
        az postgres flexible-server replica create \
            --name "$PG_REPLICA_NAME" \
            --resource-group "$secondary_rg" \
            --source-server "$PG_SERVER_NAME" \
            --location "$SECONDARY_LOCATION" \
            --tags environment=production purpose=replica \
            --only-show-errors
    fi
    
    # Configure replica firewall rules
    log "INFO" "Configuring replica firewall rules..."
    az postgres flexible-server firewall-rule create \
        --name "$PG_REPLICA_NAME" \
        --resource-group "$secondary_rg" \
        --rule-name "AllowAzureServices" \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0 \
        --only-show-errors
    
    log "INFO" "✅ Read replica created successfully"
}

create_backup_infrastructure() {
    log "INFO" "Setting up backup infrastructure..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create backup vaults: $BACKUP_VAULT_NAME"
        return 0
    fi
    
    local secondary_rg="${RESOURCE_GROUP}-secondary"
    
    # Create primary backup vault
    log "INFO" "Creating primary backup vault: $BACKUP_VAULT_NAME"
    az dataprotection backup-vault create \
        --name "$BACKUP_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --storage-settings datastore-type=VaultStore type=GeoRedundant \
        --tags purpose=backup environment=production \
        --only-show-errors
    
    # Create secondary backup vault
    log "INFO" "Creating secondary backup vault: $BACKUP_VAULT_SECONDARY"
    az dataprotection backup-vault create \
        --name "$BACKUP_VAULT_SECONDARY" \
        --resource-group "$secondary_rg" \
        --location "$SECONDARY_LOCATION" \
        --storage-settings datastore-type=VaultStore type=GeoRedundant \
        --tags purpose=backup environment=production \
        --only-show-errors
    
    log "INFO" "✅ Backup infrastructure created successfully"
}

create_monitoring_infrastructure() {
    log "INFO" "Setting up monitoring and alerting..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
        return 0
    fi
    
    # Create Log Analytics workspace
    log "INFO" "Creating Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
    az monitor log-analytics workspace create \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=monitoring environment=production \
        --only-show-errors
    
    # Get workspace ID
    local workspace_id
    workspace_id=$(az monitor log-analytics workspace show \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query customerId \
        --output tsv)
    
    # Get subscription ID
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    
    # Configure diagnostic settings
    log "INFO" "Configuring diagnostic settings..."
    az monitor diagnostic-settings create \
        --name "PostgreSQLDiagnostics" \
        --resource "/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DBforPostgreSQL/flexibleServers/${PG_SERVER_NAME}" \
        --workspace "$workspace_id" \
        --logs '[{"categoryGroup":"allLogs","enabled":true,"retentionPolicy":{"enabled":true,"days":90}}]' \
        --metrics '[{"category":"AllMetrics","enabled":true,"retentionPolicy":{"enabled":true,"days":90}}]' \
        --only-show-errors
    
    log "INFO" "✅ Monitoring infrastructure created successfully"
}

create_storage_account() {
    log "INFO" "Creating storage account for backup artifacts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create storage account: $STORAGE_ACCOUNT_NAME"
        return 0
    fi
    
    # Create storage account
    log "INFO" "Creating storage account: $STORAGE_ACCOUNT_NAME"
    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_GRS \
        --kind StorageV2 \
        --access-tier Hot \
        --tags purpose=backup environment=production \
        --only-show-errors
    
    # Create containers
    log "INFO" "Creating storage containers..."
    local containers=("database-backups" "recovery-scripts" "recovery-logs")
    for container in "${containers[@]}"; do
        az storage container create \
            --name "$container" \
            --account-name "$STORAGE_ACCOUNT_NAME" \
            --auth-mode login \
            --only-show-errors
    done
    
    log "INFO" "✅ Storage account created successfully"
}

create_automation_account() {
    log "INFO" "Setting up automation account..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create automation account: $AUTOMATION_ACCOUNT"
        return 0
    fi
    
    # Create automation account
    log "INFO" "Creating automation account: $AUTOMATION_ACCOUNT"
    az automation account create \
        --name "$AUTOMATION_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=automation environment=production \
        --only-show-errors
    
    # Create credential
    log "INFO" "Creating automation credential..."
    az automation credential create \
        --name "PostgreSQLAdmin" \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --user-name "$PG_ADMIN_USER" \
        --password "$PG_ADMIN_PASSWORD" \
        --only-show-errors
    
    log "INFO" "✅ Automation account created successfully"
}

create_alert_rules() {
    log "INFO" "Creating alert rules..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create alert rules and action groups"
        return 0
    fi
    
    # Create action group
    log "INFO" "Creating action group for alerts..."
    az monitor action-group create \
        --name "DisasterRecoveryAlerts" \
        --resource-group "$RESOURCE_GROUP" \
        --short-name "DRAlerts" \
        --only-show-errors
    
    # Get subscription ID
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    
    # Create alert rules
    local alert_rules=(
        "PostgreSQL-ConnectionFailures:failed_connections:>:10"
        "PostgreSQL-ReplicationLag:replica_lag:>:300"
        "PostgreSQL-BackupFailures:backup_failures:>:0"
    )
    
    for rule in "${alert_rules[@]}"; do
        local alert_name="${rule%%:*}"
        local metric_name="${rule#*:}"
        metric_name="${metric_name%%:*}"
        local operator="${rule#*:*:}"
        operator="${operator%%:*}"
        local threshold="${rule##*:}"
        
        log "INFO" "Creating alert rule: $alert_name"
        az monitor metrics alert create \
            --name "$alert_name" \
            --resource-group "$RESOURCE_GROUP" \
            --scopes "/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DBforPostgreSQL/flexibleServers/${PG_SERVER_NAME}" \
            --condition "count static ${metric_name} ${operator} ${threshold}" \
            --window-size 5m \
            --evaluation-frequency 1m \
            --severity 2 \
            --action-groups "/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Insights/actionGroups/DisasterRecoveryAlerts" \
            --only-show-errors
    done
    
    log "INFO" "✅ Alert rules created successfully"
}

create_sample_data() {
    log "INFO" "Creating sample database and test data..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create sample database and test data"
        return 0
    fi
    
    # Check if psql is available
    if ! command -v psql &> /dev/null; then
        log "WARN" "psql not available. Skipping sample data creation."
        return 0
    fi
    
    # Get PostgreSQL FQDN
    local pg_fqdn
    pg_fqdn=$(az postgres flexible-server show \
        --name "$PG_SERVER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query fullyQualifiedDomainName \
        --output tsv)
    
    # Create sample database and data
    log "INFO" "Creating sample database..."
    
    # Create a temporary SQL file
    local sql_file=$(mktemp)
    cat > "$sql_file" << 'EOF'
CREATE DATABASE production_db;
\c production_db;

CREATE TABLE customer_data (
    id SERIAL PRIMARY KEY,
    customer_name VARCHAR(100),
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO customer_data (customer_name, email) VALUES
('John Doe', 'john.doe@example.com'),
('Jane Smith', 'jane.smith@example.com'),
('Bob Johnson', 'bob.johnson@example.com'),
('Alice Brown', 'alice.brown@example.com'),
('Charlie Wilson', 'charlie.wilson@example.com');

CREATE TABLE order_history (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES customer_data(id),
    order_amount DECIMAL(10,2),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO order_history (customer_id, order_amount) VALUES
(1, 150.00),
(2, 200.50),
(3, 75.25),
(1, 300.00),
(4, 125.75);

CREATE INDEX idx_customer_email ON customer_data(email);
CREATE INDEX idx_order_date ON order_history(order_date);

SELECT 'Database and sample data created successfully' AS result;
EOF
    
    # Execute SQL file
    PGPASSWORD="$PG_ADMIN_PASSWORD" psql \
        --host="$pg_fqdn" \
        --port=5432 \
        --username="$PG_ADMIN_USER" \
        --dbname=postgres \
        --file="$sql_file" \
        --quiet
    
    # Clean up temporary file
    rm -f "$sql_file"
    
    log "INFO" "✅ Sample database and test data created successfully"
}

display_deployment_summary() {
    log "INFO" "Deployment Summary:"
    log "INFO" "=================="
    log "INFO" "Primary Resource Group: $RESOURCE_GROUP"
    log "INFO" "Secondary Resource Group: ${RESOURCE_GROUP}-secondary"
    log "INFO" "Primary Location: $LOCATION"
    log "INFO" "Secondary Location: $SECONDARY_LOCATION"
    log "INFO" "PostgreSQL Server: $PG_SERVER_NAME"
    log "INFO" "Read Replica: $PG_REPLICA_NAME"
    log "INFO" "Backup Vault: $BACKUP_VAULT_NAME"
    log "INFO" "Storage Account: $STORAGE_ACCOUNT_NAME"
    log "INFO" "Automation Account: $AUTOMATION_ACCOUNT"
    log "INFO" "Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
    log "INFO" ""
    log "INFO" "Next Steps:"
    log "INFO" "1. Test database connectivity"
    log "INFO" "2. Verify read replica synchronization"
    log "INFO" "3. Review backup policies"
    log "INFO" "4. Test disaster recovery procedures"
    log "INFO" "5. Configure application connection strings"
    log "INFO" ""
    log "INFO" "For cleanup, run: ./destroy.sh --resource-group $RESOURCE_GROUP"
}

main() {
    # Initialize logging
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    # Set defaults
    LOCATION="$DEFAULT_LOCATION"
    SECONDARY_LOCATION="$DEFAULT_SECONDARY_LOCATION"
    PG_ADMIN_USER="$DEFAULT_PG_ADMIN_USER"
    BACKUP_RETENTION_DAYS="$DEFAULT_BACKUP_RETENTION_DAYS"
    STORAGE_SIZE_GB="$DEFAULT_STORAGE_SIZE_GB"
    SKU_NAME="$DEFAULT_SKU_NAME"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -s|--secondary-location)
                SECONDARY_LOCATION="$2"
                shift 2
                ;;
            -n|--postgres-name)
                PG_SERVER_NAME="$2"
                shift 2
                ;;
            -u|--admin-user)
                PG_ADMIN_USER="$2"
                shift 2
                ;;
            -p|--admin-password)
                PG_ADMIN_PASSWORD="$2"
                shift 2
                ;;
            --backup-retention)
                BACKUP_RETENTION_DAYS="$2"
                shift 2
                ;;
            --storage-size)
                STORAGE_SIZE_GB="$2"
                shift 2
                ;;
            --sku-name)
                SKU_NAME="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_DEPLOY=true
                shift
                ;;
            --skip-prerequisites)
                SKIP_PREREQUISITES=true
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
    
    # Generate unique suffix for resources
    local random_suffix
    random_suffix=$(generate_random_suffix)
    
    # Set derived resource names
    PG_REPLICA_NAME="${PG_SERVER_NAME:-pg-primary-${random_suffix}}-replica"
    PG_SERVER_NAME="${PG_SERVER_NAME:-pg-primary-${random_suffix}}"
    BACKUP_VAULT_NAME="${BACKUP_VAULT_NAME:-bv-postgres-${random_suffix}}"
    BACKUP_VAULT_SECONDARY="${BACKUP_VAULT_SECONDARY:-bv-postgres-sec-${random_suffix}}"
    STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-stpostgres${random_suffix}}"
    LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-postgres-${random_suffix}}"
    AUTOMATION_ACCOUNT="${AUTOMATION_ACCOUNT:-aa-postgres-${random_suffix}}"
    
    # Prompt for password if not provided
    prompt_for_password
    
    # Run deployment steps
    check_prerequisites
    validate_parameters
    
    log "INFO" "Starting Azure PostgreSQL Disaster Recovery deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "DRY RUN MODE - No resources will be created"
    fi
    
    # Execute deployment steps
    create_resource_groups
    create_postgresql_server
    create_read_replica
    create_backup_infrastructure
    create_monitoring_infrastructure
    create_storage_account
    create_automation_account
    create_alert_rules
    create_sample_data
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "DRY RUN completed successfully"
    else
        log "INFO" "🎉 Deployment completed successfully!"
        display_deployment_summary
    fi
}

# =============================================================================
# Error handling and cleanup
# =============================================================================

cleanup_on_error() {
    local exit_code=$?
    log "ERROR" "Deployment failed with exit code $exit_code"
    log "INFO" "Check the log file for details: $LOG_FILE"
    exit $exit_code
}

trap cleanup_on_error ERR

# =============================================================================
# Main execution
# =============================================================================

main "$@"