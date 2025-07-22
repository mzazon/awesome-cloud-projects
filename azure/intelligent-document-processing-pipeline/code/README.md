# Infrastructure as Code for Intelligent Document Processing with AI Extraction

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Document Processing with AI Extraction".

## Solution Overview

This solution implements a serverless, event-driven architecture that processes documents in real-time using Azure Event Hubs for high-throughput message ingestion, Azure AI Document Intelligence for intelligent text extraction, and Azure Cosmos DB for MongoDB API for flexible, scalable document storage. Azure Functions orchestrate the processing pipeline, automatically scaling based on demand while maintaining exactly-once processing semantics.

## Architecture Components

- **Azure Event Hubs**: Distributed streaming platform for document event ingestion
- **Azure Functions**: Serverless compute for document processing orchestration
- **Azure Cosmos DB for MongoDB**: Globally distributed NoSQL database for processed documents
- **Azure AI Document Intelligence**: AI-powered document analysis and text extraction
- **Azure Blob Storage**: Storage for Function App requirements
- **Application Insights**: Monitoring and diagnostics for the serverless application

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.60.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Resource Groups
  - Event Hubs (Standard tier)
  - Azure Functions (Consumption plan)
  - Cosmos DB (MongoDB API)
  - Cognitive Services (AI Document Intelligence)
  - Storage Accounts
  - Application Insights
- Node.js 18+ for Function App runtime
- Basic understanding of event-driven architectures
- Estimated cost: $50-100 per month for moderate usage

> **Note**: This solution uses Azure AI Document Intelligence which requires specific Azure regions. Ensure your chosen region supports all required services.

## Quick Start

### Using Bicep
```bash
# Login to Azure
az login

# Set subscription (if needed)
az account set --subscription "your-subscription-id"

# Deploy infrastructure
az deployment group create \
    --resource-group rg-docprocessing \
    --template-file bicep/main.bicep \
    --parameters location=eastus

# Deploy Function App code
cd scripts/
chmod +x deploy-functions.sh
./deploy-functions.sh
```

### Using Terraform
```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply

# Deploy Function App code
cd ../scripts/
chmod +x deploy-functions.sh
./deploy-functions.sh
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy complete solution
./scripts/deploy.sh

# Verify deployment
./scripts/verify-deployment.sh
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for resources | `eastus` | Yes |
| `resourcePrefix` | Prefix for all resource names | `docprocessing` | No |
| `eventHubSku` | Event Hub namespace SKU | `Standard` | No |
| `eventHubCapacity` | Event Hub capacity units | `1` | No |
| `cosmosDbThroughput` | Cosmos DB throughput (RU/s) | `400` | No |
| `functionAppRuntime` | Function App runtime | `node` | No |
| `aiDocumentSku` | AI Document Intelligence SKU | `S0` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for resources | `eastus` | Yes |
| `resource_prefix` | Prefix for all resource names | `docprocessing` | No |
| `environment` | Environment tag | `demo` | No |
| `event_hub_sku` | Event Hub namespace SKU | `Standard` | No |
| `event_hub_capacity` | Event Hub capacity units | `1` | No |
| `cosmos_throughput` | Cosmos DB throughput (RU/s) | `400` | No |
| `function_runtime` | Function App runtime version | `18` | No |

### Environment Variables

The following environment variables are automatically configured for the Function App:

- `EventHubConnection`: Connection string for Event Hubs
- `CosmosDBConnection`: Connection string for Cosmos DB
- `AIDocumentKey`: API key for AI Document Intelligence
- `AIDocumentEndpoint`: Endpoint URL for AI Document Intelligence
- `APPINSIGHTS_INSTRUMENTATIONKEY`: Application Insights instrumentation key

## Deployment Details

### Resource Creation Order

1. **Resource Group**: Container for all resources
2. **Storage Account**: Required for Function App
3. **Event Hubs Namespace**: Messaging infrastructure
4. **Event Hub**: Document event stream
5. **Cosmos DB Account**: Database for processed documents
6. **Cosmos DB Database & Collection**: Document storage structure
7. **AI Document Intelligence**: Document analysis service
8. **Function App**: Serverless compute platform
9. **Application Insights**: Monitoring and diagnostics

### Security Configuration

- **Event Hubs**: Uses Shared Access Signature (SAS) authentication
- **Cosmos DB**: Uses primary key authentication with MongoDB API
- **AI Document Intelligence**: Uses subscription key authentication
- **Storage Account**: Uses system-assigned managed identity where possible
- **Function App**: Configured with least privilege access to dependent services

### Monitoring Setup

- **Application Insights**: Tracks function execution, performance, and errors
- **Function App Logs**: Integrated with Azure Monitor
- **Event Hubs Metrics**: Throughput, errors, and connection monitoring
- **Cosmos DB Metrics**: Request units, storage, and performance monitoring

## Testing the Deployment

### Verify Resource Creation

```bash
# Check resource group
az group show --name rg-docprocessing --query "properties.provisioningState"

