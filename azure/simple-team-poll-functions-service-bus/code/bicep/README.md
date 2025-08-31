# Azure Bicep Template - Simple Team Poll System

This directory contains Azure Bicep templates for deploying a serverless team polling system using Azure Functions and Service Bus.

## Architecture Overview

The template deploys the following Azure resources:

- **Azure Functions App**: Serverless compute hosting the polling API endpoints
- **Service Bus Namespace & Queue**: Reliable message queuing for vote processing
- **Storage Account**: Function app storage and poll results persistence
- **Application Insights**: Monitoring and diagnostics for the Function App
- **App Service Plan**: Consumption plan for cost-effective serverless hosting

## Files Structure

- `main.bicep`: Main Bicep template with all resource definitions
- `parameters.json`: Example parameter values for deployment
- `README.md`: This documentation file

## Prerequisites

Before deploying this template, ensure you have:

1. **Azure CLI**: Version 2.50.0 or later
   ```bash
   az --version
   ```

2. **Azure Subscription**: Active subscription with appropriate permissions
   - Contributor role on the target resource group or subscription
   - Permission to create role assignments

3. **Bicep CLI**: Latest version installed
   ```bash
   az bicep install
   az bicep upgrade
   ```

4. **Resource Group**: Target resource group for deployment
   ```bash
   az group create --name rg-poll-system --location "East US"
   ```

## Quick Deployment

### Using Azure CLI with Parameters File

1. **Clone or download** the template files to your local machine

2. **Review and customize** the `parameters.json` file:
   ```json
   {
     "resourcePrefix": { "value": "poll" },
     "environment": { "value": "dev" },
     "location": { "value": "East US" }
   }
   ```

3. **Deploy the template**:
   ```bash
   az deployment group create \
     --resource-group rg-poll-system \
     --template-file main.bicep \
     --parameters @parameters.json
   ```

### Using Azure CLI with Inline Parameters

```bash
az deployment group create \
  --resource-group rg-poll-system \
  --template-file main.bicep \
  --parameters resourcePrefix=poll \
               environment=dev \
               location="East US"
```

### Using Azure Portal

1. Navigate to the Azure Portal
2. Search for "Deploy a custom template"
3. Select "Build your own template in the editor"
4. Copy and paste the contents of `main.bicep`
5. Click "Save" and fill in the parameter values
6. Click "Review + create" and then "Create"

## Parameter Reference

| Parameter | Type | Default | Description | Allowed Values |
|-----------|------|---------|-------------|----------------|
| `resourcePrefix` | string | 'poll' | Prefix for all resource names | Any string |
| `location` | string | resourceGroup().location | Azure region for deployment | Any Azure region |
| `environment` | string | 'dev' | Environment designation | 'dev', 'test', 'prod' |
| `serviceBusSku` | string | 'Basic' | Service Bus pricing tier | 'Basic', 'Standard', 'Premium' |
| `storageAccountSku` | string | 'Standard_LRS' | Storage account redundancy | 'Standard_LRS', 'Standard_GRS', etc. |
| `functionsVersion` | string | '~4' | Azure Functions runtime version | '~4', '~3' |
| `nodeVersion` | string | '18' | Node.js runtime version | '18', '16', '14' |
| `tags` | object | See template | Resource tags | Any valid tags object |

## Post-Deployment Configuration

After successful deployment, you'll need to deploy the function code:

### 1. Get Deployment Outputs

```bash
# Get the Function App name and URL
FUNCTION_APP_NAME=$(az deployment group show \
  --resource-group rg-poll-system \
  --name main \
  --query 'properties.outputs.functionAppName.value' \
  --output tsv)

FUNCTION_APP_URL=$(az deployment group show \
  --resource-group rg-poll-system \
  --name main \
  --query 'properties.outputs.functionAppUrl.value' \
  --output tsv)

echo "Function App: $FUNCTION_APP_NAME"
echo "Function App URL: $FUNCTION_APP_URL"
```

### 2. Deploy Function Code

You'll need to deploy the actual function code using one of these methods:

#### Option A: Using Azure Functions Core Tools
```bash
# Install Azure Functions Core Tools
npm install -g azure-functions-core-tools@4

# Create local function project
func init poll-functions --javascript
cd poll-functions

# Add the function implementations from the recipe
# Then deploy
func azure functionapp publish $FUNCTION_APP_NAME
```

#### Option B: Using ZIP Deployment
```bash
# Create a ZIP package with your function code
# Upload using Azure CLI
az functionapp deployment source config-zip \
  --resource-group rg-poll-system \
  --name $FUNCTION_APP_NAME \
  --src functions.zip
```

### 3. Test the Deployment

```bash
# Test vote submission
curl -X POST "$FUNCTION_APP_URL/api/SubmitVote" \
  -H "Content-Type: application/json" \
  -d '{
    "pollId": "team-lunch",
    "option": "Pizza",
    "voterId": "alice@company.com"
  }'

# Test results retrieval (after a few seconds)
curl "$FUNCTION_APP_URL/api/results/team-lunch"
```

## Monitoring and Troubleshooting

### Application Insights

The template automatically configures Application Insights for monitoring:

1. **Access Application Insights**:
   ```bash
   AI_NAME=$(az deployment group show \
     --resource-group rg-poll-system \
     --name main \
     --query 'properties.outputs.applicationInsightsInstrumentationKey.value' \
     --output tsv)
   
   echo "Application Insights Key: $AI_NAME"
   ```

2. **View logs in Azure Portal**:
   - Navigate to Application Insights in the Azure Portal
   - Use the "Logs" section to query function execution logs

### Function App Logs

```bash
# Stream live logs
az webapp log tail \
  --resource-group rg-poll-system \
  --name $FUNCTION_APP_NAME
```

### Service Bus Monitoring

```bash
# Check queue status
az servicebus queue show \
  --resource-group rg-poll-system \
  --namespace-name $SERVICE_BUS_NAMESPACE \
  --name votes \
  --query '{ActiveMessageCount:activeMessageCount, DeadLetterMessageCount:deadLetterMessageCount}'
```

## Security Considerations

The template implements several security best practices:

1. **Managed Identity**: Function App uses system-assigned managed identity
2. **RBAC**: Least-privilege role assignments for Service Bus and Storage access
3. **HTTPS Only**: All communication is encrypted in transit
4. **Storage Security**: Blob public access is disabled
5. **TLS Version**: Minimum TLS 1.2 enforced

## Cost Optimization

- **Consumption Plan**: Pay only for actual function executions
- **Basic Service Bus**: Lowest cost tier suitable for development
- **Standard_LRS Storage**: Locally redundant storage for cost savings
- **Right-sizing**: All resources configured for optimal cost/performance balance

Estimated monthly cost for light usage (dev environment): $5-15 USD

## Customization Examples

### Production Environment

```json
{
  "resourcePrefix": { "value": "poll-prod" },
  "environment": { "value": "prod" },
  "serviceBusSku": { "value": "Standard" },
  "storageAccountSku": { "value": "Standard_GRS" }
}
```

### High-Availability Configuration

```json
{
  "serviceBusSku": { "value": "Premium" },
  "storageAccountSku": { "value": "Standard_RAGRS" }
}
```

## Cleanup

To remove all deployed resources:

```bash
# Delete the entire resource group
az group delete \
  --name rg-poll-system \
  --yes \
  --no-wait
```

## Troubleshooting

### Common Issues

1. **Deployment Fails with Permission Errors**:
   - Ensure you have Contributor role on the resource group
   - Verify you can create role assignments

2. **Function App Not Starting**:
   - Check Application Insights for error logs
   - Verify all app settings are correctly configured

3. **Service Bus Connection Issues**:
   - Verify the managed identity has proper RBAC assignments
   - Check Service Bus connection string in app settings

4. **Storage Access Denied**:
   - Ensure the Function App managed identity has Storage Blob Data Contributor role
   - Verify the storage account allows the Function App's IP range

### Getting Help

- **Azure Documentation**: [Azure Functions](https://docs.microsoft.com/azure/azure-functions/)
- **Service Bus Documentation**: [Azure Service Bus](https://docs.microsoft.com/azure/service-bus-messaging/)
- **Bicep Documentation**: [Azure Bicep](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)

## Version History

- **1.0**: Initial template with basic polling functionality
- **1.1**: Added Application Insights and improved security configurations
- **1.2**: Enhanced parameter validation and documentation