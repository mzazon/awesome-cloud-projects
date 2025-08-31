# Azure Bicep Template - Simple SMS Notifications

This Bicep template deploys the complete infrastructure for the "Simple SMS Notifications with Communication Services and Functions" recipe.

## Architecture Overview

The template creates:
- Azure Communication Services resource for SMS capabilities
- Azure Function App (Linux Consumption Plan) for serverless SMS processing
- Storage Account for Function App requirements
- Application Insights and Log Analytics Workspace for monitoring
- Proper security configurations and managed identity

## Prerequisites

- Azure CLI installed and authenticated
- Bicep CLI installed (`az bicep install`)
- Resource group created or permissions to create one
- Subscription with Communication Services and Functions permissions

## Quick Deployment

### 1. Deploy with Default Parameters

```bash
# Create resource group
az group create --name rg-sms-notifications --location eastus

# Deploy Bicep template
az deployment group create \
  --resource-group rg-sms-notifications \
  --template-file main.bicep
```

### 2. Deploy with Custom Parameters

```bash
# Deploy with parameters file
az deployment group create \
  --resource-group rg-sms-notifications \
  --template-file main.bicep \
  --parameters @parameters.json
```

### 3. Deploy with Inline Parameters

```bash
# Deploy with specific parameters
az deployment group create \
  --resource-group rg-sms-notifications \
  --template-file main.bicep \
  --parameters environment=prod \
               uniqueSuffix=mycompany \
               enableApplicationInsights=true
```

## Template Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `environment` | string | `dev` | Environment name (dev, test, prod) |
| `location` | string | Resource Group location | Azure region for resources |
| `uniqueSuffix` | string | Auto-generated | Unique suffix for resource names |
| `dataLocation` | string | `United States` | Data residency for Communication Services |
| `functionRuntime` | string | `node` | Function App runtime (node, dotnet, python) |
| `functionRuntimeVersion` | string | `~20` | Runtime version |
| `enableApplicationInsights` | bool | `true` | Enable monitoring and logging |
| `storageAccountSku` | string | `Standard_LRS` | Storage account performance tier |
| `tags` | object | Default tags | Resource tags for organization |

## Post-Deployment Steps

After successful deployment, complete these steps:

### 1. Purchase Phone Number

```bash
# List available phone numbers
az communication phonenumber list-available \
  --resource-group rg-sms-notifications \
  --communication-service [COMMUNICATION_SERVICE_NAME] \
  --phone-number-type "tollFree" \
  --assignment-type "application" \
  --capabilities "sms" \
  --area-code "800"

# Purchase phone number
az communication phonenumber purchase \
  --resource-group rg-sms-notifications \
  --communication-service [COMMUNICATION_SERVICE_NAME] \
  --phone-number-type "tollFree" \
  --assignment-type "application" \
  --capabilities "sms" \
  --area-code "800" \
  --quantity 1
```

### 2. Update Function App Settings

```bash
# Update SMS_FROM_PHONE setting with purchased number
az functionapp config appsettings set \
  --name [FUNCTION_APP_NAME] \
  --resource-group rg-sms-notifications \
  --settings "SMS_FROM_PHONE=+18001234567"
```

### 3. Deploy Function Code

Create the function code structure:

```bash
# Create function project
mkdir sms-function && cd sms-function
func init --javascript --model V4

# Create package.json
cat > package.json << 'EOF'
{
  "name": "sms-notification-function",
  "version": "1.0.0",
  "main": "src/index.js",
  "dependencies": {
    "@azure/communication-sms": "^1.1.0",
    "@azure/functions": "^4.0.0"
  }
}
EOF

# Create function code (see recipe for complete implementation)
mkdir -p src
# Add your function code to src/index.js

# Deploy to Azure
npm install
func azure functionapp publish [FUNCTION_APP_NAME]
```

## Template Outputs

The template provides these outputs for integration:

- `communicationServiceName`: Name of the Communication Services resource
- `functionAppName`: Name of the Function App
- `functionAppUrl`: HTTPS URL of the Function App
- `storageAccountName`: Name of the storage account
- `applicationInsightsInstrumentationKey`: Monitoring key (if enabled)
- `nextSteps`: Guidance for completing the setup

## Security Features

The template implements security best practices:

- **HTTPS Enforcement**: All traffic uses HTTPS
- **Managed Identity**: System-assigned identity for secure resource access
- **Storage Security**: Secure key access and HTTPS-only traffic
- **TLS 1.2**: Minimum TLS version enforced
- **Function Authentication**: Function keys required for API access
- **Network Security**: Storage account network ACLs configured

## Monitoring and Logging

When Application Insights is enabled:

- Function execution monitoring
- SMS delivery tracking
- Error and performance analytics
- Custom metrics and alerts

Access monitoring through:
```bash
# View function logs
az functionapp logs tail --name [FUNCTION_APP_NAME] --resource-group rg-sms-notifications

# Application Insights queries in Azure portal
```

## Cost Optimization

This template uses cost-effective configurations:

- **Consumption Plan**: Pay-per-execution for Functions
- **Standard_LRS Storage**: Locally redundant storage
- **30-day Log Retention**: Balanced monitoring and cost
- **Auto-scaling**: Resources scale to zero when not in use

Estimated monthly costs:
- Function App: $0 (pay-per-use)
- Storage Account: $1-2
- Phone Number: $2 (toll-free)
- SMS Messages: $0.0075-0.01 per message
- Application Insights: Based on data ingestion

## Customization Examples

### Production Configuration

```json
{
  "environment": { "value": "prod" },
  "storageAccountSku": { "value": "Standard_GRS" },
  "enableApplicationInsights": { "value": true },
  "tags": {
    "value": {
      "environment": "production",
      "project": "customer-notifications",
      "cost-center": "marketing"
    }
  }
}
```

### Multi-Region Deployment

Deploy to multiple regions for redundancy:

```bash
# Deploy to primary region
az deployment group create \
  --resource-group rg-sms-notifications-east \
  --template-file main.bicep \
  --parameters environment=prod uniqueSuffix=east

# Deploy to secondary region
az deployment group create \
  --resource-group rg-sms-notifications-west \
  --template-file main.bicep \
  --parameters environment=prod uniqueSuffix=west
```

## Troubleshooting

### Common Issues

1. **Deployment Fails - Resource Names**
   - Ensure uniqueSuffix creates globally unique names
   - Storage account names must be 3-24 characters, lowercase

2. **SMS Not Sending**
   - Verify toll-free number verification is complete
   - Check SMS_FROM_PHONE app setting format (+1234567890)
   - Confirm Communication Services connection string

3. **Function Not Starting**
   - Verify all app settings are configured
   - Check storage account connection
   - Review function app logs

### Validation Commands

```bash
# Check deployment status
az deployment group show \
  --resource-group rg-sms-notifications \
  --name main

# Test function app
curl -X POST "https://[FUNCTION_APP_NAME].azurewebsites.net/api/sendSMS?code=[FUNCTION_KEY]" \
  -H "Content-Type: application/json" \
  -d '{"to": "+1234567890", "message": "Test message"}'

# Check Communication Services status
az communication show \
  --name [COMMUNICATION_SERVICE_NAME] \
  --resource-group rg-sms-notifications
```

## Cleanup

Remove all resources:

```bash
# Delete resource group and all resources
az group delete --name rg-sms-notifications --yes --no-wait
```

## Support

- [Azure Communication Services Documentation](https://docs.microsoft.com/en-us/azure/communication-services/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)

## License

This template is provided as-is under the MIT license. See the original recipe documentation for usage guidelines.