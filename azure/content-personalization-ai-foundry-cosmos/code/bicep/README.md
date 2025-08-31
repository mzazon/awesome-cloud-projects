# Infrastructure as Code for Content Personalization Engine with AI Foundry and Cosmos

This directory contains Bicep Infrastructure as Code (IaC) templates for deploying the complete Content Personalization Engine solution using Azure AI Foundry, Azure Cosmos DB, Azure OpenAI, and Azure Functions.

## Architecture Overview

The solution deploys the following Azure resources:

- **Azure Cosmos DB** with vector search capabilities for user profiles and content storage
- **Azure OpenAI Service** with GPT-4 and text-embedding-ada-002 model deployments
- **Azure AI Foundry Workspace** (Machine Learning Workspace) for AI orchestration
- **Azure Functions** with Python runtime for personalization API and processing
- **Application Insights** and Log Analytics for monitoring and observability
- **Azure Storage Account** for Functions app storage requirements
- **Key Vault** for secure secrets management

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Azure CLI** installed and configured (version 2.0.81 or later)
   ```bash
   az --version
   az login
   ```

2. **Bicep CLI** installed
   ```bash
   az bicep install
   az bicep version
   ```

3. **Azure Subscription** with appropriate permissions:
   - Contributor or Owner role on the subscription
   - Access to Azure OpenAI services (may require approval)
   - Ability to create resource groups and all required resources

4. **Resource Quotas** verified for:
   - Azure OpenAI model deployments
   - Cosmos DB accounts
   - Azure Functions premium plans

5. **Regional Availability** confirmed for:
   - Azure OpenAI Service (limited regions)
   - Azure AI Foundry (Machine Learning Services)
   - Cosmos DB vector search capabilities

## Quick Start

### 1. Clone and Navigate to Directory

```bash
cd azure/content-personalization-ai-foundry-cosmos/code/bicep/
```

### 2. Review and Customize Parameters

Edit the `parameters.json` file to customize the deployment:

```bash
# Review default parameters
cat parameters.json

# Key parameters to consider:
# - location: Azure region (ensure OpenAI availability)
# - uniqueSuffix: Unique identifier for resource names
# - environment: dev, staging, or prod
# - openAiModels: Model deployment configurations
# - cosmosDbConfig: Database and container settings
```

### 3. Validate Template

```bash
# Create resource group
az group create \
    --name rg-personalization-demo \
    --location eastus

# Validate Bicep template
az deployment group validate \
    --resource-group rg-personalization-demo \
    --template-file main.bicep \
    --parameters @parameters.json
```

### 4. Deploy Infrastructure

```bash
# Deploy the complete solution
az deployment group create \
    --resource-group rg-personalization-demo \
    --template-file main.bicep \
    --parameters @parameters.json \
    --name personalization-deployment
```

### 5. Verify Deployment

```bash
# Check deployment status
az deployment group show \
    --resource-group rg-personalization-demo \
    --name personalization-deployment \
    --query properties.provisioningState

# List deployed resources
az resource list \
    --resource-group rg-personalization-demo \
    --output table
```

## Deployment Options

### Using Azure Cloud Shell

1. Upload Bicep files to Cloud Shell
2. Run deployment commands directly in the shell
3. No local setup required

### Using Azure DevOps Pipelines

```yaml
# azure-pipelines.yml example
trigger:
- main

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: AzureCLI@2
  displayName: 'Deploy Bicep Template'
  inputs:
    azureSubscription: 'your-service-connection'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: |
      az deployment group create \
        --resource-group $(resourceGroupName) \
        --template-file main.bicep \
        --parameters @parameters.json
```

### Using GitHub Actions

```yaml
# .github/workflows/deploy.yml example
name: Deploy Infrastructure

on:
  push:
    branches: [ main ]
    paths: [ 'azure/content-personalization-ai-foundry-cosmos/code/bicep/**' ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Azure Login
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Deploy Bicep Template
      run: |
        az deployment group create \
          --resource-group ${{ env.RESOURCE_GROUP_NAME }} \
          --template-file main.bicep \
          --parameters @parameters.json
```

## Configuration Options

### Environment-Specific Parameters

Create separate parameter files for different environments:

```bash
# parameters.dev.json
{
  "parameters": {
    "environment": { "value": "dev" },
    "cosmosDbConfig": {
      "value": {
        "containers": [
          {
            "name": "UserProfiles",
            "partitionKeyPath": "/userId",
            "throughput": 400
          }
        ]
      }
    }
  }
}

# parameters.prod.json
{
  "parameters": {
    "environment": { "value": "prod" },
    "cosmosDbConfig": {
      "value": {
        "containers": [
          {
            "name": "UserProfiles",
            "partitionKeyPath": "/userId",
            "throughput": 1000
          }
        ]
      }
    }
  }
}
```

### OpenAI Model Customization

Adjust model deployments based on requirements:

```json
{
  "openAiModels": {
    "value": {
      "gpt4": {
        "name": "gpt-4-content",
        "modelName": "gpt-4",
        "modelVersion": "0613",
        "skuCapacity": 20
      },
      "embedding": {
        "name": "text-embedding",
        "modelName": "text-embedding-ada-002",
        "modelVersion": "2",
        "skuCapacity": 30
      }
    }
  }
}
```

### Security Hardening

For production deployments, consider these security enhancements:

1. **Network Isolation**
   - Configure private endpoints for Cosmos DB
   - Restrict Function App to VNet integration
   - Use Azure Firewall for egress control

2. **Identity and Access Management**
   - Enable Managed Identity authentication
   - Implement least privilege RBAC
   - Use Azure Key Vault references for secrets

3. **Monitoring and Compliance**
   - Enable diagnostic settings
   - Configure security alerts
   - Implement compliance policies

## Monitoring and Observability

The template includes comprehensive monitoring setup:

### Application Insights

- Automatic instrumentation for Azure Functions
- Custom metrics and logging
- Performance monitoring and alerting

### Log Analytics

- Centralized logging for all resources
- Custom queries and dashboards
- Integration with Azure Monitor

### Cosmos DB Monitoring

- Built-in metrics for throughput and latency
- Query performance insights
- Vector search operation tracking

## Cost Optimization

### Resource Sizing Recommendations

| Environment | Cosmos DB RU/s | OpenAI Capacity | Function Plan |
|-------------|----------------|-----------------|---------------|
| Development | 400 RU/s | 10 TPM | Consumption |
| Staging | 1000 RU/s | 20 TPM | Premium EP1 |
| Production | 4000+ RU/s | 50+ TPM | Premium EP2+ |

### Cost Management Features

- Cosmos DB autoscale capability
- Function App consumption-based billing
- OpenAI pay-per-token pricing
- Resource tagging for cost allocation

## Troubleshooting

### Common Deployment Issues

1. **OpenAI Service Unavailable**
   ```bash
   # Check region availability
   az cognitiveservices account list-skus \
       --location eastus \
       --resource-type OpenAI
   ```

2. **Insufficient Quotas**
   ```bash
   # Check current quotas
   az vm list-usage --location eastus
   ```

3. **Permission Errors**
   ```bash
   # Verify role assignments
   az role assignment list --assignee $(az account show --query user.name -o tsv)
   ```

### Deployment Validation

```bash
# Test Cosmos DB connectivity
az cosmosdb show \
    --name cosmos-personalization-demo01 \
    --resource-group rg-personalization-demo

# Verify OpenAI model deployments
az cognitiveservices account deployment list \
    --name openai-personalization-demo01 \
    --resource-group rg-personalization-demo

# Check Function App status
az functionapp show \
    --name func-personalization-demo01 \
    --resource-group rg-personalization-demo \
    --query state
```

## Cleanup

To remove all deployed resources:

```bash
# Delete the entire resource group
az group delete \
    --name rg-personalization-demo \
    --yes \
    --no-wait

# Verify deletion
az group exists --name rg-personalization-demo
```

## Module Documentation

Each Bicep module is documented with:

- **Parameters**: All configurable options
- **Resources**: Azure resources created
- **Outputs**: Values returned for integration
- **Dependencies**: Required resources and order

### Module Structure

```
modules/
├── storage.bicep              # Storage Account for Functions
├── log-analytics.bicep        # Log Analytics Workspace
├── application-insights.bicep # Application monitoring
├── cosmos-db.bicep           # Cosmos DB with vector search
├── openai.bicep              # Azure OpenAI Service
├── ai-foundry.bicep          # AI Foundry Workspace
├── app-service-plan.bicep    # App Service Plan
└── function-app.bicep        # Azure Functions App
```

## Support and Resources

- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure OpenAI Service Documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/openai/)
- [Azure Cosmos DB Vector Search Guide](https://docs.microsoft.com/en-us/azure/cosmos-db/nosql/vector-search)
- [Azure AI Foundry Documentation](https://docs.microsoft.com/en-us/azure/machine-learning/)
- [Azure Functions Python Developer Guide](https://docs.microsoft.com/en-us/azure/azure-functions/functions-reference-python)

For issues with this infrastructure code, refer to the original recipe documentation or open an issue in the repository.

## Version History

- **v1.0**: Initial Bicep template with all core resources
- **v1.1**: Added comprehensive monitoring and security features
- **v1.2**: Enhanced vector search configuration and model deployment options

---

**Note**: This infrastructure code is designed to work with the Content Personalization Engine recipe. Ensure you follow the complete recipe implementation guide for the full solution deployment.