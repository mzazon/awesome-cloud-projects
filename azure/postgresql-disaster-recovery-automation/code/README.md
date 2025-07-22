# Infrastructure as Code for PostgreSQL Disaster Recovery Automation with Flexible Server and Backup Services

This directory contains Infrastructure as Code (IaC) implementations for the recipe "PostgreSQL Disaster Recovery Automation with Flexible Server and Backup Services".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.53.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Database resources (PostgreSQL Flexible Server)
  - Backup and recovery resources (Azure Backup, Recovery Services Vault)
  - Monitoring resources (Azure Monitor, Log Analytics)
  - Storage resources (Azure Storage accounts)
  - Automation resources (Azure Automation accounts)
- PowerShell 7.0+ (for Terraform Azure provider)
- Terraform 1.5+ (for Terraform implementation)
- Basic understanding of PostgreSQL administration and backup concepts
- Estimated cost: $150-300/month for production workloads (varies by region and retention)

> **Note**: This solution requires Premium or General Purpose service tiers for Azure Database for PostgreSQL Flexible Server to enable geo-redundant backups and read replicas.

## Architecture Overview

The solution deploys:
- **Primary Region**: PostgreSQL Flexible Server with high availability, monitoring, and backup infrastructure
- **Secondary Region**: Read replica for disaster recovery
- **Backup & Recovery**: Azure Backup vaults with long-term retention and geo-redundant storage
- **Monitoring**: Azure Monitor, Log Analytics, and alert rules for proactive monitoring
- **Automation**: Azure Automation account with disaster recovery runbooks

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Set deployment parameters
export LOCATION="East US"
export SECONDARY_LOCATION="West US 2"
export RESOURCE_GROUP="rg-postgres-dr-demo"
export DEPLOYMENT_NAME="postgres-dr-deployment"

# Create resource group
az group create --name ${RESOURCE_GROUP} --location "${LOCATION}"

# Deploy infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file main.bicep \
    --parameters location="${LOCATION}" \
                 secondaryLocation="${SECONDARY_LOCATION}" \
                 environmentName="production" \
                 administratorLogin="pgadmin" \
                 administratorLoginPassword="SecurePassword123!" \
    --name ${DEPLOYMENT_NAME}

# Get deployment outputs
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DEPLOYMENT_NAME} \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << 'EOF'
location = "East US"
secondary_location = "West US 2"
resource_group_name = "rg-postgres-dr-demo"
environment_name = "production"
administrator_login = "pgadmin"
administrator_login_password = "SecurePassword123!"
alert_email = "disaster-recovery@company.com"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export LOCATION="East US"
export SECONDARY_LOCATION="West US 2"
export RESOURCE_GROUP="rg-postgres-dr-demo"
export PG_ADMIN_USER="pgadmin"
export PG_ADMIN_PASSWORD="SecurePassword123!"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
./scripts/verify.sh
```

## Configuration Parameters

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Primary Azure region | East US | Yes |
| `secondaryLocation` | Secondary region for DR | West US 2 | Yes |
| `environmentName` | Environment designation | production | Yes |
| `administratorLogin` | PostgreSQL admin username | pgadmin | Yes |
| `administratorLoginPassword` | PostgreSQL admin password | - | Yes |
| `databaseSkuName` | PostgreSQL server SKU | Standard_D4s_v3 | No |
| `databaseTier` | PostgreSQL server tier | GeneralPurpose | No |
| `backupRetentionDays` | Backup retention period | 35 | No |
| `alertEmail` | Email for disaster recovery alerts | - | Yes |

### Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `location` | Primary Azure region | string | "East US" |
| `secondary_location` | Secondary region for DR | string | "West US 2" |
| `resource_group_name` | Resource group name | string | - |
| `environment_name` | Environment designation | string | "production" |
| `administrator_login` | PostgreSQL admin username | string | "pgadmin" |
| `administrator_login_password` | PostgreSQL admin password | string | - |
| `database_sku_name` | PostgreSQL server SKU | string | "Standard_D4s_v3" |
| `backup_retention_days` | Backup retention period | number | 35 |
| `alert_email` | Email for disaster recovery alerts | string | - |

## Validation & Testing

After deployment, validate the infrastructure:

```bash
# Check PostgreSQL server status
az postgres flexible-server show \
    --name <server-name> \
    --resource-group ${RESOURCE_GROUP} \
    --output table

# Test read replica connectivity
psql "postgresql://<username>:<password>@<replica-fqdn>:5432/postgres" \
    -c "SELECT version();"

# Verify backup configuration
az postgres flexible-server show \
    --name <server-name> \
    --resource-group ${RESOURCE_GROUP} \
    --query "backup" \
    --output json

# Check alert rules
az monitor metrics alert list \
    --resource-group ${RESOURCE_GROUP} \
    --output table

# Test disaster recovery automation
az automation runbook start \
    --name "PostgreSQL-DisasterRecovery" \
    --automation-account-name <automation-account> \
    --resource-group ${RESOURCE_GROUP}
```

## Monitoring and Alerts

The solution includes comprehensive monitoring:

- **Database Performance**: CPU, memory, storage, and connection metrics
- **Replication Health**: Replica lag and synchronization status
- **Backup Status**: Backup success/failure notifications
- **Disaster Recovery**: Automated recovery workflows and notifications

### Key Metrics Monitored

- Connection failures (threshold: >10 failed connections in 5 minutes)
- Replication lag (threshold: >300 seconds)
- Backup failures (immediate alert)
- Storage utilization (threshold: >80%)
- Database availability (continuous monitoring)

## Disaster Recovery Procedures

### Automatic Failover

The solution includes automated disaster recovery through:
1. Azure Monitor alerts detecting failures
2. Azure Automation runbooks executing recovery procedures
3. Read replica promotion to primary status
4. Application connection string updates

### Manual Failover

For planned maintenance or testing:

```bash
# Promote read replica to primary
az postgres flexible-server replica stop \
    --name <replica-name> \
    --resource-group <secondary-resource-group>

# Update application connection strings
# Point applications to the promoted replica
```

## Cost Optimization

### Resource Scaling

- **Development**: Use Basic tier with smaller compute sizes
- **Production**: Use General Purpose or Memory Optimized tiers
- **Backup Storage**: Optimize retention periods based on compliance needs

### Monitoring Costs

```bash
# Monitor resource costs
az consumption usage list \
    --resource-group ${RESOURCE_GROUP} \
    --output table

# Optimize backup retention
az postgres flexible-server parameter set \
    --name <server-name> \
    --resource-group ${RESOURCE_GROUP} \
    --backup-retention-days 7  # Reduce for non-production
```

## Cleanup

### Using Bicep

```bash
# Delete the deployment
az deployment group delete \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DEPLOYMENT_NAME}

# Delete resource group
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Deployment Failures**:
   - Verify Azure CLI authentication: `az account show`
   - Check resource quotas and limits
   - Ensure proper RBAC permissions

2. **PostgreSQL Connection Issues**:
   - Verify firewall rules configuration
   - Check NSG rules if using VNet integration
   - Validate SSL certificate configuration

3. **Backup Failures**:
   - Check backup vault permissions
   - Verify storage account access
   - Review backup policy configuration

4. **Replication Lag**:
   - Monitor network connectivity between regions
   - Check primary database load
   - Verify replica server capacity

### Debugging Commands

```bash
# Check deployment status
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DEPLOYMENT_NAME} \
    --query properties.provisioningState

# View deployment logs
az deployment operation group list \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DEPLOYMENT_NAME} \
    --query "[?properties.provisioningState=='Failed']"

# Check resource health
az resource list \
    --resource-group ${RESOURCE_GROUP} \
    --output table
```

## Security Considerations

- **Network Security**: Configure VNet integration and private endpoints
- **Authentication**: Use Azure AD authentication where possible
- **Encryption**: Enable encryption at rest and in transit
- **Access Control**: Implement least privilege access principles
- **Monitoring**: Enable audit logging and security monitoring

## Best Practices

1. **Regular Testing**: Perform disaster recovery drills monthly
2. **Documentation**: Keep recovery procedures updated
3. **Automation**: Use Infrastructure as Code for consistency
4. **Monitoring**: Implement comprehensive alerting
5. **Backup Validation**: Regularly test backup restore procedures

## Support and Documentation

- [Azure Database for PostgreSQL Documentation](https://docs.microsoft.com/en-us/azure/postgresql/)
- [Azure Backup Documentation](https://docs.microsoft.com/en-us/azure/backup/)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)
- [Disaster Recovery Best Practices](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-business-continuity)

## Version History

- **v1.0**: Initial implementation with basic disaster recovery
- **v1.1**: Added automated monitoring and alerting
- **v1.2**: Enhanced backup policies and cross-region replication
- **v1.3**: Improved automation workflows and cost optimization

For issues with this infrastructure code, refer to the original recipe documentation or Azure support resources.