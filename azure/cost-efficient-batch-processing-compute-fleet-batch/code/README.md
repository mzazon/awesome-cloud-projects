# Infrastructure as Code for Cost-Efficient Batch Processing with Azure Compute Fleet and Azure Batch

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cost-Efficient Batch Processing with Azure Compute Fleet and Azure Batch".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Creating resource groups
  - Managing Azure Batch accounts
  - Creating Azure Compute Fleet resources
  - Managing Azure Storage accounts
  - Configuring Azure Monitor and Log Analytics
  - Setting up cost management and budgets
- PowerShell 7.0+ (for Bicep deployment) or Bash shell
- Terraform v1.0+ (for Terraform deployment)
- Basic understanding of batch processing concepts
- Estimated cost: $50-100 for testing resources

## Architecture Overview

This solution deploys:
- Azure Batch Account with integrated storage
- Azure Compute Fleet with mixed pricing models (80% spot, 20% standard)
- Azure Storage Account for batch data and results
- Azure Monitor and Log Analytics for cost and performance tracking
- Cost management alerts and budget controls
- Sample batch pool and job configurations

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Clone and navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-batch-fleet-demo \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters storageAccountSku=Standard_LRS \
    --parameters batchPoolVmSize=Standard_D2s_v3

# Verify deployment
az deployment group show \
    --resource-group rg-batch-fleet-demo \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="location=eastus" \
    -var="resource_group_name=rg-batch-fleet-demo"

# Apply the configuration
terraform apply \
    -var="location=eastus" \
    -var="resource_group_name=rg-batch-fleet-demo"

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for:
# - Resource group name
# - Azure region
# - Storage account SKU
# - Batch pool VM size
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `location` | Azure region | `eastus` | Any valid Azure region |
| `resourceGroupName` | Resource group name | `rg-batch-fleet-demo` | Custom name |
| `storageAccountSku` | Storage account SKU | `Standard_LRS` | `Standard_LRS`, `Standard_GRS` |
| `batchPoolVmSize` | VM size for batch pool | `Standard_D2s_v3` | Any valid Azure VM size |
| `spotInstancePercentage` | Percentage of spot instances | `80` | 0-100 |
| `maxSpotPrice` | Maximum spot price per VM | `0.05` | Any decimal value |
| `enableAutoScale` | Enable auto-scaling | `true` | `true`, `false` |
| `maxPoolNodes` | Maximum pool nodes | `20` | Any integer |

### Terraform Variables

| Variable | Description | Default | Type |
|----------|-------------|---------|------|
| `location` | Azure region | `eastus` | string |
| `resource_group_name` | Resource group name | `rg-batch-fleet-demo` | string |
| `storage_account_tier` | Storage account tier | `Standard` | string |
| `storage_account_replication` | Storage replication | `LRS` | string |
| `batch_pool_vm_size` | VM size for batch pool | `Standard_D2s_v3` | string |
| `spot_instance_percentage` | Percentage of spot instances | `80` | number |
| `max_spot_price` | Maximum spot price per VM | `0.05` | number |
| `enable_monitoring` | Enable Azure Monitor | `true` | bool |
| `log_retention_days` | Log retention period | `30` | number |

### Environment Variables (Bash Scripts)

```bash
# Optional: Set these before running deploy.sh
export AZURE_LOCATION="eastus"
export RESOURCE_GROUP_NAME="rg-batch-fleet-demo"
export STORAGE_ACCOUNT_SKU="Standard_LRS"
export BATCH_POOL_VM_SIZE="Standard_D2s_v3"
export SPOT_INSTANCE_PERCENTAGE="80"
export MAX_SPOT_PRICE="0.05"
```

## Post-Deployment Verification

### Verify Azure Batch Account

```bash
# Check batch account status
az batch account show \
    --name <batch-account-name> \
    --resource-group <resource-group-name> \
    --query "{Name:name,Location:location,ProvisioningState:provisioningState}"

# List batch pools
az batch pool list \
    --query "[].{PoolId:id,State:state,VmSize:vmSize,CurrentNodes:currentDedicatedNodes}"
```

### Verify Azure Compute Fleet

```bash
# Check compute fleet status
az compute-fleet show \
    --resource-group <resource-group-name> \
    --name <compute-fleet-name> \
    --query "{Name:name,Location:location,ProvisioningState:properties.provisioningState}"

# Check fleet capacity
az compute-fleet show \
    --resource-group <resource-group-name> \
    --name <compute-fleet-name> \
    --query "properties.{SpotCapacity:spotPriorityProfile.capacity,RegularCapacity:regularPriorityProfile.capacity}"
```

### Verify Monitoring Setup

```bash
# Check Log Analytics workspace
az monitor log-analytics workspace show \
    --workspace-name <workspace-name> \
    --resource-group <resource-group-name> \
    --query "{Name:name,Sku:sku.name,RetentionInDays:retentionInDays}"

# View cost analysis
az consumption usage list \
    --start-date $(date -d '-7 days' +%Y-%m-%d) \
    --end-date $(date +%Y-%m-%d) \
    --query "[0:5].{ResourceName:instanceName,Cost:pretaxCost,Currency:currency}"
```

## Testing the Solution

### Create a Test Batch Job

```bash
# Create a simple test job
az batch job create \
    --job-id test-job-$(date +%s) \
    --pool-id <pool-id> \
    --job-manager-task-command-line "echo 'Test job running on cost-optimized compute'"

# Add test tasks
for i in {1..3}; do
    az batch task create \
        --job-id test-job-$(date +%s) \
        --task-id "task-${i}" \
        --command-line "echo 'Processing task ${i}' && sleep 30"
done
```

### Monitor Cost Optimization

```bash
# Check current costs
az consumption usage list \
    --start-date $(date +%Y-%m-%d) \
    --end-date $(date +%Y-%m-%d) \
    --query "[?contains(instanceName, 'batch')].{Resource:instanceName,Cost:pretaxCost}" \
    --output table

# Monitor batch pool scaling
az batch pool show \
    --pool-id <pool-id> \
    --query "{CurrentDedicated:currentDedicatedNodes,CurrentSpot:currentLowPriorityNodes,TargetDedicated:targetDedicatedNodes,TargetSpot:targetLowPriorityNodes}"
```

## Cleanup

### Using Bicep

```bash
# Delete the deployment
az deployment group delete \
    --resource-group rg-batch-fleet-demo \
    --name main

# Delete the resource group (if desired)
az group delete \
    --name rg-batch-fleet-demo \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy \
    -var="location=eastus" \
    -var="resource_group_name=rg-batch-fleet-demo"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will:
# - List resources to be deleted
# - Ask for confirmation
# - Delete resources in proper order
# - Verify cleanup completion
```

## Cost Optimization Tips

1. **Spot Instance Strategy**: The default 80% spot instance allocation provides optimal cost savings while maintaining reliability
2. **Auto-scaling**: Configured auto-scaling ensures resources are only provisioned when needed
3. **Resource Tagging**: All resources include cost tracking tags for detailed billing analysis
4. **Monitoring Alerts**: Set up cost alerts to prevent unexpected charges
5. **Regular Cleanup**: Use cleanup scripts to remove unused resources promptly

## Troubleshooting

### Common Issues

1. **Batch Pool Creation Fails**:
   ```bash
   # Check quota limits
   az batch location quotas show --location eastus
   
   # Request quota increase if needed
   az support tickets create \
       --ticket-name "Batch Quota Increase" \
       --issue-type QuotaIssue
   ```

2. **Spot Instance Unavailability**:
   ```bash
   # Check spot instance availability
   az vm list-skus \
       --location eastus \
       --query "[?name=='Standard_D2s_v3'].{Name:name,Available:capabilities[?name=='SpotVMSupported'].value}"
   ```

3. **Cost Alerts Not Working**:
   ```bash
   # Verify budget configuration
   az consumption budget list \
       --query "[].{Name:name,Amount:amount,Category:category,Status:status}"
   ```

### Support Resources

- [Azure Batch Documentation](https://docs.microsoft.com/en-us/azure/batch/)
- [Azure Compute Fleet Documentation](https://docs.microsoft.com/en-us/azure/virtual-machines/spot-vms)
- [Azure Cost Management](https://docs.microsoft.com/en-us/azure/cost-management-billing/)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)

## Customization

### Scaling Configuration

Modify the auto-scaling formula in the Bicep template:

```bicep
autoScaleFormula: '$TargetLowPriorityNodes = min(20, $PendingTasks.GetSample(1 * TimeInterval_Minute, 0).GetAverage() * 2);'
```

### Cost Thresholds

Adjust budget alerts in the Terraform configuration:

```hcl
threshold_percentage = 80
contact_emails = ["admin@yourcompany.com"]
```

### VM Size Optimization

Choose appropriate VM sizes based on workload:

```bash
# List available VM sizes
az vm list-sizes --location eastus --output table

# Check pricing for different sizes
az vm list-skus \
    --location eastus \
    --size Standard_D \
    --query "[].{Name:name,Cores:capabilities[?name=='vCPUs'].value,Memory:capabilities[?name=='MemoryGB'].value}"
```

## Security Considerations

- All resources use Azure Active Directory authentication
- Storage accounts have secure transfer enabled
- Network security groups restrict access to necessary ports only
- Batch accounts use managed identity for secure service access
- All secrets are stored in Azure Key Vault (when configured)

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Azure documentation for specific services
4. Contact Azure support for service-specific issues

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Use in production environments should include additional security, monitoring, and compliance configurations appropriate for your organization.