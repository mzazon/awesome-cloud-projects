#!/bin/bash

# Deploy Azure Dev Box and Deployment Environments Infrastructure
# This script deploys a complete self-service developer infrastructure solution

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in dry-run mode - no resources will be created"
fi

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if required providers are available
    local required_providers=("Microsoft.DevCenter" "Microsoft.Network" "Microsoft.Compute")
    for provider in "${required_providers[@]}"; do
        local status=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$status" != "Registered" ]]; then
            warning "Provider $provider is not registered. It will be registered during deployment."
        fi
    done
    
    success "Prerequisites check completed"
}

# Set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Default values that can be overridden
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-devinfra-demo}"
    export LOCATION="${LOCATION:-eastus}"
    export DEVCENTER_NAME="${DEVCENTER_NAME:-dc-selfservice-demo}"
    export PROJECT_NAME="${PROJECT_NAME:-proj-webapp-team}"
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    log "Resource Group: $RESOURCE_GROUP"
    log "Location: $LOCATION"
    log "DevCenter Name: $DEVCENTER_NAME"
    log "Project Name: $PROJECT_NAME"
    log "Subscription ID: $SUBSCRIPTION_ID"
    log "Random Suffix: $RANDOM_SUFFIX"
    
    success "Environment variables set"
}

# Create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create resource group $RESOURCE_GROUP in $LOCATION"
        return 0
    fi
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=demo environment=development
        success "Resource group created"
    fi
}

# Register required providers
register_providers() {
    log "Registering required resource providers..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would register providers Microsoft.DevCenter, Microsoft.Network, Microsoft.Compute"
        return 0
    fi
    
    local providers=("Microsoft.DevCenter" "Microsoft.Network" "Microsoft.Compute")
    
    for provider in "${providers[@]}"; do
        local status=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$status" != "Registered" ]]; then
            log "Registering provider: $provider"
            az provider register --namespace "$provider"
        else
            log "Provider $provider already registered"
        fi
    done
    
    # Wait for provider registration
    log "Waiting for provider registration to complete..."
    sleep 30
    
    success "Provider registration completed"
}

