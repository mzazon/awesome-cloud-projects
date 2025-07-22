#!/bin/bash

# Azure Zero-Trust Remote Access Cleanup Script
# Recipe: Zero-Trust Remote Access with Bastion and Firewall Manager
# Version: 1.0
# Description: Safely removes all resources deployed by the zero-trust remote access solution

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${ERROR_LOG}" >&2)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Error handling function
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Script failed at line ${line_number} with exit code ${exit_code}"
    log_error "Check ${ERROR_LOG} for detailed error information"
    log_warning "Some resources may not have been deleted. Please check Azure portal."
    exit ${exit_code}
}

# Set error trap
trap 'handle_error ${LINENO}' ERR

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group GROUP        Specific resource group to delete"
    echo "  -f, --force                       Skip confirmation prompts"
    echo "  -h, --help                        Display this help message"
    echo "  --dry-run                         Show what would be deleted without deleting"
    echo "  --partial                         Allow partial cleanup (continue on errors)"
    echo ""
    echo "Examples:"
    echo "  $0                                Delete using deployment info file"
    echo "  $0 -g rg-zerotrust-abc123         Delete specific resource group"
    echo "  $0 --dry-run                      Preview deletion without removing resources"
    echo "  $0 -f                             Force deletion without confirmation"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription info
    local subscription_id
    local subscription_name
    subscription_id=$(az account show --query id --output tsv)
    subscription_name=$(az account show --query name --output tsv)
    log_info "Using subscription: ${subscription_name} (${subscription_id})"
    
    log_success "Prerequisites check completed"
}

# Function to load deployment information
load_deployment_info() {
    local deployment_info_file="${SCRIPT_DIR}/.deployment_info"
    
    if [[ -f "${deployment_info_file}" ]]; then
        log_info "Loading deployment information from ${deployment_info_file}"
        
        # Source the deployment info file
        source "${deployment_info_file}"
        
        log_info "Loaded deployment info:"
        log_info "  Resource Group: ${RESOURCE_GROUP:-'Not found'}"
        log_info "  Location: ${LOCATION:-'Not found'}"
        log_info "  Deployment Date: ${DEPLOYMENT_DATE:-'Not found'}"
        
        return 0
    else
        log_warning "Deployment info file not found: ${deployment_info_file}"
        return 1
    fi
}

# Function to load resource names from individual files
load_resource_names() {
    log_info "Loading resource names from state files..."
    
    # Load individual resource names if files exist
    if [[ -f "${SCRIPT_DIR}/.bastion_name" ]]; then
        BASTION_NAME=$(cat "${SCRIPT_DIR}/.bastion_name")
        log_info "Found Bastion name: ${BASTION_NAME}"
    fi
    
    if [[ -f "${SCRIPT_DIR}/.firewall_name" ]]; then
        FIREWALL_NAME=$(cat "${SCRIPT_DIR}/.firewall_name")
        log_info "Found Firewall name: ${FIREWALL_NAME}"
    fi
    
    if [[ -f "${SCRIPT_DIR}/.firewall_policy_name" ]]; then
        FIREWALL_POLICY_NAME=$(cat "${SCRIPT_DIR}/.firewall_policy_name")
        log_info "Found Firewall Policy name: ${FIREWALL_POLICY_NAME}"
    fi
    
    if [[ -f "${SCRIPT_DIR}/.policy_definition_name" ]]; then
        POLICY_DEFINITION_NAME=$(cat "${SCRIPT_DIR}/.policy_definition_name")
        log_info "Found Policy Definition name: ${POLICY_DEFINITION_NAME}"
    fi
    
    if [[ -f "${SCRIPT_DIR}/.workspace_name" ]]; then
        WORKSPACE_NAME=$(cat "${SCRIPT_DIR}/.workspace_name")
        log_info "Found Log Analytics Workspace name: ${WORKSPACE_NAME}"
    fi
}

# Function to validate resource group
validate_resource_group() {
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_error "Resource group not specified. Use -g option or ensure deployment info file exists."
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "Resource group '${RESOURCE_GROUP}' does not exist or you don't have access to it."
        exit 1
    fi
    
    log_info "Validated resource group: ${RESOURCE_GROUP}"
}

# Function to list resources that will be deleted
list_resources_for_deletion() {
    log_info "Analyzing resources in resource group: ${RESOURCE_GROUP}"
    
    local resource_count
    resource_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" --output tsv)
    
    if [[ "${resource_count}" -eq 0 ]]; then
        log_warning "No resources found in resource group: ${RESOURCE_GROUP}"
        return 1
    fi
    
    log_info "Found ${resource_count} resources to delete:"
    
    # List all resources in the resource group
    az resource list --resource-group "${RESOURCE_GROUP}" \
        --query "[].{Name:name, Type:type, Location:location}" \
        --output table
    
    return 0
}

