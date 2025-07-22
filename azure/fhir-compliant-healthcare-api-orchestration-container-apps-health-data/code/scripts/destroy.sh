#!/bin/bash
#
# Destroy script for Azure FHIR-Compliant Healthcare API Orchestration
# This script safely removes all healthcare API infrastructure created by deploy.sh
# with proper confirmation prompts and resource dependency handling
#
# Usage: ./destroy.sh [--dry-run] [--debug] [--resource-group <name>] [--force] [--keep-logs]
#
# Requirements:
# - Azure CLI v2.53.0 or later
# - Healthcare APIs extension for Azure CLI
# - Appropriate Azure permissions for resource deletion
#
# Author: Recipe Generator
# Version: 1.0
# Date: 2025-01-27

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DRY_RUN=false
DEBUG=false
FORCE=false
KEEP_LOGS=false
RESOURCE_GROUP=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --keep-logs)
            KEEP_LOGS=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--dry-run] [--debug] [--resource-group <name>] [--force] [--keep-logs]"
            echo ""
            echo "Options:"
            echo "  --dry-run           Show what would be deleted without actually deleting"
            echo "  --debug             Enable debug logging"
            echo "  --resource-group    Specify resource group name to delete"
            echo "  --force             Skip confirmation prompts"
            echo "  --keep-logs         Keep Log Analytics workspace (preserve logs)"
            echo "  --help              Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Enable debug mode if requested
if [[ "$DEBUG" == "true" ]]; then
    set -x
fi

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Info logging
log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

# Success logging
log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

# Warning logging
log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

# Error logging
log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Progress indicator
show_progress() {
    local message="$1"
    echo -e "${BLUE}[PROGRESS]${NC} $message"
}

# Cleanup function for error handling
cleanup() {
    if [[ $? -ne 0 ]]; then
        log_error "Cleanup failed. Check $LOG_FILE for details."
        log_error "Some resources may still exist and incur charges."
        echo -e "${RED}Cleanup failed!${NC}"
        exit 1
    fi
}

# Set up error handling
trap cleanup EXIT

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Azure CLI version
check_azure_cli_version() {
    local required_version="2.53.0"
    local current_version
    
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install Azure CLI v${required_version} or later."
        exit 1
    fi
    
    current_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    
    if [[ "$(printf '%s\n' "$required_version" "$current_version" | sort -V | head -n1)" != "$required_version" ]]; then
        log_error "Azure CLI version ${current_version} is too old. Required: ${required_version} or later."
        exit 1
    fi
    
    log_success "Azure CLI version check passed: ${current_version}"
}

# Function to check Azure authentication
check_azure_auth() {
    log_info "Checking Azure authentication..."
    
    if ! az account show >/dev/null 2>&1; then
        log_error "Not authenticated to Azure. Please run: az login"
        exit 1
    fi
    
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    
    log_success "Authenticated to Azure subscription: ${subscription_name} (${subscription_id})"
}

# Function to check if resource group exists
check_resource_group() {
    local rg_name="$1"
    
    if ! az group show --name "$rg_name" >/dev/null 2>&1; then
        log_error "Resource group '$rg_name' does not exist or is not accessible."
        exit 1
    fi
    
    log_success "Resource group '$rg_name' found"
}

# Function to list resources in the resource group
list_resources() {
    local rg_name="$1"
    
    log_info "Listing resources in resource group '$rg_name'..."
    
    local resources
    resources=$(az resource list --resource-group "$rg_name" --query "[].{Name:name, Type:type, Location:location}" --output table 2>/dev/null)
    
    if [[ -z "$resources" ]]; then
        log_warning "No resources found in resource group '$rg_name'"
        return 1
    fi
    
    echo "$resources"
    return 0
}

