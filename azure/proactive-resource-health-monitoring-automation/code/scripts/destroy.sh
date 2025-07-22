#!/bin/bash

# destroy.sh - Azure Proactive Application Health Monitoring Cleanup Script
# This script safely removes all resources created by the health monitoring deployment
# Recipe: Proactive Resource Health Monitoring with Service Bus

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
START_TIME=$(date)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message function
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message function
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message function
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Cannot proceed with cleanup."
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    success "Prerequisites check completed"
}

# Function to discover resource groups
discover_resource_groups() {
    info "Discovering health monitoring resource groups..."
    
    # Find resource groups that match our naming pattern
    local resource_groups=$(az group list \
        --query "[?contains(name, 'rg-health-monitoring')].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "${resource_groups}" ]]; then
        info "No health monitoring resource groups found matching pattern 'rg-health-monitoring'"
        return 0
    fi
    
    echo "Found the following health monitoring resource groups:"
    echo "${resource_groups}" | while IFS= read -r rg; do
        echo "  - ${rg}"
    done
    echo ""
    
    # Export the list for use in other functions
    export DISCOVERED_RESOURCE_GROUPS="${resource_groups}"
}

# Function to prompt for confirmation
confirm_deletion() {
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        info "Force delete mode enabled, skipping confirmation"
        return 0
    fi
    
    echo -e "${YELLOW}⚠️  WARNING: This will permanently delete the following resources:${NC}"
    echo ""
    
    if [[ -n "${DISCOVERED_RESOURCE_GROUPS:-}" ]]; then
        echo "Resource Groups:"
        echo "${DISCOVERED_RESOURCE_GROUPS}" | while IFS= read -r rg; do
            if [[ -n "${rg}" ]]; then
                echo "  - ${rg}"
                
                # List key resources in each group
                info "Resources in ${rg}:"
                az resource list --resource-group "${rg}" \
                    --query "[].{Name:name,Type:type}" \
                    --output table 2>/dev/null || warning "Could not list resources in ${rg}"
                echo ""
            fi
        done
    fi
    
    echo -e "${RED}This action CANNOT be undone!${NC}"
    echo ""
    
    read -p "Are you sure you want to delete all these resources? (yes/no): " confirmation
    
    case "${confirmation}" in
        yes|YES|y|Y)
            info "Confirmed. Proceeding with deletion..."
            ;;
        *)
            info "Deletion cancelled by user."
            exit 0
            ;;
    esac
}

# Function to delete Logic Apps workflows
delete_logic_apps() {
    info "Deleting Logic Apps workflows..."
    
    if [[ -z "${DISCOVERED_RESOURCE_GROUPS:-}" ]]; then
        warning "No resource groups discovered for Logic Apps cleanup"
        return 0
    fi
    
    echo "${DISCOVERED_RESOURCE_GROUPS}" | while IFS= read -r rg; do
        if [[ -n "${rg}" ]]; then
            info "Checking Logic Apps in resource group: ${rg}"
            
            # Get all Logic Apps in the resource group
            local logic_apps=$(az logic workflow list \
                --resource-group "${rg}" \
                --query "[].name" \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -n "${logic_apps}" ]]; then
                echo "${logic_apps}" | while IFS= read -r la; do
                    if [[ -n "${la}" ]]; then
                        info "Deleting Logic App: ${la}"
                        az logic workflow delete \
                            --name "${la}" \
                            --resource-group "${rg}" \
                            --yes \
                            --output none 2>/dev/null || warning "Failed to delete Logic App: ${la}"
                    fi
                done
                success "Logic Apps deleted from resource group: ${rg}"
            else
                info "No Logic Apps found in resource group: ${rg}"
            fi
        fi
    done
}

# Function to delete Service Bus resources
delete_service_bus() {
    info "Deleting Service Bus resources..."
    
    if [[ -z "${DISCOVERED_RESOURCE_GROUPS:-}" ]]; then
        warning "No resource groups discovered for Service Bus cleanup"
        return 0
    fi
    
    echo "${DISCOVERED_RESOURCE_GROUPS}" | while IFS= read -r rg; do
        if [[ -n "${rg}" ]]; then
            info "Checking Service Bus namespaces in resource group: ${rg}"
            
            # Get all Service Bus namespaces in the resource group
            local namespaces=$(az servicebus namespace list \
                --resource-group "${rg}" \
                --query "[].name" \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -n "${namespaces}" ]]; then
                echo "${namespaces}" | while IFS= read -r ns; do
                    if [[ -n "${ns}" ]]; then
                        info "Deleting Service Bus namespace: ${ns}"
                        az servicebus namespace delete \
                            --name "${ns}" \
                            --resource-group "${rg}" \
                            --output none 2>/dev/null || warning "Failed to delete Service Bus namespace: ${ns}"
                    fi
                done
                success "Service Bus namespaces deleted from resource group: ${rg}"
            else
                info "No Service Bus namespaces found in resource group: ${rg}"
            fi
        fi
    done
}

