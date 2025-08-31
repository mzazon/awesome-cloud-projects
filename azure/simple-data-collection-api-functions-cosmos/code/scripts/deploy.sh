#!/bin/bash

# =============================================================================
# Azure Simple Data Collection API Deployment Script
# =============================================================================
# This script deploys a serverless data collection API using Azure Functions 
# and Cosmos DB, following the infrastructure patterns from the recipe.
#
# Services deployed:
# - Azure Functions (Consumption plan)
# - Cosmos DB (NoSQL API) 
# - Storage Account (for Functions runtime)
# - Resource Group
#
# Prerequisites:
# - Azure CLI installed and configured
# - Azure Functions Core Tools v4.0.5382+
# - Node.js 18.x or 20.x
# - Appropriate Azure permissions
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# =============================================================================
# CONFIGURATION & GLOBAL VARIABLES
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration (can be overridden with environment variables)
LOCATION="${AZURE_LOCATION:-eastus}"
RESOURCE_GROUP_PREFIX="${RESOURCE_GROUP_PREFIX:-rg-data-api}"
COSMOS_ACCOUNT_PREFIX="${COSMOS_ACCOUNT_PREFIX:-cosmos-data}"
FUNCTION_APP_PREFIX="${FUNCTION_APP_PREFIX:-func-data-api}"
STORAGE_ACCOUNT_PREFIX="${STORAGE_ACCOUNT_PREFIX:-stdataapi}"
DATABASE_NAME="${DATABASE_NAME:-DataCollectionDB}"
CONTAINER_NAME="${CONTAINER_NAME:-records}"

# Generate unique suffix for resource names
RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"

# Resource names with unique suffix
RESOURCE_GROUP="${RESOURCE_GROUP_PREFIX}-${RANDOM_SUFFIX}"
COSMOS_ACCOUNT="${COSMOS_ACCOUNT_PREFIX}-${RANDOM_SUFFIX}"
FUNCTION_APP="${FUNCTION_APP_PREFIX}-${RANDOM_SUFFIX}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT_PREFIX}${RANDOM_SUFFIX}"

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Simple Data Collection API infrastructure.

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be deployed without actually deploying
    -c, --cleanup          Clean up resources on deployment failure
    -v, --verbose          Enable verbose logging
    -f, --force            Force deployment even if resources exist
    --location LOCATION    Azure region (default: $LOCATION)
    --suffix SUFFIX        Custom suffix for resource names (default: random)
    
ENVIRONMENT VARIABLES:
    AZURE_LOCATION         Azure region for deployment
    RESOURCE_GROUP_PREFIX  Prefix for resource group name
    RANDOM_SUFFIX         Custom suffix for unique resource names

EXAMPLES:
    $0                     # Deploy with default settings
    $0 --dry-run          # Preview deployment
    $0 --location westus2  # Deploy to specific region
    $0 --suffix prod01     # Use custom suffix

EOF
}

save_deployment_state() {
    cat > "$DEPLOYMENT_STATE_FILE" << EOF
RESOURCE_GROUP="$RESOURCE_GROUP"
COSMOS_ACCOUNT="$COSMOS_ACCOUNT"
FUNCTION_APP="$FUNCTION_APP"
STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
DATABASE_NAME="$DATABASE_NAME"
CONTAINER_NAME="$CONTAINER_NAME"
LOCATION="$LOCATION"
DEPLOYMENT_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    log_info "Deployment state saved to $DEPLOYMENT_STATE_FILE"
}

