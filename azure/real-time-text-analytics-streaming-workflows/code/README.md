# Infrastructure as Code for Real-Time Text Analytics Streaming Workflows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Text Analytics Streaming Workflows".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login`)
- Appropriate Azure subscription with sufficient permissions
- Resource provider registrations for:
  - Microsoft.CognitiveServices
  - Microsoft.EventHub
  - Microsoft.Storage
  - Microsoft.Logic
  - Microsoft.Web
- Estimated cost: $15-25 per day for testing (delete resources after completion)

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to bicep directory
cd bicep/

# Create resource group
az group create --name rg-content-processing-demo --location eastus

# Deploy infrastructure
az deployment group create \
    --resource-group rg-content-processing-demo \
    --template-file main.bicep \
    --parameters @parameters.json

# Get deployment outputs
az deployment group show \
    --resource-group rg-content-processing-demo \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
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

# View created resources
az resource list --resource-group rg-content-processing-demo --output table
```

## Architecture Overview

This IaC deploys a comprehensive content processing pipeline including:

- **Azure Cognitive Services Language** - Text analytics, sentiment analysis, and language detection
- **Azure Event Hubs** - Scalable event ingestion with 4 partitions
- **Azure Logic Apps** - Serverless workflow orchestration
- **Azure Storage Account** - Results storage with organized containers
- **API Connections** - Managed connections between services

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "uniqueSuffix": {
      "value": "demo123"
    },
    "cognitiveServicesSku": {
      "value": "S"
    },
    "eventHubSku": {
      "value": "Standard"
    },
    "storageAccountSku": {
      "value": "Standard_LRS"
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
location = "East US"
unique_suffix = "demo123"
cognitive_services_sku = "S"
event_hub_sku = "Standard"
storage_account_sku = "Standard_LRS"
```

### Environment Variables for Scripts

Set these variables before running bash scripts:

```bash
export LOCATION="eastus"
export UNIQUE_SUFFIX="demo123"
export COGNITIVE_SERVICES_SKU="S"
export EVENT_HUB_SKU="Standard"
export STORAGE_ACCOUNT_SKU="Standard_LRS"
```

## Testing the Deployment

### 1. Verify Event Hub Connectivity

```bash
# Check Event Hub status
az eventhubs eventhub show \
    --name content-stream \
    --namespace-name eh-content-proc-${UNIQUE_SUFFIX} \
    --resource-group rg-content-processing-demo \
    --output table
```

### 2. Test Cognitive Services

```bash
# Get Cognitive Services endpoint and key
COGNITIVE_ENDPOINT=$(az cognitiveservices account show \
    --name cs-text-analytics-${UNIQUE_SUFFIX} \
    --resource-group rg-content-processing-demo \
    --query properties.endpoint --output tsv)

COGNITIVE_KEY=$(az cognitiveservices account keys list \
    --name cs-text-analytics-${UNIQUE_SUFFIX} \
    --resource-group rg-content-processing-demo \
    --query key1 --output tsv)

# Test sentiment analysis
curl -X POST "${COGNITIVE_ENDPOINT}/text/analytics/v3.1/sentiment" \
    -H "Ocp-Apim-Subscription-Key: ${COGNITIVE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"documents":[{"id":"1","text":"I love this service!"}]}'
```

### 3. Send Test Events

```bash
# Install Azure Event Hubs library
pip3 install azure-eventhub

# Send test content (requires EVENT_HUB_CONNECTION string from outputs)
python3 -c "
import json
from azure.eventhub import EventHubProducerClient, EventData
import os

connection_str = os.environ['EVENT_HUB_CONNECTION']
producer = EventHubProducerClient.from_connection_string(connection_str, 'content-stream')

test_message = {
    'content': 'This is a great product with excellent features!',
    'source': 'test-source',
    'timestamp': '2025-07-12T10:00:00Z'
}

with producer:
    producer.send_event(EventData(json.dumps(test_message)))
    print('Test message sent successfully')
"
```

### 4. Verify Logic App Processing

```bash
# Check Logic App runs
az logic workflow list-runs \
    --name la-content-workflow-${UNIQUE_SUFFIX} \
    --resource-group rg-content-processing-demo \
    --output table

# Check processed results in storage
az storage blob list \
    --container-name processed-insights \
    --account-name stcontentproc${UNIQUE_SUFFIX} \
    --output table
```

