# Infrastructure as Code for Automated Content Generation with Prompt Flow and OpenAI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Content Generation with Prompt Flow and OpenAI".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (Microsoft's recommended approach)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts for automated resource management

## Prerequisites

### Common Requirements
- Azure CLI installed and configured (version 2.60.0 or later)
- Azure subscription with appropriate permissions for:
  - Azure Machine Learning workspace creation
  - Azure OpenAI Service deployment (requires approval)
  - Azure Functions deployment
  - Cosmos DB account creation
  - Storage account creation and management
- Basic understanding of prompt engineering and serverless architectures

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension installed
- PowerShell or Bash terminal

#### For Terraform
- Terraform installed (version 1.5+ recommended)
- Azure provider configured
- Service principal or managed identity for authentication

#### For Bash Scripts
- Standard Unix/Linux tools (curl, jq, openssl)
- Sufficient permissions for resource creation and management

### Service Availability Notes
- Azure OpenAI Service requires approval and may not be available in all regions
- GPT-4o models offer the latest capabilities for content generation tasks
- Estimated cost: $20-30 for completing this deployment

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Create resource group
az group create \
    --name rg-content-gen-demo \
    --location eastus

# Deploy infrastructure
az deployment group create \
    --resource-group rg-content-gen-demo \
    --template-file main.bicep \
    --parameters projectName=contentgen \
                 location=eastus \
                 openaiModelDeployments='["gpt-4o-content", "text-embedding-ada-002"]'

# Get deployment outputs
az deployment group show \
    --resource-group rg-content-gen-demo \
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
terraform plan -var="project_name=contentgen" -var="location=eastus"

# Apply infrastructure
terraform apply -var="project_name=contentgen" -var="location=eastus"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP_NAME="rg-content-gen-demo"
export LOCATION="eastus"
export PROJECT_NAME="contentgen"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
./scripts/verify-deployment.sh
```

## Architecture Overview

This infrastructure deploys a complete automated content generation system including:

- **Azure Machine Learning Workspace**: Provides the foundation for Azure AI Prompt Flow
- **Azure OpenAI Service**: Hosts GPT-4o and text embedding models for content generation
- **Azure Functions**: Serverless compute for orchestrating content generation workflows
- **Cosmos DB**: NoSQL database for storing content metadata and campaign tracking
- **Storage Account**: Blob storage for content templates and generated output
- **Application Insights**: Monitoring and telemetry for the serverless application

## Configuration Options

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `projectName` | string | - | Unique project name used for resource naming |
| `location` | string | `eastus` | Azure region for resource deployment |
| `openaiSku` | string | `S0` | Azure OpenAI service tier |
| `functionAppSku` | string | `Y1` | Functions consumption plan tier |
| `cosmosDbThroughput` | int | `400` | Cosmos DB provisioned throughput (RU/s) |
| `openaiModelDeployments` | array | See template | List of AI models to deploy |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `project_name` | string | - | Unique project name for resource naming |
| `location` | string | `East US` | Azure region for deployment |
| `resource_group_name` | string | Generated | Override default resource group name |
| `openai_sku_name` | string | `S0` | Azure OpenAI service pricing tier |
| `function_sku_tier` | string | `Dynamic` | Functions hosting plan tier |
| `cosmos_throughput` | number | `400` | Cosmos DB provisioned RU/s |
| `enable_monitoring` | bool | `true` | Enable Application Insights monitoring |

### Environment Variables (Bash Scripts)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `RESOURCE_GROUP_NAME` | Yes | - | Target resource group name |
| `LOCATION` | Yes | `eastus` | Azure deployment region |
| `PROJECT_NAME` | Yes | - | Project identifier for resource naming |
| `OPENAI_SKU` | No | `S0` | Azure OpenAI service tier |
| `COSMOS_THROUGHPUT` | No | `400` | Cosmos DB throughput setting |

## Post-Deployment Setup

### 1. Configure Prompt Flow Connection

```bash
# Get OpenAI endpoint and key from deployment outputs
OPENAI_ENDPOINT=$(az cognitiveservices account show \
    --name "aoai-${PROJECT_NAME}-${RANDOM_SUFFIX}" \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --query properties.endpoint --output tsv)

