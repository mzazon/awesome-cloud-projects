# Infrastructure as Code for Event-Driven Configuration with App Configuration and Service Bus

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Event-Driven Configuration with App Configuration and Service Bus".

## Available Implementations

- **Bicep**: Microsoft's recommended infrastructure as code language for Azure
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements an event-driven configuration management system that includes:

- **Azure App Configuration**: Centralized configuration store with versioning and feature flags
- **Azure Service Bus**: Reliable messaging infrastructure with topic-based publish-subscribe pattern
- **Azure Event Grid**: Event routing for real-time configuration change notifications
- **Azure Functions**: Serverless configuration change processing
- **Azure Logic Apps**: Visual workflow orchestration for complex configuration scenarios
- **Azure Storage Account**: Backend storage for Azure Functions runtime

## Prerequisites

- Azure CLI v2.37.0 or later installed and configured
- Azure subscription with appropriate permissions for creating:
  - Resource groups
  - App Configuration stores
  - Service Bus namespaces
  - Azure Functions
  - Logic Apps
  - Storage accounts
  - Event Grid subscriptions
- For Terraform: Terraform CLI v1.0+ installed
- For Bicep: Bicep CLI installed (included with Azure CLI)
- Bash shell environment (Linux, macOS, or Windows with WSL)

## Cost Estimation

Expected monthly costs for development/testing workloads:
- Azure App Configuration (Standard): ~$1-3/month
- Service Bus (Standard): ~$10-15/month  
- Azure Functions (Consumption): ~$0-2/month
- Logic Apps (Consumption): ~$0-2/month
- Storage Account: ~$1-3/month
- Event Grid: ~$0-1/month

**Total estimated cost: $15-25/month**

## Quick Start

### Using Bicep

```bash
# Navigate to Bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-config-management \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters appConfigName=appconfig-$(openssl rand -hex 3) \
    --parameters serviceBusNamespace=sb-config-$(openssl rand -hex 3)

# Verify deployment
az deployment group show \
    --resource-group rg-config-management \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create execution plan
terraform plan \
    -var="location=eastus" \
    -var="environment=dev"

# Apply infrastructure changes
terraform apply \
    -var="location=eastus" \
    -var="environment=dev"

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
echo "Deployment completed. Resource group: $RESOURCE_GROUP"
```

## Configuration

### Bicep Parameters

Key parameters you can customize in your deployment:

- `location`: Azure region for resource deployment (default: eastus)
- `appConfigName`: Name for App Configuration store (must be globally unique)
- `serviceBusNamespace`: Service Bus namespace name (must be globally unique)
- `functionAppName`: Azure Functions app name (must be globally unique)
- `storageAccountName`: Storage account name (must be globally unique)
- `environment`: Environment tag for resources (dev/staging/prod)

### Terraform Variables

Customize the deployment by modifying variables in `terraform.tfvars`:

```hcl
location = "eastus"
environment = "dev"
resource_group_name = "rg-config-management-dev"
app_config_sku = "standard"
service_bus_sku = "Standard"
```

### Environment Variables (Bash Scripts)

Set these environment variables before running scripts:

```bash
export LOCATION="eastus"
export ENVIRONMENT="dev"
export RESOURCE_GROUP="rg-config-management-dev"
```

## Deployment Steps

### 1. Pre-deployment Validation

```bash
# Verify Azure CLI authentication
az account show

# Check subscription permissions
az provider list --query "[?namespace=='Microsoft.AppConfiguration'].registrationState" -o table
az provider list --query "[?namespace=='Microsoft.ServiceBus'].registrationState" -o table
az provider list --query "[?namespace=='Microsoft.Web'].registrationState" -o table
```

### 2. Resource Group Creation

If the resource group doesn't exist:

```bash
az group create \
    --name rg-config-management \
    --location eastus \
    --tags purpose=configuration-management environment=demo
```

### 3. Deploy Infrastructure

Choose one of the deployment methods above (Bicep, Terraform, or Bash scripts).

### 4. Post-deployment Configuration

```bash
# Add sample configuration keys
az appconfig kv set \
    --name <app-config-name> \
    --key "config/web/app-title" \
    --value "My Web Application"

# Create feature flag
az appconfig feature set \
    --name <app-config-name> \
    --feature "config/features/enable-notifications" \
    --yes
```

## Validation & Testing

### 1. Verify Resource Deployment

```bash
# Check all resources in resource group
az resource list \
    --resource-group rg-config-management \
    --output table

# Verify App Configuration store
az appconfig show \
    --name <app-config-name> \
    --query "{name:name,provisioningState:provisioningState,endpoint:endpoint}"

# Check Service Bus topic and subscriptions
az servicebus topic subscription list \
    --topic-name configuration-changes \
    --namespace-name <service-bus-namespace> \
    --resource-group rg-config-management
```

### 2. Test Event Flow

```bash
# Update configuration to trigger event
az appconfig kv set \
    --name <app-config-name> \
    --key "config/test/sample-key" \
    --value "test-value"

# Monitor Function App logs
az functionapp logs tail \
    --name <function-app-name> \
    --resource-group rg-config-management
```

### 3. Verify Event Grid Integration

```bash
# Check Event Grid subscription status
az eventgrid event-subscription list \
    --source-resource-id "/subscriptions/<subscription-id>/resourceGroups/rg-config-management/providers/Microsoft.AppConfiguration/configurationStores/<app-config-name>" \
    --query "[].{name:name,provisioningState:provisioningState}"
```

