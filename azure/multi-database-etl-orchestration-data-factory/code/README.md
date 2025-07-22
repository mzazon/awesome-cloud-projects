# Infrastructure as Code for Multi-Database ETL Orchestration with Data Factory

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Database ETL Orchestration with Data Factory".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a comprehensive ETL orchestration platform that includes:

- **Azure Data Factory**: Enterprise-grade ETL orchestration engine
- **Azure Database for MySQL Flexible Server**: Target database with high availability
- **Azure Key Vault**: Secure credential management
- **Azure Monitor & Log Analytics**: Comprehensive monitoring and alerting
- **Self-Hosted Integration Runtime**: Secure on-premises connectivity

## Prerequisites

### Required Tools
- Azure CLI v2.15.0 or higher installed and configured
- Azure subscription with appropriate permissions for:
  - Azure Data Factory
  - Azure Database for MySQL
  - Azure Key Vault
  - Azure Monitor
  - Log Analytics
- Terraform v1.0+ (for Terraform deployment)
- MySQL client tools (for testing connectivity)

### Required Permissions
- Contributor or Owner role on the target Azure subscription
- Key Vault Administrator role for secret management
- Data Factory Contributor role for pipeline management

### Network Requirements
- Connectivity between on-premises MySQL databases and Azure (VPN or ExpressRoute recommended)
- Firewall rules configured to allow Azure services access

### Cost Considerations
- **Development Environment**: $150-300/month
- **Production Environment**: $500-1,500/month (varies by data volume and frequency)
- Key cost factors:
  - Data Factory pipeline runs and data movement
  - MySQL Flexible Server compute and storage
  - Log Analytics data ingestion and retention
  - Integration Runtime compute hours

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone the repository and navigate to the code directory
cd azure/implementing-enterprise-grade-multi-database-etl-orchestration-with-azure-data-factory-and-azure-database-for-mysql/code

# Set deployment parameters
RESOURCE_GROUP="rg-etl-orchestration"
LOCATION="eastus"
DEPLOYMENT_NAME="etl-deployment-$(date +%Y%m%d-%H%M%S)"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Review and customize parameters
cp bicep/parameters.json.example bicep/parameters.json
# Edit parameters.json with your specific values

# Deploy infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json \
    --name ${DEPLOYMENT_NAME}

# Verify deployment
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DEPLOYMENT_NAME} \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan -var-file="terraform.tfvars"

# Apply infrastructure
terraform apply -var-file="terraform.tfvars"

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Review and customize environment variables in deploy.sh
# Edit the script to match your environment

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
./scripts/verify.sh
```

## Post-Deployment Configuration

### 1. Install Self-Hosted Integration Runtime

```bash
# Get the authentication key from the deployment output
IR_AUTH_KEY=$(az datafactory integration-runtime get-connection-info \
    --resource-group ${RESOURCE_GROUP} \
    --factory-name ${ADF_NAME} \
    --name "SelfHostedIR" \
    --query authKey1 -o tsv)

echo "Install Integration Runtime on your on-premises server using key: ${IR_AUTH_KEY}"
```

### 2. Configure Source Database Connections

```bash
# Update Key Vault secrets with your on-premises MySQL connection details
az keyvault secret set \
    --vault-name ${KEY_VAULT_NAME} \
    --name "mysql-source-connection-string" \
    --value "server=your-mysql-server.domain.com;port=3306;database=source_db;uid=etl_user;pwd=YourPassword"
```

### 3. Test Pipeline Execution

```bash
# Trigger a test pipeline run
az datafactory pipeline create-run \
    --resource-group ${RESOURCE_GROUP} \
    --factory-name ${ADF_NAME} \
    --name "MultiDatabaseETLPipeline"
```

## Configuration Options

### Bicep Parameters

Key parameters you can customize in `bicep/parameters.json`:

```json
{
  "resourcePrefix": {
    "value": "etl-demo"
  },
  "location": {
    "value": "eastus"
  },
  "mysqlServerSku": {
    "value": "Standard_D2ds_v4"
  },
  "mysqlStorageSize": {
    "value": "128"
  },
  "enableHighAvailability": {
    "value": true
  },
  "logAnalyticsRetentionDays": {
    "value": 90
  }
}
```

### Terraform Variables

Key variables you can customize in `terraform.tfvars`:

```hcl
resource_group_name = "rg-etl-orchestration"
location           = "eastus"
resource_prefix    = "etl-demo"

