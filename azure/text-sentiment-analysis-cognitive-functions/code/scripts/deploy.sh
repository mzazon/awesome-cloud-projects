#!/bin/bash

# Deploy script for Text Sentiment Analysis with Cognitive Services
# This script creates Azure resources for sentiment analysis using Cognitive Services and Functions

set -e  # Exit on any error

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

# Check if Azure CLI is installed and user is logged in
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check if Azure Functions Core Tools is installed
    if ! command -v func &> /dev/null; then
        log_error "Azure Functions Core Tools is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure CLI
    if ! az account show &> /dev/null; then
        log_error "You are not logged in to Azure CLI. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not available. Please install OpenSSL for random string generation."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names (6 characters)
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-sentiment-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set additional environment variables
    export LANGUAGE_SERVICE_NAME="lang-sentiment-${RANDOM_SUFFIX}"
    export FUNCTION_APP_NAME="func-sentiment-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="stsentiment${RANDOM_SUFFIX}"
    
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Language Service: ${LANGUAGE_SERVICE_NAME}"
    log_info "Function App: ${FUNCTION_APP_NAME}"
    log_info "Storage Account: ${STORAGE_ACCOUNT_NAME}"
    
    log_success "Environment variables configured"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    # Check if resource group already exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists, skipping creation"
        return 0
    fi
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=recipe environment=demo > /dev/null
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
}

# Create Azure Cognitive Services Language Resource
create_language_service() {
    log_info "Creating Cognitive Services Language resource: ${LANGUAGE_SERVICE_NAME}"
    
    # Check if language service already exists
    if az cognitiveservices account show --name "${LANGUAGE_SERVICE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Language service ${LANGUAGE_SERVICE_NAME} already exists, skipping creation"
    else
        az cognitiveservices account create \
            --name "${LANGUAGE_SERVICE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --kind TextAnalytics \
            --sku S0 \
            --custom-domain "${LANGUAGE_SERVICE_NAME}" \
            --tags purpose=sentiment-analysis > /dev/null
        
        log_success "Language service created: ${LANGUAGE_SERVICE_NAME}"
    fi
    
    # Get the endpoint and key
    export LANGUAGE_ENDPOINT=$(az cognitiveservices account show \
        --name "${LANGUAGE_SERVICE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.endpoint \
        --output tsv)
    
    export LANGUAGE_KEY=$(az cognitiveservices account keys list \
        --name "${LANGUAGE_SERVICE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 \
        --output tsv)
    
    log_info "Language endpoint: ${LANGUAGE_ENDPOINT}"
    log_success "Language service configuration retrieved"
}

# Create Storage Account for Function App
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT_NAME}"
    
    # Check if storage account already exists
    if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Storage account ${STORAGE_ACCOUNT_NAME} already exists, skipping creation"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot > /dev/null
        
        log_success "Storage account created: ${STORAGE_ACCOUNT_NAME}"
    fi
    
    # Get storage connection string
    export STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString \
        --output tsv)
    
    log_success "Storage connection string retrieved"
}

# Create Azure Function App
create_function_app() {
    log_info "Creating Function App: ${FUNCTION_APP_NAME}"
    
    # Check if function app already exists
    if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Function App ${FUNCTION_APP_NAME} already exists, skipping creation"
    else
        az functionapp create \
            --name "${FUNCTION_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT_NAME}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime python \
            --runtime-version 3.11 \
            --functions-version 4 \
            --os-type Linux > /dev/null
        
        log_success "Function App created: ${FUNCTION_APP_NAME}"
    fi
}

# Configure Function App Settings
configure_function_app() {
    log_info "Configuring Function App settings..."
    
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
            "LANGUAGE_ENDPOINT=${LANGUAGE_ENDPOINT}" \
            "LANGUAGE_KEY=${LANGUAGE_KEY}" \
            "FUNCTIONS_WORKER_RUNTIME=python" > /dev/null
    
    log_success "Function App configured with Language service settings"
}

