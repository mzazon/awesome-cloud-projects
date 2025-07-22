# Infrastructure as Code for Proactive Disaster Recovery with Backup Center Automation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Proactive Disaster Recovery with Backup Center Automation".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (ARM template successor)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.60.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Recovery Services Vault creation and management
  - Log Analytics Workspace creation
  - Logic Apps deployment
  - Azure Monitor configuration
  - Resource Group management
- For Terraform: Terraform v1.0+ installed
- For Bicep: Bicep CLI installed (included with Azure CLI v2.20.0+)
- Appropriate Azure RBAC permissions:
  - Backup Contributor
  - Logic App Contributor
  - Monitoring Contributor
  - Storage Account Contributor

## Estimated Costs

- Recovery Services Vaults: $0-200/month (depends on backup data volume)
- Log Analytics Workspace: $2-50/month (depends on data ingestion)
- Logic Apps: $0.000025 per action execution
- Storage Account: $20-100/month (depends on backup data retention)
- Azure Monitor alerts: $0.10 per metric alert rule per month

## Quick Start

### Using Bicep

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-dr-orchestration \
    --template-file main.bicep \
    --parameters primaryRegion=eastus \
                secondaryRegion=westus2 \
                environmentName=prod

# Monitor deployment progress
az deployment group show \
    --resource-group rg-dr-orchestration \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="primary_region=eastus" \
               -var="secondary_region=westus2" \
               -var="environment_name=prod"

# Deploy infrastructure
terraform apply -var="primary_region=eastus" \
                -var="secondary_region=westus2" \
                -var="environment_name=prod"

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export PRIMARY_REGION="eastus"
export SECONDARY_REGION="westus2"
export ENVIRONMENT_NAME="prod"

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment (optional)
az group deployment list \
    --resource-group rg-dr-orchestration \
    --output table
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `primaryRegion` | Primary Azure region for resources | `eastus` | Yes |
| `secondaryRegion` | Secondary Azure region for DR | `westus2` | Yes |
| `environmentName` | Environment identifier (dev/test/prod) | `prod` | Yes |
| `backupRetentionDays` | Backup retention period in days | `30` | No |
| `enableCrossRegionRestore` | Enable cross-region restore capability | `true` | No |
| `logAnalyticsSkuName` | Log Analytics workspace SKU | `PerGB2018` | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `primary_region` | Primary Azure region | `string` | `eastus` | Yes |
| `secondary_region` | Secondary Azure region | `string` | `westus2` | Yes |
| `environment_name` | Environment identifier | `string` | `prod` | Yes |
| `backup_retention_days` | Backup retention period | `number` | `30` | No |
| `enable_cross_region_restore` | Enable cross-region restore | `bool` | `true` | No |
| `log_analytics_sku` | Log Analytics workspace SKU | `string` | `PerGB2018` | No |
| `notification_email` | Email for disaster recovery alerts | `string` | `` | No |
| `notification_phone` | Phone number for SMS alerts | `string` | `` | No |

### Environment Variables (Bash Scripts)

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PRIMARY_REGION` | Primary Azure region | `eastus` | Yes |
| `SECONDARY_REGION` | Secondary Azure region | `westus2` | Yes |
| `ENVIRONMENT_NAME` | Environment identifier | `prod` | Yes |
| `BACKUP_RETENTION_DAYS` | Backup retention period | `30` | No |
| `NOTIFICATION_EMAIL` | Email for alerts | `` | No |
| `NOTIFICATION_PHONE` | Phone for SMS alerts | `` | No |

## Post-Deployment Configuration

After deploying the infrastructure, complete these manual configuration steps:

1. **Configure Protected Resources**:
   ```bash
   # Enable backup for existing VMs
   az backup protection enable-for-vm \
       --resource-group rg-dr-orchestration \
       --vault-name rsv-dr-primary-[suffix] \
       --vm [vm-name] \
       --policy-name DRVMPolicy
   ```

2. **Update Logic Apps Webhook URLs**:
   - Navigate to Azure Portal > Logic Apps
   - Update webhook URLs in Teams/email action configurations
   - Test the workflow manually

3. **Configure Custom Alert Rules**:
   ```bash
   # Add custom metrics alerts based on your specific requirements
   az monitor metrics alert create \
       --name "CustomBackupAlert" \
       --resource-group rg-dr-orchestration \
       --condition "count 'BackupHealthEvent' > 0" \
       --description "Custom backup monitoring alert"
   ```

4. **Set Up Backup Center Dashboards**:
   - Access Azure Portal > Backup Center
   - Configure custom reports and dashboards
   - Set up backup governance policies

## Monitoring and Validation

### Verify Deployment

```bash
# Check Recovery Services Vault status
az backup vault show \
    --name rsv-dr-primary-[suffix] \
    --resource-group rg-dr-backup \
    --query '{name:name,location:location,properties:properties.provisioningState}'

# Verify cross-region restore capability
az backup vault backup-properties show \
    --name rsv-dr-primary-[suffix] \
    --resource-group rg-dr-backup \
    --query crossRegionRestoreFlag

# Check Logic Apps workflow status
az logic workflow show \
    --name la-dr-orchestration-[suffix] \
    --resource-group rg-dr-orchestration \
    --query '{name:name,state:state}'

# Verify monitoring configuration
az monitor log-analytics workspace show \
    --workspace-name law-dr-monitoring-[suffix] \
    --resource-group rg-dr-orchestration \
    --query '{name:name,provisioningState:provisioningState}'
