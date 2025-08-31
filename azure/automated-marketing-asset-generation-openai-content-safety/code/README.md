# Infrastructure as Code for Automated Marketing Asset Generation with OpenAI and Content Safety

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Marketing Asset Generation with OpenAI and Content Safety".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Appropriate Azure subscription with permissions for:
  - Resource Groups
  - Storage Accounts
  - Azure Functions
  - Cognitive Services (OpenAI and Content Safety)
  - Azure Monitor (Application Insights)
- Access to Azure OpenAI Service (may require approval)
- Basic understanding of serverless functions and AI content generation

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-marketing-ai \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh
```

## Configuration Parameters

### Bicep Parameters

- `location`: Azure region for resource deployment (default: eastus)
- `resourcePrefix`: Prefix for all resource names (default: marketing-ai)
- `storageAccountSku`: Storage account SKU (default: Standard_LRS)
- `functionAppPlan`: Function app hosting plan (default: Y1 - Consumption)
- `openAiSku`: Azure OpenAI service SKU (default: S0)
- `contentSafetySku`: Content Safety service SKU (default: S0)

### Terraform Variables

- `resource_group_name`: Name of the resource group
- `location`: Azure region for deployment
- `storage_account_name`: Unique storage account name
- `function_app_name`: Unique function app name
- `openai_account_name`: Unique OpenAI service name
- `content_safety_account_name`: Unique Content Safety service name

## Post-Deployment Setup

After infrastructure deployment, complete these steps:

1. **Deploy OpenAI Models**:
   ```bash
   # Deploy GPT-4 model
   az cognitiveservices account deployment create \
       --name <openai-account-name> \
       --resource-group <resource-group-name> \
       --deployment-name "gpt-4-marketing" \
       --model-name "gpt-4" \
       --model-version "0613" \
       --model-format "OpenAI" \
       --sku-name "Standard" \
       --sku-capacity 10

   # Deploy DALL-E 3 model
   az cognitiveservices account deployment create \
       --name <openai-account-name> \
       --resource-group <resource-group-name> \
       --deployment-name "dalle-3-marketing" \
       --model-name "dall-e-3" \
       --model-version "3.0" \
       --model-format "OpenAI" \
       --sku-name "Standard" \
       --sku-capacity 1
   ```

2. **Deploy Function Code**:
   ```bash
   # Package and deploy the marketing function
   cd ../function-code/
   zip -r marketing-function.zip . -x "*.git*" "*.DS_Store*"
   
   az functionapp deployment source config-zip \
       --resource-group <resource-group-name> \
       --name <function-app-name> \
       --src marketing-function.zip
   ```

3. **Test the Solution**:
   ```bash
   # Upload a test marketing request
   az storage blob upload \
       --account-name <storage-account-name> \
       --container-name "marketing-requests" \
       --name "test-request.json" \
       --file test-marketing-request.json
   ```

## Testing

### Sample Marketing Request

Create a test file `test-marketing-request.json`:

```json
{
  "campaign_id": "summer-2025-launch",
  "generate_text": true,
  "text_prompt": "Create an engaging social media post for a summer product launch featuring sustainable outdoor gear. Include a call-to-action and relevant hashtags.",
  "generate_image": true,
  "image_prompt": "A vibrant summer scene with eco-friendly outdoor gear including backpacks and water bottles, natural lighting, professional marketing photography style"
}
```

### Validation Commands

```bash
# Check function logs
az monitor log-analytics query \
    --workspace <workspace-id> \
    --analytics-query "traces | where cloud_RoleName == '<function-app-name>' | order by timestamp desc | take 10"

# List generated marketing assets
az storage blob list \
    --account-name <storage-account-name> \
    --container-name "marketing-assets" \
    --output table

# Download generated content for review
az storage blob download \
    --account-name <storage-account-name> \
    --container-name "marketing-assets" \
    --name "text/summer-2025-launch.txt" \
    --file generated-content.txt
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-marketing-ai \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

## Cost Optimization

- **Azure Functions**: Uses consumption plan - pay per execution
- **Storage Account**: Hot tier for active assets, consider lifecycle policies
- **Azure OpenAI**: Monitor token usage and adjust model capacity
- **Content Safety**: Pay per API call - optimize batch processing

## Security Considerations

- Function app uses system-assigned managed identity
- Storage containers have appropriate access levels
- API keys stored securely in Function App settings
- Content Safety provides additional security layer
- All generated content is validated before storage

## Troubleshooting

### Common Issues

1. **OpenAI Access Denied**: Ensure Azure OpenAI access is approved for your subscription
2. **Function Deployment Fails**: Check Function App settings and dependencies
3. **Storage Access Issues**: Verify storage account permissions and connection strings
4. **Content Safety Errors**: Confirm Content Safety service is properly configured

### Debug Commands

```bash
# Check resource deployment status
az deployment group show \
    --resource-group <resource-group-name> \
    --name <deployment-name>

# View function app logs
az functionapp log tail \
    --name <function-app-name> \
    --resource-group <resource-group-name>

# Test storage connectivity
az storage account check-name \
    --name <storage-account-name>
```

## Customization

### Environment-Specific Configuration

- Modify `parameters.json` (Bicep) or `terraform.tfvars` (Terraform) for different environments
- Adjust Content Safety thresholds in function code for brand-specific requirements
- Configure custom OpenAI prompts for consistent brand voice
- Implement additional storage containers for content workflows

### Extensions

- Add Azure Logic Apps for approval workflows
- Integrate with Power BI for content analytics
- Connect to Azure Event Grid for real-time notifications
- Implement Azure Key Vault for enhanced secret management

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service documentation:
   - [Azure OpenAI Service](https://learn.microsoft.com/en-us/azure/ai-services/openai/overview)
   - [Azure AI Content Safety](https://learn.microsoft.com/en-us/azure/ai-services/content-safety/overview)
   - [Azure Functions](https://learn.microsoft.com/en-us/azure/azure-functions/)
   - [Azure Blob Storage](https://learn.microsoft.com/en-us/azure/storage/blobs/)
3. Consult Azure support for service-specific issues
4. Review function logs for application-level troubleshooting

## Architecture Overview

The deployed infrastructure creates:

- **Resource Group**: Container for all marketing automation resources
- **Storage Account**: Three containers for request processing and asset storage
- **Azure Functions App**: Serverless orchestration with blob trigger
- **Azure OpenAI Service**: GPT-4 and DALL-E 3 model deployments
- **Content Safety Service**: Multi-modal content moderation
- **Application Insights**: Function monitoring and analytics

All components are configured with security best practices and automatic scaling capabilities for production marketing workloads.