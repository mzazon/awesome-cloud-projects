#!/bin/bash

# Deploy Multi-Region API Gateway with Azure API Management and Cosmos DB
# This script automates the deployment of a globally distributed API gateway
# with Azure API Management Premium tier and Cosmos DB global distribution

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deploy_config"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() { 
    log "INFO" "${BLUE}$*${NC}"
}

log_success() { 
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() { 
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() { 
    log "ERROR" "${RED}$*${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    log_info "To clean up partial deployment, run: ./destroy.sh"
    exit 1
}

trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az --version | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    local required_version="2.50.0"
    if ! printf '%s\n%s' "${required_version}" "${az_version}" | sort -V -C; then
        log_error "Azure CLI version ${az_version} is below required ${required_version}"
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show &>/dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check required tools
    for tool in openssl jq curl; do
        if ! command -v "${tool}" &> /dev/null; then
            log_error "${tool} is required but not installed."
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Set environment variables
set_environment() {
    log_info "Setting up environment variables..."
    
    # Region configuration
    export PRIMARY_REGION="${PRIMARY_REGION:-eastus}"
    export SECONDARY_REGION_1="${SECONDARY_REGION_1:-westeurope}"
    export SECONDARY_REGION_2="${SECONDARY_REGION_2:-southeastasia}"
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-global-api-gateway}"
    
    # Generate unique suffix for globally unique names
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
        cat > "${CONFIG_FILE}" <<EOF
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    else
        source "${CONFIG_FILE}"
    fi
    
    export APIM_NAME="apim-global-${RANDOM_SUFFIX}"
    export COSMOS_ACCOUNT="cosmos-api-${RANDOM_SUFFIX}"
    export TRAFFIC_MANAGER="tm-api-${RANDOM_SUFFIX}"
    export WORKSPACE_NAME="law-api-${RANDOM_SUFFIX}"
    export APP_INSIGHTS_NAME="insights-global-${RANDOM_SUFFIX}"
    
    log_info "Resource names:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  API Management: ${APIM_NAME}"
    log_info "  Cosmos DB: ${COSMOS_ACCOUNT}"
    log_info "  Traffic Manager: ${TRAFFIC_MANAGER}"
    log_info "  Log Analytics: ${WORKSPACE_NAME}"
    
    # Save configuration for cleanup
    cat >> "${CONFIG_FILE}" <<EOF
PRIMARY_REGION=${PRIMARY_REGION}
SECONDARY_REGION_1=${SECONDARY_REGION_1}
SECONDARY_REGION_2=${SECONDARY_REGION_2}
RESOURCE_GROUP=${RESOURCE_GROUP}
APIM_NAME=${APIM_NAME}
COSMOS_ACCOUNT=${COSMOS_ACCOUNT}
TRAFFIC_MANAGER=${TRAFFIC_MANAGER}
WORKSPACE_NAME=${WORKSPACE_NAME}
APP_INSIGHTS_NAME=${APP_INSIGHTS_NAME}
EOF
}

# Create resource group and foundational resources
create_foundation() {
    log_info "Creating foundational resources..."
    
    # Create resource group
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${PRIMARY_REGION}" \
        --tags purpose=multi-region-api environment=production \
        --output none
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
    
    # Create Log Analytics workspace
    log_info "Creating Log Analytics workspace: ${WORKSPACE_NAME}"
    WORKSPACE_ID=$(az monitor log-analytics workspace create \
        --name "${WORKSPACE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${PRIMARY_REGION}" \
        --sku PerGB2018 \
        --query id --output tsv)
    
    log_success "Log Analytics workspace created: ${WORKSPACE_NAME}"
    echo "WORKSPACE_ID=${WORKSPACE_ID}" >> "${CONFIG_FILE}"
}

# Create and configure Cosmos DB
create_cosmos_db() {
    log_info "Creating multi-region Cosmos DB account..."
    
    log_info "Creating Cosmos DB account: ${COSMOS_ACCOUNT}"
    az cosmosdb create \
        --name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --default-consistency-level Session \
        --locations regionName="${PRIMARY_REGION}" \
            failoverPriority=0 isZoneRedundant=true \
        --locations regionName="${SECONDARY_REGION_1}" \
            failoverPriority=1 isZoneRedundant=true \
        --locations regionName="${SECONDARY_REGION_2}" \
            failoverPriority=2 isZoneRedundant=true \
        --enable-multiple-write-locations true \
        --enable-automatic-failover true \
        --kind GlobalDocumentDB \
        --output none
    
    log_success "Cosmos DB account created with 3 regions"
    
    # Create database and containers
    log_info "Creating database and containers..."
    az cosmosdb sql database create \
        --account-name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name APIConfiguration \
        --output none
    
    # Create container for rate limiting data
    az cosmosdb sql container create \
        --account-name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --database-name APIConfiguration \
        --name RateLimits \
        --partition-key-path "/apiId" \
        --throughput 10000 \
        --output none
    
    # Store Cosmos DB endpoint
    COSMOS_ENDPOINT=$(az cosmosdb show \
        --name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query documentEndpoint --output tsv)
    
    echo "COSMOS_ENDPOINT=${COSMOS_ENDPOINT}" >> "${CONFIG_FILE}"
    log_success "Cosmos DB database and containers configured"
}

# Deploy API Management
deploy_api_management() {
    log_info "Deploying API Management instance (this may take 30-45 minutes)..."
    
    log_info "Creating API Management instance: ${APIM_NAME}"
    az apim create \
        --name "${APIM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${PRIMARY_REGION}" \
        --publisher-name "Contoso API Platform" \
        --publisher-email "api-team@contoso.com" \
        --sku-name Premium \
        --sku-capacity 1 \
        --tags environment=production purpose=global-gateway \
        --output none
    
    log_info "Waiting for API Management deployment to complete..."
    az apim wait \
        --name "${APIM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --created
    
    log_success "API Management instance created in ${PRIMARY_REGION}"
    
    # Enable managed identity
    log_info "Enabling managed identity for API Management..."
    az apim update \
        --name "${APIM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --set identity.type=SystemAssigned \
        --output none
    
    # Get managed identity principal ID
    APIM_IDENTITY=$(az apim show \
        --name "${APIM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query identity.principalId --output tsv)
    
    echo "APIM_IDENTITY=${APIM_IDENTITY}" >> "${CONFIG_FILE}"
    log_success "Managed identity enabled: ${APIM_IDENTITY}"
}

# Configure Cosmos DB access
configure_cosmos_access() {
    log_info "Configuring Cosmos DB access for API Management..."
    
    # Get Cosmos DB resource ID
    COSMOS_ID=$(az cosmosdb show \
        --name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    # Grant Cosmos DB roles
    log_info "Granting Cosmos DB permissions..."
    az role assignment create \
        --assignee "${APIM_IDENTITY}" \
        --role "Cosmos DB Account Reader Role" \
        --scope "${COSMOS_ID}" \
        --output none
    
    az cosmosdb sql role assignment create \
        --account-name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --role-definition-name "Cosmos DB Built-in Data Contributor" \
        --principal-id "${APIM_IDENTITY}" \
        --scope "/dbs/APIConfiguration" \
        --output none
    
    log_success "Cosmos DB access configured for API Management"
}

# Add secondary regions to API Management
add_secondary_regions() {
    log_info "Adding secondary regions to API Management..."
    
    # Add West Europe region
    log_info "Adding ${SECONDARY_REGION_1} region (this may take 15-20 minutes)..."
    az apim region create \
        --name "${APIM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${SECONDARY_REGION_1}" \
        --sku-capacity 1 \
        --output none
    
    # Add Southeast Asia region
    log_info "Adding ${SECONDARY_REGION_2} region (this may take 15-20 minutes)..."
    az apim region create \
        --name "${APIM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${SECONDARY_REGION_2}" \
        --sku-capacity 1 \
        --output none
    
    log_success "Multi-region deployment completed"
    
    # List all regions to verify
    log_info "Verifying regional deployments:"
    az apim region list \
        --name "${APIM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --output table
}

# Create sample API
create_sample_api() {
    log_info "Creating sample API with global configuration..."
    
    # Create sample OpenAPI specification
    cat > "${SCRIPT_DIR}/sample-api.json" <<'EOF'
{
  "openapi": "3.0.1",
  "info": {
    "title": "Global Weather API",
    "version": "1.0"
  },
  "servers": [
    {
      "url": "https://api.openweathermap.org/data/2.5"
    }
  ],
  "paths": {
    "/weather": {
      "get": {
        "summary": "Get current weather",
        "parameters": [
          {
            "name": "q",
            "in": "query",
            "required": true,
            "schema": {
              "type": "string"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "Success"
          }
        }
      }
    }
  }
}
EOF
    
    # Create API in API Management
    log_info "Creating Weather API in API Management..."
    az apim api create \
        --service-name "${APIM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --api-id weather-api \
        --path weather \
        --display-name "Global Weather API" \
        --api-type http \
        --protocols https \
        --subscription-required true \
        --output none
    
    # Import the OpenAPI specification
    az apim api import \
        --service-name "${APIM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --api-id weather-api \
        --specification-format OpenApi \
        --specification-path "${SCRIPT_DIR}/sample-api.json" \
        --output none
    
    log_success "Sample API created and imported"
}

# Configure Traffic Manager
configure_traffic_manager() {
    log_info "Configuring Azure Traffic Manager..."
    
    # Create Traffic Manager profile
    log_info "Creating Traffic Manager profile: ${TRAFFIC_MANAGER}"
    az network traffic-manager profile create \
        --name "${TRAFFIC_MANAGER}" \
        --resource-group "${RESOURCE_GROUP}" \
        --routing-method Performance \
        --unique-dns-name "${TRAFFIC_MANAGER}" \
        --ttl 30 \
        --protocol HTTPS \
        --port 443 \
        --path "/status-0123456789abcdef" \
        --output none
    
    log_success "Traffic Manager profile created"
    
    # Get API Management resource ID
    APIM_ID=$(az apim show \
        --name "${APIM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    # Add primary region endpoint
    log_info "Adding primary region endpoint..."
    az network traffic-manager endpoint create \
        --name "endpoint-${PRIMARY_REGION}" \
        --profile-name "${TRAFFIC_MANAGER}" \
        --resource-group "${RESOURCE_GROUP}" \
        --type azureEndpoints \
        --target-resource-id "${APIM_ID}" \
        --endpoint-location "${PRIMARY_REGION}" \
        --priority 1 \
        --output none
    
    # Add secondary region endpoints
    log_info "Adding secondary region endpoints..."
    az network traffic-manager endpoint create \
        --name "endpoint-${SECONDARY_REGION_1}" \
        --profile-name "${TRAFFIC_MANAGER}" \
        --resource-group "${RESOURCE_GROUP}" \
        --type externalEndpoints \
        --target "${APIM_NAME}-${SECONDARY_REGION_1}-01.regional.azure-api.net" \
        --endpoint-location "${SECONDARY_REGION_1}" \
        --priority 2 \
        --output none
    
    az network traffic-manager endpoint create \
        --name "endpoint-${SECONDARY_REGION_2}" \
        --profile-name "${TRAFFIC_MANAGER}" \
        --resource-group "${RESOURCE_GROUP}" \
        --type externalEndpoints \
        --target "${APIM_NAME}-${SECONDARY_REGION_2}-01.regional.azure-api.net" \
        --endpoint-location "${SECONDARY_REGION_2}" \
        --priority 3 \
        --output none
    
    log_success "Traffic Manager endpoints configured"
    
    # Display global endpoint
    GLOBAL_ENDPOINT="https://${TRAFFIC_MANAGER}.trafficmanager.net"
    echo "GLOBAL_ENDPOINT=${GLOBAL_ENDPOINT}" >> "${CONFIG_FILE}"
    log_success "Global API endpoint: ${GLOBAL_ENDPOINT}"
}

# Configure monitoring
configure_monitoring() {
    log_info "Configuring multi-region monitoring..."
    
    # Get API Management ID and workspace ID
    APIM_ID=$(az apim show \
        --name "${APIM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    source "${CONFIG_FILE}"
    
    # Enable diagnostics for API Management
    log_info "Enabling diagnostics for API Management..."
    az monitor diagnostic-settings create \
        --name apim-diagnostics \
        --resource "${APIM_ID}" \
        --logs '[
          {
            "category": "GatewayLogs",
            "enabled": true,
            "retentionPolicy": {"enabled": true, "days": 30}
          }
        ]' \
        --metrics '[
          {
            "category": "AllMetrics",
            "enabled": true,
            "retentionPolicy": {"enabled": true, "days": 30}
          }
        ]' \
        --workspace "${WORKSPACE_ID}" \
        --output none
    
    log_success "Diagnostics enabled for API Management"
    
    # Create alert for regional failures
    log_info "Creating monitoring alerts..."
    az monitor metrics alert create \
        --name alert-region-failure \
        --resource-group "${RESOURCE_GROUP}" \
        --scopes "${APIM_ID}" \
        --condition "avg FailedRequests > 100" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --severity 2 \
        --description "High number of failed requests detected" \
        --output none
    
    # Create Application Insights
    log_info "Creating Application Insights..."
    APP_INSIGHTS_CONNECTION=$(az monitor app-insights component create \
        --app "${APP_INSIGHTS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${PRIMARY_REGION}" \
        --workspace "${WORKSPACE_ID}" \
        --query connectionString --output tsv)
    
    # Configure API Management to use Application Insights
    az apim logger create \
        --service-name "${APIM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --logger-id appinsights-logger \
        --logger-type applicationInsights \
        --credentials "{'connectionString':'${APP_INSIGHTS_CONNECTION}'}" \
        --output none
    
    echo "APP_INSIGHTS_CONNECTION=${APP_INSIGHTS_CONNECTION}" >> "${CONFIG_FILE}"
    log_success "Multi-region monitoring configured"
}

# Validation
validate_deployment() {
    log_info "Validating deployment..."
    
    source "${CONFIG_FILE}"
    
    # Check all regions are active
    log_info "Checking regional deployments..."
    local regions_output
    regions_output=$(az apim region list \
        --name "${APIM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --output table)
    echo "${regions_output}"
    
    # Test Traffic Manager endpoint
    log_info "Testing Traffic Manager endpoint..."
    if curl -s -o /dev/null -w "%{http_code}" "${GLOBAL_ENDPOINT}/status-0123456789abcdef" | grep -q "200"; then
        log_success "Traffic Manager endpoint responding"
    else
        log_warning "Traffic Manager endpoint may still be propagating DNS"
    fi
    
    # Check Cosmos DB status
    log_info "Checking Cosmos DB replication status..."
    az cosmosdb show \
        --name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "locations[].{Region:locationName,Status:failoverPriority}" \
        --output table
    
    log_success "Deployment validation completed"
}

# Main deployment function
main() {
    log_info "Starting multi-region API gateway deployment..."
    log_info "Log file: ${LOG_FILE}"
    
    check_prerequisites
    set_environment
    create_foundation
    create_cosmos_db
    deploy_api_management
    configure_cosmos_access
    add_secondary_regions
    create_sample_api
    configure_traffic_manager
    configure_monitoring
    validate_deployment
    
    log_success "🎉 Multi-region API gateway deployment completed successfully!"
    log_info "📋 Deployment Summary:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  API Management: ${APIM_NAME}"
    log_info "  Global Endpoint: ${GLOBAL_ENDPOINT}"
    log_info "  Cosmos DB: ${COSMOS_ACCOUNT}"
    log_info "  Traffic Manager: ${TRAFFIC_MANAGER}"
    log_info ""
    log_info "📊 Next Steps:"
    log_info "  1. Configure custom APIs and policies"
    log_info "  2. Set up custom domain names"
    log_info "  3. Configure authentication and authorization"
    log_info "  4. Monitor performance across regions"
    log_info ""
    log_info "🧹 To clean up resources: ./destroy.sh"
}

# Run main function
main "$@"