# Infrastructure as Code for Simple File Backup Automation using Logic Apps and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple File Backup Automation using Logic Apps and Storage".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts for Azure CLI

## Prerequisites

- Azure CLI installed and configured (version 2.37.0 or later)
- Azure subscription with appropriate permissions for:
  - Creating resource groups
  - Creating Logic Apps
  - Creating Storage accounts
  - Managing blob containers
- Logic Apps Azure CLI extension: `az extension add --name logic`
- For Terraform: Terraform CLI installed (version 1.0 or later)
- For Bicep: Azure CLI with Bicep extension installed

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-backup-demo \
    --template-file main.bicep \
    --parameters location=eastus \
                 environmentName=demo \
                 storageAccountName=stbackup$(openssl rand -hex 3)

# Verify deployment
az deployment group show \
    --resource-group rg-backup-demo \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="location=eastus" \
    -var="environment=demo" \
    -var="resource_group_name=rg-backup-demo"

# Apply the configuration
terraform apply \
    -var="location=eastus" \
    -var="environment=demo" \
    -var="resource_group_name=rg-backup-demo"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-backup-demo"
export LOCATION="eastus"
export ENVIRONMENT="demo"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
az logic workflow show \
    --resource-group $RESOURCE_GROUP \
    --name la-backup-* \
    --query "{Name:name, State:state}"
```

## Architecture Overview

This infrastructure creates:

- **Resource Group**: Container for all backup automation resources
- **Storage Account**: Secure blob storage with Cool access tier for cost-effective backup storage
- **Blob Container**: Private container for backup files with metadata tagging
- **Logic Apps Workflow**: Serverless automation workflow with daily recurrence trigger
- **Workflow Definition**: Pre-configured backup logic with error handling and logging

## Configuration Options

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `eastus` | Azure region for resource deployment |
| `environmentName` | string | `demo` | Environment identifier for resource naming |
| `storageAccountName` | string | Generated | Unique storage account name |
| `logicAppName` | string | Generated | Logic Apps workflow name |
| `containerName` | string | `backup-files` | Blob container name for backup files |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `location` | string | `"eastus"` | Azure region for resource deployment |
| `environment` | string | `"demo"` | Environment identifier for resource naming |
| `resource_group_name` | string | Required | Name of the resource group |
| `storage_account_name` | string | Generated | Unique storage account name |
| `logic_app_name` | string | Generated | Logic Apps workflow name |
| `backup_schedule_hour` | number | `2` | Hour of day for backup execution (0-23) |

### Script Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `RESOURCE_GROUP` | Yes | Resource group name |
| `LOCATION` | Yes | Azure region |
| `ENVIRONMENT` | No | Environment identifier (default: demo) |
| `STORAGE_ACCOUNT` | No | Storage account name (auto-generated if not set) |
| `LOGIC_APP` | No | Logic Apps name (auto-generated if not set) |

## Security Features

All implementations include these security configurations:

- **Storage Account Security**:
  - TLS 1.2 minimum encryption
  - Public blob access disabled
  - Cool access tier for cost optimization
  - Locally redundant storage (LRS) for durability

- **Logic Apps Security**:
  - Managed identity integration ready
  - Secure workflow triggers
  - Built-in authentication for Azure services

- **Network Security**:
  - Private blob containers
  - Secure HTTPS endpoints only
  - No public internet access to storage

## Monitoring and Logging

The deployed infrastructure includes:

- **Workflow History**: Automatic tracking of Logic Apps execution history
- **Storage Metrics**: Built-in Azure Storage metrics and logging
- **Activity Logs**: Azure Resource Manager activity logging
- **Integration Ready**: Compatible with Azure Monitor and Log Analytics

## Cost Optimization

This solution is designed for cost-effectiveness:

- **Logic Apps Consumption Plan**: Pay-per-execution pricing
- **Cool Storage Tier**: Optimized for infrequently accessed backup data
- **LRS Redundancy**: Cost-effective local redundancy option
- **Estimated Monthly Cost**: $2-5 for typical small business usage

## Customization Examples

### Modify Backup Schedule

To change the backup schedule from daily at 2 AM to weekly on Sundays:

**Bicep**: Update the workflow definition in `main.bicep`
```json
"recurrence": {
    "frequency": "Week",
    "interval": 1,
    "schedule": {
        "weekDays": ["Sunday"],
        "hours": [2],
        "minutes": [0]
    }
}
```

**Terraform**: Update `terraform/main.tf` workflow definition
```hcl
recurrence = {
  frequency = "Week"
  interval  = 1
  schedule = {
    week_days = ["Sunday"]
    hours     = [2]
    minutes   = [0]
  }
}
```

### Add Email Notifications

To extend the workflow with email notifications, add an Office 365 Outlook connector action after the backup completion.

### Enable Archive Storage Tier

Configure lifecycle management to automatically move files to Archive tier after 90 days for additional cost savings.

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-backup-demo \
    --yes \
    --no-wait

# Verify deletion
az group exists --name rg-backup-demo
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy \
    -var="location=eastus" \
    -var="environment=demo" \
    -var="resource_group_name=rg-backup-demo"

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Script will prompt for confirmation before deletion
# Resources are deleted in proper order to handle dependencies
```

## Troubleshooting

### Common Issues

1. **Storage Account Name Conflicts**
   - Solution: Storage account names must be globally unique. Use a random suffix or different name.

2. **Logic Apps Extension Missing**
   - Solution: Install with `az extension add --name logic`

3. **Insufficient Permissions**
   - Solution: Ensure your account has Contributor role on the subscription or resource group

4. **Workflow Not Triggering**
   - Solution: Check workflow state is "Enabled" and trigger configuration is correct

### Validation Commands

```bash
# Check Logic Apps workflow status
az logic workflow show \
    --resource-group $RESOURCE_GROUP \
    --name $LOGIC_APP \
    --query "{Name:name, State:state, Location:location}"

# Verify storage account configuration
az storage account show \
    --name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --query "{Name:name, AccessTier:accessTier, PublicAccess:allowBlobPublicAccess}"

# List backup files
az storage blob list \
    --container-name backup-files \
    --account-name $STORAGE_ACCOUNT \
    --query "[].{Name:name, LastModified:properties.lastModified}"
```

## Extension Ideas

1. **Multi-Source Integration**: Add SharePoint Online and OneDrive connectors
2. **Advanced Scheduling**: Implement different schedules for different file types
3. **Backup Verification**: Add Azure Functions to verify backup integrity
4. **Lifecycle Management**: Implement automatic archiving and deletion policies
5. **Monitoring Dashboard**: Create Azure Monitor workbooks for backup analytics

## Support

- For Azure Logic Apps issues: [Azure Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- For Azure Storage issues: [Azure Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/)
- For infrastructure issues: Refer to the original recipe documentation
- For Bicep support: [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- For Terraform support: [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Contributing

When extending this infrastructure:

1. Follow Azure naming conventions
2. Implement proper error handling
3. Add appropriate resource tags
4. Update this README with new features
5. Test deployments in a development environment first

---

**Note**: This infrastructure code provides the foundation for the backup automation solution. Customize the Logic Apps workflow definition to match your specific backup requirements and integrate with your existing file sources.