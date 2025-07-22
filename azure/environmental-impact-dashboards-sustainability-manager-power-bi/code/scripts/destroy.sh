#!/bin/bash

# Azure Environmental Impact Dashboards Cleanup Script
# This script removes all Azure resources created for sustainability tracking

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
CONFIG_FILE="${SCRIPT_DIR}/deployment_config.env"

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

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed"
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error_exit "Not logged into Azure. Please run 'az login' first"
    fi
    
    success "Prerequisites check completed"
}

# Load deployment configuration
load_configuration() {
    info "Loading deployment configuration..."
    
    if [[ -f "${CONFIG_FILE}" ]]; then
        source "${CONFIG_FILE}"
        success "Configuration loaded from ${CONFIG_FILE}"
        log "Resource Group: ${RESOURCE_GROUP}"
    else
        warning "Configuration file not found. Using manual input..."
        read -p "Enter Resource Group name to delete: " RESOURCE_GROUP
        
        if [[ -z "${RESOURCE_GROUP}" ]]; then
            error_exit "Resource Group name is required"
        fi
        
        # Set other variables that might be needed
        export POWERBI_WORKSPACE="${POWERBI_WORKSPACE:-sustainability-workspace}"
        export LOGIC_APP="${LOGIC_APP:-la-sustainability-*}"
        export APP_INSIGHTS="${APP_INSIGHTS:-ai-sustainability-*}"
        export KEY_VAULT="${KEY_VAULT:-kv-sustain-*}"
        export DATA_FACTORY="${DATA_FACTORY:-adf-sustainability-*}"
        export FUNCTION_APP="${FUNCTION_APP:-func-sustainability-*}"
    fi
}

# Confirmation prompt
confirm_deletion() {
    echo ""
    echo -e "${RED}⚠️  WARNING: This will permanently delete all resources in the following resource group:${NC}"
    echo -e "${YELLOW}   Resource Group: ${RESOURCE_GROUP}${NC}"
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    
    read -p "Are you absolutely sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Last chance! Type the resource group name to confirm: " confirm_rg
    
    if [[ "${confirm_rg}" != "${RESOURCE_GROUP}" ]]; then
        error_exit "Resource group name doesn't match. Cleanup cancelled for safety."
    fi
    
    success "Deletion confirmed"
}

# Check if resource group exists
check_resource_group() {
    info "Checking if resource group exists..."
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Resource group ${RESOURCE_GROUP} does not exist"
        echo "Nothing to clean up."
        exit 0
    fi
    
    success "Resource group found: ${RESOURCE_GROUP}"
}

# Display Power BI cleanup instructions
powerbi_cleanup_instructions() {
    echo ""
    echo -e "${YELLOW}📋 Manual Cleanup Required for Power BI:${NC}"
    echo ""
    echo "1. Log into Power BI Service (https://app.powerbi.com)"
    echo "2. Navigate to the workspace: ${POWERBI_WORKSPACE}"
    echo "3. Delete all datasets and reports in the workspace"
    echo "4. Delete the workspace itself"
    echo ""
    echo -e "${BLUE}Note: Power BI workspace cleanup cannot be automated via Azure CLI${NC}"
    echo ""
}

# Remove Logic App
remove_logic_app() {
    if [[ -n "${LOGIC_APP:-}" ]]; then
        info "Removing Logic App: ${LOGIC_APP}..."
        
        if az logic workflow show --resource-group "${RESOURCE_GROUP}" --name "${LOGIC_APP}" &> /dev/null; then
            az logic workflow delete \
                --resource-group "${RESOURCE_GROUP}" \
                --name "${LOGIC_APP}" \
                --yes \
                || warning "Failed to delete Logic App ${LOGIC_APP}"
            
            success "Logic App deleted: ${LOGIC_APP}"
        else
            warning "Logic App ${LOGIC_APP} not found"
        fi
    fi
}

# Remove Application Insights
remove_application_insights() {
    if [[ -n "${APP_INSIGHTS:-}" ]]; then
        info "Removing Application Insights: ${APP_INSIGHTS}..."
        
        if az monitor app-insights component show --app "${APP_INSIGHTS}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az monitor app-insights component delete \
                --app "${APP_INSIGHTS}" \
                --resource-group "${RESOURCE_GROUP}" \
                || warning "Failed to delete Application Insights ${APP_INSIGHTS}"
            
            success "Application Insights deleted: ${APP_INSIGHTS}"
        else
            warning "Application Insights ${APP_INSIGHTS} not found"
        fi
    fi
}

