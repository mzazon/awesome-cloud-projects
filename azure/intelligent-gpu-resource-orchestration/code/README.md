# Infrastructure as Code for Intelligent GPU Resource Orchestration with Container Apps and Azure Batch

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent GPU Resource Orchestration with Container Apps and Azure Batch".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.57.0+ installed and configured
- Appropriate Azure subscription with permissions for:
  - Container Apps
  - Azure Batch
  - Azure Monitor
  - Azure Key Vault
  - Storage Accounts
  - Function Apps
  - Log Analytics
- GPU quota approval for both Container Apps serverless GPUs and Batch GPU VMs
- Docker knowledge for containerization
- Estimated cost: $50-200/day depending on GPU usage (T4: ~$0.526/hour, A100: ~$3.06/hour)

## Quick Start

### Using Bicep (Recommended)

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription "your-subscription-id"

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-gpu-orchestration" \
    --template-file bicep/main.bicep \
    --parameters location=westus3 \
    --parameters uniqueSuffix=$(openssl rand -hex 3)
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
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This solution deploys:

- **Azure Container Apps Environment**: Serverless container hosting with GPU support
- **Azure Container Apps**: ML inference application with auto-scaling
- **Azure Batch Account**: Managed compute service for batch processing
- **Azure Batch Pool**: GPU-enabled VM pool with auto-scaling
- **Azure Key Vault**: Secure configuration management
- **Azure Storage Account**: Queue management and function app storage
- **Azure Function App**: Intelligent request routing logic
- **Azure Monitor**: Comprehensive monitoring and alerting
- **Log Analytics Workspace**: Centralized logging and analytics

## Configuration Parameters

### Common Parameters

- `location`: Azure region (default: westus3)
- `resourceGroupName`: Resource group name (default: rg-gpu-orchestration)
- `uniqueSuffix`: Unique suffix for resource names (auto-generated)

### GPU Configuration

- `acaGpuType`: Container Apps GPU type (T4 or A100)
- `batchVmSize`: Batch pool VM size (default: Standard_NC6s_v3)
- `maxAcaReplicas`: Maximum Container Apps replicas (default: 10)
- `maxBatchNodes`: Maximum Batch pool nodes (default: 4)

### Cost Optimization

- `useLowPriorityVMs`: Use low-priority VMs for Batch (default: true)
- `realtimeThresholdMs`: Response time threshold for routing (default: 2000)
- `batchCostThreshold`: Cost threshold for batch processing (default: 0.50)

## Post-Deployment Setup

### 1. Configure ML Model

```bash
# Set environment variables
export RESOURCE_GROUP="rg-gpu-orchestration"
export ACA_APP="ml-inference-app"

# Update Container App with your ML model
az containerapp update \
    --name ${ACA_APP} \
    --resource-group ${RESOURCE_GROUP} \
    --image "your-registry/ml-model:latest" \
    --set-env-vars "MODEL_PATH=/models" "GPU_ENABLED=true"
```

### 2. Upload Batch Processing Script

```bash
# Upload your batch processing script to storage
export STORAGE_ACCOUNT="storage$(openssl rand -hex 3)"
az storage blob upload \
    --account-name ${STORAGE_ACCOUNT} \
    --container-name batch-scripts \
    --file batch_inference.py \
    --name batch_inference.py
```

### 3. Configure Function App Code

```bash
# Deploy function app code
export FUNCTION_APP="router-func-$(openssl rand -hex 3)"
func azure functionapp publish ${FUNCTION_APP} --python
```

## Monitoring and Observability

### Key Metrics to Monitor

- **Container Apps GPU Utilization**: Track serverless GPU usage
- **Batch Pool Utilization**: Monitor batch processing efficiency
- **Queue Depth**: Observe batch job backlog
- **Response Times**: Monitor inference latency
- **Cost Metrics**: Track GPU spending

### Accessing Logs

```bash
# View Container Apps logs
az containerapp logs show \
    --name ${ACA_APP} \
    --resource-group ${RESOURCE_GROUP} \
    --follow

# Query Log Analytics
az monitor log-analytics query \
    --workspace ${LOG_WORKSPACE} \
    --analytics-query "ContainerAppConsoleLogs_CL | where ContainerName_s == 'ml-inference-app' | limit 100"
```

## Scaling Configuration

### Container Apps Auto-Scaling

The Container Apps instance automatically scales based on:
- HTTP request volume
- GPU utilization
- Custom metrics from Azure Monitor

### Batch Pool Auto-Scaling

The Batch pool scales based on:
- Pending tasks in the queue
- Auto-scale formula: `$TargetDedicatedNodes = min($PendingTasks.GetSample(180 * TimeInterval_Second, 70 * TimeInterval_Second), 4)`
- Evaluation interval: 5 minutes

## Security Considerations

### Access Control

- **Managed Identity**: Function App uses system-assigned managed identity
- **RBAC**: Role-based access control for all resources
- **Key Vault**: Secure secret management with access policies

### Network Security

- **Private Endpoints**: Configure for production deployments
- **Network Security Groups**: Restrict access to necessary ports
- **VNet Integration**: Isolate resources within virtual network

### Data Protection

- **Encryption**: All data encrypted at rest and in transit
- **Secrets Management**: No hardcoded secrets in code
- **Audit Logging**: Comprehensive audit trail in Azure Monitor

## Troubleshooting

### Common Issues

1. **GPU Quota Exceeded**
   ```bash
   # Check GPU quota
   az vm list-usage --location westus3 --query "[?contains(name.value, 'GPU')]"
   
   # Request quota increase through Azure Support
   ```

2. **Container Apps Not Scaling**
   ```bash
   # Check scaling configuration
   az containerapp show \
       --name ${ACA_APP} \
       --resource-group ${RESOURCE_GROUP} \
       --query "properties.template.scale"
   ```

3. **Batch Pool Creation Failed**
   ```bash
   # Check Batch account status
   az batch account show \
       --name ${BATCH_ACCOUNT} \
       --resource-group ${RESOURCE_GROUP}
   ```

### Log Analysis

```bash
# Function App logs
az functionapp log tail \
    --name ${FUNCTION_APP} \
    --resource-group ${RESOURCE_GROUP}

# Batch job logs
az batch task file list \
    --job-id ${JOB_ID} \
    --task-id ${TASK_ID}
```

## Cost Optimization

### Cost Management Tips

1. **Use Low-Priority VMs**: 80% cost savings for Batch workloads
2. **Right-Size Resources**: Match GPU types to workload requirements
3. **Auto-Scaling**: Ensure scale-to-zero for idle periods
4. **Monitoring**: Set up cost alerts and budgets

### Cost Estimation

- **Container Apps GPU**: ~$0.526/hour for T4, ~$3.06/hour for A100
- **Batch Low-Priority VMs**: ~$0.10/hour for Standard_NC6s_v3
- **Storage**: ~$0.02/GB/month for queue storage
- **Function Apps**: Consumption plan (~$0.20/million executions)

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name "rg-gpu-orchestration" \
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

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
az resource list \
    --resource-group "rg-gpu-orchestration" \
    --output table

# Check for soft-deleted Key Vault
az keyvault list-deleted \
    --query "[?properties.tags.purpose=='gpu-orchestration']"
```

## Advanced Configuration

### Custom Routing Logic

Modify the Function App to implement custom routing based on:
- Model complexity requirements
- Cost optimization policies
- SLA requirements
- Geographic distribution

### Multi-Region Deployment

Deploy across multiple regions for:
- High availability
- Disaster recovery
- Geographic load distribution
- Compliance requirements

### Integration with ML Pipelines

Connect with Azure Machine Learning for:
- Model deployment automation
- A/B testing capabilities
- Model monitoring and drift detection
- Automated retraining workflows

## Support and Documentation

### Additional Resources

- [Azure Container Apps GPU Documentation](https://learn.microsoft.com/en-us/azure/container-apps/gpu-serverless-overview)
- [Azure Batch GPU Capabilities](https://learn.microsoft.com/en-us/azure/batch/batch-pool-compute-intensive-sizes)
- [Azure Well-Architected Framework](https://learn.microsoft.com/en-us/azure/well-architected/)
- [Azure Cost Optimization Guide](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/cost-optimization)

### Getting Help

- Review the original recipe documentation for detailed implementation steps
- Check Azure service documentation for specific configuration options
- Use Azure Support for quota requests and technical issues
- Monitor Azure Service Health for service-specific announcements

## Customization

### Environment-Specific Modifications

1. **Development Environment**
   - Reduce max replicas and nodes
   - Use smaller GPU types
   - Enable additional logging

2. **Production Environment**
   - Implement private endpoints
   - Configure backup and disaster recovery
   - Set up comprehensive monitoring

3. **Cost-Optimized Environment**
   - Maximize low-priority VM usage
   - Implement aggressive auto-scaling
   - Use spot instances where possible

### Performance Tuning

- Adjust auto-scaling parameters based on workload patterns
- Optimize container images for faster startup
- Configure appropriate resource limits
- Implement caching strategies for frequently used models

This infrastructure provides a robust foundation for dynamic GPU resource allocation while maintaining flexibility for customization based on specific requirements and constraints.