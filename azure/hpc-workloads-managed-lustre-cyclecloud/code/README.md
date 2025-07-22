# Infrastructure as Code for HPC Workloads with Managed Lustre and CycleCloud

This directory contains Infrastructure as Code (IaC) implementations for the recipe "HPC Workloads with Managed Lustre and CycleCloud".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login`)
- Azure subscription with appropriate permissions:
  - Contributor role for resource group creation
  - Permissions to create Managed Lustre file systems
  - Quota for HPC VM SKUs (HBv3, HCv1, NCv3 series)
- SSH key pair for cluster access
- For Terraform: Terraform installed (version 1.0+)
- For Bicep: Bicep CLI installed (`az bicep install`)

## Quick Start

### Using Bicep (Recommended)

```bash
# Review and customize parameters
cp bicep/parameters.json bicep/parameters.local.json
# Edit parameters.local.json with your specific values

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.local.json
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
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

# Follow the interactive prompts to configure your HPC environment
```

## Architecture Overview

This infrastructure deployment creates:

- **Virtual Network**: High-performance networking with dedicated subnets for compute, management, and storage
- **Azure Managed Lustre**: Fully managed parallel file system with 4 TiB capacity and 1000 MB/s throughput
- **Azure CycleCloud**: HPC cluster orchestration and management server
- **Compute Resources**: Auto-scaling HPC cluster with Slurm scheduler
- **Monitoring**: Azure Monitor and Log Analytics for performance tracking
- **Security**: Network security groups, SSH key authentication, and role-based access control

## Configuration Options

### Bicep Parameters

Key parameters in `bicep/parameters.json`:

```json
{
  "location": "East US",
  "lustreCapacityTiB": 4,
  "lustreThroughputMBps": 1000,
  "clusterMaxNodes": 10,
  "vmSkuCompute": "Standard_HB120rs_v3",
  "vmSkuManagement": "Standard_D4s_v3",
  "sshPublicKey": "<your-ssh-public-key>"
}
```

### Terraform Variables

Key variables in `terraform/variables.tf`:

```hcl
variable "location" {
  description = "Azure region for deployment"
  type        = string
  default     = "East US"
}

variable "lustre_capacity_tib" {
  description = "Lustre file system capacity in TiB"
  type        = number
  default     = 4
}

variable "cluster_max_nodes" {
  description = "Maximum number of compute nodes"
  type        = number
  default     = 10
}
```

### Environment Variables (Bash Scripts)

The bash scripts use these key environment variables:

```bash
export AZURE_LOCATION="East US"
export LUSTRE_CAPACITY_TIB=4
export CLUSTER_MAX_NODES=10
export VM_SKU_COMPUTE="Standard_HB120rs_v3"
export SSH_PUBLIC_KEY="<your-ssh-public-key>"
```

## Deployment Steps

### 1. Pre-deployment Validation

```bash
# Check Azure CLI authentication
az account show

# Verify required quotas
az vm list-usage --location "East US" --query "[?contains(name.value, 'HB')]"

# Generate SSH key if needed
ssh-keygen -t rsa -b 4096 -f ~/.ssh/hpc-cluster-key -N ""
```

### 2. Resource Group Preparation

```bash
# Create resource group
az group create \
    --name rg-hpc-lustre-demo \
    --location "East US"
```

### 3. Deploy Infrastructure

Choose one of the deployment methods above based on your preferred IaC tool.

### 4. Post-deployment Configuration

```bash
# Get CycleCloud server IP
CYCLECLOUD_IP=$(az vm show \
    --name <cyclecloud-vm-name> \
    --resource-group <resource-group> \
    --show-details \
    --query publicIps \
    --output tsv)

# Access CycleCloud web interface
echo "CycleCloud web interface: https://${CYCLECLOUD_IP}"
```

## Validation and Testing

### 1. Verify Lustre File System

```bash
# Check Lustre file system status
az amlfs show \
    --name <lustre-name> \
    --resource-group <resource-group> \
    --query "{State:provisioningState,Capacity:storageCapacityTiB,Throughput:throughputProvisionedMBps}"
```

### 2. Test Cluster Connectivity

```bash
# SSH to CycleCloud server
ssh -i ~/.ssh/hpc-cluster-key azureuser@${CYCLECLOUD_IP}

# Check cluster status
cyclecloud show_cluster hpc-slurm-cluster
```

### 3. Submit Test Job

```bash
# Create and submit test MPI job
cat > test_job.sbatch << 'EOF'
#!/bin/bash
#SBATCH --job-name=hpc-test
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --time=00:05:00

srun hostname
EOF

