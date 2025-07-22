#!/bin/bash

# ==============================================================================
# Azure Container Apps and Key Vault Deployment Script
# ==============================================================================
# This script deploys secure container orchestration infrastructure using
# Azure Container Apps and Azure Key Vault following the recipe implementation.
# ==============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# ==============================================================================
# Configuration and Variables
# ==============================================================================

# Script metadata
SCRIPT_VERSION="1.0"
SCRIPT_NAME="deploy.sh"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="deploy_$(date '+%Y%m%d_%H%M%S').log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_LOCATION="eastus"
DEFAULT_ENVIRONMENT="demo"

# ==============================================================================
# Logging Functions
# ==============================================================================

log() {
    echo -e "${TIMESTAMP} [INFO] $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}❌ ERROR: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

log_warning() {
    echo -e "${YELLOW}⚠️  WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}ℹ️  INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# ==============================================================================
# Utility Functions
# ==============================================================================

print_banner() {
    echo -e "${BLUE}"
    echo "=============================================================="
    echo "  Azure Container Apps and Key Vault Deployment Script"
    echo "  Version: $SCRIPT_VERSION"
    echo "  Started: $TIMESTAMP"
    echo "=============================================================="
    echo -e "${NC}"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if Docker is available (optional but recommended)
    if ! command -v docker &> /dev/null; then
        log_warning "Docker is not installed. Some image operations may not work."
    fi
    
    # Check minimum Azure CLI version
    CLI_VERSION=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $CLI_VERSION"
    
    log_success "Prerequisites check completed"
}

generate_unique_suffix() {
    # Generate a unique suffix for resource names
    if command -v openssl &> /dev/null; then
        echo $(openssl rand -hex 3)
    else
        echo $(date +%s | tail -c 6)
    fi
}

wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local resource_group=$3
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for $resource_type '$resource_name' to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if [ "$resource_type" = "containerapp" ]; then
            local status=$(az containerapp show --name "$resource_name" --resource-group "$resource_group" --query "properties.runningStatus" -o tsv 2>/dev/null || echo "NotFound")
            if [ "$status" = "Running" ]; then
                log_success "$resource_type '$resource_name' is ready"
                return 0
            fi
        elif [ "$resource_type" = "containerapp-env" ]; then
            local status=$(az containerapp env show --name "$resource_name" --resource-group "$resource_group" --query "properties.provisioningState" -o tsv 2>/dev/null || echo "NotFound")
            if [ "$status" = "Succeeded" ]; then
                log_success "$resource_type '$resource_name' is ready"
                return 0
            fi
        fi
        
        echo -n "."
        sleep 10
        ((attempt++))
    done
    
    log_error "$resource_type '$resource_name' did not become ready within expected time"
}

# ==============================================================================
# Main Deployment Functions
# ==============================================================================

set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for globally unique resource names
    export RANDOM_SUFFIX=$(generate_unique_suffix)
    log_info "Generated random suffix: $RANDOM_SUFFIX"
    
    # Set environment variables for consistent resource naming
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-secure-containers-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set specific resource names
    export ACR_NAME="${ACR_NAME:-acrsecure${RANDOM_SUFFIX}}"
    export KEY_VAULT_NAME="${KEY_VAULT_NAME:-kv-secure-${RANDOM_SUFFIX}}"
    export ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-cae-secure-${RANDOM_SUFFIX}}"
    export LOG_ANALYTICS_NAME="${LOG_ANALYTICS_NAME:-law-secure-${RANDOM_SUFFIX}}"
    export APP_NAME_1="${APP_NAME_1:-api-service}"
    export APP_NAME_2="${APP_NAME_2:-worker-service}"
    export APP_INSIGHTS_NAME="${APP_INSIGHTS_NAME:-insights-${RANDOM_SUFFIX}}"
    
    # Environment tag
    export ENVIRONMENT_TAG="${ENVIRONMENT_TAG:-$DEFAULT_ENVIRONMENT}"
    
    log_info "Environment variables set:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  ACR Name: $ACR_NAME"
    log_info "  Key Vault Name: $KEY_VAULT_NAME"
    log_info "  Environment Name: $ENVIRONMENT_NAME"
    
    log_success "Environment variables configured"
}

create_resource_group() {
    log_info "Creating resource group..."
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' already exists, skipping creation"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=recipe environment="$ENVIRONMENT_TAG" owner=container-apps-recipe
    
    log_success "Resource group created: $RESOURCE_GROUP"
}

create_log_analytics_workspace() {
    log_info "Creating Log Analytics workspace..."
    
    # Check if workspace already exists
    if az monitor log-analytics workspace show --name "$LOG_ANALYTICS_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Log Analytics workspace '$LOG_ANALYTICS_NAME' already exists, skipping creation"
    else
        az monitor log-analytics workspace create \
            --name "$LOG_ANALYTICS_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --query id --output tsv > /dev/null
    fi
    
    # Get workspace ID and key
    export LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
        --name "$LOG_ANALYTICS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv)
    
    export LOG_ANALYTICS_KEY=$(az monitor log-analytics workspace \
        get-shared-keys \
        --name "$LOG_ANALYTICS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query primarySharedKey --output tsv)
    
    log_success "Log Analytics workspace ready: $LOG_ANALYTICS_NAME"
}

create_container_registry() {
    log_info "Creating Azure Container Registry..."
    
    # Check if ACR already exists
    if az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Container Registry '$ACR_NAME' already exists, skipping creation"
        return 0
    fi
    
    az acr create \
        --name "$ACR_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard \
        --admin-enabled false
    
    # Configure registry settings
    az acr update \
        --name "$ACR_NAME" \
        --anonymous-pull-enabled false
    
    log_success "Container Registry created: $ACR_NAME"
}

create_key_vault() {
    log_info "Creating Azure Key Vault..."
    
    # Check if Key Vault already exists
    if az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Key Vault '$KEY_VAULT_NAME' already exists, skipping creation"
    else
        az keyvault create \
            --name "$KEY_VAULT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku standard \
            --enable-soft-delete true \
            --retention-days 7 \
            --enable-purge-protection false
    fi
    
    # Store sample application secrets
    log_info "Adding sample secrets to Key Vault..."
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "DatabaseConnectionString" \
        --value "Server=tcp:myserver.database.windows.net;Database=mydb;Authentication=Active Directory Managed Identity;" \
        --output none
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "ApiKey" \
        --value "sample-api-key-${RANDOM_SUFFIX}" \
        --output none
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "ServiceBusConnection" \
        --value "Endpoint=sb://namespace.servicebus.windows.net/;Authentication=Managed Identity" \
        --output none
    
    log_success "Key Vault created with sample secrets: $KEY_VAULT_NAME"
}

create_container_apps_environment() {
    log_info "Creating Container Apps Environment..."
    
    # Check if environment already exists
    if az containerapp env show --name "$ENVIRONMENT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Container Apps Environment '$ENVIRONMENT_NAME' already exists, skipping creation"
        return 0
    fi
    
    az containerapp env create \
        --name "$ENVIRONMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --logs-workspace-id "$LOG_ANALYTICS_ID" \
        --logs-workspace-key "$LOG_ANALYTICS_KEY"
    
    # Wait for environment to be ready
    wait_for_resource "containerapp-env" "$ENVIRONMENT_NAME" "$RESOURCE_GROUP"
    
    log_success "Container Apps Environment created: $ENVIRONMENT_NAME"
}

build_and_push_images() {
    log_info "Building and pushing container images..."
    
    # Create a temporary directory for Dockerfile
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Create a simple Dockerfile for demonstration
    cat > Dockerfile <<EOF
FROM mcr.microsoft.com/dotnet/aspnet:7.0
WORKDIR /app
EXPOSE 80
ENV ASPNETCORE_URLS=http://+:80
RUN mkdir -p wwwroot && echo '{"message": "Hello from secure container!"}' > wwwroot/index.json
ENTRYPOINT ["dotnet", "serve", "-d", "wwwroot", "-p", "80"]
EOF
    
    # Build and push image using ACR Tasks
    log_info "Building API service image..."
    az acr build \
        --registry "$ACR_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --image api-service:v1 \
        --file Dockerfile .
    
    # Import a pre-built sample worker image
    log_info "Importing worker service image..."
    az acr import \
        --name "$ACR_NAME" \
        --source mcr.microsoft.com/azuredocs/containerapps-helloworld:latest \
        --image worker-service:v1
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    
    log_success "Container images built and pushed to registry"
}

deploy_container_apps() {
    log_info "Deploying Container Apps..."
    
    # Deploy first Container App (API service)
    log_info "Deploying API service..."
    if az containerapp show --name "$APP_NAME_1" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Container App '$APP_NAME_1' already exists, updating..."
        az containerapp update \
            --name "$APP_NAME_1" \
            --resource-group "$RESOURCE_GROUP" \
            --image "${ACR_NAME}.azurecr.io/api-service:v1"
    else
        az containerapp create \
            --name "$APP_NAME_1" \
            --resource-group "$RESOURCE_GROUP" \
            --environment "$ENVIRONMENT_NAME" \
            --image "${ACR_NAME}.azurecr.io/api-service:v1" \
            --target-port 80 \
            --ingress external \
            --registry-server "${ACR_NAME}.azurecr.io" \
            --registry-identity system \
            --system-assigned \
            --cpu 0.5 \
            --memory 1.0Gi \
            --min-replicas 1 \
            --max-replicas 5
    fi
    
    # Get the managed identity principal ID for API service
    export API_IDENTITY=$(az containerapp show \
        --name "$APP_NAME_1" \
        --resource-group "$RESOURCE_GROUP" \
        --query identity.principalId --output tsv)
    
    log_info "API service identity: $API_IDENTITY"
    
    # Deploy second Container App (Worker service)
    log_info "Deploying Worker service..."
    if az containerapp show --name "$APP_NAME_2" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Container App '$APP_NAME_2' already exists, updating..."
        az containerapp update \
            --name "$APP_NAME_2" \
            --resource-group "$RESOURCE_GROUP" \
            --image "${ACR_NAME}.azurecr.io/worker-service:v1"
    else
        az containerapp create \
            --name "$APP_NAME_2" \
            --resource-group "$RESOURCE_GROUP" \
            --environment "$ENVIRONMENT_NAME" \
            --image "${ACR_NAME}.azurecr.io/worker-service:v1" \
            --target-port 80 \
            --ingress internal \
            --registry-server "${ACR_NAME}.azurecr.io" \
            --registry-identity system \
            --system-assigned \
            --cpu 0.25 \
            --memory 0.5Gi \
            --min-replicas 0 \
            --max-replicas 3
    fi
    
    # Get the managed identity principal ID for Worker service
    export WORKER_IDENTITY=$(az containerapp show \
        --name "$APP_NAME_2" \
        --resource-group "$RESOURCE_GROUP" \
        --query identity.principalId --output tsv)
    
    log_info "Worker service identity: $WORKER_IDENTITY"
    
    # Wait for both apps to be ready
    wait_for_resource "containerapp" "$APP_NAME_1" "$RESOURCE_GROUP"
    wait_for_resource "containerapp" "$APP_NAME_2" "$RESOURCE_GROUP"
    
    log_success "Container Apps deployed successfully"
}

configure_key_vault_access() {
    log_info "Configuring Key Vault access for Container Apps..."
    
    # Grant Key Vault access to API service managed identity
    az keyvault set-policy \
        --name "$KEY_VAULT_NAME" \
        --object-id "$API_IDENTITY" \
        --secret-permissions get list
    
    # Grant Key Vault access to Worker service managed identity
    az keyvault set-policy \
        --name "$KEY_VAULT_NAME" \
        --object-id "$WORKER_IDENTITY" \
        --secret-permissions get list
    
    log_success "Key Vault access configured for both Container Apps"
}

configure_secret_references() {
    log_info "Configuring Key Vault secret references..."
    
    # Get Key Vault resource ID for secret references
    export KEY_VAULT_ID=$(az keyvault show \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv)
    
    # Update API service with Key Vault secret references
    az containerapp secret set \
        --name "$APP_NAME_1" \
        --resource-group "$RESOURCE_GROUP" \
        --secrets "db-connection=keyvaultref:${KEY_VAULT_ID}/secrets/DatabaseConnectionString,identityref:system" \
        "api-key=keyvaultref:${KEY_VAULT_ID}/secrets/ApiKey,identityref:system"
    
    # Add environment variables that reference the secrets
    az containerapp update \
        --name "$APP_NAME_1" \
        --resource-group "$RESOURCE_GROUP" \
        --set-env-vars "DATABASE_CONNECTION=secretref:db-connection" \
        "API_KEY=secretref:api-key" \
        "ENVIRONMENT=Production"
    
    log_success "Key Vault secrets integrated with Container Apps"
}

configure_monitoring() {
    log_info "Configuring monitoring and alerts..."
    
    # Create Application Insights for APM
    if az monitor app-insights component show --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Application Insights '$APP_INSIGHTS_NAME' already exists, skipping creation"
    else
        az monitor app-insights component create \
            --app "$APP_INSIGHTS_NAME" \
            --location "$LOCATION" \
            --resource-group "$RESOURCE_GROUP" \
            --workspace "$LOG_ANALYTICS_ID" \
            --output none
    fi
    
    # Get Application Insights instrumentation key
    export APP_INSIGHTS_KEY=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query instrumentationKey --output tsv)
    
    # Update Container Apps with Application Insights
    az containerapp update \
        --name "$APP_NAME_1" \
        --resource-group "$RESOURCE_GROUP" \
        --set-env-vars "APPLICATIONINSIGHTS_CONNECTION_STRING=InstrumentationKey=${APP_INSIGHTS_KEY}"
    
    # Create metric alert for high CPU usage
    CONTAINERAPP_ID=$(az containerapp show \
        --name "$APP_NAME_1" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv)
    
    if ! az monitor metrics alert show --name "high-cpu-alert" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az monitor metrics alert create \
            --name "high-cpu-alert" \
            --resource-group "$RESOURCE_GROUP" \
            --scopes "$CONTAINERAPP_ID" \
            --condition "avg CPU > 80" \
            --window-size 5m \
            --evaluation-frequency 1m \
            --severity 2 \
            --description "Alert when CPU usage exceeds 80%" \
            --output none
    fi
    
    log_success "Monitoring and alerting configured"
}

display_deployment_summary() {
    log_info "Deployment completed successfully!"
    echo
    echo -e "${GREEN}=============================================================="
    echo "  Deployment Summary"
    echo "==============================================================${NC}"
    echo
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo
    echo "Created Resources:"
    echo "  - Container Registry: $ACR_NAME"
    echo "  - Key Vault: $KEY_VAULT_NAME"
    echo "  - Container Apps Environment: $ENVIRONMENT_NAME"
    echo "  - Log Analytics Workspace: $LOG_ANALYTICS_NAME"
    echo "  - Application Insights: $APP_INSIGHTS_NAME"
    echo "  - Container Apps: $APP_NAME_1, $APP_NAME_2"
    echo
    
    # Get application URL
    APP_URL=$(az containerapp show \
        --name "$APP_NAME_1" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.configuration.ingress.fqdn --output tsv)
    
    echo "Application URL: https://$APP_URL"
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Test the application at the URL above"
    echo "2. Monitor logs in Azure Monitor"
    echo "3. Review Key Vault secret access"
    echo "4. When done, run destroy.sh to clean up resources"
    echo
    echo -e "${BLUE}Log file saved to: $LOG_FILE${NC}"
    echo
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
    print_banner
    
    # Trap to handle script interruption
    trap 'log_error "Script interrupted by user"' INT TERM
    
    # Check if dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log_info "Running in dry-run mode - no resources will be created"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_log_analytics_workspace
    create_container_registry
    create_key_vault
    create_container_apps_environment
    build_and_push_images
    deploy_container_apps
    configure_key_vault_access
    configure_secret_references
    configure_monitoring
    display_deployment_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi