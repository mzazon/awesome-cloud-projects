#!/bin/bash

# Azure Key Vault and App Service Cleanup Script
# This script removes all resources created by the deployment script

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Check if environment file exists
    if [[ -f ".deploy_env" ]]; then
        source .deploy_env
        log_success "Environment variables loaded from .deploy_env"
        log_info "  Resource Group: ${RESOURCE_GROUP}"
        log_info "  Key Vault: ${KEY_VAULT_NAME}"
        log_info "  Web App: ${WEB_APP_NAME}"
    else
        log_warning "Environment file .deploy_env not found"
        log_info "Please provide resource group name manually:"
        read -p "Resource Group Name: " RESOURCE_GROUP
        
        if [[ -z "${RESOURCE_GROUP}" ]]; then
            log_error "Resource group name is required"
            exit 1
        fi
        
        export RESOURCE_GROUP
        log_info "Using resource group: ${RESOURCE_GROUP}"
    fi
    
    # Set subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    log_warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️ "
    log_warning "This will permanently delete the following resources:"
    log_warning "  - Resource Group: ${RESOURCE_GROUP}"
    log_warning "  - All contained resources (Key Vault, Web App, etc.)"
    echo ""
    log_warning "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [[ "${confirm}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Function to check if resource group exists
check_resource_group() {
    log_info "Checking if resource group exists..."
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group '${RESOURCE_GROUP}' does not exist"
        log_info "Nothing to clean up"
        return 1
    fi
    
    log_success "Resource group found: ${RESOURCE_GROUP}"
    return 0
}

# Function to list resources to be deleted
list_resources() {
    log_info "Listing resources to be deleted..."
    
    echo ""
    log_info "Resources in ${RESOURCE_GROUP}:"
    log_info "================================"
    
    # List all resources in the resource group
    az resource list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].{Name:name, Type:type, Location:location}" \
        --output table
    
    echo ""
}

# Function to delete individual resources (safer approach)
delete_resources_individually() {
    log_info "Deleting resources individually for safer cleanup..."
    
    # Delete Web App first (if exists)
    if [[ -n "${WEB_APP_NAME:-}" ]]; then
        if az webapp show --name "${WEB_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log_info "Deleting Web App: ${WEB_APP_NAME}"
            az webapp delete \
                --name "${WEB_APP_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --keep-empty-plan false \
                > /dev/null
            log_success "Web App deleted: ${WEB_APP_NAME}"
        else
            log_warning "Web App ${WEB_APP_NAME} not found"
        fi
    fi
    
    # Delete App Service Plan (if exists)
    if [[ -n "${APP_SERVICE_PLAN:-}" ]]; then
        if az appservice plan show --name "${APP_SERVICE_PLAN}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log_info "Deleting App Service Plan: ${APP_SERVICE_PLAN}"
            az appservice plan delete \
                --name "${APP_SERVICE_PLAN}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                > /dev/null
            log_success "App Service Plan deleted: ${APP_SERVICE_PLAN}"
        else
            log_warning "App Service Plan ${APP_SERVICE_PLAN} not found"
        fi
    fi
    
    # Delete Key Vault (if exists)
    if [[ -n "${KEY_VAULT_NAME:-}" ]]; then
        if az keyvault show --name "${KEY_VAULT_NAME}" &> /dev/null; then
            log_info "Deleting Key Vault: ${KEY_VAULT_NAME}"
            az keyvault delete \
                --name "${KEY_VAULT_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                > /dev/null
            
            # Purge the Key Vault to completely remove it
            log_info "Purging Key Vault to completely remove it..."
            az keyvault purge \
                --name "${KEY_VAULT_NAME}" \
                --location "${LOCATION:-eastus}" \
                > /dev/null 2>&1 || log_warning "Could not purge Key Vault (may require additional permissions)"
            
            log_success "Key Vault deleted: ${KEY_VAULT_NAME}"
        else
            log_warning "Key Vault ${KEY_VAULT_NAME} not found"
        fi
    fi
}

# Function to delete resource group
delete_resource_group() {
    log_info "Deleting resource group and all remaining resources..."
    
    # Delete the resource group (this will delete all contained resources)
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Note: Deletion may take several minutes to complete"
}

