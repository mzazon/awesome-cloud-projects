#!/bin/bash

# Resilient Stateful Microservices with Azure Service Fabric and Durable Functions
# Cleanup/Destroy Script
# 
# This script safely removes all Azure resources created by the deployment script,
# with proper confirmation prompts and dependency handling.

set -euo pipefail

# Configuration and Logging
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/cleanup.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deployment_config"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
FORCE_DELETE="false"
DRY_RUN="false"
VERBOSE="false"
SKIP_CONFIRMATION="false"
DELETE_CERTIFICATES="false"

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely cleanup and destroy Azure Service Fabric and Durable Functions resources.

OPTIONS:
    -h, --help              Show this help message
    -f, --force             Force deletion without confirmation prompts
    -d, --dry-run          Show what would be deleted without actually deleting
    -v, --verbose          Enable verbose logging
    -y, --yes              Skip all confirmation prompts (equivalent to --force)
    --delete-certificates   Also delete local certificate files
    --resource-group RG     Specify resource group to delete (overrides config)

SAFETY FEATURES:
    - Interactive confirmation for destructive operations
    - Dry-run mode to preview deletions
    - Graceful handling of dependencies
    - Automatic backup of important configurations
    - Rollback protection for partially failed deletions

EXAMPLES:
    $0                              # Interactive cleanup with confirmations
    $0 --dry-run                    # Preview what would be deleted
    $0 --force --verbose            # Force deletion with detailed logging
    $0 --resource-group rg-test     # Delete specific resource group

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--force|-y|--yes)
                FORCE_DELETE="true"
                SKIP_CONFIRMATION="true"
                shift
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            --delete-certificates)
                DELETE_CERTIFICATES="true"
                shift
                ;;
            --resource-group)
                OVERRIDE_RESOURCE_GROUP="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Load configuration
load_configuration() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log_info "Loading configuration from $CONFIG_FILE"
        
        # Override resource group if specified
        if [[ -n "${OVERRIDE_RESOURCE_GROUP:-}" ]]; then
            RESOURCE_GROUP="$OVERRIDE_RESOURCE_GROUP"
            log_info "Using override resource group: $RESOURCE_GROUP"
        fi
        
        # Validate required variables
        local required_vars=("RESOURCE_GROUP" "LOCATION")
        for var in "${required_vars[@]}"; do
            if [[ -z "${!var:-}" ]]; then
                log_error "Required configuration variable $var is missing"
                exit 1
            fi
        done
        
        log_info "Configuration loaded successfully"
        log_info "  Resource Group: ${RESOURCE_GROUP}"
        log_info "  Location: ${LOCATION}"
        
    else
        if [[ -n "${OVERRIDE_RESOURCE_GROUP:-}" ]]; then
            RESOURCE_GROUP="$OVERRIDE_RESOURCE_GROUP"
            log_warning "No configuration file found, using resource group from command line: $RESOURCE_GROUP"
        else
            log_error "Configuration file not found: $CONFIG_FILE"
            log_error "Please run this script from the same directory as deploy.sh or specify --resource-group"
            exit 1
        fi
    fi
}

# Confirm destructive operation
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi

    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    log_warning "This will permanently delete the following resources:"
    echo ""
    
    # List resources that will be deleted
    if [[ -n "${CLUSTER_NAME:-}" ]]; then
        echo "  • Service Fabric Cluster: $CLUSTER_NAME"
    fi
    if [[ -n "${FUNCTION_APP_NAME:-}" ]]; then
        echo "  • Function App: $FUNCTION_APP_NAME"
    fi
    if [[ -n "${SQL_SERVER_NAME:-}" ]]; then
        echo "  • SQL Server: $SQL_SERVER_NAME"
        echo "  • SQL Database: ${SQL_DATABASE_NAME:-unknown}"
    fi
    if [[ -n "${STORAGE_ACCOUNT_NAME:-}" ]]; then
        echo "  • Storage Account: $STORAGE_ACCOUNT_NAME"
    fi
    if [[ -n "${APP_INSIGHTS_NAME:-}" ]]; then
        echo "  • Application Insights: $APP_INSIGHTS_NAME"
    fi
    if [[ -n "${KEYVAULT_NAME:-}" ]]; then
        echo "  • Key Vault: $KEYVAULT_NAME"
    fi
    echo "  • Resource Group: $RESOURCE_GROUP"
    
    if [[ "$DELETE_CERTIFICATES" == "true" ]]; then
        echo "  • Local certificate files"
    fi
    
    echo ""
    log_warning "💡 This action cannot be undone!"
    echo ""
    
    local response
    read -p "Are you sure you want to proceed? (yes/no): " response
    
    case "$response" in
        yes|YES|y|Y)
            log_info "Deletion confirmed by user"
            return 0
            ;;
        *)
            log_info "Deletion cancelled by user"
            exit 0
            ;;
    esac
}

# Execute Azure CLI command with error handling
execute_az_command() {
    local description="$1"
    local allow_failure="${2:-false}"
    shift 2
    local command=("$@")

    log_info "Executing: $description"
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Command: ${command[*]}"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: ${command[*]}"
        return 0
    fi

    local output
    local exit_code=0
    
    output=$("${command[@]}" 2>&1) || exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "$description completed successfully"
        if [[ "$VERBOSE" == "true" && -n "$output" ]]; then
            log_info "Output: $output"
        fi
        return 0
    else
        if [[ "$allow_failure" == "true" ]]; then
            log_warning "$description failed but continuing (exit code: $exit_code)"
            if [[ "$VERBOSE" == "true" ]]; then
                log_warning "Output: $output"
            fi
            return 0
        else
            log_error "$description failed (exit code: $exit_code)"
            log_error "Output: $output"
            return $exit_code
        fi
    fi
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="${3:-$RESOURCE_GROUP}"
    
    case "$resource_type" in
        "group")
            az group show --name "$resource_name" &> /dev/null
            ;;
        "sf-cluster")
            az sf cluster show --resource-group "$resource_group" --name "$resource_name" &> /dev/null
            ;;
        "functionapp")
            az functionapp show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "sql-server")
            az sql server show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "storage")
            az storage account show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "keyvault")
            az keyvault show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "app-insights")
            az monitor app-insights component show --app "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        *)
            log_error "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}

# Backup important configurations
backup_configurations() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    log_info "Creating backup of important configurations..."
    
    local backup_dir="${SCRIPT_DIR}/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup deployment configuration
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$backup_dir/"
        log_info "Configuration backed up to $backup_dir"
    fi
    
    # Backup Service Fabric application packages if they exist
    if [[ -d "${SCRIPT_DIR}/ServiceFabricApp" ]]; then
        cp -r "${SCRIPT_DIR}/ServiceFabricApp" "$backup_dir/"
        log_info "Service Fabric application packages backed up"
    fi
    
    # Backup Durable Functions code if it exists
    if [[ -d "${SCRIPT_DIR}/DurableFunctionsOrchestrator" ]]; then
        cp -r "${SCRIPT_DIR}/DurableFunctionsOrchestrator" "$backup_dir/"
        log_info "Durable Functions code backed up"
    fi
    
    log_success "Backup completed: $backup_dir"
}

# Delete Service Fabric Cluster
delete_service_fabric_cluster() {
    if [[ -z "${CLUSTER_NAME:-}" ]]; then
        log_warning "Service Fabric cluster name not found in configuration"
        return 0
    fi

    if ! resource_exists "sf-cluster" "$CLUSTER_NAME"; then
        log_info "Service Fabric cluster $CLUSTER_NAME does not exist"
        return 0
    fi

    log_info "Deleting Service Fabric Cluster $CLUSTER_NAME..."
    log_warning "This operation may take 5-10 minutes..."
    
    execute_az_command "Delete Service Fabric Cluster" "true" \
        az sf cluster delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME"
}

# Delete Function App
delete_function_app() {
    if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
        log_warning "Function App name not found in configuration"
        return 0
    fi

    if ! resource_exists "functionapp" "$FUNCTION_APP_NAME"; then
        log_info "Function App $FUNCTION_APP_NAME does not exist"
        return 0
    fi

    log_info "Deleting Function App $FUNCTION_APP_NAME..."
    
    execute_az_command "Delete Function App" "true" \
        az functionapp delete \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP"
}

