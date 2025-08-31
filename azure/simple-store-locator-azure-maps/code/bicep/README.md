# Azure Maps Store Locator - Bicep Infrastructure as Code

This directory contains Bicep infrastructure as code templates for deploying the Azure Maps Store Locator solution described in the [Simple Store Locator with Azure Maps recipe](../../simple-store-locator-azure-maps.md).

## Architecture Overview

The Bicep template deploys the following Azure resources:

- **Azure Maps Account (Gen2)**: Provides geospatial services, interactive mapping, search capabilities, and routing functionality
- **Resource Tags**: Organizes resources for cost tracking and management
- **Security Configuration**: Optional Microsoft Entra ID authentication and CORS rules for web applications

## Files Included

- `main.bicep` - Main Bicep template defining Azure Maps infrastructure
- `parameters.json` - Example parameter values for deployment
- `README.md` - This documentation file

## Prerequisites

Before deploying this template, ensure you have:

1. **Azure Subscription** with permissions to create Azure Maps accounts
2. **Azure CLI** (version 2.20.0 or later) or **Azure PowerShell** (version 6.0 or later)
3. **Bicep CLI** installed ([Installation Guide](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/install))
4. **Resource Group** created for the deployment

## Quick Start Deployment

### Using Azure CLI

```bash
# Login to Azure
az login

# Set your subscription (if you have multiple)
az account set --subscription "your-subscription-id"

# Create a resource group (if not already created)
az group create \
    --name "rg-storemaps-demo" \
    --location "eastus"

# Deploy the Bicep template
az deployment group create \
    --resource-group "rg-storemaps-demo" \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Azure PowerShell

```powershell
# Login to Azure
Connect-AzAccount

# Set your subscription (if you have multiple)
Set-AzContext -SubscriptionId "your-subscription-id"

# Create a resource group (if not already created)
New-AzResourceGroup `
    -Name "rg-storemaps-demo" `
    -Location "eastus"

# Deploy the Bicep template
New-AzResourceGroupDeployment `
    -ResourceGroupName "rg-storemaps-demo" `
    -TemplateFile "main.bicep" `
    -TemplateParameterFile "parameters.json"
```

### Using Azure Cloud Shell

