# Infrastructure as Code for Coordinated Database Migration with Airflow Workflows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Coordinated Database Migration with Airflow Workflows".

## Available Implementations

- **Bicep**: Azure native infrastructure as code
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Azure Data Factory
  - Azure Database Migration Service
  - Azure Monitor and Log Analytics
  - Azure Storage
  - Resource Group management
- For Terraform: Terraform v1.0+ installed
- On-premises SQL Server instances with network connectivity to Azure
- Understanding of Apache Airflow DAG concepts and Python programming

## Quick Start

### Using Bicep

```bash
# Clone or download the Bicep template
cd bicep/

# Review and customize parameters
cp parameters.json.example parameters.json
# Edit parameters.json with your specific values

# Deploy the infrastructure
az deployment group create \
    --resource-group your-resource-group \
    --template-file main.bicep \
    --parameters @parameters.json

# Verify deployment
az deployment group show \
    --resource-group your-resource-group \
    --name main \
    --output table
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply

# Verify resources
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Review and customize deployment variables
# Edit the variables section at the top of deploy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment status
az group show --name rg-db-migration-orchestration --output table
```

## Infrastructure Components

This IaC deployment creates the following Azure resources:

### Core Migration Services
- **Azure Data Factory**: Workflow orchestration platform with managed Apache Airflow
- **Database Migration Service**: Managed database migration service
- **Self-hosted Integration Runtime**: Secure connectivity to on-premises systems

### Storage and Configuration
- **Azure Storage Account**: Storage for Airflow DAGs and migration artifacts
- **Storage Container**: Dedicated container for Airflow workflow definitions

### Monitoring and Alerting
- **Log Analytics Workspace**: Centralized logging and monitoring
- **Action Group**: Notification system for migration alerts
- **Metric Alert Rules**: Automated monitoring for migration failures and performance issues
- **Diagnostic Settings**: Comprehensive logging configuration for all services

### Security and Networking
- **Managed Virtual Network**: Secure network isolation for Data Factory
- **Private Endpoints**: Secure connectivity between services
- **Role-based Access Control**: Least privilege security model

## Configuration Parameters

### Bicep Parameters (parameters.json)

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "resourcePrefix": {
      "value": "dbmig"
    },
    "location": {
      "value": "eastus"
    },
    "environment": {
      "value": "demo"
    },
    "dmsSkuName": {
      "value": "Standard_4vCores"
    },
    "storageAccountSku": {
      "value": "Standard_LRS"
    },
    "logAnalyticsSku": {
      "value": "PerGB2018"
    }
  }
}
```

### Terraform Variables (terraform.tfvars)

```hcl
# Resource configuration
resource_group_name = "rg-db-migration-orchestration"
location           = "East US"
resource_prefix    = "dbmig"
environment        = "demo"

# Database Migration Service configuration
dms_sku_name = "Standard_4vCores"

# Storage configuration
storage_account_sku = "Standard_LRS"

# Monitoring configuration
log_analytics_sku = "PerGB2018"

# Notification configuration
notification_email = "admin@company.com"

# Tags
common_tags = {
  purpose     = "database-migration"
  environment = "demo"
  managed_by  = "terraform"
}
```

## Post-Deployment Configuration

After deploying the infrastructure, complete these manual configuration steps:

### 1. Configure Workflow Orchestration Manager

```bash
# The Workflow Orchestration Manager must be configured through Azure portal
# Navigate to your Data Factory instance and enable Workflow Orchestration Manager
# Use these settings:
# - Airflow Version: 2.6.3
# - Node Size: Standard_D2s_v3
# - Auto-scaling: Enabled (1-3 nodes)
```

### 2. Install Self-hosted Integration Runtime

```bash
# Download and install the Integration Runtime on your on-premises server
# Use the authentication key from the deployment outputs
# Register the runtime with your Data Factory instance
```

### 3. Upload Airflow DAGs

```bash
# Upload the migration orchestration DAG to the storage container
az storage blob upload \
    --container-name "airflow-dags" \
    --file "../migration_orchestration_dag.py" \
    --name "migration_orchestration_dag.py" \
    --account-name <storage-account-name>
