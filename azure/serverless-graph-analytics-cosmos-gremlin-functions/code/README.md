# Infrastructure as Code for Serverless Graph Analytics with Cosmos DB Gremlin and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Serverless Graph Analytics with Cosmos DB Gremlin and Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.40.0 or later installed and configured
- An active Azure subscription with appropriate permissions
- For Bicep: Azure Bicep CLI installed (comes with Azure CLI v2.20.0+)
- For Terraform: Terraform v1.0+ installed with Azure Provider v3.0+
- For local Function development: Node.js 18.x or later
- Basic understanding of graph databases and Gremlin query language

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters randomSuffix=$(openssl rand -hex 3)
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
```

## Architecture Overview

This infrastructure deploys:

- **Azure Cosmos DB Account** with Gremlin API for graph database operations
- **Azure Functions App** for serverless event processing with three functions:
  - Graph Writer Function for data ingestion
  - Analytics Function for real-time graph queries
  - Alert Function for pattern-based notifications
- **Azure Event Grid Topic** for event-driven architecture
- **Application Insights** for monitoring and telemetry
- **Storage Account** for Function App requirements

## Configuration Parameters

### Bicep Parameters

- `location`: Azure region for resource deployment (default: eastus)
- `randomSuffix`: Unique suffix for resource names
- `cosmosDbThroughput`: Request Units for Cosmos DB (default: 400)
- `functionAppSku`: Function App hosting plan (default: Y1 for Consumption)

### Terraform Variables

- `location`: Azure region for resource deployment
- `resource_group_name`: Name of the resource group
- `cosmos_throughput`: Cosmos DB throughput in RU/s
- `environment`: Environment tag for resources

### Script Configuration

The bash scripts use environment variables for configuration:

```bash
export RESOURCE_GROUP="rg-graph-analytics"
export LOCATION="eastus"
export COSMOS_THROUGHPUT="400"
```

## Deployment Details

### Cosmos DB Configuration

- **API**: Gremlin (Graph) API enabled
- **Consistency Level**: Session (optimal for graph workloads)
- **Partitioning**: Configured with `/partitionKey` path
- **Throughput**: 400 RU/s provisioned (adjustable)
- **Indexing**: Automatic indexing for all properties

### Function App Setup

- **Runtime**: Node.js 18.x
- **Plan**: Consumption (serverless scaling)
- **Functions**: Three pre-configured functions for graph operations
- **Configuration**: Automatic connection to Cosmos DB and Application Insights
- **Triggers**: Event Grid triggers for real-time processing

### Event Grid Configuration

- **Topic**: Custom topic for graph events
- **Subscriptions**: Automatic subscription to Function endpoints
- **Event Types**: Configured for GraphDataEvent processing
- **Retry Policy**: Built-in retry logic for reliable delivery

## Post-Deployment Steps

1. **Deploy Function Code**:
   ```bash
   # Function code deployment is included in the IaC
   # Code package is automatically deployed during infrastructure creation
   ```

2. **Test the Graph System**:
   ```bash
   # Send a test event to verify the pipeline
   curl -X POST <event-grid-endpoint> \
       -H "aeg-sas-key: <event-grid-key>" \
       -H "Content-Type: application/json" \
       -d '{
         "id": "test-event",
         "eventType": "GraphDataEvent",
         "subject": "users/relationships",
         "eventTime": "2025-01-21T10:00:00Z",
         "data": {
           "action": "addVertex",
           "vertex": {
             "id": "user1",
             "label": "person",
             "partitionKey": "user1"
           }
         }
       }'
   ```

3. **Monitor the System**:
   - View Function execution logs in Application Insights
   - Monitor Cosmos DB metrics in Azure Portal
   - Check Event Grid delivery status

## Sample Gremlin Queries

Once deployed, you can query your graph using these examples:

```gremlin
// Count all vertices
g.V().count()

// Get all persons
g.V().hasLabel('person').values('name')

// Find connections
g.V('user1').out().values('name')

// Complex traversal - find friends of friends
g.V('user1').out('knows').out('knows').dedup().values('name')
```

## Cost Estimation

Estimated monthly costs for moderate usage:

- **Cosmos DB**: ~$25-50 (400 RU/s provisioned)
- **Azure Functions**: ~$10-20 (consumption based)
- **Event Grid**: ~$5-10 (per million operations)
- **Application Insights**: ~$5-15 (based on telemetry volume)
- **Storage Account**: ~$1-5 (minimal storage requirements)

**Total**: ~$46-100/month depending on usage patterns

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name <your-resource-group> --yes --no-wait
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

## Customization

### Scaling Considerations

- **Cosmos DB**: Increase RU/s for higher throughput requirements
- **Functions**: Consumption plan auto-scales, consider Premium plan for VNet integration
- **Event Grid**: Supports millions of events per second out of the box

### Security Enhancements

- Enable Cosmos DB firewall and VNet integration
- Configure Function App with managed identity
- Implement Azure Key Vault for sensitive configuration
- Enable Event Grid managed identity authentication

### Monitoring Enhancements

- Configure custom Application Insights dashboards
- Set up Azure Monitor alerts for critical metrics
- Implement custom telemetry in Function code
- Enable Cosmos DB diagnostic logging

## Troubleshooting

### Common Issues

1. **Function deployment failures**: Ensure storage account is accessible
2. **Cosmos DB connection errors**: Verify connection strings and firewall settings
3. **Event Grid delivery failures**: Check Function endpoint configuration
4. **Permission errors**: Verify appropriate Azure RBAC roles

### Debugging Steps

1. Check Application Insights for Function execution logs
2. Verify Event Grid delivery attempts in Azure Portal
3. Test Cosmos DB connectivity using Data Explorer
4. Review Azure Activity Log for deployment issues

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation
2. Check Azure service-specific documentation:
   - [Azure Cosmos DB Gremlin API](https://docs.microsoft.com/en-us/azure/cosmos-db/gremlin/)
   - [Azure Functions](https://docs.microsoft.com/en-us/azure/azure-functions/)
   - [Azure Event Grid](https://docs.microsoft.com/en-us/azure/event-grid/)
3. Review Azure Well-Architected Framework for best practices

## Next Steps

After successful deployment, consider these enhancements:

1. **Add Graph Visualization**: Implement a web dashboard using Azure Static Web Apps
2. **Enhance Analytics**: Add machine learning models for graph pattern recognition
3. **Implement Security**: Add authentication and authorization layers
4. **Scale Operations**: Configure auto-scaling policies and performance monitoring
5. **Add Data Sources**: Integrate with additional event sources like IoT Hub or Service Bus