# Function to wait for deletion completion
wait_for_deletion() {
    log_info "Waiting for resource group deletion to complete..."
    
    local max_attempts=30
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        if ! az group exists --name "${RESOURCE_GROUP}" --output tsv | grep -q "true"; then
            log_success "Resource group deletion completed"
            return 0
        fi
        
        log_info "Attempt ${attempt}/${max_attempts}: Still deleting... (waiting 30 seconds)"
        sleep 30
        ((attempt++))
    done
    
    log_warning "Deletion is taking longer than expected. Check Azure portal for status."
    return 1
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f ".deploy_env" ]]; then
        rm -f .deploy_env
        log_success "Removed .deploy_env file"
    fi
    
    # Remove any temporary files
    if [[ -f "app.zip" ]]; then
        rm -f app.zip
        log_success "Removed app.zip file"
    fi
    
    if [[ -f "app.js" ]]; then
        rm -f app.js
        log_success "Removed app.js file"
    fi
    
    if [[ -f "package.json" ]]; then
        rm -f package.json
        log_success "Removed package.json file"
    fi
    
    log_success "Local files cleaned up"
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    if az group exists --name "${RESOURCE_GROUP}" --output tsv | grep -q "true"; then
        log_warning "Resource group still exists. Deletion may be in progress."
        log_info "Check Azure portal for current status: https://portal.azure.com"
        return 1
    else
        log_success "Resource group successfully deleted"
        return 0
    fi
}

# Function to display cleanup results
display_results() {
    echo ""
    log_success "Cleanup process completed!"
    echo ""
    log_info "Cleanup Summary:"
    log_info "==============="
    log_info "✅ Resource group deletion initiated/completed"
    log_info "✅ Local files cleaned up"
    echo ""
    log_info "What was cleaned up:"
    log_info "- Resource Group: ${RESOURCE_GROUP}"
    log_info "- Key Vault and all secrets"
    log_info "- Web App and App Service Plan"
    log_info "- Managed identities and role assignments"
    log_info "- Local deployment files"
    echo ""
    log_info "💡 Check Azure portal to confirm all resources are deleted:"
    log_info "   https://portal.azure.com"
}

# Function to handle cleanup failure
handle_cleanup_failure() {
    log_error "Cleanup process encountered errors"
    echo ""
    log_info "Manual cleanup may be required:"
    log_info "1. Go to Azure portal: https://portal.azure.com"
    log_info "2. Search for resource group: ${RESOURCE_GROUP}"
    log_info "3. Delete the resource group manually"
    log_info "4. Check for any remaining Key Vault in soft-deleted state"
    echo ""
    log_info "You can also retry this script or use individual Azure CLI commands"
}

# Main cleanup function
main() {
    log_info "Starting Azure Key Vault and App Service cleanup..."
    echo ""
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    
    # Only proceed if resource group exists
    if check_resource_group; then
        list_resources
        confirm_destruction
        delete_resources_individually
        delete_resource_group
        
        # Wait for deletion (optional, can be skipped)
        read -p "Wait for deletion to complete? (y/n): " wait_choice
        if [[ "${wait_choice}" =~ ^[Yy]$ ]]; then
            wait_for_deletion
        fi
        
        verify_deletion
    fi
    
    cleanup_local_files
    display_results
    
    log_success "All cleanup steps completed!"
}

# Function to handle individual resource cleanup (alternative mode)
cleanup_individual_resources() {
    log_info "Individual resource cleanup mode"
    echo ""
    
    # Allow user to specify individual resources to clean up
    log_info "Available cleanup options:"
    log_info "1. Delete specific Web App"
    log_info "2. Delete specific Key Vault"
    log_info "3. Delete specific Resource Group"
    log_info "4. Full cleanup (recommended)"
    echo ""
    
    read -p "Choose option (1-4): " choice
    
    case ${choice} in
        1)
            read -p "Web App name: " app_name
            read -p "Resource Group: " rg_name
            if az webapp show --name "${app_name}" --resource-group "${rg_name}" &> /dev/null; then
                az webapp delete --name "${app_name}" --resource-group "${rg_name}"
                log_success "Web App deleted: ${app_name}"
            else
                log_error "Web App not found: ${app_name}"
            fi
            ;;
        2)
            read -p "Key Vault name: " kv_name
            if az keyvault show --name "${kv_name}" &> /dev/null; then
                az keyvault delete --name "${kv_name}"
                az keyvault purge --name "${kv_name}" --location "eastus" || true
                log_success "Key Vault deleted: ${kv_name}"
            else
                log_error "Key Vault not found: ${kv_name}"
            fi
            ;;
        3)
            read -p "Resource Group name: " rg_name
            confirm_destruction
            az group delete --name "${rg_name}" --yes
            log_success "Resource Group deletion initiated: ${rg_name}"
            ;;
        4)
            main
            ;;
        *)
            log_error "Invalid option selected"
            exit 1
            ;;
    esac
}

# Script entry point with error handling
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check for individual cleanup mode
    if [[ "${1:-}" == "--individual" ]]; then
        cleanup_individual_resources
    else
        # Trap errors and provide helpful message
        trap 'handle_cleanup_failure' ERR
        
        main "$@"
    fi
fi