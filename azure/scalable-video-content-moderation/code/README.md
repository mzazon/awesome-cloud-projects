# Infrastructure as Code for Scalable Video Content Moderation Pipeline

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Scalable Video Content Moderation Pipeline".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login` completed)
- Active Azure subscription with appropriate permissions
- Contributor or Owner role on target resource group
- Basic understanding of video processing and event-driven architectures
- For Terraform: Terraform 1.0+ installed
- For Bicep: Azure CLI with Bicep extension

### Required Azure Resource Providers

Ensure the following resource providers are registered in your subscription:

```bash
az provider register --namespace Microsoft.CognitiveServices
az provider register --namespace Microsoft.EventHub
az provider register --namespace Microsoft.StreamAnalytics
az provider register --namespace Microsoft.Logic
az provider register --namespace Microsoft.Storage
```

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to bicep directory
cd bicep/

# Review and customize parameters if needed
az deployment group create \
    --resource-group your-resource-group \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters environmentSuffix=$(openssl rand -hex 3)
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts and wait for deployment completion
```

## Configuration Options

### Bicep Parameters

The Bicep template accepts the following parameters:

- `location`: Azure region for resource deployment (default: eastus)
- `environmentSuffix`: Unique suffix for resource names (auto-generated if not provided)
- `eventHubSku`: Event Hubs namespace SKU (default: Standard)
- `storageAccountSku`: Storage account SKU (default: Standard_LRS)
- `streamAnalyticsUnits`: Number of streaming units (default: 3)
- `aiVisionSku`: AI Vision service SKU (default: S1)

### Terraform Variables

The Terraform configuration supports these variables in `terraform.tfvars`:

```hcl
# Required variables
location = "eastus"
environment_suffix = "unique123"

# Optional variables
event_hub_sku = "Standard"
storage_account_sku = "Standard_LRS"
stream_analytics_units = 3
ai_vision_sku = "S1"
```

### Environment Variables for Scripts

The bash scripts use these environment variables (set automatically or customize):

```bash
export RESOURCE_GROUP="rg-video-moderation-${RANDOM_SUFFIX}"
export LOCATION="eastus"
export EVENT_HUB_NAMESPACE="eh-videomod-${RANDOM_SUFFIX}"
export STORAGE_ACCOUNT="stvideomod${RANDOM_SUFFIX}"
export AI_VISION_NAME="aivision-contentmod-${RANDOM_SUFFIX}"
```

## Validation & Testing

After deployment, validate the infrastructure:

### Test AI Vision Service

```bash
# Get AI Vision endpoint and key
AI_VISION_ENDPOINT=$(az cognitiveservices account show \
    --name <ai-vision-name> \
    --resource-group <resource-group> \
    --query properties.endpoint --output tsv)

AI_VISION_KEY=$(az cognitiveservices account keys list \
    --name <ai-vision-name> \
    --resource-group <resource-group> \
    --query key1 --output tsv)

# Test content moderation API
curl -X POST "${AI_VISION_ENDPOINT}/vision/v3.2/analyze?visualFeatures=Adult" \
     -H "Ocp-Apim-Subscription-Key: ${AI_VISION_KEY}" \
     -H "Content-Type: application/json" \
     -d '{"url": "https://moderatorsampleimages.blob.core.windows.net/samples/sample.jpg"}'
```

### Test Event Hubs Connectivity

```bash
# Send test message to Event Hubs
az eventhubs eventhub send \
    --namespace-name <event-hub-namespace> \
    --name video-frames \
    --message-body '{"videoId":"test-123","frameUrl":"https://example.com/frame.jpg"}' \
    --resource-group <resource-group>
```

### Verify Stream Analytics Job

```bash
# Check Stream Analytics job status
az stream-analytics job show \
    --name <stream-analytics-job> \
    --resource-group <resource-group> \
    --query jobState
```

## Architecture Components

The deployed infrastructure includes:

- **Azure AI Vision**: Content moderation and image analysis
- **Azure Event Hubs**: High-throughput event streaming for video frames
- **Azure Stream Analytics**: Real-time stream processing and orchestration
- **Azure Logic Apps**: Automated response workflows for detected content
- **Azure Storage Account**: Persistent storage for moderation results
- **Azure Monitor**: Logging and monitoring for all components

## Cost Considerations

### Estimated Monthly Costs (East US region)

- AI Vision (S1): ~$1.50 per 1,000 transactions
- Event Hubs (Standard): ~$0.028 per million events
- Stream Analytics (3 SU): ~$80.30 per month
- Logic Apps: ~$0.000025 per action execution
- Storage Account (LRS): ~$0.021 per GB per month

> **Note**: Costs vary based on usage patterns. Monitor Azure Cost Management for actual spending.

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name your-resource-group \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Troubleshooting

### Common Issues

1. **Resource Name Conflicts**: Ensure unique suffixes for globally unique resources
2. **Permission Errors**: Verify you have Contributor/Owner role on the resource group
3. **Provider Registration**: Ensure all required resource providers are registered
4. **Region Availability**: Some services may not be available in all regions

### Debug Commands

```bash
# Check resource group status
az group show --name <resource-group>

# View deployment operations
az deployment group list --resource-group <resource-group>

# Check specific resource status
az resource list --resource-group <resource-group> --output table
```

### Stream Analytics Troubleshooting

```bash
# Check job input/output status
az stream-analytics job show \
    --name <job-name> \
    --resource-group <resource-group> \
    --query "inputs[0].properties.diagnostics"

# View job metrics
az monitor metrics list \
    --resource "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.StreamAnalytics/streamingjobs/<job-name>" \
    --metric "InputEvents,OutputEvents,RuntimeErrors"
```

## Security Considerations

The deployed infrastructure follows Azure security best practices:

- **Managed Identity**: Used where possible to avoid storing credentials
- **Key Vault Integration**: Sensitive values stored securely (configurable)
- **Network Security**: Configurable virtual network integration
- **Access Control**: RBAC implemented for service-to-service communication
- **Encryption**: Data encrypted at rest and in transit

## Customization

### Adding Custom Content Moderation Logic

1. Modify the Stream Analytics query in the Bicep/Terraform templates
2. Update Logic App workflows for custom response actions
3. Configure additional Event Hubs partitions for higher throughput
4. Implement custom AI models using Azure Custom Vision

### Scaling Considerations

- **Event Hubs**: Increase throughput units for higher event volume
- **Stream Analytics**: Add streaming units for complex processing
- **AI Vision**: Consider dedicated pricing tiers for high-volume scenarios
- **Storage**: Use premium storage for high-performance requirements

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for context
2. Check Azure service documentation for specific resource issues
3. Validate Azure CLI version and permissions
4. Review Azure Resource Manager deployment logs

For Azure-specific support, consult the [Azure documentation](https://docs.microsoft.com/en-us/azure/) and [Azure AI Vision documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/computer-vision/).

## Next Steps

After successful deployment, consider:

1. Implementing the validation and testing steps from the recipe
2. Customizing content moderation thresholds for your use case
3. Integrating with existing video processing pipelines
4. Setting up monitoring dashboards and alerts
5. Implementing the challenge enhancements from the recipe
