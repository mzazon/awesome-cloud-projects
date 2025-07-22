#!/bin/bash

# Azure Deployment Environments - Self-Service Infrastructure Lifecycle Management
# Deploy script for orchestrating infrastructure with Azure Deployment Environments and Azure Developer CLI
# Recipe: orchestrating-self-service-infrastructure-lifecycle-management-with-azure-deployment-environments-and-azure-developer-cli

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
handle_error() {
    log_error "Deployment failed on line $1"
    log_error "Command: $2"
    log_error "Cleaning up partially deployed resources..."
    
    # Basic cleanup on error
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log_warning "Attempting to clean up resource group: ${RESOURCE_GROUP}"
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait 2>/dev/null || true
    fi
    
    exit 1
}

trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

# Print banner
echo -e "${BLUE}"
echo "============================================================================="
echo "   Azure Deployment Environments - Self-Service Infrastructure Deployment"
echo "============================================================================="
echo -e "${NC}"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version (minimum 2.50.0)
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: $az_version"
    
    # Check if Azure Developer CLI is installed
    if ! command -v azd &> /dev/null; then
        log_error "Azure Developer CLI is not installed. Please install it from https://docs.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd"
        exit 1
    fi
    
    # Check Azure Developer CLI version (minimum 1.5.0)
    local azd_version=$(azd version | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
    log "Azure Developer CLI version: $azd_version"
    
    # Check if Git is installed
    if ! command -v git &> /dev/null; then
        log_error "Git is not installed. Please install Git."
        exit 1
    fi
    
    # Check if OpenSSL is installed for random string generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed. Please install OpenSSL."
        exit 1
    fi
    
    log_success "All prerequisites are met"
}

# Function to check Azure authentication
check_azure_auth() {
    log "Checking Azure authentication..."
    
    if ! az account show &> /dev/null; then
        log_error "Not authenticated to Azure. Please run 'az login' first."
        exit 1
    fi
    
    local account_name=$(az account show --query name -o tsv)
    local subscription_id=$(az account show --query id -o tsv)
    
    log_success "Authenticated to Azure"
    log "Account: $account_name"
    log "Subscription ID: $subscription_id"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-devcenter-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set specific resource names
    export DEVCENTER_NAME="dc-selfservice-${RANDOM_SUFFIX}"
    export PROJECT_NAME="proj-webapp-${RANDOM_SUFFIX}"
    export CATALOG_NAME="catalog-templates"
    export STORAGE_ACCOUNT="st${RANDOM_SUFFIX}templates"
    
    log_success "Environment variables set"
    log "Resource Group: $RESOURCE_GROUP"
    log "Location: $LOCATION"
    log "DevCenter Name: $DEVCENTER_NAME"
    log "Project Name: $PROJECT_NAME"
    log "Storage Account: $STORAGE_ACCOUNT"
}

# Function to register Azure providers
register_providers() {
    log "Registering required Azure providers..."
    
    # Register required resource providers
    az provider register --namespace Microsoft.DevCenter --wait
    az provider register --namespace Microsoft.DeploymentEnvironments --wait
    
    log_success "Azure providers registered successfully"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=infrastructure-lifecycle environment=demo
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
}

# Function to create Azure DevCenter
create_devcenter() {
    log "Creating Azure DevCenter with identity management..."
    
    # Create the DevCenter with system-assigned managed identity
    az devcenter admin devcenter create \
        --name "${DEVCENTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --identity-type SystemAssigned \
        --tags team=platform-engineering purpose=self-service
    
    # Wait for DevCenter to be fully provisioned
    log "Waiting for DevCenter to be fully provisioned..."
    sleep 60
    
    # Get the managed identity principal ID for RBAC assignments
    export DEVCENTER_IDENTITY=$(az devcenter admin devcenter show \
        --name "${DEVCENTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query identity.principalId --output tsv)
    
    log_success "DevCenter created with managed identity: ${DEVCENTER_IDENTITY}"
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account for infrastructure templates..."
    
    # Create storage account for template repository
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --allow-blob-public-access false \
        --https-only true
    
    # Create container for ARM templates
    az storage container create \
        --name templates \
        --account-name "${STORAGE_ACCOUNT}" \
        --auth-mode login
    
    # Grant DevCenter managed identity access to storage
    az role assignment create \
        --assignee "${DEVCENTER_IDENTITY}" \
        --role "Storage Blob Data Reader" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}"
    
    log_success "Storage account configured with DevCenter access"
}

