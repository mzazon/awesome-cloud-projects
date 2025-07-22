# Infrastructure as Code for Fleet Tracking with Geospatial Analytics

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Fleet Tracking with Geospatial Analytics".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.50.0 or later)
- Azure subscription with Owner or Contributor access
- Basic understanding of streaming analytics and geospatial concepts
- Familiarity with JSON data formats and REST APIs
- Estimated cost: ~$150/month for moderate workload (1000 vehicles, 1 update/minute)

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-geospatial-analytics \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This solution deploys a real-time geospatial analytics platform that includes:

- **Azure Event Hubs**: Ingests location data from GPS-enabled vehicles
- **Azure Stream Analytics**: Processes streaming data with geospatial functions
- **Azure Cosmos DB**: Stores processed events with global distribution
- **Azure Maps**: Provides mapping and visualization services
- **Azure Blob Storage**: Archives historical data for compliance
- **Azure Monitor**: Provides observability and alerting

## Key Features

- **Real-time Processing**: Sub-second latency for geospatial events
- **Geofence Monitoring**: Automatic detection of zone violations
- **Scalable Architecture**: Handles millions of location updates
- **Cost Optimization**: Consumption-based pricing model
- **Global Distribution**: Low-latency access worldwide

## Configuration

### Bicep Parameters

The `parameters.json` file contains customizable values:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "resourcePrefix": {
      "value": "fleet"
    },
    "eventhubPartitionCount": {
      "value": 4
    },
    "cosmosDbThroughput": {
      "value": 400
    }
  }
}
```

### Terraform Variables

Customize the deployment by modifying `terraform/variables.tf` or creating a `terraform.tfvars` file:

```hcl
location = "East US"
resource_prefix = "fleet"
eventhub_partition_count = 4
cosmosdb_throughput = 400
```

## Deployment Options

### Development Environment

For development and testing:

```bash
# Using Bicep
az deployment group create \
    --resource-group rg-geospatial-dev \
    --template-file bicep/main.bicep \
    --parameters location=eastus resourcePrefix=dev-fleet

# Using Terraform
terraform apply -var="environment=dev" -var="resource_prefix=dev-fleet"
```

### Production Environment

For production deployments:

```bash
# Using Bicep
az deployment group create \
    --resource-group rg-geospatial-prod \
    --template-file bicep/main.bicep \
    --parameters location=eastus resourcePrefix=prod-fleet

# Using Terraform
terraform apply -var="environment=prod" -var="resource_prefix=prod-fleet"
```

## Monitoring and Alerts

The infrastructure includes:

- **Diagnostic Settings**: Stream logs to Azure Monitor
- **Metric Alerts**: Monitor processing latency and error rates
- **Action Groups**: Configure notification channels
- **Log Analytics**: Query and analyze operational data

## Security Features

- **Managed Identity**: Secure service-to-service authentication
- **Private Endpoints**: Secure network connectivity
- **Azure Key Vault**: Secure secret storage
- **Network Security Groups**: Control network access
- **Azure RBAC**: Fine-grained access control

## Testing the Deployment

After deployment, verify the infrastructure:

```bash
# Check Stream Analytics job status
az stream-analytics job show \
    --name asa-geospatial-[suffix] \
    --resource-group rg-geospatial-analytics \
    --query jobState

# Test Event Hub connectivity
az eventhubs eventhub show \
    --name vehicle-locations \
    --namespace-name ehns-fleet-[suffix] \
    --resource-group rg-geospatial-analytics

# Verify Cosmos DB container
az cosmosdb sql container show \
    --account-name cosmos-fleet-[suffix] \
    --database-name FleetAnalytics \
    --name LocationEvents \
    --resource-group rg-geospatial-analytics
```

## Data Flow

1. **Data Ingestion**: Vehicles send GPS coordinates to Event Hubs
2. **Stream Processing**: Stream Analytics processes location data with geospatial functions
3. **Geofence Detection**: Real-time monitoring for zone violations
4. **Alert Generation**: Immediate notifications for critical events
5. **Data Storage**: Processed events stored in Cosmos DB for queries
6. **Visualization**: Azure Maps displays real-time fleet positions

## Sample Data Format

The system expects vehicle location data in this JSON format:

```json
{
    "vehicleId": "VEHICLE-001",
    "location": {
        "latitude": 47.645,
        "longitude": -122.120
    },
    "speed": 65,
    "timestamp": "2025-01-15T10:30:00Z"
}
```

## Performance Optimization

- **Partition Strategy**: Event Hubs partitioned by vehicle ID for parallel processing
- **Indexing**: Cosmos DB optimized for geospatial queries
- **Caching**: Azure Maps includes built-in caching for map tiles
- **Scaling**: Stream Analytics automatically scales based on load

## Cost Optimization

- **Consumption Tiers**: Use serverless options for variable workloads
- **Reserved Capacity**: Consider reserved instances for predictable workloads
- **Data Lifecycle**: Implement tiered storage for historical data
- **Monitoring**: Set up cost alerts and budgets

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-geospatial-analytics \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Stream Analytics Job Fails to Start**
   - Check input/output configurations
   - Verify connection strings and access keys
   - Review query syntax for errors

2. **High Processing Latency**
   - Increase Stream Analytics streaming units
   - Optimize Event Hubs partition count
   - Review query complexity

3. **Cosmos DB Throttling**
   - Increase provisioned throughput
   - Optimize partition key strategy
   - Consider autoscale settings

### Diagnostic Commands

```bash
# Check Stream Analytics job metrics
az monitor metrics list \
    --resource [stream-analytics-job-id] \
    --metric "IncomingEvents,ProcessingLatency"

# View diagnostic logs
az monitor log-analytics query \
    --workspace [workspace-id] \
    --analytics-query "AzureDiagnostics | where Category == 'Execution'"
```

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../building-real-time-geospatial-analytics-with-azure-maps-and-azure-stream-analytics.md)
- [Azure Stream Analytics documentation](https://docs.microsoft.com/en-us/azure/stream-analytics/)
- [Azure Maps documentation](https://docs.microsoft.com/en-us/azure/azure-maps/)
- [Azure Event Hubs documentation](https://docs.microsoft.com/en-us/azure/event-hubs/)

## Contributing

When modifying this infrastructure code:

1. Follow Azure naming conventions
2. Update parameter descriptions
3. Test in development environment first
4. Update documentation for any changes
5. Validate with Azure Policy compliance