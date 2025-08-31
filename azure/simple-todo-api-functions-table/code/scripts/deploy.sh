#!/bin/bash

# Azure Simple Todo API with Functions and Table Storage - Deployment Script
# This script deploys a complete serverless Todo API using Azure Functions and Table Storage
# Following the recipe: Simple Todo API with Functions and Table Storage

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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
        log_error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it first."
        log_info "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI login
    check_azure_login
    
    # Check if curl is available for testing
    if ! command_exists curl; then
        log_warning "curl is not available. API testing will be skipped."
    fi
    
    # Check if node/npm is available for function deployment
    if ! command_exists node; then
        log_warning "Node.js is not available. Function deployment may require additional setup."
    fi
    
    log_success "Prerequisites validated successfully"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique resource names
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-todo-api-$(openssl rand -hex 3)}"
    export LOCATION="${LOCATION:-eastus}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-todostorage$(openssl rand -hex 3)}"
    export FUNCTION_APP="${FUNCTION_APP:-todo-api-$(openssl rand -hex 3)}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Validate storage account name (must be 3-24 characters, lowercase letters and numbers only)
    if [[ ${#STORAGE_ACCOUNT} -gt 24 ]]; then
        export STORAGE_ACCOUNT="todostorage$(openssl rand -hex 2)"
        log_warning "Storage account name too long, shortened to: ${STORAGE_ACCOUNT}"
    fi
    
    # Validate function app name (must be globally unique)
    if [[ ${#FUNCTION_APP} -gt 60 ]]; then
        export FUNCTION_APP="todo-api-$(openssl rand -hex 2)"
        log_warning "Function app name too long, shortened to: ${FUNCTION_APP}"
    fi
    
    log_info "Environment variables:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Location: ${LOCATION}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT}"
    log_info "  Function App: ${FUNCTION_APP}"
    log_info "  Subscription ID: ${SUBSCRIPTION_ID}"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists, skipping creation"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=recipe environment=demo created_by=deploy_script \
            --output table
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT}"
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Storage account ${STORAGE_ACCOUNT} already exists, skipping creation"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --output table
        
        # Wait for storage account to be ready
        log_info "Waiting for storage account to be ready..."
        sleep 10
        
        log_success "Storage account created: ${STORAGE_ACCOUNT}"
    fi
    
    # Get storage account connection string
    log_info "Retrieving storage connection string..."
    export STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString \
        --output tsv)
    
    if [[ -z "${STORAGE_CONNECTION_STRING}" ]]; then
        log_error "Failed to retrieve storage connection string"
        exit 1
    fi
    
    log_success "Storage connection string retrieved"
}

# Function to create function app
create_function_app() {
    log_info "Creating Function App: ${FUNCTION_APP}"
    
    if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Function App ${FUNCTION_APP} already exists, skipping creation"
    else
        az functionapp create \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime node \
            --runtime-version 18 \
            --functions-version 4 \
            --output table
        
        # Wait for function app to be ready
        log_info "Waiting for Function App to be ready..."
        sleep 30
        
        log_success "Function App created: ${FUNCTION_APP}"
    fi
}

# Function to configure application settings
configure_app_settings() {
    log_info "Configuring application settings..."
    
    az functionapp config appsettings set \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "AZURE_STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION_STRING}" \
        --output table
    
    log_success "Application settings configured"
}

# Function to create table storage
create_table_storage() {
    log_info "Creating table 'todos' in storage account..."
    
    # Check if table already exists
    if az storage table exists \
        --name todos \
        --connection-string "${STORAGE_CONNECTION_STRING}" \
        --query exists \
        --output tsv | grep -q "true"; then
        log_warning "Table 'todos' already exists, skipping creation"
    else
        az storage table create \
            --name todos \
            --connection-string "${STORAGE_CONNECTION_STRING}" \
            --output table
        
        log_success "Table 'todos' created successfully"
    fi
}

# Function to create function project structure
create_function_project() {
    log_info "Creating function project structure..."
    
    # Create temporary directory for function project
    TEMP_DIR=$(mktemp -d)
    export FUNCTION_PROJECT_DIR="${TEMP_DIR}/todo-functions"
    
    mkdir -p "${FUNCTION_PROJECT_DIR}/src/functions"
    cd "${FUNCTION_PROJECT_DIR}"
    
    log_info "Function project directory: ${FUNCTION_PROJECT_DIR}"
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "todo-api-functions",
  "version": "1.0.0",
  "description": "Simple Todo API using Azure Functions and Table Storage",
  "main": "src/functions/*.js",
  "scripts": {
    "start": "func start",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "dependencies": {
    "@azure/functions": "^4.0.0",
    "@azure/data-tables": "^13.3.1"
  },
  "devDependencies": {
    "azure-functions-core-tools": "^4.0.0"
  }
}
EOF
    
    # Create function code
    cat > src/functions/todoApi.js << 'EOF'
const { app } = require('@azure/functions');
const { TableClient } = require('@azure/data-tables');

// Initialize Table Storage client
const connectionString = process.env.AZURE_STORAGE_CONNECTION_STRING;
const tableClient = TableClient.fromConnectionString(connectionString, 'todos');

// Helper function to generate unique ID
function generateId() {
    return Date.now().toString() + Math.random().toString(36).substr(2, 9);
}

// CREATE - Add new todo
app.http('createTodo', {
    methods: ['POST'],
    route: 'todos',
    handler: async (request, context) => {
        try {
            const body = await request.json();
            
            // Input validation
            if (!body.title || body.title.trim() === '') {
                return { 
                    status: 400, 
                    jsonBody: { error: 'Title is required' } 
                };
            }
            
            const todo = {
                partitionKey: 'todos',
                rowKey: generateId(),
                title: body.title.trim(),
                description: body.description || '',
                completed: body.completed || false,
                createdAt: new Date().toISOString()
            };

            await tableClient.createEntity(todo);
            
            return { 
                status: 201,
                jsonBody: {
                    id: todo.rowKey,
                    title: todo.title,
                    description: todo.description,
                    completed: todo.completed,
                    createdAt: todo.createdAt
                }
            };
        } catch (error) {
            context.error('Error creating todo:', error);
            return { 
                status: 500, 
                jsonBody: { error: 'Failed to create todo' } 
            };
        }
    }
});

// READ - Get all todos
app.http('getTodos', {
    methods: ['GET'],
    route: 'todos',
    handler: async (request, context) => {
        try {
            const entities = tableClient.listEntities({
                filter: "PartitionKey eq 'todos'"
            });
            
            const todos = [];
            for await (const entity of entities) {
                todos.push({
                    id: entity.rowKey,
                    title: entity.title,
                    description: entity.description,
                    completed: entity.completed,
                    createdAt: entity.createdAt
                });
            }
            
            return { 
                status: 200,
                jsonBody: todos 
            };
        } catch (error) {
            context.error('Error fetching todos:', error);
            return { 
                status: 500, 
                jsonBody: { error: 'Failed to fetch todos' } 
            };
        }
    }
});

// UPDATE - Update existing todo
app.http('updateTodo', {
    methods: ['PUT'],
    route: 'todos/{id}',
    handler: async (request, context) => {
        try {
            const id = request.params.id;
            const body = await request.json();
            
            // Input validation
            if (!body.title || body.title.trim() === '') {
                return { 
                    status: 400, 
                    jsonBody: { error: 'Title is required' } 
                };
            }
            
            const entity = {
                partitionKey: 'todos',
                rowKey: id,
                title: body.title.trim(),
                description: body.description || '',
                completed: body.completed || false,
                updatedAt: new Date().toISOString()
            };
            
            await tableClient.updateEntity(entity, 'Merge');
            
            return { 
                status: 200,
                jsonBody: {
                    id: entity.rowKey,
                    title: entity.title,
                    description: entity.description,
                    completed: entity.completed,
                    updatedAt: entity.updatedAt
                }
            };
        } catch (error) {
            if (error.statusCode === 404) {
                return { 
                    status: 404, 
                    jsonBody: { error: 'Todo not found' } 
                };
            }
            context.error('Error updating todo:', error);
            return { 
                status: 500, 
                jsonBody: { error: 'Failed to update todo' } 
            };
        }
    }
});

// DELETE - Remove todo
app.http('deleteTodo', {
    methods: ['DELETE'],
    route: 'todos/{id}',
    handler: async (request, context) => {
        try {
            const id = request.params.id;
            
            await tableClient.deleteEntity('todos', id);
            
            return { 
                status: 204 
            };
        } catch (error) {
            if (error.statusCode === 404) {
                return { 
                    status: 404, 
                    jsonBody: { error: 'Todo not found' } 
                };
            }
            context.error('Error deleting todo:', error);
            return { 
                status: 500, 
                jsonBody: { error: 'Failed to delete todo' } 
            };
        }
    }
});
EOF
    
    log_success "Function project structure created"
}

# Function to deploy functions
deploy_functions() {
    log_info "Deploying functions to Azure..."
    
    cd "${FUNCTION_PROJECT_DIR}"
    
    # Install dependencies if npm is available
    if command_exists npm; then
        log_info "Installing npm dependencies..."
        npm install --silent
        log_success "Dependencies installed"
    else
        log_warning "npm not available, skipping dependency installation"
    fi
    
    # Create deployment package
    log_info "Creating deployment package..."
    zip -r todo-functions.zip . -x "*.git*" "node_modules/.cache/*" >/dev/null 2>&1
    
    # Deploy using Azure CLI
    log_info "Uploading and deploying functions..."
    az functionapp deployment source config-zip \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --src todo-functions.zip \
        --output table
    
    # Wait for deployment to complete
    log_info "Waiting for deployment to complete..."
    sleep 20
    
    # Get Function App URL
    export FUNCTION_APP_URL=$(az functionapp show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query defaultHostName \
        --output tsv)
    
    log_success "Functions deployed successfully"
    log_success "Function App URL: https://${FUNCTION_APP_URL}"
    
    # Clean up temporary files
    cd - >/dev/null
    rm -rf "${TEMP_DIR}"
}

# Function to test the deployment
test_deployment() {
    if ! command_exists curl; then
        log_warning "curl not available, skipping deployment tests"
        return
    fi
    
    log_info "Testing deployed API..."
    
    # Wait a bit more for functions to be ready
    sleep 10
    
    local api_url="https://${FUNCTION_APP_URL}/api/todos"
    
    # Test GET (should return empty array initially)
    log_info "Testing GET /api/todos..."
    local get_response=$(curl -s -w "%{http_code}" -o /tmp/get_response.json "${api_url}" || echo "000")
    
    if [[ "${get_response}" == "200" ]]; then
        log_success "GET test passed"
    else
        log_warning "GET test returned HTTP ${get_response}"
    fi
    
    # Test POST (create a todo)
    log_info "Testing POST /api/todos..."
    local post_response=$(curl -s -w "%{http_code}" -o /tmp/post_response.json \
        -X POST "${api_url}" \
        -H "Content-Type: application/json" \
        -d '{"title":"Test Todo","description":"Created by deployment script","completed":false}' || echo "000")
    
    if [[ "${post_response}" == "201" ]]; then
        log_success "POST test passed"
        # Extract todo ID for further tests
        if command_exists jq; then
            export TEST_TODO_ID=$(jq -r '.id' /tmp/post_response.json 2>/dev/null || echo "")
        fi
    else
        log_warning "POST test returned HTTP ${post_response}"
    fi
    
    # Clean up test files
    rm -f /tmp/get_response.json /tmp/post_response.json
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "========================================"
    echo "         DEPLOYMENT SUMMARY"
    echo "========================================"
    echo "Resource Group:    ${RESOURCE_GROUP}"
    echo "Location:          ${LOCATION}"
    echo "Storage Account:   ${STORAGE_ACCOUNT}"
    echo "Function App:      ${FUNCTION_APP}"
    echo "API Base URL:      https://${FUNCTION_APP_URL}/api"
    echo
    echo "API Endpoints:"
    echo "  GET    /todos     - List all todos"
    echo "  POST   /todos     - Create new todo"
    echo "  PUT    /todos/{id} - Update todo"
    echo "  DELETE /todos/{id} - Delete todo"
    echo
    echo "Example API calls:"
    echo "  curl https://${FUNCTION_APP_URL}/api/todos"
    echo "  curl -X POST https://${FUNCTION_APP_URL}/api/todos \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"title\":\"My Todo\",\"description\":\"Description\"}'"
    echo
    echo "To clean up all resources, run:"
    echo "  ./destroy.sh"
    echo "========================================"
}

# Main deployment function
main() {
    log_info "Starting Azure Simple Todo API deployment..."
    echo
    
    validate_prerequisites
    setup_environment
    create_resource_group
    create_storage_account
    create_function_app
    configure_app_settings
    create_table_storage
    create_function_project
    deploy_functions
    test_deployment
    display_summary
    
    log_success "Deployment script completed successfully!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi