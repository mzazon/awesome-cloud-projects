#!/bin/bash

# Deploy script for Intelligent Document Analysis with Hybrid Search
# Recipe: implementing-intelligent-document-analysis-with-hybrid-search-using-azure-openai-service-and-postgresql
# Version: 1.0
# Provider: Azure

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

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
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log_info "Attempting to delete resource group: ${RESOURCE_GROUP}"
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait 2>/dev/null || true
    fi
    exit 1
}

trap cleanup_on_error ERR

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
CONFIG_FILE="${SCRIPT_DIR}/../.env"

# Default values
DEFAULT_LOCATION="eastus"
DEFAULT_RESOURCE_GROUP_PREFIX="rg-doc-analysis"
DEFAULT_OPENAI_ACCOUNT_PREFIX="openai-doc"
DEFAULT_POSTGRES_SERVER_PREFIX="postgres-doc"
DEFAULT_SEARCH_SERVICE_PREFIX="search-doc"
DEFAULT_FUNCTION_APP_PREFIX="func-doc"
DEFAULT_STORAGE_ACCOUNT_PREFIX="storage"

# Function to generate random suffix
generate_random_suffix() {
    openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)"
}

# Function to validate Azure CLI
validate_azure_cli() {
    log_info "Validating Azure CLI..."
    
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check CLI version
    CLI_VERSION=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: ${CLI_VERSION}"
    
    log_success "Azure CLI validation complete"
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check required tools
    local required_tools=("az" "openssl" "psql" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool '$tool' is not installed"
            exit 1
        fi
    done
    
    # Check Azure subscription
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    log_info "Using Azure subscription: ${SUBSCRIPTION_ID}"
    
    # Check for existing OpenAI access
    log_info "Checking Azure OpenAI service availability..."
    if ! az cognitiveservices account list-kinds --query "[?kind=='OpenAI']" -o table &> /dev/null; then
        log_warning "Azure OpenAI service may not be available in your subscription"
        log_warning "Please ensure you have applied for and received access to Azure OpenAI"
    fi
    
    log_success "Prerequisites validation complete"
}

# Function to set environment variables
set_environment_variables() {
    log_info "Setting environment variables..."
    
    # Generate unique suffix
    RANDOM_SUFFIX=$(generate_random_suffix)
    
    # Set environment variables
    export RESOURCE_GROUP="${RESOURCE_GROUP:-${DEFAULT_RESOURCE_GROUP_PREFIX}-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-${DEFAULT_LOCATION}}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    export OPENAI_ACCOUNT="${OPENAI_ACCOUNT:-${DEFAULT_OPENAI_ACCOUNT_PREFIX}-${RANDOM_SUFFIX}}"
    export POSTGRES_SERVER="${POSTGRES_SERVER:-${DEFAULT_POSTGRES_SERVER_PREFIX}-${RANDOM_SUFFIX}}"
    export SEARCH_SERVICE="${SEARCH_SERVICE:-${DEFAULT_SEARCH_SERVICE_PREFIX}-${RANDOM_SUFFIX}}"
    export FUNCTION_APP="${FUNCTION_APP:-${DEFAULT_FUNCTION_APP_PREFIX}-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-${DEFAULT_STORAGE_ACCOUNT_PREFIX}${RANDOM_SUFFIX}}"
    
    # Database credentials
    export POSTGRES_ADMIN_USER="${POSTGRES_ADMIN_USER:-adminuser}"
    export POSTGRES_ADMIN_PASSWORD="${POSTGRES_ADMIN_PASSWORD:-ComplexPassword123!}"
    
    # Save configuration
    cat > "${CONFIG_FILE}" << EOF
# Azure Intelligent Document Analysis Configuration
# Generated: $(date)

RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
OPENAI_ACCOUNT=${OPENAI_ACCOUNT}
POSTGRES_SERVER=${POSTGRES_SERVER}
SEARCH_SERVICE=${SEARCH_SERVICE}
FUNCTION_APP=${FUNCTION_APP}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
POSTGRES_ADMIN_USER=${POSTGRES_ADMIN_USER}
POSTGRES_ADMIN_PASSWORD=${POSTGRES_ADMIN_PASSWORD}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment variables set"
    log_info "Configuration saved to: ${CONFIG_FILE}"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=document-analysis environment=demo \
        --output table
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT}"
    
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --output table
    
    log_success "Storage account created: ${STORAGE_ACCOUNT}"
}

