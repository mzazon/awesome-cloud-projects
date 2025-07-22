#!/bin/bash

# Azure Static Web Apps and Container Apps Jobs CI/CD Testing Cleanup Script
# This script removes all resources created for the CI/CD testing workflow

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Verify Azure CLI version
    local az_version=$(az version --query '."azure-cli"' -o tsv)
    info "Azure CLI version: $az_version"
    
    log "Prerequisites check completed successfully"
}

# Function to get environment variables or use defaults
set_environment_variables() {
    log "Setting environment variables..."
    
    # Try to get RANDOM_SUFFIX from environment, otherwise prompt user
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        echo "Please provide the RANDOM_SUFFIX used during deployment"
        echo "You can find this in the deployment logs or resource names"
        read -p "Enter RANDOM_SUFFIX: " RANDOM_SUFFIX
        
        if [ -z "$RANDOM_SUFFIX" ]; then
            error "RANDOM_SUFFIX is required for cleanup"
            exit 1
        fi
    fi
    
    # Set resource names using the suffix
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-cicd-testing-${RANDOM_SUFFIX}}"
    export STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-cicd-demo-${RANDOM_SUFFIX}}"
    export CONTAINER_APPS_ENV="${CONTAINER_APPS_ENV:-cae-testing-${RANDOM_SUFFIX}}"
    export CONTAINER_REGISTRY="${CONTAINER_REGISTRY:-acr${RANDOM_SUFFIX}}"
    export TEST_JOB_NAME="${TEST_JOB_NAME:-test-runner-job}"
    export LOAD_TEST_JOB_NAME="${LOAD_TEST_JOB_NAME:-load-test-job}"
    export LOAD_TEST_RESOURCE="${LOAD_TEST_RESOURCE:-alt-cicd-${RANDOM_SUFFIX}}"
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-cicd-${RANDOM_SUFFIX}}"
    export APPLICATION_INSIGHTS="${APPLICATION_INSIGHTS:-ai-cicd-${RANDOM_SUFFIX}}"
    
    info "Environment variables set for cleanup:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Random Suffix: $RANDOM_SUFFIX"
    
    log "Environment variables configured successfully"
}

# Function to confirm cleanup
confirm_cleanup() {
    echo
    warn "This will DELETE ALL resources in the resource group: $RESOURCE_GROUP"
    warn "This action cannot be undone!"
    echo
    
    if [ "${FORCE_CLEANUP:-false}" = "true" ]; then
        warn "Force cleanup enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Cleanup confirmed, proceeding..."
}

# Function to list resources before cleanup
list_resources() {
    log "Listing resources to be deleted..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        info "Resources in $RESOURCE_GROUP:"
        az resource list --resource-group "$RESOURCE_GROUP" --output table
    else
        warn "Resource group $RESOURCE_GROUP does not exist"
        return 1
    fi
    
    return 0
}

# Function to delete Container Apps Jobs
delete_container_apps_jobs() {
    log "Deleting Container Apps Jobs..."
    
    # Delete integration test job
    if az containerapp job show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$TEST_JOB_NAME" &> /dev/null; then
        
        info "Deleting integration test job: $TEST_JOB_NAME"
        az containerapp job delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$TEST_JOB_NAME" \
            --yes
        
        log "Integration test job $TEST_JOB_NAME deleted successfully"
    else
        warn "Integration test job $TEST_JOB_NAME not found"
    fi
    
    # Delete load testing job
    if az containerapp job show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOAD_TEST_JOB_NAME" &> /dev/null; then
        
        info "Deleting load testing job: $LOAD_TEST_JOB_NAME"
        az containerapp job delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$LOAD_TEST_JOB_NAME" \
            --yes
        
        log "Load testing job $LOAD_TEST_JOB_NAME deleted successfully"
    else
        warn "Load testing job $LOAD_TEST_JOB_NAME not found"
    fi
}

# Function to delete Container Apps Environment
delete_container_apps_environment() {
    log "Deleting Container Apps Environment..."
    
    if az containerapp env show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CONTAINER_APPS_ENV" &> /dev/null; then
        
        info "Deleting Container Apps Environment: $CONTAINER_APPS_ENV"
        az containerapp env delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$CONTAINER_APPS_ENV" \
            --yes
        
        log "Container Apps Environment $CONTAINER_APPS_ENV deleted successfully"
    else
        warn "Container Apps Environment $CONTAINER_APPS_ENV not found"
    fi
}

# Function to delete Static Web App
delete_static_web_app() {
    log "Deleting Static Web App..."
    
    if az staticwebapp show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STATIC_WEB_APP_NAME" &> /dev/null; then
        
        info "Deleting Static Web App: $STATIC_WEB_APP_NAME"
        az staticwebapp delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$STATIC_WEB_APP_NAME" \
            --yes
        
        log "Static Web App $STATIC_WEB_APP_NAME deleted successfully"
    else
        warn "Static Web App $STATIC_WEB_APP_NAME not found"
    fi
}

# Function to delete Load Testing resource
delete_load_testing_resource() {
    log "Deleting Load Testing resource..."
    
    if az load show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOAD_TEST_RESOURCE" &> /dev/null; then
        
        info "Deleting Load Testing resource: $LOAD_TEST_RESOURCE"
        az load delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$LOAD_TEST_RESOURCE" \
            --yes
        
        log "Load Testing resource $LOAD_TEST_RESOURCE deleted successfully"
    else
        warn "Load Testing resource $LOAD_TEST_RESOURCE not found"
    fi
}

# Function to delete Application Insights
delete_application_insights() {
    log "Deleting Application Insights..."
    
    if az monitor app-insights component show \
        --resource-group "$RESOURCE_GROUP" \
        --app "$APPLICATION_INSIGHTS" &> /dev/null; then
        
        info "Deleting Application Insights: $APPLICATION_INSIGHTS"
        az monitor app-insights component delete \
            --resource-group "$RESOURCE_GROUP" \
            --app "$APPLICATION_INSIGHTS"
        
        log "Application Insights $APPLICATION_INSIGHTS deleted successfully"
    else
        warn "Application Insights $APPLICATION_INSIGHTS not found"
    fi
}

# Function to delete Log Analytics workspace
delete_log_analytics_workspace() {
    log "Deleting Log Analytics workspace..."
    
    if az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" &> /dev/null; then
        
        info "Deleting Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
        az monitor log-analytics workspace delete \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --yes
        
        log "Log Analytics workspace $LOG_ANALYTICS_WORKSPACE deleted successfully"
    else
        warn "Log Analytics workspace $LOG_ANALYTICS_WORKSPACE not found"
    fi
}

# Function to delete Container Registry
delete_container_registry() {
    log "Deleting Container Registry..."
    
    if az acr show --name "$CONTAINER_REGISTRY" &> /dev/null; then
        info "Deleting Container Registry: $CONTAINER_REGISTRY"
        az acr delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$CONTAINER_REGISTRY" \
            --yes
        
        log "Container Registry $CONTAINER_REGISTRY deleted successfully"
    else
        warn "Container Registry $CONTAINER_REGISTRY not found"
    fi
}

# Function to delete service principal
delete_service_principal() {
    log "Deleting service principal..."
    
    local sp_name="sp-${STATIC_WEB_APP_NAME}-testing"
    
    if az ad sp show --id "http://$sp_name" &> /dev/null; then
        info "Deleting service principal: $sp_name"
        az ad sp delete --id "http://$sp_name"
        
        log "Service principal $sp_name deleted successfully"
    else
        warn "Service principal $sp_name not found"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        info "Deleting resource group: $RESOURCE_GROUP"
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        
        log "Resource group $RESOURCE_GROUP deletion initiated"
        info "Deletion is running in the background and may take several minutes"
    else
        warn "Resource group $RESOURCE_GROUP not found"
    fi
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group $RESOURCE_GROUP still exists (deletion may be in progress)"
        info "You can check the status with: az group show --name $RESOURCE_GROUP"
    else
        log "Resource group $RESOURCE_GROUP successfully deleted"
    fi
    
    # Check if service principal still exists
    local sp_name="sp-${STATIC_WEB_APP_NAME}-testing"
    if az ad sp show --id "http://$sp_name" &> /dev/null; then
        warn "Service principal $sp_name still exists"
    else
        log "Service principal $sp_name successfully deleted"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup completed!"
    
    echo
    echo "=========================================="
    echo "CLEANUP SUMMARY"
    echo "=========================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo
    echo "Deleted Resources:"
    echo "  ✓ Container Apps Jobs"
    echo "  ✓ Container Apps Environment"
    echo "  ✓ Static Web App"
    echo "  ✓ Load Testing Resource"
    echo "  ✓ Application Insights"
    echo "  ✓ Log Analytics Workspace"
    echo "  ✓ Container Registry"
    echo "  ✓ Service Principal"
    echo "  ✓ Resource Group (deletion in progress)"
    echo "=========================================="
    echo
    
    info "All resources have been scheduled for deletion"
    info "Some resources may take additional time to be fully removed"
    info "You can verify completion with: az group show --name $RESOURCE_GROUP"
}

# Main cleanup function
main() {
    log "Starting Azure CI/CD Testing Workflow cleanup..."
    
    check_prerequisites
    set_environment_variables
    confirm_cleanup
    
    if list_resources; then
        delete_container_apps_jobs
        delete_container_apps_environment
        delete_static_web_app
        delete_load_testing_resource
        delete_application_insights
        delete_log_analytics_workspace
        delete_container_registry
        delete_service_principal
        delete_resource_group
        verify_cleanup
        display_cleanup_summary
    else
        warn "No resources found to delete"
    fi
    
    log "Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Cleanup interrupted"; exit 1' INT TERM

# Check for force cleanup flag
if [ "${1:-}" = "--force" ]; then
    export FORCE_CLEANUP=true
    shift
fi

# Run main function
main "$@"