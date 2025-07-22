#!/bin/bash

# Deploy Stateful Container Workloads with Azure Container Instances and Azure Files
# This script deploys a complete solution for stateful containers with persistent storage

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
    warning "Running in DRY-RUN mode - no resources will be created"
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
        error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! $AZ_CMD account show &> /dev/null && [ "$DRY_RUN" = "false" ]; then
        error "Please login to Azure CLI first: az login"
        exit 1
    fi
    
    # Check if required tools are available
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is required but not installed"
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
    
    # Get subscription ID
    if [ "$DRY_RUN" = "false" ]; then
        export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    else
        export SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
    fi
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export STORAGE_ACCOUNT="statefulstorage${RANDOM_SUFFIX}"
    export CONTAINER_REGISTRY="statefulregistry${RANDOM_SUFFIX}"
    export FILE_SHARE_NAME="containerdata"
    export LOG_WORKSPACE="log-stateful-containers-${RANDOM_SUFFIX}"
    
    log "Environment variables set:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Location: $LOCATION"
    log "  Storage Account: $STORAGE_ACCOUNT"
    log "  Container Registry: $CONTAINER_REGISTRY"
    log "  File Share Name: $FILE_SHARE_NAME"
    log "  Log Workspace: $LOG_WORKSPACE"
    
    success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    $AZ_CMD group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=recipe environment=demo
    
    success "Resource group created: ${RESOURCE_GROUP}"
}

# Function to create Log Analytics workspace
create_log_analytics_workspace() {
    log "Creating Log Analytics workspace..."
    
    $AZ_CMD monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_WORKSPACE}" \
        --location "${LOCATION}"
    
    success "Log Analytics workspace created: ${LOG_WORKSPACE}"
}

# Function to create storage account and Azure Files
create_storage_resources() {
    log "Creating Azure Storage Account with Azure Files..."
    
    # Create storage account
    $AZ_CMD storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --enable-large-file-share
    
    success "Storage account created: ${STORAGE_ACCOUNT}"
    
    # Create Azure Files file share
    $AZ_CMD storage share create \
        --name "${FILE_SHARE_NAME}" \
        --account-name "${STORAGE_ACCOUNT}" \
        --quota 100
    
    success "Azure Files share created: ${FILE_SHARE_NAME}"
}

# Function to configure storage access
configure_storage_access() {
    log "Configuring storage account access..."
    
    # Retrieve storage account key
    if [ "$DRY_RUN" = "false" ]; then
        export STORAGE_KEY=$(az storage account keys list \
            --resource-group "${RESOURCE_GROUP}" \
            --account-name "${STORAGE_ACCOUNT}" \
            --query "[0].value" --output tsv)
    else
        export STORAGE_KEY="dummy-key-for-dry-run"
    fi
    
    success "Storage account key retrieved"
    
    # Create directory structure in file share
    $AZ_CMD storage directory create \
        --name "app-data" \
        --share-name "${FILE_SHARE_NAME}" \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${STORAGE_KEY}"
    
    $AZ_CMD storage directory create \
        --name "database" \
        --share-name "${FILE_SHARE_NAME}" \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${STORAGE_KEY}"
    
    success "Directory structure created in file share"
}

# Function to create Azure Container Registry
create_container_registry() {
    log "Creating Azure Container Registry..."
    
    $AZ_CMD acr create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${CONTAINER_REGISTRY}" \
        --sku Basic \
        --admin-enabled true
    
    success "Azure Container Registry created: ${CONTAINER_REGISTRY}"
    
    # Get registry credentials
    if [ "$DRY_RUN" = "false" ]; then
        export REGISTRY_SERVER=$(az acr show \
            --name "${CONTAINER_REGISTRY}" \
            --query loginServer --output tsv)
        
        export REGISTRY_USERNAME=$(az acr credential show \
            --name "${CONTAINER_REGISTRY}" \
            --query username --output tsv)
        
        export REGISTRY_PASSWORD=$(az acr credential show \
            --name "${CONTAINER_REGISTRY}" \
            --query passwords[0].value --output tsv)
    else
        export REGISTRY_SERVER="${CONTAINER_REGISTRY}.azurecr.io"
        export REGISTRY_USERNAME="dummy-username"
        export REGISTRY_PASSWORD="dummy-password"
    fi
    
    success "Registry credentials configured"
}

