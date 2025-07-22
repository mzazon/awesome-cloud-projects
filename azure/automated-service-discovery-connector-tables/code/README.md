# Infrastructure as Code for Automated Service Discovery with Service Connector and Tables

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Service Discovery with Service Connector and Tables".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - App Service and Functions
  - Storage accounts and Tables
  - Azure SQL Database
  - Azure Cache for Redis
  - Azure Service Connector
- Basic understanding of microservices architecture and service discovery patterns
- Estimated cost: $20-40 per month for development resources

## Quick Start

### Using Bicep (Recommended)

```bash
# Create resource group
az group create \
    --name rg-service-discovery-demo \
    --location eastus

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-service-discovery-demo \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json

# Get deployment outputs
az deployment group show \
    --resource-group rg-service-discovery-demo \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the deployment plan
terraform plan -var-file="terraform.tfvars"

# Apply the infrastructure
terraform apply -var-file="terraform.tfvars"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
# and deploy all resources with proper configuration
```

## Architecture Overview

This solution implements a comprehensive service discovery system using:

- **Azure Service Connector**: Automated connection management between services
- **Azure Tables**: Scalable NoSQL registry for service metadata
- **Azure Functions**: Serverless health monitoring and service registration
- **Azure App Service**: Demo application for service discovery consumption
- **Azure SQL Database**: Sample backing service for discovery
- **Azure Cache for Redis**: Sample caching service for discovery

## Configuration

### Bicep Parameters

The Bicep implementation uses a `parameters.json` file for customization:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "environmentName": {
      "value": "dev"
    },
    "sqlAdminPassword": {
      "value": "YourSecurePassword123!"
    },
    "storageAccountSku": {
      "value": "Standard_LRS"
    },
    "functionAppRuntime": {
      "value": "node"
    },
    "functionAppVersion": {
      "value": "18"
    }
  }
}
```

### Terraform Variables

Create a `terraform.tfvars` file for customization:

```hcl
# Required variables
location = "East US"
environment = "dev"
sql_admin_password = "YourSecurePassword123!"

# Optional variables
storage_account_tier = "Standard"
storage_replication_type = "LRS"
function_app_runtime = "node"
function_app_version = "18"
sql_database_sku = "Basic"
redis_cache_sku = "Basic"
redis_cache_family = "C"
redis_cache_capacity = 0
```

### Bash Script Configuration

The deployment script will prompt for required parameters:

- Azure location/region
- Environment name (dev, staging, prod)
- SQL admin password
- Optional resource customizations

## Deployment Process

### 1. Resource Creation Order

1. **Storage Account**: Foundation for Azure Tables and Functions
2. **Service Registry Tables**: ServiceRegistry and HealthStatus tables
3. **Target Services**: SQL Database and Redis Cache for discovery
4. **Function App**: Health monitoring and service registration APIs
5. **Web Application**: Demo client for service discovery
6. **Service Connector**: Automated connection management
7. **Function Deployment**: Health monitoring and discovery logic

### 2. Validation Steps

After deployment, the infrastructure will be validated:

- Service registry tables are created and accessible
- Function apps are deployed and running
- Service Connector connections are established
- Health monitoring is operational
- Service discovery APIs are responding

### 3. Configuration Verification

The deployment includes automatic configuration of:

- Environment variables for all services
- Service Connector managed connections
- Function app settings and dependencies
- Health monitoring schedules
- Service registration endpoints

## Post-Deployment Configuration

### Deploy Function Code

```bash
# Get function app name from outputs
FUNCTION_APP=$(terraform output -raw function_app_name)

# Deploy health monitor function (code provided in scripts/)
cd function-code/
zip -r health-monitor.zip .
az functionapp deployment source config-zip \
    --resource-group rg-service-discovery-demo \
    --name $FUNCTION_APP \
    --src health-monitor.zip
```

### Test Service Registration

```bash
# Get Function App URL
FUNCTION_URL=$(az functionapp show \
    --name $FUNCTION_APP \
    --resource-group rg-service-discovery-demo \
    --query defaultHostName --output tsv)

# Register a test service
curl -X POST "https://${FUNCTION_URL}/api/ServiceRegistrar" \
    -H "Content-Type: application/json" \
    -d '{
        "serviceName": "test-api",
        "endpoint": "https://test-api.example.com",
        "serviceType": "api",
        "version": "1.0.0",
        "tags": ["production", "rest-api"],
        "metadata": {"region": "eastus", "port": 443}
    }'
```

### Verify Service Discovery

```bash
# Discover all services
curl "https://${FUNCTION_URL}/api/ServiceDiscovery"

# Discover services by type
curl "https://${FUNCTION_URL}/api/ServiceDiscovery?serviceType=api"

# Discover only healthy services
curl "https://${FUNCTION_URL}/api/ServiceDiscovery?healthyOnly=true"
```

## Usage

### Service Registration

Register a service with the discovery system:

```bash
# Get Function App URL from deployment outputs
FUNCTION_URL="https://your-function-app.azurewebsites.net"

