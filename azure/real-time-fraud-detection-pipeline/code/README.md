# Infrastructure as Code for Real-Time Fraud Detection with Machine Learning

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Fraud Detection with Machine Learning".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure deployments)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts with Azure CLI

## Architecture Overview

This solution deploys a comprehensive real-time fraud detection pipeline that includes:

- **Azure Event Hubs**: High-throughput transaction data ingestion
- **Azure Stream Analytics**: Real-time stream processing and fraud detection logic
- **Azure Machine Learning**: Custom fraud detection models and scoring endpoints
- **Azure Functions**: Serverless fraud alert processing and response automation
- **Azure Cosmos DB**: NoSQL storage for transactions and fraud alerts
- **Azure Storage Account**: Required storage for Function Apps and ML workspace

## Prerequisites

- Azure subscription with sufficient permissions to create resources
- Azure CLI 2.60.0 or later installed and configured
- For Terraform: Terraform 1.5+ installed
- For Bicep: Bicep CLI installed (included with Azure CLI 2.20.0+)
- Basic understanding of fraud detection patterns and stream processing concepts
- Estimated cost: $50-100 per day for development workloads

> **Note**: This solution creates premium services that may incur significant costs. Review Azure pricing for Stream Analytics, Machine Learning, and Cosmos DB before deployment.

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-fraud-detection \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment status
az deployment group show \
    --resource-group rg-fraud-detection \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Apply infrastructure changes
terraform apply

# Confirm deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
az group show --name rg-fraud-detection-* --query "properties.provisioningState"
```

## Configuration Options

### Bicep Parameters

Key parameters available in `bicep/parameters.json`:

- `location`: Azure region for deployment (default: "eastus")
- `environmentName`: Environment suffix for resource naming
- `streamingUnits`: Stream Analytics job streaming units (1-48)
- `cosmosDbThroughput`: Cosmos DB provisioned throughput (400-100000 RU/s)
- `functionAppSku`: Function App hosting plan SKU

### Terraform Variables

Key variables in `terraform/variables.tf`:

- `resource_group_name`: Name of the resource group to create
- `location`: Azure region for resource deployment
- `environment`: Environment tag for resource organization
- `enable_monitoring`: Deploy Azure Monitor and Log Analytics
- `ml_compute_size`: Machine Learning compute instance size

### Script Configuration

Environment variables for bash scripts:

- `AZURE_LOCATION`: Target Azure region
- `RESOURCE_GROUP_PREFIX`: Prefix for resource group naming
- `ENABLE_ADVANCED_FEATURES`: Enable ML endpoints and advanced analytics

## Post-Deployment Configuration

After infrastructure deployment, complete these steps:

1. **Configure Stream Analytics Query**: Deploy the fraud detection query logic
2. **Deploy ML Model**: Upload and deploy your trained fraud detection model
3. **Configure Function App**: Deploy the fraud alert processing code
4. **Test Data Flow**: Send sample transactions to validate the pipeline
5. **Set Up Monitoring**: Configure alerts and dashboards for operational monitoring

## Monitoring and Observability

The deployed infrastructure includes:

- **Azure Monitor**: Centralized monitoring and alerting
- **Application Insights**: Function App performance monitoring
- **Stream Analytics Metrics**: Job performance and throughput monitoring
- **Cosmos DB Metrics**: Database performance and request monitoring

Access monitoring dashboards through the Azure Portal or configure custom dashboards using the output values.

## Security Considerations

This implementation follows Azure security best practices:

- **Managed Identity**: Services use system-assigned managed identities where possible
- **Network Security**: Private endpoints and VNet integration where supported
- **Access Control**: Role-based access control (RBAC) with least privilege
- **Encryption**: Data encryption at rest and in transit enabled by default
- **Key Management**: Secure storage of connection strings and secrets

## Troubleshooting

### Common Issues

1. **Stream Analytics Job Fails to Start**:
   - Verify Event Hub input connectivity
   - Check output destination permissions
   - Validate query syntax

2. **Function App Deployment Errors**:
   - Ensure storage account is accessible
   - Verify Cosmos DB connection string configuration
   - Check Function App runtime version compatibility

3. **ML Workspace Access Issues**:
   - Confirm storage account permissions
   - Verify compute instance deployment status
   - Check workspace resource provider registration

4. **High Costs**:
   - Review Stream Analytics streaming units allocation
   - Monitor Cosmos DB request unit consumption
   - Optimize ML compute instance usage

### Verification Commands

```bash
# Check Stream Analytics job status
az stream-analytics job show \
    --name <job-name> \
    --resource-group <resource-group> \
    --query "jobState"

# Verify Event Hub throughput
az eventhubs eventhub show \
    --name transactions \
    --namespace-name <namespace> \
    --resource-group <resource-group>

# Test Cosmos DB connectivity
az cosmosdb sql database list \
    --account-name <cosmos-account> \
    --resource-group <resource-group>
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name rg-fraud-detection --yes --no-wait
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

> **Warning**: Cleanup operations are irreversible and will permanently delete all data. Ensure you have backups of any important information before proceeding.

## Cost Optimization

To minimize costs during development and testing:

1. **Stream Analytics**: Use minimum streaming units (1) for testing
2. **Cosmos DB**: Use provisioned throughput with autoscale
3. **Function App**: Use Consumption plan for variable workloads
4. **ML Workspace**: Stop compute instances when not in use
5. **Event Hubs**: Use Standard tier for development workloads

## Advanced Configuration

### Production Readiness Checklist

- [ ] Configure backup and disaster recovery
- [ ] Implement network security groups and private endpoints
- [ ] Set up Azure Key Vault for secrets management
- [ ] Configure multi-region deployment for high availability
- [ ] Implement proper logging and monitoring alerts
- [ ] Set up automated testing and validation pipelines
- [ ] Configure cost management alerts and budgets

### Integration Points

This infrastructure provides integration points for:

- **External notification systems** via Function App webhooks
- **Existing fraud management platforms** through Cosmos DB APIs
- **Business intelligence tools** via Stream Analytics outputs
- **MLOps pipelines** through Azure Machine Learning integration

## Support and Documentation

For additional support:

- **Azure Documentation**: [Azure Stream Analytics](https://docs.microsoft.com/azure/stream-analytics/)
- **Terraform Azure Provider**: [Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- **Bicep Documentation**: [Azure Bicep](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)
- **Original Recipe**: Refer to the recipe markdown file in the parent directory

For issues with this infrastructure code, create an issue in the repository or consult the Azure support documentation.