#!/bin/bash

# AI Model Evaluation and Benchmarking with Azure AI Foundry - Deployment Script
# This script deploys the complete infrastructure for AI model evaluation and benchmarking
# Recipe: ai-model-evaluation-benchmarking-foundry-openai

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
DEPLOYMENT_LOG="$PROJECT_ROOT/deployment.log"

# Default values - can be overridden by environment variables
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-ai-evaluation-$(openssl rand -hex 3)}"
LOCATION="${LOCATION:-eastus}"
AI_PROJECT_NAME="${AI_PROJECT_NAME:-ai-eval-project-$(openssl rand -hex 3)}"
OPENAI_RESOURCE_NAME="${OPENAI_RESOURCE_NAME:-openai-eval-$(openssl rand -hex 3)}"
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-storage$(openssl rand -hex 3)}"

# Validation functions
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random suffixes"
        exit 1
    fi
    
    # Validate location supports required services
    log "Validating location supports Azure OpenAI..."
    local openai_locations=$(az cognitiveservices account list-skus --kind OpenAI --query "[].locations[]" -o tsv | tr '\n' ' ')
    if [[ ! $openai_locations =~ $LOCATION ]]; then
        log_warning "Location $LOCATION might not support Azure OpenAI. Supported locations: $openai_locations"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    log_success "Prerequisites check completed"
}

check_quotas() {
    log "Checking Azure OpenAI quotas..."
    
    local subscription_id=$(az account show --query id --output tsv)
    log "Current subscription: $subscription_id"
    
    # Check cognitive services quota
    local quota_info=$(az cognitiveservices usage list --location $LOCATION --query "[?name.value=='OpenAI.Standard.S0']" -o json 2>/dev/null || echo "[]")
    if [[ "$quota_info" == "[]" ]]; then
        log_warning "Unable to retrieve OpenAI quota information. This might indicate the service is not available in this location."
    fi
    
    log_success "Quota check completed"
}

create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists, using existing one"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=ai-evaluation environment=demo recipe=ai-model-evaluation-benchmarking-foundry-openai \
            --output none
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

create_storage_account() {
    log "Creating storage account: $STORAGE_ACCOUNT_NAME"
    
    if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Storage account $STORAGE_ACCOUNT_NAME already exists, using existing one"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --output none
        
        # Wait for storage account to be ready
        local max_attempts=30
        local attempt=1
        while [ $attempt -le $max_attempts ]; do
            if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" --query "provisioningState" -o tsv | grep -q "Succeeded"; then
                break
            fi
            log "Waiting for storage account to be ready... (attempt $attempt/$max_attempts)"
            sleep 10
            ((attempt++))
        done
        
        if [ $attempt -gt $max_attempts ]; then
            log_error "Storage account creation timed out"
            exit 1
        fi
        
        log_success "Storage account created: $STORAGE_ACCOUNT_NAME"
    fi
}

create_openai_resource() {
    log "Creating Azure OpenAI resource: $OPENAI_RESOURCE_NAME"
    
    if az cognitiveservices account show --name "$OPENAI_RESOURCE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "OpenAI resource $OPENAI_RESOURCE_NAME already exists, using existing one"
    else
        az cognitiveservices account create \
            --name "$OPENAI_RESOURCE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind OpenAI \
            --sku S0 \
            --custom-domain "$OPENAI_RESOURCE_NAME" \
            --output none
        
        # Wait for OpenAI resource to be ready
        local max_attempts=60
        local attempt=1
        while [ $attempt -le $max_attempts ]; do
            if az cognitiveservices account show --name "$OPENAI_RESOURCE_NAME" --resource-group "$RESOURCE_GROUP" --query "provisioningState" -o tsv | grep -q "Succeeded"; then
                break
            fi
            log "Waiting for OpenAI resource to be ready... (attempt $attempt/$max_attempts)"
            sleep 15
            ((attempt++))
        done
        
        if [ $attempt -gt $max_attempts ]; then
            log_error "OpenAI resource creation timed out"
            exit 1
        fi
        
        log_success "OpenAI resource created: $OPENAI_RESOURCE_NAME"
    fi
}

