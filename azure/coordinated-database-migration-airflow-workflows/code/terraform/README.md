# Terraform Infrastructure: Intelligent Database Migration Orchestration

This Terraform configuration deploys a comprehensive intelligent database migration orchestration solution using Azure Data Factory with Workflow Orchestration Manager, Azure Database Migration Service, and comprehensive monitoring infrastructure.

## Architecture Overview

The solution deploys:
- **Azure Data Factory** with Workflow Orchestration Manager (Apache Airflow)
- **Database Migration Service** for reliable database migrations
- **Storage Account** for Airflow DAGs and migration artifacts
- **Log Analytics Workspace** for centralized logging and monitoring
- **Azure Monitor** with custom alert rules and action groups
- **Application Insights** for enhanced telemetry
- **RBAC assignments** for secure service-to-service authentication
- **Optional private endpoints** for enhanced network security

## Prerequisites

### Required Tools
- [Terraform](https://www.terraform.io/downloads.html) >= 1.5.0
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) >= 2.50.0
- An active Azure subscription with appropriate permissions

### Required Permissions
Your Azure account must have the following permissions:
- `Contributor` role on the target resource group
- `User Access Administrator` role for RBAC assignments
- Ability to create service principals and assign roles

### Network Prerequisites (for private endpoints)
If enabling private endpoints (`enable_private_endpoints = true`):
- Existing Virtual Network with appropriate subnets
- DNS configuration for private endpoint resolution
- Network connectivity from on-premises to Azure VNet

## Quick Start

### 1. Authentication Setup

```bash
# Login to Azure CLI
az login

# Set your subscription (if you have multiple)
az account set --subscription "your-subscription-id"

# Verify current context
az account show
```

### 2. Create Resource Group

```bash
# Create resource group for the migration infrastructure
az group create \
    --name "rg-db-migration-orchestration" \
    --location "East US" \
    --tags purpose=database-migration environment=dev
```

### 3. Configure Terraform Variables

```bash
# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit variables file with your specific values
nano terraform.tfvars
```

### 4. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Deploy infrastructure
terraform apply
```

## Configuration Guide

### Basic Configuration

Minimum required variables in `terraform.tfvars`:

```hcl
# Resource group (must exist)
resource_group_name = "rg-db-migration-orchestration"

# Basic settings
location    = "East US"
environment = "dev"

# Notification email for alerts
alert_notification_email = "your-email@company.com"
```

### Advanced Configuration

#### Enable Git Integration for Data Factory

```hcl
enable_git_integration = true
git_configuration = {
  type                = "FactoryGitHubConfiguration"
  account_name        = "your-github-org"
  repository_name     = "your-data-factory-repo"
  collaboration_branch = "main"
  root_folder         = "/data-factory"
}
```

#### Enable Private Endpoints

```hcl
enable_private_endpoints = true
virtual_network_id       = "/subscriptions/sub-id/resourceGroups/rg-name/providers/Microsoft.Network/virtualNetworks/vnet-name"
private_endpoint_subnet_id = "/subscriptions/sub-id/resourceGroups/rg-name/providers/Microsoft.Network/virtualNetworks/vnet-name/subnets/subnet-name"
```

#### Production Environment Settings

```hcl
environment = "prod"
dms_sku     = "Standard_4vCores"

# Enhanced security and reliability
enable_private_endpoints    = true
storage_replication_type   = "GRS"
log_analytics_retention_days = 90

# Production monitoring
log_analytics_daily_quota_gb = 50
enable_monitoring           = true
```

## Post-Deployment Configuration

### 1. Integration Runtime Setup

After deployment, set up the self-hosted integration runtime:

```bash
# Get the authentication key from Terraform output
terraform output -raw integration_runtime_auth_key_1

# Download and install Integration Runtime on your on-premises server
# https://www.microsoft.com/en-us/download/details.aspx?id=39717

# Register using the authentication key from above
```

### 2. Upload Airflow DAGs

```bash
# Get storage account details
STORAGE_ACCOUNT=$(terraform output -raw storage_account_name)
STORAGE_KEY=$(terraform output -raw storage_account_primary_access_key)

# Upload your Airflow DAG files
az storage blob upload \
    --container-name "airflow-dags" \
    --file "your-migration-dag.py" \
    --name "migration_orchestration_dag.py" \
    --account-name $STORAGE_ACCOUNT \
    --account-key $STORAGE_KEY
```

### 3. Configure Workflow Orchestration Manager

1. Open Data Factory Studio using the URL from Terraform output
2. Navigate to "Workflow Orchestration Manager"
3. Complete the Airflow environment setup
4. Configure environment variables and packages

### 4. Set Up Database Connections

```bash
# Create migration projects in DMS
DMS_NAME=$(terraform output -raw database_migration_service_name)
RESOURCE_GROUP=$(terraform output -raw resource_group_name)

az dms project create \
    --service-name $DMS_NAME \
    --resource-group $RESOURCE_GROUP \
    --project-name "sql-to-azure-migration" \
    --source-platform "SQL" \
    --target-platform "AzureSqlDatabase"
```

## Monitoring and Operations

### Access Monitoring Dashboards

```bash
# Get monitoring URLs from Terraform outputs
terraform output monitoring_dashboard_url
terraform output data_factory_studio_url
```

### View Logs and Metrics

```bash
# Query Log Analytics workspace
LOG_WORKSPACE_ID=$(terraform output -raw log_analytics_customer_id)

# Use Azure CLI to query logs
az monitor log-analytics query \
    --workspace $LOG_WORKSPACE_ID \
    --analytics-query "AzureDiagnostics | where ResourceProvider == 'MICROSOFT.DATAFACTORY' | take 100"
```

### Alert Configuration

The deployment includes predefined alert rules:
- **Migration Failure Alert**: Triggers on migration errors
- **Long Migration Alert**: Triggers when migrations exceed 1 hour
- **High CPU Alert**: Triggers when DMS CPU usage > 80%

## Cost Management

### Estimated Costs

| Component | Estimated Monthly Cost (USD) |
|-----------|------------------------------|
| Data Factory | $50-100 |
| Database Migration Service | $100-200 |
| Storage Account | $10-30 |
| Log Analytics | $20-50 |
| Monitoring | $10-20 |
| **Total** | **$190-400** |

*Costs vary by region, usage, and data volume*

### Cost Optimization

```bash
# Monitor costs with Azure CLI
az consumption usage list \
    --start-date "2025-01-01" \
    --end-date "2025-01-31" \
    --resource-group $RESOURCE_GROUP

# Set up budget alerts
az consumption budget create \
    --amount 500 \
    --category "Cost" \
    --start-date "2025-01-01" \
    --end-date "2025-12-31" \
    --resource-group $RESOURCE_GROUP \
    --budget-name "migration-budget"
```

## Security Best Practices

### Network Security

1. **Enable Private Endpoints**: For production workloads
   ```hcl
   enable_private_endpoints = true
   ```

2. **Network Security Groups**: Configure NSGs for subnets
3. **Virtual Network Integration**: Use managed VNet for Data Factory

### Identity and Access

1. **Managed Identities**: Used for service-to-service authentication
2. **RBAC**: Least privilege access assignments
3. **Key Vault**: Store sensitive connection strings (recommended)

### Data Protection

1. **Encryption**: TLS 1.2 minimum, storage encryption enabled
2. **Access Control**: Private storage containers
3. **Audit Logging**: Comprehensive diagnostic settings

## Troubleshooting

### Common Issues

#### Integration Runtime Connection Issues

```bash
# Check IR status in Data Factory
az datafactory integration-runtime show \
    --factory-name $(terraform output -raw data_factory_name) \
    --resource-group $(terraform output -raw resource_group_name) \
    --name "OnPremisesIR"
```

#### Storage Access Issues

```bash
# Verify RBAC assignments
az role assignment list \
    --assignee $(terraform output -raw data_factory_principal_id) \
    --scope $(terraform output -raw storage_account_id)
```

#### DMS Connectivity Issues

```bash
# Check DMS service status
az dms show \
    --name $(terraform output -raw database_migration_service_name) \
    --resource-group $(terraform output -raw resource_group_name)
```

### Log Analysis

```bash
# View Data Factory logs
az monitor log-analytics query \
    --workspace $(terraform output -raw log_analytics_customer_id) \
    --analytics-query "AzureDiagnostics | where ResourceProvider == 'MICROSOFT.DATAFACTORY' | order by TimeGenerated desc | take 50"

# View DMS logs  
az monitor log-analytics query \
    --workspace $(terraform output -raw log_analytics_customer_id) \
    --analytics-query "AzureDiagnostics | where ResourceProvider == 'MICROSOFT.DATAMIGRATION' | order by TimeGenerated desc | take 50"
```

## Cleanup

### Destroy Infrastructure

```bash
# Destroy all resources (use with caution)
terraform destroy

# Verify cleanup
az group show --name $(terraform output -raw resource_group_name)
```

### Selective Cleanup

```bash
# Remove specific resources while keeping others
terraform destroy -target=azurerm_database_migration_service.main
```

## Support and Contributing

### Documentation Links

- [Azure Data Factory Documentation](https://docs.microsoft.com/en-us/azure/data-factory/)
- [Database Migration Service Documentation](https://docs.microsoft.com/en-us/azure/dms/)
- [Apache Airflow Documentation](https://airflow.apache.org/docs/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

### Getting Help

1. Check Terraform output messages for deployment guidance
2. Review Azure Activity Log for resource creation issues  
3. Use Azure Support for service-specific problems
4. Consult the original recipe documentation for implementation details

## License

This Terraform configuration is part of the Azure Recipe collection and follows the same licensing terms.