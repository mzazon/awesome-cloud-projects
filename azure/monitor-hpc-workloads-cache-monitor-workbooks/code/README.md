# Infrastructure as Code for Monitor High-Performance Computing with HPC Cache and Workbooks

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Monitor High-Performance Computing with HPC Cache and Workbooks".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.40.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Creating Azure HPC Cache instances
  - Creating Azure Monitor Workbooks and Log Analytics workspaces
  - Creating Azure Batch accounts and compute pools
  - Creating Azure Storage accounts
  - Configuring diagnostic settings
- Basic understanding of HPC workloads and Azure storage concepts
- Familiarity with Azure Monitor and Log Analytics query language (KQL)

> **Important**: Azure HPC Cache will be retired on September 30, 2025. Consider migrating to Azure Managed Lustre or Azure NetApp Files for future implementations.

## Cost Considerations

- **Estimated cost**: $50-200/day for HPC Cache, compute resources, and monitoring (varies by usage)
- **HPC Cache**: $0.045/GB/hour for Standard_2G SKU
- **Azure Batch**: Compute costs based on VM size and duration
- **Log Analytics**: $2.76/GB ingested data
- **Storage**: Standard_LRS rates apply

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Review and customize parameters
cp parameters.json.example parameters.json
# Edit parameters.json with your specific values

# Deploy the infrastructure
az deployment group create \
    --resource-group your-resource-group \
    --template-file main.bicep \
    --parameters @parameters.json

# Verify deployment
az deployment group show \
    --resource-group your-resource-group \
    --name main
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-hpc-monitoring-$(openssl rand -hex 3)"
export LOCATION="eastus"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
az hpc-cache list --resource-group $RESOURCE_GROUP
az batch account list --resource-group $RESOURCE_GROUP
```

## Architecture Overview

The infrastructure creates:

1. **Storage Layer**:
   - Azure Storage Account (Standard_LRS) for backend storage
   - Azure HPC Cache (Standard_2G, 3TB) for storage acceleration

2. **Compute Layer**:
   - Azure Batch account with high-performance compute pool
   - Virtual network with dedicated subnet for HPC Cache

3. **Monitoring Layer**:
   - Log Analytics workspace for centralized logging
   - Azure Monitor Workbooks for HPC-specific dashboards
   - Diagnostic settings for comprehensive metric collection
   - Performance alerts for proactive monitoring

4. **Networking**:
   - Virtual network (10.0.0.0/16) with HPC subnet (10.0.1.0/24)
   - Network security groups with appropriate rules

## Post-Deployment Configuration

### Access the Monitoring Dashboard

1. Navigate to Azure Portal → Monitor → Workbooks
2. Find "HPC Monitoring Dashboard" in your resource group
3. Pin important visualizations to your Azure dashboard

### Configure Additional Alerts

```bash
# Example: Create custom alert for storage throughput
az monitor metrics alert create \
    --resource-group $RESOURCE_GROUP \
    --name "storage-throughput-alert" \
    --description "Alert when storage throughput exceeds threshold" \
    --scopes /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME \
    --condition "avg StorageRead > 1000" \
    --window-size 5m \
    --evaluation-frequency 1m
```

### Submit Test HPC Workload

```bash
# Login to Batch account
az batch account login --resource-group $RESOURCE_GROUP --name $BATCH_ACCOUNT_NAME

# Create test job
az batch job create --id test-hpc-workload --pool-id hpc-pool

# Add compute-intensive task
az batch task create \
    --job-id test-hpc-workload \
    --task-id hpc-task-1 \
    --command-line "python -c 'import time; import numpy as np; [np.random.random((1000,1000)).dot(np.random.random((1000,1000))) for _ in range(100)]'"
```

## Monitoring and Validation

### Key Metrics to Monitor

1. **HPC Cache Performance**:
   - Cache hit percentage (target: >80%)
   - Cache throughput (MB/s)
   - Client connections

2. **Batch Compute Metrics**:
   - Active/running node count
   - Task completion rate
   - CPU/memory utilization

3. **Storage Performance**:
   - Storage account throughput
   - Transaction rates
   - Availability metrics

### Validation Commands

```bash
# Check HPC Cache status
az hpc-cache show \
    --resource-group $RESOURCE_GROUP \
    --name $HPC_CACHE_NAME \
    --query "health.state"

# Verify Batch pool status
az batch pool show \
    --pool-id hpc-pool \
    --query "state"

# Query monitoring data
az monitor log-analytics query \
    --workspace $WORKSPACE_ID \
    --analytics-query "AzureMetrics | where ResourceProvider == 'MICROSOFT.STORAGECACHE' | summarize avg(Average) by MetricName"
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

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletions when prompted
```

## Troubleshooting

### Common Issues

1. **HPC Cache Creation Fails**:
   - Verify subnet has sufficient IP addresses
   - Check quota limits in target region
   - Ensure proper networking configuration

2. **Batch Pool Creation Fails**:
   - Verify VM quota in target region
   - Check SKU availability
   - Ensure proper IAM permissions

3. **Monitoring Data Not Appearing**:
   - Wait 5-10 minutes for metrics to populate
   - Verify diagnostic settings are enabled
   - Check Log Analytics workspace permissions

### Debug Commands

```bash
# Check resource deployment status
az deployment group list \
    --resource-group $RESOURCE_GROUP \
    --query "[].{Name:name,State:properties.provisioningState}"

# View HPC Cache logs
az monitor activity-log list \
    --resource-group $RESOURCE_GROUP \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)

# Check Batch account events
az batch account show \
    --resource-group $RESOURCE_GROUP \
    --name $BATCH_ACCOUNT_NAME
```

## Customization

### Key Parameters

- **HPC Cache Size**: Modify `cacheSizeGb` (minimum 3072 GB)
- **Batch VM Size**: Change `vmSize` for different performance profiles
- **Storage Performance**: Adjust storage account SKU (Standard_LRS, Premium_LRS)
- **Monitoring Retention**: Configure Log Analytics retention period
- **Alert Thresholds**: Customize alert conditions and evaluation frequency

### Example Customizations

```bash
# Use larger HPC Cache
export CACHE_SIZE_GB=12288  # 12TB instead of 3TB

# Use high-performance compute VMs
export BATCH_VM_SIZE="Standard_HC44rs"  # HPC-optimized

# Configure premium storage
export STORAGE_SKU="Premium_LRS"
```

## Security Considerations

- HPC Cache uses Azure managed keys by default
- Batch pools use Azure-managed identities
- Storage accounts have secure transfer enabled
- Network security groups restrict access to necessary ports
- Diagnostic logs are encrypted in Log Analytics

## Migration from Azure HPC Cache

Since Azure HPC Cache will be retired on September 30, 2025, consider these alternatives:

1. **Azure Managed Lustre**: High-performance file system for HPC workloads
2. **Azure NetApp Files**: Enterprise-grade NFS for HPC applications
3. **Azure Blob Storage with NFSv3**: Cost-effective option for specific workloads

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service health and status pages
3. Consult Azure documentation for specific services
4. Contact Azure support for service-specific issues

## Additional Resources

- [Azure HPC Cache documentation](https://docs.microsoft.com/en-us/azure/hpc-cache/)
- [Azure Monitor Workbooks guide](https://docs.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview)
- [Azure Batch documentation](https://docs.microsoft.com/en-us/azure/batch/)
- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)