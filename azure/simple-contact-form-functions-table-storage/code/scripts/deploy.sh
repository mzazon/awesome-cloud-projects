#!/bin/bash

# Deploy script for Simple Contact Form with Functions and Table Storage
# This script deploys the complete Azure infrastructure for a serverless contact form
# following the recipe: Simple Contact Form with Functions and Table Storage

set -euo pipefail

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command_exists openssl; then
        error "openssl is required for generating random strings. Please install it."
        exit 1
    fi
    
    # Check if zip is available for function deployment
    if ! command_exists zip; then
        error "zip is required for function deployment. Please install it."
        exit 1
    fi
    
    success "Prerequisites validation completed"
}

# Set default environment variables
set_default_variables() {
    log "Setting up environment variables..."
    
    # Generate unique suffix if not provided
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
        export RANDOM_SUFFIX
    fi
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-recipe-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-eastus}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stcontact${RANDOM_SUFFIX}}"
    export FUNCTION_APP="${FUNCTION_APP:-func-contact-${RANDOM_SUFFIX}}"
    export TABLE_NAME="${TABLE_NAME:-contacts}"
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    log "Resource Group: $RESOURCE_GROUP"
    log "Location: $LOCATION"
    log "Storage Account: $STORAGE_ACCOUNT"
    log "Function App: $FUNCTION_APP"
    log "Subscription ID: $SUBSCRIPTION_ID"
}

# Create resource group
create_resource_group() {
    log "Creating resource group..."
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warn "Resource group $RESOURCE_GROUP already exists, skipping creation"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=recipe environment=demo created-by=deploy-script
    
    success "Resource group created: $RESOURCE_GROUP"
}

# Create storage account
create_storage_account() {
    log "Creating storage account..."
    
    # Check if storage account already exists
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warn "Storage account $STORAGE_ACCOUNT already exists, skipping creation"
        return 0
    fi
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --tags purpose=recipe environment=demo
    
    success "Storage account created: $STORAGE_ACCOUNT"
}

# Create function app
create_function_app() {
    log "Creating Function App..."
    
    # Check if function app already exists
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warn "Function App $FUNCTION_APP already exists, skipping creation"
        return 0
    fi
    
    az functionapp create \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_ACCOUNT" \
        --consumption-plan-location "$LOCATION" \
        --runtime node \
        --runtime-version 20 \
        --functions-version 4 \
        --tags purpose=recipe environment=demo
    
    success "Function App created: $FUNCTION_APP"
}

# Configure table storage
configure_table_storage() {
    log "Configuring Table Storage..."
    
    # Get storage connection string
    local storage_connection
    storage_connection=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    # Check if table already exists
    if az storage table exists \
        --name "$TABLE_NAME" \
        --connection-string "$storage_connection" \
        --query exists \
        --output tsv | grep -q "true"; then
        warn "Table $TABLE_NAME already exists, skipping creation"
    else
        # Create table for contact submissions
        az storage table create \
            --name "$TABLE_NAME" \
            --connection-string "$storage_connection"
        
        success "Table Storage configured: $TABLE_NAME"
    fi
}

# Create function code
create_function_code() {
    log "Creating function code..."
    
    # Create temporary directory for function code
    local temp_dir
    temp_dir=$(mktemp -d)
    local function_dir="$temp_dir/contact-function"
    
    mkdir -p "$function_dir"
    cd "$function_dir"
    
    # Create function.json configuration
    cat > function.json << 'EOF'
{
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["post", "options"],
      "route": "contact"
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    },
    {
      "type": "table",
      "direction": "out",
      "name": "tableBinding",
      "tableName": "contacts",
      "connection": "AzureWebJobsStorage"
    }
  ]
}
EOF
    
    # Create the main function code
    cat > index.js << 'EOF'
