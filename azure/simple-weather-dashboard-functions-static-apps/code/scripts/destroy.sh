#!/bin/bash

# Azure Weather Dashboard - Cleanup Script
# Removes all resources created by the weather dashboard deployment
# Author: Recipe Generator v1.3
# Last Updated: 2025-07-12

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${SCRIPT_DIR}/destroy_${TIMESTAMP}.log"

# Start logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

log_info "Starting Azure Weather Dashboard cleanup - $(date)"
log_info "Script directory: $SCRIPT_DIR"
log_info "Project root: $PROJECT_ROOT"
log_info "Log file: $LOG_FILE"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Check if .env file exists
    if [ -f "${SCRIPT_DIR}/.env" ]; then
        log_info "Loading variables from .env file"
        source "${SCRIPT_DIR}/.env"
        
        # Verify required variables are set
        if [ -n "${RESOURCE_GROUP:-}" ]; then
            log_info "Environment loaded from .env file"
            log_info "  Resource Group: $RESOURCE_GROUP"
            log_info "  App Name: ${WEATHER_APP_NAME:-}"
            log_info "  Location: ${LOCATION:-}"
            log_info "  Deployment Timestamp: ${DEPLOYMENT_TIMESTAMP:-}"
            return 0
        else
            log_warning ".env file exists but required variables not found"
        fi
    else
        log_warning ".env file not found"
    fi
    
    # Try to discover resources by tags if .env is not available
    log_info "Attempting to discover resources by tags..."
    
    # Look for resource groups with recipe tags
    DISCOVERED_RG=$(az group list \
        --tag purpose=recipe \
        --query "[?contains(name, 'weather-dashboard')].name" \
        --output tsv | head -1)
    
    if [ -n "$DISCOVERED_RG" ]; then
        export RESOURCE_GROUP="$DISCOVERED_RG"
        log_info "Discovered resource group: $RESOURCE_GROUP"
        
        # Try to find the Static Web App in this resource group
        DISCOVERED_APP=$(az staticwebapp list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[?contains(name, 'weather-app')].name" \
            --output tsv | head -1)
        
        if [ -n "$DISCOVERED_APP" ]; then
            export WEATHER_APP_NAME="$DISCOVERED_APP"
            log_info "Discovered Static Web App: $WEATHER_APP_NAME"
        fi
        
        return 0
    fi
    
    # If auto-discovery fails, prompt user
    log_warning "Could not automatically discover resources"
    echo
    echo "Please provide the resource group name to clean up:"
    read -p "Resource Group Name: " USER_RESOURCE_GROUP
    
    if [ -z "$USER_RESOURCE_GROUP" ]; then
        log_error "Resource group name is required for cleanup"
        exit 1
    fi
    
    export RESOURCE_GROUP="$USER_RESOURCE_GROUP"
    log_info "Using user-provided resource group: $RESOURCE_GROUP"
}

