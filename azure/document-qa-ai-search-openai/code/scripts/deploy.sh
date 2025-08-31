#!/bin/bash

# Azure Document Q&A with AI Search and OpenAI - Deployment Script
# This script deploys the complete infrastructure for the document Q&A solution
# including Azure AI Search, Azure OpenAI Service, Azure Functions, and supporting resources

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="${PROJECT_DIR}/deployment.log"
readonly STATE_FILE="${PROJECT_DIR}/.deployment_state"

# Default configuration
readonly DEFAULT_LOCATION="eastus"
readonly DEFAULT_SKU_OPENAI="S0"
readonly DEFAULT_SKU_SEARCH="basic"
readonly DEFAULT_SKU_STORAGE="Standard_ZRS"

# Global variables
RESOURCE_GROUP=""
LOCATION=""
SUBSCRIPTION_ID=""
RANDOM_SUFFIX=""
DRY_RUN=false
SKIP_CONFIRMATION=false
VERBOSE=false

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
    echo -e "${BLUE}ℹ $*${NC}"
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}⚠ $*${NC}"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}❌ $*${NC}" >&2
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code $exit_code"
    log_info "Check the log file for details: $LOG_FILE"
    log_info "To clean up partially deployed resources, run: ./destroy.sh"
    exit $exit_code
}

trap cleanup_on_error ERR

# Helper functions
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Document Q&A with AI Search and OpenAI infrastructure.

OPTIONS:
    -g, --resource-group NAME    Resource group name (required)
    -l, --location LOCATION      Azure region (default: $DEFAULT_LOCATION)
    -s, --subscription ID        Azure subscription ID (auto-detected if not provided)
    -r, --random-suffix SUFFIX   Random suffix for resource names (auto-generated if not provided)
    -d, --dry-run               Show what would be deployed without making changes
    -y, --yes                   Skip confirmation prompts
    -v, --verbose               Enable verbose logging
    -h, --help                  Show this help message

EXAMPLES:
    $0 -g myResourceGroup
    $0 -g myResourceGroup -l westus2 -r abc123
    $0 -g myResourceGroup --dry-run
    $0 -g myResourceGroup --yes --verbose

EOF
}

# Parse command line arguments
parse_arguments() {
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
            -s|--subscription)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            -r|--random-suffix)
                RANDOM_SUFFIX="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
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

    # Validate required parameters
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log_error "Resource group name is required. Use -g or --resource-group."
        usage
        exit 1
    fi

    # Set defaults
    LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
    
    # Auto-detect subscription if not provided
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query id --output tsv 2>/dev/null || echo "")
        if [[ -z "$SUBSCRIPTION_ID" ]]; then
            log_error "Could not detect Azure subscription. Please login with 'az login' or specify with -s."
            exit 1
        fi
    fi

    # Generate random suffix if not provided
    if [[ -z "$RANDOM_SUFFIX" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    fi
}

# Prerequisites validation
validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' --output tsv)
    log_info "Azure CLI version: $az_version"

    # Check authentication
    if ! az account show &> /dev/null; then
        log_error "Not authenticated with Azure. Please run 'az login'"
        exit 1
    fi

    # Check subscription access
    local current_subscription=$(az account show --query id --output tsv)
    if [[ "$current_subscription" != "$SUBSCRIPTION_ID" ]]; then
        log_info "Setting active subscription to: $SUBSCRIPTION_ID"
        az account set --subscription "$SUBSCRIPTION_ID"
    fi

    # Validate location
    local valid_locations=$(az account list-locations --query "[].name" --output tsv)
    if ! echo "$valid_locations" | grep -q "^$LOCATION$"; then
        log_error "Invalid location: $LOCATION"
        log_info "Valid locations: $(echo "$valid_locations" | tr '\n' ' ')"
        exit 1
    fi

    # Check required providers
    log_info "Checking Azure resource providers..."
    local required_providers=(
        "Microsoft.CognitiveServices"
        "Microsoft.Search"
        "Microsoft.Storage"
        "Microsoft.Web"
    )

    for provider in "${required_providers[@]}"; do
        local state=$(az provider show --namespace "$provider" --query "registrationState" --output tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$state" != "Registered" ]]; then
            log_info "Registering provider: $provider"
            if [[ "$DRY_RUN" == "false" ]]; then
                az provider register --namespace "$provider" --wait
            fi
        fi
    done

    # Check quotas and limits
    check_quotas

    log_success "Prerequisites validation completed"
}

check_quotas() {
    log_info "Checking service quotas and availability..."

    # Check Azure OpenAI availability in region
    local openai_available=$(az cognitiveservices model list --location "$LOCATION" --query "[?name=='gpt-4o'] | length(@)" --output tsv 2>/dev/null || echo "0")
    if [[ "$openai_available" == "0" ]]; then
        log_warning "Azure OpenAI GPT-4o may not be available in $LOCATION. Consider using eastus or eastus2."
    fi

    # Check AI Search availability
    local search_available=$(az search service check-name-availability --name "test-search-$RANDOM_SUFFIX" --query "nameAvailable" --output tsv 2>/dev/null || echo "true")
    if [[ "$search_available" != "true" ]]; then
        log_info "AI Search service names are being validated..."
    fi

    log_info "Quota check completed"
}

# Resource name generation
generate_resource_names() {
    export STORAGE_ACCOUNT="stdocqa${RANDOM_SUFFIX}"
    export SEARCH_SERVICE="srch-docqa-${RANDOM_SUFFIX}"
    export OPENAI_SERVICE="oai-docqa-${RANDOM_SUFFIX}"
    export FUNCTION_APP="func-docqa-${RANDOM_SUFFIX}"
    export CONTAINER_NAME="documents"
    export SEARCH_INDEX_NAME="documents-index"
    export FUNCTION_STORAGE="funcst${RANDOM_SUFFIX}"

    log_info "Generated resource names:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Storage Account: $STORAGE_ACCOUNT"
    log_info "  Search Service: $SEARCH_SERVICE"
    log_info "  OpenAI Service: $OPENAI_SERVICE"
    log_info "  Function App: $FUNCTION_APP"
    log_info "  Function Storage: $FUNCTION_STORAGE"
}

# Save deployment state
save_deployment_state() {
    cat > "$STATE_FILE" << EOF
# Deployment state for Azure Document Q&A
RESOURCE_GROUP="$RESOURCE_GROUP"
LOCATION="$LOCATION"
SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
SEARCH_SERVICE="$SEARCH_SERVICE" 
OPENAI_SERVICE="$OPENAI_SERVICE"
FUNCTION_APP="$FUNCTION_APP"
CONTAINER_NAME="$CONTAINER_NAME"
SEARCH_INDEX_NAME="$SEARCH_INDEX_NAME"
FUNCTION_STORAGE="$FUNCTION_STORAGE"
DEPLOYMENT_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    log_info "Deployment state saved to: $STATE_FILE"
}

# Deployment confirmation
confirm_deployment() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi

    echo
    log_info "Deployment Configuration:"
    log_info "  Subscription: $SUBSCRIPTION_ID"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  Random Suffix: $RANDOM_SUFFIX"
    echo
    log_info "This will create the following Azure resources:"
    log_info "  • Resource Group (if it doesn't exist)"
    log_info "  • Storage Account with blob container"
    log_info "  • Azure AI Search service with index and skillset"
    log_info "  • Azure OpenAI service with GPT-4o and embedding models"
    log_info "  • Azure Functions app with Q&A endpoint"
    echo
    log_warning "Estimated monthly cost: \$50-100 depending on usage"
    echo

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        return 0
    fi

    read -p "Do you want to continue with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

# Execute command with dry-run support
execute_command() {
    local description="$1"
    shift
    local command="$*"

    log_info "$description"
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Command: $command"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: $command"
        return 0
    fi

    if eval "$command"; then
        log_success "$description completed"
        return 0
    else
        local exit_code=$?
        log_error "$description failed with exit code $exit_code"
        return $exit_code
    fi
}

# Deployment functions
deploy_resource_group() {
    log_info "Creating resource group..."
    
    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Resource group '$RESOURCE_GROUP' already exists"
        return 0
    fi

    execute_command "Creating resource group" \
        "az group create --name '$RESOURCE_GROUP' --location '$LOCATION' --tags purpose=recipe environment=demo"
}

deploy_storage_account() {
    log_info "Creating storage account..."

    execute_command "Creating storage account" \
        "az storage account create \
            --name '$STORAGE_ACCOUNT' \
            --resource-group '$RESOURCE_GROUP' \
            --location '$LOCATION' \
            --sku '$DEFAULT_SKU_STORAGE' \
            --kind StorageV2 \
            --access-tier Hot \
            --allow-blob-public-access false \
            --https-only true \
            --min-tls-version TLS1_2"

    if [[ "$DRY_RUN" == "false" ]]; then
        # Get storage account key
        local storage_key=$(az storage account keys list \
            --account-name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --query '[0].value' --output tsv)

        # Create container
        execute_command "Creating document container" \
            "az storage container create \
                --name '$CONTAINER_NAME' \
                --account-name '$STORAGE_ACCOUNT' \
                --account-key '$storage_key' \
                --public-access off"

        # Upload sample documents
        create_sample_documents
        upload_sample_documents "$storage_key"
    fi
}

create_sample_documents() {
    log_info "Creating sample documents..."

    cat > "${PROJECT_DIR}/sample-doc1.txt" << 'EOF'
Azure AI Search is a cloud search service that provides infrastructure, APIs, and 
tools for building rich search experiences. It supports full-text search, vector 
search, and hybrid search capabilities. Vector search enables semantic similarity 
matching through AI-powered embeddings, allowing for context-aware information 
retrieval that goes beyond keyword matching. The service includes built-in 
AI skills for content extraction, language detection, and key phrase extraction.
EOF

    cat > "${PROJECT_DIR}/sample-doc2.txt" << 'EOF'
Azure OpenAI Service provides REST API access to OpenAI's language models including 
GPT-4o, GPT-4o-mini, and embedding models like text-embedding-3-large. These models 
enable advanced natural language processing tasks such as text generation, 
summarization, and semantic search. The service supports responsible AI practices 
with content filtering and usage monitoring. GPT-4o offers enhanced multimodal 
capabilities, processing both text and images with superior performance in 
non-English languages.
EOF

    log_success "Sample documents created"
}

upload_sample_documents() {
    local storage_key="$1"
    
    log_info "Uploading sample documents..."

    execute_command "Uploading Azure AI Search overview" \
        "az storage blob upload \
            --file '${PROJECT_DIR}/sample-doc1.txt' \
            --name 'azure-ai-search-overview.txt' \
            --container-name '$CONTAINER_NAME' \
            --account-name '$STORAGE_ACCOUNT' \
            --account-key '$storage_key'"

    execute_command "Uploading Azure OpenAI overview" \
        "az storage blob upload \
            --file '${PROJECT_DIR}/sample-doc2.txt' \
            --name 'azure-openai-overview.txt' \
            --container-name '$CONTAINER_NAME' \
            --account-name '$STORAGE_ACCOUNT' \
            --account-key '$storage_key'"
}

deploy_openai_service() {
    log_info "Creating Azure OpenAI service..."

    execute_command "Creating Azure OpenAI service" \
        "az cognitiveservices account create \
            --name '$OPENAI_SERVICE' \
            --resource-group '$RESOURCE_GROUP' \
            --location '$LOCATION' \
            --kind OpenAI \
            --sku '$DEFAULT_SKU_OPENAI' \
            --yes"

    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for service to be ready
        log_info "Waiting for OpenAI service to be ready..."
        sleep 30

        # Deploy models
        deploy_openai_models
    fi
}

deploy_openai_models() {
    log_info "Deploying OpenAI models..."

    execute_command "Deploying text-embedding-3-large model" \
        "az cognitiveservices account deployment create \
            --name '$OPENAI_SERVICE' \
            --resource-group '$RESOURCE_GROUP' \
            --deployment-name 'text-embedding-3-large' \
            --model-name 'text-embedding-3-large' \
            --model-version '1' \
            --model-format OpenAI \
            --sku-capacity 30 \
            --sku-name Standard"

    execute_command "Deploying GPT-4o model" \
        "az cognitiveservices account deployment create \
            --name '$OPENAI_SERVICE' \
            --resource-group '$RESOURCE_GROUP' \
            --deployment-name 'gpt-4o' \
            --model-name 'gpt-4o' \
            --model-version '2024-11-20' \
            --model-format OpenAI \
            --sku-capacity 10 \
            --sku-name Standard"
}

deploy_search_service() {
    log_info "Creating Azure AI Search service..."

    execute_command "Creating AI Search service" \
        "az search service create \
            --name '$SEARCH_SERVICE' \
            --resource-group '$RESOURCE_GROUP' \
            --location '$LOCATION' \
            --sku '$DEFAULT_SKU_SEARCH' \
            --semantic-search free"

    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for service to be ready
        log_info "Waiting for Search service to be ready..."
        sleep 60

        # Configure search components
        configure_search_components
    fi
}

configure_search_components() {
    log_info "Configuring search index, skillset, and indexer..."

    if [[ "$DRY_RUN" == "false" ]]; then
        # Get service keys
        local search_admin_key=$(az search admin-key show \
            --service-name "$SEARCH_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --query "primaryKey" --output tsv)

        local openai_endpoint=$(az cognitiveservices account show \
            --name "$OPENAI_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --query "properties.endpoint" --output tsv)

        local openai_key=$(az cognitiveservices account keys list \
            --name "$OPENAI_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --query "key1" --output tsv)

        local storage_key=$(az storage account keys list \
            --account-name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --query '[0].value' --output tsv)

        # Create search configuration files
        create_search_configuration "$openai_endpoint" "$openai_key" "$search_admin_key" "$storage_key"
        
        # Apply configurations
        apply_search_configuration "$search_admin_key"
    fi
}

create_search_configuration() {
    local openai_endpoint="$1"
    local openai_key="$2"
    local search_admin_key="$3"
    local storage_key="$4"

    log_info "Creating search configuration files..."

    # Create search index
    cat > "${PROJECT_DIR}/search-index.json" << EOF
{
  "name": "$SEARCH_INDEX_NAME",
  "fields": [
    {
      "name": "id",
      "type": "Edm.String",
      "key": true,
      "searchable": false,
      "filterable": true,
      "sortable": false,
      "facetable": false
    },
    {
      "name": "content",
      "type": "Edm.String",
      "searchable": true,
      "filterable": false,
      "sortable": false,
      "facetable": false
    },
    {
      "name": "title",
      "type": "Edm.String",
      "searchable": true,
      "filterable": true,
      "sortable": true,
      "facetable": false
    },
    {
      "name": "contentVector",
      "type": "Collection(Edm.Single)",
      "searchable": true,
      "filterable": false,
      "sortable": false,
      "facetable": false,
      "dimensions": 3072,
      "vectorSearchProfile": "default-vector-profile"
    }
  ],
  "vectorSearch": {
    "algorithms": [
      {
        "name": "default-algorithm",
        "kind": "hnsw",
        "hnswParameters": {
          "metric": "cosine",
          "m": 4,
          "efConstruction": 400,
          "efSearch": 500
        }
      }
    ],
    "profiles": [
      {
        "name": "default-vector-profile",
        "algorithm": "default-algorithm",
        "vectorizer": "default-vectorizer"
      }
    ],
    "vectorizers": [
      {
        "name": "default-vectorizer",
        "kind": "azureOpenAI",
        "azureOpenAIParameters": {
          "resourceUri": "$openai_endpoint",
          "deploymentId": "text-embedding-3-large",
          "apiKey": "$openai_key",
          "modelName": "text-embedding-3-large"
        }
      }
    ]
  }
}
EOF

    # Create skillset
    cat > "${PROJECT_DIR}/skillset.json" << EOF
{
  "name": "documents-skillset",
  "description": "Skillset for processing documents with AI enrichment",
  "skills": [
    {
      "@odata.type": "#Microsoft.Skills.Text.SplitSkill",
      "name": "SplitSkill",
      "description": "Split text into chunks for better processing",
      "context": "/document",
      "defaultLanguageCode": "en",
      "textSplitMode": "pages",
      "maximumPageLength": 2000,
      "pageOverlapLength": 200,
      "inputs": [
        {
          "name": "text",
          "source": "/document/content"
        }
      ],
      "outputs": [
        {
          "name": "textItems",
          "targetName": "pages"
        }
      ]
    },
    {
      "@odata.type": "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill",
      "name": "EmbeddingSkill",
      "description": "Generate embeddings using Azure OpenAI",
      "context": "/document/pages/*",
      "resourceUri": "$openai_endpoint",
      "apiKey": "$openai_key",
      "deploymentId": "text-embedding-3-large",
      "modelName": "text-embedding-3-large",
      "dimensions": 3072,
      "inputs": [
        {
          "name": "text",
          "source": "/document/pages/*"
        }
      ],
      "outputs": [
        {
          "name": "embedding",
          "targetName": "contentVector"
        }
      ]
    }
  ]
}
EOF

    # Create data source
    cat > "${PROJECT_DIR}/datasource.json" << EOF
{
  "name": "documents-datasource",
  "description": "Data source for document processing",
  "type": "azureblob",
  "credentials": {
    "connectionString": "DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT;AccountKey=$storage_key;EndpointSuffix=core.windows.net"
  },
  "container": {
    "name": "$CONTAINER_NAME",
    "query": null
  }
}
EOF

    # Create indexer
    cat > "${PROJECT_DIR}/indexer.json" << EOF
{
  "name": "documents-indexer",
  "description": "Indexer for processing documents with AI enrichment",
  "dataSourceName": "documents-datasource",
  "targetIndexName": "$SEARCH_INDEX_NAME",
  "skillsetName": "documents-skillset",
  "schedule": {
    "interval": "PT5M"
  },
  "outputFieldMappings": [
    {
      "sourceFieldName": "/document/pages/*/contentVector",
      "targetFieldName": "contentVector"
    }
  ],
  "fieldMappings": [
    {
      "sourceFieldName": "metadata_storage_name",
      "targetFieldName": "title"
    },
    {
      "sourceFieldName": "content",
      "targetFieldName": "content"
    }
  ]
}
EOF
}

apply_search_configuration() {
    local search_admin_key="$1"
    local base_url="https://${SEARCH_SERVICE}.search.windows.net"

    log_info "Applying search configurations..."

    # Create index
    execute_command "Creating search index" \
        "curl -X POST '$base_url/indexes?api-version=2024-07-01' \
            -H 'Content-Type: application/json' \
            -H 'api-key: $search_admin_key' \
            -d @'${PROJECT_DIR}/search-index.json'"

    # Create skillset
    execute_command "Creating skillset" \
        "curl -X POST '$base_url/skillsets?api-version=2024-07-01' \
            -H 'Content-Type: application/json' \
            -H 'api-key: $search_admin_key' \
            -d @'${PROJECT_DIR}/skillset.json'"

    # Create data source
    execute_command "Creating data source" \
        "curl -X POST '$base_url/datasources?api-version=2024-07-01' \
            -H 'Content-Type: application/json' \
            -H 'api-key: $search_admin_key' \
            -d @'${PROJECT_DIR}/datasource.json'"

    # Create indexer
    execute_command "Creating indexer" \
        "curl -X POST '$base_url/indexers?api-version=2024-07-01' \
            -H 'Content-Type: application/json' \
            -H 'api-key: $search_admin_key' \
            -d @'${PROJECT_DIR}/indexer.json'"
}

deploy_function_app() {
    log_info "Creating Function App..."

    # Create dedicated storage account for Function App
    execute_command "Creating Function App storage account" \
        "az storage account create \
            --name '$FUNCTION_STORAGE' \
            --resource-group '$RESOURCE_GROUP' \
            --location '$LOCATION' \
            --sku Standard_LRS \
            --kind StorageV2"

    execute_command "Creating Function App" \
        "az functionapp create \
            --name '$FUNCTION_APP' \
            --resource-group '$RESOURCE_GROUP' \
            --storage-account '$FUNCTION_STORAGE' \
            --consumption-plan-location '$LOCATION' \
            --runtime python \
            --runtime-version 3.12 \
            --functions-version 4 \
            --os-type Linux \
            --https-only true"

    if [[ "$DRY_RUN" == "false" ]]; then
        configure_function_app
    fi
}

configure_function_app() {
    log_info "Configuring Function App settings..."

    # Get required values
    local search_admin_key=$(az search admin-key show \
        --service-name "$SEARCH_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "primaryKey" --output tsv)

    local openai_endpoint=$(az cognitiveservices account show \
        --name "$OPENAI_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.endpoint" --output tsv)

    local openai_key=$(az cognitiveservices account keys list \
        --name "$OPENAI_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "key1" --output tsv)

    execute_command "Configuring Function App settings" \
        "az functionapp config appsettings set \
            --name '$FUNCTION_APP' \
            --resource-group '$RESOURCE_GROUP' \
            --settings \
            'SEARCH_SERVICE_NAME=$SEARCH_SERVICE' \
            'SEARCH_ADMIN_KEY=$search_admin_key' \
            'OPENAI_ENDPOINT=$openai_endpoint' \
            'OPENAI_KEY=$openai_key' \
            'SEARCH_INDEX_NAME=$SEARCH_INDEX_NAME'"

    # Create and deploy function code
    create_function_code
    deploy_function_code
}

create_function_code() {
    log_info "Creating Function code..."

    local function_dir="${PROJECT_DIR}/qa-function"
    mkdir -p "$function_dir/qa_function"

    # Create requirements.txt
    cat > "$function_dir/requirements.txt" << 'EOF'
azure-functions>=1.19.0
azure-search-documents>=11.5.1
openai>=1.50.0
azure-identity>=1.15.0
EOF

    # Create function.json
    cat > "$function_dir/qa_function/function.json" << 'EOF'
{
  "scriptFile": "__init__.py",
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["post"],
      "route": "qa"
    },
    {
      "type": "http",
      "direction": "out",
      "name": "$return"
    }
  ]
}
EOF

    # Create function code
    cat > "$function_dir/qa_function/__init__.py" << 'EOF'
import json
import logging
import os
from azure.functions import HttpRequest, HttpResponse
from azure.search.documents import SearchClient
from azure.core.credentials import AzureKeyCredential
from openai import AzureOpenAI

# Initialize clients with environment variables
search_client = SearchClient(
    endpoint=f"https://{os.environ['SEARCH_SERVICE_NAME']}.search.windows.net",
    index_name=os.environ['SEARCH_INDEX_NAME'],
    credential=AzureKeyCredential(os.environ['SEARCH_ADMIN_KEY'])
)

openai_client = AzureOpenAI(
    azure_endpoint=os.environ['OPENAI_ENDPOINT'],
    api_key=os.environ['OPENAI_KEY'],
    api_version="2024-10-21"
)

def main(req: HttpRequest) -> HttpResponse:
    logging.info('Processing Q&A request')
    
    try:
        # Parse request body
        req_body = req.get_json()
        if not req_body:
            return HttpResponse(
                "Invalid request: JSON body required",
                status_code=400
            )
        
        question = req_body.get('question')
        if not question or not question.strip():
            return HttpResponse(
                "Question is required and cannot be empty",
                status_code=400
            )
        
        # Search for relevant documents using hybrid search
        search_results = search_client.search(
            search_text=question,
            vector_queries=[{
                "vector": get_embedding(question),
                "k_nearest_neighbors": 3,
                "fields": "contentVector"
            }],
            select=["title", "content"],
            top=3
        )
        
        # Prepare context from search results
        context_parts = []
        sources = []
        
        for result in search_results:
            title = result.get('title', 'Unknown Document')
            content = result.get('content', '')
            
            if content.strip():
                context_parts.append(f"Document: {title}\nContent: {content}")
                sources.append(title)
        
        if not context_parts:
            return HttpResponse(
                json.dumps({
                    "answer": "I couldn't find any relevant documents to answer your question.",
                    "sources": [],
                    "confidence": "low"
                }),
                mimetype="application/json"
            )
        
        context = "\n\n".join(context_parts)
        
        # Generate response using GPT-4o with enhanced prompt
        system_message = """You are a helpful AI assistant that answers questions based on provided context. 
        
        Instructions:
        - Use only the information from the provided context to answer questions
        - If the context doesn't contain enough information, clearly state this limitation
        - Provide specific, accurate answers based on the available information
        - When possible, reference which document(s) contain the information
        - Be concise but comprehensive in your responses"""
        
        response = openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": system_message},
                {"role": "user", "content": f"Context:\n{context}\n\nQuestion: {question}"}
            ],
            temperature=0.3,
            max_tokens=800,
            top_p=1.0
        )
        
        answer = response.choices[0].message.content
        
        return HttpResponse(
            json.dumps({
                "answer": answer,
                "sources": sources,
                "confidence": "high" if len(sources) >= 2 else "medium"
            }),
            mimetype="application/json",
            headers={
                "Content-Type": "application/json",
                "Cache-Control": "no-cache"
            }
        )
        
    except Exception as e:
        logging.error(f"Error processing request: {str(e)}")
        return HttpResponse(
            json.dumps({
                "error": "An error occurred while processing your request",
                "details": str(e) if os.getenv('FUNCTIONS_WORKER_RUNTIME') == 'debug' else None
            }),
            status_code=500,
            mimetype="application/json"
        )

def get_embedding(text):
    """Generate embedding for the given text"""
    try:
        response = openai_client.embeddings.create(
            model="text-embedding-3-large",
            input=text.strip(),
            dimensions=3072
        )
        return response.data[0].embedding
    except Exception as e:
        logging.error(f"Error generating embedding: {str(e)}")
        raise
EOF

    # Create host.json
    cat > "$function_dir/host.json" << 'EOF'
{
  "version": "2.0",
  "functionTimeout": "00:05:00",
  "extensions": {
    "http": {
      "routePrefix": "api",
      "maxConcurrentRequests": 100,
      "maxOutstandingRequests": 200
    }
  },
  "logging": {
    "logLevel": {
      "default": "Information"
    }
  }
}
EOF

    log_success "Function code created"
}

deploy_function_code() {
    log_info "Deploying Function code..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        local function_dir="${PROJECT_DIR}/qa-function"
        
        # Package and deploy function
        cd "$function_dir"
        
        # Note: This would require func CLI tool for actual deployment
        # For now, we'll create a deployment package
        zip -r "../function-deployment.zip" . -x "*.pyc" "__pycache__/*"
        
        cd "$PROJECT_DIR"
        
        log_info "Function package created. Deploy manually using Azure Functions Core Tools:"
        log_info "  cd qa-function && func azure functionapp publish $FUNCTION_APP"
    fi
}

# Validation functions
validate_deployment() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Skipping validation in dry-run mode"
        return 0
    fi

    log_info "Validating deployment..."

    # Check resource group
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Resource group validation failed"
        return 1
    fi

    # Check storage account
    if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Storage account validation failed"
        return 1
    fi

    # Check OpenAI service
    if ! az cognitiveservices account show --name "$OPENAI_SERVICE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_error "OpenAI service validation failed"
        return 1
    fi

    # Check Search service
    if ! az search service show --name "$SEARCH_SERVICE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Search service validation failed"
        return 1
    fi

    # Check Function App
    if ! az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Function App validation failed"
        return 1
    fi

    log_success "Deployment validation completed"
}

# Post-deployment information
show_deployment_info() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    echo
    log_success "Deployment completed successfully!"
    echo
    log_info "Resource Information:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  Storage Account: $STORAGE_ACCOUNT"
    log_info "  Search Service: $SEARCH_SERVICE"
    log_info "  OpenAI Service: $OPENAI_SERVICE"
    log_info "  Function App: $FUNCTION_APP"
    echo
    log_info "Next Steps:"
    log_info "  1. Deploy the Function App code using Azure Functions Core Tools"
    log_info "  2. Test the Q&A endpoint with sample questions"
    log_info "  3. Add your own documents to the '$CONTAINER_NAME' container"
    log_info "  4. Monitor costs and usage in the Azure portal"
    echo
    log_info "Documentation and cleanup:"
    log_info "  • View deployment log: $LOG_FILE"
    log_info "  • Clean up resources: ./destroy.sh"
    log_info "  • Recipe documentation: ../document-qa-ai-search-openai.md"
    echo
    log_warning "Remember to monitor costs and clean up resources when no longer needed."
}

# Main deployment orchestration
main() {
    local start_time=$(date +%s)

    # Initialize logging
    echo "=== Azure Document Q&A Deployment Started at $(date) ===" | tee "$LOG_FILE"

    # Parse arguments and validate prerequisites
    parse_arguments "$@"
    validate_prerequisites
    generate_resource_names
    
    # Show deployment plan and get confirmation
    confirm_deployment
    
    if [[ "$DRY_RUN" == "false" ]]; then
        save_deployment_state
    fi

    # Execute deployment steps
    deploy_resource_group
    deploy_storage_account
    deploy_openai_service
    deploy_search_service
    deploy_function_app

    # Validate and show results
    validate_deployment
    show_deployment_info

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_success "Deployment completed in ${duration} seconds"

    # Cleanup temporary files
    if [[ "$DRY_RUN" == "false" ]]; then
        rm -f "${PROJECT_DIR}/sample-doc"*.txt
        rm -f "${PROJECT_DIR}/"*.json
    fi
}

# Execute main function with all arguments
main "$@"