# Infrastructure as Code for AI Code Review Assistant with Reasoning and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI Code Review Assistant with Reasoning and Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.50.0 or later)
- Azure subscription with appropriate permissions for creating:
  - Azure OpenAI Service resources
  - Azure Functions resources
  - Azure Storage accounts
  - Resource groups
- Azure Functions Core Tools (version 4.x or later)
- Python 3.11 or later for local function development
- Azure OpenAI Service access (requires application approval)
- Estimated cost: $15-25 for testing (primarily Azure OpenAI usage)

> **Note**: Azure OpenAI Service requires application approval and may have regional availability limitations. The o1-mini model is currently available in select regions including eastus, westus, and northcentralus.

## Architecture Overview

This solution deploys:
- **Azure Storage Account**: Blob containers for code files and review reports
- **Azure OpenAI Service**: o1-mini reasoning model for code analysis
- **Azure Function App**: Serverless compute with Python runtime
- **Resource Group**: Container for all resources

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy infrastructure
az deployment group create \
    --resource-group rg-ai-code-review \
    --template-file bicep/main.bicep \
    --parameters location=eastus

# Deploy function code
cd function-code/
func azure functionapp publish <function-app-name> --python
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review deployment plan
terraform plan

# Deploy infrastructure
terraform apply

# Deploy function code (get function app name from Terraform output)
cd ../function-code/
func azure functionapp publish $(terraform output -raw function_app_name) --python
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy complete solution
./scripts/deploy.sh

# The script will prompt for required parameters and deploy both infrastructure and function code
```

## Configuration Parameters

### Bicep Parameters

- `location`: Azure region for deployment (default: eastus)
- `resourcePrefix`: Prefix for resource names (default: ai-code-review)
- `storageAccountSku`: Storage account SKU (default: Standard_LRS)
- `functionAppSku`: Function app service plan SKU (default: Y1 - consumption)
- `openAiSku`: Azure OpenAI service SKU (default: S0)

### Terraform Variables

- `location`: Azure region for deployment
- `resource_prefix`: Prefix for resource names
- `storage_account_tier`: Storage account performance tier
- `storage_account_replication_type`: Storage replication type
- `function_app_service_plan_sku`: Function app service plan SKU
- `openai_sku_name`: Azure OpenAI service SKU

### Environment Variables (Bash Scripts)

- `AZURE_LOCATION`: Azure region (default: eastus)
- `RESOURCE_PREFIX`: Prefix for resource names
- `AZURE_SUBSCRIPTION_ID`: Azure subscription ID (auto-detected if not set)

## Testing the Deployment

After deployment, test the AI code review functionality:

```bash
# Get function app URL and key from deployment outputs
FUNCTION_URL="<your-function-app-url>"
FUNCTION_KEY="<your-function-key>"

# Test code review endpoint
curl -X POST "https://${FUNCTION_URL}/api/review-code?code=${FUNCTION_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
      "filename": "sample.py",
      "code_content": "def calculate_average(numbers):\n    total = 0\n    for num in numbers:\n        total += num\n    return total / len(numbers)\n\nresult = calculate_average([1, 2, 3, 4, 5])\nprint(result)"
    }'

# Test report retrieval (use report filename from previous response)
curl "https://${FUNCTION_URL}/api/get-report?code=${FUNCTION_KEY}&report_filename=<report-filename>"
```

## Monitoring and Logs

### View Function Logs

```bash
# Stream function logs
func azure functionapp logstream <function-app-name>

# Or view in Azure portal
az functionapp browse --name <function-app-name> --resource-group <resource-group>
```

### Monitor Azure OpenAI Usage

```bash
# View OpenAI metrics
az monitor metrics list \
    --resource <openai-resource-id> \
    --metric "GeneratedTokens,PromptTokens" \
    --interval PT1H
```

### Check Storage Usage

```bash
# List blob containers and contents
az storage container list --account-name <storage-account-name>
az storage blob list --container-name code-files --account-name <storage-account-name>
az storage blob list --container-name review-reports --account-name <storage-account-name>
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name rg-ai-code-review --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Customization

### Function Code Modifications

The function code is located in the `function-code/` directory:
- `function_app.py`: Main function logic
- `requirements.txt`: Python dependencies
- Modify the system prompt in `function_app.py` to customize code review criteria
- Add additional endpoints for specific code analysis tasks

### Infrastructure Customization

#### Bicep Customization

```bash
# Deploy with custom parameters
az deployment group create \
    --resource-group rg-ai-code-review \
    --template-file bicep/main.bicep \
    --parameters location=westus2 \
    --parameters resourcePrefix=mycompany-codereview \
    --parameters storageAccountSku=Standard_ZRS
```

#### Terraform Customization

Create a `terraform.tfvars` file:

```hcl
location = "westus2"
resource_prefix = "mycompany-codereview"
storage_account_tier = "Standard"
storage_account_replication_type = "ZRS"
```

### Security Enhancements

For production deployments, consider:

1. **Enable Azure Key Vault integration**:
   ```bash
   # Store OpenAI keys in Key Vault
   az keyvault secret set \
       --vault-name <keyvault-name> \
       --name "openai-key" \
       --value "<openai-key>"
   ```

2. **Configure Azure AD authentication**:
   ```bash
   # Enable managed identity for Function App
   az functionapp identity assign \
       --name <function-app-name> \
       --resource-group <resource-group>
   ```

3. **Implement network security**:
   - Configure private endpoints for storage and OpenAI
   - Use Azure API Management for rate limiting
   - Enable Application Insights for monitoring

## Troubleshooting

### Common Issues

1. **OpenAI Model Deployment Failures**:
   - Verify o1-mini model availability in your region
   - Check Azure OpenAI service quotas
   - Ensure proper subscription permissions

2. **Function Deployment Errors**:
   - Verify Python 3.11 runtime is supported in your region
   - Check storage account connection string configuration
   - Validate function app settings

3. **Storage Access Issues**:
   - Verify storage account connection string
   - Check blob container permissions
   - Ensure storage account firewall settings allow function access

### Debug Commands

```bash
# Check resource deployment status
az deployment group show \
    --resource-group <resource-group> \
    --name <deployment-name>

# Validate function app configuration
az functionapp config appsettings list \
    --name <function-app-name> \
    --resource-group <resource-group>

# Test storage connectivity
az storage container list \
    --connection-string "<storage-connection-string>"
```

## Performance Optimization

### Cost Optimization

- Monitor Azure OpenAI token usage to optimize costs
- Use consumption-based Function App plan for variable workloads
- Implement blob storage lifecycle policies for old reports
- Consider using Azure OpenAI batch processing for large code reviews

### Performance Tuning

- Increase Function App timeout for large file processing
- Implement caching for frequently reviewed code patterns
- Use parallel processing for multiple file reviews
- Configure appropriate OpenAI model parameters for response speed vs quality

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# Azure DevOps Pipeline example
- task: AzureCLI@2
  displayName: 'Run Code Review'
  inputs:
    azureSubscription: 'Azure Service Connection'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: |
      FUNCTION_URL=$(az functionapp show --name $(functionAppName) --resource-group $(resourceGroup) --query defaultHostName -o tsv)
      FUNCTION_KEY=$(az functionapp keys list --name $(functionAppName) --resource-group $(resourceGroup) --query functionKeys.default -o tsv)
      
      curl -X POST "https://${FUNCTION_URL}/api/review-code?code=${FUNCTION_KEY}" \
          -H "Content-Type: application/json" \
          -d @code-review-payload.json
```

### GitHub Actions Integration

```yaml
name: AI Code Review
on: [pull_request]

jobs:
  code-review:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - name: Run AI Code Review
      run: |
        # Submit code files for review
        curl -X POST "${{ secrets.FUNCTION_URL }}/api/review-code?code=${{ secrets.FUNCTION_KEY }}" \
            -H "Content-Type: application/json" \
            -d '{"filename": "modified-file.py", "code_content": "'$(cat modified-file.py)'"}'
```

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review Azure Function logs and OpenAI service metrics
3. Refer to the original recipe documentation
4. Consult Azure documentation for specific services:
   - [Azure OpenAI Service](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/)
   - [Azure Functions](https://learn.microsoft.com/en-us/azure/azure-functions/)
   - [Azure Blob Storage](https://learn.microsoft.com/en-us/azure/storage/blobs/)

## Contributing

To contribute improvements to this infrastructure code:
1. Test changes thoroughly in a development environment
2. Update documentation to reflect any parameter or configuration changes
3. Ensure compatibility across all IaC implementations (Bicep, Terraform, Bash)
4. Follow Azure Well-Architected Framework principles