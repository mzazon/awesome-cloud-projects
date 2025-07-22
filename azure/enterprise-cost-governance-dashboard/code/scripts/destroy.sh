#!/bin/bash

# Azure Cost Governance Cleanup Script
# This script removes all resources created by the cost governance solution

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to discover resources
discover_resources() {
    log "Discovering resources to clean up..."
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Try to determine resource group name if not provided
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        log "Searching for cost governance resource groups..."
        
        # List resource groups with cost governance tags
        RESOURCE_GROUPS=$(az group list \
            --query "[?tags.purpose=='cost-governance'].name" \
            --output tsv)
        
        if [[ -n "${RESOURCE_GROUPS}" ]]; then
            log "Found cost governance resource groups:"
            echo "${RESOURCE_GROUPS}"
            
            # If multiple groups found, ask user to select
            if [[ $(echo "${RESOURCE_GROUPS}" | wc -l) -gt 1 ]]; then
                warning "Multiple cost governance resource groups found. Please specify one with --resource-group"
                exit 1
            else
                export RESOURCE_GROUP="${RESOURCE_GROUPS}"
                log "Using resource group: ${RESOURCE_GROUP}"
            fi
        else
            error "No cost governance resource groups found. Please specify with --resource-group"
            exit 1
        fi
    fi
    
    # Verify resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        error "Resource group '${RESOURCE_GROUP}' does not exist"
        exit 1
    fi
    
    success "Resource discovery completed"
}

# Function to display cleanup plan
display_cleanup_plan() {
    log "Cleanup Plan:"
    echo "============="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Subscription: ${SUBSCRIPTION_ID}"
    echo ""
    echo "Resources to be deleted:"
    
    # List all resources in the resource group
    az resource list \
        --resource-group "${RESOURCE_GROUP}" \
        --output table \
        --query "[].{Name:name, Type:type, Location:location}"
    
    echo ""
    warning "This will permanently delete all resources listed above!"
    echo ""
}

