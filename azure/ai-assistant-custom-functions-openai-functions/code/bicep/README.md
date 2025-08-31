# AI Assistant with Custom Functions - Bicep Infrastructure

This directory contains Azure Bicep templates for deploying the complete infrastructure required for the AI Assistant with Custom Functions recipe using Azure OpenAI and Azure Functions.

## Architecture Overview

The Bicep templates deploy the following Azure resources:

- **Azure OpenAI Service** with GPT-4 model deployment
- **Azure Functions App** (Python 3.11 runtime) for custom business logic
- **Azure Storage Account** with blob containers for conversation history
- **Azure Key Vault** for secure secret management
- **Application Insights** and **Log Analytics Workspace** for monitoring
- **App Service Plan** (Consumption/Serverless) for cost-effective scaling

## File Structure

```
bicep/
├── main.bicep                 # Main template orchestrating all modules
├── parameters.json            # Example parameter values
├── README.md                  # This file
└── modules/
    ├── logging.bicep          # Application Insights & Log Analytics
    ├── storage.bicep          # Storage Account with containers
    ├── keyvault.bicep         # Key Vault for secrets management
    ├── cognitive-services.bicep # Azure OpenAI Service
    └── function-app.bicep     # Azure Functions App
```

## Prerequisites

Before deploying, ensure you have:

1. **Azure CLI** installed and configured
   ```bash
   az --version  # Should be 2.50.0 or later
   az login
   az account set --subscription "<your-subscription-id>"
   ```

2. **Appropriate Azure permissions** for the target subscription:
   - Contributor role or higher
   - Cognitive Services Contributor (for OpenAI)
   - Key Vault Administrator (for Key Vault)

3. **Azure OpenAI Service quota** in your target region
   - Verify OpenAI availability: `az cognitiveservices account list-skus --location eastus --kind OpenAI`

4. **Resource quotas** sufficient for:
   - 1 Cognitive Services account
   - 1 Function App
   - 1 Storage Account
   - 1 Key Vault

## Deployment Instructions

### Option 1: Deploy with Default Parameters

```bash
# Create resource group
az group create \
    --name "rg-ai-assistant-demo" \
    --location "eastus"

# Deploy the Bicep template
az deployment group create \
    --resource-group "rg-ai-assistant-demo" \
    --template-file main.bicep \
    --parameters parameters.json
```

### Option 2: Deploy with Custom Parameters

```bash
# Create resource group
az group create \
    --name "rg-ai-assistant-prod" \
    --location "eastus2"

# Deploy with custom parameters
az deployment group create \
    --resource-group "rg-ai-assistant-prod" \
    --template-file main.bicep \
    --parameters \
        location="eastus2" \
        environment="prod" \
        uniqueSuffix="prod$(date +%s)" \
        openAIModelName="gpt-35-turbo" \
        openAIModelCapacity=20 \
        logRetentionDays=365 \
        storageReplication="GRS"
```

### Option 3: What-If Deployment (Preview Changes)

```bash
# Preview changes before deployment
az deployment group what-if \
    --resource-group "rg-ai-assistant-demo" \
    --template-file main.bicep \
    --parameters parameters.json
```

## Parameter Configuration

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `location` | Azure region for deployment | `"eastus"` |
| `uniqueSuffix` | Unique suffix for resource names | `"demo001"` |

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `environment` | `"dev"` | Environment name (dev/test/prod) |
| `openAIModelName` | `"gpt-4"` | OpenAI model to deploy |
| `openAIModelVersion` | `"0613"` | Model version |
| `openAIModelCapacity` | `10` | TPM capacity (1-120) |
| `pythonVersion` | `"3.11"` | Python runtime version |
| `logRetentionDays` | `90` | Log retention period |
| `storageReplication` | `"LRS"` | Storage replication type |

### Custom Parameters File

Create your own `parameters-custom.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "westus2"
    },
    "uniqueSuffix": {
      "value": "mycompany001"
    },
    "environment": {
      "value": "prod"
    },
    "openAIModelCapacity": {
      "value": 30
    },
    "resourceTags": {
      "value": {
        "Environment": "Production",
        "Application": "AI-Assistant",
        "Owner": "AI-Team",
        "CostCenter": "Research"
      }
    }
  }
}
```

## Post-Deployment Steps

After successful deployment, follow these steps:

### 1. Retrieve Deployment Outputs

```bash
# Get deployment outputs
az deployment group show \
    --resource-group "rg-ai-assistant-demo" \
    --name "main" \
    --query "properties.outputs" \
    --output table
```

### 2. Configure Function App