## Troubleshooting

### Common Issues

1. **Deployment Failures**:
   - Verify resource name uniqueness (App Config, Service Bus, Function App names must be globally unique)
   - Check Azure subscription quotas and limits
   - Ensure proper permissions for Event Grid subscription creation

2. **Event Flow Issues**:
   - Verify Event Grid subscription is active
   - Check Service Bus topic permissions
   - Review Function App configuration settings

3. **Access Denied Errors**:
   - Verify Azure CLI authentication: `az account show`
   - Check RBAC permissions for resource creation
   - Ensure subscription has required resource providers registered

### Diagnostic Commands

```bash
# Check resource provider registration
az provider show --namespace Microsoft.AppConfiguration --query registrationState
az provider show --namespace Microsoft.ServiceBus --query registrationState
az provider show --namespace Microsoft.EventGrid --query registrationState

# View deployment logs
az deployment group list \
    --resource-group rg-config-management \
    --query "[0].properties.error"

# Check Function App status
az functionapp show \
    --name <function-app-name> \
    --resource-group rg-config-management \
    --query "{state:state,hostNameSslStates:hostNameSslStates[0].sslState}"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-config-management \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="location=eastus" \
    -var="environment=dev"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource group deletion
az group exists --name rg-config-management
```

### Manual Cleanup (if needed)

```bash
# Delete Event Grid subscription first
az eventgrid event-subscription delete \
    --name config-changes-to-servicebus \
    --source-resource-id "/subscriptions/<subscription-id>/resourceGroups/rg-config-management/providers/Microsoft.AppConfiguration/configurationStores/<app-config-name>"

# Delete Function App
az functionapp delete \
    --name <function-app-name> \
    --resource-group rg-config-management

# Delete Logic App
az logic workflow delete \
    --name <logic-app-name> \
    --resource-group rg-config-management

# Delete Service Bus namespace
az servicebus namespace delete \
    --name <service-bus-namespace> \
    --resource-group rg-config-management

# Delete App Configuration store
az appconfig delete \
    --name <app-config-name> \
    --resource-group rg-config-management \
    --yes

# Delete Storage Account
az storage account delete \
    --name <storage-account-name> \
    --resource-group rg-config-management \
    --yes

# Finally, delete resource group
az group delete \
    --name rg-config-management \
    --yes
```

## Security Considerations

### Best Practices Implemented

- **Least Privilege Access**: IAM roles and permissions follow principle of least privilege
- **Network Security**: Private endpoints can be configured for production deployments
- **Encryption**: All data is encrypted at rest and in transit using Azure-managed keys
- **Monitoring**: Integration with Azure Monitor for security event tracking
- **Access Control**: Azure RBAC controls access to configuration values

### Additional Security Hardening

For production deployments, consider:

1. **Private Endpoints**: Configure private endpoints for App Configuration and Service Bus
2. **Key Vault Integration**: Store sensitive configuration values in Azure Key Vault
3. **Managed Identity**: Use managed identities for service-to-service authentication
4. **Network Restrictions**: Implement virtual network integration and firewall rules
5. **Audit Logging**: Enable diagnostic logging for all services

## Monitoring and Observability

### Built-in Monitoring

The deployment includes:

- Azure Monitor integration for all services
- Application Insights for Function Apps
- Service Bus metrics and alerts
- App Configuration access logs

### Recommended Monitoring Setup

```bash
# Create Log Analytics workspace
az monitor log-analytics workspace create \
    --resource-group rg-config-management \
    --workspace-name law-config-monitoring

# Configure diagnostic settings
az monitor diagnostic-settings create \
    --name diag-appconfig \
    --resource <app-config-resource-id> \
    --workspace <workspace-id> \
    --logs '[{"category":"HttpRequest","enabled":true}]'
```

## Extensions and Customizations

### Adding Custom Processing Logic

1. **Function App Customization**: Modify the Function code to implement custom configuration processing logic
2. **Logic Apps Integration**: Extend Logic Apps workflows for complex business rules
3. **Multiple Environments**: Deploy separate instances for different environments (dev/staging/prod)
4. **Configuration Validation**: Add validation functions to test configuration changes before propagation

### Integration Examples

```bash
# Add webhook integration
az functionapp config appsettings set \
    --name <function-app-name> \
    --resource-group rg-config-management \
    --settings "WebhookUrl=https://your-webhook-endpoint.com/config-changes"

# Configure Teams notifications
az functionapp config appsettings set \
    --name <function-app-name> \
    --resource-group rg-config-management \
    --settings "TeamsWebhookUrl=https://outlook.office.com/webhook/your-teams-webhook"
```

## Support and Documentation

### Additional Resources

- [Azure App Configuration Documentation](https://docs.microsoft.com/en-us/azure/azure-app-configuration/)
- [Azure Service Bus Documentation](https://docs.microsoft.com/en-us/azure/service-bus/)
- [Azure Event Grid Documentation](https://docs.microsoft.com/en-us/azure/event-grid/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)

### Getting Help

For issues with this infrastructure code:

1. Review the original recipe documentation for architectural guidance
2. Check Azure service documentation for specific service configurations
3. Consult Azure troubleshooting guides for deployment issues
4. Use Azure support channels for service-specific problems

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow Azure best practices and security guidelines
3. Update documentation to reflect any changes
4. Validate that all deployment methods continue to work correctly