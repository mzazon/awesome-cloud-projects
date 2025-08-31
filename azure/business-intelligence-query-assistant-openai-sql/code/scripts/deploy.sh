#!/bin/bash

# Business Intelligence Query Assistant Deployment Script
# This script deploys the Azure Business Intelligence Query Assistant with OpenAI and SQL Database
# Author: Generated for Azure recipes repository
# Version: 1.0

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_LOG="deployment.log"
FUNCTION_PROJECT_DIR="bi-function"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${DEPLOYMENT_LOG}"
}

log_info() { log "INFO" "${BLUE}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }
log_warning() { log "WARNING" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Script failed at line ${line_number} with exit code ${exit_code}"
    log_error "Check ${DEPLOYMENT_LOG} for detailed error information"
    cleanup_on_failure
    exit ${exit_code}
}

trap 'handle_error $LINENO' ERR

# Cleanup function for failures
cleanup_on_failure() {
    log_warning "Deployment failed. Cleaning up partial resources..."
    
    if [[ -n "${RESOURCE_GROUP:-}" ]] && az group exists --name "${RESOURCE_GROUP}" &>/dev/null; then
        log_info "Deleting resource group: ${RESOURCE_GROUP}"
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait || true
    fi
    
    if [[ -d "${FUNCTION_PROJECT_DIR}" ]]; then
        log_info "Cleaning up local function project directory"
        rm -rf "${FUNCTION_PROJECT_DIR}" || true
    fi
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check Azure login status
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check Functions Core Tools
    if ! command -v func &> /dev/null; then
        log_error "Azure Functions Core Tools not found. Please install Azure Functions Core Tools v4."
        exit 1
    fi
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed. Please install Node.js 18+ first."
        exit 1
    fi
    
    # Check Node.js version
    local node_version=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [[ ${node_version} -lt 18 ]]; then
        log_error "Node.js version must be 18 or higher. Current version: $(node --version)"
        exit 1
    fi
    
    # Check npm
    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed. Please install npm first."
        exit 1
    fi
    
    # Check for required tools
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install openssl first."
        exit 1
    fi
    
    log_success "All prerequisites check passed"
}

# Environment setup
setup_environment() {
    log_info "Setting up deployment environment..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-bi-assistant-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set unique resource names
    export SQL_SERVER_NAME="sql-bi-server-${RANDOM_SUFFIX}"
    export SQL_DATABASE_NAME="BiAnalyticsDB"
    export FUNCTION_APP_NAME="func-bi-assistant-${RANDOM_SUFFIX}"
    export OPENAI_SERVICE_NAME="openai-bi-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="stbi${RANDOM_SUFFIX}"
    
    # SQL Server credentials
    export SQL_ADMIN_PASSWORD="${SQL_ADMIN_PASSWORD:-ComplexP@ssw0rd123!}"
    
    log_info "Environment configuration:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Location: ${LOCATION}"
    log_info "  SQL Server: ${SQL_SERVER_NAME}"
    log_info "  Function App: ${FUNCTION_APP_NAME}"
    log_info "  OpenAI Service: ${OPENAI_SERVICE_NAME}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
    
    # Save environment variables for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SQL_SERVER_NAME=${SQL_SERVER_NAME}
SQL_DATABASE_NAME=${SQL_DATABASE_NAME}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME}
OPENAI_SERVICE_NAME=${OPENAI_SERVICE_NAME}
STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
EOF
    
    log_success "Environment setup completed"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group..."
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=business-intelligence environment=demo
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
}

