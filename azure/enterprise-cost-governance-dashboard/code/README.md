# Infrastructure as Code for Enterprise Cost Governance Dashboard with Resource Graph

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise Cost Governance Dashboard with Resource Graph".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with Owner or Contributor permissions across multiple subscriptions
- Power BI Pro or Premium license for advanced analytics
- Resource Graph Reader role at management group or subscription level
- Cost Management Reader role for billing scope access
- Appropriate permissions for resource creation and role assignments

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to the bicep directory
cd bicep/

# Create a resource group
az group create --name rg-cost-governance --location eastus

# Deploy the Bicep template
az deployment group create \
    --resource-group rg-cost-governance \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This solution deploys:

- **Azure Resource Graph**: For querying Azure resources at scale
- **Azure Storage Account**: For data persistence and Power BI integration
- **Azure Key Vault**: For secure configuration management
- **Azure Logic Apps**: For workflow automation and orchestration
- **Azure Action Groups**: For cost alert notifications
- **Azure Cost Management**: For budget monitoring and alerts

## Configuration

### Bicep Parameters

The Bicep implementation uses a `parameters.json` file for customization:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "resourcePrefix": {
      "value": "costgov"
    },
    "monthlyCostThreshold": {
      "value": 10000
    },
    "dailyCostThreshold": {
      "value": 500
    },
    "alertEmail": {
      "value": "admin@company.com"
    }
  }
}
```

### Terraform Variables

The Terraform implementation uses variables defined in `variables.tf`:

- `location`: Azure region for resource deployment
- `resource_prefix`: Prefix for resource naming
- `monthly_cost_threshold`: Monthly budget threshold
- `daily_cost_threshold`: Daily cost alert threshold
- `alert_email`: Email for cost alerts

### Environment Variables

Both implementations support environment variable configuration:

```bash
export AZURE_LOCATION="eastus"
export RESOURCE_PREFIX="costgov"
export MONTHLY_COST_THRESHOLD="10000"
export DAILY_COST_THRESHOLD="500"
export ALERT_EMAIL="admin@company.com"
```

## Post-Deployment Configuration

### Power BI Integration

After deployment, configure Power BI connectivity:

1. Obtain the storage account connection string:
   ```bash
   az storage account show-connection-string \
       --name ${STORAGE_ACCOUNT_NAME} \
       --resource-group ${RESOURCE_GROUP_NAME}
   ```

2. Create a Power BI workspace and connect to the storage account
3. Import the sample Power BI template (if provided)
4. Configure automated data refresh schedules

### Logic Apps Workflow

The Logic Apps workflow is deployed with a basic configuration. To customize:

1. Navigate to the Azure portal
2. Open the deployed Logic Apps resource
3. Configure additional triggers or actions as needed
4. Test the workflow execution

### Cost Management Integration

Verify cost management configuration:

```bash
# Check budget configuration
az consumption budget list --resource-group ${RESOURCE_GROUP_NAME}

# Verify Action Group configuration
az monitor action-group list --resource-group ${RESOURCE_GROUP_NAME}
```

## Monitoring and Validation

### Resource Graph Queries

Test Resource Graph functionality:

```bash
# Test basic resource query
az graph query --query "resources | summarize count() by type | limit 10"

# Test cost-related resource analysis
az graph query --query "resources | where type in~ ['microsoft.compute/virtualmachines', 'microsoft.storage/storageaccounts'] | project name, type, resourceGroup, location"
```

### Cost Management API

Verify Cost Management API access:

```bash
# Test cost query
az rest \
    --method POST \
    --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.CostManagement/query?api-version=2021-10-01" \
    --headers "Content-Type=application/json" \
    --body '{
        "type": "Usage",
        "timeframe": "MonthToDate",
        "dataset": {
            "granularity": "Daily",
            "aggregation": {
                "totalCost": {
                    "name": "PreTaxCost",
                    "function": "Sum"
                }
            }
        }
    }'
```

### Logic Apps Monitoring

Monitor Logic Apps execution:

```bash
# Check recent runs
az logic workflow list-runs \
    --name ${LOGIC_APP_NAME} \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --output table

# Get run details
az logic workflow show-run \
    --name ${LOGIC_APP_NAME} \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --run-name ${RUN_ID}
```

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure you have appropriate RBAC roles assigned
2. **Resource Graph Timeouts**: Large queries may need optimization
3. **Logic Apps Failures**: Check managed identity permissions
4. **Power BI Connection Issues**: Verify storage account access keys

### Debugging Steps

1. Check resource deployment status:
   ```bash
   az deployment group show \
       --resource-group ${RESOURCE_GROUP_NAME} \
       --name ${DEPLOYMENT_NAME}
   ```

2. Review Logic Apps execution logs:
   ```bash
   az logic workflow list-runs \
       --name ${LOGIC_APP_NAME} \
       --resource-group ${RESOURCE_GROUP_NAME} \
       --query '[0].status'
   ```

3. Validate Key Vault access:
   ```bash
   az keyvault secret show \
       --vault-name ${KEY_VAULT_NAME} \
       --name cost-threshold-monthly
   ```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name rg-cost-governance --yes --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

### Manual Cleanup

If automated cleanup fails:

1. Delete Logic Apps workflows
2. Remove Action Groups and budget alerts
3. Delete Key Vault (with purge protection disabled)
4. Remove storage account and containers
5. Delete resource group

## Cost Optimization

### Resource Sizing

- **Logic Apps**: Uses consumption-based pricing
- **Storage Account**: Standard LRS tier for cost optimization
- **Key Vault**: Standard tier sufficient for most scenarios
- **Action Groups**: Pay-per-notification model

### Estimated Monthly Costs

- Logic Apps: $10-30 (based on execution frequency)
- Storage Account: $5-15 (depends on data volume)
- Key Vault: $5-10 (standard operations)
- Action Groups: $1-5 (notification-based)
- **Total Estimated**: $21-60/month

### Cost Optimization Tips

1. Adjust Logic Apps execution frequency based on requirements
2. Use storage lifecycle policies for old data
3. Configure retention policies for logs and reports
4. Monitor Action Group notification volumes

## Security Considerations

### Access Control

- Logic Apps use managed identity for secure authentication
- Key Vault access is restricted to specific principals
- Storage account uses private endpoints where possible
- Cost Management API access follows least privilege principle

### Data Protection

- All data at rest is encrypted using Azure managed keys
- Data in transit uses TLS encryption
- Key Vault provides secure configuration storage
- Access logs are maintained for audit purposes

## Customization

### Adding New Queries

To add custom Resource Graph queries:

1. Edit the Logic Apps workflow
2. Add new query definitions in the workflow actions
3. Update storage containers for new data types
4. Modify Power BI datasets accordingly

### Extending Notifications

To add new notification channels:

1. Update Action Group configuration
2. Add new notification endpoints
3. Configure Logic Apps to trigger additional actions
4. Test notification delivery

### Enhanced Reporting

To create additional reports:

1. Add new storage containers for different data types
2. Create additional Resource Graph queries
3. Extend Power BI datasets and reports
4. Configure automated refresh schedules

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../implementing-automated-cost-governance-with-azure-resource-graph-and-power-bi.md)
- [Azure Resource Graph documentation](https://docs.microsoft.com/en-us/azure/governance/resource-graph/)
- [Azure Cost Management documentation](https://docs.microsoft.com/en-us/azure/cost-management/)
- [Power BI documentation](https://docs.microsoft.com/en-us/power-bi/)

## Contributing

When modifying this infrastructure code:

1. Follow Azure naming conventions
2. Update documentation for any changes
3. Test deployments in development environment
4. Validate security configurations
5. Update cost estimates if resource changes impact pricing

## License

This infrastructure code is provided as-is for educational and implementation purposes. Refer to your organization's policies for production usage guidelines.