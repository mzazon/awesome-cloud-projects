#!/bin/bash
set -e

# =============================================================================
# Azure Intelligent Image Content Discovery - Deployment Script
# =============================================================================
# This script deploys the complete infrastructure for an intelligent image
# content discovery system using Azure AI Vision and Azure AI Search.
#
# Services deployed:
# - Azure Storage Account (for image storage)
# - Azure AI Vision (for image analysis)
# - Azure AI Search (for content indexing and search)
# - Azure Functions (for serverless image processing)
# - Search Index (with vector search capabilities)
# =============================================================================

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it first."
        log_info "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if jq is installed (for JSON parsing)
    if ! command_exists jq; then
        log_error "jq is not installed. Please install it first."
        log_info "Visit: https://stedolan.github.io/jq/download/"
        exit 1
    fi
    
    # Check if curl is installed
    if ! command_exists curl; then
        log_error "curl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if openssl is installed (for random string generation)
    if ! command_exists openssl; then
        log_error "openssl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if zip is installed
    if ! command_exists zip; then
        log_error "zip is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI login status
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Set default values
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-image-discovery-demo}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique identifiers for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export STORAGE_ACCOUNT="stgimgdiscov${RANDOM_SUFFIX}"
    export VISION_SERVICE="aivision-imgdiscov-${RANDOM_SUFFIX}"
    export SEARCH_SERVICE="aisearch-imgdiscov-${RANDOM_SUFFIX}"
    export FUNCTION_APP="func-imgdiscov-${RANDOM_SUFFIX}"
    
    # Validate resource naming
    if [[ ${#STORAGE_ACCOUNT} -gt 24 ]]; then
        log_error "Storage account name is too long. Please use a shorter prefix."
        exit 1
    fi
    
    log_success "Environment variables configured"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Storage Account: ${STORAGE_ACCOUNT}"
    log_info "Vision Service: ${VISION_SERVICE}"
    log_info "Search Service: ${SEARCH_SERVICE}"
    log_info "Function App: ${FUNCTION_APP}"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group..."
    
    # Check if resource group already exists
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Resource group '${RESOURCE_GROUP}' already exists. Continuing..."
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=image-discovery environment=demo
        
        log_success "Resource group '${RESOURCE_GROUP}' created successfully"
    fi
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account..."
    
    # Check if storage account already exists
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Storage account '${STORAGE_ACCOUNT}' already exists. Continuing..."
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            --allow-blob-public-access false
        
        log_success "Storage account '${STORAGE_ACCOUNT}' created successfully"
    fi
    
    # Create container for image storage
    log_info "Creating images container..."
    
    # Get storage account key
    STORAGE_KEY=$(az storage account keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --account-name "${STORAGE_ACCOUNT}" \
        --query "[0].value" --output tsv)
    
    # Create container if it doesn't exist
    if ! az storage container show --name images --account-name "${STORAGE_ACCOUNT}" --account-key "${STORAGE_KEY}" >/dev/null 2>&1; then
        az storage container create \
            --name images \
            --account-name "${STORAGE_ACCOUNT}" \
            --account-key "${STORAGE_KEY}" \
            --public-access off
        
        log_success "Images container created successfully"
    else
        log_warning "Images container already exists. Continuing..."
    fi
    
    export STORAGE_KEY
}

# Function to create AI Vision service
create_ai_vision_service() {
    log_info "Creating Azure AI Vision service..."
    
    # Check if AI Vision service already exists
    if az cognitiveservices account show --name "${VISION_SERVICE}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "AI Vision service '${VISION_SERVICE}' already exists. Continuing..."
    else
        az cognitiveservices account create \
            --name "${VISION_SERVICE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --kind ComputerVision \
            --sku S1 \
            --custom-domain "${VISION_SERVICE}" \
            --assign-identity
        
        log_success "AI Vision service '${VISION_SERVICE}' created successfully"
    fi
    
    # Get AI Vision endpoint and key
    export VISION_ENDPOINT=$(az cognitiveservices account show \
        --name "${VISION_SERVICE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "properties.endpoint" --output tsv)
    
    export VISION_KEY=$(az cognitiveservices account keys list \
        --name "${VISION_SERVICE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "key1" --output tsv)
    
    log_success "AI Vision service configured. Endpoint: ${VISION_ENDPOINT}"
}

# Function to create AI Search service
create_ai_search_service() {
    log_info "Creating Azure AI Search service..."
    
    # Check if AI Search service already exists
    if az search service show --name "${SEARCH_SERVICE}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "AI Search service '${SEARCH_SERVICE}' already exists. Continuing..."
    else
        az search service create \
            --name "${SEARCH_SERVICE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Basic \
            --partition-count 1 \
            --replica-count 1
        
        log_success "AI Search service '${SEARCH_SERVICE}' created successfully"
    fi
    
    # Get search service endpoint and admin key
    export SEARCH_ENDPOINT="https://${SEARCH_SERVICE}.search.windows.net"
    
    export SEARCH_KEY=$(az search admin-key show \
        --service-name "${SEARCH_SERVICE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "primaryKey" --output tsv)
    
    log_success "AI Search service configured. Endpoint: ${SEARCH_ENDPOINT}"
}

# Function to create Azure Functions app
create_function_app() {
    log_info "Creating Azure Functions app..."
    
    # Check if Function App already exists
    if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Function App '${FUNCTION_APP}' already exists. Continuing..."
    else
        az functionapp create \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime python \
            --runtime-version 3.11 \
            --functions-version 4 \
            --os-type Linux
        
        log_success "Function App '${FUNCTION_APP}' created successfully"
    fi
    
    # Configure function app settings
    log_info "Configuring function app settings..."
    
    az functionapp config appsettings set \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        "VISION_ENDPOINT=${VISION_ENDPOINT}" \
        "VISION_KEY=${VISION_KEY}" \
        "SEARCH_ENDPOINT=${SEARCH_ENDPOINT}" \
        "SEARCH_KEY=${SEARCH_KEY}" \
        "STORAGE_CONNECTION_STRING=DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT};AccountKey=${STORAGE_KEY};EndpointSuffix=core.windows.net" \
        "AzureWebJobsStorage=DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT};AccountKey=${STORAGE_KEY};EndpointSuffix=core.windows.net"
    
    log_success "Function app configured with AI service connections"
}

# Function to create search index
create_search_index() {
    log_info "Creating search index with vector search capabilities..."
    
    # Check if index already exists
    if curl -s -X GET "${SEARCH_ENDPOINT}/indexes/image-content-index?api-version=2024-05-01-preview" \
        -H "api-key: ${SEARCH_KEY}" | jq -r '.name' | grep -q "image-content-index"; then
        log_warning "Search index 'image-content-index' already exists. Continuing..."
    else
        # Create search index with vector support
        curl -X POST "${SEARCH_ENDPOINT}/indexes" \
            -H "Content-Type: application/json" \
            -H "api-key: ${SEARCH_KEY}" \
            -H "api-version: 2024-05-01-preview" \
            -d '{
          "name": "image-content-index",
          "fields": [
            {
              "name": "id",
              "type": "Edm.String",
              "key": true,
              "searchable": false,
              "filterable": false,
              "sortable": false
            },
            {
              "name": "filename",
              "type": "Edm.String",
              "searchable": true,
              "filterable": true,
              "sortable": true
            },
            {
              "name": "description",
              "type": "Edm.String",
              "searchable": true,
              "filterable": false,
              "sortable": false
            },
            {
              "name": "tags",
              "type": "Collection(Edm.String)",
              "searchable": true,
              "filterable": true,
              "sortable": false
            },
            {
              "name": "objects",
              "type": "Collection(Edm.String)",
              "searchable": true,
              "filterable": true,
              "sortable": false
            },
            {
              "name": "imageUrl",
              "type": "Edm.String",
              "searchable": false,
              "filterable": false,
              "sortable": false
            },
            {
              "name": "contentVector",
              "type": "Collection(Edm.Single)",
              "searchable": true,
              "filterable": false,
              "sortable": false,
              "dimensions": 1536,
              "vectorSearchProfile": "default-vector-profile"
            }
          ],
          "vectorSearch": {
            "algorithms": [
              {
                "name": "default-hnsw",
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
                "algorithm": "default-hnsw"
              }
            ]
          }
        }'
        
        log_success "Search index created with vector search capabilities"
    fi
}

# Function to deploy function code
deploy_function_code() {
    log_info "Preparing and deploying function code..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    FUNCTION_DIR="${TEMP_DIR}/image-processor"
    
    # Create function code directory
    mkdir -p "${FUNCTION_DIR}"
    
    # Create function configuration
    cat > "${FUNCTION_DIR}/function.json" << 'EOF'
{
  "bindings": [
    {
      "name": "myBlob",
      "type": "blobTrigger",
      "direction": "in",
      "path": "images/{name}",
      "connection": "AzureWebJobsStorage"
    }
  ]
}
EOF
    
    # Create Python function code
    cat > "${FUNCTION_DIR}/__init__.py" << 'EOF'
import azure.functions as func
import json
import os
import requests
import uuid
from azure.search.documents import SearchClient
from azure.core.credentials import AzureKeyCredential
import logging

def main(myBlob: func.InputStream):
    logging.info(f"Processing image: {myBlob.name}")
    
    try:
        # Get configuration
        vision_endpoint = os.environ['VISION_ENDPOINT']
        vision_key = os.environ['VISION_KEY']
        search_endpoint = os.environ['SEARCH_ENDPOINT']
        search_key = os.environ['SEARCH_KEY']
        storage_account = os.environ['STORAGE_ACCOUNT']
        
        # Analyze image with AI Vision
        image_data = myBlob.read()
        
        # Call AI Vision API
        vision_url = f"{vision_endpoint}/vision/v3.2/analyze"
        headers = {
            'Ocp-Apim-Subscription-Key': vision_key,
            'Content-Type': 'application/octet-stream'
        }
        params = {
            'visualFeatures': 'Tags,Description,Objects,Categories',
            'language': 'en'
        }
        
        response = requests.post(vision_url, headers=headers, params=params, data=image_data)
        
        if response.status_code != 200:
            logging.error(f"AI Vision API error: {response.status_code} - {response.text}")
            return
        
        vision_result = response.json()
        
        # Extract metadata
        description = vision_result.get('description', {}).get('captions', [{}])[0].get('text', '')
        tags = [tag['name'] for tag in vision_result.get('tags', [])]
        objects = [obj['object'] for obj in vision_result.get('objects', [])]
        
        # Create search document
        document = {
            'id': str(uuid.uuid4()),
            'filename': myBlob.name,
            'description': description,
            'tags': tags,
            'objects': objects,
            'imageUrl': f"https://{storage_account}.blob.core.windows.net/images/{myBlob.name}"
        }
        
        # Index in AI Search
        search_client = SearchClient(
            endpoint=search_endpoint,
            index_name="image-content-index",
            credential=AzureKeyCredential(search_key)
        )
        
        search_client.upload_documents([document])
        logging.info(f"Successfully indexed image: {myBlob.name}")
        
    except Exception as e:
        logging.error(f"Error processing image {myBlob.name}: {str(e)}")
        raise
EOF
    
    # Create requirements.txt
    cat > "${FUNCTION_DIR}/requirements.txt" << 'EOF'
azure-functions
azure-search-documents
requests
EOF
    
    # Create host.json for the function app
    cat > "${TEMP_DIR}/host.json" << 'EOF'
{
  "version": "2.0",
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[2.*, 3.0.0)"
  }
}
EOF
    
    # Create deployment package
    cd "${TEMP_DIR}"
    zip -r image-processor.zip .
    
    # Deploy function code
    az functionapp deployment source config-zip \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FUNCTION_APP}" \
        --src image-processor.zip
    
    # Add storage account name to function app settings
    az functionapp config appsettings set \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "STORAGE_ACCOUNT=${STORAGE_ACCOUNT}"
    
    # Cleanup temporary directory
    rm -rf "${TEMP_DIR}"
    
    log_success "Function code deployed and configured for blob triggers"
}

# Function to create sample search interface
create_search_interface() {
    log_info "Creating sample search interface..."
    
    # Create search interface HTML file
    cat > "search-interface.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Intelligent Image Discovery</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; text-align: center; }
        .search-box { width: 100%; max-width: 600px; padding: 15px; margin: 20px auto; display: block; border: 2px solid #ddd; border-radius: 5px; font-size: 16px; }
        .search-button { padding: 15px 30px; background-color: #007acc; color: white; border: none; border-radius: 5px; cursor: pointer; font-size: 16px; display: block; margin: 20px auto; }
        .search-button:hover { background-color: #005a9e; }
        .result { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; background-color: #fafafa; }
        .image-preview { max-width: 200px; max-height: 200px; border-radius: 5px; margin: 10px 0; }
        .filename { font-weight: bold; color: #333; }
        .description { margin: 10px 0; color: #666; }
        .tags { margin: 5px 0; }
        .tag { background-color: #e1f5fe; padding: 3px 8px; margin: 2px; border-radius: 3px; display: inline-block; font-size: 12px; }
        .loading { text-align: center; margin: 20px 0; }
        .no-results { text-align: center; color: #666; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🖼️ Intelligent Image Discovery System</h1>
        <p style="text-align: center; color: #666;">Search for images using natural language descriptions</p>
        
        <input type="text" id="searchQuery" class="search-box" placeholder="Search for images (e.g., 'people walking', 'red car', 'office building')" />
        <button onclick="searchImages()" class="search-button">🔍 Search Images</button>
        
        <div id="loading" class="loading" style="display: none;">
            <p>🔍 Searching for images...</p>
        </div>
        
        <div id="results"></div>
        
        <div id="instructions" style="margin-top: 40px; padding: 20px; background-color: #f0f8ff; border-radius: 5px;">
            <h3>💡 How to Use</h3>
            <ul>
                <li><strong>Natural Language Search:</strong> Describe what you're looking for in plain English</li>
                <li><strong>Object Search:</strong> Search for specific objects like "car", "person", "building"</li>
                <li><strong>Scene Search:</strong> Search for scenes like "outdoor scene", "office environment"</li>
                <li><strong>Activity Search:</strong> Search for activities like "people walking", "meeting"</li>
            </ul>
            <p><strong>Note:</strong> Upload images to the storage account to see search results. The system will automatically analyze and index them.</p>
        </div>
    </div>
    
    <script>
        const SEARCH_ENDPOINT = '${SEARCH_ENDPOINT}';
        const SEARCH_KEY = '${SEARCH_KEY}';
        
        async function searchImages() {
            const query = document.getElementById('searchQuery').value;
            if (!query.trim()) {
                alert('Please enter a search query');
                return;
            }
            
            const loadingDiv = document.getElementById('loading');
            const resultsDiv = document.getElementById('results');
            
            loadingDiv.style.display = 'block';
            resultsDiv.innerHTML = '';
            
            try {
                const searchUrl = \`\${SEARCH_ENDPOINT}/indexes/image-content-index/docs/search?api-version=2024-05-01-preview\`;
                
                const response = await fetch(searchUrl, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'api-key': SEARCH_KEY
                    },
                    body: JSON.stringify({
                        search: query,
                        searchMode: 'all',
                        queryType: 'semantic',
                        top: 20
                    })
                });
                
                if (!response.ok) {
                    throw new Error(\`Search failed: \${response.status}\`);
                }
                
                const results = await response.json();
                displayResults(results.value);
                
            } catch (error) {
                console.error('Search error:', error);
                resultsDiv.innerHTML = '<div class="no-results">❌ Search failed. Please try again.</div>';
            } finally {
                loadingDiv.style.display = 'none';
            }
        }
        
        function displayResults(results) {
            const resultsDiv = document.getElementById('results');
            
            if (results.length === 0) {
                resultsDiv.innerHTML = '<div class="no-results">📝 No images found. Try uploading some images to the storage account first.</div>';
                return;
            }
            
            resultsDiv.innerHTML = \`<h3>🎯 Found \${results.length} image(s)</h3>\`;
            
            results.forEach(result => {
                const div = document.createElement('div');
                div.className = 'result';
                div.innerHTML = \`
                    <div class="filename">📄 \${result.filename}</div>
                    <div class="description">📝 \${result.description || 'No description available'}</div>
                    <div class="tags">
                        <strong>🏷️ Tags:</strong> 
                        \${result.tags ? result.tags.map(tag => \`<span class="tag">\${tag}</span>\`).join('') : 'None'}
                    </div>
                    <div class="tags">
                        <strong>🎯 Objects:</strong> 
                        \${result.objects ? result.objects.map(obj => \`<span class="tag">\${obj}</span>\`).join('') : 'None'}
                    </div>
                    <img src="\${result.imageUrl}" class="image-preview" alt="\${result.filename}" onerror="this.src='data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjAwIiBoZWlnaHQ9IjIwMCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48cmVjdCB3aWR0aD0iMjAwIiBoZWlnaHQ9IjIwMCIgZmlsbD0iI2VlZSIvPjx0ZXh0IHg9IjUwJSIgeT0iNTAlIiBmb250LXNpemU9IjE0IiBmaWxsPSIjOTk5IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBkeT0iLjNlbSI+SW1hZ2UgTm90IEF2YWlsYWJsZTwvdGV4dD48L3N2Zz4='; this.alt='Image not available';" />
                \`;
                resultsDiv.appendChild(div);
            });
        }
        
        // Allow Enter key to trigger search
        document.getElementById('searchQuery').addEventListener('keypress', function(e) {
            if (e.key === 'Enter') {
                searchImages();
            }
        });
    </script>
</body>
</html>
EOF
    
    log_success "Search interface created: search-interface.html"
}

# Function to display deployment summary
display_deployment_summary() {
    log_info "Deployment Summary"
    echo "===================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Storage Account: ${STORAGE_ACCOUNT}"
    echo "AI Vision Service: ${VISION_SERVICE}"
    echo "AI Search Service: ${SEARCH_SERVICE}"
    echo "Function App: ${FUNCTION_APP}"
    echo "Search Endpoint: ${SEARCH_ENDPOINT}"
    echo "===================="
    echo ""
    log_success "✅ Deployment completed successfully!"
    echo ""
    log_info "Next Steps:"
    echo "1. Upload images to the storage account container 'images'"
    echo "2. Open 'search-interface.html' in your web browser to test the search functionality"
    echo "3. Images will be automatically processed and indexed when uploaded"
    echo ""
    log_info "To upload test images:"
    echo "az storage blob upload --account-name ${STORAGE_ACCOUNT} --container-name images --name test.jpg --file /path/to/image.jpg --account-key ${STORAGE_KEY}"
    echo ""
    log_warning "Remember to run the destroy.sh script to clean up resources when done!"
}

# Main deployment function
main() {
    log_info "Starting Azure Intelligent Image Content Discovery deployment..."
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_storage_account
    create_ai_vision_service
    create_ai_search_service
    create_function_app
    create_search_index
    deploy_function_code
    create_search_interface
    
    display_deployment_summary
}

# Run main function
main "$@"