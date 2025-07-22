# Infrastructure as Code for Real-Time Trading Signal Analysis with Multimodal AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Trading Signal Analysis with Multimodal AI".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions to create:
  - AI Services (Cognitive Services)
  - Event Hubs
  - Stream Analytics
  - Azure Functions
  - Cosmos DB
  - Service Bus
  - Storage Accounts
- For Bicep: Azure CLI with Bicep extension
- For Terraform: Terraform v1.0+ installed
- Basic understanding of financial trading systems and real-time analytics
- Estimated cost: $200-400/month for development workloads

> **Note**: Azure AI Content Understanding is currently in preview and availability may vary by region. Ensure your subscription has access to preview features.

## Quick Start

### Using Bicep (Recommended)

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-trading-signals" \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
                 environment=production \
                 deploymentSuffix=$(openssl rand -hex 3)

# Monitor deployment status
az deployment group show \
    --resource-group "rg-trading-signals" \
    --name "main" \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Plan the deployment
terraform plan \
    -var="location=eastus" \
    -var="environment=production" \
    -var="deployment_suffix=$(openssl rand -hex 3)"

# Apply the infrastructure
terraform apply \
    -var="location=eastus" \
    -var="environment=production" \
    -var="deployment_suffix=$(openssl rand -hex 3)"

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set environment variables
export AZURE_LOCATION="eastus"
export AZURE_ENVIRONMENT="production"
export DEPLOYMENT_SUFFIX=$(openssl rand -hex 3)

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
az resource list --resource-group "rg-trading-signals-${DEPLOYMENT_SUFFIX}" --output table
```

## Architecture Overview

This infrastructure deploys a complete intelligent financial trading signal analysis system including:

### Core Components

- **Azure AI Services**: Multi-service cognitive services account for content understanding
- **Azure Event Hubs**: High-throughput data ingestion for market data and content insights
- **Azure Stream Analytics**: Real-time stream processing for trading signal generation
- **Azure Functions**: Serverless compute for content processing and signal enhancement
- **Azure Cosmos DB**: Global distributed database for signal storage and retrieval
- **Azure Service Bus**: Reliable message delivery for trading signal distribution
- **Azure Storage**: Blob storage for financial content and data lake functionality

### Key Features

- **Real-time Processing**: Sub-second latency for trading signal generation
- **Multimodal Content Analysis**: Process videos, documents, and audio content
- **Scalable Architecture**: Auto-scaling based on market data volume
- **High Availability**: Multi-region deployment capabilities
- **Cost Optimization**: Serverless and consumption-based pricing models

## Configuration Options

### Bicep Parameters

```bicep
@description('Azure region for resource deployment')
param location string = 'eastus'

@description('Environment designation (dev, staging, production)')
@allowed(['dev', 'staging', 'production'])
param environment string = 'production'

@description('Unique suffix for resource names')
param deploymentSuffix string

@description('Event Hub throughput units')
@minValue(1)
@maxValue(20)
param eventHubThroughputUnits int = 10

@description('Stream Analytics streaming units')
@minValue(1)
@maxValue(192)
param streamAnalyticsStreamingUnits int = 6

@description('Cosmos DB throughput (RU/s)')
@minValue(400)
@maxValue(100000)
param cosmosDbThroughput int = 1000
```

### Terraform Variables

```hcl
variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment designation"
  type        = string
  default     = "production"
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "deployment_suffix" {
  description = "Unique suffix for resource names"
  type        = string
}

variable "event_hub_throughput_units" {
  description = "Event Hub throughput units"
  type        = number
  default     = 10
}

variable "stream_analytics_streaming_units" {
  description = "Stream Analytics streaming units"
  type        = number
  default     = 6
}

variable "cosmos_db_throughput" {
  description = "Cosmos DB throughput (RU/s)"
  type        = number
  default     = 1000
}
```

## Post-Deployment Configuration

### 1. Configure Content Processing

```bash
# Upload sample content for testing
az storage blob upload \
    --account-name "sttrading${DEPLOYMENT_SUFFIX}" \
    --container-name "financial-videos" \
    --file "sample-earnings-call.mp4" \
    --name "earnings-calls/2025/Q1/sample-earnings-call.mp4"

# Configure AI Content Understanding analysis
az cognitiveservices account create-content-analysis \
    --name "ais-trading-${DEPLOYMENT_SUFFIX}" \
    --resource-group "rg-trading-signals-${DEPLOYMENT_SUFFIX}" \
    --content-type "video" \
    --source-url "https://sttrading${DEPLOYMENT_SUFFIX}.blob.core.windows.net/financial-videos/earnings-calls/2025/Q1/sample-earnings-call.mp4"
```

### 2. Test Market Data Ingestion

```bash
# Send test market data to Event Hub
az eventhubs eventhub send \
    --namespace-name "ehns-trading-${DEPLOYMENT_SUFFIX}" \
    --eventhub-name "eh-market-data" \
    --resource-group "rg-trading-signals-${DEPLOYMENT_SUFFIX}" \
    --data '{
        "symbol": "AAPL",
        "price": 150.25,
        "volume": 1500000,
        "timestamp": "2025-07-12T10:30:00Z"
    }'
```

### 3. Monitor Stream Analytics

```bash
# Check Stream Analytics job status
az stream-analytics job show \
    --name "saj-trading-signals" \
    --resource-group "rg-trading-signals-${DEPLOYMENT_SUFFIX}" \
    --query '{name:name, state:jobState, streamingUnits:transformation.streamingUnits}'

# View job metrics
az monitor metrics list \
    --resource "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-trading-signals-${DEPLOYMENT_SUFFIX}/providers/Microsoft.StreamAnalytics/streamingjobs/saj-trading-signals" \
    --metric "InputEvents" \
    --interval PT1M
```

## Validation & Testing

### 1. Verify Resource Deployment

```bash
# Check all resources are created
az resource list \
    --resource-group "rg-trading-signals-${DEPLOYMENT_SUFFIX}" \
    --output table

# Verify Event Hub is receiving data
az eventhubs eventhub show \
    --namespace-name "ehns-trading-${DEPLOYMENT_SUFFIX}" \
    --name "eh-market-data" \
    --resource-group "rg-trading-signals-${DEPLOYMENT_SUFFIX}"
```

### 2. Test Signal Generation

```bash
# Query Cosmos DB for generated signals
az cosmosdb sql query \
    --account-name "cosmos-trading-${DEPLOYMENT_SUFFIX}" \
    --database-name "TradingSignals" \
    --container-name "Signals" \
    --query-text "SELECT * FROM c WHERE c.signal IN ('STRONG_BUY', 'STRONG_SELL') ORDER BY c.signal_timestamp DESC OFFSET 0 LIMIT 10"
```

### 3. Validate Function App

```bash
# Check Function App status
az functionapp show \
    --name "func-trading-${DEPLOYMENT_SUFFIX}" \
    --resource-group "rg-trading-signals-${DEPLOYMENT_SUFFIX}" \
    --query '{name:name, state:state, kind:kind}'

# View Function logs
az functionapp log tail \
    --name "func-trading-${DEPLOYMENT_SUFFIX}" \
    --resource-group "rg-trading-signals-${DEPLOYMENT_SUFFIX}"
```

## Monitoring and Observability

### Key Metrics to Monitor

1. **Event Hub Metrics**:
   - Incoming Messages
   - Outgoing Messages
   - Throttled Requests
   - Server Errors

2. **Stream Analytics Metrics**:
   - Input Events
   - Output Events
   - Runtime Errors
   - Resource Utilization

3. **Function App Metrics**:
   - Function Execution Count
   - Function Execution Duration
   - Function Errors
   - Memory Usage

4. **Cosmos DB Metrics**:
   - Request Units Consumed
   - Storage Usage
   - Throttled Requests
   - Latency

### Setting Up Alerts

```bash
# Create alert rule for high error rates
az monitor metrics alert create \
    --name "HighErrorRate" \
    --resource-group "rg-trading-signals-${DEPLOYMENT_SUFFIX}" \
    --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-trading-signals-${DEPLOYMENT_SUFFIX}/providers/Microsoft.StreamAnalytics/streamingjobs/saj-trading-signals" \
    --condition "count 'Runtime Errors' > 10" \
    --window-size 5m \
    --evaluation-frequency 1m
