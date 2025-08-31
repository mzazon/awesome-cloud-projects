#!/bin/bash

# Deployment script for Simple Expense Tracker with Cosmos DB and Functions
# This script creates all Azure resources needed for the expense tracking solution

set -euo pipefail

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

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check the error messages above."
    log_warning "You may need to run destroy.sh to clean up partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if required tools are available
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required but not installed."
        exit 1
    fi
    
    if ! command -v zip &> /dev/null; then
        log_error "zip is required but not installed."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-expense-tracker-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set unique resource names
    export COSMOS_ACCOUNT="cosmos-expenses-${RANDOM_SUFFIX}"
    export FUNCTION_APP="func-expenses-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stexpenses${RANDOM_SUFFIX}"
    
    # Validate storage account name (must be 3-24 characters, lowercase letters and numbers only)
    if [[ ${#STORAGE_ACCOUNT} -gt 24 ]]; then
        log_error "Storage account name too long: ${STORAGE_ACCOUNT}"
        exit 1
    fi
    
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Cosmos Account: ${COSMOS_ACCOUNT}"
    log_info "Function App: ${FUNCTION_APP}"
    log_info "Storage Account: ${STORAGE_ACCOUNT}"
    
    log_success "Environment variables configured"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists, skipping creation"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=recipe environment=demo created_by=deploy_script
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Create Cosmos DB account
create_cosmos_db() {
    log_info "Creating Azure Cosmos DB serverless account..."
    
    if az cosmosdb show --name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Cosmos DB account ${COSMOS_ACCOUNT} already exists, skipping creation"
    else
        az cosmosdb create \
            --name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --locations regionName="${LOCATION}" \
            --capabilities EnableServerless \
            --default-consistency-level Session \
            --tags purpose=recipe environment=demo
        
        log_success "Cosmos DB serverless account created: ${COSMOS_ACCOUNT}"
    fi
}

# Create database and container
create_database_container() {
    log_info "Creating database and container..."
    
    # Create database
    if az cosmosdb sql database show --account-name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" --name ExpenseDB &> /dev/null; then
        log_warning "Database ExpenseDB already exists, skipping creation"
    else
        az cosmosdb sql database create \
            --account-name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --name ExpenseDB
        
        log_success "Database ExpenseDB created"
    fi
    
    # Create container
    if az cosmosdb sql container show --account-name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" --database-name ExpenseDB --name Expenses &> /dev/null; then
        log_warning "Container Expenses already exists, skipping creation"
    else
        az cosmosdb sql container create \
            --account-name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --database-name ExpenseDB \
            --name Expenses \
            --partition-key-path "/userId"
        
        log_success "Container Expenses created with partition key /userId"
    fi
}

# Get Cosmos DB connection string
get_cosmos_connection() {
    log_info "Retrieving Cosmos DB connection string..."
    
    export COSMOS_CONNECTION_STRING=$(az cosmosdb keys list \
        --name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --type connection-strings \
        --query 'connectionStrings[0].connectionString' \
        --output tsv)
    
    if [[ -z "${COSMOS_CONNECTION_STRING}" ]]; then
        log_error "Failed to retrieve Cosmos DB connection string"
        exit 1
    fi
    
    log_success "Connection string retrieved and stored"
}

# Create storage account
create_storage_account() {
    log_info "Creating storage account for Function App..."
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Storage account ${STORAGE_ACCOUNT} already exists, skipping creation"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --tags purpose=recipe environment=demo
        
        log_success "Storage account created: ${STORAGE_ACCOUNT}"
    fi
}

# Create Function App
create_function_app() {
    log_info "Creating Function App with Cosmos DB integration..."
    
    if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Function App ${FUNCTION_APP} already exists, skipping creation"
    else
        az functionapp create \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime node \
            --functions-version 4 \
            --os-type Linux \
            --tags purpose=recipe environment=demo
        
        log_success "Function App created: ${FUNCTION_APP}"
    fi
    
    # Configure Cosmos DB connection
    log_info "Configuring Cosmos DB connection..."
    az functionapp config appsettings set \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "CosmosDBConnection=${COSMOS_CONNECTION_STRING}"
    
    log_success "Cosmos DB connection configured"
}

# Create function code
create_function_code() {
    log_info "Creating function code..."
    
    # Create function directory structure
    rm -rf expense-functions
    mkdir -p expense-functions/CreateExpense
    mkdir -p expense-functions/GetExpenses
    
    # Create CreateExpense function
    cat > expense-functions/CreateExpense/function.json << 'EOF'
{
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["post"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    },
    {
      "type": "cosmosDB",
      "direction": "out",
      "name": "expense",
      "databaseName": "ExpenseDB",
      "containerName": "Expenses",
      "connection": "CosmosDBConnection",
      "createIfNotExists": false
    }
  ]
}
EOF
    
    cat > expense-functions/CreateExpense/index.js << 'EOF'
module.exports = async function (context, req) {
    try {
        const { amount, category, description, userId } = req.body;
        
        if (!amount || !category || !userId) {
            context.res = {
                status: 400,
                body: { error: "Missing required fields: amount, category, userId" }
            };
            return;
        }
        
        const expense = {
            id: require('crypto').randomUUID(),
            amount: parseFloat(amount),
            category: category,
            description: description || "",
            userId: userId,
            createdAt: new Date().toISOString()
        };
        
        context.bindings.expense = expense;
        
        context.res = {
            status: 201,
            body: expense
        };
    } catch (error) {
        context.res = {
            status: 500,
            body: { error: "Internal server error" }
        };
    }
};
EOF
    
    # Create GetExpenses function
    cat > expense-functions/GetExpenses/function.json << 'EOF'
{
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["get"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    },
    {
      "type": "cosmosDB",
      "direction": "in",
      "name": "expenses",
      "databaseName": "ExpenseDB",
      "containerName": "Expenses",
      "connection": "CosmosDBConnection",
      "sqlQuery": "SELECT * FROM c WHERE c.userId = {userId} AND (IS_NULL({category}) OR c.category = {category}) ORDER BY c.createdAt DESC"
    }
  ]
}
EOF
    
    cat > expense-functions/GetExpenses/index.js << 'EOF'
module.exports = async function (context, req) {
    try {
        const userId = req.query.userId;
        const category = req.query.category;
        
        if (!userId) {
            context.res = {
                status: 400,
                body: { error: "Missing required query parameter: userId" }
            };
            return;
        }
        
        context.res = {
            status: 200,
            body: {
                expenses: context.bindings.expenses || [],
                count: context.bindings.expenses ? context.bindings.expenses.length : 0,
                filteredBy: category ? { category } : null
            }
        };
    } catch (error) {
        context.res = {
            status: 500,
            body: { error: "Internal server error" }
        };
    }
};
EOF
    
    log_success "Function code created"
}

# Deploy functions
deploy_functions() {
    log_info "Deploying functions to Azure..."
    
    # Create deployment package
    cd expense-functions
    zip -r ../functions.zip . > /dev/null
    cd ..
    
    # Deploy functions to Azure
    az functionapp deployment source config-zip \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --src functions.zip
    
    # Wait for deployment to complete
    log_info "Waiting for deployment to complete..."
    sleep 30
    
    log_success "Functions deployed successfully to Azure"
}

# Get function URLs
get_function_urls() {
    log_info "Retrieving function URLs..."
    
    # Wait a bit more for functions to be fully ready
    sleep 10
    
    # Get function keys
    local create_key=$(az functionapp function keys list \
        --function-name CreateExpense \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "default" \
        --output tsv 2>/dev/null || echo "")
    
    local get_key=$(az functionapp function keys list \
        --function-name GetExpenses \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "default" \
        --output tsv 2>/dev/null || echo "")
    
    # Get function app hostname
    local hostname=$(az functionapp show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "defaultHostName" \
        --output tsv)
    
    if [[ -n "${create_key}" ]]; then
        export CREATE_URL="https://${hostname}/api/CreateExpense?code=${create_key}"
    else
        export CREATE_URL="https://${hostname}/api/CreateExpense"
        log_warning "Could not retrieve function key for CreateExpense"
    fi
    
    if [[ -n "${get_key}" ]]; then
        export GET_URL="https://${hostname}/api/GetExpenses?code=${get_key}"
    else
        export GET_URL="https://${hostname}/api/GetExpenses"
        log_warning "Could not retrieve function key for GetExpenses"
    fi
    
    log_success "Function URLs retrieved"
}

# Perform basic validation
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Function App status
    local status=$(az functionapp show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "state" \
        --output tsv)
    
    if [[ "${status}" != "Running" ]]; then
        log_warning "Function App status is: ${status} (expected: Running)"
    else
        log_success "Function App is running"
    fi
    
    # Check if Cosmos DB is accessible
    if az cosmosdb show --name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" --query "provisioningState" --output tsv | grep -q "Succeeded"; then
        log_success "Cosmos DB is ready"
    else
        log_warning "Cosmos DB may not be fully ready yet"
    fi
    
    log_success "Basic validation completed"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > deployment-info.txt << EOF
Simple Expense Tracker Deployment Information
============================================

Resource Group: ${RESOURCE_GROUP}
Location: ${LOCATION}
Cosmos DB Account: ${COSMOS_ACCOUNT}
Function App: ${FUNCTION_APP}
Storage Account: ${STORAGE_ACCOUNT}

Function URLs:
- Create Expense: ${CREATE_URL}
- Get Expenses: ${GET_URL}

Test Commands:
# Create an expense
curl -X POST "${CREATE_URL}" \\
    -H "Content-Type: application/json" \\
    -d '{
      "amount": 15.50,
      "category": "food",
      "description": "Lunch at cafe",
      "userId": "user123"
    }'

# Get expenses for a user
curl "${GET_URL}?userId=user123"

# Get expenses for a specific category
curl "${GET_URL}?userId=user123&category=food"

Cleanup:
To remove all resources, run: ./destroy.sh

Deployment completed at: $(date)
EOF
    
    log_success "Deployment information saved to deployment-info.txt"
}

# Main deployment function
main() {
    log_info "Starting Azure Expense Tracker deployment..."
    log_info "This will create Azure Cosmos DB and Functions resources"
    
    check_prerequisites
    setup_environment
    create_resource_group
    create_cosmos_db
    create_database_container
    get_cosmos_connection
    create_storage_account
    create_function_app
    create_function_code
    deploy_functions
    get_function_urls
    validate_deployment
    save_deployment_info
    
    echo
    log_success "🎉 Deployment completed successfully!"
    echo
    echo -e "${GREEN}Next steps:${NC}"
    echo "1. Review deployment-info.txt for URLs and test commands"
    echo "2. Test the API using the provided curl commands"
    echo "3. Monitor costs in the Azure portal"
    echo "4. Run ./destroy.sh when you're done to clean up resources"
    echo
    echo -e "${YELLOW}Estimated monthly cost: $0.01-$5.00 for light usage${NC}"
}

# Run main function
main "$@"