# Infrastructure as Code for Model Improvement Pipeline with Stored Completions and Prompt Flow

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Model Improvement Pipeline with Stored Completions and Prompt Flow".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts for direct Azure CLI usage

## Architecture Overview

This infrastructure deploys an automated AI model improvement pipeline that:

- Captures conversation data using Azure OpenAI's Stored Completions API
- Analyzes interaction patterns with Prompt Flow evaluation workflows  
- Generates actionable insights through Azure Functions orchestration
- Provides continuous feedback collection and automated pattern detection

### Deployed Resources

- Azure OpenAI Service with GPT-4o model deployment
- Azure Machine Learning workspace for Prompt Flow
- Azure Storage Account with containers for pipeline data
- Azure Functions App for pipeline automation
- Log Analytics workspace for monitoring
- Diagnostic settings for comprehensive observability

## Prerequisites

### Required Tools

- Azure CLI (version 2.50.0 or later) installed and configured
- Azure subscription with the following permissions:
  - Cognitive Services Contributor (for Azure OpenAI)
  - Machine Learning Contributor (for ML workspace)
  - Storage Account Contributor (for data storage)
  - Function App Contributor (for serverless automation)
  - Monitor Contributor (for logging and alerts)

### Required Knowledge

- Basic understanding of AI model evaluation and prompt engineering concepts
- Python 3.8+ knowledge for custom evaluation flows
- Familiarity with Azure resource management

### Cost Considerations

- Estimated cost: $20-40 for recipe completion
- Includes OpenAI API calls, compute resources, and storage
- Consider using Azure pricing calculator for production estimates

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone or navigate to the recipe directory
cd azure/model-improvement-stored-completions-prompt-flow/code/

# Deploy using Bicep
az deployment group create \
    --resource-group myResourceGroup \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters uniqueSuffix=$(openssl rand -hex 3)
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the interactive prompts to configure your deployment
```

## Configuration Parameters

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `eastus` | Azure region for resource deployment |
| `uniqueSuffix` | string | `[generated]` | Unique suffix for resource names |
| `openAiServiceName` | string | `openai-service-{suffix}` | Name for Azure OpenAI service |
| `functionAppName` | string | `func-insights-{suffix}` | Name for Azure Functions app |
| `storageAccountName` | string | `st{suffix}pipeline` | Name for storage account |
| `mlWorkspaceName` | string | `mlw-pipeline-{suffix}` | Name for ML workspace |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `resource_group_name` | string | `rg-model-pipeline` | Resource group name |
| `location` | string | `East US` | Azure region |
| `unique_suffix` | string | `[random]` | Unique suffix for resources |
| `openai_model_name` | string | `gpt-4o` | OpenAI model to deploy |
| `openai_model_version` | string | `2024-08-06` | Model version |
| `function_app_runtime` | string | `python` | Runtime for Functions |

## Post-Deployment Configuration

After infrastructure deployment, complete these additional setup steps:

### 1. Configure Stored Completions

```bash
# Set environment variables (from deployment outputs)
export OPENAI_ENDPOINT="<your-openai-endpoint>"
export OPENAI_API_KEY="<your-openai-key>"

# Test stored completions functionality
python3 -c "
from openai import AzureOpenAI
import os

client = AzureOpenAI(
    azure_endpoint=os.environ['OPENAI_ENDPOINT'],
    api_key=os.environ['OPENAI_API_KEY'],
    api_version='2025-02-01-preview'
)

# Test conversation with stored completions
completion = client.chat.completions.create(
    model='gpt-4o-deployment',
    store=True,
    metadata={'test': 'pipeline_setup'},
    messages=[{'role': 'user', 'content': 'Hello, testing stored completions!'}]
)

print(f'Test completion ID: {completion.id}')
"
```

### 2. Set Up Prompt Flow Evaluation

```bash
# Install required packages
pip install azure-ai-ml azure-identity promptflow

# Configure ML workspace connection
az ml workspace show --name <your-ml-workspace> --resource-group <your-rg>
```

### 3. Verify Function App Configuration

```bash
# Check function app settings
az functionapp config appsettings list \
    --name <your-function-app> \
    --resource-group <your-rg>

# Test function execution
az functionapp function invoke \
    --name <your-function-app> \
    --resource-group <your-rg> \
    --function-name "analyze_stored_completions"
```

## Monitoring and Observability

### Log Analytics Queries

Monitor your pipeline using these sample queries:

```kusto
// Function execution logs
FunctionAppLogs
| where TimeGenerated > ago(1h)
| where Category == "Function.analyze_stored_completions"
| project TimeGenerated, Level, Message

// Pipeline performance metrics
customMetrics
| where name == "conversation_analysis_duration"
| summarize avg(value) by bin(timestamp, 5m)
```

### Setting Up Alerts

```bash
# Create alert rule for pipeline failures
az monitor metrics alert create \
    --name "pipeline-failure-alert" \
    --resource-group <your-rg> \
    --scopes <function-app-resource-id> \
    --condition "count FunctionErrors > 5" \
    --window-size 5m \
    --evaluation-frequency 1m
```

## Customization

### Adding Custom Evaluation Metrics

1. Modify the Prompt Flow configuration in `flow_components/`
2. Update the Function App code to include new metrics
3. Redeploy using your chosen IaC method

### Scaling Configuration

- **Azure OpenAI**: Adjust model capacity in deployment parameters
- **Functions**: Configure consumption plan scaling limits
- **Storage**: Enable geo-redundancy for production workloads
- **ML Workspace**: Configure compute clusters for larger evaluation workloads

### Security Enhancements

- Enable Azure Private Link for services
- Configure network security groups
- Implement customer-managed encryption keys
- Set up Azure Key Vault for secrets management

## Troubleshooting

### Common Issues

1. **OpenAI Service Creation Fails**
   ```bash
   # Check regional availability
   az cognitiveservices account list-skus --location eastus --kind OpenAI
   ```

2. **Function App Deployment Issues**
   ```bash
   # Check logs
   az functionapp logs tail --name <function-app> --resource-group <rg>
   ```

3. **ML Workspace Access Issues**
   ```bash
   # Verify permissions
   az role assignment list --assignee <user-id> --resource-group <rg>
   ```

### Performance Optimization

- Monitor storage costs and implement lifecycle policies
- Optimize Function App memory allocation based on usage patterns  
- Configure Azure OpenAI rate limiting for cost control
- Use Azure Monitor to identify performance bottlenecks

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name <your-resource-group> --yes --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
az resource list --resource-group <your-rg> --output table

# Check for any remaining storage data
az storage account list --resource-group <your-rg>
```

## Production Considerations

### Security Hardening

- Enable Azure AD authentication for all services
- Configure network access restrictions
- Implement resource-specific managed identities
- Enable audit logging for compliance requirements

### High Availability

- Deploy across multiple availability zones
- Configure geo-redundant storage
- Implement multi-region disaster recovery
- Set up automated backup strategies

### Cost Optimization

- Implement resource tagging for cost allocation
- Configure auto-shutdown for development environments
- Use Azure Reservations for predictable workloads
- Monitor and optimize OpenAI token usage

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# Azure DevOps Pipeline example
trigger:
  branches:
    include:
    - main
  paths:
    include:
    - azure/model-improvement-stored-completions-prompt-flow/

stages:
- stage: Deploy
  jobs:
  - job: DeployInfrastructure
    steps:
    - task: AzureCLI@2
      inputs:
        azureSubscription: 'your-service-connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          az deployment group create \
            --resource-group $(resourceGroup) \
            --template-file bicep/main.bicep \
            --parameters uniqueSuffix=$(Build.BuildId)
```

### Monitoring Dashboard

```json
{
  "dashboard": {
    "tiles": [
      {
        "title": "Pipeline Execution Rate",
        "visualization": "timechart",
        "query": "FunctionAppLogs | where Category == 'Function.analyze_stored_completions' | summarize count() by bin(TimeGenerated, 1h)"
      },
      {
        "title": "Conversation Quality Trends", 
        "visualization": "linechart",
        "query": "customMetrics | where name == 'average_quality_score' | render timechart"
      }
    ]
  }
}
```

## Support and Resources

### Documentation Links

- [Azure OpenAI Stored Completions](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/stored-completions)
- [Prompt Flow Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/concepts/prompt-flow)
- [Azure Functions AI Integration](https://learn.microsoft.com/en-us/azure/azure-functions/functions-create-ai-enabled-apps)
- [Azure Machine Learning MLOps](https://learn.microsoft.com/en-us/azure/machine-learning/concept-model-management-and-deployment)

### Community Resources

- [Azure AI Samples Repository](https://github.com/Azure-Samples/azure-ai-ml-samples)
- [Prompt Flow Community](https://github.com/microsoft/promptflow)
- [Azure Functions Community](https://github.com/Azure/azure-functions)

### Getting Help

1. Review the original recipe documentation for implementation details
2. Check Azure service health status for regional issues  
3. Consult Azure support documentation for service-specific troubleshooting
4. Use Azure CLI `--debug` flag for detailed error information

---

**Note**: This infrastructure code implements the complete solution described in the original recipe. Refer to the recipe documentation for detailed explanations of the architecture and implementation patterns.