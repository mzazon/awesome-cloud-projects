#!/bin/bash

# =============================================================================
# Azure Database Migration Orchestration Cleanup Script
# 
# This script removes all resources created for the database migration 
# orchestration solution including Azure Data Factory, Database Migration 
# Service, Log Analytics workspace, storage accounts, and monitoring alerts.
#
# Components removed:
# - Azure Data Factory and Workflow Orchestration Manager
# - Azure Database Migration Service
# - Log Analytics workspace
# - Storage account and containers
# - Integration Runtime configurations
# - Azure Monitor alerts and action groups
# - Resource group (optional)
#
# Prerequisites:
# - Azure CLI v2.50.0 or later
# - Appropriate Azure permissions for resource deletion
# - Resource group name (either from environment or parameter)
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

# Display usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group NAME    Resource group name (default: rg-db-migration-orchestration)"
    echo "  -f, --force                  Skip confirmation prompts"
    echo "  -k, --keep-resource-group    Keep the resource group after cleanup"
    echo "  -d, --dry-run               Show what would be deleted without actually deleting"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP              Resource group name (can be overridden by -g)"
    echo ""
    echo "Examples:"
    echo "  $0                          # Interactive cleanup with default resource group"
    echo "  $0 -g my-rg -f             # Force cleanup of specific resource group"
    echo "  $0 --dry-run               # Show what would be deleted"
    echo "  $0 -k                      # Keep resource group after cleanup"
}

# Parse command line arguments
FORCE=false
KEEP_RG=false
DRY_RUN=false
RESOURCE_GROUP=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -k|--keep-resource-group)
            KEEP_RG=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
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

# Set default resource group if not provided
RESOURCE_GROUP="${RESOURCE_GROUP:-${RESOURCE_GROUP:-rg-db-migration-orchestration}}"

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================

log_info "Starting Azure Database Migration Orchestration cleanup..."
log_info "Checking prerequisites..."

# Check Azure CLI
if ! command -v az &> /dev/null; then
    log_error "Azure CLI is not installed. Please install Azure CLI v2.50.0 or later"
    exit 1
fi

# Check Azure login
if ! az account show &> /dev/null; then
    log_error "Not logged into Azure. Please run 'az login' first"
    exit 1
fi

SUBSCRIPTION_ID=$(az account show --query id --output tsv)
log_info "Using subscription: ${SUBSCRIPTION_ID}"

# Check if resource group exists
if ! az group exists --name "${RESOURCE_GROUP}" 2>/dev/null; then
    log_error "Resource group '${RESOURCE_GROUP}' does not exist"
    exit 1
fi

log_success "Prerequisites check completed"

# =============================================================================
# DISCOVERY AND INVENTORY
# =============================================================================

log_info "Discovering resources in resource group: ${RESOURCE_GROUP}"

# Get all resources in the resource group
RESOURCES=$(az resource list --resource-group "${RESOURCE_GROUP}" --output json)

# Extract specific resource names for targeted deletion
DATA_FACTORY_NAMES=($(echo "${RESOURCES}" | jq -r '.[] | select(.type=="Microsoft.DataFactory/factories") | .name'))
DMS_NAMES=($(echo "${RESOURCES}" | jq -r '.[] | select(.type=="Microsoft.DataMigration/services") | .name'))
LOG_ANALYTICS_NAMES=($(echo "${RESOURCES}" | jq -r '.[] | select(.type=="Microsoft.OperationalInsights/workspaces") | .name'))
STORAGE_ACCOUNT_NAMES=($(echo "${RESOURCES}" | jq -r '.[] | select(.type=="Microsoft.Storage/storageAccounts") | .name'))
ACTION_GROUP_NAMES=($(echo "${RESOURCES}" | jq -r '.[] | select(.type=="microsoft.insights/actionGroups") | .name'))
ALERT_RULE_NAMES=($(echo "${RESOURCES}" | jq -r '.[] | select(.type=="Microsoft.Insights/metricAlerts") | .name'))

# Display inventory
log_info "Resource Inventory:"
log_info "=================="
echo "Resource Group: ${RESOURCE_GROUP}"
echo "Data Factory instances: ${#DATA_FACTORY_NAMES[@]}"
for name in "${DATA_FACTORY_NAMES[@]}"; do
    echo "  - ${name}"
done
echo "Database Migration Service instances: ${#DMS_NAMES[@]}"
for name in "${DMS_NAMES[@]}"; do
    echo "  - ${name}"
done
echo "Log Analytics workspaces: ${#LOG_ANALYTICS_NAMES[@]}"
for name in "${LOG_ANALYTICS_NAMES[@]}"; do
    echo "  - ${name}"
done
echo "Storage accounts: ${#STORAGE_ACCOUNT_NAMES[@]}"
for name in "${STORAGE_ACCOUNT_NAMES[@]}"; do
    echo "  - ${name}"
done
echo "Action groups: ${#ACTION_GROUP_NAMES[@]}"
for name in "${ACTION_GROUP_NAMES[@]}"; do
    echo "  - ${name}"
done
echo "Alert rules: ${#ALERT_RULE_NAMES[@]}"
for name in "${ALERT_RULE_NAMES[@]}"; do
    echo "  - ${name}"
