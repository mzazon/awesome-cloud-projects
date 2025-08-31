# Simple Cost Budget Tracking with Cost Management - Bicep Templates

This directory contains Azure Bicep templates for deploying the Simple Cost Budget Tracking solution using Azure Cost Management and Azure Monitor.

## Architecture Overview

The solution deploys:

- **Resource Group**: Container for monitoring resources with comprehensive tagging
- **Azure Monitor Action Group**: Email notification system for budget alerts
- **Subscription-Level Budget**: Monitors overall subscription spending with multi-threshold alerts
- **Resource Group-Level Budget**: Targeted cost monitoring for specific resource groups

## Alert Configuration

The budgets are configured with three progressive alert thresholds:
- **50% Threshold**: Early warning (Actual spending)
- **80% Threshold**: Critical warning (Actual spending)
- **100% Threshold**: Overage alert (Forecasted spending)

## Files Structure

```
bicep/
├── main.bicep              # Main template with subscription scope
├── modules/
│   └── actionGroup.bicep   # Action Group module for email notifications
├── parameters.json         # Example parameter values
└── README.md              # This documentation
```

## Prerequisites

- Azure CLI version 2.20.0 or later
- Azure subscription with Contributor or Cost Management Contributor permissions
- Valid email address for receiving budget alerts
- Bicep CLI extension (`az bicep install`)

## Parameters

| Parameter | Type | Description | Default | Required |
|-----------|------|-------------|---------|----------|
| `uniqueSuffix` | string | Unique suffix for resource names (3-8 chars) | Generated | No |
| `location` | string | Azure region for deployment | eastus | No |
| `alertEmailAddress` | string | Email for budget notifications | - | Yes |
| `subscriptionBudgetAmount` | int | Monthly subscription budget ($1-$100,000) | 100 | No |
| `resourceGroupBudgetAmount` | int | Monthly resource group budget ($1-$100,000) | 50 | No |
| `budgetStartDate` | string | Budget start date (YYYY-MM-DD) | Current month | No |
| `budgetEndDate` | string | Budget end date (YYYY-MM-DD) | +1 year | No |
| `environment` | string | Environment tag (dev/test/stage/prod/demo) | demo | No |
| `costCenter` | string | Cost center for attribution | IT | No |
| `projectName` | string | Project name for grouping | CostManagement | No |

## Deployment Instructions

### 1. Quick Start Deployment

```bash
# Clone or download the template files
# Update parameters.json with your email address and preferences

# Deploy using parameter file
az deployment sub create \
    --name "cost-budget-tracking-$(date +%Y%m%d-%H%M)" \
    --location eastus \
    --template-file main.bicep \
    --parameters @parameters.json
```

### 2. Interactive Deployment

```bash
# Deploy with inline parameters
az deployment sub create \
    --name "cost-budget-tracking-$(date +%Y%m%d-%H%M)" \
    --location eastus \
    --template-file main.bicep \
    --parameters alertEmailAddress="your-email@company.com" \
                 subscriptionBudgetAmount=200 \
                 resourceGroupBudgetAmount=100 \
                 environment="prod"
```

### 3. Custom Configuration Deployment

```bash
# Set environment variables
export ALERT_EMAIL="admin@yourcompany.com"
export BUDGET_AMOUNT="500"
export LOCATION="westus2"
export ENVIRONMENT="prod"

# Deploy with custom values
az deployment sub create \
    --name "cost-budget-tracking-$(date +%Y%m%d-%H%M)" \
    --location $LOCATION \
    --template-file main.bicep \
    --parameters alertEmailAddress="$ALERT_EMAIL" \
                 subscriptionBudgetAmount=$BUDGET_AMOUNT \
                 location="$LOCATION" \
                 environment="$ENVIRONMENT"
```

## Validation Commands

After deployment, validate the resources:

```bash
# Get deployment outputs
az deployment sub show \
    --name "cost-budget-tracking-$(date +%Y%m%d-%H%M)" \
    --query "properties.outputs"

# List created budgets
az consumption budget list \
    --query "[].{Name:name,Amount:amount,CurrentSpend:currentSpend.amount}"

# Verify action group
az monitor action-group list \
    --resource-group "rg-cost-tracking-[suffix]" \
    --query "[].{Name:name,Enabled:enabled}"

# Test email notifications
az monitor action-group test-notifications create \
    --action-group-name "cost-alert-group-[suffix]" \
    --resource-group "rg-cost-tracking-[suffix]" \
    --alert-type "budget"
```

