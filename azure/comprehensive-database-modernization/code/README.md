# Infrastructure as Code for Comprehensive Database Modernization with Migration Service and Azure Backup

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Comprehensive Database Modernization with Migration Service and Azure Backup".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (ARM template abstraction)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.37.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Azure Database Migration Service
  - Azure SQL Database
  - Azure Backup (Recovery Services Vault)
  - Azure Monitor and Log Analytics
  - Azure Storage Account
- Network connectivity between on-premises environment and Azure (VPN or ExpressRoute)
- On-premises SQL Server instance with sample database for migration
- Basic understanding of SQL Server administration and Azure resource management

## Quick Start

### Using Bicep

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-db-migration \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json

# Monitor deployment status
az deployment group show \
    --resource-group rg-db-migration \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
az resource list --resource-group rg-db-migration-* --output table
```

## Architecture Overview

This implementation creates the following Azure resources:

- **Azure SQL Database**: Target database for migration with automated backups
- **Azure Database Migration Service**: Orchestrates the migration process
- **Recovery Services Vault**: Provides backup and disaster recovery capabilities
- **Azure Storage Account**: Stores migration assets and backup files
- **Log Analytics Workspace**: Centralized logging and monitoring
- **Azure Monitor**: Alerting and metrics collection
- **Action Groups**: Automated notifications for alerts

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "sqlServerName": {
      "value": "sqlserver-unique"
    },
    "sqlDatabaseName": {
      "value": "modernized-db"
    },
    "dmsServiceName": {
      "value": "dms-service"
    },
    "adminEmail": {
      "value": "admin@contoso.com"
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
location            = "eastus"
sql_server_name     = "sqlserver-unique"
sql_database_name   = "modernized-db"
dms_service_name    = "dms-service"
admin_email         = "admin@contoso.com"
backup_retention_days = 30
```

### Bash Script Environment Variables

The deploy script uses these environment variables (set automatically with random suffix):

```bash
export RESOURCE_GROUP="rg-db-migration-${RANDOM_SUFFIX}"
export LOCATION="eastus"
export SQL_SERVER_NAME="sqlserver-${RANDOM_SUFFIX}"
export SQL_DATABASE_NAME="modernized-db"
export DMS_SERVICE_NAME="dms-${RANDOM_SUFFIX}"
export ADMIN_EMAIL="admin@contoso.com"
```

## Deployment Process

### Phase 1: Foundation Resources
- Resource Group creation
- Log Analytics Workspace
- Storage Account for migration assets

### Phase 2: Database Infrastructure
- Azure SQL Server and Database
- Firewall rules and security configuration
- Database-level backup configuration

### Phase 3: Migration Services
- Azure Database Migration Service
- Migration project setup
- Connection configurations

### Phase 4: Backup and Recovery
- Recovery Services Vault
- Backup policies and protection
- Automated backup scheduling

### Phase 5: Monitoring and Alerting
- Azure Monitor configuration
- Action groups for notifications
- Metric alerts for failures
- Diagnostic settings

## Validation and Testing

After deployment, verify the infrastructure:

```bash
# Check Database Migration Service status
az dms show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DMS_SERVICE_NAME} \
    --query '{name:name, state:state, location:location}'

# Verify Azure SQL Database
az sql db show \
    --resource-group ${RESOURCE_GROUP} \
    --server ${SQL_SERVER_NAME} \
    --name ${SQL_DATABASE_NAME} \
    --query '{name:name, status:status, serviceLevelObjective:currentServiceObjectiveName}'

# Check backup configuration
az backup protection show \
    --resource-group ${RESOURCE_GROUP} \
    --vault-name ${BACKUP_VAULT_NAME} \
    --container-name "SQLDataBase;mssqlserver;${SQL_SERVER_NAME};${SQL_DATABASE_NAME}" \
    --item-name "${SQL_DATABASE_NAME}"

# Test monitoring configuration
az monitor diagnostic-settings list \
    --resource "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DataMigration/services/${DMS_SERVICE_NAME}"
```

## Cost Optimization

### Estimated Costs (US East region)

- **Azure SQL Database (S2)**: ~$30/month
- **Azure Database Migration Service (Premium)**: ~$40/month during migration
- **Recovery Services Vault**: Storage-based pricing (~$5-10/month)
- **Log Analytics Workspace**: Pay-per-GB ingestion (~$5-15/month)
- **Storage Account**: ~$2-5/month for migration assets

### Cost-Saving Tips

1. **Scale Down After Migration**: Reduce SQL Database service tier post-migration
2. **Delete DMS Service**: Remove Database Migration Service after successful migration
3. **Monitor Log Analytics**: Set retention policies to control costs
4. **Use Reserved Instances**: For long-term SQL Database usage
5. **Regular Cleanup**: Remove old backup files and migration artifacts

## Security Considerations

### Built-in Security Features

