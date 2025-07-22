# Infrastructure as Code for Scalable Multi-Agent AI Orchestration Platform

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Scalable Multi-Agent AI Orchestration Platform".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (declarative ARM templates)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI (v2.60.0 or later) installed and configured
- Azure subscription with appropriate permissions for:
  - Azure AI Foundry Agent Service
  - Azure Container Apps
  - Azure Event Grid
  - Azure Storage
  - Azure Cosmos DB
  - Azure Application Insights
  - Azure Log Analytics
- Docker installed locally for container image building (if customizing agents)
- Basic understanding of containerization, event-driven architecture, and AI concepts
- Estimated cost: $50-100/day for development and testing workloads

## Architecture Overview

This solution deploys a multi-agent AI orchestration system with the following components:

- **Coordinator Agent**: Central orchestrator deployed as a Container App
- **Document Processing Agent**: Specialized agent for document analysis
- **Data Analysis Agent**: Agent focused on data processing and insights
- **Customer Service Agent**: Conversational AI agent for customer interactions
- **API Gateway**: External access point for client applications
- **Event Grid**: Event-driven communication between agents
- **Azure AI Foundry**: AI model hosting and agent services
- **Storage Services**: Azure Storage and Cosmos DB for data persistence
- **Monitoring**: Application Insights and Log Analytics for observability

## Quick Start

### Using Bicep

```bash
cd bicep/

# Create resource group
az group create \
    --name "rg-multiagent-orchestration" \
    --location "eastus"

# Deploy infrastructure
az deployment group create \
    --resource-group "rg-multiagent-orchestration" \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Configure environment variables (if needed)
source scripts/set-environment.sh
```

## Configuration

### Bicep Parameters

Edit `bicep/parameters.json` to customize your deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "resourcePrefix": {
      "value": "multiagent"
    },
    "location": {
      "value": "eastus"
    },
    "containerEnvironmentName": {
      "value": "cae-agents"
    },
    "aiFoundrySkuName": {
      "value": "S0"
    },
    "cosmosDbThroughput": {
      "value": 400
    },
    "enableMonitoring": {
      "value": true
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize your deployment:

```hcl
resource_group_name = "rg-multiagent-orchestration"
location           = "eastus"
resource_prefix    = "multiagent"
environment        = "dev"

# Container Apps Configuration
container_environment_name = "cae-agents"
min_replicas              = 1
max_replicas              = 10

# AI Foundry Configuration
ai_foundry_sku = "S0"
ai_model_deployments = [
  {
    name    = "gpt-4-deployment"
    model   = "gpt-4"
    version = "0613"
    capacity = 10
  }
]

# Storage Configuration
storage_account_tier = "Standard"
storage_replication  = "LRS"

# Cosmos DB Configuration
cosmos_throughput = 400
cosmos_consistency_level = "Session"

# Monitoring Configuration
enable_monitoring = true
log_retention_days = 30

# Tags
tags = {
  Environment = "development"
  Purpose     = "multi-agent-orchestration"
  Owner       = "ai-team"
}
```

### Environment Variables

Key environment variables used by the deployment:

```bash
# Core Configuration
export RESOURCE_GROUP="rg-multiagent-orchestration"
export LOCATION="eastus"
export RESOURCE_PREFIX="multiagent"

# Container Apps
export CONTAINER_ENVIRONMENT="cae-agents"
export API_GATEWAY_URL=""  # Set after deployment

# AI Services
export AI_FOUNDRY_ENDPOINT=""  # Set after deployment
export AI_FOUNDRY_KEY=""       # Set after deployment

# Event Grid
export EVENT_GRID_ENDPOINT=""  # Set after deployment
export EVENT_GRID_KEY=""       # Set after deployment

# Storage
export STORAGE_CONNECTION_STRING=""  # Set after deployment
export COSMOS_CONNECTION_STRING=""   # Set after deployment

# Monitoring
export APPINSIGHTS_CONNECTION_STRING=""  # Set after deployment
```

## Deployment Process

### 1. Pre-Deployment Validation

```bash
# Verify Azure CLI login
az account show

# Check required permissions
az provider show --namespace Microsoft.App --query "registrationState"
az provider show --namespace Microsoft.CognitiveServices --query "registrationState"
az provider show --namespace Microsoft.EventGrid --query "registrationState"

# Validate location availability
az account list-locations --query "[?name=='eastus'].{Name:name,DisplayName:displayName}" --output table
```

### 2. Infrastructure Deployment

Choose your preferred deployment method:

#### Option A: Bicep Deployment
```bash
# Deploy main infrastructure
az deployment group create \
    --resource-group "rg-multiagent-orchestration" \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json

# Verify deployment
az deployment group show \
    --resource-group "rg-multiagent-orchestration" \
    --name "main" \
    --query "properties.provisioningState"
```

#### Option B: Terraform Deployment
```bash
# Initialize and deploy
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Verify deployment
terraform show
```

#### Option C: Bash Script Deployment
```bash
# Run deployment script
./scripts/deploy.sh

# Check deployment status
./scripts/check-deployment.sh
```

### 3. Post-Deployment Configuration

```bash
# Configure agent communication
az eventgrid event-subscription create \
    --name "agent-orchestration" \
    --source-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/egt-agent-events" \
    --endpoint-type "webhook" \
    --endpoint "https://coordinator-agent.${CONTAINER_ENVIRONMENT}.azurecontainerapps.io/api/events"

# Deploy custom agent containers (if needed)
az containerapp update \
    --name "document-agent" \
    --resource-group ${RESOURCE_GROUP} \
    --image "your-registry/document-agent:latest"
```

## Validation & Testing

### 1. Infrastructure Validation

```bash
# Check Container Apps status
az containerapp list \
    --resource-group ${RESOURCE_GROUP} \
    --query "[].{Name:name,Status:properties.runningStatus}" \
    --output table

# Verify Event Grid topic
az eventgrid topic show \
    --name "egt-agent-events" \
    --resource-group ${RESOURCE_GROUP} \
    --query "provisioningState"

# Check AI Foundry deployment
az cognitiveservices account show \
    --name "aif-orchestration" \
    --resource-group ${RESOURCE_GROUP} \
    --query "properties.provisioningState"
```

### 2. Functional Testing

```bash
# Test API Gateway endpoint
curl -X GET "https://$(az containerapp show --name api-gateway --resource-group ${RESOURCE_GROUP} --query properties.configuration.ingress.fqdn -o tsv)/health"

# Test Event Grid publishing
az eventgrid event publish \
    --topic-name "egt-agent-events" \
    --resource-group ${RESOURCE_GROUP} \
    --events '[{
        "id": "test-001",
        "subject": "test/workflow",
        "eventType": "Workflow.Test",
        "data": {"test": true}
    }]'

# Test agent endpoints
curl -X GET "https://coordinator-agent.${CONTAINER_ENVIRONMENT}.azurecontainerapps.io/health"
```

### 3. Performance Testing

```bash
# Load test API Gateway
ab -n 100 -c 10 "https://$(az containerapp show --name api-gateway --resource-group ${RESOURCE_GROUP} --query properties.configuration.ingress.fqdn -o tsv)/api/health"

# Monitor container app metrics
az monitor metrics list \
    --resource "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.App/containerApps/coordinator-agent" \
    --metric "Requests" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S)
```

## Monitoring & Observability

### Application Insights Integration

```bash
# View application logs
az monitor app-insights query \
    --app "multi-agent-insights" \
    --analytics-query "traces | where message contains 'agent' | limit 50"

# Check performance metrics
az monitor app-insights query \
    --app "multi-agent-insights" \
    --analytics-query "requests | summarize avg(duration) by bin(timestamp, 5m) | render timechart"
```

### Log Analytics Queries

```kusto
// Agent health monitoring
ContainerAppConsoleLogs_CL
| where ContainerAppName_s contains "agent"
| where Log_s contains "health"
| summarize count() by ContainerAppName_s, bin(TimeGenerated, 5m)

// Event Grid message processing
AzureActivity
| where ResourceProvider == "Microsoft.EventGrid"
| where OperationName == "Publish Events"
| summarize count() by bin(TimeGenerated, 1h)

// Container scaling events
ContainerAppSystemLogs_CL
| where Log_s contains "scaling"
| project TimeGenerated, ContainerAppName_s, Log_s
```

## Troubleshooting

### Common Issues

1. **Container App Deployment Failures**
   ```bash
   # Check deployment logs
   az containerapp logs show \
       --name "coordinator-agent" \
       --resource-group ${RESOURCE_GROUP} \
       --follow
   
   # Verify environment configuration
   az containerapp env show \
       --name ${CONTAINER_ENVIRONMENT} \
       --resource-group ${RESOURCE_GROUP}
   ```

2. **Event Grid Connection Issues**
   ```bash
   # Test Event Grid connectivity
   az eventgrid topic show \
       --name "egt-agent-events" \
       --resource-group ${RESOURCE_GROUP} \
       --query "endpoint"
   
   # Check event subscriptions
   az eventgrid event-subscription list \
       --source-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/egt-agent-events"
   ```

3. **AI Foundry Service Issues**
   ```bash
   # Check AI service status
   az cognitiveservices account show \
       --name "aif-orchestration" \
       --resource-group ${RESOURCE_GROUP} \
       --query "properties.provisioningState"
   
   # Verify model deployments
   az cognitiveservices account deployment list \
       --name "aif-orchestration" \
       --resource-group ${RESOURCE_GROUP}
   ```

### Debug Commands

```bash
# Enable detailed logging
export AZURE_DEBUG=true

# Check resource provider registrations
az provider list --query "[?contains(namespace, 'Microsoft.App') || contains(namespace, 'Microsoft.CognitiveServices') || contains(namespace, 'Microsoft.EventGrid')].{Namespace:namespace, Status:registrationState}" --output table

# Validate network connectivity
az network vnet list --resource-group ${RESOURCE_GROUP}
az network nsg list --resource-group ${RESOURCE_GROUP}
```

## Cleanup

### Using Bicep
```bash
# Delete resource group (removes all resources)
az group delete \
    --name "rg-multiagent-orchestration" \
    --yes \
    --no-wait
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource removal
az group exists --name "rg-multiagent-orchestration"
```

### Manual Cleanup (if needed)
```bash
# Stop all container apps first
az containerapp list \
    --resource-group ${RESOURCE_GROUP} \
    --query "[].name" \
    --output tsv | \
xargs -I {} az containerapp update \
    --name {} \
    --resource-group ${RESOURCE_GROUP} \
    --min-replicas 0 \
    --max-replicas 0

# Delete Event Grid subscriptions
az eventgrid event-subscription list \
    --source-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/egt-agent-events" \
    --query "[].name" \
    --output tsv | \
xargs -I {} az eventgrid event-subscription delete \
    --name {} \
    --source-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/egt-agent-events"

# Delete resource group
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait
```

## Security Considerations

- All services use managed identities for authentication
- Event Grid topics are secured with access keys
- Container Apps use internal ingress for agent communication
- AI Foundry endpoints are protected with API keys
- Storage accounts use Azure AD authentication
- Network security groups restrict traffic flow
- Application Insights data is encrypted at rest

## Cost Optimization

- Container Apps scale to zero when not in use
- Use consumption-based pricing for Event Grid
- Optimize AI model deployments based on usage patterns
- Configure appropriate retention policies for logs
- Use Azure Cost Management for monitoring

## Support

For issues with this infrastructure code, refer to:
- Original recipe documentation
- [Azure Container Apps documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Azure AI Foundry documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/)
- [Azure Event Grid documentation](https://learn.microsoft.com/en-us/azure/event-grid/)

## Contributing

When modifying this infrastructure code:
1. Test changes in a development environment
2. Update documentation accordingly
3. Validate security configurations
4. Update cost estimates if needed
5. Test cleanup procedures