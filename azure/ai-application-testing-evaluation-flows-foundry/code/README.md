# Infrastructure as Code for AI Application Testing with Evaluation Flows and AI Foundry

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI Application Testing with Evaluation Flows and AI Foundry".

## Available Implementations

- **Bicep**: Azure native infrastructure as code
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.58.0 or later)
- Azure subscription with appropriate permissions for:
  - Resource group creation and management
  - Azure AI Services deployment
  - Azure Storage account creation
  - Azure Cognitive Services management
- Basic understanding of machine learning evaluation concepts
- Knowledge of YAML pipeline syntax for Azure DevOps integration
- Estimated cost: $15-25 for compute resources and model inference during testing

> **Note**: Ensure your Azure subscription has sufficient OpenAI model quota for evaluation runs, as AI-assisted metrics require GPT model deployments.

## Quick Start

### Using Bicep

Deploy the complete AI testing infrastructure with Azure's native IaC language:

```bash
cd bicep/

# Login to Azure
az login

# Set subscription (if needed)
az account set --subscription "your-subscription-id"

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-ai-testing \
    --template-file main.bicep \
    --parameters location=eastus \
                 aiServicesName=ai-testing-svc \
                 storageAccountName=aitestingstorage

# Verify deployment
az deployment group show \
    --resource-group rg-ai-testing \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

Deploy using HashiCorp's infrastructure as code tool:

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="location=eastus" \
               -var="resource_group_name=rg-ai-testing" \
               -var="ai_services_name=ai-testing-svc"

# Apply the configuration
terraform apply -var="location=eastus" \
                -var="resource_group_name=rg-ai-testing" \
                -var="ai_services_name=ai-testing-svc"

# Verify deployment
terraform show
```

### Using Bash Scripts

Deploy using automated bash scripts with error handling:

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh

# The script will:
# 1. Create resource group
# 2. Deploy AI Services with OpenAI model
# 3. Create storage account for test data
# 4. Configure evaluation environment
# 5. Validate deployment
```

## Architecture Components

The infrastructure deployment creates:

### Core Services
- **Azure AI Services**: Multi-service resource for AI capabilities
- **OpenAI Model Deployment**: GPT-4O-mini for evaluation tasks
- **Azure Storage Account**: Test dataset and results storage
- **Resource Group**: Logical container for all resources

### Evaluation Framework
- **Built-in Evaluators**: Groundedness, relevance, coherence assessment
- **Custom Evaluation Logic**: Weighted scoring and quality gates
- **CI/CD Integration**: Azure DevOPS pipeline configuration
- **Quality Metrics**: Automated threshold-based decision making

### Security Features
- **Managed Identity**: Secure service-to-service authentication
- **Key Vault Integration**: Secure API key management
- **Network Security**: Private endpoints and restricted access
- **RBAC**: Role-based access control for resources

## Configuration Options

### Bicep Parameters

Customize your deployment by modifying these parameters:

```bicep
param location string = 'eastus'
param aiServicesName string = 'ai-testing-svc'
param storageAccountName string = 'aitestingstorage'
param openAiModelName string = 'gpt-4o-mini'
param openAiModelVersion string = '2024-07-18'
param skuName string = 'S0'
param evaluationCapacity int = 10
```

### Terraform Variables

Configure deployment through variables:

```hcl
variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-ai-testing"
}

variable "ai_services_name" {
  description = "Name of the AI Services resource"
  type        = string
}

variable "storage_account_name" {
  description = "Name of the storage account"
  type        = string
}
```

### Environment Variables

Set these environment variables for script deployment:

```bash
export AZURE_LOCATION="eastus"
export RESOURCE_GROUP_NAME="rg-ai-testing"
export AI_SERVICES_NAME="ai-testing-svc"
export STORAGE_ACCOUNT_NAME="aitestingstorage"
export OPENAI_MODEL_NAME="gpt-4o-mini"
export EVALUATION_CAPACITY="10"
```

## Post-Deployment Setup

### 1. Configure Evaluation Environment

After infrastructure deployment, set up the evaluation environment:

```bash
# Get AI Services endpoint and key
export AZURE_OPENAI_ENDPOINT=$(az cognitiveservices account show \
    --name your-ai-services-name \
    --resource-group your-resource-group \
    --query "properties.endpoint" --output tsv)

export AZURE_OPENAI_API_KEY=$(az cognitiveservices account keys list \
    --name your-ai-services-name \
    --resource-group your-resource-group \
    --query "key1" --output tsv)

# Upload test dataset
az storage blob upload \
    --file test_data.jsonl \
    --container-name test-datasets \
    --name ai-test-dataset.jsonl \
    --account-name your-storage-account
```

### 2. Install Evaluation SDK

Install required Python packages for evaluation:

```bash
pip install azure-ai-evaluation[remote] \
            azure-identity \
            azure-ai-projects \
            openai>=1.0.0
