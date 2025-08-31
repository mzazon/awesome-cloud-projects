# Bicep Template for Simple Image Resizing with Functions and Blob Storage

This Bicep template creates a complete serverless image processing solution using Azure Functions and Blob Storage. When images are uploaded to the original-images container, they are automatically resized to thumbnail and medium sizes using Event Grid triggers.

## Architecture Overview

The template deploys the following Azure resources:

- **Storage Account** with three blob containers (original-images, thumbnails, medium-images)
- **Function App** with Consumption or Premium plan
- **Event Grid System Topic** for blob storage events
- **Event Grid Subscription** to trigger functions on blob creation
- **Application Insights** for monitoring and logging (optional)
- **Log Analytics Workspace** for Application Insights data
- **Role Assignments** for managed identity access

## Prerequisites

- Azure CLI installed and configured
- Contributor access to an Azure subscription
- Resource group created for deployment

## Quick Start

### 1. Clone and Navigate

```bash
# Navigate to the Bicep template directory
cd azure/simple-image-resizing-functions-blob/code/bicep/
```

### 2. Deploy with Default Parameters

```bash
# Create a resource group
az group create --name rg-image-resize-demo --location "East US"

# Deploy the template
az deployment group create \
  --resource-group rg-image-resize-demo \
  --template-file main.bicep \
  --parameters @parameters.json
```

### 3. Deploy with Custom Parameters

```bash
# Deploy with custom environment and settings
az deployment group create \
  --resource-group rg-image-resize-demo \
  --template-file main.bicep \
  --parameters environment=prod \
               uniqueSuffix=img123 \
               functionAppPlanSku=EP1 \
               storageAccountSku=Standard_ZRS
```

## Parameters

### Required Parameters

| Parameter | Type | Description | Allowed Values |
|-----------|------|-------------|----------------|
| `environment` | string | Environment prefix for resource naming | Any string (e.g., dev, test, prod) |
| `location` | string | Azure region for deployment | Valid Azure regions |

### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `uniqueSuffix` | string | Generated | Unique suffix for globally unique names |
| `functionAppPlanSku` | string | Y1 | Function App service plan SKU |
| `storageAccountSku` | string | Standard_LRS | Storage account replication type |
| `imageProcessingConfig` | object | See below | Image resize dimensions and quality |
| `enableApplicationInsights` | bool | true | Enable monitoring and logging |
| `resourceTags` | object | See parameters.json | Resource tags for organization |

### Image Processing Configuration

```json
{
  "thumbnailWidth": 150,
  "thumbnailHeight": 150,
  "mediumWidth": 800,
  "mediumHeight": 600,
  "jpegQuality": 85
}
```

## Function App Plan Options

| SKU | Type | Description | Use Case |
|-----|------|-------------|----------|
| Y1 | Consumption | Pay-per-execution | Development, low volume |
| EP1 | Premium | Always warm, VNet integration | Production, consistent performance |
| EP2 | Premium | Higher performance tier | High volume processing |
| EP3 | Premium | Maximum performance | Enterprise workloads |

## Storage Account Options

| SKU | Description | Durability | Cost |
|-----|-------------|------------|------|
| Standard_LRS | Locally redundant | 99.999999999% | Lowest |
| Standard_ZRS | Zone redundant | 99.9999999999% | Medium |
| Standard_GRS | Geo redundant | 99.99999999999999% | Higher |
| Premium_LRS | Premium performance | 99.999999999% | Highest |

## Deployment Examples

### Development Environment

```bash
az deployment group create \
  --resource-group rg-image-resize-dev \
  --template-file main.bicep \
  --parameters environment=dev \
               functionAppPlanSku=Y1 \
               storageAccountSku=Standard_LRS \
               enableApplicationInsights=true
```

### Production Environment

```bash
az deployment group create \
  --resource-group rg-image-resize-prod \
  --template-file main.bicep \
  --parameters environment=prod \
               functionAppPlanSku=EP1 \
               storageAccountSku=Standard_ZRS \
               enableApplicationInsights=true \
               imageProcessingConfig='{"thumbnailWidth":200,"thumbnailHeight":200,"mediumWidth":1200,"mediumHeight":900,"jpegQuality":90}'
```

### Minimal Deployment (Cost Optimized)

```bash
az deployment group create \
  --resource-group rg-image-resize-minimal \
  --template-file main.bicep \
  --parameters environment=minimal \
               functionAppPlanSku=Y1 \
               storageAccountSku=Standard_LRS \
               enableApplicationInsights=false
```

## Post-Deployment Steps

### 1. Deploy Function Code

After infrastructure deployment, you'll need to deploy the image processing function code:

```bash
# Get the Function App name from deployment outputs
FUNCTION_APP_NAME=$(az deployment group show \
  --resource-group rg-image-resize-demo \
  --name main \
  --query 'properties.outputs.functionAppName.value' \
  --output tsv)

# Deploy function code (requires function project)
func azure functionapp publish $FUNCTION_APP_NAME
```

