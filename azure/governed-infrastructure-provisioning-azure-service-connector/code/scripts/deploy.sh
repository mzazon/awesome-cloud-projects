#!/bin/bash

# Azure Self-Service Infrastructure Provisioning - Deployment Script
# This script deploys Azure Deployment Environments with Service Connector integration
# and associated workflow orchestration components

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Enable verbose logging for debugging
if [[ "${DEBUG:-false}" == "true" ]]; then
    set -x
fi

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version (minimum v2.50.0)
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command_exists openssl; then
        log_error "OpenSSL is required for generating random strings"
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set Azure region (can be overridden by environment variable)
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export RESOURCE_GROUP="${RESOURCE_GROUP_NAME:-rg-selfservice-infra}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export DEVCENTER_NAME="dc-selfservice-${RANDOM_SUFFIX}"
    export PROJECT_NAME="proj-development-${RANDOM_SUFFIX}"
    export CATALOG_NAME="catalog-templates-${RANDOM_SUFFIX}"
    export LOGIC_APP_NAME="logic-approval-${RANDOM_SUFFIX}"
    export EVENT_GRID_TOPIC="eg-deployment-events-${RANDOM_SUFFIX}"
    export KEY_VAULT_NAME="kv-secrets-${RANDOM_SUFFIX}"
    
    # Additional resource names
    export SQL_SERVER="sql-server-${RANDOM_SUFFIX}"
    export SQL_DATABASE="webapp-db"
    export STORAGE_ACCOUNT="st$(echo $RANDOM_SUFFIX | tr -d '-')"
    export LIFECYCLE_LOGIC_APP="logic-lifecycle-${RANDOM_SUFFIX}"
    
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "DevCenter: $DEVCENTER_NAME"
    log_info "Project: $PROJECT_NAME"
    
    log_success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP..."
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=selfservice-infrastructure environment=demo owner=platform-team
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create Key Vault
create_key_vault() {
    log_info "Creating Key Vault: $KEY_VAULT_NAME..."
    
    if az keyvault show --name "$KEY_VAULT_NAME" >/dev/null 2>&1; then
        log_warning "Key Vault $KEY_VAULT_NAME already exists"
    else
        az keyvault create \
            --name "$KEY_VAULT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku standard \
            --enable-rbac-authorization true
        
        log_success "Key Vault created: $KEY_VAULT_NAME"
    fi
}

# Function to create Event Grid topic
create_event_grid_topic() {
    log_info "Creating Event Grid topic: $EVENT_GRID_TOPIC..."
    
    if az eventgrid topic show --name "$EVENT_GRID_TOPIC" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Event Grid topic $EVENT_GRID_TOPIC already exists"
    else
        az eventgrid topic create \
            --name "$EVENT_GRID_TOPIC" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION"
        
        log_success "Event Grid topic created: $EVENT_GRID_TOPIC"
    fi
}

