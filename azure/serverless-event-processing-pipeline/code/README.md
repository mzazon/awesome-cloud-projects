# Infrastructure as Code for Serverless Event Processing Pipeline with Auto-Scaling

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Serverless Event Processing Pipeline with Auto-Scaling".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Node.js 18+ (for Function App runtime)
- Appropriate Azure subscription with permissions to create:
  - Event Hubs namespaces
  - Function Apps
  - Storage accounts
  - Application Insights
  - Resource groups

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-recipe-demo" \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json
```

### Using Terraform

```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### Using Bash Scripts

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

This solution creates a serverless real-time data processing pipeline with the following components:

- **Event Hubs Namespace**: Scalable event ingestion service
- **Event Hub**: Configured with 4 partitions and 1-day retention
- **Function App**: Serverless compute with Event Hubs trigger
- **Storage Account**: Backend storage for Function App and checkpointing
- **Application Insights**: Monitoring and telemetry collection

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "East US"
    },
    "resourcePrefix": {
      "value": "recipe"
    },
    "eventHubPartitionCount": {
      "value": 4
    },
    "eventHubRetentionDays": {
      "value": 1
    },
    "functionAppRuntime": {
      "value": "node"
    },
    "functionAppRuntimeVersion": {
      "value": "18"
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
location = "East US"
resource_prefix = "recipe"
eventhub_partition_count = 4
eventhub_retention_days = 1
function_app_runtime = "node"
function_app_runtime_version = "18"
```

### Bash Script Environment Variables

Set these variables before running the bash scripts:

```bash
export LOCATION="eastus"
export RESOURCE_PREFIX="recipe"
export EVENTHUB_PARTITION_COUNT=4
export EVENTHUB_RETENTION_DAYS=1
export FUNCTION_APP_RUNTIME="node"
export FUNCTION_APP_RUNTIME_VERSION="18"
```

## Deployment Details

### Resource Naming Convention

All resources follow Azure naming conventions with a consistent prefix:

- Resource Group: `rg-{prefix}-{random-suffix}`
- Event Hubs Namespace: `eh-ns-{random-suffix}`
- Event Hub: `events-hub`
- Function App: `func-processor-{random-suffix}`
- Storage Account: `st{random-suffix}`
- Application Insights: `ai-processor-{random-suffix}`

### Security Configuration

The infrastructure implements the following security measures:

- Storage account with locally redundant storage (LRS)
- Application Insights with web application type
- Event Hubs with Basic tier for cost optimization
- Function App with managed identity capabilities
- Proper connection string management through app settings

### Cost Optimization

The solution is optimized for cost with:

- Event Hubs Basic tier (~$11/month)
- Function App consumption plan (pay-per-execution)
- Storage account with hot tier for frequently accessed data
- Application Insights with default pricing tier

## Post-Deployment Steps

After successful deployment, complete these steps:

1. **Deploy Function Code**:
   ```bash
   # Initialize function project
   func init event-processor --worker-runtime node --language javascript
   cd event-processor
   
   # Create Event Hub triggered function
   func new --name ProcessEvents --template "EventHubTrigger"
   
   # Deploy to Azure
   func azure functionapp publish {function-app-name}
   ```

2. **Test Event Processing**:
   ```bash
   # Send test events using the provided Node.js script
   node send-events.js
   ```

3. **Monitor Function Execution**:
   ```bash
   # View function logs
   az functionapp logs tail --name {function-app-name} --resource-group {resource-group}
   ```

## Validation and Testing

### Verify Deployment

1. **Check Resource Group**:
   ```bash
   az group list --query "[?name=='rg-recipe-{suffix}']" --output table
   ```

2. **Verify Event Hub**:
   ```bash
   az eventhubs eventhub show \
       --resource-group {resource-group} \
       --namespace-name {namespace-name} \
       --name events-hub
   ```

3. **Check Function App Status**:
   ```bash
   az functionapp show \
       --name {function-app-name} \
       --resource-group {resource-group} \
       --query "{name:name,state:state}" \
       --output table
   ```

### Performance Testing

1. **Send Test Events**:
   ```bash
   # Use the provided event producer script
   EVENTHUB_CONNECTION_STRING="{connection-string}" node send-events.js
   ```

2. **Monitor Metrics**:
   ```bash
   # Check Event Hub metrics
   az monitor metrics list \
       --resource "{event-hub-resource-id}" \
       --metric "IncomingMessages" \
       --interval PT1M
   ```

3. **Application Insights Query**:
   ```bash
   # Query function telemetry
   az monitor app-insights query \
       --app {app-insights-name} \
       --resource-group {resource-group} \
       --analytics-query "requests | limit 10"
   ```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name "rg-recipe-demo" --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Function App Not Starting**:
   - Verify storage account connection string
   - Check Application Insights configuration
   - Ensure proper runtime version

2. **Event Hub Connection Errors**:
   - Validate connection string format
   - Check Event Hub namespace status
   - Verify network connectivity

3. **Function Execution Failures**:
   - Review function logs in Application Insights
   - Check Event Hub trigger configuration
   - Validate function code syntax

### Debug Commands

```bash
# Check deployment status
az deployment group list --resource-group {resource-group}

# View Activity Log
az monitor activity-log list --resource-group {resource-group} --max-events 10

# Function App diagnostics
az functionapp show --name {function-app-name} --resource-group {resource-group}
```

## Extension Ideas

After successful deployment, consider these enhancements:

1. **Dead Letter Queue**: Add error handling with Service Bus dead letter queue
2. **Data Enrichment**: Integrate with Cosmos DB for reference data lookups
3. **Real-time Dashboards**: Connect to Power BI for live data visualization
4. **Multi-region Deployment**: Implement geo-disaster recovery
5. **Event Replay**: Add capability to replay events from Data Lake

## Support and Documentation

- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Event Hubs Documentation](https://docs.microsoft.com/en-us/azure/event-hubs/)
- [Application Insights Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Estimated Costs

- **Event Hubs Basic**: ~$11/month
- **Function App Consumption**: Pay-per-execution (first 1M executions free)
- **Storage Account**: ~$0.05/GB/month
- **Application Insights**: Based on data ingestion volume

> **Note**: Costs may vary based on usage patterns and selected regions. Use the Azure Pricing Calculator for accurate estimates.

---

*This infrastructure code was generated for the recipe "Serverless Event Processing Pipeline with Auto-Scaling" | Recipe ID: a4e7b2c8*