# Function to confirm cleanup action
confirm_cleanup() {
    log_warning "This will permanently delete the following resources:"
    echo
    
    if [ -n "${RESOURCE_GROUP:-}" ]; then
        # List resources in the resource group
        log_info "Resources in $RESOURCE_GROUP:"
        az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].{Name:name,Type:type,Location:location}" \
            --output table 2>/dev/null || log_warning "Could not list resources (resource group may not exist)"
    fi
    
    echo
    log_warning "Are you sure you want to proceed with cleanup?"
    echo "This action cannot be undone!"
    echo
    
    # Check for force flag
    if [ "${1:-}" == "--force" ] || [ "${FORCE_CLEANUP:-}" == "true" ]; then
        log_warning "Force cleanup enabled, proceeding without confirmation..."
        return 0
    fi
    
    read -p "Type 'yes' to confirm deletion: " CONFIRMATION
    
    if [ "$CONFIRMATION" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to delete Azure resources
delete_azure_resources() {
    log_info "Deleting Azure resources..."
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP does not exist"
        return 0
    fi
    
    # Delete Static Web App first (if specified)
    if [ -n "${WEATHER_APP_NAME:-}" ]; then
        log_info "Deleting Static Web App: $WEATHER_APP_NAME"
        
        if az staticwebapp show --name "$WEATHER_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az staticwebapp delete \
                --name "$WEATHER_APP_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
            
            if [ $? -eq 0 ]; then
                log_success "Static Web App deleted: $WEATHER_APP_NAME"
            else
                log_warning "Failed to delete Static Web App or it was already deleted"
            fi
        else
            log_warning "Static Web App $WEATHER_APP_NAME not found"
        fi
    fi
    
    # Delete the entire resource group
    log_info "Deleting resource group: $RESOURCE_GROUP"
    log_warning "This operation may take several minutes..."
    
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    if [ $? -eq 0 ]; then
        log_success "Resource group deletion initiated: $RESOURCE_GROUP"
        log_info "Note: Deletion will continue in the background and may take several minutes to complete"
    else
        log_error "Failed to initiate resource group deletion"
        exit 1
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove project directory if it exists
    PROJECT_DIR="${SCRIPT_DIR}/../weather-dashboard"
    if [ -d "$PROJECT_DIR" ]; then
        log_info "Removing project directory: $PROJECT_DIR"
        rm -rf "$PROJECT_DIR"
        
        if [ $? -eq 0 ]; then
            log_success "Project directory removed"
        else
            log_warning "Failed to remove project directory"
        fi
    else
        log_info "Project directory does not exist, nothing to clean"
    fi
    
    # Ask user if they want to remove the .env file
    if [ -f "${SCRIPT_DIR}/.env" ]; then
        if [ "${1:-}" == "--force" ] || [ "${FORCE_CLEANUP:-}" == "true" ]; then
            REMOVE_ENV="yes"
        else
            echo
            read -p "Remove deployment configuration file (.env)? [y/N]: " REMOVE_ENV
        fi
        
        if [[ "$REMOVE_ENV" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            rm -f "${SCRIPT_DIR}/.env"
            log_success "Configuration file removed"
        else
            log_info "Configuration file preserved"
        fi
    fi
    
    # Clean up old log files (keep only recent ones)
    log_info "Cleaning up old log files..."
    find "$SCRIPT_DIR" -name "deploy_*.log" -mtime +7 -delete 2>/dev/null || true
    find "$SCRIPT_DIR" -name "destroy_*.log" -mtime +7 -delete 2>/dev/null || true
    
    log_success "Local cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP still exists (deletion may be in progress)"
        log_info "You can check the deletion status with:"
        log_info "az group show --name $RESOURCE_GROUP"
    else
        log_success "Resource group $RESOURCE_GROUP has been deleted"
    fi
    
    # Check if project directory was removed
    PROJECT_DIR="${SCRIPT_DIR}/../weather-dashboard"
    if [ ! -d "$PROJECT_DIR" ]; then
        log_success "Project directory has been removed"
    else
        log_warning "Project directory still exists"
    fi
    
    log_success "Cleanup verification completed"
}

# Function to display cleanup summary
display_summary() {
    log_info "Cleanup Summary"
    echo "=========================================="
    echo
    echo "🧹 Weather Dashboard Cleanup Completed!"
    echo
    echo "Resources Processed:"
    echo "  - Resource Group: $RESOURCE_GROUP (deletion initiated)"
    if [ -n "${WEATHER_APP_NAME:-}" ]; then
        echo "  - Static Web App: $WEATHER_APP_NAME (deleted)"
    fi
    echo
    echo "Local Files:"
    echo "  - Project directory: Removed"
    echo "  - Log files: Old logs cleaned up"
    if [ -f "${SCRIPT_DIR}/.env" ]; then
        echo "  - Configuration: Preserved"
    else
        echo "  - Configuration: Removed"
    fi
    echo
    echo "⏳ Note: Resource deletion may take several minutes to complete"
    echo "   You can verify completion using: az group show --name $RESOURCE_GROUP"
    echo
    echo "💰 Cost Impact: All billable resources have been removed"
    echo
    echo "📋 Cleanup log saved to: $LOG_FILE"
    echo
    echo "=========================================="
}

# Function to handle errors during cleanup
handle_cleanup_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Cleanup encountered an error with exit code $exit_code"
        log_warning "Some resources may not have been fully cleaned up"
        log_warning "Please check the Azure portal to verify resource deletion"
        
        if [ -n "${RESOURCE_GROUP:-}" ]; then
            log_info "You can manually check and delete the resource group with:"
            log_info "az group delete --name $RESOURCE_GROUP --yes"
        fi
    fi
    exit $exit_code
}

# Display usage information
show_usage() {
    echo "Azure Weather Dashboard Cleanup Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --force    Skip confirmation prompts and force cleanup"
    echo "  --help     Show this help message"
    echo
    echo "Environment Variables:"
    echo "  FORCE_CLEANUP=true    Same as --force flag"
    echo
    echo "This script will:"
    echo "  1. Load deployment configuration"
    echo "  2. Delete Azure resources (Static Web App, Resource Group)"
    echo "  3. Clean up local project files"
    echo "  4. Remove old log files"
    echo
}

# Main cleanup function
main() {
    # Handle command line arguments
    case "${1:-}" in
        --help|-h)
            show_usage
            exit 0
            ;;
        --force|-f)
            FORCE_CLEANUP="true"
            ;;
    esac
    
    log_info "Starting Azure Weather Dashboard cleanup"
    
    # Set trap for error handling
    trap handle_cleanup_error EXIT
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_cleanup "${1:-}"
    delete_azure_resources
    cleanup_local_files "${1:-}"
    verify_cleanup
    display_summary
    
    # Remove trap on successful completion
    trap - EXIT
    
    log_success "Cleanup completed successfully at $(date)"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi