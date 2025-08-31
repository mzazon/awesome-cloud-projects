#!/bin/bash

# Deploy script for Model Improvement Pipeline with Stored Completions and Prompt Flow
# This script deploys the complete Azure infrastructure for the model improvement recipe

set -e  # Exit on any error
set -u  # Exit on undefined variables

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
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Python is installed
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install Python 3.8+ first."
        exit 1
    fi
    
    # Check if pip is available
    if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
        log_error "pip is not installed. Please install pip first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set default location if not provided
    export LOCATION="${LOCATION:-eastus}"
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-model-pipeline-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set service-specific variables
    export OPENAI_SERVICE_NAME="openai-service-${RANDOM_SUFFIX}"
    export FUNCTION_APP_NAME="func-insights-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="st${RANDOM_SUFFIX}pipeline"
    export ML_WORKSPACE_NAME="mlw-pipeline-${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_WORKSPACE="law-${RANDOM_SUFFIX}"
    
    # Validate storage account name (must be 3-24 characters, lowercase letters and numbers only)
    if [[ ${#STORAGE_ACCOUNT_NAME} -gt 24 ]]; then
        export STORAGE_ACCOUNT_NAME="st${RANDOM_SUFFIX:0:3}pipe"
    fi
    
    log_success "Environment variables configured"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Random Suffix: ${RANDOM_SUFFIX}"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=recipe environment=demo project="model-improvement-pipeline" \
        --output none
    
    log_success "Resource group created successfully"
}

# Function to create Azure OpenAI Service
create_openai_service() {
    log_info "Creating Azure OpenAI Service: ${OPENAI_SERVICE_NAME}"
    
    # Create Azure OpenAI Service
    az cognitiveservices account create \
        --name "${OPENAI_SERVICE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --kind OpenAI \
        --sku S0 \
        --custom-domain "${OPENAI_SERVICE_NAME}" \
        --output none
    
    # Wait for service to be ready
    log_info "Waiting for OpenAI service to be fully provisioned..."
    sleep 30
    
    # Get OpenAI service endpoint and key
    export OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "${OPENAI_SERVICE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.endpoint --output tsv)
    
    export OPENAI_API_KEY=$(az cognitiveservices account keys list \
        --name "${OPENAI_SERVICE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 --output tsv)
    
    log_success "Azure OpenAI Service created with endpoint: ${OPENAI_ENDPOINT}"
}

# Function to deploy GPT model
deploy_gpt_model() {
    log_info "Deploying GPT-4o model for conversation capture"
    
    # Deploy GPT-4o model
    az cognitiveservices account deployment create \
        --name "${OPENAI_SERVICE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-name gpt-4o-deployment \
        --model-name gpt-4o \
        --model-version "2024-08-06" \
        --model-format OpenAI \
        --sku-capacity 10 \
        --sku-name Standard \
        --output none
    
    # Wait for deployment to complete
    log_info "Waiting for model deployment to complete..."
    sleep 45
    
    # Verify deployment status
    local deployment_status=$(az cognitiveservices account deployment show \
        --name "${OPENAI_SERVICE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-name gpt-4o-deployment \
        --query properties.provisioningState --output tsv 2>/dev/null || echo "Unknown")
    
    if [[ "${deployment_status}" == "Succeeded" ]]; then
        log_success "GPT-4o model deployed successfully"
    else
        log_warning "Model deployment status: ${deployment_status}"
    fi
}

# Function to create ML workspace
create_ml_workspace() {
    log_info "Creating Azure Machine Learning workspace: ${ML_WORKSPACE_NAME}"
    
    # Create Azure Machine Learning workspace
    az ml workspace create \
        --name "${ML_WORKSPACE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --output none
    
    # Get workspace details
    export ML_WORKSPACE_ID=$(az ml workspace show \
        --name "${ML_WORKSPACE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    log_success "ML Workspace created: ${ML_WORKSPACE_NAME}"
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT_NAME}"
    
    # Create storage account
    az storage account create \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --output none
    
    # Get storage connection string
    export STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString --output tsv)
    
    # Create containers for pipeline data
    az storage container create \
        --name conversations \
        --connection-string "${STORAGE_CONNECTION_STRING}" \
        --output none
    
    az storage container create \
        --name insights \
        --connection-string "${STORAGE_CONNECTION_STRING}" \
        --output none
    
    log_success "Storage account created with containers for pipeline data"
}

# Function to install Python dependencies
install_python_dependencies() {
    log_info "Installing required Python packages..."
    
    # Create a temporary requirements file
    cat > /tmp/requirements.txt << 'EOF'
openai>=1.12.0
azure-identity>=1.15.0
azure-functions>=1.18.0
azure-storage-blob>=12.19.0
azure-ai-ml>=1.12.0
pandas>=2.0.0
EOF
    
    # Install packages
    if command -v pip3 &> /dev/null; then
        pip3 install -r /tmp/requirements.txt --user --quiet
    else
        pip install -r /tmp/requirements.txt --user --quiet
    fi
    
    # Clean up
    rm -f /tmp/requirements.txt
    
    log_success "Python dependencies installed"
}

# Function to generate sample conversations
generate_sample_conversations() {
    log_info "Generating sample conversations with stored completions"
    
    # Create Python script for conversation generation
    cat > /tmp/generate_conversations.py << 'EOF'
import os
import json
import sys
from datetime import datetime
try:
    from openai import AzureOpenAI
    from azure.identity import DefaultAzureCredential, get_bearer_token_provider
except ImportError as e:
    print(f"Error: Required package not installed: {e}")
    print("Please install required packages: pip install openai azure-identity")
    sys.exit(1)

def main():
    try:
        # Initialize Azure OpenAI client with Azure AD authentication
        token_provider = get_bearer_token_provider(
            DefaultAzureCredential(), 
            "https://cognitiveservices.azure.com/.default"
        )

        client = AzureOpenAI(
            azure_endpoint=os.getenv("OPENAI_ENDPOINT"),
            azure_ad_token_provider=token_provider,
            api_version="2025-02-01-preview"
        )

        # Sample conversation scenarios with diverse use cases
        scenarios = [
            {
                "user_type": "customer_support",
                "category": "technical_issue",
                "messages": [
                    {"role": "system", "content": "You are a helpful technical support assistant."},
                    {"role": "user", "content": "My application keeps crashing when I try to upload files larger than 100MB."},
                ]
            },
            {
                "user_type": "sales_inquiry",
                "category": "product_info",
                "messages": [
                    {"role": "system", "content": "You are a knowledgeable sales assistant."},
                    {"role": "user", "content": "What are the key differences between your premium and enterprise plans?"},
                ]
            },
            {
                "user_type": "onboarding",
                "category": "getting_started",
                "messages": [
                    {"role": "system", "content": "You are a friendly onboarding specialist."},
                    {"role": "user", "content": "I just signed up for your service. How do I get started with my first project?"},
                ]
            },
            {
                "user_type": "billing_support",
                "category": "account_management",
                "messages": [
                    {"role": "system", "content": "You are a billing support specialist."},
                    {"role": "user", "content": "I need to understand the charges on my last invoice."},
                ]
            }
        ]

        # Generate conversations with stored completions
        for i, scenario in enumerate(scenarios):
            completion = client.chat.completions.create(
                model="gpt-4o-deployment",
                store=True,  # Enable stored completions
                metadata={
                    "user_type": scenario["user_type"],
                    "category": scenario["category"],
                    "conversation_id": f"conv_{i+1}",
                    "pipeline_source": "demo",
                    "timestamp": str(datetime.utcnow())
                },
                messages=scenario["messages"]
            )
            
            print(f"Generated conversation {i+1}: {completion.id}")

        print("✅ Sample conversations generated with stored completions enabled")
        
    except Exception as e:
        print(f"Error generating conversations: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF
    
    # Run conversation generation with error handling
    if python3 /tmp/generate_conversations.py; then
        log_success "Sample conversations created with metadata for analysis"
    else
        log_warning "Sample conversation generation encountered issues, but continuing deployment"
    fi
    
    # Clean up
    rm -f /tmp/generate_conversations.py
}

# Function to create Azure Functions app
create_function_app() {
    log_info "Creating Function App for pipeline automation: ${FUNCTION_APP_NAME}"
    
    # Create Function App
    az functionapp create \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --storage-account "${STORAGE_ACCOUNT_NAME}" \
        --consumption-plan-location "${LOCATION}" \
        --runtime python \
        --runtime-version 3.12 \
        --functions-version 4 \
        --output none
    
    # Wait for function app creation
    log_info "Waiting for Function App to be ready..."
    sleep 30
    
    # Configure application settings
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
            "OPENAI_ENDPOINT=${OPENAI_ENDPOINT}" \
            "OPENAI_API_KEY=${OPENAI_API_KEY}" \
            "ML_WORKSPACE_NAME=${ML_WORKSPACE_NAME}" \
            "STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION_STRING}" \
        --output none
    
    log_success "Azure Functions created for pipeline automation"
}

# Function to create monitoring workspace
create_monitoring() {
    log_info "Setting up monitoring and alerting"
    
    # Create Log Analytics workspace
    az monitor log-analytics workspace create \
        --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --output none
    
    # Get workspace ID
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query customerId --output tsv)
    
    # Link Function App to Log Analytics
    az monitor diagnostic-settings create \
        --resource "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --resource-type "Microsoft.Web/sites" \
        --name "pipeline-monitoring" \
        --workspace "${WORKSPACE_ID}" \
        --logs '[{"category":"FunctionAppLogs","enabled":true}]' \
        --output none 2>/dev/null || log_warning "Diagnostic settings creation may have encountered issues"
    
    log_success "Monitoring and alerting configured"
}

# Function to create pipeline configuration files
create_pipeline_config() {
    log_info "Creating pipeline configuration files"
    
    # Create configuration directory
    mkdir -p ./pipeline-config
    
    # Create monitoring configuration
    cat > ./pipeline-config/monitoring_config.json << 'EOF'
{
  "pipeline_settings": {
    "analysis_frequency": "hourly",
    "batch_size": 50,
    "quality_threshold": 7.0,
    "alert_conditions": [
      "average_quality < 6.0",
      "response_length < 30",
      "error_rate > 0.05",
      "quality_issue_rate > 0.15"
    ]
  },
  "evaluation_metrics": [
    "response_quality",
    "user_satisfaction_indicators",
    "conversation_completion_rate",
    "issue_resolution_patterns",
    "response_time_analysis"
  ],
  "improvement_actions": [
    "prompt_optimization",
    "fine_tuning_data_preparation",
    "issue_categorization_updates",
    "user_experience_enhancements",
    "quality_threshold_adjustments"
  ]
}
EOF
    
    # Create deployment summary
    cat > ./pipeline-config/deployment_summary.json << EOF
{
  "deployment_info": {
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "resource_group": "${RESOURCE_GROUP}",
    "location": "${LOCATION}",
    "subscription_id": "${SUBSCRIPTION_ID}",
    "random_suffix": "${RANDOM_SUFFIX}"
  },
  "resources": {
    "openai_service": "${OPENAI_SERVICE_NAME}",
    "function_app": "${FUNCTION_APP_NAME}",
    "storage_account": "${STORAGE_ACCOUNT_NAME}",
    "ml_workspace": "${ML_WORKSPACE_NAME}",
    "log_analytics": "${LOG_ANALYTICS_WORKSPACE}",
    "openai_endpoint": "${OPENAI_ENDPOINT}"
  },
  "next_steps": [
    "Access Azure OpenAI Studio to manage models and deployments",
    "Configure Prompt Flow evaluation workflows in ML Studio",
    "Set up custom Function App code for specific analysis needs",
    "Configure monitoring alerts in Azure Monitor",
    "Review stored completions in OpenAI service"
  ]
}
EOF
    
    log_success "Pipeline configuration files created in ./pipeline-config/"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    local validation_errors=0
    
    # Check resource group
    if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        log_success "Resource Group validation: PASSED"
    else
        log_error "Resource Group validation: FAILED"
        ((validation_errors++))
    fi
    
    # Check OpenAI service
    if az cognitiveservices account show --name "${OPENAI_SERVICE_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        log_success "OpenAI Service validation: PASSED"
    else
        log_error "OpenAI Service validation: FAILED"
        ((validation_errors++))
    fi
    
    # Check storage account
    if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        log_success "Storage Account validation: PASSED"
    else
        log_error "Storage Account validation: FAILED"
        ((validation_errors++))
    fi
    
    # Check ML workspace
    if az ml workspace show --name "${ML_WORKSPACE_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        log_success "ML Workspace validation: PASSED"
    else
        log_error "ML Workspace validation: FAILED"
        ((validation_errors++))
    fi
    
    # Check Function App
    if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        log_success "Function App validation: PASSED"
    else
        log_error "Function App validation: FAILED"
        ((validation_errors++))
    fi
    
    if [[ ${validation_errors} -eq 0 ]]; then
        log_success "All validations passed!"
        return 0
    else
        log_error "Validation failed with ${validation_errors} errors"
        return 1
    fi
}

# Function to display deployment summary
display_summary() {
    echo
    echo "=========================================="
    echo "         DEPLOYMENT COMPLETED"
    echo "=========================================="
    echo
    log_success "Model Improvement Pipeline deployed successfully!"
    echo
    echo "📋 Deployment Summary:"
    echo "   Resource Group: ${RESOURCE_GROUP}"
    echo "   Location: ${LOCATION}"
    echo "   OpenAI Service: ${OPENAI_SERVICE_NAME}"
    echo "   Function App: ${FUNCTION_APP_NAME}"
    echo "   Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "   ML Workspace: ${ML_WORKSPACE_NAME}"
    echo
    echo "🔗 Quick Links:"
    echo "   Azure Portal: https://portal.azure.com/#@/resource/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
    echo "   OpenAI Studio: https://oai.azure.com/"
    echo "   ML Studio: https://ml.azure.com/"
    echo
    echo "📁 Configuration files created in: ./pipeline-config/"
    echo
    echo "🚀 Next Steps:"
    echo "   1. Access Azure OpenAI Studio to explore stored completions"
    echo "   2. Configure Prompt Flow evaluation workflows in ML Studio"
    echo "   3. Set up monitoring alerts in Azure Monitor"
    echo "   4. Review the deployment summary in ./pipeline-config/deployment_summary.json"
    echo
    echo "💰 Estimated monthly cost: $20-40 (varies by usage)"
    echo "🧹 To clean up resources, run: ./destroy.sh"
    echo
}

# Main deployment function
main() {
    echo "=========================================="
    echo "  Model Improvement Pipeline Deployment"
    echo "=========================================="
    echo
    
    # Check if running in dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log_info "Running in dry-run mode - no resources will be created"
        setup_environment
        echo "Would create resources with these settings:"
        echo "  Resource Group: ${RESOURCE_GROUP}"
        echo "  Location: ${LOCATION}"
        echo "  OpenAI Service: ${OPENAI_SERVICE_NAME}"
        echo "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
        exit 0
    fi
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_resource_group
    create_openai_service
    deploy_gpt_model
    create_ml_workspace
    create_storage_account
    install_python_dependencies
    generate_sample_conversations
    create_function_app
    create_monitoring
    create_pipeline_config
    
    # Validate deployment
    if validate_deployment; then
        display_summary
    else
        log_error "Deployment validation failed. Please check the resources manually."
        exit 1
    fi
}

# Handle script interruption
trap 'log_error "Deployment interrupted. Some resources may have been created."; exit 1' INT TERM

# Run main function with all arguments
main "$@"