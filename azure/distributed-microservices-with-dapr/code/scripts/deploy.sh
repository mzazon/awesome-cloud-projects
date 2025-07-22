#!/bin/bash

# =============================================================================
# Azure Container Apps and Dapr Deployment Script
# =============================================================================
# This script deploys the complete distributed application patterns solution
# using Azure Container Apps with Dapr integration
# =============================================================================

set -euo pipefail

# Configuration and logging
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="deployment_$(date +%Y%m%d_%H%M%S).log"
readonly MAX_RETRIES=3
readonly RETRY_DELAY=10

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration (can be overridden via environment variables)
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-dapr-microservices}"
LOCATION="${LOCATION:-eastus}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-aca-env-dapr}"
LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-dapr-microservices}"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
    local exit_code=$1
    local line_number=$2
    log_error "Script failed at line $line_number with exit code $exit_code"
    log_error "Check $LOG_FILE for detailed error information"
    exit "$exit_code"
}

trap 'handle_error $? $LINENO' ERR

# Utility functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI v2.53.0 or later."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --output json | jq -r '."azure-cli"')
    log_info "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if required extensions are installed
    if ! az extension show --name containerapp &> /dev/null; then
        log_info "Installing Azure Container Apps extension..."
        az extension add --name containerapp --yes
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_warning "OpenSSL not found. Using alternative method for random generation."
    fi
    
    log_success "Prerequisites check completed"
}

generate_unique_suffix() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 3
    else
        # Fallback method using date and random
        echo "$(date +%s | tail -c 6)$(( RANDOM % 1000 ))" | head -c 6
    fi
}

wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    local max_wait="${4:-300}" # Default 5 minutes
    local wait_interval=30
    local elapsed=0
    
    log_info "Waiting for $resource_type '$resource_name' to be ready..."
    
    while [ $elapsed -lt $max_wait ]; do
        local status
        case "$resource_type" in
            "cosmosdb")
                status=$(az cosmosdb show --name "$resource_name" --resource-group "$resource_group" \
                    --query "provisioningState" --output tsv 2>/dev/null || echo "Unknown")
                ;;
            "servicebus")
                status=$(az servicebus namespace show --name "$resource_name" --resource-group "$resource_group" \
                    --query "provisioningState" --output tsv 2>/dev/null || echo "Unknown")
                ;;
            "containerapp-env")
                status=$(az containerapp env show --name "$resource_name" --resource-group "$resource_group" \
                    --query "properties.provisioningState" --output tsv 2>/dev/null || echo "Unknown")
                ;;
            "containerapp")
                status=$(az containerapp show --name "$resource_name" --resource-group "$resource_group" \
                    --query "properties.provisioningState" --output tsv 2>/dev/null || echo "Unknown")
                ;;
            *)
                log_warning "Unknown resource type: $resource_type"
                return 0
                ;;
        esac
        
        if [[ "$status" == "Succeeded" ]]; then
            log_success "$resource_type '$resource_name' is ready"
            return 0
        elif [[ "$status" == "Failed" ]]; then
            log_error "$resource_type '$resource_name' failed to deploy"
            return 1
        fi
        
        log_info "Status: $status. Waiting ${wait_interval}s..."
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    
    log_error "Timeout waiting for $resource_type '$resource_name' (${max_wait}s)"
    return 1
}

retry_command() {
    local command="$1"
    local description="$2"
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        log_info "Attempt $attempt/$MAX_RETRIES: $description"
        
        if eval "$command"; then
            log_success "$description completed successfully"
            return 0
        else
            log_warning "$description failed (attempt $attempt/$MAX_RETRIES)"
            if [ $attempt -lt $MAX_RETRIES ]; then
                log_info "Retrying in ${RETRY_DELAY}s..."
                sleep $RETRY_DELAY
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "$description failed after $MAX_RETRIES attempts"
    return 1
}

# Main deployment functions
setup_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Get subscription ID
    export SUBSCRIPTION_ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for globally unique names
    RANDOM_SUFFIX=$(generate_unique_suffix)
    export SERVICE_BUS_NAMESPACE="sb-dapr-${RANDOM_SUFFIX}"
    export COSMOS_ACCOUNT="cosmos-dapr-${RANDOM_SUFFIX}"
    export KEY_VAULT_NAME="kv-dapr-${RANDOM_SUFFIX}"
    
    log_info "Environment variables configured:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  Environment Name: $ENVIRONMENT_NAME"
    log_info "  Service Bus Namespace: $SERVICE_BUS_NAMESPACE"
    log_info "  Cosmos Account: $COSMOS_ACCOUNT"
    log_info "  Key Vault Name: $KEY_VAULT_NAME"
    log_info "  Subscription ID: $SUBSCRIPTION_ID"
}

create_resource_group() {
    log_info "Creating resource group..."
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=microservices-demo environment=development
        
        log_success "Resource group '$RESOURCE_GROUP' created"
    fi
}

create_log_analytics_workspace() {
    log_info "Creating Log Analytics workspace..."
    
    # Check if workspace already exists
    if az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" &> /dev/null; then
        log_warning "Log Analytics workspace '$LOG_ANALYTICS_WORKSPACE' already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --location "$LOCATION"
        
        log_success "Log Analytics workspace '$LOG_ANALYTICS_WORKSPACE' created"
    fi
    
    # Get workspace details
    export LOG_ANALYTICS_ID
    LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query id --output tsv)
    
    export LOG_ANALYTICS_KEY
    LOG_ANALYTICS_KEY=$(az monitor log-analytics workspace get-shared-keys \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query primarySharedKey --output tsv)
}

create_container_apps_environment() {
    log_info "Creating Container Apps environment..."
    
    # Check if environment already exists
    if az containerapp env show --name "$ENVIRONMENT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Container Apps environment '$ENVIRONMENT_NAME' already exists"
    else
        retry_command \
            "az containerapp env create \
                --name '$ENVIRONMENT_NAME' \
                --resource-group '$RESOURCE_GROUP' \
                --location '$LOCATION' \
                --logs-workspace-id '$LOG_ANALYTICS_ID' \
                --logs-workspace-key '$LOG_ANALYTICS_KEY'" \
            "Creating Container Apps environment"
        
        wait_for_resource "containerapp-env" "$ENVIRONMENT_NAME" "$RESOURCE_GROUP"
    fi
}

create_service_bus() {
    log_info "Creating Azure Service Bus..."
    
    # Check if namespace already exists
    if az servicebus namespace show --name "$SERVICE_BUS_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Service Bus namespace '$SERVICE_BUS_NAMESPACE' already exists"
    else
        retry_command \
            "az servicebus namespace create \
                --name '$SERVICE_BUS_NAMESPACE' \
                --resource-group '$RESOURCE_GROUP' \
                --location '$LOCATION' \
                --sku Standard" \
            "Creating Service Bus namespace"
        
        wait_for_resource "servicebus" "$SERVICE_BUS_NAMESPACE" "$RESOURCE_GROUP"
    fi
    
    # Create topic for order events
    if az servicebus topic show --name orders --namespace-name "$SERVICE_BUS_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Service Bus topic 'orders' already exists"
    else
        az servicebus topic create \
            --name orders \
            --namespace-name "$SERVICE_BUS_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP"
        
        log_success "Service Bus topic 'orders' created"
    fi
    
    # Get Service Bus connection string
    export SERVICE_BUS_CONNECTION
    SERVICE_BUS_CONNECTION=$(az servicebus namespace authorization-rule keys list \
        --name RootManageSharedAccessKey \
        --namespace-name "$SERVICE_BUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryConnectionString --output tsv)
}

create_cosmos_db() {
    log_info "Creating Azure Cosmos DB..."
    
    # Check if account already exists
    if az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Cosmos DB account '$COSMOS_ACCOUNT' already exists"
    else
        retry_command \
            "az cosmosdb create \
                --name '$COSMOS_ACCOUNT' \
                --resource-group '$RESOURCE_GROUP' \
                --locations regionName='$LOCATION' \
                --capabilities EnableServerless \
                --default-consistency-level Session" \
            "Creating Cosmos DB account"
        
        wait_for_resource "cosmosdb" "$COSMOS_ACCOUNT" "$RESOURCE_GROUP"
    fi
    
    # Create database
    if az cosmosdb sql database show \
        --account-name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --name daprstate &> /dev/null; then
        log_warning "Cosmos DB database 'daprstate' already exists"
    else
        az cosmosdb sql database create \
            --account-name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --name daprstate
        
        log_success "Cosmos DB database 'daprstate' created"
    fi
    
    # Create container
    if az cosmosdb sql container show \
        --account-name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --database-name daprstate \
        --name statestore &> /dev/null; then
        log_warning "Cosmos DB container 'statestore' already exists"
    else
        az cosmosdb sql container create \
            --account-name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --database-name daprstate \
            --name statestore \
            --partition-key-path /partitionKey
        
        log_success "Cosmos DB container 'statestore' created"
    fi
    
    # Get Cosmos DB connection details
    export COSMOS_URL
    COSMOS_URL=$(az cosmosdb show \
        --name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query documentEndpoint --output tsv)
    
    export COSMOS_KEY
    COSMOS_KEY=$(az cosmosdb keys list \
        --name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryMasterKey --output tsv)
}

create_key_vault() {
    log_info "Creating Azure Key Vault..."
    
    # Check if Key Vault already exists
    if az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Key Vault '$KEY_VAULT_NAME' already exists"
    else
        retry_command \
            "az keyvault create \
                --name '$KEY_VAULT_NAME' \
                --resource-group '$RESOURCE_GROUP' \
                --location '$LOCATION' \
                --enable-rbac-authorization false" \
            "Creating Key Vault"
    fi
    
    # Store secrets
    log_info "Storing secrets in Key Vault..."
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "servicebus-connectionstring" \
        --value "$SERVICE_BUS_CONNECTION" > /dev/null
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "cosmosdb-url" \
        --value "$COSMOS_URL" > /dev/null
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "cosmosdb-key" \
        --value "$COSMOS_KEY" > /dev/null
    
    log_success "Secrets stored in Key Vault"
}

configure_dapr_components() {
    log_info "Configuring Dapr components..."
    
    # Create temporary directory for component files
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create Service Bus pub/sub component YAML
    cat > "$temp_dir/pubsub-servicebus.yaml" <<EOF
componentType: pubsub.azure.servicebus
version: v1
metadata:
  - name: connectionString
    secretKeyRef:
      name: servicebus-connectionstring
      key: servicebus-connectionstring
secrets:
  - name: servicebus-connectionstring
    value: "${SERVICE_BUS_CONNECTION}"
scopes:
  - order-service
  - inventory-service
EOF
    
    # Deploy pub/sub component
    retry_command \
        "az containerapp env dapr-component set \
            --name '$ENVIRONMENT_NAME' \
            --resource-group '$RESOURCE_GROUP' \
            --dapr-component-name pubsub \
            --yaml '$temp_dir/pubsub-servicebus.yaml'" \
        "Deploying Service Bus pub/sub component"
    
    # Create Cosmos DB state store component YAML
    cat > "$temp_dir/statestore-cosmosdb.yaml" <<EOF
componentType: state.azure.cosmosdb
version: v1
metadata:
  - name: url
    value: "${COSMOS_URL}"
  - name: masterKey
    secretKeyRef:
      name: cosmosdb-key
      key: cosmosdb-key
  - name: database
    value: daprstate
  - name: collection
    value: statestore
secrets:
  - name: cosmosdb-key
    value: "${COSMOS_KEY}"
scopes:
  - order-service
  - inventory-service
EOF
    
    # Deploy state store component
    retry_command \
        "az containerapp env dapr-component set \
            --name '$ENVIRONMENT_NAME' \
            --resource-group '$RESOURCE_GROUP' \
            --dapr-component-name statestore \
            --yaml '$temp_dir/statestore-cosmosdb.yaml'" \
        "Deploying Cosmos DB state store component"
    
    # Cleanup temporary files
    rm -rf "$temp_dir"
    
    log_success "Dapr components configured"
}

deploy_order_service() {
    log_info "Deploying Order Service..."
    
    # Check if order service already exists
    if az containerapp show --name order-service --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Order service already exists, updating..."
        
        az containerapp update \
            --name order-service \
            --resource-group "$RESOURCE_GROUP" \
            --image mcr.microsoft.com/azuredocs/containerapps-helloworld:latest \
            --set-env-vars \
                DAPR_HTTP_PORT=3500 \
                PUBSUB_NAME=pubsub \
                TOPIC_NAME=orders \
                STATE_STORE_NAME=statestore
    else
        retry_command \
            "az containerapp create \
                --name order-service \
                --resource-group '$RESOURCE_GROUP' \
                --environment '$ENVIRONMENT_NAME' \
                --image mcr.microsoft.com/azuredocs/containerapps-helloworld:latest \
                --target-port 80 \
                --ingress external \
                --min-replicas 1 \
                --max-replicas 10 \
                --enable-dapr \
                --dapr-app-id order-service \
                --dapr-app-port 80 \
                --dapr-app-protocol http \
                --cpu 0.5 \
                --memory 1.0Gi \
                --env-vars \
                    DAPR_HTTP_PORT=3500 \
                    PUBSUB_NAME=pubsub \
                    TOPIC_NAME=orders \
                    STATE_STORE_NAME=statestore" \
            "Deploying Order Service"
        
        wait_for_resource "containerapp" "order-service" "$RESOURCE_GROUP"
    fi
    
    # Get order service URL
    export ORDER_SERVICE_URL
    ORDER_SERVICE_URL=$(az containerapp show \
        --name order-service \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.configuration.ingress.fqdn \
        --output tsv)
    
    log_success "Order Service deployed: https://$ORDER_SERVICE_URL"
}

deploy_inventory_service() {
    log_info "Deploying Inventory Service..."
    
    # Check if inventory service already exists
    if az containerapp show --name inventory-service --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Inventory service already exists, updating..."
        
        az containerapp update \
            --name inventory-service \
            --resource-group "$RESOURCE_GROUP" \
            --image mcr.microsoft.com/azuredocs/containerapps-helloworld:latest \
            --set-env-vars \
                DAPR_HTTP_PORT=3500 \
                PUBSUB_NAME=pubsub \
                TOPIC_NAME=orders \
                STATE_STORE_NAME=statestore
    else
        retry_command \
            "az containerapp create \
                --name inventory-service \
                --resource-group '$RESOURCE_GROUP' \
                --environment '$ENVIRONMENT_NAME' \
                --image mcr.microsoft.com/azuredocs/containerapps-helloworld:latest \
                --target-port 80 \
                --ingress internal \
                --min-replicas 1 \
                --max-replicas 10 \
                --enable-dapr \
                --dapr-app-id inventory-service \
                --dapr-app-port 80 \
                --dapr-app-protocol http \
                --cpu 0.5 \
                --memory 1.0Gi \
                --env-vars \
                    DAPR_HTTP_PORT=3500 \
                    PUBSUB_NAME=pubsub \
                    TOPIC_NAME=orders \
                    STATE_STORE_NAME=statestore" \
            "Deploying Inventory Service"
        
        wait_for_resource "containerapp" "inventory-service" "$RESOURCE_GROUP"
    fi
    
    log_success "Inventory Service deployed"
}

enable_monitoring() {
    log_info "Enabling Application Insights..."
    
    local app_insights_name="insights-dapr-demo"
    
    # Check if Application Insights already exists
    if az monitor app-insights component show \
        --app "$app_insights_name" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Application Insights '$app_insights_name' already exists"
    else
        az monitor app-insights component create \
            --app "$app_insights_name" \
            --location "$LOCATION" \
            --resource-group "$RESOURCE_GROUP" \
            --workspace "$LOG_ANALYTICS_ID"
        
        log_success "Application Insights '$app_insights_name' created"
    fi
    
    # Get instrumentation key
    local instrumentation_key
    instrumentation_key=$(az monitor app-insights component show \
        --app "$app_insights_name" \
        --resource-group "$RESOURCE_GROUP" \
        --query instrumentationKey --output tsv)
    
    # Update container apps with Application Insights
    az containerapp update \
        --name order-service \
        --resource-group "$RESOURCE_GROUP" \
        --set-env-vars APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=$instrumentation_key"
    
    az containerapp update \
        --name inventory-service \
        --resource-group "$RESOURCE_GROUP" \
        --set-env-vars APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=$instrumentation_key"
    
    log_success "Distributed tracing enabled"
}

validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Container Apps environment
    local env_status
    env_status=$(az containerapp env show \
        --name "$ENVIRONMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.provisioningState" --output tsv)
    
    if [[ "$env_status" == "Succeeded" ]]; then
        log_success "Container Apps environment is ready"
    else
        log_error "Container Apps environment status: $env_status"
        return 1
    fi
    
    # Check Dapr components
    log_info "Checking Dapr components..."
    az containerapp env dapr-component list \
        --name "$ENVIRONMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --output table
    
    # Check services
    local order_status inventory_status
    order_status=$(az containerapp show \
        --name order-service \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.runningStatus" --output tsv)
    
    inventory_status=$(az containerapp show \
        --name inventory-service \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.runningStatus" --output tsv)
    
    if [[ "$order_status" == "Running" ]]; then
        log_success "Order service is running"
    else
        log_error "Order service status: $order_status"
    fi
    
    if [[ "$inventory_status" == "Running" ]]; then
        log_success "Inventory service is running"
    else
        log_error "Inventory service status: $inventory_status"
    fi
    
    log_success "Deployment validation completed"
}

print_deployment_summary() {
    log_success "=== DEPLOYMENT SUMMARY ==="
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Container Apps Environment: $ENVIRONMENT_NAME"
    log_info "Service Bus Namespace: $SERVICE_BUS_NAMESPACE"
    log_info "Cosmos DB Account: $COSMOS_ACCOUNT"
    log_info "Key Vault Name: $KEY_VAULT_NAME"
    log_info "Order Service URL: https://$ORDER_SERVICE_URL"
    log_info ""
    log_info "Dapr Components:"
    log_info "  - pubsub (Azure Service Bus)"
    log_info "  - statestore (Azure Cosmos DB)"
    log_info ""
    log_info "Services Deployed:"
    log_info "  - order-service (external ingress)"
    log_info "  - inventory-service (internal ingress)"
    log_info ""
    log_info "Monitoring:"
    log_info "  - Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
    log_info "  - Application Insights: insights-dapr-demo"
    log_info ""
    log_info "Next Steps:"
    log_info "1. Test the Order Service: curl -X POST https://$ORDER_SERVICE_URL/api/orders"
    log_info "2. Monitor logs: az containerapp logs show --name order-service --resource-group $RESOURCE_GROUP --follow"
    log_info "3. View metrics in Azure Portal"
    log_info ""
    log_info "To clean up resources, run: ./destroy.sh"
    log_success "============================="
}

# Main deployment function
main() {
    log_info "Starting Azure Container Apps and Dapr deployment..."
    log_info "Script: $SCRIPT_NAME"
    log_info "Log file: $LOG_FILE"
    log_info "Timestamp: $(date)"
    
    check_prerequisites
    setup_environment_variables
    create_resource_group
    create_log_analytics_workspace
    create_container_apps_environment
    create_service_bus
    create_cosmos_db
    create_key_vault
    configure_dapr_components
    deploy_order_service
    deploy_inventory_service
    enable_monitoring
    validate_deployment
    print_deployment_summary
    
    log_success "Deployment completed successfully!"
    log_info "Total deployment time: $(date)"
}

# Help function
show_help() {
    cat << EOF
Azure Container Apps and Dapr Deployment Script

USAGE:
    $SCRIPT_NAME [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -g, --resource-group    Resource group name (default: rg-dapr-microservices)
    -l, --location          Azure region (default: eastus)
    -e, --environment       Container Apps environment name (default: aca-env-dapr)
    -w, --workspace         Log Analytics workspace name (default: law-dapr-microservices)
    --dry-run              Show what would be deployed without making changes

ENVIRONMENT VARIABLES:
    RESOURCE_GROUP          Resource group name
    LOCATION               Azure region
    ENVIRONMENT_NAME       Container Apps environment name
    LOG_ANALYTICS_WORKSPACE Log Analytics workspace name

EXAMPLES:
    # Deploy with defaults
    $SCRIPT_NAME

    # Deploy to specific resource group and location
    $SCRIPT_NAME -g my-rg -l westus2

    # Deploy with custom environment name
    $SCRIPT_NAME -e my-dapr-env

    # Dry run (show what would be deployed)
    $SCRIPT_NAME --dry-run

For more information, see the recipe documentation.
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
        -e|--environment)
            ENVIRONMENT_NAME="$2"
            shift 2
            ;;
        -w|--workspace)
            LOG_ANALYTICS_WORKSPACE="$2"
            shift 2
            ;;
        --dry-run)
            log_info "DRY RUN MODE - No resources will be created"
            log_info "Would deploy:"
            log_info "  - Resource Group: $RESOURCE_GROUP"
            log_info "  - Location: $LOCATION"
            log_info "  - Container Apps Environment: $ENVIRONMENT_NAME"
            log_info "  - Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
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
main "$@"