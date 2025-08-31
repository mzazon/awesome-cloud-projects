# Infrastructure as Code for Simple Data Collection API with Azure Functions and Cosmos DB

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Data Collection API with Azure Functions and Cosmos DB".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az --version` to verify)
- Azure subscription with Contributor permissions
- Azure Functions Core Tools v4.0.5382 or higher
- Node.js 18.x or 20.x for function development
- Terraform 1.0+ (for Terraform deployment)
- Basic knowledge of REST APIs and HTTP methods

> **Note**: This solution uses Azure Functions Consumption plan and Cosmos DB free tier, making it very cost-effective for development and testing scenarios.

## Architecture Overview

This IaC deploys a serverless REST API consisting of:

- **Azure Functions**: HTTP-triggered serverless compute for CRUD operations
- **Cosmos DB**: NoSQL database with automatic scaling and global distribution
- **Storage Account**: Required for Azure Functions runtime and logging
- **Application Insights**: Function monitoring and diagnostics (optional)

## Quick Start

### Using Bicep (Recommended)

Azure Bicep is Microsoft's domain-specific language for deploying Azure resources. It provides a more readable and maintainable alternative to ARM templates.

```bash
# Navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-data-api-demo" \
    --template-file main.bicep \
    --parameters location="eastus" \
    --parameters appName="dataapi$(openssl rand -hex 3)"

# Get the Function App URL for testing
FUNCTION_APP_NAME=$(az deployment group show \
    --resource-group "rg-data-api-demo" \
    --name "main" \
    --query "properties.outputs.functionAppName.value" \
    --output tsv)

echo "Function App URL: https://${FUNCTION_APP_NAME}.azurewebsites.net"
```

### Using Terraform

Terraform provides a consistent workflow for managing infrastructure across multiple cloud providers.

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="location=eastus"

# Apply the configuration
terraform apply -var="location=eastus"

# Get outputs
terraform output function_app_url
terraform output cosmos_db_endpoint
```

### Using Bash Scripts

The bash scripts provide a streamlined deployment experience using Azure CLI commands.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output the Function App URL and other important information
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for resources | `eastus` | No |
| `appName` | Unique name prefix for resources | Generated | No |
| `cosmosDbThroughput` | Cosmos DB container throughput (RU/s) | `400` | No |
| `functionAppPlan` | Functions hosting plan | `Y1` (Consumption) | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for resources | `East US` | No |
| `resource_group_name` | Resource group name | `rg-data-api-terraform` | No |
| `app_name_prefix` | Unique name prefix | `dataapi` | No |
| `cosmos_throughput` | Cosmos DB throughput | `400` | No |

### Environment Variables (Bash Scripts)

| Variable | Description | Default |
|----------|-------------|---------|
| `LOCATION` | Azure region | `eastus` |
| `RESOURCE_GROUP` | Resource group name | Generated with random suffix |
| `APP_NAME` | Application name prefix | Generated with random suffix |

## Testing the Deployed API

After deployment, test the CRUD operations using the Function App URL:

### Create a Record

```bash
# Replace FUNCTION_APP_URL with your actual URL
curl -X POST "https://FUNCTION_APP_URL/api/records" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "Sample Record",
      "category": "test",
      "description": "This is a test record"
    }'
```

### Get All Records

```bash
curl -X GET "https://FUNCTION_APP_URL/api/records"
```

### Get Specific Record

```bash
# Replace RECORD_ID with actual ID from create response
curl -X GET "https://FUNCTION_APP_URL/api/records/{RECORD_ID}"
```

### Update a Record

```bash
curl -X PUT "https://FUNCTION_APP_URL/api/records/{RECORD_ID}" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "Updated Record",
      "category": "updated",
      "description": "This record has been updated"
    }'
```

### Delete a Record

```bash
curl -X DELETE "https://FUNCTION_APP_URL/api/records/{RECORD_ID}"
```

## Monitoring and Troubleshooting

### View Function Logs

```bash
# Using Azure CLI
az functionapp logs tail \
    --name YOUR_FUNCTION_APP_NAME \
    --resource-group YOUR_RESOURCE_GROUP