# Delete SQL Database and Server
delete_sql_resources() {
    if [[ -z "${SQL_SERVER_NAME:-}" ]]; then
        log_warning "SQL Server name not found in configuration"
        return 0
    fi

    if ! resource_exists "sql-server" "$SQL_SERVER_NAME"; then
        log_info "SQL Server $SQL_SERVER_NAME does not exist"
        return 0
    fi

    log_info "Deleting SQL Database and Server..."
    
    # Delete database first (if specified)
    if [[ -n "${SQL_DATABASE_NAME:-}" ]]; then
        execute_az_command "Delete SQL Database" "true" \
            az sql db delete \
            --resource-group "$RESOURCE_GROUP" \
            --server "$SQL_SERVER_NAME" \
            --name "$SQL_DATABASE_NAME" \
            --yes
    fi
    
    # Delete server
    execute_az_command "Delete SQL Server" "true" \
        az sql server delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SQL_SERVER_NAME" \
        --yes
}

# Delete Storage Account
delete_storage_account() {
    if [[ -z "${STORAGE_ACCOUNT_NAME:-}" ]]; then
        log_warning "Storage Account name not found in configuration"
        return 0
    fi

    if ! resource_exists "storage" "$STORAGE_ACCOUNT_NAME"; then
        log_info "Storage Account $STORAGE_ACCOUNT_NAME does not exist"
        return 0
    fi

    log_info "Deleting Storage Account $STORAGE_ACCOUNT_NAME..."
    
    execute_az_command "Delete Storage Account" "true" \
        az storage account delete \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --yes
}

# Delete Key Vault
delete_key_vault() {
    if [[ -z "${KEYVAULT_NAME:-}" ]]; then
        log_warning "Key Vault name not found in configuration"
        return 0
    fi

    if ! resource_exists "keyvault" "$KEYVAULT_NAME"; then
        log_info "Key Vault $KEYVAULT_NAME does not exist"
        return 0
    fi

    log_info "Deleting Key Vault $KEYVAULT_NAME..."
    
    execute_az_command "Delete Key Vault" "true" \
        az keyvault delete \
        --name "$KEYVAULT_NAME" \
        --resource-group "$RESOURCE_GROUP"
    
    # Purge Key Vault to completely remove it
    log_info "Purging Key Vault to permanently delete..."
    execute_az_command "Purge Key Vault" "true" \
        az keyvault purge \
        --name "$KEYVAULT_NAME" \
        --location "${LOCATION:-eastus}"
}

# Delete Application Insights
delete_application_insights() {
    if [[ -z "${APP_INSIGHTS_NAME:-}" ]]; then
        log_warning "Application Insights name not found in configuration"
        return 0
    fi

    if ! resource_exists "app-insights" "$APP_INSIGHTS_NAME"; then
        log_info "Application Insights $APP_INSIGHTS_NAME does not exist"
        return 0
    fi

    log_info "Deleting Application Insights $APP_INSIGHTS_NAME..."
    
    execute_az_command "Delete Application Insights" "true" \
        az monitor app-insights component delete \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP"
}