## Monitoring and Management

### Azure Portal URLs

- **Cost Management**: https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/overview
- **Budgets**: https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/budgets
- **Action Groups**: https://portal.azure.com/#view/HubsExtension/BrowseResource/resourceType/Microsoft.Insights%2FactionGroups

### CLI Monitoring Commands

```bash
# Check current month spending
az consumption usage list \
    --start-date "$(date -d 'first day of this month' +%Y-%m-%d)" \
    --end-date "$(date +%Y-%m-%d)" \
    --query "sum([].pretaxCost)"

# Get budget status
az consumption budget show \
    --budget-name "monthly-cost-budget-[suffix]" \
    --query "{Budget:amount,Current:currentSpend.amount,Forecasted:forecastSpend.amount}"
```

## Customization Options

### Additional Alert Channels

Modify the `actionGroup.bicep` module to add:
- SMS notifications
- Webhook integrations
- Logic App triggers
- Azure Function calls

### Budget Filters

Add custom filters to budgets:
```bicep
filter: {
  and: [
    {
      dimensions: {
        name: 'ResourceGroupName'
        operator: 'In'
        values: ['rg-production', 'rg-staging']
      }
    }
    {
      tags: {
        name: 'Environment'
        operator: 'In'
        values: ['prod', 'stage']
      }
    }
  ]
}
```

### Multiple Budget Scenarios

Create additional budgets for:
- Department-specific tracking
- Project-based monitoring
- Service-category budgets
- Geographic region budgets

## Cleanup

To remove all resources:

```bash
# Get the resource group name from deployment outputs
RG_NAME=$(az deployment sub show \
    --name "cost-budget-tracking-$(date +%Y%m%d-%H%M)" \
    --query "properties.outputs.resourceGroupName.value" -o tsv)

# Delete budgets (they exist at subscription level)
az consumption budget delete --budget-name "monthly-cost-budget-[suffix]"
az consumption budget delete --budget-name "rg-budget-[suffix]"

# Delete resource group and contained resources
az group delete --name "$RG_NAME" --yes --no-wait
```

## Security Considerations

- **Email Security**: Whitelist azure-noreply@microsoft.com to prevent alert emails from being filtered
- **RBAC**: Ensure proper Cost Management Contributor permissions
- **Resource Tags**: Maintain consistent tagging for cost allocation and governance
- **Action Group Security**: Limit access to action group modifications

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure you have Cost Management Contributor role at subscription level
2. **Email Not Received**: Check spam folder and whitelist Azure notification addresses
3. **Budget Creation Failed**: Verify subscription ID and budget name uniqueness
4. **Action Group Test Failed**: Confirm email address is valid and accessible

### Debug Commands

```bash
# Check current user permissions
az role assignment list --assignee $(az account show --query user.name -o tsv) \
    --scope "/subscriptions/$(az account show --query id -o tsv)"

# Validate template before deployment
az deployment sub validate \
    --location eastus \
    --template-file main.bicep \
    --parameters @parameters.json

# Check deployment status
az deployment sub list \
    --query "[?contains(name, 'cost-budget-tracking')].{Name:name,State:properties.provisioningState,Timestamp:properties.timestamp}"
```

## Support and Documentation

- [Azure Cost Management Documentation](https://learn.microsoft.com/en-us/azure/cost-management-billing/)
- [Azure Monitor Action Groups](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/action-groups)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Recipe Documentation](../simple-cost-budget-tracking-cost-management.md)

## Best Practices

1. **Regular Review**: Monitor budget performance monthly and adjust thresholds as needed
2. **Tag Consistency**: Use consistent resource tagging for accurate cost allocation
3. **Alert Tuning**: Adjust notification thresholds based on spending patterns
4. **Automation**: Consider integrating with Logic Apps for automated responses
5. **Documentation**: Keep deployment parameters documented for future reference