# Infrastructure as Code for Serverless Containers with Event Grid and Container Instances

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Serverless Containers with Event Grid and Container Instances".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.15.0 or higher installed and configured
- Azure subscription with appropriate permissions for creating:
  - Resource groups
  - Storage accounts
  - Event Grid topics and subscriptions
  - Container instances and registries
  - Function apps
  - Log Analytics workspaces
  - Action groups
- For Bicep: Azure CLI with Bicep extension installed
- For Terraform: Terraform v1.0+ installed
- Bash shell environment (Linux, macOS, or Windows Subsystem for Linux)

## Architecture Overview

This solution implements an event-driven serverless architecture that:

1. **Storage Events**: Automatically triggers on blob creation in Azure Storage
2. **Event Processing**: Routes events through Azure Event Grid with filtering
3. **Container Execution**: Deploys Azure Container Instances for processing
4. **Webhook Integration**: Uses Azure Function Apps for event handling
5. **Monitoring**: Provides comprehensive logging and alerting

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to the bicep directory
cd bicep/

# Login to Azure (if not already logged in)
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Create resource group
az group create --name "rg-event-driven-containers" --location "eastus"

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-event-driven-containers" \
    --template-file main.bicep \
    --parameters @parameters.json

# Verify deployment
az deployment group show \
    --resource-group "rg-event-driven-containers" \
    --name "main"
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
az group show --name "rg-event-driven-containers" --query "properties.provisioningState"
```

## Configuration

### Environment Variables

The following environment variables are used across all implementations:

```bash
export RESOURCE_GROUP="rg-event-driven-containers"
export LOCATION="eastus"
export STORAGE_ACCOUNT="steventcontainers$(openssl rand -hex 4)"
export CONTAINER_REGISTRY="acreventcontainers$(openssl rand -hex 4)"
export EVENT_GRID_TOPIC="egt-container-events"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
```

### Bicep Parameters

Customize the deployment by editing `bicep/parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "storageAccountSku": {
      "value": "Standard_LRS"
    },
    "containerRegistrySku": {
      "value": "Basic"
    },
    "functionAppRuntimeStack": {
      "value": "node"
    }
  }
}
```

### Terraform Variables

Customize the deployment by editing `terraform/terraform.tfvars`:

```hcl
location = "eastus"
resource_group_name = "rg-event-driven-containers"
storage_account_sku = "Standard_LRS"
container_registry_sku = "Basic"
function_app_runtime = "node"
```

## Testing the Solution

### Upload Test File

```bash
# Set storage account variables
STORAGE_ACCOUNT=$(az storage account list --resource-group "rg-event-driven-containers" --query "[0].name" -o tsv)
STORAGE_KEY=$(az storage account keys list --resource-group "rg-event-driven-containers" --account-name $STORAGE_ACCOUNT --query "[0].value" -o tsv)

# Upload test file to trigger events
echo "Test file for event processing" > test-file.txt
az storage blob upload \
    --account-name $STORAGE_ACCOUNT \
    --account-key $STORAGE_KEY \
    --container-name "input" \
    --name "test-file.txt" \
    --file test-file.txt
```

### Monitor Events

```bash
# Check Event Grid metrics
az monitor metrics list \
    --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-event-driven-containers/providers/Microsoft.EventGrid/topics/egt-container-events" \
    --metric "PublishedEvents" \
    --interval PT1M

# View container logs
CONTAINER_NAME=$(az container list --resource-group "rg-event-driven-containers" --query "[0].name" -o tsv)
az container logs --resource-group "rg-event-driven-containers" --name $CONTAINER_NAME
```

## Monitoring and Troubleshooting

### View Deployment Status

```bash
# Check resource group status
az group show --name "rg-event-driven-containers"

# List all resources
az resource list --resource-group "rg-event-driven-containers" --output table

# Check Event Grid topic
az eventgrid topic show --name "egt-container-events" --resource-group "rg-event-driven-containers"
```

### Log Analytics Queries

Access the Log Analytics workspace to run queries:

```kusto
// Container instance logs
ContainerInstanceLog_CL
| where TimeGenerated > ago(1h)
| project TimeGenerated, ContainerGroup_s, ContainerName_s, LogEntry_s

// Event Grid delivery attempts
AzureActivity
| where ResourceProvider == "Microsoft.EventGrid"
| where ActivityStatus == "Failed"
| project TimeGenerated, ResourceId, ActivityStatus, ActivitySubstatus
```

### Common Issues

1. **Event Grid subscription validation fails**
   - Ensure webhook endpoint is accessible
   - Check function app deployment status
   - Verify CORS settings if applicable

2. **Container instances fail to start**
   - Check container registry authentication
   - Verify resource quotas
   - Review container instance logs

3. **Storage events not triggering**
   - Verify event subscription configuration
   - Check storage account event settings
   - Ensure proper file upload to monitored containers

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name "rg-event-driven-containers" --yes --no-wait
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

# Confirm when prompted
```

### Manual Cleanup Verification

```bash
# Verify resource group deletion
az group exists --name "rg-event-driven-containers"

# Clean up any remaining resources if needed
az resource list --resource-group "rg-event-driven-containers" --output table
```

## Cost Optimization

### Resource Costs

- **Storage Account**: ~$0.01-0.05/GB/month
- **Container Registry**: ~$5/month (Basic tier)
- **Container Instances**: ~$0.0012/vCPU/second + $0.00013/GB/second
- **Event Grid**: ~$0.60/million operations
- **Function App**: Consumption plan - pay per execution
- **Log Analytics**: ~$2.30/GB ingested

### Cost Optimization Tips

1. **Container Instances**: Use appropriate CPU/memory sizing
2. **Storage**: Implement lifecycle policies for blob storage
3. **Event Grid**: Use event filtering to reduce unnecessary operations
4. **Function Apps**: Optimize code for faster execution times
5. **Log Analytics**: Set appropriate retention policies

## Security Considerations

### Implemented Security Features

- **Storage Account**: Private access with key-based authentication
- **Container Registry**: Admin access enabled for deployment
- **Event Grid**: Webhook validation and HTTPS endpoints
- **Function Apps**: Managed identity integration
- **Monitoring**: Comprehensive logging and alerting

### Additional Security Recommendations

1. **Network Security**: Implement Virtual Network integration
2. **Identity Management**: Use Azure AD integration
3. **Secrets Management**: Integrate with Azure Key Vault
4. **Access Control**: Apply least privilege RBAC policies
5. **Monitoring**: Set up security alerts and monitoring

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Azure Documentation**: [Azure Event Grid](https://docs.microsoft.com/en-us/azure/event-grid/)
3. **Container Instances**: [Azure Container Instances](https://docs.microsoft.com/en-us/azure/container-instances/)
4. **Bicep Documentation**: [Azure Bicep](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
5. **Terraform Azure Provider**: [HashiCorp Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)

## Contributing

When modifying this infrastructure code:

1. Follow Azure naming conventions
2. Maintain backward compatibility
3. Update documentation accordingly
4. Test changes in development environment
5. Validate security configurations

## Version History

- **v1.0**: Initial implementation with Event Grid and Container Instances
- Support for Bicep, Terraform, and Bash deployment methods
- Comprehensive monitoring and logging setup
- Security best practices implementation