#!/bin/bash

# Azure Container Apps Cleanup Script
# This script removes all resources created by the deployment script
# Based on the recipe: Simple Container App Deployment with Container Apps

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deploy_config"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
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

# Error handler
error_handler() {
    local line_number="$1"
    log_error "Script failed at line ${line_number}. Check ${LOG_FILE} for details."
    log_warning "Some resources may not have been cleaned up. Manual verification recommended."
    exit 1
}

trap 'error_handler ${LINENO}' ERR

# Usage function
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Clean up Azure Container Apps infrastructure and resources.

OPTIONS:
    -r, --resource-group    Resource group name (required if no config file)
    -f, --force             Skip confirmation prompts
    -k, --keep-resource-group    Keep the resource group (only delete container resources)
    -c, --config-file       Path to deployment config file (default: .deploy_config)
    -h, --help              Show this help message
    -v, --verbose           Enable verbose logging
    --dry-run               Show what would be deleted without executing

EXAMPLES:
    ${SCRIPT_NAME}                                    # Clean up using saved config
    ${SCRIPT_NAME} -f                                # Force cleanup without prompts
    ${SCRIPT_NAME} -r my-resource-group              # Clean up specific resource group
    ${SCRIPT_NAME} --keep-resource-group             # Keep resource group, delete only app resources
    ${SCRIPT_NAME} --dry-run                         # Preview what would be deleted

NOTES:
    - If no resource group is specified and no config file exists, the script will prompt for input
    - Use --force to skip all confirmation prompts (useful for automation)
    - The script will attempt to load configuration from the deploy script if available

EOF
}

# Default values
RESOURCE_GROUP=""
FORCE=false
KEEP_RESOURCE_GROUP=false
VERBOSE=false
DRY_RUN=false
CONFIG_FILE_PATH="$CONFIG_FILE"

# Deployment configuration variables (loaded from config file)
LOCATION=""
SUBSCRIPTION_ID=""
CONTAINERAPPS_ENVIRONMENT=""
CONTAINER_APP_NAME=""
APP_URL=""
DEPLOYMENT_TIME=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -k|--keep-resource-group)
            KEEP_RESOURCE_GROUP=true
            shift
            ;;
        -c|--config-file)
            CONFIG_FILE_PATH="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --dry-run)
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

# Load configuration from deploy script
load_configuration() {
    log_info "Loading deployment configuration..."
    
    if [[ -f "$CONFIG_FILE_PATH" ]]; then
        log_info "Loading configuration from: $CONFIG_FILE_PATH"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE_PATH"
        
        # Use configuration values if resource group not specified
        if [[ -z "$RESOURCE_GROUP" && -n "${RESOURCE_GROUP:-}" ]]; then
            RESOURCE_GROUP="$RESOURCE_GROUP"
        fi
        
        log_info "Configuration loaded:"
        log_info "  Resource Group: ${RESOURCE_GROUP:-Not set}"
        log_info "  Location: ${LOCATION:-Not set}"
        log_info "  Container Apps Environment: ${CONTAINERAPPS_ENVIRONMENT:-Not set}"
        log_info "  Container App Name: ${CONTAINER_APP_NAME:-Not set}"
        [[ -n "$DEPLOYMENT_TIME" ]] && log_info "  Deployed at: $DEPLOYMENT_TIME"
        
    else
        log_warning "Configuration file not found: $CONFIG_FILE_PATH"
        if [[ -z "$RESOURCE_GROUP" ]]; then
            log_error "No resource group specified and no configuration file found."
            log_info "Please specify resource group with -r option or ensure .deploy_config exists."
            exit 1
        fi
    fi
    
    # Validate required configuration
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log_error "Resource group is required. Use -r option or ensure configuration file exists."
        exit 1
    fi
}