# Function to create DevCenter
create_devcenter() {
    log_info "Creating Azure Deployment Environments DevCenter: $DEVCENTER_NAME..."
    
    if az devcenter admin devcenter show --name "$DEVCENTER_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "DevCenter $DEVCENTER_NAME already exists"
    else
        az devcenter admin devcenter create \
            --name "$DEVCENTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --identity-type SystemAssigned
        
        log_success "DevCenter created: $DEVCENTER_NAME"
    fi
    
    # Get the DevCenter principal ID for role assignments
    export DEVCENTER_PRINCIPAL_ID=$(az devcenter admin devcenter show \
        --name "$DEVCENTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query identity.principalId --output tsv)
    
    log_info "DevCenter managed identity: $DEVCENTER_PRINCIPAL_ID"
}

# Function to create and configure catalog
create_catalog() {
    log_info "Creating environment catalog: $CATALOG_NAME..."
    
    if az devcenter admin catalog show --name "$CATALOG_NAME" --devcenter-name "$DEVCENTER_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Catalog $CATALOG_NAME already exists"
    else
        az devcenter admin catalog create \
            --name "$CATALOG_NAME" \
            --devcenter-name "$DEVCENTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --git-hub-repo-url "https://github.com/Azure/deployment-environments" \
            --git-hub-branch "main" \
            --git-hub-path "/Environments"
        
        log_success "Environment catalog created: $CATALOG_NAME"
    fi
    
    # Wait for catalog synchronization
    log_info "Waiting for catalog synchronization..."
    sleep 30
    
    # Check catalog sync status
    local sync_state=$(az devcenter admin catalog show \
        --name "$CATALOG_NAME" \
        --devcenter-name "$DEVCENTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "syncState" --output tsv)
    
    log_info "Catalog sync state: $sync_state"
    
    if [[ "$sync_state" != "Succeeded" ]]; then
        log_warning "Catalog synchronization may still be in progress. Current state: $sync_state"
    fi
}

# Function to create project
create_project() {
    log_info "Creating project: $PROJECT_NAME..."
    
    if az devcenter admin project show --name "$PROJECT_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Project $PROJECT_NAME already exists"
    else
        az devcenter admin project create \
            --name "$PROJECT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --devcenter-name "$DEVCENTER_NAME" \
            --location "$LOCATION" \
            --max-dev-boxes-per-user 3
        
        log_success "Project created: $PROJECT_NAME"
    fi
    
    # Configure project environment types
    log_info "Configuring project environment types..."
    
    az devcenter admin project-environment-type create \
        --project-name "$PROJECT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --environment-type-name "Development" \
        --deployment-target-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        --status Enabled || log_warning "Environment type may already exist"
    
    # Set up role assignments for current user
    local current_user_id=$(az ad signed-in-user show --query id --output tsv)
    
    az role assignment create \
        --assignee-object-id "$current_user_id" \
        --role "DevCenter Project Admin" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DevCenter/projects/${PROJECT_NAME}" || log_warning "Role assignment may already exist"
    
    log_success "Project environment type and permissions configured"
}

# Function to create Logic Apps
create_logic_apps() {
    log_info "Creating Logic App for approval workflow: $LOGIC_APP_NAME..."
    
    if az logic workflow show --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Logic App $LOGIC_APP_NAME already exists"
    else
        # Create approval workflow Logic App
        local logic_app_definition='{
            "$schema": "https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {
                "manual": {
                    "type": "Request",
                    "kind": "Http"
                }
            },
            "actions": {
                "approve_environment": {
                    "type": "Http",
                    "inputs": {
                        "method": "POST",
                        "uri": "https://management.azure.com/subscriptions/'${SUBSCRIPTION_ID}'/resourceGroups/'${RESOURCE_GROUP}'/providers/Microsoft.DevCenter/projects/'${PROJECT_NAME}'/environments/approve"
                    }
                }
            }
        }'
        
        az logic workflow create \
            --name "$LOGIC_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --definition "$logic_app_definition"
        
        log_success "Approval Logic App created: $LOGIC_APP_NAME"
    fi
    
    # Create lifecycle management Logic App
    log_info "Creating lifecycle management Logic App: $LIFECYCLE_LOGIC_APP..."
    
    if az logic workflow show --name "$LIFECYCLE_LOGIC_APP" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Lifecycle Logic App $LIFECYCLE_LOGIC_APP already exists"
    else
        local lifecycle_definition='{
            "$schema": "https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {
                "recurrence": {
                    "type": "Recurrence",
                    "recurrence": {
                        "frequency": "Day",
                        "interval": 1
                    }
                }
            },
            "actions": {
                "check_environment_expiry": {
                    "type": "Http",
                    "inputs": {
                        "method": "GET",
                        "uri": "https://management.azure.com/subscriptions/'${SUBSCRIPTION_ID}'/resourceGroups/'${RESOURCE_GROUP}'/providers/Microsoft.DevCenter/projects/'${PROJECT_NAME}'/environments"
                    }
                }
            }
        }'
        
        az logic workflow create \
            --name "$LIFECYCLE_LOGIC_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --definition "$lifecycle_definition"
        
        log_success "Lifecycle Logic App created: $LIFECYCLE_LOGIC_APP"
    fi
}

# Function to configure Event Grid integration
configure_event_grid() {
    log_info "Configuring Event Grid integration..."
    
    # Get Logic App trigger URL
    local logic_app_url=$(az logic workflow show \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "accessEndpoint" --output tsv)
    
    # Create storage account for dead letter events
    if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS
        
        log_success "Storage account created: $STORAGE_ACCOUNT"
    else
        log_warning "Storage account $STORAGE_ACCOUNT already exists"
    fi
    
    # Create Event Grid subscription
    local subscription_name="deployment-approval-subscription"
    
    if ! az eventgrid event-subscription show \
        --name "$subscription_name" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DevCenter/projects/${PROJECT_NAME}" >/dev/null 2>&1; then
        
        az eventgrid event-subscription create \
            --name "$subscription_name" \
            --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DevCenter/projects/${PROJECT_NAME}" \
            --endpoint-type webhook \
            --endpoint "${logic_app_url}/triggers/manual/invoke" \
            --included-event-types "Microsoft.DevCenter.EnvironmentCreated" \
                                 "Microsoft.DevCenter.EnvironmentDeleted" \
                                 "Microsoft.DevCenter.EnvironmentDeploymentCompleted"
        
        log_success "Event Grid subscription created"
    else
        log_warning "Event Grid subscription already exists"
    fi
}

