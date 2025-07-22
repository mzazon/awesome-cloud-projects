#!/bin/bash

# Destroy Stateful Container Workloads with Azure Container Instances and Azure Files
# This script safely removes all resources created by the deployment script

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}

if [ "$DRY_RUN" = "true" ]; then
    warning "Running in DRY-RUN mode - no resources will be deleted"
    AZ_CMD="echo [DRY-RUN] az"
else
    AZ_CMD="az"
fi

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! $AZ_CMD account show &> /dev/null && [ "$DRY_RUN" = "false" ]; then
        error "Please login to Azure CLI first: az login"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Set default values if not already set
    export RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-stateful-containers"}
    export LOCATION=${LOCATION:-"eastus"}
    
    # If specific resource names are not provided, we'll discover them
    if [ -z "${STORAGE_ACCOUNT:-}" ] || [ -z "${CONTAINER_REGISTRY:-}" ] || [ -z "${LOG_WORKSPACE:-}" ]; then
        discover_resources
    fi
    
    export FILE_SHARE_NAME=${FILE_SHARE_NAME:-"containerdata"}
    
    success "Environment variables configured"
}

# Function to discover existing resources
discover_resources() {
    log "Discovering existing resources in resource group: ${RESOURCE_GROUP}"
    
    if [ "$DRY_RUN" = "false" ]; then
        # Check if resource group exists
        if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            error "Resource group '${RESOURCE_GROUP}' does not exist"
            exit 1
        fi
        
        # Discover storage account
        if [ -z "${STORAGE_ACCOUNT:-}" ]; then
            STORAGE_ACCOUNT=$(az storage account list \
                --resource-group "${RESOURCE_GROUP}" \
                --query "[?contains(name, 'statefulstorage')].name | [0]" \
                --output tsv)
        fi
        
        # Discover container registry
        if [ -z "${CONTAINER_REGISTRY:-}" ]; then
            CONTAINER_REGISTRY=$(az acr list \
                --resource-group "${RESOURCE_GROUP}" \
                --query "[?contains(name, 'statefulregistry')].name | [0]" \
                --output tsv)
        fi
        
        # Discover log analytics workspace
        if [ -z "${LOG_WORKSPACE:-}" ]; then
            LOG_WORKSPACE=$(az monitor log-analytics workspace list \
                --resource-group "${RESOURCE_GROUP}" \
                --query "[?contains(name, 'log-stateful-containers')].name | [0]" \
                --output tsv)
        fi
        
        log "Discovered resources:"
        log "  Storage Account: ${STORAGE_ACCOUNT:-'not found'}"
        log "  Container Registry: ${CONTAINER_REGISTRY:-'not found'}"
        log "  Log Workspace: ${LOG_WORKSPACE:-'not found'}"
    else
        # Set dummy values for dry-run
        export STORAGE_ACCOUNT="dummy-storage-account"
        export CONTAINER_REGISTRY="dummy-container-registry"
        export LOG_WORKSPACE="dummy-log-workspace"
    fi
}

# Function to confirm deletion
confirm_deletion() {
    if [ "$DRY_RUN" = "true" ]; then
        log "Dry-run mode: skipping confirmation"
        return 0
    fi
    
    warning "This will permanently delete the following resources:"
    warning "  Resource Group: ${RESOURCE_GROUP}"
    warning "  Storage Account: ${STORAGE_ACCOUNT:-'not found'}"
    warning "  Container Registry: ${CONTAINER_REGISTRY:-'not found'}"
    warning "  Log Workspace: ${LOG_WORKSPACE:-'not found'}"
    warning "  All container instances in the resource group"
    warning "  All data stored in Azure Files"
    
    echo
    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    success "Deletion confirmed"
}

# Function to delete container instances
delete_container_instances() {
    log "Deleting container instances..."
    
    local containers=("postgres-stateful" "app-stateful" "worker-stateful" "monitored-app")
    
    for container in "${containers[@]}"; do
        if [ "$DRY_RUN" = "false" ]; then
            # Check if container exists before trying to delete
            if az container show --resource-group "${RESOURCE_GROUP}" --name "$container" &> /dev/null; then
                log "Deleting container instance: $container"
                $AZ_CMD container delete \
                    --resource-group "${RESOURCE_GROUP}" \
                    --name "$container" \
                    --yes
                success "Container instance deleted: $container"
            else
                warning "Container instance not found: $container"
            fi
        else
            $AZ_CMD container delete \
                --resource-group "${RESOURCE_GROUP}" \
                --name "$container" \
                --yes
        fi
    done
    
    success "All container instances deleted"
}