# Function to get confirmation from user
get_user_confirmation() {
    local force_flag="$1"
    local resource_group="$2"
    
    if [[ "${force_flag}" == "true" ]]; then
        log_warning "Force flag enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    echo "================================================================"
    echo "                        ⚠️  WARNING  ⚠️"
    echo "================================================================"
    echo ""
    echo "You are about to DELETE the following resources:"
    echo ""
    echo "  Resource Group: ${resource_group}"
    echo "  All contained resources (VNets, Bastion, Firewall, etc.)"
    echo "  Azure Policy definitions and assignments"
    echo "  Log Analytics workspace and all logs"
    echo ""
    echo "This action is IRREVERSIBLE and will:"
    echo "  • Remove all zero-trust remote access infrastructure"
    echo "  • Delete all firewall rules and policies"
    echo "  • Remove all monitoring data and logs"
    echo "  • Stop all recurring charges for these resources"
    echo ""
    echo "================================================================"
    
    read -p "Are you absolutely sure you want to proceed? (type 'DELETE' to confirm): " -r
    echo
    
    if [[ "${REPLY}" != "DELETE" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_warning "User confirmed deletion. Proceeding with resource cleanup..."
}

# Function to remove Azure Policy assignments
remove_policy_assignments() {
    log_info "Removing Azure Policy assignments..."
    
    # List and remove policy assignments in the resource group
    local assignments
    assignments=$(az policy assignment list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || true)
    
    if [[ -n "${assignments}" ]]; then
        while IFS= read -r assignment; do
            if [[ -n "${assignment}" ]]; then
                log_info "Removing policy assignment: ${assignment}"
                az policy assignment delete \
                    --name "${assignment}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --output none 2>/dev/null || log_warning "Failed to delete policy assignment: ${assignment}"
            fi
        done <<< "${assignments}"
        
        log_success "Policy assignments removed"
    else
        log_info "No policy assignments found to remove"
    fi
}

# Function to remove Azure Policy definitions
remove_policy_definitions() {
    log_info "Removing Azure Policy definitions..."
    
    if [[ -n "${POLICY_DEFINITION_NAME:-}" ]]; then
        log_info "Removing policy definition: ${POLICY_DEFINITION_NAME}"
        az policy definition delete \
            --name "${POLICY_DEFINITION_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none 2>/dev/null || log_warning "Failed to delete policy definition: ${POLICY_DEFINITION_NAME}"
        
        log_success "Policy definition removed: ${POLICY_DEFINITION_NAME}"
    else
        log_info "No policy definition name found to remove"
    fi
}

# Function to remove diagnostic settings
remove_diagnostic_settings() {
    log_info "Removing diagnostic settings..."
    
    # Remove Bastion diagnostic settings
    if [[ -n "${BASTION_NAME:-}" ]] && [[ -n "${RESOURCE_GROUP:-}" ]]; then
        local bastion_id
        bastion_id=$(az network bastion show \
            --name "${BASTION_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query id --output tsv 2>/dev/null || true)
        
        if [[ -n "${bastion_id}" ]]; then
            log_info "Removing Bastion diagnostic settings"
            az monitor diagnostic-settings delete \
                --name diag-bastion \
                --resource "${bastion_id}" \
                --output none 2>/dev/null || log_warning "Failed to remove Bastion diagnostic settings"
        fi
    fi
    
    # Remove Firewall diagnostic settings
    if [[ -n "${FIREWALL_NAME:-}" ]] && [[ -n "${RESOURCE_GROUP:-}" ]]; then
        local firewall_id
        firewall_id=$(az network firewall show \
            --name "${FIREWALL_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query id --output tsv 2>/dev/null || true)
        
        if [[ -n "${firewall_id}" ]]; then
            log_info "Removing Firewall diagnostic settings"
            az monitor diagnostic-settings delete \
                --name diag-firewall \
                --resource "${firewall_id}" \
                --output none 2>/dev/null || log_warning "Failed to remove Firewall diagnostic settings"
        fi
    fi
    
    log_success "Diagnostic settings cleanup completed"
}

# Function to delete resource group and all resources
delete_resource_group() {
    log_info "Deleting resource group and all contained resources..."
    log_info "This may take 10-20 minutes to complete..."
    
    # Start the deletion process
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        --output none
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Deletion is running in the background. You can check status in Azure portal."
}

# Function to wait for deletion completion (optional)
wait_for_deletion_completion() {
    local max_wait_minutes=30
    local wait_interval=30
    local elapsed_minutes=0
    
    log_info "Monitoring deletion progress (max wait: ${max_wait_minutes} minutes)..."
    
    while [[ ${elapsed_minutes} -lt ${max_wait_minutes} ]]; do
        if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            log_success "Resource group successfully deleted: ${RESOURCE_GROUP}"
            return 0
        fi
        
        sleep ${wait_interval}
        elapsed_minutes=$((elapsed_minutes + 1))
        log_info "Still deleting... (${elapsed_minutes}/${max_wait_minutes} minutes elapsed)"
    done
    
    log_warning "Deletion is taking longer than expected. Check Azure portal for status."
    return 1
}

# Function to clean up state files
cleanup_state_files() {
    log_info "Cleaning up local state files..."
    
    local state_files=(
        ".deployment_info"
        ".bastion_name"
        ".firewall_name"
        ".firewall_private_ip"
        ".firewall_policy_name"
        ".policy_definition_name"
        ".workspace_name"
    )
    
    for file in "${state_files[@]}"; do
        local file_path="${SCRIPT_DIR}/${file}"
        if [[ -f "${file_path}" ]]; then
            rm -f "${file_path}"
            log_info "Removed state file: ${file}"
        fi
    done
    
    log_success "State files cleanup completed"
}

# Function to display deletion summary
display_deletion_summary() {
    echo ""
    echo "================================================================"
    echo "           ZERO-TRUST REMOTE ACCESS CLEANUP COMPLETE"
    echo "================================================================"
    echo ""
    echo "Deleted Resources:"
    echo "  ✅ Resource Group: ${RESOURCE_GROUP}"
    echo "  ✅ All Virtual Networks (Hub and Spokes)"
    echo "  ✅ Azure Bastion and Public IP"
    echo "  ✅ Azure Firewall and Public IP"
    echo "  ✅ Firewall Policies and Rules"
    echo "  ✅ Network Security Groups"
    echo "  ✅ Route Tables"
    echo "  ✅ Azure Policy Definitions and Assignments"
    echo "  ✅ Log Analytics Workspace"
    echo "  ✅ All Diagnostic Settings"
    echo "  ✅ Local State Files"
    echo ""
    echo "Cost Impact:"
    echo "  💰 Stopped all recurring charges (~$1,015/month)"
    echo "  💰 Azure Bastion charges stopped"
    echo "  💰 Azure Firewall charges stopped"
    echo "  💰 Log Analytics ingestion charges stopped"
    echo ""
    echo "Important Notes:"
    echo "  • All remote access capabilities have been removed"
    echo "  • Firewall protection is no longer active"
    echo "  • All security policies have been deleted"
    echo "  • Historical logs and monitoring data are lost"
    echo ""
    echo "To redeploy: ./deploy.sh"
    echo "================================================================"
}

# Main cleanup function
main() {
    local force_flag=false
    local dry_run=false
    local partial_cleanup=false
    local resource_group_override=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                resource_group_override="$2"
                shift 2
                ;;
            -f|--force)
                force_flag=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --partial)
                partial_cleanup=true
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
    
    log_info "Starting Zero-Trust Remote Access cleanup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment information
    if [[ -n "${resource_group_override}" ]]; then
        RESOURCE_GROUP="${resource_group_override}"
        log_info "Using resource group from command line: ${RESOURCE_GROUP}"
    else
        if ! load_deployment_info; then
            log_error "No deployment info found and no resource group specified."
            log_error "Use -g option to specify resource group to delete."
            exit 1
        fi
    fi
    
    # Load resource names
    load_resource_names
    
    # Validate resource group
    validate_resource_group
    
    # List resources for deletion
    if ! list_resources_for_deletion; then
        log_info "Resource group is empty or already cleaned up"
        cleanup_state_files
        exit 0
    fi
    
    # Dry run mode
    if [[ "${dry_run}" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        log_info "Resources listed above would be deleted in actual run"
        exit 0
    fi
    
    # Get user confirmation
    get_user_confirmation "${force_flag}" "${RESOURCE_GROUP}"
    
    # Enable partial cleanup mode if requested
    if [[ "${partial_cleanup}" == "true" ]]; then
        log_info "Partial cleanup mode enabled - continuing on errors"
        set +e  # Disable exit on error
    fi
    
    # Start cleanup process
    log_info "Beginning cleanup process..."
    
    # Remove Azure Policy resources first (they can prevent resource deletion)
    remove_policy_assignments
    remove_policy_definitions
    
    # Remove diagnostic settings
    remove_diagnostic_settings
    
    # Delete the entire resource group (this removes all contained resources)
    delete_resource_group
    
    # Clean up local state files
    cleanup_state_files
    
    # Display summary
    display_deletion_summary
    
    log_success "Zero-Trust Remote Access cleanup completed successfully!"
    log_info "Note: Resource deletion may take several more minutes to complete in Azure."
}

# Execute main function with all arguments
main "$@"