# Function to execute command with dry-run support
execute_command() {
    local description="$1"
    local command="$2"
    local required="${3:-true}"
    local ignore_errors="${4:-false}"
    
    show_progress "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: $command"
        return 0
    fi
    
    log_info "Executing: $command"
    
    if eval "$command" >> "$LOG_FILE" 2>&1; then
        log_success "$description completed successfully"
        return 0
    else
        if [[ "$ignore_errors" == "true" ]]; then
            log_warning "$description failed (ignored)"
            return 0
        elif [[ "$required" == "true" ]]; then
            log_error "$description failed"
            exit 1
        else
            log_warning "$description failed (non-critical)"
            return 1
        fi
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    local max_attempts="${4:-20}"
    local sleep_interval="${5:-15}"
    
    log_info "Waiting for ${resource_type} '${resource_name}' to be deleted..."
    
    for i in $(seq 1 $max_attempts); do
        case "$resource_type" in
            "apim")
                if ! az apim show --resource-group "$resource_group" --name "$resource_name" >/dev/null 2>&1; then
                    log_success "${resource_type} '${resource_name}' has been deleted"
                    return 0
                fi
                ;;
            "containerapp")
                if ! az containerapp show --resource-group "$resource_group" --name "$resource_name" >/dev/null 2>&1; then
                    log_success "${resource_type} '${resource_name}' has been deleted"
                    return 0
                fi
                ;;
            "containerapp-env")
                if ! az containerapp env show --resource-group "$resource_group" --name "$resource_name" >/dev/null 2>&1; then
                    log_success "${resource_type} '${resource_name}' has been deleted"
                    return 0
                fi
                ;;
            "healthcareapis-fhir")
                if ! az healthcareapis fhir-service show --resource-group "$resource_group" --workspace-name "$resource_name" >/dev/null 2>&1; then
                    log_success "${resource_type} '${resource_name}' has been deleted"
                    return 0
                fi
                ;;
            *)
                log_info "Skipping wait for unknown resource type: $resource_type"
                return 0
                ;;
        esac
        
        log_info "Attempt $i/$max_attempts: ${resource_type} '${resource_name}' still exists. Waiting ${sleep_interval} seconds..."
        sleep "$sleep_interval"
    done
    
    log_warning "Timeout waiting for ${resource_type} '${resource_name}' to be deleted (may still be in progress)"
    return 1
}

