# Infrastructure as Code for Simple Cost Budget Tracking with Cost Management

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Cost Budget Tracking with Cost Management". This solution provides automated cost budgets with email alert notifications using Azure Cost Management and Azure Monitor to track spending against predefined thresholds.

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.0.81 or later)
- Azure subscription with Contributor or Cost Management Contributor permissions
- Valid email address for receiving budget alerts
- Basic understanding of Azure billing and cost concepts

### Required Azure Permissions

- Cost Management Contributor role (or higher) at subscription level
- Contributor permissions for creating resource groups and monitor resources

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to bicep directory
cd bicep/

# Set required parameters
RESOURCE_GROUP="rg-cost-tracking-$(openssl rand -hex 3)"
LOCATION="eastus"
EMAIL_ADDRESS="your-email@example.com"
BUDGET_AMOUNT="100"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file main.bicep \
    --parameters \
        budgetAmount=${BUDGET_AMOUNT} \
        emailAddress=${EMAIL_ADDRESS} \
        location=${LOCATION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
resource_group_name = "rg-cost-tracking-$(openssl rand -hex 3)"
location = "eastus"
budget_amount = "100"
email_address = "your-email@example.com"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Set environment variables
export RESOURCE_GROUP="rg-cost-tracking-$(openssl rand -hex 3)"
export LOCATION="eastus"
export EMAIL_ADDRESS="your-email@example.com"
export BUDGET_AMOUNT="100"

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy infrastructure
./deploy.sh
```

## Configuration Options

### Budget Settings

- **Budget Amount**: Monthly spending limit (default: $100)
- **Alert Thresholds**: 50%, 80%, and 100% of budget amount
- **Time Period**: Monthly recurring budget
- **Scope**: Subscription-level monitoring

### Alert Configuration

- **Email Notifications**: Immediate email alerts when thresholds are exceeded
- **Alert Types**: Both actual spending and forecasted spending alerts
- **Action Groups**: Centralized notification management for scaling

### Resource Scope

- **Subscription Budget**: Monitors all costs within the subscription
- **Resource Group Budget**: Optional filtered budget for specific resource groups
- **Tag-based Filtering**: Support for monitoring specific tagged resources

## Customization

### Bicep Parameters

Edit the following parameters in `main.bicep` or pass via command line:

```bicep
@description('Monthly budget amount in USD')
param budgetAmount string = '100'

@description('Email address for budget notifications')
param emailAddress string

@description('Azure region for resources')
param location string = resourceGroup().location

@description('Budget alert thresholds as percentages')
param alertThresholds array = [50, 80, 100]
```

### Terraform Variables

Modify `variables.tf` or create `terraform.tfvars`:

```hcl
variable "budget_amount" {
  description = "Monthly budget amount in USD"
  type        = string
  default     = "100"
}

variable "email_address" {
  description = "Email address for budget notifications"
  type        = string
}

variable "alert_thresholds" {
  description = "Budget alert thresholds as percentages"
  type        = list(number)
  default     = [50, 80, 100]
}
```

### Script Environment Variables

Set these variables before running bash scripts:

```bash
export RESOURCE_GROUP="your-resource-group-name"
export LOCATION="eastus"
export EMAIL_ADDRESS="your-email@example.com"
export BUDGET_AMOUNT="100"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
```

## Validation & Testing

### Verifying Deployment

1. **Check Budget Creation**:
   ```bash
   # List all budgets
   az consumption budget list --scope "/subscriptions/$(az account show --query id -o tsv)"
   ```

2. **Test Action Group**:
   ```bash
   # Send test notification
   az monitor action-group test-notifications create \
       --action-group-name "cost-alert-group" \
       --resource-group ${RESOURCE_GROUP} \
       --alert-type "budget"
   ```

3. **View in Azure Portal**:
   - Navigate to Cost Management + Billing
   - Select Budgets to view configured budgets
   - Check Action Groups in Azure Monitor

### Expected Outputs

- **Budget**: Monthly $100 budget with 3-tier alerting
- **Action Group**: Email notification system
- **Alerts**: Progressive warnings at 50%, 80%, and 100% thresholds

## Cleanup

### Using Bicep

```bash
# Delete resource group (removes all resources)
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait

# Delete subscription-level budgets manually if needed
az consumption budget delete \
    --budget-name "monthly-cost-budget" \
    --scope "/subscriptions/$(az account show --query id -o tsv)"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Confirm deletion when prompted
```

## Cost Considerations

- **Cost Management**: Free Azure service
- **Azure Monitor**: Free for basic alerts and action groups
- **Resource Group**: No additional cost
- **Total Estimated Cost**: $0/month for the monitoring infrastructure

> **Note**: The budget monitoring system itself incurs no charges. Costs are only associated with the actual Azure resources being monitored.

## Troubleshooting

### Common Issues

1. **Permission Denied**:
   - Ensure you have Cost Management Contributor role
   - Verify subscription-level permissions

2. **Email Not Received**:
   - Check spam/junk folders
   - Verify email address in action group configuration
   - Whitelist azure-noreply@microsoft.com

3. **Budget Not Triggering**:
   - Budgets evaluate costs every 4-8 hours
   - Ensure sufficient spending to trigger thresholds
   - Check budget scope and filters

4. **API Version Errors**:
   - Ensure using latest Azure CLI version
   - Update REST API versions in scripts if needed

### Getting Help

- [Azure Cost Management Documentation](https://learn.microsoft.com/en-us/azure/cost-management-billing/)
- [Azure Monitor Action Groups](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/action-groups)
- [Azure Budgets API Reference](https://learn.microsoft.com/en-us/rest/api/consumption/budgets)

## Security Best Practices

- **Least Privilege**: Use Cost Management Contributor role instead of Contributor when possible
- **Email Security**: Configure email filtering to prevent alert bypass
- **Action Group Security**: Limit action group permissions to necessary contacts
- **Budget Scope**: Use filtered budgets for granular cost control

## Advanced Features

### Multi-Level Budgets

Create hierarchical budgets for different organizational units:

```bash
# Management group budget
az consumption budget create \
    --scope "/providers/Microsoft.Management/managementGroups/your-mg-id" \
    --budget-name "management-group-budget"

# Resource group budget
az consumption budget create \
    --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
    --budget-name "resource-group-budget"
```

### Custom Alert Actions

Extend action groups with Logic Apps or webhooks for automated responses:

```bash
# Add webhook to action group
az monitor action-group create \
    --name "advanced-cost-alerts" \
    --resource-group ${RESOURCE_GROUP} \
    --action webhook "cost-webhook" "https://your-endpoint.com/webhook"
```

### Tag-Based Budgets

Create budgets that monitor costs for specific tags:

```bash
# Budget filtered by tags
az consumption budget create \
    --budget-name "project-alpha-budget" \
    --amount 50 \
    --time-grain "Monthly" \
    --scope "/subscriptions/${SUBSCRIPTION_ID}" \
    --filter '{
        "dimensions": {
            "name": "ResourceGroupName",
            "operator": "In", 
            "values": ["rg-project-alpha"]
        }
    }'
```

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation
2. Check Azure Cost Management documentation
3. Review Azure CLI command reference
4. Contact Azure support for platform-specific issues

## Contributing

When modifying this infrastructure code:

1. Test changes in a non-production subscription
2. Validate all deployment methods work correctly
3. Update documentation to reflect changes
4. Follow Azure naming conventions and best practices