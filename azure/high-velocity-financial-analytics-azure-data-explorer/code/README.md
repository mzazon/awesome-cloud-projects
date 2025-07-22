# Infrastructure as Code for High-Velocity Financial Analytics with Azure Data Explorer and Event Hubs

This directory contains Infrastructure as Code (IaC) implementations for the recipe "High-Velocity Financial Analytics with Azure Data Explorer and Event Hubs".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a comprehensive real-time financial market data processing pipeline including:

- Azure Data Explorer cluster for high-performance analytics
- Event Hubs namespace with dedicated hubs for market data and trading events
- Azure Functions for serverless data processing
- Event Grid for automated trading alerts
- Application Insights and Log Analytics for monitoring
- Storage Account for Function App requirements

## Prerequisites

- Azure CLI version 2.50.0 or later installed and configured
- Azure subscription with contributor permissions
- For Terraform: Terraform CLI version 1.0+ installed
- Basic understanding of financial market data structures (OHLCV, tick data)
- Estimated cost: $150-300 per day for testing (production costs vary by volume)

### Required Permissions

Your Azure account needs the following permissions:
- Contributor role on the target subscription or resource group
- Permission to create Azure Data Explorer clusters
- Permission to create Event Hubs namespaces
- Permission to create Azure Functions and storage accounts

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-financial-market-data \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json

# Monitor deployment progress
az deployment group show \
    --resource-group rg-financial-market-data \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# Check deployment status
./scripts/status.sh
```

## Configuration Parameters

### Bicep Parameters

Key parameters available in `bicep/parameters.json`:

- `location`: Azure region for deployment (default: eastus)
- `resourcePrefix`: Prefix for all resource names
- `adxSkuName`: Azure Data Explorer SKU (default: Dev(No SLA)_Standard_D11_v2)
- `eventHubsSkuTier`: Event Hubs pricing tier (default: Standard)
- `eventHubsThroughputUnits`: Initial throughput units (default: 2)
- `functionAppRuntime`: Function App runtime (default: python)

### Terraform Variables

Key variables in `terraform/variables.tf`:

- `resource_group_name`: Name of the resource group to create
- `location`: Azure region for deployment
- `environment`: Environment tag (dev/staging/prod)
- `adx_cluster_sku`: Azure Data Explorer cluster configuration
- `enable_monitoring`: Enable Application Insights and monitoring (default: true)

## Post-Deployment Configuration

After infrastructure deployment, complete these additional setup steps:

### 1. Create Database Tables

```bash
# Get ADX cluster URI
ADX_URI=$(az kusto cluster show \
    --cluster-name <adx-cluster-name> \
    --resource-group <resource-group> \
    --query uri --output tsv)

# Execute KQL commands to create tables (see recipe for full schema)
# Use Azure Data Explorer web UI or Kusto CLI
```

### 2. Deploy Function Code

```bash
# Package and deploy Azure Functions
cd function-code/
func azure functionapp publish <function-app-name>
```

### 3. Configure Event Grid Subscriptions

```bash
# Create subscription for trading alerts
az eventgrid event-subscription create \
    --source-resource-id <event-grid-topic-id> \
    --name trading-alerts-subscription \
    --endpoint <webhook-endpoint>
```

## Validation and Testing

### Infrastructure Validation

```bash
# Check Azure Data Explorer cluster status
az kusto cluster show \
    --cluster-name <adx-cluster-name> \
    --resource-group <resource-group> \
    --query "{name:name,state:state,uri:uri}" --output table

# Verify Event Hubs configuration
az eventhubs namespace show \
    --resource-group <resource-group> \
    --name <event-hub-namespace> \
    --query "{name:name,status:status}" --output table

# Test Function App deployment
az functionapp show \
    --name <function-app-name> \
    --resource-group <resource-group> \
    --query "{name:name,state:state}" --output table
```

### Data Flow Testing

```bash
# Send test market data to Event Hub
az eventhubs eventhub send \
    --resource-group <resource-group> \
    --namespace-name <event-hub-namespace> \
    --name market-data-hub \
    --body '{"symbol":"AAPL","price":150.25,"timestamp":"2025-01-15T10:30:00Z"}'

# Query ADX for ingested data
# Use KQL: MarketDataRaw | where symbol == "AAPL" | top 10 by timestamp desc
```

## Monitoring and Observability

### Application Insights

Access performance metrics and logs:
- Function execution metrics
- Event processing latency
- Error rates and exceptions
- Custom trading metrics

### Log Analytics

Centralized logging for:
- Azure Data Explorer query performance
- Event Hubs throughput metrics
- Function App execution logs
- Security and audit events

### Key Metrics to Monitor

- **Ingestion Latency**: Time from Event Hub to ADX
- **Query Performance**: ADX query execution times
- **Throughput**: Events processed per second
- **Error Rates**: Failed function executions
- **Storage Usage**: ADX cluster storage consumption

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-financial-market-data \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
az group show --name rg-financial-market-data
```

## Cost Optimization

### Development/Testing

- Use Azure Data Explorer Dev/Basic SKU for non-production workloads
- Set Event Hubs auto-inflate with lower maximum throughput units
- Use consumption plan for Azure Functions
- Enable auto-pause for ADX clusters during off-hours

### Production Optimization

- Right-size ADX cluster based on query patterns and data volume
- Implement data retention policies in ADX (hot cache period optimization)
- Use reserved capacity for predictable workloads
- Monitor and optimize Event Hubs partition count based on throughput

## Security Considerations

### Network Security

- Configure private endpoints for ADX and Event Hubs in production
- Implement network security groups and Azure Firewall rules
- Use Azure Private DNS for private endpoint resolution

### Identity and Access Management

- Configure Azure AD authentication for ADX cluster
- Implement least privilege access using Azure RBAC
- Use managed identities for Function App connections
- Rotate Event Hubs access keys regularly

### Data Protection

- Enable encryption at rest for all storage components
- Configure TLS 1.2+ for all data in transit
- Implement data masking for sensitive financial data
- Configure audit logging for compliance requirements

## Troubleshooting

### Common Issues

1. **ADX Cluster Creation Timeout**
   - Verify quota limits in target region
   - Check Azure service health status
   - Ensure proper permissions for cluster creation

2. **Event Hubs Connection Failures**
   - Verify connection string format
   - Check network connectivity and firewall rules
   - Validate Event Hubs namespace status

3. **Function App Deployment Issues**
   - Verify storage account access
   - Check Function App runtime version compatibility
   - Review Application Insights for error details

### Diagnostic Commands

```bash
# Check ADX cluster health
az kusto cluster show \
    --cluster-name <cluster-name> \
    --resource-group <resource-group> \
    --query "properties.provisioningState"

# View Event Hubs metrics
az monitor metrics list \
    --resource <event-hub-resource-id> \
    --metric IncomingMessages

# Review Function App logs
az functionapp logs tail \
    --name <function-app-name> \
    --resource-group <resource-group>
```

## Performance Tuning

### Azure Data Explorer Optimization

- Configure materialized views for frequently queried aggregations
- Optimize ingestion batching policies
- Implement proper partitioning strategies
- Monitor cache hit ratios and adjust retention policies

### Event Hubs Optimization

- Right-size partition count based on expected throughput
- Configure appropriate message retention periods
- Implement consumer group strategies for parallel processing
- Monitor throughput unit utilization

### Function App Optimization

- Configure appropriate timeout and memory settings
- Implement efficient batching for ADX operations
- Use async/await patterns for I/O operations
- Monitor cold start performance and optimize accordingly

## Compliance and Governance

### Financial Services Compliance

This solution supports compliance with common financial regulations:

- **SOX (Sarbanes-Oxley)**: Comprehensive audit trails and data integrity
- **MiFID II**: Transaction reporting and record keeping
- **GDPR**: Data protection and privacy controls
- **PCI DSS**: Secure data handling for payment-related data

### Governance Features

- Azure Policy integration for resource compliance
- Resource tagging for cost allocation and management
- Azure Blueprint support for repeatable deployments
- Role-based access control (RBAC) for granular permissions

## Support and Documentation

### Official Documentation

- [Azure Data Explorer Documentation](https://docs.microsoft.com/en-us/azure/data-explorer/)
- [Azure Event Hubs Documentation](https://docs.microsoft.com/en-us/azure/event-hubs/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Event Grid Documentation](https://docs.microsoft.com/en-us/azure/event-grid/)

### Best Practices Guides

- [Azure Data Explorer Best Practices](https://docs.microsoft.com/en-us/azure/data-explorer/kusto/query/best-practices)
- [Event Hubs Performance Guide](https://docs.microsoft.com/en-us/azure/event-hubs/event-hubs-scalability)
- [Azure Functions Performance](https://docs.microsoft.com/en-us/azure/azure-functions/functions-best-practices)

### Community Resources

- [Azure Data Explorer Community](https://techcommunity.microsoft.com/t5/azure-data-explorer/bg-p/AzureDataExplorer)
- [Azure Architecture Center](https://docs.microsoft.com/en-us/azure/architecture/)
- [Financial Services on Azure](https://azure.microsoft.com/en-us/industries/financial-services/)

For issues with this infrastructure code, refer to the original recipe documentation or open an issue in the repository.