# Or view in Azure Portal
echo "Navigate to: https://portal.azure.com -> Function Apps -> YOUR_FUNCTION_APP_NAME -> Functions -> Logs"
```

### Check Cosmos DB Metrics

```bash
# View Cosmos DB account information
az cosmosdb show \
    --name YOUR_COSMOS_ACCOUNT_NAME \
    --resource-group YOUR_RESOURCE_GROUP \
    --query "{name:name, documentEndpoint:documentEndpoint, provisioningState:provisioningState}"
```

### Common Issues

1. **Function App not responding**: Check if the Function App is running and properly configured
2. **Cosmos DB connection errors**: Verify connection string in Function App settings
3. **CORS issues**: Configure CORS settings in Function App if accessing from browser
4. **Authentication errors**: Ensure proper permissions and connection strings

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name "rg-data-api-demo" \
    --yes \
    --no-wait

echo "Cleanup initiated. Resources will be deleted in the background."
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="location=eastus"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Cost Optimization

This solution is designed to be cost-effective:

- **Azure Functions Consumption Plan**: Pay only for execution time (1M free requests/month)
- **Cosmos DB Free Tier**: 1000 RU/s and 25 GB storage included free
- **Storage Account**: Minimal costs for function metadata and logs

Estimated monthly cost for development workloads: $3-8 USD

## Security Considerations

The deployed infrastructure includes several security best practices:

- **Managed Identity**: Functions use managed identity for secure Cosmos DB access
- **Connection String Security**: Secrets stored in Function App settings, not code
- **HTTPS Only**: All API endpoints enforce HTTPS
- **Firewall Rules**: Cosmos DB configured with appropriate access controls

For production deployments, consider:

- Implementing Azure AD authentication
- Adding API Management for rate limiting
- Using Azure Key Vault for secrets management
- Enabling diagnostic logging and monitoring

## Customization

### Adding Authentication

To add Azure AD authentication to your Function App:

```bash
# Enable authentication using Azure CLI
az functionapp auth update \
    --name YOUR_FUNCTION_APP_NAME \
    --resource-group YOUR_RESOURCE_GROUP \
    --enabled true \
    --action LoginWithAzureActiveDirectory
```

### Scaling Configuration

To modify Cosmos DB throughput:

```bash
# Update container throughput
az cosmosdb sql container throughput update \
    --account-name YOUR_COSMOS_ACCOUNT \
    --resource-group YOUR_RESOURCE_GROUP \
    --database-name DataCollectionDB \
    --name records \
    --throughput 800
```

### Function App Settings

To add custom application settings:

```bash
az functionapp config appsettings set \
    --name YOUR_FUNCTION_APP_NAME \
    --resource-group YOUR_RESOURCE_GROUP \
    --settings "CUSTOM_SETTING=value"
```

## Development Workflow

### Local Development

1. **Install Azure Functions Core Tools**:
   ```bash
   npm install -g azure-functions-core-tools@4 --unsafe-perm true
   ```

2. **Clone function code locally**:
   ```bash
   func init --typescript --model V4
   # Copy the function code from the recipe
   ```

3. **Run locally**:
   ```bash
   npm install
   npm run build
   func start
   ```

### Continuous Deployment

For production scenarios, consider setting up continuous deployment:

```bash
# Configure GitHub Actions deployment
az functionapp deployment source config \
    --name YOUR_FUNCTION_APP_NAME \
    --resource-group YOUR_RESOURCE_GROUP \
    --repo-url YOUR_GITHUB_REPO \
    --branch main \
    --manual-integration
```

## Support

- **Azure Functions Documentation**: [https://docs.microsoft.com/en-us/azure/azure-functions/](https://docs.microsoft.com/en-us/azure/azure-functions/)
- **Azure Cosmos DB Documentation**: [https://docs.microsoft.com/en-us/azure/cosmos-db/](https://docs.microsoft.com/en-us/azure/cosmos-db/)
- **Azure Bicep Documentation**: [https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- **Terraform Azure Provider**: [https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or open an issue in the repository.

## Contributing

When modifying the infrastructure code:

1. Test changes in a development environment
2. Update documentation as needed
3. Validate all deployment methods work correctly
4. Ensure cleanup procedures are tested
5. Update cost estimates if resource configurations change

## Version History

- **v1.0**: Initial implementation with basic CRUD operations
- **v1.1**: Added comprehensive monitoring and security enhancements