# Function to delete virtual machines
delete_virtual_machines() {
    info "Deleting virtual machines..."
    
    if [[ -z "${DISCOVERED_RESOURCE_GROUPS:-}" ]]; then
        warning "No resource groups discovered for VM cleanup"
        return 0
    fi
    
    echo "${DISCOVERED_RESOURCE_GROUPS}" | while IFS= read -r rg; do
        if [[ -n "${rg}" ]]; then
            info "Checking VMs in resource group: ${rg}"
            
            # Get all VMs in the resource group
            local vms=$(az vm list \
                --resource-group "${rg}" \
                --query "[].name" \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -n "${vms}" ]]; then
                echo "${vms}" | while IFS= read -r vm; do
                    if [[ -n "${vm}" ]]; then
                        info "Deleting VM: ${vm}"
                        az vm delete \
                            --name "${vm}" \
                            --resource-group "${rg}" \
                            --yes \
                            --output none 2>/dev/null || warning "Failed to delete VM: ${vm}"
                        
                        # Delete associated resources (NICs, disks, public IPs)
                        info "Cleaning up VM-associated resources for: ${vm}"
                        
                        # Delete network interfaces
                        local nics=$(az network nic list \
                            --resource-group "${rg}" \
                            --query "[?contains(name, '${vm}')].name" \
                            --output tsv 2>/dev/null || echo "")
                        
                        if [[ -n "${nics}" ]]; then
                            echo "${nics}" | while IFS= read -r nic; do
                                if [[ -n "${nic}" ]]; then
                                    az network nic delete \
                                        --name "${nic}" \
                                        --resource-group "${rg}" \
                                        --output none 2>/dev/null || warning "Failed to delete NIC: ${nic}"
                                fi
                            done
                        fi
                        
                        # Delete public IPs
                        local public_ips=$(az network public-ip list \
                            --resource-group "${rg}" \
                            --query "[?contains(name, '${vm}')].name" \
                            --output tsv 2>/dev/null || echo "")
                        
                        if [[ -n "${public_ips}" ]]; then
                            echo "${public_ips}" | while IFS= read -r pip; do
                                if [[ -n "${pip}" ]]; then
                                    az network public-ip delete \
                                        --name "${pip}" \
                                        --resource-group "${rg}" \
                                        --output none 2>/dev/null || warning "Failed to delete public IP: ${pip}"
                                fi
                            done
                        fi
                        
                        # Delete disks
                        local disks=$(az disk list \
                            --resource-group "${rg}" \
                            --query "[?contains(name, '${vm}')].name" \
                            --output tsv 2>/dev/null || echo "")
                        
                        if [[ -n "${disks}" ]]; then
                            echo "${disks}" | while IFS= read -r disk; do
                                if [[ -n "${disk}" ]]; then
                                    az disk delete \
                                        --name "${disk}" \
                                        --resource-group "${rg}" \
                                        --yes \
                                        --output none 2>/dev/null || warning "Failed to delete disk: ${disk}"
                                fi
                            done
                        fi
                    fi
                done
                success "VMs and associated resources deleted from resource group: ${rg}"
            else
                info "No VMs found in resource group: ${rg}"
            fi
        fi
    done
}

# Function to delete Log Analytics workspaces
delete_log_analytics() {
    info "Deleting Log Analytics workspaces..."
    
    if [[ -z "${DISCOVERED_RESOURCE_GROUPS:-}" ]]; then
        warning "No resource groups discovered for Log Analytics cleanup"
        return 0
    fi
    
    echo "${DISCOVERED_RESOURCE_GROUPS}" | while IFS= read -r rg; do
        if [[ -n "${rg}" ]]; then
            info "Checking Log Analytics workspaces in resource group: ${rg}"
            
            # Get all Log Analytics workspaces in the resource group
            local workspaces=$(az monitor log-analytics workspace list \
                --resource-group "${rg}" \
                --query "[].name" \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -n "${workspaces}" ]]; then
                echo "${workspaces}" | while IFS= read -r ws; do
                    if [[ -n "${ws}" ]]; then
                        info "Deleting Log Analytics workspace: ${ws}"
                        az monitor log-analytics workspace delete \
                            --workspace-name "${ws}" \
                            --resource-group "${rg}" \
                            --yes \
                            --output none 2>/dev/null || warning "Failed to delete Log Analytics workspace: ${ws}"
                    fi
                done
                success "Log Analytics workspaces deleted from resource group: ${rg}"
            else
                info "No Log Analytics workspaces found in resource group: ${rg}"
            fi
        fi
    done
}

