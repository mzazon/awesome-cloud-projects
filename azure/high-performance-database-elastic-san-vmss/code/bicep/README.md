# Azure Elastic SAN and VMSS High-Performance Database Infrastructure

This Bicep template deploys a complete high-performance database infrastructure using Azure Elastic SAN for storage and Virtual Machine Scale Sets for compute, optimized for PostgreSQL workloads.

## Architecture Overview

The template deploys:

- **Azure Elastic SAN**: Cloud-native storage area network with high IOPS and low latency
- **Virtual Machine Scale Sets**: Auto-scaling compute instances with PostgreSQL
- **Azure Load Balancer**: High availability and load distribution
- **PostgreSQL Flexible Server**: Managed PostgreSQL service with high availability
- **Azure Monitor**: Comprehensive monitoring and alerting
- **Auto-scaling**: Automatic scaling based on CPU utilization

## Prerequisites

- Azure CLI 2.50.0 or later
- Azure subscription with appropriate permissions
- Bicep CLI installed
- Resource group created for deployment

### Required Permissions

- Contributor or Owner role on the target resource group
- Ability to create Elastic SAN resources (preview feature)
- Network Contributor role for networking resources

## Quick Start

### 1. Clone or Download Files

Ensure you have the following files in your deployment directory:
- `main.bicep` - Main Bicep template
- `parameters.json` - Parameter values
- `setup-postgres.sh` - PostgreSQL setup script

### 2. Customize Parameters

Edit the `parameters.json` file to match your requirements:

```json
{
  "location": "East US",
  "environment": "dev",
  "vmSku": "Standard_D4s_v3",
  "vmssInitialInstanceCount": 2,
  "elasticSanBaseSizeTiB": 1,
  "postgresHighAvailability": true
}
```

### 3. Deploy the Template

```bash
# Login to Azure
az login

# Set subscription (if needed)
az account set --subscription "Your-Subscription-ID"

# Create resource group
az group create --name "rg-elastic-san-demo" --location "East US"

# Deploy the template
az deployment group create \
  --resource-group "rg-elastic-san-demo" \
  --template-file main.bicep \
  --parameters @parameters.json
```

### 4. Monitor Deployment

```bash
# Check deployment status
az deployment group show \
  --resource-group "rg-elastic-san-demo" \
  --name "main"

# List created resources
az resource list --resource-group "rg-elastic-san-demo" --output table
```

## Parameter Reference

### Core Configuration

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `location` | string | Azure region for deployment | Resource group location |
| `resourceSuffix` | string | Unique suffix for resource names | Auto-generated |
| `environment` | string | Environment tag (dev/staging/prod) | dev |

### Networking

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `vnetAddressPrefix` | string | Virtual network address space | 10.0.0.0/16 |
| `subnetAddressPrefix` | string | Subnet address space | 10.0.1.0/24 |

### Virtual Machine Scale Set

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `vmSku` | string | VM size for scale set instances | Standard_D4s_v3 |
| `vmssInitialInstanceCount` | int | Initial number of VM instances | 2 |
| `vmssMinInstanceCount` | int | Minimum instances for auto-scaling | 2 |
| `vmssMaxInstanceCount` | int | Maximum instances for auto-scaling | 10 |
| `adminUsername` | string | VM administrator username | azureuser |
| `adminPassword` | securestring | VM administrator password | Required |

### Elastic SAN

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `elasticSanBaseSizeTiB` | int | Base storage size in TiB | 1 |
| `elasticSanExtendedCapacityTiB` | int | Extended capacity in TiB | 2 |
| `dataVolumeSizeGB` | int | Data volume size in GB | 500 |
| `logVolumeSizeGB` | int | Log volume size in GB | 200 |

### PostgreSQL

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `postgresAdminUsername` | string | PostgreSQL admin username | pgadmin |
| `postgresAdminPassword` | securestring | PostgreSQL admin password | Required |
| `postgresStorageSizeGB` | int | PostgreSQL storage size in GB | 128 |
| `postgresSku` | string | PostgreSQL server SKU | Standard_D2s_v3 |
| `postgresHighAvailability` | bool | Enable high availability | true |

## Post-Deployment Configuration

### 1. Connect to PostgreSQL

```bash
# Get the load balancer public IP
az network public-ip show \
  --resource-group "rg-elastic-san-demo" \
  --name "pip-db-<suffix>" \
  --query "ipAddress" \
  --output tsv

# Connect to PostgreSQL through load balancer
psql -h <public-ip> -U pgadmin -d appdb
```

### 2. Configure Elastic SAN Volumes

```bash
# SSH into a VMSS instance
ssh azureuser@<instance-ip>

# Discover iSCSI targets
sudo iscsiadm -m discovery -t sendtargets -p <elastic-san-endpoint>

# Login to iSCSI targets
sudo iscsiadm -m node --login

# Check available disks
sudo lsblk
```

### 3. Monitor Performance

```bash
# Check auto-scaling status
az monitor autoscale show \
  --resource-group "rg-elastic-san-demo" \
  --name "vmss-autoscale-<suffix>"

# View metrics
az monitor metrics list \
  --resource-group "rg-elastic-san-demo" \
  --resource-type "Microsoft.Compute/virtualMachineScaleSets" \
  --resource-name "vmss-db-<suffix>" \
  --metric "Percentage CPU"
```

## Troubleshooting

### Common Issues

1. **Elastic SAN not available in region**
   - Verify Azure Elastic SAN is available in your target region
   - Check preview feature registration

2. **PostgreSQL connection issues**
   - Verify network security group rules
   - Check PostgreSQL service status on VMSS instances
   - Validate load balancer configuration

3. **Auto-scaling not working**
   - Check auto-scale profile configuration
   - Verify VM metrics are being collected
   - Review scaling rules and thresholds

### Diagnostic Commands

```bash
# Check VMSS instance health
az vmss list-instances \
  --resource-group "rg-elastic-san-demo" \
  --name "vmss-db-<suffix>" \
  --query "[].{Name:name,Status:provisioningState,Health:instanceView.statuses[1].displayStatus}"

# View deployment logs
az deployment group show \
  --resource-group "rg-elastic-san-demo" \
  --name "main" \
  --query "properties.error"

# Check Elastic SAN status
az elastic-san show \
  --resource-group "rg-elastic-san-demo" \
  --name "esan-db-<suffix>" \
  --query "{Name:name,Status:provisioningState,Size:totalSizeTiB}"
```

## Security Considerations

- Change default passwords in parameters file
- Configure network security groups for least privilege access
- Enable Azure Monitor for security monitoring
- Use Azure Key Vault for sensitive configuration
- Implement proper backup and disaster recovery

## Cost Optimization

- Use Azure Advisor recommendations
- Monitor resource utilization with Azure Monitor
- Implement auto-scaling to optimize compute costs
- Use Azure Cost Management for budget tracking
- Consider reserved instances for predictable workloads

## Cleanup

To remove all resources:

```bash
# Delete the resource group and all resources
az group delete --name "rg-elastic-san-demo" --yes --no-wait
```

## Support

For issues with this template:
1. Check the troubleshooting section above
2. Review Azure Elastic SAN documentation
3. Consult Azure Virtual Machine Scale Sets documentation
4. Contact Azure support for service-specific issues

## References

- [Azure Elastic SAN Documentation](https://docs.microsoft.com/en-us/azure/storage/elastic-san/)
- [Virtual Machine Scale Sets Documentation](https://docs.microsoft.com/en-us/azure/virtual-machine-scale-sets/)
- [PostgreSQL on Azure Documentation](https://docs.microsoft.com/en-us/azure/postgresql/)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)