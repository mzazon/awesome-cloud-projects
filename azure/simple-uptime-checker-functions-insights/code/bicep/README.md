# Azure Bicep Templates for Simple Uptime Checker

This directory contains Azure Bicep templates for deploying a simple website uptime monitoring solution using Azure Functions and Application Insights.

## Architecture Overview

The solution consists of:

- **Azure Function App**: Timer-triggered function that checks website availability every 5 minutes
- **Application Insights**: Collects telemetry, logs, and provides monitoring dashboards
- **Storage Account**: Required for Azure Functions runtime
- **Action Groups & Alert Rules**: Automated alerting when websites go down
- **Log Analytics Workspace**: Optional backend for Application Insights
- **Custom Workbook**: Pre-built dashboard for monitoring visualizations

## Files Structure

```
bicep/
├── main.bicep                 # Main template with all resources
├── deploy.bicep              # Enhanced deployment with additional features
├── parameters.json           # Example parameters for basic deployment
├── parameters.dev.json       # Development environment parameters
├── parameters.prod.json      # Production environment parameters
├── function-code.js          # JavaScript code for the uptime checker function
├── modules/
│   ├── function-app.bicep    # Reusable Function App module
│   └── monitoring.bicep      # Reusable Application Insights and alerting module
└── README.md                 # This file
```

## Quick Start

### Prerequisites

- Azure CLI installed and configured
- Appropriate Azure permissions to create resources
- Resource Group already created (or permissions to create one)

### Basic Deployment

1. **Create a Resource Group** (if needed):
   ```bash
   az group create --name rg-uptime-checker --location "East US"
   ```

2. **Deploy using main template**:
   ```bash
   az deployment group create \
     --resource-group rg-uptime-checker \
     --template-file main.bicep \
     --parameters @parameters.json
   ```

3. **Deploy using enhanced template with environment-specific parameters**:
   ```bash
   # For development environment
   az deployment group create \
     --resource-group rg-uptime-checker-dev \
     --template-file deploy.bicep \
     --parameters @parameters.dev.json
   
   # For production environment
   az deployment group create \
     --resource-group rg-uptime-checker-prod \
     --template-file deploy.bicep \
     --parameters @parameters.prod.json
   ```

### Custom Deployment

1. **Copy and modify parameters**:
   ```bash
   cp parameters.json my-parameters.json
   # Edit my-parameters.json with your specific values
   ```

2. **Deploy with custom parameters**:
   ```bash
   az deployment group create \
     --resource-group your-resource-group \
     --template-file main.bicep \
     --parameters @my-parameters.json
   ```

## Configuration Parameters

### Main Template Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `functionAppName` | string | Generated | Name of the Function App |
| `appInsightsName` | string | Generated | Name of Application Insights |
| `storageAccountName` | string | Generated | Name of Storage Account |
| `location` | string | Resource Group location | Azure region |
| `nodeVersion` | string | '18' | Node.js runtime version |
| `hostingPlanSku` | string | 'Y1' | Function App hosting plan |
| `websitesToMonitor` | string | Microsoft sites | Comma-separated URLs to monitor |
| `monitoringIntervalMinutes` | int | 5 | How often to check websites |
| `functionTimeoutMinutes` | int | 5 | Function execution timeout |
| `enableAlerting` | bool | true | Enable Application Insights alerts |
| `alertSeverity` | int | 2 | Alert severity level (0-4) |
| `tags` | object | {} | Tags to apply to resources |

### Enhanced Deployment Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `namePrefix` | string | 'uptime' | Prefix for all resource names |
| `environment` | string | 'dev' | Environment (dev/test/prod) |
| `alertEmailAddress` | string | '' | Email for alert notifications |
| `resourceTags` | object | {} | Additional resource tags |

## Monitoring Configuration

### Websites to Monitor

Edit the `websitesToMonitor` parameter to include your websites:

```json
{
  "websitesToMonitor": {
    "value": "https://www.yoursite.com,https://api.yoursite.com,https://admin.yoursite.com"
  }
}
```

### Monitoring Interval

The function runs on a timer trigger based on the `monitoringIntervalMinutes` parameter:

- Minimum: 5 minutes
- Maximum: 60 minutes
- Recommended: 5 minutes for critical sites, 15-30 minutes for less critical

### Alert Configuration

Alerts are automatically configured for:

1. **Website Down**: Triggers when any monitored website returns an error
2. **High Response Time**: Triggers when average response time exceeds 5 seconds

To receive email notifications, set the `alertEmailAddress` parameter in `deploy.bicep`.

## Function Code

The uptime checker function (`function-code.js`) includes:

- HTTP/HTTPS website checking with timeout handling
- Custom telemetry logging to Application Insights
- Error handling and retry logic
- Response time measurement
- Status code validation
- Comprehensive logging for troubleshooting

### Customizing the Function

To modify the function behavior:

1. Edit `function-code.js`
2. Redeploy the Bicep template
3. The function code will be updated automatically

## Application Insights Queries

### Check Website Status
```kusto
traces
| where timestamp > ago(24h)
| where message contains "✅" or message contains "❌"
| extend Status = case(message contains "✅", "UP", "DOWN")
| summarize Count = count() by Status, bin(timestamp, 1h)
| render timechart
```

### Response Time Analysis
```kusto
traces
| where timestamp > ago(24h)
| where message contains "ms)"
| extend ResponseTime = extract(@"\\((\\d+)ms\\)", 1, message)
| extend Website = extract(@"(https?://[^:]+)", 1, message)
| where isnotnull(ResponseTime)
| summarize AvgResponseTime = avg(toint(ResponseTime)) by Website
| render barchart
```

### Failure Analysis
```kusto
traces
| where timestamp > ago(24h)
| where message contains "❌"
| extend Website = extract(@"❌ ([^:]+):", 1, message)
| extend Error = extract(@"❌ [^:]+: (.+)", 1, message)
| summarize Count = count() by Website, Error
| order by Count desc
```

## Troubleshooting

### Common Issues

1. **Function not executing**: Check the timer trigger configuration and Function App status
2. **No Application Insights data**: Verify the connection string configuration
3. **Alerts not firing**: Check alert rule configuration and action group settings
4. **Storage account name conflicts**: Use unique names or let the template generate them

### Debug Steps

1. **Check Function App logs**:
   ```bash
   az webapp log tail --name your-function-app --resource-group your-rg
   ```

2. **View Application Insights data**:
   ```bash
   az monitor app-insights query \
     --app your-app-insights \
     --resource-group your-rg \
     --analytics-query "traces | limit 10"
   ```

3. **Test function manually**:
   ```bash
   # Get function URL from Azure portal and trigger manually
   curl -X POST "https://your-function-app.azurewebsites.net/admin/functions/UptimeChecker"
   ```

## Cost Optimization

### Consumption Plan (Default)
- Pay-per-execution pricing
- Automatic scaling
- First 1 million executions free monthly
- Estimated cost: $0.01-$0.50 per day for 5-minute intervals

### Premium Plan (Production)
- Always-on instances
- Better performance
- VNet integration support
- Higher cost but predictable billing

### Cost Monitoring

Monitor costs using:
- Azure Cost Management
- Application Insights usage and billing metrics
- Function execution metrics

## Security Considerations

### Built-in Security Features

- HTTPS-only communication
- Managed Identity support (ready for implementation)
- Storage account with secure defaults
- TLS 1.2 minimum requirement
- Disabled FTP access

### Additional Security Recommendations

1. **Enable Managed Identity**: Use managed identity for secure access to other Azure services
2. **Network Security**: Consider VNet integration for production deployments
3. **Access Controls**: Implement proper RBAC for resource access
4. **Key Management**: Use Azure Key Vault for sensitive configuration
5. **Monitoring**: Enable Security Center recommendations

## Scaling and Production Considerations

### High Availability
- Deploy across multiple regions
- Use Traffic Manager for global load balancing
- Implement comprehensive monitoring

### Performance
- Consider Premium hosting plan for better performance
- Optimize function code for efficiency
- Monitor execution times and resource usage

### Compliance
- Configure data retention policies
- Implement audit logging
- Consider compliance requirements for data storage

## Support and Troubleshooting

### Useful Azure CLI Commands

```bash
# List all resources in the resource group
az resource list --resource-group your-rg --output table

# Get Function App configuration
az functionapp config show --name your-function-app --resource-group your-rg

# Check Application Insights status
az monitor app-insights component show --app your-app-insights --resource-group your-rg

# View alert rules
az monitor scheduled-query list --resource-group your-rg --output table
```

### Getting Help

- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Application Insights Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure CLI Reference](https://docs.microsoft.com/en-us/cli/azure/)

## Cleanup

To remove all resources created by this template:

```bash
# Delete the entire resource group (removes all resources)
az group delete --name your-resource-group --yes --no-wait

# Or delete individual deployments
az deployment group delete --name your-deployment-name --resource-group your-rg
```

> **Warning**: Resource group deletion is irreversible and will remove all resources within the group.