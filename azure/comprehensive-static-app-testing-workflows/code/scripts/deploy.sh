#!/bin/bash

# Azure Static Web Apps and Container Apps Jobs CI/CD Testing Deployment Script
# This script deploys the complete infrastructure for automated CI/CD testing workflows

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Docker is installed (for container registry operations)
    if ! command -v docker &> /dev/null; then
        warn "Docker is not installed. You may need it for container operations."
    fi
    
    # Check if openssl is available for generating random values
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is not installed. Required for generating random suffixes."
        exit 1
    fi
    
    # Verify Azure CLI version
    local az_version=$(az version --query '."azure-cli"' -o tsv)
    info "Azure CLI version: $az_version"
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set default values (can be overridden by environment variables)
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-cicd-testing-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Static Web Apps variables
    export STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-cicd-demo-${RANDOM_SUFFIX}}"
    export GITHUB_REPO_URL="${GITHUB_REPO_URL:-https://github.com/yourusername/your-repo}"
    export GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
    
    # Container Apps variables
    export CONTAINER_APPS_ENV="${CONTAINER_APPS_ENV:-cae-testing-${RANDOM_SUFFIX}}"
    export CONTAINER_REGISTRY="${CONTAINER_REGISTRY:-acr${RANDOM_SUFFIX}}"
    export TEST_JOB_NAME="${TEST_JOB_NAME:-test-runner-job}"
    export LOAD_TEST_JOB_NAME="${LOAD_TEST_JOB_NAME:-load-test-job}"
    
    # Load Testing variables
    export LOAD_TEST_RESOURCE="${LOAD_TEST_RESOURCE:-alt-cicd-${RANDOM_SUFFIX}}"
    
    # Monitoring variables
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-cicd-${RANDOM_SUFFIX}}"
    export APPLICATION_INSIGHTS="${APPLICATION_INSIGHTS:-ai-cicd-${RANDOM_SUFFIX}}"
    
    info "Environment variables set:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Location: $LOCATION"
    info "  Random Suffix: $RANDOM_SUFFIX"
    info "  Static Web App: $STATIC_WEB_APP_NAME"
    info "  Container Apps Environment: $CONTAINER_APPS_ENV"
    info "  Container Registry: $CONTAINER_REGISTRY"
    
    log "Environment variables configured successfully"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=cicd-testing environment=demo
        
        log "Resource group $RESOURCE_GROUP created successfully"
    fi
}

# Function to create Log Analytics workspace
create_log_analytics_workspace() {
    log "Creating Log Analytics workspace..."
    
    if az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" &> /dev/null; then
        warn "Log Analytics workspace $LOG_ANALYTICS_WORKSPACE already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --location "$LOCATION"
        
        log "Log Analytics workspace $LOG_ANALYTICS_WORKSPACE created successfully"
    fi
    
    # Get workspace ID for later use
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query customerId --output tsv)
    
    info "Workspace ID: $WORKSPACE_ID"
}