## Monitoring and Troubleshooting

### View Logic App Run History

```bash
# Get detailed run information
az logic workflow show-run \
    --name la-content-workflow-${UNIQUE_SUFFIX} \
    --resource-group rg-content-processing-demo \
    --run-name <run-id>
```

### Check Event Hub Metrics

```bash
# View Event Hub metrics
az monitor metrics list \
    --resource /subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-content-processing-demo/providers/Microsoft.EventHub/namespaces/eh-content-proc-${UNIQUE_SUFFIX}/eventhubs/content-stream \
    --metric IncomingMessages \
    --interval PT1H
```

### Storage Account Diagnostics

```bash
# Enable storage logging
az storage logging update \
    --services b \
    --log rwd \
    --retention 7 \
    --account-name stcontentproc${UNIQUE_SUFFIX}
```

## Cost Optimization

### Resource Scaling

- **Event Hubs**: Adjust throughput units based on message volume
- **Cognitive Services**: Monitor usage and consider batch processing
- **Storage**: Use lifecycle policies for automatic archiving
- **Logic Apps**: Optimize workflow frequency and actions

### Monitoring Costs

```bash
# Set up budget alerts
az consumption budget create \
    --resource-group rg-content-processing-demo \
    --budget-name content-processing-budget \
    --amount 50 \
    --time-grain Monthly \
    --start-date 2025-07-01 \
    --end-date 2025-12-31
```

## Security Considerations

### Key Management

- Cognitive Services keys are stored in Azure Key Vault (if using advanced template)
- Storage account keys are rotated regularly
- Event Hub connection strings use SAS tokens with minimal permissions

### Network Security

- Consider implementing VNet integration for production deployments
- Use Private Endpoints for enhanced security
- Enable Azure Firewall rules for restricted access

### Identity and Access

- Logic Apps use Managed Identity for service authentication
- RBAC policies follow least privilege principle
- Audit logs enabled for all services

## Cleanup

### Using Bicep

```bash
# Delete resource group (removes all resources)
az group delete \
    --name rg-content-processing-demo \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Clean up state files
rm -f terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az resource list \
    --resource-group rg-content-processing-demo \
    --output table
```

## Advanced Configuration

### Custom Workflow Logic

The Logic Apps workflow can be customized by:

1. Modifying the workflow definition JSON
2. Adding custom actions and conditions
3. Integrating with additional Azure services
4. Implementing custom connectors

### Scaling Considerations

- **Event Hubs**: Use auto-inflate for dynamic throughput scaling
- **Cognitive Services**: Implement request throttling and retry logic
- **Storage**: Consider Premium storage for high-throughput scenarios
- **Logic Apps**: Use parallel processing for batch operations

### Integration Options

- **Power BI**: Connect processed data for real-time dashboards
- **Azure Monitor**: Set up custom alerts and dashboards
- **Azure Synapse**: Integrate for advanced analytics
- **Microsoft Teams**: Add notifications for critical events

## Troubleshooting Common Issues

### Event Hub Connection Issues

```bash
# Test Event Hub connectivity
az eventhubs eventhub authorization-rule keys list \
    --resource-group rg-content-processing-demo \
    --namespace-name eh-content-proc-${UNIQUE_SUFFIX} \
    --eventhub-name content-stream \
    --name SendPolicy
```

### Cognitive Services API Errors

```bash
# Check service availability
az cognitiveservices account list-usage \
    --name cs-text-analytics-${UNIQUE_SUFFIX} \
    --resource-group rg-content-processing-demo
```

### Logic Apps Workflow Failures

```bash
# Get failed run details
az logic workflow show-run \
    --name la-content-workflow-${UNIQUE_SUFFIX} \
    --resource-group rg-content-processing-demo \
    --run-name <failed-run-id> \
    --query 'properties.error'
```

## Support and Documentation

- [Azure Cognitive Services Language Documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/language-service/)
- [Azure Event Hubs Documentation](https://docs.microsoft.com/en-us/azure/event-hubs/)
- [Azure Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [Azure Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/)

For issues with this infrastructure code, refer to the original recipe documentation or Azure support channels.

## Contributing

To contribute improvements to this IaC:

1. Test changes thoroughly in a development environment
2. Ensure all resource dependencies are properly configured
3. Update documentation to reflect changes
4. Validate security best practices are maintained
5. Test both deployment and cleanup procedures