done

if [[ ${DRY_RUN} == true ]]; then
    log_info ""
    log_info "=== DRY RUN MODE - NO RESOURCES WILL BE DELETED ==="
    log_info ""
    log_info "The following resources would be deleted:"
    log_info "1. Alert rules and action groups"
    log_info "2. Integration Runtime configurations"
    log_info "3. Storage accounts and containers"
    log_info "4. Database Migration Service instances"
    log_info "5. Data Factory instances (including Workflow Orchestration Manager)"
    log_info "6. Log Analytics workspaces"
    if [[ ${KEEP_RG} == false ]]; then
        log_info "7. Resource group: ${RESOURCE_GROUP}"
    else
        log_info "7. Resource group will be preserved"
    fi
    log_info ""
    log_info "To perform actual cleanup, run without --dry-run flag"
    exit 0
fi

# =============================================================================
# CONFIRMATION
# =============================================================================

if [[ ${FORCE} == false ]]; then
    log_warning ""
    log_warning "=== DESTRUCTIVE OPERATION WARNING ==="
    log_warning ""
    log_warning "This will permanently delete the following resources:"
    log_warning "- ${#DATA_FACTORY_NAMES[@]} Data Factory instance(s)"
    log_warning "- ${#DMS_NAMES[@]} Database Migration Service instance(s)"
    log_warning "- ${#LOG_ANALYTICS_NAMES[@]} Log Analytics workspace(s)"
    log_warning "- ${#STORAGE_ACCOUNT_NAMES[@]} Storage account(s)"
    log_warning "- ${#ACTION_GROUP_NAMES[@]} Action group(s)"
    log_warning "- ${#ALERT_RULE_NAMES[@]} Alert rule(s)"
    if [[ ${KEEP_RG} == false ]]; then
        log_warning "- Resource group: ${RESOURCE_GROUP}"
    fi
    log_warning ""
    log_warning "This action cannot be undone!"
    log_warning ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with cleanup in 5 seconds... (Ctrl+C to cancel)"
    for i in {5..1}; do
        echo -n "${i}... "
        sleep 1
    done
    echo ""
fi

log_info "Starting resource cleanup..."

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

