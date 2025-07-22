#!/bin/bash

# Deployment script for Event-Driven Microservices Choreography with Azure Service Bus Premium
# This script deploys the complete microservices architecture with observability

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=${DRY_RUN:-false}

# Function to log messages
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Function to log info messages
log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

# Function to log success messages
log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

# Function to log warning messages
log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

# Function to log error messages
log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    az_version=$(az version --output tsv --query '"azure-cli"')
    log_info "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some features may not work properly."
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        log_warning "openssl is not installed. Using alternative random string generation."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
set_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    export RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-microservices-choreography"}
    export LOCATION=${LOCATION:-"eastus"}
    export SUBSCRIPTION_ID=${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}
    
    # Generate unique suffix for resource names
    if command -v openssl &> /dev/null; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    else
        RANDOM_SUFFIX=$(date +%s | tail -c 7)
    fi
    
    export NAMESPACE_NAME=${NAMESPACE_NAME:-"sb-choreography-${RANDOM_SUFFIX}"}
    export WORKSPACE_NAME=${WORKSPACE_NAME:-"log-choreography-${RANDOM_SUFFIX}"}
    export APPINSIGHTS_NAME=${APPINSIGHTS_NAME:-"ai-choreography-${RANDOM_SUFFIX}"}
    export CONTAINER_ENV_NAME=${CONTAINER_ENV_NAME:-"cae-choreography-${RANDOM_SUFFIX}"}
    export STORAGE_ACCOUNT=${STORAGE_ACCOUNT:-"stfunc${RANDOM_SUFFIX}"}
    export PAYMENT_FUNCTION_NAME=${PAYMENT_FUNCTION_NAME:-"payment-service-${RANDOM_SUFFIX}"}
    export SHIPPING_FUNCTION_NAME=${SHIPPING_FUNCTION_NAME:-"shipping-service-${RANDOM_SUFFIX}"}
    
    # Log environment variables
    log_info "Environment variables set:"
    log_info "  RESOURCE_GROUP: $RESOURCE_GROUP"
    log_info "  LOCATION: $LOCATION"
    log_info "  SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
    log_info "  NAMESPACE_NAME: $NAMESPACE_NAME"
    log_info "  WORKSPACE_NAME: $WORKSPACE_NAME"
    log_info "  APPINSIGHTS_NAME: $APPINSIGHTS_NAME"
    log_info "  CONTAINER_ENV_NAME: $CONTAINER_ENV_NAME"
    log_info "  STORAGE_ACCOUNT: $STORAGE_ACCOUNT"
    log_info "  PAYMENT_FUNCTION_NAME: $PAYMENT_FUNCTION_NAME"
    log_info "  SHIPPING_FUNCTION_NAME: $SHIPPING_FUNCTION_NAME"
    
    # Save environment variables to file for destroy script
    cat > "${SCRIPT_DIR}/.env" << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
NAMESPACE_NAME=$NAMESPACE_NAME
WORKSPACE_NAME=$WORKSPACE_NAME
APPINSIGHTS_NAME=$APPINSIGHTS_NAME
CONTAINER_ENV_NAME=$CONTAINER_ENV_NAME
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
PAYMENT_FUNCTION_NAME=$PAYMENT_FUNCTION_NAME
SHIPPING_FUNCTION_NAME=$SHIPPING_FUNCTION_NAME
EOF
    
    log_success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create resource group: $RESOURCE_GROUP"
        return
    fi
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=microservices-choreography environment=demo
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create Log Analytics workspace
create_log_analytics() {
    log_info "Creating Log Analytics workspace..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Log Analytics workspace: $WORKSPACE_NAME"
        return
    fi
    
    # Check if workspace already exists
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" &> /dev/null; then
        log_warning "Log Analytics workspace $WORKSPACE_NAME already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$WORKSPACE_NAME" \
            --location "$LOCATION" \
            --sku PerGB2018
        
        log_success "Log Analytics workspace created: $WORKSPACE_NAME"
    fi
    
    # Get workspace ID for later use
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --query id --output tsv)
    
    log_info "Workspace ID: $WORKSPACE_ID"
}

# Function to create Service Bus Premium namespace
create_service_bus() {
    log_info "Creating Service Bus Premium namespace..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Service Bus namespace: $NAMESPACE_NAME"
        return
    fi
    
    # Check if namespace already exists
    if az servicebus namespace show --name "$NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Service Bus namespace $NAMESPACE_NAME already exists"
    else
        az servicebus namespace create \
            --name "$NAMESPACE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Premium \
            --capacity 1
        
        log_success "Service Bus Premium namespace created: $NAMESPACE_NAME"
    fi
    
    # Get Service Bus connection string
    export SERVICE_BUS_CONNECTION=$(az servicebus namespace authorization-rule keys list \
        --resource-group "$RESOURCE_GROUP" \
        --namespace-name "$NAMESPACE_NAME" \
        --name RootManageSharedAccessKey \
        --query primaryConnectionString --output tsv)
    
    log_info "Service Bus connection string obtained"
}

# Function to create Service Bus topics and subscriptions
create_service_bus_topics() {
    log_info "Creating Service Bus topics and subscriptions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Service Bus topics and subscriptions"
        return
    fi
    
    # Array of topics to create
    topics=("order-events" "payment-events" "inventory-events" "shipping-events")
    
    for topic in "${topics[@]}"; do
        if az servicebus topic show --name "$topic" --namespace-name "$NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log_warning "Topic $topic already exists"
        else
            az servicebus topic create \
                --name "$topic" \
                --namespace-name "$NAMESPACE_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --max-message-size-in-kilobytes 1024
            
            log_success "Topic created: $topic"
        fi
    done
    
    # Create subscriptions for choreography pattern
    subscriptions=(
        "payment-service-sub:order-events"
        "inventory-service-sub:order-events"
        "shipping-service-sub:payment-events"
        "high-priority-orders:order-events"
    )
    
    for sub_topic in "${subscriptions[@]}"; do
        IFS=':' read -r sub_name topic_name <<< "$sub_topic"
        
        if az servicebus topic subscription show --name "$sub_name" --topic-name "$topic_name" --namespace-name "$NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log_warning "Subscription $sub_name already exists"
        else
            az servicebus topic subscription create \
                --name "$sub_name" \
                --topic-name "$topic_name" \
                --namespace-name "$NAMESPACE_NAME" \
                --resource-group "$RESOURCE_GROUP"
            
            log_success "Subscription created: $sub_name for topic $topic_name"
        fi
    done
    
    # Create SQL filter for high-priority orders
    if ! az servicebus topic subscription rule show --name "HighPriorityRule" --subscription-name "high-priority-orders" --topic-name "order-events" --namespace-name "$NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az servicebus topic subscription rule create \
            --name HighPriorityRule \
            --subscription-name high-priority-orders \
            --topic-name order-events \
            --namespace-name "$NAMESPACE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --filter-type SqlFilter \
            --filter-sql-expression "Priority = 'High'"
        
        log_success "SQL filter created for high-priority orders"
    fi
    
    # Create dead letter queue
    if az servicebus queue show --name "failed-events-dlq" --namespace-name "$NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Dead letter queue already exists"
    else
        az servicebus queue create \
            --name failed-events-dlq \
            --namespace-name "$NAMESPACE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --enable-dead-lettering-on-message-expiration true \
            --max-delivery-count 3
        
        log_success "Dead letter queue created"
    fi
}

# Function to create Application Insights
create_application_insights() {
    log_info "Creating Application Insights..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Application Insights: $APPINSIGHTS_NAME"
        return
    fi
    
    # Check if Application Insights already exists
    if az monitor app-insights component show --app "$APPINSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Application Insights $APPINSIGHTS_NAME already exists"
    else
        az monitor app-insights component create \
            --app "$APPINSIGHTS_NAME" \
            --location "$LOCATION" \
            --resource-group "$RESOURCE_GROUP" \
            --workspace "$WORKSPACE_ID" \
            --kind web \
            --application-type web
        
        log_success "Application Insights created: $APPINSIGHTS_NAME"
    fi
    
    # Get Application Insights connection string and instrumentation key
    export APPINSIGHTS_CONNECTION=$(az monitor app-insights component show \
        --app "$APPINSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    export APPINSIGHTS_KEY=$(az monitor app-insights component show \
        --app "$APPINSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query instrumentationKey --output tsv)
    
    log_info "Application Insights connection string and key obtained"
}

# Function to create Container Apps Environment
create_container_apps_env() {
    log_info "Creating Container Apps Environment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Container Apps Environment: $CONTAINER_ENV_NAME"
        return
    fi
    
    # Check if Container Apps Environment already exists
    if az containerapp env show --name "$CONTAINER_ENV_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Container Apps Environment $CONTAINER_ENV_NAME already exists"
    else
        az containerapp env create \
            --name "$CONTAINER_ENV_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --logs-workspace-id "$WORKSPACE_ID"
        
        log_success "Container Apps Environment created: $CONTAINER_ENV_NAME"
    fi
    
    # Get Container Apps Environment ID
    export CONTAINER_ENV_ID=$(az containerapp env show \
        --name "$CONTAINER_ENV_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv)
    
    log_info "Container Apps Environment ID: $CONTAINER_ENV_ID"
}

# Function to deploy Container Apps
deploy_container_apps() {
    log_info "Deploying Container Apps..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy Order Service and Inventory Service"
        return
    fi
    
    # Deploy Order Service
    if az containerapp show --name "order-service" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Order Service already exists"
    else
        az containerapp create \
            --name order-service \
            --resource-group "$RESOURCE_GROUP" \
            --environment "$CONTAINER_ENV_NAME" \
            --image mcr.microsoft.com/azuredocs/containerapps-helloworld:latest \
            --target-port 80 \
            --ingress external \
            --min-replicas 1 \
            --max-replicas 10 \
            --cpu 0.25 \
            --memory 0.5Gi \
            --env-vars \
                "SERVICE_BUS_CONNECTION=$SERVICE_BUS_CONNECTION" \
                "APPINSIGHTS_CONNECTION=$APPINSIGHTS_CONNECTION" \
                "SERVICE_NAME=order-service"
        
        log_success "Order Service deployed"
    fi
    
    # Deploy Inventory Service
    if az containerapp show --name "inventory-service" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Inventory Service already exists"
    else
        az containerapp create \
            --name inventory-service \
            --resource-group "$RESOURCE_GROUP" \
            --environment "$CONTAINER_ENV_NAME" \
            --image mcr.microsoft.com/azuredocs/containerapps-helloworld:latest \
            --target-port 80 \
            --ingress internal \
            --min-replicas 1 \
            --max-replicas 5 \
            --cpu 0.25 \
            --memory 0.5Gi \
            --env-vars \
                "SERVICE_BUS_CONNECTION=$SERVICE_BUS_CONNECTION" \
                "APPINSIGHTS_CONNECTION=$APPINSIGHTS_CONNECTION" \
                "SERVICE_NAME=inventory-service"
        
        log_success "Inventory Service deployed"
    fi
    
    # Get Order Service URL
    export ORDER_SERVICE_URL=$(az containerapp show \
        --name order-service \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.configuration.ingress.fqdn \
        --output tsv)
    
    log_info "Order Service URL: https://$ORDER_SERVICE_URL"
}

# Function to create storage account for Function Apps
create_storage_account() {
    log_info "Creating storage account for Function Apps..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create storage account: $STORAGE_ACCOUNT"
        return
    fi
    
    # Check if storage account already exists
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Storage account $STORAGE_ACCOUNT already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS
        
        log_success "Storage account created: $STORAGE_ACCOUNT"
    fi
}

# Function to deploy Function Apps
deploy_function_apps() {
    log_info "Deploying Function Apps..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy Payment Service and Shipping Service Function Apps"
        return
    fi
    
    # Deploy Payment Service Function App
    if az functionapp show --name "$PAYMENT_FUNCTION_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Payment Service Function App already exists"
    else
        az functionapp create \
            --name "$PAYMENT_FUNCTION_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --consumption-plan-location "$LOCATION" \
            --storage-account "$STORAGE_ACCOUNT" \
            --runtime node \
            --functions-version 4 \
            --app-insights "$APPINSIGHTS_NAME"
        
        log_success "Payment Service Function App created"
        
        # Configure Function App settings
        az functionapp config appsettings set \
            --name "$PAYMENT_FUNCTION_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --settings \
                "SERVICE_BUS_CONNECTION=$SERVICE_BUS_CONNECTION" \
                "APPINSIGHTS_CONNECTION=$APPINSIGHTS_CONNECTION"
        
        log_success "Payment Service Function App configured"
    fi
    
    # Deploy Shipping Service Function App
    if az functionapp show --name "$SHIPPING_FUNCTION_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Shipping Service Function App already exists"
    else
        az functionapp create \
            --name "$SHIPPING_FUNCTION_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --consumption-plan-location "$LOCATION" \
            --storage-account "$STORAGE_ACCOUNT" \
            --runtime node \
            --functions-version 4 \
            --app-insights "$APPINSIGHTS_NAME"
        
        log_success "Shipping Service Function App created"
        
        # Configure Function App settings
        az functionapp config appsettings set \
            --name "$SHIPPING_FUNCTION_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --settings \
                "SERVICE_BUS_CONNECTION=$SERVICE_BUS_CONNECTION" \
                "APPINSIGHTS_CONNECTION=$APPINSIGHTS_CONNECTION"
        
        log_success "Shipping Service Function App configured"
    fi
}

# Function to create Azure Monitor Workbook
create_workbook() {
    log_info "Creating Azure Monitor Workbook..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Azure Monitor Workbook"
        return
    fi
    
    # Create workbook template directory
    mkdir -p "${SCRIPT_DIR}/workbook-templates"
    
    # Create workbook template JSON
    cat > "${SCRIPT_DIR}/workbook-templates/choreography-workbook.json" << 'EOF'
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 1,
      "content": {
        "json": "# Microservices Choreography Dashboard\n\nThis workbook provides comprehensive observability for event-driven microservices choreography patterns using Azure Service Bus Premium and distributed tracing."
      },
      "name": "title"
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "requests\n| where cloud_RoleName in ('order-service', 'inventory-service', 'payment-service', 'shipping-service')\n| summarize RequestCount = count() by bin(timestamp, 5m), cloud_RoleName\n| render timechart",
        "size": 0,
        "title": "Request Volume by Service"
      },
      "name": "requestVolume"
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "dependencies\n| where type == 'Azure Service Bus'\n| summarize MessageCount = count() by bin(timestamp, 5m), cloud_RoleName\n| render timechart",
        "size": 0,
        "title": "Service Bus Messages by Service"
      },
      "name": "serviceBusMessages"
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "requests\n| where cloud_RoleName in ('order-service', 'inventory-service', 'payment-service', 'shipping-service')\n| summarize AvgDuration = avg(duration) by cloud_RoleName\n| render barchart",
        "size": 0,
        "title": "Average Response Time by Service"
      },
      "name": "responseTime"
    }
  ]
}
EOF
    
    # Create the workbook
    az monitor workbook create \
        --resource-group "$RESOURCE_GROUP" \
        --name "Microservices Choreography Dashboard" \
        --display-name "Microservices Choreography Dashboard" \
        --source-id "$WORKSPACE_ID" \
        --category "microservices" \
        --serialized-data @"${SCRIPT_DIR}/workbook-templates/choreography-workbook.json"
    
    log_success "Azure Monitor Workbook created"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment"
        return
    fi
    
    # Check Service Bus namespace
    if az servicebus namespace show --name "$NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP" --query "status" --output tsv | grep -q "Active"; then
        log_success "Service Bus namespace is active"
    else
        log_error "Service Bus namespace is not active"
    fi
    
    # Check Container Apps
    container_apps=("order-service" "inventory-service")
    for app in "${container_apps[@]}"; do
        if az containerapp show --name "$app" --resource-group "$RESOURCE_GROUP" --query "properties.runningStatus" --output tsv | grep -q "Running"; then
            log_success "Container App $app is running"
        else
            log_warning "Container App $app is not running"
        fi
    done
    
    # Check Function Apps
    function_apps=("$PAYMENT_FUNCTION_NAME" "$SHIPPING_FUNCTION_NAME")
    for app in "${function_apps[@]}"; do
        if az functionapp show --name "$app" --resource-group "$RESOURCE_GROUP" --query "state" --output tsv | grep -q "Running"; then
            log_success "Function App $app is running"
        else
            log_warning "Function App $app is not running"
        fi
    done
    
    # Check Application Insights
    if az monitor app-insights component show --app "$APPINSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" --query "appId" --output tsv &> /dev/null; then
        log_success "Application Insights is configured"
    else
        log_warning "Application Insights is not properly configured"
    fi
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    log_info "=================="
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Service Bus Namespace: $NAMESPACE_NAME"
    log_info "Log Analytics Workspace: $WORKSPACE_NAME"
    log_info "Application Insights: $APPINSIGHTS_NAME"
    log_info "Container Apps Environment: $CONTAINER_ENV_NAME"
    log_info "Storage Account: $STORAGE_ACCOUNT"
    log_info "Payment Function App: $PAYMENT_FUNCTION_NAME"
    log_info "Shipping Function App: $SHIPPING_FUNCTION_NAME"
    
    if [[ -n "${ORDER_SERVICE_URL:-}" ]]; then
        log_info "Order Service URL: https://$ORDER_SERVICE_URL"
    fi
    
    log_info ""
    log_info "Next Steps:"
    log_info "1. Navigate to the Azure Portal to view your resources"
    log_info "2. Check the Azure Monitor Workbook for observability insights"
    log_info "3. Test the choreography workflow by sending messages to the Order Service"
    log_info ""
    log_info "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log_info "Starting deployment of Event-Driven Microservices Choreography..."
    
    # Initialize log file
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    # Check if this is a dry run
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY RUN mode - no resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites
    set_environment
    create_resource_group
    create_log_analytics
    create_service_bus
    create_service_bus_topics
    create_application_insights
    create_container_apps_env
    deploy_container_apps
    create_storage_account
    deploy_function_apps
    create_workbook
    
    # Validate deployment
    validate_deployment
    
    # Display summary
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Handle script interruption
trap 'log_error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"