# Function to delete Azure Container Registry
delete_container_registry() {
    if [ -z "${CONTAINER_REGISTRY:-}" ] || [ "${CONTAINER_REGISTRY}" = "not found" ]; then
        warning "Container Registry not found, skipping deletion"
        return 0
    fi
    
    log "Deleting Azure Container Registry: ${CONTAINER_REGISTRY}"
    
    if [ "$DRY_RUN" = "false" ]; then
        # Check if registry exists
        if az acr show --name "${CONTAINER_REGISTRY}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            $AZ_CMD acr delete \
                --resource-group "${RESOURCE_GROUP}" \
                --name "${CONTAINER_REGISTRY}" \
                --yes
            success "Azure Container Registry deleted: ${CONTAINER_REGISTRY}"
        else
            warning "Container Registry not found: ${CONTAINER_REGISTRY}"
        fi
    else
        $AZ_CMD acr delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${CONTAINER_REGISTRY}" \
            --yes
    fi
}

# Function to delete storage resources
delete_storage_resources() {
    if [ -z "${STORAGE_ACCOUNT:-}" ] || [ "${STORAGE_ACCOUNT}" = "not found" ]; then
        warning "Storage Account not found, skipping deletion"
        return 0
    fi
    
    log "Deleting storage resources..."
    
    # Delete Azure Files share first
    if [ "$DRY_RUN" = "false" ]; then
        # Get storage account key
        if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            STORAGE_KEY=$(az storage account keys list \
                --resource-group "${RESOURCE_GROUP}" \
                --account-name "${STORAGE_ACCOUNT}" \
                --query "[0].value" --output tsv)
            
            # Delete file share
            if az storage share show --name "${FILE_SHARE_NAME}" --account-name "${STORAGE_ACCOUNT}" &> /dev/null; then
                $AZ_CMD storage share delete \
                    --name "${FILE_SHARE_NAME}" \
                    --account-name "${STORAGE_ACCOUNT}" \
                    --account-key "${STORAGE_KEY}"
                success "Azure Files share deleted: ${FILE_SHARE_NAME}"
            else
                warning "File share not found: ${FILE_SHARE_NAME}"
            fi
            
            # Delete storage account
            $AZ_CMD storage account delete \
                --resource-group "${RESOURCE_GROUP}" \
                --name "${STORAGE_ACCOUNT}" \
                --yes
            success "Storage account deleted: ${STORAGE_ACCOUNT}"
        else
            warning "Storage account not found: ${STORAGE_ACCOUNT}"
        fi
    else
        $AZ_CMD storage share delete \
            --name "${FILE_SHARE_NAME}" \
            --account-name "${STORAGE_ACCOUNT}" \
            --account-key "dummy-key"
        
        $AZ_CMD storage account delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${STORAGE_ACCOUNT}" \
            --yes
    fi
}

# Function to delete Log Analytics workspace
delete_log_analytics_workspace() {
    if [ -z "${LOG_WORKSPACE:-}" ] || [ "${LOG_WORKSPACE}" = "not found" ]; then
        warning "Log Analytics workspace not found, skipping deletion"
        return 0
    fi
    
    log "Deleting Log Analytics workspace: ${LOG_WORKSPACE}"
    
    if [ "$DRY_RUN" = "false" ]; then
        # Check if workspace exists
        if az monitor log-analytics workspace show --resource-group "${RESOURCE_GROUP}" --workspace-name "${LOG_WORKSPACE}" &> /dev/null; then
            $AZ_CMD monitor log-analytics workspace delete \
                --resource-group "${RESOURCE_GROUP}" \
                --workspace-name "${LOG_WORKSPACE}" \
                --yes
            success "Log Analytics workspace deleted: ${LOG_WORKSPACE}"
        else
            warning "Log Analytics workspace not found: ${LOG_WORKSPACE}"
        fi
    else
        $AZ_CMD monitor log-analytics workspace delete \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_WORKSPACE}" \
            --yes
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group: ${RESOURCE_GROUP}"
    
    if [ "$DRY_RUN" = "false" ]; then
        # Check if resource group exists
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            $AZ_CMD group delete \
                --name "${RESOURCE_GROUP}" \
                --yes \
                --no-wait
            success "Resource group deletion initiated: ${RESOURCE_GROUP}"
            warning "Note: Deletion may take several minutes to complete"
        else
            warning "Resource group not found: ${RESOURCE_GROUP}"
        fi
    else
        $AZ_CMD group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait
    fi
}

