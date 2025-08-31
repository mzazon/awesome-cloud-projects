# Azure Bicep Template for QR Code Generator

This directory contains Azure Bicep Infrastructure as Code (IaC) templates for deploying the Simple QR Code Generator solution using Azure Functions and Blob Storage.

## Architecture Overview

The Bicep template deploys the following Azure resources:

- **Azure Storage Account**: Stores generated QR code images with public blob access
- **Blob Container**: Container named `qr-codes` for organizing QR code images
- **Azure Functions App**: Serverless HTTP-triggered function for QR code generation
- **App Service Plan**: Consumption plan for cost-effective serverless hosting
- **Application Insights**: Monitoring and telemetry for the Function App
- **Role Assignments**: Managed identity permissions for secure storage access

## Features

- **Serverless Architecture**: Pay-per-execution pricing with automatic scaling
- **Secure by Default**: HTTPS-only, managed identity, and encrypted storage
- **Production Ready**: Includes monitoring, logging, and proper resource tagging
- **Customizable**: Parameterized template for different environments
- **Cost Optimized**: Uses consumption pricing and standard storage tiers

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with contributor permissions
- Resource group created (or permissions to create one)

## Quick Start

### 1. Deploy with Default Parameters

```bash
# Create resource group
az group create \
    --name rg-qr-generator-dev \
    --location eastus

# Deploy Bicep template
az deployment group create \
    --resource-group rg-qr-generator-dev \
    --template-file main.bicep \
    --parameters parameters.json
```

### 2. Deploy with Custom Parameters

```bash
# Deploy with custom configuration
az deployment group create \
    --resource-group rg-qr-generator-prod \
    --template-file main.bicep \
    --parameters \
        environment=prod \
        location=westus2 \
        projectName=company-qr \
        storageSkuName=Standard_GRS \
        functionAppSkuName=EP1
```

### 3. Deploy with Parameter File Override

```bash
# Create custom parameters file
cat > custom-parameters.json << EOF
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {"value": "westeurope"},
    "environment": {"value": "prod"},
    "projectName": {"value": "enterprise-qr"},
    "storageSkuName": {"value": "Standard_ZRS"},
    "functionAppSkuName": {"value": "EP2"},
    "pythonVersion": {"value": "3.11"},
    "allowBlobPublicAccess": {"value": false}
  }
}
EOF

# Deploy with custom parameters
az deployment group create \
    --resource-group rg-enterprise-qr-prod \
    --template-file main.bicep \
    --parameters custom-parameters.json
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `resourceGroup().location` | Azure region for deployment |
| `uniqueSuffix` | string | `uniqueString(resourceGroup().id)` | Unique suffix for resource naming |
| `environment` | string | `dev` | Environment name (dev, test, prod) |
| `projectName` | string | `qr-generator` | Project name for resource naming |
| `storageSkuName` | string | `Standard_LRS` | Storage account SKU |
| `functionAppSkuName` | string | `Y1` | Function App plan SKU |
| `pythonVersion` | string | `3.11` | Python runtime version |
| `allowBlobPublicAccess` | bool | `true` | Enable public blob access |
| `minimumTlsVersion` | string | `TLS1_2` | Minimum TLS version |

## Outputs

The template provides comprehensive outputs for integration and verification:

- `resourceGroupName`: Name of the deployed resource group
- `storageAccountName`: Storage account name
- `blobContainerName`: QR codes container name
- `functionAppName`: Function App name
- `functionAppHostName`: Function App hostname
- `qrGenerationEndpoint`: Complete QR generation API endpoint
- `storageAccountBlobEndpoint`: Storage blob endpoint URL
- `applicationInsightsInstrumentationKey`: Application Insights key
- `storageConnectionString`: Storage connection string
- `functionAppPrincipalId`: Managed identity principal ID
- `deploymentSummary`: Complete deployment configuration summary

## Security Features

### Managed Identity
- Function App uses system-assigned managed identity
- No need for storage account keys in application code
- Automatic role assignment for blob storage access

### Network Security
- HTTPS-only traffic enforcement
- TLS 1.2 minimum encryption
- Secure storage account configuration

### Access Control
- Storage Blob Data Contributor role for Function App
- Principle of least privilege access
- Optional private blob access for enhanced security

## Monitoring and Observability

### Application Insights Integration
- Automatic telemetry collection
- Performance monitoring
- Error tracking and alerts
- Custom metrics support

### Built-in Logging
- Function execution logs
- HTTP request tracking
- Storage operation monitoring
- Cost and usage analytics

## Customization Examples

### Production Environment
```bash
az deployment group create \
    --resource-group rg-qr-prod \
    --template-file main.bicep \
    --parameters \
        environment=prod \
        storageSkuName=Standard_GRS \
        functionAppSkuName=EP1 \
        allowBlobPublicAccess=false
