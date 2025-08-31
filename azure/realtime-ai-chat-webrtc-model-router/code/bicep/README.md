# Real-time AI Chat with WebRTC and Model Router - Bicep Implementation

This directory contains the Bicep Infrastructure as Code (IaC) implementation for deploying a real-time AI chat application using Azure OpenAI's WebRTC-enabled Realtime API with intelligent model routing.

## Architecture Overview

The solution deploys the following Azure resources:

- **Azure OpenAI Service** with custom domain for WebRTC Realtime API access
- **Two OpenAI Model Deployments**:
  - GPT-4o-mini-realtime-preview (cost-effective for simple queries)
  - GPT-4o-realtime-preview (premium for complex interactions)
- **Azure SignalR Service** in serverless mode for real-time communication
- **Azure Functions** consumption plan for serverless compute
- **Storage Account** for Azure Functions runtime
- **Application Insights** for monitoring and analytics
- **Managed Identity** and role assignments for secure access

## Prerequisites

Before deploying this template, ensure you have:

1. **Azure CLI** installed and configured
2. **Azure subscription** with contributor permissions
3. **Regional access** to Azure OpenAI Realtime API (East US 2 or Sweden Central)
4. **Sufficient quotas** for Azure OpenAI model deployments
5. **Bicep CLI** installed (comes with Azure CLI 2.20.0+)

## Quick Start

### 1. Clone and Navigate to Directory

```bash
# Navigate to the Bicep directory
cd azure/realtime-ai-chat-webrtc-model-router/code/bicep/
```

### 2. Review and Customize Parameters

Edit the `parameters.json` file to customize the deployment:

```json
{
  "namePrefix": {
    "value": "realtimechat"  // Change to your preferred prefix
  },
  "location": {
    "value": "eastus2"       // Use eastus2 or swedencentral
  },
  "environment": {
    "value": "dev"           // dev, test, or prod
  }
}
```

### 3. Deploy the Infrastructure

```bash
# Create resource group
az group create \
    --name rg-realtime-chat-dev \
    --location eastus2 \
    --tags purpose=realtime-ai-chat environment=dev

# Deploy the Bicep template
az deployment group create \
    --resource-group rg-realtime-chat-dev \
    --template-file main.bicep \
    --parameters @parameters.json
```

### 4. Verify Deployment

```bash
# Check deployment status
az deployment group list \
    --resource-group rg-realtime-chat-dev \
    --output table

# Verify OpenAI model deployments
az cognitiveservices account deployment list \
    --name $(az deployment group show --resource-group rg-realtime-chat-dev --name main --query 'properties.outputs.openAIServiceName.value' -o tsv) \
    --resource-group rg-realtime-chat-dev \
    --output table
```

## Parameters Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `namePrefix` | string | `realtimechat` | Prefix for all resource names |
| `location` | string | `resourceGroup().location` | Deployment region (eastus2 or swedencentral recommended) |
| `environment` | string | `dev` | Environment tag (dev/test/prod) |
| `openAICustomDomain` | string | `auto-generated` | Custom domain for Azure OpenAI service |
| `openAISku` | string | `S0` | SKU for Azure OpenAI service |
| `signalRSku` | string | `Standard_S1` | SKU for SignalR Service |
| `modelCapacity` | int | `10` | Capacity for each OpenAI model deployment |
| `enableAppInsights` | bool | `true` | Enable Application Insights monitoring |
| `tags` | object | `default tags` | Resource tags for organization |

## Key Features

### Intelligent Model Routing
- **Cost Optimization**: Automatically routes simple queries to GPT-4o-mini (60% cost savings)
- **Performance**: Complex queries use GPT-4o-realtime for superior capability
- **Complexity Analysis**: Built-in algorithm analyzes message content and context

### Security Features
- **Managed Identity**: Secure access between services without storing credentials
- **RBAC Integration**: Proper role assignments for least privilege access
- **HTTPS Only**: All communication encrypted in transit
- **Key Vault Ready**: Architecture supports Azure Key Vault integration

### Monitoring and Operations
- **Application Insights**: Comprehensive monitoring and analytics
- **Structured Logging**: SignalR and Function App logging enabled
- **Cost Tracking**: Resource tagging for cost allocation
- **Performance Metrics**: Built-in performance monitoring

## Post-Deployment Steps

### 1. Deploy Function Code

After infrastructure deployment, you need to deploy the Function App code:

```bash
# Get Function App name from deployment outputs
FUNCTION_APP_NAME=$(az deployment group show \
    --resource-group rg-realtime-chat-dev \
    --name main \
    --query 'properties.outputs.functionAppName.value' \
    --output tsv)

# Create function project (see main recipe for complete code)
mkdir chat-router-functions
cd chat-router-functions

# Initialize function project
func init --worker-runtime node --language javascript

# Create functions (ModelRouter, SignalRInfo, SignalRMessages)
# ... (see recipe for complete function implementation)

# Deploy function code
func azure functionapp publish $FUNCTION_APP_NAME
```

### 2. Test Model Routing

```bash
# Get Function App URL
FUNCTION_URL=$(az deployment group show \
    --resource-group rg-realtime-chat-dev \
    --name main \
    --query 'properties.outputs.functionAppUrl.value' \
    --output tsv)

# Test simple query routing (should use gpt-4o-mini)
curl -X POST "$FUNCTION_URL/api/ModelRouter" \
    -H "Content-Type: application/json" \
    -d '{"message":"Hello, how are you?","userId":"test-user","sessionId":"test-session"}'

# Test complex query routing (should use gpt-4o)
curl -X POST "$FUNCTION_URL/api/ModelRouter" \
    -H "Content-Type: application/json" \
    -d '{"message":"Explain distributed microservices architecture","userId":"test-user","sessionId":"test-session"}'
```

### 3. Monitor Performance

```bash
# View Application Insights data
az monitor app-insights query \
    --app $(az deployment group show --resource-group rg-realtime-chat-dev --name main --query 'properties.outputs.appInsightsKey.value' -o tsv) \
    --analytics-query "requests | limit 10"
```

## Outputs Reference

The template provides the following outputs for integration:

| Output | Description | Usage |
|--------|-------------|-------|
| `openAIEndpoint` | Azure OpenAI service URL | Configure client applications |
| `signalRConnectionString` | SignalR connection string | Client app configuration |
| `functionAppUrl` | Function App base URL | API endpoint base |
| `modelRouterEndpoint` | Model routing API endpoint | Direct API access |
| `webRTCEndpoint` | Regional WebRTC endpoint | Client WebRTC configuration |
| `deployedModels` | Model deployment details | Validation and monitoring |

## Cost Management

### Estimated Monthly Costs (East US 2)

| Service | Configuration | Estimated Cost |
|---------|---------------|----------------|
| Azure OpenAI | 2 models, 10 capacity each | $50-200/month |
| SignalR Service | Standard S1 | $50/month |
| Function App | Consumption plan | $5-20/month |
| Storage Account | Standard LRS | $2/month |
| Application Insights | Standard | $10-30/month |
| **Total** | | **$117-302/month** |

### Cost Optimization Tips

1. **Monitor Usage**: Use Application Insights to track model selection patterns
2. **Adjust Capacity**: Scale model capacity based on actual demand
3. **Review Complexity Thresholds**: Fine-tune routing logic for cost savings
4. **Use Free Tier**: SignalR Free_F1 for development environments

## Security Considerations

### Network Security
- All services use HTTPS/TLS encryption
- Public network access can be restricted via parameters
- SignalR CORS configured for specific origins

### Identity and Access
- Managed Identity for service-to-service authentication
- Role-based access control (RBAC) implemented
- API keys stored securely in Function App settings

### Data Protection
- No persistent storage of conversation data by default
- Ephemeral tokens for WebRTC authentication (1-minute expiry)
- Azure Key Vault integration ready for secrets management

## Troubleshooting

### Common Issues

1. **Model Deployment Failures**
   ```bash
   # Check quota availability
   az cognitiveservices account list-usage \
       --name $OPENAI_SERVICE_NAME \
       --resource-group $RESOURCE_GROUP
   ```

2. **Function App Connection Issues**
   ```bash
   # Verify app settings
   az functionapp config appsettings list \
       --name $FUNCTION_APP_NAME \
       --resource-group $RESOURCE_GROUP
   ```

3. **SignalR Connection Problems**
   ```bash
   # Check SignalR service status
   az signalr show \
       --name $SIGNALR_SERVICE_NAME \
       --resource-group $RESOURCE_GROUP \
       --query "properties.provisioningState"
   ```

### Logs and Diagnostics

```bash
# Function App logs
az functionapp log tail \
    --name $FUNCTION_APP_NAME \
    --resource-group $RESOURCE_GROUP

# Application Insights queries
az monitor app-insights query \
    --app $APP_INSIGHTS_KEY \
    --analytics-query "exceptions | take 10"
```

## Cleanup

To avoid ongoing charges, delete the resource group:

```bash
# Delete resource group and all resources
az group delete \
    --name rg-realtime-chat-dev \
    --yes \
    --no-wait
```

## Support and Documentation

- [Azure OpenAI Realtime API Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/realtime-audio-webrtc)
- [Azure SignalR Service Documentation](https://learn.microsoft.com/en-us/azure/azure-signalr/)
- [Azure Functions Documentation](https://learn.microsoft.com/en-us/azure/azure-functions/)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)

## Contributing

This infrastructure code is part of the Azure Recipes collection. For improvements or issues:

1. Follow the repository contribution guidelines
2. Test changes in a development environment
3. Update documentation for any parameter changes
4. Ensure security best practices are maintained