#!/bin/bash

# Destroy script for Azure App Configuration and Key Vault recipe
# This script removes all resources created by the deploy.sh script

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}

if [[ "$DRY_RUN" == "true" ]]; then
    warning "Running in DRY RUN mode - no resources will be deleted"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    info "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: $cmd"
        return 0
    else
        eval "$cmd"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log "All prerequisites met ✅"
}

# Function to load configuration from deployment
load_configuration() {
    log "Loading deployment configuration..."
    
    # Check if configuration file exists
    if [[ ! -f ".deployment_config" ]]; then
        error "Configuration file .deployment_config not found!"
        error "This file is created by deploy.sh and contains resource names."
        error "Please ensure you're running this script from the same directory as deploy.sh"
        exit 1
    fi
    
    # Source the configuration file
    source .deployment_config
    
    # Verify required variables are set
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        error "RESOURCE_GROUP not found in configuration file"
        exit 1
    fi
    
    info "Configuration loaded from .deployment_config:"
    info "  Resource Group: ${RESOURCE_GROUP}"
    info "  App Configuration: ${APP_CONFIG_NAME:-not set}"
    info "  Key Vault: ${KEY_VAULT_NAME:-not set}"
    info "  Web App: ${WEB_APP_NAME:-not set}"
    info "  App Service Plan: ${APP_SERVICE_PLAN:-not set}"
    info "  Location: ${LOCATION:-not set}"
    
    log "Configuration loaded ✅"
}

# Function to confirm destruction
confirm_destruction() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    warning "This will permanently delete all resources in resource group: ${RESOURCE_GROUP}"
    warning "This action cannot be undone!"
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    warning "Final confirmation required. Type 'DELETE' to proceed:"
    read -p "Confirmation: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed by user ✅"
}

# Function to stop Web App
stop_web_app() {
    log "Stopping Web App..."
    
    if [[ -n "${WEB_APP_NAME:-}" ]]; then
        # Check if Web App exists
        if az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            execute_command "az webapp stop \
                --name ${WEB_APP_NAME} \
                --resource-group ${RESOURCE_GROUP}" \
                "Stopping Web App ${WEB_APP_NAME}"
            
            log "Web App stopped ✅"
        else
            warning "Web App ${WEB_APP_NAME} not found, skipping stop"
        fi
    else
        warning "WEB_APP_NAME not set, skipping Web App stop"
    fi
}

# Function to remove Web App and App Service Plan
remove_web_app() {
    log "Removing Web App and App Service Plan..."
    
    if [[ -n "${WEB_APP_NAME:-}" ]]; then
        # Check if Web App exists
        if az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            execute_command "az webapp delete \
                --name ${WEB_APP_NAME} \
                --resource-group ${RESOURCE_GROUP}" \
                "Deleting Web App ${WEB_APP_NAME}"
            
            log "Web App deleted ✅"
        else
            warning "Web App ${WEB_APP_NAME} not found, skipping deletion"
        fi
    else
        warning "WEB_APP_NAME not set, skipping Web App deletion"
    fi
    
    if [[ -n "${APP_SERVICE_PLAN:-}" ]]; then
        # Check if App Service Plan exists
        if az appservice plan show --name "$APP_SERVICE_PLAN" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            execute_command "az appservice plan delete \
                --name ${APP_SERVICE_PLAN} \
                --resource-group ${RESOURCE_GROUP} \
                --yes" \
                "Deleting App Service Plan ${APP_SERVICE_PLAN}"
            
            log "App Service Plan deleted ✅"
        else
            warning "App Service Plan ${APP_SERVICE_PLAN} not found, skipping deletion"
        fi
    else
        warning "APP_SERVICE_PLAN not set, skipping App Service Plan deletion"
    fi
}

# Function to remove Key Vault
remove_key_vault() {
    log "Removing Key Vault..."
    
    if [[ -n "${KEY_VAULT_NAME:-}" ]]; then
        # Check if Key Vault exists
        if az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            execute_command "az keyvault delete \
                --name ${KEY_VAULT_NAME} \
                --resource-group ${RESOURCE_GROUP}" \
                "Deleting Key Vault ${KEY_VAULT_NAME}"
            
            # Purge Key Vault to completely remove it (avoid soft-delete retention)
            if [[ "$DRY_RUN" != "true" ]]; then
                sleep 10  # Wait for delete to complete
                execute_command "az keyvault purge \
                    --name ${KEY_VAULT_NAME} \
                    --location ${LOCATION}" \
                    "Purging Key Vault ${KEY_VAULT_NAME}"
            fi
            
            log "Key Vault deleted and purged ✅"
        else
            warning "Key Vault ${KEY_VAULT_NAME} not found, skipping deletion"
        fi
    else
        warning "KEY_VAULT_NAME not set, skipping Key Vault deletion"
    fi
}

