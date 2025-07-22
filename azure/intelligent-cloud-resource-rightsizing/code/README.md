# Infrastructure as Code for Intelligent Cloud Resource Rightsizing with Cost Management and Developer CLI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Cloud Resource Rightsizing with Cost Management and Developer CLI".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (ARM template successor)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0+ installed and configured
- Azure Developer CLI (azd) v1.15.0+ installed
- Node.js 18+ for Azure Functions development
- Azure subscription with Contributor permissions for resource management
- Appropriate permissions for creating and managing:
  - Resource Groups
  - Azure Functions
  - Storage Accounts
  - Log Analytics Workspaces
  - Application Insights
  - Logic Apps
  - Azure Monitor alerts and budgets
  - Virtual Machines (for testing)
  - App Service Plans and Web Apps

## Architecture Overview

This solution implements an automated resource rightsizing system that:

- Continuously monitors application performance using Azure Monitor
- Analyzes resource utilization patterns with Azure Functions
- Generates intelligent rightsizing recommendations
- Integrates with Azure Developer CLI workflows
- Provides automated scaling actions via Logic Apps
- Implements cost management alerts and budgets

## Quick Start

### Using Bicep
```bash
cd bicep/

# Deploy the main infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters @parameters.json

# Verify deployment
az deployment group show \
    --resource-group <your-resource-group> \
    --name main
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the solution
./scripts/deploy.sh

# Verify deployment
az resource list --resource-group <your-resource-group> --output table
```

## Configuration

### Environment Variables

Before deployment, set these environment variables:

```bash
export RESOURCE_GROUP="rg-rightsizing-demo"
export LOCATION="eastus"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
```

### Parameters

Key parameters you can customize:

- **resourceGroupName**: Name of the resource group for all resources
- **location**: Azure region for resource deployment
- **functionAppName**: Name of the Azure Function App
- **storageAccountName**: Name of the storage account (must be globally unique)
- **logAnalyticsWorkspaceName**: Name of the Log Analytics workspace
- **appInsightsName**: Name of the Application Insights instance
- **logicAppName**: Name of the Logic App workflow
- **budgetAmount**: Monthly budget amount for cost monitoring (default: $100)
- **cpuThresholdLow**: CPU threshold for downsizing recommendations (default: 20%)
- **cpuThresholdHigh**: CPU threshold for upsizing recommendations (default: 80%)

### Cost Estimates

Expected monthly costs for this solution:

- Azure Functions (Consumption): $0-20
- Storage Account: $1-5
- Log Analytics Workspace: $10-50
- Application Insights: $5-25
- Logic Apps: $0-10
- Azure Monitor alerts: $0-5
- Test resources (if created): $10-100

**Total estimated cost: $26-215/month** (depending on usage and test resources)

## Validation & Testing

After deployment, validate the solution:

### 1. Verify Function App
```bash
# Check Function App status
az functionapp show \
    --resource-group <your-resource-group> \
    --name <function-app-name> \
    --query "{name:name, state:state, defaultHostName:defaultHostName}"

# Test function execution
az functionapp function invoke \
    --resource-group <your-resource-group> \
    --name <function-app-name> \
    --function-name RightsizingAnalyzer
```

### 2. Test Rightsizing Analysis
```bash
# Get function key
FUNCTION_KEY=$(az functionapp keys list \
    --name <function-app-name> \
    --resource-group <your-resource-group> \
    --query "functionKeys.default" \
    --output tsv)

# Test analysis endpoint
curl -X POST "https://<function-app-name>.azurewebsites.net/api/RightsizingAnalyzer?code=${FUNCTION_KEY}"
```

### 3. Verify Monitoring Setup
```bash
# Check Log Analytics workspace
az monitor log-analytics workspace show \
    --resource-group <your-resource-group> \
    --workspace-name <workspace-name>

# Check Application Insights
az monitor app-insights component show \
    --resource-group <your-resource-group> \
    --app <app-insights-name>
```

### 4. Test Cost Management
```bash
# Check budget status
az consumption budget show \
    --resource-group <your-resource-group> \
    --budget-name "rightsizing-budget"

# Verify alert rules
az monitor metrics alert list \
    --resource-group <your-resource-group> \
    --output table
```

## Monitoring and Operations

### Key Metrics to Monitor

1. **Function App Execution Count**: Monitor successful runs of the rightsizing analyzer
2. **Cost Trends**: Track resource costs over time
3. **Alert Frequency**: Monitor how often cost and performance alerts trigger
4. **Rightsizing Recommendations**: Review generated optimization suggestions
5. **Resource Utilization**: Track CPU, memory, and storage utilization patterns

### Accessing Logs

```bash
# View Function App logs
az functionapp log tail \
    --resource-group <your-resource-group> \
    --name <function-app-name>

# Query Log Analytics
az monitor log-analytics query \
    --workspace <workspace-id> \
    --analytics-query "
        FunctionAppLogs
        | where TimeGenerated > ago(1d)
        | where FunctionName == 'RightsizingAnalyzer'
        | project TimeGenerated, Level, Message
        | order by TimeGenerated desc
    "
```

### Troubleshooting

Common issues and solutions:

1. **Function App Not Executing**
   - Check function app configuration and permissions
   - Verify Log Analytics workspace connection
   - Review function code for errors

2. **No Rightsizing Recommendations**
   - Ensure test resources are generating performance data
   - Check monitoring data collection is working
   - Verify CPU thresholds are appropriate

3. **Cost Alerts Not Triggering**
   - Verify budget configuration
   - Check alert rule conditions
   - Ensure notification settings are correct

## Integration with Azure Developer CLI

The solution integrates with Azure Developer CLI for streamlined deployment:

```bash
# Initialize azd in your project
azd init --template rightsizing-automation

# Deploy using azd
azd deploy

# Monitor deployment
azd monitor

# Clean up resources
azd down
```

## Security Considerations

- Function App uses managed identity for Azure resource access
- Storage account uses encryption at rest
- Log Analytics workspace has appropriate access controls
- Budget alerts use secure email notifications
- All resources follow Azure security best practices

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete \
    --name <your-resource-group> \
    --yes \
    --no-wait
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify all resources are deleted
az resource list --resource-group <your-resource-group>
```

## Customization

### Extending the Solution

1. **Add More Resource Types**
   - Modify function code to analyze App Services, SQL Databases, etc.
   - Update monitoring queries for additional metrics

2. **Implement Advanced Algorithms**
   - Add machine learning models for predictive rightsizing
   - Implement time-based scaling patterns

3. **Enhance Notifications**
   - Add Teams or Slack integration
   - Implement approval workflows for changes

4. **Cost Optimization**
   - Add reserved instance recommendations
   - Implement spot instance suggestions

### Configuration Files

- `bicep/parameters.json`: Bicep deployment parameters
- `terraform/variables.tf`: Terraform variable definitions
- `scripts/config.sh`: Bash script configuration

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review Azure documentation for specific services
3. Verify prerequisites and permissions
4. Check Azure service health status
5. Review deployment logs for errors

## Related Resources

- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)
- [Azure Cost Management Documentation](https://docs.microsoft.com/en-us/azure/cost-management-billing/)
- [Azure Developer CLI Documentation](https://docs.microsoft.com/en-us/azure/developer/azure-developer-cli/)

## License

This infrastructure code is provided as-is for educational and demonstration purposes.