```

### 3. Configure Azure DevOps Pipeline

Set up CI/CD integration:

1. Create service connection in Azure DevOps
2. Configure pipeline variables:
   - `azureServiceConnection`: Your Azure service connection
   - `resourceGroup`: Resource group name
   - `aiServicesName`: AI Services resource name
   - `storageAccount`: Storage account name

## Testing and Validation

### Run Evaluation Test

Test the deployed infrastructure:

```bash
# Run sample evaluation
python run_evaluation.py \
    --data-path test_data.jsonl \
    --output-path evaluation_results.json

# Check quality gates
python check_quality_gates.py evaluation_results.json
```

Expected output:
- Evaluation metrics for groundedness, relevance, coherence
- Overall quality score and tier assessment
- Pass/fail status for quality gates

### Verify Infrastructure

Validate deployed resources:

```bash
# Check AI Services deployment
az cognitiveservices account show \
    --name your-ai-services-name \
    --resource-group your-resource-group

# Verify model deployment
az cognitiveservices account deployment list \
    --name your-ai-services-name \
    --resource-group your-resource-group

# Check storage account
az storage account show \
    --name your-storage-account \
    --resource-group your-resource-group
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-ai-testing \
    --yes \
    --no-wait

echo "✅ Resource group deletion initiated"
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="location=eastus" \
                  -var="resource_group_name=rg-ai-testing" \
                  -var="ai_services_name=ai-testing-svc"

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete model deployments
# 2. Remove AI Services resources
# 3. Delete storage accounts
# 4. Remove resource group
# 5. Clean up local files
```

## Cost Optimization

### Resource Sizing

- **AI Services SKU**: Start with S0 for development, scale to S1+ for production
- **OpenAI Model Capacity**: Begin with 10 TPM, adjust based on evaluation frequency
- **Storage Tier**: Use Standard_LRS for cost-effective test data storage

### Usage Monitoring

Monitor costs with these commands:

```bash
# Check current resource costs
az consumption usage list \
    --start-date 2025-01-01 \
    --end-date 2025-01-31 \
    --resource-group rg-ai-testing

# Set up budget alerts
az consumption budget create \
    --budget-name ai-testing-budget \
    --amount 50 \
    --resource-group rg-ai-testing
```

## Troubleshooting

### Common Issues

1. **Model Quota Exceeded**:
   ```bash
   # Check quota usage
   az cognitiveservices usage list \
       --location eastus \
       --subscription-id your-subscription-id
   ```

2. **Storage Access Denied**:
   ```bash
   # Verify storage permissions
   az storage account keys list \
       --name your-storage-account \
       --resource-group your-resource-group
   ```

3. **Evaluation SDK Import Errors**:
   ```bash
   # Reinstall SDK with correct version
   pip install --upgrade azure-ai-evaluation[remote]
   ```

### Debug Mode

Enable verbose logging for troubleshooting:

```bash
# Set debug environment variables
export AZURE_LOG_LEVEL=DEBUG
export AZURE_CLI_DIAGNOSTICS=true

# Run deployment with debug output
az deployment group create --debug \
    --resource-group rg-ai-testing \
    --template-file main.bicep
```

## Advanced Configuration

### Custom Evaluation Metrics

Extend the framework with domain-specific evaluators:

```python
# Create custom evaluator
from azure.ai.evaluation import evaluate

def custom_domain_evaluator(query, response, context):
    # Implement domain-specific logic
    return {"custom_score": score, "reasoning": explanation}

# Add to evaluation pipeline
evaluators = {
    "groundedness": GroundednessEvaluator(model_config),
    "relevance": RelevanceEvaluator(model_config),
    "coherence": CoherenceEvaluator(model_config),
    "domain_specific": custom_domain_evaluator
}
```

### Multi-Environment Setup

Configure separate environments:

```bash
# Development environment
az deployment group create \
    --resource-group rg-ai-testing-dev \
    --template-file main.bicep \
    --parameters environment=dev capacity=5

# Production environment
az deployment group create \
    --resource-group rg-ai-testing-prod \
    --template-file main.bicep \
    --parameters environment=prod capacity=50
```

## Security Best Practices

### Network Security

- Configure private endpoints for AI Services
- Implement network security groups
- Use Azure Private DNS zones

### Identity and Access

- Enable managed identity for service authentication
- Implement principle of least privilege
- Use Azure Key Vault for secret management

### Data Protection

- Enable encryption at rest for storage accounts
- Configure backup and retention policies
- Implement data loss prevention policies

## Support and Documentation

### Resources

- [Azure AI Foundry Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/)
- [Azure AI Evaluation SDK](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/develop/evaluate-sdk)
- [Azure DevOps Pipelines](https://learn.microsoft.com/en-us/azure/devops/pipelines/)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Azure service health status
3. Consult the original recipe documentation
4. Contact your Azure support team

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow Azure best practices
3. Update documentation accordingly
4. Validate across all deployment methods

---

**Note**: This infrastructure code implements the complete solution described in the "AI Application Testing with Evaluation Flows and AI Foundry" recipe. For detailed implementation guidance, refer to the original recipe documentation.