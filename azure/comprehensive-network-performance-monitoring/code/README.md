# Infrastructure as Code for Comprehensive Network Performance Monitoring Solution

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Comprehensive Network Performance Monitoring Solution".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI 2.0.74 or later installed and configured
- Azure subscription with appropriate permissions
- Contributor or Network Contributor permissions on the subscription
- Network Watcher enabled in target Azure regions
- Basic understanding of Azure networking concepts and monitoring

### Cost Considerations

- Estimated monthly cost: $10-20 for monitoring resources and data ingestion
- Connection Monitor charges apply based on number of tests and frequency
- Log Analytics workspace charges for data ingestion and retention
- Virtual machines incur standard compute charges

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to Bicep directory
cd bicep/

# Create resource group
az group create --name rg-network-monitoring --location eastus

# Deploy infrastructure
az deployment group create \
    --resource-group rg-network-monitoring \
    --template-file main.bicep \
    --parameters @parameters.json

# Verify deployment
az deployment group show \
    --resource-group rg-network-monitoring \
    --name main
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Apply infrastructure
terraform apply

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

# Verify deployment status
az resource list --resource-group rg-network-monitoring --output table
```

## Architecture Overview

The deployed infrastructure includes:

- **Log Analytics Workspace**: Centralized logging and monitoring data storage
- **Application Insights**: Application performance monitoring and telemetry
- **Virtual Network**: Isolated network environment for testing
- **Virtual Machines**: Source and destination endpoints for connection testing
- **Network Watcher**: Network performance monitoring and diagnostics
- **Connection Monitor**: Continuous network connectivity testing
- **Storage Account**: Flow logs and diagnostic data storage
- **Network Security Groups**: Network traffic filtering and flow logging
- **Alert Rules**: Proactive monitoring and notification system
- **Action Groups**: Alert notification and response automation

## Configuration Options

### Bicep Parameters

Customize the deployment by modifying `parameters.json`:

```json
{
  "location": "eastus",
  "resourceGroupName": "rg-network-monitoring",
  "vnetAddressPrefix": "10.0.0.0/16",
  "subnetAddressPrefix": "10.0.1.0/24",
  "vmSize": "Standard_B2s",
  "adminUsername": "azureuser",
  "testFrequency": 30,
  "logRetentionDays": 30
}
```

### Terraform Variables

Customize the deployment by modifying `variables.tf` or using a `terraform.tfvars` file:

```hcl
location = "eastus"
resource_group_name = "rg-network-monitoring"
vnet_address_space = ["10.0.0.0/16"]
subnet_address_prefix = "10.0.1.0/24"
vm_size = "Standard_B2s"
admin_username = "azureuser"
test_frequency = 30
log_retention_days = 30
```

### Bash Script Environment Variables

Set environment variables before running scripts:

```bash
export LOCATION="eastus"
export RESOURCE_GROUP="rg-network-monitoring"
export VNET_ADDRESS_PREFIX="10.0.0.0/16"
export SUBNET_ADDRESS_PREFIX="10.0.1.0/24"
export VM_SIZE="Standard_B2s"
export ADMIN_USERNAME="azureuser"
```

## Deployment Validation

### Verify Network Watcher Configuration

```bash
# Check Network Watcher status
az network watcher show --location eastus --resource-group NetworkWatcherRG

# Verify connection monitor
az network watcher connection-monitor list --location eastus
```

### Test Network Connectivity

```bash
# Test connectivity between VMs
az network watcher test-connectivity \
    --source-resource /subscriptions/{subscription-id}/resourceGroups/rg-network-monitoring/providers/Microsoft.Compute/virtualMachines/vm-source \
    --dest-resource /subscriptions/{subscription-id}/resourceGroups/rg-network-monitoring/providers/Microsoft.Compute/virtualMachines/vm-dest \
    --dest-port 80 \
    --protocol TCP
```

### Query Monitoring Data

```bash
# Query Log Analytics workspace
az monitor log-analytics query \
    --workspace {workspace-id} \
    --analytics-query "NetworkMonitoring | where TimeGenerated > ago(10m) | summarize by TestName, SourceName, DestinationName"

# Check Application Insights telemetry
az monitor app-insights query \
    --app {app-insights-name} \
    --analytics-query "customMetrics | where name contains 'Network' | summarize count() by name"
```

## Monitoring and Alerting

### Default Alert Rules

The infrastructure creates the following alert rules:

1. **High Network Latency Alert**: Triggers when network latency exceeds 1000ms
2. **Network Connectivity Failure**: Triggers when connectivity drops below 100%
3. **Packet Loss Alert**: Triggers when packet loss exceeds 5%
4. **Application Response Time**: Triggers when response time increases significantly

### Custom Queries

Use these sample queries in Log Analytics:

```kusto
// Network latency trends
NetworkMonitoring
| where TimeGenerated > ago(1h)
| summarize AvgLatency = avg(LatencyMs) by bin(TimeGenerated, 5m)
| render timechart