1. Open [Azure Cloud Shell](https://shell.azure.com)
2. Upload the Bicep files to Cloud Shell
3. Run the deployment commands:

```bash
# Create resource group
az group create --name "rg-storemaps-demo" --location "eastus"

# Deploy template
az deployment group create \
    --resource-group "rg-storemaps-demo" \
    --template-file main.bicep \
    --parameters @parameters.json
```

## Template Parameters

### Required Parameters

| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `mapsAccountName` | string | Globally unique name for the Azure Maps account | `mapstore-demo-001` |

### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | Resource Group location | Location for the Maps account |
| `environment` | string | `dev` | Environment tag (dev/test/staging/prod) |
| `projectName` | string | `store-locator` | Project name for resource tagging |
| `costCenter` | string | `demo` | Cost center for billing allocation |
| `enableSystemIdentity` | bool | `false` | Enable system-assigned managed identity |
| `disableLocalAuth` | bool | `false` | Disable subscription key authentication |
| `additionalDataProcessingRegions` | array | `[]` | Additional regions for data processing |
| `corsRules` | array | See template | CORS rules for web applications |

## Customization Examples

### Development Environment

```json
{
  "mapsAccountName": { "value": "mapstore-dev-001" },
  "environment": { "value": "dev" },
  "disableLocalAuth": { "value": false },
  "corsRules": {
    "value": [
      {
        "allowedOrigins": [
          "http://localhost:*",
          "https://localhost:*"
        ]
      }
    ]
  }
}
```

### Production Environment with Enhanced Security

```json
{
  "mapsAccountName": { "value": "mapstore-prod-001" },
  "environment": { "value": "prod" },
  "enableSystemIdentity": { "value": true },
  "disableLocalAuth": { "value": true },
  "corsRules": {
    "value": [
      {
        "allowedOrigins": [
          "https://yourdomain.com",
          "https://www.yourdomain.com"
        ]
      }
    ]
  },
  "additionalDataProcessingRegions": {
    "value": ["westus2", "northeurope"]
  }
}
```

## Template Outputs

The template provides the following outputs for integration with your store locator application:

| Output | Type | Description |
|--------|------|-------------|
| `mapsAccountId` | string | Resource ID of the Maps account |
| `mapsAccountName` | string | Name of the deployed Maps account |
| `primaryKey` | securestring | Primary subscription key for authentication |
| `secondaryKey` | securestring | Secondary subscription key for authentication |
| `clientId` | string | Client ID for Microsoft Entra ID authentication |
| `mapsApiEndpoint` | string | Azure Maps REST API endpoint |
| `webSdkUrl` | string | Azure Maps Web SDK JavaScript URL |
| `webSdkCssUrl` | string | Azure Maps Web SDK CSS URL |
| `configurationSummary` | object | Summary of deployed configuration |

### Using Outputs in Your Application

After deployment, you can retrieve the subscription key for your web application:

```bash
# Get the primary key
az deployment group show \
    --resource-group "rg-storemaps-demo" \
    --name "main" \
    --query "properties.outputs.primaryKey.value" \
    --output tsv
```

## Security Considerations

### Subscription Keys vs. Microsoft Entra ID

- **Development**: Use subscription keys for simplicity
- **Production**: Consider Microsoft Entra ID authentication for enhanced security

### CORS Configuration

Configure CORS rules to restrict access to your specific domains:

```json
{
  "corsRules": {
    "value": [
      {
        "allowedOrigins": [
          "https://yourdomain.com",
          "https://www.yourdomain.com"
        ]
      }
    ]
  }
}
```

### Key Management

- Store subscription keys securely (Azure Key Vault recommended)
- Rotate keys periodically
- Use separate keys for different environments
- Monitor key usage through Azure Monitor

## Cost Management

### Azure Maps Gen2 Pricing

- **Free Tier**: 1,000 transactions per month
- **Pay-per-use**: $0.50 per 1,000 transactions after free tier
- **Transaction Types**: Map loads, searches, routes, etc.

### Cost Optimization Tips

1. **Implement Caching**: Cache map tiles and search results
2. **Optimize Requests**: Batch operations when possible
3. **Monitor Usage**: Use Azure Monitor to track transaction consumption
4. **Set Budgets**: Create Azure budgets with alerts

### Estimating Costs

For a typical store locator with moderate usage:
- **Small Business**: ~500 visits/month = FREE
- **Medium Business**: ~5,000 visits/month = ~$2.50/month
- **Large Business**: ~50,000 visits/month = ~$25/month

## Monitoring and Observability

### Azure Monitor Integration

The deployed Maps account automatically integrates with Azure Monitor for:

- **Metrics**: Request count, latency, error rates
- **Logs**: API usage, authentication events
- **Alerts**: Threshold-based notifications

### Recommended Alerts

```bash
# Create alert for high transaction usage (approaching free tier limit)
az monitor metrics alert create \
    --name "Maps Transaction Alert" \
    --resource-group "rg-storemaps-demo" \
    --scopes "/subscriptions/{subscription-id}/resourceGroups/rg-storemaps-demo/providers/Microsoft.Maps/accounts/mapstore-demo-001" \
    --condition "count \"Total Transactions\" >= 800" \
    --description "Alert when approaching monthly free tier limit"
```

## Troubleshooting

### Common Deployment Issues

1. **Name Already Exists**: Maps account names must be globally unique
   - **Solution**: Try a different name or append random characters

2. **Permission Denied**: Insufficient permissions to create Maps accounts
   - **Solution**: Ensure you have `Contributor` or `Maps Account Contributor` role

3. **Location Not Supported**: Some regions may not support Azure Maps
   - **Solution**: Use supported regions like `eastus`, `westus2`, `northeurope`

### Validation Commands

```bash
# Verify deployment status
az deployment group show \
    --resource-group "rg-storemaps-demo" \
    --name "main"

# Test Maps account functionality
az maps account show \
    --resource-group "rg-storemaps-demo" \
    --name "mapstore-demo-001"

# List available subscription keys
az maps account keys list \
    --resource-group "rg-storemaps-demo" \
    --name "mapstore-demo-001"
```

## Integration with Store Locator Application

After successful deployment, integrate the Maps account with your web application:

1. **Update JavaScript Configuration**:
   ```javascript
   const MAPS_KEY = 'your-primary-key-from-output';
   ```

2. **Configure CORS** (if needed):
   Update the `corsRules` parameter to include your application's domain

3. **Test Integration**:
   Verify that your web application can load maps and perform searches

## Cleanup

To remove all deployed resources:

```bash
# Delete the entire resource group (WARNING: This removes ALL resources)
az group delete --name "rg-storemaps-demo" --yes --no-wait

# Or delete just the Maps account
az maps account delete \
    --resource-group "rg-storemaps-demo" \
    --name "mapstore-demo-001"
```

## Additional Resources

- [Azure Maps Documentation](https://docs.microsoft.com/en-us/azure/azure-maps/)
- [Azure Maps Pricing](https://azure.microsoft.com/pricing/details/azure-maps/)
- [Understanding Azure Maps Transactions](https://docs.microsoft.com/en-us/azure/azure-maps/understanding-azure-maps-transactions)
- [Azure Maps Web SDK Samples](https://samples.azuremaps.com/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)

## Support

For issues with this Bicep template:
1. Check the [troubleshooting section](#troubleshooting) above
2. Review Azure Maps [known issues](https://docs.microsoft.com/en-us/azure/azure-maps/troubleshoot)
3. Submit an issue in your project repository

For Azure Maps service issues:
- [Azure Support](https://azure.microsoft.com/support/)
- [Azure Maps Community Forum](https://docs.microsoft.com/en-us/answers/topics/azure-maps.html)