# Create DevCenter
create_devcenter() {
    log "Creating Azure DevCenter..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create DevCenter $DEVCENTER_NAME"
        return 0
    fi
    
    # Check if DevCenter already exists
    if az devcenter admin devcenter show --name "$DEVCENTER_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "DevCenter $DEVCENTER_NAME already exists"
    else
        az devcenter admin devcenter create \
            --name "$DEVCENTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --identity-type SystemAssigned
        success "DevCenter created"
    fi
    
    # Get the dev center's principal ID for role assignments
    export DEVCENTER_PRINCIPAL_ID=$(az devcenter admin devcenter show \
        --name "$DEVCENTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query identity.principalId \
        --output tsv)
    
    log "DevCenter Principal ID: $DEVCENTER_PRINCIPAL_ID"
    success "DevCenter configuration completed"
}

# Configure DevCenter permissions
configure_permissions() {
    log "Configuring DevCenter permissions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would assign Contributor and User Access Administrator roles"
        return 0
    fi
    
    # Check if role assignments already exist
    local contributor_exists=$(az role assignment list \
        --assignee "$DEVCENTER_PRINCIPAL_ID" \
        --role "Contributor" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" \
        --query "length(@)" -o tsv)
    
    if [[ "$contributor_exists" == "0" ]]; then
        log "Assigning Contributor role..."
        az role assignment create \
            --assignee "$DEVCENTER_PRINCIPAL_ID" \
            --role "Contributor" \
            --scope "/subscriptions/$SUBSCRIPTION_ID"
    else
        log "Contributor role already assigned"
    fi
    
    local admin_exists=$(az role assignment list \
        --assignee "$DEVCENTER_PRINCIPAL_ID" \
        --role "User Access Administrator" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" \
        --query "length(@)" -o tsv)
    
    if [[ "$admin_exists" == "0" ]]; then
        log "Assigning User Access Administrator role..."
        az role assignment create \
            --assignee "$DEVCENTER_PRINCIPAL_ID" \
            --role "User Access Administrator" \
            --scope "/subscriptions/$SUBSCRIPTION_ID"
    else
        log "User Access Administrator role already assigned"
    fi
    
    success "DevCenter permissions configured"
}

# Attach QuickStart catalog
attach_catalog() {
    log "Attaching QuickStart catalog..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would attach QuickStart catalog from Microsoft GitHub repository"
        return 0
    fi
    
    # Check if catalog already exists
    if az devcenter admin catalog show \
        --name "QuickStartCatalog" \
        --dev-center "$DEVCENTER_NAME" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "QuickStart catalog already attached"
    else
        az devcenter admin catalog create \
            --name "QuickStartCatalog" \
            --dev-center "$DEVCENTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --git-hub uri="https://github.com/microsoft/devcenter-catalog.git" \
            --branch "main" \
            --path "/Environment-Definitions"
        
        # Wait for catalog sync
        log "Waiting for catalog synchronization..."
        sleep 60
        
        # Check sync status
        local sync_state=$(az devcenter admin catalog show \
            --name "QuickStartCatalog" \
            --dev-center "$DEVCENTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query syncState \
            --output tsv)
        
        log "Catalog sync state: $sync_state"
        success "QuickStart catalog attached and synchronized"
    fi
}

# Create environment types
create_environment_types() {
    log "Creating environment types..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create Development and Staging environment types"
        return 0
    fi
    
    local env_types=("Development" "Staging")
    
    for env_type in "${env_types[@]}"; do
        if az devcenter admin environment-type show \
            --name "$env_type" \
            --dev-center "$DEVCENTER_NAME" \
            --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log "Environment type $env_type already exists"
        else
            az devcenter admin environment-type create \
                --name "$env_type" \
                --dev-center "$DEVCENTER_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --tags purpose="${env_type,,}" cost-center=engineering
            log "Created environment type: $env_type"
        fi
    done
    
    success "Environment types created"
}

# Create network configuration
create_network_config() {
    log "Creating network configuration for Dev Boxes..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create virtual network and network connection"
        return 0
    fi
    
    local vnet_name="vnet-devbox-$RANDOM_SUFFIX"
    local nc_name="nc-devbox-$RANDOM_SUFFIX"
    
    # Create virtual network
    if az network vnet show --name "$vnet_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Virtual network $vnet_name already exists"
    else
        az network vnet create \
            --name "$vnet_name" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --address-prefix 10.0.0.0/16 \
            --subnet-name "snet-devbox" \
            --subnet-prefix 10.0.1.0/24
        success "Virtual network created"
    fi
    
    # Create network connection
    if az devcenter admin network-connection show \
        --name "$nc_name" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Network connection $nc_name already exists"
    else
        az devcenter admin network-connection create \
            --name "$nc_name" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --subnet-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/$vnet_name/subnets/snet-devbox" \
            --network-connection-type "AzureADJoin"
        success "Network connection created"
    fi
    
    # Attach network connection to dev center
    if az devcenter admin attached-network show \
        --name "default" \
        --dev-center "$DEVCENTER_NAME" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Network connection already attached to DevCenter"
    else
        az devcenter admin attached-network create \
            --name "default" \
            --dev-center "$DEVCENTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --network-connection-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DevCenter/networkConnections/$nc_name"
        success "Network connection attached to DevCenter"
    fi
}

# Create Dev Box definition
create_devbox_definition() {
    log "Creating Dev Box definition..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create Dev Box definition with Visual Studio"
        return 0
    fi
    
    local definition_name="VSEnterprise-8cpu-32gb"
    
    if az devcenter admin devbox-definition show \
        --name "$definition_name" \
        --dev-center "$DEVCENTER_NAME" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Dev Box definition $definition_name already exists"
    else
        az devcenter admin devbox-definition create \
            --name "$definition_name" \
            --dev-center "$DEVCENTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --image-reference id="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DevCenter/devcenters/$DEVCENTER_NAME/galleries/default/images/MicrosoftWindowsDesktop_windows-ent-cpc_win11-22h2-ent-cpc-vs2022" \
            --sku-name "general_i_8c32gb256ssd_v2" \
            --hibernate-support "Enabled"
        success "Dev Box definition created"
    fi
}

# Create project
create_project() {
    log "Creating project and configuring access..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create project $PROJECT_NAME"
        return 0
    fi
    
    # Create project
    if az devcenter admin project show \
        --name "$PROJECT_NAME" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Project $PROJECT_NAME already exists"
    else
        az devcenter admin project create \
            --name "$PROJECT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --dev-center-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DevCenter/devcenters/$DEVCENTER_NAME" \
            --description "Web application team development project"
        success "Project created"
    fi
    
    # Create project environment type
    if az devcenter admin project-environment-type show \
        --name "Development" \
        --project "$PROJECT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --dev-center "$DEVCENTER_NAME" &> /dev/null; then
        warning "Project environment type Development already exists"
    else
        az devcenter admin project-environment-type create \
            --name "Development" \
            --project "$PROJECT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --dev-center "$DEVCENTER_NAME" \
            --deployment-target-id "/subscriptions/$SUBSCRIPTION_ID" \
            --identity-type "SystemAssigned" \
            --status "Enabled"
        success "Project environment type created"
    fi
}

# Create Dev Box pool
create_devbox_pool() {
    log "Creating Dev Box pool..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create Dev Box pool with auto-stop schedule"
        return 0
    fi
    
    local pool_name="WebDevPool"
    
    # Create Dev Box pool
    if az devcenter admin pool show \
        --name "$pool_name" \
        --project "$PROJECT_NAME" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Dev Box pool $pool_name already exists"
    else
        az devcenter admin pool create \
            --name "$pool_name" \
            --project "$PROJECT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --devbox-definition-name "VSEnterprise-8cpu-32gb" \
            --network-connection-name "default" \
            --local-administrator "Enabled" \
            --location "$LOCATION"
        success "Dev Box pool created"
    fi
    
    # Create auto-stop schedule
    if az devcenter admin schedule show \
        --name "AutoStop-7PM" \
        --pool-name "$pool_name" \
        --project "$PROJECT_NAME" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Auto-stop schedule already exists"
    else
        az devcenter admin schedule create \
            --name "AutoStop-7PM" \
            --pool-name "$pool_name" \
            --project "$PROJECT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --state "Enabled" \
            --type "StopDevBox" \
            --frequency "Daily" \
            --time "19:00" \
            --timezone "Eastern Standard Time"
        success "Auto-stop schedule created"
    fi
}

# Assign developer access
assign_developer_access() {
    log "Assigning developer access..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would assign Dev Box User and Deployment Environments User roles"
        return 0
    fi
    
    # Get current user's object ID
    local current_user_id=$(az ad signed-in-user show --query id --output tsv)
    log "Current user ID: $current_user_id"
    
    # Assign Dev Box User role
    local devbox_role_exists=$(az role assignment list \
        --assignee "$current_user_id" \
        --role "DevCenter Dev Box User" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DevCenter/projects/$PROJECT_NAME" \
        --query "length(@)" -o tsv)
    
    if [[ "$devbox_role_exists" == "0" ]]; then
        az role assignment create \
            --assignee "$current_user_id" \
            --role "DevCenter Dev Box User" \
            --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DevCenter/projects/$PROJECT_NAME"
        log "Dev Box User role assigned"
    else
        log "Dev Box User role already assigned"
    fi
    
    # Assign Deployment Environments User role
    local env_role_exists=$(az role assignment list \
        --assignee "$current_user_id" \
        --role "Deployment Environments User" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DevCenter/projects/$PROJECT_NAME" \
        --query "length(@)" -o tsv)
    
    if [[ "$env_role_exists" == "0" ]]; then
        az role assignment create \
            --assignee "$current_user_id" \
            --role "Deployment Environments User" \
            --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DevCenter/projects/$PROJECT_NAME"
        log "Deployment Environments User role assigned"
    else
        log "Deployment Environments User role already assigned"
    fi
    
    success "Developer access configured"
}

# Validation
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would validate all deployed resources"
        return 0
    fi
    
    # Check DevCenter status
    local devcenter_status=$(az devcenter admin devcenter show \
        --name "$DEVCENTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query provisioningState \
        --output tsv)
    
    if [[ "$devcenter_status" == "Succeeded" ]]; then
        success "DevCenter is in Succeeded state"
    else
        error "DevCenter is in $devcenter_status state"
    fi
    
    # Check catalog sync status
    local catalog_status=$(az devcenter admin catalog show \
        --name "QuickStartCatalog" \
        --dev-center "$DEVCENTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query syncState \
        --output tsv)
    
    if [[ "$catalog_status" == "Succeeded" ]]; then
        success "Catalog is synchronized"
    else
        warning "Catalog sync state: $catalog_status"
    fi
    
    # Check project status
    local project_status=$(az devcenter admin project show \
        --name "$PROJECT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query provisioningState \
        --output tsv)
    
    if [[ "$project_status" == "Succeeded" ]]; then
        success "Project is in Succeeded state"
    else
        error "Project is in $project_status state"
    fi
    
    success "Deployment validation completed"
}

# Display next steps
show_next_steps() {
    log "Deployment completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Access the Developer Portal at: https://devportal.microsoft.com"
    echo "2. Navigate to your project: $PROJECT_NAME"
    echo "3. Create a new Dev Box from the WebDevPool"
    echo "4. Deploy environment templates from the QuickStart catalog"
    echo ""
    echo "Resources created:"
    echo "- Resource Group: $RESOURCE_GROUP"
    echo "- DevCenter: $DEVCENTER_NAME"
    echo "- Project: $PROJECT_NAME"
    echo "- Dev Box Pool: WebDevPool"
    echo "- Network: vnet-devbox-$RANDOM_SUFFIX"
    echo ""
    echo "Cost optimization:"
    echo "- Dev Boxes will auto-stop at 7 PM daily"
    echo "- Remember to delete unused deployment environments"
    echo "- Monitor costs in Azure Cost Management"
}

# Main deployment function
main() {
    log "Starting Azure Dev Box and Deployment Environments deployment..."
    
    check_prerequisites
    set_environment_variables
    create_resource_group
    register_providers
    create_devcenter
    configure_permissions
    attach_catalog
    create_environment_types
    create_network_config
    create_devbox_definition
    create_project
    create_devbox_pool
    assign_developer_access
    validate_deployment
    show_next_steps
    
    success "Deployment completed successfully!"
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may have been created."; exit 1' INT TERM

# Run main function
main "$@"