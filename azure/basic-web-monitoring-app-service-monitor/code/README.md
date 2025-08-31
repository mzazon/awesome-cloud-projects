# Infrastructure as Code for Basic Web App Monitoring with App Service and Azure Monitor

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Basic Web App Monitoring with App Service and Azure Monitor".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture

This template deploys a complete web application monitoring solution including:

- **App Service Plan**: Hosting plan for the web application (configurable SKU)
- **App Service Web App**: Containerized Node.js web application  
- **Log Analytics Workspace**: Centralized logging and analytics platform
- **Application Insights**: Application performance monitoring
- **Diagnostic Settings**: Routes logs and metrics to Log Analytics
- **Alert Rules**: Proactive monitoring alerts for:
  - High response time (>5 seconds)
  - HTTP 5xx errors (>10 in 5 minutes)
  - High CPU usage (>80% for 10 minutes)
  - High memory usage (>85% for 10 minutes)
- **Action Group**: Email notifications for alerts

## Prerequisites

- Azure CLI installed and configured (version 2.37.0 or later) ([Installation Guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli))
- Active Azure subscription with Contributor access
- Bash shell environment (Linux, macOS, or Windows Subsystem for Linux)
- For Bicep: Bicep CLI extension installed (`az bicep install`)
- For Terraform: Terraform CLI installed (version 1.0 or later)
- Email address for alert notifications

### Estimated Costs

- **App Service Plan (F1 Free tier)**: $0/month
- **Log Analytics Workspace**: ~$2-5/month (based on data ingestion)
- **Azure Monitor Alerts**: ~$0.10 per alert rule per month
- **Total estimated cost**: $2-6/month

> **Note**: Costs may vary based on actual usage, data retention settings, and alert frequency.

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to the bicep directory
cd bicep/

# Set required parameters
export EMAIL_ADDRESS="your-email@example.com"
export LOCATION="eastus"

# Create resource group
az group create \
    --name "rg-web-monitoring-demo" \
    --location "${LOCATION}"

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-web-monitoring-demo" \
    --template-file main.bicep \
    --parameters alertEmail="${EMAIL_ADDRESS}" \
    --parameters location="${LOCATION}"
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create a terraform.tfvars file with your configuration
cat > terraform.tfvars << EOF
resource_group_name = "rg-web-monitoring-demo"
location = "eastus"
alert_email = "your-email@example.com"
app_name_prefix = "webapp"
environment = "demo"
EOF

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export RESOURCE_GROUP="rg-web-monitoring-demo"
export LOCATION="eastus"
export ALERT_EMAIL="your-email@example.com"

# Deploy the infrastructure
./scripts/deploy.sh
```

## Configuration Options

### Bicep Parameters

- `location`: Azure region for resource deployment (default: "eastus")
- `appNamePrefix`: Prefix for App Service and related resources (default: "webapp")
- `alertEmail`: Email address for alert notifications (required)
- `environment`: Environment tag for resources (default: "demo")
- `logRetentionDays`: Log retention period in days (default: 30)

### Terraform Variables

- `resource_group_name`: Name of the resource group (required)
- `location`: Azure region for deployment (default: "eastus")
- `alert_email`: Email address for notifications (required)
- `app_name_prefix`: Prefix for resource names (default: "webapp")
- `environment`: Environment designation (default: "demo")
- `log_retention_days`: Log Analytics retention in days (default: 30)
- `response_time_threshold`: Alert threshold in seconds (default: 5)
- `error_count_threshold`: HTTP 5xx error count threshold (default: 10)

### Bash Script Variables

Set these environment variables before running the deployment script:

- `RESOURCE_GROUP`: Resource group name (required)
- `LOCATION`: Azure region (required)
- `ALERT_EMAIL`: Email for notifications (required)
- `APP_NAME_PREFIX`: Resource name prefix (optional)
- `ENVIRONMENT`: Environment tag (optional)

## What Gets Deployed

This infrastructure creates the following Azure resources:

1. **Resource Group**: Container for all resources
2. **App Service Plan**: Free tier (F1) hosting plan
3. **App Service**: Web application with sample Node.js container
4. **Log Analytics Workspace**: Centralized logging and analytics
5. **Diagnostic Settings**: Log and metric collection configuration
6. **Action Group**: Email notification configuration
7. **Metric Alert Rules**:
   - High response time alert (>5 seconds)
   - HTTP 5xx error alert (>10 errors in 5 minutes)

## Monitoring Features

### Automatic Logging

- **Application Logs**: Captures application output and errors
- **Web Server Logs**: Records HTTP requests and responses
- **Platform Metrics**: CPU, memory, and request statistics
- **Diagnostic Logs**: Platform-level operational information

### Alert Conditions

1. **Performance Alert**: Triggers when average response time exceeds 5 seconds over 5 minutes
2. **Error Alert**: Triggers when HTTP 5xx errors exceed 10 occurrences in 5 minutes

### Log Analytics Queries

Access your monitoring data using these sample KQL queries:

```kql
// Recent HTTP requests
AppServiceHTTPLogs
| where TimeGenerated > ago(1h)
| project TimeGenerated, CsHost, CsUriStem, ScStatus, TimeTaken
| order by TimeGenerated desc

