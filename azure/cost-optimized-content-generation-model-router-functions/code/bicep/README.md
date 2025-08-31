# Bicep Templates for Cost-Optimized Content Generation

This directory contains Azure Bicep Infrastructure as Code (IaC) templates for deploying the cost-optimized content generation solution using Azure AI Foundry Model Router and Azure Functions.

## Architecture Overview

The Bicep template deploys a complete serverless content generation pipeline with:

- **Azure AI Foundry**: AI Services resource with Model Router deployment for intelligent model selection
- **Azure Functions**: Serverless compute with consumption plan for cost optimization
- **Azure Storage**: Blob containers for content requests/outputs and queues for orchestration
- **Event Grid**: Event-driven triggers for blob processing
- **Application Insights**: Monitoring and telemetry with Log Analytics workspace
- **Cost Management**: Budget alerts and monitoring for cost optimization
- **Security**: RBAC assignments and managed identity for secure resource access

## Cost Optimization Features

- **Consumption Plan**: Pay-per-execution Functions with automatic scaling
- **Intelligent AI Model Selection**: Model Router automatically routes to cost-effective models
- **Standard LRS Storage**: Cost-effective storage redundancy for development/testing
- **Budget Monitoring**: Automated alerts and cost tracking
- **Log Retention Policies**: Optimized data retention to control storage costs

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with Contributor permissions
- Bicep CLI tools installed (or use Azure Cloud Shell)

## Quick Start

### 1. Deploy with Default Parameters

```bash
# Create resource group
az group create \
    --name rg-content-generation-dev \
    --location eastus

# Deploy the Bicep template
az deployment group create \
    --resource-group rg-content-generation-dev \
    --template-file main.bicep \
    --parameters @parameters.json
```

### 2. Deploy with Custom Parameters

```bash
# Deploy with custom base name and environment
az deployment group create \
    --resource-group rg-content-generation-prod \
    --template-file main.bicep \
    --parameters \
        baseName="contentprod" \
        environment="prod" \
        aiFoundrySku="S1" \
        budgetAmount=500 \
        alertEmail="devops@yourcompany.com"
```

### 3. Validate Template Before Deployment

```bash
# Validate the template
az deployment group validate \
    --resource-group rg-content-generation-dev \
    --template-file main.bicep \
    --parameters @parameters.json
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `baseName` | string | `contentgen{uniqueString}` | Base name for all resources (3-15 chars) |
| `location` | string | Resource group location | Azure region for deployment |
| `environment` | string | `dev` | Environment (dev/test/prod) |
| `costCenter` | string | `marketing` | Cost center for billing |
| `aiFoundrySku` | string | `S0` | AI Foundry pricing tier (S0/S1/S2) |
| `modelRouterCapacity` | int | `10` | Model Router capacity (1-10) |
| `storageAccountSku` | string | `Standard_LRS` | Storage redundancy level |
| `functionRuntime` | string | `node` | Function runtime (node/dotnet/python) |
| `functionRuntimeVersion` | string | `18` | Runtime version |
| `budgetAmount` | int | `100` | Monthly budget in USD (10-1000) |
| `budgetAlertThreshold` | int | `80` | Budget alert percentage (50-100) |
| `alertEmail` | string | `admin@company.com` | Email for budget alerts |
| `logRetentionDays` | int | `30` | Log Analytics retention (30-730) |

## Outputs

The template provides comprehensive outputs for integration and verification:

- Resource names and connection strings
- Endpoint URLs and access keys
- Configuration values for application deployment
- Cost optimization summary

## Post-Deployment Configuration

### 1. Deploy Function Code

After infrastructure deployment, deploy the function code:

```bash
# Get the Function App name from deployment outputs
FUNCTION_APP_NAME=$(az deployment group show \
    --resource-group rg-content-generation-dev \
    --name main \
    --query properties.outputs.functionAppName.value -o tsv)

# Deploy function code (assuming you have the function project)
func azure functionapp publish $FUNCTION_APP_NAME
```

### 2. Test the Pipeline

```bash
# Get storage connection string
STORAGE_CONNECTION=$(az deployment group show \
    --resource-group rg-content-generation-dev \
    --name main \
    --query properties.outputs.storageConnectionString.value -o tsv)

