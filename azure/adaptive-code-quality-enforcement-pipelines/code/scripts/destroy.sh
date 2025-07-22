#!/bin/bash

# Destroy script for Adaptive Code Quality Enforcement with DevOps Extensions
# This script removes all resources created by the deploy script

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [[ -f .env ]]; then
        # Source the environment file
        source .env
        success "Environment variables loaded from .env file"
        
        log "Loaded configuration:"
        log "  Resource Group: ${RESOURCE_GROUP}"
        log "  DevOps Organization: ${DEVOPS_ORG}"
        log "  Project Name: ${PROJECT_NAME}"
        log "  Application Insights: ${APP_INSIGHTS_NAME}"
        log "  Logic App: ${LOGIC_APP_NAME}"
        log "  Storage Account: ${STORAGE_ACCOUNT}"
    else
        warning "Environment file .env not found. Using default values or prompting for input..."
        
        # Set default values or prompt for input
        export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-code-quality-pipeline}"
        export DEVOPS_ORG="${DEVOPS_ORG:-}"
        export PROJECT_NAME="${PROJECT_NAME:-quality-pipeline-demo}"
        
        # Prompt for DevOps organization if not set
        if [[ -z "${DEVOPS_ORG}" ]]; then
            read -p "Enter your Azure DevOps organization name: " DEVOPS_ORG
            export DEVOPS_ORG
        fi
        
        log "Using configuration:"
        log "  Resource Group: ${RESOURCE_GROUP}"
        log "  DevOps Organization: ${DEVOPS_ORG}"
        log "  Project Name: ${PROJECT_NAME}"
    fi
}

# Check prerequisites
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
    
    # Check if Azure DevOps extension is installed
    if ! az extension show --name azure-devops &> /dev/null; then
        warning "Azure DevOps extension not installed. Installing..."
        az extension add --name azure-devops
    fi
    
    # Configure Azure DevOps
    az devops configure --defaults organization=https://dev.azure.com/${DEVOPS_ORG}
    
    success "Prerequisites check completed"
}

# Confirmation prompt
confirm_destruction() {
    log "This operation will permanently delete the following resources:"
    log "  - Azure DevOps Project: ${PROJECT_NAME}"
    log "  - Azure Resource Group: ${RESOURCE_GROUP} (and all contained resources)"
    log "  - All pipelines, test plans, and associated data"
    
    echo ""
    warning "THIS ACTION CANNOT BE UNDONE!"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'DELETE' to confirm): " confirmation
    
    if [[ "${confirmation}" != "DELETE" ]]; then
        log "Operation cancelled by user."
        exit 0
    fi
    
    log "Destruction confirmed. Proceeding with cleanup..."
}

