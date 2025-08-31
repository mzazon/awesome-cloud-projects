#!/bin/bash

# Simple Daily Quote Generator - Azure Deployment Script
# This script deploys Azure Functions and Table Storage for serving random quotes

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Azure CLI login status
check_azure_login() {
    if ! az account show >/dev/null 2>&1; then
        log_error "Azure CLI not logged in. Please run 'az login' first."
        exit 1
    fi
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check Azure CLI
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $AZ_VERSION"
    
    # Check if logged in
    check_azure_login
    
    # Check subscription
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    log_info "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    
    # Check for required tools
    if ! command_exists openssl; then
        log_error "openssl is not installed. Please install it to generate random suffixes."
        exit 1
    fi
    
    if ! command_exists jq; then
        log_warning "jq is not installed. Some output formatting may be limited."
    fi
    
    log_success "Prerequisites validation completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-quote-generator-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set resource names with unique suffix
    export STORAGE_ACCOUNT="stquote${RANDOM_SUFFIX}"
    export FUNCTION_APP="func-quote-${RANDOM_SUFFIX}"
    
    # Validate storage account name (must be 3-24 characters, lowercase letters and numbers only)
    if [[ ${#STORAGE_ACCOUNT} -gt 24 ]]; then
        log_error "Storage account name is too long: $STORAGE_ACCOUNT"
        exit 1
    fi
    
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Storage Account: $STORAGE_ACCOUNT"
    log_info "Function App: $FUNCTION_APP"
    
    log_success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group..."
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=recipe environment=demo created_by=deploy_script
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account..."
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Storage account $STORAGE_ACCOUNT already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            --tags purpose=recipe component=storage
        
        log_success "Storage account created: $STORAGE_ACCOUNT"
    fi
    
    # Get storage account connection string
    export STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    if [[ -z "$STORAGE_CONNECTION" ]]; then
        log_error "Failed to get storage connection string"
        exit 1
    fi
    
    log_success "Storage connection string retrieved"
}

# Function to create function app
create_function_app() {
    log_info "Creating Function App..."
    
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Function App $FUNCTION_APP already exists"
    else
        az functionapp create \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --storage-account "$STORAGE_ACCOUNT" \
            --consumption-plan-location "$LOCATION" \
            --runtime node \
            --runtime-version 20 \
            --functions-version 4 \
            --os-type Linux \
            --tags purpose=recipe component=function
        
        log_success "Function App created: $FUNCTION_APP"
    fi
}

# Function to create table storage
create_table_storage() {
    log_info "Creating Table Storage for quotes..."
    
    # Check if table exists
    if az storage table exists \
        --name quotes \
        --account-name "$STORAGE_ACCOUNT" \
        --connection-string "$STORAGE_CONNECTION" \
        --query exists -o tsv | grep -q "true"; then
        log_warning "Table 'quotes' already exists"
    else
        az storage table create \
            --name quotes \
            --account-name "$STORAGE_ACCOUNT" \
            --connection-string "$STORAGE_CONNECTION"
        
        log_success "Table Storage 'quotes' created successfully"
    fi
}

# Function to populate table with sample data
populate_sample_data() {
    log_info "Populating table with sample quote data..."
    
    # Check if data already exists
    ENTITY_COUNT=$(az storage entity query \
        --table-name quotes \
        --filter "PartitionKey eq 'inspiration'" \
        --account-name "$STORAGE_ACCOUNT" \
        --connection-string "$STORAGE_CONNECTION" \
        --query "length(items)" -o tsv 2>/dev/null || echo "0")
    
    if [[ "$ENTITY_COUNT" -gt 0 ]]; then
        log_warning "Sample data already exists ($ENTITY_COUNT quotes found)"
        return
    fi
    
    # Insert sample inspirational quotes
    declare -a quotes=(
        "PartitionKey=inspiration RowKey=001 quote=\"The only way to do great work is to love what you do.\" author=\"Steve Jobs\" category=motivation"
        "PartitionKey=inspiration RowKey=002 quote=\"Innovation distinguishes between a leader and a follower.\" author=\"Steve Jobs\" category=innovation"
        "PartitionKey=inspiration RowKey=003 quote=\"Success is not final, failure is not fatal.\" author=\"Winston Churchill\" category=perseverance"
        "PartitionKey=inspiration RowKey=004 quote=\"The future belongs to those who believe in the beauty of their dreams.\" author=\"Eleanor Roosevelt\" category=dreams"
        "PartitionKey=inspiration RowKey=005 quote=\"It is during our darkest moments that we must focus to see the light.\" author=\"Aristotle\" category=hope"
    )
    
    for quote_data in "${quotes[@]}"; do
        if ! az storage entity insert \
            --table-name quotes \
            --entity $quote_data \
            --account-name "$STORAGE_ACCOUNT" \
            --connection-string "$STORAGE_CONNECTION" >/dev/null; then
            log_error "Failed to insert quote: $quote_data"
            exit 1
        fi
    done
    
    log_success "Sample quotes inserted into Table Storage"
}

# Function to create and deploy function code
deploy_function_code() {
    log_info "Creating and deploying function code..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    FUNCTION_DIR="$TEMP_DIR/quote-function"
    mkdir -p "$FUNCTION_DIR"
    
    # Create function.json for HTTP trigger configuration
    cat > "$FUNCTION_DIR/function.json" << 'EOF'
{
  "bindings": [
    {
      "authLevel": "anonymous",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["get"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    }
  ]
}
EOF
    
    # Create the main function code
    cat > "$FUNCTION_DIR/index.js" << 'EOF'
const { TableClient } = require("@azure/data-tables");

module.exports = async function (context, req) {
    try {
        // Initialize Table Storage client
        const connectionString = process.env.AzureWebJobsStorage;
        const tableClient = TableClient.fromConnectionString(connectionString, "quotes");
        
        // Query all quotes from the inspiration partition
        const quotes = [];
        const entities = tableClient.listEntities({
            filter: "PartitionKey eq 'inspiration'"
        });
        
        for await (const entity of entities) {
            quotes.push({
                id: entity.rowKey,
                quote: entity.quote,
                author: entity.author,
                category: entity.category
            });
        }
        
        if (quotes.length === 0) {
            context.res = {
                status: 404,
                headers: { "Content-Type": "application/json" },
                body: { error: "No quotes found" }
            };
            return;
        }
        
        // Select random quote
        const randomIndex = Math.floor(Math.random() * quotes.length);
        const selectedQuote = quotes[randomIndex];
        
        // Return successful response
        context.res = {
            status: 200,
            headers: {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "public, max-age=300"
            },
            body: {
                success: true,
                data: selectedQuote,
                timestamp: new Date().toISOString(),
                total_quotes: quotes.length
            }
        };
        
    } catch (error) {
        context.log.error('Error retrieving quote:', error);
        context.res = {
            status: 500,
            headers: { "Content-Type": "application/json" },
            body: { 
                success: false,
                error: "Internal server error",
                message: "Unable to retrieve quote at this time"
            }
        };
    }
};
EOF
    
    # Create package.json for dependencies
    cat > "$FUNCTION_DIR/package.json" << 'EOF'
{
  "name": "quote-generator-function",
  "version": "1.0.0",
  "description": "Azure Function for serving random inspirational quotes",
  "main": "index.js",
  "dependencies": {
    "@azure/data-tables": "^13.3.1"
  }
}
EOF
    
    # Create deployment package
    cd "$FUNCTION_DIR"
    ZIP_FILE="$TEMP_DIR/quote-function.zip"
    
    if command_exists zip; then
        zip -r "$ZIP_FILE" .
    else
        log_error "zip command not found. Please install zip utility."
        exit 1
    fi
    
    # Deploy function to Azure
    log_info "Deploying function to Azure..."
    az functionapp deployment source config-zip \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP" \
        --src "$ZIP_FILE"
    
    # Wait for deployment to complete
    log_info "Waiting for deployment to complete..."
    sleep 30
    
    # Cleanup temporary files
    cd - >/dev/null
    rm -rf "$TEMP_DIR"
    
    log_success "Function deployed successfully to Azure"
}

# Function to configure CORS and application settings
configure_function_app() {
    log_info "Configuring Function App settings..."
    
    # Enable CORS for web applications
    az functionapp cors add \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP" \
        --allowed-origins "*"
    
    # Verify storage connection is configured
    STORAGE_SETTING=$(az functionapp config appsettings list \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP" \
        --query "[?name=='AzureWebJobsStorage'].value" \
        --output tsv)
    
    if [[ -z "$STORAGE_SETTING" ]]; then
        log_error "Storage connection setting not found in Function App"
        exit 1
    fi
    
    log_success "Function app configured for cross-origin requests"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Function App status
    FUNCTION_STATUS=$(az functionapp show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP" \
        --query "state" \
        --output tsv)
    
    if [[ "$FUNCTION_STATUS" != "Running" ]]; then
        log_error "Function App is not running. Status: $FUNCTION_STATUS"
        exit 1
    fi
    
    # Check if quotes table has data
    QUOTE_COUNT=$(az storage entity query \
        --table-name quotes \
        --filter "PartitionKey eq 'inspiration'" \
        --account-name "$STORAGE_ACCOUNT" \
        --connection-string "$STORAGE_CONNECTION" \
        --query "length(items)" -o tsv)
    
    if [[ "$QUOTE_COUNT" -eq 0 ]]; then
        log_error "No quotes found in Table Storage"
        exit 1
    fi
    
    log_success "Deployment validation completed successfully"
    log_info "Function App Status: $FUNCTION_STATUS"
    log_info "Quotes in Table Storage: $QUOTE_COUNT"
}

# Function to display deployment summary
display_summary() {
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo ""
    log_info "Resource Details:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Storage Account: $STORAGE_ACCOUNT"
    echo "  Function App: $FUNCTION_APP"
    echo ""
    
    # Get function URL
    log_info "Getting Function URL..."
    FUNCTION_URL=$(az functionapp function show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP" \
        --function-name quote-function \
        --query invokeUrlTemplate \
        --output tsv 2>/dev/null || echo "Unable to retrieve function URL")
    
    if [[ "$FUNCTION_URL" != "Unable to retrieve function URL" ]]; then
        log_info "Quote API Endpoint: $FUNCTION_URL"
        echo ""
        log_info "Test your API with:"
        echo "  curl '$FUNCTION_URL'"
        if command_exists jq; then
            echo "  curl -s '$FUNCTION_URL' | jq '.'"
        fi
    else
        log_warning "Function URL could not be retrieved. The function may still be initializing."
        log_info "You can get the URL later with:"
        echo "  az functionapp function show --resource-group $RESOURCE_GROUP --name $FUNCTION_APP --function-name quote-function --query invokeUrlTemplate -o tsv"
    fi
    
    echo ""
    log_info "Cleanup Instructions:"
    echo "  To remove all resources, run: ./destroy.sh"
    echo "  Or manually delete resource group: az group delete --name $RESOURCE_GROUP --yes"
}

# Main execution function
main() {
    log_info "Starting Azure Simple Daily Quote Generator deployment..."
    echo ""
    
    validate_prerequisites
    setup_environment
    create_resource_group
    create_storage_account
    create_function_app
    create_table_storage
    populate_sample_data
    deploy_function_code
    configure_function_app
    validate_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi