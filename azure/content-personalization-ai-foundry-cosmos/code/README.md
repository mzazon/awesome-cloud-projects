# Infrastructure as Code for Content Personalization Engine with AI Foundry and Cosmos

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Content Personalization Engine with AI Foundry and Cosmos". This solution builds an intelligent content personalization system using Azure AI Foundry's orchestration capabilities to coordinate Azure OpenAI models with user behavior data stored in Azure Cosmos DB, leveraging vector search for semantic matching and Azure Functions for serverless processing.

## Architecture Overview

The solution deploys a complete content personalization platform consisting of:

- **Azure Cosmos DB** with vector search capabilities for user profiles and content storage
- **Azure OpenAI Service** with GPT-4 and text-embedding-ada-002 models
- **Azure AI Foundry** workspace for AI orchestration and agent management
- **Azure Functions** for serverless API processing and personalization logic
- **Azure Storage Account** for function app hosting requirements

## Available Implementations

- **Bicep**: Azure native infrastructure as code (declarative ARM template language)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Bash Scripts**: Deployment and cleanup automation scripts

## Prerequisites

### General Requirements
- Azure subscription with appropriate permissions for all required services
- Azure CLI installed and configured (version 2.60.0 or later)
- Access to Azure AI Foundry preview features (if not available, some components may be limited)
- Access to Azure OpenAI Service (requires application approval)
- Permissions to create Cognitive Services, Cosmos DB, Functions, and Storage accounts

### Service-Specific Prerequisites
- **Azure OpenAI**: Approved access to Azure OpenAI Service
- **Azure AI Foundry**: Preview access for AI Foundry workspace features
- **Azure Cosmos DB**: Vector search capabilities (generally available)
- **Azure Functions**: Premium or Consumption plan permissions

### Cost Considerations
- **Estimated cost**: $50-100 for moderate usage testing (varies by region)
- **Azure OpenAI**: Pay-per-token usage for GPT-4 and embedding models
- **Cosmos DB**: RU/s consumption for database operations and vector search
- **Azure Functions**: Consumption plan scales with usage
- **Storage Account**: Minimal cost for function hosting

> **Important**: This recipe uses Azure AI Foundry's agent service and vector search capabilities in Cosmos DB. Ensure your subscription has access to these preview features and review pricing for Azure OpenAI usage before deployment.

## Quick Start

### Using Bicep

```bash
# Set deployment parameters
export LOCATION="eastus"
export DEPLOYMENT_NAME="personalization-$(date +%s)"
export RESOURCE_GROUP="rg-personalization-demo"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file bicep/main.bicep \
    --parameters location=${LOCATION} \
    --name ${DEPLOYMENT_NAME}

# Get deployment outputs
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DEPLOYMENT_NAME} \
    --query properties.outputs
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review deployment plan
terraform plan \
    -var="location=eastus" \
    -var="resource_group_name=rg-personalization-demo"

# Apply infrastructure
terraform apply \
    -var="location=eastus" \
    -var="resource_group_name=rg-personalization-demo"

# View important outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables (optional, script will prompt if not set)
export LOCATION="eastus"
export RESOURCE_GROUP="rg-personalization-demo"

# Deploy infrastructure
./scripts/deploy.sh

# The script will output connection details and endpoints
```

## Configuration Options

### Bicep Parameters

The Bicep template supports the following parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `resourceGroup().location` | Azure region for deployment |
| `projectName` | string | `personalization` | Base name for resources |
| `cosmosDbThroughput` | int | `400` | Cosmos DB container throughput (RU/s) |
| `functionAppPlan` | string | `Y1` | Functions hosting plan (Y1=Consumption) |
| `openAISkuName` | string | `S0` | Azure OpenAI service tier |
| `deploymentSuffix` | string | `[uniqueString(resourceGroup().id)]` | Unique suffix for resource names |

### Terraform Variables

The Terraform configuration supports these variables:

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `location` | string | `"eastus"` | Azure region for deployment |
| `resource_group_name` | string | | Name of the resource group |
| `project_name` | string | `"personalization"` | Base name for resources |
| `cosmos_throughput` | number | `400` | Cosmos DB RU/s throughput |
| `openai_sku` | string | `"S0"` | Azure OpenAI service SKU |
| `tags` | map(string) | `{}` | Resource tags |

### Environment Variables for Bash Scripts

The deployment script recognizes these environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `LOCATION` | Azure region | `eastus` |
| `RESOURCE_GROUP` | Resource group name | Generated with timestamp |
| `PROJECT_NAME` | Base name for resources | `personalization` |
| `COSMOS_THROUGHPUT` | Cosmos DB RU/s | `400` |
| `OPENAI_SKU` | OpenAI service tier | `S0` |

## Post-Deployment Configuration

After deploying the infrastructure, additional configuration is required:

### 1. Configure Vector Search Index

The Cosmos DB containers require vector search indexing configuration:

```bash
# Get Cosmos DB account name from deployment outputs
COSMOS_ACCOUNT="<your-cosmos-account-name>"
RESOURCE_GROUP="<your-resource-group>"

# Apply vector search index policy
az cosmosdb sql container update \
    --account-name ${COSMOS_ACCOUNT} \
    --resource-group ${RESOURCE_GROUP} \
    --database-name PersonalizationDB \
    --name ContentItems \
    --idx @vector-index-policy.json
```

### 2. Deploy Function Code

The Azure Functions app requires code deployment:

```bash
# Get Function App name from deployment outputs
FUNCTION_APP="<your-function-app-name>"

# Deploy the personalization function code
az functionapp deployment source config-zip \
    --name ${FUNCTION_APP} \
    --resource-group ${RESOURCE_GROUP} \
    --src personalization-function.zip
```

### 3. Configure AI Foundry Connections

Set up connections between AI Foundry and other services:

```bash
# Configure AI Foundry workspace connections
# This typically requires using the AI Foundry Studio portal
# or Azure ML CLI for advanced configuration
```

## Validation and Testing

### Verify Deployment

```bash
# Check all resource deployment status
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DEPLOYMENT_NAME} \
    --query properties.provisioningState

# Verify Cosmos DB vector search capabilities
az cosmosdb sql container show \
    --account-name ${COSMOS_ACCOUNT} \
    --resource-group ${RESOURCE_GROUP} \
    --database-name PersonalizationDB \
    --name ContentItems \
    --query indexingPolicy.vectorIndexes

# Check OpenAI model deployments
az cognitiveservices account deployment list \
    --name ${OPENAI_SERVICE} \
    --resource-group ${RESOURCE_GROUP} \
    --output table
```

### Test Personalization API

```bash
# Get Function App URL and key
FUNCTION_URL=$(az functionapp function show \
    --name ${FUNCTION_APP} \
    --resource-group ${RESOURCE_GROUP} \
    --function-name personalization-function \
    --query invokeUrlTemplate \
    --output tsv)

FUNCTION_KEY=$(az functionapp keys list \
    --name ${FUNCTION_APP} \
    --resource-group ${RESOURCE_GROUP} \
    --query functionKeys.default \
    --output tsv)

# Test the API endpoint
curl -X GET "${FUNCTION_URL}?userId=test-user&code=${FUNCTION_KEY}" \
     -H "Content-Type: application/json"
```

Expected response:
```json
{
  "userId": "test-user",
  "recommendations": [
    {
      "contentId": "article_001",
      "title": "Personalized Content Title",
      "type": "article",
      "confidence": 0.95
    }
  ],
  "status": "success"
}
```

## Monitoring and Observability

### Application Insights Integration

The deployment includes Application Insights for monitoring:

```bash
# View Function App logs
az monitor app-insights query \
    --app ${APPLICATION_INSIGHTS_NAME} \
    --analytics-query "traces | where cloud_RoleName == '${FUNCTION_APP}' | order by timestamp desc | limit 50"

# Monitor OpenAI API usage
az monitor metrics list \
    --resource ${OPENAI_SERVICE} \
    --metric "TotalTokens" \
    --interval PT1H
```

### Cost Management

Monitor deployment costs:

```bash
# View resource costs by resource group
az consumption usage list \
    --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
    --start-date $(date -d '30 days ago' +%Y-%m-%d) \
    --end-date $(date +%Y-%m-%d)
```

## Troubleshooting

### Common Issues

1. **Azure OpenAI Access Denied**
   - Ensure you have applied for and received access to Azure OpenAI Service
   - Check that the selected region supports Azure OpenAI

2. **AI Foundry Preview Features**
   - Some AI Foundry features may be in preview and require special access
   - Consider using Azure ML workspace as an alternative for basic functionality

3. **Cosmos DB Vector Search**
   - Vector search may take time to initialize after container creation
   - Verify the vector index configuration is correctly applied

4. **Function App Cold Start**
   - Initial function calls may experience cold start delays
   - Consider using Premium hosting plan for production workloads

### Debug Commands

```bash
# Check deployment logs
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DEPLOYMENT_NAME} \
    --query properties.error

# View Function App logs
az functionapp log tail \
    --name ${FUNCTION_APP} \
    --resource-group ${RESOURCE_GROUP}

# Check OpenAI service status
az cognitiveservices account show \
    --name ${OPENAI_SERVICE} \
    --resource-group ${RESOURCE_GROUP} \
    --query properties.provisioningState
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait

echo "Resource group deletion initiated. This may take several minutes."
```

### Using Terraform

```bash
cd terraform/

# Destroy all managed resources
terraform destroy \
    -var="location=eastus" \
    -var="resource_group_name=rg-personalization-demo"

# Clean up Terraform state
rm -rf .terraform/
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deletion
```

### Manual Cleanup Verification

```bash
# Verify resource group deletion
az group show --name ${RESOURCE_GROUP} 2>/dev/null || echo "Resource group successfully deleted"

# Clear local environment variables
unset RESOURCE_GROUP LOCATION PROJECT_NAME DEPLOYMENT_NAME
```

## Security Considerations

### Secrets Management

- All sensitive values (API keys, connection strings) are stored in Azure Key Vault or Function App settings
- Service-to-service authentication uses managed identities where possible
- Vector search data is encrypted at rest in Cosmos DB

### Network Security

- Consider implementing private endpoints for production deployments
- Use Azure API Management for external API access control
- Enable Cosmos DB firewall rules to restrict access

### Access Control

- Apply least privilege principles for all service connections
- Use Azure RBAC for fine-grained access control
- Enable audit logging for compliance requirements

## Performance Optimization

### Cosmos DB Optimization

- Monitor RU/s consumption and adjust throughput based on usage patterns
- Use appropriate partition keys for even distribution
- Consider autoscale for variable workloads

### Function App Optimization

- Use Premium hosting plan for consistent performance
- Implement connection pooling for database connections
- Cache frequently accessed data to reduce latency

### AI Model Optimization

- Monitor token usage to optimize costs
- Use appropriate model versions for your use case
- Implement request throttling to manage API limits

## Support and Documentation

### Azure Documentation Links

- [Azure AI Foundry documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/)
- [Azure Cosmos DB vector search guide](https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/vector-search)
- [Azure OpenAI Service documentation](https://learn.microsoft.com/en-us/azure/ai-services/openai/)
- [Azure Functions Python developer guide](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-python)
- [Azure Well-Architected Framework for AI workloads](https://learn.microsoft.com/en-us/azure/well-architected/ai/)

### Recipe Documentation

For detailed implementation guidance, refer to the original recipe documentation at:
`../content-personalization-ai-foundry-cosmos.md`

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Azure service status pages
3. Consult the official Azure documentation
4. Open an issue in the recipe repository

## License

This infrastructure code is provided as part of the Azure Cloud Recipes collection. Please refer to the main repository license for usage terms.