- **Encryption at Rest**: All data encrypted using Azure Storage Service Encryption
- **Encryption in Transit**: TLS 1.2 enforced for all connections
- **Network Security**: Firewall rules restrict database access
- **Identity and Access Management**: Azure AD integration ready
- **Audit Logging**: Comprehensive logging to Log Analytics
- **Backup Encryption**: Recovery Services Vault encrypts all backups

### Security Best Practices

1. **Enable Azure AD Authentication**: Replace SQL authentication post-migration
2. **Configure Private Endpoints**: Eliminate public internet access
3. **Implement Network Security Groups**: Control traffic at subnet level
4. **Enable Advanced Threat Protection**: Detect suspicious activities
5. **Regular Security Assessments**: Use Azure Security Center recommendations

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-db-migration \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Destroy all resources
cd terraform/
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify cleanup completion
az group list --query "[?starts_with(name, 'rg-db-migration')]" --output table
```

## Troubleshooting

### Common Issues

1. **Migration Service Provisioning Fails**:
   - Check subscription quota limits
   - Verify region availability for Premium SKU
   - Ensure proper permissions for service principal

2. **Backup Protection Fails**:
   - Verify SQL Database is online
   - Check Recovery Services Vault permissions
   - Ensure backup policy is valid

3. **Monitoring Alerts Not Firing**:
   - Verify metric alert conditions
   - Check action group configuration
   - Ensure proper diagnostic settings

### Debugging Commands

```bash
# Check deployment status
az deployment group list \
    --resource-group ${RESOURCE_GROUP} \
    --query '[].{name:name, state:properties.provisioningState}'

# View activity log
az monitor activity-log list \
    --resource-group ${RESOURCE_GROUP} \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)

# Check service health
az resource list \
    --resource-group ${RESOURCE_GROUP} \
    --query '[].{name:name, type:type, location:location, provisioningState:properties.provisioningState}'
```

## Monitoring and Maintenance

### Key Metrics to Monitor

- **Database Migration Service**: Success rate, duration, errors
- **Azure SQL Database**: DTU/vCore utilization, connection count
- **Recovery Services Vault**: Backup success rate, storage usage
- **Log Analytics**: Query performance, data ingestion volume

### Recommended Alerts

1. **Migration Failure Alert**: Immediate notification for failed migrations
2. **Backup Failure Alert**: Daily backup failure notifications
3. **High Database Utilization**: Performance degradation warnings
4. **Storage Threshold Alert**: Monitor backup storage usage

### Maintenance Tasks

- **Weekly**: Review backup reports and migration logs
- **Monthly**: Analyze cost reports and optimize resource usage
- **Quarterly**: Review security assessments and update policies
- **Annually**: Update backup retention policies and disaster recovery plans

## Advanced Configuration

### Custom Backup Policies

Modify the backup policy configuration for specific requirements:

```json
{
  "backupManagementType": "AzureSql",
  "workLoadType": "SQLDataBase",
  "schedulePolicy": {
    "schedulePolicyType": "SimpleSchedulePolicy",
    "scheduleRunFrequency": "Daily",
    "scheduleRunTimes": ["02:00:00Z"]
  },
  "retentionPolicy": {
    "retentionPolicyType": "LongTermRetentionPolicy",
    "dailySchedule": {
      "retentionDuration": {
        "count": 180,
        "durationType": "Days"
      }
    },
    "weeklySchedule": {
      "retentionDuration": {
        "count": 52,
        "durationType": "Weeks"
      }
    }
  }
}
```

### Migration Performance Tuning

Optimize migration performance with these settings:

```bash
# Increase DMS service tier for better performance
az dms create \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DMS_SERVICE_NAME} \
    --location ${LOCATION} \
    --sku Premium_8vCores

# Configure parallel data transfer
MIGRATION_CONFIG='{
    "parallelism": 8,
    "batchSize": 10000,
    "timeout": 3600
}'
```

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# Azure DevOps Pipeline example
stages:
- stage: Deploy
  jobs:
  - job: DeployInfrastructure
    steps:
    - task: AzureCLI@2
      inputs:
        azureSubscription: 'Azure-Connection'
        scriptType: 'bash'
        scriptPath: 'scripts/deploy.sh'
        workingDirectory: 'azure/orchestrating-database-modernization-with-azure-database-migration-service-and-azure-backup/code'
```

### PowerShell Module Integration

```powershell
# PowerShell deployment example
Import-Module Az

# Deploy using Bicep
New-AzResourceGroupDeployment `
    -ResourceGroupName "rg-db-migration" `
    -TemplateFile "bicep/main.bicep" `
    -TemplateParameterFile "bicep/parameters.json"
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Azure Documentation**: [Azure Database Migration Service](https://docs.microsoft.com/en-us/azure/dms/)
3. **Azure Support**: Create support tickets for service-specific issues
4. **Community Forums**: [Microsoft Q&A](https://docs.microsoft.com/en-us/answers/topics/azure-database-migration-service.html)

## Contributing

When modifying this infrastructure code:

1. Test all changes in a development environment
2. Update parameter documentation
3. Verify security configurations
4. Update cost estimates
5. Test cleanup procedures

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Modify according to your organization's requirements and security policies.