# Function to create SQL Database for demo
create_sql_database() {
    log_info "Creating SQL Database for demo: $SQL_SERVER..."
    
    if ! az sql server show --name "$SQL_SERVER" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        # Generate a random password
        local sql_password="P@ssw0rd$(openssl rand -hex 4)!"
        
        az sql server create \
            --name "$SQL_SERVER" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --admin-user "sqladmin" \
            --admin-password "$sql_password" \
            --enable-ad-only-auth false
        
        # Store password in Key Vault
        az keyvault secret set \
            --vault-name "$KEY_VAULT_NAME" \
            --name "sql-admin-password" \
            --value "$sql_password"
        
        log_success "SQL Server created: $SQL_SERVER"
        log_info "SQL admin password stored in Key Vault"
    else
        log_warning "SQL Server $SQL_SERVER already exists"
    fi
    
    # Create database
    if ! az sql db show --name "$SQL_DATABASE" --server "$SQL_SERVER" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        az sql db create \
            --name "$SQL_DATABASE" \
            --server "$SQL_SERVER" \
            --resource-group "$RESOURCE_GROUP" \
            --service-objective S0
        
        log_success "SQL Database created: $SQL_DATABASE"
    else
        log_warning "SQL Database $SQL_DATABASE already exists"
    fi
}

# Function to configure environment tagging
configure_tagging() {
    log_info "Configuring environment tagging for lifecycle management..."
    
    az tag create \
        --resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        --tags "environment-expiry=7days" "auto-cleanup=enabled" "cost-center=development" || log_warning "Tags may already exist"
    
    log_success "Environment tagging configured"
}

# Function to display deployment summary
display_summary() {
    log_success "🎉 Deployment completed successfully!"
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "DevCenter: $DEVCENTER_NAME"
    echo "Project: $PROJECT_NAME"
    echo "Catalog: $CATALOG_NAME"
    echo "Key Vault: $KEY_VAULT_NAME"
    echo "Event Grid Topic: $EVENT_GRID_TOPIC"
    echo "Logic Apps:"
    echo "  - Approval: $LOGIC_APP_NAME"
    echo "  - Lifecycle: $LIFECYCLE_LOGIC_APP"
    echo "SQL Server: $SQL_SERVER"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo ""
    echo "=== NEXT STEPS ==="
    echo "1. Verify DevCenter and Project configuration:"
    echo "   az devcenter admin devcenter show --name $DEVCENTER_NAME --resource-group $RESOURCE_GROUP"
    echo ""
    echo "2. List available environment definitions:"
    echo "   az devcenter dev environment-definition list --project-name $PROJECT_NAME --dev-center-name $DEVCENTER_NAME"
    echo ""
    echo "3. Create a test environment:"
    echo "   az devcenter dev environment create --project-name $PROJECT_NAME --dev-center-name $DEVCENTER_NAME --environment-name test-env --environment-type Development --catalog-name $CATALOG_NAME --environment-definition-name WebApp"
    echo ""
    echo "4. Clean up resources when done:"
    echo "   ./destroy.sh"
    echo ""
}

# Function to handle cleanup on error
cleanup_on_error() {
    log_error "Deployment failed. Check the error messages above."
    log_info "You may need to run the destroy script to clean up partial deployments."
    exit 1
}

# Main deployment function
main() {
    log_info "Starting Azure Self-Service Infrastructure Provisioning deployment..."
    echo "=== Azure Deployment Environments with Service Connector ==="
    echo ""
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Execute deployment steps
    validate_prerequisites
    setup_environment
    create_resource_group
    create_key_vault
    create_event_grid_topic
    create_devcenter
    create_catalog
    create_project
    create_logic_apps
    configure_event_grid
    create_sql_database
    configure_tagging
    
    # Display completion summary
    display_summary
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi