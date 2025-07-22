# Infrastructure as Code for Carbon-Aware Cost Optimization with Azure Carbon Optimization and Azure Automation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Carbon-Aware Cost Optimization with Azure Carbon Optimization and Azure Automation".

## Available Implementations

- **Bicep**: Azure native infrastructure as code
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login` completed)
- Appropriate Azure subscription permissions (Owner or Contributor role)
- For Terraform: Terraform v1.0+ installed
- For Bicep: Azure CLI with Bicep extension
- PowerShell execution policy configured for Azure Automation runbooks

## Architecture Overview

This solution deploys:
- Azure Key Vault for secure configuration storage
- Azure Automation Account with carbon optimization runbook
- Azure Logic Apps for workflow orchestration
- Log Analytics workspace for monitoring
- Storage account for Logic Apps state management
- Role assignments and managed identities for secure automation

## Quick Start

### Using Bicep

```bash
# Navigate to Bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters @parameters.json

# Verify deployment
az deployment group show \
    --resource-group <your-resource-group> \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Apply infrastructure
terraform apply

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
echo "Review Azure portal for resource deployment status"
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export RESOURCE_GROUP_NAME="rg-carbon-optimization"
export LOCATION="eastus"
export RANDOM_SUFFIX="$(openssl rand -hex 3)"
```

### Customizable Parameters

Key parameters you can customize in `bicep/parameters.json` or `terraform/terraform.tfvars`:

- `location`: Azure region for resource deployment
- `resourcePrefix`: Prefix for resource naming
- `carbonThresholdKg`: Carbon emissions threshold (default: 100 kg CO2e/month)
- `costThresholdUsd`: Cost threshold for optimization actions (default: $500/month)
- `cpuUtilizationThreshold`: CPU threshold for rightsizing (default: 20%)
- `optimizationSchedule`: Cron expression for automation schedule

### Carbon Optimization Thresholds

Configure these thresholds based on your sustainability goals:

- **Carbon Threshold**: Minimum carbon savings to trigger optimization (kg CO2e)
- **Cost Threshold**: Minimum cost savings required for action (USD)
- **CPU Utilization**: Threshold for identifying underutilized resources (%)
- **Carbon Reduction**: Minimum percentage reduction required (%)

## Post-Deployment Configuration

After infrastructure deployment, complete these steps:

1. **Configure Carbon Intensity API Access**:
   ```bash
   # The Logic Apps workflow uses public carbon intensity APIs
   # No additional configuration required for basic functionality
   ```

2. **Test Carbon Optimization Runbook**:
   ```bash
   # Start a test execution
   az automation runbook start \
       --automation-account-name <automation-account-name> \
       --resource-group <resource-group> \
       --name "CarbonOptimizationRunbook"
   ```

3. **Enable Logic Apps Workflow**:
   ```bash
   # Verify workflow is enabled
   az logic workflow show \
       --resource-group <resource-group> \
       --name <logic-app-name> \
       --query state
   ```

## Monitoring and Validation

### Check Carbon Optimization Status

```bash
# View carbon optimization recommendations
az rest --method GET \
    --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/Microsoft.CarbonOptimization/carbonOptimizationRecommendations?api-version=2023-10-01-preview"

# Check Automation job history
az automation job list \
    --automation-account-name <automation-account-name> \
    --resource-group <resource-group>

# View Logic Apps run history
az logic workflow run list \
    --resource-group <resource-group> \
    --name <logic-app-name>
```

### Log Analytics Queries

Use these KQL queries in Log Analytics to monitor carbon optimization:

```kql
// Carbon optimization actions
CarbonOptimization_CL
| where action_s == "optimization_triggered"
| summarize count() by bin(TimeGenerated, 1d)

// Resource optimization results
CarbonOptimization_CL
| where isnotempty(carbonSavings_d)
| summarize TotalCarbonSaved = sum(carbonSavings_d), TotalCostSaved = sum(costSavings_d)
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name <your-resource-group> \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

## Security Considerations

This solution implements several security best practices:

- **Managed Identities**: All service-to-service authentication uses managed identities
- **Key Vault**: Sensitive configuration stored in Azure Key Vault with RBAC
- **Least Privilege**: Role assignments follow principle of least privilege
- **Network Security**: Consider implementing private endpoints for enhanced security

### Additional Security Hardening

For production deployments, consider:

1. **Private Endpoints**: Configure private endpoints for Key Vault and Storage
2. **Network Restrictions**: Implement VNet integration for Logic Apps
3. **Audit Logging**: Enable diagnostic settings for all resources
4. **Access Reviews**: Regular review of role assignments and permissions

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your account has sufficient permissions
   ```bash
   az role assignment list --assignee $(az account show --query user.name -o tsv)
   ```

2. **Carbon Optimization API Access**: Verify subscription is enabled for Carbon Optimization
   ```bash
   az feature show --namespace Microsoft.CarbonOptimization --name CarbonOptimization
   ```

3. **Automation Runbook Failures**: Check runbook execution logs
   ```bash
   az automation job output show \
       --automation-account-name <name> \
       --resource-group <rg> \
       --job-id <job-id>
   ```

### Debug Logging

Enable verbose logging for troubleshooting:

```bash
# For Azure CLI commands
az config set core.only_show_errors=false
az config set core.output=json

# For Terraform
export TF_LOG=DEBUG
```

## Cost Estimation

Estimated monthly costs for this solution:

- **Azure Automation Account**: ~$5-10/month (depends on runbook execution frequency)
- **Logic Apps**: ~$2-5/month (standard workflow with daily triggers)
- **Key Vault**: ~$1-2/month (secrets storage and transactions)
- **Log Analytics**: ~$5-15/month (depends on data ingestion volume)
- **Storage Account**: ~$1-3/month (Logic Apps state storage)

**Total Estimated Cost**: $14-35/month

> **Note**: Actual costs depend on usage patterns, data volumes, and regional pricing. Use the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) for precise estimates.

## Extension Ideas

Enhance this solution with additional capabilities:

1. **Power BI Dashboard**: Create sustainability reporting dashboards
2. **Multi-Region Optimization**: Extend to optimize across Azure regions
3. **Predictive Analytics**: Add ML models for carbon intensity forecasting
4. **Teams Integration**: Add Microsoft Teams notifications for optimization actions
5. **Policy Integration**: Integrate with Azure Policy for governance controls

## Support and Resources

- [Azure Carbon Optimization Documentation](https://learn.microsoft.com/en-us/azure/carbon-optimization/)
- [Azure Automation Documentation](https://learn.microsoft.com/en-us/azure/automation/)
- [Azure Logic Apps Documentation](https://learn.microsoft.com/en-us/azure/logic-apps/)
- [Microsoft Sustainability Resources](https://www.microsoft.com/sustainability)

For issues with this infrastructure code, refer to the original recipe documentation or Azure support channels.