# Function to create sample infrastructure templates
create_templates() {
    log "Creating sample infrastructure templates..."
    
    # Create a simple web app ARM template
    cat > webapp-template.json << 'EOF'
{
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "appName": {
            "type": "string",
            "defaultValue": "[concat('webapp-', uniqueString(resourceGroup().id))]"
        },
        "location": {
            "type": "string",
            "defaultValue": "[resourceGroup().location]"
        }
    },
    "resources": [
        {
            "type": "Microsoft.Web/serverfarms",
            "apiVersion": "2021-02-01",
            "name": "[concat(parameters('appName'), '-plan')]",
            "location": "[parameters('location')]",
            "sku": {
                "name": "F1",
                "tier": "Free"
            },
            "properties": {}
        },
        {
            "type": "Microsoft.Web/sites",
            "apiVersion": "2021-02-01",
            "name": "[parameters('appName')]",
            "location": "[parameters('location')]",
            "dependsOn": [
                "[resourceId('Microsoft.Web/serverfarms', concat(parameters('appName'), '-plan'))]"
            ],
            "properties": {
                "serverFarmId": "[resourceId('Microsoft.Web/serverfarms', concat(parameters('appName'), '-plan'))]"
            }
        }
    ],
    "outputs": {
        "webAppUrl": {
            "type": "string",
            "value": "[concat('https://', reference(parameters('appName')).defaultHostName)]"
        }
    }
}
EOF
    
    # Upload template to storage account
    az storage blob upload \
        --file webapp-template.json \
        --name webapp-environment.json \
        --container-name templates \
        --account-name "${STORAGE_ACCOUNT}" \
        --auth-mode login
    
    # Clean up local template file
    rm -f webapp-template.json
    
    log_success "Infrastructure template uploaded to catalog"
}

# Function to create environment catalog
create_catalog() {
    log "Creating environment catalog and definitions..."
    
    # Create catalog linked to storage account
    az devcenter admin catalog create \
        --name "${CATALOG_NAME}" \
        --devcenter-name "${DEVCENTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --git-hub-path "/" \
        --git-hub-branch main \
        --git-hub-secret-identifier "" \
        --git-hub-uri "https://${STORAGE_ACCOUNT}.blob.core.windows.net/templates"
    
    # Wait for catalog sync to complete
    log "Waiting for catalog sync to complete..."
    sleep 60
    
    # Create environment definition for web application
    az devcenter admin environment-definition create \
        --name "webapp-env" \
        --catalog-name "${CATALOG_NAME}" \
        --devcenter-name "${DEVCENTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --template-path "webapp-environment.json" \
        --description "Standard web application environment with App Service"
    
    log_success "Environment catalog and definitions configured"
}

# Function to configure environment types
configure_environment_types() {
    log "Configuring environment types and governance..."
    
    # Create development environment type with cost controls
    az devcenter admin environment-type create \
        --name "development" \
        --devcenter-name "${DEVCENTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --tags tier=development cost-center=engineering
    
    # Create staging environment type with enhanced monitoring
    az devcenter admin environment-type create \
        --name "staging" \
        --devcenter-name "${DEVCENTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --tags tier=staging cost-center=engineering monitoring=enhanced
    
    # Configure deployment subscription for environment types
    az devcenter admin environment-type update \
        --name "development" \
        --devcenter-name "${DEVCENTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-target-id "/subscriptions/${SUBSCRIPTION_ID}"
    
    az devcenter admin environment-type update \
        --name "staging" \
        --devcenter-name "${DEVCENTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-target-id "/subscriptions/${SUBSCRIPTION_ID}"
    
    log_success "Environment types configured with governance policies"
}

# Function to create project
create_project() {
    log "Creating project and assigning permissions..."
    
    # Create project for web application development
    az devcenter admin project create \
        --name "${PROJECT_NAME}" \
        --devcenter-name "${DEVCENTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --description "Web application development project with self-service environments"
    
    # Associate environment types with the project
    az devcenter admin project-environment-type create \
        --project-name "${PROJECT_NAME}" \
        --environment-type-name "development" \
        --devcenter-name "${DEVCENTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-target-id "/subscriptions/${SUBSCRIPTION_ID}" \
        --status Enabled
    
    az devcenter admin project-environment-type create \
        --project-name "${PROJECT_NAME}" \
        --environment-type-name "staging" \
        --devcenter-name "${DEVCENTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-target-id "/subscriptions/${SUBSCRIPTION_ID}" \
        --status Enabled
    
    # Get current user ID for RBAC assignment
    local USER_ID=$(az ad signed-in-user show --query id --output tsv)
    
    # Assign Deployment Environments User role to enable self-service
    az role assignment create \
        --assignee "${USER_ID}" \
        --role "Deployment Environments User" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DevCenter/projects/${PROJECT_NAME}"
    
    log_success "Project created with development team access"
}

