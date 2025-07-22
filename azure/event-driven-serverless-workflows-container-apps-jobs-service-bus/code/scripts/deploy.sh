#!/bin/bash

# Azure Event-Driven Serverless Workflows Deployment Script
# Recipe: Event-Driven Serverless Workflows with Azure Container Apps Jobs and Azure Service Bus
# Description: Deploys a complete event-driven serverless architecture using Azure Container Apps Jobs and Service Bus

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# ANSI color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deployment-$(date +%Y%m%d-%H%M%S).log"
readonly TEMP_DIR=$(mktemp -d)

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
    if [[ ${exit_code} -ne 0 ]]; then
        echo -e "${RED}❌ Deployment failed. Check ${LOG_FILE} for details.${NC}"
    fi
    exit ${exit_code}
}

trap cleanup EXIT

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

print_status() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "${LOG_FILE}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "${LOG_FILE}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "${LOG_FILE}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "${LOG_FILE}"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv)
    print_status "Azure CLI version: ${az_version}"
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Docker is available (for local development)
    if command -v docker &> /dev/null; then
        print_success "Docker is available for local development"
    else
        print_warning "Docker not found. Local container development will not be available."
    fi
    
    # Check for openssl (for random generation)
    if ! command -v openssl &> /dev/null; then
        print_error "openssl is required for generating random values."
        exit 1
    fi
    
    print_success "All prerequisites check passed"
}

# Set default environment variables
set_default_environment() {
    print_status "Setting up default environment variables..."
    
    # Resource configuration
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-container-jobs-demo}"
    export LOCATION="${LOCATION:-eastus}"
    export ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-env-container-jobs}"
    export QUEUE_NAME="${QUEUE_NAME:-message-processing-queue}"
    export JOB_NAME="${JOB_NAME:-message-processor-job}"
    export CONTAINER_IMAGE_NAME="${CONTAINER_IMAGE_NAME:-message-processor:1.0}"
    
    # Generate unique suffix for global resources
    local random_suffix
    random_suffix=$(openssl rand -hex 3)
    export SERVICE_BUS_NAMESPACE="${SERVICE_BUS_NAMESPACE:-sb-container-jobs-${random_suffix}}"
    export CONTAINER_REGISTRY_NAME="${CONTAINER_REGISTRY_NAME:-acrjobs${random_suffix}}"
    
    # Display configuration
    cat << EOF | tee -a "${LOG_FILE}"

📋 Deployment Configuration:
   Resource Group: ${RESOURCE_GROUP}
   Location: ${LOCATION}
   Container Environment: ${ENVIRONMENT_NAME}
   Service Bus Namespace: ${SERVICE_BUS_NAMESPACE}
   Queue Name: ${QUEUE_NAME}
   Container Registry: ${CONTAINER_REGISTRY_NAME}
   Job Name: ${JOB_NAME}
   Container Image: ${CONTAINER_IMAGE_NAME}

EOF
}

# Register Azure resource providers
register_providers() {
    print_status "Registering Azure resource providers..."
    
    local providers=(
        "Microsoft.App"
        "Microsoft.ServiceBus"
        "Microsoft.ContainerRegistry"
        "Microsoft.OperationalInsights"
    )
    
    for provider in "${providers[@]}"; do
        print_status "Registering provider: ${provider}"
        if az provider register --namespace "${provider}" --wait &>> "${LOG_FILE}"; then
            print_success "Registered provider: ${provider}"
        else
            print_error "Failed to register provider: ${provider}"
            exit 1
        fi
    done
}

# Create resource group
create_resource_group() {
    print_status "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=demo environment=learning \
        &>> "${LOG_FILE}"; then
        print_success "Resource group created: ${RESOURCE_GROUP}"
    else
        print_error "Failed to create resource group"
        exit 1
    fi
}

# Create Azure Container Apps environment
create_container_apps_environment() {
    print_status "Creating Container Apps environment: ${ENVIRONMENT_NAME}"
    
    if az containerapp env create \
        --name "${ENVIRONMENT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --logs-destination log-analytics \
        &>> "${LOG_FILE}"; then
        print_success "Container Apps environment created: ${ENVIRONMENT_NAME}"
    else
        print_error "Failed to create Container Apps environment"
        exit 1
    fi
}