```

## Security Considerations

### Identity and Access Management

- All services use Azure Managed Identity for authentication
- Key Vault integration for secrets management
- Role-based access control (RBAC) for resource access
- Network security groups for traffic filtering

### Data Protection

- Encryption at rest for all storage services
- TLS 1.2 for data in transit
- Azure Private Link for secure service communication
- Data residency controls for compliance

### Compliance Features

- Audit logging for all operations
- Data retention policies
- Compliance with SOC 2, ISO 27001, and other standards
- GDPR compliance features

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name "rg-trading-signals-${DEPLOYMENT_SUFFIX}" \
    --yes \
    --no-wait

# Verify deletion
az group exists --name "rg-trading-signals-${DEPLOYMENT_SUFFIX}"
```

### Using Terraform

```bash
# Destroy all resources
cd terraform/
terraform destroy \
    -var="location=eastus" \
    -var="environment=production" \
    -var="deployment_suffix=${DEPLOYMENT_SUFFIX}"

# Verify state is clean
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group exists --name "rg-trading-signals-${DEPLOYMENT_SUFFIX}"
```

## Cost Optimization

### Strategies

1. **Auto-scaling**: Enable auto-scaling for Event Hubs and Stream Analytics
2. **Reserved Capacity**: Use Azure Reserved Instances for predictable workloads
3. **Storage Tiering**: Implement lifecycle policies for blob storage
4. **Right-sizing**: Monitor and adjust capacity based on actual usage

### Cost Monitoring

```bash
# View cost analysis
az consumption budget list \
    --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-trading-signals-${DEPLOYMENT_SUFFIX}"

# Set up budget alerts
az consumption budget create \
    --budget-name "TradingSignalsBudget" \
    --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-trading-signals-${DEPLOYMENT_SUFFIX}" \
    --amount 500 \
    --time-grain Monthly
```

## Troubleshooting

### Common Issues

1. **Stream Analytics Job Errors**:
   - Check input data format matches expected schema
   - Verify Event Hub connection string and permissions
   - Monitor streaming unit allocation

2. **Function App Failures**:
   - Check application settings configuration
   - Verify storage account connectivity
   - Review function logs for specific errors

3. **Cosmos DB Throttling**:
   - Monitor request unit consumption
   - Consider increasing throughput or using autoscale
   - Optimize query patterns

### Diagnostic Commands

```bash
# View Stream Analytics job errors
az stream-analytics job show \
    --name "saj-trading-signals" \
    --resource-group "rg-trading-signals-${DEPLOYMENT_SUFFIX}" \
    --query "jobState"

# Check Function App logs
az functionapp log tail \
    --name "func-trading-${DEPLOYMENT_SUFFIX}" \
    --resource-group "rg-trading-signals-${DEPLOYMENT_SUFFIX}"

# Monitor Cosmos DB metrics
az cosmosdb show \
    --name "cosmos-trading-${DEPLOYMENT_SUFFIX}" \
    --resource-group "rg-trading-signals-${DEPLOYMENT_SUFFIX}"
```

## Customization

### Scaling Considerations

- **Event Hub Partitions**: Increase for higher throughput
- **Stream Analytics Units**: Scale based on query complexity
- **Function App Plan**: Consider Premium or Dedicated plans for consistent performance
- **Cosmos DB Autoscale**: Enable for variable workloads

### Regional Deployment

```bash
# Deploy to multiple regions for high availability
az deployment group create \
    --resource-group "rg-trading-signals-west" \
    --template-file bicep/main.bicep \
    --parameters location=westus2 \
                 environment=production \
                 deploymentSuffix=${DEPLOYMENT_SUFFIX}
```

## Support and Documentation

### Resources

- [Azure AI Content Understanding Documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/content-understanding/)
- [Azure Stream Analytics Documentation](https://docs.microsoft.com/en-us/azure/stream-analytics/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Cosmos DB Documentation](https://docs.microsoft.com/en-us/azure/cosmos-db/)
- [Azure Architecture Center - Financial Services](https://docs.microsoft.com/en-us/azure/architecture/industries/financial/)

### Support Channels

- Azure Support Portal for technical issues
- Azure Community Forums for general questions
- GitHub Issues for infrastructure code problems
- Microsoft FastTrack for enterprise deployments

For issues with this infrastructure code, refer to the original recipe documentation or the Azure service-specific documentation linked above.