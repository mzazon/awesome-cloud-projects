# Infrastructure as Code for Smart Writing Feedback System with OpenAI and Cosmos

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Writing Feedback System with OpenAI and Cosmos".

## Solution Overview

This solution creates an intelligent writing assistant that analyzes content for tone, clarity, readability, and sentiment using Azure OpenAI Service, with Azure Cosmos DB for storing detailed feedback and improvement tracking data, and Azure Functions orchestrating the serverless processing workflow.

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure includes:
- Azure OpenAI Service with GPT-4 model deployment
- Azure Cosmos DB with NoSQL API for feedback storage
- Azure Functions App with consumption plan
- Azure Storage Account for Functions runtime
- Application settings and secure configuration

## Prerequisites

### General Requirements
- Azure subscription with appropriate permissions
- Azure CLI installed and configured (version 2.51.0 or later)
- Basic understanding of serverless architecture and REST APIs
- Estimated cost: $15-25 per month for development/testing workloads

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension installed
- PowerShell or Bash shell

#### For Terraform
- Terraform installed (version 1.0 or later)
- Azure CLI authentication configured

#### For Bash Scripts
- Bash shell environment
- curl and jq utilities installed
- OpenSSL for random string generation

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Login to Azure
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Create resource group
az group create --name "rg-writing-feedback" --location "eastus"

# Deploy infrastructure
az deployment group create \
    --resource-group "rg-writing-feedback" \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters resourceSuffix=$(openssl rand -hex 3)

# Get deployment outputs
az deployment group show \
    --resource-group "rg-writing-feedback" \
    --name "main" \
    --query "properties.outputs"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="location=eastus" -var="resource_suffix=$(openssl rand -hex 3)"

# Apply infrastructure
terraform apply -var="location=eastus" -var="resource_suffix=$(openssl rand -hex 3)"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh

# View deployment results
echo "Check Azure portal for created resources"
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for resources | `eastus` | Yes |
| `resourceSuffix` | Unique suffix for resource names | Generated | No |
| `openaiSku` | Azure OpenAI service SKU | `S0` | No |
| `cosmosDbThroughput` | Cosmos DB throughput (RU/s) | `400` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for resources | `eastus` | Yes |
| `resource_suffix` | Unique suffix for resource names | Generated | No |
| `resource_group_name` | Resource group name | `rg-writing-feedback-{suffix}` | No |
| `openai_sku` | Azure OpenAI service SKU | `S0` | No |
| `cosmos_throughput` | Cosmos DB throughput (RU/s) | `400` | No |

## Post-Deployment Configuration

### Deploy Function Code

After infrastructure deployment, you'll need to deploy the writing analysis function:

1. **Create function project structure**:
   ```bash
   mkdir writing-feedback-function
   cd writing-feedback-function
   ```

2. **Create package.json**:
   ```json
   {
     "name": "writing-feedback-function",
     "version": "1.0.0",
     "dependencies": {
       "@azure/functions": "^4.5.0",
       "@azure/cosmos": "^4.1.1",
       "axios": "^1.7.0"
     }
   }
   ```

3. **Deploy function code**:
   ```bash
   # Get function app name from deployment outputs
   FUNCTION_APP_NAME="your-function-app-name"
   
   # Deploy using Azure Functions Core Tools
   func azure functionapp publish $FUNCTION_APP_NAME
   ```

### Test the Deployment

1. **Get function URL and key**:
   ```bash
   FUNCTION_URL=$(az functionapp function show \
       --name $FUNCTION_APP_NAME \
       --resource-group "rg-writing-feedback" \
       --function-name analyzeWriting \
       --query "invokeUrlTemplate" --output tsv)
   
   FUNCTION_KEY=$(az functionapp keys list \
       --name $FUNCTION_APP_NAME \
       --resource-group "rg-writing-feedback" \
       --query "functionKeys.default" --output tsv)
   ```

2. **Test with sample request**:
   ```bash
   curl -X POST "${FUNCTION_URL}?code=${FUNCTION_KEY}" \
       -H "Content-Type: application/json" \
       -d '{
         "text": "This is a sample text for analysis. The writing quality should be evaluated for tone, clarity, and sentiment.",
         "userId": "test-user-001",
         "documentId": "sample-doc-001"
       }'
   ```

## Monitoring and Troubleshooting

### View Function Logs

```bash
# Stream function logs in real-time
az webapp log tail --name $FUNCTION_APP_NAME --resource-group "rg-writing-feedback"

# View Application Insights data
az monitor app-insights query \
    --app "your-app-insights-name" \
    --analytics-query "requests | limit 10"
```

### Common Issues

1. **OpenAI Model Deployment Timeout**:
   - Model deployment can take 5-10 minutes
   - Check deployment status in Azure portal

2. **Function App Cold Start**:
   - First request may take longer due to cold start
   - Consider using Premium plan for production

3. **Cosmos DB Connection Issues**:
   - Verify firewall settings allow Azure services
   - Check connection strings in application settings

## Security Considerations

- All sensitive configuration is stored in Azure Key Vault or Function App settings
- Cosmos DB uses managed identity where possible
- OpenAI endpoints are secured with API keys
- Network security groups restrict access to necessary ports only
- All data is encrypted at rest and in transit

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name "rg-writing-feedback" --yes --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Cost Optimization

### Development Environment
- Use consumption plan for Functions (pay-per-execution)
- Set Cosmos DB to minimum throughput (400 RU/s)
- Use S0 tier for OpenAI service
- Estimated monthly cost: $15-25

### Production Environment
- Consider Premium Functions plan for consistent performance
- Scale Cosmos DB throughput based on usage patterns
- Monitor OpenAI token usage and implement caching
- Estimated monthly cost: $50-150 (varies by usage)

## Customization

### Modify OpenAI Analysis Prompts

Edit the function code to customize writing analysis criteria:

```javascript
// Modify the prompt in src/index.js
const prompt = `Your custom analysis prompt here...`;
```

### Add Custom Feedback Metrics

Extend the Cosmos DB schema to include additional metrics:

```javascript
const feedbackDoc = {
    // ... existing fields
    customMetrics: {
        industrySpecific: analysis.industryScore,
        brandVoice: analysis.brandAlignment
    }
};
```

### Configure Scaling Policies

For production deployments, consider:

- Auto-scaling policies for Function Apps
- Cosmos DB autoscale for variable workloads
- Application Insights for monitoring and alerting

## Support and Documentation

- [Azure OpenAI Service Documentation](https://docs.microsoft.com/en-us/azure/ai-services/openai/)
- [Azure Cosmos DB Documentation](https://docs.microsoft.com/en-us/azure/cosmos-db/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Contributing

When modifying the infrastructure:

1. Update both Bicep and Terraform implementations
2. Test deployments in development environment
3. Update documentation and parameter descriptions
4. Validate security configurations
5. Update cost estimates if resource changes impact pricing

For issues with this infrastructure code, refer to the original recipe documentation or the relevant Azure service documentation.