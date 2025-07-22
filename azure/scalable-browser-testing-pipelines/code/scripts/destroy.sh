#!/bin/bash

# Azure Playwright Testing Pipeline Cleanup Script
# This script removes all resources created for the Azure Playwright Testing solution

set -e  # Exit on any error

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

# Default values
DRY_RUN=false
FORCE=false
SKIP_CONFIRMATION=false
KEEP_RESOURCE_GROUP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --keep-resource-group)
            KEEP_RESOURCE_GROUP=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run             Show what would be deleted without making changes"
            echo "  --force               Force deletion of resources even if errors occur"
            echo "  --yes                 Skip confirmation prompts"
            echo "  --keep-resource-group Keep the resource group after cleanup"
            echo "  --help                Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    log "Prerequisites check passed"
}

# Load environment variables
load_environment_variables() {
    log "Loading environment variables..."
    
    # Try to load from existing deployment or use defaults
    export AZURE_REGION=${AZURE_REGION:-"eastus"}
    export RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-playwright-testing"}
    export DEVOPS_ORG=${DEVOPS_ORG:-"your-devops-org"}
    export PROJECT_NAME=${PROJECT_NAME:-"playwright-testing-project"}
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Try to discover existing resources
    discover_resources
    
    log "Environment variables loaded"
}

