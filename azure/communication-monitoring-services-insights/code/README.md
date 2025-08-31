# Infrastructure as Code for Communication Monitoring with Communication Services and Application Insights

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Communication Monitoring with Communication Services and Application Insights".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a comprehensive communication monitoring system that includes:

- **Azure Communication Services**: Enterprise-grade email and SMS capabilities
- **Log Analytics Workspace**: Centralized data store for monitoring telemetry
- **Application Insights**: Advanced monitoring with dashboards and alerting
- **Diagnostic Settings**: Automated telemetry data flow configuration
- **Metric Alerts**: Proactive monitoring and incident response

## Prerequisites

### Required Tools
- Azure CLI installed and configured (version 2.37.0 or later)
- Bicep CLI (for Bicep deployments)
- Terraform (version 1.0 or later, for Terraform deployments)
- Appropriate Azure permissions for resource creation

### Required Permissions
- Contributor role on the target subscription or resource group
- Communication Services Contributor role
- Log Analytics Contributor role
- Application Insights Component Contributor role

### Cost Considerations
- Estimated cost: $5-10 USD for initial testing
- Communication Services: Charges per message sent (includes free monthly quotas)
- Log Analytics: Charges for data ingestion and retention
- Application Insights: Free tier available with usage limits

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Login to Azure
az login

# Set your subscription (replace with your subscription ID)
az account set --subscription "your-subscription-id"

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-comm-monitor-demo" \
    --template-file main.bicep \
    --parameters location="eastus" \
                environment="demo" \
                resourcePrefix="commmon"

# View deployment outputs
az deployment group show \
    --resource-group "rg-comm-monitor-demo" \
    --name "main" \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan \
    -var="resource_group_name=rg-comm-monitor-demo" \
    -var="location=eastus" \
    -var="environment=demo"

# Apply the configuration
terraform apply \
    -var="resource_group_name=rg-comm-monitor-demo" \
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

# Set required environment variables
export RESOURCE_GROUP="rg-comm-monitor-demo"
export LOCATION="eastus"
export ENVIRONMENT="demo"

# Deploy the infrastructure
./deploy.sh

# View deployment status
az group list --query "[?name=='${RESOURCE_GROUP}']"
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `environment` | Environment tag (dev/test/prod) | `demo` | No |
| `resourcePrefix` | Prefix for resource names | `commmon` | No |
| `retentionInDays` | Log Analytics retention period | `30` | No |
| `alertsEnabled` | Enable metric alerts | `true` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `resource_group_name` | Name of the resource group | - | Yes |
| `location` | Azure region for deployment | `East US` | No |
| `environment` | Environment tag | `demo` | No |
| `resource_prefix` | Prefix for resource names | `commmon` | No |
| `log_retention_days` | Log Analytics retention | `30` | No |
| `enable_alerts` | Enable metric alerts | `true` | No |

### Script Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `RESOURCE_GROUP` | Resource group name | Yes |
| `LOCATION` | Azure region | Yes |
| `ENVIRONMENT` | Environment tag | No |
| `RESOURCE_PREFIX` | Resource name prefix | No |

## Post-Deployment Configuration

### 1. Configure Communication Services Domain

```bash
# List available email domains (requires setup in Azure portal)
az communication email domain list \
    --resource-group "${RESOURCE_GROUP}"

# Configure sender authentication for email services
# Note: Domain verification must be completed in Azure portal
```

### 2. Test Monitoring Integration

```bash
# Verify diagnostic settings are active
COMM_SERVICE_NAME=$(az communication list \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[0].name" --output tsv)

az monitor diagnostic-settings list \
    --resource "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Communication/communicationServices/${COMM_SERVICE_NAME}"
```

### 3. Access Application Insights

```bash
# Get Application Insights connection string
AI_NAME=$(az monitor app-insights component list \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[0].name" --output tsv)

az monitor app-insights component show \
    --app "${AI_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "connectionString" --output tsv
```

## Monitoring and Alerting

### Key Metrics to Monitor

- **Email Delivery Rate**: Percentage of successfully delivered emails
- **SMS Delivery Rate**: Percentage of successfully delivered SMS messages
- **API Request Failures**: Failed requests to Communication Services
- **Resource Utilization**: Log Analytics workspace usage and costs

### Custom Queries

Access Log Analytics workspace and use these sample KQL queries:

```kql
// Email delivery success rate over time
ACSEmailSendMailOperational
| where TimeGenerated >= ago(24h)
| summarize 
    Total = count(),
    Successful = countif(Level == "Informational"),
    Failed = countif(Level == "Error")
    by bin(TimeGenerated, 1h)
| extend SuccessRate = round((todouble(Successful) / todouble(Total)) * 100, 2)
| render timechart
```

### Alert Configuration

The deployment includes automatic alerts for:
- API request failures exceeding threshold
- High error rates in email/SMS delivery
- Log Analytics workspace approaching limits

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Check current Azure context
   az account show
   
   # Verify resource provider registration
   az provider register --namespace Microsoft.Communication
   az provider register --namespace Microsoft.OperationalInsights
   ```

2. **Diagnostic Settings Not Working**
   ```bash
   # Verify Communication Services resource exists
   az communication list --resource-group "${RESOURCE_GROUP}"
   
   # Check diagnostic settings configuration
   az monitor diagnostic-settings list --resource "${COMM_SERVICE_ID}"
   ```

3. **Missing Log Data**
   ```bash
   # Verify Log Analytics workspace is receiving data
   az monitor log-analytics workspace show \
       --resource-group "${RESOURCE_GROUP}" \
       --workspace-name "${LOG_WORKSPACE_NAME}"
   ```

### Log Files

- Deployment logs: Check Azure Activity Log in the portal
- Application logs: Available in Application Insights Logs section
- Resource logs: Available in Log Analytics workspace

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name "rg-comm-monitor-demo" \
    --yes \
    --no-wait

# Verify deletion
az group exists --name "rg-comm-monitor-demo"
```

### Using Terraform

```bash
cd terraform/

# Destroy the infrastructure
terraform destroy \
    -var="resource_group_name=rg-comm-monitor-demo" \
    -var="location=eastus" \
    -var="environment=demo"

# Verify state is clean
terraform show
```

### Using Bash Scripts

```bash
cd scripts/

# Run cleanup script
./destroy.sh

# Verify resources are deleted
az group list --query "[?name=='${RESOURCE_GROUP}']"
```

## Customization

### Adding Custom Metrics

1. **Modify Diagnostic Settings**: Edit the IaC templates to include additional log categories
2. **Create Custom Queries**: Add KQL queries in Log Analytics for specific metrics
3. **Configure Dashboards**: Create Azure Monitor workbooks for visualization

### Scaling Considerations

- **Multi-Region**: Deploy resources across multiple Azure regions for high availability
- **Cost Optimization**: Implement log retention policies and data archiving
- **Performance**: Configure Application Insights sampling for high-volume scenarios

### Security Enhancements

- **Network Security**: Implement Private Endpoints for Communication Services
- **Access Control**: Configure RBAC for granular permissions
- **Data Encryption**: Enable Customer Managed Keys (CMK) for additional security

## Best Practices

1. **Resource Naming**: Use consistent naming conventions with environment prefixes
2. **Tagging Strategy**: Apply comprehensive tags for cost management and governance
3. **Monitoring**: Set up comprehensive alerting and dashboard monitoring
4. **Documentation**: Maintain deployment documentation and runbooks
5. **Testing**: Implement infrastructure testing with tools like Pester or Terratest

## Support

### Documentation Links

- [Azure Communication Services Documentation](https://learn.microsoft.com/en-us/azure/communication-services/)
- [Application Insights Documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)
- [Log Analytics Workspace Documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-workspace-overview)
- [Azure Monitor Documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/)

### Additional Resources

- [Azure Communication Services Pricing](https://azure.microsoft.com/en-us/pricing/details/communication-services/)
- [KQL Query Reference](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/)
- [Azure Monitor Best Practices](https://learn.microsoft.com/en-us/azure/azure-monitor/best-practices)

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the project repository.