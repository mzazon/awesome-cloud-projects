# Infrastructure as Code for Network Threat Detection Automation with Watcher and Analytics

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Network Threat Detection Automation with Watcher and Analytics".

## Available Implementations

- **Bicep**: Microsoft's recommended infrastructure as code language for Azure
- **Terraform**: Multi-cloud infrastructure as code using HashiCorp Configuration Language
- **Scripts**: Bash deployment and cleanup scripts for automated resource management

## Architecture Overview

This solution implements automated network threat detection using:

- **Azure Network Watcher**: Network monitoring and NSG Flow Logs collection
- **Azure Storage Account**: Secure storage for network flow log data
- **Azure Log Analytics Workspace**: Advanced analytics and threat detection queries
- **Azure Monitor Alert Rules**: Automated threat detection and alerting
- **Azure Logic Apps**: Automated incident response workflows
- **Azure Monitor Workbooks**: Real-time threat monitoring dashboards

## Prerequisites

### General Requirements

- Azure subscription with appropriate permissions:
  - Network Contributor role
  - Security Admin role
  - Log Analytics Contributor role
  - Logic App Contributor role
- Azure CLI v2.50.0 or later installed and configured
- Basic understanding of network security concepts and KQL (Kusto Query Language)
- At least one Azure Virtual Network with Network Security Groups configured

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension installed
- Bicep CLI v0.15.0 or later

#### For Terraform
- Terraform v1.0.0 or later
- Azure Provider v3.0.0 or later

#### For Bash Scripts
- Azure CLI authenticated with appropriate permissions
- jq utility for JSON processing
- OpenSSL for random string generation

### Cost Estimation

- **Log Analytics Workspace**: $2.30/GB ingested (Pay-as-you-go pricing)
- **Storage Account**: $0.018/GB/month (Hot tier, LRS)
- **Logic Apps**: $0.000025 per action execution
- **Network Watcher**: No additional charges for NSG Flow Logs
- **Estimated monthly cost**: $50-100 depending on network traffic volume

> **Note**: Network Watcher is automatically enabled when you create your first virtual network in a region.

## Quick Start

### Using Bicep

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-network-threat-detection \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters storageAccountPrefix=sanetlogs \
    --parameters logAnalyticsWorkspaceName=law-threat-detection

# Verify deployment
az deployment group show \
    --resource-group rg-network-threat-detection \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the deployment plan
terraform plan -var="location=eastus" -var="resource_group_name=rg-network-threat-detection"

# Apply the infrastructure
terraform apply -var="location=eastus" -var="resource_group_name=rg-network-threat-detection"

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
az resource list \
    --resource-group rg-network-threat-detection \
    --output table
```

## Customization

### Configuration Variables

#### Bicep Parameters
- `location`: Azure region for resource deployment (default: eastus)
- `resourceGroupName`: Name of the resource group
- `storageAccountPrefix`: Prefix for storage account name
- `logAnalyticsWorkspaceName`: Name of the Log Analytics workspace
- `logAnalyticsRetentionDays`: Data retention period (default: 30 days)
- `alertEvaluationFrequency`: How often alert rules evaluate (default: PT5M)
- `logicAppName`: Name of the Logic Apps workflow

#### Terraform Variables
- `location`: Azure region for deployment
- `resource_group_name`: Resource group name
- `storage_account_name`: Storage account name (must be globally unique)
- `log_analytics_workspace_name`: Log Analytics workspace name
- `logic_app_name`: Logic Apps workflow name
- `environment`: Environment tag (default: production)
- `project`: Project tag (default: network-security)

#### Bash Script Environment Variables
- `RESOURCE_GROUP`: Resource group name
- `LOCATION`: Azure region
- `STORAGE_ACCOUNT`: Storage account name
- `LOG_ANALYTICS_WORKSPACE`: Log Analytics workspace name
- `LOGIC_APP_NAME`: Logic Apps workflow name

### Threat Detection Customization

#### KQL Query Thresholds
Modify these values in the alert rules to adjust sensitivity:

```kusto
// Port scanning detection
| where DestPorts > 20 and FlowCount > 50  // Adjust thresholds as needed

// Data exfiltration detection
| where TotalBytes > 1000000000  // 1GB threshold - adjust for your environment

