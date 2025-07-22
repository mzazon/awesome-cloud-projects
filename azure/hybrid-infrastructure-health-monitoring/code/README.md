# Infrastructure as Code for Hybrid Infrastructure Health Monitoring with Functions and Update Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Hybrid Infrastructure Health Monitoring with Functions and Update Manager".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys an automated infrastructure health monitoring system using:

- **Azure Functions Flex Consumption**: Serverless compute with VNet integration
- **Azure Update Manager**: Centralized update management and assessment
- **Azure Event Grid**: Event-driven architecture for real-time notifications
- **Azure Monitor & Log Analytics**: Comprehensive monitoring and logging
- **Azure Key Vault**: Secure credential and configuration management
- **Azure Virtual Network**: Secure connectivity to hybrid infrastructure

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Function Apps and Azure Functions
  - Virtual Networks and subnets
  - Event Grid topics and subscriptions
  - Key Vault creation and access policies
  - Log Analytics workspaces
  - Storage accounts
  - Role assignments and managed identities
- Basic understanding of Azure serverless architecture and networking concepts
- Knowledge of Azure Arc for hybrid infrastructure management (if managing on-premises resources)

### Required Azure Permissions

Your account needs the following role assignments:
- `Contributor` or `Owner` on the target resource group
- `User Access Administrator` for role assignments
- `Key Vault Administrator` for Key Vault operations

## Quick Start

### Using Bicep (Recommended)

1. **Deploy the infrastructure**:
   ```bash
   cd bicep/
   
   # Create resource group
   az group create --name rg-infra-health-monitor --location eastus
   
   # Deploy main template
   az deployment group create \
       --resource-group rg-infra-health-monitor \
       --template-file main.bicep \
       --parameters @parameters.json
   ```

2. **Verify deployment**:
   ```bash
   # Check resource group contents
   az resource list --resource-group rg-infra-health-monitor --output table
   
   # Test function app
   az functionapp function invoke \
       --name func-health-monitor-[suffix] \
       --resource-group rg-infra-health-monitor \
       --function-name HealthChecker
   ```

### Using Terraform

1. **Initialize and deploy**:
   ```bash
   cd terraform/
   
   # Initialize Terraform
   terraform init
   
   # Review deployment plan
   terraform plan
   
   # Apply configuration
   terraform apply
   ```

2. **Verify deployment**:
   ```bash
   # Show outputs
   terraform output
   
   # Test function app deployment
   terraform output function_app_name | xargs -I {} az functionapp show --name {} --resource-group $(terraform output -raw resource_group_name)
   ```

### Using Bash Scripts

1. **Deploy infrastructure**:
   ```bash
   cd scripts/
   
   # Make scripts executable
   chmod +x deploy.sh destroy.sh
   
   # Deploy infrastructure
   ./deploy.sh
   ```

2. **Monitor deployment**:
   ```bash
   # The script will provide progress updates
   # Check final status
   az functionapp list --resource-group rg-infra-health-monitor --output table
   ```

## Configuration

### Environment Variables

The following environment variables can be set to customize the deployment:

```bash
# Core Configuration
export RESOURCE_GROUP="rg-infra-health-monitor"
export LOCATION="eastus"
export ENVIRONMENT="dev"  # Options: dev, staging, prod

# Resource Naming (optional - auto-generated if not set)
export FUNCTION_APP_NAME="func-health-monitor-custom"
export STORAGE_ACCOUNT_NAME="sthealthcustom"
export KEY_VAULT_NAME="kv-health-custom"

# Network Configuration
export VNET_ADDRESS_PREFIX="10.0.0.0/16"
export SUBNET_ADDRESS_PREFIX="10.0.1.0/24"

# Monitoring Configuration
export LOG_RETENTION_DAYS="30"
export ALERT_EMAIL="admin@company.com"
```

### Bicep Parameters

Edit `bicep/parameters.json` to customize your deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "environment": {
      "value": "dev"
    },
    "functionAppSku": {
      "value": "FlexConsumption"
    },
    "vnetAddressPrefix": {
      "value": "10.0.0.0/16"
    },
    "subnetAddressPrefix": {
      "value": "10.0.1.0/24"
    },
    "logRetentionDays": {
      "value": 30
    }
  }
}
```

### Terraform Variables

Create a `terraform.tfvars` file to customize your deployment:

```hcl
# Basic Configuration
location = "East US"
environment = "dev"

# Resource Naming
resource_group_name = "rg-infra-health-monitor"
function_app_name = "func-health-monitor"
storage_account_name = "sthealthmonitor"

# Network Configuration
vnet_address_space = ["10.0.0.0/16"]
subnet_address_prefix = "10.0.1.0/24"

# Monitoring Configuration
log_analytics_retention_days = 30
enable_application_insights = true

# Tags
common_tags = {
  Environment = "dev"
  Project = "infrastructure-monitoring"
  Owner = "platform-team"
}
```

## Post-Deployment Configuration

### 1. Configure Azure Arc (for Hybrid Monitoring)

If monitoring on-premises or multi-cloud infrastructure:

```bash
# Install Azure Arc on target servers
# Download and run the installation script on each server
curl -L https://aka.ms/azcmagent | bash

# Connect servers to Azure Arc
azcmagent connect \
    --resource-group rg-infra-health-monitor \
    --tenant-id $(az account show --query tenantId -o tsv) \
    --location eastus \
    --subscription-id $(az account show --query id -o tsv)
```

### 2. Configure Update Manager

```bash
# Enable Update Manager for Azure Arc servers
az rest --method put \
    --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-infra-health-monitor/providers/Microsoft.Maintenance/configurationAssignments/default-config?api-version=2021-09-01-preview" \
    --body '{
        "properties": {
            "maintenanceConfigurationId": "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-infra-health-monitor/providers/Microsoft.Maintenance/maintenanceConfigurations/default-maintenance-config"
        }
    }'
```

### 3. Test Health Monitoring

```bash
# Trigger manual health check
FUNCTION_APP_NAME=$(az functionapp list --resource-group rg-infra-health-monitor --query '[0].name' -o tsv)

az functionapp function invoke \
    --name $FUNCTION_APP_NAME \
    --resource-group rg-infra-health-monitor \
    --function-name HealthChecker

# Check function logs
az functionapp log tail \
    --name $FUNCTION_APP_NAME \
    --resource-group rg-infra-health-monitor
```

### 4. Configure Notifications

Set up notification channels in Event Grid:

```bash
# Create email subscription for critical alerts
az eventgrid event-subscription create \
    --name "critical-health-alerts" \
    --source-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-infra-health-monitor/providers/Microsoft.EventGrid/topics/egt-health-updates-*" \
    --endpoint-type webhook \
    --endpoint "https://your-webhook-endpoint.com/alerts" \
    --included-event-types "Infrastructure.HealthCheck.Critical"

# Create Teams integration (requires Logic App or webhook)
# See Azure documentation for Teams webhook configuration
```

## Monitoring and Operations

### Health Check Monitoring

```bash
# View health check execution history
az monitor activity-log list \
    --resource-group rg-infra-health-monitor \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
    --query '[?contains(operationName.value, "Function")]'

# Check Application Insights metrics
az monitor app-insights metrics show \
    --app $(az functionapp show --name $FUNCTION_APP_NAME --resource-group rg-infra-health-monitor --query name -o tsv) \
    --resource-group rg-infra-health-monitor \
    --metric requests/count \
    --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
```

### Update Manager Operations

```bash
# View update assessments
az graph query -q "
    Resources
    | where type == 'microsoft.hybridcompute/machines'
    | where resourceGroup == 'rg-infra-health-monitor'
    | project name, location, properties.status
"

# Trigger update assessment
az maintenance assignment create \
    --resource-group rg-infra-health-monitor \
    --resource-name your-arc-server \
    --resource-type Microsoft.HybridCompute/machines \
    --provider-name Microsoft.HybridCompute \
    --configuration-assignment-name default-assessment
```

### Log Analytics Queries

Access Log Analytics workspace for detailed monitoring:

```kusto
// Function execution summary
FunctionAppLogs
| where TimeGenerated > ago(24h)
| where FunctionName in ("HealthChecker", "UpdateEventHandler")
| summarize ExecutionCount = count(), SuccessRate = countif(Level != "Error") * 100.0 / count() by FunctionName
| order by FunctionName

// Health check results
traces
| where TimeGenerated > ago(24h)
| where message contains "Health check"
| extend Status = extract(@"Status: (\w+)", 1, message)
| summarize count() by Status
| render piechart

// Event Grid delivery metrics
AzureActivity
| where TimeGenerated > ago(24h)
| where ResourceProvider == "Microsoft.EventGrid"
| where OperationName contains "Deliver"
| summarize DeliveryCount = count(), SuccessfulDeliveries = countif(ActivityStatus == "Succeeded") by bin(TimeGenerated, 1h)
| render timechart
```

## Troubleshooting

### Common Issues

1. **Function App VNet Integration Fails**:
   ```bash
   # Check subnet delegation
   az network vnet subnet show \
       --resource-group rg-infra-health-monitor \
       --vnet-name vnet-health-monitor \
       --name subnet-functions \
       --query delegations
   
   # Verify delegation is set to Microsoft.App/environments
   ```

2. **Key Vault Access Denied**:
   ```bash
   # Check managed identity assignment
   az functionapp identity show \
       --name $FUNCTION_APP_NAME \
       --resource-group rg-infra-health-monitor
   
   # Verify Key Vault access policy
   az keyvault show \
       --name kv-health-* \
       --resource-group rg-infra-health-monitor \
       --query accessPolicies
   ```

3. **Event Grid Events Not Delivered**:
   ```bash
   # Check event subscription status
   az eventgrid event-subscription list \
       --source-resource-id "/subscriptions/$(az account show --query id -o tsv)" \
       --output table
   
   # View delivery failures
   az eventgrid event-subscription show \
       --name update-manager-events \
       --source-resource-id "/subscriptions/$(az account show --query id -o tsv)" \
       --include-full-endpoint-url
   ```

### Performance Optimization

1. **Function App Cold Start Reduction**:
   - Enable "Always On" for Flex Consumption (when available)
   - Optimize function code for faster initialization
   - Use managed identity instead of connection strings

2. **Network Performance**:
   - Place resources in the same region
   - Use private endpoints for Key Vault and Storage Account
   - Configure regional Event Grid topics

3. **Cost Optimization**:
   - Adjust function timeout settings
   - Optimize Log Analytics retention periods
   - Use lifecycle policies for storage accounts

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name rg-infra-health-monitor --yes --no-wait

# Or delete specific deployment
az deployment group delete \
    --resource-group rg-infra-health-monitor \
    --name main
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
cd scripts/

# Run cleanup script
./destroy.sh

# Verify resource group is empty
az resource list --resource-group rg-infra-health-monitor --output table
```

### Manual Cleanup Verification

```bash
# Ensure all resources are removed
az resource list --resource-group rg-infra-health-monitor --output table

# Check for orphaned role assignments
az role assignment list --all --query "[?principalName==null]" --output table

# Verify Event Grid subscriptions are removed
az eventgrid event-subscription list --output table
```

## Security Considerations

### Network Security

- Virtual Network integration isolates function execution
- Subnet delegation provides secure connectivity
- Private endpoints can be added for enhanced security

### Identity and Access Management

- Managed identity eliminates credential management
- Key Vault provides secure secret storage
- Role-based access control (RBAC) limits permissions

### Data Protection

- All communications use HTTPS/TLS encryption
- Key Vault encrypts secrets at rest
- Log Analytics data is encrypted in transit and at rest

### Monitoring and Auditing

- Application Insights tracks all function executions
- Azure Activity Log records all resource operations
- Event Grid provides audit trail for event delivery

## Cost Estimation

### Monthly Cost Estimates (East US region)

| Component | Usage | Estimated Cost |
|-----------|-------|----------------|
| Azure Functions Flex Consumption | 100,000 executions/month | $5-10 |
| Storage Account (Standard LRS) | 10 GB storage | $2-3 |
| Log Analytics Workspace | 5 GB ingestion/month | $10-15 |
| Event Grid | 10,000 events/month | $1-2 |
| Key Vault | 10,000 operations/month | $3-5 |
| Virtual Network | Standard configuration | $5-10 |
| Application Insights | 5 GB telemetry/month | $10-15 |
| **Total Estimated Cost** | | **$36-60/month** |

*Costs may vary based on actual usage patterns and regional pricing differences.*

### Cost Optimization Tips

1. **Right-size Log Analytics retention**: Adjust based on compliance requirements
2. **Use lifecycle policies**: Archive old storage data automatically
3. **Monitor function execution**: Optimize code to reduce execution time
4. **Set up cost alerts**: Monitor spending with Azure Cost Management

## Support and Documentation

### Additional Resources

- [Azure Functions Flex Consumption Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/flex-consumption-plan)
- [Azure Update Manager Guide](https://docs.microsoft.com/en-us/azure/update-manager/overview)
- [Azure Event Grid Documentation](https://docs.microsoft.com/en-us/azure/event-grid/)
- [Azure Functions VNet Integration](https://docs.microsoft.com/en-us/azure/azure-functions/functions-networking-options)
- [Azure Key Vault Best Practices](https://docs.microsoft.com/en-us/azure/key-vault/general/best-practices)

### Getting Help

- **Azure Support**: Create support ticket in Azure portal
- **Community Support**: Azure forums and Stack Overflow
- **Documentation Issues**: GitHub issues for Azure documentation
- **Feature Requests**: Azure feedback portal

For issues specific to this infrastructure code, refer to the original recipe documentation or create an issue in the recipe repository.