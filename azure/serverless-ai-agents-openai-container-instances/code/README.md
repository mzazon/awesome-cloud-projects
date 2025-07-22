# Infrastructure as Code for Serverless AI Agents with OpenAI Service and Container Instances

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Serverless AI Agents with OpenAI Service and Container Instances".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions
- Docker installed locally for building container images
- Azure OpenAI Service access (requires approval at https://aka.ms/oai/access)
- Appropriate permissions for resource creation:
  - Contributor role on the subscription or resource group
  - Cognitive Services Contributor role for Azure OpenAI Service
  - Container Registry Contributor role for Azure Container Registry
  - Storage Account Contributor role for Azure Storage

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file bicep/main.bicep \
    --parameters bicep/parameters.json

# Build and push container image
az acr login --name <container-registry-name>
docker build -t <container-registry-name>.azurecr.io/ai-agent:latest .
docker push <container-registry-name>.azurecr.io/ai-agent:latest

# Deploy Function App code
cd scripts/
./deploy-function-app.sh
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# Build and push container image
az acr login --name $(terraform output -raw container_registry_name)
docker build -t $(terraform output -raw container_registry_login_server)/ai-agent:latest .
docker push $(terraform output -raw container_registry_login_server)/ai-agent:latest

# Deploy Function App code
cd ../scripts/
./deploy-function-app.sh
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# The script will:
# 1. Create all Azure resources
# 2. Build and push the container image
# 3. Deploy the Function App code
# 4. Configure monitoring and alerts
```

## Configuration

### Environment Variables

Before deployment, set these environment variables:

```bash
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export AZURE_LOCATION="eastus"
export RESOURCE_GROUP_NAME="rg-ai-agents"
export RANDOM_SUFFIX=$(openssl rand -hex 3)
```

### Customization Parameters

#### Bicep Parameters

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
      "value": "ai-agents"
    },
    "openAiSkuName": {
      "value": "S0"
    },
    "containerCpuCores": {
      "value": "1.0"
    },
    "containerMemoryInGb": {
      "value": "1.5"
    }
  }
}
```

#### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
location = "eastus"
resource_prefix = "ai-agents"
openai_sku_name = "S0"
container_cpu_cores = "1.0"
container_memory_in_gb = "1.5"
enable_monitoring = true
```

## Architecture

This solution deploys:

1. **Azure OpenAI Service** - Provides GPT-4 model for intelligent processing
2. **Azure Container Registry** - Stores the AI agent container images
3. **Azure Container Instances** - Serverless compute for agent execution
4. **Azure Functions** - API gateway for request handling
5. **Azure Event Grid** - Event-driven orchestration
6. **Azure Storage Account** - State management and result storage
7. **Application Insights** - Monitoring and observability
8. **Logic Apps** - Container instance orchestration

## Usage

### Submit an AI Agent Task

```bash
# Get the Function App URL
FUNCTION_URL=$(az functionapp function show \
    --name func-agents-${RANDOM_SUFFIX} \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --function-name agent-api \
    --query invokeUrlTemplate \
    --output tsv)

# Submit a task
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
      "prompt": "Analyze the benefits of serverless architectures for AI workloads"
    }'
```

### Monitor Agent Execution

```bash
# Check container instances
az container list \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --output table

# View agent logs
az container logs \
    --name <task-id> \
    --resource-group ${RESOURCE_GROUP_NAME}

# Check results in storage
az storage blob list \
    --container-name results \
    --account-name st${RANDOM_SUFFIX} \
    --output table
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name <your-resource-group> \
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
./scripts/destroy.sh
```

## Security Considerations

This implementation includes several security best practices:

- **Private Container Registry**: Images are stored in Azure Container Registry with admin access enabled only during deployment
- **Managed Identity**: Function Apps use managed identity for secure access to other Azure services
- **Key Vault Integration**: Sensitive values like API keys are stored in Azure Key Vault
- **Network Security**: Container instances run in isolated environments
- **RBAC**: Role-based access control is configured for all resources

## Monitoring and Observability

The solution includes comprehensive monitoring:

- **Application Insights**: End-to-end request tracking and performance monitoring
- **Azure Monitor**: Resource health and performance metrics
- **Custom Alerts**: Automated notifications for failures and performance issues
- **Log Analytics**: Centralized logging for all components

### Key Metrics to Monitor

- Function App execution time and success rate
- Container instance startup time and resource utilization
- Azure OpenAI Service token usage and response times
- Storage account throughput and capacity
- Event Grid message delivery rates

## Troubleshooting

### Common Issues

1. **Azure OpenAI Access Denied**
   - Ensure you have approved access to Azure OpenAI Service
   - Verify the deployment location supports OpenAI Service

2. **Container Instance Startup Failures**
   - Check container registry credentials
   - Verify image exists and is accessible
   - Review container environment variables

3. **Function App Deployment Issues**
   - Ensure all required app settings are configured
   - Check Function App runtime version compatibility
   - Verify Event Grid connection strings

### Debugging Steps

```bash
# Check resource deployment status
az deployment group show \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --name main

# View Function App logs
az functionapp logs tail \
    --name func-agents-${RANDOM_SUFFIX} \
    --resource-group ${RESOURCE_GROUP_NAME}

# Check Event Grid topic health
az eventgrid topic show \
    --name egt-agents-${RANDOM_SUFFIX} \
    --resource-group ${RESOURCE_GROUP_NAME}
```

## Cost Optimization

### Estimated Monthly Costs

- Azure OpenAI Service: $50-200 (depends on usage)
- Azure Functions: $10-50 (consumption plan)
- Container Instances: $20-100 (depends on execution frequency)
- Storage Account: $5-20
- Event Grid: $1-5
- Application Insights: $10-30

### Cost Optimization Tips

1. **Right-size Container Resources**: Adjust CPU and memory allocations based on actual usage
2. **Monitor OpenAI Token Usage**: Implement caching for similar requests
3. **Use Consumption Plans**: Functions and Container Instances auto-scale to zero
4. **Implement Request Throttling**: Prevent excessive API calls
5. **Archive Old Results**: Move processed results to cheaper storage tiers

## Performance Optimization

1. **Container Image Optimization**: Use multi-stage builds to minimize image size
2. **Parallel Processing**: Configure multiple container instances for high-throughput scenarios
3. **Caching**: Implement result caching for frequently requested analyses
4. **Regional Deployment**: Deploy in regions close to your users
5. **Connection Pooling**: Reuse connections to Azure services

## Compliance and Governance

- **Data Residency**: All data remains in your selected Azure region
- **Audit Logging**: All actions are logged in Azure Activity Log
- **Compliance**: Supports SOC, ISO, and other compliance frameworks
- **Data Encryption**: Data encrypted at rest and in transit
- **Access Controls**: Implement Azure AD integration for user authentication

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review Azure service documentation
3. Consult Azure support resources
4. Check the troubleshooting section above

## Contributing

To contribute improvements to this IaC:

1. Test changes in a development environment
2. Validate against the original recipe requirements
3. Update documentation as needed
4. Follow Azure best practices and naming conventions