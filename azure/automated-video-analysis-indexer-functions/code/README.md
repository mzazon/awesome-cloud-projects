# Infrastructure as Code for Automated Video Analysis with Video Indexer and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Video Analysis with Video Indexer and Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (ARM template successor)
- **Terraform**: Multi-cloud infrastructure as code using Azure Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.50.0 or later)
- Azure subscription with Owner or Contributor permissions
- Basic understanding of video processing and serverless architectures
- For Terraform: Terraform CLI installed (version 1.0 or later)
- For Bicep: Azure CLI with Bicep extension installed

## Resource Overview

This infrastructure deploys:
- Azure Resource Group for organizing resources
- Azure Storage Account with containers for videos and insights
- Azure AI Video Indexer account for video analysis
- Azure Functions App with consumption plan for serverless processing
- Blob trigger function for automated video processing
- Application Insights for monitoring and diagnostics

## Quick Start

### Using Bicep

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment sub create \
    --location eastus \
    --template-file main.bicep \
    --parameters projectName=videoanalysis \
                 environment=demo \
                 location=eastus

# Get deployment outputs
az deployment sub show \
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
terraform plan \
    -var="project_name=videoanalysis" \
    -var="environment=demo" \
    -var="location=East US"

# Apply the configuration
terraform apply \
    -var="project_name=videoanalysis" \
    -var="environment=demo" \
    -var="location=East US"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set required environment variables
export PROJECT_NAME="videoanalysis"
export ENVIRONMENT="demo"
export LOCATION="eastus"

# Deploy the infrastructure
./deploy.sh

# View deployment summary
cat deployment-summary.txt
```

## Configuration Options

### Common Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_name` | Name prefix for all resources | `videoanalysis` | Yes |
| `environment` | Environment designation | `demo` | Yes |
| `location` | Azure region for deployment | `eastus` | Yes |
| `storage_sku` | Storage account SKU | `Standard_LRS` | No |
| `function_runtime` | Function runtime version | `python` | No |
| `function_version` | Functions host version | `4` | No |

### Bicep Parameters

```bicep
// Example parameter file (parameters.json)
{
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "projectName": {
            "value": "videoanalysis"
        },
        "environment": {
            "value": "demo"
        },
        "location": {
            "value": "eastus"
        }
    }
}
```

### Terraform Variables

```hcl
# terraform.tfvars example
project_name = "videoanalysis"
environment = "demo"
location = "East US"
storage_account_tier = "Standard"
storage_account_replication_type = "LRS"
function_app_service_plan_tier = "Y1"
tags = {
    Purpose = "video-analysis"
    Owner = "data-team"
}
```

## Post-Deployment Steps

### 1. Verify Function Deployment

```bash
# Check Function App status
az functionapp show \
    --name func-videoanalysis-demo \
    --resource-group rg-videoanalysis-demo \
    --query state

# List function app settings
az functionapp config appsettings list \
    --name func-videoanalysis-demo \
    --resource-group rg-videoanalysis-demo
```

### 2. Test Video Upload

```bash
# Upload a test video file
az storage blob upload \
    --account-name savideoanalysisdemo \
    --container-name videos \
    --name test-video.mp4 \
    --file /path/to/your/video.mp4
```

### 3. Monitor Processing

```bash
# Check Application Insights logs
az monitor app-insights query \
    --app func-videoanalysis-demo \
    --analytics-query "traces | where message contains 'VideoAnalyzer' | limit 10"

# Check for generated insights
az storage blob list \
    --account-name savideoanalysisdemo \
    --container-name insights \
    --output table
```

## Architecture Components

### Storage Architecture
- **videos container**: Stores uploaded video files with blob triggers
- **insights container**: Stores processed analysis results as JSON files
- **Private endpoints**: Secure network access to storage resources

### Compute Architecture
- **Consumption Plan**: Pay-per-execution serverless hosting
- **Blob Trigger**: Automatic function execution on video uploads
- **Python 3.11 Runtime**: Latest supported Python runtime for Azure Functions

### AI Services Architecture
- **Video Indexer ARM Account**: Enterprise-grade video analysis service
- **30+ AI Models**: Comprehensive video and audio analysis capabilities
- **REST API Integration**: Programmatic access to analysis results

## Security Considerations

### Identity and Access
- System-assigned managed identity for Function App
- Role-based access control (RBAC) for resource access
- Private storage container access only

### Data Protection
- HTTPS-only storage account access
- TLS 1.2 minimum encryption
- Azure Key Vault integration for sensitive configuration

### Network Security
- Storage account firewall rules
- Function App VNET integration support
- Private endpoint connectivity options

## Cost Optimization