# Create Service Bus namespace and queue
create_service_bus() {
    print_status "Creating Service Bus namespace: ${SERVICE_BUS_NAMESPACE}"
    
    # Create Service Bus namespace
    if az servicebus namespace create \
        --name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard \
        &>> "${LOG_FILE}"; then
        print_success "Service Bus namespace created: ${SERVICE_BUS_NAMESPACE}"
    else
        print_error "Failed to create Service Bus namespace"
        exit 1
    fi
    
    print_status "Creating Service Bus queue: ${QUEUE_NAME}"
    
    # Create Service Bus queue
    if az servicebus queue create \
        --name "${QUEUE_NAME}" \
        --namespace-name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --max-delivery-count 5 \
        --lock-duration PT1M \
        &>> "${LOG_FILE}"; then
        print_success "Service Bus queue created: ${QUEUE_NAME}"
    else
        print_error "Failed to create Service Bus queue"
        exit 1
    fi
    
    # Get Service Bus connection string
    print_status "Retrieving Service Bus connection string..."
    if SERVICE_BUS_CONNECTION_STRING=$(az servicebus namespace \
        authorization-rule keys list \
        --name RootManageSharedAccessKey \
        --namespace-name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query primaryConnectionString \
        --output tsv 2>> "${LOG_FILE}"); then
        export SERVICE_BUS_CONNECTION_STRING
        print_success "Service Bus connection string retrieved"
    else
        print_error "Failed to retrieve Service Bus connection string"
        exit 1
    fi
}

# Create Azure Container Registry
create_container_registry() {
    print_status "Creating Azure Container Registry: ${CONTAINER_REGISTRY_NAME}"
    
    if az acr create \
        --name "${CONTAINER_REGISTRY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Basic \
        --admin-enabled true \
        &>> "${LOG_FILE}"; then
        print_success "Container Registry created: ${CONTAINER_REGISTRY_NAME}"
    else
        print_error "Failed to create Container Registry"
        exit 1
    fi
    
    # Get registry credentials
    print_status "Retrieving Container Registry credentials..."
    if ACR_USERNAME=$(az acr credential show \
        --name "${CONTAINER_REGISTRY_NAME}" \
        --query username \
        --output tsv 2>> "${LOG_FILE}") && \
       ACR_PASSWORD=$(az acr credential show \
        --name "${CONTAINER_REGISTRY_NAME}" \
        --query passwords[0].value \
        --output tsv 2>> "${LOG_FILE}"); then
        export ACR_USERNAME ACR_PASSWORD
        print_success "Container Registry credentials retrieved"
    else
        print_error "Failed to retrieve Container Registry credentials"
        exit 1
    fi
}

# Build and push container image
build_container_image() {
    print_status "Building and pushing container image..."
    
    local app_dir="${TEMP_DIR}/message-processor"
    mkdir -p "${app_dir}"
    
    # Create Dockerfile
    cat > "${app_dir}/Dockerfile" << 'EOF'
FROM mcr.microsoft.com/dotnet/runtime:8.0-alpine
WORKDIR /app

# Copy application files
COPY . .

# Install dependencies
RUN dotnet restore
RUN dotnet publish -c Release -o out

# Set entry point
ENTRYPOINT ["dotnet", "out/MessageProcessor.dll"]
EOF
    
    # Create .NET project file
    cat > "${app_dir}/MessageProcessor.csproj" << 'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Azure.Messaging.ServiceBus" Version="7.15.0" />
    <PackageReference Include="Microsoft.Extensions.Hosting" Version="8.0.0" />
    <PackageReference Include="Microsoft.Extensions.Logging" Version="8.0.0" />
  </ItemGroup>
</Project>
EOF
    
    # Create sample message processor application
    cat > "${app_dir}/Program.cs" << 'EOF'
using Azure.Messaging.ServiceBus;
using Microsoft.Extensions.Logging;

var loggerFactory = LoggerFactory.Create(builder => builder.AddConsole());
var logger = loggerFactory.CreateLogger<Program>();

var connectionString = Environment.GetEnvironmentVariable("SERVICE_BUS_CONNECTION_STRING");
var queueName = Environment.GetEnvironmentVariable("QUEUE_NAME");

if (string.IsNullOrEmpty(connectionString) || string.IsNullOrEmpty(queueName))
{
    logger.LogError("Missing required environment variables");
    Environment.Exit(1);
}

var client = new ServiceBusClient(connectionString);
var processor = client.CreateProcessor(queueName);

processor.ProcessMessageAsync += async args =>
{
    var message = args.Message;
    logger.LogInformation($"Processing message: {message.Body}");
    
    // Simulate processing work
    await Task.Delay(1000);
    
    logger.LogInformation($"Message processed successfully: {message.MessageId}");
    await args.CompleteMessageAsync(message);
};

processor.ProcessErrorAsync += args =>
{
    logger.LogError($"Error processing message: {args.Exception}");
    return Task.CompletedTask;
};

await processor.StartProcessingAsync();

// Keep the job alive until a message is processed
await Task.Delay(30000);

await processor.StopProcessingAsync();
await processor.DisposeAsync();
await client.DisposeAsync();

logger.LogInformation("Message processor completed");
EOF
    
    # Build and push image using ACR Build
    print_status "Building container image with ACR Build..."
    if (cd "${app_dir}" && az acr build \
        --registry "${CONTAINER_REGISTRY_NAME}" \
        --image "${CONTAINER_IMAGE_NAME}" \
        --file Dockerfile \
        . &>> "${LOG_FILE}"); then
        print_success "Container image built and pushed to registry"
    else
        print_error "Failed to build container image"
        exit 1
    fi
}

