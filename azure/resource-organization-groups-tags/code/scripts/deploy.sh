#!/bin/bash

# Resource Organization with Resource Groups and Tags - Deployment Script
# Recipe: resource-organization-groups-tags
# Version: 1.1
# Provider: Azure

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for graceful exit
cleanup() {
    if [[ $? -ne 0 ]]; then
        log_error "Deployment failed. Check the logs above for details."
        log_info "You may need to run the destroy script to clean up any partially created resources."
    fi
}

trap cleanup EXIT

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null) || error_exit "Failed to get Azure CLI version"
    log_info "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is required for generating random suffixes. Please install it."
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default location if not provided
    export LOCATION="${LOCATION:-eastus}"
    
    # Get subscription ID
    export SUBSCRIPTION_ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv) || error_exit "Failed to get subscription ID"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3) || error_exit "Failed to generate random suffix"
    
    # Set base names for different environments
    export DEV_RG="rg-demo-dev-${RANDOM_SUFFIX}"
    export PROD_RG="rg-demo-prod-${RANDOM_SUFFIX}"
    export SHARED_RG="rg-demo-shared-${RANDOM_SUFFIX}"
    
    # Store variables in a file for cleanup script
    cat > .env_vars << EOF
export LOCATION="${LOCATION}"
export SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
export DEV_RG="${DEV_RG}"
export PROD_RG="${PROD_RG}"
export SHARED_RG="${SHARED_RG}"
EOF
    
    log_success "Environment variables configured"
    log_info "   Subscription: ${SUBSCRIPTION_ID}"
    log_info "   Location: ${LOCATION}"
    log_info "   Suffix: ${RANDOM_SUFFIX}"
}

# Create development resource group
create_dev_resource_group() {
    log_info "Creating development resource group..."
    
    if az group show --name "${DEV_RG}" &> /dev/null; then
        log_warning "Development resource group ${DEV_RG} already exists, skipping creation"
        return 0
    fi
    
    az group create \
        --name "${DEV_RG}" \
        --location "${LOCATION}" \
        --tags environment=development \
               purpose=demo \
               department=engineering \
               costcenter=dev001 \
               owner=devteam \
               project=resource-organization \
        || error_exit "Failed to create development resource group"
    
    log_success "Development resource group created: ${DEV_RG}"
}

# Create production resource group
create_prod_resource_group() {
    log_info "Creating production resource group..."
    
    if az group show --name "${PROD_RG}" &> /dev/null; then
        log_warning "Production resource group ${PROD_RG} already exists, skipping creation"
        return 0
    fi
    
    az group create \
        --name "${PROD_RG}" \
        --location "${LOCATION}" \
        --tags environment=production \
               purpose=demo \
               department=engineering \
               costcenter=prod001 \
               owner=opsTeam \
               project=resource-organization \
               sla=high \
               backup=daily \
               compliance=sox \
        || error_exit "Failed to create production resource group"
    
    log_success "Production resource group created: ${PROD_RG}"
}

# Create shared resource group
create_shared_resource_group() {
    log_info "Creating shared resource group..."
    
    if az group show --name "${SHARED_RG}" &> /dev/null; then
        log_warning "Shared resource group ${SHARED_RG} already exists, skipping creation"
        return 0
    fi
    
    az group create \
        --name "${SHARED_RG}" \
        --location "${LOCATION}" \
        --tags environment=shared \
               purpose=infrastructure \
               department=platform \
               costcenter=shared001 \
               owner=platformTeam \
               project=resource-organization \
               scope=multi-environment \
        || error_exit "Failed to create shared resource group"
    
    log_success "Shared resource group created: ${SHARED_RG}"
}

# Create sample resources in development group
create_dev_resources() {
    log_info "Creating sample resources in development environment..."
    
    # Create storage account in development environment
    local storage_dev="stdev${RANDOM_SUFFIX}"
    if az storage account show --name "${storage_dev}" --resource-group "${DEV_RG}" &> /dev/null; then
        log_warning "Development storage account ${storage_dev} already exists, skipping creation"
    else
        az storage account create \
            --name "${storage_dev}" \
            --resource-group "${DEV_RG}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --tags tier=standard \
                   dataclass=non-sensitive \
            || error_exit "Failed to create development storage account"
        
        log_success "Development storage account created: ${storage_dev}"
    fi
    
    # Create App Service plan in development environment
    local app_plan_dev="asp-dev-${RANDOM_SUFFIX}"
    if az appservice plan show --name "${app_plan_dev}" --resource-group "${DEV_RG}" &> /dev/null; then
        log_warning "Development App Service plan ${app_plan_dev} already exists, skipping creation"
    else
        az appservice plan create \
            --name "${app_plan_dev}" \
            --resource-group "${DEV_RG}" \
            --location "${LOCATION}" \
            --sku B1 \
            --tags tier=basic \
                   workload=web-app \
            || error_exit "Failed to create development App Service plan"
        
        log_success "Development App Service plan created: ${app_plan_dev}"
    fi
    
    # Store resource names for cleanup
    cat >> .env_vars << EOF
export STORAGE_DEV="${storage_dev}"
export APP_PLAN_DEV="${app_plan_dev}"
EOF
}