# Discover existing resources
discover_resources() {
    log "Discovering existing resources..."
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Resource group ${RESOURCE_GROUP} not found"
        return
    fi
    
    # Discover Playwright workspace
    PLAYWRIGHT_WORKSPACES=$(az playwright workspace list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [ -n "$PLAYWRIGHT_WORKSPACES" ]; then
        export PLAYWRIGHT_WORKSPACE=$(echo "$PLAYWRIGHT_WORKSPACES" | head -n1)
        log "Found Playwright workspace: ${PLAYWRIGHT_WORKSPACE}"
    fi
    
    # Discover Container Registry
    ACR_REGISTRIES=$(az acr list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [ -n "$ACR_REGISTRIES" ]; then
        export ACR_NAME=$(echo "$ACR_REGISTRIES" | head -n1)
        log "Found Container Registry: ${ACR_NAME}"
    fi
    
    # Check DevOps project
    if az devops project show --project "${PROJECT_NAME}" &> /dev/null 2>&1; then
        export PROJECT_ID=$(az devops project show --project "${PROJECT_NAME}" --query id --output tsv 2>/dev/null || echo "")
        log "Found DevOps project: ${PROJECT_NAME}"
    fi
    
    log "Resource discovery completed"
}

# Confirmation prompt
confirm_deletion() {
    if [ "$SKIP_CONFIRMATION" = true ]; then
        return
    fi
    
    echo ""
    warn "This will permanently delete the following resources:"
    echo "  - Resource Group: ${RESOURCE_GROUP}"
    if [ -n "$PLAYWRIGHT_WORKSPACE" ]; then
        echo "  - Playwright Workspace: ${PLAYWRIGHT_WORKSPACE}"
    fi
    if [ -n "$ACR_NAME" ]; then
        echo "  - Container Registry: ${ACR_NAME}"
    fi
    if [ -n "$PROJECT_ID" ]; then
        echo "  - DevOps Project: ${PROJECT_NAME}"
    fi
    echo "  - All associated data, configurations, and test results"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy]([Ee][Ss])?$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Delete Azure DevOps project
delete_devops_project() {
    if [ -z "$PROJECT_ID" ]; then
        log "No DevOps project found to delete"
        return
    fi
    
    log "Deleting Azure DevOps project..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete DevOps project ${PROJECT_NAME}"
        return
    fi
    
    # Install Azure DevOps CLI extension if not installed
    if ! az extension show --name azure-devops &> /dev/null; then
        log "Installing Azure DevOps CLI extension..."
        az extension add --name azure-devops
    fi
    
    # Configure Azure DevOps defaults
    az devops configure --defaults organization=https://dev.azure.com/${DEVOPS_ORG}
    
    # Delete the project
    if [ "$FORCE" = true ]; then
        az devops project delete --id "${PROJECT_ID}" --yes || warn "Failed to delete DevOps project"
    else
        az devops project delete --id "${PROJECT_ID}" --yes
    fi
    
    log "✅ DevOps project deleted: ${PROJECT_NAME}"
}

# Delete Playwright workspace
delete_playwright_workspace() {
    if [ -z "$PLAYWRIGHT_WORKSPACE" ]; then
        log "No Playwright workspace found to delete"
        return
    fi
    
    log "Deleting Playwright workspace..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete Playwright workspace ${PLAYWRIGHT_WORKSPACE}"
        return
    fi
    
    # Delete the workspace
    if [ "$FORCE" = true ]; then
        az playwright workspace delete \
            --name "${PLAYWRIGHT_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes || warn "Failed to delete Playwright workspace"
    else
        az playwright workspace delete \
            --name "${PLAYWRIGHT_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes
    fi
    
    log "✅ Playwright workspace deleted: ${PLAYWRIGHT_WORKSPACE}"
}

# Delete Container Registry
delete_container_registry() {
    if [ -z "$ACR_NAME" ]; then
        log "No Container Registry found to delete"
        return
    fi
    
    log "Deleting Container Registry..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete Container Registry ${ACR_NAME}"
        return
    fi
    
    # Delete the registry
    if [ "$FORCE" = true ]; then
        az acr delete \
            --name "${ACR_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes || warn "Failed to delete Container Registry"
    else
        az acr delete \
            --name "${ACR_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes
    fi
    
    log "✅ Container Registry deleted: ${ACR_NAME}"
}

# Delete additional resources
delete_additional_resources() {
    log "Cleaning up additional resources..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would clean up additional resources"
        return
    fi
    
    # List and delete any remaining resources in the resource group
    REMAINING_RESOURCES=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name,Type:type}" --output tsv 2>/dev/null || echo "")
    
    if [ -n "$REMAINING_RESOURCES" ]; then
        warn "Found additional resources in resource group:"
        echo "$REMAINING_RESOURCES"
        
        # Delete remaining resources
        az resource list --resource-group "${RESOURCE_GROUP}" --query "[].id" --output tsv | while read -r resource_id; do
            if [ -n "$resource_id" ]; then
                if [ "$FORCE" = true ]; then
                    az resource delete --ids "$resource_id" --verbose || warn "Failed to delete resource: $resource_id"
                else
                    az resource delete --ids "$resource_id" --verbose
                fi
            fi
        done
    fi
    
    log "Additional resources cleanup completed"
}

# Delete resource group
delete_resource_group() {
    if [ "$KEEP_RESOURCE_GROUP" = true ]; then
        log "Keeping resource group as requested"
        return
    fi
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log "Resource group ${RESOURCE_GROUP} does not exist"
        return
    fi
    
    log "Deleting resource group..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete resource group ${RESOURCE_GROUP}"
        return
    fi
    
    # Delete the resource group
    if [ "$FORCE" = true ]; then
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait || warn "Failed to delete resource group"
    else
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait
    fi
    
    log "✅ Resource group deletion initiated: ${RESOURCE_GROUP}"
    log "Note: Complete deletion may take several minutes"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would clean up local files"
        return
    fi
    
    # Remove test directory if it exists
    if [ -d "playwright-tests" ]; then
        warn "Removing local playwright-tests directory"
        rm -rf playwright-tests
        log "✅ Local playwright-tests directory removed"
    fi
    
    # Remove temporary files
    rm -f /tmp/acr-service-connection.json
    rm -f /tmp/playwright-*.tmp
    
    log "Local files cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would verify cleanup"
        return
    fi
    
    # Check if resource group still exists
    if [ "$KEEP_RESOURCE_GROUP" = false ]; then
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            warn "Resource group ${RESOURCE_GROUP} still exists (deletion may be in progress)"
        else
            log "✅ Resource group ${RESOURCE_GROUP} has been deleted"
        fi
    fi
    
    # Check DevOps project
    if [ -n "$PROJECT_ID" ]; then
        if az devops project show --project "${PROJECT_NAME}" &> /dev/null 2>&1; then
            warn "DevOps project ${PROJECT_NAME} still exists"
        else
            log "✅ DevOps project ${PROJECT_NAME} has been deleted"
        fi
    fi
    
    # Check for remaining resources
    if [ "$KEEP_RESOURCE_GROUP" = true ]; then
        REMAINING_RESOURCES=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
        if [ -n "$REMAINING_RESOURCES" ]; then
            warn "Some resources may still exist in resource group ${RESOURCE_GROUP}:"
            echo "$REMAINING_RESOURCES"
        else
            log "✅ All resources have been removed from resource group ${RESOURCE_GROUP}"
        fi
    fi
    
    log "Cleanup verification completed"
}

# Print cleanup summary
print_cleanup_summary() {
    log "Cleanup Summary:"
    echo "=================================="
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN MODE - No resources were actually deleted"
    else
        info "The following resources have been deleted:"
        
        if [ -n "$PLAYWRIGHT_WORKSPACE" ]; then
            info "✅ Playwright Workspace: ${PLAYWRIGHT_WORKSPACE}"
        fi
        
        if [ -n "$ACR_NAME" ]; then
            info "✅ Container Registry: ${ACR_NAME}"
        fi
        
        if [ -n "$PROJECT_ID" ]; then
            info "✅ DevOps Project: ${PROJECT_NAME}"
        fi
        
        if [ "$KEEP_RESOURCE_GROUP" = false ]; then
            info "✅ Resource Group: ${RESOURCE_GROUP} (deletion initiated)"
        fi
    fi
    
    echo "=================================="
    
    if [ "$DRY_RUN" = false ]; then
        log "Cleanup completed successfully!"
        info "All Azure Playwright Testing resources have been removed."
        info "You will no longer be charged for these resources."
    else
        log "Dry run completed successfully!"
        info "Run without --dry-run to actually delete the resources."
    fi
}

# Handle script interruption
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        error "Script interrupted or failed"
        warn "Some resources may not have been deleted"
        warn "Please check the Azure portal and run the script again if needed"
    fi
}

# Set trap for cleanup on exit
trap cleanup_on_exit EXIT

# Main execution
main() {
    log "Starting Azure Playwright Testing cleanup..."
    
    check_prerequisites
    load_environment_variables
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_devops_project
    delete_playwright_workspace
    delete_container_registry
    delete_additional_resources
    delete_resource_group
    cleanup_local_files
    verify_cleanup
    print_cleanup_summary
}

# Execute main function
main "$@"