# Infrastructure as Code for Voice-to-Multilingual Content Pipeline with Speech and OpenAI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Voice-to-Multilingual Content Pipeline with Speech and OpenAI".

## Available Implementations

- **Bicep**: Microsoft's recommended infrastructure as code language for Azure
- **Terraform**: Multi-cloud infrastructure as code using Azure Provider
- **Scripts**: Bash deployment and cleanup scripts for automated resource management

## Prerequisites

- Azure CLI installed and configured (`az --version` should show 2.50.0 or later)
- Azure subscription with sufficient permissions for:
  - Resource Group creation and management
  - Storage Account creation and blob container management
  - Cognitive Services deployment (Speech, OpenAI, Translator)
  - Azure Functions App deployment and configuration
- Azure OpenAI Service access (requires separate application approval at https://aka.ms/oaiapply)
- Terraform installed (version 1.5.0 or later) if using Terraform implementation
- Appropriate Azure RBAC permissions:
  - Contributor role on subscription or resource group
  - Cognitive Services Contributor role for AI services

## Architecture Overview

This infrastructure deploys a serverless voice-to-multilingual content pipeline with the following components:

- **Azure Storage Account**: Blob storage with containers for audio input and content output
- **Azure Speech Service**: Enterprise-grade speech-to-text transcription with multi-language support
- **Azure OpenAI Service**: GPT-4 powered content enhancement and intelligent text processing
- **Azure Translator**: Neural machine translation for multilingual content generation
- **Azure Functions**: Serverless orchestration and event-driven processing pipeline

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-voice-pipeline-demo" \
    --template-file main.bicep \
    --parameters \
        location="eastus" \
        uniqueSuffix="$(openssl rand -hex 3)" \
        targetLanguages="es,fr,de,ja,pt"

# Get deployment outputs
az deployment group show \
    --resource-group "rg-voice-pipeline-demo" \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan \
    -var="location=eastus" \
    -var="resource_group_name=rg-voice-pipeline-demo" \
    -var="target_languages=[\"es\",\"fr\",\"de\",\"ja\",\"pt\"]"

# Deploy infrastructure
terraform apply \
    -var="location=eastus" \
    -var="resource_group_name=rg-voice-pipeline-demo" \
    -var="target_languages=[\"es\",\"fr\",\"de\",\"ja\",\"pt\"]"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set deployment parameters
export AZURE_LOCATION="eastus"
export RESOURCE_GROUP_NAME="rg-voice-pipeline-demo"
export TARGET_LANGUAGES="es,fr,de,ja,pt"

# Deploy infrastructure
./deploy.sh

# View deployment status
az group show --name ${RESOURCE_GROUP_NAME} --query properties.provisioningState
```

## Configuration Options

### Bicep Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `location` | string | Azure region for deployment | `eastus` |
| `uniqueSuffix` | string | Suffix for unique resource naming | `[uniqueString(resourceGroup().id)]` |
| `targetLanguages` | string | Comma-separated target languages | `es,fr,de,ja,pt` |
| `speechServiceSku` | string | Speech service pricing tier | `S0` |
| `openaiServiceSku` | string | OpenAI service pricing tier | `S0` |
| `translatorServiceSku` | string | Translator service pricing tier | `S1` |
| `storageAccountSku` | string | Storage account replication type | `Standard_LRS` |

### Terraform Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `location` | string | Azure region for deployment | `eastus` |
| `resource_group_name` | string | Resource group name | `rg-voice-pipeline` |
| `unique_suffix` | string | Suffix for unique resource naming | `random` |
| `target_languages` | list(string) | List of target languages | `["es","fr","de","ja","pt"]` |
| `speech_service_sku` | string | Speech service pricing tier | `S0` |
| `openai_service_sku` | string | OpenAI service pricing tier | `S0` |
| `translator_service_sku` | string | Translator service pricing tier | `S1` |
| `storage_account_sku` | string | Storage account replication type | `Standard_LRS` |

### Environment Variables (Bash Scripts)

| Variable | Description | Default |
|----------|-------------|---------|
| `AZURE_LOCATION` | Azure region for deployment | `eastus` |
| `RESOURCE_GROUP_NAME` | Resource group name | `rg-voice-pipeline-${RANDOM}` |
| `TARGET_LANGUAGES` | Comma-separated target languages | `es,fr,de,ja,pt` |
| `SPEECH_SERVICE_SKU` | Speech service pricing tier | `S0` |
| `OPENAI_SERVICE_SKU` | OpenAI service pricing tier | `S0` |
| `TRANSLATOR_SERVICE_SKU` | Translator service pricing tier | `S1` |

## Post-Deployment Steps

### 1. Deploy Function Code

After infrastructure deployment, deploy the Azure Functions processing code:

```bash
# Get function app name from deployment outputs
FUNCTION_APP_NAME=$(az functionapp list \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --query "[0].name" --output tsv)

# Create local function project (if not exists)
func init voice-pipeline-functions --python
cd voice-pipeline-functions

# Add required dependencies to requirements.txt
echo "azure-functions
azure-storage-blob
azure-cognitiveservices-speech  
openai
requests
azure-identity" > requirements.txt

# Deploy function code
func azure functionapp publish ${FUNCTION_APP_NAME}
```

### 2. Test the Pipeline

Upload a test audio file to trigger the processing pipeline:

```bash
# Get storage account name from deployment
STORAGE_ACCOUNT=$(az storage account list \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --query "[0].name" --output tsv)

# Upload test audio file
az storage blob upload \
    --file test-audio.wav \
    --container-name audio-input \
    --name "test-$(date +%s).wav" \
    --account-name ${STORAGE_ACCOUNT}

# Monitor function execution
az monitor activity-log list \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --max-events 10
```

### 3. Access Results

Processed multilingual content will be available in the output container:

```bash
# List processed content
az storage blob list \
    --container-name content-output \
    --account-name ${STORAGE_ACCOUNT} \
    --output table

# Download processed content
az storage blob download \
    --container-name content-output \
    --name "processed/your-file.json" \
    --file ./processed-content.json \
    --account-name ${STORAGE_ACCOUNT}
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all contained resources
az group delete \
    --name "rg-voice-pipeline-demo" \
    --yes \
    --no-wait

# Verify deletion
az group exists --name "rg-voice-pipeline-demo"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="location=eastus" \
    -var="resource_group_name=rg-voice-pipeline-demo"

# Verify cleanup
az group exists --name "rg-voice-pipeline-demo"
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Confirm resource group deletion
az group exists --name ${RESOURCE_GROUP_NAME}
```

## Troubleshooting

### Common Issues

1. **Azure OpenAI Service Access Denied**
   - Ensure you have been approved for Azure OpenAI Service access
   - Apply at https://aka.ms/oaiapply if not already approved
   - Check service availability in your selected region

2. **Function App Deployment Failures**
   - Verify Azure Functions Core Tools are installed (`func --version`)
   - Ensure Python 3.11 runtime is available
   - Check function app configuration and application settings

3. **Storage Access Issues**
   - Verify blob containers were created successfully
   - Check storage account access keys and connection strings
   - Ensure proper RBAC permissions for function app managed identity

4. **AI Service Authentication Errors**
   - Verify all cognitive services are deployed and active
   - Check service keys and endpoints in function app configuration
   - Ensure proper network access and firewall rules

### Diagnostic Commands

```bash
# Check resource deployment status
az deployment group list \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --query "[].{Name:name,State:properties.provisioningState}" \
    --output table

# Verify AI service endpoints
az cognitiveservices account list \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --query "[].{Name:name,Endpoint:properties.endpoint,State:properties.provisioningState}" \
    --output table

# Check function app status
az functionapp list \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --query "[].{Name:name,State:state,Runtime:linuxFxVersion}" \
    --output table

# View function app logs
az functionapp log tail \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP_NAME}
```

## Cost Optimization

### Estimated Costs (USD/month)

- **Azure Storage**: $5-15 (depending on data volume and access frequency)
- **Azure Speech Service**: $15-50 (based on audio transcription hours)
- **Azure OpenAI Service**: $20-100 (GPT-4 usage for content enhancement)
- **Azure Translator**: $10-30 (translation volume dependent)
- **Azure Functions**: $5-20 (consumption plan, execution dependent)

**Total estimated monthly cost**: $55-215 for moderate usage

### Cost Optimization Tips

1. **Use appropriate service tiers**: Start with Standard tiers and monitor usage
2. **Implement lifecycle policies**: Archive processed content to cool/archive storage tiers
3. **Monitor AI service usage**: Set up alerts for unexpected usage spikes
4. **Optimize function execution**: Use efficient processing patterns to minimize execution time
5. **Consider reserved capacity**: For predictable workloads, reserved instances can reduce costs

## Security Considerations

### Implemented Security Features

- **Managed Identity**: Function app uses system-assigned managed identity for service authentication
- **Private Endpoints**: Optional private endpoints for enhanced network security
- **Storage Security**: Blob containers configured with private access and HTTPS-only transfers
- **Key Vault Integration**: Sensitive configuration stored in Azure Key Vault (optional)
- **Network Security**: VNet integration available for enhanced isolation

### Additional Security Recommendations

1. **Enable diagnostic logging** for all services for security monitoring
2. **Implement Azure Policy** for governance and compliance
3. **Use Azure Security Center** for vulnerability assessment
4. **Configure alerts** for unusual activity patterns
5. **Regular security reviews** of access permissions and configurations

## Monitoring and Observability

### Application Insights Integration

The infrastructure includes Application Insights for comprehensive monitoring:

```bash
# View function execution metrics
az monitor app-insights metrics show \
    --app ${APPLICATION_INSIGHTS_NAME} \
    --metric "requests/count" \
    --aggregation count

# Query function logs
az monitor app-insights query \
    --app ${APPLICATION_INSIGHTS_NAME} \
    --analytics-query "traces | where message contains 'Processing audio file' | take 10"
```

### Custom Dashboards

Create custom monitoring dashboards using Azure Monitor:

1. Function execution success/failure rates
2. Audio processing duration metrics
3. AI service response times and error rates
4. Storage usage and access patterns
5. Cost tracking and optimization opportunities

## Support and Documentation

### Additional Resources

- [Azure Speech Service Documentation](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/)
- [Azure OpenAI Service Documentation](https://learn.microsoft.com/en-us/azure/ai-services/openai/)
- [Azure Translator Documentation](https://learn.microsoft.com/en-us/azure/ai-services/translator/)
- [Azure Functions Documentation](https://learn.microsoft.com/en-us/azure/azure-functions/)
- [Azure Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

### Community Support

- [Azure Functions Community](https://techcommunity.microsoft.com/t5/azure-functions/ct-p/AzureFunctions)
- [Azure AI Services Community](https://techcommunity.microsoft.com/t5/azure-ai-services/ct-p/AzureAIServices)
- [Terraform Azure Provider Issues](https://github.com/hashicorp/terraform-provider-azurerm/issues)

For issues with this infrastructure code, refer to the original recipe documentation or the Azure service documentation linked above.