# Create Azure OpenAI Service
create_openai_service() {
    log_info "Creating Azure OpenAI Service..."
    
    # Create Azure OpenAI Service
    az cognitiveservices account create \
        --name "${OPENAI_SERVICE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --kind OpenAI \
        --sku S0 \
        --custom-domain "${OPENAI_SERVICE_NAME}"
    
    # Wait for service to be ready
    log_info "Waiting for OpenAI service to be ready..."
    sleep 30
    
    # Get OpenAI endpoint and key
    export OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "${OPENAI_SERVICE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.endpoint --output tsv)
    
    export OPENAI_KEY=$(az cognitiveservices account keys list \
        --name "${OPENAI_SERVICE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 --output tsv)
    
    log_success "Azure OpenAI Service created: ${OPENAI_SERVICE_NAME}"
    log_info "OpenAI Endpoint: ${OPENAI_ENDPOINT}"
}

# Deploy GPT-4o model
deploy_gpt_model() {
    log_info "Deploying GPT-4o model..."
    
    # Deploy GPT-4o model for natural language to SQL conversion
    az cognitiveservices account deployment create \
        --name "${OPENAI_SERVICE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-name gpt-4o \
        --model-name gpt-4o \
        --model-version "2024-11-20" \
        --model-format OpenAI \
        --sku-capacity 10 \
        --sku-name "Standard"
    
    log_success "GPT-4o model deployed successfully"
}

# Create SQL Database
create_sql_database() {
    log_info "Creating Azure SQL Database..."
    
    # Create SQL Server with Azure AD authentication
    az sql server create \
        --name "${SQL_SERVER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --admin-user sqladmin \
        --admin-password "${SQL_ADMIN_PASSWORD}" \
        --enable-ad-only-auth false
    
    # Create SQL Database
    az sql db create \
        --resource-group "${RESOURCE_GROUP}" \
        --server "${SQL_SERVER_NAME}" \
        --name "${SQL_DATABASE_NAME}" \
        --service-objective Basic \
        --backup-storage-redundancy Local
    
    # Configure firewall to allow Azure services
    az sql server firewall-rule create \
        --resource-group "${RESOURCE_GROUP}" \
        --server "${SQL_SERVER_NAME}" \
        --name AllowAzureServices \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0
    
    log_success "SQL Database created: ${SQL_DATABASE_NAME}"
}

# Create sample business data
create_sample_data() {
    log_info "Creating sample business data..."
    
    # Get SQL connection string
    export SQL_CONNECTION=$(az sql db show-connection-string \
        --client ado.net \
        --server "${SQL_SERVER_NAME}" \
        --name "${SQL_DATABASE_NAME}" \
        --output tsv | sed "s/<username>/sqladmin/g; s/<password>/${SQL_ADMIN_PASSWORD}/g")
    
    # Wait a moment for database to be fully ready
    sleep 15
    
    # Create sample business schema and data
    az sql db query \
        --server "${SQL_SERVER_NAME}" \
        --name "${SQL_DATABASE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "
        CREATE TABLE Customers (
            CustomerID INT IDENTITY(1,1) PRIMARY KEY,
            CompanyName NVARCHAR(100) NOT NULL,
            ContactName NVARCHAR(50),
            City NVARCHAR(50),
            Country NVARCHAR(50),
            Revenue DECIMAL(12,2)
        );
        
        CREATE TABLE Orders (
            OrderID INT IDENTITY(1,1) PRIMARY KEY,
            CustomerID INT FOREIGN KEY REFERENCES Customers(CustomerID),
            OrderDate DATE,
            TotalAmount DECIMAL(10,2),
            Status NVARCHAR(20)
        );
        
        INSERT INTO Customers VALUES 
        ('Contoso Corp', 'John Smith', 'Seattle', 'USA', 250000.00),
        ('Fabrikam Inc', 'Jane Doe', 'London', 'UK', 180000.00),
        ('Adventure Works', 'Bob Johnson', 'Toronto', 'Canada', 320000.00);
        
        INSERT INTO Orders VALUES 
        (1, '2024-01-15', 15000.00, 'Completed'),
        (2, '2024-01-20', 8500.00, 'Pending'),
        (3, '2024-01-25', 22000.00, 'Completed');"
    
    log_success "Sample business data created successfully"
}

# Create Function App
create_function_app() {
    log_info "Creating Function App with Storage Account..."
    
    # Create storage account for Function App
    az storage account create \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2
    
    # Create Function App
    az functionapp create \
        --resource-group "${RESOURCE_GROUP}" \
        --consumption-plan-location "${LOCATION}" \
        --runtime node \
        --runtime-version 18 \
        --functions-version 4 \
        --name "${FUNCTION_APP_NAME}" \
        --storage-account "${STORAGE_ACCOUNT_NAME}" \
        --disable-app-insights false
    
    log_success "Function App created: ${FUNCTION_APP_NAME}"
}

# Configure Function App settings
configure_function_app() {
    log_info "Configuring Function App settings..."
    
    # Configure Function App settings with OpenAI and SQL connections
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        "AZURE_OPENAI_ENDPOINT=${OPENAI_ENDPOINT}" \
        "AZURE_OPENAI_KEY=${OPENAI_KEY}" \
        "AZURE_OPENAI_DEPLOYMENT=gpt-4o" \
        "SQL_CONNECTION_STRING=${SQL_CONNECTION}" \
        "FUNCTIONS_EXTENSION_VERSION=~4" \
        "WEBSITE_NODE_DEFAULT_VERSION=~18"
    
    log_success "Function App configured with OpenAI and SQL settings"
}

# Deploy Function code
deploy_function_code() {
    log_info "Deploying Business Intelligence Query Function..."
    
    # Create local function project structure
    mkdir -p "${FUNCTION_PROJECT_DIR}/QueryProcessor"
    cd "${FUNCTION_PROJECT_DIR}"
    
    # Initialize Azure Functions project
    func init --javascript --worker-runtime node
    
    # Create new function
    func new --name QueryProcessor --template "HTTP trigger" --authlevel function
    
    # Create package.json for dependencies
    cat > package.json << 'EOF'
{
  "name": "bi-query-assistant",
  "version": "1.0.0",
  "scripts": {
    "start": "func start"
  },
  "dependencies": {
    "@azure/functions": "^4.0.0",
    "mssql": "^10.0.0",
    "axios": "^1.6.0"
  }
}
EOF
    
    # Install dependencies
    npm install
    
    # Create main function logic
    cat > QueryProcessor/index.js << 'EOF'
const sql = require('mssql');
const axios = require('axios');

module.exports = async function (context, req) {
    try {
        const { query } = req.body;
        
        if (!query) {
            context.res = { status: 400, body: "Query parameter required" };
            return;
        }
        
        // Generate SQL from natural language using Azure OpenAI
        const generatedSQL = await generateSQLFromNaturalLanguage(query);
        
        // Validate and execute SQL query
        const results = await executeQuery(generatedSQL);
        
        context.res = {
            status: 200,
            body: {
                naturalLanguageQuery: query,
                generatedSQL: generatedSQL,
                results: results,
                executionTime: new Date().toISOString()
            }
        };
        
    } catch (error) {
        context.log.error('Query processing error:', error);
        context.res = {
            status: 500,
            body: { error: "Query processing failed", details: error.message }
        };
    }
};

async function generateSQLFromNaturalLanguage(naturalQuery) {
    const systemPrompt = `You are a business intelligence SQL generator. Convert natural language to SQL for this schema:
    
    Tables:
    - Customers (CustomerID, CompanyName, ContactName, City, Country, Revenue)
    - Orders (OrderID, CustomerID, OrderDate, TotalAmount, Status)
    
    Rules:
    - Only generate SELECT statements
    - Use parameterized queries for security
    - Return only valid SQL without explanations
    - Focus on business metrics and insights`;
    
    const response = await axios.post(
        `${process.env.AZURE_OPENAI_ENDPOINT}/openai/deployments/${process.env.AZURE_OPENAI_DEPLOYMENT}/chat/completions?api-version=2024-10-21`,
        {
            messages: [
                { role: "system", content: systemPrompt },
                { role: "user", content: naturalQuery }
            ],
            temperature: 0.1,
            max_tokens: 200
        },
        {
            headers: {
                'api-key': process.env.AZURE_OPENAI_KEY,
                'Content-Type': 'application/json'
            }
        }
    );
    
    return response.data.choices[0].message.content.trim();
}

async function executeQuery(sqlQuery) {
    const pool = await sql.connect(process.env.SQL_CONNECTION_STRING);
    const result = await pool.request().query(sqlQuery);
    await pool.close();
    return result.recordset;
}
EOF
    
    # Update host.json for Function App configuration
    cat > host.json << 'EOF'
{
  "version": "2.0",
  "functionTimeout": "00:05:00",
  "extensions": {
    "http": {
      "routePrefix": "api"
    }
  }
}
EOF
    
    # Deploy function to Azure
    func azure functionapp publish "${FUNCTION_APP_NAME}"
    
    cd ..
    
    log_success "Business Intelligence query function deployed"
}

# Configure managed identity
configure_managed_identity() {
    log_info "Configuring system-assigned managed identity..."
    
    # Enable managed identity for Function App
    az functionapp identity assign \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}"
    
    # Get the managed identity principal ID
    PRINCIPAL_ID=$(az functionapp show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query identity.principalId --output tsv)
    
    # Grant SQL Database access to managed identity
    az sql server ad-admin set \
        --server "${SQL_SERVER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --display-name "${FUNCTION_APP_NAME}" \
        --object-id "${PRINCIPAL_ID}"
    
    log_success "Managed identity configured for secure database access"
}