cleanup_on_failure() {
    log_warning "Deployment failed. Starting cleanup..."
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        source "$DEPLOYMENT_STATE_FILE"
        if az group exists --name "$RESOURCE_GROUP" &>/dev/null; then
            log_info "Deleting resource group: $RESOURCE_GROUP"
            az group delete --name "$RESOURCE_GROUP" --yes --no-wait || true
        fi
        rm -f "$DEPLOYMENT_STATE_FILE"
    fi
}

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI."
        return 1
    fi
    
    # Check Azure CLI login
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login'."
        return 1
    fi
    
    # Check Azure Functions Core Tools
    if ! command -v func &> /dev/null; then
        log_warning "Azure Functions Core Tools not found. Will skip function deployment."
        log_warning "Install with: npm install -g azure-functions-core-tools@4 --unsafe-perm true"
    else
        local func_version=$(func --version 2>/dev/null | head -n1)
        log_info "Azure Functions Core Tools version: $func_version"
    fi
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        log_warning "Node.js not found. Required for function deployment."
        log_warning "Install Node.js 18.x or 20.x from https://nodejs.org/"
    else
        local node_version=$(node --version)
        log_info "Node.js version: $node_version"
    fi
    
    # Check required Azure providers
    log_info "Checking Azure resource providers..."
    local providers=("Microsoft.Web" "Microsoft.DocumentDB" "Microsoft.Storage")
    for provider in "${providers[@]}"; do
        if ! az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null | grep -q "Registered"; then
            log_info "Registering provider: $provider"
            az provider register --namespace "$provider" --wait
        fi
    done
    
    # Get subscription info
    local subscription_id=$(az account show --query id -o tsv)
    local subscription_name=$(az account show --query name -o tsv)
    log_info "Using subscription: $subscription_name ($subscription_id)"
    
    # Check resource limits (basic validation)
    local rg_count=$(az group list --query "length(@)" -o tsv)
    if [[ $rg_count -gt 800 ]]; then
        log_warning "High number of resource groups ($rg_count). Consider cleanup."
    fi
    
    log_success "Prerequisites check completed"
    return 0
}

# =============================================================================
# DEPLOYMENT FUNCTIONS
# =============================================================================

deploy_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if az group exists --name "$RESOURCE_GROUP" &>/dev/null; then
        if [[ "${FORCE_DEPLOYMENT:-false}" == "true" ]]; then
            log_warning "Resource group exists, continuing due to --force flag"
        else
            log_error "Resource group '$RESOURCE_GROUP' already exists. Use --force to continue."
            return 1
        fi
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=recipe environment=demo created-by=deploy-script
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

deploy_cosmos_db() {
    log_info "Creating Cosmos DB account: $COSMOS_ACCOUNT"
    
    # Create Cosmos DB account
    az cosmosdb create \
        --name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --default-consistency-level Session \
        --locations regionName="$LOCATION" \
        --enable-automatic-failover false \
        --tags purpose=recipe environment=demo
    
    log_success "Cosmos DB account created: $COSMOS_ACCOUNT"
    
    # Create database
    log_info "Creating database: $DATABASE_NAME"
    az cosmosdb sql database create \
        --account-name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DATABASE_NAME"
    
    # Create container with partition key
    log_info "Creating container: $CONTAINER_NAME"
    az cosmosdb sql container create \
        --account-name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --database-name "$DATABASE_NAME" \
        --name "$CONTAINER_NAME" \
        --partition-key-path "/id" \
        --throughput 400
    
    log_success "Cosmos DB database and container created successfully"
}

deploy_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT"
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --tags purpose=recipe environment=demo
    
    log_success "Storage account created: $STORAGE_ACCOUNT"
}

deploy_function_app() {
    log_info "Creating Function App: $FUNCTION_APP"
    
    # Create Function App on Consumption plan
    az functionapp create \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_ACCOUNT" \
        --consumption-plan-location "$LOCATION" \
        --runtime node \
        --runtime-version 20 \
        --functions-version 4 \
        --tags purpose=recipe environment=demo
    
    log_success "Function App created: $FUNCTION_APP"
    
    # Get Cosmos DB connection string
    log_info "Configuring Function App settings..."
    local cosmos_connection
    cosmos_connection=$(az cosmosdb keys list \
        --name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --type connection-strings \
        --query "connectionStrings[0].connectionString" \
        --output tsv)
    
    # Configure Function App settings
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
        "COSMOS_DB_CONNECTION_STRING=$cosmos_connection" \
        "COSMOS_DB_DATABASE_NAME=$DATABASE_NAME" \
        "COSMOS_DB_CONTAINER_NAME=$CONTAINER_NAME" \
        > /dev/null
    
    log_success "Function App configuration completed"
}

