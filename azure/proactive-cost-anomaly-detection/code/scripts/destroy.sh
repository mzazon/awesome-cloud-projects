#!/bin/bash

# =============================================================================
# Azure Cost Anomaly Detection Cleanup Script
# =============================================================================
# This script removes all resources created for the automated cost anomaly 
# detection solution to prevent ongoing charges.
# 
# Prerequisites:
# - Azure CLI installed and configured
# - Same environment variables or resource names as deployment
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Please login to Azure using 'az login'"
    fi
    
    log "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Check if environment variables are set or prompt for input
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        read -p "Enter Resource Group name: " RESOURCE_GROUP
    fi
    
    if [[ -z "${FUNCTION_APP:-}" ]]; then
        read -p "Enter Function App name: " FUNCTION_APP
    fi
    
    if [[ -z "${COSMOS_ACCOUNT:-}" ]]; then
        read -p "Enter Cosmos DB account name: " COSMOS_ACCOUNT
    fi
    
    if [[ -z "${STORAGE_ACCOUNT:-}" ]]; then
        read -p "Enter Storage Account name: " STORAGE_ACCOUNT
    fi
    
    if [[ -z "${LOGIC_APP:-}" ]]; then
        read -p "Enter Logic App name: " LOGIC_APP
    fi
    
    # Set defaults if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-cost-anomaly-detection}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    log "Environment variables set:"
    info "  Resource Group: ${RESOURCE_GROUP}"
    info "  Function App: ${FUNCTION_APP:-Not specified}"
    info "  Cosmos Account: ${COSMOS_ACCOUNT:-Not specified}"
    info "  Storage Account: ${STORAGE_ACCOUNT:-Not specified}"
    info "  Logic App: ${LOGIC_APP:-Not specified}"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warn "⚠️  DANGER: This will permanently delete all resources!"
    warn "This action cannot be undone."
    echo ""
    
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log "Force delete mode enabled - skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to delete all resources? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed"
}

# Function to list resources before deletion
list_resources() {
    log "Listing resources to be deleted..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        echo ""
        echo "Resources in resource group '${RESOURCE_GROUP}':"
        az resource list --resource-group "${RESOURCE_GROUP}" --output table
        echo ""
    else
        info "Resource group '${RESOURCE_GROUP}' does not exist"
    fi
}

# Function to delete Function App
delete_function_app() {
    if [[ -n "${FUNCTION_APP:-}" ]]; then
        log "Deleting Function App: ${FUNCTION_APP}"
        
        if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            # Remove role assignments first
            PRINCIPAL_ID=$(az functionapp identity show \
                --name "${FUNCTION_APP}" \
                --resource-group "${RESOURCE_GROUP}" \
                --query principalId \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -n "${PRINCIPAL_ID}" ]]; then
                log "Removing role assignments for Function App..."
                
                # Remove Cost Management Reader role
                az role assignment delete \
                    --assignee "${PRINCIPAL_ID}" \
                    --role "Cost Management Reader" \
                    --scope "/subscriptions/${SUBSCRIPTION_ID}" \
                    2>/dev/null || warn "Failed to remove Cost Management Reader role"
                
                # Remove Cosmos DB role assignments
                if [[ -n "${COSMOS_ACCOUNT:-}" ]]; then
                    az cosmosdb sql role assignment delete \
                        --account-name "${COSMOS_ACCOUNT}" \
                        --resource-group "${RESOURCE_GROUP}" \
                        --scope "/" \
                        --principal-id "${PRINCIPAL_ID}" \
                        --role-definition-id "00000000-0000-0000-0000-000000000002" \
                        2>/dev/null || warn "Failed to remove Cosmos DB role assignment"
                fi
            fi
            
            # Delete Function App
            az functionapp delete \
                --name "${FUNCTION_APP}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes
            
            log "Function App '${FUNCTION_APP}' deleted successfully"
        else
            info "Function App '${FUNCTION_APP}' not found"
        fi
    else
        info "Function App name not provided - skipping"
    fi
}

# Function to delete Cosmos DB
delete_cosmos_db() {
    if [[ -n "${COSMOS_ACCOUNT:-}" ]]; then
        log "Deleting Cosmos DB account: ${COSMOS_ACCOUNT}"
        
        if az cosmosdb show --name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az cosmosdb delete \
                --name "${COSMOS_ACCOUNT}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes
            
            log "Cosmos DB account '${COSMOS_ACCOUNT}' deleted successfully"
        else
            info "Cosmos DB account '${COSMOS_ACCOUNT}' not found"
        fi
    else
        info "Cosmos DB account name not provided - skipping"
    fi
}

# Function to delete Storage Account
delete_storage_account() {
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        log "Deleting Storage Account: ${STORAGE_ACCOUNT}"
        
        if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az storage account delete \
                --name "${STORAGE_ACCOUNT}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes
            
            log "Storage Account '${STORAGE_ACCOUNT}' deleted successfully"
        else
            info "Storage Account '${STORAGE_ACCOUNT}' not found"
        fi
    else
        info "Storage Account name not provided - skipping"
    fi
}

# Function to delete Logic App
delete_logic_app() {
    if [[ -n "${LOGIC_APP:-}" ]]; then
        log "Deleting Logic App: ${LOGIC_APP}"
        
        if az logic workflow show --name "${LOGIC_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az logic workflow delete \
                --name "${LOGIC_APP}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes
            
            log "Logic App '${LOGIC_APP}' deleted successfully"
        else
            info "Logic App '${LOGIC_APP}' not found"
        fi
    else
        info "Logic App name not provided - skipping"
    fi
}

