# HPC Cache and Azure Monitor Workbooks - Bicep Infrastructure

This directory contains Azure Bicep templates for deploying a comprehensive High-Performance Computing (HPC) monitoring solution using Azure HPC Cache and Azure Monitor Workbooks.

## Architecture Overview

The solution deploys:

- **Azure Virtual Network**: Dedicated network for HPC infrastructure
- **Azure Storage Account**: High-performance storage for HPC workloads
- **Azure HPC Cache**: Storage acceleration layer for compute workloads
- **Azure Batch**: Managed compute pool for HPC jobs
- **Azure Monitor Workbooks**: Interactive dashboards for performance monitoring
- **Log Analytics Workspace**: Centralized logging and metrics collection
- **Metric Alerts**: Automated alerts for performance thresholds

## File Structure

```
bicep/
├── main.bicep                 # Monolithic deployment template
├── main-modular.bicep         # Modular deployment template
├── parameters.json            # Development environment parameters
├── parameters-prod.json       # Production environment parameters
├── modules/                   # Reusable Bicep modules
│   ├── networking.bicep       # Virtual network and subnet
│   ├── storage.bicep          # Storage account configuration
│   ├── hpc-cache.bicep        # HPC Cache deployment
│   ├── batch.bicep            # Batch account and pool
│   └── monitoring.bicep       # Monitoring and alerting
└── README.md                  # This file
```

## Prerequisites

- Azure CLI version 2.40.0 or later
- Azure subscription with appropriate permissions
- Bicep CLI (included with Azure CLI)
- Resource group for deployment

### Required Permissions

- Contributor access to the target resource group
- Network Contributor for virtual network resources
- Storage Account Contributor for storage resources
- Monitoring Contributor for Log Analytics and alerts

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd azure/monitoring-high-performance-computing-workloads-with-azure-hpc-cache-and-azure-monitor-workbooks/code/bicep
```

### 2. Login to Azure

```bash
az login
az account set --subscription <subscription-id>
```

### 3. Create Resource Group

```bash
az group create --name rg-hpc-monitoring --location eastus
```

### 4. Deploy Infrastructure

Choose one of the deployment methods below:

#### Option A: Monolithic Template (Recommended for beginners)

```bash
az deployment group create \
  --resource-group rg-hpc-monitoring \
  --template-file main.bicep \
  --parameters @parameters.json
```

#### Option B: Modular Template (Recommended for advanced users)

```bash
az deployment group create \
  --resource-group rg-hpc-monitoring \
  --template-file main-modular.bicep \
  --parameters @parameters.json
```

#### Option C: Production Deployment

```bash
az deployment group create \
  --resource-group rg-hpc-monitoring-prod \
  --template-file main.bicep \
  --parameters @parameters-prod.json
```

## Configuration Parameters

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `resourcePrefix` | Prefix for resource naming | `"hpc"` |
| `alertEmailAddress` | Email for alert notifications | `"admin@company.com"` |

### Optional Parameters

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `environment` | Environment name | `"dev"` | `dev`, `staging`, `prod` |
| `location` | Azure region | `resourceGroup().location` | Any valid Azure region |
| `hpcCacheSize` | Cache size in GB | `3072` | `3072`, `6144`, `12288`, `24576`, `49152` |
| `hpcCacheSku` | Cache performance tier | `"Standard_2G"` | `Standard_2G`, `Standard_4G`, `Standard_8G` |
| `batchVmSize` | Batch pool VM size | `"Standard_HC44rs"` | Any valid Azure VM size |
| `batchPoolNodeCount` | Initial node count | `2` | `0-100` |
| `logAnalyticsRetentionDays` | Log retention period | `90` | `30-730` |
| `enableDiagnostics` | Enable diagnostic settings | `true` | `true`, `false` |

### Parameter Files

#### Development Environment (`parameters.json`)
- Minimal resource sizes
- Standard performance tiers
- Basic monitoring configuration

#### Production Environment (`parameters-prod.json`)
- Optimized resource sizes
- Premium performance tiers
- Extended monitoring retention
- Enhanced alerting configuration

## Customization

### Modify Parameters

Edit the parameter files to customize the deployment:

```json
{
  "parameters": {
    "resourcePrefix": {
      "value": "mycompany-hpc"
    },
    "hpcCacheSize": {
      "value": 6144
    },
    "batchPoolNodeCount": {
      "value": 5
    }
  }
}
```

### Add Custom Tags

```json
{
  "parameters": {
    "tags": {
      "value": {
        "Environment": "prod",
        "CostCenter": "Research",
        "Project": "Scientific-Computing",
        "Owner": "HPC-Team"
      }
    }
  }
}
```

### Advanced Configuration

For advanced customization, modify the Bicep templates directly:

1. **Networking**: Edit `modules/networking.bicep` for custom VNET configuration
2. **Storage**: Modify `modules/storage.bicep` for additional storage features
3. **HPC Cache**: Update `modules/hpc-cache.bicep` for custom cache settings
4. **Monitoring**: Customize `modules/monitoring.bicep` for additional alerts

## Deployment Validation

### Check Deployment Status

```bash
az deployment group show \
  --resource-group rg-hpc-monitoring \
  --name <deployment-name>
```

### Validate Resources

```bash
# Check HPC Cache status
az hpc-cache show \
  --resource-group rg-hpc-monitoring \
  --name <cache-name>

# Check Batch account
az batch account show \
  --resource-group rg-hpc-monitoring \
  --name <batch-account-name>

# Check Log Analytics workspace
az monitor log-analytics workspace show \
  --resource-group rg-hpc-monitoring \
  --workspace-name <workspace-name>
```

## Monitoring and Alerts

### Access Workbook Dashboard

1. Navigate to Azure Portal
2. Go to Azure Monitor → Workbooks
3. Find your HPC monitoring workbook
4. Click to open the dashboard

### Configure Additional Alerts

```bash
# Create custom metric alert
az monitor metrics alert create \
  --name "custom-hpc-alert" \
  --resource-group rg-hpc-monitoring \
  --scopes <resource-id> \
  --condition "avg MetricName > threshold"
```

### Query Logs

```bash
# Query HPC Cache metrics
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "AzureMetrics | where ResourceProvider == 'MICROSOFT.STORAGECACHE'"
```

## Troubleshooting

### Common Issues

1. **Deployment Fails**: Check parameter values and resource quotas
2. **HPC Cache Creation Error**: Verify subnet delegation and permissions
3. **Batch Pool Issues**: Ensure VM size availability in the region
4. **Monitoring Data Missing**: Check diagnostic settings configuration

### Debug Commands

```bash
# Check deployment errors
az deployment group show \
  --resource-group rg-hpc-monitoring \
  --name <deployment-name> \
  --query "properties.error"

# Validate Bicep template
az deployment group validate \
  --resource-group rg-hpc-monitoring \
  --template-file main.bicep \
  --parameters @parameters.json
```

## Cost Optimization

### Resource Sizing Guidelines

- **Development**: Use minimal cache sizes (3072 GB) and small VM sizes
- **Production**: Size based on workload requirements and performance testing
- **Monitoring**: Configure appropriate log retention periods

### Cost Monitoring

```bash
# Check resource costs
az consumption usage list \
  --start-date 2024-01-01 \
  --end-date 2024-01-31 \
  --resource-group rg-hpc-monitoring
```

## Security Considerations

- Storage accounts use TLS 1.2 minimum
- Network security groups restrict access
- Diagnostic data stored in Log Analytics workspace
- RBAC permissions follow least privilege principle

## Cleanup

### Remove All Resources

```bash
# Delete resource group and all resources
az group delete \
  --name rg-hpc-monitoring \
  --yes \
  --no-wait
```

### Selective Cleanup

```bash
# Remove specific resources
az hpc-cache delete \
  --resource-group rg-hpc-monitoring \
  --name <cache-name>

az batch account delete \
  --resource-group rg-hpc-monitoring \
  --name <batch-account-name>
```

## Support and Documentation

- [Azure HPC Cache Documentation](https://docs.microsoft.com/en-us/azure/hpc-cache/)
- [Azure Monitor Workbooks Guide](https://docs.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview)
- [Azure Batch Documentation](https://docs.microsoft.com/en-us/azure/batch/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)

## Migration Notice

**Important**: Azure HPC Cache will be retired on September 30, 2025. Consider migrating to:
- [Azure Managed Lustre](https://docs.microsoft.com/en-us/azure/azure-managed-lustre/)
- [Azure NetApp Files](https://docs.microsoft.com/en-us/azure/azure-netapp-files/)

## Contributing

To contribute improvements to these templates:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.