### 2. Test the Solution

```bash
# Get storage account name and create connection string
STORAGE_ACCOUNT=$(az deployment group show \
  --resource-group rg-image-resize-demo \
  --name main \
  --query 'properties.outputs.storageAccountName.value' \
  --output tsv)

# Upload a test image
az storage blob upload \
  --account-name $STORAGE_ACCOUNT \
  --container-name original-images \
  --name test-image.jpg \
  --file /path/to/test-image.jpg \
  --auth-mode login
```

### 3. Monitor Processing

```bash
# View function logs
az webapp log tail --name $FUNCTION_APP_NAME --resource-group rg-image-resize-demo

# Check processed images
az storage blob list \
  --account-name $STORAGE_ACCOUNT \
  --container-name thumbnails \
  --auth-mode login \
  --output table
```

## Outputs

The template provides comprehensive outputs for integration:

### Key Outputs

- `storageAccountName` - Name of the created storage account
- `functionAppName` - Name of the Function App
- `storageConnectionString` - Connection string for storage access
- `containerUrls` - Direct URLs to blob containers
- `applicationInsightsConnectionString` - Monitoring connection string

### Integration Example

```bash
# Get deployment outputs
az deployment group show \
  --resource-group rg-image-resize-demo \
  --name main \
  --query 'properties.outputs' \
  --output json > deployment-outputs.json

# Use outputs in other scripts
STORAGE_URL=$(jq -r '.containerUrls.value.originalImages' deployment-outputs.json)
echo "Upload images to: $STORAGE_URL"
```

## Cost Optimization

### Consumption Plan Benefits

- **Pay-per-execution**: Only charged for actual function runs
- **Automatic scaling**: Scales to zero when not in use
- **No idle costs**: Perfect for variable workloads

### Estimated Costs (Monthly)

| Component | Consumption Plan | Premium Plan (EP1) |
|-----------|------------------|-------------------|
| Function App | $0.20/million executions | $146/month |
| Storage Account | $0.05/GB | $0.05/GB |
| Application Insights | $2.30/GB ingested | $2.30/GB ingested |
| Event Grid | $0.60/million events | $0.60/million events |
| **Total (low usage)** | **~$5/month** | **~$150/month** |

## Security Features

### Built-in Security

- **HTTPS Only**: All endpoints require secure connections
- **Managed Identity**: Function App uses system-assigned identity
- **Role-based Access**: Minimal required permissions assigned
- **TLS 1.2 Minimum**: Enforced across all services
- **Key Vault Integration**: Ready for secret management

### Network Security

- **Public Access Control**: Configurable network access rules
- **CORS Configuration**: Properly configured for web access
- **Storage Firewall**: Ready for IP restrictions if needed

## Troubleshooting

### Common Issues

1. **Function not triggering**
   - Check Event Grid subscription status
   - Verify blob uploads to correct container
   - Review function app logs

2. **Permission errors**
   - Ensure role assignments completed
   - Check managed identity configuration
   - Verify storage account access

3. **Performance issues**
   - Consider Premium plan for consistent performance
   - Monitor Application Insights metrics
   - Check storage account throttling

### Diagnostic Commands

```bash
# Check function app status
az functionapp show --name $FUNCTION_APP_NAME --resource-group rg-image-resize-demo

# View Event Grid subscription
az eventgrid system-topic event-subscription list \
  --resource-group rg-image-resize-demo \
  --system-topic-name evgt-dev-imgresiz-123456

# Check role assignments
az role assignment list --assignee $(az functionapp identity show \
  --name $FUNCTION_APP_NAME \
  --resource-group rg-image-resize-demo \
  --query principalId -o tsv)
```

## Cleanup

Remove all created resources:

```bash
# Delete the entire resource group
az group delete --name rg-image-resize-demo --yes --no-wait
```

## Advanced Configuration

### Custom Domain Setup

```bash
# Add custom domain to Function App
az functionapp config hostname add \
  --webapp-name $FUNCTION_APP_NAME \
  --resource-group rg-image-resize-demo \
  --hostname images.yourdomain.com
```

### VNet Integration

Modify the template to add VNet integration for Premium plans:

```bicep
// Add to Function App properties
vnetRouteAllEnabled: true
```

### Key Vault Integration

Add Key Vault references for sensitive settings:

```bicep
{
  name: 'StorageConnection'
  value: '@Microsoft.KeyVault(SecretUri=https://your-keyvault.vault.azure.net/secrets/storage-connection/)'
}
```

## Support

For issues with this Bicep template:

1. Check the [Azure Functions documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
2. Review [Bicep documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
3. Consult [Event Grid documentation](https://docs.microsoft.com/en-us/azure/event-grid/)

## Contributing

To improve this template:

1. Test changes in a development environment
2. Update parameters.json with new parameter examples
3. Document changes in this README
4. Validate with `az deployment group validate`