// Failed connection attempts
| where FailedAttempts > 100  // Adjust based on normal traffic patterns
```

#### Alert Rule Configuration
- **Evaluation Frequency**: How often queries run (PT5M = every 5 minutes)
- **Window Size**: Time window for data analysis (PT1H = 1 hour)
- **Threshold**: Number of results that trigger an alert
- **Severity**: Alert severity level (0=Critical, 1=Error, 2=Warning, 3=Informational)

### Logic Apps Workflow Customization

The workflow can be extended to include:
- **Microsoft Teams notifications**: Add Teams connector
- **ServiceNow integration**: Create incident tickets automatically
- **Azure Automation runbooks**: Trigger automated remediation
- **Custom webhook endpoints**: Integrate with external systems

## Validation and Testing

### Post-Deployment Validation

1. **Verify NSG Flow Logs are active**:
   ```bash
   # Check flow log configuration
   az network watcher flow-log list \
       --resource-group NetworkWatcherRG \
       --output table
   ```

2. **Validate Log Analytics data ingestion**:
   ```bash
   # Query for recent network data
   az monitor log-analytics query \
       --workspace $(az monitor log-analytics workspace show \
           --resource-group rg-network-threat-detection \
           --workspace-name law-threat-detection \
           --query id --output tsv) \
       --analytics-query "AzureNetworkAnalytics_CL | take 10"
   ```

3. **Test alert rules**:
   ```bash
   # List active alert rules
   az monitor scheduled-query list \
       --resource-group rg-network-threat-detection \
       --output table
   ```

4. **Verify Logic Apps workflow**:
   ```bash
   # Check workflow status
   az logic workflow show \
       --resource-group rg-network-threat-detection \
       --name la-threat-response \
       --query state
   ```

### Security Validation

- **Storage Account**: Verify HTTPS-only access and appropriate access tiers
- **Log Analytics**: Confirm appropriate retention policies and access controls
- **Alert Rules**: Validate thresholds match your security requirements
- **Logic Apps**: Ensure secure connections and proper authentication

## Monitoring and Maintenance

### Key Metrics to Monitor

1. **Data Ingestion**: Monitor Log Analytics data ingestion rates
2. **Alert Frequency**: Track alert rule firing frequency to tune thresholds
3. **Storage Costs**: Monitor storage account usage and costs
4. **Query Performance**: Optimize KQL queries for better performance

### Maintenance Tasks

1. **Regular threshold review**: Adjust alert thresholds based on observed patterns
2. **Query optimization**: Improve KQL query performance as data volume grows
3. **Cost optimization**: Implement data lifecycle policies for storage
4. **Security updates**: Keep Logic Apps connectors and workflows updated

## Troubleshooting

### Common Issues

1. **No flow log data in Log Analytics**:
   - Verify Network Watcher is enabled in your region
   - Check NSG Flow Logs configuration
   - Ensure proper permissions for data ingestion

2. **Alert rules not firing**:
   - Verify KQL query syntax and logic
   - Check alert rule evaluation frequency
   - Ensure sufficient data volume for thresholds

3. **Logic Apps workflow failures**:
   - Check connector authentication
   - Verify workflow trigger configuration
   - Review Logic Apps run history for error details

4. **High storage costs**:
   - Implement storage lifecycle policies
   - Adjust Log Analytics retention period
   - Consider data sampling for high-volume environments

### Support Resources

- [Azure Network Watcher Documentation](https://docs.microsoft.com/en-us/azure/network-watcher/)
- [Log Analytics Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/logs/)
- [Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [KQL Reference](https://docs.microsoft.com/en-us/azure/kusto/query/)

## Cleanup

### Using Bicep
```bash
# Delete the resource group and all resources
az group delete \
    --name rg-network-threat-detection \
    --yes \
    --no-wait
```

### Using Terraform
```bash
# Destroy all resources
cd terraform/
terraform destroy -var="location=eastus" -var="resource_group_name=rg-network-threat-detection"
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Verification
```bash
# Verify all resources are deleted
az resource list \
    --resource-group rg-network-threat-detection \
    --output table

# Check for any remaining Network Watcher resources
az network watcher flow-log list \
    --resource-group NetworkWatcherRG \
    --output table
```

## Security Considerations

### Data Protection
- All data transmission uses HTTPS encryption
- Storage account configured with secure transfer required
- Log Analytics workspace uses Azure AD authentication
- Network flow logs contain potentially sensitive network information

### Access Control
- Implement least privilege access for all resources
- Use Azure RBAC for granular permissions
- Regularly review and audit access permissions
- Consider using Azure Key Vault for sensitive configuration values

### Compliance
- Network flow logs may contain data subject to compliance requirements
- Configure appropriate data retention policies
- Implement data governance policies for log data
- Consider data residency requirements for your organization

## Migration Notice

> **Important**: NSG Flow Logs will be deprecated starting June 30, 2025, with full retirement by September 30, 2027. Microsoft recommends migrating to VNet Flow Logs for continued network monitoring capabilities. Plan your migration strategy accordingly to maintain threat detection capabilities.

## Support

For issues with this infrastructure code:
1. Review the troubleshooting section above
2. Check the original recipe documentation
3. Consult Azure provider documentation for specific resource types
4. Review Azure Monitor and Network Watcher documentation

## Contributing

When modifying this infrastructure code:
1. Follow Azure naming conventions and best practices
2. Update variable documentation for any new parameters
3. Test changes in a development environment first
4. Update this README.md with any new features or requirements