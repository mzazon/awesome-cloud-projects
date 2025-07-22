# Infrastructure as Code for Semantic Image Content Discovery with AI Vision

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Semantic Image Content Discovery with AI Vision".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with appropriate permissions
- PowerShell or Bash shell environment
- For Terraform: Terraform CLI v1.0+ installed
- For Bicep: Azure CLI v2.20.0+ (includes Bicep automatically)

### Required Azure Permissions

- Contributor role on the target resource group
- Cognitive Services Contributor for AI Vision service
- Search Service Contributor for Azure AI Search
- Storage Account Contributor for Azure Storage
- Website Contributor for Function App deployment

## Quick Start

### Using Bicep (Recommended)

```bash
# Create resource group
az group create --name rg-image-discovery-demo --location eastus

# Deploy infrastructure
az deployment group create \
    --resource-group rg-image-discovery-demo \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters environmentName=demo

# Get deployment outputs
az deployment group show \
    --resource-group rg-image-discovery-demo \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan -var="location=eastus" -var="environment_name=demo"

# Deploy infrastructure
terraform apply -var="location=eastus" -var="environment_name=demo"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export LOCATION="eastus"
export ENVIRONMENT_NAME="demo"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/status.sh
```

## Architecture Overview

The infrastructure deploys the following Azure resources:

- **Azure Storage Account**: Stores uploaded images and triggers processing
- **Azure AI Vision**: Analyzes image content and extracts metadata
- **Azure AI Search**: Indexes image metadata with vector search capabilities
- **Azure Functions**: Serverless processing pipeline for image analysis
- **Application Insights**: Monitoring and logging for the solution

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `environmentName` | Environment suffix for resources | `demo` | Yes |
| `storageAccountSku` | Storage account performance tier | `Standard_LRS` | No |
| `searchServiceSku` | Search service pricing tier | `basic` | No |
| `visionServiceSku` | AI Vision service tier | `S1` | No |
| `functionAppSku` | Function app hosting plan | `Y1` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `environment_name` | Environment suffix for resources | `demo` | Yes |
| `resource_group_name` | Name of the resource group | `rg-image-discovery-${var.environment_name}` | No |
| `storage_account_tier` | Storage account performance tier | `Standard` | No |
| `search_service_sku` | Search service pricing tier | `basic` | No |
| `vision_service_sku` | AI Vision service tier | `S1` | No |

### Environment Variables (Bash Scripts)

```bash
export LOCATION="eastus"                    # Azure region
export ENVIRONMENT_NAME="demo"              # Environment suffix
export RESOURCE_GROUP="rg-image-discovery-demo"  # Resource group name
export STORAGE_SKU="Standard_LRS"           # Storage performance tier
export SEARCH_SKU="basic"                   # Search service tier
export VISION_SKU="S1"                      # AI Vision service tier
```

## Post-Deployment Configuration

### Function App Deployment

After infrastructure deployment, deploy the image processing function:

```bash
# Get function app name from outputs
FUNCTION_APP_NAME=$(az deployment group show \
    --resource-group rg-image-discovery-demo \
    --name main \
    --query properties.outputs.functionAppName.value -o tsv)

# Deploy function code (requires function code in current directory)
func azure functionapp publish $FUNCTION_APP_NAME --python
```

### Search Index Configuration

Create the search index with vector capabilities:

```bash
# Get search service details
SEARCH_SERVICE_NAME=$(az deployment group show \
    --resource-group rg-image-discovery-demo \
    --name main \
    --query properties.outputs.searchServiceName.value -o tsv)

SEARCH_ADMIN_KEY=$(az search admin-key show \
    --service-name $SEARCH_SERVICE_NAME \
    --resource-group rg-image-discovery-demo \
    --query primaryKey -o tsv)

# Create search index (using the index definition from the recipe)
curl -X POST "https://${SEARCH_SERVICE_NAME}.search.windows.net/indexes" \
    -H "Content-Type: application/json" \
    -H "api-key: ${SEARCH_ADMIN_KEY}" \
    -H "api-version: 2024-05-01-preview" \
    -d @search-index-schema.json
```

## Testing the Deployment

### Upload Test Images

```bash
# Get storage account name
STORAGE_ACCOUNT_NAME=$(az deployment group show \
    --resource-group rg-image-discovery-demo \
    --name main \
    --query properties.outputs.storageAccountName.value -o tsv)

# Upload a test image
az storage blob upload \
    --account-name $STORAGE_ACCOUNT_NAME \
    --container-name images \
    --name test-image.jpg \
    --file /path/to/your/test-image.jpg
```

### Verify Image Processing

```bash
# Check function execution logs
az functionapp logs tail \
    --name $FUNCTION_APP_NAME \
    --resource-group rg-image-discovery-demo

# Query search index for processed images
curl -X POST "https://${SEARCH_SERVICE_NAME}.search.windows.net/indexes/image-content-index/docs/search?api-version=2024-05-01-preview" \
    -H "Content-Type: application/json" \
    -H "api-key: ${SEARCH_ADMIN_KEY}" \
    -d '{"search": "*", "top": 10}'
```

## Monitoring and Troubleshooting

### Application Insights

Monitor the solution using Application Insights:

```bash
# Get Application Insights details
APP_INSIGHTS_NAME=$(az deployment group show \
    --resource-group rg-image-discovery-demo \
    --name main \
    --query properties.outputs.applicationInsightsName.value -o tsv)

# View recent logs
az monitor app-insights query \
    --app $APP_INSIGHTS_NAME \
    --analytics-query "traces | where timestamp > ago(1h) | order by timestamp desc"
```

### Common Issues

1. **Function not triggering**: Check storage account connection string and blob trigger configuration
2. **AI Vision errors**: Verify API key and endpoint configuration in function app settings
3. **Search indexing failures**: Check search service capacity and index schema
4. **Permission errors**: Ensure all services have appropriate managed identity permissions

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-image-discovery-demo \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy -var="location=eastus" -var="environment_name=demo"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
az group show --name rg-image-discovery-demo --query properties.provisioningState
```

## Cost Optimization

### Estimated Monthly Costs (USD)

| Service | Tier | Estimated Cost |
|---------|------|----------------|
| Azure Storage | Standard LRS | $1-5 |
| Azure AI Vision | S1 | $1-10 |
| Azure AI Search | Basic | $250 |
| Azure Functions | Consumption | $0-20 |
| Application Insights | Basic | $0-10 |
| **Total** | | **$252-295** |

### Cost Reduction Tips

1. **Use Free Tier**: AI Vision and Search offer free tiers for development/testing
2. **Optimize Search Service**: Use free tier for small datasets (<50MB, 3 indexes)
3. **Function Optimization**: Optimize function execution time to reduce costs
4. **Storage Lifecycle**: Implement lifecycle policies for old images
5. **Monitor Usage**: Use Azure Cost Management to track spending

## Security Considerations

### Implemented Security Features

- **Managed Identity**: Services authenticate using system-assigned managed identities
- **Key Vault Integration**: Sensitive configuration stored in Azure Key Vault
- **Network Security**: Storage accounts configured with private access
- **RBAC**: Role-based access control for all services
- **Encryption**: Data encrypted at rest and in transit

### Additional Security Recommendations

1. **Network Isolation**: Consider Azure Private Link for production deployments
2. **API Management**: Add Azure API Management for external access control
3. **Content Moderation**: Integrate Azure Content Moderator for content filtering
4. **Audit Logging**: Enable Azure Activity Log and resource-specific logging
5. **Backup Strategy**: Implement backup policies for critical data

## Performance Optimization

### Scaling Considerations

1. **Function App**: Automatically scales based on blob trigger volume
2. **Search Service**: Scale up/out based on query volume and index size
3. **Storage Account**: Consider premium storage for high-throughput scenarios
4. **AI Vision**: Monitor transaction rates and scale service tier accordingly

### Performance Monitoring

```bash
# Monitor function performance
az monitor metrics list \
    --resource $FUNCTION_APP_NAME \
    --resource-group rg-image-discovery-demo \
    --resource-type Microsoft.Web/sites \
    --metric FunctionExecutionCount,FunctionExecutionUnits

# Monitor search performance
az monitor metrics list \
    --resource $SEARCH_SERVICE_NAME \
    --resource-group rg-image-discovery-demo \
    --resource-type Microsoft.Search/searchServices \
    --metric SearchLatency,SearchQueriesPerSecond
```

## Customization

### Adding Custom Vision Models

To integrate custom AI Vision models:

1. Train custom models in Azure AI Vision Studio
2. Update function code to use custom model endpoints
3. Modify search index schema for custom extracted fields
4. Update function app configuration with custom model details

### Extending Search Capabilities

Enhance search functionality by:

1. Adding custom skillsets for specialized content extraction
2. Implementing semantic search configurations
3. Adding faceted search for improved filtering
4. Integrating with Azure Cognitive Search enrichment pipeline

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Azure Documentation**: Check [Azure AI Search](https://docs.microsoft.com/en-us/azure/search/) and [Azure AI Vision](https://docs.microsoft.com/en-us/azure/cognitive-services/computer-vision/) documentation
3. **Community Support**: Visit [Azure Community Forums](https://techcommunity.microsoft.com/t5/azure/ct-p/Azure)
4. **Microsoft Support**: Create support tickets through Azure Portal for production issues

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Validate against the original recipe requirements
3. Update documentation to reflect changes
4. Follow Azure Well-Architected Framework principles