# Azure Database for PostgreSQL Flexible Server Disaster Recovery - Bicep Implementation

This directory contains Azure Bicep templates for implementing a comprehensive disaster recovery solution for Azure Database for PostgreSQL Flexible Server with automated backups, cross-region replication, and monitoring.

## Architecture Overview

The solution deploys:

- **Primary PostgreSQL Flexible Server** with zone-redundant high availability
- **Read Replica** in secondary region for disaster recovery
- **Azure Backup Vaults** in both regions for long-term retention
- **Azure Monitor** with Log Analytics workspace for observability
- **Azure Automation** for automated disaster recovery workflows
- **Storage Account** for backup artifacts and recovery scripts
- **Alert Rules** for proactive monitoring and notifications

## Files Structure

```
bicep/
├── main.bicep                    # Main Bicep template
├── modules/
│   └── secondary-resources.bicep # Secondary region resources module
├── parameters.json               # Production parameters
├── parameters-dev.json           # Development parameters
├── deploy.ps1                    # Deployment script
├── cleanup.ps1                   # Cleanup script
└── README.md                     # This file
```

## Prerequisites

### Required Tools
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) v2.53.0 or later
- [Azure PowerShell](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps) v9.0.0 or later
- [Bicep CLI](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/install) v0.21.0 or later

### Azure Permissions
The deploying user/service principal needs the following permissions:
- `Contributor` role on the target subscription
- `User Access Administrator` role (for managed identity assignments)
- Permission to create resource groups in both regions

### Resource Requirements
- Two Azure regions (primary and secondary)
- Available quotas for PostgreSQL Flexible Server resources
- Estimated monthly cost: $150-300 (varies by region and configuration)

## Quick Start

### 1. Login to Azure
```bash
az login
az account set --subscription "your-subscription-id"
```

### 2. Clone and Navigate
```bash
git clone <repository-url>
cd azure/implementing-automated-database-disaster-recovery-with-azure-database-for-postgresql-flexible-server-and-azure-backup/code/bicep
```

### 3. Update Parameters
Edit `parameters.json` to customize the deployment:
```json
{
  "baseName": { "value": "your-postgres-dr" },
  "primaryLocation": { "value": "East US" },
  "secondaryLocation": { "value": "West US 2" },
  "administratorPassword": { "value": "YourSecurePassword123!" },
  "notificationEmail": { "value": "your-email@company.com" }
}
```

### 4. Deploy Using PowerShell Script
```powershell
.\deploy.ps1 -SubscriptionId "your-subscription-id" -ResourceGroupName "rg-postgres-dr" -Location "East US"
```

### 5. Deploy Using Azure CLI
```bash
# Create resource groups
az group create --name rg-postgres-dr --location "East US"
az group create --name rg-postgres-dr-secondary --location "West US 2"

# Deploy the main template
az deployment group create \
  --resource-group rg-postgres-dr \
  --template-file main.bicep \
  --parameters @parameters.json
```

## Deployment Options

### Production Deployment
Use `parameters.json` for production environments with:
- Zone-redundant high availability
- Geo-redundant backups
- Full monitoring and automation
- General Purpose tier

### Development Deployment
Use `parameters-dev.json` for development/testing with:
- Burstable tier for cost savings
- Reduced backup retention
- Simplified configuration

```powershell
.\deploy.ps1 -SubscriptionId "your-subscription-id" -ResourceGroupName "rg-postgres-dr-dev" -Location "East US" -ParametersFile "parameters-dev.json"
```

## Configuration Parameters

### Core Parameters
| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `baseName` | Base name for all resources | `postgres-dr` | Yes |
| `primaryLocation` | Primary region | `East US` | Yes |
| `secondaryLocation` | Secondary region | `West US 2` | Yes |
| `administratorLogin` | PostgreSQL admin username | `pgadmin` | Yes |
| `administratorPassword` | PostgreSQL admin password | - | Yes |

### PostgreSQL Configuration
| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `skuName` | PostgreSQL SKU | `Standard_D4s_v3` | See [Azure docs](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-compute-storage) |
| `tier` | PostgreSQL tier | `GeneralPurpose` | `Burstable`, `GeneralPurpose`, `MemoryOptimized` |
| `storageSizeGB` | Storage size in GB | `128` | 32-16384 |
| `backupRetentionDays` | Backup retention | `35` | 7-35 |
| `geoRedundantBackup` | Enable geo-redundant backup | `true` | `true`, `false` |
| `highAvailability` | Enable high availability | `true` | `true`, `false` |
| `highAvailabilityMode` | HA mode | `ZoneRedundant` | `ZoneRedundant`, `SameZone` |

### Feature Toggles
| Parameter | Description | Default |
|-----------|-------------|---------|
| `enableReadReplica` | Deploy read replica | `true` |
| `enableBackupPolicies` | Enable backup policies | `true` |
| `enableMonitoring` | Enable monitoring | `true` |
| `enableAutomation` | Enable automation | `true` |

## Deployment Validation

### 1. Verify PostgreSQL Servers
```bash
# Primary server
az postgres flexible-server show --name <server-name> --resource-group <resource-group>

# Read replica
az postgres flexible-server show --name <replica-name> --resource-group <secondary-resource-group>
```

### 2. Test Connectivity
```bash
# Test primary server
psql "postgresql://pgadmin:password@server.postgres.database.azure.com:5432/postgres"

# Test read replica
psql "postgresql://pgadmin:password@replica.postgres.database.azure.com:5432/postgres"
```

### 3. Validate Backup Configuration
```bash
# Check backup settings
az postgres flexible-server show --name <server-name> --resource-group <resource-group> --query "backup"

# List backup vaults
az dataprotection backup-vault list --resource-group <resource-group>
```

### 4. Verify Monitoring
```bash
# Check Log Analytics workspace
az monitor log-analytics workspace show --workspace-name <workspace-name> --resource-group <resource-group>

# List alert rules
az monitor metrics alert list --resource-group <resource-group>
```

## Disaster Recovery Testing

### 1. Simulate Failover
```bash
# Promote read replica to primary
az postgres flexible-server replica stop --name <replica-name> --resource-group <secondary-resource-group>
```

### 2. Test Backup Restore
```bash
# Create point-in-time restore
az postgres flexible-server restore --name <restored-server> --resource-group <resource-group> --source-server <source-server> --restore-time "2024-01-01T10:00:00Z"
```

### 3. Validate Automation
```bash
# Test automation runbook
az automation runbook start --name "PostgreSQL-DisasterRecovery" --automation-account-name <automation-account> --resource-group <resource-group>
```

## Monitoring and Alerting

### Key Metrics
- **Connection Failures**: Alerts when connection failures exceed threshold
- **Replication Lag**: Monitors read replica lag
- **Backup Failures**: Alerts on backup failures
- **Storage Usage**: Monitors storage consumption
- **CPU/Memory**: Performance monitoring

### Alert Notifications
- Email notifications to specified addresses
- Integration with Azure Monitor action groups
- Automation runbook triggers for critical alerts

## Cost Optimization

### Development Environment
- Use Burstable tier (`Standard_B2s`)
- Reduce backup retention to 7 days
- Disable geo-redundant backups
- Turn off high availability

### Production Environment
- Right-size compute based on workload
- Use reserved instances for predictable workloads
- Monitor storage growth and optimize
- Review backup retention policies

## Security Considerations

### Network Security
- Firewall rules configured for Azure services
- Private endpoints can be added for enhanced security
- Network isolation through VNet integration

### Data Protection
- Encryption at rest and in transit
- Geo-redundant backup for disaster recovery
- Soft delete enabled on backup vaults
- Secure credential management through Azure Automation

### Access Control
- Azure AD integration available
- Role-based access control (RBAC)
- Managed identities for service authentication
- Audit logging through Azure Monitor

## Troubleshooting

### Common Issues
1. **Deployment Failures**
   - Check Azure resource quotas
   - Verify region availability
   - Review template parameter validation

2. **Connectivity Issues**
   - Check firewall rules
   - Verify network security groups
   - Test DNS resolution

3. **Backup Failures**
   - Check backup vault permissions
   - Verify storage account access
   - Review backup policy configuration

4. **Replication Lag**
   - Monitor network latency between regions
   - Check resource utilization
   - Review replication settings

### Debug Commands
```bash
# Check deployment status
az deployment group list --resource-group <resource-group>

# View deployment logs
az deployment group show --name <deployment-name> --resource-group <resource-group>

# Check resource health
az resource list --resource-group <resource-group> --query "[].{Name:name,Type:type,Location:location,Status:properties.provisioningState}"
```

## Cleanup

### Using PowerShell Script
```powershell
# Preview what will be deleted
.\cleanup.ps1 -SubscriptionId "your-subscription-id" -ResourceGroupName "rg-postgres-dr" -WhatIf

# Delete all resources
.\cleanup.ps1 -SubscriptionId "your-subscription-id" -ResourceGroupName "rg-postgres-dr"
```

### Using Azure CLI
```bash
# Delete secondary resource group first
az group delete --name rg-postgres-dr-secondary --yes --no-wait

# Delete primary resource group
az group delete --name rg-postgres-dr --yes --no-wait
```

## Support and Documentation

### Azure Documentation
- [Azure Database for PostgreSQL Flexible Server](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/)
- [Azure Backup](https://docs.microsoft.com/en-us/azure/backup/)
- [Azure Monitor](https://docs.microsoft.com/en-us/azure/azure-monitor/)
- [Azure Automation](https://docs.microsoft.com/en-us/azure/automation/)

### Best Practices
- [PostgreSQL High Availability](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-high-availability)
- [Backup and Restore](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-backup-restore)
- [Monitoring](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-monitoring)

## License

This template is provided under the MIT License. See the LICENSE file for details.

## Contributing

Please read the contributing guidelines before submitting changes or issues.