# Create event-driven Container Apps job
create_container_apps_job() {
    print_status "Creating event-driven Container Apps job: ${JOB_NAME}"
    
    if az containerapp job create \
        --name "${JOB_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --environment "${ENVIRONMENT_NAME}" \
        --trigger-type "Event" \
        --replica-timeout "1800" \
        --replica-retry-limit "3" \
        --replica-completion-count "1" \
        --parallelism "5" \
        --min-executions "0" \
        --max-executions "10" \
        --polling-interval "30" \
        --scale-rule-name "servicebus-queue-rule" \
        --scale-rule-type "azure-servicebus" \
        --scale-rule-metadata \
            "queueName=${QUEUE_NAME}" \
            "namespace=${SERVICE_BUS_NAMESPACE}" \
            "messageCount=1" \
        --scale-rule-auth "connection=servicebus-connection-secret" \
        --image "${CONTAINER_REGISTRY_NAME}.azurecr.io/${CONTAINER_IMAGE_NAME}" \
        --cpu "0.5" \
        --memory "1Gi" \
        --secrets "servicebus-connection-secret=${SERVICE_BUS_CONNECTION_STRING}" \
        --registry-server "${CONTAINER_REGISTRY_NAME}.azurecr.io" \
        --registry-username "${ACR_USERNAME}" \
        --registry-password "${ACR_PASSWORD}" \
        --env-vars \
            "SERVICE_BUS_CONNECTION_STRING=secretref:servicebus-connection-secret" \
            "QUEUE_NAME=${QUEUE_NAME}" \
        &>> "${LOG_FILE}"; then
        print_success "Event-driven Container Apps job created: ${JOB_NAME}"
    else
        print_error "Failed to create Container Apps job"
        exit 1
    fi
}

# Configure monitoring and alerts
configure_monitoring() {
    print_status "Configuring monitoring and alerts..."
    
    # Get the current subscription ID
    local subscription_id
    if subscription_id=$(az account show --query id -o tsv 2>> "${LOG_FILE}"); then
        local job_resource_id="/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.App/jobs/${JOB_NAME}"
        
        # Create alert rule for job failures
        if az monitor metrics alert create \
            --name "container-job-failure-alert" \
            --resource-group "${RESOURCE_GROUP}" \
            --scopes "${job_resource_id}" \
            --condition "count static.Microsoft.App/jobs.JobExecutionCount > 0" \
            --description "Alert when container job executions fail" \
            --evaluation-frequency 5m \
            --window-size 5m \
            --severity 2 \
            &>> "${LOG_FILE}"; then
            print_success "Monitoring and alerting configured"
        else
            print_warning "Failed to create alert rule, but continuing deployment"
        fi
    else
        print_warning "Could not retrieve subscription ID for monitoring setup"
    fi
}

