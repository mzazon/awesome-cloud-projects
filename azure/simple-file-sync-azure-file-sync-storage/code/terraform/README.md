# Azure File Sync Terraform Infrastructure

This Terraform configuration deploys a complete Azure File Sync solution including:

- Azure Resource Group
- Azure Storage Account with large file share support
- Azure File Share with sample files
- Azure File Sync Service
- Sync Group and Cloud Endpoint configuration

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Terraform >= 1.0 installed
- Appropriate Azure permissions for creating:
  - Resource Groups
  - Storage Accounts
  - Azure File Sync resources

## Quick Start

1. **Initialize Terraform:**
   ```bash
   terraform init
   ```

2. **Review the plan:**
   ```bash
   terraform plan
   ```

3. **Deploy the infrastructure:**
   ```bash
   terraform apply
   ```

4. **Clean up resources:**
   ```bash
   terraform destroy
   ```

## Customization

Customize the deployment by creating a `terraform.tfvars` file:

```hcl
# Basic configuration
location            = "East US"
resource_group_name = "my-filesync-rg"
storage_account_name = "myfilesync"

# File share configuration
file_share_name     = "companyfiles"
file_share_quota    = 2048
file_share_access_tier = "Hot"

# Sync service configuration
storage_sync_service_name = "my-filesync-service"
sync_group_name          = "main-sync-group"

# Tags
common_tags = {
  Environment = "Production"
  Department  = "IT"
  Project     = "File Sync"
}
```

## Important Outputs

After deployment, Terraform provides essential information including:

- **Server Registration Information**: Required for registering Windows Servers
- **SMB Connection Information**: For direct file share access
- **Management URLs**: Links to Azure portal resources
- **Security Features**: Summary of enabled security settings

## Next Steps

1. **Install Azure File Sync Agent** on your Windows Server(s)
2. **Register your servers** using the provided registration information
3. **Create server endpoints** to define local synchronization paths
4. **Configure cloud tiering** policies for cost optimization
5. **Monitor sync health** through the Azure portal

## Security Considerations

This configuration implements security best practices:

- HTTPS-only traffic enforcement
- TLS 1.2 minimum requirement
- Encryption at rest and in transit
- Controlled network access (Azure services allowed)
- Metadata tagging for governance

## Cost Optimization

Consider these cost optimization strategies:

- Use **Standard LRS** replication for development environments
- Enable **cloud tiering** to reduce local storage requirements
- Monitor **transaction costs** for high-activity scenarios
- Review **data transfer costs** for cross-region deployments

## Troubleshooting

Common issues and solutions:

- **Storage account name conflicts**: Enable `use_random_suffix = true`
- **Quota exceeded**: Increase `file_share_quota` or use Premium tier
- **Network access issues**: Review `network_rules` configuration
- **Permission errors**: Ensure proper Azure RBAC permissions

## Documentation

- [Azure File Sync Documentation](https://docs.microsoft.com/azure/storage/files/storage-sync-files-deployment-guide)
- [Azure Files Documentation](https://docs.microsoft.com/azure/storage/files/)
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm)

## Support

For issues with this Terraform configuration, refer to:
- The original recipe documentation
- Azure File Sync troubleshooting guides
- Terraform AzureRM provider documentation