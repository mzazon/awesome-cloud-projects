# Infrastructure as Code for DevOps Monitoring with Live Dashboard Updates

This directory contains Infrastructure as Code (IaC) implementations for the recipe "DevOps Monitoring with Live Dashboard Updates". This solution creates an automated real-time monitoring dashboard system that leverages Azure DevOps webhooks, Azure Functions for event processing, and Azure SignalR Service for instant web-based updates.

## Available Implementations

- **Bicep**: Azure native infrastructure as code (Microsoft's recommended IaC language)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

The solution deploys the following Azure resources:

- **Azure SignalR Service** (Standard tier) - Real-time messaging infrastructure
- **Azure Functions** (Consumption plan) - Serverless event processing
- **Azure Storage Account** - Functions storage requirements
- **Azure App Service** - Web dashboard hosting
- **Azure Monitor** - Infrastructure monitoring and alerting
- **Log Analytics Workspace** - Centralized logging

## Prerequisites

- Azure CLI v2.37.0 or later installed and configured
- Azure subscription with appropriate permissions for resource creation
- Node.js v16 or later (for local development and testing)
- Bicep CLI v0.22.X or later (for Bicep deployments)
- Terraform v1.0 or later (for Terraform deployments)
- Git client for source code management
- Estimated cost: $25-50/month for development environment

### Required Azure Permissions

The deployment requires the following Azure RBAC roles:
- `Contributor` role on the target resource group
- `SignalR Service Contributor` role for SignalR Service configuration
- `Function App Contributor` role for Azure Functions deployment

## Quick Start

### Using Bicep

```bash
# Navigate to the bicep directory
cd bicep/

# Create resource group
az group create --name rg-monitoring-dashboard --location eastus

# Deploy infrastructure
az deployment group create \
    --resource-group rg-monitoring-dashboard \
    --template-file main.bicep \
    --parameters @parameters.json

# Get deployment outputs
az deployment group show \
    --resource-group rg-monitoring-dashboard \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment information
cat deployment-info.json
```

## Configuration

### Bicep Parameters

The Bicep template accepts the following parameters (defined in `parameters.json`):

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `location` | string | Azure region for resources | `eastus` |
| `resourcePrefix` | string | Prefix for resource names | `monitor` |
| `signalRSku` | string | SignalR Service SKU | `Standard_S1` |
| `functionAppRuntime` | string | Functions runtime stack | `node` |
| `functionAppRuntimeVersion` | string | Functions runtime version | `18` |
| `webAppSku` | string | App Service Plan SKU | `B1` |
| `environment` | string | Environment tag | `development` |

### Terraform Variables

The Terraform configuration uses the following variables (defined in `variables.tf`):

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `location` | string | Azure region | `East US` |
| `resource_group_name` | string | Resource group name | `rg-monitoring-dashboard` |
| `resource_prefix` | string | Resource name prefix | `monitor` |
| `signalr_sku` | string | SignalR Service SKU | `Standard_S1` |
| `function_app_runtime` | string | Functions runtime | `node` |
| `app_service_sku` | string | App Service Plan SKU | `B1` |
| `tags` | map(string) | Resource tags | `{}` |

Create a `terraform.tfvars` file to customize these values:

```hcl
location = "East US"
resource_group_name = "rg-monitoring-dashboard"
resource_prefix = "mycompany"
signalr_sku = "Standard_S1"
tags = {
  Environment = "development"
  Project     = "monitoring-dashboard"
  Owner       = "devops-team"
}
```

## Post-Deployment Configuration

### 1. Azure DevOps Service Hooks

After deployment, configure Azure DevOps Service Hooks to send events to the Function App:

```bash
# Get the webhook URL from deployment outputs
WEBHOOK_URL=$(az deployment group show \
    --resource-group rg-monitoring-dashboard \
    --name main \
    --query properties.outputs.webhookUrl.value -o tsv)

echo "Configure Azure DevOps Service Hooks with URL: $WEBHOOK_URL"
```

1. Navigate to your Azure DevOps project settings
2. Go to **Service hooks** 
3. Create a new service hook:
   - **Service**: Web Hooks
   - **Event**: Build completed, Release deployment completed
   - **URL**: Use the webhook URL from deployment outputs
   - **Resource details**: All events

### 2. Dashboard Access

Access the real-time dashboard using the Web App URL:

```bash
# Get dashboard URL from deployment outputs
DASHBOARD_URL=$(az deployment group show \
    --resource-group rg-monitoring-dashboard \
    --name main \
    --query properties.outputs.dashboardUrl.value -o tsv)

echo "Dashboard available at: $DASHBOARD_URL"
```

### 3. Function App Code Deployment

The infrastructure deployment creates the Function App, but you need to deploy the function code:

```bash
# Clone the function code (if not already available)
git clone https://github.com/your-org/monitoring-functions.git
cd monitoring-functions

# Deploy to Function App
func azure functionapp publish <function-app-name>
```

## Monitoring and Maintenance

### Health Checks

Verify the deployment health:

```bash
# Check SignalR Service status
az signalr show \
    --name <signalr-name> \
    --resource-group rg-monitoring-dashboard \
    --query provisioningState

# Check Function App status
az functionapp show \
    --name <function-app-name> \
    --resource-group rg-monitoring-dashboard \
    --query state

# Check Web App status
az webapp show \
    --name <web-app-name> \
    --resource-group rg-monitoring-dashboard \
    --query state
```

### Scaling Considerations

- **SignalR Service**: Automatically scales based on connection count
- **Azure Functions**: Consumption plan scales automatically based on events
- **App Service**: Consider upgrading to Premium tier for production loads

### Security Recommendations

1. **Enable HTTPS only** for all web services
2. **Configure managed identities** for service-to-service authentication
3. **Use Azure Key Vault** for connection strings and secrets
4. **Enable Azure Monitor** for comprehensive logging and alerting
5. **Configure network security groups** for production environments

## Cost Optimization

### Development Environment

- Use consumption plans for Functions and SignalR
- Use Basic tier for App Service Plan
- Enable auto-shutdown for non-production environments

### Production Environment

- Consider Premium plans for guaranteed performance
- Use reserved instances for predictable workloads
- Enable cost monitoring and alerts

## Troubleshooting

### Common Issues

1. **Function App fails to start**
   - Check that the storage account is accessible
   - Verify SignalR connection string is configured
   - Review Function App logs in Azure Monitor

2. **SignalR connections fail**
   - Ensure SignalR Service is in "Default" mode (not Serverless)
   - Check network connectivity and firewall settings
   - Verify CORS settings if accessing from different domains

3. **Dashboard not receiving updates**
   - Test the webhook endpoint directly
   - Check Function App execution logs
   - Verify SignalR hub configuration

### Debugging Commands

```bash
# Check Function App logs
az functionapp log tail \
    --name <function-app-name> \
    --resource-group rg-monitoring-dashboard

# Check SignalR Service metrics
az monitor metrics list \
    --resource <signalr-resource-id> \
    --metric ConnectionCount

# Test webhook endpoint
curl -X POST "<webhook-url>" \
    -H "Content-Type: application/json" \
    -d '{"eventType": "test", "resource": {"status": "success"}}'
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-monitoring-dashboard \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Remove state files (optional)
rm -rf .terraform* terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm resource cleanup
az group exists --name rg-monitoring-dashboard
```

## Customization

### Adding Custom Metrics

Extend the solution by modifying the Function App code to collect custom metrics:

```javascript
// Add custom metric collection in DevOpsWebhook function
const customMetrics = {
    deploymentDuration: calculateDeploymentTime(event),
    testResults: extractTestResults(event),
    codeQuality: parseQualityGates(event)
};

context.bindings.signalRMessages = {
    target: 'customMetrics',
    arguments: [customMetrics]
};
```

### Integration with External Systems

- **Microsoft Teams**: Add Teams webhook notifications
- **Slack**: Configure Slack integration for alerts
- **PagerDuty**: Set up incident management workflows
- **Jira**: Auto-create issues for failed deployments

## Support

For issues with this infrastructure code:

1. Check the [Azure SignalR Service documentation](https://learn.microsoft.com/en-us/azure/azure-signalr/)
2. Review [Azure Functions documentation](https://learn.microsoft.com/en-us/azure/azure-functions/)
3. Consult the [original recipe documentation](../devops-monitoring-live-dashboards.md)
4. Review [Bicep documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/) for Bicep-specific issues
5. Check [Terraform Azure Provider documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) for Terraform-specific issues

## License

This infrastructure code is provided under the same license as the parent recipe repository.