# Infrastructure as Code for Multi-Tenant Database Optimization with Elastic Pools and Backup Vault

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Tenant Database Optimization with Elastic Pools and Backup Vault".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with Contributor permissions
- PowerShell 7+ (for some Azure CLI operations)
- Terraform CLI (version 1.0+) - for Terraform deployment
- Bicep CLI - for Bicep deployment
- OpenSSL - for password generation
- Appropriate permissions for creating:
  - Azure SQL Database servers and elastic pools
  - Azure Backup Vaults
  - Azure Cost Management budgets
  - Azure Monitor Log Analytics workspaces
  - Resource groups and associated resources

## Architecture Overview

This infrastructure deploys:
- Azure SQL Database Server with security configuration
- Azure Elastic Database Pool (Standard tier, 200 DTUs)
- Multiple tenant databases within the elastic pool
- Azure Backup Vault with geo-redundant storage
- Backup policies for SQL databases
- Azure Cost Management budgets and alerts
- Azure Monitor Log Analytics workspace
- Sample multi-tenant database schema

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-multitenant-db \
    --template-file main.bicep \
    --parameters \
        location=eastus \
        sqlServerName=sqlserver-mt-$(openssl rand -hex 3) \
        elasticPoolName=elasticpool-saas-$(openssl rand -hex 3) \
        backupVaultName=bv-multitenant-$(openssl rand -hex 3) \
        sqlAdminUsername=sqladmin \
        sqlAdminPassword=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-20)
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan \
    -var="location=eastus" \
    -var="sql_admin_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-20)"

# Apply the configuration
terraform apply \
    -var="location=eastus" \
    -var="sql_admin_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-20)"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
# or you can set environment variables:
export RESOURCE_GROUP="rg-multitenant-db-$(openssl rand -hex 3)"
export LOCATION="eastus"
./scripts/deploy.sh
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | No |
| `sqlServerName` | Name for SQL Database server | Generated | No |
| `elasticPoolName` | Name for elastic database pool | Generated | No |
| `backupVaultName` | Name for backup vault | Generated | No |
| `sqlAdminUsername` | SQL Server admin username | `sqladmin` | No |
| `sqlAdminPassword` | SQL Server admin password | None | Yes |
| `elasticPoolDtu` | DTU allocation for elastic pool | `200` | No |
| `maxDatabaseDtu` | Maximum DTU per database | `50` | No |
| `tenantDatabaseCount` | Number of tenant databases to create | `4` | No |
| `budgetAmount` | Monthly budget amount in USD | `500` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for deployment | `"eastus"` | No |
| `resource_group_name` | Resource group name | Generated | No |
| `sql_server_name` | SQL Database server name | Generated | No |
| `elastic_pool_name` | Elastic database pool name | Generated | No |
| `backup_vault_name` | Backup vault name | Generated | No |
| `sql_admin_username` | SQL Server admin username | `"sqladmin"` | No |
| `sql_admin_password` | SQL Server admin password | None | Yes |
| `elastic_pool_dtu` | DTU allocation for elastic pool | `200` | No |
| `max_database_dtu` | Maximum DTU per database | `50` | No |
| `tenant_database_count` | Number of tenant databases | `4` | No |
| `budget_amount` | Monthly budget amount | `500` | No |

### Environment Variables (for Bash Scripts)

| Variable | Description | Required |
|----------|-------------|----------|
| `RESOURCE_GROUP` | Target resource group name | Yes |
| `LOCATION` | Azure region | Yes |
| `SQL_ADMIN_PASSWORD` | SQL Server admin password | Yes |
| `ELASTIC_POOL_DTU` | Elastic pool DTU capacity | No |
| `TENANT_COUNT` | Number of tenant databases | No |
| `BUDGET_AMOUNT` | Monthly budget limit | No |

## Post-Deployment Verification

After deployment, verify the infrastructure:

```bash
# Check elastic pool status
az sql elastic-pool show \
    --name <elastic-pool-name> \
    --server <sql-server-name> \
    --resource-group <resource-group-name> \
    --output table

# List tenant databases
az sql db list \
    --server <sql-server-name> \
    --resource-group <resource-group-name> \
    --query "[?elasticPoolName=='<elastic-pool-name>'].[name,elasticPoolName]" \
    --output table

# Check backup vault
az dataprotection backup-vault show \
    --name <backup-vault-name> \
    --resource-group <resource-group-name> \
    --output table

# Verify cost budget
az consumption budget list \
    --resource-group <resource-group-name> \
    --output table
```

## Testing Database Connectivity

Test connection to a tenant database:

```bash
# Test sample tenant database connection
az sql db query \
    --server <sql-server-name> \
    --database <tenant-database-name> \
    --auth-type Sql \
    --username sqladmin \
    --password <sql-admin-password> \
    --queries "SELECT GETUTCDATE() as CurrentTime, @@VERSION as SqlVersion"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name <resource-group-name> \
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
    -var="sql_admin_password=<your-password>"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Or manually delete the resource group
az group delete \
    --name $RESOURCE_GROUP \
    --yes \
    --no-wait
```

## Cost Optimization

This infrastructure implements several cost optimization strategies:

1. **Elastic Pool Resource Sharing**: Up to 4 databases share 200 DTUs
2. **Geo-Redundant Backup Storage**: Balances cost with disaster recovery
3. **Automated Cost Monitoring**: $500 monthly budget with 80% alerts
4. **Standard Tier Configuration**: Optimized for SaaS workloads
5. **30-day Log Retention**: Reduces long-term storage costs

### Estimated Monthly Costs

| Component | Estimated Cost (USD) |
|-----------|---------------------|
| Elastic Pool (Standard, 200 DTU) | $200-300 |
| Backup Storage (geo-redundant) | $50-100 |
| Log Analytics Workspace | $20-50 |
| Total | $270-450 |

## Security Features

- SQL Server configured with TLS 1.2 minimum
- Azure Active Directory authentication support
- Firewall rules for Azure services only
- Geo-redundant backup storage
- Automated backup policies
- Cost monitoring and alerts

## Troubleshooting

### Common Issues

1. **SQL Admin Password Requirements**:
   - Must be 8-128 characters
   - Must contain characters from 3 of: uppercase, lowercase, numbers, symbols

2. **Resource Naming Conflicts**:
   - SQL Server names must be globally unique
   - Add random suffix to avoid conflicts

3. **Permission Issues**:
   - Ensure Contributor role on subscription
   - Verify Azure CLI authentication: `az account show`

4. **Cost Budget Creation**:
   - Requires Cost Management permissions
   - May take up to 24 hours to become active

### Debugging Commands

```bash
# Check Azure CLI authentication
az account show

# Verify resource group exists
az group show --name <resource-group-name>

# Check deployment status (Bicep/ARM)
az deployment group list \
    --resource-group <resource-group-name> \
    --output table

# View activity log for errors
az monitor activity-log list \
    --resource-group <resource-group-name> \
    --max-events 50 \
    --output table
```

## Multi-Tenant Best Practices

This implementation follows Azure multi-tenant database best practices:

1. **Database-per-Tenant**: Provides strong isolation
2. **Elastic Pool Sharing**: Optimizes cost through resource sharing
3. **Tenant ID Indexing**: Enables efficient tenant-scoped queries
4. **Centralized Backup**: Consistent disaster recovery across tenants
5. **Cost Monitoring**: Tracks spending per tenant category

## Advanced Configuration

### Scaling the Elastic Pool

```bash
# Scale up the elastic pool
az sql elastic-pool update \
    --name <elastic-pool-name> \
    --server <sql-server-name> \
    --resource-group <resource-group-name> \
    --dtu 400 \
    --database-dtu-max 100
```

### Adding New Tenant Databases

```bash
# Create additional tenant database
az sql db create \
    --name tenant-5-db \
    --server <sql-server-name> \
    --resource-group <resource-group-name> \
    --elastic-pool <elastic-pool-name>
```

### Configuring Backup Policies

```bash
# Create custom backup policy
az dataprotection backup-policy create \
    --name custom-sql-policy \
    --resource-group <resource-group-name> \
    --vault-name <backup-vault-name> \
    --policy @custom-policy.json
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../implementing-cost-optimized-multi-tenant-database-architecture-with-azure-elastic-database-pools-and-azure-backup-vault.md)
2. Review [Azure SQL Database documentation](https://docs.microsoft.com/en-us/azure/azure-sql/database/)
3. Consult [Azure Elastic Pool best practices](https://docs.microsoft.com/en-us/azure/azure-sql/database/elastic-pool-overview)
4. Reference [Azure Backup documentation](https://docs.microsoft.com/en-us/azure/backup/)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update parameter documentation
3. Verify cost estimates remain accurate
4. Test both deployment and cleanup procedures
5. Update this README with any new requirements or procedures