# Function to find and delete container apps
delete_container_apps() {
    local rg_name="$1"
    
    log_info "Finding Container Apps in resource group '$rg_name'..."
    
    local container_apps
    container_apps=$(az containerapp list --resource-group "$rg_name" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$container_apps" ]]; then
        log_info "No Container Apps found"
        return 0
    fi
    
    for app in $container_apps; do
        execute_command \
            "Deleting Container App: $app" \
            "az containerapp delete --resource-group '$rg_name' --name '$app' --yes" \
            false \
            true
        
        if [[ "$DRY_RUN" == "false" ]]; then
            wait_for_deletion "containerapp" "$app" "$rg_name" 10 10
        fi
    done
}

# Function to find and delete container environments
delete_container_environments() {
    local rg_name="$1"
    
    log_info "Finding Container App Environments in resource group '$rg_name'..."
    
    local environments
    environments=$(az containerapp env list --resource-group "$rg_name" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$environments" ]]; then
        log_info "No Container App Environments found"
        return 0
    fi
    
    for env in $environments; do
        execute_command \
            "Deleting Container App Environment: $env" \
            "az containerapp env delete --resource-group '$rg_name' --name '$env' --yes" \
            false \
            true
        
        if [[ "$DRY_RUN" == "false" ]]; then
            wait_for_deletion "containerapp-env" "$env" "$rg_name" 15 10
        fi
    done
}

# Function to find and delete FHIR services
delete_fhir_services() {
    local rg_name="$1"
    
    log_info "Finding Healthcare workspaces in resource group '$rg_name'..."
    
    local workspaces
    workspaces=$(az healthcareapis workspace list --resource-group "$rg_name" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$workspaces" ]]; then
        log_info "No Healthcare workspaces found"
        return 0
    fi
    
    for workspace in $workspaces; do
        log_info "Finding FHIR services in workspace: $workspace"
        
        local fhir_services
        fhir_services=$(az healthcareapis fhir-service list --resource-group "$rg_name" --workspace-name "$workspace" --query "[].name" --output tsv 2>/dev/null || echo "")
        
        for fhir_service in $fhir_services; do
            execute_command \
                "Deleting FHIR Service: $fhir_service" \
                "az healthcareapis fhir-service delete --resource-group '$rg_name' --workspace-name '$workspace' --fhir-service-name '$fhir_service' --yes" \
                false \
                true
        done
        
        execute_command \
            "Deleting Healthcare Workspace: $workspace" \
            "az healthcareapis workspace delete --resource-group '$rg_name' --workspace-name '$workspace' --yes" \
            false \
            true
    done
}

# Function to find and delete Communication Services
delete_communication_services() {
    local rg_name="$1"
    
    log_info "Finding Communication Services in resource group '$rg_name'..."
    
    local comm_services
    comm_services=$(az communication list --resource-group "$rg_name" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$comm_services" ]]; then
        log_info "No Communication Services found"
        return 0
    fi
    
    for comm_service in $comm_services; do
        execute_command \
            "Deleting Communication Service: $comm_service" \
            "az communication delete --name '$comm_service' --resource-group '$rg_name' --yes" \
            false \
            true
    done
}

# Function to find and delete API Management instances
delete_api_management() {
    local rg_name="$1"
    
    log_info "Finding API Management instances in resource group '$rg_name'..."
    
    local apim_instances
    apim_instances=$(az apim list --resource-group "$rg_name" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$apim_instances" ]]; then
        log_info "No API Management instances found"
        return 0
    fi
    
    for apim in $apim_instances; do
        execute_command \
            "Deleting API Management instance: $apim" \
            "az apim delete --resource-group '$rg_name' --name '$apim' --yes" \
            false \
            true
        
        if [[ "$DRY_RUN" == "false" ]]; then
            wait_for_deletion "apim" "$apim" "$rg_name" 30 30
        fi
    done
}

# Function to find and delete Log Analytics workspaces
delete_log_analytics() {
    local rg_name="$1"
    
    if [[ "$KEEP_LOGS" == "true" ]]; then
        log_info "Keeping Log Analytics workspace (--keep-logs specified)"
        return 0
    fi
    
    log_info "Finding Log Analytics workspaces in resource group '$rg_name'..."
    
    local workspaces
    workspaces=$(az monitor log-analytics workspace list --resource-group "$rg_name" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$workspaces" ]]; then
        log_info "No Log Analytics workspaces found"
        return 0
    fi
    
    for workspace in $workspaces; do
        execute_command \
            "Deleting Log Analytics workspace: $workspace" \
            "az monitor log-analytics workspace delete --resource-group '$rg_name' --workspace-name '$workspace' --force true" \
            false \
            true
    done
}

# Function to delete remaining resources
delete_remaining_resources() {
    local rg_name="$1"
    
    log_info "Deleting any remaining resources in resource group '$rg_name'..."
    
    local remaining_resources
    remaining_resources=$(az resource list --resource-group "$rg_name" --query "[].id" --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$remaining_resources" ]]; then
        log_info "No remaining resources found"
        return 0
    fi
    
    for resource_id in $remaining_resources; do
        local resource_name=$(basename "$resource_id")
        execute_command \
            "Deleting remaining resource: $resource_name" \
            "az resource delete --ids '$resource_id' --verbose" \
            false \
            true
    done
}

# Main destroy function
destroy_infrastructure() {
    local rg_name="$1"
    
    log_info "Starting destruction of healthcare API orchestration infrastructure..."
    
    # Step 1: Delete Container Apps (in dependency order)
    delete_container_apps "$rg_name"
    
    # Step 2: Delete Container App Environments
    delete_container_environments "$rg_name"
    
    # Step 3: Delete FHIR Services and Healthcare Workspaces
    delete_fhir_services "$rg_name"
    
    # Step 4: Delete Communication Services
    delete_communication_services "$rg_name"
    
    # Step 5: Delete API Management (takes longest time)
    delete_api_management "$rg_name"
    
    # Step 6: Delete Log Analytics workspace (if not keeping)
    delete_log_analytics "$rg_name"
    
    # Step 7: Delete any remaining resources
    delete_remaining_resources "$rg_name"
    
    # Step 8: Delete the resource group itself
    execute_command \
        "Deleting resource group: $rg_name" \
        "az group delete --name '$rg_name' --yes --no-wait" \
        true \
        false
    
    log_success "Healthcare API orchestration infrastructure destruction completed!"
    
    # Display cleanup summary
    echo ""
    echo "======================================"
    echo "CLEANUP SUMMARY"
    echo "======================================"
    echo "Resource Group: ${rg_name}"
    echo "Status: Deletion initiated"
    echo ""
    echo "Deleted resource types:"
    echo "  - Container Apps (microservices)"
    echo "  - Container App Environments"
    echo "  - FHIR Services and Healthcare Workspaces"
    echo "  - Communication Services"
    echo "  - API Management instances"
    if [[ "$KEEP_LOGS" == "false" ]]; then
        echo "  - Log Analytics workspaces"
    else
        echo "  - Log Analytics workspaces (PRESERVED)"
    fi
    echo ""
    echo "Notes:"
    echo "  - Resource group deletion is running in background"
    echo "  - Some resources may take additional time to fully delete"
    echo "  - Verify no charges are incurred by checking Azure portal"
    echo "  - Soft-deleted resources may need manual cleanup"
    echo ""
    echo "To check deletion status:"
    echo "  az group show --name '${rg_name}' (should fail when fully deleted)"
    echo "======================================"
}

# Function to prompt for resource group if not provided
prompt_for_resource_group() {
    if [[ -z "$RESOURCE_GROUP" ]]; then
        echo ""
        echo "Available resource groups with healthcare resources:"
        az group list --query "[?tags.purpose=='healthcare-fhir'].{Name:name, Location:location}" --output table 2>/dev/null || echo "No healthcare resource groups found"
        echo ""
        read -p "Enter the resource group name to delete: " RESOURCE_GROUP
        
        if [[ -z "$RESOURCE_GROUP" ]]; then
            log_error "Resource group name is required"
            exit 1
        fi
    fi
}

# Main execution
main() {
    log_info "Starting destroy script with PID: $$"
    
    # Initialize log file
    echo "=== Azure FHIR Healthcare API Orchestration Destruction Log ===" > "$LOG_FILE"
    echo "Date: $(date)" >> "$LOG_FILE"
    echo "User: $(whoami)" >> "$LOG_FILE"
    echo "Arguments: $*" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    # Pre-destruction checks
    check_azure_cli_version
    check_azure_auth
    
    # Get resource group name
    prompt_for_resource_group
    
    # Verify resource group exists
    check_resource_group "$RESOURCE_GROUP"
    
    # Show destruction plan
    echo ""
    echo "======================================"
    echo "DESTRUCTION PLAN"
    echo "======================================"
    echo "Mode: $([ "$DRY_RUN" == "true" ] && echo "DRY RUN" || echo "LIVE DESTRUCTION")"
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Force Mode: ${FORCE}"
    echo "Keep Logs: ${KEEP_LOGS}"
    echo "Debug Mode: ${DEBUG}"
    echo "Log File: ${LOG_FILE}"
    echo "======================================"
    echo ""
    
    # List resources to be deleted
    echo "Resources to be deleted:"
    echo "------------------------"
    if list_resources "$RESOURCE_GROUP"; then
        echo ""
    else
        log_warning "Resource group appears to be empty or inaccessible"
    fi
    
    # Confirm destruction
    if [[ "$FORCE" == "false" ]]; then
        echo -e "${RED}WARNING: This will permanently delete all resources in the resource group!${NC}"
        echo -e "${RED}This action cannot be undone!${NC}"
        echo ""
        read -p "Are you sure you want to delete resource group '$RESOURCE_GROUP' and ALL its resources? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Destruction cancelled by user"
            exit 0
        fi
        
        echo ""
        echo -e "${YELLOW}Last chance to cancel!${NC}"
        read -p "Type 'DELETE' to confirm permanent deletion: " confirm
        if [[ "$confirm" != "DELETE" ]]; then
            log_info "Destruction cancelled by user"
            exit 0
        fi
    fi
    
    # Start destruction
    destroy_infrastructure "$RESOURCE_GROUP"
    
    log_success "Destruction completed successfully!"
}

# Run main function
main "$@"