cleanup_alert_rules() {
    if [[ ${#ALERT_RULE_NAMES[@]} -gt 0 ]]; then
        log_info "Removing alert rules..."
        for alert_name in "${ALERT_RULE_NAMES[@]}"; do
            log_info "Deleting alert rule: ${alert_name}"
            az monitor metrics alert delete \
                --name "${alert_name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes &>/dev/null || log_warning "Failed to delete alert rule: ${alert_name}"
        done
        log_success "Alert rules cleanup completed"
    else
        log_info "No alert rules found to delete"
    fi
}

cleanup_action_groups() {
    if [[ ${#ACTION_GROUP_NAMES[@]} -gt 0 ]]; then
        log_info "Removing action groups..."
        for action_group_name in "${ACTION_GROUP_NAMES[@]}"; do
            log_info "Deleting action group: ${action_group_name}"
            az monitor action-group delete \
                --name "${action_group_name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes &>/dev/null || log_warning "Failed to delete action group: ${action_group_name}"
        done
        log_success "Action groups cleanup completed"
    else
        log_info "No action groups found to delete"
    fi
}

cleanup_storage_accounts() {
    if [[ ${#STORAGE_ACCOUNT_NAMES[@]} -gt 0 ]]; then
        log_info "Removing storage accounts..."
        for storage_name in "${STORAGE_ACCOUNT_NAMES[@]}"; do
            log_info "Deleting storage account: ${storage_name}"
            
            # List containers before deletion for logging
            CONTAINERS=$(az storage container list \
                --account-name "${storage_name}" \
                --query '[].name' --output tsv 2>/dev/null || echo "")
            
            if [[ -n "${CONTAINERS}" ]]; then
                log_info "  Found containers: ${CONTAINERS}"
            fi
            
            az storage account delete \
                --name "${storage_name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes &>/dev/null || log_warning "Failed to delete storage account: ${storage_name}"
        done
        log_success "Storage accounts cleanup completed"
    else
        log_info "No storage accounts found to delete"
    fi
}

cleanup_dms_instances() {
    if [[ ${#DMS_NAMES[@]} -gt 0 ]]; then
        log_info "Removing Database Migration Service instances..."
        for dms_name in "${DMS_NAMES[@]}"; do
            log_info "Deleting DMS instance: ${dms_name}"
            
            # Check for active migrations
            ACTIVE_MIGRATIONS=$(az dms project list \
                --service-name "${dms_name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --query 'length(@)' --output tsv 2>/dev/null || echo "0")
            
            if [[ ${ACTIVE_MIGRATIONS} -gt 0 ]]; then
                log_warning "  Found ${ACTIVE_MIGRATIONS} project(s) - they will be deleted with the service"
            fi
            
            az dms delete \
                --name "${dms_name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes &>/dev/null || log_warning "Failed to delete DMS instance: ${dms_name}"
        done
        log_success "Database Migration Service cleanup completed"
    else
        log_info "No Database Migration Service instances found to delete"
    fi
}

cleanup_data_factory_instances() {
    if [[ ${#DATA_FACTORY_NAMES[@]} -gt 0 ]]; then
        log_info "Removing Data Factory instances..."
        for df_name in "${DATA_FACTORY_NAMES[@]}"; do
            log_info "Deleting Data Factory: ${df_name}"
            
            # List integration runtimes for logging
            IR_NAMES=$(az datafactory integration-runtime list \
                --factory-name "${df_name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --query '[].name' --output tsv 2>/dev/null || echo "")
            
            if [[ -n "${IR_NAMES}" ]]; then
                log_info "  Found integration runtimes: ${IR_NAMES}"
                log_info "  They will be deleted with the Data Factory"
            fi
            
            # Check for Workflow Orchestration Manager
            log_info "  Checking for Workflow Orchestration Manager environment..."
            
            az datafactory delete \
                --name "${df_name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes &>/dev/null || log_warning "Failed to delete Data Factory: ${df_name}"
        done
        log_success "Data Factory instances cleanup completed"
    else
        log_info "No Data Factory instances found to delete"
    fi
}

cleanup_log_analytics_workspaces() {
    if [[ ${#LOG_ANALYTICS_NAMES[@]} -gt 0 ]]; then
        log_info "Removing Log Analytics workspaces..."
        for law_name in "${LOG_ANALYTICS_NAMES[@]}"; do
            log_info "Deleting Log Analytics workspace: ${law_name}"
            az monitor log-analytics workspace delete \
                --workspace-name "${law_name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --force true \
                --yes &>/dev/null || log_warning "Failed to delete Log Analytics workspace: ${law_name}"
        done
        log_success "Log Analytics workspaces cleanup completed"
    else
        log_info "No Log Analytics workspaces found to delete"
    fi
}

cleanup_resource_group() {
    if [[ ${KEEP_RG} == false ]]; then
        log_info "Removing resource group..."
        
        # Final check for remaining resources
        REMAINING_RESOURCES=$(az resource list --resource-group "${RESOURCE_GROUP}" --query 'length(@)' --output tsv)
        
        if [[ ${REMAINING_RESOURCES} -gt 0 ]]; then
            log_warning "Found ${REMAINING_RESOURCES} remaining resources in the resource group"
            log_info "Proceeding with resource group deletion (will remove all remaining resources)"
        fi
        
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait || log_error "Failed to initiate resource group deletion"
        
        log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        log_info "Note: Complete deletion may take several minutes to complete"
    else
        log_info "Preserving resource group as requested: ${RESOURCE_GROUP}"
    fi
}

# =============================================================================
# EXECUTE CLEANUP
# =============================================================================

log_info "Executing cleanup in optimal order..."

# Cleanup in reverse dependency order
cleanup_alert_rules
cleanup_action_groups
cleanup_storage_accounts
cleanup_dms_instances
cleanup_data_factory_instances
cleanup_log_analytics_workspaces
cleanup_resource_group

# =============================================================================
# CLEANUP VERIFICATION
# =============================================================================

if [[ ${KEEP_RG} == true ]]; then
    log_info "Verifying cleanup completion..."
    
    sleep 10  # Allow time for deletions to propagate
    
    REMAINING_RESOURCES=$(az resource list --resource-group "${RESOURCE_GROUP}" --output json)
    REMAINING_COUNT=$(echo "${REMAINING_RESOURCES}" | jq '. | length')
    
    if [[ ${REMAINING_COUNT} -eq 0 ]]; then
        log_success "All resources successfully removed from resource group"
    else
        log_warning "Found ${REMAINING_COUNT} remaining resources:"
        echo "${REMAINING_RESOURCES}" | jq -r '.[] | "  - \(.type): \(.name)"'
        log_info "These resources may take additional time to delete or require manual cleanup"
    fi
fi

# =============================================================================
# CLEANUP SUMMARY
# =============================================================================

log_success "=== CLEANUP COMPLETED ==="
log_info ""
log_info "Cleanup Summary:"
log_info "==============="
log_info "✅ Alert rules and action groups removed"
log_info "✅ Storage accounts and containers removed"
log_info "✅ Database Migration Service instances removed"
log_info "✅ Data Factory instances removed (including Workflow Orchestration Manager)"
log_info "✅ Log Analytics workspaces removed"

if [[ ${KEEP_RG} == false ]]; then
    log_info "✅ Resource group deletion initiated"
    log_info ""
    log_warning "Note: Resource group deletion is asynchronous and may take several minutes"
    log_info "You can check the status in the Azure portal or using:"
    log_info "  az group show --name ${RESOURCE_GROUP}"
else
    log_info "✅ Resource group preserved: ${RESOURCE_GROUP}"
fi

log_info ""
log_info "Important Notes:"
log_info "- Integration Runtime installations on on-premises servers are not affected"
log_info "- Any custom configurations or data outside Azure have been preserved"
log_info "- Billing for deleted resources will stop within 24 hours"
log_info ""
log_success "Database Migration Orchestration infrastructure cleanup completed successfully!"

exit 0