deploy_models() {
    log "Deploying AI models..."
    
    # Deploy GPT-4o model
    log "Deploying GPT-4o model..."
    if az cognitiveservices account deployment show --name "$OPENAI_RESOURCE_NAME" --resource-group "$RESOURCE_GROUP" --deployment-name "gpt-4o-eval" &> /dev/null; then
        log_warning "GPT-4o deployment already exists, skipping"
    else
        az cognitiveservices account deployment create \
            --name "$OPENAI_RESOURCE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name "gpt-4o-eval" \
            --model-name "gpt-4o" \
            --model-version "2024-08-06" \
            --model-format "OpenAI" \
            --sku-capacity 10 \
            --sku-name "Standard" \
            --output none
        
        log_success "GPT-4o model deployed"
    fi
    
    # Deploy GPT-3.5 Turbo model
    log "Deploying GPT-3.5 Turbo model..."
    if az cognitiveservices account deployment show --name "$OPENAI_RESOURCE_NAME" --resource-group "$RESOURCE_GROUP" --deployment-name "gpt-35-turbo-eval" &> /dev/null; then
        log_warning "GPT-3.5 Turbo deployment already exists, skipping"
    else
        az cognitiveservices account deployment create \
            --name "$OPENAI_RESOURCE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name "gpt-35-turbo-eval" \
            --model-name "gpt-35-turbo" \
            --model-version "0125" \
            --model-format "OpenAI" \
            --sku-capacity 10 \
            --sku-name "Standard" \
            --output none
        
        log_success "GPT-3.5 Turbo model deployed"
    fi
    
    # Deploy GPT-4o Mini model
    log "Deploying GPT-4o Mini model..."
    if az cognitiveservices account deployment show --name "$OPENAI_RESOURCE_NAME" --resource-group "$RESOURCE_GROUP" --deployment-name "gpt-4o-mini-eval" &> /dev/null; then
        log_warning "GPT-4o Mini deployment already exists, skipping"
    else
        az cognitiveservices account deployment create \
            --name "$OPENAI_RESOURCE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name "gpt-4o-mini-eval" \
            --model-name "gpt-4o-mini" \
            --model-version "2024-07-18" \
            --model-format "OpenAI" \
            --sku-capacity 10 \
            --sku-name "Standard" \
            --output none
        
        log_success "GPT-4o Mini model deployed"
    fi
}

create_ai_project() {
    log "Creating AI Foundry project: $AI_PROJECT_NAME"
    
    if az ml workspace show --name "$AI_PROJECT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "AI project $AI_PROJECT_NAME already exists, using existing one"
    else
        az ml workspace create \
            --name "$AI_PROJECT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --storage-account "$STORAGE_ACCOUNT_NAME" \
            --description "AI Model Evaluation Project" \
            --output none
        
        # Set default workspace for subsequent operations
        az configure --defaults workspace="$AI_PROJECT_NAME" group="$RESOURCE_GROUP"
        
        log_success "AI Foundry project created: $AI_PROJECT_NAME"
    fi
}

setup_evaluation_dataset() {
    log "Setting up evaluation dataset..."
    
    # Create evaluation dataset file
    cat > "$PROJECT_ROOT/evaluation_dataset.jsonl" << 'EOF'
{"question": "Explain the benefits of cloud computing for small businesses", "expected_categories": ["technology", "business"], "complexity": "intermediate"}
{"question": "What are the best practices for data security in healthcare?", "expected_categories": ["security", "healthcare"], "complexity": "advanced"}
{"question": "How do I set up a basic website?", "expected_categories": ["technology", "beginner"], "complexity": "basic"}
{"question": "Describe the impact of AI on modern marketing strategies", "expected_categories": ["ai", "marketing"], "complexity": "advanced"}
{"question": "What are the key components of a business plan?", "expected_categories": ["business", "planning"], "complexity": "intermediate"}
{"question": "Explain machine learning in simple terms", "expected_categories": ["ai", "education"], "complexity": "basic"}
{"question": "How can IoT devices improve supply chain management?", "expected_categories": ["iot", "business"], "complexity": "advanced"}
{"question": "What is the difference between HTTP and HTTPS?", "expected_categories": ["technology", "security"], "complexity": "intermediate"}
{"question": "How to implement sustainable business practices?", "expected_categories": ["business", "sustainability"], "complexity": "intermediate"}
{"question": "What are the fundamentals of cybersecurity?", "expected_categories": ["security", "technology"], "complexity": "advanced"}
EOF
    
    # Upload dataset to Azure ML datastore
    if az ml data show --name "evaluation-dataset" --version 1 &> /dev/null; then
        log_warning "Evaluation dataset already exists, skipping upload"
    else
        az ml data create \
            --name "evaluation-dataset" \
            --version 1 \
            --type "uri_file" \
            --path "$PROJECT_ROOT/evaluation_dataset.jsonl" \
            --description "Model evaluation test dataset" \
            --output none
        
        log_success "Evaluation dataset created and uploaded"
    fi
}

