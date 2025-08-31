#!/bin/bash

# Azure AI Cost Monitoring with Foundry and Application Insights - Cleanup Script
# This script safely removes all resources created by the deployment script
# Version: 1.0
# Last Updated: 2025-01-16

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Global variables
FORCE_DELETE=false
PRESERVE_DATA=false
STATE_FILE="./.deployment_state"

# Load deployment state
load_deployment_state() {
    if [[ -f "${STATE_FILE}" ]]; then
        log "Loading deployment state from ${STATE_FILE}"
        # shellcheck source=/dev/null
        source "${STATE_FILE}"
        
        info "Loaded state for resource group: ${RESOURCE_GROUP:-'not found'}"
        return 0
    else
        warn "No deployment state file found. Manual resource specification may be required."
        return 1
    fi
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check subscription access
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    info "Using subscription: ${subscription_id}"
    
    log "Prerequisites check passed ✅"
}

# Resource discovery function
discover_resources() {
    log "Discovering resources to delete..."
    
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        error "Resource group not specified. Cannot proceed with discovery."
        return 1
    fi
    
    # Check if resource group exists
    if ! az group exists --name "${RESOURCE_GROUP}" --output tsv 2>/dev/null; then
        warn "Resource group '${RESOURCE_GROUP}' does not exist. Nothing to clean up."
        return 1
    fi
    
    # List all resources in the resource group
    local resource_count
    resource_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query 'length(@)' --output tsv 2>/dev/null || echo "0")
    
    if [[ "${resource_count}" -eq 0 ]]; then
        warn "No resources found in resource group '${RESOURCE_GROUP}'"
        return 1
    fi
    
    info "Found ${resource_count} resources in resource group '${RESOURCE_GROUP}'"
    
    # Display resources that will be deleted
    echo ""
    info "Resources that will be deleted:"
    az resource list --resource-group "${RESOURCE_GROUP}" \
        --query '[].{Name:name, Type:type, Location:location}' \
        --output table 2>/dev/null || warn "Could not list resources in detail"
    echo ""
    
    return 0
}

# Confirmation prompt
confirm_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        warn "Force delete mode enabled. Skipping confirmation."
        return 0
    fi
    
    echo -e "${RED}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                              ⚠️  WARNING ⚠️                                  ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ This action will PERMANENTLY DELETE all resources in the resource group     ║
║ and cannot be undone. This includes:                                        ║
║                                                                              ║
║ • Azure AI Foundry Hub and Projects                                         ║
║ • Application Insights and Log Analytics data                               ║
║ • Storage accounts and all stored data                                      ║
║ • Budgets and alert configurations                                          ║
║ • Azure Monitor workbooks and dashboards                                    ║
║                                                                              ║
║ All monitoring data and configurations will be lost!                        ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    read -r -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        info "Cleanup cancelled by user."
        exit 0
    fi
    
    # Double confirmation for production-like names
    if [[ "${RESOURCE_GROUP}" =~ (prod|production|prd) ]]; then
        echo -e "${RED}Production-like resource group detected!${NC}"
        read -r -p "Type the resource group name '${RESOURCE_GROUP}' to confirm: " rg_confirmation
        
        if [[ "${rg_confirmation}" != "${RESOURCE_GROUP}" ]]; then
            error "Resource group name mismatch. Cleanup cancelled."
            exit 1
        fi
    fi
    
    log "Deletion confirmed by user ✅"
}

# Data backup function (optional)
backup_critical_data() {
    if [[ "${PRESERVE_DATA}" == "false" ]]; then
        info "Data preservation disabled. Skipping backup."
        return 0
    fi
    
    log "Backing up critical data before deletion..."
    local backup_dir="./backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${backup_dir}"
    
    # Backup Application Insights configuration
    if [[ -n "${APP_INSIGHTS_NAME:-}" ]]; then
        info "Backing up Application Insights configuration..."
        az monitor app-insights component show \
            --app "${APP_INSIGHTS_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output json > "${backup_dir}/app-insights-config.json" 2>/dev/null || warn "Could not backup App Insights config"
    fi
    
    # Backup workbook configurations
    info "Backing up Azure Monitor workbooks..."
    az monitor workbook list \
        --resource-group "${RESOURCE_GROUP}" \
        --output json > "${backup_dir}/workbooks-config.json" 2>/dev/null || warn "Could not backup workbooks"
    
    # Backup Action Groups
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        info "Backing up Action Group configuration..."
        az monitor action-group show \
            --resource-group "${RESOURCE_GROUP}" \
            --name "ai-cost-alerts-${RANDOM_SUFFIX}" \
            --output json > "${backup_dir}/action-group-config.json" 2>/dev/null || warn "Could not backup Action Group"
    fi
    
    # Save deployment state
    if [[ -f "${STATE_FILE}" ]]; then
        cp "${STATE_FILE}" "${backup_dir}/original-deployment-state"
    fi
    
    info "Backup completed in directory: ${backup_dir}"
}