# Remove monitoring alerts
remove_monitoring_alerts() {
    info "Removing monitoring alerts..."
    
    # List and delete all alert rules in the resource group
    alert_rules=$(az monitor metrics alert list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${alert_rules}" ]]; then
        for alert in ${alert_rules}; do
            info "Removing alert rule: ${alert}"
            az monitor metrics alert delete \
                --name "${alert}" \
                --resource-group "${RESOURCE_GROUP}" \
                || warning "Failed to delete alert rule ${alert}"
        done
        success "Monitoring alerts removed"
    else
        warning "No alert rules found"
    fi
}

# Remove Function App
remove_function_app() {
    if [[ -n "${FUNCTION_APP:-}" ]]; then
        info "Removing Function App: ${FUNCTION_APP}..."
        
        if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az functionapp delete \
                --name "${FUNCTION_APP}" \
                --resource-group "${RESOURCE_GROUP}" \
                || warning "Failed to delete Function App ${FUNCTION_APP}"
            
            success "Function App deleted: ${FUNCTION_APP}"
        else
            warning "Function App ${FUNCTION_APP} not found"
        fi
    fi
}

# Remove Key Vault (with purge protection)
remove_key_vault() {
    if [[ -n "${KEY_VAULT:-}" ]]; then
        info "Removing Key Vault: ${KEY_VAULT}..."
        
        if az keyvault show --name "${KEY_VAULT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            # Delete the Key Vault
            az keyvault delete \
                --name "${KEY_VAULT}" \
                --resource-group "${RESOURCE_GROUP}" \
                || warning "Failed to delete Key Vault ${KEY_VAULT}"
            
            # Purge the Key Vault (if soft-delete is enabled)
            sleep 10
            az keyvault purge \
                --name "${KEY_VAULT}" \
                --location "${LOCATION:-eastus}" \
                || warning "Failed to purge Key Vault ${KEY_VAULT} (may require manual purge)"
            
            success "Key Vault deleted and purged: ${KEY_VAULT}"
        else
            warning "Key Vault ${KEY_VAULT} not found"
        fi
    fi
}

# Remove Data Factory
remove_data_factory() {
    if [[ -n "${DATA_FACTORY:-}" ]]; then
        info "Removing Data Factory: ${DATA_FACTORY}..."
        
        if az datafactory show --resource-group "${RESOURCE_GROUP}" --name "${DATA_FACTORY}" &> /dev/null; then
            az datafactory delete \
                --name "${DATA_FACTORY}" \
                --resource-group "${RESOURCE_GROUP}" \
                || warning "Failed to delete Data Factory ${DATA_FACTORY}"
            
            success "Data Factory deleted: ${DATA_FACTORY}"
        else
            warning "Data Factory ${DATA_FACTORY} not found"
        fi
    fi
}

# Remove entire resource group
remove_resource_group() {
    info "Removing resource group and all remaining resources..."
    
    echo ""
    echo -e "${YELLOW}This will delete ALL resources in the resource group: ${RESOURCE_GROUP}${NC}"
    echo "Including any resources not created by this script."
    echo ""
    
    read -p "Continue with resource group deletion? (y/N): " confirm_final
    
    if [[ "${confirm_final}" =~ ^[Yy]$ ]]; then
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait \
            || error_exit "Failed to initiate resource group deletion"
        
        success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        info "Deletion may take several minutes to complete"
        
        # Optional: Wait for deletion to complete
        read -p "Wait for deletion to complete? This may take 10-15 minutes (y/N): " wait_confirm
        
        if [[ "${wait_confirm}" =~ ^[Yy]$ ]]; then
            info "Waiting for resource group deletion to complete..."
            
            while az group show --name "${RESOURCE_GROUP}" &> /dev/null; do
                echo -n "."
                sleep 30
            done
            
            echo ""
            success "Resource group completely deleted: ${RESOURCE_GROUP}"
        fi
    else
        warning "Resource group deletion cancelled. Some resources may remain."
    fi
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local configuration files..."
    
    if [[ -f "${CONFIG_FILE}" ]]; then
        read -p "Remove local configuration file? (y/N): " remove_config
        
        if [[ "${remove_config}" =~ ^[Yy]$ ]]; then
            rm -f "${CONFIG_FILE}"
            success "Configuration file removed"
        else
            warning "Configuration file retained: ${CONFIG_FILE}"
        fi
    fi
}

# Verify cleanup completion
verify_cleanup() {
    info "Verifying cleanup completion..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Resource group still exists. Deletion may be in progress."
        echo "You can check the status in the Azure Portal or by running:"
        echo "az group show --name ${RESOURCE_GROUP}"
    else
        success "Resource group successfully deleted"
    fi
}

# Main cleanup function
main() {
    echo -e "${RED}🗑️  Azure Environmental Impact Dashboard Cleanup${NC}"
    log "Starting cleanup process"
    
    check_prerequisites
    load_configuration
    confirm_deletion
    check_resource_group
    
    # Display manual cleanup instructions first
    powerbi_cleanup_instructions
    
    # Remove individual resources first (optional, for granular control)
    echo -e "${BLUE}Removing individual resources...${NC}"
    remove_logic_app
    remove_application_insights
    remove_monitoring_alerts
    remove_function_app
    remove_key_vault
    remove_data_factory
    
    # Remove entire resource group
    echo ""
    echo -e "${BLUE}Final cleanup: Resource Group deletion${NC}"
    remove_resource_group
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    echo ""
    echo -e "${GREEN}🎉 Cleanup process completed!${NC}"
    echo ""
    echo -e "${YELLOW}Remember to manually clean up:${NC}"
    echo "• Power BI workspace: ${POWERBI_WORKSPACE}"
    echo "• Microsoft Cloud for Sustainability configuration"
    echo "• Any external data source connections"
    echo ""
    echo -e "${BLUE}If you encounter any issues, check the Azure Portal for remaining resources.${NC}"
    
    log "Cleanup process completed"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi