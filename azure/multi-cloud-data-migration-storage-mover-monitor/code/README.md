# Infrastructure as Code for Multi-Cloud Data Migration with Azure Storage Mover and Azure Monitor

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Cloud Data Migration with Azure Storage Mover and Azure Monitor".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Azure Storage Mover
  - Azure Monitor and Log Analytics
  - Azure Logic Apps
  - Azure Storage Account
  - Azure Alerts and Action Groups
- AWS CLI configured with appropriate S3 permissions (for source data)
- Microsoft.StorageMover and Microsoft.HybridCompute resource providers registered
- Appropriate permissions for resource creation and management
- OpenSSL installed for generating random values

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group your-resource-group \
    --template-file bicep/main.bicep \
    --parameters storageAccountName=yourstorageaccount \
                awsS3Bucket=your-source-s3-bucket \
                awsAccountId=your-aws-account-id \
                adminEmail=admin@yourcompany.com
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="storage_account_name=yourstorageaccount" \
               -var="aws_s3_bucket=your-source-s3-bucket" \
               -var="aws_account_id=your-aws-account-id" \
               -var="admin_email=admin@yourcompany.com"

# Apply the configuration
terraform apply -var="storage_account_name=yourstorageaccount" \
                -var="aws_s3_bucket=your-source-s3-bucket" \
                -var="aws_account_id=your-aws-account-id" \
                -var="admin_email=admin@yourcompany.com"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-migration-demo"
export LOCATION="eastus"
export AWS_S3_BUCKET="your-source-s3-bucket"
export AWS_ACCOUNT_ID="your-aws-account-id"

# Deploy the infrastructure
./scripts/deploy.sh
```

## Configuration Parameters

### Bicep Parameters

- `storageAccountName`: Name for the Azure Storage Account (must be globally unique)
- `location`: Azure region for resource deployment (default: eastus)
- `awsS3Bucket`: Source AWS S3 bucket name
- `awsAccountId`: AWS Account ID containing the source S3 bucket
- `adminEmail`: Email address for alert notifications
- `logRetentionDays`: Log Analytics workspace retention period (default: 30)

### Terraform Variables

- `storage_account_name`: Name for the Azure Storage Account
- `location`: Azure region for resource deployment
- `aws_s3_bucket`: Source AWS S3 bucket name
- `aws_account_id`: AWS Account ID containing the source S3 bucket
- `admin_email`: Email address for alert notifications
- `log_retention_days`: Log Analytics workspace retention period
- `resource_group_name`: Resource group name for deployment

### Environment Variables (Bash Scripts)

- `RESOURCE_GROUP`: Resource group name
- `LOCATION`: Azure region
- `AWS_S3_BUCKET`: Source AWS S3 bucket name
- `AWS_ACCOUNT_ID`: AWS Account ID
- `ADMIN_EMAIL`: Email for notifications (optional)

## Deployed Resources

This infrastructure deployment creates:

1. **Azure Storage Account** - Target storage for migrated data
2. **Log Analytics Workspace** - Centralized logging and monitoring
3. **Azure Storage Mover** - Orchestrates multi-cloud data migration
4. **Azure Arc Multicloud Connector** - Enables secure AWS connectivity
5. **Storage Mover Endpoints** - Source (AWS S3) and target (Azure Blob) endpoints
6. **Azure Logic App** - Workflow automation for migration processes
7. **Azure Monitor Alerts** - Proactive notifications for migration events
8. **Action Groups** - Email notifications for alerts
9. **Blob Container** - Target container for migrated data

## Post-Deployment Steps

After deploying the infrastructure, you need to:

1. **Configure AWS Credentials**: Ensure the Storage Mover can access your AWS S3 bucket
2. **Start Migration Job**: Use the Azure CLI or Logic App to initiate data transfer
3. **Monitor Progress**: Check Azure Monitor and Log Analytics for migration status
4. **Validate Data**: Verify migrated data integrity in Azure Blob Storage

### Starting a Migration Job

```bash
# Create and start a migration job
az storage-mover job-definition create \
    --resource-group ${RESOURCE_GROUP} \
    --storage-mover-name ${STORAGE_MOVER_NAME} \
    --project-name "s3-to-blob-migration" \
    --name "initial-migration" \
    --source-endpoint "aws-s3-source" \
    --target-endpoint "azure-blob-target" \
    --copy-mode "Mirror"

