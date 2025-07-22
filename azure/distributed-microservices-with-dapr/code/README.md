# Infrastructure as Code for Distributed Microservices Architecture with Container Apps and Dapr

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Distributed Microservices Architecture with Container Apps and Dapr".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI (version 2.53.0 or later) installed and configured
- Azure subscription with Owner or Contributor access
- Terraform CLI (version 1.0 or later) for Terraform deployment
- Basic understanding of microservices architecture and containerization
- Docker installed locally for container image building (optional)

### Required Azure Providers/Extensions

For Azure CLI:
```bash
# Install Container Apps extension
az extension add --name containerapp --upgrade
```

For Terraform:
- Azure Resource Manager provider (azurerm)
- Azure Active Directory provider (azuread)

## Architecture Overview

This implementation deploys:
- Azure Container Apps Environment with Dapr enabled
- Azure Service Bus (Standard tier) with topics for pub/sub messaging
- Azure Cosmos DB (Serverless) for state management
- Azure Key Vault for secrets management
- Azure Log Analytics workspace for monitoring
- Azure Application Insights for distributed tracing
- Two container applications (order-service and inventory-service)
- Dapr components for pub/sub and state store

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Set deployment parameters
export RESOURCE_GROUP="rg-dapr-microservices"
export LOCATION="eastus"
export DEPLOYMENT_NAME="dapr-microservices-$(date +%Y%m%d-%H%M%S)"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file main.bicep \
    --name ${DEPLOYMENT_NAME} \
    --parameters location=${LOCATION}

# Get deployment outputs
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DEPLOYMENT_NAME} \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/status.sh
```

## Configuration Options

### Bicep Parameters

Key parameters you can customize in the Bicep deployment:

| Parameter | Description | Default | Type |
|-----------|-------------|---------|------|
| `location` | Azure region for resources | `eastus` | string |
| `environmentName` | Container Apps environment name | `aca-env-dapr` | string |
| `serviceBusNamespaceName` | Service Bus namespace name | Auto-generated | string |
| `cosmosAccountName` | Cosmos DB account name | Auto-generated | string |
| `keyVaultName` | Key Vault name | Auto-generated | string |
| `logAnalyticsWorkspaceName` | Log Analytics workspace name | Auto-generated | string |

Example with custom parameters:
```bash
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file main.bicep \
    --parameters \
        location="westus2" \
        environmentName="my-dapr-env"
```

### Terraform Variables

Customize deployment by creating a `terraform.tfvars` file:

```hcl
# terraform.tfvars
location                = "westus2"
resource_group_name     = "rg-dapr-custom"
environment_name        = "aca-env-custom"
enable_application_insights = true
cosmos_consistency_level = "Session"

