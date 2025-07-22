#!/bin/bash

# Azure Financial Market Data Processing - Cleanup Script
# Recipe: High-Velocity Financial Analytics with Azure Data Explorer and Event Hubs
# Version: 1.1
# Last Updated: 2025-07-12

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load deployment info
load_deployment_info() {
    log "Loading deployment information..."
    
    if [[ -f .deployment_info ]]; then
        source .deployment_info
        log "Loaded deployment info from .deployment_info file"
    else
        warning "No .deployment_info file found. Please provide resource information manually."
        
        read -p "Enter Resource Group name: " RESOURCE_GROUP
        read -p "Enter ADX Cluster name: " ADX_CLUSTER_NAME
        read -p "Enter Event Hub Namespace: " EVENT_HUB_NAMESPACE
        read -p "Enter Function App name: " FUNCTION_APP_NAME
        read -p "Enter Storage Account name: " STORAGE_ACCOUNT_NAME
        read -p "Enter Event Grid Topic name: " EVENT_GRID_TOPIC
        read -p "Enter Random Suffix: " RANDOM_SUFFIX
        
        export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    fi
    
    # Display what will be deleted
    log "Resources to be deleted:"
    echo "  Resource Group: ${RESOURCE_GROUP}"
    echo "  ADX Cluster: ${ADX_CLUSTER_NAME}"
    echo "  Event Hub Namespace: ${EVENT_HUB_NAMESPACE}"
    echo "  Function App: ${FUNCTION_APP_NAME}"
    echo "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "  Event Grid Topic: ${EVENT_GRID_TOPIC}"
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        echo "  Log Analytics: law-market-data-${RANDOM_SUFFIX}"
        echo "  Application Insights: ${FUNCTION_APP_NAME}-insights"
    fi
    
    success "Deployment information loaded"
}

# Function to confirm deletion
confirm_deletion() {
    log "Confirming resource deletion..."
    
    warning "This will permanently delete ALL resources created by the deployment!"
    warning "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you sure you want to delete all resources? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource deletion..."
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="${3:-$RESOURCE_GROUP}"
    
    case "$resource_type" in
        "group")
            az group show --name "$resource_name" &> /dev/null
            ;;
        "kusto-cluster")
            az kusto cluster show --cluster-name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "eventhubs-namespace")
            az eventhubs namespace show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "functionapp")
            az functionapp show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "storage-account")
            az storage account show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "eventgrid-topic")
            az eventgrid topic show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "app-insights")
            az monitor app-insights component show --app "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "log-analytics")
            az monitor log-analytics workspace show --workspace-name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to delete Event Grid topic
delete_event_grid() {
    log "Deleting Event Grid topic..."
    
    if resource_exists "eventgrid-topic" "${EVENT_GRID_TOPIC}"; then
        az eventgrid topic delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${EVENT_GRID_TOPIC}" \
            --yes \
            --no-wait
        
        success "Event Grid topic deletion initiated: ${EVENT_GRID_TOPIC}"
    else
        warning "Event Grid topic not found or already deleted: ${EVENT_GRID_TOPIC}"
    fi
}

# Function to delete Function App
delete_function_app() {
    log "Deleting Function App..."
    
    if resource_exists "functionapp" "${FUNCTION_APP_NAME}"; then
        az functionapp delete \
            --name "${FUNCTION_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --no-wait
        
        success "Function App deletion initiated: ${FUNCTION_APP_NAME}"
    else
        warning "Function App not found or already deleted: ${FUNCTION_APP_NAME}"
    fi
}

# Function to delete Application Insights
delete_app_insights() {
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        log "Deleting Application Insights..."
        
        local insights_name="${FUNCTION_APP_NAME}-insights"
        if resource_exists "app-insights" "${insights_name}"; then
            az monitor app-insights component delete \
                --app "${insights_name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes
            
            success "Application Insights deleted: ${insights_name}"
        else
            warning "Application Insights not found or already deleted: ${insights_name}"
        fi
    fi
}

# Function to delete Log Analytics workspace
delete_log_analytics() {
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        log "Deleting Log Analytics workspace..."
        
        local law_name="law-market-data-${RANDOM_SUFFIX}"
        if resource_exists "log-analytics" "${law_name}"; then
            az monitor log-analytics workspace delete \
                --resource-group "${RESOURCE_GROUP}" \
                --workspace-name "${law_name}" \
                --yes \
                --force
            
            success "Log Analytics workspace deleted: ${law_name}"
        else
            warning "Log Analytics workspace not found or already deleted: ${law_name}"
        fi
    fi
}

# Function to delete Event Hubs namespace
delete_event_hubs() {
    log "Deleting Event Hubs namespace..."
    
    if resource_exists "eventhubs-namespace" "${EVENT_HUB_NAMESPACE}"; then
        az eventhubs namespace delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${EVENT_HUB_NAMESPACE}" \
            --no-wait
        
        success "Event Hubs namespace deletion initiated: ${EVENT_HUB_NAMESPACE}"
    else
        warning "Event Hubs namespace not found or already deleted: ${EVENT_HUB_NAMESPACE}"
    fi
}

# Function to delete Azure Data Explorer cluster
delete_adx_cluster() {
    log "Deleting Azure Data Explorer cluster (this may take 10-15 minutes)..."
    
    if resource_exists "kusto-cluster" "${ADX_CLUSTER_NAME}"; then
        az kusto cluster delete \
            --cluster-name "${ADX_CLUSTER_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --no-wait
        
        success "ADX cluster deletion initiated: ${ADX_CLUSTER_NAME}"
        warning "ADX cluster deletion is running in background and may take 10-15 minutes"
    else
        warning "ADX cluster not found or already deleted: ${ADX_CLUSTER_NAME}"
    fi
}

# Function to delete storage account
delete_storage_account() {
    log "Deleting storage account..."
    
    if resource_exists "storage-account" "${STORAGE_ACCOUNT_NAME}"; then
        az storage account delete \
            --name "${STORAGE_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes
        
        success "Storage account deleted: ${STORAGE_ACCOUNT_NAME}"
    else
        warning "Storage account not found or already deleted: ${STORAGE_ACCOUNT_NAME}"
    fi
}

# Function to wait for critical deletions
wait_for_deletions() {
    log "Waiting for critical resource deletions to complete..."
    
    local max_wait_time=300  # 5 minutes
    local wait_interval=30   # 30 seconds
    local elapsed_time=0
    
    while [[ $elapsed_time -lt $max_wait_time ]]; do
        local resources_remaining=0
        
        # Check if Function App still exists
        if resource_exists "functionapp" "${FUNCTION_APP_NAME}"; then
            resources_remaining=$((resources_remaining + 1))
        fi
        
        # Check if Event Hubs namespace still exists
        if resource_exists "eventhubs-namespace" "${EVENT_HUB_NAMESPACE}"; then
            resources_remaining=$((resources_remaining + 1))
        fi
        
        # Check if Event Grid topic still exists
        if resource_exists "eventgrid-topic" "${EVENT_GRID_TOPIC}"; then
            resources_remaining=$((resources_remaining + 1))
        fi
        
        if [[ $resources_remaining -eq 0 ]]; then
            success "Critical resources have been deleted"
            break
        fi
        
        log "Waiting for $resources_remaining resources to be deleted... (${elapsed_time}s elapsed)"
        sleep $wait_interval
        elapsed_time=$((elapsed_time + wait_interval))
    done
    
    if [[ $elapsed_time -ge $max_wait_time ]]; then
        warning "Some resources may still be deleting. Check Azure portal for status."
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group and all remaining resources..."
    
    if resource_exists "group" "${RESOURCE_GROUP}"; then
        # Final confirmation for resource group deletion
        warning "This will delete the entire resource group: ${RESOURCE_GROUP}"
        read -p "Continue with resource group deletion? (yes/no): " final_confirm
        
        if [[ "$final_confirm" == "yes" ]]; then
            az group delete \
                --name "${RESOURCE_GROUP}" \
                --yes \
                --no-wait
            
            success "Resource group deletion initiated: ${RESOURCE_GROUP}"
            log "Resource group deletion is running in background"
        else
            warning "Resource group deletion cancelled"
            warning "Individual resources have been deleted, but resource group remains"
        fi
    else
        warning "Resource group not found or already deleted: ${RESOURCE_GROUP}"
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment info file
    if [[ -f .deployment_info ]]; then
        rm -f .deployment_info
        success "Removed .deployment_info file"
    fi
    
    # Remove KQL schema file if it exists
    if [[ -f market_data_schema.kql ]]; then
        rm -f market_data_schema.kql
        success "Removed market_data_schema.kql file"
    fi
    
    success "Local files cleaned up"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "===================="
    echo "The following resources have been deleted or deletion initiated:"
    echo "✅ Event Grid Topic: ${EVENT_GRID_TOPIC}"
    echo "✅ Function App: ${FUNCTION_APP_NAME}"
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        echo "✅ Application Insights: ${FUNCTION_APP_NAME}-insights"
        echo "✅ Log Analytics Workspace: law-market-data-${RANDOM_SUFFIX}"
    fi
    echo "✅ Event Hubs Namespace: ${EVENT_HUB_NAMESPACE}"
    echo "✅ Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "🔄 ADX Cluster: ${ADX_CLUSTER_NAME} (may still be deleting)"
    echo "🔄 Resource Group: ${RESOURCE_GROUP} (if confirmed)"
    echo ""
    warning "Note: Some resources (especially ADX cluster) may take additional time to fully delete"
    warning "Check the Azure portal to confirm all resources have been removed"
    echo ""
    success "Cleanup process completed!"
}

# Function to verify Azure subscription
verify_subscription() {
    log "Verifying Azure subscription..."
    
    local current_sub=$(az account show --query id --output tsv)
    
    if [[ -n "${SUBSCRIPTION_ID:-}" && "$current_sub" != "$SUBSCRIPTION_ID" ]]; then
        warning "Current subscription ($current_sub) differs from deployment subscription (${SUBSCRIPTION_ID})"
        read -p "Continue with cleanup in current subscription? (yes/no): " sub_confirm
        
        if [[ "$sub_confirm" != "yes" ]]; then
            error "Cleanup cancelled due to subscription mismatch"
            exit 1
        fi
    fi
    
    success "Subscription verified: $current_sub"
}

# Main cleanup function
main() {
    log "Starting Azure Financial Market Data Processing cleanup..."
    
    check_prerequisites
    load_deployment_info
    verify_subscription
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_event_grid
    delete_function_app
    delete_app_insights
    delete_log_analytics
    delete_event_hubs
    delete_adx_cluster
    delete_storage_account
    
    # Wait for critical deletions to complete
    wait_for_deletions
    
    # Delete resource group (optional)
    delete_resource_group
    
    # Cleanup local files
    cleanup_local_files
    
    # Display summary
    display_cleanup_summary
}

# Error handling
trap 'error "Cleanup failed at line $LINENO. Some resources may still exist."' ERR

# Run main function
main "$@"