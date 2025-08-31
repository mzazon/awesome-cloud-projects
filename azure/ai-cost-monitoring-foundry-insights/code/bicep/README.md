# AI Cost Monitoring with Azure AI Foundry and Application Insights - Bicep Template

This directory contains Azure Bicep Infrastructure as Code (IaC) templates for deploying a comprehensive AI cost monitoring solution using Azure AI Foundry and Application Insights.

## Solution Overview

This Bicep template deploys a complete AI cost monitoring infrastructure that includes:

- **Azure AI Foundry Hub and Project** for centralized AI resource management
- **Application Insights** with custom metrics for token usage tracking
- **Log Analytics Workspace** for centralized logging and analysis
- **Azure Monitor Workbook** with pre-configured AI cost analytics dashboard
- **Budget and Cost Alerts** with automated notifications
- **Key Vault** for secure secrets management
- **Storage Account** optimized for AI Foundry requirements
- **RBAC assignments** following least privilege principles

## Architecture Components

The template creates the following Azure resources:

| Resource Type | Purpose | Configuration |
|---------------|---------|---------------|
| AI Foundry Hub | Central management of AI resources | Machine Learning Workspace (kind: hub) |
| AI Foundry Project | Project-specific AI workload isolation | Machine Learning Workspace (kind: project) |
| Application Insights | Telemetry collection and AI monitoring | Custom metrics with dimensions enabled |
| Log Analytics Workspace | Centralized logging and KQL queries | PerGB2018 pricing tier with retention controls |
| Key Vault | Secure storage of connection strings | RBAC-enabled with soft delete |
| Storage Account | AI Foundry artifact storage | StorageV2 with encryption and security hardening |
| Budget | Proactive cost management | Monthly budget with 80%, 90%, 100% thresholds |
| Action Group | Automated alert responses | Email and webhook notifications |
| Workbook | AI cost analytics dashboard | Custom KQL queries for token usage visualization |
| Metric Alert | High token usage monitoring | Real-time alerting on usage thresholds |

## Prerequisites

Before deploying this template, ensure you have:

1. **Azure CLI** installed and configured (version 2.60.0 or later)
2. **Azure subscription** with Owner or Contributor permissions
3. **Resource group** created for the deployment
4. **Appropriate Azure role assignments**:
   - Contributor or Owner on the target subscription/resource group
   - Key Vault Administrator (for Key Vault RBAC assignments)
   - User Access Administrator (for service principal RBAC assignments)

## Quick Start

### 1. Clone or Download Template Files

Ensure you have both `main.bicep` and `parameters.json` files in your working directory.

### 2. Customize Parameters

Edit the `parameters.json` file to match your requirements:

```json
{
  "location": {
    "value": "eastus"  // Change to your preferred region
  },
  "budgetAlertEmails": {
    "value": "your-email@company.com"  // Update to your email addresses
  },
  "budgetAmount": {
    "value": 500  // Adjust budget amount as needed
  }
}
```

### 3. Deploy Using Azure CLI

```bash
# Login to Azure
az login

# Set your subscription (if you have multiple)
az account set --subscription "your-subscription-id"

# Create resource group (if it doesn't exist)
az group create --name "rg-ai-monitoring-demo" --location "eastus"

# Deploy the Bicep template
az deployment group create \
  --resource-group "rg-ai-monitoring-demo" \
  --template-file main.bicep \
  --parameters @parameters.json \
  --name "ai-monitoring-deployment"
```

### 4. Deploy Using Azure PowerShell

```powershell
# Connect to Azure
Connect-AzAccount

# Set subscription context
Set-AzContext -SubscriptionId "your-subscription-id"

# Create resource group (if it doesn't exist)
New-AzResourceGroup -Name "rg-ai-monitoring-demo" -Location "East US"

# Deploy the template
New-AzResourceGroupDeployment `
  -ResourceGroupName "rg-ai-monitoring-demo" `
  -TemplateFile "main.bicep" `
  -TemplateParameterFile "parameters.json" `
  -Name "ai-monitoring-deployment"
```

## Parameter Configuration

### Required Parameters

| Parameter | Description | Example Value |
|-----------|-------------|---------------|
| `location` | Azure region for resource deployment | `"eastus"` |
| `budgetAlertEmails` | Comma-separated email addresses for budget alerts | `"admin@company.com,finance@company.com"` |

### Optional Parameters

| Parameter | Description | Default Value | Allowed Values |
|-----------|-------------|---------------|----------------|
| `uniqueSuffix` | Unique suffix for resource names | Auto-generated | Any string (6 chars max) |
| `environment` | Environment designation | `"dev"` | `"dev"`, `"test"`, `"prod"` |
| `budgetAmount` | Monthly budget limit in USD | `100` | Any positive integer |
| `appInsightsRetentionDays` | Application Insights data retention | `90` | 30, 60, 90, 120, 180, 270, 365, 550, 730 |
| `logAnalyticsRetentionDays` | Log Analytics data retention | `30` | 30-730 days |
| `storageAccountSku` | Storage account performance tier | `"Standard_LRS"` | Standard_LRS, Standard_GRS, etc. |
| `enableCustomMetrics` | Enable AI-specific custom metrics | `true` | `true`, `false` |

### Advanced Configuration

For production deployments, consider these parameter adjustments:

```json
{
  "environment": {
    "value": "prod"
  },
  "appInsightsRetentionDays": {
    "value": 365
  },
  "logAnalyticsRetentionDays": {
    "value": 90
  },
  "storageAccountSku": {
    "value": "Standard_GRS"
  },
  "budgetAmount": {
    "value": 5000
  }
}
```

## Post-Deployment Configuration

After successful deployment, complete these additional configuration steps:

### 1. Verify Resource Deployment

```bash
# Check deployment status
az deployment group show \
  --resource-group "rg-ai-monitoring-demo" \
  --name "ai-monitoring-deployment" \
  --query "properties.provisioningState"

# List deployed resources
az resource list \
  --resource-group "rg-ai-monitoring-demo" \
  --output table
```

### 2. Configure AI Foundry Project

1. Navigate to the Azure AI Foundry portal
2. Open your created AI Hub and Project
3. Configure model deployments as needed
4. Set up Prompt Flow with cost tracking integration

### 3. Test Application Insights Integration

```bash
# Get Application Insights instrumentation key
INSTRUMENTATION_KEY=$(az monitor app-insights component show \
  --app "appins-ai-uniquesuffix" \
  --resource-group "rg-ai-monitoring-demo" \
  --query "instrumentationKey" \
  --output tsv)

echo "Instrumentation Key: $INSTRUMENTATION_KEY"
```

### 4. Access Monitoring Dashboard

1. Navigate to Azure Portal > Monitor > Workbooks
2. Find "AI Cost Monitoring Dashboard"
3. Configure additional queries and visualizations as needed

## Cost Monitoring Features

The deployed solution provides comprehensive cost monitoring through:

### Budget Management
- **Monthly budget tracking** with configurable thresholds
- **Automated alerts** at 80%, 90%, and 100% of budget
- **Forecasted spending** alerts to prevent overruns
- **Email and webhook notifications** for immediate response

### Application Insights Analytics
- **Custom metrics collection** for AI-specific measurements
- **Token usage tracking** with cost attribution
- **Performance monitoring** including latency and throughput
- **Real-time dashboards** with KQL-powered visualizations

### Cost Allocation and Reporting
- **Resource tagging** for cost center attribution
- **Detailed cost breakdowns** by service and resource type
- **Historical usage patterns** for optimization insights
- **Cross-project cost comparison** through AI Foundry Hub

## Security Features

The template implements Azure security best practices:

### Identity and Access Management
- **System-assigned managed identities** for all Azure services
- **RBAC assignments** following least privilege principles
- **Key Vault integration** for secure secrets storage
- **Service principal authentication** for cross-service communication

