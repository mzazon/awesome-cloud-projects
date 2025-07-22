#!/bin/bash

# =============================================================================
# Azure Serverless AI Prompt Workflow Deployment Script
# Recipe: Orchestrating Serverless AI Prompt Workflows with Azure AI Studio 
#         Prompt Flow and Azure Container Apps
# =============================================================================

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Error handler
error_handler() {
    local line_number=$1
    log_error "Script failed at line ${line_number}. Exiting..."
    exit 1
}

trap 'error_handler ${LINENO}' ERR

# Configuration variables with defaults
LOCATION="${LOCATION:-eastus}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-ai-serverless-$(date +%s)}"
AI_HUB_NAME="${AI_HUB_NAME:-hub-ai-$(date +%s)}"
AI_PROJECT_NAME="${AI_PROJECT_NAME:-project-promptflow-$(date +%s)}"
ACR_NAME="${ACR_NAME:-acr$(date +%s | tail -c 7)}"
ACA_ENV_NAME="${ACA_ENV_NAME:-env-serverless-$(date +%s)}"
ACA_APP_NAME="${ACA_APP_NAME:-app-promptflow-$(date +%s)}"
WORKSPACE_NAME="${WORKSPACE_NAME:-ws-ai-$(date +%s)}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-35-turbo}"
OPENAI_MODEL_VERSION="${OPENAI_MODEL_VERSION:-0613}"
OPENAI_CAPACITY="${OPENAI_CAPACITY:-10}"

# Dry run flag
DRY_RUN="${DRY_RUN:-false}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: ${az_version}"
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker from https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check OpenSSL for random generation
    if ! command -v openssl &> /dev/null; then
        log_warning "OpenSSL not found. Using alternative method for random generation."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate Azure subscription and quotas
validate_subscription() {
    log_info "Validating Azure subscription and quotas..."
    
    local subscription_id
    subscription_id=$(az account show --query id -o tsv)
    log_info "Using subscription: ${subscription_id}"
    
    # Check if required providers are registered
    local providers=("Microsoft.App" "Microsoft.CognitiveServices" "Microsoft.ContainerRegistry" "Microsoft.MachineLearningServices" "Microsoft.OperationalInsights")
    
    for provider in "${providers[@]}"; do
        local status
        status=$(az provider show --namespace "${provider}" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
        
        if [[ "${status}" != "Registered" ]]; then
            log_warning "Provider ${provider} is not registered. Registering..."
            if [[ "${DRY_RUN}" == "false" ]]; then
                az provider register --namespace "${provider}" --wait
                log_success "Provider ${provider} registered"
            else
                log_info "[DRY RUN] Would register provider ${provider}"
            fi
        else
            log_info "Provider ${provider} is already registered"
        fi
    done
    
    log_success "Subscription validation completed"
}

# Function to generate unique suffix
generate_random_suffix() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 3
    else
        # Fallback method using date and random
        echo $(date +%s | tail -c 7)$(($RANDOM % 100))
    fi
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            log_warning "Resource group ${RESOURCE_GROUP} already exists"
        else
            az group create \
                --name "${RESOURCE_GROUP}" \
                --location "${LOCATION}" \
                --output none
            log_success "Resource group created: ${RESOURCE_GROUP}"
        fi
    else
        log_info "[DRY RUN] Would create resource group ${RESOURCE_GROUP} in ${LOCATION}"
    fi
}

