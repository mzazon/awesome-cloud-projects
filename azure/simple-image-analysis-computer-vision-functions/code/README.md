# Infrastructure as Code for Simple Image Analysis with Computer Vision and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Image Analysis with Computer Vision and Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.50.0 or later)
- Azure subscription with appropriate permissions for:
  - Creating resource groups
  - Creating Azure Functions
  - Creating Storage Accounts
  - Creating Cognitive Services (Computer Vision)
- Azure Functions Core Tools version 4.0.5095 or later (for local development)
- Python 3.11 runtime for Azure Functions
- Appropriate Azure permissions for resource creation
- Estimated cost: $1-5 per month for development and testing

## Quick Start

### Using Bicep

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-image-analysis \
    --template-file bicep/main.bicep \
    --parameters location=eastus

# Deploy the function code (requires Azure Functions Core Tools)
cd ../function-code/
func azure functionapp publish <function-app-name>
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# Note the output values for function deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy everything (infrastructure + function code)
./scripts/deploy.sh

# The script will prompt for required parameters or use environment variables
```

## Architecture Overview

This solution deploys:

1. **Resource Group**: Container for all Azure resources
2. **Azure Computer Vision Service**: AI service for image analysis (F0 free tier)
3. **Storage Account**: Required for Azure Functions runtime
4. **Azure Function App**: Serverless compute with Python 3.11 runtime
5. **Function Configuration**: Application settings for Computer Vision integration

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | No |
| `resourcePrefix` | Prefix for resource names | `imganalysis` | No |
| `functionAppName` | Custom Function App name | Auto-generated | No |
| `computerVisionTier` | Computer Vision pricing tier | `F0` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for deployment | `East US` | No |
| `resource_prefix` | Prefix for resource names | `imganalysis` | No |
| `environment` | Environment tag | `demo` | No |
| `computer_vision_sku` | Computer Vision SKU | `F0` | No |

### Environment Variables (Bash Scripts)

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `AZURE_LOCATION` | Azure region | `eastus` | No |
| `RESOURCE_PREFIX` | Resource name prefix | `imganalysis` | No |
| `SUBSCRIPTION_ID` | Azure subscription ID | Current subscription | No |

## Function Code Deployment

After infrastructure deployment, you'll need to deploy the function code:

### Manual Deployment

```bash
# Navigate to function code directory
cd function-code/

# Install dependencies locally (optional for testing)
pip install -r requirements.txt

# Deploy to Azure Function App
func azure functionapp publish <function-app-name>
```

### Automated Deployment (using deploy.sh)

The bash deployment script automatically handles both infrastructure and function code deployment.

## Testing the Deployment

### Health Check

```bash
# Test the health endpoint
curl "https://<function-app-name>.azurewebsites.net/api/health"
```

Expected response:
```json
{
  "status": "healthy",
  "service": "image-analysis"
}
```

### Image Analysis Test

```bash
# Test with image file upload
curl -X POST \
    -F "image=@test-image.jpg" \
    "https://<function-app-name>.azurewebsites.net/api/analyze"

# Test with base64 encoded image (JSON)
curl -X POST \
    -H "Content-Type: application/json" \
    -d '{"image_base64":"<base64-encoded-image>"}' \
    "https://<function-app-name>.azurewebsites.net/api/analyze"
```

Expected response:
```json
{
  "success": true,
  "analysis": {
    "description": {
      "text": "a description of the image",
      "confidence": 0.85
    },
    "text": [
      {
        "text": "extracted text",
        "bounding_box": [...]
      }
    ],
    "tags": [...],
    "objects": [...],
    "people": [...]
  }
}
```

## Monitoring and Logging

### Azure Portal

1. Navigate to your Function App in the Azure Portal
2. Use **Functions** → **Monitor** to view execution logs
3. Use **Application Insights** for detailed telemetry (if enabled)

### CLI Monitoring

```bash
# View Function App logs
az functionapp log tail \
    --name <function-app-name> \
    --resource-group <resource-group-name>

# Check Computer Vision service usage
az cognitiveservices account show \
    --name <computer-vision-name> \
    --resource-group <resource-group-name>
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-image-analysis \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirms before deletion and provides progress updates
```

## Customization

### Scaling Configuration

To modify the Function App scaling behavior, update the hosting plan in your IaC:

**Bicep:**
```bicep
// Change from Consumption to Premium plan for better performance
functionApp: {
  kind: 'FunctionApp'
  sku: {
    name: 'EP1'  // Elastic Premium
    tier: 'ElasticPremium'
  }
}
```

**Terraform:**
```hcl
// Modify the App Service Plan
resource "azurerm_service_plan" "main" {
  os_type  = "Linux"
  sku_name = "EP1"  # Elastic Premium
}
```

### Computer Vision Features

To modify which Computer Vision features are used, update the function code in `function_app.py`:

```python
# Modify the visual_features list
visual_features=[
    VisualFeatures.CAPTION,     # Image description
    VisualFeatures.READ,        # Text extraction (OCR)
    VisualFeatures.TAGS,        # Object/concept tags
    VisualFeatures.OBJECTS,     # Object detection
    VisualFeatures.PEOPLE,      # People detection
    VisualFeatures.BRANDS,      # Brand detection (add this)
    VisualFeatures.FACES,       # Face detection (add this)
]
```

### Security Enhancements

For production deployments, consider these security improvements:

1. **Enable HTTPS only:**
   ```bicep
   httpsOnly: true
   ```

2. **Configure Function authentication:**
   ```bicep
   authSettings: {
     enabled: true
     defaultProvider: 'AzureActiveDirectory'
   }
   ```

3. **Use Azure Key Vault for secrets:**
   ```bicep
   // Reference Key Vault secrets in app settings
   appSettings: [
     {
       name: 'COMPUTER_VISION_KEY'
       value: '@Microsoft.KeyVault(SecretUri=...)'
     }
   ]
   ```

## Cost Optimization

### Development/Testing

- Uses **F0 (Free)** tier for Computer Vision (5,000 transactions/month)
- Uses **Consumption Plan** for Functions (pay-per-execution)
- Uses **Standard_LRS** storage (lowest cost option)

### Production Considerations

- Monitor Computer Vision usage and upgrade to **S1** tier if needed
- Consider **Premium Functions plan** for consistent performance
- Implement **Application Insights** for monitoring (additional cost)
- Use **Reserved Instances** for predictable workloads

## Troubleshooting

### Common Issues

1. **Function deployment fails:**
   ```bash
   # Check Function App status
   az functionapp show \
       --name <function-app-name> \
       --resource-group <resource-group-name> \
       --query "state"
   ```

2. **Computer Vision authentication errors:**
   ```bash
   # Verify Computer Vision key is set correctly
   az functionapp config appsettings list \
       --name <function-app-name> \
       --resource-group <resource-group-name> \
       --query "[?name=='COMPUTER_VISION_KEY']"
   ```

3. **Function returns 500 errors:**
   ```bash
   # Check function logs for detailed error messages
   az functionapp log tail \
       --name <function-app-name> \
       --resource-group <resource-group-name>
   ```

### Error Codes

| Error | Description | Solution |
|-------|-------------|----------|
| 400 | Invalid image format | Ensure image is in supported format (JPG, PNG, BMP, GIF) |
| 401 | Authentication failed | Verify Computer Vision key in Function App settings |
| 403 | Quota exceeded | Check Computer Vision usage or upgrade tier |
| 500 | Internal server error | Check function logs for detailed error information |

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Azure Documentation**: [Azure Functions](https://docs.microsoft.com/en-us/azure/azure-functions/) and [Computer Vision](https://docs.microsoft.com/en-us/azure/cognitive-services/computer-vision/)
3. **GitHub Issues**: Report infrastructure-specific issues in the repository
4. **Azure Support**: For Azure service-specific issues

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate with both Bicep and Terraform implementations
3. Update documentation and examples
4. Ensure cleanup scripts work correctly
5. Follow Azure naming conventions and best practices