# Function to confirm cleanup
confirm_cleanup() {
    if [[ "${SKIP_CONFIRMATION}" != "true" ]]; then
        echo -e "${RED}⚠️  WARNING: This will permanently delete all resources in the resource group!${NC}"
        echo -e "${RED}⚠️  This action cannot be undone!${NC}"
        echo ""
        read -p "Are you sure you want to proceed? Type 'yes' to continue: " -r
        echo
        if [[ $REPLY != "yes" ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
        
        # Double confirmation for safety
        read -p "Please confirm again by typing 'DELETE': " -r
        echo
        if [[ $REPLY != "DELETE" ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
}

# Function to remove budget alerts
remove_budget_alerts() {
    log "Removing budget alerts..."
    
    # List and remove budget alerts
    BUDGETS=$(az consumption budget list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${BUDGETS}" ]]; then
        for budget in ${BUDGETS}; do
            log "Deleting budget: ${budget}"
            az consumption budget delete \
                --budget-name "${budget}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || warning "Failed to delete budget: ${budget}"
        done
        success "Budget alerts removed"
    else
        log "No budget alerts found to remove"
    fi
}

# Function to remove Logic App
remove_logic_app() {
    log "Removing Logic App workflows..."
    
    # List and remove Logic Apps
    LOGIC_APPS=$(az logic workflow list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${LOGIC_APPS}" ]]; then
        for logic_app in ${LOGIC_APPS}; do
            log "Deleting Logic App: ${logic_app}"
            az logic workflow delete \
                --name "${logic_app}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || warning "Failed to delete Logic App: ${logic_app}"
        done
        success "Logic Apps removed"
    else
        log "No Logic Apps found to remove"
    fi
}

# Function to remove Action Groups
remove_action_groups() {
    log "Removing Action Groups..."
    
    # List and remove Action Groups
    ACTION_GROUPS=$(az monitor action-group list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${ACTION_GROUPS}" ]]; then
        for action_group in ${ACTION_GROUPS}; do
            log "Deleting Action Group: ${action_group}"
            az monitor action-group delete \
                --name "${action_group}" \
                --resource-group "${RESOURCE_GROUP}" || warning "Failed to delete Action Group: ${action_group}"
        done
        success "Action Groups removed"
    else
        log "No Action Groups found to remove"
    fi
}

# Function to remove role assignments
remove_role_assignments() {
    log "Removing role assignments..."
    
    # Find and remove role assignments for resources in the resource group
    ROLE_ASSIGNMENTS=$(az role assignment list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].{id:id, principalId:principalId, roleDefinitionName:roleDefinitionName}" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${ROLE_ASSIGNMENTS}" ]]; then
        while IFS=$'\t' read -r assignment_id principal_id role_name; do
            if [[ -n "${assignment_id}" ]]; then
                log "Removing role assignment: ${role_name} for principal ${principal_id}"
                az role assignment delete \
                    --ids "${assignment_id}" || warning "Failed to remove role assignment: ${assignment_id}"
            fi
        done <<< "${ROLE_ASSIGNMENTS}"
        success "Role assignments removed"
    else
        log "No role assignments found to remove"
    fi
}

# Function to clean up storage account data
cleanup_storage_data() {
    log "Cleaning up storage account data..."
    
    # Find storage accounts in the resource group
    STORAGE_ACCOUNTS=$(az storage account list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${STORAGE_ACCOUNTS}" ]]; then
        for storage_account in ${STORAGE_ACCOUNTS}; do
            log "Cleaning up storage account: ${storage_account}"
            
            # Get storage account key
            STORAGE_KEY=$(az storage account keys list \
                --account-name "${storage_account}" \
                --resource-group "${RESOURCE_GROUP}" \
                --query '[0].value' \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -n "${STORAGE_KEY}" ]]; then
                # List and delete containers
                CONTAINERS=$(az storage container list \
                    --account-name "${storage_account}" \
                    --account-key "${STORAGE_KEY}" \
                    --query "[].name" \
                    --output tsv 2>/dev/null || echo "")
                
                if [[ -n "${CONTAINERS}" ]]; then
                    for container in ${CONTAINERS}; do
                        log "Deleting container: ${container}"
                        az storage container delete \
                            --name "${container}" \
                            --account-name "${storage_account}" \
                            --account-key "${STORAGE_KEY}" \
                            --yes || warning "Failed to delete container: ${container}"
                    done
                fi
            fi
        done
        success "Storage account data cleaned up"
    else
        log "No storage accounts found to clean up"
    fi
}

# Function to clean up Key Vault
cleanup_key_vault() {
    log "Cleaning up Key Vault..."
    
    # Find Key Vaults in the resource group
    KEY_VAULTS=$(az keyvault list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${KEY_VAULTS}" ]]; then
        for key_vault in ${KEY_VAULTS}; do
            log "Cleaning up Key Vault: ${key_vault}"
            
            # Delete all secrets
            SECRETS=$(az keyvault secret list \
                --vault-name "${key_vault}" \
                --query "[].name" \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -n "${SECRETS}" ]]; then
                for secret in ${SECRETS}; do
                    log "Deleting secret: ${secret}"
                    az keyvault secret delete \
                        --vault-name "${key_vault}" \
                        --name "${secret}" || warning "Failed to delete secret: ${secret}"
                done
            fi
        done
        success "Key Vault cleaned up"
    else
        log "No Key Vaults found to clean up"
    fi
}

# Function to remove resource group
remove_resource_group() {
    log "Removing resource group and all remaining resources..."
    
    # Delete the entire resource group
    if [[ "${DELETE_RESOURCE_GROUP}" == "true" ]]; then
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait
        
        success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        log "Complete deletion may take several minutes"
    else
        log "Skipping resource group deletion (use --delete-resource-group to remove)"
    fi
}

# Function to clean up local temporary files
cleanup_local_files() {
    log "Cleaning up local temporary files..."
    
    # Remove temporary files that might have been created
    local temp_files=(
        "/tmp/cost-analysis-query.kql"
        "/tmp/cost-analysis-results.json"
        "/tmp/tag-compliance-query.kql"
        "/tmp/tag-compliance-results.json"
        "/tmp/resource-inventory.json"
        "/tmp/resource-inventory.csv"
    )
    
    for temp_file in "${temp_files[@]}"; do
        if [[ -f "${temp_file}" ]]; then
            rm -f "${temp_file}"
            log "Deleted temporary file: ${temp_file}"
        fi
    done
    
    success "Local temporary files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        if [[ "${DELETE_RESOURCE_GROUP}" == "true" ]]; then
            warning "Resource group still exists but deletion is in progress"
        else
            # List remaining resources
            REMAINING_RESOURCES=$(az resource list \
                --resource-group "${RESOURCE_GROUP}" \
                --query "[].name" \
                --output tsv)
            
            if [[ -n "${REMAINING_RESOURCES}" ]]; then
                warning "Some resources may still exist:"
                echo "${REMAINING_RESOURCES}"
            else
                success "All resources have been successfully removed"
            fi
        fi
    else
        success "Resource group has been successfully deleted"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "================"
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Subscription: ${SUBSCRIPTION_ID}"
    echo ""
    echo "Cleanup actions performed:"
    echo "✅ Budget alerts removed"
    echo "✅ Logic Apps removed"
    echo "✅ Action Groups removed"
    echo "✅ Role assignments removed"
    echo "✅ Storage account data cleaned"
    echo "✅ Key Vault secrets cleaned"
    echo "✅ Local temporary files cleaned"
    
    if [[ "${DELETE_RESOURCE_GROUP}" == "true" ]]; then
        echo "✅ Resource group deletion initiated"
    else
        echo "⚠️  Resource group preserved (use --delete-resource-group to remove)"
    fi
    
    echo ""
    echo "Note: Resource deletion may take several minutes to complete."
    echo "Use 'az group show --name ${RESOURCE_GROUP}' to check if deletion is complete."
    echo ""
    success "Cleanup process completed!"
}

# Main cleanup function
main() {
    log "Starting Azure Cost Governance Solution Cleanup"
    
    # Check prerequisites
    check_prerequisites
    
    # Discover resources
    discover_resources
    
    # Display cleanup plan
    display_cleanup_plan
    
    # Confirm cleanup
    confirm_cleanup
    
    # Perform cleanup in proper order
    remove_budget_alerts
    remove_logic_app
    remove_action_groups
    remove_role_assignments
    cleanup_storage_data
    cleanup_key_vault
    remove_resource_group
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_cleanup_summary
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --delete-resource-group)
            DELETE_RESOURCE_GROUP="true"
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --resource-group NAME      Resource group name to clean up"
            echo "  --delete-resource-group    Delete the entire resource group"
            echo "  --skip-confirmation        Skip cleanup confirmation prompts"
            echo "  --help                     Show this help message"
            echo ""
            echo "Safety Notes:"
            echo "- This script will permanently delete resources"
            echo "- Resource group deletion removes ALL resources in the group"
            echo "- Use with caution in production environments"
            echo "- Always verify the resource group before running"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set default values
DELETE_RESOURCE_GROUP="${DELETE_RESOURCE_GROUP:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# Run main function
main "$@"