# Verify Event Hub
az eventhubs eventhub show \
    --name document-events \
    --namespace-name <namespace-name> \
    --resource-group rg-docprocessing

# Check Cosmos DB
az cosmosdb show \
    --name <cosmos-account-name> \
    --resource-group rg-docprocessing \
    --query "provisioningState"

# Verify Function App
az functionapp show \
    --name <function-app-name> \
    --resource-group rg-docprocessing \
    --query "state"
```

### Send Test Document Event

```bash
# Install Event Hubs SDK
npm install @azure/event-hubs

# Create test message
cat > test-message.json << 'EOF'
{
  "documentId": "test-doc-001",
  "documentUrl": "https://example.com/sample-document.pdf",
  "metadata": {
    "type": "invoice",
    "source": "api",
    "timestamp": "2025-07-12T10:00:00Z"
  }
}
EOF

# Send test event (requires Event Hub connection string)
node -e "
const { EventHubProducerClient } = require('@azure/event-hubs');
const client = new EventHubProducerClient('<connection-string>', 'document-events');
const message = require('./test-message.json');
client.sendBatch([{ body: message }]).then(() => {
  console.log('✅ Test message sent successfully');
  process.exit(0);
}).catch(console.error);
"
```

### Monitor Processing

```bash
# Check Function App logs
az functionapp log show \
    --name <function-app-name> \
    --resource-group rg-docprocessing

# Query processed documents in Cosmos DB
az cosmosdb sql query \
    --account-name <cosmos-account-name> \
    --database-name DocumentProcessingDB \
    --container-name ProcessedDocuments \
    --query-text "SELECT * FROM c WHERE c.documentId = 'test-doc-001'"
```

## Cleanup

### Using Bicep
```bash
# Delete resource group (removes all resources)
az group delete --name rg-docprocessing --yes --no-wait
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

### Manual Cleanup Verification

```bash
# Verify resource group deletion
az group exists --name rg-docprocessing

# Check for any remaining resources
az resource list --resource-group rg-docprocessing --output table
```

## Troubleshooting

### Common Issues

1. **Function App Deployment Failures**:
   - Ensure Storage Account is created successfully
   - Verify Function App runtime version compatibility
   - Check Application Insights instrumentation key configuration

2. **Event Hub Connection Issues**:
   - Validate connection string format
   - Ensure Event Hub namespace and hub exist
   - Check consumer group configuration

3. **Cosmos DB Authentication**:
   - Verify MongoDB API is enabled
   - Check connection string format
   - Ensure database and collection exist

4. **AI Document Intelligence Errors**:
   - Verify service is available in selected region
   - Check API key and endpoint configuration
   - Ensure S0 pricing tier is supported

### Log Analysis

```bash
# Function App logs
az functionapp log show --name <function-app-name> --resource-group rg-docprocessing

# Application Insights queries
az monitor app-insights query \
    --app <app-insights-name> \
    --analytics-query "requests | where timestamp > ago(1h) | summarize count() by resultCode"
```

## Performance Tuning

### Scaling Considerations

- **Event Hubs**: Increase partition count for higher throughput
- **Function App**: Consider Premium plan for predictable performance
- **Cosmos DB**: Adjust throughput based on processing volume
- **AI Document Intelligence**: Monitor rate limits and consider multiple keys

### Cost Optimization

- **Event Hubs**: Use Standard tier for development, Premium for production
- **Function App**: Consumption plan for variable workloads
- **Cosmos DB**: Use serverless for unpredictable workloads
- **Storage**: Implement lifecycle policies for blob storage

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for architectural guidance
2. Review Azure service documentation for specific service issues
3. Validate resource configurations against Azure best practices
4. Monitor Application Insights for runtime issues

## Security Best Practices

- Use Azure Key Vault for sensitive configuration values
- Implement network security groups for resource isolation
- Enable Azure Security Center recommendations
- Regular security updates for Function App runtime
- Monitor and audit resource access with Azure Activity Log

## Additional Resources

- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Event Hubs Documentation](https://docs.microsoft.com/en-us/azure/event-hubs/)
- [Azure Cosmos DB for MongoDB Documentation](https://docs.microsoft.com/en-us/azure/cosmos-db/mongodb/)
- [Azure AI Document Intelligence Documentation](https://docs.microsoft.com/en-us/azure/applied-ai-services/form-recognizer/)
- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)