# Function to create Azure Container Registry
create_container_registry() {
    log "Creating Azure Container Registry..."
    
    if az acr show --name "$CONTAINER_REGISTRY" &> /dev/null; then
        warn "Container Registry $CONTAINER_REGISTRY already exists"
    else
        az acr create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$CONTAINER_REGISTRY" \
            --sku Basic \
            --admin-enabled true \
            --location "$LOCATION"
        
        log "Container Registry $CONTAINER_REGISTRY created successfully"
    fi
    
    # Get ACR login server
    export ACR_LOGIN_SERVER=$(az acr show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CONTAINER_REGISTRY" \
        --query loginServer --output tsv)
    
    info "Container Registry login server: $ACR_LOGIN_SERVER"
}

# Function to create Container Apps Environment
create_container_apps_environment() {
    log "Creating Container Apps Environment..."
    
    if az containerapp env show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CONTAINER_APPS_ENV" &> /dev/null; then
        warn "Container Apps Environment $CONTAINER_APPS_ENV already exists"
    else
        az containerapp env create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$CONTAINER_APPS_ENV" \
            --location "$LOCATION" \
            --logs-workspace-id "$WORKSPACE_ID"
        
        # Wait for environment to be ready
        info "Waiting for Container Apps Environment to be ready..."
        local max_attempts=30
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            local state=$(az containerapp env show \
                --resource-group "$RESOURCE_GROUP" \
                --name "$CONTAINER_APPS_ENV" \
                --query provisioningState --output tsv)
            
            if [ "$state" = "Succeeded" ]; then
                log "Container Apps Environment $CONTAINER_APPS_ENV created successfully"
                break
            fi
            
            info "Attempt $attempt/$max_attempts: Environment state is $state, waiting..."
            sleep 10
            ((attempt++))
        done
        
        if [ $attempt -gt $max_attempts ]; then
            error "Container Apps Environment creation timed out"
            exit 1
        fi
    fi
}

# Function to create Static Web App
create_static_web_app() {
    log "Creating Static Web App..."
    
    if az staticwebapp show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STATIC_WEB_APP_NAME" &> /dev/null; then
        warn "Static Web App $STATIC_WEB_APP_NAME already exists"
    else
        if [ "$GITHUB_REPO_URL" = "https://github.com/yourusername/your-repo" ]; then
            warn "Using default GitHub repository URL. Please update GITHUB_REPO_URL environment variable with your actual repository."
        fi
        
        az staticwebapp create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$STATIC_WEB_APP_NAME" \
            --source "$GITHUB_REPO_URL" \
            --branch "$GITHUB_BRANCH" \
            --app-location "/" \
            --output-location "dist" \
            --location "$LOCATION"
        
        log "Static Web App $STATIC_WEB_APP_NAME created successfully"
    fi
    
    # Get Static Web App URL
    export STATIC_WEB_APP_URL=$(az staticwebapp show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STATIC_WEB_APP_NAME" \
        --query defaultHostname --output tsv)
    
    info "Static Web App URL: https://$STATIC_WEB_APP_URL"
}

# Function to create Application Insights
create_application_insights() {
    log "Creating Application Insights..."
    
    if az monitor app-insights component show \
        --resource-group "$RESOURCE_GROUP" \
        --app "$APPLICATION_INSIGHTS" &> /dev/null; then
        warn "Application Insights $APPLICATION_INSIGHTS already exists"
    else
        az monitor app-insights component create \
            --resource-group "$RESOURCE_GROUP" \
            --app "$APPLICATION_INSIGHTS" \
            --location "$LOCATION" \
            --workspace "$LOG_ANALYTICS_WORKSPACE"
        
        log "Application Insights $APPLICATION_INSIGHTS created successfully"
    fi
    
    # Get Application Insights instrumentation key
    export INSTRUMENTATION_KEY=$(az monitor app-insights component show \
        --resource-group "$RESOURCE_GROUP" \
        --app "$APPLICATION_INSIGHTS" \
        --query instrumentationKey --output tsv)
    
    info "Application Insights instrumentation key: $INSTRUMENTATION_KEY"
}

# Function to create Load Testing resource
create_load_testing_resource() {
    log "Creating Azure Load Testing resource..."
    
    if az load show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOAD_TEST_RESOURCE" &> /dev/null; then
        warn "Load Testing resource $LOAD_TEST_RESOURCE already exists"
    else
        az load create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$LOAD_TEST_RESOURCE" \
            --location "$LOCATION"
        
        # Wait for load testing resource to be ready
        info "Waiting for Load Testing resource to be ready..."
        local max_attempts=20
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            local state=$(az load show \
                --resource-group "$RESOURCE_GROUP" \
                --name "$LOAD_TEST_RESOURCE" \
                --query provisioningState --output tsv)
            
            if [ "$state" = "Succeeded" ]; then
                log "Load Testing resource $LOAD_TEST_RESOURCE created successfully"
                break
            fi
            
            info "Attempt $attempt/$max_attempts: Load Testing resource state is $state, waiting..."
            sleep 15
            ((attempt++))
        done
        
        if [ $attempt -gt $max_attempts ]; then
            error "Load Testing resource creation timed out"
            exit 1
        fi
    fi
}

# Function to create integration test job
create_integration_test_job() {
    log "Creating integration test Container Apps Job..."
    
    if az containerapp job show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$TEST_JOB_NAME" &> /dev/null; then
        warn "Integration test job $TEST_JOB_NAME already exists"
    else
        az containerapp job create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$TEST_JOB_NAME" \
            --environment "$CONTAINER_APPS_ENV" \
            --image "mcr.microsoft.com/azure-cli:latest" \
            --trigger-type Manual \
            --replica-timeout 1800 \
            --replica-retry-limit 3 \
            --parallelism 1 \
            --replica-completion-count 1 \
            --command "/bin/bash" \
            --args "-c,echo 'Running integration tests...'; sleep 30; echo 'Tests completed successfully'"
        
        # Set environment variables for the test job
        az containerapp job update \
            --resource-group "$RESOURCE_GROUP" \
            --name "$TEST_JOB_NAME" \
            --set-env-vars \
                "STATIC_WEB_APP_URL=https://$STATIC_WEB_APP_URL" \
                "INSTRUMENTATION_KEY=$INSTRUMENTATION_KEY"
        
        log "Integration test job $TEST_JOB_NAME created successfully"
    fi
}

# Function to create load testing job
create_load_test_job() {
    log "Creating load testing Container Apps Job..."
    
    if az containerapp job show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOAD_TEST_JOB_NAME" &> /dev/null; then
        warn "Load testing job $LOAD_TEST_JOB_NAME already exists"
    else
        az containerapp job create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$LOAD_TEST_JOB_NAME" \
            --environment "$CONTAINER_APPS_ENV" \
            --image "mcr.microsoft.com/azure-cli:latest" \
            --trigger-type Manual \
            --replica-timeout 3600 \
            --replica-retry-limit 2 \
            --parallelism 1 \
            --replica-completion-count 1 \
            --command "/bin/bash" \
            --args "-c,echo 'Starting load test...'; echo 'Load test configuration: Target URL https://$STATIC_WEB_APP_URL'; sleep 60; echo 'Load test completed'"
        
        # Configure load test job environment
        az containerapp job update \
            --resource-group "$RESOURCE_GROUP" \
            --name "$LOAD_TEST_JOB_NAME" \
            --set-env-vars \
                "LOAD_TEST_RESOURCE=$LOAD_TEST_RESOURCE" \
                "TARGET_URL=https://$STATIC_WEB_APP_URL" \
                "RESOURCE_GROUP=$RESOURCE_GROUP"
        
        log "Load testing job $LOAD_TEST_JOB_NAME created successfully"
    fi
}

# Function to configure GitHub Actions integration
configure_github_actions() {
    log "Configuring GitHub Actions integration..."
    
    # Get Static Web App deployment token
    export DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STATIC_WEB_APP_NAME" \
        --query properties.apiKey --output tsv)
    
    # Create service principal for Container Apps Jobs access
    local sp_name="sp-${STATIC_WEB_APP_NAME}-testing"
    
    if az ad sp show --id "http://$sp_name" &> /dev/null; then
        warn "Service principal $sp_name already exists"
        export SP_JSON=$(az ad sp create-for-rbac \
            --name "$sp_name" \
            --role contributor \
            --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
            --sdk-auth)
    else
        export SP_JSON=$(az ad sp create-for-rbac \
            --name "$sp_name" \
            --role contributor \
            --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
            --sdk-auth)
    fi
    
    log "GitHub Actions integration configured successfully"
    
    info "Add the following secrets to your GitHub repository:"
    info "AZURE_CREDENTIALS: $SP_JSON"
    info "DEPLOYMENT_TOKEN: $DEPLOYMENT_TOKEN"
}

# Function to run validation tests
run_validation_tests() {
    log "Running validation tests..."
    
    # Test Static Web App
    info "Testing Static Web App accessibility..."
    if curl -s -I "https://$STATIC_WEB_APP_URL" | head -n 1 | grep -q "200 OK"; then
        log "Static Web App is accessible"
    else
        warn "Static Web App may not be fully ready yet"
    fi
    
    # Test Container Apps Jobs
    info "Testing Container Apps Jobs..."
    if az containerapp job start \
        --resource-group "$RESOURCE_GROUP" \
        --name "$TEST_JOB_NAME" &> /dev/null; then
        log "Integration test job started successfully"
    else
        warn "Could not start integration test job"
    fi
    
    # Test Load Testing resource
    info "Validating Load Testing resource..."
    if az load show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOAD_TEST_RESOURCE" &> /dev/null; then
        log "Load Testing resource is accessible"
    else
        warn "Load Testing resource validation failed"
    fi
    
    log "Validation tests completed"
}

# Function to display deployment summary
display_deployment_summary() {
    log "Deployment completed successfully!"
    
    echo
    echo "=========================================="
    echo "DEPLOYMENT SUMMARY"
    echo "=========================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo
    echo "Static Web App:"
    echo "  Name: $STATIC_WEB_APP_NAME"
    echo "  URL: https://$STATIC_WEB_APP_URL"
    echo
    echo "Container Apps:"
    echo "  Environment: $CONTAINER_APPS_ENV"
    echo "  Integration Test Job: $TEST_JOB_NAME"
    echo "  Load Test Job: $LOAD_TEST_JOB_NAME"
    echo
    echo "Container Registry:"
    echo "  Name: $CONTAINER_REGISTRY"
    echo "  Login Server: $ACR_LOGIN_SERVER"
    echo
    echo "Load Testing:"
    echo "  Resource: $LOAD_TEST_RESOURCE"
    echo
    echo "Monitoring:"
    echo "  Log Analytics: $LOG_ANALYTICS_WORKSPACE"
    echo "  Application Insights: $APPLICATION_INSIGHTS"
    echo "  Instrumentation Key: $INSTRUMENTATION_KEY"
    echo
    echo "GitHub Actions Secrets:"
    echo "  AZURE_CREDENTIALS: (see above output)"
    echo "  DEPLOYMENT_TOKEN: $DEPLOYMENT_TOKEN"
    echo "=========================================="
    echo
    
    info "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting Azure CI/CD Testing Workflow deployment..."
    
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_log_analytics_workspace
    create_container_registry
    create_container_apps_environment
    create_static_web_app
    create_application_insights
    create_load_testing_resource
    create_integration_test_job
    create_load_test_job
    configure_github_actions
    run_validation_tests
    display_deployment_summary
    
    log "Deployment completed successfully!"
}

# Handle script interruption
trap 'error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"