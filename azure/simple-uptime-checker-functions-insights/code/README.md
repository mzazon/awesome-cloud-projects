# Infrastructure as Code for Simple Website Uptime Checker with Functions and Application Insights

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Website Uptime Checker with Functions and Application Insights".

## Available Implementations

- **Bicep**: Azure native infrastructure as code
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with appropriate permissions for:
  - Resource Groups
  - Azure Functions
  - Application Insights
  - Storage Accounts
  - Monitor Alert Rules
- For Terraform: Terraform >= 1.0 installed
- For Bicep: Bicep CLI installed
- Bash shell environment

## Quick Start

### Using Bicep

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters functionAppName=func-uptime-$(openssl rand -hex 3) \
    --parameters storageAccountName=stg$(openssl rand -hex 3) \
    --parameters appInsightsName=ai-uptime-$(openssl rand -hex 3)
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# When prompted, type 'yes' to confirm deployment
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure your deployment
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default Value |
|-----------|-------------|---------------|
| `location` | Azure region for deployment | `eastus` |
| `functionAppName` | Name for the Function App | Auto-generated |
| `storageAccountName` | Storage account name | Auto-generated |
| `appInsightsName` | Application Insights name | Auto-generated |
| `websites` | Array of websites to monitor | `['https://www.microsoft.com', 'https://azure.microsoft.com']` |
| `checkIntervalMinutes` | Minutes between uptime checks | `5` |

### Terraform Variables

| Variable | Description | Default Value |
|----------|-------------|---------------|
| `resource_group_name` | Resource group name | `rg-uptime-checker` |
| `location` | Azure region | `East US` |
| `function_app_name` | Function App name | Auto-generated |
| `storage_account_name` | Storage account name | Auto-generated |
| `app_insights_name` | Application Insights name | Auto-generated |
| `websites_to_monitor` | List of websites to monitor | `["https://www.microsoft.com", "https://azure.microsoft.com"]` |
| `timer_schedule` | CRON expression for timer trigger | `0 */5 * * * *` |

### Environment Variables for Bash Scripts

| Variable | Description | Required |
|----------|-------------|----------|
| `AZURE_LOCATION` | Azure region | No (defaults to eastus) |
| `WEBSITES_TO_MONITOR` | Comma-separated list of URLs | No (uses defaults) |
| `CHECK_INTERVAL` | Timer schedule CRON expression | No (defaults to every 5 minutes) |

## Deployment Steps

### 1. Pre-deployment Setup

```bash
# Login to Azure (if not already logged in)
az login

# Set your preferred subscription
az account set --subscription "your-subscription-id"

# Create a resource group (if using Terraform or manual deployment)
az group create \
    --name rg-uptime-checker \
    --location eastus
```

### 2. Deploy Infrastructure

Choose one of the deployment methods above based on your preference and organizational standards.

### 3. Post-deployment Verification

```bash
# Verify Function App deployment
az functionapp list \
    --resource-group <your-resource-group> \
    --output table

# Check Application Insights configuration
az monitor app-insights component show \
    --app <app-insights-name> \
    --resource-group <your-resource-group>

# View recent function executions
az monitor app-insights query \
    --app <app-insights-name> \
    --resource-group <your-resource-group> \
    --analytics-query "traces | where timestamp > ago(30m) | order by timestamp desc"
```

## Monitoring and Alerting

The deployed solution includes:

- **Function App**: Serverless uptime checking function with timer trigger
- **Application Insights**: Comprehensive telemetry collection and analysis
- **Alert Rules**: Automatic notifications when websites are detected as down
- **Action Groups**: Configurable notification channels

### Accessing Monitoring Data

1. **Azure Portal**: Navigate to your Application Insights resource
2. **Live Metrics**: View real-time function execution data
3. **Logs**: Query custom telemetry using KQL (Kusto Query Language)
4. **Dashboards**: Create custom visualizations of uptime data