# Function to delete Action Groups
delete_action_groups() {
    info "Deleting Action Groups..."
    
    if [[ -z "${DISCOVERED_RESOURCE_GROUPS:-}" ]]; then
        warning "No resource groups discovered for Action Groups cleanup"
        return 0
    fi
    
    echo "${DISCOVERED_RESOURCE_GROUPS}" | while IFS= read -r rg; do
        if [[ -n "${rg}" ]]; then
            info "Checking Action Groups in resource group: ${rg}"
            
            # Get all Action Groups in the resource group
            local action_groups=$(az monitor action-group list \
                --resource-group "${rg}" \
                --query "[].name" \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -n "${action_groups}" ]]; then
                echo "${action_groups}" | while IFS= read -r ag; do
                    if [[ -n "${ag}" ]]; then
                        info "Deleting Action Group: ${ag}"
                        az monitor action-group delete \
                            --name "${ag}" \
                            --resource-group "${rg}" \
                            --output none 2>/dev/null || warning "Failed to delete Action Group: ${ag}"
                    fi
                done
                success "Action Groups deleted from resource group: ${rg}"
            else
                info "No Action Groups found in resource group: ${rg}"
            fi
        fi
    done
}

# Function to delete activity log alerts
delete_activity_log_alerts() {
    info "Deleting Activity Log Alerts..."
    
    if [[ -z "${DISCOVERED_RESOURCE_GROUPS:-}" ]]; then
        warning "No resource groups discovered for Activity Log Alerts cleanup"
        return 0
    fi
    
    echo "${DISCOVERED_RESOURCE_GROUPS}" | while IFS= read -r rg; do
        if [[ -n "${rg}" ]]; then
            info "Checking Activity Log Alerts in resource group: ${rg}"
            
            # Get all Activity Log Alerts in the resource group
            local alerts=$(az monitor activity-log alert list \
                --resource-group "${rg}" \
                --query "[].name" \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -n "${alerts}" ]]; then
                echo "${alerts}" | while IFS= read -r alert; do
                    if [[ -n "${alert}" ]]; then
                        info "Deleting Activity Log Alert: ${alert}"
                        az monitor activity-log alert delete \
                            --name "${alert}" \
                            --resource-group "${rg}" \
                            --output none 2>/dev/null || warning "Failed to delete Activity Log Alert: ${alert}"
                    fi
                done
                success "Activity Log Alerts deleted from resource group: ${rg}"
            else
                info "No Activity Log Alerts found in resource group: ${rg}"
            fi
        fi
    done
}

# Function to delete resource groups
delete_resource_groups() {
    info "Deleting resource groups..."
    
    if [[ -z "${DISCOVERED_RESOURCE_GROUPS:-}" ]]; then
        warning "No resource groups to delete"
        return 0
    fi
    
    echo "${DISCOVERED_RESOURCE_GROUPS}" | while IFS= read -r rg; do
        if [[ -n "${rg}" ]]; then
            info "Deleting resource group: ${rg}"
            
            # Check if resource group exists before attempting deletion
            if az group show --name "${rg}" &> /dev/null; then
                az group delete \
                    --name "${rg}" \
                    --yes \
                    --no-wait \
                    --output none 2>/dev/null || warning "Failed to initiate deletion of resource group: ${rg}"
                
                info "Deletion initiated for resource group: ${rg} (running in background)"
            else
                warning "Resource group does not exist: ${rg}"
            fi
        fi
    done
    
    success "Resource group deletions initiated"
}

