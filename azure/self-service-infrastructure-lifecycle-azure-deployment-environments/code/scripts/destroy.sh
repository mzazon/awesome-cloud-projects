#!/bin/bash

# Azure Deployment Environments - Self-Service Infrastructure Lifecycle Management
# Destroy script for cleaning up infrastructure deployed with Azure Deployment Environments and Azure Developer CLI
# Recipe: self-service-infrastructure-lifecycle-azure-deployment-environments

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
handle_error() {
    log_error "Cleanup failed on line $1"
    log_error "Command: $2"
    log_warning "Some resources may not have been cleaned up properly"
    log_warning "Please check the Azure portal for any remaining resources"
    exit 1
}

trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

# Print banner
echo -e "${RED}"
echo "============================================================================="
echo "   Azure Deployment Environments - Self-Service Infrastructure Cleanup"
echo "============================================================================="
echo -e "${NC}"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if Azure Developer CLI is installed
    if ! command -v azd &> /dev/null; then
        log_error "Azure Developer CLI is not installed. Please install it from https://docs.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to check Azure authentication
check_azure_auth() {
    log "Checking Azure authentication..."
    
    if ! az account show &> /dev/null; then
        log_error "Not authenticated to Azure. Please run 'az login' first."
        exit 1
    fi
    
    local account_name=$(az account show --query name -o tsv)
    local subscription_id=$(az account show --query id -o tsv)
    
    log_success "Authenticated to Azure"
    log "Account: $account_name"
    log "Subscription ID: $subscription_id"
    
    export SUBSCRIPTION_ID=$subscription_id
}

