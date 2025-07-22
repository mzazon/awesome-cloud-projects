# Infrastructure as Code for Event-Driven Infrastructure Deployments with Azure Bicep and Event Grid

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Event-Driven Infrastructure Deployments with Azure Bicep and Event Grid".

## Architecture Overview

This solution creates an event-driven infrastructure deployment system using:

- **Azure Bicep** for declarative infrastructure definitions
- **Azure Event Grid** for event routing and pub-sub messaging
- **Azure Container Instances** for executing deployments (triggered via Azure Functions)
- **Azure Functions** for serverless event processing
- **Azure Container Registry** for storing deployment runner images
- **Azure Key Vault** for secure secrets management
- **Azure Storage Account** for hosting Bicep templates
- **Azure Monitor & Application Insights** for observability

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Active Azure subscription with Owner or Contributor role access
- Appropriate permissions for resource creation including:
  - Resource Group management
  - Event Grid topics and subscriptions
  - Storage Account creation
  - Azure Container Registry access
  - Key Vault management
  - Azure Functions deployment
  - Container Instances provisioning

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension (automatically installed with recent Azure CLI versions)

#### For Terraform
- Terraform v1.0 or later
- Azure CLI for authentication

#### For Bash Scripts
- Azure CLI v2.50.0 or later
- Bash shell environment
- jq for JSON processing
- curl for API calls

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
                 storageAccountName=<unique-storage-name> \
                 eventGridTopicName=<unique-topic-name> \
                 containerRegistryName=<unique-acr-name> \
                 keyVaultName=<unique-kv-name>
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the interactive prompts to configure your deployment
```

## Configuration Options

### Bicep Parameters

- `location`: Azure region for resource deployment (default: eastus)
- `storageAccountName`: Unique name for the storage account hosting Bicep templates
- `eventGridTopicName`: Unique name for the Event Grid topic
- `containerRegistryName`: Unique name for Azure Container Registry
- `keyVaultName`: Unique name for Azure Key Vault
- `functionAppName`: Unique name for Azure Function App
- `resourceTags`: Tags to apply to all resources (optional)

### Terraform Variables

- `resource_group_name`: Name of the resource group to create
- `location`: Azure region for deployment
- `storage_account_name`: Storage account name for Bicep templates
- `event_grid_topic_name`: Event Grid topic name
- `container_registry_name`: Azure Container Registry name
- `key_vault_name`: Key Vault name for secrets
- `function_app_name`: Function App name for event processing
- `tags`: Map of tags to apply to resources

### Environment Variables (Bash Scripts)

Set these environment variables before running the deployment script:

```bash
export AZURE_LOCATION="eastus"
export RESOURCE_GROUP_PREFIX="rg-bicep-eventgrid"
export STORAGE_ACCOUNT_PREFIX="stbicep"
export EVENT_GRID_TOPIC_PREFIX="egt-deployments"
export CONTAINER_REGISTRY_PREFIX="acrbicep"
export KEY_VAULT_PREFIX="kv-bicep"
export FUNCTION_APP_PREFIX="func-bicep"
```

## Post-Deployment Setup

After successful deployment, follow these steps to complete the automation setup:

### 1. Upload Sample Bicep Template

```bash
# Get storage account name from deployment output
STORAGE_ACCOUNT=$(az deployment group show \
  --resource-group "rg-bicep-eventgrid-demo" \
  --name "main" \
  --query properties.outputs.storageAccountName.value -o tsv)

# Create sample Bicep template
cat > storage-account.bicep << 'EOF'
@description('Storage account name')
param storageAccountName string

@description('Location for resources')
param location string = resourceGroup().location

@allowed([
  'Standard_LRS'
  'Standard_GRS'
])
@description('Storage SKU')
param storageSku string = 'Standard_LRS'

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageSku
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
  }
}

output storageAccountId string = storageAccount.id
output primaryEndpoint string = storageAccount.properties.primaryEndpoints.blob
EOF

# Upload template to storage
az storage blob upload \
  --account-name $STORAGE_ACCOUNT \
  --container-name bicep-templates \
  --name "storage-account.bicep" \
  --file "storage-account.bicep" \
  --auth-mode login