# Validation and testing
validate_deployment() {
    log_info "Validating deployment..."
    
    # Get Function App URL and function key
    local function_url=$(az functionapp show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query defaultHostName --output tsv)
    
    local function_key=$(az functionapp keys list \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "functionKeys.default || keys[0].value" --output tsv)
    
    # Wait for function to be ready
    log_info "Waiting for Function App to be ready..."
    sleep 30
    
    # Test with business intelligence query
    log_info "Testing natural language query processing..."
    local test_response=$(curl -s -X POST "https://${function_url}/api/QueryProcessor?code=${function_key}" \
         -H "Content-Type: application/json" \
         -d '{"query": "Show me total revenue by country for all customers"}' || echo "Test failed")
    
    if [[ "${test_response}" == *"results"* ]]; then
        log_success "Function App validation successful"
        log_info "Function URL: https://${function_url}/api/QueryProcessor?code=${function_key}"
    else
        log_warning "Function App validation could not be completed. Please test manually."
        log_info "Function URL: https://${function_url}/api/QueryProcessor?code=${function_key}"
    fi
}

# Main deployment function
main() {
    log_info "Starting Business Intelligence Query Assistant deployment..."
    log_info "Deployment log: ${DEPLOYMENT_LOG}"
    
    check_prerequisites
    setup_environment
    create_resource_group
    create_openai_service
    deploy_gpt_model
    create_sql_database
    create_sample_data
    create_function_app
    configure_function_app
    deploy_function_code
    configure_managed_identity
    validate_deployment
    
    log_success "🎉 Business Intelligence Query Assistant deployment completed successfully!"
    log_info ""
    log_info "Deployment Summary:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  OpenAI Service: ${OPENAI_SERVICE_NAME}"
    log_info "  SQL Server: ${SQL_SERVER_NAME}"
    log_info "  SQL Database: ${SQL_DATABASE_NAME}"
    log_info "  Function App: ${FUNCTION_APP_NAME}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
    log_info ""
    log_info "Next Steps:"
    log_info "  1. Test the Function App with natural language queries"
    log_info "  2. Monitor costs and usage in the Azure portal"
    log_info "  3. Use the destroy.sh script to clean up resources when done"
    log_warning "  4. Remember to clean up resources to avoid ongoing charges"
    
    # Clean up local function project
    if [[ -d "${FUNCTION_PROJECT_DIR}" ]]; then
        rm -rf "${FUNCTION_PROJECT_DIR}"
    fi
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi