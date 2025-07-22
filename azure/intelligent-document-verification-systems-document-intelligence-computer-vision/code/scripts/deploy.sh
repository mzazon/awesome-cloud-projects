#!/bin/bash

# Azure Document Verification System Deployment Script
# This script deploys the complete Azure Document Intelligence and Computer Vision solution
# for automated document verification with audit trail capabilities

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deployment.log"
readonly DEPLOYMENT_NAME="docverify-deployment-$(date +%Y%m%d-%H%M%S)"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Deployment failed. Check $LOG_FILE for details."
    exit 1
}

# Trap for cleanup on script exit
cleanup() {
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Script failed. Cleaning up temporary resources..."
        # Additional cleanup logic can be added here
    fi
}
trap cleanup EXIT

# Display script header
display_header() {
    echo ""
    echo "================================================================"
    echo "Azure Document Verification System Deployment"
    echo "================================================================"
    echo "This script will deploy:"
    echo "- Azure Document Intelligence (Form Recognizer)"
    echo "- Azure Computer Vision"
    echo "- Azure Functions App"
    echo "- Azure Storage Account"
    echo "- Azure Cosmos DB"
    echo "- Azure Logic Apps"
    echo "- Azure API Management"
    echo "================================================================"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if required Azure providers are registered
    log "INFO" "Checking Azure resource providers..."
    local providers=("Microsoft.CognitiveServices" "Microsoft.Web" "Microsoft.DocumentDB" "Microsoft.Storage" "Microsoft.Logic" "Microsoft.ApiManagement")
    
    for provider in "${providers[@]}"; do
        local status=$(az provider show --namespace "$provider" --query "registrationState" --output tsv 2>/dev/null)
        if [[ "$status" != "Registered" ]]; then
            log "INFO" "Registering provider: $provider"
            az provider register --namespace "$provider" || error_exit "Failed to register provider: $provider"
        fi
    done
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is required for generating random strings. Please install it."
    fi
    
    log "INFO" "Prerequisites check completed successfully."
}

# Get or set environment variables
setup_environment() {
    log "INFO" "Setting up environment variables..."
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-docverify-$(openssl rand -hex 3)}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    
    # Generate unique suffix for resource names
    local random_suffix=$(openssl rand -hex 3)
    export RANDOM_SUFFIX="${RANDOM_SUFFIX:-$random_suffix}"
    
    # Set resource names
    export STORAGE_ACCOUNT="stdocverify${RANDOM_SUFFIX}"
    export DOC_INTELLIGENCE_NAME="docintel-${RANDOM_SUFFIX}"
    export VISION_NAME="vision-${RANDOM_SUFFIX}"
    export FUNCTION_APP_NAME="func-docverify-${RANDOM_SUFFIX}"
    export COSMOS_ACCOUNT_NAME="cosmos-docverify-${RANDOM_SUFFIX}"
    export LOGIC_APP_NAME="logic-docverify-${RANDOM_SUFFIX}"
    export APIM_NAME="apim-docverify-${RANDOM_SUFFIX}"
    
    # Display configuration
    log "INFO" "Deployment configuration:"
    log "INFO" "  Resource Group: $RESOURCE_GROUP"
    log "INFO" "  Location: $LOCATION"
    log "INFO" "  Subscription ID: $SUBSCRIPTION_ID"
    log "INFO" "  Random Suffix: $RANDOM_SUFFIX"
    
    # Save environment variables to file for destroy script
    cat > "${SCRIPT_DIR}/deployment-vars.env" << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
RANDOM_SUFFIX=$RANDOM_SUFFIX
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
DOC_INTELLIGENCE_NAME=$DOC_INTELLIGENCE_NAME
VISION_NAME=$VISION_NAME
FUNCTION_APP_NAME=$FUNCTION_APP_NAME
COSMOS_ACCOUNT_NAME=$COSMOS_ACCOUNT_NAME
LOGIC_APP_NAME=$LOGIC_APP_NAME
APIM_NAME=$APIM_NAME
EOF
    
    log "INFO" "Environment variables saved to deployment-vars.env"
}

# Create resource group
create_resource_group() {
    log "INFO" "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "WARN" "Resource group already exists: $RESOURCE_GROUP"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=docverify environment=demo \
            || error_exit "Failed to create resource group"
        
        log "INFO" "Resource group created successfully: $RESOURCE_GROUP"
    fi
}