# Function to wait for deletion completion
wait_for_deletion() {
    if [ "$DRY_RUN" = "true" ]; then
        success "Dry-run mode: skipping deletion wait"
        return 0
    fi
    
    local wait_time=${WAIT_FOR_DELETION:-true}
    if [ "$wait_time" = "false" ]; then
        warning "Skipping deletion wait as requested"
        return 0
    fi
    
    log "Waiting for resource group deletion to complete..."
    log "This may take several minutes..."
    
    local timeout=1800  # 30 minutes timeout
    local elapsed=0
    local check_interval=30
    
    while [ $elapsed -lt $timeout ]; do
        if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            success "Resource group deletion completed"
            return 0
        fi
        
        log "Still deleting... (${elapsed}s elapsed)"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    warning "Timeout waiting for resource group deletion"
    warning "Please check the Azure portal for deletion status"
}

# Function to clean up environment variables
cleanup_environment() {
    log "Cleaning up environment variables..."
    
    unset RESOURCE_GROUP LOCATION STORAGE_ACCOUNT CONTAINER_REGISTRY
    unset FILE_SHARE_NAME STORAGE_KEY REGISTRY_SERVER REGISTRY_USERNAME
    unset REGISTRY_PASSWORD APP_FQDN LOG_WORKSPACE WORKSPACE_ID WORKSPACE_KEY
    
    success "Environment variables cleaned up"
}

# Function to validate deletion
validate_deletion() {
    log "Validating deletion..."
    
    if [ "$DRY_RUN" = "true" ]; then
        success "Deletion validation skipped in dry-run mode"
        return 0
    fi
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Resource group still exists: ${RESOURCE_GROUP}"
        warning "Deletion may still be in progress"
    else
        success "Resource group successfully deleted: ${RESOURCE_GROUP}"
    fi
    
    success "Deletion validation completed"
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary:"
    log "==============="
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Storage Account: ${STORAGE_ACCOUNT:-'not found'}"
    log "Container Registry: ${CONTAINER_REGISTRY:-'not found'}"
    log "Log Workspace: ${LOG_WORKSPACE:-'not found'}"
    log ""
    
    if [ "$DRY_RUN" = "false" ]; then
        log "All resources have been deleted or deletion has been initiated."
        log "If you enabled resource locks, you may need to remove them manually."
        log ""
        log "To verify deletion:"
        log "  az group show --name ${RESOURCE_GROUP}"
        log "  (Should return 'ResourceGroupNotFound' error)"
    else
        log "Dry-run completed. No resources were actually deleted."
    fi
}

# Main cleanup function
main() {
    log "Starting cleanup of Stateful Container Workloads with Azure Container Instances and Azure Files"
    
    # Check if help is requested
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  -h, --help     Show this help message"
        echo "  --dry-run      Run in dry-run mode (no resources deleted)"
        echo "  --no-wait      Don't wait for deletion completion"
        echo "  --force        Skip confirmation prompt"
        echo ""
        echo "Environment Variables:"
        echo "  RESOURCE_GROUP       Resource group name (default: rg-stateful-containers)"
        echo "  STORAGE_ACCOUNT      Storage account name (auto-discovered if not set)"
        echo "  CONTAINER_REGISTRY   Container registry name (auto-discovered if not set)"
        echo "  LOG_WORKSPACE        Log workspace name (auto-discovered if not set)"
        echo "  DRY_RUN             Enable dry-run mode (default: false)"
        echo "  WAIT_FOR_DELETION   Wait for deletion completion (default: true)"
        echo ""
        echo "Examples:"
        echo "  DRY_RUN=true $0                    # Dry run"
        echo "  $0 --force --no-wait               # Force delete without waiting"
        echo "  RESOURCE_GROUP=my-rg $0            # Delete specific resource group"
        exit 0
    fi
    
    # Parse command line arguments
    FORCE_DELETE=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-wait)
                WAIT_FOR_DELETION=false
                shift
                ;;
            --force)
                FORCE_DELETE=true
                shift
                ;;
            *)
                warning "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    # Execute cleanup steps
    check_prerequisites
    set_environment_variables
    
    # Skip confirmation if force flag is set
    if [ "$FORCE_DELETE" = "false" ]; then
        confirm_deletion
    fi
    
    delete_container_instances
    delete_container_registry
    delete_storage_resources
    delete_log_analytics_workspace
    delete_resource_group
    
    # Wait for deletion if requested
    if [ "${WAIT_FOR_DELETION:-true}" = "true" ]; then
        wait_for_deletion
    fi
    
    validate_deletion
    cleanup_environment
    display_summary
    
    success "Cleanup completed successfully!"
    
    if [ "$DRY_RUN" = "false" ]; then
        log "All resources have been deleted. You should no longer be charged for these resources."
    fi
}

# Error handling
trap 'error "Script failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"