# Infrastructure as Code for Smart Model Selection with AI Foundry and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Model Selection with AI Foundry and Functions".

## Overview

This solution builds an intelligent model selection system using Azure AI Foundry's Model Router to automatically choose the optimal AI model for each request. The system uses Azure Functions for serverless scalability, with Azure Storage tracking cost metrics and performance analytics. This implementation can reduce AI costs by up to 60% while maintaining response quality.

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using official Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure deploys the following Azure resources:

- **Azure AI Services**: Provides Model Router deployment with intelligent model selection
- **Azure Functions**: Serverless compute for processing requests and analytics
- **Azure Storage Account**: Tables for metrics and cost tracking analytics
- **Application Insights**: Comprehensive monitoring and telemetry
- **Resource Group**: Logical container for all resources

## Prerequisites

### General Requirements

- Azure subscription with appropriate permissions for creating resources
- Azure CLI installed and configured (version 2.60.0 or later)
- Resource creation permissions for:
  - Azure AI Services
  - Azure Functions
  - Azure Storage
  - Application Insights
  - Resource Groups

### Tool-Specific Requirements

#### For Bicep Deployment
- Azure CLI with Bicep extension (automatically installed with recent CLI versions)
- PowerShell or Bash terminal

#### For Terraform Deployment
- Terraform installed (version 1.0 or later)
- Azure CLI authenticated with appropriate subscription
- Terraform Azure provider configured

#### For Script Deployment
- Bash shell environment
- Azure Functions Core Tools (version 4.x or later)
- Python 3.11 for function development

### Cost Considerations

- Estimated testing cost: $15-25 for resources
- Model Router is in preview (East US 2 and Sweden Central regions only)
- Consumption-based pricing for Functions and AI Services
- Standard LRS storage for analytics data

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Review and customize parameters
cat parameters.json

# Deploy infrastructure
az deployment group create \
    --resource-group rg-smart-model-$(openssl rand -hex 3) \
    --template-file main.bicep \
    --parameters @parameters.json

# Get deployment outputs
az deployment group show \
    --resource-group <your-resource-group> \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure and application
./scripts/deploy.sh

# View deployment status
echo "Check Azure portal for resource status"
```

## Deployment Details

### Resource Configuration

The IaC creates the following key configurations:

1. **AI Services Resource**:
   - SKU: S0 (Standard)
   - Custom domain enabled for Model Router
   - Location: East US 2 (required for Model Router preview)

2. **Model Router Deployment**:
   - Model: model-router (version 2025-05-19)
   - Capacity: 10 units
   - SKU: GlobalStandard

3. **Function App**:
   - Runtime: Python 3.11
   - Plan: Consumption (pay-per-execution)
   - Functions: ModelSelection and AnalyticsDashboard

4. **Storage Account**:
   - SKU: Standard_LRS
   - Tables: modelmetrics and costtracking
   - Optimized for analytics workloads

5. **Application Insights**:
   - Integrated with Function App
   - Custom metrics for model selection tracking

### Environment Variables

The deployment automatically configures these environment variables:

- `AI_FOUNDRY_ENDPOINT`: Azure AI Services endpoint URL
- `AI_FOUNDRY_KEY`: Authentication key for AI Services
- `STORAGE_CONNECTION_STRING`: Connection string for analytics storage
- `APPINSIGHTS_INSTRUMENTATIONKEY`: Application Insights telemetry key

## Testing the Deployment

### Verify Resource Creation

```bash
# Check resource group contents
az resource list --resource-group <your-resource-group> --output table

# Verify AI Services deployment
az cognitiveservices account show \
    --name <ai-services-name> \
    --resource-group <your-resource-group>

# Check Function App status
az functionapp show \
    --name <function-app-name> \
    --resource-group <your-resource-group> \
    --query "state"
```

### Test Model Selection Function

```bash
# Get function URL and key
FUNCTION_URL=$(az functionapp function show \
    --name <function-app-name> \
    --resource-group <your-resource-group> \
    --function-name "ModelSelection" \
    --query "invokeUrlTemplate" \
    --output tsv)

FUNCTION_KEY=$(az functionapp keys list \
    --name <function-app-name> \
    --resource-group <your-resource-group> \
    --query "functionKeys.default" \
    --output tsv)

# Test with simple query
curl -X POST "${FUNCTION_URL}?code=${FUNCTION_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
        "message": "What is the capital of France?",
        "user_id": "test_user_1"
    }'

# Test with complex query
curl -X POST "${FUNCTION_URL}?code=${FUNCTION_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
        "message": "Analyze the philosophical implications of AI on society.",
        "user_id": "test_user_2"
    }'
```

### View Analytics Dashboard

```bash
# Get analytics function URL
ANALYTICS_URL=$(az functionapp function show \
    --name <function-app-name> \
    --resource-group <your-resource-group> \
    --function-name "AnalyticsDashboard" \
    --query "invokeUrlTemplate" \
    --output tsv)