# Create function project structure
create_function_project() {
    log_info "Creating function project structure..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Initialize function project with Python runtime
    func init sentiment-function --worker-runtime python --model V2 > /dev/null 2>&1
    cd sentiment-function
    
    # Create the function
    func new --name analyze_sentiment --template "HTTP trigger" > /dev/null 2>&1
    
    log_success "Function project structure created in ${TEMP_DIR}/sentiment-function"
    
    # Store the temp directory path for later use
    export FUNCTION_PROJECT_DIR="${TEMP_DIR}/sentiment-function"
}

# Implement sentiment analysis logic
implement_function_code() {
    log_info "Implementing sentiment analysis function code..."
    
    cd "${FUNCTION_PROJECT_DIR}"
    
    # Create the function code
    cat > function_app.py << 'EOF'
import azure.functions as func
import json
import logging
import os
from azure.ai.textanalytics import TextAnalyticsClient
from azure.core.credentials import AzureKeyCredential

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

def get_text_analytics_client():
    """Initialize and return Text Analytics client"""
    endpoint = os.environ.get('LANGUAGE_ENDPOINT')
    key = os.environ.get('LANGUAGE_KEY')
    
    if not endpoint or not key:
        raise ValueError("Missing Language service configuration")
    
    credential = AzureKeyCredential(key)
    return TextAnalyticsClient(endpoint=endpoint, credential=credential)

@app.route(route="analyze", methods=["POST"])
def analyze_sentiment(req: func.HttpRequest) -> func.HttpResponse:
    """Analyze sentiment of input text"""
    try:
        # Parse request body
        req_body = req.get_json()
        if not req_body:
            return func.HttpResponse(
                json.dumps({"error": "Request body is required"}),
                status_code=400,
                mimetype="application/json"
            )
        
        # Validate input
        text = req_body.get('text', '').strip()
        if not text:
            return func.HttpResponse(
                json.dumps({"error": "Text field is required"}),
                status_code=400,
                mimetype="application/json"
            )
        
        # Initialize client and analyze sentiment
        client = get_text_analytics_client()
        documents = [text]
        
        # Perform sentiment analysis with opinion mining
        response = client.analyze_sentiment(
            documents=documents,
            show_opinion_mining=True
        )
        
        # Process results
        result = response[0]
        
        if result.is_error:
            return func.HttpResponse(
                json.dumps({"error": f"Analysis failed: {result.error}"}),
                status_code=500,
                mimetype="application/json"
            )
        
        # Format response
        sentiment_result = {
            "text": text,
            "sentiment": result.sentiment,
            "confidence_scores": {
                "positive": round(result.confidence_scores.positive, 3),
                "neutral": round(result.confidence_scores.neutral, 3),
                "negative": round(result.confidence_scores.negative, 3)
            },
            "sentences": []
        }
        
        # Add sentence-level analysis
        for sentence in result.sentences:
            sentence_data = {
                "text": sentence.text,
                "sentiment": sentence.sentiment,
                "confidence_scores": {
                    "positive": round(sentence.confidence_scores.positive, 3),
                    "neutral": round(sentence.confidence_scores.neutral, 3),
                    "negative": round(sentence.confidence_scores.negative, 3)
                }
            }
            sentiment_result["sentences"].append(sentence_data)
        
        return func.HttpResponse(
            json.dumps(sentiment_result, indent=2),
            status_code=200,
            mimetype="application/json"
        )
        
    except ValueError as ve:
        logging.error(f"Configuration error: {ve}")
        return func.HttpResponse(
            json.dumps({"error": "Service configuration error"}),
            status_code=500,
            mimetype="application/json"
        )
    except Exception as e:
        logging.error(f"Unexpected error: {e}")
        return func.HttpResponse(
            json.dumps({"error": "Internal server error"}),
            status_code=500,
            mimetype="application/json"
        )
EOF
    
    # Create requirements file
    cat > requirements.txt << 'EOF'
azure-functions
azure-ai-textanalytics>=5.3.0
azure-core>=1.24.0
EOF
    
    # Remove the default analyze_sentiment directory created by func new
    rm -rf analyze_sentiment
    
    log_success "Function code and dependencies configured"
}

# Deploy function to Azure
deploy_function() {
    log_info "Deploying function to Azure..."
    
    cd "${FUNCTION_PROJECT_DIR}"
    
    # Deploy function to Azure
    func azure functionapp publish "${FUNCTION_APP_NAME}" --python > /dev/null 2>&1
    
    # Wait a moment for deployment to complete
    sleep 10
    
    # Get function URL
    export FUNCTION_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net/api/analyze"
    
    log_success "Function deployed successfully"
    log_info "Function URL: ${FUNCTION_URL}"
}

# Test the deployed function
test_function() {
    log_info "Testing deployed function..."
    
    # Wait for function to be fully ready
    sleep 15
    
    # Test with simple positive sentiment
    local test_response=$(curl -s -X POST "${FUNCTION_URL}" \
        -H "Content-Type: application/json" \
        -d '{"text": "I love this service!"}' \
        -w "%{http_code}")
    
    local http_code="${test_response: -3}"
    
    if [[ "${http_code}" == "200" ]]; then
        log_success "Function test passed - HTTP 200 response received"
    else
        log_warning "Function test returned HTTP ${http_code}. Function may need more time to initialize."
    fi
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    # Create deployment info file
    cat > deployment-info.txt << EOF
# Azure Text Sentiment Analysis Deployment Information
# Generated on: $(date)

RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
LANGUAGE_SERVICE_NAME=${LANGUAGE_SERVICE_NAME}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME}
STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME}
FUNCTION_URL=${FUNCTION_URL}
LANGUAGE_ENDPOINT=${LANGUAGE_ENDPOINT}

# To test the function:
curl -X POST "${FUNCTION_URL}" \\
    -H "Content-Type: application/json" \\
    -d '{"text": "Your text to analyze here"}'

# To view function logs:
az functionapp logs tail --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP}

# To cleanup resources:
az group delete --name ${RESOURCE_GROUP} --yes --no-wait
EOF
    
    log_success "Deployment information saved to deployment-info.txt"
}

# Cleanup temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    if [[ -n "${FUNCTION_PROJECT_DIR}" && -d "${FUNCTION_PROJECT_DIR}" ]]; then
        rm -rf "$(dirname ${FUNCTION_PROJECT_DIR})"
        log_success "Temporary function project files cleaned up"
    fi
}

# Main deployment function
main() {
    log_info "Starting Azure Text Sentiment Analysis deployment..."
    
    # Check for help flag
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --location LOCATION Set Azure location (default: eastus)"
        echo ""
        echo "Environment Variables:"
        echo "  AZURE_LOCATION      Set deployment location (default: eastus)"
        echo ""
        echo "This script deploys the Text Sentiment Analysis solution using:"
        echo "  - Azure Cognitive Services (Language API)"
        echo "  - Azure Functions (Python runtime)"
        echo "  - Azure Storage Account"
        echo ""
        exit 0
    fi
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --location)
                export AZURE_LOCATION="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                log_info "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Trap to cleanup on script exit
    trap cleanup_temp_files EXIT
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_resource_group
    create_language_service
    create_storage_account
    create_function_app
    configure_function_app
    create_function_project
    implement_function_code
    deploy_function
    test_function
    save_deployment_info
    
    log_success "Deployment completed successfully!"
    log_info ""
    log_info "Resources created:"
    log_info "  - Resource Group: ${RESOURCE_GROUP}"
    log_info "  - Language Service: ${LANGUAGE_SERVICE_NAME}"
    log_info "  - Storage Account: ${STORAGE_ACCOUNT_NAME}"
    log_info "  - Function App: ${FUNCTION_APP_NAME}"
    log_info "  - Function URL: ${FUNCTION_URL}"
    log_info ""
    log_info "Test your function with:"
    log_info "curl -X POST \"${FUNCTION_URL}\" \\"
    log_info "    -H \"Content-Type: application/json\" \\"
    log_info "    -d '{\"text\": \"I love this amazing service!\"}'"
    log_info ""
    log_info "View function logs with:"
    log_info "az functionapp logs tail --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP}"
    log_info ""
    log_info "To cleanup all resources, run:"
    log_info "./destroy.sh"
}

# Run main function with all arguments
main "$@"