sbatch test_job.sbatch
squeue
```

## Performance Optimization

### Lustre Configuration

- **Capacity Planning**: Start with 4 TiB and scale based on workload requirements
- **Throughput Optimization**: Configure throughput based on concurrent user count
- **Client Tuning**: Optimize Lustre client settings for your workload pattern

### Compute Optimization

- **VM SKU Selection**: Choose appropriate VM sizes based on workload characteristics
- **Auto-scaling**: Configure CycleCloud auto-scaling policies for cost efficiency
- **Job Scheduling**: Optimize Slurm configuration for your job mix

### Network Performance

- **InfiniBand**: Use InfiniBand-enabled VM SKUs for tightly coupled workloads
- **Placement Groups**: Configure proximity placement groups for low-latency communication
- **Network Optimization**: Tune network settings for maximum throughput

## Monitoring and Troubleshooting

### Azure Monitor Queries

```kusto
# Check compute node utilization
AzureMetrics
| where ResourceProvider == "MICROSOFT.COMPUTE"
| where MetricName == "Percentage CPU"
| summarize avg(Average) by bin(TimeGenerated, 5m)

# Monitor Lustre performance
AzureMetrics
| where ResourceProvider == "MICROSOFT.STORAGECACHE"
| where MetricName in ("ThroughputRead", "ThroughputWrite")
| summarize avg(Average) by MetricName, bin(TimeGenerated, 1m)
```

### Common Issues

1. **Lustre Mount Failures**
   - Check network connectivity between compute nodes and Lustre
   - Verify Lustre client packages are installed
   - Ensure proper subnet configuration

2. **Cluster Scaling Issues**
   - Verify VM quota availability
   - Check CycleCloud autoscaling policies
   - Review Slurm configuration

3. **Performance Problems**
   - Monitor Lustre client cache settings
   - Check for network bottlenecks
   - Verify InfiniBand connectivity

## Cost Optimization

### Cost Monitoring

```bash
# Get current costs
az consumption usage list \
    --resource-group <resource-group> \
    --start-date $(date -d '30 days ago' +%Y-%m-%d) \
    --end-date $(date +%Y-%m-%d)
```

### Cost Optimization Strategies

1. **Compute**: Use spot instances for fault-tolerant workloads
2. **Storage**: Implement data lifecycle management
3. **Scaling**: Configure aggressive scale-down policies
4. **Scheduling**: Use reserved instances for predictable workloads

## Security Considerations

### Network Security

- Network security groups restrict access to management interfaces
- Private subnets for compute and storage traffic
- VPN or ExpressRoute for secure hybrid connectivity

### Identity and Access

- Role-based access control (RBAC) for resource management
- SSH key authentication for cluster access
- Azure Active Directory integration for user management

### Data Protection

- Encryption at rest for Lustre file system
- Encryption in transit for all data movement
- Backup and disaster recovery planning

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name <resource-group-name> \
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
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
az resource list \
    --resource-group <resource-group> \
    --query "[].{Name:name,Type:type,State:properties.provisioningState}"
```

## Advanced Configurations

### Multi-Region Deployment

For disaster recovery and global collaboration:

```bash
# Deploy secondary cluster in different region
az deployment group create \
    --resource-group rg-hpc-lustre-secondary \
    --template-file bicep/main.bicep \
    --parameters location="West US 2" \
    --parameters lustreReplication=true
```

### GPU-Accelerated Computing

Modify VM SKU parameters for GPU workloads:

```json
{
  "vmSkuCompute": "Standard_NC96ads_A100_v4",
  "enableGpuDrivers": true,
  "gpuDriverVersion": "latest"
}
```

### Hybrid Cloud Integration

Connect to on-premises HPC resources:

```bash
# Configure ExpressRoute or VPN gateway
az network vnet-gateway create \
    --resource-group <resource-group> \
    --name hpc-vpn-gateway \
    --public-ip-address hpc-gateway-ip \
    --vnet <vnet-name> \
    --gateway-type Vpn
```

## Support and Documentation

### Official Documentation

- [Azure Managed Lustre Documentation](https://docs.microsoft.com/azure/azure-managed-lustre/)
- [Azure CycleCloud Documentation](https://docs.microsoft.com/azure/cyclecloud/)
- [Azure HPC Architecture Guide](https://docs.microsoft.com/azure/architecture/topics/high-performance-computing/)

### Community Resources

- [Azure HPC Community](https://techcommunity.microsoft.com/t5/azure-high-performance-computing/bg-p/AzureHighPerformanceComputing)
- [CycleCloud GitHub Repository](https://github.com/Azure/cyclecloud-slurm)
- [Azure Samples for HPC](https://github.com/Azure-Samples/azure-hpc-samples)

### Support Channels

- Azure Support for production issues
- GitHub Issues for IaC-specific problems
- Community forums for best practices and optimization

## Contributing

To contribute improvements to this infrastructure code:

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Submit a pull request with detailed description

## License

This infrastructure code is provided under the same license as the parent repository.