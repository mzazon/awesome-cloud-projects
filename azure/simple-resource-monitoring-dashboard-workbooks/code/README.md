# Infrastructure as Code for Simple Resource Monitoring Dashboard with Azure Monitor Workbooks

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Resource Monitoring Dashboard with Azure Monitor Workbooks".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.37.0 or later)
- Azure subscription with Contributor or Owner permissions
- Basic understanding of Azure Monitor concepts
- For Terraform: Terraform CLI installed (version 1.0+ recommended)
- For Bicep: Bicep CLI installed (included with Azure CLI 2.20.0+)

## Architecture Overview

This IaC deployment creates:

- Resource Group for organizing monitoring resources
- Log Analytics Workspace for centralized logging and queries
- Storage Account for demonstration and monitoring
- App Service Plan and Web App for sample resource monitoring
- Azure Monitor Workbook with custom monitoring dashboard
- Sample KQL queries for resource health, performance, and cost monitoring

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters environment=demo \
    --parameters location=eastus

# View deployment outputs
az deployment group show \
    --resource-group myResourceGroup \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="resource_group_name=rg-monitoring-demo" \
    -var="location=eastus" \
    -var="environment=demo"

# Apply the configuration
terraform apply \
    -var="resource_group_name=rg-monitoring-demo" \
    -var="location=eastus" \
    -var="environment=demo"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy infrastructure
./deploy.sh

# Follow the prompts to configure deployment parameters
```

## Configuration Options

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `eastus` | Azure region for resource deployment |
| `environment` | string | `demo` | Environment tag for resources |
| `workspaceName` | string | Generated | Log Analytics workspace name |
| `storageAccountName` | string | Generated | Storage account name (must be globally unique) |
| `appServicePlanName` | string | Generated | App Service plan name |
| `webAppName` | string | Generated | Web application name |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `resource_group_name` | string | `rg-monitoring-demo` | Name of the resource group |
| `location` | string | `eastus` | Azure region for deployment |
| `environment` | string | `demo` | Environment tag for resources |
| `log_analytics_sku` | string | `PerGB2018` | Log Analytics workspace pricing tier |
| `app_service_plan_sku` | string | `F1` | App Service plan size (F1 = Free tier) |

### Bash Script Environment Variables

The deployment script will prompt for or use these environment variables:

- `AZURE_LOCATION`: Target Azure region (default: eastus)
- `RESOURCE_GROUP_NAME`: Resource group name (default: generated)
- `ENVIRONMENT_TAG`: Environment tag (default: demo)

## Post-Deployment Steps

After successful deployment, complete these manual steps to activate the monitoring dashboard:

1. **Navigate to Azure Monitor Workbooks**:
   ```bash
   echo "Navigate to: https://portal.azure.com/#view/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/~/workbooks"
   ```

2. **Create Custom Workbook**:
   - Select "Empty" template in the Azure portal
   - Add sections for Resource Health, Performance Metrics, and Cost Monitoring
   - Use the provided KQL queries from the deployment outputs

3. **Configure Interactive Parameters**:
   - Add Time Range parameter (default: Last 24 hours)
   - Add Resource Group parameter (set to deployed resource group)
   - Add Subscription parameter (current subscription)

4. **Save and Share Workbook**:
   - Save with descriptive name and associate with the resource group
   - Configure sharing permissions for team access

## Monitoring Queries

The deployment includes sample KQL queries for workbook sections:

### Resource Health Query
```kql
AzureActivity
| where TimeGenerated >= ago(1h)
| where ActivityStatusValue in ("Success", "Failed", "Warning")
| summarize 
    SuccessfulOperations = countif(ActivityStatusValue == "Success"),
    FailedOperations = countif(ActivityStatusValue == "Failed"),
    WarningOperations = countif(ActivityStatusValue == "Warning"),
    TotalOperations = count()
| extend HealthPercentage = round((SuccessfulOperations * 100.0) / TotalOperations, 1)
```

### Performance Metrics Query
```kql
Perf
| where TimeGenerated >= ago(4h)
| where CounterName in ("% Processor Time", "Available MBytes", "Disk Read Bytes/sec")
| summarize 
    AvgCPU = avg(CounterValue), 
    AvgMemory = avg(CounterValue),
    MaxDiskIO = max(CounterValue)
by Computer, CounterName, bin(TimeGenerated, 15m)
| render timechart
```

## Validation

Verify the deployment was successful:

### Check Resource Creation

```bash
# Verify resource group and resources
az group show --name <your-resource-group> --query "{Name:name, State:properties.provisioningState}"

# Check Log Analytics workspace
az monitor log-analytics workspace list \
    --resource-group <your-resource-group> \
    --query "[].{Name:name, State:provisioningState, Location:location}"

# Verify storage account
az storage account list \
    --resource-group <your-resource-group> \
    --query "[].{Name:name, State:provisioningState, Location:location}"

# Check web app
az webapp list \
    --resource-group <your-resource-group> \
    --query "[].{Name:name, State:state, DefaultHostName:defaultHostName}"
```

### Test Monitoring Data

```bash
# Check available metrics for storage account
az monitor metrics list-definitions \
    --resource <storage-account-resource-id> \
    --query "[].{Name:name.value, Unit:unit}" \
    --output table

# Verify Log Analytics data ingestion
az monitor log-analytics query \
    --workspace <workspace-id> \
    --analytics-query "Heartbeat | limit 10"
```

## Troubleshooting

### Common Issues

1. **Resource Name Conflicts**: Storage account names must be globally unique
   - Solution: The templates generate unique names using random suffixes

2. **Insufficient Permissions**: Deployment requires Contributor or Owner role
   - Solution: Ensure proper Azure RBAC permissions are assigned

3. **Region Availability**: Some services may not be available in all regions
   - Solution: Use supported regions like East US, West Europe, or Southeast Asia

4. **Log Analytics Data Delay**: Metrics may take 5-15 minutes to appear
   - Solution: Wait for data ingestion or generate test activity

### Debug Commands

```bash
# Check Azure CLI authentication
az account show

# Verify subscription access
az account list --query "[].{Name:name, State:state, IsDefault:isDefault}"

# Check resource provider registration
az provider show --namespace Microsoft.OperationalInsights --query registrationState
az provider show --namespace Microsoft.Web --query registrationState
az provider show --namespace Microsoft.Storage --query registrationState
```

## Cost Considerations

### Estimated Monthly Costs (USD)

- **Log Analytics Workspace**: $0-15 (depends on data ingestion volume)
- **Storage Account**: $1-5 (Standard LRS, minimal usage)
- **App Service Plan**: $0 (F1 Free tier)
- **Azure Monitor Workbooks**: Free
- **Total Estimated**: $1-20/month

### Cost Optimization Tips

1. Use the F1 (Free) tier for App Service during testing
2. Configure Log Analytics data retention based on requirements (31-730 days)
3. Monitor data ingestion to avoid unexpected charges
4. Clean up resources when not needed for extended periods

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name <your-resource-group> \
    --yes \
    --no-wait

# Verify deletion (after a few minutes)
az group exists --name <your-resource-group>
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy \
    -var="resource_group_name=<your-resource-group>" \
    -var="location=eastus" \
    -var="environment=demo"

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

```bash
# Verify resource group deletion
az group exists --name <your-resource-group>

# Check for any remaining resources
az resource list --query "[?resourceGroup=='<your-resource-group>']"
```

## Customization

### Extending the Solution

1. **Add Custom Metrics**: Integrate Application Insights for application-level monitoring
2. **Multi-Subscription Support**: Modify queries to aggregate data across subscriptions  
3. **Automated Alerting**: Add Azure Monitor alert rules based on workbook queries
4. **Advanced Visualizations**: Include geo-mapping, funnel charts, and custom charts
5. **Role-Based Access**: Create different workbook views for various stakeholder groups

### Modifying Templates

- **Bicep**: Edit `main.bicep` and associated parameter files
- **Terraform**: Modify `main.tf`, `variables.tf`, and `outputs.tf`  
- **Bash Scripts**: Update environment variables and resource configurations

### Integration Options

- **CI/CD Pipelines**: Integrate with Azure DevOps or GitHub Actions
- **Infrastructure Testing**: Add Pester tests for PowerShell or Terratest for Terraform
- **Security Scanning**: Include Azure Security Center recommendations
- **Compliance**: Add Azure Policy assignments for governance

## Support

### Documentation References

- [Azure Monitor Workbooks Documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview)
- [Bicep Language Reference](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Monitor KQL Reference](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Refer to the original recipe documentation
3. Consult Azure provider documentation for specific resources
4. Review Azure Monitor best practices documentation

### Contributing

To improve this infrastructure code:

1. Test changes thoroughly in a development environment
2. Follow Azure naming conventions and best practices
3. Update documentation for any new parameters or features
4. Ensure backwards compatibility when possible