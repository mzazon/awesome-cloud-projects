# Infrastructure as Code for Product Description Generation with AI Vision and OpenAI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Product Description Generation with AI Vision and OpenAI".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Appropriate Azure permissions for resource creation:
  - Contributor role on subscription or resource group
  - Cognitive Services Contributor role
  - Storage Account Contributor role
  - Website Contributor role (for Function Apps)
- For Terraform: Terraform CLI installed (>= 1.0)
- For Bicep: Bicep CLI installed (latest version)

## Architecture Overview

This solution deploys an event-driven AI pipeline that automatically generates product descriptions by:

1. **Storage Layer**: Azure Blob Storage with containers for input images and output descriptions
2. **AI Services**: Azure AI Vision for image analysis and Azure OpenAI Service for text generation
3. **Processing Engine**: Azure Functions with Python runtime for orchestrating the AI pipeline
4. **Event Integration**: Event Grid subscription for real-time processing triggers

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters projectName=prodDesc

# Note: OpenAI service requires manual approval in some regions
# Check deployment status
az deployment group show \
    --resource-group myResourceGroup \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# Confirm deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for resource naming and configuration
```

## Configuration Parameters

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `projectName` | string | - | Prefix for all resource names |
| `location` | string | `eastus` | Azure region for deployment |
| `storageAccountTier` | string | `Standard_LRS` | Storage account replication type |
| `functionAppPlan` | string | `Consumption` | Function App Service Plan |
| `aiVisionSku` | string | `S1` | AI Vision service pricing tier |
| `openAiSku` | string | `S0` | OpenAI service pricing tier |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `resource_group_name` | string | - | Name of the resource group |
| `location` | string | `East US` | Azure region for deployment |
| `project_name` | string | - | Prefix for all resource names |
| `storage_account_tier` | string | `Standard_LRS` | Storage account replication type |
| `ai_vision_sku` | string | `S1` | AI Vision service pricing tier |
| `openai_sku` | string | `S0` | OpenAI service pricing tier |

## Post-Deployment Configuration

### 1. Deploy OpenAI Model

After infrastructure deployment, deploy the GPT-4o model:

```bash
# Get OpenAI service name from deployment outputs
OPENAI_NAME=$(az deployment group show \
    --resource-group myResourceGroup \
    --name main \
    --query properties.outputs.openaiServiceName.value -o tsv)

# Deploy GPT-4o model
az cognitiveservices account deployment create \
    --name $OPENAI_NAME \
    --resource-group myResourceGroup \
    --deployment-name gpt-4o \
    --model-name gpt-4o \
    --model-version "2024-11-20" \
    --model-format OpenAI \
    --sku-capacity 10 \
    --sku-name Standard
```

### 2. Deploy Function Code

```bash
# Get Function App name from deployment outputs
FUNCTION_APP=$(az deployment group show \
    --resource-group myResourceGroup \
    --name main \
    --query properties.outputs.functionAppName.value -o tsv)

# Deploy function code (assumes code package is available)
az functionapp deployment source config-zip \
    --name $FUNCTION_APP \
    --resource-group myResourceGroup \
    --src function-code.zip
```

### 3. Test the Solution

```bash
# Get storage account name
STORAGE_ACCOUNT=$(az deployment group show \
    --resource-group myResourceGroup \
    --name main \
    --query properties.outputs.storageAccountName.value -o tsv)

# Upload test image
az storage blob upload \
    --account-name $STORAGE_ACCOUNT \
    --container-name product-images \
    --name test-product.jpg \
    --file /path/to/test-image.jpg \
    --auth-mode login

# Check generated description (after processing)
az storage blob download \
    --account-name $STORAGE_ACCOUNT \
    --container-name descriptions \
    --name description_test-product.json \
    --file generated-description.json \
    --auth-mode login
