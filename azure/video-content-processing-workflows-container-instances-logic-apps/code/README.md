# Infrastructure as Code for Video Content Processing Workflows with Azure Container Instances and Azure Logic Apps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Video Content Processing Workflows with Azure Container Instances and Azure Logic Apps".

## Available Implementations

- **Bicep**: Azure native infrastructure as code
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az --version`)
- Appropriate Azure subscription with permissions for:
  - Resource Groups
  - Storage Accounts
  - Container Instances
  - Logic Apps
  - Event Grid
- Terraform installed (for Terraform deployment)
- Basic understanding of video processing workflows and containerization
- Estimated cost: $20-50 for resources created during deployment

## Quick Start

### Using Bicep

```bash
# Navigate to bicep directory
cd bicep/

# Create resource group
az group create --name rg-video-workflow --location eastus

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-video-workflow \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment status
az deployment group show \
    --resource-group rg-video-workflow \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts and monitor progress
```

## Solution Architecture

This solution deploys:

- **Azure Storage Account** with containers for input and output videos
- **Azure Container Instances** with FFmpeg for video processing
- **Azure Logic Apps** for workflow orchestration
- **Azure Event Grid** for event-driven automation
- **Event Grid Subscriptions** to trigger processing on video uploads

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "storageAccountSku": {
      "value": "Standard_LRS"
    },
    "containerCpu": {
      "value": 2
    },
    "containerMemory": {
      "value": 4
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
location                = "East US"
storage_account_sku     = "Standard_LRS"
container_cpu          = 2
container_memory       = 4
enable_monitoring      = true
```

## Testing the Deployment

After deployment, test the video processing workflow:

```bash
# Get storage account connection string
STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
    --name <storage-account-name> \
    --resource-group <resource-group-name> \
    --output tsv)

# Upload a test video to trigger the workflow
az storage blob upload \
    --file test-video.mp4 \
    --container-name "input-videos" \
    --name "test-upload-$(date +%s).mp4" \
    --connection-string $STORAGE_CONNECTION_STRING

# Monitor Logic App runs in Azure Portal
echo "Monitor workflow execution at:"
echo "https://portal.azure.com/#@/resource/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Logic/workflows/<logic-app-name>/overview"
```

## Monitoring and Troubleshooting

### Check deployment status:

```bash
# For Bicep deployments
az deployment group list \
    --resource-group <resource-group-name> \
    --output table

# For Terraform deployments
terraform show
```

### Monitor video processing:

```bash
# Check container logs
az container logs \
    --name <container-group-name> \
    --resource-group <resource-group-name>

# List processed videos
az storage blob list \
    --container-name "output-videos" \
    --connection-string $STORAGE_CONNECTION_STRING \
    --output table
```

### Troubleshoot Logic Apps:

```bash
# Check Logic App runs
az logic workflow run list \
    --workflow-name <logic-app-name> \
    --resource-group <resource-group-name> \
    --output table
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-video-workflow \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

## Customization

### Video Processing Options

The FFmpeg container can be customized for different video processing needs:

- **Quality Settings**: Modify CRF values and presets in the processing script
- **Output Formats**: Add multiple format outputs (MP4, WebM, HLS)
- **Resolution Options**: Configure multiple resolution outputs for adaptive streaming
- **Audio Processing**: Add audio normalization and enhancement

### Workflow Extensions

The Logic App workflow can be extended with:

- **Content Analysis**: Integration with Azure Cognitive Services
- **Notification Services**: Email or SMS notifications on completion
- **Parallel Processing**: Multiple container groups for different quality levels
- **Error Handling**: Advanced retry logic and failure notifications

### Security Enhancements

Consider implementing:

- **Managed Identity**: Use managed identities instead of connection strings
- **Key Vault**: Store sensitive configuration in Azure Key Vault
- **Network Security**: Virtual network integration for container isolation
- **Access Controls**: RBAC for fine-grained permissions

## Performance Optimization

### Container Scaling

- Adjust CPU and memory allocation based on video complexity
- Use multiple container groups for parallel processing
- Consider Azure Container Apps for auto-scaling capabilities

### Storage Optimization

- Use appropriate storage tiers for input/output content
- Implement lifecycle management for processed videos
- Consider Azure CDN for content distribution

## Cost Management

### Resource Optimization

- Container Instances charge per second - optimize processing time
- Use cool storage tiers for archived content
- Monitor Logic App execution costs
- Implement auto-shutdown for development environments

### Cost Monitoring

```bash
# Check current costs
az consumption usage list \
    --billing-period-name $(az billing period list --query '[0].name' -o tsv) \
    --output table
```

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for solution architecture details
2. Review Azure service documentation for specific resource configurations
3. Validate Azure CLI authentication and permissions
4. Check Azure service limits and quotas for your subscription

## Additional Resources

- [Azure Container Instances Documentation](https://docs.microsoft.com/en-us/azure/container-instances/)
- [Azure Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [Azure Event Grid Documentation](https://docs.microsoft.com/en-us/azure/event-grid/)
- [FFmpeg Documentation](https://ffmpeg.org/documentation.html)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)