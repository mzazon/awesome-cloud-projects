# Infrastructure as Code for Intelligent Product Catalog with OpenAI and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Product Catalog with OpenAI and Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys an automated product catalog system that uses:
- Azure Functions triggered by blob uploads
- Azure OpenAI Service's GPT-4o multimodal AI for image analysis
- Azure Blob Storage for scalable file processing
- Serverless architecture for cost-effective scaling

## Prerequisites

### Common Requirements
- Azure CLI installed and configured
- Azure subscription with appropriate permissions
- Azure OpenAI Service access (apply at [aka.ms/oai/access](https://aka.ms/oai/access))
- Basic understanding of Azure services and JSON

### Tool-Specific Requirements

#### For Bicep
- Azure CLI with Bicep extension installed
- Visual Studio Code with Bicep extension (recommended)

#### For Terraform
- Terraform >= 1.0 installed
- Azure CLI authenticated (`az login`)

#### For Bash Scripts
- bash shell environment
- jq installed for JSON processing
- curl for downloading test images

### Required Permissions
- Contributor role on the resource group or subscription
- Cognitive Services Contributor for Azure OpenAI
- Storage Account Contributor for blob storage
- Function App Contributor for Azure Functions

## Quick Start

### Using Bicep (Recommended)

```bash
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-catalog-demo" \
    --template-file main.bicep \
    --parameters location="eastus" \
                 suffix="$(openssl rand -hex 3)"

# The deployment will output the Function App name and storage account details
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="location=eastus"

# Apply the configuration
terraform apply -var="location=eastus"

# Note the outputs for testing
terraform output
```

### Using Bash Scripts

```bash
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy the complete solution
./deploy.sh

# Follow the script prompts for configuration
```

## Configuration Options

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `suffix` | Unique suffix for resource names | Auto-generated | No |
| `environment` | Environment tag (dev/test/prod) | `demo` | No |

### Bicep Parameters

Edit the `main.bicep` file or use parameter files:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "suffix": {
      "value": "prod01"
    },
    "environment": {
      "value": "production"
    }
  }
}
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
location              = "eastus"
resource_group_name   = "rg-catalog-production"
environment          = "production"
openai_model_version = "2024-11-20"
```

## Post-Deployment Setup

After successful deployment, you'll need to:

1. **Verify OpenAI Model Deployment**: The GPT-4o model deployment may take 5-10 minutes to complete.

2. **Test the Function**: Upload a test image to verify the pipeline works:

```bash
# Get storage account name from deployment outputs
STORAGE_ACCOUNT="<from-deployment-outputs>"

# Upload test image
az storage blob upload \
    --account-name ${STORAGE_ACCOUNT} \
    --container-name product-images \
    --name "test-product.jpg" \
    --file ./sample-images/test-product.jpg
```

3. **Monitor Function Execution**: Check the Function App logs to verify processing:

```bash
# Get Function App name from deployment outputs
FUNCTION_APP="<from-deployment-outputs>"

# View logs
az functionapp logs tail \
    --name ${FUNCTION_APP} \
    --resource-group ${RESOURCE_GROUP}
```

4. **Verify Results**: Check for generated catalog data:

```bash
# List results
az storage blob list \
    --account-name ${STORAGE_ACCOUNT} \
    --container-name catalog-results \
    --output table

# Download and view a result
az storage blob download \
    --account-name ${STORAGE_ACCOUNT} \
    --container-name catalog-results \
    --name "test-product.jpg.json" \
    --file result.json

cat result.json | jq '.'
```

## Testing the Solution

### Upload Sample Images

```bash
# Create test images directory
mkdir -p test-images

# Download sample product images
curl -o test-images/electronics.jpg \
    "https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=500"

curl -o test-images/clothing.jpg \
    "https://images.unsplash.com/photo-1434389677669-e08b4cac3105?w=500"

# Upload to storage
for image in test-images/*.jpg; do
    az storage blob upload \
        --account-name ${STORAGE_ACCOUNT} \
        --container-name product-images \
        --name "$(basename $image)" \
        --file "$image"
done
```

### Expected Output Format

The Function will generate JSON files with this structure:

```json
{
  "product_name": "Wireless Bluetooth Headphones",
  "description": "Premium over-ear wireless headphones with noise cancellation and long battery life.",
  "features": [
    "Bluetooth 5.0 connectivity",
    "Active noise cancellation",
    "30-hour battery life",
    "Foldable design"
  ],
  "category": "Electronics",
  "subcategory": "Audio Equipment",
  "colors": ["Black", "Silver"],
  "materials": ["Plastic", "Metal", "Fabric"],
  "style": "Modern",
  "target_audience": "Tech enthusiasts and professionals",
  "keywords": ["wireless", "headphones", "bluetooth", "noise-cancelling"],
  "estimated_price_range": "mid-range",
  "processing_timestamp": "2025-01-16T10:30:00Z",
  "source_image": "electronics.jpg",
  "image_size_bytes": 45678,
  "model_used": "gpt-4o-deployment"
}
```

## Monitoring and Troubleshooting

### Common Issues

1. **OpenAI API Rate Limits**: Monitor Azure OpenAI usage in the Azure portal
2. **Function Timeout**: Check function execution duration and adjust timeout settings
3. **Storage Connection**: Verify storage account connection strings in Function App settings
4. **Missing Results**: Check Function App logs for processing errors

### Monitoring Resources

```bash
# Check Function App metrics
az monitor metrics list \
    --resource "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/sites/${FUNCTION_APP}" \
    --metric "FunctionExecutionCount"

# Check OpenAI usage
az cognitiveservices account list-usage \
    --name ${OPENAI_ACCOUNT} \
    --resource-group ${RESOURCE_GROUP}
```

### Log Analysis

```bash
# Query Application Insights (if configured)
az monitor app-insights query \
    --app ${FUNCTION_APP} \
    --analytics-query "traces | where message contains 'Processing blob' | take 10"
```

## Cost Optimization

### Estimated Costs (East US region)

- **Azure Functions**: ~$0.000016 per execution (consumption plan)
- **Azure OpenAI**: ~$0.01-0.03 per image analysis
- **Blob Storage**: ~$0.02 per GB stored
- **Total**: ~$0.05-0.10 per product image processed

### Cost Optimization Tips

1. **Use consumption plan** for Azure Functions (included in deployment)
2. **Configure blob lifecycle policies** to archive old images
3. **Monitor OpenAI token usage** and optimize prompts
4. **Use Azure Cost Management** to track spending

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name "rg-catalog-demo" \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
cd scripts/

# Run cleanup script
./destroy.sh

# Follow prompts to confirm deletion
```

### Manual Cleanup Verification

```bash
# Verify resource group deletion
az group exists --name "rg-catalog-demo"

# Should return: false
```

## Customization

### Extending the Solution

1. **Multi-language Support**: Modify the OpenAI prompt in the Function code to generate descriptions in multiple languages

2. **Custom Categories**: Enhance the prompt to include industry-specific categories and terminology

3. **Quality Validation**: Add Azure Cognitive Services Custom Vision for image quality checks before OpenAI processing

4. **Batch Processing**: Implement Azure Durable Functions for processing large image batches

5. **Analytics Dashboard**: Connect to Power BI or Azure Synapse for catalog analytics

### Code Customization

The Function code is deployed as part of the infrastructure. To modify:

1. **Clone the Function code** from the deployment
2. **Modify the prompt or processing logic** in `function_app.py`
3. **Redeploy using Azure Functions Core Tools**:

```bash
func azure functionapp publish ${FUNCTION_APP}
```

## Security Considerations

### Implemented Security Features

- **Private blob containers** with no public access
- **Managed Identity** for Function App authentication
- **Key Vault integration** for sensitive configuration (optional)
- **Network isolation** options available
- **RBAC** for resource access control

### Additional Security Recommendations

1. **Enable Advanced Threat Protection** for storage accounts
2. **Configure Azure Private Link** for OpenAI Service
3. **Implement VNet integration** for Function Apps
4. **Use Azure Key Vault** for OpenAI API keys
5. **Enable audit logging** for all resources

## Support and Documentation

### Azure Documentation References

- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure OpenAI Service Documentation](https://docs.microsoft.com/en-us/azure/ai-services/openai/)
- [Azure Blob Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/blobs/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

### Getting Help

For issues with this infrastructure code:
1. Check the original recipe documentation
2. Review Azure service documentation
3. Consult provider-specific troubleshooting guides
4. Use Azure Support for production issues

### Version Information

- **Recipe Version**: 1.1
- **Last Updated**: 2025-07-12
- **Infrastructure Code Version**: 1.0
- **Supported Azure CLI Version**: >= 2.50.0
- **Supported Terraform Version**: >= 1.0

---

> **Note**: This infrastructure code is generated based on the recipe "Intelligent Product Catalog with OpenAI and Functions". For the complete implementation guide and step-by-step instructions, refer to the original recipe documentation.