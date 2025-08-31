# Infrastructure as Code for Simple File Sync with Azure File Sync and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple File Sync with Azure File Sync and Storage".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Azure CLI installed and configured (`az --version` to verify)
- Azure subscription with appropriate permissions for:
  - Storage Account creation and management
  - Azure File Sync service deployment
  - Resource Group management
- Bash shell environment (Linux, macOS, or Windows Subsystem for Linux)
- Internet connectivity for downloading dependencies

### Specific Tool Requirements

#### For Bicep
- Azure CLI with Bicep support (automatically included in recent versions)
- Bicep CLI installed (`az bicep install` if needed)

#### For Terraform
- Terraform >= 1.0 installed ([Download here](https://developer.hashicorp.com/terraform/downloads))
- Azure CLI authenticated (`az login`)

### Permissions Required
Your Azure account needs the following permissions:
- `Storage Account Contributor` or higher on the subscription/resource group
- `Storage Sync Service Contributor` for Azure File Sync operations
- `Resource Group Contributor` for resource management

### Cost Considerations
- Storage costs: $0.06-$0.18 per GB/month (LRS pricing)
- Azure File Sync licensing: ~$15/month per server after the first server
- Transaction costs for sync operations
- Estimated monthly cost for testing: $5-15 (depending on data volume)

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to the bicep directory
cd bicep/

# Deploy with default parameters
az deployment group create \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters storageAccountName=filesync$(date +%s)

# Deploy with custom parameters
az deployment group create \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters \
        storageAccountName=myfilesync123 \
        fileShareName=companydata \
        fileShareQuota=2048 \
        location=eastus
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform (downloads providers)
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply

# Apply with custom variables
terraform apply \
    -var="resource_group_name=my-filesync-rg" \
    -var="storage_account_name=myfilesync123" \
    -var="location=westus2"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Deploy with environment variables
RESOURCE_GROUP="my-filesync-rg" \
LOCATION="eastus" \
STORAGE_ACCOUNT="filesync123" \
./scripts/deploy.sh
```

## Configuration Options

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `storageAccountName` | string | Required | Globally unique storage account name (3-24 chars, alphanumeric) |
| `storageSyncServiceName` | string | Auto-generated | Name for the Storage Sync Service |
| `fileShareName` | string | `companyfiles` | Name of the Azure file share |
| `fileShareQuota` | int | `1024` | File share quota in GB (1-100000) |
| `syncGroupName` | string | `main-sync-group` | Name of the sync group |
| `location` | string | Resource group location | Azure region for deployment |
| `storageAccountSku` | string | `Standard_LRS` | Storage account SKU (LRS, GRS, RAGRS) |
| `tags` | object | Default tags | Resource tags for organization |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `resource_group_name` | string | `rg-filesync-demo` | Resource group name |
| `location` | string | `East US` | Azure region |
| `storage_account_name` | string | Auto-generated | Storage account name |
| `storage_sync_service_name` | string | Auto-generated | Storage Sync Service name |
| `file_share_name` | string | `companyfiles` | File share name |
| `file_share_quota_gb` | number | `1024` | File share quota in GB |
| `sync_group_name` | string | `main-sync-group` | Sync group name |
| `storage_sku` | string | `Standard_LRS` | Storage account replication type |
| `enable_large_file_share` | bool | `true` | Enable large file share (up to 100TB) |
| `tags` | map(string) | Default tags | Resource tags |

### Environment Variables (Bash Scripts)

| Variable | Default | Description |
|----------|---------|-------------|
| `RESOURCE_GROUP` | `rg-filesync-demo` | Resource group name |
| `LOCATION` | `eastus` | Azure region |
| `STORAGE_ACCOUNT` | Auto-generated | Storage account name |
| `STORAGE_SYNC_SERVICE` | Auto-generated | Storage Sync Service name |
| `FILE_SHARE_NAME` | `companyfiles` | File share name |
| `SYNC_GROUP_NAME` | `main-sync-group` | Sync group name |

## Deployment Examples

### Production Deployment with Bicep

```bash
# Create resource group first
az group create --name prod-filesync-rg --location eastus

# Deploy with production settings
az deployment group create \
    --resource-group prod-filesync-rg \
    --template-file bicep/main.bicep \
    --parameters \
        storageAccountName=prodfilesync$(date +%s) \
        fileShareName=production-data \
        fileShareQuota=5120 \
        storageAccountSku=Standard_GRS \
        tags='{"Environment":"Production","Department":"IT","CostCenter":"12345"}'
```

### Multi-Environment with Terraform

```bash
# Development environment
terraform apply \
    -var-file="environments/dev.tfvars"

# Production environment
terraform apply \
    -var-file="environments/prod.tfvars"
```

Example `environments/prod.tfvars`:
```hcl
resource_group_name = "prod-filesync-rg"
location = "East US"
storage_account_name = "prodfilesync123"
file_share_quota_gb = 5120
storage_sku = "Standard_GRS"
tags = {
  Environment = "Production"
  Department = "IT"
  CostCenter = "12345"
}
```

## Post-Deployment Steps

After deploying the infrastructure, you'll need to complete the Azure File Sync setup:

### 1. Server Registration
On your Windows Server, install the Azure File Sync agent and register:

```powershell
# Download and install Azure File Sync agent
# https://docs.microsoft.com/en-us/azure/storage/file-sync/file-sync-deployment-guide

# Register server (run from PowerShell as Administrator)
Import-Module "C:\Program Files\Azure\StorageSyncAgent\StorageSync.Management.PowerShell.Cmdlets.dll"
Login-AzureRmStorageSync -SubscriptionID "<subscription-id>" -ResourceGroupName "<resource-group>"
Register-AzureRmStorageSyncServer -ResourceGroupName "<resource-group>" -StorageSyncServiceName "<sync-service-name>"
```

### 2. Create Server Endpoint
```powershell
# Create server endpoint
New-AzureRmStorageSyncServerEndpoint `
    -ResourceGroupName "<resource-group>" `
    -StorageSyncServiceName "<sync-service-name>" `
    -SyncGroupName "<sync-group-name>" `
    -ServerEndpointName "ServerEndpoint1" `
    -RegisteredServerId "<server-id>" `
    -ServerLocalPath "D:\SyncFolder" `
    -CloudTiering $true `
    -VolumeFreeSpacePercent 20
```

### 3. Verify Synchronization
Monitor sync status through Azure portal or PowerShell:

```powershell
# Check sync status
Get-AzureRmStorageSyncServerEndpoint -ResourceGroupName "<resource-group>" -StorageSyncServiceName "<sync-service-name>" -SyncGroupName "<sync-group-name>"
```

## Validation and Testing

### Verify Deployment

```bash
# Check Storage Sync Service
az storagesync show \
    --resource-group <resource-group> \
    --name <storage-sync-service-name>

# List sync groups
az storagesync sync-group list \
    --resource-group <resource-group> \
    --storage-sync-service <storage-sync-service-name>

# Check file share
az storage share show \
    --account-name <storage-account-name> \
    --name <file-share-name>
```

### Test File Synchronization

```bash
# Upload test file to Azure file share
echo "Test sync file $(date)" > test-sync.txt
az storage file upload \
    --account-name <storage-account-name> \
    --share-name <file-share-name> \
    --source test-sync.txt \
    --path test-sync.txt

# Verify file exists
az storage file list \
    --account-name <storage-account-name> \
    --share-name <file-share-name>
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name <resource-group-name> --yes --no-wait

# Or delete individual deployment
az deployment group delete \
    --resource-group <resource-group-name> \
    --name <deployment-name>
```

### Using Terraform

```bash
cd terraform/
terraform destroy

# Confirm destruction when prompted
# Enter 'yes' to proceed
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Troubleshooting

### Common Issues

#### Storage Account Name Already Exists
```bash
# Error: Storage account name must be globally unique
# Solution: Use a unique suffix or different name
STORAGE_ACCOUNT="filesync$(openssl rand -hex 3)"
```

#### Insufficient Permissions
```bash
# Error: Authorization failed
# Solution: Verify Azure CLI authentication and permissions
az login
az account show
az role assignment list --assignee $(az account show --query user.name -o tsv)
```

#### Terraform Provider Issues
```bash
# Error: Provider version conflicts
# Solution: Update providers
cd terraform/
terraform init -upgrade
```

### Monitoring and Logs

```bash
# Check deployment status
az deployment group list --resource-group <resource-group-name>

# View deployment logs
az deployment group show \
    --resource-group <resource-group-name> \
    --name <deployment-name> \
    --query properties.error

# Monitor Storage Sync Service health
az storagesync show \
    --resource-group <resource-group-name> \
    --name <storage-sync-service-name> \
    --query provisioningState
```

## Security Considerations

- **Network Security**: Configure firewall rules and private endpoints if needed
- **Access Control**: Use Azure RBAC and storage account access keys securely
- **Encryption**: All data is encrypted in transit (TLS 1.2+) and at rest (AES-256)
- **Monitoring**: Enable Azure Monitor and set up alerts for sync failures
- **Backup**: Consider Azure Backup for additional data protection

## Cost Optimization

- **Storage Tiers**: Use appropriate storage tiers based on access patterns
- **Cloud Tiering**: Enable cloud tiering to reduce on-premises storage costs
- **Monitoring**: Set up cost alerts and budgets
- **Cleanup**: Regularly remove unused resources

## Support and Resources

- [Azure File Sync Documentation](https://docs.microsoft.com/en-us/azure/storage/file-sync/)
- [Azure Files Pricing](https://azure.microsoft.com/pricing/details/storage/files/)
- [Troubleshooting Guide](https://docs.microsoft.com/en-us/azure/storage/file-sync/file-sync-troubleshoot)
- [Azure Storage Security Guide](https://docs.microsoft.com/en-us/azure/storage/common/storage-security-guide)

For issues with this infrastructure code, refer to the original recipe documentation or Azure support resources.