# Delete Azure DevOps pipelines
delete_pipelines() {
    log "Deleting Azure DevOps pipelines..."
    
    # List and delete pipelines
    PIPELINE_IDS=$(az pipelines list --project "${PROJECT_NAME}" --query "[].id" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${PIPELINE_IDS}" ]]; then
        for pipeline_id in $PIPELINE_IDS; do
            log "Deleting pipeline ID: ${pipeline_id}"
            az pipelines delete --id "${pipeline_id}" --project "${PROJECT_NAME}" --yes &> /dev/null || warning "Failed to delete pipeline ${pipeline_id}"
        done
        success "Pipelines deleted"
    else
        warning "No pipelines found to delete"
    fi
}

# Delete Azure DevOps test plans
delete_test_plans() {
    log "Deleting Azure DevOps test plans..."
    
    # Test plans deletion via REST API
    if [[ -n "${TEST_PLAN_ID:-}" ]]; then
        log "Deleting test plan ID: ${TEST_PLAN_ID}"
        az devops invoke \
            --area testplan \
            --resource testplans \
            --route-parameters project="${PROJECT_NAME}" planId="${TEST_PLAN_ID}" \
            --http-method DELETE &> /dev/null || warning "Failed to delete test plan ${TEST_PLAN_ID}"
        success "Test plan deleted"
    else
        warning "No test plan ID found in environment"
    fi
}

# Delete Azure DevOps dashboards
delete_dashboards() {
    log "Deleting Azure DevOps dashboards..."
    
    # Get dashboard IDs
    DASHBOARD_IDS=$(az devops invoke \
        --area dashboard \
        --resource dashboards \
        --route-parameters project="${PROJECT_NAME}" \
        --http-method GET \
        --query "value[?name=='Code Quality Dashboard'].id" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${DASHBOARD_IDS}" ]]; then
        for dashboard_id in $DASHBOARD_IDS; do
            log "Deleting dashboard ID: ${dashboard_id}"
            az devops invoke \
                --area dashboard \
                --resource dashboards \
                --route-parameters project="${PROJECT_NAME}" dashboardId="${dashboard_id}" \
                --http-method DELETE &> /dev/null || warning "Failed to delete dashboard ${dashboard_id}"
        done
        success "Dashboards deleted"
    else
        warning "No dashboards found to delete"
    fi
}

# Delete Azure DevOps project
delete_devops_project() {
    log "Deleting Azure DevOps project..."
    
    # Check if project exists
    if az devops project show --project "${PROJECT_NAME}" &> /dev/null; then
        log "Deleting project: ${PROJECT_NAME}"
        
        # Get project ID
        PROJECT_ID=$(az devops project show --project "${PROJECT_NAME}" --query id --output tsv)
        
        # Delete the project
        az devops project delete --id "${PROJECT_ID}" --yes &> /dev/null
        
        # Wait for deletion to complete
        log "Waiting for project deletion to complete..."
        sleep 30
        
        # Verify deletion
        if ! az devops project show --project "${PROJECT_NAME}" &> /dev/null; then
            success "Azure DevOps project deleted: ${PROJECT_NAME}"
        else
            warning "Project deletion may still be in progress"
        fi
    else
        warning "Azure DevOps project ${PROJECT_NAME} not found or already deleted"
    fi
}

# Delete Azure resources
delete_azure_resources() {
    log "Deleting Azure resources..."
    
    # Check if resource group exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log "Deleting resource group: ${RESOURCE_GROUP}"
        
        # List resources in the group before deletion
        log "Resources to be deleted:"
        az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" --output table || warning "Failed to list resources"
        
        # Delete the resource group and all contained resources
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait
        
        log "Resource group deletion initiated (running in background)"
        
        # Wait for deletion to complete (with timeout)
        log "Waiting for resource group deletion to complete..."
        TIMEOUT=300  # 5 minutes timeout
        ELAPSED=0
        
        while az group show --name "${RESOURCE_GROUP}" &> /dev/null; do
            if [[ $ELAPSED -ge $TIMEOUT ]]; then
                warning "Resource group deletion timeout reached. Deletion may still be in progress."
                break
            fi
            sleep 10
            ELAPSED=$((ELAPSED + 10))
            log "Still waiting for deletion... (${ELAPSED}s elapsed)"
        done
        
        if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            success "Resource group deleted: ${RESOURCE_GROUP}"
        else
            warning "Resource group may still be deleting in the background"
        fi
    else
        warning "Resource group ${RESOURCE_GROUP} not found or already deleted"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f .env ]]; then
        rm -f .env
        success "Environment file removed"
    fi
    
    # Remove any temporary files
    rm -f logic-app-definition.json
    rm -f azure-pipeline-quality.yml
    
    success "Local cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check if Azure DevOps project is deleted
    if ! az devops project show --project "${PROJECT_NAME}" &> /dev/null; then
        success "Azure DevOps project verified as deleted"
    else
        warning "Azure DevOps project may still exist"
    fi
    
    # Check if resource group is deleted
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        success "Resource group verified as deleted"
    else
        warning "Resource group may still exist or be in deletion process"
    fi
    
    log "Cleanup verification completed"
}

# Main destroy function
main() {
    log "Starting destruction of Intelligent Code Quality Pipeline..."
    
    load_environment
    check_prerequisites
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_pipelines
    delete_test_plans
    delete_dashboards
    delete_devops_project
    delete_azure_resources
    cleanup_local_files
    verify_cleanup
    
    success "Destruction completed successfully!"
    
    log "Cleanup Summary:"
    log "  ✅ Azure DevOps project removed"
    log "  ✅ Azure resource group removed"
    log "  ✅ Local files cleaned up"
    
    log "Notes:"
    log "  - Some resources may take additional time to fully delete"
    log "  - Check Azure portal to verify all resources are removed"
    log "  - Billing should stop once resources are fully deleted"
    
    warning "If you need to recreate the infrastructure, run the deploy script again"
}

# Handle script interruption
cleanup_on_exit() {
    log "Script interrupted. Cleaning up temporary files..."
    rm -f logic-app-definition.json
    rm -f azure-pipeline-quality.yml
    exit 1
}

# Set up signal handling
trap cleanup_on_exit INT TERM

# Run main function
main "$@"