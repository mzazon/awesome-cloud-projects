#!/bin/bash

# Destroy script for Microservices Choreography with Service Bus and Observability
# This script removes all Azure resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DRY_RUN=${DRY_RUN:-false}

# Function to log messages
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Function to log info messages
log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

# Function to log success messages
log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

# Function to log warning messages
log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

# Function to log error messages
log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Check if .env file exists
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        log_info "Loading variables from .env file..."
        source "${SCRIPT_DIR}/.env"
    else
        log_warning ".env file not found. Using default values or environment variables."
        
        # Set default values if not provided
        export RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-microservices-choreography"}
        export LOCATION=${LOCATION:-"eastus"}
        export SUBSCRIPTION_ID=${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}
        
        # Generate default names (these might not match the actual deployed resources)
        RANDOM_SUFFIX=${RANDOM_SUFFIX:-"default"}
        export NAMESPACE_NAME=${NAMESPACE_NAME:-"sb-choreography-${RANDOM_SUFFIX}"}
        export WORKSPACE_NAME=${WORKSPACE_NAME:-"log-choreography-${RANDOM_SUFFIX}"}
        export APPINSIGHTS_NAME=${APPINSIGHTS_NAME:-"ai-choreography-${RANDOM_SUFFIX}"}
        export CONTAINER_ENV_NAME=${CONTAINER_ENV_NAME:-"cae-choreography-${RANDOM_SUFFIX}"}
        export STORAGE_ACCOUNT=${STORAGE_ACCOUNT:-"stfunc${RANDOM_SUFFIX}"}
        export PAYMENT_FUNCTION_NAME=${PAYMENT_FUNCTION_NAME:-"payment-service-${RANDOM_SUFFIX}"}
        export SHIPPING_FUNCTION_NAME=${SHIPPING_FUNCTION_NAME:-"shipping-service-${RANDOM_SUFFIX}"}
        
        log_warning "Using default resource names. These might not match your deployed resources."
    fi
    
    # Log loaded variables
    log_info "Environment variables loaded:"
    log_info "  RESOURCE_GROUP: $RESOURCE_GROUP"
    log_info "  LOCATION: $LOCATION"
    log_info "  NAMESPACE_NAME: $NAMESPACE_NAME"
    log_info "  WORKSPACE_NAME: $WORKSPACE_NAME"
    log_info "  APPINSIGHTS_NAME: $APPINSIGHTS_NAME"
    log_info "  CONTAINER_ENV_NAME: $CONTAINER_ENV_NAME"
    log_info "  STORAGE_ACCOUNT: $STORAGE_ACCOUNT"
    log_info "  PAYMENT_FUNCTION_NAME: $PAYMENT_FUNCTION_NAME"
    log_info "  SHIPPING_FUNCTION_NAME: $SHIPPING_FUNCTION_NAME"
    
    log_success "Environment variables loaded"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN mode - skipping confirmation"
        return
    fi
    
    log_warning "This will permanently delete all resources in the resource group: $RESOURCE_GROUP"
    log_warning "This action cannot be undone!"
    
    echo -n "Are you sure you want to proceed? (type 'yes' to confirm): "
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource deletion..."
}

# Function to delete Function Apps
delete_function_apps() {
    log_info "Deleting Function Apps..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Function Apps"
        return
    fi
    
    # Array of Function Apps to delete
    function_apps=("$PAYMENT_FUNCTION_NAME" "$SHIPPING_FUNCTION_NAME")
    
    for app in "${function_apps[@]}"; do
        if az functionapp show --name "$app" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log_info "Deleting Function App: $app"
            az functionapp delete --name "$app" --resource-group "$RESOURCE_GROUP" --yes
            log_success "Function App deleted: $app"
        else
            log_warning "Function App $app not found or already deleted"
        fi
    done
}

# Function to delete Container Apps and Environment
delete_container_apps() {
    log_info "Deleting Container Apps..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Container Apps and Environment"
        return
    fi
    
    # Array of Container Apps to delete
    container_apps=("order-service" "inventory-service")
    
    for app in "${container_apps[@]}"; do
        if az containerapp show --name "$app" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log_info "Deleting Container App: $app"
            az containerapp delete --name "$app" --resource-group "$RESOURCE_GROUP" --yes
            log_success "Container App deleted: $app"
        else
            log_warning "Container App $app not found or already deleted"
        fi
    done
    
    # Delete Container Apps Environment
    if az containerapp env show --name "$CONTAINER_ENV_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Deleting Container Apps Environment: $CONTAINER_ENV_NAME"
        az containerapp env delete --name "$CONTAINER_ENV_NAME" --resource-group "$RESOURCE_GROUP" --yes
        log_success "Container Apps Environment deleted: $CONTAINER_ENV_NAME"
    else
        log_warning "Container Apps Environment $CONTAINER_ENV_NAME not found or already deleted"
    fi
}