# Optional: Specify custom naming
service_bus_namespace_name = "sb-custom-name"
cosmos_account_name       = "cosmos-custom-name"
key_vault_name           = "kv-custom-name"
```

## Deployment Validation

### Post-Deployment Checks

1. **Verify Container Apps Environment**:
   ```bash
   az containerapp env show \
       --name ${ENVIRONMENT_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --query "properties.provisioningState"
   ```

2. **Check Dapr Components**:
   ```bash
   az containerapp env dapr-component list \
       --name ${ENVIRONMENT_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --output table
   ```

3. **Validate Container Apps**:
   ```bash
   az containerapp list \
       --resource-group ${RESOURCE_GROUP} \
       --output table
   ```

4. **Test Service Connectivity**:
   ```bash
   # Get order service URL
   ORDER_SERVICE_URL=$(az containerapp show \
       --name order-service \
       --resource-group ${RESOURCE_GROUP} \
       --query properties.configuration.ingress.fqdn \
       --output tsv)
   
   # Test health endpoint
   curl -X GET https://${ORDER_SERVICE_URL}/health
   ```

## Monitoring and Observability

### Application Insights Integration

The deployment automatically configures Application Insights for distributed tracing:

1. **View Application Map**:
   ```bash
   # Get Application Insights resource
   INSIGHTS_NAME=$(az monitor app-insights component list \
       --resource-group ${RESOURCE_GROUP} \
       --query "[0].name" --output tsv)
   
   echo "Application Insights: ${INSIGHTS_NAME}"
   echo "Access via Azure Portal > Monitor > Application Insights"
   ```

2. **Custom Dashboards**:
   - Navigate to Azure Portal > Dashboard
   - Create custom tiles for Container Apps metrics
   - Add Dapr-specific monitoring queries

### Log Analytics Queries

Useful KQL queries for monitoring:

```kql
// Container Apps logs
ContainerAppConsoleLogs_CL
| where ContainerName_s == "order-service"
| order by TimeGenerated desc

// Dapr sidecar logs
ContainerAppConsoleLogs_CL
| where ContainerName_s == "daprd"
| where Log_s contains "order-service"
| order by TimeGenerated desc

// Service invocation metrics
AppTraces
| where OperationName contains "invoke"
| summarize count() by OperationName, bin(TimeGenerated, 5m)
```

## Troubleshooting

### Common Issues

1. **Container Apps Not Starting**:
   ```bash
   # Check container logs
   az containerapp logs show \
       --name order-service \
       --resource-group ${RESOURCE_GROUP} \
       --follow
   ```

2. **Dapr Component Errors**:
   ```bash
   # View Dapr sidecar logs
   az containerapp logs show \
       --name order-service \
       --resource-group ${RESOURCE_GROUP} \
       --container daprd
   ```

3. **Service Bus Connection Issues**:
   ```bash
   # Verify Service Bus namespace
   az servicebus namespace show \
       --name ${SERVICE_BUS_NAMESPACE} \
       --resource-group ${RESOURCE_GROUP}
   
   # Check authorization rules
   az servicebus namespace authorization-rule list \
       --namespace-name ${SERVICE_BUS_NAMESPACE} \
       --resource-group ${RESOURCE_GROUP}
   ```

4. **Cosmos DB Access Problems**:
   ```bash
   # Check Cosmos DB account
   az cosmosdb show \
       --name ${COSMOS_ACCOUNT} \
       --resource-group ${RESOURCE_GROUP}
   
   # Verify database and container
   az cosmosdb sql database show \
       --account-name ${COSMOS_ACCOUNT} \
       --resource-group ${RESOURCE_GROUP} \
       --name daprstate
   ```

### Performance Optimization

1. **Container Apps Scaling**:
   ```bash
   # Update scaling rules
   az containerapp update \
       --name order-service \
       --resource-group ${RESOURCE_GROUP} \
       --min-replicas 2 \
       --max-replicas 20
   ```

2. **Cosmos DB Performance**:
   - Monitor Request Units (RU) consumption
   - Consider switching to provisioned throughput for predictable workloads
   - Review partition key strategy for optimal distribution

3. **Service Bus Optimization**:
   - Enable partitioning for high-throughput scenarios
   - Configure message batching
   - Implement exponential backoff for retries

## Cleanup

### Using Bicep

```bash
# Delete resource group (removes all resources)
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait

echo "✅ Resource group deletion initiated"
echo "Note: Complete deletion may take several minutes"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

### Manual Cleanup Verification

If needed, verify complete cleanup:

```bash
# Check if resource group exists
az group exists --name ${RESOURCE_GROUP}

# List any remaining resources
az resource list \
    --resource-group ${RESOURCE_GROUP} \
    --output table
```

## Cost Estimation

### Estimated Monthly Costs (USD)

Based on moderate usage patterns:

| Service | Configuration | Estimated Cost |
|---------|---------------|----------------|
| Container Apps | 2 apps, 0.5 vCPU, 1GB RAM | $15-30 |
| Service Bus | Standard tier, moderate usage | $10-15 |
| Cosmos DB | Serverless, low-moderate usage | $20-40 |
| Key Vault | Standard tier | $3-5 |
| Log Analytics | 1GB ingestion/day | $5-10 |
| Application Insights | Basic monitoring | $5-10 |
| **Total** | | **$58-110** |

> **Note**: Costs vary based on actual usage, region, and Azure pricing changes. Use the [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/) for accurate estimates.

## Security Considerations

### Implemented Security Features

1. **Managed Identity**: Container Apps use system-assigned managed identities
2. **Key Vault Integration**: Secrets stored securely in Azure Key Vault
3. **Network Security**: Internal ingress for inventory service
4. **RBAC**: Least privilege access for all components
5. **TLS Encryption**: All communication encrypted in transit
6. **Cosmos DB**: Encryption at rest enabled by default

### Additional Security Recommendations

1. **Enable Azure Defender**: For enhanced threat protection
2. **Configure Azure Firewall**: For additional network security
3. **Implement Azure Policy**: For governance and compliance
4. **Regular Security Reviews**: Monitor security recommendations
5. **Vulnerability Scanning**: Enable container image scanning

## Advanced Customization

### Adding Custom Container Images

Replace the demo images with your own:

```bash
# Update container apps with custom images
az containerapp update \
    --name order-service \
    --resource-group ${RESOURCE_GROUP} \
    --image youracr.azurecr.io/order-service:latest

az containerapp update \
    --name inventory-service \
    --resource-group ${RESOURCE_GROUP} \
    --image youracr.azurecr.io/inventory-service:latest
```

### Multi-Region Deployment

For production deployments, consider:

1. **Azure Traffic Manager**: For global load balancing
2. **Cosmos DB Global Distribution**: Multi-region replication
3. **Container Apps in Multiple Regions**: For high availability
4. **Azure Front Door**: For global application delivery

### CI/CD Integration

Example GitHub Actions workflow structure:

```yaml
# .github/workflows/deploy.yml
name: Deploy to Azure

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      - name: Deploy Bicep
        run: |
          az deployment group create \
            --resource-group ${{ secrets.RESOURCE_GROUP }} \
            --template-file bicep/main.bicep
```

## Support and Documentation

### Additional Resources

- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Dapr Documentation](https://docs.dapr.io/)
- [Azure Service Bus Documentation](https://learn.microsoft.com/en-us/azure/service-bus-messaging/)
- [Azure Cosmos DB Documentation](https://learn.microsoft.com/en-us/azure/cosmos-db/)
- [Azure Key Vault Documentation](https://learn.microsoft.com/en-us/azure/key-vault/)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review Azure resource logs and metrics
3. Consult the original recipe documentation
4. Refer to Azure support documentation

### Contributing

When modifying this infrastructure:
1. Test changes in a development environment
2. Update documentation for any parameter changes
3. Validate security configurations
4. Update cost estimates if needed