### Sample Queries

```kql
// View uptime check results from the last 24 hours
traces
| where timestamp > ago(24h)
| where message contains "✅" or message contains "❌"
| order by timestamp desc

// Calculate uptime percentage by website
traces
| where timestamp > ago(24h)
| where message contains "✅" or message contains "❌"
| extend website = extract(@"(https?://[^\s:]+)", 1, message)
| extend status = iff(message contains "✅", "UP", "DOWN")
| summarize 
    total_checks = count(),
    successful_checks = countif(status == "UP"),
    uptime_percentage = round(100.0 * countif(status == "UP") / count(), 2)
    by website
| order by uptime_percentage desc
```

## Customization

### Adding More Websites

#### Bicep
Edit the `websites` parameter in your deployment command or parameter file.

#### Terraform
Update the `websites_to_monitor` variable in `terraform.tfvars` or pass via command line:

```bash
terraform apply -var='websites_to_monitor=["https://example1.com","https://example2.com"]'
```

#### Bash Scripts
Set the `WEBSITES_TO_MONITOR` environment variable:

```bash
export WEBSITES_TO_MONITOR="https://example1.com,https://example2.com"
./scripts/deploy.sh
```

### Modifying Check Frequency

Update the timer schedule (CRON expression) to change how often checks run:

- Every minute: `0 * * * * *`
- Every 10 minutes: `0 */10 * * * *`
- Every hour: `0 0 * * * *`
- Every day at 9 AM: `0 0 9 * * *`

### Enhancing Function Logic

The deployed function code can be modified to include:

- Custom HTTP headers for authentication
- POST request monitoring for API endpoints
- Response time SLA validation
- Content validation (checking for specific text)
- Geographic availability testing

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
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# When prompted, type 'yes' to confirm deletion
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Troubleshooting

### Common Issues

1. **Function Not Executing**
   - Verify timer trigger configuration
   - Check Function App runtime status
   - Review Application Insights logs for errors

2. **No Telemetry Data**
   - Confirm Application Insights connection string is configured
   - Verify Function App has proper permissions
   - Check for any function runtime errors

3. **Alerts Not Firing**
   - Validate alert rule configuration
   - Ensure action groups are properly configured
   - Check alert rule evaluation frequency

### Debug Commands

```bash
# Check Function App configuration
az functionapp config show \
    --name <function-app-name> \
    --resource-group <resource-group>

# View Function App logs
az functionapp log tail \
    --name <function-app-name> \
    --resource-group <resource-group>

# Test function manually
az rest \
    --method post \
    --url "https://<function-app-name>.azurewebsites.net/admin/functions/UptimeChecker"
```

## Cost Optimization

This solution is designed for cost efficiency:

- **Function App**: Consumption plan provides pay-per-execution pricing
- **Application Insights**: First 1GB of data ingestion per month is free
- **Storage Account**: Minimal storage requirements for function metadata
- **Estimated Cost**: $0.01-$0.50 per day for monitoring 5-10 websites

### Cost Reduction Tips

1. Adjust check frequency based on SLA requirements
2. Use sampling in Application Insights for high-volume scenarios
3. Set up retention policies for log data
4. Monitor and adjust alert thresholds to reduce noise

## Security Considerations

The deployed infrastructure follows Azure security best practices:

- **Managed Identity**: Function App uses system-assigned managed identity
- **HTTPS Only**: All function endpoints require HTTPS
- **Network Security**: Resources are deployed with appropriate network controls
- **Access Control**: Role-based access control (RBAC) for resource management

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure Function Apps documentation: https://docs.microsoft.com/en-us/azure/azure-functions/
3. Review Application Insights documentation: https://docs.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview
4. Consult Azure CLI reference: https://docs.microsoft.com/en-us/cli/azure/

## License

This infrastructure code is provided as-is for educational and reference purposes. Please review and test thoroughly before using in production environments.