mysql_server_sku   = "Standard_D2ds_v4"
mysql_storage_gb   = 128
mysql_ha_enabled   = true

log_retention_days = 90
environment        = "development"
```

## Monitoring and Troubleshooting

### Access Monitoring Dashboard

```bash
# Get Log Analytics workspace ID
WORKSPACE_ID=$(az monitor log-analytics workspace show \
    --resource-group ${RESOURCE_GROUP} \
    --workspace-name ${LOG_ANALYTICS_NAME} \
    --query customerId -o tsv)

echo "Log Analytics Workspace ID: ${WORKSPACE_ID}"
```

### Common KQL Queries

```kql
// Pipeline execution summary
ADFPipelineRun
| where TimeGenerated > ago(24h)
| summarize count() by Status, PipelineName
| render piechart

// Failed pipeline runs
ADFPipelineRun
| where TimeGenerated > ago(24h) and Status == "Failed"
| project TimeGenerated, PipelineName, RunId, ErrorMessage

// Data movement statistics
ADFActivityRun
| where TimeGenerated > ago(24h) and ActivityType == "Copy"
| summarize TotalRowsCopied = sum(toint(Output.rowsCopied)) by bin(TimeGenerated, 1h)
| render timechart
```

### Troubleshooting Tips

1. **Integration Runtime Connectivity Issues**:
   ```bash
   # Check IR status
   az datafactory integration-runtime show \
       --resource-group ${RESOURCE_GROUP} \
       --factory-name ${ADF_NAME} \
       --name "SelfHostedIR"
   ```

2. **MySQL Connection Problems**:
   ```bash
   # Test MySQL connectivity
   mysql -h ${MYSQL_SERVER_NAME}.mysql.database.azure.com \
       -u ${MYSQL_ADMIN_USER} \
       -p${MYSQL_ADMIN_PASSWORD} \
       -e "SELECT VERSION();"
   ```

3. **Pipeline Execution Failures**:
   - Check Data Factory monitoring blade in Azure Portal
   - Review activity run details and error messages
   - Verify linked service connections
   - Check Key Vault access policies

## Security Considerations

### Network Security
- All database connections use SSL/TLS encryption
- Integration Runtime uses encrypted communication channels
- Azure services communicate over Microsoft backbone network

### Access Control
- Managed identities used for service-to-service authentication
- Key Vault implements least-privilege access policies
- Role-based access control (RBAC) for all Azure resources

### Data Protection
- Sensitive credentials stored in Azure Key Vault
- Diagnostic data retention policies configured
- Audit logs enabled for all critical operations

## Performance Optimization

### Data Factory Optimization
- Parallel copy activities configured for large datasets
- Data Integration Units (DIUs) optimized for workload
- Incremental data loading using watermarks

### MySQL Performance
- Flexible Server configured with appropriate compute size
- High availability enabled for production workloads
- Connection pooling and query optimization recommended

### Cost Optimization
- Scheduled triggers to run during off-peak hours
- Auto-pause capabilities for development environments
- Reserved capacity for predictable workloads

## Cleanup

### Using Bicep

```bash
# Delete the deployment and resource group
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait

# Verify deletion
az group exists --name ${RESOURCE_GROUP}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var-file="terraform.tfvars"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group exists --name ${RESOURCE_GROUP}
```

## Support and Resources

### Documentation Links
- [Azure Data Factory Documentation](https://docs.microsoft.com/en-us/azure/data-factory/)
- [Azure Database for MySQL Documentation](https://docs.microsoft.com/en-us/azure/mysql/)
- [Azure Key Vault Documentation](https://docs.microsoft.com/en-us/azure/key-vault/)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)

### Best Practices
- [Data Factory Security Best Practices](https://docs.microsoft.com/en-us/azure/data-factory/data-factory-security-considerations)
- [MySQL Performance Best Practices](https://docs.microsoft.com/en-us/azure/mysql/concepts-performance-recommendations)
- [Azure Security Baseline](https://docs.microsoft.com/en-us/security/benchmark/azure/baselines/data-factory-security-baseline)

### Community Resources
- [Azure Data Factory Community](https://techcommunity.microsoft.com/t5/azure-data-factory/bd-p/AzureDataFactory)
- [MySQL Community](https://dev.mysql.com/doc/)
- [Azure Architecture Center](https://docs.microsoft.com/en-us/azure/architecture/)

## Contributing

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.

## License

This infrastructure code is provided under the same license as the parent repository.