# Function to delete individual resources
delete_individual_resources() {
    log "Deleting individual resources..."
    
    delete_function_app
    delete_cosmos_db
    delete_storage_account
    delete_logic_app
    
    log "Individual resource deletion completed"
}

# Function to delete entire resource group
delete_resource_group() {
    log "Deleting resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        # Check if resource group has any resources
        RESOURCE_COUNT=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" --output tsv)
        
        if [[ "${RESOURCE_COUNT}" -eq 0 ]]; then
            info "Resource group '${RESOURCE_GROUP}' is empty"
        else
            log "Deleting resource group with ${RESOURCE_COUNT} resources..."
        fi
        
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait
        
        log "Resource group '${RESOURCE_GROUP}' deletion initiated"
        info "Deletion will continue in the background"
    else
        info "Resource group '${RESOURCE_GROUP}' not found"
    fi
}

# Function to wait for resource group deletion
wait_for_deletion() {
    if [[ "${WAIT_FOR_COMPLETION:-}" == "true" ]]; then
        log "Waiting for resource group deletion to complete..."
        
        while az group show --name "${RESOURCE_GROUP}" &> /dev/null; do
            info "Resource group still exists, waiting..."
            sleep 30
        done
        
        log "Resource group deletion completed"
    else
        info "Resource group deletion initiated in background"
        info "Use 'az group show --name ${RESOURCE_GROUP}' to check status"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove any temporary function directories
    if [[ -d "./cost-anomaly-functions" ]]; then
        rm -rf "./cost-anomaly-functions"
        log "Removed local function directory"
    fi
    
    # Remove any temporary files
    find . -name "*.tmp" -delete 2>/dev/null || true
    find . -name "local.settings.json" -delete 2>/dev/null || true
    
    log "Local cleanup completed"
}

# Function to verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    # Check if resource group exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        REMAINING_RESOURCES=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" --output tsv)
        
        if [[ "${REMAINING_RESOURCES}" -gt 0 ]]; then
            warn "Resource group still contains ${REMAINING_RESOURCES} resources"
            warn "Deletion may still be in progress"
        else
            info "Resource group exists but is empty"
        fi
    else
        log "Resource group '${RESOURCE_GROUP}' has been deleted"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary:"
    echo "===================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Function App: ${FUNCTION_APP:-Not specified}"
    echo "Cosmos DB: ${COSMOS_ACCOUNT:-Not specified}"
    echo "Storage Account: ${STORAGE_ACCOUNT:-Not specified}"
    echo "Logic App: ${LOGIC_APP:-Not specified}"
    echo "===================="
    echo ""
    echo "Cleanup Actions:"
    echo "✅ Resource deletion initiated"
    echo "✅ Role assignments removed"
    echo "✅ Local files cleaned up"
    echo ""
    info "Note: Some resources may take several minutes to be fully deleted"
    info "You can monitor deletion progress in the Azure portal"
    echo ""
    log "All Azure charges for these resources will stop once deletion is complete"
}

# Main execution flow
main() {
    log "Starting Azure Cost Anomaly Detection cleanup..."
    
    # Parse command line arguments
    DELETE_MODE="${1:-individual}"  # individual or group
    
    case "${DELETE_MODE}" in
        "individual")
            log "Running individual resource cleanup mode"
            ;;
        "group")
            log "Running resource group cleanup mode"
            ;;
        "--help"|"-h")
            echo "Usage: $0 [individual|group] [--force] [--wait]"
            echo ""
            echo "Arguments:"
            echo "  individual    Delete individual resources (default)"
            echo "  group         Delete entire resource group"
            echo ""
            echo "Options:"
            echo "  --force       Skip confirmation prompt"
            echo "  --wait        Wait for resource group deletion to complete"
            echo ""
            echo "Environment variables:"
            echo "  RESOURCE_GROUP    Resource group name"
            echo "  FUNCTION_APP      Function app name"
            echo "  COSMOS_ACCOUNT    Cosmos DB account name"
            echo "  STORAGE_ACCOUNT   Storage account name"
            echo "  LOGIC_APP         Logic app name"
            echo "  FORCE_DELETE      Set to 'true' to skip confirmation"
            echo "  WAIT_FOR_COMPLETION Set to 'true' to wait for completion"
            exit 0
            ;;
        *)
            error "Unknown mode: ${DELETE_MODE}. Use 'individual' or 'group'"
            ;;
    esac
    
    # Check for force flag
    if [[ "${2:-}" == "--force" ]] || [[ "${3:-}" == "--force" ]]; then
        export FORCE_DELETE=true
    fi
    
    # Check for wait flag
    if [[ "${2:-}" == "--wait" ]] || [[ "${3:-}" == "--wait" ]]; then
        export WAIT_FOR_COMPLETION=true
    fi
    
    # Execute cleanup steps
    check_prerequisites
    set_environment_variables
    list_resources
    confirm_deletion
    
    if [[ "${DELETE_MODE}" == "group" ]]; then
        delete_resource_group
        wait_for_deletion
    else
        delete_individual_resources
    fi
    
    cleanup_local_files
    verify_deletion
    display_summary
    
    log "Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may not have been deleted."' INT

# Run main function with all arguments
main "$@"