# Create prompt flow connection in ML workspace
az ml connection create \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --workspace-name "ml-${PROJECT_NAME}-${RANDOM_SUFFIX}" \
    --file connection-config.yaml
```

### 2. Deploy Function Code

```bash
# Deploy function app code using Azure Functions Core Tools
func azure functionapp publish func-${PROJECT_NAME}-${RANDOM_SUFFIX}
```

### 3. Test Content Generation

```bash
# Get function URL from deployment outputs
FUNCTION_URL=$(terraform output -raw function_app_url)

# Test content generation
curl -X POST "${FUNCTION_URL}/api/ContentGenerationTrigger?code=${FUNCTION_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
      "campaign_type": "social_media",
      "target_audience": "small business owners",
      "content_tone": "professional",
      "key_messages": "Boost productivity with AI automation"
    }'
```

## Monitoring and Troubleshooting

### Application Insights Queries

```kusto
# Monitor function executions
requests
| where name contains "ContentGenerationTrigger"
| summarize Count=count(), AvgDuration=avg(duration) by bin(timestamp, 1h)

# Track content generation success rates
traces
| where message contains "Content generation"
| summarize SuccessRate=countif(severityLevel <= 2) * 100.0 / count() by bin(timestamp, 1h)
```

### Common Issues and Solutions

1. **OpenAI Service Access Denied**
   - Verify Azure OpenAI Service approval status
   - Check region availability for OpenAI service
   - Validate subscription permissions

2. **Function App Cold Start Issues**
   - Consider upgrading to Premium plan for production workloads
   - Implement warming strategies for consistent performance

3. **Cosmos DB Throttling**
   - Monitor RU consumption in Azure portal
   - Increase provisioned throughput if needed
   - Optimize query patterns and partition key selection

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-content-gen-demo \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all infrastructure
terraform destroy -var="project_name=contentgen" -var="location=eastus"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
# Script will remove all resources in correct dependency order
```

## Customization

### Adding Custom Content Templates

1. **Upload templates to Blob Storage**:
   ```bash
   az storage blob upload \
       --container-name content-templates \
       --file ./custom-template.json \
       --name templates/custom-template.json \
       --connection-string "${STORAGE_CONNECTION_STRING}"
   ```

2. **Update Prompt Flow logic** to reference new templates in content generation workflows

### Extending AI Model Capabilities

1. **Deploy additional models**:
   ```bash
   az cognitiveservices account deployment create \
       --name ${OPENAI_ACCOUNT_NAME} \
       --resource-group ${RESOURCE_GROUP_NAME} \
       --deployment-name custom-model \
       --model-name gpt-4-turbo \
       --model-version "latest"
   ```

2. **Update function code** to utilize new model capabilities for specialized content types

### Scaling for Production

1. **Upgrade Function App plan**:
   - Premium plan for consistent performance
   - Dedicated plan for predictable costs
   - Enable autoscaling based on queue length

2. **Optimize Cosmos DB**:
   - Implement hierarchical partition keys
   - Use analytical store for reporting workloads
   - Configure automatic scaling

## Security Considerations

- All resources use managed identities where possible
- OpenAI keys are stored securely in Key Vault (when deployed)
- Function app uses system-assigned managed identity
- Network access can be restricted using private endpoints
- Cosmos DB uses built-in encryption at rest
- Storage accounts implement hierarchical namespace for fine-grained access control

## Cost Optimization

- Functions use consumption plan for automatic scaling to zero
- Cosmos DB uses manual throughput (can be changed to autoscale)
- Storage uses hot tier for active content, configure lifecycle policies for archival
- OpenAI models deployed with minimum required capacity
- Application Insights sampling reduces telemetry costs

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Azure Documentation**: Check [Azure Machine Learning](https://docs.microsoft.com/en-us/azure/machine-learning/) and [Azure OpenAI](https://docs.microsoft.com/en-us/azure/cognitive-services/openai/) documentation
3. **Community Support**: Use Azure community forums and Stack Overflow
4. **Enterprise Support**: Contact Azure support for production issues

## Version Information

- **Recipe Version**: 1.1
- **Infrastructure Version**: 1.0
- **Last Updated**: 2025-07-12
- **Compatible Azure CLI**: 2.60.0+
- **Compatible Terraform**: 1.5+