# Function to remove App Configuration
remove_app_configuration() {
    log "Removing App Configuration store..."
    
    if [[ -n "${APP_CONFIG_NAME:-}" ]]; then
        # Check if App Configuration exists
        if az appconfig show --name "$APP_CONFIG_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            execute_command "az appconfig delete \
                --name ${APP_CONFIG_NAME} \
                --resource-group ${RESOURCE_GROUP} \
                --yes" \
                "Deleting App Configuration store ${APP_CONFIG_NAME}"
            
            log "App Configuration store deleted ✅"
        else
            warning "App Configuration store ${APP_CONFIG_NAME} not found, skipping deletion"
        fi
    else
        warning "APP_CONFIG_NAME not set, skipping App Configuration deletion"
    fi
}

# Function to remove resource group
remove_resource_group() {
    log "Removing resource group..."
    
    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        execute_command "az group delete \
            --name ${RESOURCE_GROUP} \
            --yes \
            --no-wait" \
            "Deleting resource group ${RESOURCE_GROUP}"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            info "Resource group deletion initiated. This may take several minutes..."
            
            # Wait for resource group deletion to complete
            local max_wait=300  # 5 minutes maximum wait
            local wait_time=0
            
            while az group show --name "$RESOURCE_GROUP" &> /dev/null && [[ $wait_time -lt $max_wait ]]; do
                sleep 10
                wait_time=$((wait_time + 10))
                info "Still waiting for resource group deletion... (${wait_time}s)"
            done
            
            if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
                warning "Resource group deletion is taking longer than expected."
                warning "Please check the Azure portal for completion status."
            else
                log "Resource group deletion completed ✅"
            fi
        fi
    else
        warning "Resource group ${RESOURCE_GROUP} not found, skipping deletion"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment configuration file
    if [[ -f ".deployment_config" ]]; then
        execute_command "rm -f .deployment_config" \
            "Removing deployment configuration file"
    fi
    
    # Remove any temporary files that might have been created
    if [[ -f "app.zip" ]]; then
        execute_command "rm -f app.zip" \
            "Removing temporary application zip file"
    fi
    
    log "Local files cleaned up ✅"
}

# Function to validate destruction
validate_destruction() {
    log "Validating resource destruction..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Skipping validation in dry-run mode"
        return 0
    fi
    
    local resources_remaining=0
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group ${RESOURCE_GROUP} still exists"
        resources_remaining=$((resources_remaining + 1))
    fi
    
    # Check if App Configuration still exists
    if [[ -n "${APP_CONFIG_NAME:-}" ]] && az appconfig show --name "$APP_CONFIG_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null 2>&1; then
        warning "App Configuration store ${APP_CONFIG_NAME} still exists"
        resources_remaining=$((resources_remaining + 1))
    fi
    
    # Check if Key Vault still exists (accounting for soft-delete)
    if [[ -n "${KEY_VAULT_NAME:-}" ]] && az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null 2>&1; then
        warning "Key Vault ${KEY_VAULT_NAME} still exists"
        resources_remaining=$((resources_remaining + 1))
    fi
    
    # Check if Web App still exists
    if [[ -n "${WEB_APP_NAME:-}" ]] && az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null 2>&1; then
        warning "Web App ${WEB_APP_NAME} still exists"
        resources_remaining=$((resources_remaining + 1))
    fi
    
    if [[ $resources_remaining -eq 0 ]]; then
        log "All resources successfully destroyed ✅"
    else
        warning "Some resources may still be in the process of being deleted"
        warning "Please check the Azure portal for final confirmation"
    fi
}

# Function to display summary
display_summary() {
    log "=========================================================="
    log "Destruction Summary"
    log "=========================================================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN MODE - No resources were actually deleted"
        info "The following resources would have been deleted:"
    else
        info "The following resources have been deleted:"
    fi
    
    info "  Resource Group: ${RESOURCE_GROUP}"
    info "  App Configuration: ${APP_CONFIG_NAME:-not set}"
    info "  Key Vault: ${KEY_VAULT_NAME:-not set}"
    info "  Web App: ${WEB_APP_NAME:-not set}"
    info "  App Service Plan: ${APP_SERVICE_PLAN:-not set}"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        info ""
        info "Local configuration files have been cleaned up"
        info "All recipe resources have been successfully destroyed"
    fi
    
    log "=========================================================="
}

# Main destruction function
main() {
    log "Starting Azure App Configuration and Key Vault resource destruction..."
    log "=========================================================="
    
    check_prerequisites
    load_configuration
    confirm_destruction
    stop_web_app
    remove_web_app
    remove_key_vault
    remove_app_configuration
    remove_resource_group
    cleanup_local_files
    validate_destruction
    display_summary
    
    log "=========================================================="
    log "Resource destruction completed! 🗑️"
    log "=========================================================="
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be deleted without actually deleting"
            echo "  --help, -h   Show this help message"
            echo ""
            echo "This script removes all resources created by the deploy.sh script."
            echo "It reads configuration from the .deployment_config file."
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"