### Data Protection
- **Encryption at rest** for all storage components
- **TLS 1.2 minimum** for all network communications
- **Private network access** options for sensitive workloads
- **Audit logging** for all administrative actions

### Network Security
- **Virtual network integration** support (configurable)
- **Private endpoint** compatibility for enhanced isolation
- **Network access controls** for storage and Key Vault
- **Azure Firewall** integration support

## Troubleshooting

### Common Deployment Issues

**Issue**: Deployment fails with "resource name already exists"
```bash
# Solution: Use a different uniqueSuffix parameter
az deployment group create \
  --parameters uniqueSuffix="newvalue"
```

**Issue**: Insufficient permissions for RBAC assignments
```bash
# Solution: Ensure you have User Access Administrator role
az role assignment create \
  --assignee "your-user-id" \
  --role "User Access Administrator" \
  --scope "/subscriptions/your-subscription-id"
```

**Issue**: Key Vault access denied during deployment
```bash
# Solution: Verify RBAC is enabled on Key Vault
az keyvault update \
  --name "your-keyvault-name" \
  --enable-rbac-authorization true
```

### Validation Commands

```bash
# Verify AI Foundry Hub status
az ml workspace show \
  --name "aihub-uniquesuffix" \
  --resource-group "rg-ai-monitoring-demo"

# Check Application Insights configuration
az monitor app-insights component show \
  --app "appins-ai-uniquesuffix" \
  --resource-group "rg-ai-monitoring-demo"

# Validate budget configuration
az consumption budget list \
  --resource-group "rg-ai-monitoring-demo"
```

## Cleanup

To remove all resources created by this template:

### Complete Resource Group Deletion

```bash
# Delete entire resource group (removes all resources)
az group delete \
  --name "rg-ai-monitoring-demo" \
  --yes \
  --no-wait
```

### Selective Resource Cleanup

```bash
# Delete specific deployment
az deployment group delete \
  --resource-group "rg-ai-monitoring-demo" \
  --name "ai-monitoring-deployment"

# Note: This only removes deployment history, not actual resources
# Use resource group deletion for complete cleanup
```

## Customization and Extensions

### Adding Custom Metrics

Extend the Application Insights configuration to track additional AI metrics:

1. Modify the `main.bicep` template to include additional custom events
2. Update the workbook queries to visualize new metrics
3. Configure additional alerts for new threshold monitoring

### Multi-Environment Deployments

Deploy across multiple environments using parameter files:

```bash
# Development environment
az deployment group create --parameters @parameters-dev.json

# Production environment  
az deployment group create --parameters @parameters-prod.json
```

### Integration with CI/CD Pipelines

Example Azure DevOps pipeline integration:

```yaml
- task: AzureResourceManagerTemplateDeployment@3
  inputs:
    deploymentScope: 'Resource Group'
    azureResourceManagerConnection: 'Azure-Connection'
    subscriptionId: '$(subscriptionId)'
    action: 'Create Or Update Resource Group'
    resourceGroupName: '$(resourceGroupName)'
    location: '$(location)'
    templateLocation: 'Linked artifact'
    csmFile: 'bicep/main.bicep'
    csmParametersFile: 'bicep/parameters.json'
    deploymentMode: 'Incremental'
```

## Support and Documentation

### Azure Service Documentation
- [Azure AI Foundry Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/)
- [Application Insights Documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)
- [Azure Monitor Workbooks](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview)
- [Azure Budgets and Cost Management](https://learn.microsoft.com/en-us/azure/cost-management-billing/)

### Bicep Language Reference
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Bicep Best Practices](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/best-practices)
- [Azure Resource Reference](https://docs.microsoft.com/en-us/azure/templates/)

For issues with this Infrastructure as Code implementation, refer to the original recipe documentation or open an issue in the repository.

## License

This template is provided under the same license as the parent recipe repository.