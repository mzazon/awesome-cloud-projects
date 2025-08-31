# Automated Content Moderation with Content Safety and Logic Apps - Bicep Deployment

This directory contains Azure Bicep templates for deploying the automated content moderation solution described in the recipe. The solution uses Azure AI Content Safety, Logic Apps, and Storage Accounts to create an intelligent content moderation workflow.

## Architecture Overview

The Bicep template deploys the following Azure resources:

- **Azure AI Content Safety**: Analyzes uploaded content for harmful material across multiple categories (sexual, violence, hate, self-harm)
- **Azure Storage Account**: Stores uploaded content and triggers workflow events
- **Azure Logic Apps**: Orchestrates the content moderation workflow with automated decision-making
- **Azure Blob Storage Connection**: Enables Logic Apps to interact with the storage account

## Prerequisites

Before deploying this template, ensure you have:

1. **Azure CLI** installed and configured
2. **Azure subscription** with appropriate permissions to create:
   - Cognitive Services accounts
   - Storage accounts
   - Logic Apps
   - Web connections
3. **Resource group** where resources will be deployed
4. **Bicep CLI** installed (or use Azure Cloud Shell)

## Files in this Directory

- `main.bicep` - Main Bicep template with all resource definitions
- `parameters.json` - Default parameter values for demo/testing
- `parameters.dev.json` - Development environment parameters (uses free tier)
- `parameters.prod.json` - Production environment parameters (uses premium storage)
- `README.md` - This file with deployment instructions

## Parameter Configuration

### Key Parameters

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `namePrefix` | Prefix for resource names | `contmod` | Any valid string |
| `location` | Azure region for deployment | `eastus` | Any Azure region |
| `environment` | Environment designation | `demo` | dev, test, prod, etc. |
| `contentSafetyPricingTier` | Content Safety pricing tier | `S0` | `F0` (free), `S0` (standard) |
| `storageAccountPricingTier` | Storage account redundancy | `Standard_LRS` | LRS, ZRS, GRS, RAGRS |
| `autoApprovalThreshold` | Max severity for auto-approval | `0` | 0-6 (lower = stricter) |
| `autoRejectionThreshold` | Min severity for auto-rejection | `4` | 0-6 (higher = more permissive) |

### Content Safety Severity Levels

The Azure AI Content Safety service returns severity levels from 0-6 for each category:

- **0-1**: Safe content (typically auto-approved)
- **2-3**: Moderate risk (typically requires human review)
- **4-6**: High risk (typically auto-rejected)

Adjust thresholds based on your organization's content policies and risk tolerance.

## Deployment Instructions

### 1. Deploy with Default Parameters (Demo Environment)

```bash
# Create resource group
az group create --name rg-content-moderation-demo --location eastus

# Deploy template with default parameters
az deployment group create \
    --resource-group rg-content-moderation-demo \
    --template-file main.bicep \
    --parameters @parameters.json
```

### 2. Deploy for Development Environment

```bash
# Create resource group
az group create --name rg-content-moderation-dev --location eastus

# Deploy with development parameters (uses free tier)
az deployment group create \
    --resource-group rg-content-moderation-dev \
    --template-file main.bicep \
    --parameters @parameters.dev.json
```

### 3. Deploy for Production Environment

```bash
# Create resource group
az group create --name rg-content-moderation-prod --location eastus

# Deploy with production parameters
az deployment group create \
    --resource-group rg-content-moderation-prod \
    --template-file main.bicep \
    --parameters @parameters.prod.json
```

### 4. Deploy with Custom Parameters

```bash
# Deploy with inline parameter overrides
az deployment group create \
    --resource-group rg-content-moderation-custom \
    --template-file main.bicep \
    --parameters namePrefix=myorg environment=staging location=westus2
```

### 5. Validate Template Before Deployment

```bash
# Validate template syntax and parameters
az deployment group validate \
    --resource-group rg-content-moderation-demo \
    --template-file main.bicep \
    --parameters @parameters.json
```

## Post-Deployment Configuration

After successful deployment, you'll need to:

### 1. Verify Resource Creation

```bash
# List all resources in the resource group
az resource list --resource-group rg-content-moderation-demo --output table

# Get deployment outputs
az deployment group show \
    --resource-group rg-content-moderation-demo \
    --name main \
    --query properties.outputs
```

### 2. Test Content Upload

