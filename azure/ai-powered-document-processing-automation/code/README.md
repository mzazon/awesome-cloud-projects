# Infrastructure as Code for AI-Powered Document Processing Automation with OpenAI Assistants

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI-Powered Document Processing Automation with OpenAI Assistants".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions
- Azure OpenAI Service access (requires approval)
- Docker (for container image building)
- The following Azure resource providers registered:
  - Microsoft.CognitiveServices
  - Microsoft.ServiceBus
  - Microsoft.ContainerRegistry
  - Microsoft.App
  - Microsoft.OperationalInsights
  - Microsoft.Insights

## Required Permissions

Your Azure account needs the following permissions:
- Contributor role on the target subscription or resource group
- User Access Administrator (for managed identity assignments)
- Azure OpenAI Service access (separate approval required)

## Architecture Overview

This solution deploys:
- Azure OpenAI Service with GPT-4 model for intelligent document processing
- Azure Service Bus (namespace, queue, topic, and subscription) for message orchestration
- Azure Container Registry for storing job container images
- Azure Container Apps Environment for serverless job execution
- Azure Container Apps Jobs with event-driven scaling
- Azure Monitor and Log Analytics for observability
- Application Insights for OpenAI monitoring

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group your-resource-group \
    --template-file main.bicep \
    --parameters @parameters.json

# Or deploy with inline parameters
az deployment group create \
    --resource-group your-resource-group \
    --template-file main.bicep \
    --parameters location=eastus uniqueSuffix=abc123
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts and wait for deployment to complete
```

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize your deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "uniqueSuffix": {
      "value": "your-unique-suffix"
    },
    "openAiSkuName": {
      "value": "S0"
    },
    "serviceBusSkuName": {
      "value": "Standard"
    }
  }
}
```

### Terraform Variables

Customize `terraform/terraform.tfvars`:

```hcl
location = "East US"
resource_group_name = "rg-intelligent-automation"
unique_suffix = "your-unique-suffix"
openai_sku_name = "S0"
servicebus_sku_name = "Standard"
tags = {
  environment = "development"
  project = "intelligent-automation"
}
```

## Post-Deployment Steps

After successful infrastructure deployment, complete these additional setup steps:

### 1. Build and Push Container Images

```bash
# Set environment variables (replace with your values)
export CONTAINER_REGISTRY="acr${UNIQUE_SUFFIX}.azurecr.io"
export RESOURCE_GROUP="your-resource-group"

# Login to Azure Container Registry
az acr login --name acr${UNIQUE_SUFFIX}

# Build the processing job image
docker build -t processing-job:latest -f scripts/processing-job.dockerfile .

# Tag and push the image
docker tag processing-job:latest ${CONTAINER_REGISTRY}/processing-job:latest
docker push ${CONTAINER_REGISTRY}/processing-job:latest
```

### 2. Create Azure OpenAI Assistant

```bash
# Get the OpenAI endpoint and key from deployment outputs
export OPENAI_ENDPOINT=$(az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --query properties.outputs.openAiEndpoint.value \
    --output tsv)

export OPENAI_KEY=$(az cognitiveservices account keys list \
    --name openai-automation-${UNIQUE_SUFFIX} \
    --resource-group ${RESOURCE_GROUP} \
    --query key1 \
    --output tsv)

# Run the assistant creation script
python scripts/create_assistant.py
```

### 3. Deploy Container Apps Jobs

```bash
# Deploy the document processing job
az containerapp job create \
    --name document-processor \
    --resource-group ${RESOURCE_GROUP} \
    --environment aca-env-${UNIQUE_SUFFIX} \
    --image ${CONTAINER_REGISTRY}/processing-job:latest \
    --registry-server ${CONTAINER_REGISTRY} \
    --registry-identity system \
    --trigger-type Event \
    --replica-timeout 300 \
    --parallelism 3 \
    --scale-rule-name servicebus-scale \
    --scale-rule-type azure-servicebus \
    --scale-rule-metadata connectionFromEnv=SERVICEBUS_CONNECTION queueName=processing-queue messageCount=1 \
    --env-vars SERVICEBUS_CONNECTION=secretref:servicebus-connection \
    --secrets servicebus-connection="${SERVICEBUS_CONNECTION}"
```

## Testing the Solution

### 1. Send Test Message

```bash
# Send a test document processing request
az servicebus queue send \
    --name processing-queue \
    --namespace-name sb-automation-${UNIQUE_SUFFIX} \
    --resource-group ${RESOURCE_GROUP} \
    --messages '[{"document_id": "test-doc-001", "processing_type": "analysis", "priority": "high"}]'
```

### 2. Monitor Job Execution

```bash
# Check job execution status
az containerapp job execution list \
    --name document-processor \
    --resource-group ${RESOURCE_GROUP} \
    --output table

# View job logs
az containerapp job logs show \
    --name document-processor \
    --resource-group ${RESOURCE_GROUP}
```

### 3. Verify Message Processing

```bash
# Check Service Bus metrics
az servicebus queue show \
    --name processing-queue \
    --namespace-name sb-automation-${UNIQUE_SUFFIX} \
    --resource-group ${RESOURCE_GROUP} \
    --query "{ActiveMessages:countDetails.activeMessageCount, DeadLetterMessages:countDetails.deadLetterMessageCount}"
```

## Monitoring and Observability

### Access Azure Monitor

1. Navigate to Azure Portal
2. Go to your resource group
3. Open the Log Analytics workspace
4. Query container app logs:

```kusto
ContainerAppConsoleLogs_CL
| where ContainerName_s == "document-processor"
| order by TimeGenerated desc
```

### Application Insights

Monitor Azure OpenAI usage:
1. Open Application Insights resource
2. Navigate to Logs
3. Query API usage patterns

### Service Bus Metrics

Monitor message processing:
1. Open Service Bus namespace
2. View Metrics dashboard
3. Monitor queue depth and processing rates

## Troubleshooting

### Common Issues

1. **OpenAI Assistant Creation Fails**
   - Verify Azure OpenAI Service has the required model deployed
   - Check API key permissions
   - Ensure preview API version is supported

2. **Container Jobs Not Scaling**
   - Verify Service Bus connection string is correct
   - Check KEDA scaling configuration
   - Review Container Apps Job logs

3. **Container Registry Access Denied**
   - Ensure managed identity has AcrPull role
   - Verify registry admin user is enabled
   - Check network access rules

4. **High OpenAI API Costs**
   - Monitor token usage in Application Insights
   - Implement request throttling
   - Optimize assistant instructions

### Debug Commands

```bash
# Check resource deployment status
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main

# Verify Container Apps environment
az containerapp env show \
    --name aca-env-${UNIQUE_SUFFIX} \
    --resource-group ${RESOURCE_GROUP}

# Check Service Bus connection
az servicebus namespace authorization-rule keys list \
    --resource-group ${RESOURCE_GROUP} \
    --namespace-name sb-automation-${UNIQUE_SUFFIX} \
    --name RootManageSharedAccessKey
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name your-resource-group \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

### Manual Cleanup (if needed)

```bash
# Delete specific resources if automated cleanup fails
az cognitiveservices account delete \
    --name openai-automation-${UNIQUE_SUFFIX} \
    --resource-group ${RESOURCE_GROUP}

az servicebus namespace delete \
    --name sb-automation-${UNIQUE_SUFFIX} \
    --resource-group ${RESOURCE_GROUP}

az acr delete \
    --name acr${UNIQUE_SUFFIX} \
    --resource-group ${RESOURCE_GROUP} \
    --yes
```

## Security Considerations

### Production Deployment Recommendations

1. **Network Security**
   - Deploy resources in private virtual networks
   - Use private endpoints for Azure services
   - Implement network security groups

2. **Identity and Access**
   - Use managed identities for service-to-service authentication
   - Implement least privilege access principles
   - Enable Azure AD authentication where possible

3. **Data Protection**
   - Enable encryption at rest for all storage services
   - Use Azure Key Vault for sensitive configuration
   - Implement data classification and protection policies

4. **Monitoring and Compliance**
   - Enable Azure Security Center recommendations
   - Implement log retention policies
   - Set up security alerts and notifications

### Cost Optimization

1. **Azure OpenAI Usage**
   - Monitor token consumption patterns
   - Implement request caching where appropriate
   - Use appropriate model sizes for workloads

2. **Container Apps Scaling**
   - Configure appropriate scaling rules
   - Set resource limits for jobs
   - Monitor CPU and memory utilization

3. **Service Bus Optimization**
   - Use message batching for high-volume scenarios
   - Configure appropriate message TTL
   - Monitor and optimize partition counts

## Support and Documentation

- [Azure OpenAI Service Documentation](https://docs.microsoft.com/azure/cognitive-services/openai/)
- [Azure Container Apps Documentation](https://docs.microsoft.com/azure/container-apps/)
- [Azure Service Bus Documentation](https://docs.microsoft.com/azure/service-bus-messaging/)
- [Bicep Documentation](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or Azure support channels.

## Version Information

- Recipe Version: 1.0
- Infrastructure Code Version: 1.0
- Last Updated: 2025-07-12
- Compatible Azure CLI Version: 2.50.0+