deploy_function_code() {
    if ! command -v func &> /dev/null || ! command -v node &> /dev/null; then
        log_warning "Skipping function code deployment (missing tools)"
        log_info "To deploy function code manually:"
        log_info "1. Install Azure Functions Core Tools and Node.js"
        log_info "2. Run the function deployment commands from the recipe"
        return 0
    fi
    
    log_info "Deploying function code..."
    
    # Create temporary directory for function code
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Initialize Functions project
    func init --typescript --model V4
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "data-collection-api",
  "version": "1.0.0",
  "description": "Simple data collection API using Azure Functions and Cosmos DB",
  "main": "dist/src/functions/*.js",
  "scripts": {
    "build": "tsc",
    "watch": "tsc --watch",
    "prestart": "npm run build",
    "start": "func start",
    "test": "echo \"No tests yet\""
  },
  "dependencies": {
    "@azure/functions": "^4.5.0",
    "@azure/cosmos": "^4.0.0"
  },
  "devDependencies": {
    "@types/node": "^20.x",
    "typescript": "^5.0.0"
  }
}
EOF
    
    # Create the function code
    mkdir -p src/functions
    cat > src/functions/dataApi.ts << 'EOF'
import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { CosmosClient } from '@azure/cosmos';

// Initialize Cosmos DB client
const cosmosClient = new CosmosClient(process.env.COSMOS_DB_CONNECTION_STRING!);
const database = cosmosClient.database(process.env.COSMOS_DB_DATABASE_NAME!);
const container = database.container(process.env.COSMOS_DB_CONTAINER_NAME!);

// CREATE - Add new record
app.http('createRecord', {
    methods: ['POST'],
    route: 'records',
    authLevel: 'anonymous',
    handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
        try {
            const body = await request.json() as any;
            const record = {
                id: body.id || crypto.randomUUID(),
                ...body,
                createdAt: new Date().toISOString(),
                updatedAt: new Date().toISOString()
            };
            
            const { resource } = await container.items.create(record);
            context.log(`Created record with id: ${resource.id}`);
            
            return {
                status: 201,
                jsonBody: resource
            };
        } catch (error) {
            context.error('Error creating record:', error);
            return {
                status: 500,
                jsonBody: { error: 'Failed to create record' }
            };
        }
    }
});

// READ - Get all records
app.http('getRecords', {
    methods: ['GET'],
    route: 'records',
    authLevel: 'anonymous',
    handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
        try {
            const { resources } = await container.items.readAll().fetchAll();
            context.log(`Retrieved ${resources.length} records`);
            
            return {
                status: 200,
                jsonBody: resources
            };
        } catch (error) {
            context.error('Error retrieving records:', error);
            return {
                status: 500,
                jsonBody: { error: 'Failed to retrieve records' }
            };
        }
    }
});

// READ - Get specific record by ID
app.http('getRecord', {
    methods: ['GET'],
    route: 'records/{id}',
    authLevel: 'anonymous',
    handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
        try {
            const id = request.params.id;
            const { resource } = await container.item(id, id).read();
            
            if (!resource) {
                return {
                    status: 404,
                    jsonBody: { error: 'Record not found' }
                };
            }
            
            context.log(`Retrieved record with id: ${id}`);
            return {
                status: 200,
                jsonBody: resource
            };
        } catch (error) {
            context.error('Error retrieving record:', error);
            return {
                status: 500,
                jsonBody: { error: 'Failed to retrieve record' }
            };
        }
    }
});

// UPDATE - Update existing record
app.http('updateRecord', {
    methods: ['PUT'],
    route: 'records/{id}',
    authLevel: 'anonymous',
    handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
        try {
            const id = request.params.id;
            const body = await request.json() as any;
            
            const updatedRecord = {
                ...body,
                id: id,
                updatedAt: new Date().toISOString()
            };
            
            const { resource } = await container.item(id, id).replace(updatedRecord);
            context.log(`Updated record with id: ${id}`);
            
            return {
                status: 200,
                jsonBody: resource
            };
        } catch (error) {
            context.error('Error updating record:', error);
            return {
                status: 500,
                jsonBody: { error: 'Failed to update record' }
            };
        }
    }
});