# Function to create Azure Container Registry
create_container_registry() {
    log_info "Creating Azure Container Registry: ${ACR_NAME}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        if az acr show --name "${ACR_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log_warning "Container Registry ${ACR_NAME} already exists"
        else
            az acr create \
                --name "${ACR_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --sku Basic \
                --admin-enabled true \
                --output none
            log_success "Container Registry created: ${ACR_NAME}"
        fi
    else
        log_info "[DRY RUN] Would create Container Registry ${ACR_NAME}"
    fi
}

# Function to create AI Hub and Project
create_ai_resources() {
    log_info "Creating AI Hub and Project..."
    
    local random_suffix
    random_suffix=$(generate_random_suffix)
    local storage_account="st${random_suffix}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create storage account for AI Hub
        log_info "Creating storage account: ${storage_account}"
        if ! az storage account show --name "${storage_account}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az storage account create \
                --name "${storage_account}" \
                --resource-group "${RESOURCE_GROUP}" \
                --location "${LOCATION}" \
                --sku Standard_LRS \
                --output none
            log_success "Storage account created: ${storage_account}"
        else
            log_warning "Storage account ${storage_account} already exists"
        fi
        
        # Create AI Hub
        log_info "Creating AI Hub: ${AI_HUB_NAME}"
        if ! az ml workspace show --name "${AI_HUB_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az ml workspace create \
                --name "${AI_HUB_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --location "${LOCATION}" \
                --kind hub \
                --storage-account "${storage_account}" \
                --output none
            log_success "AI Hub created: ${AI_HUB_NAME}"
        else
            log_warning "AI Hub ${AI_HUB_NAME} already exists"
        fi
        
        # Create AI Project
        log_info "Creating AI Project: ${AI_PROJECT_NAME}"
        if ! az ml workspace show --name "${AI_PROJECT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            local subscription_id
            subscription_id=$(az account show --query id -o tsv)
            local hub_id="/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/workspaces/${AI_HUB_NAME}"
            
            az ml workspace create \
                --name "${AI_PROJECT_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --location "${LOCATION}" \
                --kind project \
                --hub-id "${hub_id}" \
                --output none
            log_success "AI Project created: ${AI_PROJECT_NAME}"
        else
            log_warning "AI Project ${AI_PROJECT_NAME} already exists"
        fi
    else
        log_info "[DRY RUN] Would create storage account ${storage_account}"
        log_info "[DRY RUN] Would create AI Hub ${AI_HUB_NAME}"
        log_info "[DRY RUN] Would create AI Project ${AI_PROJECT_NAME}"
    fi
}

# Function to deploy Azure OpenAI
deploy_openai() {
    log_info "Deploying Azure OpenAI resources..."
    
    local random_suffix
    random_suffix=$(generate_random_suffix)
    local openai_name="aoai-${random_suffix}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create Azure OpenAI resource
        log_info "Creating Azure OpenAI resource: ${openai_name}"
        if ! az cognitiveservices account show --name "${openai_name}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az cognitiveservices account create \
                --name "${openai_name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --location "${LOCATION}" \
                --kind OpenAI \
                --sku S0 \
                --custom-domain "${openai_name}" \
                --output none
            log_success "Azure OpenAI resource created: ${openai_name}"
        else
            log_warning "Azure OpenAI resource ${openai_name} already exists"
        fi
        
        # Wait for resource to be ready
        log_info "Waiting for OpenAI resource to be ready..."
        sleep 30
        
        # Deploy GPT model
        log_info "Deploying ${OPENAI_MODEL} model..."
        if ! az cognitiveservices account deployment show \
            --name "${openai_name}" \
            --resource-group "${RESOURCE_GROUP}" \
            --deployment-name "${OPENAI_MODEL}" &> /dev/null; then
            
            az cognitiveservices account deployment create \
                --name "${openai_name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --deployment-name "${OPENAI_MODEL}" \
                --model-name "${OPENAI_MODEL}" \
                --model-version "${OPENAI_MODEL_VERSION}" \
                --model-format OpenAI \
                --sku-name "Standard" \
                --sku-capacity "${OPENAI_CAPACITY}" \
                --output none
            log_success "Model ${OPENAI_MODEL} deployed"
        else
            log_warning "Model ${OPENAI_MODEL} already deployed"
        fi
        
        # Export OpenAI details for later use
        export OPENAI_NAME="${openai_name}"
        export OPENAI_ENDPOINT=$(az cognitiveservices account show \
            --name "${openai_name}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query properties.endpoint -o tsv)
        export OPENAI_KEY=$(az cognitiveservices account keys list \
            --name "${openai_name}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query key1 -o tsv)
        
        log_success "Azure OpenAI deployed with endpoint: ${OPENAI_ENDPOINT}"
    else
        log_info "[DRY RUN] Would create Azure OpenAI resource ${openai_name}"
        log_info "[DRY RUN] Would deploy model ${OPENAI_MODEL}"
    fi
}

# Function to create Container Apps environment
create_container_apps_environment() {
    log_info "Creating Container Apps environment..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create Log Analytics workspace
        log_info "Creating Log Analytics workspace: ${WORKSPACE_NAME}"
        if ! az monitor log-analytics workspace show --name "${WORKSPACE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az monitor log-analytics workspace create \
                --name "${WORKSPACE_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --location "${LOCATION}" \
                --output none
            log_success "Log Analytics workspace created: ${WORKSPACE_NAME}"
        else
            log_warning "Log Analytics workspace ${WORKSPACE_NAME} already exists"
        fi
        
        # Get Log Analytics credentials
        local log_analytics_id
        local log_analytics_key
        log_analytics_id=$(az monitor log-analytics workspace show \
            --name "${WORKSPACE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query customerId -o tsv)
        log_analytics_key=$(az monitor log-analytics workspace get-shared-keys \
            --name "${WORKSPACE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query primarySharedKey -o tsv)
        
        # Create Container Apps environment
        log_info "Creating Container Apps environment: ${ACA_ENV_NAME}"
        if ! az containerapp env show --name "${ACA_ENV_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az containerapp env create \
                --name "${ACA_ENV_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --location "${LOCATION}" \
                --logs-workspace-id "${log_analytics_id}" \
                --logs-workspace-key "${log_analytics_key}" \
                --output none
            log_success "Container Apps environment created: ${ACA_ENV_NAME}"
        else
            log_warning "Container Apps environment ${ACA_ENV_NAME} already exists"
        fi
    else
        log_info "[DRY RUN] Would create Log Analytics workspace ${WORKSPACE_NAME}"
        log_info "[DRY RUN] Would create Container Apps environment ${ACA_ENV_NAME}"
    fi
}

# Function to create prompt flow files
create_prompt_flow_files() {
    log_info "Creating prompt flow files..."
    
    local temp_dir="/tmp/promptflow-$$"
    mkdir -p "${temp_dir}"
    
    # Create flow.dag.yaml
    cat > "${temp_dir}/flow.dag.yaml" << 'EOF'
inputs:
  question:
    type: string
outputs:
  answer:
    type: string
    reference: ${answer_node.output}
nodes:
- name: answer_node
  type: llm
  source:
    type: code
    path: answer.jinja2
  inputs:
    deployment_name: gpt-35-turbo
    temperature: 0.7
    max_tokens: 150
    question: ${inputs.question}
  connection: aoai_connection
EOF
    
    # Create prompt template
    cat > "${temp_dir}/answer.jinja2" << 'EOF'
system:
You are a helpful AI assistant that provides clear and concise answers.

user:
{{question}}
EOF
    
    # Create requirements file
    cat > "${temp_dir}/requirements.txt" << 'EOF'
promptflow==1.10.0
promptflow-tools==1.4.0
python-dotenv==1.0.0
EOF
    
    # Create Dockerfile
    cat > "${temp_dir}/Dockerfile" << 'EOF'
FROM mcr.microsoft.com/azureml/promptflow/promptflow-runtime:latest

WORKDIR /app

# Copy flow files
COPY flow.dag.yaml .
COPY answer.jinja2 .
COPY requirements.txt .

# Install dependencies
RUN pip install -r requirements.txt

# Set environment variables
ENV AZURE_OPENAI_ENDPOINT=${AZURE_OPENAI_ENDPOINT}
ENV AZURE_OPENAI_API_KEY=${AZURE_OPENAI_API_KEY}

# Expose port
EXPOSE 8080

# Run prompt flow
CMD ["pf", "flow", "serve", "--source", ".", "--port", "8080", "--host", "0.0.0.0"]
EOF
    
    export TEMP_DIR="${temp_dir}"
    log_success "Prompt flow files created in ${temp_dir}"
}

# Function to build and push container image
build_and_push_image() {
    log_info "Building and pushing container image..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Login to ACR
        log_info "Logging in to Azure Container Registry..."
        az acr login --name "${ACR_NAME}"
        
        # Build container image
        log_info "Building container image..."
        docker build -t "promptflow-app:latest" "${TEMP_DIR}"
        
        # Tag for ACR
        local acr_login_server
        acr_login_server=$(az acr show --name "${ACR_NAME}" --resource-group "${RESOURCE_GROUP}" --query loginServer -o tsv)
        docker tag "promptflow-app:latest" "${acr_login_server}/promptflow-app:latest"
        
        # Push to ACR
        log_info "Pushing image to Container Registry..."
        docker push "${acr_login_server}/promptflow-app:latest"
        
        export ACR_LOGIN_SERVER="${acr_login_server}"
        log_success "Container image built and pushed to ${acr_login_server}/promptflow-app:latest"
    else
        log_info "[DRY RUN] Would build and push container image to ${ACR_NAME}"
    fi
}

# Function to deploy Container App
deploy_container_app() {
    log_info "Deploying Container App..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Get ACR credentials
        local acr_username
        local acr_password
        acr_username=$(az acr credential show --name "${ACR_NAME}" --query username -o tsv)
        acr_password=$(az acr credential show --name "${ACR_NAME}" --query passwords[0].value -o tsv)
        
        # Create Container App
        log_info "Creating Container App: ${ACA_APP_NAME}"
        if ! az containerapp show --name "${ACA_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az containerapp create \
                --name "${ACA_APP_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --environment "${ACA_ENV_NAME}" \
                --image "${ACR_LOGIN_SERVER}/promptflow-app:latest" \
                --registry-server "${ACR_LOGIN_SERVER}" \
                --registry-username "${acr_username}" \
                --registry-password "${acr_password}" \
                --target-port 8080 \
                --ingress external \
                --min-replicas 0 \
                --max-replicas 10 \
                --scale-rule-name http-rule \
                --scale-rule-type http \
                --scale-rule-http-concurrency 10 \
                --env-vars \
                    AZURE_OPENAI_ENDPOINT="${OPENAI_ENDPOINT}" \
                    AZURE_OPENAI_API_KEY="${OPENAI_KEY}" \
                --output none
            
            log_success "Container App created: ${ACA_APP_NAME}"
        else
            log_warning "Container App ${ACA_APP_NAME} already exists"
        fi
        
        # Get Container App URL
        export APP_URL=$(az containerapp show \
            --name "${ACA_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query properties.configuration.ingress.fqdn -o tsv)
        
        log_success "Container App deployed at: https://${APP_URL}"
    else
        log_info "[DRY RUN] Would deploy Container App ${ACA_APP_NAME}"
    fi
}

# Function to configure monitoring
configure_monitoring() {
    log_info "Configuring monitoring and alerts..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Enable Application Insights
        local app_insights_name="${ACA_APP_NAME}-insights"
        log_info "Creating Application Insights: ${app_insights_name}"
        
        if ! az monitor app-insights component show --app "${app_insights_name}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az monitor app-insights component create \
                --app "${app_insights_name}" \
                --location "${LOCATION}" \
                --resource-group "${RESOURCE_GROUP}" \
                --workspace "${WORKSPACE_NAME}" \
                --output none
            log_success "Application Insights created: ${app_insights_name}"
        else
            log_warning "Application Insights ${app_insights_name} already exists"
        fi
        
        # Get Application Insights key
        local instrumentation_key
        instrumentation_key=$(az monitor app-insights component show \
            --app "${app_insights_name}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query instrumentationKey -o tsv)
        
        # Update Container App with Application Insights
        log_info "Updating Container App with Application Insights integration..."
        az containerapp update \
            --name "${ACA_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --set-env-vars \
                APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=${instrumentation_key}" \
            --output none
        
        # Create alert rule for high response time
        local alert_name="${ACA_APP_NAME}-response-time-alert"
        log_info "Creating alert rule: ${alert_name}"
        
        if ! az monitor metrics alert show --name "${alert_name}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            local subscription_id
            subscription_id=$(az account show --query id -o tsv)
            local scope="/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.App/containerApps/${ACA_APP_NAME}"
            
            az monitor metrics alert create \
                --name "${alert_name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --scopes "${scope}" \
                --condition "avg ResponseTime > 1000" \
                --window-size 5m \
                --evaluation-frequency 1m \
                --description "Alert when average response time exceeds 1 second" \
                --output none
            log_success "Alert rule created: ${alert_name}"
        else
            log_warning "Alert rule ${alert_name} already exists"
        fi
        
        log_success "Monitoring and alerts configured"
    else
        log_info "[DRY RUN] Would configure Application Insights and alerts"
    fi
}

# Function to perform deployment validation
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Test the deployed prompt flow endpoint
        if [[ -n "${APP_URL:-}" ]]; then
            log_info "Testing prompt flow endpoint..."
            local test_response
            test_response=$(curl -s -X POST "https://${APP_URL}/score" \
                -H "Content-Type: application/json" \
                -d '{"question": "What is Azure Container Apps?"}' \
                --max-time 30 || echo "ERROR")
            
            if [[ "${test_response}" != "ERROR" ]] && [[ -n "${test_response}" ]]; then
                log_success "Endpoint test successful"
                log_info "Response: ${test_response}"
            else
                log_warning "Endpoint test failed or timed out"
            fi
        else
            log_warning "APP_URL not available for testing"
        fi
        
        # Check resource status
        log_info "Checking resource status..."
        
        # Check Container App status
        local app_status
        app_status=$(az containerapp show \
            --name "${ACA_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query properties.provisioningState -o tsv 2>/dev/null || echo "NotFound")
        
        if [[ "${app_status}" == "Succeeded" ]]; then
            log_success "Container App is running successfully"
        else
            log_warning "Container App status: ${app_status}"
        fi
        
        log_success "Deployment validation completed"
    else
        log_info "[DRY RUN] Would validate deployment"
    fi
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    local info_file="${PWD}/deployment-info.txt"
    
    cat > "${info_file}" << EOF
# Azure Serverless AI Prompt Workflow Deployment Information
# Generated on: $(date)

RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
AI_HUB_NAME=${AI_HUB_NAME}
AI_PROJECT_NAME=${AI_PROJECT_NAME}
ACR_NAME=${ACR_NAME}
ACA_ENV_NAME=${ACA_ENV_NAME}
ACA_APP_NAME=${ACA_APP_NAME}
WORKSPACE_NAME=${WORKSPACE_NAME}
OPENAI_NAME=${OPENAI_NAME:-}
OPENAI_ENDPOINT=${OPENAI_ENDPOINT:-}
APP_URL=${APP_URL:-}
ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-}

# To test the endpoint:
# curl -X POST "https://${APP_URL:-<APP_URL>}/score" \\
#      -H "Content-Type: application/json" \\
#      -d '{"question": "Your question here"}'

# To view logs:
# az containerapp logs show --name ${ACA_APP_NAME} --resource-group ${RESOURCE_GROUP}

# To clean up:
# ./destroy.sh
EOF
    
    log_success "Deployment information saved to ${info_file}"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    if [[ -n "${TEMP_DIR:-}" ]] && [[ -d "${TEMP_DIR}" ]]; then
        log_info "Cleaning up temporary files..."
        rm -rf "${TEMP_DIR}"
        log_success "Temporary files cleaned up"
    fi
}

# Main deployment function
main() {
    echo "======================================================================"
    echo "Azure Serverless AI Prompt Workflow Deployment"
    echo "======================================================================"
    echo
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --location)
                LOCATION="$2"
                shift 2
                ;;
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --dry-run              Perform a dry run without creating resources"
                echo "  --location LOCATION    Azure region (default: eastus)"
                echo "  --resource-group NAME  Resource group name (default: auto-generated)"
                echo "  --help                 Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
        echo
    fi
    
    # Display configuration
    log_info "Deployment Configuration:"
    echo "  Location: ${LOCATION}"
    echo "  Resource Group: ${RESOURCE_GROUP}"
    echo "  AI Hub: ${AI_HUB_NAME}"
    echo "  AI Project: ${AI_PROJECT_NAME}"
    echo "  Container Registry: ${ACR_NAME}"
    echo "  Container Apps Environment: ${ACA_ENV_NAME}"
    echo "  Container App: ${ACA_APP_NAME}"
    echo "  Log Analytics Workspace: ${WORKSPACE_NAME}"
    echo
    
    # Set up cleanup trap
    trap cleanup_temp_files EXIT
    
    # Execute deployment steps
    check_prerequisites
    validate_subscription
    create_resource_group
    create_container_registry
    create_ai_resources
    deploy_openai
    create_container_apps_environment
    create_prompt_flow_files
    build_and_push_image
    deploy_container_app
    configure_monitoring
    validate_deployment
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        save_deployment_info
    fi
    
    echo
    echo "======================================================================"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_success "DRY RUN COMPLETED - No resources were created"
    else
        log_success "DEPLOYMENT COMPLETED SUCCESSFULLY!"
        echo
        if [[ -n "${APP_URL:-}" ]]; then
            echo "🚀 Your serverless AI prompt workflow is now available at:"
            echo "   https://${APP_URL}"
            echo
            echo "📝 Test your endpoint with:"
            echo "   curl -X POST \"https://${APP_URL}/score\" \\"
            echo "        -H \"Content-Type: application/json\" \\"
            echo "        -d '{\"question\": \"What is Azure Container Apps?\"}'"
        fi
        echo
        echo "📊 Monitor your application:"
        echo "   az containerapp logs show --name ${ACA_APP_NAME} --resource-group ${RESOURCE_GROUP}"
        echo
        echo "🧹 Clean up resources when done:"
        echo "   ./destroy.sh"
    fi
    echo "======================================================================"
}

# Execute main function with all arguments
main "$@"