# Create sample resources in production group
create_prod_resources() {
    log_info "Creating sample resources in production environment..."
    
    # Create storage account in production environment
    local storage_prod="stprod${RANDOM_SUFFIX}"
    if az storage account show --name "${storage_prod}" --resource-group "${PROD_RG}" &> /dev/null; then
        log_warning "Production storage account ${storage_prod} already exists, skipping creation"
    else
        az storage account create \
            --name "${storage_prod}" \
            --resource-group "${PROD_RG}" \
            --location "${LOCATION}" \
            --sku Standard_GRS \
            --kind StorageV2 \
            --tags tier=premium \
                   dataclass=sensitive \
                   encryption=enabled \
                   backup=enabled \
            || error_exit "Failed to create production storage account"
        
        log_success "Production storage account created: ${storage_prod}"
    fi
    
    # Create App Service plan in production environment
    local app_plan_prod="asp-prod-${RANDOM_SUFFIX}"
    if az appservice plan show --name "${app_plan_prod}" --resource-group "${PROD_RG}" &> /dev/null; then
        log_warning "Production App Service plan ${app_plan_prod} already exists, skipping creation"
    else
        az appservice plan create \
            --name "${app_plan_prod}" \
            --resource-group "${PROD_RG}" \
            --location "${LOCATION}" \
            --sku P1V2 \
            --tags tier=premium \
                   workload=web-app \
                   monitoring=enabled \
            || error_exit "Failed to create production App Service plan"
        
        log_success "Production App Service plan created: ${app_plan_prod}"
    fi
    
    # Store resource names for cleanup
    cat >> .env_vars << EOF
export STORAGE_PROD="${storage_prod}"
export APP_PLAN_PROD="${app_plan_prod}"
EOF
}

# Apply additional tags to resource groups
update_resource_group_tags() {
    log_info "Updating resource groups with additional tags..."
    
    # Update development resource group with additional operational tags
    az group update \
        --name "${DEV_RG}" \
        --set tags.lastUpdated=2025-07-12 \
              tags.managedBy=azure-cli \
              tags.automation=enabled \
        || error_exit "Failed to update development resource group tags"
    
    # Update production resource group with compliance tags
    az group update \
        --name "${PROD_RG}" \
        --set tags.lastUpdated=2025-07-12 \
              tags.managedBy=azure-cli \
              tags.automation=enabled \
              tags.auditRequired=true \
        || error_exit "Failed to update production resource group tags"
    
    # Update shared resource group with operational tags
    az group update \
        --name "${SHARED_RG}" \
        --set tags.lastUpdated=2025-07-12 \
              tags.managedBy=azure-cli \
              tags.automation=enabled \
        || error_exit "Failed to update shared resource group tags"
    
    log_success "Resource groups updated with additional tags"
}

# Validation and testing
validate_deployment() {
    log_info "Validating deployment..."
    
    # Verify resource groups exist
    local resource_groups=("${DEV_RG}" "${PROD_RG}" "${SHARED_RG}")
    for rg in "${resource_groups[@]}"; do
        if ! az group show --name "${rg}" &> /dev/null; then
            error_exit "Resource group ${rg} was not created successfully"
        fi
    done
    
    # List all created resource groups with their tags
    log_info "Created resource groups:"
    az group list \
        --query "[?contains(name, '${RANDOM_SUFFIX}')].{Name:name, Location:location, Tags:tags}" \
        --output table
    
    # Query resources by environment tag
    log_info "Development environment resources:"
    az resource list \
        --tag environment=development \
        --query "[].{Name:name, Type:type, ResourceGroup:resourceGroup}" \
        --output table || log_warning "No development resources found or query failed"
    
    # Generate cost allocation report
    log_info "Resources with cost allocation tags:"
    az resource list \
        --query "[?tags.costcenter != null].{Name:name, Environment:tags.environment, CostCenter:tags.costcenter, Department:tags.department}" \
        --output table || log_warning "No resources with cost center tags found"
    
    log_success "Deployment validation completed successfully"
}

# Main deployment function
main() {
    log_info "Starting Azure Resource Organization deployment..."
    log_info "Recipe: resource-organization-groups-tags v1.1"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_dev_resource_group
    create_prod_resource_group
    create_shared_resource_group
    create_dev_resources
    create_prod_resources
    update_resource_group_tags
    validate_deployment
    
    log_success "Deployment completed successfully!"
    log_info "Environment variables saved to .env_vars file for cleanup script"
    log_info "To clean up resources, run: ./destroy.sh"
    
    # Display resource summary
    echo
    log_info "=== Deployment Summary ==="
    log_info "Development Resource Group: ${DEV_RG}"
    log_info "Production Resource Group: ${PROD_RG}"
    log_info "Shared Resource Group: ${SHARED_RG}"
    log_info "Location: ${LOCATION}"
    log_info "Subscription: ${SUBSCRIPTION_ID}"
    echo
}

# Execute main function
main "$@"