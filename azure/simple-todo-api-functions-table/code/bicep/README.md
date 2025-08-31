# Simple Todo API - Bicep Infrastructure as Code

This directory contains Bicep templates for deploying the Simple Todo API with Azure Functions and Table Storage infrastructure.

## Architecture

The Bicep template creates the following Azure resources:

- **Storage Account**: Stores both Function App content and Todo data via Table Storage
- **Table Storage**: NoSQL storage for Todo items with the `todos` table
- **App Service Plan**: Consumption (Serverless) plan for cost-effective scaling
- **Function App**: Node.js 18 runtime with HTTP triggers for REST API endpoints
- **Application Insights**: Monitoring and telemetry (optional)
- **Role Assignments**: Managed identity permissions for secure storage access

## Files

- `main.bicep`: Main Bicep template defining all infrastructure resources
- `parameters.json`: Example parameter values for deployment
- `README.md`: This documentation file

## Prerequisites

Before deploying, ensure you have:

- Azure CLI installed and authenticated (`az login`)
- Bicep CLI installed (`az bicep install`)
- Appropriate Azure subscription permissions for:
  - Creating resource groups
  - Creating storage accounts
  - Creating function apps
  - Assigning IAM roles

## Quick Start

### 1. Deploy with Default Parameters

```bash
# Create resource group
az group create --name "rg-simple-todo-api" --location "East US"

# Deploy template
az deployment group create \
  --resource-group "rg-simple-todo-api" \
  --template-file main.bicep \
  --parameters parameters.json
```

### 2. Deploy with Custom Parameters

```bash
# Deploy with custom resource prefix
az deployment group create \
  --resource-group "rg-simple-todo-api" \
  --template-file main.bicep \
  --parameters resourcePrefix="mytodo" environment="prod" location="West US 2"
```

### 3. Deploy with Inline Parameters

```bash
az deployment group create \
  --resource-group "rg-simple-todo-api" \
  --template-file main.bicep \
  --parameters @parameters.json \
  --parameters resourcePrefix="demo" storageAccountSku="Standard_GRS"
```

## Parameters

| Parameter | Type | Description | Default | Allowed Values |
|-----------|------|-------------|---------|----------------|
| `location` | string | Azure region for resources | `resourceGroup().location` | Any Azure region |
| `environment` | string | Environment name | `dev` | `dev`, `test`, `prod` |
| `resourcePrefix` | string | Prefix for resource names (3-10 chars) | Required | 3-10 characters |
| `enableApplicationInsights` | bool | Enable monitoring | `true` | `true`, `false` |
| `storageAccountSku` | string | Storage replication | `Standard_LRS` | `Standard_LRS`, `Standard_GRS`, `Standard_RAGRS` |
| `runtimeStack` | string | Function runtime | `node` | `node`, `python`, `dotnet` |
| `runtimeVersion` | string | Runtime version | `18` | Version string |
| `tags` | object | Resource tags | Default tags | Key-value pairs |

## Outputs

The template provides the following outputs for integration and testing:

| Output | Description |
|--------|-------------|
| `functionAppName` | Name of the created Function App |
| `functionAppUrl` | HTTPS URL of the Function App |
| `storageAccountName` | Name of the Storage Account |
| `todosTableName` | Name of the Todos table |
| `functionAppPrincipalId` | Managed identity ID for additional permissions |
| `applicationInsightsInstrumentationKey` | Application Insights key |
| `applicationInsightsConnectionString` | Application Insights connection string |
| `resourceGroupName` | Resource group name |
| `storageConnectionString` | Storage connection string for development |
| `apiBaseUrl` | Base URL for API endpoints |
| `testCommands` | Sample curl commands for testing |

## Post-Deployment Steps

### 1. Verify Resources

```bash
# List created resources
az resource list --resource-group "rg-simple-todo-api" --output table

# Check Function App status
az functionapp show --name "<function-app-name>" --resource-group "rg-simple-todo-api" --query "state"
```

### 2. Get Deployment Outputs

```bash
# Get all outputs
az deployment group show \
  --resource-group "rg-simple-todo-api" \
  --name "main" \
  --query "properties.outputs"

# Get specific output (e.g., Function App URL)
az deployment group show \
  --resource-group "rg-simple-todo-api" \
  --name "main" \
  --query "properties.outputs.functionAppUrl.value" -o tsv
```

### 3. Deploy Function Code

After infrastructure deployment, deploy your function code:

