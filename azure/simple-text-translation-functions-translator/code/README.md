# Infrastructure as Code for Simple Text Translation with Functions and Translator

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Text Translation with Functions and Translator".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (declarative ARM templates)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az --version`)
- Azure subscription with appropriate permissions for:
  - Creating resource groups
  - Deploying Azure Functions and App Service Plans
  - Creating Azure AI Translator (Cognitive Services)
  - Creating Storage Accounts
  - Managing Application Insights
- For Terraform: Terraform CLI installed (version >= 1.0)
- For Bicep: Azure CLI with Bicep extension (`az bicep install`)
- Bash shell environment (Linux, macOS, or WSL on Windows)

## Architecture Overview

This implementation deploys:
- Azure Functions with HTTP trigger for translation API
- Azure AI Translator service for text translation capabilities
- Azure Storage Account for Function App requirements
- Application Insights for monitoring and logging
- Resource Group to contain all resources

## Quick Start

### Using Bicep

```bash
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-translation-demo" \
    --template-file main.bicep \
    --parameters location="eastus" \
                 environment="demo" \
                 appName="translate-$(openssl rand -hex 3)"

# Get the Function App URL
az functionapp function show \
    --resource-group "rg-translation-demo" \
    --name "translate-func-$(openssl rand -hex 3)" \
    --function-name "index" \
    --query "invokeUrlTemplate" \
    --output tsv
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned deployment
terraform plan

# Deploy the infrastructure
terraform apply

# Get outputs including Function URL
terraform output function_url
terraform output translator_endpoint
```

### Using Bash Scripts

```bash
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy the complete solution
./deploy.sh

# The script will output the Function URL and test commands
```

## Testing the Deployment

Once deployed, test your translation API:

```bash
# Test English to Spanish translation
curl -X POST "YOUR_FUNCTION_URL" \
    -H "Content-Type: application/json" \
    -d '{
        "text": "Hello, how are you today?",
        "to": "es"
    }'

# Test with source language specified
curl -X POST "YOUR_FUNCTION_URL" \
    -H "Content-Type: application/json" \
    -d '{
        "text": "Bonjour le monde",
        "from": "fr",
        "to": "en"
    }'

# Test multiple language support
curl -X POST "YOUR_FUNCTION_URL" \
    -H "Content-Type: application/json" \
    -d '{
        "text": "Welcome to our global marketplace",
        "to": "de"
    }'
```

Expected response format:
```json
{
  "original": "Hello, how are you today?",
  "translated": "Hola, ¿cómo estás hoy?",
  "from": "en",
  "to": "es",
  "confidence": 1.0
}
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | No |
| `environment` | Environment tag (dev/test/prod) | `dev` | No |
| `appName` | Base name for resources | `translate-app` | No |
| `translatorSku` | Translator service tier | `F0` | No |
| `functionAppSku` | Function App service plan | `Dynamic` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for deployment | `East US` | No |
| `resource_group_name` | Resource group name | `rg-translation-demo` | No |
| `app_name` | Base name for resources | Generated randomly | No |
| `environment` | Environment tag | `demo` | No |
| `translator_sku` | Translator service tier | `F0` | No |

### Environment Variables (Scripts)

The bash scripts use these environment variables (auto-generated if not set):

- `RESOURCE_GROUP`: Resource group name
- `LOCATION`: Azure region
- `APP_NAME`: Base name for resources
- `ENVIRONMENT`: Environment tag

## Cost Estimation

This solution uses Azure's pay-per-use pricing model:

- **Azure Functions**: Consumption Plan (~$0.01 USD for testing)
  - First 1M executions free per month
  - $0.20 per million executions thereafter
- **Azure AI Translator**: F0 (Free) tier
  - 2M characters free per month
  - Standard tier: $10 per million characters
- **Storage Account**: Standard LRS (~$0.02 USD per month)
- **Application Insights**: First 5GB free per month

**Estimated monthly cost for low usage**: $0.01 - $0.10 USD

## Security Considerations

This implementation follows Azure security best practices:

- **Function Authentication**: Uses function-level keys for API access
- **Key Management**: Translator keys stored securely in Function App settings
- **HTTPS Only**: All endpoints use HTTPS encryption
- **Least Privilege**: Minimal required permissions assigned
- **Resource Isolation**: Resources deployed in dedicated resource group

For production deployments, consider:
- Integrating Azure Key Vault for secret management
- Implementing Azure API Management for advanced security
- Adding Azure Active Directory authentication
- Enabling Advanced Threat Protection

## Monitoring and Logging

Application Insights is automatically configured to provide:

- **Function Execution Metrics**: Duration, success/failure rates
- **Translation API Usage**: Request counts and response times
- **Error Tracking**: Detailed error logs and stack traces
- **Performance Monitoring**: Dependency calls and performance bottlenecks

Access monitoring through:
```bash
# Get Application Insights resource
az monitor app-insights component show \
    --resource-group YOUR_RESOURCE_GROUP \
    --app YOUR_APP_NAME
```

## Troubleshooting

### Common Issues

1. **Function App Not Responding**
   ```bash
   # Check Function App status
   az functionapp show \
       --resource-group YOUR_RESOURCE_GROUP \
       --name YOUR_FUNCTION_APP \
       --query "state"
   ```

2. **Translation API Errors**
   ```bash
   # Verify Translator service status
   az cognitiveservices account show \
       --resource-group YOUR_RESOURCE_GROUP \
       --name YOUR_TRANSLATOR_NAME \
       --query "properties.provisioningState"
   ```

3. **Missing Function Code**
   ```bash
   # Redeploy function code
   az functionapp deployment source config-zip \
       --resource-group YOUR_RESOURCE_GROUP \
       --name YOUR_FUNCTION_APP \
       --src function.zip
   ```

### Debug Commands

```bash
# View Function App logs
az functionapp log tail \
    --resource-group YOUR_RESOURCE_GROUP \
    --name YOUR_FUNCTION_APP

# Check Function App configuration
az functionapp config appsettings list \
    --resource-group YOUR_RESOURCE_GROUP \
    --name YOUR_FUNCTION_APP
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name "rg-translation-demo" \
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

# Run the cleanup script
./destroy.sh

# Confirm deletion when prompted
```

## Customization

### Adding Language Detection

Modify the Function code to add a language detection endpoint:

```javascript
// Add to index.js
if (req.url.includes('/detect')) {
    // Language detection logic
    const detectPath = '/detect?api-version=3.0';
    // ... implementation
}
```

### Implementing Caching

Add Azure Redis Cache for translation caching:

```hcl
# Add to Terraform main.tf
resource "azurerm_redis_cache" "translation_cache" {
  name                = "${var.app_name}-cache"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  capacity            = 0
  family              = "C"
  sku_name            = "Basic"
}
```

### Production Hardening

For production deployments:

1. **Use Premium Function Plan** for predictable performance
2. **Implement Azure API Management** for rate limiting and authentication
3. **Add Azure Key Vault** for secure secret storage
4. **Configure custom domains** with SSL certificates
5. **Set up deployment slots** for blue-green deployments

## Support

For issues with this infrastructure code:

1. Review the [original recipe documentation](../simple-text-translation-functions-translator.md)
2. Check [Azure Functions documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
3. Reference [Azure AI Translator documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/translator/)
4. For Terraform issues, see [Azure Provider documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
5. For Bicep issues, see [Bicep documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)

## Contributing

To improve this infrastructure code:

1. Follow Azure naming conventions
2. Implement proper error handling
3. Add comprehensive comments
4. Test in multiple Azure regions
5. Validate against Azure security best practices
6. Update documentation for any changes