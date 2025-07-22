#!/bin/bash

# Azure Service Discovery with Service Connector and Tables - Deployment Script
# This script deploys the complete infrastructure for automated service discovery
# using Azure Service Connector, Azure Tables, and Azure Functions

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

# Check prerequisites
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
    
    # Check if required tools are available
    local tools=("curl" "zip" "openssl")
    for tool in "${tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Setup environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-service-discovery-$(openssl rand -hex 3)}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set service-specific variables
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stdiscovery${RANDOM_SUFFIX}}"
    export FUNCTION_APP="${FUNCTION_APP:-func-discovery-${RANDOM_SUFFIX}}"
    export APP_SERVICE_PLAN="${APP_SERVICE_PLAN:-plan-discovery-${RANDOM_SUFFIX}}"
    export WEB_APP="${WEB_APP:-app-discovery-${RANDOM_SUFFIX}}"
    export SQL_SERVER="${SQL_SERVER:-sql-discovery-${RANDOM_SUFFIX}}"
    export SQL_DATABASE="${SQL_DATABASE:-ServiceRegistry}"
    export REDIS_CACHE="${REDIS_CACHE:-redis-discovery-${RANDOM_SUFFIX}}"
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
FUNCTION_APP=${FUNCTION_APP}
APP_SERVICE_PLAN=${APP_SERVICE_PLAN}
WEB_APP=${WEB_APP}
SQL_SERVER=${SQL_SERVER}
SQL_DATABASE=${SQL_DATABASE}
REDIS_CACHE=${REDIS_CACHE}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
EOF
    
    log_success "Environment variables configured"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Storage Account: ${STORAGE_ACCOUNT}"
}

# Create resource group and storage account
create_foundation() {
    log_info "Creating foundation resources..."
    
    # Create resource group
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=service-discovery environment=demo \
        --output none
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
    
    # Create storage account for Azure Tables and Functions
    log_info "Creating storage account: ${STORAGE_ACCOUNT}"
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --output none
    
    # Wait for storage account to be ready
    log_info "Waiting for storage account to be ready..."
    az storage account show \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "provisioningState" \
        --output tsv | grep -q "Succeeded"
    
    log_success "Storage account created: ${STORAGE_ACCOUNT}"
    
    # Get storage connection string
    export STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString --output tsv)
    
    log_success "Foundation resources created successfully"
}

# Create Azure Tables for service registry
create_service_registry() {
    log_info "Creating Azure Tables for service registry..."
    
    # Get storage account key
    local storage_key=$(az storage account keys list \
        --account-name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[0].value" --output tsv)
    
    # Create service registry table
    log_info "Creating ServiceRegistry table..."
    az storage table create \
        --name "ServiceRegistry" \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "$storage_key" \
        --output none
    
    # Create health status table
    log_info "Creating HealthStatus table..."
    az storage table create \
        --name "HealthStatus" \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "$storage_key" \
        --output none
    
    log_success "Service registry tables created successfully"
}

# Create target services for discovery
create_target_services() {
    log_info "Creating target services for discovery..."
    
    # Create Azure SQL Database
    log_info "Creating Azure SQL Server: ${SQL_SERVER}"
    az sql server create \
        --name "${SQL_SERVER}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --admin-user sqladmin \
        --admin-password "SecurePassword123!" \
        --output none
    
    log_info "Creating Azure SQL Database: ${SQL_DATABASE}"
    az sql db create \
        --resource-group "${RESOURCE_GROUP}" \
        --server "${SQL_SERVER}" \
        --name "${SQL_DATABASE}" \
        --service-objective Basic \
        --output none
    
    # Create Azure Cache for Redis
    log_info "Creating Azure Cache for Redis: ${REDIS_CACHE}"
    az redis create \
        --name "${REDIS_CACHE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Basic \
        --vm-size C0 \
        --output none &
    
    # Store Redis creation PID for later waiting
    local redis_pid=$!
    
    log_success "Target services creation initiated"
    
    # Wait for Redis creation to complete
    log_info "Waiting for Redis cache creation to complete..."
    wait $redis_pid
    
    log_success "Target services created successfully"
}

# Create Azure Function App for health monitoring
create_function_app() {
    log_info "Creating Azure Function App for health monitoring..."
    
    # Create App Service Plan for Functions
    log_info "Creating App Service Plan: ${APP_SERVICE_PLAN}"
    az appservice plan create \
        --name "${APP_SERVICE_PLAN}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Y1 \
        --is-linux \
        --output none
    
    # Create Function App
    log_info "Creating Function App: ${FUNCTION_APP}"
    az functionapp create \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --plan "${APP_SERVICE_PLAN}" \
        --storage-account "${STORAGE_ACCOUNT}" \
        --runtime node \
        --runtime-version 18 \
        --functions-version 4 \
        --output none
    
    # Configure Function App settings
    log_info "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION_STRING}" \
                   "WEBSITE_NODE_DEFAULT_VERSION=18" \
        --output none
    
    log_success "Function App created and configured"
}

# Deploy health monitoring function
deploy_health_monitor() {
    log_info "Deploying health monitoring function..."
    
    # Create temporary directory for function code
    local temp_dir="/tmp/health-monitor-$$"
    mkdir -p "$temp_dir"
    
    # Create package.json
    cat > "$temp_dir/package.json" << 'EOF'
{
  "name": "health-monitor",
  "version": "1.0.0",
  "dependencies": {
    "@azure/data-tables": "^13.2.2",
    "@azure/functions": "^4.0.0",
    "axios": "^1.6.0"
  }
}
EOF
    
    # Create host.json configuration
    cat > "$temp_dir/host.json" << 'EOF'
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true
      }
    }
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  }
}
EOF
    
    # Create health monitor function
    mkdir -p "$temp_dir/HealthMonitor"
    cat > "$temp_dir/HealthMonitor/function.json" << 'EOF'
{
  "bindings": [
    {
      "name": "myTimer",
      "type": "timerTrigger",
      "direction": "in",
      "schedule": "0 */5 * * * *"
    }
  ]
}
EOF
    
    # Create health monitor implementation
    cat > "$temp_dir/HealthMonitor/index.js" << 'EOF'
