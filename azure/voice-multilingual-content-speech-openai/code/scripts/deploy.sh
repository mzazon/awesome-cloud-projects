#!/bin/bash

# Voice-to-Multilingual Content Pipeline Deployment Script
# This script deploys Azure resources for processing voice recordings into multilingual content

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

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_NAME="voice-pipeline-$(date +%Y%m%d-%H%M%S)"
RESOURCE_GROUP=""
LOCATION="eastus"
RANDOM_SUFFIX=""
DRY_RUN=false

# Resource names (will be set with unique suffix)
STORAGE_ACCOUNT=""
FUNCTION_APP=""
SPEECH_SERVICE=""
OPENAI_SERVICE=""
TRANSLATOR_SERVICE=""

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Voice-to-Multilingual Content Pipeline

OPTIONS:
    -g, --resource-group    Azure resource group name (required)
    -l, --location          Azure region (default: eastus)
    -s, --suffix            Custom suffix for resource names (optional)
    -d, --dry-run           Show what would be deployed without actually deploying
    -h, --help              Show this help message

EXAMPLES:
    $0 -g my-voice-pipeline-rg
    $0 -g my-voice-pipeline-rg -l westus2 -s dev
    $0 -g my-voice-pipeline-rg --dry-run

PREREQUISITES:
    - Azure CLI installed and configured
    - Sufficient permissions to create resources
    - Azure OpenAI Service access (application approval required)

EOF
}

# Parse command line arguments
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
        -s|--suffix)
            RANDOM_SUFFIX="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
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
    log_error "Resource group name is required. Use -g or --resource-group"
    usage
    exit 1
fi

# Generate random suffix if not provided
if [[ -z "$RANDOM_SUFFIX" ]]; then
    RANDOM_SUFFIX=$(openssl rand -hex 3)
fi

# Set resource names with unique suffix
STORAGE_ACCOUNT="stvoicepipe${RANDOM_SUFFIX}"
FUNCTION_APP="func-voice-pipeline-${RANDOM_SUFFIX}"
SPEECH_SERVICE="speech-voice-pipeline-${RANDOM_SUFFIX}"
OPENAI_SERVICE="openai-voice-pipeline-${RANDOM_SUFFIX}"
TRANSLATOR_SERVICE="translator-voice-pipeline-${RANDOM_SUFFIX}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
    
    # Get subscription info
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    log_info "Using subscription: $subscription_name ($subscription_id)"
    
    # Check if location is valid
    if ! az account list-locations --query "[?name=='$LOCATION']" --output tsv | grep -q "$LOCATION"; then
        log_error "Invalid location: $LOCATION"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return
    fi
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=voice-pipeline environment=demo
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create storage account: $STORAGE_ACCOUNT"
        return
    fi
    
    # Create storage account
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --allow-blob-public-access false
    
    # Get storage connection string
    local storage_connection=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    # Create containers
    az storage container create \
        --name "audio-input" \
        --account-name "$STORAGE_ACCOUNT" \
        --connection-string "$storage_connection" \
        --public-access off
    
    az storage container create \
        --name "content-output" \
        --account-name "$STORAGE_ACCOUNT" \
        --connection-string "$storage_connection" \
        --public-access off
    
    log_success "Storage account and containers created: $STORAGE_ACCOUNT"
}

# Function to create Speech service
create_speech_service() {
    log_info "Creating Speech service: $SPEECH_SERVICE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Speech service: $SPEECH_SERVICE"
        return
    fi
    
    az cognitiveservices account create \
        --name "$SPEECH_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind SpeechServices \
        --sku S0 \
        --custom-domain "$SPEECH_SERVICE"
    
    log_success "Speech service created: $SPEECH_SERVICE"
}

