# Infrastructure as Code for Scalable HPC Workload Processing with Elastic SAN and Azure Batch

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Scalable HPC Workload Processing with Elastic SAN and Azure Batch".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.50.0 or later)
- Azure subscription with appropriate permissions for:
  - Azure Elastic SAN (Premium storage)
  - Azure Batch service
  - Azure Virtual Network
  - Azure Storage Account
  - Azure Monitor and Log Analytics
- For Terraform: Terraform v1.0+ installed
- For Bicep: Bicep CLI installed
- Appropriate Azure RBAC permissions:
  - Contributor role on the subscription or resource group
  - Storage Account Contributor for storage operations
  - Network Contributor for VNet operations

## Architecture Overview

This solution deploys a complete HPC infrastructure including:
- Azure Elastic SAN for high-performance shared storage (up to 80,000 IOPS)
- Azure Batch for managed parallel processing
- Virtual Network with security groups for isolated communication
- Auto-scaling configuration for dynamic resource management
- Azure Monitor for comprehensive observability
- iSCSI connectivity for shared storage access

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group myResourceGroup \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters environmentName=hpc-demo

# Monitor deployment
az deployment group show \
    --resource-group myResourceGroup \
    --name main
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan -var="resource_group_name=myResourceGroup" \
               -var="location=eastus"

# Deploy infrastructure
terraform apply -var="resource_group_name=myResourceGroup" \
                -var="location=eastus"
```

### Using Bash Scripts

```bash
# Set environment variables
export RESOURCE_GROUP="rg-hpc-demo"
export LOCATION="eastus"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `environmentName` | Prefix for resource names | `hpc` | Yes |
| `location` | Azure region | `eastus` | Yes |
| `elasticSanBaseSizeTiB` | Base size for Elastic SAN in TiB | `1` | No |
| `elasticSanExtendedSizeTiB` | Extended capacity in TiB | `2` | No |
| `batchPoolVmSize` | VM size for Batch pool | `Standard_HC44rs` | No |
| `batchPoolTargetNodes` | Initial number of nodes | `2` | No |
| `batchPoolMaxNodes` | Maximum nodes for auto-scaling | `20` | No |
| `enableMonitoring` | Enable Azure Monitor | `true` | No |
| `tags` | Resource tags | `{}` | No |

### Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `resource_group_name` | Resource group name | `string` | n/a |
| `location` | Azure region | `string` | `eastus` |
| `environment_name` | Environment prefix | `string` | `hpc` |
| `elastic_san_base_size_tib` | Elastic SAN base size | `number` | `1` |
| `elastic_san_extended_size_tib` | Extended capacity | `number` | `2` |
| `batch_pool_vm_size` | Batch pool VM size | `string` | `Standard_HC44rs` |
| `batch_pool_target_nodes` | Target dedicated nodes | `number` | `2` |
| `batch_pool_max_nodes` | Maximum nodes | `number` | `20` |
| `enable_monitoring` | Enable monitoring | `bool` | `true` |

## Post-Deployment Configuration

### iSCSI Volume Mounting

After deployment, configure iSCSI connectivity on Batch compute nodes:

```bash
# Get Elastic SAN connection information
az elastic-san show \
    --resource-group myResourceGroup \
    --name myElasticSAN \
    --query "properties.connectConnectivity"

# Mount volumes on compute nodes (executed automatically via start task)
sudo iscsiadm -m discovery -t st -p <elastic-san-endpoint>:3260
sudo iscsiadm -m node --login
```

### Batch Job Submission

Submit HPC workloads to the configured Batch pool:

```bash
# Create a job
az batch job create \
    --id hpc-workload-job \
    --pool-id hpc-compute-pool

# Add tasks to the job
az batch task create \
    --job-id hpc-workload-job \
    --task-id task-1 \
    --command-line "python3 /mnt/shared/hpc-workload.py"
```

## Monitoring and Observability

### Key Metrics to Monitor

- **Batch Service**: Pool utilization, task completion rates, node health
- **Elastic SAN**: IOPS utilization, throughput, latency
- **Compute Nodes**: CPU usage, memory utilization, network I/O
- **Cost**: Daily spend, resource utilization efficiency

### Azure Monitor Queries

```kusto
// Batch pool performance
AzureMetrics
| where ResourceProvider == "MICROSOFT.BATCH"
| where MetricName == "Pool.CPUUsage"
| summarize avg(Average) by bin(TimeGenerated, 5m)

// Elastic SAN throughput
AzureMetrics
| where ResourceProvider == "MICROSOFT.STORAGE"
| where MetricName == "TotalThroughput"
| summarize max(Maximum) by bin(TimeGenerated, 5m)
```

## Cost Optimization

### Estimated Costs (Per Day)

| Component | Size | Estimated Cost |
|-----------|------|----------------|
| Azure Batch (Standard_HC44rs) | 2-20 nodes | $150-300 |
| Azure Elastic SAN (Premium) | 3 TiB | $50-100 |
| Virtual Network | Standard | $5-10 |
| Storage Account | Standard LRS | $2-5 |
| **Total Daily** | | **$207-415** |

### Cost Optimization Strategies

1. **Auto-scaling**: Configure aggressive scale-down policies
2. **Spot VMs**: Use Azure Spot VMs for fault-tolerant workloads
3. **Reserved Instances**: Purchase reserved capacity for predictable workloads
4. **Storage Optimization**: Right-size Elastic SAN capacity based on actual usage

## Security Considerations

### Network Security

- Virtual network isolation with Network Security Groups
- Private endpoints for storage access
- iSCSI traffic restricted to Batch subnet

### Identity and Access

- Managed identities for service authentication
- Role-based access control (RBAC) for resource access
- Azure Key Vault integration for secrets management

### Data Protection

- Encryption at rest for Elastic SAN volumes
- Encryption in transit for all data transfers
- Network access controls for storage endpoints

## Troubleshooting

### Common Issues

1. **Elastic SAN Connectivity**
   ```bash
   # Check network connectivity
   az network vnet subnet show \
       --resource-group myResourceGroup \
       --vnet-name myVNet \
       --name batch-subnet \
       --query "networkSecurityGroup"
   ```

2. **Batch Pool Scaling**
   ```bash
   # Check auto-scaling formula
   az batch pool autoscale show \
       --pool-id hpc-compute-pool \
       --query "autoScaleFormula"
   ```

3. **Storage Performance**
   ```bash
   # Monitor Elastic SAN metrics
   az monitor metrics list \
       --resource myElasticSAN \
       --metric "TotalIOPS" \
       --interval PT5M
   ```

### Log Analysis

```bash
# View Batch service logs
az monitor log-analytics query \
    --workspace myLogAnalyticsWorkspace \
    --analytics-query "AzureDiagnostics | where ResourceProvider == 'MICROSOFT.BATCH'"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name myResourceGroup --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="resource_group_name=myResourceGroup" \
                 -var="location=eastus"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group exists --name myResourceGroup
```

## Advanced Configuration

### Custom Auto-scaling Formula

```text
// Advanced auto-scaling for HPC workloads
startingNumberOfVMs = 1;
maxNumberofVMs = 50;
pendingTaskSamplePercent = $PendingTasks.GetSamplePercent(180 * TimeInterval_Second);
pendingTaskSamples = pendingTaskSamplePercent < 70 ? startingNumberOfVMs : 
                    avg($PendingTasks.GetSample(180 * TimeInterval_Second));

// Scale up quickly for pending tasks
$TargetDedicatedNodes = min(maxNumberofVMs, pendingTaskSamples);
$NodeDeallocationOption = taskcompletion;
```

### High-Performance Storage Configuration

```bash
# Configure multipath for high availability
echo "multipaths {
    multipath {
        wwid <elastic-san-wwid>
        alias hpc-data
        path_grouping_policy multibus
        path_selector round-robin
        failback immediate
        rr_weight priorities
    }
}" >> /etc/multipath.conf
```

## Performance Tuning

### Batch Pool Optimization

- Use HPC-optimized VM sizes (HC, HB series)
- Enable SR-IOV for maximum network performance
- Configure inter-node communication for MPI workloads
- Optimize task-to-node ratio based on workload characteristics

### Storage Performance

- Use Premium SSD for Elastic SAN base storage
- Configure appropriate volume sizes for IOPS requirements
- Implement read-ahead caching for sequential workloads
- Monitor and tune iSCSI connection parameters

## Integration Examples

### Azure Machine Learning

```python
# Integration with Azure ML for HPC training
from azure.ai.ml import MLClient
from azure.ai.ml.entities import BatchEndpoint

# Create batch endpoint for HPC workloads
batch_endpoint = BatchEndpoint(
    name="hpc-batch-endpoint",
    compute="hpc-compute-pool",
    max_concurrency_per_instance=8
)
```

### Power BI Dashboard

```powerquery
// Power BI query for HPC metrics
let
    Source = AzureMonitor.Contents("subscription-id", "resource-group", "batch-account"),
    Metrics = Source[Metrics],
    CPUUsage = Metrics[Pool.CPUUsage],
    FilteredData = Table.SelectRows(CPUUsage, each [TimeGenerated] >= DateTime.AddDays(DateTime.LocalNow(), -7))
in
    FilteredData
```

## Support and Documentation

- [Azure Elastic SAN Documentation](https://docs.microsoft.com/en-us/azure/storage/elastic-san/)
- [Azure Batch Documentation](https://docs.microsoft.com/en-us/azure/batch/)
- [Azure HPC Best Practices](https://docs.microsoft.com/en-us/azure/architecture/topics/high-performance-computing/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Contributing

For issues with this infrastructure code, refer to the original recipe documentation or submit issues to the recipe repository.

## License

This infrastructure code is provided under the same license as the parent recipe repository.