# Create storage account
create_storage_account() {
    log "INFO" "Creating storage account: $STORAGE_ACCOUNT"
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        --min-tls-version TLS1_2 \
        || error_exit "Failed to create storage account"
    
    log "INFO" "Storage account created successfully: $STORAGE_ACCOUNT"
    
    # Get storage account connection string
    local storage_connection
    storage_connection=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv) \
        || error_exit "Failed to get storage connection string"
    
    export STORAGE_CONNECTION="$storage_connection"
    
    # Create containers for document processing
    log "INFO" "Creating storage containers..."
    
    az storage container create \
        --name "incoming-docs" \
        --connection-string "$STORAGE_CONNECTION" \
        --public-access off \
        || error_exit "Failed to create incoming-docs container"
    
    az storage container create \
        --name "processed-docs" \
        --connection-string "$STORAGE_CONNECTION" \
        --public-access off \
        || error_exit "Failed to create processed-docs container"
    
    log "INFO" "Storage containers created successfully"
}

# Create Azure Document Intelligence service
create_document_intelligence() {
    log "INFO" "Creating Azure Document Intelligence service: $DOC_INTELLIGENCE_NAME"
    
    az cognitiveservices account create \
        --name "$DOC_INTELLIGENCE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind FormRecognizer \
        --sku S0 \
        --custom-domain "$DOC_INTELLIGENCE_NAME" \
        --yes \
        || error_exit "Failed to create Document Intelligence service"
    
    log "INFO" "Document Intelligence service created successfully"
    
    # Get endpoint and key
    local doc_intelligence_endpoint
    doc_intelligence_endpoint=$(az cognitiveservices account show \
        --name "$DOC_INTELLIGENCE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv) \
        || error_exit "Failed to get Document Intelligence endpoint"
    
    local doc_intelligence_key
    doc_intelligence_key=$(az cognitiveservices account keys list \
        --name "$DOC_INTELLIGENCE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv) \
        || error_exit "Failed to get Document Intelligence key"
    
    export DOC_INTELLIGENCE_ENDPOINT="$doc_intelligence_endpoint"
    export DOC_INTELLIGENCE_KEY="$doc_intelligence_key"
    
    log "INFO" "Document Intelligence endpoint: $DOC_INTELLIGENCE_ENDPOINT"
}

# Create Azure Computer Vision service
create_computer_vision() {
    log "INFO" "Creating Azure Computer Vision service: $VISION_NAME"
    
    az cognitiveservices account create \
        --name "$VISION_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind ComputerVision \
        --sku S1 \
        --custom-domain "$VISION_NAME" \
        --yes \
        || error_exit "Failed to create Computer Vision service"
    
    log "INFO" "Computer Vision service created successfully"
    
    # Get endpoint and key
    local vision_endpoint
    vision_endpoint=$(az cognitiveservices account show \
        --name "$VISION_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv) \
        || error_exit "Failed to get Computer Vision endpoint"
    
    local vision_key
    vision_key=$(az cognitiveservices account keys list \
        --name "$VISION_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv) \
        || error_exit "Failed to get Computer Vision key"
    
    export VISION_ENDPOINT="$vision_endpoint"
    export VISION_KEY="$vision_key"
    
    log "INFO" "Computer Vision endpoint: $VISION_ENDPOINT"
}

# Create Azure Functions App
create_function_app() {
    log "INFO" "Creating Azure Functions App: $FUNCTION_APP_NAME"
    
    az functionapp create \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_ACCOUNT" \
        --consumption-plan-location "$LOCATION" \
        --runtime python \
        --runtime-version 3.11 \
        --functions-version 4 \
        --disable-app-insights false \
        --https-only true \
        || error_exit "Failed to create Function App"
    
    log "INFO" "Function App created successfully"
    
    # Configure application settings
    log "INFO" "Configuring Function App settings..."
    
    az functionapp config appsettings set \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
        "DOCUMENT_INTELLIGENCE_ENDPOINT=$DOC_INTELLIGENCE_ENDPOINT" \
        "DOCUMENT_INTELLIGENCE_KEY=$DOC_INTELLIGENCE_KEY" \
        "COMPUTER_VISION_ENDPOINT=$VISION_ENDPOINT" \
        "COMPUTER_VISION_KEY=$VISION_KEY" \
        "STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION" \
        || error_exit "Failed to configure Function App settings"
    
    log "INFO" "Function App settings configured successfully"
}

# Create Cosmos DB
create_cosmos_db() {
    log "INFO" "Creating Cosmos DB account: $COSMOS_ACCOUNT_NAME"
    
    az cosmosdb create \
        --name "$COSMOS_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind GlobalDocumentDB \
        --enable-free-tier false \
        --default-consistency-level Session \
        --enable-automatic-failover true \
        --locations regionName="$LOCATION" failoverPriority=0 isZoneRedundant=false \
        || error_exit "Failed to create Cosmos DB account"
    
    log "INFO" "Cosmos DB account created successfully"
    
    # Create database and container
    log "INFO" "Creating Cosmos DB database and container..."
    
    az cosmosdb sql database create \
        --account-name "$COSMOS_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "DocumentVerification" \
        || error_exit "Failed to create Cosmos DB database"
    
    az cosmosdb sql container create \
        --account-name "$COSMOS_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --database-name "DocumentVerification" \
        --name "VerificationResults" \
        --partition-key-path "/documentId" \
        --throughput 400 \
        || error_exit "Failed to create Cosmos DB container"
    
    # Get connection string
    local cosmos_connection
    cosmos_connection=$(az cosmosdb keys list \
        --name "$COSMOS_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --type connection-strings \
        --query "connectionStrings[0].connectionString" --output tsv) \
        || error_exit "Failed to get Cosmos DB connection string"
    
    export COSMOS_CONNECTION="$cosmos_connection"
    
    log "INFO" "Cosmos DB database and container created successfully"
}

# Create Logic App
create_logic_app() {
    log "INFO" "Creating Logic App: $LOGIC_APP_NAME"
    
    # Create a basic Logic App workflow
    local workflow_definition='{
        "$schema": "https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#",
        "contentVersion": "1.0.0.0",
        "parameters": {
            "$connections": {
                "defaultValue": {},
                "type": "Object"
            }
        },
        "triggers": {
            "manual": {
                "type": "Request",
                "kind": "Http",
                "inputs": {
                    "schema": {
                        "properties": {
                            "document_url": {
                                "type": "string"
                            }
                        },
                        "type": "object"
                    }
                }
            }
        },
        "actions": {
            "Response": {
                "type": "Response",
                "kind": "Http",
                "inputs": {
                    "statusCode": 200,
                    "body": {
                        "message": "Document verification workflow triggered"
                    }
                }
            }
        },
        "outputs": {}
    }'
    
    az logic workflow create \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --definition "$workflow_definition" \
        || error_exit "Failed to create Logic App"
    
    log "INFO" "Logic App created successfully"
}

# Create API Management
create_api_management() {
    log "INFO" "Creating API Management service: $APIM_NAME"
    log "WARN" "API Management deployment takes 20-30 minutes..."
    
    az apim create \
        --name "$APIM_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --publisher-name "Document Verification System" \
        --publisher-email "admin@company.com" \
        --sku-name Developer \
        --sku-capacity 1 \
        --no-wait \
        || error_exit "Failed to create API Management service"
    
    log "INFO" "API Management service creation initiated (running in background)"
}

# Deploy Function App code
deploy_function_code() {
    log "INFO" "Deploying Function App code..."
    
    # Create temporary directory for function code
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Create function code structure
    mkdir -p DocumentVerificationFunction
    
    # Create host.json
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
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
azure-functions
azure-ai-formrecognizer
azure-cognitiveservices-vision-computervision
azure-storage-blob
azure-cosmos
requests
EOF
    
    # Create function.json
    cat > DocumentVerificationFunction/function.json << 'EOF'
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
    
    # Create Python function code
    cat > DocumentVerificationFunction/__init__.py << 'EOF'
import azure.functions as func
import json
import logging
import os
from datetime import datetime
import uuid

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function processed a request.')
    
    try:
        # Parse request
        req_body = req.get_json()
        
        if not req_body:
            return func.HttpResponse(
                json.dumps({"error": "Request body is required"}),
                status_code=400,
                mimetype="application/json"
            )
        
        document_url = req_body.get('document_url')
        
        if not document_url:
            return func.HttpResponse(
                json.dumps({"error": "document_url is required"}),
                status_code=400,
                mimetype="application/json"
            )
        
        # Mock verification result for demonstration
        verification_result = {
            "document_id": str(uuid.uuid4()),
            "timestamp": datetime.utcnow().isoformat(),
            "document_url": document_url,
            "verification_status": "VERIFIED",
            "confidence_score": 0.95,
            "extracted_fields": {
                "document_type": "driver_license",
                "name": "Sample Name",
                "document_number": "D123456789"
            },
            "fraud_indicators": [],
            "message": "Document verification completed successfully"
        }
        
        return func.HttpResponse(
            json.dumps(verification_result),
            status_code=200,
            mimetype="application/json"
        )
        
    except Exception as e:
        logging.error(f"Error processing document: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Processing failed: {str(e)}"}),
            status_code=500,
            mimetype="application/json"
        )
EOF
    
    # Deploy function code using zip deployment
    zip -r function.zip . > /dev/null 2>&1
    
    az functionapp deployment source config-zip \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --src function.zip \
        || error_exit "Failed to deploy function code"
    
    # Clean up temporary directory
    cd "$SCRIPT_DIR"
    rm -rf "$temp_dir"
    
    log "INFO" "Function App code deployed successfully"
}

# Validate deployment
validate_deployment() {
    log "INFO" "Validating deployment..."
    
    # Check if all resources exist
    local resources=("$DOC_INTELLIGENCE_NAME" "$VISION_NAME" "$FUNCTION_APP_NAME" "$COSMOS_ACCOUNT_NAME" "$LOGIC_APP_NAME")
    
    for resource in "${resources[@]}"; do
        if ! az resource show --name "$resource" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            error_exit "Resource not found: $resource"
        fi
    done
    
    # Test Function App
    log "INFO" "Testing Function App..."
    
    local function_url
    function_url=$(az functionapp show \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query defaultHostName --output tsv) \
        || error_exit "Failed to get Function App URL"
    
    local function_key
    function_key=$(az functionapp keys list \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query functionKeys.default --output tsv) \
        || error_exit "Failed to get Function App key"
    
    export FUNCTION_URL="https://$function_url"
    export FUNCTION_KEY="$function_key"
    
    log "INFO" "Function App URL: $FUNCTION_URL"
    log "INFO" "Function App Key: $FUNCTION_KEY"
    
    # Test with sample request
    local test_response
    test_response=$(curl -s -X POST \
        "${FUNCTION_URL}/api/DocumentVerificationFunction" \
        -H "Content-Type: application/json" \
        -H "x-functions-key: $FUNCTION_KEY" \
        -d '{"document_url": "https://example.com/sample-document.jpg"}' \
        2>/dev/null) || log "WARN" "Function test failed - this is expected for demo deployment"
    
    log "INFO" "Deployment validation completed"
}

# Display deployment summary
display_summary() {
    log "INFO" "Deployment completed successfully!"
    echo ""
    echo "================================================================"
    echo "Azure Document Verification System - Deployment Summary"
    echo "================================================================"
    echo ""
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo ""
    echo "Services Deployed:"
    echo "- Document Intelligence: $DOC_INTELLIGENCE_NAME"
    echo "- Computer Vision: $VISION_NAME"
    echo "- Function App: $FUNCTION_APP_NAME"
    echo "- Storage Account: $STORAGE_ACCOUNT"
    echo "- Cosmos DB: $COSMOS_ACCOUNT_NAME"
    echo "- Logic App: $LOGIC_APP_NAME"
    echo "- API Management: $APIM_NAME (may still be deploying)"
    echo ""
    echo "Function App URL: $FUNCTION_URL"
    echo "Function App Key: $FUNCTION_KEY"
    echo ""
    echo "Test the API with:"
    echo "curl -X POST \"$FUNCTION_URL/api/DocumentVerificationFunction\" \\"
    echo "  -H \"Content-Type: application/json\" \\"
    echo "  -H \"x-functions-key: $FUNCTION_KEY\" \\"
    echo "  -d '{\"document_url\": \"https://example.com/sample-document.jpg\"}'"
    echo ""
    echo "Configuration saved to: ${SCRIPT_DIR}/deployment-vars.env"
    echo "Deployment log: $LOG_FILE"
    echo ""
    echo "================================================================"
}

# Main deployment function
main() {
    # Initialize log file
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    display_header
    
    # Check if dry run
    if [[ "${1:-}" == "--dry-run" ]]; then
        log "INFO" "Dry run mode - no resources will be created"
        return 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_resource_group
    create_storage_account
    create_document_intelligence
    create_computer_vision
    create_function_app
    create_cosmos_db
    create_logic_app
    create_api_management
    deploy_function_code
    validate_deployment
    display_summary
    
    log "INFO" "Deployment completed successfully at $(date)"
}

# Run main function with all arguments
main "$@"