```

### 4. Configure Database Connections

```bash
# Create linked services for your source and target databases
# Configure connection strings and credentials through Azure portal
# Test connectivity through the Data Factory interface
```

## Validation & Testing

### Verify Infrastructure Deployment

```bash
# Check resource group resources
az resource list \
    --resource-group rg-db-migration-orchestration \
    --output table

# Verify Data Factory status
az datafactory show \
    --resource-group rg-db-migration-orchestration \
    --name <data-factory-name> \
    --output table

# Check Database Migration Service
az dms show \
    --resource-group rg-db-migration-orchestration \
    --name <dms-name> \
    --output table

# Verify monitoring configuration
az monitor diagnostic-settings list \
    --resource <resource-id> \
    --output table
```

### Test Migration Workflow

```bash
# Trigger the Airflow DAG through the Data Factory interface
# Monitor execution through Azure Monitor and Log Analytics
# Verify alert notifications are working
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name your-resource-group \
    --yes \
    --no-wait

# Verify deletion
az group exists --name your-resource-group
```

### Using Terraform

```bash
cd terraform/

# Plan destruction
terraform plan -destroy

# Destroy infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify resource deletion
az group show --name rg-db-migration-orchestration 2>/dev/null || echo "Resource group deleted"
```

## Customization

### Adding Additional Databases

To support additional databases in your migration workflow:

1. **Update Airflow DAG**: Add new database tasks to the migration orchestration DAG
2. **Configure DMS Projects**: Create additional migration projects for each database
3. **Update Monitoring**: Add specific alerts for new database migrations
4. **Modify Dependencies**: Update task dependencies in the Airflow workflow

### Scaling Configuration

For production environments, consider these modifications:

- **Increase DMS SKU**: Use Premium_4vCores or higher for better performance
- **Enable Auto-scaling**: Configure Airflow worker auto-scaling for high workloads
- **Add Redundancy**: Deploy across multiple Azure regions for disaster recovery
- **Enhanced Monitoring**: Add custom metrics and dashboards for detailed visibility

### Security Hardening

For production deployments, implement these security enhancements:

- **Private Endpoints**: Enable private connectivity for all services
- **Key Vault Integration**: Store secrets and connection strings in Azure Key Vault
- **Network Security Groups**: Restrict network access to required traffic only
- **Azure Policy**: Implement governance policies for resource compliance

## Cost Optimization

Monitor and optimize costs using these strategies:

- **Resource Scheduling**: Scale down non-production environments during off-hours
- **Storage Optimization**: Use appropriate storage tiers for Airflow artifacts
- **DMS Right-sizing**: Choose DMS SKU based on actual migration requirements
- **Log Retention**: Configure appropriate log retention policies in Log Analytics

## Troubleshooting

### Common Issues

1. **Integration Runtime Connectivity**: Verify network connectivity and firewall rules
2. **DMS Migration Failures**: Check source database connectivity and permissions
3. **Airflow DAG Errors**: Review Airflow logs in Azure Monitor
4. **Alert Configuration**: Verify action group email addresses and notification settings

### Monitoring and Diagnostics

```bash
# Check Airflow execution logs
az monitor log-analytics query \
    --workspace <workspace-id> \
    --analytics-query "DataFactoryPipelineRuns | where PipelineName == 'database_migration_orchestration'"

# Monitor DMS migration progress
az monitor log-analytics query \
    --workspace <workspace-id> \
    --analytics-query "AzureDiagnostics | where ResourceProvider == 'MICROSOFT.DATAMIGRATION'"
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for solution architecture details
2. Consult Azure Data Factory and Database Migration Service documentation
3. Check Azure Monitor logs for detailed error information
4. Contact your Azure support team for service-specific issues

## References

- [Azure Data Factory Documentation](https://docs.microsoft.com/en-us/azure/data-factory/)
- [Azure Database Migration Service Documentation](https://docs.microsoft.com/en-us/azure/dms/)
- [Apache Airflow Documentation](https://airflow.apache.org/docs/)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/)