```bash
# Using Azure Functions Core Tools
func azure functionapp publish <function-app-name>

# Using Azure CLI (zip deployment)
az functionapp deployment source config-zip \
  --resource-group "rg-simple-todo-api" \
  --name "<function-app-name>" \
  --src "function-code.zip"
```

### 4. Test the API

Use the output `testCommands` or manually test endpoints:

```bash
# Get API base URL
API_URL=$(az deployment group show \
  --resource-group "rg-simple-todo-api" \
  --name "main" \
  --query "properties.outputs.apiBaseUrl.value" -o tsv)

# Test endpoints
curl -X POST "${API_URL}/todos" \
  -H "Content-Type: application/json" \
  -d '{"title": "Test Todo", "description": "Testing API", "completed": false}'

curl -X GET "${API_URL}/todos"
```

## Security Features

The template implements several security best practices:

- **HTTPS Only**: Function App requires HTTPS connections
- **Managed Identity**: Function App uses system-assigned managed identity
- **RBAC**: Principle of least privilege with specific storage roles
- **TLS 1.2**: Minimum TLS version enforced
- **Storage Encryption**: Storage encryption at rest enabled
- **Public Access**: Blob public access disabled by default

## Cost Optimization

- **Consumption Plan**: Pay-per-execution pricing model
- **Standard_LRS**: Locally redundant storage for development
- **Application Insights**: Basic tier with 30-day retention
- **Auto-scaling**: Automatic scaling based on demand

## Monitoring and Observability

When Application Insights is enabled:

- **Function Execution Metrics**: Duration, success/failure rates
- **HTTP Request Telemetry**: Response times, status codes
- **Dependency Tracking**: Storage account interactions
- **Live Metrics**: Real-time performance monitoring
- **Custom Telemetry**: Application-level logging

Access monitoring:
```bash
# Get Application Insights resource
az monitor app-insights component show \
  --resource-group "rg-simple-todo-api" \
  --app "<app-insights-name>"
```

## Troubleshooting

### Common Issues

1. **Deployment Fails with Role Assignment Error**
   - Ensure your account has Owner or User Access Administrator role
   - Check if the subscription allows role assignments

2. **Function App Not Starting**
   - Verify storage account connection string
   - Check Application Insights configuration
   - Review Function App logs in Azure portal

3. **API Returns 500 Errors**
   - Check Function App logs
   - Verify table storage permissions
   - Validate storage connection string

### Diagnostic Commands

```bash
# Check deployment status
az deployment group list --resource-group "rg-simple-todo-api" --output table

# View Function App logs
az webapp log tail --resource-group "rg-simple-todo-api" --name "<function-app-name>"

# Test storage connectivity
az storage table list --connection-string "<storage-connection-string>"
```

## Cleanup

To remove all resources:

```bash
# Delete resource group and all resources
az group delete --name "rg-simple-todo-api" --yes --no-wait
```

## Customization

### Environment-Specific Deployments

Create separate parameter files for different environments:

```bash
# parameters.dev.json
{
  "parameters": {
    "environment": {"value": "dev"},
    "storageAccountSku": {"value": "Standard_LRS"},
    "enableApplicationInsights": {"value": true}
  }
}

# parameters.prod.json
{
  "parameters": {
    "environment": {"value": "prod"},
    "storageAccountSku": {"value": "Standard_GRS"},
    "enableApplicationInsights": {"value": true}
  }
}
```

### Adding Custom Domains

To add a custom domain, modify the Function App configuration:

```bicep
resource customDomain 'Microsoft.Web/sites/hostNameBindings@2023-01-01' = {
  parent: functionApp
  name: 'api.yourdomain.com'
  properties: {
    siteName: functionApp.name
    hostNameType: 'Verified'
  }
}
```

### Scaling Configuration

Adjust scaling settings for production workloads:

```bicep
// In the Function App site config
functionAppScaleLimit: 50  // Limit concurrent executions
minimumElasticInstanceCount: 1  // Always-warm instances
```

## Support

For issues with this Bicep template:

1. Check the [Azure Bicep documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
2. Review the original recipe documentation
3. Validate template syntax: `az bicep build --file main.bicep`
4. Use `--debug` flag for detailed deployment logs

## Version History

- **v1.0**: Initial template with Function App and Table Storage
- **v1.1**: Added Application Insights and role-based security
- **v1.2**: Enhanced with comprehensive outputs and documentation