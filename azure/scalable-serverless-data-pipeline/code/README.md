# Infrastructure as Code for Scalable Serverless Data Pipeline with Synapse and Data Factory

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Scalable Serverless Data Pipeline with Synapse and Data Factory".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2 installed and configured
- Active Azure subscription with appropriate permissions
- Resource creation permissions for:
  - Azure Synapse Analytics
  - Azure Data Factory
  - Azure Data Lake Storage Gen2
  - Azure Key Vault
  - Azure Monitor
- Basic understanding of serverless data pipeline concepts
- Estimated cost: $50-200/month depending on data volume (pay-per-use model)

> **Note**: This solution uses serverless components which charge based on actual usage. Monitor costs through Azure Cost Management to avoid unexpected charges.

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to bicep directory
cd bicep/

# Create resource group
az group create \
    --name rg-serverless-pipeline \
    --location eastus

# Deploy infrastructure
az deployment group create \
    --resource-group rg-serverless-pipeline \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh
```

## Architecture Overview

The solution creates a serverless data pipeline using:

- **Azure Synapse Analytics**: Serverless SQL pools for on-demand querying
- **Azure Data Factory**: Orchestration and mapping data flows
- **Azure Data Lake Storage Gen2**: Hierarchical namespace storage
- **Azure Key Vault**: Secure credential management
- **Azure Monitor**: Comprehensive monitoring and alerting

## Configuration

### Bicep Parameters

Key parameters in `parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "resourcePrefix": {
      "value": "pipeline"
    },
    "sqlAdminLogin": {
      "value": "sqladmin"
    },
    "sqlAdminPassword": {
      "value": "P@ssw0rd123!"
    }
  }
}
```

### Terraform Variables

Key variables in `variables.tf`:

- `location`: Azure region for resource deployment
- `resource_prefix`: Prefix for resource naming
- `sql_admin_login`: Synapse SQL admin username
- `sql_admin_password`: Synapse SQL admin password
- `tags`: Resource tags for organization

### Environment Variables

For bash scripts, set these environment variables:

```bash
export RESOURCE_GROUP="rg-serverless-pipeline"
export LOCATION="eastus"
export RESOURCE_PREFIX="pipeline"
export SQL_ADMIN_LOGIN="sqladmin"
export SQL_ADMIN_PASSWORD="P@ssw0rd123!"
```

## Post-Deployment Configuration

After infrastructure deployment, complete these manual steps:

1. **Configure Data Factory Pipelines**:
   - Create mapping data flows in Azure Data Factory
   - Configure pipeline triggers and schedules
   - Test data transformation logic

2. **Set Up External Tables**:
   - Create external tables in Synapse serverless SQL pool
   - Configure data lake access permissions
   - Test query performance

3. **Configure Monitoring**:
   - Set up custom alerts for pipeline failures
   - Configure log analytics workspace
   - Create monitoring dashboards

## Security Considerations

- **Managed Identity**: All services use managed identities for authentication
- **Key Vault Integration**: Credentials stored securely in Azure Key Vault
- **Network Security**: Private endpoints configured for secure communication
- **RBAC**: Role-based access control implemented across all resources
- **Encryption**: Data encrypted at rest and in transit

## Cost Optimization

- **Serverless Model**: Pay-per-use pricing for compute resources
- **Auto-scaling**: Automatic scaling based on workload demands
- **Storage Tiering**: Intelligent tiering for cost-effective storage
- **Resource Tagging**: Comprehensive tagging for cost tracking

## Monitoring and Alerting

The solution includes:

- **Pipeline Monitoring**: Real-time pipeline execution tracking
- **Performance Metrics**: Query performance and resource utilization
- **Cost Alerts**: Automated cost threshold notifications
- **Failure Alerts**: Immediate notification of pipeline failures

## Validation

After deployment, verify the solution:

1. **Resource Verification**:
   ```bash
   # Check deployed resources
   az resource list --resource-group rg-serverless-pipeline --output table
   ```

2. **Synapse Connectivity**:
   ```bash
   # Test Synapse serverless SQL pool
   sqlcmd -S your-synapse-workspace.sql.azuresynapse.net -d master \
       -U sqladmin -P "P@ssw0rd123!" \
       -Q "SELECT @@VERSION"
   ```

3. **Data Factory Validation**:
   ```bash
   # List Data Factory components
   az datafactory linked-service list \
       --factory-name your-data-factory \
       --resource-group rg-serverless-pipeline
   ```

## Cleanup

### Using Bicep
```bash
# Delete resource group (removes all resources)
az group delete \
    --name rg-serverless-pipeline \
    --yes \
    --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your account has Contributor access to the subscription
2. **Resource Name Conflicts**: Use unique resource prefixes to avoid naming conflicts
3. **Quota Limits**: Check Azure subscription limits for Synapse and Data Factory
4. **Network Connectivity**: Verify firewall rules allow access to Synapse endpoints

### Diagnostic Commands

```bash
# Check resource group status
az group show --name rg-serverless-pipeline

# View activity logs
az monitor activity-log list \
    --resource-group rg-serverless-pipeline \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)

# Check Data Factory pipeline runs
az datafactory pipeline-run query \
    --factory-name your-data-factory \
    --resource-group rg-serverless-pipeline \
    --last-updated-after $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)
```

## Customization

### Scaling Configuration

Modify these parameters for different workload sizes:

- **Storage Account SKU**: Adjust for performance requirements
- **Synapse DWU**: Configure data warehouse units for dedicated pools
- **Data Factory Integration Runtime**: Scale integration runtime nodes
- **Key Vault SKU**: Upgrade to Premium for HSM-backed keys

### Regional Deployment

For multi-region deployments:

1. Update location parameters in configuration files
2. Configure cross-region replication for storage
3. Set up geo-redundant backup strategies
4. Implement disaster recovery procedures

## Support

For issues with this infrastructure code:

1. Review the [original recipe documentation](../establishing-serverless-data-pipeline-with-azure-synapse-analytics-and-azure-data-factory.md)
2. Check [Azure Synapse Analytics documentation](https://docs.microsoft.com/en-us/azure/synapse-analytics/)
3. Review [Azure Data Factory documentation](https://docs.microsoft.com/en-us/azure/data-factory/)
4. Consult [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)

## Next Steps

After successful deployment, consider these enhancements:

1. **Real-time Streaming**: Add Azure Event Hubs for streaming data ingestion
2. **Data Quality**: Implement data quality checks and monitoring
3. **Data Catalog**: Integrate with Azure Purview for data governance
4. **Advanced Analytics**: Add Azure Machine Learning for predictive analytics
5. **Multi-tenancy**: Implement tenant isolation for enterprise scenarios