# Function to configure Azure Developer CLI
configure_azd() {
    log "Configuring Azure Developer CLI integration..."
    
    # Configure azd to use Azure Deployment Environments
    azd config set platform.type devcenter
    
    # Create sample application directory
    mkdir -p webapp-sample
    cd webapp-sample
    
    # Create azure.yaml for azd integration
    cat > azure.yaml << EOF
name: webapp-sample
metadata:
  template: webapp-sample@1.0.0
platform:
  type: devcenter
services:
  web:
    project: ./src
    host: appservice
EOF
    
    # Create basic application structure
    mkdir -p src
    echo "<h1>Hello from Azure Deployment Environments!</h1>" > src/index.html
    
    cd ..
    
    log_success "Azure Developer CLI configured for deployment environments"
}

# Function to run validation tests
run_validation() {
    log "Running validation tests..."
    
    # Check DevCenter status and configuration
    log "Validating DevCenter configuration..."
    az devcenter admin devcenter show \
        --name "${DEVCENTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "provisioningState" \
        --output tsv
    
    # Verify environment types are configured
    log "Validating environment types..."
    local env_types=$(az devcenter admin environment-type list \
        --devcenter-name "${DEVCENTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "length([?provisioningState=='Succeeded'])" \
        --output tsv)
    
    if [[ $env_types -ge 2 ]]; then
        log_success "Environment types configured successfully"
    else
        log_error "Environment types not configured properly"
        exit 1
    fi
    
    # Verify RBAC assignments
    log "Validating RBAC assignments..."
    local rbac_count=$(az role assignment list \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DevCenter/projects/${PROJECT_NAME}" \
        --query "length([?roleDefinitionName=='Deployment Environments User'])" \
        --output tsv)
    
    if [[ $rbac_count -ge 1 ]]; then
        log_success "RBAC assignments configured successfully"
    else
        log_error "RBAC assignments not configured properly"
        exit 1
    fi
    
    log_success "All validation tests passed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    
    echo
    echo -e "${GREEN}============================================================================="
    echo "                          DEPLOYMENT SUMMARY"
    echo "=============================================================================${NC}"
    echo
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "DevCenter Name: ${DEVCENTER_NAME}"
    echo "Project Name: ${PROJECT_NAME}"
    echo "Storage Account: ${STORAGE_ACCOUNT}"
    echo "DevCenter Identity: ${DEVCENTER_IDENTITY}"
    echo
    echo "Environment Types Available:"
    echo "  - development"
    echo "  - staging"
    echo
    echo "Environment Definitions Available:"
    echo "  - webapp-env (Web Application with App Service)"
    echo
    echo "Next Steps:"
    echo "1. Test environment deployment using Azure CLI:"
    echo "   az devcenter dev environment create \\"
    echo "     --project-name ${PROJECT_NAME} \\"
    echo "     --endpoint \"https://${DEVCENTER_NAME}-${LOCATION}.devcenter.azure.com/\" \\"
    echo "     --environment-name \"test-env-\$(date +%s)\" \\"
    echo "     --environment-type \"development\" \\"
    echo "     --catalog-name ${CATALOG_NAME} \\"
    echo "     --environment-definition-name \"webapp-env\""
    echo
    echo "2. Use Azure Developer CLI for seamless deployment:"
    echo "   cd webapp-sample"
    echo "   azd auth login"
    echo "   azd init --template minimal"
    echo "   azd provision --environment development"
    echo
    echo "3. Access the Developer Portal:"
    echo "   https://devportal.microsoft.com/"
    echo
    echo -e "${GREEN}=============================================================================${NC}"
}

# Main execution
main() {
    check_prerequisites
    check_azure_auth
    set_environment_variables
    register_providers
    create_resource_group
    create_devcenter
    create_storage_account
    create_templates
    create_catalog
    configure_environment_types
    create_project
    configure_azd
    run_validation
    display_summary
}

# Run main function
main "$@"