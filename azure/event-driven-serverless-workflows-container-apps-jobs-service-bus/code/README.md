# Infrastructure as Code for Event-Driven Serverless Workflows with Azure Container Apps Jobs and Azure Service Bus

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Event-Driven Serverless Workflows with Azure Container Apps Jobs and Azure Service Bus".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation deploys an event-driven serverless architecture that includes:

- Azure Container Apps Environment with Log Analytics
- Azure Service Bus Namespace and Queue
- Azure Container Registry for storing container images
- Azure Container Apps Job with KEDA-based event-driven scaling
- Monitoring and alerting with Azure Monitor

## Prerequisites

- Azure CLI 2.51.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Container Apps and Container Registry
  - Service Bus messaging
  - Log Analytics and Azure Monitor
  - Resource group creation
- Docker Desktop or equivalent container runtime (for local development)
- Terraform 1.0+ (if using Terraform implementation)
- Basic understanding of containerization and message queues

### Required Azure Resource Providers

The following resource providers must be registered in your subscription:
- Microsoft.App
- Microsoft.ServiceBus
- Microsoft.ContainerRegistry
- Microsoft.OperationalInsights

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Review and customize parameters
cp parameters.json.example parameters.json
# Edit parameters.json with your values

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-container-jobs-demo \
    --template-file main.bicep \
    --parameters @parameters.json

# Get deployment outputs
az deployment group show \
    --resource-group rg-container-jobs-demo \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-container-jobs-demo"
export LOCATION="eastus"
export CONTAINER_REGISTRY_NAME="acrjobs$(date +%s)"
export SERVICE_BUS_NAMESPACE="sb-container-jobs-$(date +%s)"

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/status.sh
```

## Configuration Parameters

### Key Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `resourceGroupName` | Name of the resource group | `rg-container-jobs-demo` | Yes |
| `location` | Azure region for deployment | `eastus` | Yes |
| `environmentName` | Container Apps environment name | `env-container-jobs` | Yes |
| `serviceBusNamespace` | Service Bus namespace name | Generated with timestamp | Yes |
| `containerRegistryName` | Container registry name | Generated with timestamp | Yes |
| `queueName` | Service Bus queue name | `message-processing-queue` | Yes |
| `jobName` | Container Apps job name | `message-processor-job` | Yes |
| `containerImage` | Container image name and tag | `message-processor:1.0` | Yes |

### Scaling Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `minExecutions` | Minimum job executions | `0` |
| `maxExecutions` | Maximum job executions | `10` |
| `parallelism` | Parallel job executions | `5` |
| `pollingInterval` | KEDA polling interval | `30` seconds |
| `messageCount` | Messages per job trigger | `1` |

## Post-Deployment Steps

After deploying the infrastructure, you'll need to:

1. **Build and push your container image**:
   ```bash
   # Get registry credentials
   ACR_USERNAME=$(az acr credential show --name <registry-name> --query username -o tsv)
   ACR_PASSWORD=$(az acr credential show --name <registry-name> --query passwords[0].value -o tsv)
   
   # Build and push your message processor image
   az acr build --registry <registry-name> --image message-processor:1.0 .
   ```

2. **Test the event-driven workflow**:
   ```bash
   # Send test messages to trigger job executions
   for i in {1..5}; do
       az servicebus queue message send \
           --namespace-name <service-bus-namespace> \
           --queue-name message-processing-queue \
           --resource-group <resource-group> \
           --body "Test message $i - $(date)"
   done
   ```

3. **Monitor job executions**:
   ```bash
   # List job executions
   az containerapp job execution list \
       --name <job-name> \
       --resource-group <resource-group> \
       --output table
   
   # View job logs
   az containerapp job logs show \
       --name <job-name> \
       --resource-group <resource-group>
   ```

## Monitoring and Observability

The deployment includes comprehensive monitoring:

- **Log Analytics Workspace**: Centralized logging for all Container Apps
- **Azure Monitor Metrics**: Job execution metrics and performance data
- **Alert Rules**: Automated alerts for job failures and performance issues
- **Application Insights**: Optional for advanced application monitoring

### Key Metrics to Monitor

- Job execution count and success rate
- Message processing latency
- Queue depth and message age
- Resource utilization (CPU/Memory)
- Scaling events and duration

## Security Considerations

This implementation follows Azure security best practices:

- **Managed Identity**: Container Apps job uses managed identity for Azure resource access
- **Key Vault Integration**: Sensitive configuration stored in Azure Key Vault
- **Network Security**: Container Apps environment uses virtual network integration
- **Registry Security**: Container registry uses admin credentials (can be enhanced with managed identity)
- **Service Bus Security**: Uses connection string authentication (can be enhanced with managed identity)

### Security Enhancements

For production deployments, consider:
- Using managed identity instead of connection strings
- Implementing private endpoints for Container Registry and Service Bus
- Enabling Azure Defender for Containers
- Implementing network security groups and application security groups

## Cost Optimization

### Cost Factors

- **Container Apps Jobs**: Pay-per-execution model
- **Service Bus**: Based on message operations and storage
- **Container Registry**: Storage and bandwidth usage
- **Log Analytics**: Data ingestion and retention

### Cost Optimization Tips

- Configure appropriate scaling parameters to avoid over-provisioning
- Use Standard tier Service Bus only if premium features are needed
- Implement log retention policies in Log Analytics
- Monitor and optimize container image sizes
- Use Azure Cost Management for ongoing cost tracking

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-container-jobs-demo \
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
# Run the destroy script
./scripts/destroy.sh

# Verify cleanup
az group show --name rg-container-jobs-demo --query properties.provisioningState
```

## Troubleshooting

### Common Issues

1. **Job not triggering**: Check Service Bus connection string and queue permissions
2. **Container image pull failures**: Verify Container Registry credentials and image exists
3. **Scaling not working**: Review KEDA scaler configuration and Service Bus metrics
4. **Resource creation failures**: Check Azure resource provider registration and quotas

### Debug Commands

```bash
# Check Container Apps environment status
az containerapp env show --name <env-name> --resource-group <rg-name>

# Check job configuration
az containerapp job show --name <job-name> --resource-group <rg-name>

# View recent job executions
az containerapp job execution list --name <job-name> --resource-group <rg-name>

# Check Service Bus queue metrics
az servicebus queue show --name <queue-name> --namespace-name <namespace> --resource-group <rg-name>
```

## Customization

### Adding Custom Scaling Rules

Modify the Container Apps job scaling configuration to add additional triggers:

```bicep
scalingRules: [
  {
    name: 'servicebus-queue-rule'
    custom: {
      type: 'azure-servicebus'
      metadata: {
        queueName: queueName
        namespace: serviceBusNamespaceName
        messageCount: '1'
      }
      auth: [{
        secretRef: 'servicebus-connection-secret'
        triggerParameter: 'connection'
      }]
    }
  }
  // Add additional scaling rules here
]
```

### Implementing Multiple Queues

To process multiple queues, create additional Container Apps jobs or modify the existing job to handle multiple message types.

### Adding Dead Letter Queue Processing

Extend the solution with additional jobs for dead letter queue processing and error handling.

## Support and Documentation

- [Azure Container Apps Documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
- [Azure Service Bus Documentation](https://docs.microsoft.com/en-us/azure/service-bus-messaging/)
- [KEDA Scalers Documentation](https://keda.sh/docs/scalers/)
- [Azure Container Registry Documentation](https://docs.microsoft.com/en-us/azure/container-registry/)

For issues with this infrastructure code, refer to the original recipe documentation or the Azure service documentation.

## Version Information

- Infrastructure Code Version: 1.0
- Recipe Version: 1.0
- Last Updated: 2025-07-12
- Compatible with: Azure CLI 2.51.0+, Terraform 1.0+