# Infrastructure as Code for Simple Todo API with Functions and Table Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Todo API with Functions and Table Storage".

## Overview

This recipe demonstrates how to build a serverless REST API using Azure Functions with HTTP triggers connected to Azure Table Storage for data persistence. The solution provides a fully managed, pay-per-execution API that handles CRUD operations without infrastructure overhead.

## Available Implementations

- **Bicep**: Microsoft's recommended infrastructure as code language for Azure
- **Terraform**: Multi-cloud infrastructure as code using HashiCorp's declarative language
- **Scripts**: Bash deployment and cleanup scripts for quick setup and teardown

## Architecture

The infrastructure provisions:
- **Azure Functions App**: Serverless compute with Node.js 18 runtime
- **Azure Storage Account**: Hosts both the Function App storage and Table Storage
- **Azure Table Storage**: NoSQL data store for todo items
- **Application Settings**: Secure configuration for storage connection strings

## Prerequisites

- Azure CLI installed and configured (`az --version` to verify)
- Azure subscription with appropriate permissions to create:
  - Resource Groups
  - Storage Accounts
  - Function Apps
- For Terraform: Terraform CLI installed (version 1.0+)
- For Bicep: Azure CLI with Bicep extension (included by default)
- Basic understanding of Azure serverless architecture

## Quick Start

### Using Bicep

Bicep is Microsoft's domain-specific language for deploying Azure resources with simplified syntax and native Azure integration.

```bash
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-todo-api-demo \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters environmentName=demo

# Get deployment outputs
az deployment group show \
    --resource-group rg-todo-api-demo \
    --name main \
    --query properties.outputs
```

### Using Terraform

Terraform provides a cloud-agnostic approach with extensive provider ecosystem and state management capabilities.

```bash
cd terraform/

# Initialize Terraform (download providers and modules)
terraform init

# Review the execution plan
terraform plan

# Deploy the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

Quick deployment scripts for development and testing environments with minimal configuration required.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will output the Function App URL and other important information
```

## Configuration Options

### Bicep Parameters

Customize the deployment by modifying parameters in `bicep/main.bicep`:

- `location`: Azure region for resource deployment (default: eastus)
- `environmentName`: Environment suffix for resource naming (default: demo)
- `functionAppRuntime`: Runtime stack for Azure Functions (default: node)
- `functionAppRuntimeVersion`: Runtime version (default: 18)

### Terraform Variables

Configure the deployment through `terraform/variables.tf`:

- `resource_group_name`: Name of the resource group
- `location`: Azure region for resources
- `storage_account_name`: Storage account name (must be globally unique)
- `function_app_name`: Function App name (must be globally unique)
- `environment`: Environment tag for resources

### Script Configuration

The bash scripts use environment variables for customization:

```bash
# Set custom values before running deploy.sh
export RESOURCE_GROUP="my-custom-rg"
export LOCATION="westus2"
export ENVIRONMENT="production"

./scripts/deploy.sh
```

## Post-Deployment Steps

After infrastructure deployment, you'll need to:

1. **Deploy Function Code**: Use the generated Function App to deploy your application code
2. **Configure CORS**: Set up Cross-Origin Resource Sharing if accessing from web applications
3. **Set up Monitoring**: Enable Application Insights for observability
4. **Configure Custom Domains**: Add custom domain names if required

### Deploy Function Code

```bash
# Example using Azure CLI
az functionapp deployment source config-zip \
    --resource-group <resource-group-name> \
    --name <function-app-name> \
    --src your-function-code.zip
```

## Testing the Deployment

### Verify Infrastructure

```bash
# Check Function App status
az functionapp show \
    --resource-group <resource-group-name> \
    --name <function-app-name> \
    --query "{name:name, state:state, hostNames:hostNames}"

# Verify Table Storage
az storage table list \
    --connection-string "<storage-connection-string>"
```

### Test API Endpoints

Once function code is deployed, test the REST API:

```bash
# Replace <function-app-url> with your actual Function App URL

# Create a todo
curl -X POST "https://<function-app-url>/api/todos" \
    -H "Content-Type: application/json" \
    -d '{"title": "Test Todo", "description": "Testing the API"}'

# Get all todos
curl -X GET "https://<function-app-url>/api/todos"

# Update a todo (replace {id} with actual ID)
curl -X PUT "https://<function-app-url>/api/todos/{id}" \
    -H "Content-Type: application/json" \
    -d '{"title": "Updated Todo", "completed": true}'

# Delete a todo (replace {id} with actual ID)
curl -X DELETE "https://<function-app-url>/api/todos/{id}"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-todo-api-demo \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Cost Considerations

This serverless architecture follows Azure's consumption-based pricing model:

- **Azure Functions**: Pay per execution and memory usage
  - Free tier: 1 million requests and 400,000 GB-seconds per month
  - Estimated cost: ~$0.10-$2.00/month for development workloads
- **Azure Storage Account**: Pay for storage used and transactions
  - Table Storage: ~$0.045 per GB stored per month
  - Transactions: ~$0.004 per 10,000 transactions
- **Application Insights**: Optional monitoring service
  - Free tier: 5 GB data ingestion per month

### Cost Optimization Tips

- Use consumption plan for Functions to pay only for actual usage
- Enable automatic scaling to handle traffic efficiently
- Monitor and set up alerts for unexpected usage spikes
- Clean up test resources regularly to avoid unnecessary charges

## Security Best Practices

The infrastructure implements several security measures:

- **Managed Identity**: Use Azure Managed Identity for secure service-to-service authentication
- **Connection String Security**: Storage connection strings are stored as encrypted application settings
- **HTTPS Only**: Function App configured to require HTTPS
- **Firewall Rules**: Consider implementing storage account network access rules for production
- **Key Rotation**: Regularly rotate storage account keys

### Additional Security Enhancements

For production deployments, consider:

- Implementing Azure API Management for API gateway functionality
- Adding Azure Active Directory authentication
- Configuring network security groups and private endpoints
- Enabling Azure Security Center recommendations
- Implementing logging and monitoring with Azure Sentinel

## Troubleshooting

### Common Issues

**Function App deployment fails**:
- Verify storage account is in the same region
- Check that storage account name is globally unique
- Ensure sufficient permissions in subscription

**Table Storage access denied**:
- Verify connection string is correctly configured
- Check storage account access keys are valid
- Ensure Function App has proper permissions

**Cold start performance**:
- Consider Premium plan for production workloads
- Implement keep-warm strategies
- Monitor performance with Application Insights

### Diagnostic Commands

```bash
# Check Function App logs
az functionapp log tail \
    --resource-group <resource-group-name> \
    --name <function-app-name>

# Verify storage account configuration
az storage account show \
    --resource-group <resource-group-name> \
    --name <storage-account-name>

# Check resource group status
az group show \
    --name <resource-group-name> \
    --query "{name:name, provisioningState:properties.provisioningState}"
```

## Customization Examples

### Adding Environment-Specific Configuration

```bash
# Development environment
az deployment group create \
    --resource-group rg-todo-api-dev \
    --template-file main.bicep \
    --parameters environmentName=dev location=eastus

# Production environment with different settings
az deployment group create \
    --resource-group rg-todo-api-prod \
    --template-file main.bicep \
    --parameters environmentName=prod location=westus2
```

### Integration with CI/CD

```yaml
# Example Azure DevOps pipeline step
- task: AzureResourceManagerTemplateDeployment@3
  displayName: 'Deploy Infrastructure'
  inputs:
    deploymentScope: 'Resource Group'
    azureResourceManagerConnection: '$(serviceConnection)'
    resourceGroupName: '$(resourceGroupName)'
    location: '$(location)'
    templateLocation: 'Linked artifact'
    csmFile: 'bicep/main.bicep'
    overrideParameters: |
      -environmentName $(Environment.Name)
      -location $(location)
```

## Support and Documentation

- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Table Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/tables/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.

## Contributing

When modifying the infrastructure code:

1. Follow Azure naming conventions and tagging standards
2. Update variable descriptions and validation rules
3. Test changes in a development environment first
4. Update this README with any new configuration options
5. Ensure backward compatibility where possible

## License

This infrastructure code is provided as part of the Azure Recipes collection and follows the same licensing terms as the main repository.