// Network-Application correlation
let NetworkData = NetworkMonitoring
| where TimeGenerated > ago(1h)
| summarize AvgLatency = avg(LatencyMs) by bin(TimeGenerated, 5m);
let AppData = requests
| where timestamp > ago(1h)
| summarize AvgResponseTime = avg(duration) by bin(timestamp, 5m);
NetworkData
| join kind=inner (AppData) on $left.TimeGenerated == $right.timestamp
| project TimeGenerated, AvgLatency, AvgResponseTime
| render timechart
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name rg-network-monitoring --yes --no-wait

# Verify deletion
az group exists --name rg-network-monitoring
```

### Using Terraform

```bash
# Navigate to Terraform directory
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

# Verify resource deletion
az resource list --resource-group rg-network-monitoring
```

## Troubleshooting

### Common Issues

1. **Network Watcher Not Enabled**
   ```bash
   # Enable Network Watcher
   az network watcher configure --location eastus --enabled true
   ```

2. **Connection Monitor Fails to Start**
   ```bash
   # Check VM extensions
   az vm extension list --vm-name vm-source --resource-group rg-network-monitoring
   
   # Install Network Watcher extension
   az vm extension set \
       --vm-name vm-source \
       --resource-group rg-network-monitoring \
       --name NetworkWatcherAgentLinux \
       --publisher Microsoft.Azure.NetworkWatcher
   ```

3. **Log Analytics Data Not Appearing**
   ```bash
   # Check workspace configuration
   az monitor log-analytics workspace show \
       --resource-group rg-network-monitoring \
       --workspace-name {workspace-name}
   
   # Verify data collection rules
   az monitor data-collection rule list \
       --resource-group rg-network-monitoring
   ```

### Debugging Steps

1. **Check Resource Deployment Status**
   ```bash
   az deployment group list --resource-group rg-network-monitoring
   ```

2. **Verify Network Connectivity**
   ```bash
   az network watcher test-connectivity \
       --source-resource {source-vm-id} \
       --dest-resource {dest-vm-id} \
       --dest-port 80
   ```

3. **Review Activity Logs**
   ```bash
   az monitor activity-log list \
       --resource-group rg-network-monitoring \
       --start-time 2024-01-01T00:00:00Z
   ```

## Security Considerations

### Network Security

- Network Security Groups (NSGs) are configured with minimal required rules
- Flow logs are enabled for network traffic analysis
- VM access is restricted to necessary ports only
- Storage accounts use secure transfer and private endpoints where possible

### Identity and Access Management

- Managed identities are used for service-to-service authentication
- Least privilege principle is applied to all role assignments
- Log Analytics workspace access is controlled through RBAC
- Application Insights uses Azure AD integration for access control

### Data Protection

- All data is encrypted at rest and in transit
- Log Analytics workspace uses customer-managed encryption keys
- Network flow logs are stored in encrypted storage accounts
- Application Insights telemetry is encrypted and access-controlled

## Performance Optimization

### Connection Monitor Configuration

- Test frequency is configurable (default: 30 seconds)
- Multiple test configurations for different protocols
- Geographically distributed test endpoints
- Customizable success thresholds

### Log Analytics Optimization

- Data retention policies configured for cost optimization
- Query performance optimized through proper indexing
- Custom metrics reduce data ingestion costs
- Automated data archiving for long-term storage

## Integration Examples

### Power BI Integration

```bash
# Connect Power BI to Log Analytics
az monitor log-analytics workspace show \
    --resource-group rg-network-monitoring \
    --workspace-name {workspace-name} \
    --query customerId
```

### Azure DevOps Integration

```yaml
# Azure DevOps pipeline integration
trigger:
  - main

stages:
  - stage: Deploy
    jobs:
      - job: DeployInfrastructure
        steps:
          - task: AzureCLI@2
            inputs:
              azureSubscription: 'Azure-Connection'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                az deployment group create \
                  --resource-group rg-network-monitoring \
                  --template-file bicep/main.bicep
```

## Support and Documentation

### Additional Resources

- [Azure Network Watcher Documentation](https://docs.microsoft.com/en-us/azure/network-watcher/)
- [Application Insights Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review Azure service health and status pages
3. Consult the original recipe documentation
4. Contact Azure support for service-specific issues

## Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Validate with both Bicep and Terraform implementations
3. Update documentation and examples
4. Follow Azure Well-Architected Framework principles
5. Ensure security best practices are maintained