# Function to create OpenAI service
create_openai_service() {
    log_info "Creating Azure OpenAI service: $OPENAI_SERVICE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create OpenAI service: $OPENAI_SERVICE"
        return
    fi
    
    # Note: OpenAI service creation might fail if user doesn't have access
    if ! az cognitiveservices account create \
        --name "$OPENAI_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind OpenAI \
        --sku S0 \
        --custom-domain "$OPENAI_SERVICE"; then
        
        log_error "Failed to create OpenAI service. You may need to apply for Azure OpenAI access at https://aka.ms/oaiapply"
        exit 1
    fi
    
    log_success "Azure OpenAI service created: $OPENAI_SERVICE"
}

# Function to create Translator service
create_translator_service() {
    log_info "Creating Translator service: $TRANSLATOR_SERVICE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Translator service: $TRANSLATOR_SERVICE"
        return
    fi
    
    az cognitiveservices account create \
        --name "$TRANSLATOR_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind TextTranslation \
        --sku S1 \
        --custom-domain "$TRANSLATOR_SERVICE"
    
    log_success "Translator service created: $TRANSLATOR_SERVICE"
}

# Function to create Function App
create_function_app() {
    log_info "Creating Function App: $FUNCTION_APP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Function App: $FUNCTION_APP"
        return
    fi
    
    az functionapp create \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_ACCOUNT" \
        --consumption-plan-location "$LOCATION" \
        --runtime python \
        --runtime-version 3.11 \
        --functions-version 4
    
    log_success "Function App created: $FUNCTION_APP"
}

# Function to configure Function App settings
configure_function_app() {
    log_info "Configuring Function App with AI service credentials"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure Function App settings"
        return
    fi
    
    # Get service keys and endpoints
    local speech_key=$(az cognitiveservices account keys list \
        --name "$SPEECH_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    local speech_endpoint=$(az cognitiveservices account show \
        --name "$SPEECH_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    local openai_key=$(az cognitiveservices account keys list \
        --name "$OPENAI_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    local openai_endpoint=$(az cognitiveservices account show \
        --name "$OPENAI_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    local translator_key=$(az cognitiveservices account keys list \
        --name "$TRANSLATOR_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    local translator_endpoint=$(az cognitiveservices account show \
        --name "$TRANSLATOR_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    local storage_connection=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    # Configure function app settings
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
            "SPEECH_KEY=$speech_key" \
            "SPEECH_ENDPOINT=$speech_endpoint" \
            "OPENAI_KEY=$openai_key" \
            "OPENAI_ENDPOINT=$openai_endpoint" \
            "TRANSLATOR_KEY=$translator_key" \
            "TRANSLATOR_ENDPOINT=$translator_endpoint" \
            "STORAGE_CONNECTION_STRING=$storage_connection" \
            "TARGET_LANGUAGES=es,fr,de,ja,pt"
    
    log_success "Function App configured with AI service credentials"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "=================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Deployment Name: $DEPLOYMENT_NAME"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Created Resources:"
    echo "- Storage Account: $STORAGE_ACCOUNT"
    echo "- Function App: $FUNCTION_APP"
    echo "- Speech Service: $SPEECH_SERVICE"
    echo "- OpenAI Service: $OPENAI_SERVICE"
    echo "- Translator Service: $TRANSLATOR_SERVICE"
    echo ""
    echo "Next Steps:"
    echo "1. Deploy function code to: $FUNCTION_APP"
    echo "2. Upload test audio files to 'audio-input' container"
    echo "3. Monitor processing in 'content-output' container"
    echo ""
    echo "To cleanup resources, run:"
    echo "./destroy.sh -g $RESOURCE_GROUP"
    echo "=================================="
}

# Main deployment function
main() {
    log_info "Starting Voice-to-Multilingual Content Pipeline deployment"
    log_info "Deployment Name: $DEPLOYMENT_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites
    create_resource_group
    create_storage_account 
    create_speech_service
    create_openai_service
    create_translator_service
    create_function_app
    configure_function_app
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run completed successfully"
    else
        log_success "Deployment completed successfully!"
        display_summary
    fi
}

# Trap errors and cleanup
trap 'log_error "Deployment failed at line $LINENO"' ERR

# Run main function
main "$@"