# Function to wait for deletions to complete
wait_for_deletions() {
    if [[ "${WAIT_FOR_COMPLETION:-true}" == "false" ]]; then
        info "Skipping wait for completion"
        return 0
    fi
    
    info "Waiting for resource group deletions to complete..."
    
    if [[ -z "${DISCOVERED_RESOURCE_GROUPS:-}" ]]; then
        return 0
    fi
    
    local remaining_groups=""
    echo "${DISCOVERED_RESOURCE_GROUPS}" | while IFS= read -r rg; do
        if [[ -n "${rg}" ]]; then
            remaining_groups="${remaining_groups} ${rg}"
        fi
    done
    
    local max_wait_time=1800  # 30 minutes
    local wait_interval=30    # 30 seconds
    local elapsed_time=0
    
    while [[ ${elapsed_time} -lt ${max_wait_time} ]] && [[ -n "${remaining_groups}" ]]; do
        local still_existing=""
        
        for rg in ${remaining_groups}; do
            if az group show --name "${rg}" &> /dev/null; then
                still_existing="${still_existing} ${rg}"
            fi
        done
        
        remaining_groups="${still_existing}"
        
        if [[ -z "${remaining_groups}" ]]; then
            success "All resource groups have been deleted"
            break
        fi
        
        info "Still waiting for deletion of: ${remaining_groups}"
        sleep ${wait_interval}
        elapsed_time=$((elapsed_time + wait_interval))
    done
    
    if [[ -n "${remaining_groups}" ]]; then
        warning "Some resource groups are still being deleted: ${remaining_groups}"
        warning "Deletion may take additional time to complete"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove generated files
    local files_to_remove=(
        "${SCRIPT_DIR}/health_monitoring_queries.kql"
        "${SCRIPT_DIR}/../*.tmp"
        "/tmp/main-workflow.json"
        "/tmp/restart-workflow.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}" && info "Removed: ${file}"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to display cleanup summary
display_summary() {
    local end_time=$(date)
    local duration=$(($(date +%s) - $(date -d "${START_TIME}" +%s)))
    
    info "Cleanup Summary"
    echo "=================================="
    echo "Start Time: ${START_TIME}"
    echo "End Time: ${end_time}"
    echo "Duration: ${duration} seconds"
    echo ""
    
    if [[ -n "${DISCOVERED_RESOURCE_GROUPS:-}" ]]; then
        echo "Resource Groups Processed:"
        echo "${DISCOVERED_RESOURCE_GROUPS}" | while IFS= read -r rg; do
            if [[ -n "${rg}" ]]; then
                local status="Unknown"
                if ! az group show --name "${rg}" &> /dev/null; then
                    status="Deleted"
                else
                    status="Still Deleting"
                fi
                echo "  - ${rg}: ${status}"
            fi
        done
    else
        echo "No resource groups were found for cleanup"
    fi
    
    echo "=================================="
    echo ""
    echo "Cleanup completed!"
    
    if [[ "${WAIT_FOR_COMPLETION:-true}" == "false" ]]; then
        warning "Note: Resource group deletions may still be in progress."
        warning "Check the Azure portal to monitor deletion status."
    fi
}

# Function to show help
show_help() {
    echo "Azure Health Monitoring Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force                 Skip confirmation prompts"
    echo "  --no-wait              Don't wait for deletions to complete"
    echo "  --help                 Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  FORCE_DELETE=true      Same as --force"
    echo "  WAIT_FOR_COMPLETION=false  Same as --no-wait"
    echo ""
    echo "Examples:"
    echo "  $0                     Interactive cleanup with confirmation"
    echo "  $0 --force             Automatic cleanup without confirmation"
    echo "  $0 --no-wait           Cleanup without waiting for completion"
    echo ""
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE_DELETE=true
                shift
                ;;
            --no-wait)
                export WAIT_FOR_COMPLETION=false
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main cleanup function
main() {
    echo -e "${BLUE}"
    echo "=================================================="
    echo "  Azure Health Monitoring Cleanup Script"
    echo "=================================================="
    echo -e "${NC}"
    
    log "Starting cleanup process"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Execute cleanup steps
    check_prerequisites
    discover_resource_groups
    confirm_deletion
    delete_activity_log_alerts
    delete_logic_apps
    delete_virtual_machines
    delete_service_bus
    delete_log_analytics
    delete_action_groups
    delete_resource_groups
    wait_for_deletions
    cleanup_local_files
    display_summary
    
    success "🎉 Cleanup completed successfully!"
    info "Check the cleanup log for details: ${LOG_FILE}"
}

# Trap signals for cleanup
trap 'echo -e "${RED}Cleanup interrupted${NC}"; exit 1' INT TERM

# Execute main function
main "$@"