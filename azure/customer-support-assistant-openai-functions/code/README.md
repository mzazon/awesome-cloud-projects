# Infrastructure as Code for Customer Support Assistant with OpenAI Assistants and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Customer Support Assistant with OpenAI Assistants and Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys:
- **Azure Storage Account** with Table Storage (tickets, customers), Blob Storage (FAQs), and Queue Storage (escalations)
- **Azure OpenAI Service** with GPT-4o model deployment
- **Azure Functions App** with four custom functions for support operations
- **Required IAM roles and permissions** for service integration

## Prerequisites

- Azure CLI installed and configured with appropriate subscription access
- Node.js 20+ for local development and testing
- Azure subscription with permissions to create:
  - Azure OpenAI Service (requires approved access)
  - Azure Functions
  - Azure Storage Account
  - Cognitive Services
- Terraform installed (if using Terraform deployment)
- Bicep CLI installed (if using Bicep deployment)

> **Important**: Azure OpenAI Service requires approved access. Ensure you have been granted access to deploy GPT-4o models in your target region.

## Cost Estimation

Expected costs for this deployment:
- **Azure OpenAI Service**: $0.03 per 1K prompt tokens, $0.06 per 1K completion tokens
- **Azure Functions**: $0.20 per million executions (Consumption plan)
- **Azure Storage**: $0.05-0.10 per GB/month depending on access tier
- **Total estimated cost for testing**: $15-25 for recipe completion

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to Bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-support-assistant \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters environmentName=demo

# Get deployment outputs
az deployment group show \
    --resource-group rg-support-assistant \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="location=eastus" \
    -var="environment=demo"

# Apply the configuration
terraform apply \
    -var="location=eastus" \
    -var="environment=demo"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export LOCATION="eastus"
export ENVIRONMENT="demo"

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment summary
./scripts/deploy.sh --status
```

## Deployment Parameters

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `eastus` | Azure region for resource deployment |
| `environmentName` | string | `demo` | Environment name for resource naming |
| `storageSkuName` | string | `Standard_LRS` | Storage account SKU |
| `functionAppRuntime` | string | `node` | Function App runtime stack |
| `openAiSkuName` | string | `S0` | Azure OpenAI Service pricing tier |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `location` | string | `eastus` | Azure region for resource deployment |
| `environment` | string | `demo` | Environment name for resource naming |
| `resource_group_name` | string | `rg-support-assistant` | Resource group name |
| `storage_account_tier` | string | `Standard` | Storage account performance tier |
| `openai_sku_name` | string | `S0` | Azure OpenAI Service pricing tier |

### Bash Script Environment Variables

```bash
# Required variables
export LOCATION="eastus"                    # Azure region
export ENVIRONMENT="demo"                   # Environment name
export RESOURCE_GROUP="rg-support-assistant-${ENVIRONMENT}"

# Optional customization
export STORAGE_SKU="Standard_LRS"           # Storage account SKU
export FUNCTION_RUNTIME="node"              # Function runtime
export OPENAI_SKU="S0"                     # OpenAI service tier
```

## Post-Deployment Configuration

After successful infrastructure deployment, complete these additional steps:

### 1. Deploy Function Code

```bash
# Clone or navigate to your function code directory
cd ../support-functions/

# Install dependencies
npm install @azure/data-tables @azure/storage-blob @azure/storage-queue openai

# Deploy functions to Azure
func azure functionapp publish <function-app-name>
```

### 2. Create OpenAI Assistant

```bash
# Set environment variables from deployment outputs
export OPENAI_ENDPOINT="<openai-endpoint-from-output>"
export OPENAI_KEY="<openai-key-from-output>"

# Run assistant creation script
node create-assistant.js
```

### 3. Configure Function Authentication

```bash
# Get function app authentication key
export FUNCTION_KEY=$(az functionapp keys list \
    --name <function-app-name> \
    --resource-group <resource-group-name> \
    --query functionKeys.default --output tsv)
```

## Testing the Deployment

### 1. Verify Infrastructure

```bash
# Check resource group
az group show --name <resource-group-name>

# Verify Function App
az functionapp show --name <function-app-name> --resource-group <resource-group-name>

# Check OpenAI Service
az cognitiveservices account show --name <openai-service-name> --resource-group <resource-group-name>

# Verify Storage Account
az storage account show --name <storage-account-name> --resource-group <resource-group-name>
```

### 2. Test Function Endpoints

```bash
# Test FAQ retrieval
curl -X POST "https://<function-app-name>.azurewebsites.net/api/faqRetrieval?code=<function-key>" \
     -H "Content-Type: application/json" \
     -d '{"query": "password"}'

# Test ticket lookup (should return 404 for non-existent ticket)
curl -X POST "https://<function-app-name>.azurewebsites.net/api/ticketLookup?code=<function-key>" \
     -H "Content-Type: application/json" \
     -d '{"ticketId": "test-123"}'
```

### 3. Test OpenAI Assistant

```bash
# Create test conversation
node test-assistant.js
```

## Monitoring and Observability

### Enable Application Insights

```bash
# Enable Application Insights for Function App
az functionapp config appsettings set \
    --name <function-app-name> \
    --resource-group <resource-group-name> \
    --settings "APPINSIGHTS_INSTRUMENTATIONKEY=<instrumentation-key>"
```

### View Logs

```bash
# Stream Function App logs
az webapp log tail --name <function-app-name> --resource-group <resource-group-name>

# View OpenAI Service metrics
az monitor metrics list \
    --resource <openai-resource-id> \
    --metric "TokenTransaction"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-support-assistant \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy \
    -var="location=eastus" \
    -var="environment=demo"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
./scripts/destroy.sh --verify
```

## Customization

### Scaling Configuration

Modify the Function App scaling settings:

```bash
# Set maximum scale-out limit
az functionapp config set \
    --name <function-app-name> \
    --resource-group <resource-group-name> \
    --number-of-workers 5
```

### Security Hardening

1. **Enable Private Endpoints**: Configure private endpoints for Storage and OpenAI services
2. **Network Security**: Implement VNet integration for Function App
3. **Access Control**: Configure Azure RBAC for fine-grained permissions
4. **Key Management**: Use Azure Key Vault for storing sensitive configuration

### Performance Optimization

1. **Function App Settings**:
   ```bash
   az functionapp config appsettings set \
       --name <function-app-name> \
       --resource-group <resource-group-name> \
       --settings "FUNCTIONS_WORKER_PROCESS_COUNT=4"
   ```

2. **Storage Optimization**: Configure appropriate storage tiers based on access patterns

3. **OpenAI Rate Limiting**: Implement request throttling and retry logic in function code

## Troubleshooting

### Common Issues

1. **OpenAI Service Access Denied**: Ensure you have approved access to Azure OpenAI Service
2. **Function Deployment Failures**: Check that all required dependencies are installed
3. **Storage Connection Issues**: Verify storage account connection strings in Function App settings
4. **CORS Errors**: Configure CORS settings if accessing from web applications

### Debug Commands

```bash
# Check Function App configuration
az functionapp config show --name <function-app-name> --resource-group <resource-group-name>

# View recent deployments
az deployment group list --resource-group <resource-group-name>

# Check service health
az resource list --resource-group <resource-group-name> --query "[].{Name:name,Type:type,Location:location}"
```

## Security Considerations

- All resources are deployed with managed identities where possible
- Storage accounts use private endpoints and disable public access
- Function Apps are configured with authentication requirements
- OpenAI services include content filtering and abuse monitoring
- Network access is restricted through Azure networking controls

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Azure service documentation for specific resource types
3. Verify all prerequisites are met
4. Ensure proper permissions are configured
5. Review deployment logs for specific error messages

## Additional Resources

- [Azure OpenAI Service Documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/openai/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/)
- [Bicep Language Reference](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)