```bash
# Get storage account name from deployment outputs
STORAGE_ACCOUNT=$(az deployment group show \
    --resource-group rg-content-moderation-demo \
    --name main \
    --query properties.outputs.storageAccountName.value -o tsv)

# Upload test content
echo "This is a test message for content moderation." > test-content.txt
az storage blob upload \
    --account-name $STORAGE_ACCOUNT \
    --container-name content-uploads \
    --name test-$(date +%s).txt \
    --file test-content.txt \
    --auth-mode login
```

### 3. Monitor Logic App Execution

```bash
# Get Logic App name
LOGIC_APP=$(az deployment group show \
    --resource-group rg-content-moderation-demo \
    --name main \
    --query properties.outputs.logicAppName.value -o tsv)

# View recent Logic App runs
az logic workflow list-runs \
    --resource-group rg-content-moderation-demo \
    --name $LOGIC_APP \
    --top 5
```

## Customization Options

### 1. Modify Content Safety Thresholds

Edit the parameters file to adjust content moderation sensitivity:

```json
{
  "autoApprovalThreshold": {
    "value": 1  // More permissive auto-approval
  },
  "autoRejectionThreshold": {
    "value": 3  // Stricter auto-rejection
  }
}
```

### 2. Add Additional Logic App Actions

Modify the Logic App workflow definition in `main.bicep` to add:

- Email notifications
- Teams/Slack integration
- Database logging
- Webhook callbacks
- File quarantine actions

### 3. Configure Network Security

For production deployments, consider adding:

- Private endpoints for storage accounts
- Virtual network integration for Logic Apps
- Network access restrictions for Content Safety

## Monitoring and Troubleshooting

### View Logic App Run History

```bash
# Get detailed run information
az logic workflow show \
    --resource-group rg-content-moderation-demo \
    --name $LOGIC_APP

# View specific run details
az logic workflow run show \
    --resource-group rg-content-moderation-demo \
    --workflow-name $LOGIC_APP \
    --run-name <run-id>
```

### Check Content Safety Service Health

```bash
# Get Content Safety endpoint
CONTENT_SAFETY_ENDPOINT=$(az deployment group show \
    --resource-group rg-content-moderation-demo \
    --name main \
    --query properties.outputs.contentSafetyEndpoint.value -o tsv)

echo "Content Safety endpoint: $CONTENT_SAFETY_ENDPOINT"
```

### Common Issues and Solutions

1. **Logic App not triggering**: Verify blob container exists and has proper permissions
2. **Content Safety API errors**: Check pricing tier limits and API quotas
3. **Storage connection issues**: Validate storage account key and connection string
4. **Permission errors**: Ensure Logic App has proper access to storage and Content Safety

## Cost Optimization

### Development/Testing
- Use `F0` (free) tier for Content Safety
- Use `Standard_LRS` for storage account
- Set more restrictive thresholds to reduce API calls

### Production
- Monitor API usage and adjust pricing tiers accordingly
- Use `Standard_GRS` for storage redundancy
- Implement lifecycle policies for old content
- Consider using Azure Monitor for cost tracking

## Security Considerations

1. **Storage Account**: Private blob access is enforced by default
2. **Content Safety**: API keys are managed through Azure Key Vault integration
3. **Logic Apps**: Uses managed identity where possible
4. **Network Access**: Configure network restrictions for production environments

## Clean Up Resources

To avoid ongoing charges, delete the resource group when no longer needed:

```bash
# Delete resource group and all resources
az group delete --name rg-content-moderation-demo --yes --no-wait
```

## Support and Troubleshooting

For issues with this template:

1. Check the [Azure Logic Apps documentation](https://docs.microsoft.com/azure/logic-apps/)
2. Review [Azure AI Content Safety documentation](https://docs.microsoft.com/azure/ai-services/content-safety/)
3. Validate Bicep template syntax using Azure CLI
4. Check Azure Activity Log for deployment errors

## Additional Resources

- [Azure Bicep Documentation](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)
- [Azure AI Content Safety API Reference](https://docs.microsoft.com/rest/api/contentsafety/)
- [Logic Apps Workflow Definition Language](https://docs.microsoft.com/azure/logic-apps/logic-apps-workflow-definition-language)
- [Azure Storage Events and Event Grid](https://docs.microsoft.com/azure/storage/blobs/storage-blob-event-overview)