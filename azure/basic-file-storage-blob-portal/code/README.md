# Infrastructure as Code for Basic File Storage with Blob Storage and Portal

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Basic File Storage with Blob Storage and Portal".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.57.0 or later)
- Azure subscription with Owner or Contributor role on resource group
- Appropriate permissions for creating:
  - Storage accounts
  - Blob containers
  - Role assignments (Storage Blob Data Contributor)
- For Terraform: Terraform CLI installed (version 1.0 or later)
- Basic understanding of cloud storage concepts

## Architecture Overview

This solution deploys:
- Azure Storage Account (General-purpose v2) with security hardening
- Three blob containers (documents, images, backups)
- RBAC role assignment for secure access
- TLS 1.2 enforcement and disabled public blob access

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Create resource group
az group create \
    --name "rg-storage-demo" \
    --location "eastus"

# Deploy the Bicep template
az deployment group create \
    --resource-group "rg-storage-demo" \
    --template-file main.bicep \
    --parameters storageAccountPrefix="mystorageacct"

# The deployment will output the storage account name and container URLs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="resource_group_name=rg-storage-demo" \
    -var="location=eastus" \
    -var="storage_account_prefix=mystorageacct"

# Apply the configuration
terraform apply \
    -var="resource_group_name=rg-storage-demo" \
    -var="location=eastus" \
    -var="storage_account_prefix=mystorageacct"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-storage-demo"
export LOCATION="eastus"
export STORAGE_ACCOUNT_PREFIX="mystorageacct"

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output connection details and next steps
```

## Customization

### Bicep Parameters

Key parameters you can customize in the Bicep deployment:

- `storageAccountPrefix`: Prefix for the storage account name (6-18 characters)
- `location`: Azure region for deployment (default: resource group location)
- `skuName`: Storage redundancy option (default: Standard_LRS)
- `accessTier`: Storage access tier (default: Hot)
- `containerNames`: Array of container names to create (default: ["documents", "images", "backups"])

### Terraform Variables

Customize your deployment by modifying variables in `terraform/variables.tf` or passing them via command line:

```bash
terraform apply \
    -var="resource_group_name=my-rg" \
    -var="location=westus2" \
    -var="storage_account_prefix=mycompany" \
    -var="sku_name=Standard_GRS" \
    -var="access_tier=Cool"
```

### Bash Script Environment Variables

Set these environment variables before running the deployment script:

```bash
export RESOURCE_GROUP="your-resource-group"
export LOCATION="your-preferred-region"
export STORAGE_ACCOUNT_PREFIX="your-prefix"
export SKU_NAME="Standard_LRS"  # Optional
export ACCESS_TIER="Hot"        # Optional
```

## Post-Deployment Steps

After successful deployment:

1. **Verify RBAC Permissions**: Role assignments may take 1-2 minutes to propagate
2. **Access Azure Portal**: Navigate to the storage account in the Azure Portal
3. **Test File Operations**: Upload test files using either CLI or Portal
4. **Review Security Settings**: Verify TLS 1.2 enforcement and disabled public access

### Portal Access

Access your storage account through the Azure Portal:
1. Navigate to Azure Portal → Storage accounts
2. Select your deployed storage account
3. Choose "Storage browser" from the left menu
4. Select "Blob containers" to manage files

### CLI File Operations

```bash
# Set your storage account name (from deployment output)
STORAGE_ACCOUNT="your-deployed-storage-account-name"

# Upload a test file
az storage blob upload \
    --file "test-file.txt" \
    --name "test-file.txt" \
    --container-name "documents" \
    --account-name $STORAGE_ACCOUNT \
    --auth-mode login

# List blobs in container
az storage blob list \
    --container-name "documents" \
    --account-name $STORAGE_ACCOUNT \
    --auth-mode login \
    --output table
```

## Security Features

This implementation includes several security best practices:

- **TLS 1.2 Enforcement**: Minimum TLS version set to 1.2
- **Disabled Public Access**: Public blob access disabled by default
- **RBAC Integration**: Uses Microsoft Entra ID for authentication
- **Least Privilege**: Storage Blob Data Contributor role for data operations only
- **Secure Defaults**: Hot tier with locally redundant storage for cost efficiency

## Cost Optimization

- **Storage Tier**: Configured with Hot access tier for frequently accessed data
- **Redundancy**: Uses Standard_LRS for cost-effective local redundancy
- **Lifecycle Management**: Ready for implementing automated tier transitions
- **Estimated Cost**: $0.02-0.05 per month for standard usage (first 5GB free)

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name "rg-storage-demo" \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy \
    -var="resource_group_name=rg-storage-demo" \
    -var="location=eastus" \
    -var="storage_account_prefix=mystorageacct"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

## Troubleshooting

### Common Issues

1. **Storage Account Name Conflicts**: Storage account names must be globally unique
   - Solution: Use a more unique prefix or let the system generate a suffix

2. **RBAC Permission Delays**: Role assignments may take time to propagate
   - Solution: Wait 1-2 minutes before attempting blob operations

3. **Authentication Errors**: Ensure you're logged in with appropriate permissions
   - Solution: Run `az login` and verify your account has Contributor access

4. **Region Availability**: Some regions may not support all storage features
   - Solution: Use well-established regions like East US, West US 2, or West Europe

### Validation Commands

```bash
# Check storage account status
az storage account show \
    --name "your-storage-account" \
    --resource-group "your-resource-group" \
    --query "{name:name,status:provisioningState,tls:minimumTlsVersion}"

# List containers
az storage container list \
    --account-name "your-storage-account" \
    --auth-mode login \
    --output table

# Check RBAC assignments
az role assignment list \
    --scope "/subscriptions/your-subscription/resourceGroups/your-rg/providers/Microsoft.Storage/storageAccounts/your-storage-account" \
    --output table
```

## Extensions and Enhancements

Consider these enhancements for production use:

1. **Lifecycle Management**: Implement policies to transition data to cooler tiers
2. **Soft Delete**: Enable blob soft delete for data protection
3. **Versioning**: Enable blob versioning for point-in-time recovery
4. **Monitoring**: Add Azure Monitor alerts for storage metrics
5. **Network Security**: Configure private endpoints for enhanced security
6. **Cross-Region Replication**: Implement GRS or RA-GRS for disaster recovery

## Support and Documentation

- [Azure Blob Storage Documentation](https://learn.microsoft.com/en-us/azure/storage/blobs/)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure CLI Reference](https://learn.microsoft.com/en-us/cli/azure/storage)

For issues with this infrastructure code, refer to the original recipe documentation or consult the Azure documentation links above.

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Adapt it according to your organization's requirements and security policies.