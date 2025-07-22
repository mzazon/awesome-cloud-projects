#!/bin/bash

# Azure Performance Regression Detection - Cleanup Script
# This script safely removes all infrastructure created for the
# automated performance regression detection solution

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default values
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/azure-perftest-destroy-$(date +%Y%m%d-%H%M%S).log"
readonly DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment-state"

# Configuration variables
RESOURCE_GROUP=""
FORCE=false
DRY_RUN=false
VERBOSE=false
SKIP_CONFIRMATION=false

# Resource information
LOAD_TEST_NAME=""
CONTAINER_APP_NAME=""
WORKSPACE_NAME=""
ENVIRONMENT_NAME=""
ACR_NAME=""
WORKBOOK_NAME=""

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] ${message}${NC}" | tee -a "${LOG_FILE}"
}

print_info() { print_status "${BLUE}" "INFO: $1"; }
print_success() { print_status "${GREEN}" "SUCCESS: $1"; }
print_warning() { print_status "${YELLOW}" "WARNING: $1"; }
print_error() { print_status "${RED}" "ERROR: $1"; }

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    print_success "Prerequisites check completed"
}

# Function to load deployment state
load_deployment_state() {
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        print_info "Loading deployment state from: $DEPLOYMENT_STATE_FILE"
        source "$DEPLOYMENT_STATE_FILE"
        
        # Set resource group from state if not provided via command line
        if [[ -z "$RESOURCE_GROUP" ]] && [[ -n "${RESOURCE_GROUP:-}" ]]; then
            RESOURCE_GROUP="$RESOURCE_GROUP"
        fi
        
        print_info "Loaded deployment state for resource group: ${RESOURCE_GROUP:-unknown}"
    else
        print_warning "No deployment state file found at: $DEPLOYMENT_STATE_FILE"
        if [[ -z "$RESOURCE_GROUP" ]]; then
            print_error "Resource group must be specified when no deployment state is available"
            exit 1
        fi
    fi
}

# Function to validate parameters
validate_parameters() {
    if [[ -z "$RESOURCE_GROUP" ]]; then
        print_error "Resource group name is required. Use --resource-group parameter or ensure deployment state file exists."
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group exists --name "$RESOURCE_GROUP"; then
        print_error "Resource group '$RESOURCE_GROUP' does not exist"
        exit 1
    fi
}

# Function to discover resources in resource group
discover_resources() {
    print_info "Discovering resources in resource group: $RESOURCE_GROUP"
    
    if $DRY_RUN; then
        print_info "[DRY RUN] Would discover resources in: $RESOURCE_GROUP"
        return
    fi
    
    # Get all resources in the resource group
    local resources
    resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].{Name:name, Type:type}' --output table)
    
    if [[ -n "$resources" ]]; then
        print_info "Found resources in $RESOURCE_GROUP:"
        echo "$resources" | tee -a "${LOG_FILE}"
    else
        print_warning "No resources found in resource group: $RESOURCE_GROUP"
    fi
}

# Function to confirm destruction
confirm_destruction() {
    if $SKIP_CONFIRMATION; then
        print_warning "Skipping confirmation as requested"
        return
    fi
    
    echo ""
    print_warning "=========================================="
    print_warning "WARNING: DESTRUCTIVE OPERATION"
    print_warning "=========================================="
    print_warning "This will DELETE the following:"
    print_warning "  • Resource Group: $RESOURCE_GROUP"
    print_warning "  • ALL resources within the resource group"
    print_warning "  • ALL data and configurations"
    print_warning ""
    print_warning "This action CANNOT be undone!"
    print_warning "=========================================="
    echo ""
    
    if $FORCE; then
        print_warning "Force mode enabled - proceeding without confirmation"
        return
    fi
    
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Operation cancelled by user"
        exit 0
    fi
    
    # Double confirmation for production-like names
    if [[ "$RESOURCE_GROUP" =~ (prod|production|live) ]]; then
        echo ""
        print_warning "This appears to be a PRODUCTION resource group!"
        read -p "Please type the resource group name to confirm: " -r
        if [[ "$REPLY" != "$RESOURCE_GROUP" ]]; then
            print_error "Resource group name does not match. Aborting."
            exit 1
        fi
    fi
}

