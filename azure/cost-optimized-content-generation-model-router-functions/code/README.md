# Infrastructure as Code for Cost-Optimized Content Generation using Model Router and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cost-Optimized Content Generation using Model Router and Functions".

## Overview

This solution implements an intelligent content generation pipeline using Azure AI Foundry Model Router that automatically selects the most cost-effective AI model based on content complexity analysis. The serverless architecture uses Azure Functions with Blob Storage triggers to orchestrate the workflow while maintaining comprehensive cost tracking and optimization.

## Available Implementations

- **Bicep**: Azure's recommended infrastructure as code language (declarative ARM template successor)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts with comprehensive error handling

## Architecture Components

The IaC implementations deploy the following Azure resources:

- **Azure AI Foundry Resource** with Model Router deployment
- **Azure Functions App** (Consumption plan) with Node.js 18 runtime
- **Azure Storage Account** with blob containers for input/output
- **Event Grid Subscription** for blob trigger automation
- **Azure Monitor** components for cost tracking and alerting
- **Budget Management** with automated cost alerts

## Prerequisites

- Azure CLI installed and configured (`az --version` >= 2.40.0)
- Azure subscription with the following permissions:
  - Contributor role on target resource group
  - Azure AI Foundry service access
  - Event Grid resource provider registered
- For Terraform: Terraform CLI installed (`>= 1.5.0`)
- For Bicep: Azure CLI with Bicep extension (`az bicep version`)
- Node.js 18+ and Azure Functions Core Tools v4 (for local development)
- Estimated deployment cost: $15-25 for testing environment

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Validate the template
az deployment group validate \
    --resource-group your-resource-group \
    --template-file main.bicep \
    --parameters location=eastus

# Deploy the infrastructure
az deployment group create \
    --resource-group your-resource-group \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters resourceNamePrefix=contentgen

# Monitor deployment progress
az deployment group show \
    --resource-group your-resource-group \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan \
    -var="resource_group_name=rg-content-generation" \
    -var="location=East US" \
    -var="resource_name_prefix=contentgen"

# Apply the configuration
terraform apply \
    -var="resource_group_name=rg-content-generation" \
    -var="location=East US" \
    -var="resource_name_prefix=contentgen"

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-content-generation-demo"
export LOCATION="eastus"
export RESOURCE_NAME_PREFIX="contentgen"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
az group show --name $RESOURCE_GROUP --output table
```

## Configuration Parameters

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `resourceGroup().location` | Azure region for resources |
| `resourceNamePrefix` | string | `contentgen` | Prefix for all resource names |
| `storageAccountSku` | string | `Standard_LRS` | Storage account performance tier |
| `functionAppPlan` | string | `Y1` | Functions consumption plan SKU |
| `aiFoundryModel` | string | `model-router` | AI Foundry model deployment name |
| `budgetAmount` | int | `100` | Monthly budget limit in USD |
| `alertEmail` | string | Required | Email for budget alerts |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `resource_group_name` | string | Required | Target resource group name |
| `location` | string | `East US` | Azure region for deployment |
| `resource_name_prefix` | string | `contentgen` | Prefix for resource naming |
| `storage_replication_type` | string | `LRS` | Storage account replication |
| `function_app_runtime` | string | `node` | Functions runtime stack |
| `ai_model_deployment` | string | `model-router-deployment` | Model Router deployment name |
| `budget_threshold` | number | `100` | Budget alert threshold |
| `notification_email` | string | Required | Email for cost alerts |

## Post-Deployment Configuration

### 1. Deploy Function Code

After infrastructure deployment, deploy the Azure Functions code:

```bash
# Clone or prepare your function code
mkdir content-functions && cd content-functions

# Initialize function project
func init --javascript --name ContentProcessor

# Create function files (ContentAnalyzer and ContentGenerator)
# ... (function code from recipe steps)

# Deploy to Azure Functions
func azure functionapp publish <function-app-name>
```

### 2. Configure Event Grid Integration

```bash
# Get storage account ID
STORAGE_ID=$(az storage account show \
    --name <storage-account-name> \
    --resource-group <resource-group> \
    --query id --output tsv)

# Create Event Grid subscription
az eventgrid event-subscription create \
    --name content-processing-events \
    --source-resource-id $STORAGE_ID \
    --endpoint-type azurefunction \
    --endpoint "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Web/sites/<function-app>/functions/ContentAnalyzer" \
    --included-event-types Microsoft.Storage.BlobCreated
```

### 3. Test the Solution

```bash
# Upload test content request
az storage blob upload \
    --file sample-request.json \
    --container-name content-requests \
    --name "test-$(date +%s).json" \
    --connection-string "<storage-connection-string>"

