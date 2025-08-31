# Infrastructure as Code for Simple Daily Quote Generator with Functions and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Daily Quote Generator with Functions and Storage".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.0.76 or later)
- Azure account with active subscription and Contributor role permissions
- Basic knowledge of REST APIs and JSON data structures
- Understanding of serverless computing concepts
- Node.js 20 or later (for function development)
- Appropriate permissions for resource creation:
  - Microsoft.Resources/resourceGroups/* (for resource group operations)
  - Microsoft.Storage/storageAccounts/* (for storage account operations)
  - Microsoft.Web/sites/* (for Function App operations)

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-quote-generator \
    --template-file main.bicep \
    --parameters location=eastus

# Get the Function App URL from outputs
az deployment group show \
    --resource-group rg-quote-generator \
    --name main \
    --query properties.outputs.functionAppUrl.value
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply

# Get outputs
terraform output function_app_url
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output the Function App URL upon completion
```

## Architecture Overview

This IaC deploys:

- **Resource Group**: Container for all resources
- **Storage Account**: Hosts Function App files and Table Storage for quotes
- **Function App**: Serverless HTTP API with Consumption plan
- **Table Storage**: NoSQL storage for quote data
- **Sample Data**: Pre-populated inspirational quotes

## Configuration Options

### Bicep Parameters

- `location`: Azure region for deployment (default: eastus)
- `storageAccountName`: Name for the storage account (auto-generated if not provided)
- `functionAppName`: Name for the Function App (auto-generated if not provided)
- `environment`: Environment tag (default: demo)

### Terraform Variables

- `location`: Azure region for deployment
- `resource_group_name`: Resource group name
- `storage_account_name`: Storage account name
- `function_app_name`: Function App name
- `tags`: Resource tags map

### Bash Script Environment Variables

The deploy script accepts these environment variables:

- `AZURE_LOCATION`: Azure region (default: eastus)
- `RESOURCE_GROUP_PREFIX`: Prefix for resource group name
- `ENVIRONMENT`: Environment tag (default: demo)

## Outputs

All implementations provide these outputs:

- **Function App URL**: The HTTP endpoint for the quote API
- **Storage Account Name**: Name of the created storage account
- **Resource Group Name**: Name of the created resource group
- **Function App Name**: Name of the created Function App

## Testing the Deployment

After deployment, test the quote API:

```bash
# Get a random quote (replace with your actual Function App URL)
curl "https://func-quote-abc123.azurewebsites.net/api/quote-function"

# Expected response format:
{
  "success": true,
  "data": {
    "id": "001",
    "quote": "The only way to do great work is to love what you do.",
    "author": "Steve Jobs",
    "category": "motivation"
  },
  "timestamp": "2025-01-XX:XX:XX.XXXZ",
  "total_quotes": 5
}
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all contained resources
az group delete --name rg-quote-generator --yes --no-wait
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

## Cost Considerations

This solution is designed to be cost-effective:

- **Azure Functions Consumption Plan**: Pay-per-execution (1M free requests/month)
- **Table Storage**: Pay-per-GB stored and transactions
- **Storage Account**: Standard LRS with Hot access tier

Estimated monthly cost for development/testing: $0.10-$0.50

## Security Features

The deployed infrastructure includes:

- **Anonymous HTTP trigger**: Suitable for public quote APIs
- **CORS enabled**: Supports web application integration
- **HTTPS only**: Secure data transmission
- **Managed identity**: Secure access between Azure services
- **Storage encryption**: Data encrypted at rest by default

## Customization

### Adding More Quotes

```bash
# Connect to your storage account
STORAGE_CONNECTION=$(az storage account show-connection-string \
    --name <your-storage-account> \
    --resource-group <your-resource-group> \
    --query connectionString --output tsv)

# Add a new quote
az storage entity insert \
    --table-name quotes \
    --entity PartitionKey=inspiration RowKey=006 \
    quote="Your custom quote here" \
    author="Author Name" category=custom \
    --connection-string "${STORAGE_CONNECTION}"
```

### Modifying Function Code

1. Update the function code in the deployed Function App
2. Use Azure Portal, VS Code Azure Functions extension, or Azure CLI
3. Redeploy using `func azure functionapp publish <function-app-name>`

## Troubleshooting

### Common Issues

1. **Function not responding**: Check Function App logs in Azure Portal
2. **CORS errors**: Verify CORS settings allow your domain
3. **Storage connection issues**: Verify storage account connection string
4. **Deployment failures**: Check resource naming constraints and permissions

### Monitoring

- Use Application Insights for function performance monitoring
- Check Azure Storage metrics for table operation insights
- Monitor Function App consumption and execution metrics

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure Functions and Table Storage documentation
3. Verify Azure CLI and tool versions are current
4. Review Azure service limits and quotas

## Additional Resources

- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Table Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/tables/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)