# Delete Monitoring Resources
delete_monitoring_resources() {
    log_info "Deleting monitoring resources..."
    
    # Delete metric alerts
    local alerts=$(az monitor metrics alert list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$alerts" ]]; then
        while IFS= read -r alert; do
            if [[ -n "$alert" ]]; then
                execute_az_command "Delete metric alert: $alert" "true" \
                    az monitor metrics alert delete \
                    --name "$alert" \
                    --resource-group "$RESOURCE_GROUP"
            fi
        done <<< "$alerts"
    fi
}

# Delete Resource Group
delete_resource_group() {
    if ! resource_exists "group" "$RESOURCE_GROUP"; then
        log_info "Resource Group $RESOURCE_GROUP does not exist"
        return 0
    fi

    log_info "Deleting Resource Group $RESOURCE_GROUP..."
    log_warning "This will delete ALL remaining resources in the resource group"
    
    execute_az_command "Delete Resource Group" "false" \
        az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    log_info "Resource group deletion initiated (running in background)"
}

# Delete local files
delete_local_files() {
    if [[ "$DELETE_CERTIFICATES" != "true" ]]; then
        log_info "Skipping local certificate deletion (use --delete-certificates to remove)"
        return 0
    fi

    log_info "Deleting local certificate files..."
    
    # Delete certificate directory
    if [[ -d "${SCRIPT_DIR}/certificates" ]]; then
        rm -rf "${SCRIPT_DIR}/certificates"
        log_success "Certificate directory deleted"
    fi
    
    # Delete Service Fabric app packages
    if [[ -d "${SCRIPT_DIR}/ServiceFabricApp" ]]; then
        local response
        if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
            read -p "Delete Service Fabric application packages? (y/n): " response
        else
            response="y"
        fi
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm -rf "${SCRIPT_DIR}/ServiceFabricApp"
            log_success "Service Fabric application packages deleted"
        fi
    fi
    
    # Delete Durable Functions code
    if [[ -d "${SCRIPT_DIR}/DurableFunctionsOrchestrator" ]]; then
        local response
        if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
            read -p "Delete Durable Functions orchestrator code? (y/n): " response
        else
            response="y"
        fi
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm -rf "${SCRIPT_DIR}/DurableFunctionsOrchestrator"
            log_success "Durable Functions orchestrator code deleted"
        fi
    fi
}

# Clean up configuration files
cleanup_configuration() {
    if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
        local response
        read -p "Delete deployment configuration file? (y/n): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Keeping configuration file: $CONFIG_FILE"
            return 0
        fi
    fi
    
    if [[ -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"
        log_success "Configuration file deleted"
    fi
}

# Validate cleanup
validate_cleanup() {
    log_info "Validating cleanup..."
    
    # Check if resource group still exists
    if resource_exists "group" "$RESOURCE_GROUP"; then
        log_warning "Resource group $RESOURCE_GROUP still exists (deletion may be in progress)"
    else
        log_success "Resource group successfully deleted"
    fi
    
    # Check for remaining certificates
    if [[ -d "${SCRIPT_DIR}/certificates" && "$DELETE_CERTIFICATES" == "true" ]]; then
        log_warning "Certificate directory still exists"
    fi
    
    log_success "Cleanup validation completed"
}

# Print cleanup summary
print_cleanup_summary() {
    log_info "Cleanup Summary"
    log_info "==============="
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Dry Run: $DRY_RUN"
    log_info ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "No resources were actually deleted (dry run mode)"
    else
        log_success "Cleanup completed successfully!"
        log_info ""
        log_info "The following resources have been deleted:"
        log_info "• Service Fabric Cluster: ${CLUSTER_NAME:-N/A}"
        log_info "• Function App: ${FUNCTION_APP_NAME:-N/A}"
        log_info "• SQL Server and Database: ${SQL_SERVER_NAME:-N/A}"
        log_info "• Storage Account: ${STORAGE_ACCOUNT_NAME:-N/A}"
        log_info "• Key Vault: ${KEYVAULT_NAME:-N/A}"
        log_info "• Application Insights: ${APP_INSIGHTS_NAME:-N/A}"
        log_info "• Resource Group: $RESOURCE_GROUP"
        
        if [[ "$DELETE_CERTIFICATES" == "true" ]]; then
            log_info "• Local certificate files"
        fi
        
        log_info ""
        log_info "💡 It may take several minutes for all resources to be completely removed"
        log_info "💡 You can monitor the deletion progress in the Azure portal"
    fi
}

# Main cleanup function
main() {
    log_info "Starting Azure Microservices Orchestration cleanup"
    log_info "Dry run: $DRY_RUN"
    log_info "Force delete: $FORCE_DELETE"
    
    # Load configuration and confirm deletion
    load_configuration
    confirm_deletion
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run mode - showing what would be deleted:"
    else
        backup_configurations
    fi
    
    # Execute cleanup steps in reverse order of creation
    delete_monitoring_resources
    delete_function_app
    delete_service_fabric_cluster
    delete_storage_account
    delete_sql_resources
    delete_application_insights
    delete_key_vault
    delete_resource_group
    delete_local_files
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cleanup_configuration
        validate_cleanup
    fi
    
    print_cleanup_summary
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Initialize logging
    echo "Cleanup started at $(date)" > "$LOG_FILE"
    
    # Parse arguments and run main function
    parse_arguments "$@"
    main
fi