```

### High Availability Setup
```bash
az deployment group create \
    --resource-group rg-qr-ha \
    --template-file main.bicep \
    --parameters \
        environment=prod \
        storageSkuName=Standard_ZRS \
        functionAppSkuName=EP2 \
        location=eastus2
```

### Development Environment
```bash
az deployment group create \
    --resource-group rg-qr-dev \
    --template-file main.bicep \
    --parameters \
        environment=dev \
        storageSkuName=Standard_LRS \
        functionAppSkuName=Y1 \
        pythonVersion=3.11
```

## Post-Deployment Steps

After successful deployment, you need to:

1. **Deploy Function Code**: Upload the Python function code to the Function App
2. **Configure Dependencies**: Ensure requirements.txt includes all Python packages
3. **Test Endpoint**: Verify the QR generation API is working
4. **Monitor Resources**: Check Application Insights for telemetry

### Deploy Function Code Example
```bash
# Get Function App name from deployment output
FUNCTION_APP_NAME=$(az deployment group show \
    --resource-group rg-qr-generator-dev \
    --name main \
    --query properties.outputs.functionAppName.value \
    --output tsv)

# Deploy function code (zip deployment)
az functionapp deployment source config-zip \
    --resource-group rg-qr-generator-dev \
    --name $FUNCTION_APP_NAME \
    --src function-code.zip
```

## Cost Optimization

### Consumption Plan Benefits
- Pay only for execution time and requests
- Automatic scaling from zero to high load
- No charges when function is idle
- First 1 million executions free monthly

### Storage Cost Management
- Use Standard_LRS for development environments
- Implement blob lifecycle policies for cleanup
- Monitor storage usage through Azure Cost Management

### Monitoring Costs
```bash
# View current month costs for resource group
az consumption usage list \
    --scope /subscriptions/{subscription-id}/resourceGroups/rg-qr-generator-dev \
    --start-date 2024-01-01 \
    --end-date 2024-01-31
```

## Troubleshooting

### Common Deployment Issues

**Storage Account Name Conflicts**
```bash
# Check storage account name availability
az storage account check-name \
    --name "stqrgen$(openssl rand -hex 3)"
```

**Function App Cold Start**
- Consider EP1 plan for production workloads
- Implement warming strategies for better performance

**Blob Access Issues**
- Verify public access settings
- Check CORS configuration for web access
- Validate container permissions

### Validation Commands
```bash
# Verify deployment status
az deployment group show \
    --resource-group rg-qr-generator-dev \
    --name main \
    --query properties.provisioningState

# Test storage connectivity
az storage blob list \
    --container-name qr-codes \
    --account-name $STORAGE_ACCOUNT_NAME \
    --auth-mode login

# Check Function App status
az functionapp show \
    --resource-group rg-qr-generator-dev \
    --name $FUNCTION_APP_NAME \
    --query state
```

## Cleanup

To remove all deployed resources:

```bash
# Delete entire resource group and all resources
az group delete \
    --name rg-qr-generator-dev \
    --yes \
    --no-wait
```

## Advanced Configuration

### Custom Domain Setup
```bash
# Add custom domain to Function App
az functionapp config hostname add \
    --webapp-name $FUNCTION_APP_NAME \
    --resource-group rg-qr-generator-prod \
    --hostname api.yourcompany.com
```

### SSL Certificate Configuration
```bash
# Bind SSL certificate
az functionapp config ssl bind \
    --certificate-thumbprint $CERT_THUMBPRINT \
    --ssl-type SNI \
    --name $FUNCTION_APP_NAME \
    --resource-group rg-qr-generator-prod
```

### Private Endpoint Setup
For enhanced security in production environments, consider implementing private endpoints for storage and Function App connectivity.

## Support and Documentation

- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Original Recipe Documentation](../simple-qr-generator-functions-blob.md)

For issues with this Bicep template, please refer to the original recipe documentation or Azure support resources.