# Function to create Azure OpenAI service
create_openai_service() {
    log_info "Creating Azure OpenAI service: ${OPENAI_ACCOUNT}"
    
    # Create OpenAI service
    az cognitiveservices account create \
        --name "${OPENAI_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --kind OpenAI \
        --sku S0 \
        --custom-domain "${OPENAI_ACCOUNT}" \
        --output table
    
    # Get OpenAI endpoint and key
    export OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "${OPENAI_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.endpoint \
        --output tsv)
    
    export OPENAI_KEY=$(az cognitiveservices account keys list \
        --name "${OPENAI_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 \
        --output tsv)
    
    log_success "Azure OpenAI service created: ${OPENAI_ACCOUNT}"
    log_info "OpenAI endpoint: ${OPENAI_ENDPOINT}"
}

# Function to deploy text embedding model
deploy_embedding_model() {
    log_info "Deploying text embedding model..."
    
    # Deploy text-embedding-ada-002 model
    az cognitiveservices account deployment create \
        --name "${OPENAI_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-name text-embedding-ada-002 \
        --model-name text-embedding-ada-002 \
        --model-version "2" \
        --model-format OpenAI \
        --sku-capacity 10 \
        --sku-name Standard \
        --output table
    
    log_success "Text embedding model deployed successfully"
}

# Function to create PostgreSQL database
create_postgresql_database() {
    log_info "Creating PostgreSQL database: ${POSTGRES_SERVER}"
    
    # Create PostgreSQL flexible server
    az postgres flexible-server create \
        --name "${POSTGRES_SERVER}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --admin-user "${POSTGRES_ADMIN_USER}" \
        --admin-password "${POSTGRES_ADMIN_PASSWORD}" \
        --sku-name Standard_D2s_v3 \
        --tier GeneralPurpose \
        --storage-size 128 \
        --version 14 \
        --output table
    
    # Configure firewall to allow Azure services
    az postgres flexible-server firewall-rule create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${POSTGRES_SERVER}" \
        --rule-name allow-azure-services \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0 \
        --output table
    
    # Enable pgvector extension
    az postgres flexible-server parameter set \
        --resource-group "${RESOURCE_GROUP}" \
        --server-name "${POSTGRES_SERVER}" \
        --name shared_preload_libraries \
        --value "vector" \
        --output table
    
    log_success "PostgreSQL server created with pgvector support"
}

# Function to create Azure AI Search service
create_search_service() {
    log_info "Creating Azure AI Search service: ${SEARCH_SERVICE}"
    
    # Create Azure AI Search service
    az search service create \
        --name "${SEARCH_SERVICE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard \
        --partition-count 1 \
        --replica-count 1 \
        --output table
    
    # Get search service key
    export SEARCH_KEY=$(az search admin-key show \
        --service-name "${SEARCH_SERVICE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query primaryKey \
        --output tsv)
    
    export SEARCH_ENDPOINT="https://${SEARCH_SERVICE}.search.windows.net"
    
    log_success "Azure AI Search service created: ${SEARCH_SERVICE}"
    log_info "Search endpoint: ${SEARCH_ENDPOINT}"
}

# Function to create Function App
create_function_app() {
    log_info "Creating Function App: ${FUNCTION_APP}"
    
    # Create Function App
    az functionapp create \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --storage-account "${STORAGE_ACCOUNT}" \
        --consumption-plan-location "${LOCATION}" \
        --runtime python \
        --functions-version 4 \
        --os-type Linux \
        --output table
    
    # Configure application settings
    az functionapp config appsettings set \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        "OPENAI_ENDPOINT=${OPENAI_ENDPOINT}" \
        "OPENAI_KEY=${OPENAI_KEY}" \
        "POSTGRES_HOST=${POSTGRES_SERVER}.postgres.database.azure.com" \
        "POSTGRES_USER=${POSTGRES_ADMIN_USER}" \
        "POSTGRES_PASSWORD=${POSTGRES_ADMIN_PASSWORD}" \
        "POSTGRES_DATABASE=postgres" \
        "SEARCH_ENDPOINT=${SEARCH_ENDPOINT}" \
        "SEARCH_KEY=${SEARCH_KEY}" \
        --output table
    
    log_success "Function App created and configured: ${FUNCTION_APP}"
}

# Function to initialize database schema
initialize_database_schema() {
    log_info "Initializing database schema..."
    
    # Create database schema script
    cat > "${SCRIPT_DIR}/init_db.sql" << 'EOF'
-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Create documents table with vector support
CREATE TABLE IF NOT EXISTS documents (
    id SERIAL PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    content TEXT NOT NULL,
    file_path VARCHAR(1000),
    content_type VARCHAR(100),
    embedding vector(1536),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create vector index for similarity search
CREATE INDEX IF NOT EXISTS idx_documents_embedding 
ON documents USING ivfflat (embedding vector_cosine_ops) 
WITH (lists = 100);

-- Create text search index
CREATE INDEX IF NOT EXISTS idx_documents_content_fts 
ON documents USING gin(to_tsvector('english', content));

-- Create metadata indexes
CREATE INDEX IF NOT EXISTS idx_documents_title 
ON documents USING btree(title);

CREATE INDEX IF NOT EXISTS idx_documents_content_type 
ON documents USING btree(content_type);
EOF
    
    # Execute database initialization
    PGPASSWORD="${POSTGRES_ADMIN_PASSWORD}" psql \
        "host=${POSTGRES_SERVER}.postgres.database.azure.com port=5432 dbname=postgres user=${POSTGRES_ADMIN_USER} sslmode=require" \
        -f "${SCRIPT_DIR}/init_db.sql"
    
    log_success "Database schema initialized with vector support"
}

# Function to create search index
create_search_index() {
    log_info "Creating Azure AI Search index..."
    
    # Create search index configuration
    cat > "${SCRIPT_DIR}/search_index.json" << 'EOF'
{
    "name": "documents-index",
    "fields": [
        {
            "name": "id",
            "type": "Edm.String",
            "key": true,
            "searchable": false,
            "filterable": true,
            "sortable": true
        },
        {
            "name": "title",
            "type": "Edm.String",
            "searchable": true,
            "filterable": true,
            "sortable": true,
            "analyzer": "standard.lucene"
        },
        {
            "name": "content",
            "type": "Edm.String",
            "searchable": true,
            "filterable": false,
            "sortable": false,
            "analyzer": "standard.lucene"
        },
        {
            "name": "contentType",
            "type": "Edm.String",
            "searchable": false,
            "filterable": true,
            "sortable": true
        },
        {
            "name": "createdAt",
            "type": "Edm.DateTimeOffset",
            "searchable": false,
            "filterable": true,
            "sortable": true
        }
    ]
}
EOF
    
    # Create the search index
    curl -X PUT \
        "${SEARCH_ENDPOINT}/indexes/documents-index?api-version=2023-11-01" \
        -H "Content-Type: application/json" \
        -H "api-key: ${SEARCH_KEY}" \
        -d @"${SCRIPT_DIR}/search_index.json"
    
    log_success "Azure AI Search index created successfully"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check resource group
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "Resource group validation failed"
        return 1
    fi
    
    # Check OpenAI service
    if ! az cognitiveservices account show --name "${OPENAI_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "OpenAI service validation failed"
        return 1
    fi
    
    # Check PostgreSQL server
    if ! az postgres flexible-server show --name "${POSTGRES_SERVER}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "PostgreSQL server validation failed"
        return 1
    fi
    
    # Check search service
    if ! az search service show --name "${SEARCH_SERVICE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "Search service validation failed"
        return 1
    fi
    
    # Check function app
    if ! az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "Function app validation failed"
        return 1
    fi
    
    log_success "Deployment validation complete"
}

# Function to display deployment summary
display_deployment_summary() {
    log_success "===========================================" 
    log_success "  DEPLOYMENT COMPLETED SUCCESSFULLY"
    log_success "===========================================" 
    echo
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    echo
    log_info "Azure OpenAI Service: ${OPENAI_ACCOUNT}"
    log_info "OpenAI Endpoint: ${OPENAI_ENDPOINT}"
    echo
    log_info "PostgreSQL Server: ${POSTGRES_SERVER}"
    log_info "PostgreSQL Host: ${POSTGRES_SERVER}.postgres.database.azure.com"
    echo
    log_info "Azure AI Search: ${SEARCH_SERVICE}"
    log_info "Search Endpoint: ${SEARCH_ENDPOINT}"
    echo
    log_info "Function App: ${FUNCTION_APP}"
    log_info "Function App URL: https://${FUNCTION_APP}.azurewebsites.net"
    echo
    log_info "Configuration saved to: ${CONFIG_FILE}"
    echo
    log_warning "IMPORTANT: Save your configuration file for cleanup!"
    log_warning "To clean up resources, run: ./destroy.sh"
    echo
    log_info "Next Steps:"
    log_info "1. Deploy your function code to the Function App"
    log_info "2. Test document processing with the /api/process_document endpoint"
    log_info "3. Test hybrid search with the /api/hybrid_search endpoint"
    echo
}

# Main deployment function
main() {
    log_info "Starting Azure Intelligent Document Analysis deployment..."
    log_info "Timestamp: $(date)"
    
    # Initialize log file
    echo "Azure Intelligent Document Analysis Deployment Log" > "${LOG_FILE}"
    echo "Started: $(date)" >> "${LOG_FILE}"
    
    # Execute deployment steps
    validate_azure_cli
    validate_prerequisites
    set_environment_variables
    create_resource_group
    create_storage_account
    create_openai_service
    deploy_embedding_model
    create_postgresql_database
    create_search_service
    create_function_app
    initialize_database_schema
    create_search_index
    validate_deployment
    display_deployment_summary
    
    log_success "Deployment completed successfully!"
    echo "Completed: $(date)" >> "${LOG_FILE}"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi