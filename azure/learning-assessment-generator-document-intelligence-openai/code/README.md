# Infrastructure as Code for Learning Assessment Generator with Document Intelligence and OpenAI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Learning Assessment Generator with Document Intelligence and OpenAI".

## Available Implementations

- **Bicep**: Azure native infrastructure as code using Bicep language
- **Terraform**: Multi-cloud infrastructure as code using HashiCorp Terraform
- **Scripts**: Bash deployment and cleanup scripts for manual resource management

## Prerequisites

### Common Requirements
- Azure subscription with appropriate permissions
- Estimated cost: $15-25 per month for development/testing usage
- Azure OpenAI service access (requires approved access through the limited access program)

### Tool-Specific Prerequisites

#### For Bicep Deployment
- Azure CLI version 2.20.0 or later installed and configured
- Bicep extension for Azure CLI (automatically installed with recent Azure CLI versions)
- Azure subscription with the following permissions:
  - `Contributor` or `Owner` role on the target resource group
  - `Microsoft.Resources/deployments/*` permissions
  - Permissions to create Cognitive Services, Storage, Functions, and Cosmos DB resources

#### For Terraform Deployment
- Terraform CLI version 1.0 or later
- Azure CLI installed and authenticated (`az login`)
- Terraform Azure provider (`azurerm`) will be automatically installed

#### For Bash Scripts
- Azure CLI version 2.20.0 or later
- `jq` command-line JSON processor (for parsing CLI output)
- `openssl` (for generating random suffixes)

## Quick Start

### Prerequisites Setup

First, ensure you're logged into Azure and have selected the appropriate subscription:

```bash
# Login to Azure
az login

# List available subscriptions
az account list --output table

# Set the subscription (replace with your subscription ID)
az account set --subscription "your-subscription-id"

# Verify your current subscription
az account show --output table
```

### Using Bicep

Deploy the complete learning assessment generator infrastructure using Azure's native Bicep language:

```bash
# Create a resource group
az group create --name rg-learning-assessment --location eastus

# Deploy the Bicep template
az deployment group create \
    --resource-group rg-learning-assessment \
    --template-file bicep/main.bicep \
    --parameters environment=dev \
    --parameters openaiRequiredAccess=true

# View deployment outputs
az deployment group show \
    --resource-group rg-learning-assessment \
    --name main \
    --query properties.outputs
```

#### Bicep Parameters

You can customize the deployment by providing parameters:

```bash
az deployment group create \
    --resource-group rg-learning-assessment \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json
```

Create a `bicep/parameters.json` file:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environment": {
      "value": "dev"
    },
    "location": {
      "value": "eastus"
    },
    "openaiRequiredAccess": {
      "value": true
    }
  }
}
```

### Using Terraform

Deploy using HashiCorp Terraform for infrastructure as code with state management:

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform (downloads providers and modules)
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure changes
terraform apply

# View outputs
terraform output
```

#### Terraform Variables

Customize your deployment by creating a `terraform.tfvars` file:

```hcl
# terraform.tfvars
environment          = "dev"
location            = "East US"
resource_group_name = "rg-learning-assessment-dev"

# OpenAI Configuration
openai_sku_name     = "S0"
openai_model_name   = "gpt-4o"
openai_model_version = "2024-08-06"

# Storage Configuration
storage_replication_type = "LRS"

# Function App Configuration
function_app_runtime = "python"
function_app_version = "3.12"

# Tags
tags = {
  Environment = "Development"
  Project     = "Learning Assessment Generator"
  CostCenter  = "Education Technology"
}
```

#### Terraform Environment Variables

Alternatively, set variables via environment variables:

```bash
export TF_VAR_environment="production"
export TF_VAR_location="East US"
export TF_VAR_openai_sku_name="S0"
```

### Using Bash Scripts

For manual deployment using Azure CLI commands:

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts to configure your deployment
# The script will create all necessary resources and output connection details

# Verify deployment
az resource list --resource-group rg-learning-assessment --output table
```

The deployment script will prompt you for:
- Resource group name
- Azure region
- Environment name (dev/staging/prod)
- Whether to deploy with premium SKUs

## Configuration Options

### Environment-Specific Deployments

All implementations support multiple environments:

- **Development**: Basic SKUs, minimal redundancy, cost-optimized
- **Staging**: Standard SKUs, regional redundancy, performance testing ready
- **Production**: Premium SKUs, multi-region support, enterprise features

### Resource Naming Convention

Resources follow this naming pattern:
- Storage Account: `assess<env><random>`
- Cosmos DB: `assess-cosmos-<env>-<random>`
- Function App: `assess-functions-<env>-<random>`
- Document Intelligence: `assess-doc-intel-<env>-<random>`
- OpenAI Service: `assess-openai-<env>-<random>`

### Azure OpenAI Model Configuration

The solution deploys GPT-4o model by default. You can customize:

```bash
# In Bicep parameters
"openaiModelName": "gpt-4o",
"openaiModelVersion": "2024-08-06",
"openaiSkuCapacity": 20

# In Terraform variables
openai_model_name = "gpt-4o"
openai_model_version = "2024-08-06"
openai_sku_capacity = 20
```

## Validation and Testing

After deployment, verify your infrastructure:

### Test Storage Account

```bash
# Get storage account name
STORAGE_ACCOUNT=$(az storage account list \
    --resource-group rg-learning-assessment \
    --query "[0].name" --output tsv)

# Test blob upload
echo "Test document content" > test-doc.txt
az storage blob upload \
    --account-name $STORAGE_ACCOUNT \
    --container-name documents \
    --file test-doc.txt \
    --name test-doc.txt
```

### Test Azure OpenAI Deployment

```bash
# Get OpenAI endpoint
OPENAI_ENDPOINT=$(az cognitiveservices account show \
    --name assess-openai-dev-* \
    --resource-group rg-learning-assessment \
    --query properties.endpoint --output tsv)

echo "OpenAI endpoint: $OPENAI_ENDPOINT"
```

### Test Function App

```bash
# Get Function App URL
FUNCTION_URL=$(az functionapp show \
    --name assess-functions-dev-* \
    --resource-group rg-learning-assessment \
    --query defaultHostName --output tsv)

echo "Function App URL: https://$FUNCTION_URL"
```

### Test Cosmos DB

```bash
# List Cosmos DB databases
az cosmosdb sql database list \
    --account-name assess-cosmos-dev-* \
    --resource-group rg-learning-assessment
```

## Monitoring and Troubleshooting

### View Deployment Status

#### Bicep
```bash
# Check deployment status
az deployment group list \
    --resource-group rg-learning-assessment \
    --query "[].{Name:name, State:properties.provisioningState, Timestamp:properties.timestamp}"
```

#### Terraform
```bash
# View Terraform state
terraform show

# Check for configuration drift
terraform plan
```

### View Resource Health

```bash
# Check all resources in the resource group
az resource list \
    --resource-group rg-learning-assessment \
    --query "[].{Name:name, Type:type, State:properties.provisioningState}" \
    --output table
```

### Function App Logs

```bash
# Stream Function App logs
az functionapp log tail \
    --name assess-functions-dev-* \
    --resource-group rg-learning-assessment
```

### Application Insights

```bash
# Get Application Insights connection string
az monitor app-insights component show \
    --app assess-functions-dev-*-insights \
    --resource-group rg-learning-assessment \
    --query connectionString
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name rg-learning-assessment --yes --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm by typing 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
az group show --name rg-learning-assessment --output table
# Should show "ResourceGroupNotFound" error

# List any remaining resources (if resource group still exists)
az resource list --resource-group rg-learning-assessment --output table
```

## Customization

### Adding Custom Functions

To extend the solution with additional Azure Functions:

1. **Bicep**: Add new function definitions in `bicep/modules/functions.bicep`
2. **Terraform**: Add function resources in `terraform/functions.tf`
3. **Scripts**: Modify the function deployment section in `scripts/deploy.sh`

### Integrating with CI/CD

#### GitHub Actions (Bicep)

```yaml
# .github/workflows/deploy.yml
name: Deploy Learning Assessment Generator
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    - name: Deploy Bicep
      run: |
        az deployment group create \
          --resource-group rg-learning-assessment \
          --template-file bicep/main.bicep
```

#### Azure DevOps (Terraform)

```yaml
# azure-pipelines.yml
trigger:
- main

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: TerraformInstaller@0
  inputs:
    terraformVersion: 'latest'
- task: TerraformTaskV3@3
  inputs:
    provider: 'azurerm'
    command: 'init'
    workingDirectory: 'terraform/'
- task: TerraformTaskV3@3
  inputs:
    provider: 'azurerm'
    command: 'apply'
    workingDirectory: 'terraform/'
```

### Security Considerations

- All resources use Azure managed identities where possible
- Secrets are stored in Azure Key Vault (in production configurations)
- Network security groups restrict access to essential ports only
- Azure OpenAI content filtering is enabled by default
- Storage accounts use private endpoints in production

### Cost Optimization

- Development environments use consumption-based pricing where available
- Storage accounts use Standard LRS replication
- Cosmos DB uses serverless mode for variable workloads
- Azure Functions use consumption plan for cost efficiency

## Support

For issues with this infrastructure code:

1. **Azure Service Issues**: Check the [Azure Service Health Dashboard](https://status.azure.com/)
2. **Bicep Issues**: Refer to [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
3. **Terraform Issues**: Refer to [Terraform AzureRM Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
4. **Recipe Issues**: Refer to the original recipe documentation

### Useful Resources

- [Azure AI Document Intelligence Documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/form-recognizer/)
- [Azure OpenAI Service Documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/openai/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Cosmos DB Documentation](https://docs.microsoft.com/en-us/azure/cosmos-db/)
- [Azure Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/)

## Architecture Overview

The infrastructure deploys the following resources:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Blob Storage  │───▶│  Azure Functions │───▶│   Cosmos DB     │
│   (Documents)   │    │  (Processing)    │    │ (Assessments)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
┌─────────────────┐    ┌──────────────────┐
│ Document Intel  │    │   Azure OpenAI   │
│  (OCR & Layout) │    │   (GPT-4o Model) │
└─────────────────┘    └──────────────────┘
```

This architecture provides:
- **Serverless Processing**: Automatic scaling based on document volume
- **AI-Powered Analysis**: Advanced document understanding and assessment generation
- **Flexible Storage**: NoSQL database for structured assessment data
- **Event-Driven**: Automatic processing when documents are uploaded
- **Cost-Effective**: Pay-per-use pricing for all major components