```

### Test Disaster Recovery Workflow

```bash
# Trigger test backup job
az backup protection backup-now \
    --resource-group rg-dr-backup \
    --vault-name rsv-dr-primary-[suffix] \
    --container-name [container-name] \
    --item-name [backup-item-name]

# Monitor backup job status
az backup job list \
    --resource-group rg-dr-backup \
    --vault-name rsv-dr-primary-[suffix] \
    --output table

# Test alert notification (simulate failure)
az monitor metrics alert create \
    --name "TestAlert" \
    --resource-group rg-dr-orchestration \
    --condition "count 'TestMetric' > 0" \
    --action ag-dr-alerts-[suffix]
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all Bicep-deployed resources)
az group delete \
    --name rg-dr-orchestration \
    --yes \
    --no-wait

# Delete backup resource group
az group delete \
    --name rg-dr-backup \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="primary_region=eastus" \
                  -var="secondary_region=westus2" \
                  -var="environment_name=prod"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
az group list --query "[?starts_with(name, 'rg-dr-')].name" --output table
```

## Customization

### Adding Custom Backup Policies

Modify the backup policies in your chosen IaC template:

**Bicep Example**:
```bicep
resource customBackupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2023-01-01' = {
  name: 'CustomDatabasePolicy'
  properties: {
    backupManagementType: 'AzureWorkload'
    workLoadType: 'SQLDataBase'
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: 'Weekly'
      scheduleRunDays: ['Sunday']
      scheduleRunTimes: ['2024-01-01T02:00:00Z']
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      weeklySchedule: {
        daysOfTheWeek: ['Sunday']
        retentionTimes: ['2024-01-01T02:00:00Z']
        retentionDuration: {
          count: 52
          durationType: 'Weeks'
        }
      }
    }
  }
}
```

### Extending Monitoring Capabilities

Add custom alert rules for application-specific metrics:

**Terraform Example**:
```hcl
resource "azurerm_monitor_metric_alert" "custom_alert" {
  name                = "custom-application-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights.main.id]
  
  criteria {
    metric_namespace = "Microsoft.Insights/components"
    metric_name      = "requests/failed"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}
```

### Multi-Subscription Deployment

For enterprise scenarios requiring cross-subscription deployment:

1. Modify provider configurations to target multiple subscriptions
2. Update RBAC assignments for cross-subscription access
3. Configure cross-subscription resource dependencies
4. Update monitoring and alerting for multi-subscription visibility

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**:
   ```bash
   # Check current user permissions
   az role assignment list --assignee $(az account show --query user.name -o tsv)
   
   # Assign required roles
   az role assignment create \
       --assignee [user-principal-name] \
       --role "Backup Contributor" \
       --scope /subscriptions/[subscription-id]
   ```

2. **Cross-Region Restore Not Available**:
   ```bash
   # Verify vault configuration
   az backup vault backup-properties show \
       --name [vault-name] \
       --resource-group [resource-group] \
       --query storageType
   
   # Update to GeoRedundant if needed
   az backup vault backup-properties set \
       --name [vault-name] \
       --resource-group [resource-group] \
       --backup-storage-redundancy GeoRedundant
   ```

3. **Logic Apps Authentication Issues**:
   ```bash
   # Enable managed identity
   az logic workflow identity assign \
       --name [logic-app-name] \
       --resource-group [resource-group]
   
   # Assign appropriate roles to managed identity
   az role assignment create \
       --assignee [managed-identity-principal-id] \
       --role "Recovery Services Contributor" \
       --scope [vault-resource-id]
   ```

### Log Analysis

Monitor deployment and operational logs:

```bash
# Check Azure Activity Log for deployment issues
az monitor activity-log list \
    --resource-group rg-dr-orchestration \
    --start-time 2024-01-01T00:00:00Z \
    --output table

# Query Log Analytics for backup job status
az monitor log-analytics query \
    --workspace [workspace-id] \
    --analytics-query "AzureBackupReport | where TimeGenerated > ago(24h) | summarize count() by JobStatus"

# Check Logic Apps run history
az logic workflow run list \
    --name [logic-app-name] \
    --resource-group [resource-group] \
    --output table
```

## Security Considerations

- All resources use managed identities where possible to avoid credential management
- Recovery Services Vaults use Azure AD authentication and role-based access control
- Cross-region replication uses encrypted storage with Microsoft-managed keys
- Network security groups and private endpoints can be added for enhanced security
- Backup data is encrypted at rest and in transit by default

## Compliance and Governance

This solution supports various compliance frameworks:

- **SOC 2**: Backup monitoring and alerting capabilities
- **ISO 27001**: Disaster recovery and business continuity controls
- **GDPR**: Data protection and retention policy enforcement
- **HIPAA**: Healthcare data backup and recovery requirements

Configure additional compliance features:

```bash
# Enable backup soft delete (recommended for compliance)
az backup vault backup-properties set \
    --name [vault-name] \
    --resource-group [resource-group] \
    --soft-delete-feature-state Enable

# Configure backup encryption with customer-managed keys
az backup vault encryption update \
    --name [vault-name] \
    --resource-group [resource-group] \
    --encryption-key-id [key-vault-key-id]
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for conceptual guidance
2. Check Azure service documentation for specific resource configurations
3. Consult Azure Support for subscription-specific issues
4. Review Azure Backup and Recovery Services documentation for advanced scenarios

## Contributing

To contribute improvements to this IaC implementation:

1. Test changes in a non-production environment
2. Validate against Azure best practices
3. Update documentation accordingly
4. Ensure compatibility across all supported deployment methods