```

## Resource Details

### Created Resources

1. **Resource Group**: Container for all solution resources
2. **Storage Account**: Blob storage for images and descriptions
   - Container: `product-images` (input images)
   - Container: `descriptions` (generated content)
3. **AI Vision Service**: Computer vision analysis
4. **OpenAI Service**: GPT-4o model for text generation
5. **Function App**: Serverless processing engine
6. **Application Insights**: Monitoring and logging
7. **Event Grid**: Event-driven processing triggers

### Security Configuration

- **Managed Identity**: Function App uses system-assigned managed identity
- **RBAC**: Minimal required permissions assigned to managed identity
- **Key Vault**: Secrets stored securely (if using Bicep advanced configuration)
- **Network Security**: Storage account allows Function App access
- **API Keys**: Stored in Function App application settings

## Monitoring and Troubleshooting

### View Function Logs

```bash
# Stream function logs
az functionapp logs tail \
    --name $FUNCTION_APP \
    --resource-group myResourceGroup
```

### Check Application Insights

```bash
# Get Application Insights name
APP_INSIGHTS=$(az deployment group show \
    --resource-group myResourceGroup \
    --name main \
    --query properties.outputs.applicationInsightsName.value -o tsv)

# Query recent function executions
az monitor app-insights query \
    --app $APP_INSIGHTS \
    --analytics-query "requests | where timestamp > ago(1h) | order by timestamp desc"
```

### Validate Event Grid Subscription

```bash
# List Event Grid subscriptions
az eventgrid event-subscription list \
    --source-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/myResourceGroup/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"
```

## Cost Optimization

### Estimated Costs (per month)

- **Storage Account**: $1-5 (depending on data volume)
- **Function App**: $0-10 (consumption plan, execution-based)
- **AI Vision**: $1-15 (S1 tier, per 1000 transactions)
- **OpenAI Service**: $10-50 (depending on token usage)
- **Application Insights**: $0-5 (basic tier)

### Cost Management

- Monitor AI service usage through Azure Cost Management
- Implement request throttling for high-volume scenarios
- Use consumption-based Function App plan for variable workloads
- Archive old descriptions to cool storage tier

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name myResourceGroup \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Customization

### Environment-Specific Configuration

1. **Development**: Use Basic tier services and minimal capacity
2. **Production**: Enable geo-redundant storage and higher AI service tiers
3. **Multi-Region**: Deploy to multiple regions with traffic distribution

### Advanced Features

1. **Batch Processing**: Modify function to process multiple images
2. **Approval Workflow**: Add Logic Apps for human review
3. **Multi-Language**: Integrate Azure Translator service
4. **Custom Models**: Use Azure Machine Learning for specialized recognition

## Troubleshooting

### Common Issues

1. **OpenAI Service Access Denied**
   - Ensure your subscription has OpenAI service access approved
   - Check service availability in your selected region

2. **Function App Deployment Failures**
   - Verify storage account connectivity
   - Check Application Insights configuration
   - Review Function App logs for specific errors

3. **Event Grid Not Triggering**
   - Validate Event Grid subscription status
   - Check blob container name matches configuration
   - Verify storage account event settings

4. **AI Service Authentication Errors**
   - Confirm service keys are correctly configured
   - Verify managed identity has required permissions
   - Check service endpoint URLs

### Debug Commands

```bash
# Check resource deployment status
az deployment group show \
    --resource-group myResourceGroup \
    --name main \
    --query properties.provisioningState

# Validate Function App configuration
az functionapp config show \
    --name $FUNCTION_APP \
    --resource-group myResourceGroup

# Test storage account connectivity
az storage account show-connection-string \
    --name $STORAGE_ACCOUNT \
    --resource-group myResourceGroup
```

## Support

- **Azure Documentation**: [Azure Functions](https://docs.microsoft.com/en-us/azure/azure-functions/)
- **AI Services**: [Azure AI Vision](https://docs.microsoft.com/en-us/azure/cognitive-services/computer-vision/) and [Azure OpenAI](https://docs.microsoft.com/en-us/azure/cognitive-services/openai/)
- **Infrastructure**: [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/) and [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)

For issues with this infrastructure code, refer to the original recipe documentation or the provider's documentation.