# Function to deploy PostgreSQL database container
deploy_database_container() {
    log "Deploying PostgreSQL database container..."
    
    $AZ_CMD container create \
        --resource-group "${RESOURCE_GROUP}" \
        --name postgres-stateful \
        --image postgres:13 \
        --cpu 1 \
        --memory 2 \
        --environment-variables \
            POSTGRES_PASSWORD=SecurePassword123! \
            POSTGRES_DB=appdb \
            PGDATA=/var/lib/postgresql/data/pgdata \
        --azure-file-volume-account-name "${STORAGE_ACCOUNT}" \
        --azure-file-volume-account-key "${STORAGE_KEY}" \
        --azure-file-volume-share-name "${FILE_SHARE_NAME}" \
        --azure-file-volume-mount-path /var/lib/postgresql/data \
        --os-type Linux \
        --restart-policy Always
    
    success "PostgreSQL container deployed with persistent storage"
    
    # Wait for container to be ready
    if [ "$DRY_RUN" = "false" ]; then
        log "Waiting for PostgreSQL container to be ready..."
        sleep 30
        
        # Check container status
        CONTAINER_STATUS=$(az container show \
            --resource-group "${RESOURCE_GROUP}" \
            --name postgres-stateful \
            --query "containers[0].instanceView.currentState.state" \
            --output tsv)
        
        if [ "$CONTAINER_STATUS" = "Running" ]; then
            success "PostgreSQL container is running"
        else
            warning "PostgreSQL container status: $CONTAINER_STATUS"
        fi
    fi
}

# Function to deploy application container
deploy_application_container() {
    log "Deploying application container..."
    
    # Generate unique DNS name
    DNS_NAME="stateful-app-$(openssl rand -hex 3)"
    
    $AZ_CMD container create \
        --resource-group "${RESOURCE_GROUP}" \
        --name app-stateful \
        --image nginx:alpine \
        --cpu 0.5 \
        --memory 1 \
        --ports 80 \
        --dns-name-label "${DNS_NAME}" \
        --azure-file-volume-account-name "${STORAGE_ACCOUNT}" \
        --azure-file-volume-account-key "${STORAGE_KEY}" \
        --azure-file-volume-share-name "${FILE_SHARE_NAME}" \
        --azure-file-volume-mount-path /usr/share/nginx/html \
        --os-type Linux \
        --restart-policy Always
    
    success "Application container deployed with shared storage"
    
    # Get application FQDN
    if [ "$DRY_RUN" = "false" ]; then
        export APP_FQDN=$(az container show \
            --resource-group "${RESOURCE_GROUP}" \
            --name app-stateful \
            --query ipAddress.fqdn --output tsv)
        
        success "Application available at: http://${APP_FQDN}"
    else
        export APP_FQDN="${DNS_NAME}.${LOCATION}.azurecontainer.io"
        success "Application would be available at: http://${APP_FQDN}"
    fi
}