// Application errors
AppServiceConsoleLogs
| where TimeGenerated > ago(24h)
| where ResultDescription contains "error"
| project TimeGenerated, ResultDescription

// Performance metrics
AverageResponseTime
| where TimeGenerated > ago(6h)
| render timechart
```

## Validation

After deployment, verify the setup:

1. **Check web application**: Visit the App Service URL provided in the output
2. **Verify logging**: View live logs in the Azure portal or via CLI
3. **Test monitoring**: Generate some traffic to create log entries
4. **Confirm alerts**: Check that alert rules are enabled and configured

### CLI Validation Commands

```bash
# Get the web app URL
az webapp show \
    --name "<your-app-name>" \
    --resource-group "<your-resource-group>" \
    --query "defaultHostName" \
    --output tsv

# Check application logs
az webapp log tail \
    --name "<your-app-name>" \
    --resource-group "<your-resource-group>"

# Verify alert rules
az monitor metrics alert list \
    --resource-group "<your-resource-group>" \
    --output table
```

## Monitoring and Alerts

### View Logs in Azure Portal

1. Navigate to your Log Analytics workspace
2. Go to **Logs** section
3. Query application logs:

```kusto
AppServiceHTTPLogs
| where TimeGenerated > ago(1h)
| limit 50
```

### Test Alert Rules

Generate test traffic to trigger alerts:

```bash
# Generate multiple requests to test response time
for i in {1..10}; do
  curl https://your-app-name.azurewebsites.net
  sleep 1
done
```

## Cost Optimization

- **Free Tier (F1)**: $0/month for App Service plan
- **Log Analytics**: Pay-per-GB ingested (1GB daily cap included)
- **Application Insights**: First 5GB/month free
- **Alerts**: First 1000 alert evaluations/month free

## Customization

### Modifying Alert Thresholds

Edit the alert rule parameters in your chosen IaC template:

- **Response Time**: Adjust `response_time_threshold` variable
- **Error Count**: Modify `error_count_threshold` variable
- **Time Windows**: Change evaluation frequency and window size

### Adding Custom Metrics

Extend the solution by:

1. Adding Application Insights for detailed application telemetry
2. Creating custom log queries for specific business metrics
3. Implementing availability tests for uptime monitoring
4. Adding autoscaling rules based on performance metrics

### Environment-Specific Configurations

Create multiple parameter files for different environments:

```bash
# Development environment
terraform.dev.tfvars

# Staging environment
terraform.staging.tfvars

# Production environment
terraform.prod.tfvars
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name "rg-web-monitoring-demo" \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm when prompted to delete resources
```

## Troubleshooting

### Common Issues

1. **Deployment Failures**:
   - Verify Azure CLI is logged in: `az account show`
   - Check subscription permissions: `az role assignment list --assignee $(az account show --query user.name --output tsv)`
   - Ensure resource group exists or can be created

2. **Missing Logs**:
   - Wait 5-10 minutes after deployment for log collection to begin
   - Generate web traffic by visiting the application URL
   - Check diagnostic settings are properly configured

3. **Alert Not Triggering**:
   - Verify email address is correct in action group
   - Check alert rule thresholds and time windows
   - Generate sufficient load to trigger thresholds

### Useful Commands

```bash
# Check deployment status
az deployment group list \
    --resource-group "<your-resource-group>" \
    --output table

# View resource group resources
az resource list \
    --resource-group "<your-resource-group>" \
    --output table

# Test web application
curl -I https://<your-app-name>.azurewebsites.net
```

## Security Considerations

This implementation follows Azure security best practices:

- Uses managed identities where possible
- Implements least privilege access patterns
- Enables diagnostic logging for audit trails
- Uses Azure Monitor for centralized security monitoring
- Follows Azure Well-Architected Framework security principles

> **Important**: For production deployments, consider additional security measures such as private endpoints, network security groups, and Azure Key Vault for sensitive configuration.

## Support

For issues with this infrastructure code:

1. Review the [original recipe documentation](../basic-web-monitoring-app-service-monitor.md)
2. Consult [Azure App Service documentation](https://docs.microsoft.com/en-us/azure/app-service/)
3. Check [Azure Monitor documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)
4. Review [Azure CLI reference](https://docs.microsoft.com/en-us/cli/azure/)