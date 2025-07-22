# Infrastructure as Code for Global API Gateway with Multi-Region Distribution

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Global API Gateway with Multi-Region Distribution".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (Microsoft's recommended IaC language)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with Owner or Contributor access
- Terraform v1.0+ (for Terraform deployment)
- Bash shell environment (Linux, macOS, or WSL on Windows)
- Appropriate permissions for resource creation:
  - API Management service creation
  - Cosmos DB account creation
  - Traffic Manager profile creation
  - Log Analytics workspace creation
  - Role assignments for managed identities

## Architecture Overview

This implementation deploys:
- **Azure API Management Premium** instances across 3 regions (East US, West Europe, Southeast Asia)
- **Azure Cosmos DB** with multi-region writes and automatic failover
- **Azure Traffic Manager** for DNS-based global load balancing
- **Azure Monitor** with Log Analytics and Application Insights for comprehensive observability
- **Sample Weather API** with global rate limiting policies

## Quick Start

### Using Bicep

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters publisherName="Your Company" \
    --parameters publisherEmail="admin@yourcompany.com"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="publisher_name=Your Company" \
               -var="publisher_email=admin@yourcompany.com"

# Apply the configuration
terraform apply -var="publisher_name=Your Company" \
                -var="publisher_email=admin@yourcompany.com"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PUBLISHER_NAME="Your Company"
export PUBLISHER_EMAIL="admin@yourcompany.com"
export RESOURCE_GROUP="rg-global-api-gateway"

# Deploy the infrastructure
./scripts/deploy.sh
```

## Configuration Parameters

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `publisherName` | API Management publisher organization name | "Contoso API Platform" |
| `publisherEmail` | API Management publisher email address | "api-team@contoso.com" |
| `resourceGroupName` | Azure resource group name | "rg-global-api-gateway" |

### Optional Parameters

| Parameter | Description | Default | Notes |
|-----------|-------------|---------|-------|
| `primaryRegion` | Primary deployment region | "eastus" | Must support API Management Premium |
| `secondaryRegion1` | First secondary region | "westeurope" | Must support API Management Premium |
| `secondaryRegion2` | Second secondary region | "southeastasia" | Must support API Management Premium |
| `apimSkuCapacity` | API Management capacity per region | 1 | Minimum for Premium tier |
| `cosmosDbThroughput` | Cosmos DB provisioned throughput | 10000 | RU/s for rate limiting container |
| `environment` | Environment tag | "production" | Used for resource tagging |

## Deployment Time

- **Total deployment time**: 90-120 minutes
- **API Management**: 45-60 minutes (primary region)
- **Regional expansions**: 15-20 minutes each
- **Other resources**: 5-10 minutes

> **Note**: API Management Premium tier deployment is time-intensive. Consider using Developer tier for testing to reduce deployment time and costs.

## Cost Estimation

Monthly cost breakdown (approximate):

| Service | Configuration | Estimated Cost |
|---------|--------------|----------------|
| API Management Premium | 3 regions, 1 unit each | ~$4,500 |
| Cosmos DB | Multi-region, 10K RU/s | ~$600 |
| Traffic Manager | Performance routing | ~$15 |
| Log Analytics | Standard ingestion | ~$100 |
| Application Insights | Standard monitoring | ~$50 |
| **Total** | | **~$5,265/month** |

Use Azure Cost Calculator for precise estimates based on your usage patterns.

## Validation

After deployment, verify the infrastructure:

```bash
# Check API Management regions
az apim region list \
    --name <apim-name> \
    --resource-group <resource-group> \
    --output table

# Test global endpoint
curl -I https://<traffic-manager-name>.trafficmanager.net/status-0123456789abcdef

# Verify Cosmos DB replication
az cosmosdb show \
    --name <cosmos-account> \
    --resource-group <resource-group> \
    --query "locations[].{Region:locationName,Status:failoverPriority}" \
    --output table
```

## Monitoring and Observability

The deployment includes comprehensive monitoring:

- **Application Insights**: Distributed tracing and performance monitoring
- **Log Analytics**: Centralized logging from all regions
- **Azure Monitor**: Metrics and alerts for regional failures
- **Custom Dashboards**: Global API performance visualization

Access monitoring:
```bash
# View Log Analytics workspace
az monitor log-analytics workspace show \
    --resource-group <resource-group> \
    --workspace-name <workspace-name>

# Query regional performance
# Execute in Log Analytics: ApiManagementGatewayLogs | summarize avg(ResponseTime) by Region
```

## Security Features

The implementation includes:

- **Managed Identity**: Password-less authentication between services
- **Azure RBAC**: Least privilege access controls
- **Network Security**: VNet integration and private endpoints (where applicable)
- **Encryption**: Data encryption at rest and in transit
- **API Security**: Subscription keys and rate limiting policies

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name <resource-group> \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy -var="publisher_name=Your Company" \
                  -var="publisher_email=admin@yourcompany.com"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm resource group deletion
az group delete \
    --name $RESOURCE_GROUP \
    --yes \
    --no-wait
```

## Customization

### Adding Additional Regions

To add more regions to the API Management deployment:

1. **Bicep**: Add new region objects to the `additionalRegions` parameter
2. **Terraform**: Extend the `secondary_regions` variable list
3. **Bash**: Add region names to the script's region arrays

### Custom API Policies

Modify the rate limiting policy in each implementation:

- **Bicep**: Update the `policyContent` parameter in the API policy resource
- **Terraform**: Modify the `policy_xml` variable content
- **Bash**: Edit the policy XML file template in the scripts

### Cosmos DB Configuration

Adjust Cosmos DB settings:

- **Consistency Level**: Modify for your consistency requirements
- **Throughput**: Adjust RU/s based on expected load
- **Backup Policy**: Configure backup retention and frequency

## Troubleshooting

### Common Issues

1. **API Management Deployment Timeout**
   - Solution: API Management Premium deployment can take 45-60 minutes
   - Check deployment status: `az deployment group show --name <deployment-name> --resource-group <rg>`

2. **Regional Capacity Limits**
   - Solution: Some regions may have capacity constraints for Premium tier
   - Alternative: Use different regions or contact Azure support

3. **Traffic Manager Health Probes**
   - Solution: Ensure API Management status endpoint is accessible
   - Check: https://your-apim.azure-api.net/status-0123456789abcdef

4. **Cosmos DB Access Issues**
   - Solution: Verify managed identity role assignments
   - Check: API Management identity has "Cosmos DB Built-in Data Contributor" role

### Debug Commands

```bash
# Check deployment status
az deployment group list \
    --resource-group <resource-group> \
    --output table

# View API Management status
az apim show \
    --name <apim-name> \
    --resource-group <resource-group> \
    --query "provisioningState"

# Test managed identity authentication
az rest --method GET \
    --url "https://management.azure.com/subscriptions/{subscription-id}/providers/Microsoft.ManagedIdentity/userAssignedIdentities" \
    --resource "https://management.azure.com/"
```

## Performance Optimization

### API Management

- **Caching**: Enable response caching for frequently accessed APIs
- **Compression**: Enable response compression for bandwidth optimization
- **Connection Pooling**: Configure backend connection pooling settings

### Cosmos DB

- **Indexing**: Optimize indexing policies for query patterns
- **Partitioning**: Use effective partition keys for even distribution
- **Request Units**: Monitor and adjust provisioned throughput

### Traffic Manager

- **TTL Settings**: Adjust DNS TTL for balance between failover speed and DNS load
- **Health Check Frequency**: Configure appropriate probe intervals

## Advanced Features

### Implementing Custom Policies

The infrastructure supports advanced API Management policies:

- **JWT Validation**: Implement OAuth 2.0/OpenID Connect authentication
- **IP Filtering**: Restrict access based on client IP addresses
- **Request/Response Transformation**: Modify API requests and responses
- **Circuit Breaker**: Implement resilience patterns with Cosmos DB state

### Multi-Tenant Scenarios

For multi-tenant deployments:

- **Subscription Segmentation**: Use product-based API subscriptions
- **Rate Limiting**: Implement per-tenant rate limiting with Cosmos DB
- **Monitoring**: Separate telemetry by tenant using custom dimensions

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for architectural guidance
2. **Azure Documentation**: 
   - [API Management Documentation](https://docs.microsoft.com/en-us/azure/api-management/)
   - [Cosmos DB Documentation](https://docs.microsoft.com/en-us/azure/cosmos-db/)
   - [Traffic Manager Documentation](https://docs.microsoft.com/en-us/azure/traffic-manager/)
3. **Community Support**: Azure community forums and Stack Overflow
4. **Professional Support**: Azure Support plans for production deployments

## Version Information

- **Recipe Version**: 1.1
- **Last Updated**: 2025-07-12
- **Compatible Azure CLI**: v2.50.0+
- **Compatible Terraform**: v1.0+
- **Bicep Version**: Latest stable

---

> **Important**: This infrastructure deploys Premium tier services that incur significant costs. Always clean up resources after testing to avoid unexpected charges. Consider using Azure Cost Management to set up budgets and alerts for cost control.