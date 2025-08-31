# Budget Alert Notifications - Bicep Template

This directory contains Azure Bicep templates for deploying the Budget Alert Notifications solution using Azure Cost Management and Logic Apps.

## Architecture Overview

The template deploys:
- **Azure Storage Account**: Runtime storage for Logic App workflows
- **App Service Plan**: Hosting plan for Logic App (Workflow Standard tier)
- **Logic App**: Serverless workflow automation for processing budget alerts
- **Action Group**: Azure Monitor component that triggers notifications
- **Budget**: Cost Management budget with configurable alert thresholds

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with appropriate permissions:
  - Cost Management Contributor role (for budget creation)
  - Contributor role on target resource group
- Bicep CLI installed (or use Azure Cloud Shell)

## Quick Start

### 1. Clone and Navigate
```bash
cd azure/budget-alert-notifications-cost-management-logic-apps/code/bicep/
```

### 2. Create Resource Group
```bash
# Set variables
RESOURCE_GROUP="rg-budget-alerts-demo"
LOCATION="eastus"

# Create resource group
az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION
```

### 3. Deploy Template
```bash
# Deploy with default parameters
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters @parameters.json

# Or deploy with custom parameters
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters budgetAmount=500 \
                 notificationEmails="your-email@domain.com" \
                 firstThresholdPercentage=75 \
                 secondThresholdPercentage=90
```

### 4. Verify Deployment
```bash
# List deployed resources
az resource list \
    --resource-group $RESOURCE_GROUP \
    --output table

# Get deployment outputs
az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name main \
    --query properties.outputs
```

## Template Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `resourceGroup().location` | Azure region for resource deployment |
| `baseName` | string | `budget-alerts` | Base name for all resources |
| `uniqueSuffix` | string | `uniqueString(resourceGroup().id)` | Unique suffix for global resource names |
| `budgetAmount` | int | `100` | Budget amount in USD (1-1,000,000) |
| `budgetStartDate` | string | `2025-01-01` | Budget start date (YYYY-MM-DD) |
| `budgetEndDate` | string | `2025-12-31` | Budget end date (YYYY-MM-DD) |
| `notificationEmails` | string | `''` | Comma-separated email addresses |
| `firstThresholdPercentage` | int | `80` | First alert threshold (actual spending) |
| `secondThresholdPercentage` | int | `100` | Second alert threshold (forecasted spending) |
| `resourceTags` | object | See parameters.json | Tags applied to all resources |

## Template Outputs

The template provides comprehensive outputs for verification and integration:

- **Resource Names**: Names of all created resources
- **Resource IDs**: Full Azure resource identifiers
- **Configuration Summary**: Budget and alert configuration details
- **Portal URLs**: Direct links to resources in Azure Portal
- **Next Steps**: Guidance for completing the Logic App workflow

## Post-Deployment Configuration

After successful deployment, complete the Logic App workflow configuration:

### 1. Navigate to Logic App
```bash
# Get Logic App portal URL from outputs
az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name main \
    --query properties.outputs.portalUrls.value.logicApp \
    --output tsv
```

### 2. Create Budget Alert Workflow

1. **Create New Workflow**:
   - Name: `BudgetAlertProcessor`
   - Template: `HTTP Request-Response`

2. **Configure HTTP Trigger**:
   - Trigger type: `When a HTTP request is received`
   - Method: `POST`
   - Use sample payload to generate schema

3. **Add Parse JSON Action**:
   - Content: `triggerBody()`
   - Schema: Budget alert schema (see example below)

4. **Add Office 365 Outlook Action**:
   - Action: `Send an email (V2)`
   - Configure email template with dynamic content

### 3. Sample Budget Alert Schema
```json
{
  "type": "object",
  "properties": {
    "schemaId": {"type": "string"},
    "data": {
      "type": "object",
      "properties": {
        "SubscriptionId": {"type": "string"},
        "SubscriptionName": {"type": "string"},
        "BudgetName": {"type": "string"},
        "BudgetType": {"type": "string"},
        "BudgetThreshold": {"type": "number"},
        "BudgetThresholdType": {"type": "string"},
        "BudgetStartDate": {"type": "string"},
        "NotificationThresholdAmount": {"type": "number"},
        "BudgetCreator": {"type": "string"},
        "Unit": {"type": "string"},
        "Amount": {"type": "number"},
        "SpendType": {"type": "string"}
      }
    }
  }
}
```

## Customization Options

### Multiple Email Recipients
```bash
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters notificationEmails="admin@company.com,finance@company.com,manager@company.com"
```

### Different Alert Thresholds
```bash
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters firstThresholdPercentage=60 \
                 secondThresholdPercentage=85
```

### Custom Tags
```bash
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters resourceTags='{"environment":"production","owner":"finance","project":"cost-control"}'
```

## Monitoring and Troubleshooting

### Check Budget Status
```bash
# List all budgets
az consumption budget list --output table

# Get specific budget details
BUDGET_NAME=$(az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name main \
    --query properties.outputs.budgetName.value \
    --output tsv)

az consumption budget show \
    --budget-name $BUDGET_NAME \
    --output table
```

### Monitor Logic App Runs
```bash
# Get Logic App name
LOGIC_APP_NAME=$(az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name main \
    --query properties.outputs.logicAppName.value \
    --output tsv)

# View Logic App metrics
az monitor metrics list \
    --resource "/subscriptions/$(az account show --query id --output tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$LOGIC_APP_NAME" \
    --metric "WorkflowRunsStarted,WorkflowRunsCompleted,WorkflowRunsFailed" \
    --start-time "2025-01-01T00:00:00Z"
```

### Test Action Group
```bash
# Get Action Group ID
ACTION_GROUP_ID=$(az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name main \
    --query properties.outputs.actionGroupResourceId.value \
    --output tsv)

# Test Action Group (this will trigger the Logic App)
az monitor action-group test-notifications create \
    --resource-group $RESOURCE_GROUP \
    --action-group-name $(basename $ACTION_GROUP_ID) \
    --notification-type "logicapp" \
    --receivers "BudgetLogicApp"
```

## Cost Considerations

- **Logic App**: Pay-per-execution model (~$0.000025 per action execution)
- **Storage Account**: Minimal cost for runtime storage (~$0.02/month)
- **Action Group**: No direct cost, included in Azure Monitor
- **Budget**: No cost for budget creation and monitoring

Estimated monthly cost: **$0.50 - $2.00** (depending on alert frequency)

## Security Best Practices

The template implements several security measures:

1. **Storage Account Security**:
   - HTTPS-only traffic
   - Minimum TLS 1.2
   - Blob public access disabled
   - Encryption at rest enabled

2. **Logic App Security**:
   - HTTPS-only communication
   - Managed identity for Azure service authentication
   - Function-level authorization

3. **Action Group Security**:
   - Common alert schema for consistent data format
   - Secure webhook endpoints

## Cleanup

To remove all resources created by this template:

```bash
# Delete the entire resource group
az group delete \
    --name $RESOURCE_GROUP \
    --yes \
    --no-wait

# Verify deletion
az group exists --name $RESOURCE_GROUP
```

## Troubleshooting

### Common Issues

1. **Budget Creation Fails**:
   - Verify Cost Management Contributor permissions
   - Check subscription has billing account access
   - Ensure date format is YYYY-MM-DD

2. **Logic App Deployment Fails**:
   - Verify App Service Plan SKU availability in region
   - Check storage account creation succeeded
   - Ensure unique naming (storage account names must be globally unique)

3. **Action Group Not Triggering**:
   - Verify Logic App HTTP trigger URL is correct
   - Check Action Group receiver configuration
   - Test Action Group manually

### Validation Commands

```bash
# Validate template before deployment
az deployment group validate \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters @parameters.json

# Check deployment status
az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name main \
    --query properties.provisioningState
```

## Support

For issues with this template:
1. Check Azure Activity Log for deployment errors
2. Verify all prerequisites are met
3. Review Azure service limits and quotas
4. Consult Azure Bicep documentation: https://docs.microsoft.com/azure/azure-resource-manager/bicep/

## Related Resources

- [Azure Cost Management budgets](https://docs.microsoft.com/azure/cost-management-billing/costs/tutorial-acm-create-budgets)
- [Azure Logic Apps Standard](https://docs.microsoft.com/azure/logic-apps/logic-apps-overview)
- [Azure Monitor Action Groups](https://docs.microsoft.com/azure/azure-monitor/alerts/action-groups)
- [Azure Bicep documentation](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)