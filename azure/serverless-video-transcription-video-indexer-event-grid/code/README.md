# Infrastructure as Code for Serverless Video Transcription with Video Indexer and Event Grid

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Serverless Video Transcription with Video Indexer and Event Grid".

## Overview

This solution creates a serverless video transcription pipeline that automatically processes videos uploaded to Azure Blob Storage, extracts transcriptions and insights using Azure Video Indexer, and orchestrates the workflow using Azure Event Grid and Azure Functions.

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure includes:
- Azure Storage Account with blob containers for videos and results
- Azure Cosmos DB for metadata storage
- Azure Functions for processing logic
- Azure Event Grid topic and subscriptions for event orchestration
- Application Insights for monitoring

## Prerequisites

- Azure CLI v2.0 or later installed and configured
- Azure subscription with appropriate permissions (Contributor role)
- Azure Video Indexer account (manual setup required)
- For Terraform: Terraform v1.0+ installed
- For Bicep: Azure CLI with Bicep extension

## Quick Start

### Using Bicep (Recommended)

```bash
# Set required parameters
export RESOURCE_GROUP="rg-video-indexer-demo"
export LOCATION="eastus"
export VIDEO_INDEXER_ACCOUNT_ID="your-vi-account-id"
export VIDEO_INDEXER_API_KEY="your-vi-api-key"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Deploy infrastructure
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json \
    --parameters videoIndexerAccountId=$VIDEO_INDEXER_ACCOUNT_ID \
    --parameters videoIndexerApiKey=$VIDEO_INDEXER_API_KEY
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export RESOURCE_GROUP="rg-video-indexer-demo"
export LOCATION="eastus"
export VIDEO_INDEXER_ACCOUNT_ID="your-vi-account-id"
export VIDEO_INDEXER_API_KEY="your-vi-api-key"

# Deploy infrastructure
./scripts/deploy.sh
```

## Configuration

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `resourceGroupName` | Name of the Azure resource group | `rg-video-indexer-demo` |
| `location` | Azure region for deployment | `eastus` |
| `videoIndexerAccountId` | Video Indexer account ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `videoIndexerApiKey` | Video Indexer API key | `your-api-key` |

### Optional Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `storageAccountName` | Storage account name (auto-generated if not provided) | `stvideo{uniqueString}` |
| `functionAppName` | Function app name (auto-generated if not provided) | `func-video-{uniqueString}` |
| `cosmosAccountName` | Cosmos DB account name (auto-generated if not provided) | `cosmos-video-{uniqueString}` |
| `eventGridTopicName` | Event Grid topic name (auto-generated if not provided) | `eg-video-{uniqueString}` |

## Post-Deployment Setup

### 1. Azure Video Indexer Account Setup

If you don't have a Video Indexer account:

1. Visit [https://www.videoindexer.ai/](https://www.videoindexer.ai/)
2. Sign in with your Azure account
3. Create a new account or use existing
4. Note your Account ID and API Key from the Profile page
5. Update deployment parameters with these values

### 2. Function Code Deployment

The infrastructure creates the Function App, but you need to deploy the function code:

```bash
# Clone or download the function code
# Navigate to the function project directory

# Deploy functions
func azure functionapp publish <function-app-name>
```

### 3. Test the Pipeline

```bash
# Upload a test video
az storage blob upload \
    --account-name <storage-account-name> \
    --container-name videos \
    --name test-video.mp4 \
    --file path/to/your/video.mp4
```

## Monitoring and Troubleshooting

### View Function Logs

```bash
# Stream function logs
az webapp log tail \
    --name <function-app-name> \
    --resource-group <resource-group-name>
```

### Check Event Grid Metrics

```bash
# View Event Grid topic metrics
az monitor metrics list \
    --resource <event-grid-topic-resource-id> \
    --metric "PublishedEvents,DeliveryAttempts"
```

### Query Processed Videos

```bash
# List processed videos in Cosmos DB
az cosmosdb sql query \
    --account-name <cosmos-account-name> \
    --database-name VideoAnalytics \
    --container-name VideoMetadata \
    --resource-group <resource-group-name> \
    --query-text "SELECT c.videoId, c.name, c.duration FROM c"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Cost Optimization

### Estimated Monthly Costs

For moderate usage (100 videos/month, avg 5 minutes each):

- **Azure Video Indexer**: ~$25 (500 minutes indexing)
- **Azure Functions**: ~$5 (consumption plan)
- **Azure Storage**: ~$5 (500GB storage)
- **Azure Cosmos DB**: ~$10 (serverless tier)
- **Azure Event Grid**: ~$1 (1M operations)
- **Total**: ~$46/month

### Cost Reduction Tips

1. Use storage lifecycle policies to archive old videos
2. Enable Cosmos DB serverless tier for variable workloads
3. Monitor and adjust Function App timeout settings
4. Use Video Indexer free tier (10 hours/month) for development

## Security Considerations

### Default Security Features

- All storage accounts use private endpoints where possible
- Function apps use managed identity for Azure service authentication
- Cosmos DB uses role-based access control (RBAC)
- Event Grid topics use access keys with rotation capability

### Additional Security Recommendations

1. Enable Azure Private Link for storage accounts
2. Configure network restrictions for Function Apps
3. Use Azure Key Vault for Video Indexer API keys
4. Enable diagnostic logging for all services
5. Implement Azure Policy for compliance

## Troubleshooting

### Common Issues

1. **Video Indexer API authentication errors**
   - Verify Account ID and API Key are correct
   - Check Video Indexer account is active
   - Ensure API key hasn't expired

2. **Function deployment failures**
   - Check Function App runtime version compatibility
   - Verify all required application settings are configured
   - Review deployment logs in Azure portal

3. **Event Grid subscription issues**
   - Verify endpoint URLs are accessible
   - Check Event Grid topic key is valid
   - Review Event Grid delivery metrics

4. **Cosmos DB connection errors**
   - Verify connection string format
   - Check Cosmos DB account exists
   - Ensure database and container are created

### Debug Commands

```bash
# Check Function App status
az functionapp show \
    --name <function-app-name> \
    --resource-group <resource-group-name> \
    --query "{state:state, defaultHostName:defaultHostName}"

# Verify storage account configuration
az storage account show \
    --name <storage-account-name> \
    --resource-group <resource-group-name> \
    --query "{accessTier:accessTier, kind:kind, provisioningState:provisioningState}"

# Check Event Grid topic status
az eventgrid topic show \
    --name <event-grid-topic-name> \
    --resource-group <resource-group-name> \
    --query "{provisioningState:provisioningState, endpoint:endpoint}"
```

## Customization

### Adding Custom Processing Logic

Modify the Function App code to:
- Add custom video analysis workflows
- Integrate with additional Azure AI services
- Implement custom notification systems
- Add content moderation rules

### Scaling Considerations

For high-volume scenarios:
- Use Azure Functions Premium plan for better performance
- Implement Azure Storage premium tier for faster access
- Consider Azure Video Indexer reserved capacity
- Use Azure Cosmos DB provisioned throughput

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Azure service documentation
3. Review Azure CLI and Bicep/Terraform documentation
4. Use Azure support channels for service-specific issues

## Contributing

To contribute improvements to this IaC:
1. Test changes in a development environment
2. Follow Azure naming conventions
3. Update documentation accordingly
4. Ensure all security best practices are maintained