```

### 2. Build and Push Container Image

```bash
# Get container registry name
ACR_NAME=$(az deployment group show \
  --resource-group "rg-bicep-eventgrid-demo" \
  --name "main" \
  --query properties.outputs.containerRegistryName.value -o tsv)

# Create Dockerfile for deployment runner
cat > Dockerfile << 'EOF'
FROM mcr.microsoft.com/azure-cli:latest

# Install additional tools
RUN apk add --no-cache \
    curl \
    jq \
    bash

# Create working directory
WORKDIR /deployment

# Copy deployment script
COPY deploy.sh /deployment/
RUN chmod +x /deployment/deploy.sh

ENTRYPOINT ["/deployment/deploy.sh"]
EOF

# Create deployment script
cat > deploy.sh << 'EOF'
#!/bin/bash
set -e

echo "Starting deployment process..."

# Parse event data
EVENT_DATA=$1
TEMPLATE_NAME=$(echo $EVENT_DATA | jq -r '.templateName')
PARAMETERS=$(echo $EVENT_DATA | jq -r '.parameters')
TARGET_RG=$(echo $EVENT_DATA | jq -r '.targetResourceGroup')

# Download Bicep template
az storage blob download \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY \
  --container-name bicep-templates \
  --name "${TEMPLATE_NAME}.bicep" \
  --file "/tmp/${TEMPLATE_NAME}.bicep"

# Deploy Bicep template
az deployment group create \
  --resource-group $TARGET_RG \
  --template-file "/tmp/${TEMPLATE_NAME}.bicep" \
  --parameters "$PARAMETERS"

echo "Deployment completed successfully"
EOF

# Build and push container image
az acr build \
  --registry $ACR_NAME \
  --image deployment-runner:v1 \
  --file Dockerfile .
```

### 3. Deploy Function App Code

Create a simple Azure Function to handle Event Grid events:

```csharp
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Azure.Messaging.EventGrid;
using Azure.Messaging.EventGrid.SystemEvents;

namespace EventGridProcessor
{
    public class DeploymentHandler
    {
        private readonly ILogger _logger;

        public DeploymentHandler(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<DeploymentHandler>();
        }

        [Function("DeploymentHandler")]
        public async Task Run([EventGridTrigger] EventGridEvent eventGridEvent)
        {
            _logger.LogInformation($"Event type: {eventGridEvent.EventType}, subject: {eventGridEvent.Subject}");
            
            // Process deployment event
            var eventData = eventGridEvent.Data?.ToString();
            _logger.LogInformation($"Event data: {eventData}");
            
            // Here you would trigger the container instance deployment
            // Implementation details depend on your specific requirements
        }
    }
}
```

## Testing the Solution

### 1. Publish Test Event

```bash
# Get Event Grid endpoint and key
EVENT_GRID_ENDPOINT=$(az deployment group show \
  --resource-group "rg-bicep-eventgrid-demo" \
  --name "main" \
  --query properties.outputs.eventGridTopicEndpoint.value -o tsv)

# Get Event Grid key from Key Vault
KEY_VAULT_NAME=$(az deployment group show \
  --resource-group "rg-bicep-eventgrid-demo" \
  --name "main" \
  --query properties.outputs.keyVaultName.value -o tsv)

EVENT_GRID_KEY=$(az keyvault secret show \
  --vault-name $KEY_VAULT_NAME \
  --name "EventGridKey" \
  --query value -o tsv)

# Create test event
EVENT_DATA='[{
  "id": "test-001",
  "eventType": "Microsoft.EventGrid.CustomEvent",
  "subject": "/deployments/test",
  "eventTime": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'",
  "data": {
    "templateName": "storage-account",
    "targetResourceGroup": "rg-bicep-eventgrid-demo",
    "parameters": {
      "storageAccountName": "sttest'$(date +%s)'"
    }
  }
}]'

# Publish test event
curl -X POST $EVENT_GRID_ENDPOINT \
  -H "aeg-sas-key: $EVENT_GRID_KEY" \
  -H "Content-Type: application/json" \
  -d "$EVENT_DATA"
```

### 2. Monitor Deployment

```bash
# Check Application Insights logs
AI_NAME=$(az deployment group show \
  --resource-group "rg-bicep-eventgrid-demo" \
  --name "main" \
  --query properties.outputs.applicationInsightsName.value -o tsv)

