#!/bin/bash

#######################################
# Azure URL Shortener Deployment Script
# Deploys Azure Functions and Table Storage for URL shortening service
# Author: Recipe Generator
# Version: 1.0
#######################################

set -euo pipefail
IFS=$'\n\t'

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Configuration variables with defaults
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-url-shortener-$(openssl rand -hex 3)}"
LOCATION="${LOCATION:-eastus}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-urlstore$(openssl rand -hex 3)}"
FUNCTION_APP="${FUNCTION_APP:-url-shortener-$(openssl rand -hex 3)}"
TABLE_NAME="${TABLE_NAME:-urlmappings}"
DRY_RUN="${DRY_RUN:-false}"

# Display banner
echo "=================================================="
echo "Azure URL Shortener Deployment Script"
echo "=================================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "Storage Account: $STORAGE_ACCOUNT"
echo "Function App: $FUNCTION_APP"
echo "Table Name: $TABLE_NAME"
echo "Dry Run: $DRY_RUN"
echo "=================================================="

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI first."
    fi
    
    # Check Azure CLI version
    AZ_VERSION=$(az version --query '."azure-cli"' -o tsv)
    log_info "Azure CLI version: $AZ_VERSION"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Get subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    log_info "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    
    # Check if required tools are available
    if ! command -v openssl &> /dev/null; then
        error_exit "OpenSSL is not available. Required for generating random strings."
    fi
    
    if ! command -v node &> /dev/null; then
        log_warning "Node.js not found locally. Function deployment will use Azure's runtime."
    else
        NODE_VERSION=$(node --version)
        log_info "Node.js version: $NODE_VERSION"
    fi
    
    log_success "Prerequisites check completed"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return 0
    fi
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=recipe environment=demo created-by=deployment-script \
        --output table
    
    log_success "Resource group created: $RESOURCE_GROUP"
}

# Create storage account
create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create storage account: $STORAGE_ACCOUNT"
        return 0
    fi
    
    # Check if storage account already exists
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Storage account $STORAGE_ACCOUNT already exists"
        return 0
    fi
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --output table
    
    log_success "Storage account created: $STORAGE_ACCOUNT"
}

# Create function app
create_function_app() {
    log_info "Creating Function App: $FUNCTION_APP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Function App: $FUNCTION_APP"
        return 0
    fi
    
    # Check if function app already exists
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Function App $FUNCTION_APP already exists"
        return 0
    fi
    
    az functionapp create \
        --resource-group "$RESOURCE_GROUP" \
        --consumption-plan-location "$LOCATION" \
        --runtime node \
        --runtime-version 20 \
        --functions-version 4 \
        --name "$FUNCTION_APP" \
        --storage-account "$STORAGE_ACCOUNT" \
        --disable-app-insights false \
        --output table
    
    log_success "Function App created: $FUNCTION_APP"
}

# Configure storage connection
configure_storage_connection() {
    log_info "Configuring storage connection for Function App"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure storage connection"
        return 0
    fi
    
    # Get storage account connection string
    STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    # Configure Function App with storage connection
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings "STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION" \
        --output table
    
    log_success "Storage connection configured"
}

# Create URL mappings table
create_table() {
    log_info "Creating URL mappings table: $TABLE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create table: $TABLE_NAME"
        return 0
    fi
    
    # Get storage account connection string
    STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    # Check if table already exists
    if az storage table exists \
        --name "$TABLE_NAME" \
        --connection-string "$STORAGE_CONNECTION" \
        --query exists \
        --output tsv | grep -q "true"; then
        log_warning "Table $TABLE_NAME already exists"
        return 0
    fi
    
    # Create table for storing URL mappings
    az storage table create \
        --name "$TABLE_NAME" \
        --connection-string "$STORAGE_CONNECTION" \
        --output table
    
    log_success "Table created: $TABLE_NAME"
}

# Deploy function code
deploy_functions() {
    log_info "Deploying function code"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy function code"
        return 0
    fi
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    log_info "Creating function code in temporary directory: $TEMP_DIR"
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "url-shortener-functions",
  "version": "1.0.0",
  "main": "src/functions/*.js",
  "dependencies": {
    "@azure/functions": "^4.5.1",
    "@azure/data-tables": "^13.3.1"
  }
}
EOF
    
    # Create source directory structure
    mkdir -p src/functions
    
    # Create shorten function
    cat > src/functions/shorten.js << 'EOF'
const { app } = require('@azure/functions');
const { TableClient } = require('@azure/data-tables');

app.http('shorten', {
    methods: ['POST'],
    authLevel: 'anonymous',
    handler: async (request, context) => {
        try {
            const body = await request.json();
            const originalUrl = body.url;

            if (!originalUrl) {
                return {
                    status: 400,
                    jsonBody: { error: 'URL is required' }
                };
            }

            // Validate URL format
            try {
                new URL(originalUrl);
            } catch {
                return {
                    status: 400,
                    jsonBody: { error: 'Invalid URL format' }
                };
            }

            // Generate short code (6 characters)
            const shortCode = Math.random().toString(36).substring(2, 8);

            // Initialize Table client
            const tableClient = TableClient.fromConnectionString(
                process.env.STORAGE_CONNECTION_STRING,
                'urlmappings'
            );

            // Store URL mapping
            const entity = {
                partitionKey: shortCode,
                rowKey: shortCode,
                originalUrl: originalUrl,
                createdAt: new Date().toISOString(),
                clickCount: 0
            };

            await tableClient.createEntity(entity);

            return {
                status: 201,
                jsonBody: {
                    shortCode: shortCode,
                    shortUrl: `https://${request.headers.get('host')}/api/${shortCode}`,
                    originalUrl: originalUrl
                }
            };
        } catch (error) {
            context.error('Error in shorten function:', error);
            return {
                status: 500,
                jsonBody: { error: 'Internal server error' }
            };
        }
    }
});
EOF
    
    # Create redirect function
    cat > src/functions/redirect.js << 'EOF'
