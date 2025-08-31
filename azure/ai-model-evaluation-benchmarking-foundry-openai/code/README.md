# Infrastructure as Code for AI Model Evaluation and Benchmarking with Azure AI Foundry

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI Model Evaluation and Benchmarking with Azure AI Foundry".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts with Azure CLI

## Prerequisites

- Azure CLI installed and configured (version 2.50.0 or later)
- Active Azure subscription with appropriate permissions
- Azure OpenAI service access (may require approval)
- Contributor role or higher on the target subscription
- For Terraform: Terraform installed (version 1.0 or later)
- For Bicep: Azure CLI with Bicep extension

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
                projectName=ai-eval-project

# Monitor deployment status
az deployment group show \
    --resource-group <your-resource-group> \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan -var="location=eastus" \
               -var="resource_group_name=rg-ai-evaluation"

# Deploy infrastructure
terraform apply -var="location=eastus" \
                -var="resource_group_name=rg-ai-evaluation"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
# or you can set environment variables:
export LOCATION="eastus"
export RESOURCE_GROUP_NAME="rg-ai-evaluation"
export PROJECT_NAME="ai-eval-project"
./scripts/deploy.sh
```

## Architecture Components

This IaC deployment creates:

- **Azure AI Foundry Project**: Centralized workspace for AI model evaluation
- **Azure OpenAI Service**: Access to GPT-4o, GPT-3.5 Turbo, and GPT-4o Mini models
- **Model Deployments**: Three model deployments for comparative evaluation
- **Azure Machine Learning Workspace**: Foundation for AI Foundry project
- **Storage Account**: Data storage for evaluation datasets and results
- **Application Insights**: Monitoring and logging for evaluation processes
- **Key Vault**: Secure storage for API keys and secrets

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `projectName` | Base name for AI project resources | `ai-eval-project` | Yes |
| `openAiSkuName` | Azure OpenAI service tier | `S0` | No |
| `storageAccountType` | Storage account performance tier | `Standard_LRS` | No |
| `deployGpt4o` | Deploy GPT-4o model | `true` | No |
| `deployGpt35Turbo` | Deploy GPT-3.5 Turbo model | `true` | No |
| `deployGpt4oMini` | Deploy GPT-4o Mini model | `true` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `resource_group_name` | Resource group name | `rg-ai-evaluation` | Yes |
| `project_name` | Base name for resources | `ai-eval-project` | Yes |
| `openai_sku_name` | Azure OpenAI service tier | `S0` | No |
| `storage_account_tier` | Storage account tier | `Standard` | No |
| `storage_replication_type` | Storage replication type | `LRS` | No |
| `tags` | Resource tags | `{}` | No |

### Environment Variables for Scripts

| Variable | Description | Default |
|----------|-------------|---------|
| `LOCATION` | Azure region | `eastus` |
| `RESOURCE_GROUP_NAME` | Resource group name | Generated |
| `PROJECT_NAME` | AI project name | Generated |
| `STORAGE_ACCOUNT_NAME` | Storage account name | Generated |
| `OPENAI_RESOURCE_NAME` | OpenAI resource name | Generated |

## Post-Deployment Steps

After successful infrastructure deployment:

1. **Verify Model Deployments**:
   ```bash
   # Check Azure OpenAI model deployments
   az cognitiveservices account deployment list \
       --name <openai-resource-name> \
       --resource-group <resource-group-name>
   ```

2. **Upload Evaluation Dataset**:
   ```bash
   # Upload your evaluation dataset to the storage account
   az storage blob upload \
       --account-name <storage-account-name> \
       --container-name datasets \
       --name evaluation_dataset.jsonl \
       --file evaluation_dataset.jsonl
   ```

3. **Configure Evaluation Flow**:
   ```bash
   # Set up custom evaluation flow in Azure AI Foundry
   az ml code create \
       --name custom-evaluation-flow \
       --version 1 \
       --path custom_evaluation_flow
   ```

## Cost Estimation

Estimated monthly costs for this deployment (East US region):

- **Azure OpenAI Service**: $0-200+ (based on token usage)
  - GPT-4o: ~$15 per 1M input tokens
  - GPT-3.5 Turbo: ~$1.50 per 1M input tokens
  - GPT-4o Mini: ~$1.50 per 1M input tokens
- **Azure Machine Learning**: $50-100 (compute instances for evaluation)
- **Storage Account**: $5-15 (data storage and transactions)
- **Application Insights**: $2-10 (monitoring and logs)
- **Key Vault**: $1-3 (secret operations)

**Total Estimated Cost**: $58-328+ per month (heavily dependent on model usage)

> **Note**: Costs vary significantly based on evaluation frequency, dataset size, and model usage. Monitor Azure Cost Management for accurate tracking.

## Security Features

This deployment implements Azure security best practices:

- **Managed Identity**: Used for secure service-to-service authentication
- **Key Vault Integration**: Secure storage of API keys and connection strings
- **Network Security**: Private endpoints for Azure OpenAI and Storage (optional)
- **RBAC**: Role-based access control for resource access
- **Resource Locks**: Prevention of accidental resource deletion
- **Audit Logging**: Activity logging through Azure Monitor

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name <your-resource-group> \
    --yes \
    --no-wait

# Or delete specific deployment
az deployment group delete \
    --resource-group <your-resource-group> \
    --name main
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="location=eastus" \
                 -var="resource_group_name=rg-ai-evaluation"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
# Script will remove all created resources
```

## Customization

### Adding Custom Models

To add additional Azure OpenAI model deployments, modify the IaC templates:

**Bicep**: Add new model deployment resources in `main.bicep`
**Terraform**: Add new `azurerm_cognitive_deployment` resources
**Scripts**: Add deployment commands in `deploy.sh`

### Scaling Configuration

Adjust model deployment capacity based on expected load:

```bash
# Increase model deployment capacity
az cognitiveservices account deployment create \
    --name <openai-resource-name> \
    --resource-group <resource-group-name> \
    --deployment-name gpt-4o-eval \
    --sku-capacity 20  # Increased from default 10
```

### Custom Evaluation Metrics

Extend the evaluation framework by:

1. Adding custom Python evaluation scripts
2. Modifying Prompt Flow evaluation templates
3. Creating additional Azure ML datasets
4. Implementing custom scoring algorithms

## Troubleshooting

### Common Issues

1. **Azure OpenAI Access Denied**:
   - Ensure your subscription has Azure OpenAI access
   - Check regional availability for required models
   - Verify quota limits in Azure portal

2. **Model Deployment Failures**:
   - Check Azure OpenAI quota limits
   - Verify model availability in target region
   - Ensure sufficient capacity allocation

3. **Storage Access Issues**:
   - Verify storage account permissions
   - Check managed identity configuration
   - Ensure network access rules allow connections

4. **Evaluation Job Failures**:
   - Check Azure ML compute availability
   - Verify dataset format and accessibility
   - Review evaluation flow code syntax

### Getting Help

- Review Azure AI Foundry documentation: [Azure AI Foundry Docs](https://learn.microsoft.com/en-us/azure/ai-foundry/)
- Check Azure OpenAI troubleshooting: [Azure OpenAI Docs](https://learn.microsoft.com/en-us/azure/cognitive-services/openai/)
- Azure support: Create support ticket in Azure portal

## Monitoring and Logging

Monitor your AI evaluation system using:

- **Application Insights**: Performance metrics and error tracking
- **Azure Monitor**: Resource health and usage metrics
- **Cost Management**: Track spending and optimization opportunities
- **Activity Log**: Audit trail of all resource operations

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure provider documentation for Terraform/Bicep
3. Consult Azure AI Foundry troubleshooting guides
4. Create GitHub issues for infrastructure code problems

## Contributing

To improve this IaC implementation:

1. Test changes in a development environment
2. Follow Azure naming conventions
3. Update documentation for any new features
4. Validate security best practices
5. Include cost impact analysis

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and adapt security settings for production use.