# Function to deploy worker container
deploy_worker_container() {
    log "Deploying worker container for background processing..."
    
    $AZ_CMD container create \
        --resource-group "${RESOURCE_GROUP}" \
        --name worker-stateful \
        --image alpine:latest \
        --cpu 0.5 \
        --memory 0.5 \
        --command-line "sh -c 'while true; do echo \"Worker processing at \$(date)\" >> /shared/logs/worker.log; sleep 60; done'" \
        --azure-file-volume-account-name "${STORAGE_ACCOUNT}" \
        --azure-file-volume-account-key "${STORAGE_KEY}" \
        --azure-file-volume-share-name "${FILE_SHARE_NAME}" \
        --azure-file-volume-mount-path /shared \
        --os-type Linux \
        --restart-policy Always
    
    success "Worker container deployed for background processing"
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring container monitoring and logging..."
    
    # Get Log Analytics workspace details
    if [ "$DRY_RUN" = "false" ]; then
        export WORKSPACE_ID=$(az monitor log-analytics workspace show \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_WORKSPACE}" \
            --query customerId --output tsv)
        
        export WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_WORKSPACE}" \
            --query primarySharedKey --output tsv)
    else
        export WORKSPACE_ID="dummy-workspace-id"
        export WORKSPACE_KEY="dummy-workspace-key"
    fi
    
    # Deploy monitored application container
    $AZ_CMD container create \
        --resource-group "${RESOURCE_GROUP}" \
        --name monitored-app \
        --image nginx:alpine \
        --cpu 0.5 \
        --memory 1 \
        --ports 80 \
        --log-analytics-workspace "${WORKSPACE_ID}" \
        --log-analytics-workspace-key "${WORKSPACE_KEY}" \
        --azure-file-volume-account-name "${STORAGE_ACCOUNT}" \
        --azure-file-volume-account-key "${STORAGE_KEY}" \
        --azure-file-volume-share-name "${FILE_SHARE_NAME}" \
        --azure-file-volume-mount-path /usr/share/nginx/html \
        --os-type Linux \
        --restart-policy Always
    
    success "Container monitoring configured with Log Analytics"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [ "$DRY_RUN" = "true" ]; then
        success "Deployment validation skipped in dry-run mode"
        return 0
    fi
    
    # Check resource group
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        success "Resource group exists: ${RESOURCE_GROUP}"
    else
        error "Resource group validation failed"
        return 1
    fi
    
    # Check storage account
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        success "Storage account exists: ${STORAGE_ACCOUNT}"
    else
        error "Storage account validation failed"
        return 1
    fi
    
    # Check file share
    if az storage share show --name "${FILE_SHARE_NAME}" --account-name "${STORAGE_ACCOUNT}" &> /dev/null; then
        success "File share exists: ${FILE_SHARE_NAME}"
    else
        error "File share validation failed"
        return 1
    fi
    
    # Check container instances
    local containers=("postgres-stateful" "app-stateful" "worker-stateful" "monitored-app")
    for container in "${containers[@]}"; do
        if az container show --resource-group "${RESOURCE_GROUP}" --name "$container" &> /dev/null; then
            success "Container instance exists: $container"
        else
            warning "Container instance not found: $container"
        fi
    done
    
    success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    log "=================="
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Location: ${LOCATION}"
    log "Storage Account: ${STORAGE_ACCOUNT}"
    log "Container Registry: ${CONTAINER_REGISTRY}"
    log "File Share: ${FILE_SHARE_NAME}"
    log "Log Workspace: ${LOG_WORKSPACE}"
    
    if [ "$DRY_RUN" = "false" ]; then
        log "Application URL: http://${APP_FQDN}"
        log ""
        log "To view container logs:"
        log "  az container logs --resource-group ${RESOURCE_GROUP} --name <container-name>"
        log ""
        log "To view Log Analytics workspace:"
        log "  az monitor log-analytics workspace show --resource-group ${RESOURCE_GROUP} --workspace-name ${LOG_WORKSPACE}"
    fi
    
    log ""
    log "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting deployment of Stateful Container Workloads with Azure Container Instances and Azure Files"
    
    # Check if help is requested
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  -h, --help     Show this help message"
        echo "  --dry-run      Run in dry-run mode (no resources created)"
        echo ""
        echo "Environment Variables:"
        echo "  RESOURCE_GROUP    Resource group name (default: rg-stateful-containers)"
        echo "  LOCATION          Azure region (default: eastus)"
        echo "  DRY_RUN          Enable dry-run mode (default: false)"
        echo ""
        echo "Example:"
        echo "  DRY_RUN=true $0"
        echo "  RESOURCE_GROUP=my-rg LOCATION=westus2 $0"
        exit 0
    fi
    
    # Check for dry-run flag
    if [[ "${1:-}" == "--dry-run" ]]; then
        DRY_RUN=true
    fi
    
    # Execute deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_log_analytics_workspace
    create_storage_resources
    configure_storage_access
    create_container_registry
    deploy_database_container
    deploy_application_container
    deploy_worker_container
    configure_monitoring
    validate_deployment
    display_summary
    
    success "Deployment completed successfully!"
    
    if [ "$DRY_RUN" = "false" ]; then
        log "Resources are now running and incurring charges. Remember to run destroy.sh when finished."
    fi
}

# Error handling
trap 'error "Script failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"