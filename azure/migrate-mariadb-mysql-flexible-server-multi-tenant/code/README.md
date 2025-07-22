# Infrastructure as Code for Migrate Multi-tenant MariaDB Workloads to MySQL Flexible Server

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Migrate Multi-tenant MariaDB Workloads to MySQL Flexible Server".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts for manual orchestration

## Prerequisites

### General Requirements
- Azure CLI v2.60.0 or later installed and configured
- Azure subscription with appropriate permissions for database services
- MySQL client tools (mysql, mysqldump, mydumper, myloader)
- Network connectivity between source and target environments
- Valid Azure subscription with Owner or Contributor access

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension installed
- PowerShell 7.0+ or Bash shell

#### For Terraform
- Terraform v1.0+ installed
- Azure CLI authenticated or service principal configured
- terraform-docs (optional, for documentation generation)

#### For Bash Scripts
- Bash 4.0+ or compatible shell
- jq for JSON processing
- OpenSSL for generating random values

## Architecture Overview

This IaC deployment creates:
- Azure Database for MySQL - Flexible Server with zone-redundant high availability
- Read replicas for near-zero downtime migration
- Log Analytics workspace for centralized monitoring
- Application Insights for performance tracking
- Storage account for migration artifacts
- Automated monitoring alerts and diagnostic settings
- Network security configurations and firewall rules

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to the bicep directory
cd bicep/

# Login to Azure (if not already authenticated)
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-mariadb-migration" \
    --template-file main.bicep \
    --parameters sourceMariaDBServer="your-source-server" \
                 sourceMariaDBAdmin="mariadbadmin" \
                 targetMySQLAdmin="mysqladmin" \
                 location="eastus"

# Monitor deployment progress
az deployment group show \
    --resource-group "rg-mariadb-migration" \
    --name "main"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan \
    -var="source_mariadb_server=your-source-server" \
    -var="source_mariadb_admin=mariadbadmin" \
    -var="target_mysql_admin=mysqladmin" \
    -var="location=eastus"

# Apply the configuration
terraform apply \
    -var="source_mariadb_server=your-source-server" \
    -var="source_mariadb_admin=mariadbadmin" \
    -var="target_mysql_admin=mysqladmin" \
    -var="location=eastus"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set required environment variables
export SOURCE_MARIADB_SERVER="your-source-server"
export SOURCE_MARIADB_ADMIN="mariadbadmin"
export TARGET_MYSQL_ADMIN="mysqladmin"
export LOCATION="eastus"
export RESOURCE_GROUP="rg-mariadb-migration"

# Deploy infrastructure
./deploy.sh

# Monitor deployment (check Azure portal or use Azure CLI)
az resource list --resource-group $RESOURCE_GROUP --output table
```

## Configuration Parameters

### Required Parameters
- `sourceMariaDBServer`: Name of the existing MariaDB server to migrate from
- `sourceMariaDBAdmin`: Administrator username for source MariaDB server
- `targetMySQLAdmin`: Administrator username for target MySQL Flexible Server
- `location`: Azure region for deployment (e.g., "eastus", "westus2")

### Optional Parameters
- `resourceGroupName`: Name of the resource group (default: "rg-mariadb-migration")
- `targetMySQLPassword`: Password for MySQL admin (auto-generated if not provided)
- `mysqlSkuName`: MySQL server SKU (default: "Standard_D2ds_v4")
- `mysqlTier`: MySQL server tier (default: "GeneralPurpose")
- `mysqlVersion`: MySQL version (default: "5.7")
- `storageSize`: Storage size in GB (default: 128)
- `backupRetention`: Backup retention in days (default: 35)
- `enableHighAvailability`: Enable zone-redundant HA (default: true)

## Post-Deployment Steps

After infrastructure deployment, complete the migration process:

1. **Configure Source MariaDB for Replication**:
   ```bash
   # Connect to source MariaDB and enable binary logging
   mysql -h your-source-server.mariadb.database.azure.com \
         -u mariadbadmin -p
   
   # Create replication user
   CREATE USER 'replication_user'@'%' IDENTIFIED BY 'ReplicationPass123!';
   GRANT REPLICATION SLAVE ON *.* TO 'replication_user'@'%';
   FLUSH PRIVILEGES;
   ```

2. **Perform Data Migration**:
   ```bash
   # Export data using MyDumper
   mydumper --host=source-server.mariadb.database.azure.com \
            --user=mariadbadmin \
            --password=your-password \
            --outputdir=./migration-data \
            --compress --single-transaction
   
   # Import data using MyLoader
   myloader --host=target-server.mysql.database.azure.com \
            --user=mysqladmin \
            --password=your-password \
            --directory=./migration-data
   ```

3. **Update Application Connections**:
   - Update connection strings to point to new MySQL Flexible Server
   - Test application connectivity and performance
   - Monitor metrics through Application Insights

## Monitoring and Alerts

The deployment includes automated monitoring for:
- **CPU Usage**: Alerts when CPU > 80% for 5 minutes
- **Connection Count**: Alerts when active connections > 800
- **Storage Usage**: Alerts when storage > 85%
- **Slow Query Monitoring**: Enabled with 2-second threshold

Access monitoring through:
- Azure Monitor dashboard
- Application Insights performance metrics
- Log Analytics workspace queries

## Security Features

- **SSL/TLS Encryption**: Required for all connections
- **Firewall Rules**: Configured for secure access
- **Zone-Redundant HA**: 99.99% availability SLA
- **Automated Backups**: 35-day retention with point-in-time recovery
- **Diagnostic Logging**: Comprehensive audit and slow query logs

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete --resource-group "rg-mariadb-migration" --yes --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy \
    -var="source_mariadb_server=your-source-server" \
    -var="source_mariadb_admin=mariadbadmin" \
    -var="target_mysql_admin=mysqladmin" \
    -var="location=eastus"
```

### Using Bash Scripts
```bash
cd scripts/
./destroy.sh
```

## Cost Optimization

To minimize costs during migration:
- Use burstable compute tiers for development/testing
- Scale down during non-peak hours
- Remove read replicas after migration completion
- Delete source MariaDB server after successful migration validation

Estimated costs:
- MySQL Flexible Server (Standard_D2ds_v4): ~$120-150/month
- Storage (128 GB): ~$15-20/month
- Backup storage: ~$5-10/month
- Log Analytics: ~$2-5/month (based on ingestion)

## Troubleshooting

### Common Issues

1. **Authentication Failures**:
   - Verify Azure CLI authentication: `az account show`
   - Check resource group permissions
   - Validate subscription limits

2. **Network Connectivity**:
   - Review firewall rules
   - Check virtual network configurations
   - Verify DNS resolution

3. **Migration Performance**:
   - Monitor CPU and memory usage during migration
   - Adjust connection limits and timeout values
   - Use parallel processing for large datasets

4. **Data Integrity**:
   - Compare row counts between source and target
   - Validate foreign key constraints
   - Test application functionality

### Useful Commands

```bash
# Check deployment status
az deployment group show --resource-group "rg-mariadb-migration" --name "main"

# View MySQL server status
az mysql flexible-server show --name "mysql-target-server" --resource-group "rg-mariadb-migration"

# Monitor metrics
az monitor metrics list \
    --resource "/subscriptions/{subscription}/resourceGroups/rg-mariadb-migration/providers/Microsoft.DBforMySQL/flexibleServers/mysql-target-server" \
    --metric cpu_percent,memory_percent,active_connections

# View logs
az monitor log-analytics query \
    --workspace "migration-logs-workspace" \
    --analytics-query "AzureDiagnostics | where ResourceProvider == 'MICROSOFT.DBFORMYSQL'"
```

## Support and Documentation

- [Azure Database for MariaDB Migration Guide](https://learn.microsoft.com/en-us/azure/mariadb/migrate/whats-happening-to-mariadb)
- [MySQL Flexible Server Documentation](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/)
- [Azure Database Migration Best Practices](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/concept-performance-best-practices)
- [Bicep Language Reference](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or Azure support channels.

## Contributing

When modifying this IaC:
1. Test changes in a development environment
2. Validate syntax using provider-specific tools
3. Update documentation accordingly
4. Follow Azure naming conventions and tagging standards
5. Ensure security best practices are maintained