# Function to delete specific Azure resources (graceful cleanup)
delete_azure_resources() {
    print_info "Starting graceful resource cleanup..."
    
    if $DRY_RUN; then
        print_info "[DRY RUN] Would delete Azure resources"
        return
    fi
    
    # Delete Container Apps first (to avoid dependency issues)
    if [[ -n "${CONTAINER_APP_NAME:-}" ]]; then
        print_info "Deleting Container App: $CONTAINER_APP_NAME"
        if az containerapp show --name "$CONTAINER_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az containerapp delete \
                --name "$CONTAINER_APP_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none || print_warning "Failed to delete Container App: $CONTAINER_APP_NAME"
            print_success "Container App deleted: $CONTAINER_APP_NAME"
        else
            print_warning "Container App not found: $CONTAINER_APP_NAME"
        fi
    fi
    
    # Delete Container Apps Environment
    if [[ -n "${ENVIRONMENT_NAME:-}" ]]; then
        print_info "Deleting Container Apps Environment: $ENVIRONMENT_NAME"
        if az containerapp env show --name "$ENVIRONMENT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az containerapp env delete \
                --name "$ENVIRONMENT_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none || print_warning "Failed to delete Container Apps Environment: $ENVIRONMENT_NAME"
            print_success "Container Apps Environment deleted: $ENVIRONMENT_NAME"
        else
            print_warning "Container Apps Environment not found: $ENVIRONMENT_NAME"
        fi
    fi
    
    # Delete Container Registry
    if [[ -n "${ACR_NAME:-}" ]]; then
        print_info "Deleting Azure Container Registry: $ACR_NAME"
        if az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az acr delete \
                --name "$ACR_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none || print_warning "Failed to delete Container Registry: $ACR_NAME"
            print_success "Container Registry deleted: $ACR_NAME"
        else
            print_warning "Container Registry not found: $ACR_NAME"
        fi
    fi
    
    # Delete Load Testing resource
    if [[ -n "${LOAD_TEST_NAME:-}" ]]; then
        print_info "Deleting Azure Load Testing resource: $LOAD_TEST_NAME"
        if az load show --name "$LOAD_TEST_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az load delete \
                --name "$LOAD_TEST_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none || print_warning "Failed to delete Load Testing resource: $LOAD_TEST_NAME"
            print_success "Load Testing resource deleted: $LOAD_TEST_NAME"
        else
            print_warning "Load Testing resource not found: $LOAD_TEST_NAME"
        fi
    fi
    
    # Delete Log Analytics Workspace
    if [[ -n "${WORKSPACE_NAME:-}" ]]; then
        print_info "Deleting Log Analytics Workspace: $WORKSPACE_NAME"
        if az monitor log-analytics workspace show --workspace-name "$WORKSPACE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az monitor log-analytics workspace delete \
                --workspace-name "$WORKSPACE_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --force true \
                --output none || print_warning "Failed to delete Log Analytics Workspace: $WORKSPACE_NAME"
            print_success "Log Analytics Workspace deleted: $WORKSPACE_NAME"
        else
            print_warning "Log Analytics Workspace not found: $WORKSPACE_NAME"
        fi
    fi
    
    # Delete any remaining alert rules and action groups
    print_info "Cleaning up monitoring resources..."
    local action_groups
    action_groups=$(az monitor action-group list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || true)
    for ag in $action_groups; do
        print_info "Deleting action group: $ag"
        az monitor action-group delete \
            --name "$ag" \
            --resource-group "$RESOURCE_GROUP" \
            --output none || print_warning "Failed to delete action group: $ag"
    done
    
    print_success "Graceful resource cleanup completed"
}

# Function to delete entire resource group
delete_resource_group() {
    print_info "Deleting resource group: $RESOURCE_GROUP"
    
    if $DRY_RUN; then
        print_info "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return
    fi
    
    # Final check that resource group exists
    if ! az group exists --name "$RESOURCE_GROUP"; then
        print_warning "Resource group '$RESOURCE_GROUP' does not exist"
        return
    fi
    
    print_info "Starting resource group deletion (this may take several minutes)..."
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none
    
    print_success "Resource group deletion initiated: $RESOURCE_GROUP"
    print_info "Note: Deletion continues in the background and may take several minutes to complete"
}

# Function to verify deletion
verify_deletion() {
    if $DRY_RUN; then
        print_info "[DRY RUN] Would verify deletion"
        return
    fi
    
    print_info "Verifying resource group deletion..."
    
    local max_wait=300  # 5 minutes
    local wait_interval=10
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        if ! az group exists --name "$RESOURCE_GROUP"; then
            print_success "Resource group successfully deleted: $RESOURCE_GROUP"
            return
        fi
        
        print_info "Waiting for deletion to complete... ($elapsed/$max_wait seconds)"
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    
    print_warning "Resource group deletion is taking longer than expected"
    print_info "You can check the status with: az group show --name $RESOURCE_GROUP"
}