// DELETE - Remove record
app.http('deleteRecord', {
    methods: ['DELETE'],
    route: 'records/{id}',
    authLevel: 'anonymous',
    handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
        try {
            const id = request.params.id;
            await container.item(id, id).delete();
            context.log(`Deleted record with id: ${id}`);
            
            return {
                status: 204
            };
        } catch (error) {
            context.error('Error deleting record:', error);
            return {
                status: 500,
                jsonBody: { error: 'Failed to delete record' }
            };
        }
    }
});
EOF
    
    # Install dependencies and build
    log_info "Installing dependencies..."
    npm install > /dev/null 2>&1
    
    log_info "Building function code..."
    npm run build > /dev/null 2>&1
    
    # Deploy to Azure
    log_info "Publishing functions to Azure..."
    func azure functionapp publish "$FUNCTION_APP" > /dev/null 2>&1
    
    # Cleanup temp directory
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    log_success "Function code deployed successfully"
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_deployment() {
    log_info "Validating deployment..."
    
    # Check resource group
    if ! az group exists --name "$RESOURCE_GROUP" &>/dev/null; then
        log_error "Resource group validation failed"
        return 1
    fi
    
    # Check Cosmos DB
    local cosmos_state
    cosmos_state=$(az cosmosdb show \
        --name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query "provisioningState" \
        -o tsv 2>/dev/null)
    
    if [[ "$cosmos_state" != "Succeeded" ]]; then
        log_error "Cosmos DB validation failed (state: $cosmos_state)"
        return 1
    fi
    
    # Check Function App
    local func_state
    func_state=$(az functionapp show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query "state" \
        -o tsv 2>/dev/null)
    
    if [[ "$func_state" != "Running" ]]; then
        log_error "Function App validation failed (state: $func_state)"
        return 1
    fi
    
    # Get Function App URL
    local function_url
    function_url=$(az functionapp show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query "defaultHostName" \
        -o tsv 2>/dev/null)
    
    log_success "Deployment validation completed successfully"
    log_info "API Base URL: https://${function_url}/api"
    
    return 0
}

show_deployment_summary() {
    log_success "=== DEPLOYMENT SUMMARY ==="
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Cosmos DB Account: $COSMOS_ACCOUNT"
    log_info "Function App: $FUNCTION_APP"
    log_info "Storage Account: $STORAGE_ACCOUNT"
    log_info "Database: $DATABASE_NAME"
    log_info "Container: $CONTAINER_NAME"
    
    # Get Function App URL
    local function_url
    function_url=$(az functionapp show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query "defaultHostName" \
        -o tsv 2>/dev/null)
    
    log_info ""
    log_success "API Endpoints:"
    log_info "  Base URL: https://${function_url}/api"
    log_info "  GET    /records        - List all records"
    log_info "  POST   /records        - Create new record"
    log_info "  GET    /records/{id}   - Get specific record"
    log_info "  PUT    /records/{id}   - Update record"
    log_info "  DELETE /records/{id}   - Delete record"
    
    log_info ""
    log_info "Test the API with:"
    log_info "  curl -X GET \"https://${function_url}/api/records\""
    
    log_info ""
    log_info "Deployment log: $LOG_FILE"
    log_info "State file: $DEPLOYMENT_STATE_FILE"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Parse command line arguments
    local dry_run=false
    local cleanup_on_fail=false
    local verbose=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -c|--cleanup)
                cleanup_on_fail=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -f|--force)
                FORCE_DEPLOYMENT=true
                shift
                ;;
            --location)
                LOCATION="$2"
                shift 2
                ;;
            --suffix)
                RANDOM_SUFFIX="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set up error handling
    if [[ "$cleanup_on_fail" == "true" ]]; then
        trap cleanup_on_failure ERR
    fi
    
    # Start deployment
    log_info "Starting Azure Simple Data Collection API deployment"
    log_info "Log file: $LOG_FILE"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "=== DRY RUN MODE ==="
        log_info "Would deploy the following resources:"
        log_info "  Resource Group: $RESOURCE_GROUP"
        log_info "  Location: $LOCATION" 
        log_info "  Cosmos DB: $COSMOS_ACCOUNT"
        log_info "  Function App: $FUNCTION_APP"
        log_info "  Storage Account: $STORAGE_ACCOUNT"
        log_info "No resources will be created."
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    deploy_resource_group
    save_deployment_state
    deploy_storage_account
    deploy_cosmos_db
    deploy_function_app
    deploy_function_code
    validate_deployment
    show_deployment_summary
    
    log_success "Deployment completed successfully!"
}

# Execute main function with all arguments
main "$@"