# Start the migration job
az storage-mover job-run start \
    --resource-group ${RESOURCE_GROUP} \
    --storage-mover-name ${STORAGE_MOVER_NAME} \
    --project-name "s3-to-blob-migration" \
    --job-definition-name "initial-migration"
```

## Monitoring and Alerting

The deployment includes comprehensive monitoring capabilities:

- **Migration Job Status**: Real-time tracking of migration progress
- **Performance Metrics**: Data transfer rates and throughput monitoring
- **Error Detection**: Automated alerts for migration failures
- **Success Notifications**: Alerts for completed migrations
- **Log Analytics**: Detailed logging for troubleshooting and analysis

### Accessing Logs

```bash
# Query migration logs
az monitor log-analytics query \
    --workspace ${WORKSPACE_ID} \
    --analytics-query "
        StorageMoverLogs_CL
        | where TimeGenerated > ago(1h)
        | where JobName_s == 'initial-migration'
        | project TimeGenerated, JobStatus_s, TransferredBytes_d
        | order by TimeGenerated desc"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name your-resource-group --yes --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="storage_account_name=yourstorageaccount" \
                  -var="aws_s3_bucket=your-source-s3-bucket" \
                  -var="aws_account_id=your-aws-account-id" \
                  -var="admin_email=admin@yourcompany.com"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

## Security Considerations

This deployment implements several security best practices:

- **Least Privilege Access**: IAM roles and permissions follow principle of least privilege
- **Encrypted Storage**: All data is encrypted at rest and in transit
- **Secure Connectivity**: Azure Arc provides secure connection to AWS resources
- **Access Control**: Storage account configured with private access by default
- **Audit Logging**: Comprehensive logging for compliance and monitoring

## Cost Optimization

To optimize costs for this solution:

1. **Storage Tier Selection**: Choose appropriate storage tiers based on access patterns
2. **Log Retention**: Adjust Log Analytics retention period based on compliance requirements
3. **Alert Frequency**: Configure alert evaluation frequency to balance responsiveness and cost
4. **Resource Cleanup**: Remove resources when migration is complete to avoid ongoing charges

## Troubleshooting

Common issues and solutions:

1. **Resource Provider Registration**: Ensure Microsoft.StorageMover and Microsoft.HybridCompute are registered
2. **AWS Permissions**: Verify AWS credentials have sufficient S3 permissions
3. **Storage Account Naming**: Ensure storage account names are globally unique
4. **Resource Limits**: Check subscription limits for Storage Mover and other resources

## Customization

### Scaling for Large Datasets

For large-scale migrations, consider:

- Implementing parallel migration jobs
- Using Azure Storage premium tiers for higher throughput
- Configuring incremental migration strategies
- Setting up multiple target containers for data organization

### Integration with Existing Systems

This solution can be extended to integrate with:

- Azure Data Factory for additional data processing
- Azure Synapse Analytics for data analytics
- Azure Purview for data governance
- Custom applications via Logic Apps and Azure Functions

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure Storage Mover documentation: https://docs.microsoft.com/en-us/azure/storage-mover/
3. Consult Azure Monitor documentation: https://docs.microsoft.com/en-us/azure/azure-monitor/
4. Review Azure Arc documentation: https://docs.microsoft.com/en-us/azure/azure-arc/

## Version History

- **1.0**: Initial implementation with Bicep, Terraform, and Bash scripts
- Supports Azure Storage Mover, Azure Monitor, and Logic Apps integration
- Includes comprehensive monitoring and alerting capabilities