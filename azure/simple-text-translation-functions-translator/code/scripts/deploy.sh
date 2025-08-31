#!/bin/bash

#######################################################################
# Azure Simple Text Translation Deployment Script
# 
# This script deploys Azure Functions with Azure AI Translator
# for a serverless text translation API
#
# Prerequisites:
# - Azure CLI installed and authenticated
# - Appropriate Azure permissions for resource creation
# - bash shell environment
#######################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Node.js is available (for function code)
    if ! command -v node &> /dev/null; then
        log_warning "Node.js not found. This is needed for local testing but not for deployment."
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        log_error "zip command not found. Please install zip utility."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
    fi
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-translation-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv 2>/dev/null || echo '')}"
    export TRANSLATOR_NAME="${TRANSLATOR_NAME:-translator-${RANDOM_SUFFIX}}"
    export FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-translate-func-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-storage${RANDOM_SUFFIX}}"
    
    # Validate storage account name (must be 3-24 chars, lowercase, numbers only)
    if [ ${#STORAGE_ACCOUNT_NAME} -gt 24 ]; then
        STORAGE_ACCOUNT_NAME="st${RANDOM_SUFFIX}"
        log_warning "Storage account name truncated to: ${STORAGE_ACCOUNT_NAME}"
    fi
    
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Translator Name: ${TRANSLATOR_NAME}"
    log_info "Function App Name: ${FUNCTION_APP_NAME}"
    log_info "Storage Account Name: ${STORAGE_ACCOUNT_NAME}"
    
    log_success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=recipe environment=demo \
            --output table
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Function to create Azure AI Translator
create_translator() {
    log_info "Creating Azure AI Translator service: ${TRANSLATOR_NAME}"
    
    if az cognitiveservices account show --name "${TRANSLATOR_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Translator service ${TRANSLATOR_NAME} already exists"
    else
        az cognitiveservices account create \
            --name "${TRANSLATOR_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --kind TextTranslation \
            --sku F0 \
            --yes \
            --output table
        
        log_success "Translator service created: ${TRANSLATOR_NAME}"
    fi
    
    # Get translator endpoint and key
    export TRANSLATOR_ENDPOINT=$(az cognitiveservices account show \
        --name "${TRANSLATOR_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.endpoint \
        --output tsv)
    
    export TRANSLATOR_KEY=$(az cognitiveservices account keys list \
        --name "${TRANSLATOR_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 \
        --output tsv)
    
    log_success "Translator endpoint: ${TRANSLATOR_ENDPOINT}"
    log_info "Translator key retrieved (hidden for security)"
}

# Function to create storage account
create_storage() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT_NAME}"
    
    if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Storage account ${STORAGE_ACCOUNT_NAME} already exists"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --output table
        
        log_success "Storage account created: ${STORAGE_ACCOUNT_NAME}"
    fi
}

# Function to create Function App
create_function_app() {
    log_info "Creating Function App: ${FUNCTION_APP_NAME}"
    
    if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Function App ${FUNCTION_APP_NAME} already exists"
    else
        az functionapp create \
            --resource-group "${RESOURCE_GROUP}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime node \
            --runtime-version 20 \
            --functions-version 4 \
            --name "${FUNCTION_APP_NAME}" \
            --storage-account "${STORAGE_ACCOUNT_NAME}" \
            --disable-app-insights false \
            --output table
        
        log_success "Function App created: ${FUNCTION_APP_NAME}"
    fi
    
    # Configure application settings
    log_info "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
            "TRANSLATOR_ENDPOINT=${TRANSLATOR_ENDPOINT}" \
            "TRANSLATOR_KEY=${TRANSLATOR_KEY}" \
            "WEBSITE_NODE_DEFAULT_VERSION=~20" \
        --output table
    
    log_success "Function App settings configured"
}

# Function to create and deploy function code
deploy_function_code() {
    log_info "Creating and deploying function code..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Create function.json configuration
    cat > function.json << 'EOF'
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
    }
  ]
}
EOF
    
    # Create index.js with translation logic
    cat > index.js << 'EOF'
const https = require('https');

module.exports = async function (context, req) {
    context.log('Translation function processed a request.');

    // Validate request body
    if (!req.body || !req.body.text || !req.body.to) {
        context.res = {
            status: 400,
            body: { 
                error: "Please provide 'text' and 'to' language in request body",
                example: { text: "Hello world", to: "es" }
            }
        };
        return;
    }

    const { text, to, from } = req.body;
    const translatorKey = process.env.TRANSLATOR_KEY;
    const translatorEndpoint = process.env.TRANSLATOR_ENDPOINT;

    try {
        // Prepare translation request
        const path = `/translate?api-version=3.0&to=${to}${from ? `&from=${from}` : ''}`;
        const requestBody = JSON.stringify([{ text: text }]);

        const options = {
            method: 'POST',
            hostname: 'api.cognitive.microsofttranslator.com',
            path: path,
            headers: {
                'Ocp-Apim-Subscription-Key': translatorKey,
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(requestBody)
            }
        };

        // Make translation request
        const translation = await new Promise((resolve, reject) => {
            const req = https.request(options, (res) => {
                let data = '';
                res.on('data', (chunk) => data += chunk);
                res.on('end', () => {
                    try {
                        resolve(JSON.parse(data));
                    } catch (error) {
                        reject(new Error('Failed to parse translation response'));
                    }
                });
            });

            req.on('error', reject);
            req.write(requestBody);
            req.end();
        });

        // Return successful translation
        context.res = {
            status: 200,
            body: {
                original: text,
                translated: translation[0].translations[0].text,
                from: translation[0].detectedLanguage?.language || from,
                to: to,
                confidence: translation[0].detectedLanguage?.score
            }
        };

    } catch (error) {
        context.log.error('Translation error:', error);
        context.res = {
            status: 500,
            body: { error: 'Translation service unavailable' }
        };
    }
};
EOF
    
    # Create deployment package
    zip -r function.zip . > /dev/null
    
    # Deploy to Function App
    log_info "Deploying function code to Azure..."
    az functionapp deployment source config-zip \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FUNCTION_APP_NAME}" \
        --src function.zip \
        --output table
    
    # Wait for deployment to complete
    log_info "Waiting for deployment to complete..."
    sleep 30
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "${TEMP_DIR}"
    
    log_success "Function code deployed successfully"
}

