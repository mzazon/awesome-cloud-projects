# Infrastructure as Code for Automated Audio Summarization with OpenAI and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Audio Summarization with OpenAI and Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure deploys:
- Azure Storage Account with blob containers for audio input/output
- Azure Functions App with Python runtime for serverless processing
- Azure OpenAI resource with Whisper and GPT-4 model deployments
- Cognitive Services account for AI capabilities
- Application Insights for monitoring and logging
- Required IAM roles and permissions for secure operation

## Prerequisites

- Azure CLI installed and configured (`az --version`)
- Azure subscription with appropriate permissions for:
  - Resource Group creation
  - Storage Account management
  - Azure Functions deployment
  - Azure OpenAI service access (requires approval)
  - Cognitive Services provisioning
- For Terraform: Terraform CLI installed (`terraform --version`)
- For Bicep: Bicep CLI installed (`az bicep version`)
- Azure OpenAI service access approved (apply at [Azure OpenAI Access](https://customervoice.microsoft.com/Pages/ResponsePage.aspx?id=v4j5cvGGr0GRqy180BHbR7en2Ais5pxKtso_Pz4b1_xUNTZBNzRKNlVQSFhZMU9aV09EVzYxWFdORCQlQCN0PWcu))

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to bicep directory
cd bicep/

# Review and customize parameters
cat parameters.json

# Deploy infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
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

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Review configuration variables
head deploy.sh

# Deploy infrastructure
./deploy.sh

# View deployed resources
az resource list --resource-group <resource-group-name> --output table
```

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "resourcePrefix": {
      "value": "audiosumm"
    },
    "openAiSku": {
      "value": "S0"
    },
    "functionAppSku": {
      "value": "Y1"
    }
  }
}
```

### Terraform Variables

Customize `terraform/terraform.tfvars`:

```hcl
location = "East US"
resource_group_name = "rg-audio-summarization"
resource_prefix = "audiosumm"
openai_sku_name = "S0"
storage_account_tier = "Standard"
storage_replication_type = "LRS"
```

### Bash Script Variables

Edit variables at the top of `scripts/deploy.sh`:

```bash
# Configuration variables
LOCATION="eastus"
RESOURCE_PREFIX="audiosumm"
OPENAI_SKU="S0"
FUNCTION_RUNTIME="python"
FUNCTION_VERSION="4"
```

## Deployment Verification

After deployment, verify the infrastructure:

```bash
# Check resource group contents
az resource list --resource-group <resource-group-name> --output table

# Verify Function App status
az functionapp show \
    --name <function-app-name> \
    --resource-group <resource-group-name> \
    --query "state"

# Check OpenAI model deployments
az cognitiveservices account deployment list \
    --name <openai-resource-name> \
    --resource-group <resource-group-name>

# Verify storage containers
az storage container list \
    --account-name <storage-account-name> \
    --query "[].name"
```

## Function Deployment

After infrastructure is deployed, deploy the function code:

```bash
# Create local function project (if not already created)
func init audio-function --worker-runtime python
cd audio-function

# Create requirements.txt
cat > requirements.txt << 'EOF'
azure-functions==1.21.0
azure-storage-blob==12.23.1
openai==1.54.3
python-multipart==0.0.9
EOF

# Create function code (refer to recipe for complete implementation)
func new --name ProcessAudio --template "Azure Blob Storage trigger"

# Deploy function to Azure
func azure functionapp publish <function-app-name> --python
```

## Testing the Solution

1. **Upload test audio file**:
   ```bash
   # Upload sample audio to trigger processing
   az storage blob upload \
       --container-name audio-input \
       --file sample-audio.wav \
       --name "test-audio.wav" \
       --account-name <storage-account-name>
   ```

2. **Monitor function execution**:
   ```bash
   # View function logs
   az webapp log tail \
       --name <function-app-name> \
       --resource-group <resource-group-name>
   ```

3. **Check processing results**:
   ```bash
   # List processed files
   az storage blob list \
       --container-name audio-output \
       --account-name <storage-account-name> \
       --output table
   
   # Download results
   az storage blob download \
       --container-name audio-output \
       --name "processed/test-audio.wav.json" \
       --file result.json \
       --account-name <storage-account-name>
   ```

## Monitoring and Troubleshooting

### Application Insights

The deployment includes Application Insights for monitoring:

```bash
# Query function performance
az monitor app-insights query \
    --app <app-insights-name> \
    --analytics-query "requests | limit 10"

# Check for errors
az monitor app-insights query \
    --app <app-insights-name> \
    --analytics-query "exceptions | limit 10"
```

### Function App Logs

```bash
# Stream live logs
az webapp log tail \
    --name <function-app-name> \
    --resource-group <resource-group-name>

# Download log files
az webapp log download \
    --name <function-app-name> \
    --resource-group <resource-group-name> \
    --log-file logs.zip
```

### Storage Diagnostics

```bash
# Enable storage logging
az storage logging update \
    --services b \
    --log-operations rwd \
    --retention-days 7 \
    --account-name <storage-account-name>

# View storage metrics
az monitor metrics list \
    --resource <storage-resource-id> \
    --metric "Transactions"
```

## Cost Optimization

### Resource Sizing

- **Function App**: Consumption plan (Y1) for event-driven workloads
- **Storage**: Standard LRS for cost-effective regional redundancy
- **OpenAI**: Start with S0 tier, scale based on usage

### Cost Monitoring

```bash
# Check current costs
az consumption usage list \
    --billing-period-name <billing-period> \
    --resource-group <resource-group-name>

# Set up budget alerts
az consumption budget create \
    --budget-name "audio-processing-budget" \
    --amount 100 \
    --resource-group <resource-group-name> \
    --time-grain Monthly
```

## Security Considerations

### Managed Identity

The deployment uses system-assigned managed identity for secure access:

```bash
# Verify managed identity is enabled
az functionapp identity show \
    --name <function-app-name> \
    --resource-group <resource-group-name>

# Check role assignments
az role assignment list \
    --assignee <principal-id> \
    --resource-group <resource-group-name>
```

### Network Security

- Storage accounts configured with private endpoints
- Function app configured with VNET integration
- OpenAI service restricted to authorized networks

### Key Management

```bash
# Rotate storage keys
az storage account keys renew \
    --account-name <storage-account-name> \
    --key key1

# Update function app settings with new keys
az functionapp config appsettings set \
    --name <function-app-name> \
    --resource-group <resource-group-name> \
    --settings "STORAGE_CONNECTION_STRING=<new-connection-string>"
```

## Scaling Considerations

### Function App Scaling

```bash
# Monitor function execution count
az monitor metrics list \
    --resource <function-app-resource-id> \
    --metric "FunctionExecutionCount"

# Set scale rules (if using Premium plan)
az functionapp plan update \
    --name <app-service-plan-name> \
    --resource-group <resource-group-name> \
    --max-burst 20
```

### OpenAI Service Scaling

```bash
# Monitor OpenAI usage
az cognitiveservices account usage list \
    --name <openai-resource-name> \
    --resource-group <resource-group-name>

# Scale model deployment capacity
az cognitiveservices account deployment update \
    --name <openai-resource-name> \
    --resource-group <resource-group-name> \
    --deployment-name whisper-1 \
    --sku-capacity 20
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name <resource-group-name> \
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
cd scripts/
chmod +x destroy.sh
./destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
az resource list \
    --resource-group <resource-group-name> \
    --output table

# Check for any remaining costs
az consumption usage list \
    --resource-group <resource-group-name>
```

## Customization and Extensions

### Adding Additional Models

```bash
# Deploy additional OpenAI models
az cognitiveservices account deployment create \
    --name <openai-resource-name> \
    --resource-group <resource-group-name> \
    --deployment-name gpt-3.5-turbo \
    --model-name gpt-35-turbo \
    --model-version "0613" \
    --sku-capacity 10
```

### Custom Function Triggers

Modify the function to support additional triggers:
- Timer trigger for batch processing
- HTTP trigger for API access
- Service Bus trigger for queue-based processing

### Enhanced Monitoring

```bash
# Create custom dashboard
az portal dashboard create \
    --resource-group <resource-group-name> \
    --name audio-processing-dashboard \
    --input-path dashboard.json
```

## Support and Resources

- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure OpenAI Service Documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/openai/)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or the Azure documentation links above.

## Important Notes

> **Note**: Azure OpenAI access requires approval and may have regional limitations. Ensure your subscription has access before deployment.

> **Warning**: Monitor costs closely, especially OpenAI API usage, as charges are based on token consumption and model usage time.

> **Tip**: Use Azure Cost Management to set up automated alerts and spending limits to prevent unexpected charges during testing.