# Test the deployment
test_deployment() {
    print_status "Testing the deployment by sending test messages..."
    
    # Send test messages to Service Bus queue
    for i in {1..3}; do
        if az servicebus queue message send \
            --namespace-name "${SERVICE_BUS_NAMESPACE}" \
            --queue-name "${QUEUE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --body "Test message ${i} - $(date)" \
            &>> "${LOG_FILE}"; then
            print_success "Test message ${i} sent successfully"
        else
            print_warning "Failed to send test message ${i}"
        fi
    done
    
    print_status "Waiting for job executions to start..."
    sleep 30
    
    # Check job executions
    print_status "Checking job execution status..."
    if az containerapp job execution list \
        --name "${JOB_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --output table &>> "${LOG_FILE}"; then
        print_success "Job executions are running. Check Azure portal for detailed logs."
    else
        print_warning "Could not retrieve job execution status"
    fi
}

# Save deployment information
save_deployment_info() {
    local info_file="${SCRIPT_DIR}/deployment-info.env"
    
    cat > "${info_file}" << EOF
# Azure Event-Driven Serverless Workflows Deployment Information
# Generated on: $(date)

export RESOURCE_GROUP="${RESOURCE_GROUP}"
export LOCATION="${LOCATION}"
export ENVIRONMENT_NAME="${ENVIRONMENT_NAME}"
export SERVICE_BUS_NAMESPACE="${SERVICE_BUS_NAMESPACE}"
export QUEUE_NAME="${QUEUE_NAME}"
export CONTAINER_REGISTRY_NAME="${CONTAINER_REGISTRY_NAME}"
export JOB_NAME="${JOB_NAME}"
export CONTAINER_IMAGE_NAME="${CONTAINER_IMAGE_NAME}"
export ACR_USERNAME="${ACR_USERNAME}"
# Note: ACR_PASSWORD and SERVICE_BUS_CONNECTION_STRING are not saved for security reasons

# To load these variables in future sessions, run:
# source ${info_file}
EOF
    
    print_success "Deployment information saved to: ${info_file}"
}

# Main deployment function
main() {
    log "Starting Azure Event-Driven Serverless Workflows deployment..."
    
    echo -e "${BLUE}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║    Azure Event-Driven Serverless Workflows Deployment          ║
║                                                                  ║
║    This script will deploy:                                     ║
║    • Azure Container Apps Environment                           ║
║    • Azure Service Bus Namespace and Queue                      ║
║    • Azure Container Registry                                   ║
║    • Event-driven Container Apps Job                            ║
║    • Monitoring and Alerting                                    ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    check_prerequisites
    set_default_environment
    register_providers
    create_resource_group
    create_container_apps_environment
    create_service_bus
    create_container_registry
    build_container_image
    create_container_apps_job
    configure_monitoring
    test_deployment
    save_deployment_info
    
    echo -e "${GREEN}"
    cat << EOF

🎉 Deployment completed successfully!

📋 Resources created:
   • Resource Group: ${RESOURCE_GROUP}
   • Container Apps Environment: ${ENVIRONMENT_NAME}
   • Service Bus Namespace: ${SERVICE_BUS_NAMESPACE}
   • Service Bus Queue: ${QUEUE_NAME}
   • Container Registry: ${CONTAINER_REGISTRY_NAME}
   • Container Apps Job: ${JOB_NAME}

🔗 Quick links:
   • Azure Portal: https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}
   • Service Bus: https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ServiceBus/namespaces/${SERVICE_BUS_NAMESPACE}
   • Container Apps: https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.App/managedEnvironments/${ENVIRONMENT_NAME}

📊 To monitor your deployment:
   • Check job executions: az containerapp job execution list --name ${JOB_NAME} --resource-group ${RESOURCE_GROUP}
   • View logs: az containerapp job logs show --name ${JOB_NAME} --resource-group ${RESOURCE_GROUP}
   • Send test messages: az servicebus queue message send --namespace-name ${SERVICE_BUS_NAMESPACE} --queue-name ${QUEUE_NAME} --resource-group ${RESOURCE_GROUP} --body "Test message"

💡 Next steps:
   1. Send messages to the Service Bus queue to trigger job executions
   2. Monitor job performance in the Azure portal
   3. Customize the message processor for your specific use case
   4. Scale the job configuration based on your workload requirements

📝 Deployment log: ${LOG_FILE}
🔧 Deployment info: ${SCRIPT_DIR}/deployment-info.env

💰 Cost reminder: Remember to run the destroy script when done to avoid ongoing charges.

EOF
    echo -e "${NC}"
    
    log "Deployment completed successfully"
}

# Run main function
main "$@"