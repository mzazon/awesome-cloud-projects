# Infrastructure as Code for Budget Alert Notifications with Cost Management and Logic Apps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Budget Alert Notifications with Cost Management and Logic Apps".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with Cost Management access
- Office 365 Outlook account for email notifications
- Appropriate permissions:
  - Cost Management Contributor role for budget creation
  - Contributor role for resource group and Logic Apps
  - User Access Administrator for Action Group configuration
- PowerShell 7+ (for Bicep deployment)
- Terraform 1.0+ (for Terraform deployment)

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to bicep directory
cd bicep/

# Set deployment parameters
RESOURCE_GROUP="rg-budget-alerts-demo"
LOCATION="eastus"
DEPLOYMENT_NAME="budget-alerts-$(date +%Y%m%d-%H%M%S)"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file main.bicep \
    --name ${DEPLOYMENT_NAME} \
    --parameters location=${LOCATION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="resource_group_name=rg-budget-alerts-demo" \
    -var="location=eastus"

# Apply infrastructure
terraform apply \
    -var="resource_group_name=rg-budget-alerts-demo" \
    -var="location=eastus"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration parameters
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for resources | `eastus` | Yes |
| `budgetAmount` | Monthly budget limit in USD | `100` | No |
| `alertThresholds` | Budget alert thresholds | `[80, 100]` | No |
| `resourcePrefix` | Prefix for resource names | `budget-demo` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `resource_group_name` | Name of the resource group | `rg-budget-alerts` | Yes |
| `location` | Azure region for resources | `eastus` | Yes |
| `budget_amount` | Monthly budget limit in USD | `100` | No |
| `alert_thresholds` | Budget alert thresholds | `[80, 100]` | No |
| `environment` | Environment tag | `demo` | No |

## Post-Deployment Configuration

After infrastructure deployment, complete these manual steps:

### 1. Configure Logic App Workflow

```bash
# Get Logic App information
LOGIC_APP_NAME=$(az logicapp list --resource-group ${RESOURCE_GROUP} --query "[0].name" -o tsv)
RESOURCE_GROUP_NAME=$(az group list --query "[?contains(name, 'budget-alerts')].name" -o tsv)

echo "Configure Logic App: ${LOGIC_APP_NAME}"
echo "Resource Group: ${RESOURCE_GROUP_NAME}"
echo ""
echo "Complete these steps in Azure Portal:"
echo "1. Navigate to Logic App: ${LOGIC_APP_NAME}"
echo "2. Create new workflow with HTTP trigger"
echo "3. Add Office 365 Outlook connector for email notifications"
echo "4. Configure email template with budget alert data"
```

### 2. Update Action Group with Logic App Callback URL

```bash
# After configuring Logic App workflow, update Action Group
# Get the HTTP trigger callback URL from Logic App and run:

ACTION_GROUP_NAME=$(az monitor action-group list --resource-group ${RESOURCE_GROUP} --query "[0].name" -o tsv)
LOGIC_APP_CALLBACK_URL="<YOUR_LOGIC_APP_HTTP_TRIGGER_URL>"

az monitor action-group update \
    --resource-group ${RESOURCE_GROUP} \
    --name ${ACTION_GROUP_NAME} \
    --logic-app-receivers name="BudgetLogicApp" \
        resource-id="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/sites/${LOGIC_APP_NAME}" \
        callback-url="${LOGIC_APP_CALLBACK_URL}" \
        use-common-alert-schema=true
```

## Validation

### Verify Budget Configuration

```bash
# List all budgets in subscription
az consumption budget list --query "[].{Name:name, Amount:amount, TimeGrain:timeGrain}" -o table

# Check specific budget details
BUDGET_NAME=$(az consumption budget list --query "[?contains(name, 'budget-demo')].name" -o tsv)
az consumption budget show --budget-name ${BUDGET_NAME}
```

### Verify Action Group Configuration

```bash
# Check Action Group status
az monitor action-group list --resource-group ${RESOURCE_GROUP} \
    --query "[].{Name:name, Enabled:enabled, Receivers:length(logicAppReceivers)}" -o table
```

### Test Logic App Connectivity

```bash
# Get Logic App status
az logicapp show --resource-group ${RESOURCE_GROUP} --name ${LOGIC_APP_NAME} \
    --query "{Name:name, State:state, URL:defaultHostName}" -o table
```

## Monitoring and Troubleshooting

### View Budget Alert History

```bash
# Check recent budget notifications
az monitor activity-log list \
    --start-time $(date -d '7 days ago' -u +%Y-%m-%dT%H:%M:%SZ) \
    --resource-group ${RESOURCE_GROUP} \
    --query "[?contains(operationName.localizedValue, 'Budget')]"
```

### Monitor Logic App Runs

```bash
# View Logic App run history (requires workflow name)
az logicapp workflow list --resource-group ${RESOURCE_GROUP} --name ${LOGIC_APP_NAME}
```

### Debug Action Group Notifications

```bash
# Test Action Group manually
az monitor action-group enable-receiver \
    --resource-group ${RESOURCE_GROUP} \
    --action-group-name ${ACTION_GROUP_NAME} \
    --receiver-name "BudgetLogicApp"
```

## Cleanup

### Using Bicep

```bash
# Delete resource group and all resources
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait

# Verify deletion
az group exists --name ${RESOURCE_GROUP}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="resource_group_name=rg-budget-alerts-demo" \
    -var="location=eastus"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

### Manual Cleanup (if needed)

```bash
# Remove budget (budgets are subscription-scoped)
BUDGET_NAME=$(az consumption budget list --query "[?contains(name, 'budget-demo')].name" -o tsv)
az consumption budget delete --budget-name ${BUDGET_NAME}

# Clean up resource group
az group delete --name ${RESOURCE_GROUP} --yes
```

## Customization

### Modifying Budget Thresholds

Edit the budget configuration in your chosen IaC template:

**Bicep (main.bicep):**
```bicep
param alertThresholds array = [50, 80, 90, 100]
```

**Terraform (variables.tf):**
```hcl
variable "alert_thresholds" {
  description = "Budget alert thresholds as percentages"
  type        = list(number)
  default     = [50, 80, 90, 100]
}
```

### Adding Multiple Email Recipients

Update the Logic App workflow to include additional email addresses or notification channels like Microsoft Teams.

### Custom Budget Scope

Modify the budget scope to target specific resource groups or resources:

```bash
# Budget for specific resource group
az consumption budget create \
    --budget-name "rg-specific-budget" \
    --amount 50 \
    --resource-group-filter ${TARGET_RESOURCE_GROUP}
```

## Cost Considerations

This solution has minimal cost impact:

- **Logic Apps**: ~$0.000025 per execution (budget alerts are infrequent)
- **Storage Account**: ~$0.02-0.05 per month for Logic App runtime
- **Action Groups**: No additional cost
- **Cost Management Budgets**: No additional cost

Total estimated monthly cost: **$0.02-0.10**

## Security Best Practices

- Logic Apps use managed identity for secure resource access
- Action Groups use Azure RBAC for access control
- Budget alerts contain no sensitive financial data beyond spending amounts
- Email notifications should be sent to authorized personnel only

## Support and Documentation

- [Azure Cost Management Documentation](https://docs.microsoft.com/en-us/azure/cost-management-billing/)
- [Azure Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [Azure Monitor Action Groups](https://docs.microsoft.com/en-us/azure/azure-monitor/alerts/action-groups)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Contributing

For issues with this infrastructure code, refer to the original recipe documentation or file issues in the repository.

## License

This infrastructure code is provided as-is for educational and demonstration purposes.