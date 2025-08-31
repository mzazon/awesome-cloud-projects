# Bicep Infrastructure for Simple Expense Tracker

This directory contains Azure Bicep templates for deploying the Simple Expense Tracker solution with Azure Cosmos DB and Azure Functions.

## Architecture Overview

The Bicep template deploys a complete serverless expense tracking solution including:

- **Azure Cosmos DB** (Serverless) with ExpenseDB database and Expenses container
- **Azure Functions** (Consumption plan) for HTTP-triggered expense operations
- **Azure Storage Account** for Functions runtime and metadata
- **Application Insights** for monitoring and telemetry
- **Log Analytics Workspace** for centralized logging
- **Managed Identity** and role assignments for secure access

## Files

- `main.bicep`: Main Bicep template with all infrastructure resources
- `parameters.json`: Example parameter values for deployment
- `README.md`: This documentation file

## Prerequisites

1. **Azure CLI** installed and configured
   ```bash
   az login
   az account set --subscription "your-subscription-id"
   ```

2. **Azure subscription** with sufficient permissions to create:
   - Resource Groups
   - Cosmos DB accounts
   - Function Apps
   - Storage Accounts
   - Application Insights
   - Log Analytics Workspaces
   - Role assignments

3. **Resource Group** (will be created if it doesn't exist)

## Quick Start

### 1. Create Resource Group

```bash
# Set variables
RESOURCE_GROUP="rg-expense-tracker-dev"
LOCATION="eastus"

# Create resource group
az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION
```

### 2. Deploy with Default Parameters

```bash
# Deploy using default parameters
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters @parameters.json
```

### 3. Deploy with Custom Parameters

```bash
# Deploy with custom parameters
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters \
        location="westus2" \
        environment="test" \
        appName="myexpense" \
        uniqueSuffix="xyz789"
```

### 4. Deploy with What-If Preview

```bash
# Preview changes before deployment
az deployment group what-if \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters @parameters.json
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `resourceGroup().location` | Azure region for deployment |
| `environment` | string | `dev` | Environment name (dev/test/prod) |
| `appName` | string | `expenses` | Application name prefix (max 8 chars) |
| `uniqueSuffix` | string | `substring(uniqueString...)` | Unique suffix for resource naming |
| `tags` | object | `{purpose: recipe...}` | Tags applied to all resources |
| `cosmosConsistencyLevel` | string | `Session` | Cosmos DB consistency level |
| `cosmosAutomaticFailover` | bool | `false` | Enable automatic failover |
| `functionRuntime` | string | `node` | Function App runtime (node/dotnet/python) |
| `functionRuntimeVersion` | string | `~4` | Functions runtime version |
| `storageAccountSku` | string | `Standard_LRS` | Storage account replication type |

## Customization Examples

### Production Environment

```bash
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters \
        environment="prod" \
        cosmosAutomaticFailover=true \
        storageAccountSku="Standard_GRS" \
        tags='{"environment":"prod","purpose":"expense-tracker","owner":"finance-team"}'
```

### Different Runtime

```bash
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters \
        functionRuntime="python" \
        functionRuntimeVersion="~4"
```

## Post-Deployment Steps

### 1. Retrieve Function Keys

```bash
# Get function app name from deployment output
FUNCTION_APP_NAME=$(az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name main \
    --query 'properties.outputs.functionAppName.value' \
    --output tsv)

# List function keys
az functionapp keys list \
    --name $FUNCTION_APP_NAME \
    --resource-group $RESOURCE_GROUP
```

### 2. Deploy Function Code

The Bicep template creates the infrastructure but doesn't deploy function code. Deploy your functions using:

```bash
# Using Azure Functions Core Tools
func azure functionapp publish $FUNCTION_APP_NAME

# Or using ZIP deployment
az functionapp deployment source config-zip \
    --resource-group $RESOURCE_GROUP \
    --name $FUNCTION_APP_NAME \
    --src functions.zip
```

### 3. Test API Endpoints

```bash
# Get function URLs
CREATE_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net/api/CreateExpense"
GET_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net/api/GetExpenses"

# Test creating an expense (add function key as query parameter)
curl -X POST "${CREATE_URL}?code=<function-key>" \
    -H "Content-Type: application/json" \
    -d '{"amount": 15.50, "category": "food", "description": "Lunch", "userId": "user123"}'

# Test retrieving expenses
curl "${GET_URL}?userId=user123&code=<function-key>"
```

## Outputs

The template provides comprehensive outputs for integration and verification:

- **Resource identifiers**: Names and IDs for all created resources
- **Connection information**: URLs and connection strings
- **Security**: Principal IDs for role assignments
- **Monitoring**: Application Insights keys and workspace information

## Security Features

- **Managed Identity**: Function App uses system-assigned managed identity
- **Role-based Access**: Cosmos DB access via Azure RBAC
- **Encryption**: Storage and Cosmos DB encrypted at rest
- **HTTPS Only**: All endpoints enforce HTTPS
- **TLS 1.2**: Minimum TLS version enforced
- **Key Vault Integration**: Ready for secret management (optional)

## Cost Optimization

- **Serverless Cosmos DB**: Pay only for consumed RUs and storage
- **Consumption Plan**: Functions charged per execution
- **Standard LRS Storage**: Locally redundant storage for cost efficiency
- **30-day Log Retention**: Balanced monitoring vs. cost

Estimated monthly cost for light usage: $0.01 - $5.00

## Monitoring and Logging

- **Application Insights**: Function performance and error tracking
- **Log Analytics**: Centralized log storage and analysis
- **Built-in Metrics**: CPU, memory, and request metrics
- **Custom Telemetry**: Ready for custom application metrics

## Cleanup

### Delete Resource Group (All Resources)

```bash
az group delete \
    --name $RESOURCE_GROUP \
    --yes \
    --no-wait
```

### Delete Specific Deployment

```bash
az deployment group delete \
    --resource-group $RESOURCE_GROUP \
    --name main
```

## Troubleshooting

### Common Issues

1. **Resource naming conflicts**: Adjust `uniqueSuffix` parameter
2. **Permission errors**: Ensure sufficient Azure subscription permissions
3. **Region availability**: Some services may not be available in all regions
4. **Quota limits**: Check Azure subscription quotas for Cosmos DB and Functions

### Validation Commands

```bash
# Check resource group
az group show --name $RESOURCE_GROUP

# Verify Cosmos DB
az cosmosdb show --name $COSMOS_ACCOUNT_NAME --resource-group $RESOURCE_GROUP

# Check Function App
az functionapp show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP

# Test connectivity
az cosmosdb collection show \
    --collection-name Expenses \
    --db-name ExpenseDB \
    --name $COSMOS_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP
```

## Advanced Configuration

### Custom VNet Integration

For production scenarios, consider adding VNet integration:

```bicep
// Add to main.bicep for VNet integration
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  // VNet configuration
}

resource functionAppVnetConfig 'Microsoft.Web/sites/networkConfig@2023-01-01' = {
  parent: functionApp
  name: 'virtualNetwork'
  properties: {
    subnetResourceId: subnet.id
  }
}
```

### Private Endpoints

For enhanced security, add private endpoints:

```bicep
// Private endpoint for Cosmos DB
resource cosmosPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  // Private endpoint configuration
}
```

## Support

For questions about this Bicep template:

1. Check Azure Bicep documentation: https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/
2. Review Azure Functions documentation: https://docs.microsoft.com/en-us/azure/azure-functions/
3. Consult Azure Cosmos DB documentation: https://docs.microsoft.com/en-us/azure/cosmos-db/

## Version History

- **v1.0**: Initial Bicep template with basic infrastructure
- **v1.1**: Added Application Insights and Log Analytics integration
- **v1.2**: Enhanced security with managed identity and RBAC