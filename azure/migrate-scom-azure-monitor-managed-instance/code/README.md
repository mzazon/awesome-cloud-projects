# Infrastructure as Code for Migrate On-Premises SCOM to Azure Monitor Managed Instance

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Migrate On-Premises SCOM to Azure Monitor Managed Instance".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts with Azure CLI

## Prerequisites

### Common Requirements
- Azure CLI installed and configured (`az --version`)
- Azure subscription with appropriate permissions
- PowerShell (for on-premises SCOM management pack export)
- Existing System Center Operations Manager 2019 or 2022 deployment
- Network connectivity between on-premises and Azure environments

### Specific Tool Requirements

#### For Bicep
- Azure CLI with Bicep extension installed
- Bicep CLI (`bicep --version`)

#### For Terraform
- Terraform CLI installed (`terraform --version`)
- Azure CLI for authentication

#### For Bash Scripts
- Azure CLI with extensions for SQL and Monitor
- OpenSSL for generating random values

### Permissions Required
- Contributor role on target subscription
- SQL Managed Instance Contributor role
- Network Contributor role
- Key Vault Contributor role
- Monitoring Contributor role

## Cost Considerations

**Estimated Monthly Cost**: $2,000-$5,000 for typical 500 VM deployment

### Main Cost Components:
- **Azure SQL Managed Instance**: $1,500-$3,000/month (8 vCores, 256GB storage)
- **Azure Monitor SCOM Managed Instance**: $500-$1,500/month (based on monitored resources)
- **Virtual Network**: $50-$100/month (data transfer and gateway costs)
- **Log Analytics Workspace**: $200-$500/month (data ingestion and retention)
- **Storage Account**: $20-$50/month (management pack storage)

> **Note**: Costs vary by region and actual usage. Use Azure Pricing Calculator for precise estimates.

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone and navigate to the code directory
cd bicep/

# Review and customize parameters
# Edit bicep/main.bicep to adjust default values as needed

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-scom-migration \
    --template-file main.bicep \
    --parameters location="East US" \
    --parameters environmentName="prod" \
    --parameters adminUsername="scomadmin" \
    --parameters adminPassword="P@ssw0rd123!"

# Monitor deployment progress
az deployment group show \
    --resource-group rg-scom-migration \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan \
    -var="location=East US" \
    -var="environment_name=prod" \
    -var="admin_username=scomadmin" \
    -var="admin_password=P@ssw0rd123!"

# Apply the configuration
terraform apply \
    -var="location=East US" \
    -var="environment_name=prod" \
    -var="admin_username=scomadmin" \
    -var="admin_password=P@ssw0rd123!"

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export LOCATION="East US"
export ADMIN_USERNAME="scomadmin"
export ADMIN_PASSWORD="P@ssw0rd123!"

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment logs
tail -f deployment.log
```

## Deployment Process

### Phase 1: Foundation Infrastructure
1. **Resource Group**: Creates main resource group for all resources
2. **Virtual Network**: Configures VNet with dedicated subnets for SCOM MI and SQL MI
3. **Network Security Groups**: Implements security rules for proper communication
4. **Key Vault**: Stores connection strings and secrets securely

### Phase 2: Database Layer
1. **Azure SQL Managed Instance**: Deploys SQL MI for SCOM backend databases
2. **Database Configuration**: Sets up Operations and Data Warehouse databases
3. **Connectivity**: Configures public endpoint and firewall rules

### Phase 3: SCOM Infrastructure
1. **Managed Identity**: Creates identity for secure service-to-service authentication
2. **SCOM Managed Instance**: Deploys the core SCOM MI service
3. **Monitor Integration**: Configures Log Analytics workspace integration
4. **Storage Account**: Sets up temporary storage for management pack migration

### Phase 4: Configuration
1. **Network Security**: Applies security groups and firewall rules
2. **Monitoring Setup**: Configures Azure Monitor action groups
3. **Access Control**: Implements RBAC for secure access

## Post-Deployment Configuration

After infrastructure deployment, complete these manual steps:

### 1. Management Pack Migration
```bash
# Export management packs from on-premises SCOM
# Run on your SCOM management server
Get-SCOMManagementPack | Where-Object { $_.Sealed -eq $false } | \
    Export-SCOMManagementPack -Path "C:\Temp\Unsealed_MPs"

# Upload to Azure Storage (container created during deployment)
az storage blob upload-batch \
    --source "C:\Temp\Unsealed_MPs" \
    --destination management-packs \
    --account-name <storage-account-name>
```

### 2. Agent Configuration
```powershell
# Configure multi-homing for gradual migration
# Run on pilot agent machines
$ScomMIServer = "<scom-mi-name>.<location>.cloudapp.azure.com"
$Agent = Get-WmiObject -Class "Microsoft.ManagementInfrastructure.Agent" `
    -Namespace "root\Microsoft\SystemCenter\Agent"
$Agent.AddManagementGroup("SCOM_MI_MG", $ScomMIServer, 5723)
```

### 3. Validation Steps
```bash
# Verify SCOM MI status
az monitor scom-managed-instance show \
    --name <scom-mi-name> \
    --resource-group rg-scom-migration

# Test connectivity
Test-NetConnection -ComputerName "<scom-mi-fqdn>" -Port 5723
```

## Configuration Options

### Customizable Parameters

| Parameter | Description | Default Value | Example |
|-----------|-------------|---------------|---------|
| `location` | Azure region | "East US" | "West US 2" |
| `environment_name` | Environment suffix | "prod" | "dev", "staging" |
| `admin_username` | SQL MI admin username | "scomadmin" | "dbadmin" |
| `admin_password` | SQL MI admin password | (required) | "SecurePass123!" |
| `sql_mi_capacity` | SQL MI vCore capacity | 8 | 4, 16, 32 |
| `sql_mi_storage` | SQL MI storage size | "256GB" | "128GB", "512GB" |
| `log_retention_days` | Log Analytics retention | 30 | 7, 90, 365 |

### Network Configuration

- **Virtual Network**: 10.0.0.0/16 address space
- **SCOM MI Subnet**: 10.0.1.0/24 (supports ~250 instances)
- **SQL MI Subnet**: 10.0.2.0/27 (minimum required for SQL MI)
- **NSG Rules**: Configured for SCOM agent communication (port 5723)

### Security Features

- **Managed Identity**: For service-to-service authentication
- **Key Vault**: Secure storage for connection strings and secrets
- **Network Security Groups**: Restrictive rules for network access
- **SQL MI Public Endpoint**: Enabled with firewall rules
- **RBAC**: Least privilege access patterns

## Monitoring and Troubleshooting

### Deployment Monitoring

```bash
# Monitor deployment progress (Bicep)
az deployment group show \
    --resource-group rg-scom-migration \
    --name main \
    --query properties.provisioningState

# Monitor deployment progress (Terraform)
terraform show | grep -A 10 "provisioning_state"

# View deployment logs
az monitor activity-log list \
    --resource-group rg-scom-migration \
    --start-time "2025-01-01T00:00:00Z"
```

### Common Issues and Solutions

1. **SQL MI Deployment Timeout**
   - SQL MI deployment can take 4-6 hours
   - Monitor progress in Azure portal
   - Check subnet configuration and IP address availability

2. **Network Connectivity Issues**
   - Verify NSG rules allow required ports
   - Check route table configurations
   - Validate DNS resolution

3. **SCOM MI Creation Failures**
   - Ensure SQL MI is fully provisioned first
   - Verify managed identity permissions
   - Check Key Vault access policies

## Cleanup

### Using Bicep
```bash
# Delete the resource group and all resources
az group delete \
    --name rg-scom-migration \
    --yes \
    --no-wait

# Monitor deletion progress
az group show \
    --name rg-scom-migration \
    --query properties.provisioningState
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
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
az group show --name rg-scom-migration --query properties.provisioningState
```

### Manual Cleanup Steps

1. **Remove Agent Multi-homing**:
   ```powershell
   # Remove SCOM MI management group from agents
   $Agent = Get-WmiObject -Class "Microsoft.ManagementInfrastructure.Agent" `
       -Namespace "root\Microsoft\SystemCenter\Agent"
   $Agent.RemoveManagementGroup("SCOM_MI_MG")
   ```

2. **Clear DNS Cache**:
   ```bash
   # Clear local DNS cache after resource deletion
   sudo dscacheutil -flushcache  # macOS
   ipconfig /flushdns             # Windows
   ```

## Migration Strategy

### Recommended Approach

1. **Assessment Phase** (Week 1-2):
   - Inventory existing SCOM infrastructure
   - Export management packs and configurations
   - Plan network connectivity requirements

2. **Pilot Deployment** (Week 3-4):
   - Deploy SCOM MI infrastructure
   - Import core management packs
   - Configure pilot agent group for multi-homing

3. **Validation Phase** (Week 5-6):
   - Verify monitoring data collection
   - Test alerting and notification workflows
   - Validate performance and functionality

4. **Production Migration** (Week 7-8):
   - Migrate remaining agent groups
   - Implement monitoring dashboards
   - Decommission on-premises infrastructure

### Rollback Plan

If issues occur during migration:

1. **Immediate**: Revert agents to on-premises SCOM only
2. **Short-term**: Maintain dual monitoring during issue resolution
3. **Long-term**: Plan infrastructure modifications and re-attempt migration

## Security Considerations

- **Network Isolation**: Use dedicated subnets with NSG protection
- **Identity Management**: Implement managed identities for service authentication
- **Secret Management**: Store sensitive configuration in Key Vault
- **Access Control**: Apply least privilege RBAC permissions
- **Monitoring**: Enable Azure Monitor for security event tracking

## Performance Optimization

### SQL MI Optimization
- **Compute**: Start with 8 vCores and scale based on monitoring data
- **Storage**: Use General Purpose tier for cost-effectiveness
- **Backup**: Configure automated backups with appropriate retention

### SCOM MI Optimization
- **Scaling**: Monitor resource utilization and adjust capacity
- **Network**: Optimize agent communication patterns
- **Storage**: Implement lifecycle policies for log data

## Support and Documentation

### Microsoft Resources
- [Azure Monitor SCOM Managed Instance Documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/scom-manage-instance/)
- [Migration Accelerator Tools](https://www.microsoft.com/en-my/download/details.aspx?id=105722)
- [Azure SQL Managed Instance Documentation](https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/)

### Community Resources
- [System Center TechCommunity](https://techcommunity.microsoft.com/t5/system-center-blog/bg-p/SystemCenterBlog)
- [Azure Monitor Community](https://techcommunity.microsoft.com/t5/azure-monitor/bg-p/AzureMonitorBlog)

### Support Channels
- **Azure Support**: For infrastructure and service issues
- **Microsoft Premier Support**: For complex migration scenarios
- **Community Forums**: For general questions and best practices

## Contributing

To improve this infrastructure code:

1. Follow Azure and Terraform best practices
2. Test changes in non-production environments
3. Update documentation for any parameter changes
4. Validate security configurations
5. Consider cost optimization opportunities

## License

This infrastructure code is provided as-is for educational and implementation purposes. Refer to your Azure subscription terms for service usage rights.