### Pricing Components
- **Video Indexer**: Pay-per-minute processing ($0.15-0.20 per minute)
- **Azure Functions**: Pay-per-execution ($0.000016 per GB-second)
- **Blob Storage**: $0.018 per GB for hot tier, $0.01 per GB for cool tier
- **Application Insights**: $2.88 per GB ingested data

### Cost Management
- Storage lifecycle policies for video archival
- Function timeout configuration (10 minutes default)
- Video Indexer regional pricing optimization
- Blob storage tier optimization based on access patterns

## Monitoring and Observability

### Application Insights Integration
```bash
# Query function execution metrics
az monitor app-insights query \
    --app func-videoanalysis-demo \
    --analytics-query "requests | summarize count() by bin(timestamp, 1h)"
```

### Custom Metrics
- Video processing duration
- Analysis success/failure rates
- Storage utilization trends
- Function execution costs

## Troubleshooting

### Common Issues

1. **Function deployment fails**
   ```bash
   # Check deployment logs
   az functionapp log tail \
       --name func-videoanalysis-demo \
       --resource-group rg-videoanalysis-demo
   ```

2. **Video Indexer authentication errors**
   ```bash
   # Verify Video Indexer account status
   az cognitiveservices account show \
       --name vi-videoanalysis-demo \
       --resource-group rg-videoanalysis-demo
   ```

3. **Storage access issues**
   ```bash
   # Test storage connectivity
   az storage blob exists \
       --account-name savideoanalysisdemo \
       --container-name videos \
       --name test-file.txt
   ```

### Debug Mode
Enable detailed logging by setting `FUNCTIONS_WORKER_RUNTIME_LOG_LEVEL=DEBUG` in Function App settings.

## Cleanup

### Using Bicep
```bash
# Delete the resource group and all resources
az group delete \
    --name rg-videoanalysis-demo \
    --yes \
    --no-wait
```

### Using Terraform
```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy \
    -var="project_name=videoanalysis" \
    -var="environment=demo" \
    -var="location=East US"

# Clean up state files
rm -f terraform.tfstate*
```

### Using Bash Scripts
```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Verify cleanup completion
cat cleanup-summary.txt
```

## Customization Examples

### Scaling Configuration
```bicep
// Scale Function App for higher throughput
functionAppSettings: [
    {
        name: 'FUNCTIONS_WORKER_PROCESS_COUNT'
        value: '4'
    }
    {
        name: 'PYTHON_THREADPOOL_THREAD_COUNT'
        value: '8'
    }
]
```

### Advanced Storage Configuration
```terraform
# Configure storage lifecycle management
resource "azurerm_storage_management_policy" "video_lifecycle" {
  storage_account_id = azurerm_storage_account.main.id

  rule {
    name    = "video_archival"
    enabled = true

    filters {
      prefix_match = ["videos/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 90
      }
    }
  }
}
```

### Regional Deployment
```bash
# Deploy to multiple regions for global availability
export REGIONS=("eastus" "westeurope" "southeastasia")

for region in "${REGIONS[@]}"; do
    ./deploy.sh --region $region --suffix $region
done
```

## Performance Optimization

### Video Processing Performance
- Optimize function timeout based on average video length
- Configure parallel processing for multiple video uploads
- Implement retry logic with exponential backoff

### Storage Performance
- Use premium storage for frequently accessed content
- Configure CDN for global video distribution
- Implement blob storage hot/cool/archive tiers

## Integration Patterns

### Event-Driven Architecture
```json
{
    "eventType": "Microsoft.Storage.BlobCreated",
    "subject": "/blobServices/default/containers/videos/blobs/video.mp4",
    "eventTime": "2024-01-15T10:00:00Z",
    "data": {
        "api": "PutBlob",
        "contentType": "video/mp4",
        "contentLength": 104857600
    }
}
```

### Webhook Integration
```python
# Example webhook handler for Video Indexer callbacks
@app.route('/webhook', methods=['POST'])
def video_indexer_webhook():
    data = request.json
    video_id = data.get('id')
    state = data.get('state')
    
    if state == 'Processed':
        # Handle successful processing
        process_video_insights(video_id)
    
    return jsonify({'status': 'received'})
```

## Support and Documentation

### Official Documentation
- [Azure AI Video Indexer Documentation](https://learn.microsoft.com/en-us/azure/azure-video-indexer/)
- [Azure Functions Python Developer Guide](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-python)
- [Azure Blob Storage Documentation](https://learn.microsoft.com/en-us/azure/storage/blobs/)

### Community Resources
- [Azure Functions GitHub Repository](https://github.com/Azure/azure-functions-host)
- [Video Indexer API Reference](https://api-portal.videoindexer.ai/)
- [Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/)

### Getting Help
- Create issues in the recipe repository for infrastructure questions
- Use Azure Support for production deployment assistance
- Join the Azure Functions community for technical discussions

---

For additional customization options and advanced configurations, refer to the individual IaC implementation files in their respective directories.