# Prerequisites check function
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Check if resource group exists
check_resource_group_exists() {
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# List resources to be deleted
list_resources() {
    log_info "Scanning for resources to delete..."
    
    if ! check_resource_group_exists; then
        log_warning "Resource group '$RESOURCE_GROUP' does not exist or is not accessible"
        return 1
    fi
    
    # List Container Apps
    log_info "Container Apps in resource group '$RESOURCE_GROUP':"
    local container_apps
    container_apps=$(az containerapp list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$container_apps" ]]; then
        echo "$container_apps" | while read -r app; do
            log_info "  - $app"
        done
    else
        log_info "  - No Container Apps found"
    fi
    
    # List Container Apps Environments
    log_info "Container Apps Environments in resource group '$RESOURCE_GROUP':"
    local environments
    environments=$(az containerapp env list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$environments" ]]; then
        echo "$environments" | while read -r env; do
            log_info "  - $env"
        done
    else
        log_info "  - No Container Apps Environments found" 
    fi
    
    # List all resources in resource group
    log_info "All resources in resource group '$RESOURCE_GROUP':"
    local all_resources
    all_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" -o table 2>/dev/null || echo "No resources found")
    echo "$all_resources" | while IFS= read -r line; do
        log_info "  $line"
    done
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE" == "true" ]]; then
        log_info "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This will delete the following:"
    if [[ "$KEEP_RESOURCE_GROUP" == "true" ]]; then
        log_warning "  - All Container Apps in resource group: $RESOURCE_GROUP"
        log_warning "  - All Container Apps Environments in resource group: $RESOURCE_GROUP"
        log_warning "  - Associated Log Analytics workspaces and other supporting resources"
        log_info "  - Resource group '$RESOURCE_GROUP' will be KEPT"
    else
        log_warning "  - Resource group: $RESOURCE_GROUP"
        log_warning "  - ALL resources within the resource group"
    fi
    echo
    
    read -rp "Are you sure you want to continue? (yes/no): " confirmation
    case "$confirmation" in
        yes|YES|y|Y)
            log_info "Deletion confirmed"
            return 0
            ;;
        *)
            log_info "Deletion cancelled"
            exit 0
            ;;
    esac
}

# Delete Container App
delete_container_app() {
    if [[ -z "$CONTAINER_APP_NAME" ]]; then
        log_info "No specific container app name found, checking for any apps in resource group"
        local apps
        apps=$(az containerapp list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
        
        if [[ -n "$apps" ]]; then
            echo "$apps" | while read -r app; do
                log_info "Deleting container app: $app"
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_info "[DRY RUN] Would delete container app: $app"
                else
                    az containerapp delete --name "$app" --resource-group "$RESOURCE_GROUP" --yes
                    log_success "Container app deleted: $app"
                fi
            done
        else
            log_info "No container apps found to delete"
        fi
        return 0
    fi
    
    log_info "Deleting container app: $CONTAINER_APP_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete container app: $CONTAINER_APP_NAME"
        return 0
    fi
    
    # Check if container app exists
    if az containerapp show --name "$CONTAINER_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az containerapp delete --name "$CONTAINER_APP_NAME" --resource-group "$RESOURCE_GROUP" --yes
        log_success "Container app deleted: $CONTAINER_APP_NAME"
    else
        log_info "Container app '$CONTAINER_APP_NAME' does not exist or was already deleted"
    fi
}

# Delete Container Apps Environment
delete_environment() {
    if [[ -z "$CONTAINERAPPS_ENVIRONMENT" ]]; then
        log_info "No specific environment name found, checking for any environments in resource group"
        local environments
        environments=$(az containerapp env list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
        
        if [[ -n "$environments" ]]; then
            echo "$environments" | while read -r env; do
                log_info "Deleting Container Apps environment: $env"
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_info "[DRY RUN] Would delete Container Apps environment: $env"
                else
                    az containerapp env delete --name "$env" --resource-group "$RESOURCE_GROUP" --yes
                    log_success "Container Apps environment deleted: $env"
                fi
            done
        else
            log_info "No Container Apps environments found to delete"
        fi
        return 0
    fi
    
    log_info "Deleting Container Apps environment: $CONTAINERAPPS_ENVIRONMENT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Container Apps environment: $CONTAINERAPPS_ENVIRONMENT"
        return 0
    fi
    
    # Check if environment exists
    if az containerapp env show --name "$CONTAINERAPPS_ENVIRONMENT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az containerapp env delete --name "$CONTAINERAPPS_ENVIRONMENT" --resource-group "$RESOURCE_GROUP" --yes
        log_success "Container Apps environment deleted: $CONTAINERAPPS_ENVIRONMENT"
    else
        log_info "Container Apps environment '$CONTAINERAPPS_ENVIRONMENT' does not exist or was already deleted"
    fi
}

# Delete resource group
delete_resource_group() {
    if [[ "$KEEP_RESOURCE_GROUP" == "true" ]]; then
        log_info "Keeping resource group as requested: $RESOURCE_GROUP"
        return 0
    fi
    
    log_info "Deleting resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    # Check if resource group exists
    if check_resource_group_exists; then
        # Delete resource group and all resources within it
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait
        
        log_success "Resource group deletion initiated: $RESOURCE_GROUP"
        log_info "Note: Deletion may take several minutes to complete"
        
        # Optional: Wait and verify deletion
        if [[ "$VERBOSE" == "true" ]]; then
            log_info "Waiting for resource group deletion to complete..."
            local max_attempts=60  # 10 minutes maximum
            local attempt=1
            
            while [[ $attempt -le $max_attempts ]]; do
                if ! check_resource_group_exists; then
                    log_success "Resource group deletion completed"
                    break
                fi
                
                log_info "Waiting for deletion... (attempt $attempt/$max_attempts)"
                sleep 10
                ((attempt++))
            done
            
            if [[ $attempt -gt $max_attempts ]]; then
                log_warning "Resource group deletion taking longer than expected"
                log_info "Check deletion status with: az group show --name $RESOURCE_GROUP"
            fi
        fi
    else
        log_info "Resource group '$RESOURCE_GROUP' does not exist or was already deleted"
    fi
}

# Clean up configuration files
cleanup_config() {
    log_info "Cleaning up configuration files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove configuration files"
        return 0
    fi
    
    if [[ -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"
        log_success "Removed configuration file: $CONFIG_FILE"
    fi
    
    # Clean up any other temporary files
    if [[ -f "${SCRIPT_DIR}/deploy.log" ]]; then
        log_info "Deployment log preserved: ${SCRIPT_DIR}/deploy.log"
    fi
}

# Verify cleanup
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify cleanup"
        return 0
    fi
    
    log_info "Verifying cleanup..."
    
    if [[ "$KEEP_RESOURCE_GROUP" == "true" ]]; then
        # Check if container apps and environments are deleted
        local remaining_apps
        remaining_apps=$(az containerapp list --resource-group "$RESOURCE_GROUP" --query "length([*])" -o tsv 2>/dev/null || echo "0")
        
        local remaining_envs
        remaining_envs=$(az containerapp env list --resource-group "$RESOURCE_GROUP" --query "length([*])" -o tsv 2>/dev/null || echo "0")
        
        if [[ "$remaining_apps" -eq 0 && "$remaining_envs" -eq 0 ]]; then
            log_success "All Container Apps resources have been removed"
        else
            log_warning "Some Container Apps resources may still exist:"
            log_warning "  Container Apps: $remaining_apps"
            log_warning "  Environments: $remaining_envs"
        fi
    else
        # Check if resource group still exists
        if ! check_resource_group_exists; then
            log_success "Resource group has been completely removed"
        else
            log_warning "Resource group still exists (deletion may be in progress)"
            log_info "Check status with: az group show --name $RESOURCE_GROUP"
        fi
    fi
}

# Display cleanup summary
show_summary() {
    log_info "Cleanup Summary"
    log_info "==============="
    log_info "Resource Group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] No resources were actually deleted"
    else
        if [[ "$KEEP_RESOURCE_GROUP" == "true" ]]; then
            log_info "Status: Container Apps resources removed, resource group preserved"
            log_info "Remaining resources in resource group (if any) preserved"
        else
            log_info "Status: Resource group and all resources marked for deletion"
            log_info "Deletion may take several minutes to complete in the background"
        fi
    fi
    
    log_info ""
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Cleanup completed successfully!"
        log_info "Cleanup log: ${LOG_FILE}"
        
        if [[ "$KEEP_RESOURCE_GROUP" != "true" ]]; then
            log_info "Verify deletion with: az group show --name $RESOURCE_GROUP"
            log_info "(Command should return 'ResourceGroupNotFound' when deletion is complete)"
        fi
    fi
}

# Main execution
main() {
    log_info "Starting Azure Container Apps cleanup"
    log_info "Script: $SCRIPT_NAME"
    log_info "Log file: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
    fi
    
    check_prerequisites
    load_configuration
    list_resources
    confirm_deletion
    
    if [[ "$KEEP_RESOURCE_GROUP" == "true" ]]; then
        delete_container_app
        delete_environment  
    else
        delete_resource_group
    fi
    
    cleanup_config
    verify_cleanup
    show_summary
    
    log_success "Cleanup process completed!"
}

# Execute main function
main "$@"