# Function to discover existing resources
discover_resources() {
    log "Discovering existing Azure Deployment Environments resources..."
    
    # Look for resource groups that match our naming pattern
    local resource_groups=$(az group list --query "[?starts_with(name, 'rg-devcenter-')].name" -o tsv)
    
    if [[ -z "$resource_groups" ]]; then
        log_warning "No Azure Deployment Environments resource groups found matching pattern 'rg-devcenter-*'"
        echo
        log "Available resource groups:"
        az group list --query "[].name" -o tsv | sed 's/^/  - /'
        echo
        read -p "Enter the resource group name to clean up (or press Enter to exit): " RESOURCE_GROUP
        
        if [[ -z "$RESOURCE_GROUP" ]]; then
            log "Exiting cleanup process"
            exit 0
        fi
    else
        echo
        log "Found the following Azure Deployment Environments resource groups:"
        echo "$resource_groups" | sed 's/^/  - /'
        echo
        
        if [[ $(echo "$resource_groups" | wc -l) -eq 1 ]]; then
            RESOURCE_GROUP=$(echo "$resource_groups" | head -1)
            log "Using resource group: $RESOURCE_GROUP"
        else
            log "Multiple resource groups found. Please select one:"
            select RESOURCE_GROUP in $resource_groups "Exit"; do
                if [[ "$RESOURCE_GROUP" == "Exit" ]]; then
                    log "Exiting cleanup process"
                    exit 0
                elif [[ -n "$RESOURCE_GROUP" ]]; then
                    log "Selected resource group: $RESOURCE_GROUP"
                    break
                else
                    log_warning "Invalid selection. Please try again."
                fi
            done
        fi
    fi
    
    export RESOURCE_GROUP
    
    # Discover resources in the selected resource group
    log "Discovering resources in resource group: $RESOURCE_GROUP"
    
    # Get DevCenter details
    local devcenter_name=$(az devcenter admin devcenter list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$devcenter_name" ]]; then
        export DEVCENTER_NAME="$devcenter_name"
        log "Found DevCenter: $DEVCENTER_NAME"
        
        # Get project details
        local project_name=$(az devcenter admin project list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[0].name" -o tsv 2>/dev/null || echo "")
        
        if [[ -n "$project_name" ]]; then
            export PROJECT_NAME="$project_name"
            log "Found Project: $PROJECT_NAME"
        fi
    fi
    
    # Get storage account details
    local storage_account=$(az storage account list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?starts_with(name, 'st') && ends_with(name, 'templates')].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$storage_account" ]]; then
        export STORAGE_ACCOUNT="$storage_account"
        log "Found Storage Account: $STORAGE_ACCOUNT"
    fi
    
    log_success "Resource discovery completed"
}

# Function to confirm cleanup
confirm_cleanup() {
    echo
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo
    echo "This script will permanently delete the following resources:"
    echo "  - Resource Group: ${RESOURCE_GROUP}"
    
    if [[ -n "${DEVCENTER_NAME:-}" ]]; then
        echo "  - DevCenter: ${DEVCENTER_NAME}"
    fi
    
    if [[ -n "${PROJECT_NAME:-}" ]]; then
        echo "  - Project: ${PROJECT_NAME}"
    fi
    
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        echo "  - Storage Account: ${STORAGE_ACCOUNT}"
    fi
    
    echo "  - All deployed environments and associated resources"
    echo "  - All infrastructure templates and configurations"
    echo "  - All RBAC assignments and permissions"
    echo
    echo "This action cannot be undone!"
    echo
    
    read -p "Are you absolutely sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log_success "Cleanup confirmed by user"
}

# Function to clean up deployed environments
cleanup_environments() {
    log "Cleaning up deployed environments..."
    
    if [[ -n "${DEVCENTER_NAME:-}" && -n "${PROJECT_NAME:-}" ]]; then
        # Get DevCenter endpoint
        local devcenter_location=$(az devcenter admin devcenter show \
            --name "$DEVCENTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query "location" -o tsv 2>/dev/null || echo "")
        
        if [[ -n "$devcenter_location" ]]; then
            local endpoint="https://${DEVCENTER_NAME}-${devcenter_location}.devcenter.azure.com/"
            
            # List all environments in the project
            local environments=$(az devcenter dev environment list \
                --project-name "$PROJECT_NAME" \
                --endpoint "$endpoint" \
                --query "[].name" -o tsv 2>/dev/null || echo "")
            
            if [[ -n "$environments" ]]; then
                log "Found environments to clean up:"
                echo "$environments" | sed 's/^/  - /'
                
                # Delete each environment
                while IFS= read -r env_name; do
                    if [[ -n "$env_name" ]]; then
                        log "Deleting environment: $env_name"
                        az devcenter dev environment delete \
                            --project-name "$PROJECT_NAME" \
                            --endpoint "$endpoint" \
                            --environment-name "$env_name" \
                            --yes 2>/dev/null || log_warning "Failed to delete environment: $env_name"
                    fi
                done <<< "$environments"
                
                # Wait for environments to be deleted
                log "Waiting for environments to be fully deleted..."
                sleep 60
                
                log_success "Environments cleanup completed"
            else
                log "No environments found to clean up"
            fi
        else
            log_warning "Could not determine DevCenter location for environment cleanup"
        fi
    else
        log "No DevCenter or Project found for environment cleanup"
    fi
}

# Function to reset Azure Developer CLI configuration
reset_azd_config() {
    log "Resetting Azure Developer CLI configuration..."
    
    # Reset azd configuration
    azd config unset platform.type 2>/dev/null || true
    
    # Clean up local azd environment and sample application
    if [[ -d "webapp-sample" ]]; then
        log "Removing local webapp-sample directory..."
        rm -rf webapp-sample
    fi
    
    log_success "Azure Developer CLI configuration reset"
}

# Function to delete DevCenter project
delete_project() {
    log "Deleting DevCenter project..."
    
    if [[ -n "${PROJECT_NAME:-}" && -n "${DEVCENTER_NAME:-}" ]]; then
        # Check if project exists
        if az devcenter admin project show \
            --name "$PROJECT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query "name" -o tsv &>/dev/null; then
            
            log "Deleting project: $PROJECT_NAME"
            az devcenter admin project delete \
                --name "$PROJECT_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
            
            log_success "Project deleted: $PROJECT_NAME"
        else
            log "Project not found or already deleted: $PROJECT_NAME"
        fi
    else
        log "No project found to delete"
    fi
}

# Function to delete DevCenter
delete_devcenter() {
    log "Deleting DevCenter..."
    
    if [[ -n "${DEVCENTER_NAME:-}" ]]; then
        # Check if DevCenter exists
        if az devcenter admin devcenter show \
            --name "$DEVCENTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query "name" -o tsv &>/dev/null; then
            
            log "Deleting DevCenter: $DEVCENTER_NAME"
            az devcenter admin devcenter delete \
                --name "$DEVCENTER_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
            
            log_success "DevCenter deleted: $DEVCENTER_NAME"
        else
            log "DevCenter not found or already deleted: $DEVCENTER_NAME"
        fi
    else
        log "No DevCenter found to delete"
    fi
}

# Function to delete storage account
delete_storage_account() {
    log "Deleting storage account..."
    
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        # Check if storage account exists
        if az storage account show \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --query "name" -o tsv &>/dev/null; then
            
            log "Deleting storage account: $STORAGE_ACCOUNT"
            az storage account delete \
                --name "$STORAGE_ACCOUNT" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
            
            log_success "Storage account deleted: $STORAGE_ACCOUNT"
        else
            log "Storage account not found or already deleted: $STORAGE_ACCOUNT"
        fi
    else
        log "No storage account found to delete"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group and all remaining resources..."
    
    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" --query "name" -o tsv &>/dev/null; then
        log "Deleting resource group: $RESOURCE_GROUP"
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        
        log_success "Resource group deletion initiated: $RESOURCE_GROUP"
        log "Note: Resource group deletion is running asynchronously"
    else
        log "Resource group not found or already deleted: $RESOURCE_GROUP"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" --query "name" -o tsv &>/dev/null; then
        log_warning "Resource group still exists (deletion may be in progress): $RESOURCE_GROUP"
        
        # Check resource group status
        local provisioning_state=$(az group show --name "$RESOURCE_GROUP" --query "properties.provisioningState" -o tsv 2>/dev/null || echo "")
        if [[ "$provisioning_state" == "Deleting" ]]; then
            log "Resource group is being deleted: $RESOURCE_GROUP"
        else
            log_warning "Resource group status: $provisioning_state"
        fi
    else
        log_success "Resource group successfully deleted: $RESOURCE_GROUP"
    fi
    
    # Clean up any remaining local files
    if [[ -f "webapp-template.json" ]]; then
        rm -f webapp-template.json
        log "Cleaned up local template file"
    fi
    
    log_success "Cleanup verification completed"
}

# Function to display cleanup summary
display_summary() {
    echo
    echo -e "${GREEN}============================================================================="
    echo "                          CLEANUP SUMMARY"
    echo "=============================================================================${NC}"
    echo
    echo "Resource Group: ${RESOURCE_GROUP}"
    
    if [[ -n "${DEVCENTER_NAME:-}" ]]; then
        echo "DevCenter: ${DEVCENTER_NAME}"
    fi
    
    if [[ -n "${PROJECT_NAME:-}" ]]; then
        echo "Project: ${PROJECT_NAME}"
    fi
    
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        echo "Storage Account: ${STORAGE_ACCOUNT}"
    fi
    
    echo
    echo "Cleanup Actions Completed:"
    echo "  ✅ Deployed environments deleted"
    echo "  ✅ Azure Developer CLI configuration reset"
    echo "  ✅ DevCenter project deleted"
    echo "  ✅ DevCenter deleted"
    echo "  ✅ Storage account deleted"
    echo "  ✅ Resource group deletion initiated"
    echo "  ✅ Local files cleaned up"
    echo
    echo "Important Notes:"
    echo "  - Resource group deletion runs asynchronously"
    echo "  - Check the Azure portal to confirm complete deletion"
    echo "  - All RBAC assignments are automatically removed with resource deletion"
    echo "  - All environment templates and configurations have been deleted"
    echo
    echo "To verify complete cleanup, run:"
    echo "  az group exists --name ${RESOURCE_GROUP}"
    echo "  (Should return 'false' when deletion is complete)"
    echo
    echo -e "${GREEN}=============================================================================${NC}"
}

# Main execution
main() {
    check_prerequisites
    check_azure_auth
    discover_resources
    confirm_cleanup
    cleanup_environments
    reset_azd_config
    delete_project
    delete_devcenter
    delete_storage_account
    delete_resource_group
    verify_cleanup
    display_summary
}

# Run main function
main "$@"