# Upload a test content request
az storage blob upload \
    --connection-string "$STORAGE_CONNECTION" \
    --container-name content-requests \
    --file sample-request.json \
    --name "test-$(date +%s).json"
```

### 3. Monitor Costs and Performance

Access monitoring through Azure Portal:
- **Cost Management**: View budget and spending trends
- **Application Insights**: Monitor function performance and costs
- **Log Analytics**: Query logs and create custom dashboards

## Security Configuration

The template configures:
- **System-assigned managed identity** for the Function App
- **RBAC assignments** for storage and AI services access
- **Network security** with HTTPS-only communication
- **Key management** through Azure Key Vault integration (optional)

## Cost Estimation

Based on typical usage patterns:

### Development Environment
- **Function App**: $0-5/month (consumption plan)
- **Storage**: $1-5/month (LRS, minimal data)
- **AI Foundry**: $10-50/month (depends on usage)
- **Monitoring**: $5-15/month (basic retention)
- **Total**: ~$15-75/month

### Production Environment
- **Function App**: $20-100/month (higher volume)
- **Storage**: $10-50/month (GRS recommended)
- **AI Foundry**: $100-500/month (depends on scale)
- **Monitoring**: $20-100/month (extended retention)
- **Total**: ~$150-750/month

## Customization Options

### Environment-Specific Configurations

**Development:**
```json
{
  "environment": { "value": "dev" },
  "aiFoundrySku": { "value": "S0" },
  "storageAccountSku": { "value": "Standard_LRS" },
  "budgetAmount": { "value": 50 }
}
```

**Production:**
```json
{
  "environment": { "value": "prod" },
  "aiFoundrySku": { "value": "S1" },
  "storageAccountSku": { "value": "Standard_GRS" },
  "budgetAmount": { "value": 500 }
}
```

### High Availability Configuration

For production workloads requiring high availability:

```json
{
  "storageAccountSku": { "value": "Standard_GRS" },
  "modelRouterCapacity": { "value": 20 },
  "logRetentionDays": { "value": 90 }
}
```

## Troubleshooting

### Common Issues

1. **Resource Name Conflicts**: Ensure `baseName` is unique globally
2. **Quota Limits**: Check AI Services quotas in target region
3. **RBAC Permissions**: Verify deployment identity has sufficient permissions
4. **Model Router Availability**: Ensure Model Router is available in selected region

### Validation Commands

```bash
# Check deployment status
az deployment group list --resource-group rg-content-generation-dev

# Verify Function App configuration
az functionapp config show --name $FUNCTION_APP_NAME --resource-group rg-content-generation-dev

# Test AI Foundry endpoint
az cognitiveservices account list --resource-group rg-content-generation-dev
```

## Cleanup

To remove all resources:

```bash
# Delete the entire resource group
az group delete \
    --name rg-content-generation-dev \
    --yes \
    --no-wait
```

## Integration with CI/CD

### Azure DevOps Pipeline

```yaml
trigger:
- main

pool:
  vmImage: 'ubuntu-latest'

variables:
  resourceGroup: 'rg-content-generation-prod'
  location: 'eastus'

steps:
- task: AzureCLI@2
  displayName: 'Deploy Infrastructure'
  inputs:
    azureSubscription: 'Your-Service-Connection'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: |
      az deployment group create \
        --resource-group $(resourceGroup) \
        --template-file bicep/main.bicep \
        --parameters @bicep/parameters.json \
        --parameters environment=prod
```

### GitHub Actions

```yaml
name: Deploy Content Generation Infrastructure

on:
  push:
    branches: [ main ]
    paths: [ 'bicep/**' ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Deploy Bicep template
      run: |
        az deployment group create \
          --resource-group rg-content-generation-prod \
          --template-file bicep/main.bicep \
          --parameters @bicep/parameters.json
```

## Support

For issues with this infrastructure template:
1. Review the [original recipe documentation](../cost-optimized-content-generation-model-router-functions.md)
2. Check [Azure Bicep documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
3. Consult [Azure AI Foundry documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/)

## Contributing

To contribute improvements:
1. Test changes in development environment
2. Update parameter validation and descriptions
3. Document any breaking changes
4. Update cost estimates if resource configurations change