const { app } = require('@azure/functions');
const { TableClient } = require('@azure/data-tables');

app.http('redirect', {
    methods: ['GET'],
    authLevel: 'anonymous',
    route: '{shortCode}',
    handler: async (request, context) => {
        try {
            const shortCode = request.params.shortCode;

            if (!shortCode) {
                return {
                    status: 400,
                    jsonBody: { error: 'Short code is required' }
                };
            }

            // Initialize Table client
            const tableClient = TableClient.fromConnectionString(
                process.env.STORAGE_CONNECTION_STRING,
                'urlmappings'
            );

            // Lookup URL mapping
            const entity = await tableClient.getEntity(shortCode, shortCode);

            if (!entity) {
                return {
                    status: 404,
                    jsonBody: { error: 'Short URL not found' }
                };
            }

            // Increment click count (optional analytics)
            entity.clickCount = (entity.clickCount || 0) + 1;
            await tableClient.updateEntity(entity, 'Replace');

            // Redirect to original URL
            return {
                status: 302,
                headers: {
                    'Location': entity.originalUrl,
                    'Cache-Control': 'no-cache'
                }
            };
        } catch (error) {
            if (error.statusCode === 404) {
                return {
                    status: 404,
                    jsonBody: { error: 'Short URL not found' }
                };
            }
            
            context.error('Error in redirect function:', error);
            return {
                status: 500,
                jsonBody: { error: 'Internal server error' }
            };
        }
    }
});
EOF
    
    # Create host.json
    cat > host.json << 'EOF'
{
  "version": "2.0",
  "functionTimeout": "00:05:00",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true
      }
    }
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  }
}
EOF
    
    # Create deployment package
    log_info "Creating deployment package"
    zip -r function-app.zip . -x "*.git*" "node_modules/*" > /dev/null
    
    # Deploy to Function App
    log_info "Deploying to Function App (this may take a few minutes)..."
    az functionapp deployment source config-zip \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP" \
        --src function-app.zip \
        --output table
    
    # Wait for deployment to complete
    sleep 30
    
    # Clean up temporary directory
    cd /
    rm -rf "$TEMP_DIR"
    
    log_success "Functions deployed successfully"
}

# Get deployment outputs
get_outputs() {
    log_info "Retrieving deployment outputs"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would retrieve deployment outputs"
        return 0
    fi
    
    # Get Function App URL
    FUNCTION_URL=$(az functionapp show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP" \
        --query defaultHostName \
        --output tsv)
    
    echo ""
    echo "=================================================="
    echo "DEPLOYMENT OUTPUTS"
    echo "=================================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Function App Name: $FUNCTION_APP"
    echo "Function App URL: https://$FUNCTION_URL"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "Table Name: $TABLE_NAME"
    echo ""
    echo "API Endpoints:"
    echo "  - Shorten URL: POST https://$FUNCTION_URL/api/shorten"
    echo "  - Redirect: GET https://$FUNCTION_URL/api/{shortCode}"
    echo "=================================================="
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify deployment"
        return 0
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error_exit "Resource group $RESOURCE_GROUP not found"
    fi
    
    # Check if storage account exists
    if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        error_exit "Storage account $STORAGE_ACCOUNT not found"
    fi
    
    # Check if function app exists
    if ! az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        error_exit "Function App $FUNCTION_APP not found"
    fi
    
    # Check if table exists
    STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    if ! az storage table exists \
        --name "$TABLE_NAME" \
        --connection-string "$STORAGE_CONNECTION" \
        --query exists \
        --output tsv | grep -q "true"; then
        error_exit "Table $TABLE_NAME not found"
    fi
    
    log_success "Deployment verification completed"
}

# Main deployment function
main() {
    log_info "Starting deployment process"
    
    check_prerequisites
    create_resource_group
    create_storage_account
    create_function_app
    configure_storage_connection
    create_table
    deploy_functions
    
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_deployment
        get_outputs
    else
        log_info "Dry run completed - no resources were created"
    fi
    
    log_success "Deployment completed successfully!"
}

# Script usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group    Resource group name (default: auto-generated)"
    echo "  -l, --location          Azure region (default: eastus)"
    echo "  -s, --storage-account   Storage account name (default: auto-generated)"
    echo "  -f, --function-app      Function app name (default: auto-generated)"
    echo "  -t, --table-name        Table name (default: urlmappings)"
    echo "  -d, --dry-run          Perform dry run without creating resources"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP         Override resource group name"
    echo "  LOCATION              Override Azure region"
    echo "  STORAGE_ACCOUNT       Override storage account name"
    echo "  FUNCTION_APP          Override function app name"
    echo "  TABLE_NAME            Override table name"
    echo "  DRY_RUN               Set to 'true' for dry run"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 --dry-run"
    echo "  $0 --resource-group my-rg --location westus2"
    echo "  RESOURCE_GROUP=my-rg $0"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -s|--storage-account)
            STORAGE_ACCOUNT="$2"
            shift 2
            ;;
        -f|--function-app)
            FUNCTION_APP="$2"
            shift 2
            ;;
        -t|--table-name)
            TABLE_NAME="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run main function with error handling
if ! main; then
    error_exit "Deployment failed"
fi