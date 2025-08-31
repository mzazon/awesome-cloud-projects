# Infrastructure as Code for AI Assistant with Custom Functions using OpenAI and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI Assistant with Custom Functions using OpenAI and Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code language
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys an intelligent AI assistant that combines Azure OpenAI Assistants API with custom serverless functions. The infrastructure includes:

- Azure OpenAI Service with GPT-4 model deployment
- Azure Functions App with custom business logic functions
- Azure Storage Account for conversation persistence
- Integrated function calling capabilities for dynamic business operations

## Prerequisites

### General Requirements
- Azure subscription with appropriate permissions
- Azure CLI installed and configured (`az --version` >= 2.30.0)
- Bash shell environment (Windows users can use WSL2 or Azure Cloud Shell)

### For Bicep Deployment
- Azure CLI with Bicep support (automatically included in recent versions)
- Resource creation permissions for:
  - Cognitive Services (Azure OpenAI)
  - Azure Functions and hosting plans
  - Storage Accounts
  - Resource Groups

### For Terraform Deployment
- Terraform installed (`terraform --version` >= 1.0)
- Azure authentication configured (Azure CLI or Service Principal)
- Resource creation permissions as listed above

### Cost Estimates
- **Azure OpenAI**: $20-40 for GPT-4 usage during testing
- **Azure Functions**: $5-10 for Flex Consumption plan
- **Azure Storage**: $2-5 for blob storage and transactions
- **Total estimated cost**: $27-55 for recipe execution and testing

## Quick Start

### Using Bicep

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-ai-assistant-demo" \
    --template-file main.bicep \
    --parameters location="eastus" \
                 environmentName="demo" \
                 openAiModelName="gpt-4" \
                 openAiModelVersion="0613"

# The deployment will output important values like function URLs and OpenAI endpoints
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="location=eastus" -var="environment_name=demo"

# Apply the configuration
terraform apply -var="location=eastus" -var="environment_name=demo"

# Important outputs will be displayed including function URLs and connection strings
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run the deployment script
./scripts/deploy.sh

# Follow the prompts to configure your deployment
# The script will create all resources and configure the AI assistant
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `environmentName` | Environment suffix for resource naming | `demo` | Yes |
| `openAiModelName` | OpenAI model to deploy | `gpt-4` | No |
| `openAiModelVersion` | Model version | `0613` | No |
| `functionAppSku` | Functions hosting plan SKU | `FlexConsumption` | No |
| `storageAccountSku` | Storage account SKU | `Standard_LRS` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `environment_name` | Environment suffix | `demo` | Yes |
| `resource_group_name` | Resource group name | `rg-ai-assistant-{environment}` | No |
| `openai_model_name` | OpenAI model to deploy | `gpt-4` | No |
| `openai_model_version` | Model version | `0613` | No |
| `storage_replication_type` | Storage replication | `LRS` | No |

## Post-Deployment Configuration

After the infrastructure is deployed, you'll need to configure the AI assistant:

### 1. Create the AI Assistant

```bash
# Install required Python packages
pip install openai azure-storage-blob requests

# Use the output values from your deployment to set environment variables
export OPENAI_ENDPOINT="<your-openai-endpoint>"
export OPENAI_KEY="<your-openai-key>"
export STORAGE_CONNECTION_STRING="<your-storage-connection-string>"

# Create assistant using the provided script
python ../create-assistant.py
```

### 2. Deploy Custom Functions

```bash
# Navigate to the functions directory (created during deployment)
cd assistant-functions/

# Deploy functions to Azure
func azure functionapp publish <your-function-app-name>

# Note the function URLs for testing
```

### 3. Test the Solution

```bash
# Run the conversation manager to test end-to-end functionality
export ASSISTANT_ID="<your-assistant-id>"
export CUSTOMER_FUNCTION_URL="<your-customer-function-url>"
export ANALYTICS_FUNCTION_URL="<your-analytics-function-url>"

python ../conversation-manager.py
```

## Validation and Testing

### Infrastructure Validation

```bash
# Verify Azure OpenAI deployment
az cognitiveservices account show \
    --name "<your-openai-account>" \
    --resource-group "<your-resource-group>"

# Check Functions App status
az functionapp show \
    --name "<your-function-app>" \
    --resource-group "<your-resource-group>" \
    --query "state"

# Verify storage account
az storage account show \
    --name "<your-storage-account>" \
    --resource-group "<your-resource-group>" \
    --query "primaryEndpoints"
```

### Function Testing

```bash
# Test customer information function
curl -X POST "<customer-function-url>" \
    -H "Content-Type: application/json" \
    -d '{"customerId": "CUST001", "includeHistory": true}'

# Test analytics function
curl -X POST "<analytics-function-url>" \
    -H "Content-Type: application/json" \
    -d '{"metric": "sales", "timeframe": "last_month"}'
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name "rg-ai-assistant-demo" \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="location=eastus" -var="environment_name=demo"

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

## Troubleshooting

### Common Issues

**OpenAI Model Deployment Fails**
- Verify your subscription has access to Azure OpenAI services
- Check if GPT-4 is available in your selected region
- Ensure you have sufficient quota for the model

**Function Deployment Issues**
- Verify Azure Functions Core Tools are installed (`func --version`)
- Check that Python 3.11 is available if developing locally
- Ensure the Functions runtime is properly configured

**Storage Connection Issues**
- Verify storage account connection string is correctly set
- Check that blob containers are created with proper permissions
- Ensure network access rules allow function app connectivity

**Assistant Creation Fails**
- Verify all environment variables are set correctly
- Check OpenAI API version compatibility
- Ensure the deployed model name matches the assistant configuration

### Debug Commands

```bash
# Check resource group contents
az resource list --resource-group "<your-resource-group>" --output table

# View Function App logs
az webapp log tail --name "<your-function-app>" --resource-group "<your-resource-group>"

# Check OpenAI service status
az cognitiveservices account list-models \
    --name "<your-openai-account>" \
    --resource-group "<your-resource-group>"

# Test storage connectivity
az storage container list \
    --connection-string "<your-storage-connection-string>"
```

## Customization

### Adding Custom Functions

1. Create new function in the Functions App:
   ```bash
   func new --name YourCustomFunction --template "HTTP trigger"
   ```

2. Update the assistant configuration to include the new function schema:
   ```python
   custom_function = {
       "type": "function",
       "function": {
           "name": "your_custom_function",
           "description": "Description of what your function does",
           "parameters": {
               # Define your function parameters here
           }
       }
   }
   ```

3. Update the conversation manager to handle the new function calls.

### Scaling Considerations

- **Azure OpenAI**: Adjust token per minute (TPM) limits based on usage patterns
- **Functions**: Configure auto-scaling settings for high-traffic scenarios
- **Storage**: Consider premium storage tiers for high-throughput applications
- **Monitoring**: Implement Application Insights for performance tracking

### Security Enhancements

- Enable managed identity for Functions to access other Azure services
- Configure Key Vault for sensitive configuration values
- Implement API Management for function endpoint security
- Enable private endpoints for storage and OpenAI services

## Monitoring and Maintenance

### Key Metrics to Monitor

- OpenAI API request rates and error rates
- Function execution duration and success rates
- Storage transaction costs and data growth
- Assistant conversation success rates

### Recommended Alerts

```bash
# Set up cost alerts
az consumption budget create \
    --budget-name "ai-assistant-budget" \
    --amount 100 \
    --time-grain Monthly \
    --resource-group "<your-resource-group>"

# Monitor function failures
az monitor metrics alert create \
    --name "function-failures" \
    --resource-group "<your-resource-group>" \
    --scopes "<function-app-resource-id>" \
    --condition "count 'FunctionExecutionCount' < 1"
```

## Support and Resources

- [Azure OpenAI Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/)
- [Azure Functions Documentation](https://learn.microsoft.com/en-us/azure/azure-functions/)
- [Bicep Language Reference](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or Azure support channels.

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Adapt as needed for your production requirements.