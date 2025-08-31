# Infrastructure as Code for Real-Time AI Chat with WebRTC and Model Router

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time AI Chat with WebRTC and Model Router".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a real-time AI chat system that intelligently routes conversations between cost-effective GPT-4o-mini and premium GPT-4o models based on complexity analysis. The infrastructure includes:

- Azure OpenAI Service with realtime models (GPT-4o-mini-realtime and GPT-4o-realtime)
- Azure SignalR Service for real-time connection management
- Azure Functions for serverless model routing logic
- Storage Account for function runtime requirements

## Prerequisites

### Azure Requirements
- Azure subscription with contributor permissions
- Azure CLI installed and configured (version 2.50.0 or later)
- Access to Azure OpenAI Service (with GPT-4o realtime models preview)
- Available quota for Azure OpenAI in East US 2 or Sweden Central regions

### Development Tools
- Node.js 18+ for Function App development and testing
- Basic understanding of WebRTC, real-time communication, and Azure services

### Permissions Required
- Microsoft.CognitiveServices/* (for Azure OpenAI)
- Microsoft.SignalRService/* (for SignalR Service)
- Microsoft.Web/* (for Function Apps)
- Microsoft.Storage/* (for Storage Accounts)
- Microsoft.Resources/* (for Resource Groups)

### Cost Estimates
- Estimated cost: $15-25 for testing resources over 2-3 days
- Azure OpenAI: ~$0.001-0.006 per 1K tokens (varies by model)
- SignalR Service: ~$1.00 per unit per day
- Functions: Consumption plan - first 1M executions free
- Storage: ~$0.02 per GB per month

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Create resource group
RESOURCE_GROUP="rg-realtime-chat-demo"
LOCATION="eastus2"
az group create --name $RESOURCE_GROUP --location $LOCATION

# Deploy infrastructure
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters location=$LOCATION

# Get deployment outputs
az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name main \
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

# The script will prompt for required parameters
# Follow the interactive setup process
```

## Configuration Parameters

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus2` | Yes |
| `resourcePrefix` | Prefix for resource naming | `rtchat` | No |
| `openAISkuName` | Azure OpenAI SKU | `S0` | No |
| `signalRSkuTier` | SignalR Service tier | `Standard` | No |
| `signalRSkuSize` | SignalR Service size | `S1` | No |
| `functionAppSku` | Function App hosting plan | `Consumption` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `resource_group_name` | Name of the resource group | `rg-realtime-chat` | No |
| `location` | Azure region | `East US 2` | No |
| `resource_prefix` | Prefix for resource names | `rtchat` | No |
| `openai_sku_name` | OpenAI service SKU | `S0` | No |
| `signalr_sku` | SignalR service SKU | `Standard_S1` | No |
| `tags` | Resource tags | `{}` | No |

## Deployment Steps

### 1. Pre-deployment Validation

```bash
# Verify Azure CLI authentication
az account show

# Check available locations for Azure OpenAI
az cognitiveservices account list-skus \
    --kind OpenAI \
    --query "[?contains(locations, 'eastus2')]"

# Validate resource provider registrations
az provider show --namespace Microsoft.CognitiveServices --query registrationState
az provider show --namespace Microsoft.SignalRService --query registrationState
az provider show --namespace Microsoft.Web --query registrationState
```

### 2. Infrastructure Deployment

The deployment process creates resources in the following order:
1. Resource Group (if using scripts)
2. Azure OpenAI Service
3. Storage Account for Function App
4. Azure SignalR Service
5. Function App with system-assigned managed identity
6. Model deployments (GPT-4o-mini-realtime and GPT-4o-realtime)

### 3. Post-deployment Configuration

After infrastructure deployment, you'll need to:

1. **Deploy Function Code**:
   ```bash
   # Package and deploy the Function App code
   cd ../functions/
   zip -r ../deployment-package.zip . -x "node_modules/.bin/*"
   
   # Deploy to Function App
   az functionapp deployment source config-zip \
       --resource-group $RESOURCE_GROUP \
       --name $FUNCTION_APP_NAME \
       --src ../deployment-package.zip
   ```

2. **Configure Application Settings**:
   ```bash
   # Set runtime configuration
   az functionapp config appsettings set \
       --name $FUNCTION_APP_NAME \
       --resource-group $RESOURCE_GROUP \
       --settings "WEBSITE_RUN_FROM_PACKAGE=1"
   ```

## Validation & Testing

### 1. Verify Resource Deployment

```bash
# Check all resources are created
az resource list \
    --resource-group $RESOURCE_GROUP \
    --output table

# Verify OpenAI models are deployed
az cognitiveservices account deployment list \
    --name $OPENAI_SERVICE_NAME \
    --resource-group $RESOURCE_GROUP \
    --output table
```

### 2. Test Function Endpoints

```bash
# Get Function App URL
FUNCTION_URL=$(az functionapp show \
    --name $FUNCTION_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --query defaultHostName \
    --output tsv)

# Test model router endpoint
curl -X POST "https://$FUNCTION_URL/api/ModelRouter" \
    -H "Content-Type: application/json" \
    -d '{"message":"Hello, how are you?","userId":"test-user","sessionId":"test-session"}'
```

### 3. Validate SignalR Connection

```bash
# Test SignalR connection info endpoint
curl -X POST "https://$FUNCTION_URL/api/SignalRInfo" \
    -H "Content-Type: application/json" \
    -d '{}'
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow interactive prompts to confirm deletion
```

## Customization

### Model Configuration

To modify the AI models used:

1. **Update model deployments** in the IaC templates
2. **Adjust complexity analysis** in the Function App code
3. **Modify routing logic** to support additional models

### Scaling Configuration

To handle higher loads:

1. **Increase SignalR Service tier** (`Standard_S1` → `Premium_P1`)
2. **Scale Function App** to Dedicated hosting plan
3. **Adjust OpenAI model capacity** (increase `sku-capacity`)

### Security Hardening

For production deployments:

1. **Enable private endpoints** for Azure OpenAI and SignalR
2. **Configure Function App authentication** with Azure AD
3. **Implement API key rotation** for enhanced security
4. **Enable diagnostic logging** for all services

### Regional Deployment

To deploy in different regions:

1. **Verify model availability** in target region
2. **Update location parameters** in IaC templates
3. **Adjust WebRTC endpoints** in Function App code

## Monitoring and Troubleshooting

### Application Insights Integration

```bash
# Enable Application Insights for Function App
az monitor app-insights component create \
    --app myapp-insights \
    --location $LOCATION \
    --resource-group $RESOURCE_GROUP

# Link to Function App
az functionapp config appsettings set \
    --name $FUNCTION_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --settings "APPINSIGHTS_INSTRUMENTATIONKEY=$(az monitor app-insights component show --app myapp-insights --resource-group $RESOURCE_GROUP --query instrumentationKey -o tsv)"
```

### Common Issues

1. **Model deployment failures**: Verify region supports realtime models
2. **Function timeout errors**: Increase Function App timeout settings
3. **SignalR connection issues**: Check service mode is set to "Serverless"
4. **WebRTC authentication failures**: Verify ephemeral token generation

### Diagnostic Commands

```bash
# Check Function App logs
az functionapp log tail --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP

# View SignalR Service metrics
az signalr show --name $SIGNALR_SERVICE_NAME --resource-group $RESOURCE_GROUP

# Monitor OpenAI service usage
az cognitiveservices account show --name $OPENAI_SERVICE_NAME --resource-group $RESOURCE_GROUP
```

## Support

### Documentation References

- [Azure OpenAI Realtime API Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/realtime-audio-webrtc)
- [Azure SignalR Service Architecture](https://learn.microsoft.com/en-us/azure/azure-signalr/signalr-concept-azure-functions)
- [Azure Functions Best Practices](https://learn.microsoft.com/en-us/azure/azure-functions/functions-best-practices)
- [Bicep Language Reference](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

### Getting Help

For issues with this infrastructure code:

1. **Check the troubleshooting section** above
2. **Review the original recipe documentation** for implementation details
3. **Consult Azure service documentation** for specific service issues
4. **Check Azure service health** for regional outages
5. **Review deployment logs** for specific error messages

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate against Azure best practices
3. Update documentation for any parameter changes
4. Ensure cleanup scripts remove all created resources