# Register a service
curl -X POST "${FUNCTION_URL}/api/ServiceRegistrar" \
    -H "Content-Type: application/json" \
    -d '{
        "serviceName": "my-api",
        "endpoint": "https://my-api.example.com",
        "serviceType": "api",
        "version": "1.0.0",
        "tags": ["production", "rest-api"],
        "metadata": {"region": "eastus", "port": 443}
    }'
```

### Service Discovery

Discover available services:

```bash
# Discover all services
curl "${FUNCTION_URL}/api/ServiceDiscovery"

# Discover services by type
curl "${FUNCTION_URL}/api/ServiceDiscovery?serviceType=api"

# Discover only healthy services
curl "${FUNCTION_URL}/api/ServiceDiscovery?healthyOnly=true"
```

### Health Monitoring

Health checks run automatically every 5 minutes, but you can monitor the results:

```bash
# View function logs
az functionapp logs tail \
    --name your-function-app \
    --resource-group rg-service-discovery-demo
```

## Key Features

- **Dynamic Service Registration**: HTTP API for automatic service registration
- **Health Monitoring**: Timer-triggered functions monitor service health every 5 minutes
- **Service Discovery API**: REST endpoints for discovering available services
- **Automated Connections**: Service Connector manages secure connections between services
- **Scalable Storage**: Azure Tables provide high-performance service registry
- **Observability**: Application Insights integration for monitoring and alerting

## Monitoring and Troubleshooting

### Application Insights

All Function Apps are configured with Application Insights for monitoring:

- Function execution metrics
- Service discovery API performance
- Health check results and failures
- Custom telemetry for service registration

### Common Issues

1. **Service Registration Failures**
   - Check Function App logs for authentication errors
   - Verify storage account access permissions
   - Confirm JSON payload format

2. **Health Check Failures**
   - Verify service endpoints are accessible
   - Check network connectivity and firewall rules
   - Review health check timeout settings

3. **Service Discovery Timeouts**
   - Monitor Azure Tables performance metrics
   - Check Function App scaling settings
   - Verify Service Connector connection health

### Logs and Metrics

Access detailed logs and metrics:

```bash
# Function App logs
az functionapp logs tail --name your-function-app --resource-group rg-service-discovery-demo

# Storage account metrics
az monitor metrics list \
    --resource your-storage-account \
    --metric-names Transactions,Availability \
    --aggregation Average

# Application Insights queries
az monitor app-insights query \
    --app your-app-insights \
    --analytics-query "traces | where message contains 'ServiceDiscovery'"
```

## Security Considerations

### Authentication and Authorization

- Function Apps use Azure AD authentication
- Service Connector manages secure connections
- Storage accounts use Azure AD and managed identities
- SQL Database uses Azure AD authentication

### Network Security

- All services deployed with minimal network exposure
- Service Connector handles secure connectivity
- Function Apps use HTTPS-only communication
- Storage accounts restrict access to authenticated requests

### Secrets Management

- SQL passwords stored as secure parameters
- Connection strings managed by Service Connector
- Function app settings use Key Vault integration
- No hardcoded secrets in the infrastructure code

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-service-discovery-demo \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var-file="terraform.tfvars"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation
# before deleting resources
```

## Customization

### Adding New Services

To extend the solution with additional services:

1. Add new Service Connector connections in the IaC
2. Update health monitoring to include new endpoints
3. Configure service registration for new services
4. Add appropriate security and network configurations

### Scaling Configuration

Adjust scaling settings in the IaC:

- Function App consumption plan settings
- Storage account performance tier
- SQL Database service tier
- Redis cache size and tier

### Environment-Specific Deployments

Use different parameter files for each environment:

```bash
# Development environment
az deployment group create \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.dev.json

# Production environment
az deployment group create \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.prod.json
```

## Cost Optimization

### Resource Sizing

- **Storage Account**: Standard LRS for development, consider ZRS for production
- **Function Apps**: Consumption plan for variable workloads
- **SQL Database**: Basic tier for development, scale up for production
- **Redis Cache**: Basic C0 for development, Standard for production

### Cost Monitoring

Set up cost alerts and budgets:

```bash
# Create cost budget
az consumption budget create \
    --budget-name service-discovery-budget \
    --amount 100 \
    --time-grain Monthly \
    --resource-group rg-service-discovery-demo
```

## Performance Optimization

- Monitor Azure Tables request units and scale accordingly
- Adjust Function App consumption plan based on usage patterns
- Implement connection pooling for high-frequency service discovery
- Use Azure CDN for geographically distributed service discovery

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for architecture guidance
2. Review Azure Service Connector documentation for connection issues
3. Consult Azure Tables documentation for storage-related problems
4. Use Azure support channels for platform-specific issues

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Validate against the original recipe requirements
3. Ensure all IaC types remain synchronized
4. Update documentation as needed

## Version History

- **v1.0**: Initial implementation with Bicep, Terraform, and Bash scripts
- Supports Azure Service Connector, Tables, Functions, and App Service
- Includes automated health monitoring and service discovery APIs
- Provides comprehensive deployment and cleanup procedures