# Function to delete Storage Account
delete_storage_account() {
    log_info "Deleting Storage Account..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Storage Account: $STORAGE_ACCOUNT"
        return
    fi
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Deleting Storage Account: $STORAGE_ACCOUNT"
        az storage account delete --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --yes
        log_success "Storage Account deleted: $STORAGE_ACCOUNT"
    else
        log_warning "Storage Account $STORAGE_ACCOUNT not found or already deleted"
    fi
}

# Function to delete Azure Monitor Workbook
delete_workbook() {
    log_info "Deleting Azure Monitor Workbook..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Azure Monitor Workbook"
        return
    fi
    
    # List and delete workbooks in the resource group
    workbook_ids=$(az monitor workbook list --resource-group "$RESOURCE_GROUP" --query "[].id" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$workbook_ids" ]]; then
        while IFS= read -r workbook_id; do
            if [[ -n "$workbook_id" ]]; then
                log_info "Deleting workbook: $workbook_id"
                az monitor workbook delete --ids "$workbook_id" --yes
                log_success "Workbook deleted: $workbook_id"
            fi
        done <<< "$workbook_ids"
    else
        log_warning "No workbooks found in resource group $RESOURCE_GROUP"
    fi
}

# Function to delete Service Bus resources
delete_service_bus() {
    log_info "Deleting Service Bus resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Service Bus namespace: $NAMESPACE_NAME"
        return
    fi
    
    if az servicebus namespace show --name "$NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Deleting Service Bus namespace: $NAMESPACE_NAME"
        az servicebus namespace delete --name "$NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP"
        log_success "Service Bus namespace deleted: $NAMESPACE_NAME"
        
        # Wait for namespace deletion to complete
        log_info "Waiting for Service Bus namespace deletion to complete..."
        while az servicebus namespace show --name "$NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; do
            sleep 10
        done
        log_success "Service Bus namespace deletion completed"
    else
        log_warning "Service Bus namespace $NAMESPACE_NAME not found or already deleted"
    fi
}

# Function to delete Application Insights
delete_application_insights() {
    log_info "Deleting Application Insights..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Application Insights: $APPINSIGHTS_NAME"
        return
    fi
    
    if az monitor app-insights component show --app "$APPINSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Deleting Application Insights: $APPINSIGHTS_NAME"
        az monitor app-insights component delete --app "$APPINSIGHTS_NAME" --resource-group "$RESOURCE_GROUP"
        log_success "Application Insights deleted: $APPINSIGHTS_NAME"
    else
        log_warning "Application Insights $APPINSIGHTS_NAME not found or already deleted"
    fi
}

# Function to delete Log Analytics workspace
delete_log_analytics() {
    log_info "Deleting Log Analytics workspace..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Log Analytics workspace: $WORKSPACE_NAME"
        return
    fi
    
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" &> /dev/null; then
        log_info "Deleting Log Analytics workspace: $WORKSPACE_NAME"
        az monitor log-analytics workspace delete --resource-group "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" --yes
        log_success "Log Analytics workspace deleted: $WORKSPACE_NAME"
    else
        log_warning "Log Analytics workspace $WORKSPACE_NAME not found or already deleted"
    fi
}

# Function to delete resource group (alternative cleanup method)
delete_resource_group() {
    log_info "Deleting entire resource group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return
    fi
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Deleting resource group: $RESOURCE_GROUP"
        log_warning "This will delete ALL resources in the resource group!"
        
        # Additional confirmation for resource group deletion
        echo -n "Are you absolutely sure you want to delete the entire resource group? (type 'DELETE' to confirm): "
        read -r final_confirmation
        
        if [[ "$final_confirmation" == "DELETE" ]]; then
            az group delete --name "$RESOURCE_GROUP" --yes --no-wait
            log_success "Resource group deletion initiated: $RESOURCE_GROUP"
            log_info "Note: Resource group deletion is running in the background and may take several minutes"
        else
            log_info "Resource group deletion cancelled"
        fi
    else
        log_warning "Resource group $RESOURCE_GROUP not found or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local files"
        return
    fi
    
    # Remove .env file
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        rm "${SCRIPT_DIR}/.env"
        log_success "Removed .env file"
    fi
    
    # Remove workbook templates directory
    if [[ -d "${SCRIPT_DIR}/workbook-templates" ]]; then
        rm -rf "${SCRIPT_DIR}/workbook-templates"
        log_success "Removed workbook-templates directory"
    fi
    
    # Remove deployment info file if it exists
    if [[ -f "${SCRIPT_DIR}/deployment-info.txt" ]]; then
        rm "${SCRIPT_DIR}/deployment-info.txt"
        log_success "Removed deployment-info.txt"
    fi
    
    log_success "Local files cleaned up"
}

# Function to validate deletion
validate_deletion() {
    log_info "Validating resource deletion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate deletion"
        return
    fi
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Resource group still exists, checking individual resources..."
        
        # Check remaining resources in the resource group
        remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv)
        
        if [[ "$remaining_resources" -eq 0 ]]; then
            log_success "All resources successfully deleted"
        else
            log_warning "$remaining_resources resources still remain in the resource group"
            az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name,Type:type,Location:location}" --output table
        fi
    else
        log_success "Resource group successfully deleted"
    fi
}

# Function to display destruction summary
display_summary() {
    log_info "Destruction Summary"
    log_info "=================="
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info ""
    log_info "Resources that were targeted for deletion:"
    log_info "- Service Bus Namespace: $NAMESPACE_NAME"
    log_info "- Log Analytics Workspace: $WORKSPACE_NAME"
    log_info "- Application Insights: $APPINSIGHTS_NAME"
    log_info "- Container Apps Environment: $CONTAINER_ENV_NAME"
    log_info "- Storage Account: $STORAGE_ACCOUNT"
    log_info "- Payment Function App: $PAYMENT_FUNCTION_NAME"
    log_info "- Shipping Function App: $SHIPPING_FUNCTION_NAME"
    log_info "- Container Apps: order-service, inventory-service"
    log_info "- Azure Monitor Workbook"
    log_info ""
    log_info "If you used resource group deletion, all resources have been removed."
    log_info "Check the Azure Portal to confirm all resources are deleted."
}

# Main destruction function
main() {
    log_info "Starting destruction of Event-Driven Microservices Choreography resources..."
    
    # Initialize log file
    echo "Destruction started at $(date)" > "$LOG_FILE"
    
    # Check if this is a dry run
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY RUN mode - no resources will be deleted"
    fi
    
    # Execute destruction steps
    check_prerequisites
    load_environment
    confirm_deletion
    
    # Provide option for full resource group deletion or individual resource deletion
    echo -n "Do you want to delete the entire resource group (faster) or individual resources? (group/individual): "
    read -r deletion_method
    
    if [[ "$deletion_method" == "group" ]]; then
        delete_resource_group
    else
        log_info "Deleting individual resources (this may take longer)..."
        delete_function_apps
        delete_container_apps
        delete_storage_account
        delete_workbook
        delete_service_bus
        delete_application_insights
        delete_log_analytics
        
        # Optionally delete the resource group if it's empty
        echo -n "Delete the resource group if it's empty? (y/n): "
        read -r delete_rg
        if [[ "$delete_rg" == "y" ]]; then
            delete_resource_group
        fi
    fi
    
    # Clean up local files
    cleanup_local_files
    
    # Validate deletion
    validate_deletion
    
    # Display summary
    display_summary
    
    log_success "Destruction completed!"
}

# Handle script interruption
trap 'log_error "Destruction interrupted"; exit 1' INT TERM

# Check for command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --dry-run      Show what would be deleted without actually deleting"
        echo ""
        echo "Environment variables:"
        echo "  DRY_RUN        Set to 'true' to run in dry-run mode"
        echo "  RESOURCE_GROUP Override the resource group name"
        echo ""
        echo "Examples:"
        echo "  $0              # Delete resources normally"
        echo "  $0 --dry-run    # Show what would be deleted"
        echo "  DRY_RUN=true $0 # Same as --dry-run"
        exit 0
        ;;
    --dry-run)
        export DRY_RUN=true
        ;;
    "")
        # No arguments, proceed normally
        ;;
    *)
        log_error "Unknown argument: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Run main function
main "$@"