# View recent traces
az monitor app-insights events show \
  --app $AI_NAME \
  --type traces \
  --start-time "1 hour ago"
```

## Validation and Testing

### Verify Deployment

```bash
# Check Event Grid topic status
az eventgrid topic show \
    --name <event-grid-topic-name> \
    --resource-group <resource-group-name> \
    --output table

# Verify storage account and container
az storage container list \
    --account-name <storage-account-name> \
    --auth-mode login

# Check Function App status
az functionapp show \
    --name <function-app-name> \
    --resource-group <resource-group-name> \
    --query state
```

### Test Event Flow

```bash
# List Event Grid subscriptions
az eventgrid event-subscription list \
    --source-resource-id <event-grid-topic-resource-id>

# Monitor Function App logs
az webapp log tail \
    --name <function-app-name> \
    --resource-group <resource-group-name>
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name <your-resource-group> \
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

# Follow prompts to confirm resource deletion
```

## Security Considerations

- All storage accounts are configured with HTTPS-only access
- Key Vault uses RBAC authorization for enhanced security
- Container Registry has admin access enabled only for deployment purposes
- Function App uses managed identity for Azure service authentication
- Event Grid topics use access keys stored securely in Key Vault

## Cost Optimization

- Storage accounts use Standard_LRS for cost efficiency
- Container Instances use consumption-based pricing
- Function Apps use consumption plan for automatic scaling
- Event Grid charges per operation with generous free tier

## Troubleshooting

### Common Issues

1. **Resource Name Conflicts**: Ensure all resource names are globally unique
2. **Permission Issues**: Verify your Azure account has sufficient permissions
3. **Quota Limits**: Check Azure subscription limits for Container Instances
4. **Event Delivery Failures**: Verify Event Grid subscription endpoints

### Debugging Steps

```bash
# Check resource group deployment status
az deployment group list \
    --resource-group <resource-group-name> \
    --output table

# View detailed error messages
az deployment group show \
    --resource-group <resource-group-name> \
    --name <deployment-name>

# Monitor Activity Log
az monitor activity-log list \
    --resource-group <resource-group-name> \
    --start-time <timestamp>
```

## Customization

### Adding New Bicep Templates

1. Create your Bicep template following Azure best practices
2. Upload to the storage account's `bicep-templates` container
3. Test deployment by publishing an event with the template name

### Extending Event Processing

Modify the Function App code to:
- Add parameter validation
- Implement approval workflows
- Support additional event sources
- Add deployment notifications

### Monitoring Enhancements

- Configure custom dashboards in Azure Monitor
- Set up alerts for deployment failures
- Implement cost tracking and reporting
- Add performance metrics collection

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure you have sufficient permissions in the Azure subscription
2. **Naming Conflicts**: Resource names must be globally unique (especially storage accounts)
3. **User Object ID**: Must provide valid Azure AD user object ID for Key Vault access
4. **Function App Cold Start**: First event processing may take longer due to cold start

### Diagnostic Commands

```bash
# Check deployment status
az deployment group show \
  --resource-group "rg-bicep-eventgrid-demo" \
  --name "main"

# View Function App logs
az webapp log tail \
  --resource-group "rg-bicep-eventgrid-demo" \
  --name $FUNCTION_APP_NAME

# Check Event Grid subscription status
az eventgrid event-subscription show \
  --source-resource-id $EVENT_GRID_TOPIC_ID \
  --name "deployment-subscription"
```

## Cost Estimation

Estimated monthly costs (East US region):

- **Event Grid Topic**: ~$0.60/million operations
- **Storage Account (LRS)**: ~$0.045/GB/month
- **Function App (Consumption)**: ~$0.20/million executions
- **Container Registry (Basic)**: ~$5/month
- **Key Vault**: ~$0.03/10,000 operations
- **Application Insights**: ~$2.88/GB ingested
- **Log Analytics**: ~$2.76/GB ingested

Total estimated cost: **$10-20/month** for moderate usage

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for architecture details
2. Check Azure service documentation for specific service configurations
3. Consult Azure Bicep documentation for template syntax
4. Review Terraform Azure provider documentation for resource configurations

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment first
2. Update parameter files for different environments
3. Document any new requirements or dependencies
4. Follow Azure naming conventions and best practices
5. Ensure all secrets are properly secured in Key Vault