```bash
# Get Function App name from outputs
FUNCTION_APP_NAME=$(az deployment group show \
    --resource-group "rg-ai-assistant-demo" \
    --name "main" \
    --query "properties.outputs.functionAppName.value" \
    --output tsv)

# Deploy function code (requires Python functions to be developed)
# func azure functionapp publish $FUNCTION_APP_NAME
```

### 3. Test the Deployment

```bash
# Test OpenAI endpoint
OPENAI_ENDPOINT=$(az deployment group show \
    --resource-group "rg-ai-assistant-demo" \
    --name "main" \
    --query "properties.outputs.openAIServiceEndpoint.value" \
    --output tsv)

echo "OpenAI Endpoint: $OPENAI_ENDPOINT"

# Test Function App health endpoint
FUNCTION_APP_URL=$(az deployment group show \
    --resource-group "rg-ai-assistant-demo" \
    --name "main" \
    --query "properties.outputs.functionAppUrl.value" \
    --output tsv)

curl "${FUNCTION_APP_URL}/api/health"
```

## Monitoring and Troubleshooting

### View Application Insights

```bash
# Get Application Insights name
AI_NAME=$(az deployment group show \
    --resource-group "rg-ai-assistant-demo" \
    --name "main" \
    --query "properties.outputs.applicationInsightsName.value" \
    --output tsv)

# Open in browser
az monitor app-insights component show \
    --app $AI_NAME \
    --resource-group "rg-ai-assistant-demo" \
    --query "appId"
```

### Check Function App Logs

```bash
# Stream Function App logs
az webapp log tail \
    --name $FUNCTION_APP_NAME \
    --resource-group "rg-ai-assistant-demo"
```

### Validate Key Vault Access

```bash
# Get Key Vault name
KV_NAME=$(az deployment group show \
    --resource-group "rg-ai-assistant-demo" \
    --name "main" \
    --query "properties.outputs.keyVaultName.value" \
    --output tsv)

# List secrets (requires appropriate permissions)
az keyvault secret list --vault-name $KV_NAME
```

## Cost Optimization

### Estimated Monthly Costs

| Service | Tier | Est. Cost (USD) |
|---------|------|-----------------|
| Azure OpenAI | Standard | $20-100 (usage-based) |
| Azure Functions | Consumption | $5-20 |
| Storage Account | Standard LRS | $2-10 |
| Key Vault | Standard | $1-5 |
| Application Insights | Pay-as-you-go | $5-15 |
| **Total** | | **$33-150/month** |

### Cost Reduction Tips

1. **Use Standard LRS storage** for development environments
2. **Configure lifecycle policies** for blob storage (included in template)
3. **Monitor OpenAI token usage** and adjust capacity as needed
4. **Use consumption plan** for Function Apps in development
5. **Set budget alerts** in Azure Cost Management

## Security Considerations

The templates implement security best practices:

- **Managed Identity** for Function App authentication
- **Key Vault integration** for secure secret storage
- **HTTPS-only** enforcement for all web services
- **Network access controls** with Azure Services bypass
- **RBAC authorization** for Key Vault access
- **Diagnostic logging** enabled for all services

## Cleanup

To remove all deployed resources:

```bash
# Delete the entire resource group
az group delete \
    --name "rg-ai-assistant-demo" \
    --yes \
    --no-wait

# Verify deletion
az group show --name "rg-ai-assistant-demo" --query "properties.provisioningState"
```

## Troubleshooting Common Issues

### 1. OpenAI Service Quota Exceeded

```bash
# Check available quotas
az cognitiveservices account list-skus \
    --location eastus \
    --kind OpenAI

# Request quota increase through Azure Portal
```

### 2. Function App Deployment Fails

- Verify Python version compatibility
- Check Application Settings in Azure Portal
- Review Function App logs for detailed errors

### 3. Key Vault Access Denied

- Verify RBAC permissions are properly assigned
- Check if Function App managed identity is enabled
- Ensure Key Vault allows Azure Services access

### 4. Storage Account Name Conflicts

- Modify `uniqueSuffix` parameter to ensure global uniqueness
- Check existing storage accounts in the subscription

## Support

For issues with this infrastructure template:

1. Check the [original recipe documentation](../../../ai-assistant-custom-functions-openai-functions.md)
2. Review Azure service documentation for specific services
3. Check deployment logs in Azure Portal
4. Verify all prerequisites are met

## Contributing

To improve these Bicep templates:

1. Follow Azure Bicep best practices
2. Test changes in development environment
3. Update parameter documentation
4. Validate security configurations
5. Update cost estimates as needed