const { TableClient } = require('@azure/data-tables');
const axios = require('axios');

module.exports = async function (context, myTimer) {
    const storageConnectionString = process.env.STORAGE_CONNECTION_STRING;
    const registryClient = new TableClient(storageConnectionString, 'ServiceRegistry');
    const healthClient = new TableClient(storageConnectionString, 'HealthStatus');
    
    try {
        // Query all registered services
        const services = registryClient.listEntities();
        
        for await (const service of services) {
            const healthStatus = await checkServiceHealth(service);
            
            // Update health status in table
            await healthClient.upsertEntity({
                partitionKey: service.partitionKey,
                rowKey: service.rowKey,
                serviceName: service.serviceName,
                status: healthStatus.status,
                lastChecked: new Date().toISOString(),
                responseTime: healthStatus.responseTime,
                errorMessage: healthStatus.errorMessage || ''
            });
            
            context.log(`Health check completed for ${service.serviceName}: ${healthStatus.status}`);
        }
    } catch (error) {
        context.log.error('Health monitoring failed:', error);
    }
};

async function checkServiceHealth(service) {
    try {
        const startTime = Date.now();
        const response = await axios.get(service.healthEndpoint || service.endpoint, {
            timeout: 5000,
            validateStatus: (status) => status < 500
        });
        
        const responseTime = Date.now() - startTime;
        
        return {
            status: response.status < 400 ? 'healthy' : 'unhealthy',
            responseTime: responseTime,
            errorMessage: response.status >= 400 ? `HTTP ${response.status}` : null
        };
    } catch (error) {
        return {
            status: 'unhealthy',
            responseTime: 0,
            errorMessage: error.message
        };
    }
}
EOF
    
    # Deploy function to Azure
    cd "$temp_dir"
    zip -r health-monitor.zip . > /dev/null 2>&1
    
    az functionapp deployment source config-zip \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FUNCTION_APP}" \
        --src health-monitor.zip \
        --output none
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    log_success "Health monitoring function deployed"
}

# Create Web Application for service discovery
create_web_app() {
    log_info "Creating Web Application for service discovery..."
    
    # Create Web App
    log_info "Creating Web App: ${WEB_APP}"
    az webapp create \
        --name "${WEB_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --plan "${APP_SERVICE_PLAN}" \
        --runtime "NODE:18-lts" \
        --output none
    
    # Configure Web App settings
    log_info "Configuring Web App settings..."
    az webapp config appsettings set \
        --name "${WEB_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION_STRING}" \
        --output none
    
    log_success "Web application created for service discovery"
}

# Configure Service Connector connections
configure_service_connector() {
    log_info "Configuring Service Connector connections..."
    
    # Connect Function App to Storage Tables
    log_info "Connecting Function App to Storage Tables..."
    az functionapp connection create storage-table \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FUNCTION_APP}" \
        --target-resource-group "${RESOURCE_GROUP}" \
        --account "${STORAGE_ACCOUNT}" \
        --connection "StorageConnection" \
        --client-type nodejs \
        --output none
    
    # Connect Web App to Storage Tables
    log_info "Connecting Web App to Storage Tables..."
    az webapp connection create storage-table \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${WEB_APP}" \
        --target-resource-group "${RESOURCE_GROUP}" \
        --account "${STORAGE_ACCOUNT}" \
        --connection "ServiceRegistryConnection" \
        --client-type nodejs \
        --output none
    
    # Connect Web App to SQL Database
    log_info "Connecting Web App to SQL Database..."
    az webapp connection create sql \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${WEB_APP}" \
        --target-resource-group "${RESOURCE_GROUP}" \
        --server "${SQL_SERVER}" \
        --database "${SQL_DATABASE}" \
        --connection "DatabaseConnection" \
        --client-type nodejs \
        --output none
    
    # Connect Web App to Redis Cache
    log_info "Connecting Web App to Redis Cache..."
    az webapp connection create redis \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${WEB_APP}" \
        --target-resource-group "${RESOURCE_GROUP}" \
        --server "${REDIS_CACHE}" \
        --connection "CacheConnection" \
        --client-type nodejs \
        --output none
    
    log_success "Service Connector connections configured"
}

# Deploy service registration logic
deploy_service_registrar() {
    log_info "Deploying service registration logic..."
    
    # Create temporary directory for function code
    local temp_dir="/tmp/service-registrar-$$"
    mkdir -p "$temp_dir"
    
    # Create package.json
    cat > "$temp_dir/package.json" << 'EOF'
{
  "name": "service-registrar",
  "version": "1.0.0",
  "dependencies": {
    "@azure/data-tables": "^13.2.2",
    "@azure/functions": "^4.0.0"
  }
}
EOF
    
    # Create service registrar function
    mkdir -p "$temp_dir/ServiceRegistrar"
    cat > "$temp_dir/ServiceRegistrar/function.json" << 'EOF'
{
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["post"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    }
  ]
}
EOF
    
    cat > "$temp_dir/ServiceRegistrar/index.js" << 'EOF'
const { TableClient } = require('@azure/data-tables');

module.exports = async function (context, req) {
    const storageConnectionString = process.env.STORAGE_CONNECTION_STRING;
    const registryClient = new TableClient(storageConnectionString, 'ServiceRegistry');
    
    try {
        const serviceInfo = req.body;
        
        // Validate required fields
        if (!serviceInfo.serviceName || !serviceInfo.endpoint) {
            context.res = {
                status: 400,
                body: { error: 'serviceName and endpoint are required' }
            };
            return;
        }
        
        // Create service registration entry
        const serviceEntity = {
            partitionKey: serviceInfo.serviceType || 'default',
            rowKey: serviceInfo.serviceName,
            serviceName: serviceInfo.serviceName,
            endpoint: serviceInfo.endpoint,
            healthEndpoint: serviceInfo.healthEndpoint || serviceInfo.endpoint,
            serviceType: serviceInfo.serviceType || 'default',
            version: serviceInfo.version || '1.0.0',
            tags: JSON.stringify(serviceInfo.tags || []),
            metadata: JSON.stringify(serviceInfo.metadata || {}),
            registeredAt: new Date().toISOString(),
            lastHeartbeat: new Date().toISOString()
        };
        
        await registryClient.upsertEntity(serviceEntity);
        
        context.res = {
            status: 200,
            body: { 
                message: 'Service registered successfully',
                serviceId: `${serviceEntity.partitionKey}:${serviceEntity.rowKey}`
            }
        };
        
        context.log(`Service registered: ${serviceInfo.serviceName}`);
        
    } catch (error) {
        context.log.error('Service registration failed:', error);
        context.res = {
            status: 500,
            body: { error: 'Service registration failed' }
        };
    }
};
EOF
    
    # Deploy service registrar
    cd "$temp_dir"
    zip -r service-registrar.zip . > /dev/null 2>&1
    
    az functionapp deployment source config-zip \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FUNCTION_APP}" \
        --src service-registrar.zip \
        --output none
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    log_success "Service registration logic deployed"
}

# Create service discovery API
create_discovery_api() {
    log_info "Creating service discovery API..."
    
    # Create temporary directory for function code
    local temp_dir="/tmp/service-discovery-$$"
    mkdir -p "$temp_dir"
    
    # Create package.json
    cat > "$temp_dir/package.json" << 'EOF'
{
  "name": "service-discovery",
  "version": "1.0.0",
  "dependencies": {
    "@azure/data-tables": "^13.2.2",
    "@azure/functions": "^4.0.0"
  }
}
EOF
    
    # Create discovery function
    mkdir -p "$temp_dir/ServiceDiscovery"
    cat > "$temp_dir/ServiceDiscovery/function.json" << 'EOF'
{
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["get"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    }
  ]
}
EOF
    
    cat > "$temp_dir/ServiceDiscovery/index.js" << 'EOF'
const { TableClient } = require('@azure/data-tables');

module.exports = async function (context, req) {
    const storageConnectionString = process.env.STORAGE_CONNECTION_STRING;
    const registryClient = new TableClient(storageConnectionString, 'ServiceRegistry');
    const healthClient = new TableClient(storageConnectionString, 'HealthStatus');
    
    try {
        const serviceType = req.query.serviceType;
        const serviceName = req.query.serviceName;
        const healthyOnly = req.query.healthyOnly === 'true';
        
        // Query services based on parameters
        let queryOptions = {};
        if (serviceType) {
            queryOptions.filter = `PartitionKey eq '${serviceType}'`;
        }
        if (serviceName) {
            queryOptions.filter = queryOptions.filter 
                ? `${queryOptions.filter} and RowKey eq '${serviceName}'`
                : `RowKey eq '${serviceName}'`;
        }
        
        const services = [];
        const servicesIterator = registryClient.listEntities(queryOptions);
        
        for await (const service of servicesIterator) {
            let healthStatus = null;
            
            // Get health status if requested
            if (healthyOnly) {
                try {
                    healthStatus = await healthClient.getEntity(service.partitionKey, service.rowKey);
                } catch (error) {
                    // Skip services without health data if healthyOnly is true
                    continue;
                }
                
                if (healthStatus.status !== 'healthy') {
                    continue;
                }
            }
            
            services.push({
                serviceName: service.serviceName,
                endpoint: service.endpoint,
                healthEndpoint: service.healthEndpoint,
                serviceType: service.serviceType,
                version: service.version,
                tags: JSON.parse(service.tags || '[]'),
                metadata: JSON.parse(service.metadata || '{}'),
                registeredAt: service.registeredAt,
                lastHeartbeat: service.lastHeartbeat,
                healthStatus: healthStatus ? {
                    status: healthStatus.status,
                    lastChecked: healthStatus.lastChecked,
                    responseTime: healthStatus.responseTime
                } : null
            });
        }
        
        context.res = {
            status: 200,
            body: {
                services: services,
                count: services.length,
                timestamp: new Date().toISOString()
            }
        };
        
    } catch (error) {
        context.log.error('Service discovery failed:', error);
        context.res = {
            status: 500,
            body: { error: 'Service discovery failed' }
        };
    }
};
EOF
    
    # Deploy service discovery API
    cd "$temp_dir"
    zip -r service-discovery.zip . > /dev/null 2>&1
    
    az functionapp deployment source config-zip \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FUNCTION_APP}" \
        --src service-discovery.zip \
        --output none
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    log_success "Service discovery API deployed"
}

# Display deployment summary
show_deployment_summary() {
    log_info "Deployment Summary"
    echo "=================================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Storage Account: ${STORAGE_ACCOUNT}"
    echo "Function App: ${FUNCTION_APP}"
    echo "Web App: ${WEB_APP}"
    echo "SQL Server: ${SQL_SERVER}"
    echo "Redis Cache: ${REDIS_CACHE}"
    echo "=================================="
    
    # Get Function App URL
    local function_url=$(az functionapp show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query defaultHostName --output tsv)
    
    echo ""
    log_info "API Endpoints:"
    echo "Service Registration: https://${function_url}/api/ServiceRegistrar"
    echo "Service Discovery: https://${function_url}/api/ServiceDiscovery"
    echo ""
    
    # Get Web App URL
    local web_url=$(az webapp show \
        --name "${WEB_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query defaultHostName --output tsv)
    
    echo "Web Application: https://${web_url}"
    echo ""
    
    log_info "Environment file saved to: .env"
    log_info "Use this file with the cleanup script: ./destroy.sh"
}

# Main deployment function
main() {
    log_info "Starting Azure Service Discovery deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_foundation
    create_service_registry
    create_target_services
    create_function_app
    deploy_health_monitor
    create_web_app
    configure_service_connector
    deploy_service_registrar
    create_discovery_api
    show_deployment_summary
    
    log_success "Deployment completed successfully!"
    log_info "Total deployment time: $SECONDS seconds"
}

# Run main function
main "$@"