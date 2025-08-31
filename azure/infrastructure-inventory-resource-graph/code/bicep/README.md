# Infrastructure as Code for Infrastructure Inventory Reports with Resource Graph

This directory contains Bicep templates for deploying the infrastructure needed to implement comprehensive Azure infrastructure inventory reporting using Azure Resource Graph.

## Architecture Overview

The Bicep template deploys:

- **Managed Identity**: For secure access to Azure Resource Graph
- **Storage Account**: For storing inventory reports and exports
- **Function App**: For automated inventory report generation (optional)
- **Key Vault**: For secure storage of connection strings and secrets
- **Log Analytics Workspace**: For monitoring and alerting
- **Application Insights**: For Function App telemetry
- **Azure Workbook**: Pre-configured dashboard for inventory visualization
- **Role Assignments**: Reader access for Resource Graph queries

## Prerequisites

- Azure CLI installed and configured (version 2.22.0 or higher)
- Bicep CLI installed (`az bicep install`)
- Azure Resource Graph extension (`az extension add --name resource-graph`)
- Appropriate Azure permissions:
  - Contributor access to the target resource group
  - User Access Administrator (for role assignments)
  - Reader access across subscriptions you want to inventory

## Parameters

| Parameter | Type | Description | Default | Allowed Values |
|-----------|------|-------------|---------|----------------|
| `location` | string | Azure region for deployment | Resource Group location | Any Azure region |
| `environment` | string | Environment name | `dev` | `dev`, `staging`, `prod` |
| `organizationName` | string | Organization name for resource naming | Required | 2-10 characters |
| `enableAutomatedReports` | boolean | Enable Function App for automated reports | `true` | `true`, `false` |
| `reportFrequencyHours` | integer | Report frequency in hours | `24` | `24`, `48`, `72`, `168` |
| `storageAccountType` | string | Storage account replication type | `Standard_LRS` | `Standard_LRS`, `Standard_GRS`, `Standard_ZRS` |
| `enableComplianceMonitoring` | boolean | Enable compliance monitoring features | `true` | `true`, `false` |
| `tags` | object | Resource tags | Default tags | Custom tag object |

## Quick Start

### 1. Deploy with Default Parameters

```bash
# Create resource group
az group create --name rg-inventory-dev --location "East US"

# Deploy template with minimal parameters
az deployment group create \
    --resource-group rg-inventory-dev \
    --template-file main.bicep \
    --parameters organizationName="contoso"
```

### 2. Deploy with Custom Parameters

```bash
# Deploy with custom parameters file
az deployment group create \
    --resource-group rg-inventory-dev \
    --template-file main.bicep \
    --parameters @parameters.json
```

### 3. Deploy with Inline Parameters

```bash
# Deploy with inline parameter overrides
az deployment group create \
    --resource-group rg-inventory-dev \
    --template-file main.bicep \
    --parameters \
        organizationName="myorg" \
        environment="prod" \
        enableAutomatedReports=false \
        storageAccountType="Standard_GRS"
```

## Post-Deployment Configuration

### 1. Verify Resource Graph Access

```bash
# Test Resource Graph connectivity
az graph query -q "Resources | limit 5" --output table

# Verify managed identity access
az graph query -q "Resources | count" --output json
```

### 2. Access the Inventory Dashboard

1. Navigate to the Azure Portal
2. Go to Monitor > Workbooks
3. Find the "Infrastructure Inventory Dashboard" workbook
4. Pin frequently used queries to your dashboard

### 3. Configure Function App (if enabled)

The deployed Function App includes placeholders for PowerShell functions. To implement automated reporting:

1. Navigate to the Function App in the Azure Portal
2. Create new functions for specific inventory tasks
3. Configure timer triggers based on your requirements
4. Use the provided managed identity for Resource Graph access

### 4. Sample Inventory Queries

Use these queries in the Azure Portal Resource Graph Explorer or Azure CLI:

```bash
# Basic resource inventory
az graph query -q "
Resources
| project name, type, location, resourceGroup, subscriptionId
| order by type asc, name asc
| limit 50
" --output table

# Resource count by type
az graph query -q "
Resources
| summarize count() by type
| order by count_ desc
" --output table

# Location distribution
az graph query -q "
Resources
| where location != ''
| summarize ResourceCount=count() by Location=location
| order by ResourceCount desc
" --output table

# Tagging compliance
az graph query -q "
Resources
| extend TagCount = array_length(todynamic(tags))
| extend HasTags = case(TagCount > 0, 'Tagged', 'Untagged')
| summarize count() by HasTags, type
| order by type asc
" --output table

# Export comprehensive inventory
az graph query -q "
Resources
| project 
    ResourceName=name,
    ResourceType=type,
    Location=location,
    ResourceGroup=resourceGroup,
    SubscriptionId=subscriptionId,
    Tags=tags,
    ResourceId=id,
    Kind=kind
| order by ResourceType asc, ResourceName asc
" --output json > infrastructure-inventory-$(date +%Y%m%d).json
```

## Storage Account Structure

The deployed storage account includes these containers:

- **inventory-reports**: For automated inventory exports
- **compliance-reports**: For compliance monitoring reports (if enabled)

## Security Considerations

- Managed Identity uses least-privilege access (Reader role only)
- Storage Account disables public blob access
- Key Vault restricts access to the managed identity
- All resources enforce HTTPS/TLS 1.2
- Function App (if enabled) uses system-assigned managed identity

## Monitoring and Alerting

The deployment includes:

- **Log Analytics Workspace**: For centralized logging
- **Application Insights**: For Function App performance monitoring
- **Azure Workbook**: For inventory visualization and analysis

Consider setting up alerts for:
- Failed inventory report generation
- Compliance violations (untagged resources)
- Resource Graph API rate limiting

## Cost Optimization

- Azure Resource Graph is free (no query charges)
- Storage costs depend on report retention and frequency
- Function App uses Consumption plan (pay-per-execution)
- Log Analytics charges based on data ingestion

Estimated monthly costs (East US region):
- Storage Account (Standard_LRS, 1GB): ~$0.02
- Log Analytics (1GB ingestion): ~$2.30
- Function App (100 executions/month): ~$0.00
- Key Vault (1000 operations): ~$0.03

**Total estimated monthly cost: ~$2.35**

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure the managed identity has Reader access to target subscriptions
2. **Resource Graph Limits**: Be aware of query complexity and result size limits
3. **Storage Access**: Verify Key Vault access policies for the managed identity
4. **Function App Issues**: Check Application Insights for detailed error logs

### Useful Commands

```bash
# Check managed identity role assignments
az role assignment list --assignee <principal-id> --output table

# Test Key Vault access
az keyvault secret show --vault-name <key-vault-name> --name StorageConnectionString

# View Function App logs
az webapp log tail --name <function-app-name> --resource-group <resource-group>

# Validate Bicep template
az deployment group validate \
    --resource-group <resource-group> \
    --template-file main.bicep \
    --parameters @parameters.json
```

## Customization

### Adding Custom Queries

1. Modify the workbook template (`workbook-template.json`)
2. Add new query tiles or visualizations
3. Redeploy the template to update the workbook

### Extending Function App

1. Add PowerShell function files to the Function App
2. Use the provided environment variables for configuration
3. Implement custom business logic for inventory processing

### Integration with Other Services

- **Logic Apps**: For workflow automation
- **Power BI**: For advanced analytics and reporting
- **Azure Monitor**: For custom alerting rules
- **Azure Policy**: For governance and compliance

## Cleanup

```bash
# Delete the entire resource group (removes all resources)
az group delete --name rg-inventory-dev --yes --no-wait

# Or delete specific resources
az deployment group delete --resource-group rg-inventory-dev --name <deployment-name>
```

## Additional Resources

- [Azure Resource Graph Overview](https://learn.microsoft.com/en-us/azure/governance/resource-graph/overview)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure Resource Graph Query Language (KQL)](https://learn.microsoft.com/en-us/azure/governance/resource-graph/concepts/query-language)
- [Azure Functions with PowerShell](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-powershell)
- [Azure Workbooks](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview)

## Support

For issues with this infrastructure code, refer to:
- The original recipe documentation
- Azure Resource Graph documentation
- Azure Bicep documentation
- Azure support channels