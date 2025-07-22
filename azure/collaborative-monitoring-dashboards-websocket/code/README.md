# Infrastructure as Code for Collaborative Monitoring Dashboards with WebSocket Synchronization

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Collaborative Monitoring Dashboards with WebSocket Synchronization".

## Available Implementations

- **Bicep**: Azure native infrastructure as code
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure deploys:
- **Azure Web PubSub**: Serverless WebSocket service for real-time communication
- **Azure Monitor**: Centralized monitoring and analytics platform
- **Azure Static Web Apps**: Global frontend hosting with CDN
- **Azure Functions**: Serverless backend processing
- **Application Insights**: Application performance monitoring
- **Log Analytics Workspace**: Centralized logging and queries
- **Storage Account**: Function app storage and state management

## Prerequisites

- Azure CLI v2.50.0 or higher installed
- Azure subscription with Contributor access
- Node.js 18.x or higher (for Function App development)
- Terraform v1.5+ (if using Terraform implementation)
- Bicep CLI (if using Bicep implementation)
- Basic familiarity with WebSocket connections and real-time applications

### Required Permissions

Your Azure account needs the following minimum permissions:
- `Contributor` role on the target resource group
- `Web PubSub Service Owner` role for Web PubSub configuration
- `Static Web Apps Contributor` role for frontend deployment
- `Storage Account Contributor` role for Function App storage

## Quick Start

### Using Bicep

```bash
# Navigate to Bicep directory
cd bicep/

# Deploy infrastructure
az deployment group create \
    --resource-group "rg-collab-dashboard" \
    --template-file main.bicep \
    --parameters @parameters.json

# Get deployment outputs
az deployment group show \
    --resource-group "rg-collab-dashboard" \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="resource_group_name=rg-collab-dashboard" \
    -var="location=eastus"

# Apply infrastructure
terraform apply \
    -var="resource_group_name=rg-collab-dashboard" \
    -var="location=eastus"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-collab-dashboard"
export LOCATION="eastus"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/deploy.sh --status
```

## Configuration Options

### Bicep Parameters

Modify `bicep/parameters.json` to customize the deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "environmentName": {
      "value": "dev"
    },
    "webPubSubSku": {
      "value": "Free_F1"
    },
    "functionAppPlan": {
      "value": "Y1"
    },
    "logRetentionDays": {
      "value": 30
    }
  }
}
```

### Terraform Variables

Customize deployment by setting variables in `terraform/terraform.tfvars`:

```hcl
# Basic configuration
resource_group_name = "rg-collab-dashboard"
location           = "eastus"
environment        = "dev"

# Service configuration
webpubsub_sku = "Free_F1"
function_app_sku = "Y1"
log_retention_days = 30

# Monitoring configuration
enable_application_insights = true
enable_diagnostic_settings = true

# Tagging
tags = {
  Environment = "Development"
  Purpose     = "CollaborativeDashboard"
  Owner       = "Platform-Team"
}
```

### Script Configuration

Set environment variables before running bash scripts:

```bash
# Required variables
export RESOURCE_GROUP="rg-collab-dashboard"
export LOCATION="eastus"

# Optional customization
export ENVIRONMENT="dev"
export WEBPUBSUB_SKU="Free_F1"
export FUNCTION_APP_SKU="Y1"
export LOG_RETENTION_DAYS="30"
```

## Post-Deployment Setup

After infrastructure deployment, complete these steps:

### 1. Deploy Function App Code

```bash
# Get Function App name from outputs
FUNCTION_APP_NAME=$(az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --query properties.outputs.functionAppName.value -o tsv)

# Deploy function code (requires local function project)
func azure functionapp publish ${FUNCTION_APP_NAME} --javascript
```

### 2. Configure Static Web App

```bash
# Get Static Web App details
STATIC_APP_NAME=$(az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --query properties.outputs.staticWebAppName.value -o tsv)

# Link backend API (if not done during deployment)
az staticwebapp backends link \
    --name ${STATIC_APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --backend-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/sites/${FUNCTION_APP_NAME}"
```

### 3. Verify Deployment

```bash
# Check Web PubSub status
az webpubsub show \
    --name $(az deployment group show --resource-group ${RESOURCE_GROUP} --name main --query properties.outputs.webPubSubName.value -o tsv) \
    --resource-group ${RESOURCE_GROUP} \
    --query provisioningState

# Test Function App endpoints
FUNCTION_URL=$(az functionapp show \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query defaultHostName -o tsv)

curl -X POST "https://${FUNCTION_URL}/api/negotiate" \
    -H "Content-Type: application/json" \
    -H "x-user-id: test-user"

# Get Static Web App URL
STATIC_URL=$(az staticwebapp show \
    --name ${STATIC_APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query defaultHostname -o tsv)

echo "Dashboard URL: https://${STATIC_URL}"
```

## Monitoring and Troubleshooting

### Application Insights Queries

Access the Log Analytics workspace to run these KQL queries:

```kusto
// Monitor WebSocket connections
SignalRServiceDiagnosticLogs
| where OperationName == "ConnectionConnected"
| summarize Connections = count() by bin(TimeGenerated, 5m)
| render timechart

// Function execution metrics
FunctionAppLogs
| where Category == "Function.MetricsCollector"
| project TimeGenerated, Level, Message
| order by TimeGenerated desc

// Web PubSub message throughput
SignalRServiceDiagnosticLogs
| where OperationName contains "Message"
| summarize Messages = count() by bin(TimeGenerated, 1m)
| render timechart
```

### Common Issues

**WebSocket Connection Failures**:
- Verify Web PubSub service is running
- Check Function App CORS settings
- Validate connection string configuration

**Function App Not Responding**:
- Check Application Insights for exceptions
- Verify storage account accessibility
- Review function app settings and connection strings

**Static Web App Deploy Issues**:
- Ensure GitHub repository is properly linked
- Check build and deployment logs
- Verify API backend linking

### Health Checks

```bash
# Check all service health
./scripts/health-check.sh

# Monitor specific services
az monitor metrics list \
    --resource "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.SignalRService/webPubSub/${WEBPUBSUB_NAME}" \
    --metric "ConnectionCount" \
    --interval PT1M
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name "rg-collab-dashboard" \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="resource_group_name=rg-collab-dashboard" \
    -var="location=eastus"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
az group exists --name "rg-collab-dashboard"
```

## Cost Optimization

### Development Environment

- Use **Free** tier for Web PubSub (1,000 concurrent connections)
- Use **Consumption** plan for Function Apps (first 1M executions free)
- Use **Free** tier for Static Web Apps (100GB bandwidth)
- Set 30-day retention for Log Analytics to minimize storage costs

### Production Considerations

- Monitor Web PubSub connection usage and upgrade tier as needed
- Consider **Premium** Function App plan for consistent performance
- Implement connection pooling and efficient message batching
- Use Azure Monitor cost management alerts

### Cost Monitoring

```bash
# Enable cost alerts
az consumption budget create \
    --budget-name "dashboard-budget" \
    --amount 50 \
    --time-grain Monthly \
    --resource-group ${RESOURCE_GROUP}
```

## Security Considerations

### Authentication and Authorization

- Configure Azure AD authentication for Static Web Apps
- Implement proper CORS policies
- Use managed identities for service-to-service communication
- Enable Web PubSub access keys rotation

### Network Security

- Configure private endpoints for production deployments
- Implement proper firewall rules
- Use Azure Key Vault for sensitive configuration
- Enable diagnostic logging for security monitoring

### Data Protection

- Enable encryption at rest for all storage services
- Configure HTTPS-only access for all endpoints
- Implement proper input validation in Function Apps
- Use Azure Monitor for security event tracking

## Customization

### Adding Custom Metrics

Extend the metrics collection by modifying the Function App code:

```javascript
// Add custom metric collection
const customMetrics = await client.queryResource(
    resourceId,
    ["Custom Metric Name"],
    { timespan: "PT5M", interval: "PT1M" }
);
```

### Dashboard Enhancements

- Add new chart types in the frontend application
- Implement user presence indicators
- Create custom annotation features
- Add real-time alerts and notifications

### Scaling Considerations

- Configure Web PubSub auto-scaling policies
- Implement Function App scaling rules
- Use Azure Front Door for global distribution
- Consider Azure Service Bus for message queuing

## Development Workflow

### Local Development

```bash
# Start local Function App
cd function-app/
func host start

# Start frontend development server
cd frontend/
npm run dev

# Test WebSocket connections locally
wscat -c ws://localhost:7071/api/ws
```

### CI/CD Integration

The infrastructure supports GitHub Actions deployment:

```yaml
name: Deploy Dashboard Infrastructure
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      - name: Deploy Infrastructure
        run: |
          az deployment group create \
            --resource-group ${{ vars.RESOURCE_GROUP }} \
            --template-file bicep/main.bicep \
            --parameters @bicep/parameters.json
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../building-real-time-collaborative-dashboards-with-azure-web-pubsub-and-azure-monitor.md)
2. Review [Azure Web PubSub documentation](https://docs.microsoft.com/en-us/azure/azure-web-pubsub/)
3. Consult [Azure Monitor best practices](https://docs.microsoft.com/en-us/azure/azure-monitor/best-practices)
4. Review [Azure Static Web Apps documentation](https://docs.microsoft.com/en-us/azure/static-web-apps/)

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Update documentation for any new parameters
3. Ensure backward compatibility
4. Add appropriate validation and error handling
5. Update the README with new features or changes