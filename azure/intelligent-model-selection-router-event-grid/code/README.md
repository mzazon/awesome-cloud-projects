# Infrastructure as Code for Intelligent Model Selection with Model Router and Event Grid

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Model Selection with Model Router and Event Grid".

## Available Implementations

- **Bicep**: Azure native infrastructure as code
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.50+)
- Azure subscription with contributor permissions
- Access to Azure AI Foundry and Model Router preview features
- Basic understanding of serverless architectures and event-driven patterns

### Regional Requirements

> **Important**: Model Router is currently in preview and available in East US 2 and Sweden Central regions. Ensure your subscription has access to Azure AI Foundry preview features.

### Required Azure Resource Providers

```bash
az provider register --namespace Microsoft.CognitiveServices
az provider register --namespace Microsoft.EventGrid
az provider register --namespace Microsoft.Web
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.Storage
```

## Quick Start

### Using Bicep

Deploy the complete intelligent routing infrastructure:

```bash
# Login to Azure
az login

# Set subscription (optional)
az account set --subscription "your-subscription-id"

# Create resource group
az group create \
    --name "rg-intelligent-router" \
    --location "eastus2"

# Deploy infrastructure
az deployment group create \
    --resource-group "rg-intelligent-router" \
    --template-file bicep/main.bicep \
    --parameters environmentName="demo" \
                 location="eastus2"
```

### Using Terraform

Initialize and deploy with Terraform:

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="environment_name=demo" \
    -var="location=eastus2"

# Apply configuration
terraform apply \
    -var="environment_name=demo" \
    -var="location=eastus2"
```

### Using Bash Scripts

Execute the deployment script:

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration options
```

## Architecture Overview

The infrastructure creates an event-driven AI orchestration system with the following components:

- **Event Grid Topic**: Routes AI requests to processing functions
- **Azure Functions**: Processes requests and implements intelligent routing logic
- **Model Router Deployment**: Automatically selects optimal AI models based on complexity
- **Azure AI Foundry**: Provides foundational AI platform for model management
- **Application Insights**: Monitors performance and routing decisions
- **Storage Account**: Supports Azure Functions execution

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `environmentName` | Environment identifier | `demo` | Yes |
| `location` | Azure region | `eastus2` | Yes |
| `functionAppName` | Custom function app name | Generated | No |
| `storageAccountName` | Custom storage account name | Generated | No |
| `enableApplicationInsights` | Enable monitoring | `true` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `environment_name` | Environment identifier | `demo` | Yes |
| `location` | Azure region | `eastus2` | Yes |
| `resource_group_name` | Custom resource group name | Generated | No |
| `tags` | Resource tags | `{}` | No |

### Bash Script Configuration

The deployment script will prompt for:
- Environment name
- Azure region
- Resource naming preferences
- Monitoring configuration

## Post-Deployment Steps

After successful deployment, complete these steps:

1. **Verify Model Router Deployment**:
   ```bash
   # Check deployment status
   az cognitiveservices account deployment show \
       --name "ai-foundry-${ENVIRONMENT}" \
       --resource-group "rg-intelligent-router" \
       --deployment-name "model-router-deployment"
   ```

2. **Test Event Grid Integration**:
   ```bash
   # Send test event
   az eventgrid event send \
       --topic-name "egt-router-${ENVIRONMENT}" \
       --resource-group "rg-intelligent-router" \
       --events '[{
         "id": "test-001",
         "eventType": "AIRequest.Submitted",
         "subject": "test-request",
         "data": {
           "prompt": "What is artificial intelligence?",
           "request_id": "test-001"
         },
         "dataVersion": "1.0"
       }]'
   ```

3. **Monitor Function Execution**:
   ```bash
   # View function logs
   az monitor app-insights query \
       --app "ai-router-${ENVIRONMENT}" \
       --analytics-query "traces | where timestamp > ago(5m) | project timestamp, message"
   ```

## Testing the Solution

### Simple Request Test

Test intelligent routing with a basic query:

```bash
# Simple request that should route to a lightweight model
az eventgrid event send \
    --topic-name "egt-router-${ENVIRONMENT}" \
    --resource-group "rg-intelligent-router" \
    --events '[{
      "id": "simple-001",
      "eventType": "AIRequest.Submitted",
      "subject": "simple-request",
      "data": {
        "prompt": "Hello, how are you?",
        "request_id": "simple-001"
      },
      "dataVersion": "1.0"
    }]'
```

### Complex Request Test

Test with a complex reasoning query:

```bash
# Complex request that should route to a more capable model
az eventgrid event send \
    --topic-name "egt-router-${ENVIRONMENT}" \
    --resource-group "rg-intelligent-router" \
    --events '[{
      "id": "complex-001",
      "eventType": "AIRequest.Submitted",
      "subject": "complex-request",
      "data": {
        "prompt": "Please analyze the economic implications of artificial intelligence on job markets, considering both positive and negative impacts across different industries, and provide detailed reasoning for your conclusions with supporting evidence.",
        "request_id": "complex-001"
      },
      "dataVersion": "1.0"
    }]'
```

## Monitoring and Troubleshooting

### Application Insights Queries

Monitor model selection decisions:

```bash
# View routing decisions
az monitor app-insights query \
    --app "ai-router-${ENVIRONMENT}" \
    --analytics-query "
      traces
      | where message contains 'Selected model'
      | project timestamp, message
      | order by timestamp desc
      | take 20
    "
```

### Common Issues

1. **Model Router Deployment Failed**:
   - Verify region supports Model Router preview
   - Check subscription has AI Foundry access
   - Confirm resource group permissions

2. **Event Grid Not Triggering Functions**:
   - Verify event subscription endpoint
   - Check function app deployment status
   - Review Event Grid topic permissions

3. **Function Execution Errors**:
   - Check Application Insights logs
   - Verify environment variables configuration
   - Confirm AI Foundry endpoint connectivity

## Cost Optimization

The deployed infrastructure is designed for cost optimization:

- **Consumption-based Functions**: Pay only for actual executions
- **Model Router**: Automatically selects cost-effective models (30-50% savings)
- **Event Grid**: Pay-per-event pricing model
- **Application Insights**: Sampling configured to reduce ingestion costs

### Estimated Costs

For moderate usage (1000 requests/day):
- Azure Functions: ~$5-10/month
- Event Grid: ~$2-5/month
- AI Foundry/Model Router: ~$20-50/month (varies by model usage)
- Application Insights: ~$5-15/month
- Storage Account: ~$1-3/month

## Cleanup

### Using Bicep

```bash
# Delete resource group and all resources
az group delete \
    --name "rg-intelligent-router" \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy \
    -var="environment_name=demo" \
    -var="location=eastus2"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm deletion
```

## Security Considerations

The infrastructure implements several security best practices:

- **Managed Identity**: Functions use managed identity for Azure service authentication
- **Key Vault Integration**: Sensitive configuration stored in Azure Key Vault
- **Network Security**: Event Grid topics configured with access policies
- **RBAC**: Role-based access control for all resources
- **Encryption**: Data encrypted in transit and at rest

## Customization

### Adding Custom Models

To integrate additional models beyond the standard Model Router options:

1. Update the AI Foundry resource configuration
2. Modify the complexity analysis algorithm in function code
3. Add new routing logic for custom model selection

### Scaling Configuration

For higher throughput requirements:

1. Increase Function App hosting plan to Premium
2. Configure Event Grid topic for higher message throughput
3. Enable Azure Functions auto-scaling settings
4. Consider multi-region deployment for global distribution

### Advanced Monitoring

Enhance monitoring capabilities:

1. Add custom metrics for business KPIs
2. Configure automated alerts for cost thresholds
3. Implement distributed tracing across components
4. Set up dashboard for real-time monitoring

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service health status
3. Consult Azure AI Foundry documentation
4. Review Application Insights logs for detailed error information

## Additional Resources

- [Azure Model Router Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/concepts/model-router)
- [Azure Event Grid Best Practices](https://learn.microsoft.com/en-us/azure/event-grid/overview)
- [Azure Functions Performance Guide](https://learn.microsoft.com/en-us/azure/azure-functions/functions-best-practices)
- [Azure AI Foundry Getting Started](https://learn.microsoft.com/en-us/azure/ai-foundry/)