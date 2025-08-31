# Infrastructure as Code for Real-time Status Notifications with SignalR and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-time Status Notifications with SignalR and Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (Microsoft's recommended IaC language)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI 2.0 or later installed and configured
- Azure subscription with appropriate permissions for resource creation
- For Terraform: Terraform 1.0+ installed
- For Bicep: Azure CLI with Bicep extension installed
- Azure Functions Core Tools v4.0.5611 or higher for Node.js v4 programming model
- Node.js 18+ for function development

## Required Permissions

Your Azure account needs the following permissions:
- Contributor role on the target resource group (or subscription)
- Ability to create Azure SignalR Service instances
- Ability to create Azure Functions and App Service plans
- Ability to create Storage Accounts

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Create resource group
az group create \
    --name rg-signalr-demo \
    --location eastus

# Deploy infrastructure
az deployment group create \
    --resource-group rg-signalr-demo \
    --template-file bicep/main.bicep \
    --parameters location=eastus

# Get deployment outputs
az deployment group show \
    --resource-group rg-signalr-demo \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
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

# View deployment status
az group show --name rg-signalr-demo --query properties.provisioningState
```

## Architecture Overview

This infrastructure deploys:

- **Azure SignalR Service** (Free tier, Serverless mode)
- **Azure Functions App** (Consumption plan with Node.js 18 runtime)
- **Storage Account** (Standard LRS for Functions backend)
- **CORS Configuration** for web client access
- **Function Code Deployment** with negotiate and broadcast functions

## Configuration Options

### Bicep Parameters

- `location`: Azure region for deployment (default: eastus)
- `signalRName`: Custom name for SignalR Service (auto-generated if not provided)
- `functionAppName`: Custom name for Function App (auto-generated if not provided)
- `storageAccountName`: Custom name for Storage Account (auto-generated if not provided)

### Terraform Variables

- `location`: Azure region for deployment
- `resource_group_name`: Name of the resource group
- `signalr_name`: Name for the SignalR Service
- `function_app_name`: Name for the Function App
- `storage_account_name`: Name for the Storage Account
- `tags`: Resource tags (optional)

## Post-Deployment Steps

After infrastructure deployment, you'll need to:

1. **Deploy Function Code**: The infrastructure creates the Function App, but you need to deploy the actual function code:

```bash
# Clone or create your function project
func init signalr-functions --javascript --worker-runtime node --model V4
cd signalr-functions

# Install dependencies
npm install @azure/functions

# Deploy functions
func azure functionapp publish <your-function-app-name>
```

2. **Test the Solution**: Use the provided test client or create your own:

```bash
# Get Function App URL
FUNCTION_URL=$(az functionapp show \
    --name <your-function-app-name> \
    --resource-group rg-signalr-demo \
    --query defaultHostName \
    --output tsv)

# Test negotiate endpoint
curl -X POST https://${FUNCTION_URL}/api/negotiate
```

## Monitoring and Observability

The deployed infrastructure includes:

- **Application Insights** integration for Functions monitoring
- **SignalR Service metrics** available in Azure Monitor
- **Function execution logs** in Application Insights
- **Storage Account diagnostics** for troubleshooting

Access monitoring through:
```bash
# View Function App logs
az functionapp log tail --name <your-function-app-name> --resource-group rg-signalr-demo

# View SignalR Service metrics
az monitor metrics list \
    --resource <signalr-resource-id> \
    --metric "ConnectionCount,MessageCount"
```

## Scaling and Performance

The deployed solution includes:

- **SignalR Service Free Tier**: 20 concurrent connections, 20,000 messages/day
- **Functions Consumption Plan**: Auto-scaling based on demand
- **Storage Account Standard LRS**: Suitable for development/testing

For production workloads, consider:
- Upgrading SignalR Service to Standard tier for higher limits
- Using Premium Functions plan for predictable performance
- Implementing connection management and message batching

## Security Considerations

The infrastructure implements:

- **Managed Identity** integration between Functions and SignalR
- **Connection string protection** via App Settings
- **CORS configuration** (configured for demo - restrict in production)
- **HTTPS-only** communication for all services

## Cost Optimization

This deployment uses cost-effective tiers:

- **SignalR Service Free Tier**: $0/month (20 connections limit)
- **Functions Consumption Plan**: Pay per execution (~$0.20 per million executions)
- **Storage Account Standard LRS**: ~$0.024/GB per month
- **Application Insights**: 5GB free per month

Estimated monthly cost for light usage: Under $5/month

## Cleanup

### Using Bicep
```bash
# Delete resource group and all resources
az group delete --name rg-signalr-demo --yes --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   - Ensure Azure Functions Core Tools are installed
   - Verify Function App runtime version matches local development
   - Check Storage Account connectivity

2. **SignalR connection issues**:
   - Verify CORS settings allow your client domain
   - Check SignalR connection string configuration
   - Ensure negotiate function returns valid connection info

3. **Resource naming conflicts**:
   - Storage account names must be globally unique
   - SignalR service names must be unique within region
   - Use the random suffix generation in scripts

### Debug Commands

```bash
# Check Function App configuration
az functionapp config show --name <function-app-name> --resource-group rg-signalr-demo

# Verify SignalR Service status
az signalr show --name <signalr-name> --resource-group rg-signalr-demo

# Check Storage Account connectivity
az storage account show-connection-string \
    --name <storage-account-name> \
    --resource-group rg-signalr-demo
```

## Customization

### Environment Variables

Set these variables before deployment for custom configuration:

```bash
export AZURE_LOCATION="westus2"
export RESOURCE_GROUP_NAME="my-signalr-rg"
export SIGNALR_SERVICE_NAME="my-signalr-service"
export FUNCTION_APP_NAME="my-signalr-functions"
export STORAGE_ACCOUNT_NAME="mysignalrstorage"
```

### Function Code Modifications

The infrastructure supports custom function implementations:

- Modify negotiate function for user authentication
- Add custom broadcast functions for specific scenarios
- Implement SignalR groups for targeted messaging
- Add integration with other Azure services

## Integration Examples

### With Azure Cosmos DB
```bash
# Add Cosmos DB connection to Function App
az functionapp config appsettings set \
    --name <function-app-name> \
    --resource-group rg-signalr-demo \
    --settings "CosmosDB_ConnectionString=<cosmos-connection-string>"
```

### With Azure Service Bus
```bash
# Add Service Bus connection for message queuing
az functionapp config appsettings set \
    --name <function-app-name> \
    --resource-group rg-signalr-demo \
    --settings "ServiceBus_ConnectionString=<servicebus-connection-string>"
```

## Support

For issues with this infrastructure code:

1. **Azure SignalR Service**: [Azure SignalR Documentation](https://docs.microsoft.com/en-us/azure/azure-signalr/)
2. **Azure Functions**: [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
3. **Bicep**: [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
4. **Terraform Azure Provider**: [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update documentation for any new parameters or outputs
3. Ensure cleanup scripts remove all created resources
4. Follow Azure naming conventions and best practices
5. Update cost estimates if adding/changing resources

## License

This infrastructure code is provided as-is for educational and demonstration purposes.