create_evaluation_environment() {
    log "Creating evaluation environment..."
    
    # Create environment file
    cat > "$PROJECT_ROOT/evaluation_environment.yml" << 'EOF'
name: evaluation-env
channels:
  - conda-forge
dependencies:
  - python=3.9
  - pip
  - pip:
    - promptflow[azure]
    - openai
    - azure-ai-ml
EOF
    
    if az ml environment show --name "evaluation-environment" --version 1 &> /dev/null; then
        log_warning "Evaluation environment already exists, skipping creation"
    else
        az ml environment create \
            --name "evaluation-environment" \
            --version 1 \
            --conda-file "$PROJECT_ROOT/evaluation_environment.yml" \
            --description "Environment for model evaluation runs" \
            --output none
        
        log_success "Evaluation environment created"
    fi
}

display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "======================================"
    echo "DEPLOYMENT SUMMARY"
    echo "======================================"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "AI Project: $AI_PROJECT_NAME"
    echo "OpenAI Resource: $OPENAI_RESOURCE_NAME"
    echo "Storage Account: $STORAGE_ACCOUNT_NAME"
    echo
    echo "Deployed Models:"
    echo "  - gpt-4o-eval (GPT-4o 2024-08-06)"
    echo "  - gpt-35-turbo-eval (GPT-3.5 Turbo 0125)"
    echo "  - gpt-4o-mini-eval (GPT-4o Mini 2024-07-18)"
    echo
    echo "Next Steps:"
    echo "1. Access Azure AI Foundry portal: https://ai.azure.com"
    echo "2. Navigate to your project: $AI_PROJECT_NAME"
    echo "3. Use the evaluation dataset to compare models"
    echo
    echo "To clean up resources, run: ./destroy.sh"
    echo "======================================"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check the logs for details."
    echo "To clean up any partially created resources, run: ./destroy.sh"
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Main execution
main() {
    log "Starting AI Model Evaluation deployment..."
    log "Deployment log: $DEPLOYMENT_LOG"
    
    # Redirect all output to log file while still showing on console
    exec > >(tee -a "$DEPLOYMENT_LOG")
    exec 2>&1
    
    check_prerequisites
    check_quotas
    create_resource_group
    create_storage_account
    create_openai_resource
    deploy_models
    create_ai_project
    setup_evaluation_dataset
    create_evaluation_environment
    display_summary
    
    log_success "All components deployed successfully!"
}

# Help function
show_help() {
    cat << EOF
AI Model Evaluation and Benchmarking Deployment Script

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -g, --resource-group    Resource group name (default: auto-generated)
    -l, --location          Azure region (default: eastus)
    -p, --project-name      AI project name (default: auto-generated)
    -o, --openai-name       OpenAI resource name (default: auto-generated)
    -s, --storage-name      Storage account name (default: auto-generated)
    --dry-run              Show what would be deployed without creating resources

ENVIRONMENT VARIABLES:
    RESOURCE_GROUP         Override default resource group name
    LOCATION              Override default location
    AI_PROJECT_NAME       Override default AI project name
    OPENAI_RESOURCE_NAME  Override default OpenAI resource name
    STORAGE_ACCOUNT_NAME  Override default storage account name

EXAMPLES:
    $0                                           # Deploy with defaults
    $0 -g my-rg -l westus2                     # Deploy to specific RG and location
    $0 --dry-run                               # Show deployment plan
    LOCATION=eastus2 $0                        # Deploy using environment variable

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -p|--project-name)
            AI_PROJECT_NAME="$2"
            shift 2
            ;;
        -o|--openai-name)
            OPENAI_RESOURCE_NAME="$2"
            shift 2
            ;;
        -s|--storage-name)
            STORAGE_ACCOUNT_NAME="$2"
            shift 2
            ;;
        --dry-run)
            log "DRY RUN MODE - No resources will be created"
            log "Would deploy:"
            log "  Resource Group: $RESOURCE_GROUP"
            log "  Location: $LOCATION"
            log "  AI Project: $AI_PROJECT_NAME"
            log "  OpenAI Resource: $OPENAI_RESOURCE_NAME"
            log "  Storage Account: $STORAGE_ACCOUNT_NAME"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main