# View analytics data
curl "${ANALYTICS_URL}?code=${FUNCTION_KEY}&days=1"
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
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resources are removed
az resource list --resource-group <your-resource-group>
```

## Customization

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus2"
    },
    "resourcePrefix": {
      "value": "smartmodel"
    },
    "functionAppSku": {
      "value": "Y1"
    },
    "storageSku": {
      "value": "Standard_LRS"
    }
  }
}
```

### Terraform Variables

Modify `terraform/variables.tf` or create `terraform.tfvars`:

```hcl
location = "East US 2"
resource_prefix = "smartmodel"
environment = "production"
enable_monitoring = true
storage_replication_type = "LRS"
```

### Common Customizations

1. **Region Selection**: Change location (must support Model Router preview)
2. **Naming Convention**: Modify resource prefix and naming patterns
3. **SKU Selection**: Adjust compute and storage SKUs based on requirements
4. **Monitoring Level**: Configure Application Insights sampling and retention
5. **Security Settings**: Modify access policies and authentication methods

## Monitoring and Operations

### Key Metrics to Monitor

- **Function Execution Count**: Number of model selection requests
- **Response Time**: Average processing time per request
- **Error Rate**: Failed requests and error patterns
- **Cost Per Request**: AI service costs per model selection
- **Model Distribution**: Usage patterns across different models

### Application Insights Queries

```kusto
// Function execution trends
requests
| where name == "ModelSelection"
| summarize count() by bin(timestamp, 1h)
| render timechart

// Model selection patterns
traces
| where message contains "Model selected"
| extend model = extract("model: ([^,]+)", 1, message)
| summarize count() by model
| render piechart

// Cost analysis
customMetrics
| where name == "EstimatedCost"
| summarize avg(value), sum(value) by bin(timestamp, 1d)
| render timechart
```

### Scaling Considerations

- **Function App**: Automatically scales based on demand (Consumption plan)
- **AI Services**: Increase quota for higher throughput
- **Storage**: Consider premium storage for high-volume analytics
- **Application Insights**: Adjust sampling for cost optimization

## Troubleshooting

### Common Issues

1. **Model Router Deployment Failed**:
   - Verify region supports Model Router (East US 2 or Sweden Central)
   - Check AI Services quota and limits
   - Ensure custom domain is properly configured

2. **Function App Authentication Errors**:
   - Verify AI Services key is correctly configured
   - Check environment variable configuration
   - Validate storage connection string

3. **Storage Table Access Issues**:
   - Confirm storage account permissions
   - Verify connection string format
   - Check network access rules

4. **Cost Tracking Inaccuracies**:
   - Review token estimation logic
   - Update pricing information in function code
   - Validate model mapping configurations

### Debug Commands

```bash
# Check Function App logs
az functionapp logs tail \
    --name <function-app-name> \
    --resource-group <your-resource-group>

# Verify AI Services connectivity
az cognitiveservices account keys list \
    --name <ai-services-name> \
    --resource-group <your-resource-group>

# Test storage table access
az storage entity query \
    --table-name modelmetrics \
    --connection-string "<storage-connection-string>"
```

## Security Considerations

### Best Practices Implemented

- **API Key Management**: Stored in Function App configuration (encrypted at rest)
- **Network Security**: Resources use Azure managed networking
- **Access Control**: Function-level authentication for HTTP triggers
- **Data Encryption**: Storage and AI Services use encryption at rest and in transit
- **Monitoring**: Comprehensive logging and alerting via Application Insights

### Additional Security Enhancements

- Consider using Azure Key Vault for secret management
- Implement Azure Private Link for network isolation
- Enable Azure AD authentication for enhanced access control
- Configure custom domain with SSL certificates
- Implement rate limiting and request throttling

## Performance Optimization

### Function App Optimization

- **Cold Start Mitigation**: Consider Premium plan for consistent performance
- **Memory Allocation**: Optimize based on processing requirements
- **Connection Pooling**: Implement efficient connections to external services
- **Async Processing**: Use async patterns for concurrent requests

### Storage Optimization

- **Table Design**: Optimize partition keys for query performance
- **Batch Operations**: Use batch inserts for high-volume scenarios
- **Archival Strategy**: Implement data lifecycle policies for cost management

### AI Services Optimization

- **Quota Management**: Monitor and adjust quota based on usage patterns
- **Regional Deployment**: Consider multi-region deployment for global access
- **Caching Strategy**: Implement response caching for repeated queries

## Support and Documentation

### Additional Resources

- [Azure AI Foundry Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/)
- [Azure Functions Best Practices](https://learn.microsoft.com/en-us/azure/azure-functions/functions-best-practices)
- [Bicep Resource Reference](https://learn.microsoft.com/en-us/azure/templates/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)

### Getting Help

For issues with this infrastructure code:

1. Review the original recipe documentation for context
2. Check Azure service health and regional availability
3. Consult Azure support for service-specific issues
4. Review Application Insights for runtime errors and performance issues

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow Azure Resource Manager best practices
3. Update documentation for any parameter changes
4. Validate security and cost implications