# Function to get function URL
get_function_url() {
    log_info "Retrieving function URL and access key..."
    
    # Wait a bit more for function to be fully ready
    sleep 10
    
    # Get function URL (try multiple times as it might not be immediately available)
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if FUNCTION_URL=$(az functionapp function show \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${FUNCTION_APP_NAME}" \
            --function-name index \
            --query invokeUrlTemplate \
            --output tsv 2>/dev/null); then
            break
        fi
        
        log_warning "Attempt $attempt/$max_attempts: Function URL not ready, waiting..."
        sleep 10
        ((attempt++))
    done
    
    if [ -z "${FUNCTION_URL:-}" ]; then
        log_error "Failed to retrieve function URL after $max_attempts attempts"
        return 1
    fi
    
    # Get function access key
    FUNCTION_KEY=$(az functionapp keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FUNCTION_APP_NAME}" \
        --query functionKeys.default \
        --output tsv)
    
    export FUNCTION_URL
    export FUNCTION_KEY
    
    log_success "Function URL retrieved successfully"
    log_info "Function URL: ${FUNCTION_URL}?code=${FUNCTION_KEY}"
}

# Function to test the deployment
test_deployment() {
    log_info "Testing the translation function..."
    
    if [ -z "${FUNCTION_URL:-}" ] || [ -z "${FUNCTION_KEY:-}" ]; then
        log_error "Function URL or key not available for testing"
        return 1
    fi
    
    # Test basic translation
    log_info "Testing English to Spanish translation..."
    
    local test_response
    if test_response=$(curl -s -X POST "${FUNCTION_URL}?code=${FUNCTION_KEY}" \
        -H "Content-Type: application/json" \
        -d '{
            "text": "Hello, how are you today?",
            "to": "es"
        }' 2>/dev/null); then
        
        if echo "$test_response" | grep -q "translated"; then
            log_success "Translation test passed!"
            log_info "Test response: $test_response"
        else
            log_warning "Translation test returned unexpected response: $test_response"
        fi
    else
        log_error "Translation test failed - could not reach function endpoint"
        return 1
    fi
}

# Function to save deployment info
save_deployment_info() {
    local info_file="deployment-info.txt"
    log_info "Saving deployment information to ${info_file}..."
    
    cat > "${info_file}" << EOF
# Azure Text Translation Deployment Information
# Generated on: $(date)

# Resource Group
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}

# Services
TRANSLATOR_NAME=${TRANSLATOR_NAME}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME}
STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME}

# Function Access
FUNCTION_URL=${FUNCTION_URL:-Not available}
FUNCTION_KEY=${FUNCTION_KEY:-Not available}

# Full Function Endpoint
FULL_ENDPOINT=${FUNCTION_URL}?code=${FUNCTION_KEY}

# Test Command
curl -X POST "${FUNCTION_URL}?code=${FUNCTION_KEY}" \\
    -H "Content-Type: application/json" \\
    -d '{
        "text": "Hello, how are you today?",
        "to": "es"
    }'

# Cleanup Command
./destroy.sh
EOF
    
    log_success "Deployment information saved to ${info_file}"
}

# Main deployment function
main() {
    log_info "Starting Azure Text Translation deployment..."
    log_info "================================================"
    
    # Check if running in dry-run mode
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_info "DRY RUN MODE - No resources will be created"
        setup_environment
        log_info "Would create the following resources:"
        log_info "- Resource Group: ${RESOURCE_GROUP}"
        log_info "- Translator: ${TRANSLATOR_NAME}"
        log_info "- Storage Account: ${STORAGE_ACCOUNT_NAME}"
        log_info "- Function App: ${FUNCTION_APP_NAME}"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_resource_group
    create_translator
    create_storage
    create_function_app
    deploy_function_code
    get_function_url
    test_deployment
    save_deployment_info
    
    log_success "================================================"
    log_success "Deployment completed successfully!"
    log_success "================================================"
    log_info "Function URL: ${FUNCTION_URL}?code=${FUNCTION_KEY}"
    log_info "Test your translation API with the command in deployment-info.txt"
    log_info "Run './destroy.sh' when you want to clean up resources"
}

# Handle script interruption
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        log_error "Deployment failed! Check the error messages above."
        log_info "You may need to run './destroy.sh' to clean up any partially created resources."
    fi
}

trap cleanup_on_exit EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            export DRY_RUN=true
            shift
            ;;
        --resource-group)
            export RESOURCE_GROUP="$2"
            shift 2
            ;;
        --location)
            export LOCATION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run              Show what would be deployed without creating resources"
            echo "  --resource-group NAME  Specify custom resource group name"
            echo "  --location LOCATION    Specify Azure region (default: eastus)"
            echo "  --help                 Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  RESOURCE_GROUP         Override resource group name"
            echo "  LOCATION              Override Azure region"
            echo "  RANDOM_SUFFIX         Override random suffix for resource names"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main deployment
main "$@"