# Infrastructure as Code for Intelligent Vision Model Retraining with Custom Vision MLOps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Vision Model Retraining with Custom Vision MLOps".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (ARM template language)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login` completed)
- Appropriate Azure subscription permissions for:
  - Cognitive Services (Custom Vision)
  - Logic Apps
  - Storage Accounts
  - Log Analytics Workspaces
  - Resource Groups
- For Terraform: Terraform >= 1.0 installed
- For Bicep: Azure CLI with Bicep extension installed
- Bash shell environment (Linux, macOS, or WSL on Windows)

## Architecture Overview

This solution deploys:
- **Azure Blob Storage**: Scalable storage for training images and model artifacts
- **Azure Custom Vision**: Managed computer vision service for model training
- **Azure Logic Apps**: Serverless workflow orchestration for automated retraining
- **Azure Monitor**: Performance tracking and alerting for the MLOps pipeline

## Quick Start

### Using Bicep

```bash
# Navigate to Bicep directory
cd bicep/

# Create resource group
az group create --name rg-cv-retraining --location eastus

# Deploy infrastructure
az deployment group create \
    --resource-group rg-cv-retraining \
    --template-file main.bicep \
    --parameters @parameters.json

# Get deployment outputs
az deployment group show \
    --resource-group rg-cv-retraining \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your specific values
# resource_group_name = "rg-cv-retraining"
# location = "East US"

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for resource configuration
```

## Configuration Options

### Bicep Parameters

Key parameters available in `parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "resourceGroupName": {
      "value": "rg-cv-retraining"
    },
    "location": {
      "value": "eastus"
    },
    "storageAccountName": {
      "value": "stcvretrain"
    },
    "customVisionName": {
      "value": "cv-service"
    },
    "logicAppName": {
      "value": "logic-cv-retrain"
    },
    "logAnalyticsWorkspaceName": {
      "value": "log-cv-monitor"
    },
    "customVisionSku": {
      "value": "S0"
    },
    "storageAccountTier": {
      "value": "Standard_LRS"
    },
    "environment": {
      "value": "demo"
    }
  }
}
```

### Terraform Variables

Key variables available in `terraform.tfvars`:

```hcl
# Resource configuration
resource_group_name = "rg-cv-retraining"
location = "East US"

# Storage configuration
storage_account_name = "stcvretrain"
storage_account_tier = "Standard_LRS"
storage_account_replication_type = "LRS"

# Custom Vision configuration
custom_vision_name = "cv-service"
custom_vision_sku = "S0"

# Logic App configuration
logic_app_name = "logic-cv-retrain"

# Monitoring configuration
log_analytics_workspace_name = "log-cv-monitor"
log_analytics_sku = "PerGB2018"

# Tagging
environment = "demo"
purpose = "ml-automation"
```

## Post-Deployment Configuration

After infrastructure deployment, complete these manual steps:

1. **Configure Logic App Connections**:
   ```bash
   # The Logic App requires API connections to be authorized
   # Navigate to Azure portal > Logic Apps > your-logic-app > API connections
   # Authorize the Azure Blob Storage connection
   ```

2. **Create Custom Vision Project**:
   ```bash
   # Get Custom Vision endpoint and key from deployment outputs
   # Use the provided API calls to create your vision project
   ```

3. **Upload Training Data**:
   ```bash
   # Upload initial training images to the storage account
   az storage blob upload-batch \
       --destination training-images \
       --source ./training-data \
       --account-name <storage-account-name>
   ```

## Testing the Deployment

### Verify Storage Account

```bash
# List storage containers
az storage container list \
    --account-name <storage-account-name> \
    --output table

# Upload test image
echo "Test image data" > test-image.jpg
az storage blob upload \
    --account-name <storage-account-name> \
    --container-name training-images \
    --name test-folder/test-image.jpg \
    --file test-image.jpg
```

### Verify Custom Vision Service

```bash
# Get Custom Vision details
az cognitiveservices account show \
    --name <custom-vision-name> \
    --resource-group <resource-group-name>

# Test API connectivity
CUSTOM_VISION_KEY=$(az cognitiveservices account keys list \
    --name <custom-vision-name> \
    --resource-group <resource-group-name> \
    --query 'key1' --output tsv)

CUSTOM_VISION_ENDPOINT=$(az cognitiveservices account show \
    --name <custom-vision-name> \
    --resource-group <resource-group-name> \
    --query 'properties.endpoint' --output tsv)

curl -X GET \
    -H "Training-Key: ${CUSTOM_VISION_KEY}" \
    "${CUSTOM_VISION_ENDPOINT}customvision/v3.0/Training/projects"
```

### Verify Logic App

```bash
# Check Logic App status
az logic workflow show \
    --resource-group <resource-group-name> \
    --name <logic-app-name> \
    --query '{name:name, state:state, location:location}'

# View run history
az logic workflow list-runs \
    --resource-group <resource-group-name> \
    --name <logic-app-name> \
    --output table
```

## Monitoring and Observability

### View Metrics

```bash
# Custom Vision metrics
az monitor metrics list \
    --resource "/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.CognitiveServices/accounts/<custom-vision-name>" \
    --metric "TotalCalls,SuccessfulCalls" \
    --aggregation Average \
    --interval PT1H

# Logic App metrics
az monitor metrics list \
    --resource "/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.Logic/workflows/<logic-app-name>" \
    --metric "RunsStarted,RunsCompleted,RunsFailed" \
    --aggregation Total \
    --interval PT1H
```

### View Alerts

```bash
# List configured alerts
az monitor metrics alert list \
    --resource-group <resource-group-name> \
    --output table
```

## Troubleshooting

### Common Issues

1. **Logic App Connection Authorization**:
   - Navigate to Azure Portal > Logic Apps > API connections
   - Ensure all connections are authorized and valid

2. **Custom Vision Training Failures**:
   - Verify minimum 15 images per tag requirement
   - Check training data format and quality
   - Review Custom Vision project configuration

3. **Storage Access Issues**:
   - Verify storage account access keys
   - Check container permissions and access policies
   - Validate blob storage connection strings

### Debug Commands

```bash
# View detailed Logic App run information
az logic workflow show-run \
    --resource-group <resource-group-name> \
    --name <logic-app-name> \
    --run-name <run-id>

# Check storage account activity
az storage logging show \
    --account-name <storage-account-name>

# View Custom Vision service logs
az monitor activity-log list \
    --resource-group <resource-group-name> \
    --resource-type "Microsoft.CognitiveServices/accounts"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-cv-retraining \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for resource deletion confirmation
```

### Manual Cleanup Verification

```bash
# Verify resource group deletion
az group exists --name rg-cv-retraining

# Check for any remaining resources
az resource list \
    --resource-group rg-cv-retraining \
    --output table
```

## Cost Optimization

### Cost Monitoring

```bash
# View resource group costs
az consumption usage list \
    --resource-group <resource-group-name> \
    --output table

# Set up cost alerts
az consumption budget create \
    --resource-group <resource-group-name> \
    --budget-name "cv-retraining-budget" \
    --amount 100 \
    --time-grain Monthly
```

### Cost Optimization Tips

- Use Azure Storage cool tier for long-term model artifact storage
- Monitor Custom Vision API call usage to optimize training frequency
- Configure Logic App to run only during business hours if appropriate
- Use Log Analytics data retention policies to manage monitoring costs

## Security Considerations

### Access Control

- Custom Vision service uses API keys for authentication
- Logic Apps use managed identity where possible
- Storage accounts configured with private endpoints when needed
- All resources follow principle of least privilege

### Data Protection

- Storage accounts encrypted at rest and in transit
- Custom Vision models remain within Azure tenant
- Log Analytics workspace configured with appropriate retention
- Network security groups restrict access to necessary ports only

## Support and Documentation

### Azure Service Documentation

- [Azure Custom Vision Documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/custom-vision-service/)
- [Azure Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [Azure Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)

### Infrastructure as Code Resources

- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure CLI Reference](https://docs.microsoft.com/en-us/cli/azure/)

### Additional Resources

- [Azure MLOps Best Practices](https://docs.microsoft.com/en-us/azure/machine-learning/concept-ml-pipelines)
- [Azure Cost Management](https://docs.microsoft.com/en-us/azure/cost-management-billing/)
- [Azure Security Best Practices](https://docs.microsoft.com/en-us/azure/security/fundamentals/best-practices-and-patterns)

For issues with this infrastructure code, refer to the original recipe documentation or the Azure service documentation links above.