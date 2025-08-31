# Infrastructure as Code for Text Sentiment Analysis with Cognitive Services

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Text Sentiment Analysis with Cognitive Services".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.55.0 or later)
- Azure Functions Core Tools (version 4.x) for local development
- Appropriate Azure permissions for creating:
  - Resource Groups
  - Cognitive Services (Language API)
  - Storage Accounts
  - Function Apps
  - Application Settings
- Basic understanding of serverless computing and REST APIs
- Estimated cost: $0.50-$2.00 for testing (includes Function App consumption plan and Language API calls)

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension (included by default in Azure CLI 2.20.0+)

#### For Terraform
- Terraform installed (version 1.0 or later)
- Azure Provider for Terraform

## Architecture Overview

This solution creates:
- **Azure Cognitive Services Language API**: For advanced sentiment analysis with confidence scores
- **Azure Function App**: Serverless HTTP-triggered function for processing requests
- **Azure Storage Account**: Required for Function App runtime and metadata
- **Resource Group**: Container for all resources

## Quick Start

### Using Bicep (Recommended)

```bash
# Set deployment parameters
export RESOURCE_GROUP="rg-sentiment-$(openssl rand -hex 3)"
export LOCATION="eastus"
export APP_NAME_SUFFIX=$(openssl rand -hex 3)

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file bicep/main.bicep \
    --parameters \
        location=${LOCATION} \
        appNameSuffix=${APP_NAME_SUFFIX}

# Get deployment outputs
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Set variables (optional - defaults will be used)
export TF_VAR_location="eastus"
export TF_VAR_app_name_suffix="$(openssl rand -hex 3)"

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for configuration or use environment variables:
# - AZURE_LOCATION (default: eastus)
# - APP_NAME_SUFFIX (auto-generated if not set)
```

## Function Deployment

After infrastructure deployment, deploy the sentiment analysis function:

```bash
# Set environment variables from infrastructure outputs
export FUNCTION_APP_NAME="func-sentiment-${APP_NAME_SUFFIX}"
export RESOURCE_GROUP="rg-sentiment-${APP_NAME_SUFFIX}"

# Create local function project
mkdir sentiment-function && cd sentiment-function
func init --worker-runtime python --model V2
func new --name analyze_sentiment --template "HTTP trigger"

# Deploy function code (requires function code from recipe)
func azure functionapp publish ${FUNCTION_APP_NAME}

# Get function URL
az functionapp function show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${FUNCTION_APP_NAME} \
    --function-name analyze_sentiment \
    --query invokeUrlTemplate \
    --output tsv
```

## Testing the Deployment

Once deployed, test the sentiment analysis API:

```bash
# Get function URL from outputs
FUNCTION_URL=$(terraform output -raw function_url)  # For Terraform
# OR
FUNCTION_URL=$(az deployment group show --resource-group ${RESOURCE_GROUP} --name main --query properties.outputs.functionUrl.value -o tsv)  # For Bicep

# Test positive sentiment
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{
        "text": "I absolutely love this product! The quality is outstanding."
    }'

# Test negative sentiment
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{
        "text": "This service is terrible. Very disappointed with the quality."
    }'
```

## Configuration Options

### Bicep Parameters

- `location`: Azure region for deployment (default: "eastus")
- `appNameSuffix`: Suffix for resource names (default: auto-generated)
- `languageServiceSku`: Cognitive Services pricing tier (default: "S0")
- `storageAccountType`: Storage replication type (default: "Standard_LRS")

### Terraform Variables

- `location`: Azure region for deployment
- `app_name_suffix`: Suffix for resource names
- `language_service_sku`: Cognitive Services pricing tier
- `storage_account_type`: Storage replication type
- `tags`: Resource tags for organization and billing

### Environment Variables for Scripts

- `AZURE_LOCATION`: Deployment region
- `APP_NAME_SUFFIX`: Resource naming suffix
- `RESOURCE_GROUP`: Target resource group name

## Outputs

All implementations provide these outputs:

- `resource_group_name`: Name of the created resource group
- `language_service_endpoint`: Cognitive Services Language API endpoint
- `function_app_name`: Name of the created Function App
- `function_url`: HTTP trigger URL for the sentiment analysis function
- `storage_account_name`: Name of the created storage account

## Cleanup

### Using Bicep

```bash
# Delete resource group (removes all resources)
az group delete \
    --name ${RESOURCE_GROUP} \
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
./scripts/destroy.sh

# Or manually delete resource group
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait
```

## Customization

### Scaling Configuration

Modify the Function App configuration to adjust scaling:

```bash
# Set maximum scale-out limit
az functionapp config appsettings set \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --settings "FUNCTIONS_WORKER_PROCESS_COUNT=4"
```

### Security Enhancements

1. **Enable Function App authentication**:
   ```bash
   az webapp auth update \
       --name ${FUNCTION_APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --enabled true
   ```

2. **Configure Key Vault integration** (modify IaC templates):
   - Store Language API key in Key Vault
   - Use managed identity for secure access

3. **Network isolation**:
   - Deploy Function App in VNet
   - Use Private Endpoints for Cognitive Services

### Monitoring Setup

```bash
# Enable Application Insights
az monitor app-insights component create \
    --app ${FUNCTION_APP_NAME}-insights \
    --location ${LOCATION} \
    --resource-group ${RESOURCE_GROUP}

# Link to Function App
INSTRUMENTATION_KEY=$(az monitor app-insights component show \
    --app ${FUNCTION_APP_NAME}-insights \
    --resource-group ${RESOURCE_GROUP} \
    --query instrumentationKey \
    --output tsv)

az functionapp config appsettings set \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --settings "APPINSIGHTS_INSTRUMENTATIONKEY=${INSTRUMENTATION_KEY}"
```

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   - Verify Azure CLI is logged in: `az account show`
   - Check Function App status: `az functionapp show --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP}`

2. **API returns authentication errors**:
   - Verify Language service key in Function App settings
   - Check endpoint URL format in configuration

3. **Sentiment analysis returns errors**:
   - Validate input JSON format
   - Check Function App logs: `az functionapp logs tail --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP}`

### Debug Commands

```bash
# Check resource status
az resource list --resource-group ${RESOURCE_GROUP} --output table

# View Function App logs
az functionapp logs tail \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP}

# Test Language service directly
az cognitiveservices account list-usage \
    --name ${LANGUAGE_SERVICE_NAME} \
    --resource-group ${RESOURCE_GROUP}
```

## Cost Optimization

- **Function App**: Consumption plan charges only for execution time
- **Language API**: 5,000 free transactions per month, then pay-per-use
- **Storage**: Minimal cost for Function App metadata storage
- **Total estimated cost**: $0.50-$2.00 for typical testing scenarios

### Cost Monitoring

```bash
# Set up budget alerts
az consumption budget create \
    --budget-name "sentiment-analysis-budget" \
    --amount 10 \
    --time-grain Monthly \
    --time-period start-date=$(date +%Y-%m-01) \
    --resource-group ${RESOURCE_GROUP}
```

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check Azure documentation for specific services
3. Review Function App and Cognitive Services troubleshooting guides
4. Use Azure CLI help: `az functionapp --help` or `az cognitiveservices --help`

## Security Considerations

- Language API keys are stored as Function App application settings
- Function App uses anonymous authentication (modify for production use)
- All resources use Azure's managed security features
- Consider implementing API rate limiting for production deployments
- Regular key rotation recommended for production environments

## Next Steps

1. **Implement authentication**: Add Azure AD authentication to the Function App
2. **Add monitoring**: Integrate with Application Insights for detailed analytics
3. **Scale testing**: Test with high-volume text processing scenarios
4. **Multi-language support**: Extend function to handle multiple languages
5. **Batch processing**: Add support for analyzing multiple texts in one request