# Monitor function execution
az monitor log-analytics query \
    --workspace <function-app-name> \
    --analytics-query "traces | where message contains 'Content analyzed' | order by timestamp desc"
```

## Monitoring and Cost Management

### Access Deployed Resources

```bash
# List all deployed resources
az resource list \
    --resource-group <resource-group> \
    --output table

# Check AI Foundry deployment status
az cognitiveservices account deployment list \
    --name <ai-foundry-resource> \
    --resource-group <resource-group>

# Monitor function app logs
az webapp log tail \
    --name <function-app-name> \
    --resource-group <resource-group>
```

### Cost Monitoring

```bash
# View current costs
az consumption usage list \
    --start-date $(date -d '30 days ago' '+%Y-%m-%d') \
    --end-date $(date '+%Y-%m-%d') \
    --output table

# Check budget status
az consumption budget list \
    --output table
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name your-resource-group \
    --yes \
    --no-wait

# Or delete specific resources
az deployment group delete \
    --resource-group your-resource-group \
    --name main
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy \
    -var="resource_group_name=rg-content-generation" \
    -var="location=East US" \
    -var="resource_name_prefix=contentgen"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify all resources are removed
az group show --name $RESOURCE_GROUP --output table 2>/dev/null || echo "Resource group successfully deleted"
```

## Customization

### Adding Custom Models

To add additional AI models to the Model Router configuration:

1. **Bicep**: Modify the `aiFoundryDeployments` parameter in `main.bicep`
2. **Terraform**: Update the `model_deployments` variable in `variables.tf`
3. **Scripts**: Add model deployment commands in `deploy.sh`

### Scaling Configuration

Adjust the following parameters for production workloads:

- **Storage Performance**: Change from `Standard_LRS` to `Premium_LRS` for higher IOPS
- **Function App Plan**: Consider Premium plan for predictable workloads
- **AI Foundry Capacity**: Increase model deployment capacity for higher throughput
- **Budget Limits**: Set appropriate budget thresholds for production costs

### Security Enhancements

- Enable **Azure Key Vault** integration for secure credential management
- Configure **Managed Identity** for service-to-service authentication
- Implement **Private Endpoints** for enhanced network security
- Enable **Diagnostic Settings** for comprehensive audit logging

## Troubleshooting

### Common Issues

1. **Model Router Deployment Fails**
   ```bash
   # Check AI Foundry resource status
   az cognitiveservices account show \
       --name <ai-foundry-resource> \
       --resource-group <resource-group> \
       --query properties.provisioningState
   ```

2. **Function Deployment Issues**
   ```bash
   # Check function app status
   az functionapp show \
       --name <function-app-name> \
       --resource-group <resource-group> \
       --query state
   ```

3. **Event Grid Subscription Problems**
   ```bash
   # List event subscriptions
   az eventgrid event-subscription list \
       --source-resource-id <storage-account-id>
   ```

### Debugging

Enable verbose logging for detailed troubleshooting:

```bash
# Enable debug mode for Azure CLI
az configure --defaults group=<resource-group>
export AZURE_CLI_ENABLE_DEBUG=true

# For Terraform debugging
export TF_LOG=DEBUG
terraform apply
```

## Performance Optimization

### Function App Optimization

- **Cold Start Reduction**: Consider Premium plan for production workloads
- **Memory Allocation**: Optimize function memory settings based on content complexity
- **Concurrency Limits**: Configure appropriate concurrent execution limits

### Cost Optimization

- **Storage Tiering**: Implement lifecycle policies for long-term content storage
- **Model Selection Tuning**: Fine-tune complexity analysis algorithms
- **Reserved Capacity**: Consider Azure AI reserved instances for predictable workloads

## Security Best Practices

The IaC implementations include the following security measures:

- **Managed Identity**: Service-to-service authentication without stored credentials
- **Network Security**: Private endpoints and service-specific firewall rules
- **Data Encryption**: Encryption at rest and in transit for all data stores
- **Least Privilege**: Minimal required permissions for all service principals
- **Audit Logging**: Comprehensive activity logging and monitoring

## Support and Documentation

- **Recipe Documentation**: Refer to the main recipe markdown file for detailed implementation guidance
- **Azure AI Foundry**: [Model Router Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/concepts/model-router)
- **Azure Functions**: [Serverless Computing Guide](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview)
- **Bicep Language**: [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- **Terraform Azure Provider**: [Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Contributing

To improve these IaC implementations:

1. **Test Changes**: Validate all modifications in a development environment
2. **Security Review**: Ensure security best practices are maintained
3. **Documentation**: Update README.md with any configuration changes
4. **Versioning**: Follow semantic versioning for template updates

---

**Note**: This infrastructure code deploys cloud resources that incur costs. Always review the estimated costs and clean up resources when no longer needed to avoid unexpected charges.