module.exports = async function (context, req) {
    // Enable CORS for web requests
    context.res.headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    };

    // Handle preflight OPTIONS request
    if (req.method === 'OPTIONS') {
        context.res = {
            status: 200,
            headers: context.res.headers
        };
        return;
    }

    try {
        // Validate required fields
        const { name, email, message } = req.body || {};
        
        if (!name || !email || !message) {
            context.res = {
                status: 400,
                headers: context.res.headers,
                body: { 
                    error: "Missing required fields: name, email, message" 
                }
            };
            return;
        }

        // Basic email validation
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(email)) {
            context.res = {
                status: 400,
                headers: context.res.headers,
                body: { error: "Invalid email format" }
            };
            return;
        }

        // Create contact entity for Table Storage
        const contactEntity = {
            PartitionKey: "contacts",
            RowKey: `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
            Name: name.substring(0, 100), // Limit field length
            Email: email.substring(0, 100),
            Message: message.substring(0, 1000),
            SubmittedAt: new Date().toISOString(),
            IPAddress: req.headers['x-forwarded-for'] || 'unknown'
        };

        // Store in Table Storage using output binding
        context.bindings.tableBinding = contactEntity;

        // Return success response
        context.res = {
            status: 200,
            headers: context.res.headers,
            body: { 
                message: "Contact form submitted successfully",
                id: contactEntity.RowKey
            }
        };

    } catch (error) {
        context.log.error('Function error:', error);
        context.res = {
            status: 500,
            headers: context.res.headers,
            body: { error: "Internal server error" }
        };
    }
};
EOF
    
    # Create deployment package
    zip -r "$temp_dir/contact-function.zip" .
    
    # Store paths for deployment
    export FUNCTION_ZIP_PATH="$temp_dir/contact-function.zip"
    export TEMP_DIR="$temp_dir"
    
    success "Function code created and packaged"
}

# Deploy function code
deploy_function_code() {
    log "Deploying function code..."
    
    # Deploy function code to Azure
    az functionapp deployment source config-zip \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP" \
        --src "$FUNCTION_ZIP_PATH"
    
    # Wait for deployment to complete
    log "Waiting for deployment to complete..."
    sleep 30
    
    success "Function code deployed successfully"
}

# Configure application settings
configure_app_settings() {
    log "Configuring application settings..."
    
    # Get storage connection string
    local storage_connection
    storage_connection=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    # Set storage connection string for table binding
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings "AzureWebJobsStorage=$storage_connection"
    
    success "Application settings configured"
}

# Get function URL
get_function_url() {
    log "Retrieving function URL..."
    
    # Wait a bit more for function to be fully ready
    sleep 10
    
    # Get function key
    local function_key
    function_key=$(az functionapp keys list \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query "functionKeys.default" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$function_key" ]]; then
        warn "Could not retrieve function key immediately. The function may still be initializing."
        log "You can get the function URL later with:"
        log "az functionapp function show --resource-group $RESOURCE_GROUP --name $FUNCTION_APP --function-name contact-function --query invokeUrlTemplate --output tsv"
        return 0
    fi
    
    # Get function URL template
    local function_url_template
    function_url_template=$(az functionapp function show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP" \
        --function-name contact-function \
        --query "invokeUrlTemplate" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$function_url_template" ]]; then
        local function_url="${function_url_template}?code=${function_key}"
        success "Function URL: $function_url"
        
        # Store URL in a file for easy access
        echo "$function_url" > "${RESOURCE_GROUP}_function_url.txt"
        log "Function URL saved to: ${RESOURCE_GROUP}_function_url.txt"
    else
        warn "Could not retrieve function URL template. The function may still be initializing."
    fi
}

# Test deployment
test_deployment() {
    log "Testing deployment..."
    
    # Check Function App status
    local app_state
    app_state=$(az functionapp show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query "state" \
        --output tsv)
    
    if [[ "$app_state" == "Running" ]]; then
        success "Function App is running successfully"
    else
        warn "Function App state: $app_state (may still be starting up)"
    fi
    
    # Verify table exists
    local storage_connection
    storage_connection=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    if az storage table exists \
        --name "$TABLE_NAME" \
        --connection-string "$storage_connection" \
        --query exists \
        --output tsv | grep -q "true"; then
        success "Table Storage is configured correctly"
    else
        error "Table Storage verification failed"
        return 1
    fi
}

# Cleanup temporary files
cleanup_temp_files() {
    if [[ -n "${TEMP_DIR:-}" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log "Temporary files cleaned up"
    fi
}

# Main deployment function
main() {
    log "Starting deployment of Simple Contact Form with Functions and Table Storage"
    
    # Trap to ensure cleanup happens
    trap cleanup_temp_files EXIT
    
    validate_prerequisites
    set_default_variables
    create_resource_group
    create_storage_account
    create_function_app
    configure_table_storage
    create_function_code
    deploy_function_code
    configure_app_settings
    get_function_url
    test_deployment
    
    success "Deployment completed successfully!"
    log "Resource Group: $RESOURCE_GROUP"
    log "Function App: $FUNCTION_APP"
    log "Storage Account: $STORAGE_ACCOUNT"
    log "Table Name: $TABLE_NAME"
    
    if [[ -f "${RESOURCE_GROUP}_function_url.txt" ]]; then
        log "Function URL is saved in: ${RESOURCE_GROUP}_function_url.txt"
    fi
    
    log "You can now integrate this contact form API with your website"
    log "Remember to run the destroy script when you're done testing to avoid charges"
}

# Run main function
main "$@"