# Function to clean up local files
cleanup_local_files() {
    print_info "Cleaning up local configuration files..."
    
    if $DRY_RUN; then
        print_info "[DRY RUN] Would clean up local files"
        return
    fi
    
    local files_to_remove=(
        "${SCRIPT_DIR}/loadtest.jmx"
        "${SCRIPT_DIR}/loadtest-config.yaml"
        "${SCRIPT_DIR}/azure-pipelines.yml"
        "${SCRIPT_DIR}/.deployment-state"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            print_info "Removed: $file"
        fi
    done
    
    # Remove any temporary workbook templates
    local temp_files
    temp_files=$(find /tmp -name "performance-workbook-*.json" 2>/dev/null || true)
    for file in $temp_files; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            print_info "Removed temp file: $file"
        fi
    done
    
    print_success "Local cleanup completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    print_success "=== CLEANUP COMPLETED ==="
    echo ""
    print_info "Resource Group: $RESOURCE_GROUP"
    print_info "Status: Deletion initiated"
    echo ""
    print_info "Cleaned up resources:"
    if [[ -n "${LOAD_TEST_NAME:-}" ]]; then
        print_info "  • Load Testing: $LOAD_TEST_NAME"
    fi
    if [[ -n "${CONTAINER_APP_NAME:-}" ]]; then
        print_info "  • Container App: $CONTAINER_APP_NAME"
    fi
    if [[ -n "${WORKSPACE_NAME:-}" ]]; then
        print_info "  • Log Analytics: $WORKSPACE_NAME"
    fi
    if [[ -n "${ENVIRONMENT_NAME:-}" ]]; then
        print_info "  • Container Env: $ENVIRONMENT_NAME"
    fi
    if [[ -n "${ACR_NAME:-}" ]]; then
        print_info "  • Container Registry: $ACR_NAME"
    fi
    echo ""
    print_info "Local files cleaned up from: $SCRIPT_DIR"
    print_info "Log file: $LOG_FILE"
    echo ""
    print_warning "Note: Resource deletion may continue in the background"
    print_info "Verify deletion with: az group exists --name $RESOURCE_GROUP"
}

# Function to handle errors
handle_error() {
    local exit_code=$1
    print_error "Cleanup failed with exit code: $exit_code"
    print_error "Check the log file for details: $LOG_FILE"
    print_warning "Some resources may still exist in: $RESOURCE_GROUP"
    print_info "You may need to manually clean up remaining resources"
    exit $exit_code
}

# Function to show usage
show_usage() {
    cat << EOF
Azure Performance Regression Detection - Cleanup Script

Usage: $0 [OPTIONS]

Options:
  --resource-group NAME    Name of the Azure resource group to delete
  --force                 Skip confirmation prompts (dangerous!)
  --dry-run              Show what would be done without making changes
  --skip-confirmation    Skip confirmation prompts (same as --force)
  --verbose              Enable verbose logging
  --help                 Show this help message

Examples:
  $0 --resource-group rg-perftest-demo
  $0 --resource-group rg-perftest-prod --force
  $0 --dry-run --resource-group rg-perftest-test

WARNING: This script will DELETE ALL resources in the specified resource group!

The script will look for a deployment state file (.deployment-state) in the same
directory to discover resource names. If no state file exists, it will attempt
to delete the entire resource group.

For more information, see the recipe documentation.
EOF
}

# Main execution function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            --skip-confirmation)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set up error handling
    trap 'handle_error $?' ERR
    
    # Enable verbose logging if requested
    if $VERBOSE; then
        set -x
    fi
    
    print_info "Starting Azure Performance Regression Detection cleanup"
    print_info "Log file: $LOG_FILE"
    
    if $DRY_RUN; then
        print_warning "DRY RUN MODE: No resources will be deleted"
    fi
    
    # Execute cleanup steps
    check_prerequisites
    load_deployment_state
    validate_parameters
    discover_resources
    confirm_destruction
    
    delete_azure_resources
    delete_resource_group
    cleanup_local_files
    
    if ! $DRY_RUN; then
        verify_deletion
    fi
    
    display_cleanup_summary
    
    print_success "Cleanup completed successfully!"
}

# Execute main function with all arguments
main "$@"