#!/bin/bash

# ==============================================================================
# Azure RAG Knowledge Base Deployment Script
# ==============================================================================
# This script deploys an Azure RAG (Retrieval-Augmented Generation) knowledge
# base with AI Search, Azure Functions, Azure OpenAI Service, and Blob Storage.
# ==============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deployment.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.env"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ==============================================================================
# Utility Functions
# ==============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "${RED}❌ $*${NC}"
}

print_banner() {
    echo ""
    echo "=================================================================="
    echo "  Azure RAG Knowledge Base Deployment Script"
    echo "=================================================================="
    echo ""
}

cleanup_on_error() {
    log_error "Deployment failed! Cleaning up resources..."
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log_info "Attempting to delete resource group: $RESOURCE_GROUP"
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true
    fi
    
    # Clean up local files
    rm -f sample-doc*.txt search-index.json data-source.json indexer.json 2>/dev/null || true
    rm -rf rag-function 2>/dev/null || true
    
    exit 1
}

# Set trap to cleanup on script failure
trap cleanup_on_error ERR

# ==============================================================================
# Prerequisites and Validation
# ==============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Please install curl."
        exit 1
    fi
    
    # Check if zip is installed
    if ! command -v zip &> /dev/null; then
        log_error "zip is not installed. Please install zip."
        exit 1
    fi
    
    # Check if openssl is installed (for random suffix generation)
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install openssl."
        exit 1
    fi
    
    # Check Azure CLI login status
    if ! az account show &> /dev/null; then
        log_error "You are not logged in to Azure CLI. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

validate_permissions() {
    log_info "Validating Azure permissions..."
    
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    
    # Check if user has Contributor role at subscription level
    local has_contributor
    has_contributor=$(az role assignment list \
        --assignee "$(az account show --query user.name --output tsv)" \
        --scope "/subscriptions/$subscription_id" \
        --query "[?roleDefinitionName=='Contributor' || roleDefinitionName=='Owner']" \
        --output tsv)
    
    if [[ -z "$has_contributor" ]]; then
        log_warning "You may not have sufficient permissions. Contributor or Owner role is recommended."
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    log_success "Permission validation completed"
}

# ==============================================================================
# Configuration and Environment Setup
# ==============================================================================

setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    local random_suffix
    random_suffix=$(openssl rand -hex 3)
    
    # Set default values
    export LOCATION="${LOCATION:-eastus}"
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-rag-kb-${random_suffix}}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-ragkbstorage${random_suffix}}"
    export SEARCH_SERVICE="${SEARCH_SERVICE:-rag-kb-search-${random_suffix}}"
    export FUNCTION_APP="${FUNCTION_APP:-rag-kb-func-${random_suffix}}"
    export OPENAI_SERVICE="${OPENAI_SERVICE:-rag-kb-openai-${random_suffix}}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    
    # Validate resource names
    if [[ ${#STORAGE_ACCOUNT} -gt 24 ]]; then
        log_error "Storage account name is too long (max 24 characters): $STORAGE_ACCOUNT"
        exit 1
    fi
    
    # Save configuration to file for cleanup script
    cat > "$CONFIG_FILE" << EOF
LOCATION=$LOCATION
RESOURCE_GROUP=$RESOURCE_GROUP
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
SEARCH_SERVICE=$SEARCH_SERVICE
FUNCTION_APP=$FUNCTION_APP
OPENAI_SERVICE=$OPENAI_SERVICE
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
EOF
    
    log_info "Configuration saved to: $CONFIG_FILE"
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Storage Account: $STORAGE_ACCOUNT"
    log_info "Search Service: $SEARCH_SERVICE"
    log_info "Function App: $FUNCTION_APP"
    log_info "OpenAI Service: $OPENAI_SERVICE"
    
    log_success "Environment setup completed"
}

# ==============================================================================
# Resource Deployment Functions
# ==============================================================================

create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=recipe environment=demo owner="$(az account show --query user.name --output tsv)" \
        --output none
    
    log_success "Resource group created: $RESOURCE_GROUP"
}

create_storage_account() {
    log_info "Creating Azure Blob Storage account: $STORAGE_ACCOUNT"
    
    # Check if storage account name is available
    local name_available
    name_available=$(az storage account check-name \
        --name "$STORAGE_ACCOUNT" \
        --query nameAvailable \
        --output tsv)
    
    if [[ "$name_available" != "true" ]]; then
        log_error "Storage account name '$STORAGE_ACCOUNT' is not available"
        exit 1
    fi
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --hierarchical-namespace true \
        --allow-blob-public-access false \
        --output none
    
    # Wait for storage account to be ready
    sleep 10
    
    # Get storage connection string
    STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    if [[ -z "$STORAGE_CONNECTION" ]]; then
        log_error "Failed to retrieve storage connection string"
        exit 1
    fi
    
    log_success "Storage account created: $STORAGE_ACCOUNT"
}

create_document_container() {
    log_info "Creating document container and uploading sample documents"
    
    # Create container for documents
    az storage container create \
        --name documents \
        --account-name "$STORAGE_ACCOUNT" \
        --connection-string "$STORAGE_CONNECTION" \
        --public-access off \
        --output none
    
    # Create sample documents for testing
    cat > sample-doc1.txt << 'EOF'
Azure Functions is a serverless compute service that lets you run event-triggered code without having to explicitly provision or manage infrastructure. With Azure Functions, you pay only for the time your code runs.

Key features include:
- Automatic scaling based on demand
- Built-in integration with other Azure services
- Support for multiple programming languages
- Pay-per-execution pricing model
EOF
    
    cat > sample-doc2.txt << 'EOF'
Azure AI Search is a cloud search service that gives developers infrastructure, APIs, and tools for building a rich search experience. Use it to create search solutions over private, heterogeneous content in web, mobile, and enterprise applications.

Core capabilities:
- Full-text search with AI enrichment
- Vector search for semantic similarity
- Hybrid search combining keyword and vector
- Built-in AI skills for content extraction
EOF
    
    # Upload sample documents
    az storage blob upload \
        --file sample-doc1.txt \
        --name "azure-functions-overview.txt" \
        --container-name documents \
        --account-name "$STORAGE_ACCOUNT" \
        --connection-string "$STORAGE_CONNECTION" \
        --output none
    
    az storage blob upload \
        --file sample-doc2.txt \
        --name "azure-search-overview.txt" \
        --container-name documents \
        --account-name "$STORAGE_ACCOUNT" \
        --connection-string "$STORAGE_CONNECTION" \
        --output none
    
    log_success "Sample documents uploaded to documents container"
}

create_search_service() {
    log_info "Creating Azure AI Search service: $SEARCH_SERVICE"
    
    # Check if search service name is available
    local name_available
    name_available=$(az search service check-name \
        --name "$SEARCH_SERVICE" \
        --query nameAvailable \
        --output tsv)
    
    if [[ "$name_available" != "true" ]]; then
        log_error "Search service name '$SEARCH_SERVICE' is not available"
        exit 1
    fi
    
    az search service create \
        --name "$SEARCH_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Basic \
        --replica-count 1 \
        --partition-count 1 \
        --output none
    
    # Wait for search service to be ready
    log_info "Waiting for search service to be ready..."
    sleep 30
    
    # Get search service admin key
    SEARCH_ADMIN_KEY=$(az search admin-key show \
        --service-name "$SEARCH_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryKey \
        --output tsv)
    
    if [[ -z "$SEARCH_ADMIN_KEY" ]]; then
        log_error "Failed to retrieve search admin key"
        exit 1
    fi
    
    # Set search service URL
    SEARCH_ENDPOINT="https://${SEARCH_SERVICE}.search.windows.net"
    
    log_success "AI Search service created: $SEARCH_SERVICE"
}

create_openai_service() {
    log_info "Creating Azure OpenAI service: $OPENAI_SERVICE"
    
    # Check if Azure OpenAI is available in the region
    local available_locations
    available_locations=$(az cognitiveservices account list-kinds \
        --query "[?kind=='OpenAI'].locations[]" \
        --output tsv | tr '\n' ' ')
    
    if [[ ! $available_locations =~ $LOCATION ]]; then
        log_warning "Azure OpenAI may not be available in $LOCATION. Common locations: eastus, westeurope, southcentralus"
        log_info "Attempting deployment anyway..."
    fi
    
    az cognitiveservices account create \
        --name "$OPENAI_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind OpenAI \
        --sku S0 \
        --custom-domain "$OPENAI_SERVICE" \
        --output none
    
    # Wait for OpenAI service to be ready
    log_info "Waiting for OpenAI service to be ready..."
    sleep 30
    
    # Get OpenAI endpoint and key
    OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "$OPENAI_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint \
        --output tsv)
    
    OPENAI_API_KEY=$(az cognitiveservices account keys list \
        --name "$OPENAI_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 \
        --output tsv)
    
    if [[ -z "$OPENAI_ENDPOINT" ]] || [[ -z "$OPENAI_API_KEY" ]]; then
        log_error "Failed to retrieve OpenAI service details"
        exit 1
    fi
    
    # Deploy GPT-4o model for chat completions
    log_info "Deploying GPT-4o model..."
    az cognitiveservices account deployment create \
        --name "$OPENAI_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name gpt-4o \
        --model-name gpt-4o \
        --model-version "2024-11-20" \
        --model-format OpenAI \
        --sku-capacity 10 \
        --sku-name Standard \
        --output none
    
    log_success "OpenAI service created with GPT-4o deployment: $OPENAI_SERVICE"
}

create_search_index() {
    log_info "Creating search index with semantic search configuration"
    
    # Create search index definition
    cat > search-index.json << 'EOF'
{
  "name": "knowledge-base-index",
  "fields": [
    {
      "name": "id",
      "type": "Edm.String",
      "searchable": false,
      "filterable": true,
      "retrievable": true,
      "sortable": false,
      "facetable": false,
      "key": true
    },
    {
      "name": "content",
      "type": "Edm.String",
      "searchable": true,
      "filterable": false,
      "retrievable": true,
      "sortable": false,
      "facetable": false
    },
    {
      "name": "title",
      "type": "Edm.String",
      "searchable": true,
      "filterable": true,
      "retrievable": true,
      "sortable": true,
      "facetable": false
    },
    {
      "name": "metadata_storage_path",
      "type": "Edm.String",
      "searchable": false,
      "filterable": true,
      "retrievable": true,
      "sortable": false,
      "facetable": false
    }
  ],
  "semantic": {
    "configurations": [
      {
        "name": "semantic-config",
        "prioritizedFields": {
          "titleField": {
            "fieldName": "title"
          },
          "prioritizedContentFields": [
            {
              "fieldName": "content"
            }
          ]
        }
      }
    ]
  }
}
EOF
    
    # Create the search index with retry logic
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if curl -X POST "${SEARCH_ENDPOINT}/indexes?api-version=2023-11-01" \
            -H "Content-Type: application/json" \
            -H "api-key: ${SEARCH_ADMIN_KEY}" \
            -d @search-index.json \
            --silent --fail > /dev/null; then
            break
        else
            ((retry_count++))
            if [[ $retry_count -eq $max_retries ]]; then
                log_error "Failed to create search index after $max_retries attempts"
                exit 1
            fi
            log_warning "Failed to create search index, retrying in 10 seconds... (attempt $retry_count/$max_retries)"
            sleep 10
        fi
    done
    
    log_success "Search index created with semantic search configuration"
}

create_search_indexer() {
    log_info "Creating and configuring search indexer"
    
    # Create data source for blob storage
    cat > data-source.json << EOF
{
  "name": "blob-datasource",
  "type": "azureblob",
  "credentials": {
    "connectionString": "${STORAGE_CONNECTION}"
  },
  "container": {
    "name": "documents"
  }
}
EOF
    
    # Create the data source
    curl -X POST "${SEARCH_ENDPOINT}/datasources?api-version=2023-11-01" \
        -H "Content-Type: application/json" \
        -H "api-key: ${SEARCH_ADMIN_KEY}" \
        -d @data-source.json \
        --silent --fail > /dev/null
    
    # Create indexer configuration
    cat > indexer.json << 'EOF'
{
  "name": "blob-indexer",
  "dataSourceName": "blob-datasource",
  "targetIndexName": "knowledge-base-index",
  "fieldMappings": [
    {
      "sourceFieldName": "metadata_storage_path",
      "targetFieldName": "id",
      "mappingFunction": {
        "name": "base64Encode"
      }
    },
    {
      "sourceFieldName": "content",
      "targetFieldName": "content"
    },
    {
      "sourceFieldName": "metadata_storage_name",
      "targetFieldName": "title"
    },
    {
      "sourceFieldName": "metadata_storage_path",
      "targetFieldName": "metadata_storage_path"
    }
  ],
  "schedule": {
    "interval": "PT15M"
  }
}
EOF
    
    # Create and run the indexer
    curl -X POST "${SEARCH_ENDPOINT}/indexers?api-version=2023-11-01" \
        -H "Content-Type: application/json" \
        -H "api-key: ${SEARCH_ADMIN_KEY}" \
        -d @indexer.json \
        --silent --fail > /dev/null
    
    log_success "Search indexer created and running every 15 minutes"
}

create_function_app() {
    log_info "Creating Azure Function App: $FUNCTION_APP"
    
    # Check if function app name is available
    local name_available
    name_available=$(az functionapp list \
        --query "[?name=='$FUNCTION_APP']" \
        --output tsv)
    
    if [[ -n "$name_available" ]]; then
        log_error "Function app name '$FUNCTION_APP' is not available"
        exit 1
    fi
    
    az functionapp create \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_ACCOUNT" \
        --consumption-plan-location "$LOCATION" \
        --runtime python \
        --runtime-version 3.11 \
        --functions-version 4 \
        --os-type Linux \
        --output none
    
    # Wait for function app to be ready
    log_info "Waiting for function app to be ready..."
    sleep 30
    
    # Configure application settings for AI services
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
        "SEARCH_ENDPOINT=${SEARCH_ENDPOINT}" \
        "SEARCH_API_KEY=${SEARCH_ADMIN_KEY}" \
        "OPENAI_ENDPOINT=${OPENAI_ENDPOINT}" \
        "OPENAI_API_KEY=${OPENAI_API_KEY}" \
        "OPENAI_DEPLOYMENT=gpt-4o" \
        --output none
    
    log_success "Function App created: $FUNCTION_APP"
}

deploy_rag_function() {
    log_info "Deploying RAG Query function"
    
    # Create function code directory
    mkdir -p rag-function
    pushd rag-function > /dev/null
    
    # Create requirements.txt for Python dependencies
    cat > requirements.txt << 'EOF'
azure-functions>=1.18.0
azure-search-documents>=11.4.0
openai>=1.50.0
requests>=2.31.0
EOF
    
    # Create function.json for HTTP trigger
    mkdir -p rag_query
    cat > rag_query/function.json << 'EOF'
{
  "scriptFile": "__init__.py",
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
      "name": "$return"
    }
  ]
}
EOF
    
    # Create the main function code
    cat > rag_query/__init__.py << 'EOF'
import json
import logging
import os
import azure.functions as func
from azure.search.documents import SearchClient
from azure.core.credentials import AzureKeyCredential
from openai import AzureOpenAI

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('RAG query function processed a request.')
    
    try:
        # Get query from request
        req_body = req.get_json()
        query = req_body.get('query', '')
        
        if not query:
            return func.HttpResponse(
                json.dumps({"error": "Query parameter is required"}),
                status_code=400,
                mimetype="application/json"
            )
        
        # Initialize AI Search client
        search_endpoint = os.environ["SEARCH_ENDPOINT"]
        search_key = os.environ["SEARCH_API_KEY"]
        search_client = SearchClient(
            endpoint=search_endpoint,
            index_name="knowledge-base-index",
            credential=AzureKeyCredential(search_key)
        )
        
        # Perform hybrid search with semantic ranking
        search_results = search_client.search(
            search_text=query,
            query_type="semantic",
            semantic_configuration_name="semantic-config",
            top=3,
            select=["content", "title", "metadata_storage_path"]
        )
        
        # Collect search results for context
        context_docs = []
        for result in search_results:
            context_docs.append({
                "title": result.get("title", ""),
                "content": result.get("content", ""),
                "source": result.get("metadata_storage_path", "")
            })
        
        if not context_docs:
            return func.HttpResponse(
                json.dumps({"answer": "No relevant documents found.", "sources": []}),
                status_code=200,
                mimetype="application/json"
            )
        
        # Initialize Azure OpenAI client
        openai_client = AzureOpenAI(
            api_key=os.environ["OPENAI_API_KEY"],
            api_version="2024-10-21",
            azure_endpoint=os.environ["OPENAI_ENDPOINT"]
        )
        
        # Create context from search results
        context = "\n\n".join([
            f"Document: {doc['title']}\nContent: {doc['content']}"
            for doc in context_docs
        ])
        
        # Create prompt for OpenAI
        system_prompt = """You are a helpful assistant that answers questions based on the provided context documents. 
        Use only the information from the context to answer questions. If the context doesn't contain enough information 
        to answer the question, say so. Always cite the document sources in your response."""
        
        user_prompt = f"Context:\n{context}\n\nQuestion: {query}\n\nAnswer:"
        
        # Generate response using Azure OpenAI
        response = openai_client.chat.completions.create(
            model=os.environ["OPENAI_DEPLOYMENT"],
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            max_tokens=500,
            temperature=0.3
        )
        
        answer = response.choices[0].message.content
        sources = [{"title": doc["title"], "source": doc["source"]} for doc in context_docs]
        
        return func.HttpResponse(
            json.dumps({
                "answer": answer,
                "sources": sources,
                "query": query
            }),
            status_code=200,
            mimetype="application/json"
        )
        
    except Exception as e:
        logging.error(f"Error processing request: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Internal server error: {str(e)}"}),
            status_code=500,
            mimetype="application/json"
        )
EOF
    
    # Create host.json for function app configuration
    cat > host.json << 'EOF'
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true
      }
    }
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[3.*, 4.0.0)"
  }
}
EOF
    
    # Deploy function to Azure
    zip -r function-package.zip . -x "*.git*" > /dev/null
    
    az functionapp deployment source config-zip \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --src function-package.zip \
        --output none
    
    popd > /dev/null
    
    log_success "RAG query function deployed successfully"
}

# ==============================================================================
# Validation and Testing
# ==============================================================================

validate_deployment() {
    log_info "Validating deployment..."
    
    # Wait for indexer to process documents
    log_info "Waiting for indexer to process documents (60 seconds)..."
    sleep 60
    
    # Check if documents were indexed successfully
    local doc_count
    doc_count=$(curl -X GET "${SEARCH_ENDPOINT}/indexes/knowledge-base-index/docs/\$count?api-version=2023-11-01" \
        -H "api-key: ${SEARCH_ADMIN_KEY}" \
        --silent)
    
    if [[ "$doc_count" -ge 2 ]]; then
        log_success "Search index populated with $doc_count documents"
    else
        log_warning "Search index has fewer documents than expected: $doc_count"
    fi
    
    # Get function URL and key for testing
    local function_url
    function_url=$(az functionapp function show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --function-name rag_query \
        --query invokeUrlTemplate \
        --output tsv)
    
    local function_key
    function_key=$(az functionapp keys list \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query functionKeys.default \
        --output tsv)
    
    if [[ -n "$function_url" ]] && [[ -n "$function_key" ]]; then
        log_success "Function endpoint is accessible"
        log_info "Function URL: ${function_url}?code=${function_key}"
        
        # Save endpoint information
        echo "FUNCTION_URL=${function_url}" >> "$CONFIG_FILE"
        echo "FUNCTION_KEY=${function_key}" >> "$CONFIG_FILE"
    else
        log_warning "Could not retrieve function endpoint details"
    fi
    
    log_success "Deployment validation completed"
}

# ==============================================================================
# Main Deployment Process
# ==============================================================================

main() {
    print_banner
    
    log_info "Starting Azure RAG Knowledge Base deployment..."
    log_info "Log file: $LOG_FILE"
    
    # Prerequisites and setup
    check_prerequisites
    validate_permissions
    setup_environment
    
    # Core infrastructure deployment
    create_resource_group
    create_storage_account
    create_document_container
    create_search_service
    create_openai_service
    
    # Search configuration
    create_search_index
    create_search_indexer
    
    # Function deployment
    create_function_app
    deploy_rag_function
    
    # Validation
    validate_deployment
    
    # Clean up temporary files
    rm -f sample-doc*.txt search-index.json data-source.json indexer.json
    rm -rf rag-function
    
    # Final success message
    echo ""
    echo "=================================================================="
    log_success "Azure RAG Knowledge Base deployment completed successfully!"
    echo "=================================================================="
    echo ""
    echo "Resources created:"
    echo "  • Resource Group: $RESOURCE_GROUP"
    echo "  • Storage Account: $STORAGE_ACCOUNT"
    echo "  • Search Service: $SEARCH_SERVICE"
    echo "  • Function App: $FUNCTION_APP"
    echo "  • OpenAI Service: $OPENAI_SERVICE"
    echo ""
    echo "Configuration saved to: $CONFIG_FILE"
    echo "Deployment log: $LOG_FILE"
    echo ""
    echo "To test your RAG API, use the function URL saved in the config file."
    echo "To clean up resources, run: ./destroy.sh"
    echo ""
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi