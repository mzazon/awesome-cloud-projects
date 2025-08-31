# Infrastructure as Code for Simple Image Resizing with Functions and Blob Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Image Resizing with Functions and Blob Storage".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.0.80+)
- Azure subscription with contributor permissions
- Node.js 18+ (for Azure Functions runtime)
- For Terraform: Terraform CLI installed (version 1.0+)
- For Bicep: Bicep CLI installed (bundled with Azure CLI 2.20+)
- Appropriate permissions for:
  - Resource Group creation and management
  - Storage Account creation and management
  - Function App creation and management
  - Event Grid subscription management

## Architecture Overview

This solution deploys:
- **Storage Account** with Hot tier access for optimal performance
- **Blob Containers** for organizing original and processed images
- **Function App** with Consumption plan for cost-effective serverless execution
- **Event Grid Integration** for real-time blob event processing
- **Application Settings** for configurable image processing parameters

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Set deployment parameters
export RESOURCE_GROUP="rg-image-resize-$(openssl rand -hex 3)"
export LOCATION="eastus"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Deploy infrastructure
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters location=$LOCATION

# Deploy function code (after infrastructure deployment)
cd ../
func azure functionapp publish $(az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name main \
    --query properties.outputs.functionAppName.value -o tsv)
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

# Note the function app name from output
export FUNCTION_APP_NAME=$(terraform output -raw function_app_name)

# Deploy function code (after infrastructure deployment)
cd ../
func azure functionapp publish $FUNCTION_APP_NAME
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy complete solution
./scripts/deploy.sh

# Script will prompt for:
# - Resource group name (or generate random)
# - Azure region (default: eastus)
# - Confirmation to proceed
```

## Configuration Options

### Bicep Parameters

You can override default values by creating a `parameters.json` file:

```json
{
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "location": {
            "value": "westus2"
        },
        "storageAccountSku": {
            "value": "Standard_GRS"
        },
        "thumbnailWidth": {
            "value": 200
        },
        "thumbnailHeight": {
            "value": 200
        },
        "mediumWidth": {
            "value": 1024
        },
        "mediumHeight": {
            "value": 768
        }
    }
}
```

Deploy with parameters:
```bash
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Terraform Variables

Override defaults in `terraform.tfvars`:

```hcl
location = "West US 2"
storage_account_tier = "Standard"
storage_account_replication_type = "GRS"
thumbnail_width = 200
thumbnail_height = 200
medium_width = 1024
medium_height = 768
environment = "production"
```

### Environment Variables (Bash Scripts)

Set these variables before running deploy scripts:

```bash
export AZURE_LOCATION="westus2"
export STORAGE_SKU="Standard_GRS"
export THUMBNAIL_WIDTH="200"
export THUMBNAIL_HEIGHT="200"
export MEDIUM_WIDTH="1024"
export MEDIUM_HEIGHT="768"
```

## Function Deployment

After infrastructure deployment, deploy the function code:

### Automatic Deployment (Bash Scripts)
The bash deployment script handles both infrastructure and function code deployment automatically.

### Manual Function Deployment

1. **Prepare Function Project**:
   ```bash
   # Create function project structure
   mkdir image-resize-function && cd image-resize-function
   func init . --javascript --model V4
   func new --name ImageResize --template "Azure Blob Storage trigger"
   
   # Install dependencies
   npm install sharp @azure/storage-blob @azure/functions
   ```

2. **Deploy Function Code**:
   ```bash
   # Get function app name from deployment output
   export FUNCTION_APP_NAME="your-function-app-name"
   
   # Deploy function
   func azure functionapp publish $FUNCTION_APP_NAME
   ```

## Testing the Deployment

### Upload Test Image

```bash
# Get storage account name and connection string
export STORAGE_ACCOUNT=$(az storage account list \
    --resource-group $RESOURCE_GROUP \
    --query "[0].name" -o tsv)

export STORAGE_CONNECTION=$(az storage account show-connection-string \
    --name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --query connectionString -o tsv)

# Download test image
curl -o test-image.jpg "https://picsum.photos/1200/900.jpg"

# Upload to trigger processing
az storage blob upload \
    --container-name "original-images" \
    --name "test-photo.jpg" \
    --file test-image.jpg \
    --connection-string "$STORAGE_CONNECTION"
```

### Verify Processing Results

```bash
# Wait for processing (typically 5-15 seconds)
sleep 15

# Check generated thumbnails
az storage blob list \
    --container-name "thumbnails" \
    --connection-string "$STORAGE_CONNECTION" \
    --output table

# Check generated medium images
az storage blob list \
    --container-name "medium-images" \
    --connection-string "$STORAGE_CONNECTION" \
    --output table

# Get public URLs for verification
echo "Thumbnail URL:"
az storage blob url \
    --container-name "thumbnails" \
    --name "test-photo-thumb.jpg" \
    --connection-string "$STORAGE_CONNECTION"

echo "Medium Image URL:"
az storage blob url \
    --container-name "medium-images" \
    --name "test-photo-medium.jpg" \
    --connection-string "$STORAGE_CONNECTION"
```

## Monitoring and Troubleshooting

### View Function Logs

```bash
# Stream live logs
func azure functionapp logstream $FUNCTION_APP_NAME

# Or view in Azure Portal
az functionapp browse --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP
```

### Application Insights Queries

Use these KQL queries in Application Insights:

```kql
// Recent function executions
traces
| where timestamp > ago(1h)
| where severityLevel >= 1
| order by timestamp desc

// Function performance metrics
performanceCounters
| where timestamp > ago(1h)
| where counter contains "Execution"
| summarize avg(value) by bin(timestamp, 5m)
```

### Common Issues

1. **Function Not Triggering**: Verify Event Grid subscription is created and active
2. **Image Processing Errors**: Check Sharp library installation and supported formats
3. **Permission Issues**: Ensure Function App has Storage Blob Data Contributor role
4. **Memory Errors**: Consider upgrading to Premium plan for large images

## Cleanup

### Using Bicep

```bash
# Delete resource group (removes all resources)
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Or manual cleanup
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

## Cost Optimization

### Consumption Plan Benefits
- **Pay per execution**: Only charged for actual function execution time
- **Automatic scaling**: Scales from 0 to thousands of concurrent executions
- **Free tier**: 1 million executions and 400,000 GB-s per month included

### Storage Cost Optimization
- **Hot tier**: Optimal for frequently accessed processed images
- **Cool tier**: Consider for original image archival (30+ day retention)
- **Lifecycle policies**: Automatically transition old images to cooler tiers

### Estimated Monthly Costs (USD)
- **Function App (Consumption)**: $0.50 - $5.00 (based on usage)
- **Storage Account**: $1.00 - $10.00 (based on data volume)
- **Event Grid**: $0.01 - $0.50 (based on events)
- **Total**: $1.51 - $15.50 per month for moderate usage

## Performance Optimization

### Sharp Library Optimization
- Uses libvips for 4x-5x better performance than ImageMagick
- Memory-efficient streaming processing
- Native support for progressive JPEG and WebP formats

### Function Performance Tips
- **Cold start optimization**: Keep functions warm with timer triggers if needed
- **Memory allocation**: Monitor memory usage and adjust if necessary
- **Batch processing**: Consider batching multiple images for efficiency

## Security Considerations

### Storage Security
- Blob containers configured with public read access for processed images
- Original images container uses private access with function-only permissions
- Storage account uses HTTPS-only access and minimum TLS 1.2

### Function Security
- Managed identity for secure access to storage resources
- Application settings for secure configuration management
- Function-level authorization for additional security

### Network Security
- Consider VNet integration for enterprise scenarios
- Private endpoints for storage account in high-security environments
- IP restrictions for function app management

## Customization Examples

### Adding WebP Support

Modify the function to generate WebP format alongside JPEG:

```javascript
// Add WebP processing
const webpBuffer = await sharp(blob)
    .resize(mediumWidth, mediumHeight, {
        fit: 'inside',
        withoutEnlargement: true
    })
    .webp({ quality: 85 })
    .toBuffer();

// Upload WebP version
const webpBlob = mediumContainer.getBlockBlobClient(`${baseName}-medium.webp`);
await webpBlob.upload(webpBuffer, webpBuffer.length, {
    blobHTTPHeaders: { blobContentType: 'image/webp' }
});
```

### Custom Image Sizes

Add environment variables and processing logic for additional sizes:

```bash
# Add to application settings
az functionapp config appsettings set \
    --name $FUNCTION_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --settings "LARGE_WIDTH=1920" "LARGE_HEIGHT=1080"
```

## Support and Documentation

- **Azure Functions Documentation**: https://docs.microsoft.com/azure/azure-functions/
- **Azure Blob Storage Documentation**: https://docs.microsoft.com/azure/storage/blobs/
- **Sharp Library Documentation**: https://sharp.pixelplumbing.com/
- **Bicep Documentation**: https://docs.microsoft.com/azure/azure-resource-manager/bicep/
- **Terraform Azure Provider**: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs

For issues with this infrastructure code, refer to the original recipe documentation or open an issue in the repository.