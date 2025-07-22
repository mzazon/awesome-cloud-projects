# Infrastructure as Code for Governance Dashboard Automation with Resource Graph and Monitor Workbooks

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Governance Dashboard Automation with Resource Graph and Monitor Workbooks".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.60.0 or later installed and configured
- Azure subscription with appropriate permissions:
  - Reader permissions across all subscriptions to monitor
  - Contributor permissions for Resource Graph, Monitor Workbooks, Policy, and Logic Apps
- Understanding of Azure Resource Graph query language (KQL)
- Knowledge of Azure Policy and governance concepts
- For Terraform: Terraform v1.0+ installed
- For Bicep: Bicep CLI installed (comes with Azure CLI v2.20.0+)

## Architecture Overview

This solution deploys:
- Azure Monitor Workbooks for governance visualization
- Azure Logic Apps for automated remediation workflows
- Azure Monitor alerts for proactive governance monitoring
- Log Analytics workspace for governance data storage
- Action groups for alert notifications
- Scheduled queries for continuous compliance monitoring

## Quick Start

### Using Bicep (Recommended)

```bash
cd bicep/

# Deploy with default parameters
az deployment group create \
    --resource-group rg-governance-dashboard \
    --template-file main.bicep \
    --parameters @parameters.json

# Or deploy with inline parameters
az deployment group create \
    --resource-group rg-governance-dashboard \
    --template-file main.bicep \
    --parameters workbookName=governance-dashboard \
                 logicAppName=governance-automation \
                 location=eastus
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the configuration
terraform apply

# Confirm deployment when prompted
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the solution
./scripts/deploy.sh

# Follow the prompts to configure resource names and location
```

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "workbookName": {
      "value": "governance-dashboard"
    },
    "logicAppName": {
      "value": "governance-automation"
    },
    "location": {
      "value": "eastus"
    },
    "environment": {
      "value": "production"
    }
  }
}
```

### Terraform Variables

Configure `terraform/terraform.tfvars`:

```hcl
resource_group_name = "rg-governance-dashboard"
location           = "eastus"
workbook_name      = "governance-dashboard"
logic_app_name     = "governance-automation"
environment        = "production"

# Optional: Configure webhook URL for notifications
webhook_url = "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
```

## Post-Deployment Configuration

After deployment, complete these steps:

1. **Configure Resource Graph Queries**: Update the workbook with your organization's specific governance queries
2. **Set Up Notification Webhooks**: Configure the Logic App with your team's notification endpoints
3. **Customize Alert Thresholds**: Adjust alert rules based on your compliance requirements
4. **Test Governance Workflows**: Verify end-to-end functionality from detection to remediation

## Accessing the Dashboard

After deployment, access your governance dashboard:

1. Navigate to Azure Portal
2. Go to Azure Monitor > Workbooks
3. Find your deployed workbook: `governance-dashboard-{suffix}`
4. Open the workbook to view governance metrics and compliance data

## Sample Governance Queries

The workbook includes these pre-configured Resource Graph queries:

- Resources without required tags (Environment, Owner, CostCenter)
- Non-compliant resource locations
- Policy compliance summary
- Security center recommendations
- Resource distribution by type and location

## Estimated Costs

Monthly cost estimates for this solution:
- Azure Monitor Workbooks: No additional charges
- Logic Apps: $5-10 (based on execution frequency)
- Log Analytics workspace: $2-5 (based on data ingestion)
- Azure Monitor alerts: $1-3 (based on alert frequency)

**Total estimated cost: $8-18 per month**

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-governance-dashboard \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Troubleshooting

### Common Issues

1. **Resource Graph Permissions**: Ensure you have Reader access to all subscriptions you want to monitor
2. **Logic App Triggers**: Verify webhook URLs are correctly configured in the Logic App
3. **Workbook Access**: Check that users have appropriate permissions to view Monitor Workbooks
4. **Alert Notifications**: Confirm action groups are properly configured with valid endpoints

### Validation Commands

```bash
# Verify Resource Graph access
az graph query --graph-query "resources | limit 1"

# Check workbook deployment
az monitor app-insights workbook list --resource-group rg-governance-dashboard

# Validate Logic App status
az logic workflow list --resource-group rg-governance-dashboard

# Test alert rules
az monitor metrics alert list --resource-group rg-governance-dashboard
```

## Customization

### Adding Custom Governance Queries

1. Edit the workbook template in your IaC files
2. Add new KQL queries following the Resource Graph documentation
3. Update visualization types as needed (charts, tables, maps)
4. Redeploy to apply changes

### Extending Automation Workflows

1. Modify the Logic App definition in your IaC
2. Add new triggers for different alert types
3. Implement custom remediation actions
4. Integrate with external systems (ITSM, SIEM, etc.)

### Multi-Subscription Monitoring

To monitor multiple subscriptions:

1. Ensure proper permissions across all target subscriptions
2. Update Resource Graph queries to include subscription filters
3. Configure workbook parameters for subscription selection
4. Test cross-subscription query performance

## Security Considerations

- Logic Apps use managed identity for secure authentication
- Workbooks inherit user permissions for data access
- Alert action groups should use secure webhook endpoints
- Resource Graph queries automatically respect user access permissions
- Log Analytics workspace uses role-based access control

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../implementing-automated-governance-dashboards-with-azure-resource-graph-and-azure-monitor-workbooks.md)
2. Review [Azure Resource Graph documentation](https://docs.microsoft.com/en-us/azure/governance/resource-graph/)
3. Consult [Azure Monitor Workbooks documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview)
4. Reference [Azure Logic Apps documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)

## Related Resources

- [Azure Governance Documentation](https://docs.microsoft.com/en-us/azure/governance/)
- [Azure Policy Best Practices](https://docs.microsoft.com/en-us/azure/governance/policy/overview)
- [Azure Monitor Pricing Guide](https://docs.microsoft.com/en-us/azure/azure-monitor/usage-estimated-costs)
- [Logic Apps Pricing Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/logic-apps-pricing)