# Individual resource cleanup functions
cleanup_budgets() {
    log "Cleaning up budgets and cost management resources..."
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local budget_name="ai-foundry-budget-${RANDOM_SUFFIX}"
        
        if az consumption budget show --budget-name "${budget_name}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
            info "Deleting budget: ${budget_name}"
            az consumption budget delete \
                --budget-name "${budget_name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output none 2>/dev/null || warn "Could not delete budget ${budget_name}"
        else
            info "Budget ${budget_name} not found or already deleted"
        fi
    else
        warn "Random suffix not available. Attempting to find and delete budgets..."
        # Try to find budgets in the resource group
        local budgets
        budgets=$(az consumption budget list --resource-group "${RESOURCE_GROUP}" --query '[].name' --output tsv 2>/dev/null || echo "")
        
        if [[ -n "${budgets}" ]]; then
            echo "${budgets}" | while IFS= read -r budget; do
                info "Deleting budget: ${budget}"
                az consumption budget delete \
                    --budget-name "${budget}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --output none 2>/dev/null || warn "Could not delete budget ${budget}"
            done
        fi
    fi
}

cleanup_alerts_and_action_groups() {
    log "Cleaning up alerts and action groups..."
    
    # Delete metric alerts
    local alert_rules
    alert_rules=$(az monitor metrics alert list --resource-group "${RESOURCE_GROUP}" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${alert_rules}" ]]; then
        echo "${alert_rules}" | while IFS= read -r alert; do
            info "Deleting alert rule: ${alert}"
            az monitor metrics alert delete \
                --name "${alert}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output none 2>/dev/null || warn "Could not delete alert rule ${alert}"
        done
    fi
    
    # Delete action groups
    local action_groups
    action_groups=$(az monitor action-group list --resource-group "${RESOURCE_GROUP}" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${action_groups}" ]]; then
        echo "${action_groups}" | while IFS= read -r ag; do
            info "Deleting action group: ${ag}"
            az monitor action-group delete \
                --resource-group "${RESOURCE_GROUP}" \
                --name "${ag}" \
                --output none 2>/dev/null || warn "Could not delete action group ${ag}"
        done
    fi
}

cleanup_monitoring_resources() {
    log "Cleaning up monitoring resources..."
    
    # Delete workbooks
    local workbooks
    workbooks=$(az monitor workbook list --resource-group "${RESOURCE_GROUP}" --query '[].id' --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${workbooks}" ]]; then
        echo "${workbooks}" | while IFS= read -r workbook_id; do
            local workbook_name
            workbook_name=$(basename "${workbook_id}")
            info "Deleting workbook: ${workbook_name}"
            az monitor workbook delete \
                --resource-group "${RESOURCE_GROUP}" \
                --name "${workbook_name}" \
                --output none 2>/dev/null || warn "Could not delete workbook ${workbook_name}"
        done
    fi
}

cleanup_ai_foundry_resources() {
    log "Cleaning up AI Foundry resources..."
    
    # Delete AI Foundry Projects first (dependencies)
    if [[ -n "${AI_PROJECT_NAME:-}" ]]; then
        if az ml workspace show --resource-group "${RESOURCE_GROUP}" --name "${AI_PROJECT_NAME}" &>/dev/null; then
            info "Deleting AI Foundry Project: ${AI_PROJECT_NAME}"
            az ml workspace delete \
                --resource-group "${RESOURCE_GROUP}" \
                --name "${AI_PROJECT_NAME}" \
                --yes \
                --output none 2>/dev/null || warn "Could not delete AI Project ${AI_PROJECT_NAME}"
            
            # Wait for project deletion to complete
            info "Waiting for project deletion to complete..."
            sleep 30
        fi
    fi
    
    # Delete AI Foundry Hub
    if [[ -n "${AI_HUB_NAME:-}" ]]; then
        if az ml workspace show --resource-group "${RESOURCE_GROUP}" --name "${AI_HUB_NAME}" &>/dev/null; then
            info "Deleting AI Foundry Hub: ${AI_HUB_NAME}"
            az ml workspace delete \
                --resource-group "${RESOURCE_GROUP}" \
                --name "${AI_HUB_NAME}" \
                --yes \
                --output none 2>/dev/null || warn "Could not delete AI Hub ${AI_HUB_NAME}"
            
            # Wait for hub deletion to complete
            info "Waiting for hub deletion to complete..."
            sleep 30
        fi
    fi
}

# Main resource group deletion
delete_resource_group() {
    log "Initiating resource group deletion..."
    
    if ! az group exists --name "${RESOURCE_GROUP}" --output tsv 2>/dev/null; then
        warn "Resource group '${RESOURCE_GROUP}' does not exist."
        return 0
    fi
    
    info "Deleting resource group: ${RESOURCE_GROUP}"
    info "This operation may take several minutes..."
    
    # Delete resource group with no-wait initially, then wait with timeout
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        --output none
    
    # Wait for deletion with timeout
    local timeout=1800  # 30 minutes
    local elapsed=0
    local interval=30
    
    info "Waiting for resource group deletion to complete (timeout: ${timeout}s)..."
    
    while [[ ${elapsed} -lt ${timeout} ]]; do
        if ! az group exists --name "${RESOURCE_GROUP}" --output tsv 2>/dev/null; then
            log "Resource group successfully deleted ✅"
            return 0
        fi
        
        info "Still deleting... (${elapsed}s elapsed)"
        sleep ${interval}
        elapsed=$((elapsed + interval))
    done
    
    warn "Resource group deletion is taking longer than expected."
    warn "Check Azure portal for deletion status: ${RESOURCE_GROUP}"
    return 1
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove deployment state file
    if [[ -f "${STATE_FILE}" ]]; then
        rm -f "${STATE_FILE}"
        info "Removed deployment state file"
    fi
    
    # Remove any temporary files created during deployment
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        rm -f "/tmp/cost_tracker_${RANDOM_SUFFIX}.py" 2>/dev/null || true
        rm -f "/tmp/ai-monitoring-workbook-${RANDOM_SUFFIX}.json" 2>/dev/null || true
        info "Removed temporary files"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    if az group exists --name "${RESOURCE_GROUP}" --output tsv 2>/dev/null; then
        warn "Resource group still exists. Cleanup may not be complete."
        return 1
    fi
    
    info "Cleanup verification passed ✅"
    return 0
}

# Generate cleanup summary
generate_cleanup_summary() {
    log "Generating cleanup summary..."
    
    cat << EOF

╔══════════════════════════════════════════════════════════════════════════════╗
║                            CLEANUP SUMMARY                                  ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ Resource Group:         ${RESOURCE_GROUP:-'N/A'}
║ Status:                $(if az group exists --name "${RESOURCE_GROUP:-}" --output tsv 2>/dev/null; then echo "❌ Still exists"; else echo "✅ Deleted successfully"; fi)
║ Cleanup Date:          $(date)
╠══════════════════════════════════════════════════════════════════════════════╣
║                             RESOURCES REMOVED                               ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ • AI Foundry Hub and Projects                                               ║
║ • Application Insights and Log Analytics                                    ║
║ • Storage accounts and data                                                 ║
║ • Cost budgets and alerts                                                   ║
║ • Action groups and monitoring resources                                    ║
║ • Azure Monitor workbooks                                                   ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                             IMPORTANT NOTES                                 ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ • All AI monitoring data has been permanently deleted                       ║
║ • Cost tracking and budgets have been removed                               ║
║ • Check Azure portal to confirm complete deletion                           ║
║ • Some resources may take additional time to fully remove                   ║
╚══════════════════════════════════════════════════════════════════════════════╝

EOF
}

# Usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --resource-group NAME  Specify resource group to delete (overrides state file)
    --force               Skip confirmation prompts
    --preserve-data       Backup critical data before deletion
    --help                Show this help message

Examples:
    $0                              # Delete using deployment state file
    $0 --force                      # Delete without confirmation
    $0 --resource-group my-rg       # Delete specific resource group
    $0 --preserve-data              # Backup data before deletion

EOF
}

# Main execution function
main() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                     Azure AI Cost Monitoring Cleanup                       ║
║                          Resource Deletion Script                           ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                warn "Using manual resource group specification: ${RESOURCE_GROUP}"
                shift 2
                ;;
            --force)
                FORCE_DELETE=true
                warn "Force delete mode enabled"
                shift
                ;;
            --preserve-data)
                PRESERVE_DATA=true
                info "Data preservation enabled"
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Load deployment state if resource group not manually specified
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        if ! load_deployment_state; then
            error "No resource group specified and no deployment state found."
            error "Use --resource-group option to specify the resource group to delete."
            show_usage
            exit 1
        fi
    fi
    
    # Execute cleanup steps
    check_prerequisites
    
    if discover_resources; then
        confirm_deletion
        backup_critical_data
        
        # Perform cleanup in proper order
        cleanup_budgets
        cleanup_alerts_and_action_groups
        cleanup_monitoring_resources
        cleanup_ai_foundry_resources
        
        # Final resource group deletion
        delete_resource_group
        
        # Post-cleanup tasks
        cleanup_temp_files
        verify_cleanup
        generate_cleanup_summary
        
        log "Cleanup script completed successfully! ✅"
    else
        info "No resources found to clean up."
    fi
}

# Execute main function
main "$@"