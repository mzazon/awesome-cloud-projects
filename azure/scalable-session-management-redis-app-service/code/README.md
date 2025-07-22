# Infrastructure as Code for Scalable Session Management with Redis and App Service

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Scalable Session Management with Redis and App Service".

## Available Implementations

- **Bicep**: Azure-native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using official Azure provider
- **Scripts**: Bash deployment and cleanup scripts for manual execution

## Prerequisites

- Azure CLI installed and configured (version 2.0 or later)
- Appropriate Azure subscription with permissions for:
  - Creating resource groups
  - Deploying Azure Managed Redis instances
  - Creating Azure App Service plans and web apps
  - Setting up virtual networks and subnets
  - Configuring Azure Monitor and diagnostic settings
- For Terraform: Terraform CLI installed (version 1.0 or later)

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to bicep directory
cd bicep/

# Review and customize parameters
az deployment group create \
    --resource-group rg-session-demo \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
az redis show --name redis-session-$(openssl rand -hex 3) --resource-group rg-session-demo
```

## Architecture Overview

This infrastructure deploys a complete distributed session management solution with:

- **Azure Managed Redis**: Memory Optimized tier for high-performance session storage
- **Azure App Service**: Standard tier with multiple instances for horizontal scaling
- **Virtual Network**: Secure network isolation between App Service and Redis
- **Azure Monitor**: Comprehensive monitoring with alerts and diagnostic logging
- **Log Analytics**: Centralized logging for troubleshooting and analytics

## Configuration Options

### Resource Naming

All implementations use a consistent naming convention with random suffixes to ensure uniqueness:

- Resource Group: `rg-session-demo`
- Redis Instance: `redis-session-{random}`
- App Service Plan: `plan-session-{random}`
- Web App: `app-session-{random}`
- Virtual Network: `vnet-session-{random}`

### Performance Tiers

The default configuration deploys:

- **Redis**: Memory Optimized M10 (1GB memory, dedicated resources)
- **App Service**: Standard S1 (1.75GB RAM, 100 ACU)
- **Instances**: 2 App Service instances for testing session persistence

### Cost Optimization

For development/testing environments, consider these alternatives:

- Redis: Balanced B1 tier (saves ~40% on costs)
- App Service: Basic B1 tier (saves ~30% on costs)
- Reduce instance count to 1 for single-instance testing

## Customization

### Bicep Parameters

Modify `parameters.json` to customize the deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "redisSkuName": {
      "value": "M10"
    },
    "appServicePlanSku": {
      "value": "S1"
    },
    "instanceCount": {
      "value": 2
    }
  }
}
```

### Terraform Variables

Customize `variables.tf` or create a `terraform.tfvars` file:

```hcl
location = "eastus"
redis_sku_name = "M10"
app_service_plan_sku = "S1"
instance_count = 2
environment = "demo"
```

### Environment Variables for Scripts

Set these environment variables before running scripts:

```bash
export RESOURCE_GROUP="rg-session-demo"
export LOCATION="eastus"
export REDIS_SKU="M10"
export APP_SERVICE_SKU="S1"
```

## Validation

After deployment, verify the infrastructure:

### Check Redis Status

```bash
# Get Redis details
az redis show \
    --name redis-session-${RANDOM_SUFFIX} \
    --resource-group ${RESOURCE_GROUP} \
    --query "{Status:provisioningState, HostName:hostName, Port:sslPort}"
```

### Test App Service Connectivity

```bash
# Check App Service status
az webapp show \
    --name app-session-${RANDOM_SUFFIX} \
    --resource-group ${RESOURCE_GROUP} \
    --query "{Status:state, URL:defaultHostName, Instances:numberOfWorkers}"
```

### Verify Network Configuration

```bash
# Check virtual network setup
az network vnet show \
    --name vnet-session-${RANDOM_SUFFIX} \
    --resource-group ${RESOURCE_GROUP} \
    --query "{AddressSpace:addressSpace.addressPrefixes[0], Subnets:subnets[].name}"
```

### Test Session Persistence

```bash
# Scale App Service to multiple instances
az appservice plan update \
    --name plan-session-${RANDOM_SUFFIX} \
    --resource-group ${RESOURCE_GROUP} \
    --number-of-workers 3

# Verify scaling
az appservice plan show \
    --name plan-session-${RANDOM_SUFFIX} \
    --resource-group ${RESOURCE_GROUP} \
    --query "numberOfWorkers"
```

## Monitoring and Diagnostics

### Azure Monitor Alerts

The infrastructure includes pre-configured alerts for:

- High Redis cache miss rates (>100 misses in 5 minutes)
- Redis connection errors (>10 errors in 5 minutes)
- App Service availability issues

### Log Analytics Queries

Access diagnostic logs in Log Analytics workspace:

```kusto
// Redis connection patterns
AzureDiagnostics
| where Category == "ConnectedClientList"
| where TimeGenerated > ago(1h)
| summarize ConnectionCount = count() by bin(TimeGenerated, 5m)

// App Service performance metrics
AppServiceHTTPLogs
| where TimeGenerated > ago(1h)
| summarize AvgResponseTime = avg(TimeTaken) by bin(TimeGenerated, 5m)
```

### Performance Monitoring

Monitor key metrics through Azure portal:

- **Redis**: Cache hit ratio, memory usage, connected clients
- **App Service**: CPU usage, memory consumption, response times
- **Network**: Latency between App Service and Redis

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-session-demo \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Verify Cleanup

```bash
# Confirm resource group deletion
az group exists --name rg-session-demo
# Should return: false
```

## Security Considerations

This infrastructure implements several security best practices:

- **Network Isolation**: Redis deployed in dedicated subnet
- **TLS Encryption**: All Redis connections use TLS 1.2+
- **Non-SSL Port Disabled**: Only secure connections allowed to Redis
- **Managed Identities**: App Service uses managed identity where possible
- **Private Networking**: VNet integration for secure communication

## Troubleshooting

### Common Issues

1. **Redis Connection Timeout**
   ```bash
   # Check network security group rules
   az network nsg list --resource-group ${RESOURCE_GROUP}
   ```

2. **App Service Cannot Reach Redis**
   ```bash
   # Verify VNet integration
   az webapp vnet-integration list --name app-session-${RANDOM_SUFFIX} --resource-group ${RESOURCE_GROUP}
   ```

3. **High Memory Usage in Redis**
   ```bash
   # Check Redis configuration
   az redis show --name redis-session-${RANDOM_SUFFIX} --resource-group ${RESOURCE_GROUP} --query "redisConfiguration"
   ```

### Diagnostic Commands

```bash
# Get comprehensive status
az resource list \
    --resource-group ${RESOURCE_GROUP} \
    --output table

# Check deployment status
az deployment group list \
    --resource-group ${RESOURCE_GROUP} \
    --query "[].{Name:name, Status:properties.provisioningState, Timestamp:properties.timestamp}"
```

## Cost Management

### Cost Monitoring

- Enable Azure Cost Management alerts for the resource group
- Set budget alerts at $100/month for demo environments
- Monitor daily spend through Azure portal

### Cost Optimization Tips

1. **Development Environments**: Use Basic tiers for Redis and App Service
2. **Scheduled Shutdown**: Implement auto-shutdown for non-production environments
3. **Resource Tagging**: Apply cost center tags for chargeback
4. **Reserved Instances**: Consider reserved instances for production workloads

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../implementing-distributed-session-management-with-azure-managed-redis-and-azure-app-service.md)
2. Review [Azure Managed Redis documentation](https://learn.microsoft.com/en-us/azure/redis/)
3. Consult [Azure App Service documentation](https://learn.microsoft.com/en-us/azure/app-service/)
4. Check [Azure Monitor documentation](https://learn.microsoft.com/en-us/azure/monitor/) for monitoring guidance

## Next Steps

After successful deployment, consider these enhancements:

1. **SSL Certificate Configuration**: Add custom domain and SSL certificate
2. **Auto-scaling Rules**: Implement metric-based auto-scaling
3. **Backup Strategy**: Configure Redis data persistence
4. **Multi-region Deployment**: Extend to multiple Azure regions
5. **Application Code**: Implement Redis session provider in your application

For production deployments, review the [Azure Well-Architected Framework](https://learn.microsoft.com/en-us/azure/well-architected/) guidance for security, reliability, and performance optimization.