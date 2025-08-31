# Output Values for Azure File Sync Infrastructure
# These outputs provide essential information for server registration,
# monitoring, and integration with the deployed Azure File Sync solution

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.filesync.name
}

output "resource_group_id" {
  description = "Full resource ID of the created resource group"
  value       = azurerm_resource_group.filesync.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.filesync.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the created storage account"
  value       = azurerm_storage_account.filesync.name
}

output "storage_account_id" {
  description = "Full resource ID of the storage account"
  value       = azurerm_storage_account.filesync.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint URL for the storage account"
  value       = azurerm_storage_account.filesync.primary_file_endpoint
}

output "storage_account_primary_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.filesync.primary_access_key
  sensitive   = true
}

output "storage_account_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.filesync.primary_connection_string
  sensitive   = true
}

# Azure File Share Information
output "file_share_name" {
  description = "Name of the created Azure file share"
  value       = azurerm_storage_share.filesync.name
}

output "file_share_id" {
  description = "Full resource ID of the Azure file share"
  value       = azurerm_storage_share.filesync.id
}

output "file_share_url" {
  description = "URL of the Azure file share"
  value       = azurerm_storage_share.filesync.url
}

output "file_share_quota_gb" {
  description = "Quota of the Azure file share in GB"
  value       = azurerm_storage_share.filesync.quota
}

output "file_share_access_tier" {
  description = "Access tier of the Azure file share"
  value       = azurerm_storage_share.filesync.access_tier
}

# Storage Sync Service Information
output "storage_sync_service_name" {
  description = "Name of the created Storage Sync Service"
  value       = azurerm_storage_sync.filesync.name
}

output "storage_sync_service_id" {
  description = "Full resource ID of the Storage Sync Service"
  value       = azurerm_storage_sync.filesync.id
}

# Sync Group Information
output "sync_group_name" {
  description = "Name of the created sync group"
  value       = azurerm_storage_sync_group.filesync.name
}

output "sync_group_id" {
  description = "Full resource ID of the sync group"
  value       = azurerm_storage_sync_group.filesync.id
}

# Cloud Endpoint Information
output "cloud_endpoint_name" {
  description = "Name of the created cloud endpoint"
  value       = azurerm_storage_sync_cloud_endpoint.filesync.name
}

output "cloud_endpoint_id" {
  description = "Full resource ID of the cloud endpoint"
  value       = azurerm_storage_sync_cloud_endpoint.filesync.id
}

# Sample Files Information
output "sample_files_created" {
  description = "List of sample files created in the Azure file share"
  value = var.create_sample_files ? [
    for key, file in local.sample_files_with_timestamp : {
      name = file.path
      path = file.path
    }
  ] : []
}

# Server Registration Information
# This information is essential for registering Windows Servers with Azure File Sync
output "server_registration_info" {
  description = "Information needed for Azure File Sync server registration"
  value = {
    subscription_id           = data.azurerm_client_config.current.subscription_id
    tenant_id                = data.azurerm_client_config.current.tenant_id
    resource_group_name       = azurerm_resource_group.filesync.name
    storage_sync_service_name = azurerm_storage_sync.filesync.name
    storage_sync_service_id   = azurerm_storage_sync.filesync.id
    location                  = azurerm_resource_group.filesync.location
    sync_group_name          = azurerm_storage_sync_group.filesync.name
  }
}

# Connection Information for SMB Access
output "smb_connection_info" {
  description = "Information for connecting to the Azure file share via SMB"
  value = {
    file_share_url        = azurerm_storage_share.filesync.url
    storage_account_name  = azurerm_storage_account.filesync.name
    file_share_name       = azurerm_storage_share.filesync.name
    mount_command_windows = "net use Z: \\\\${azurerm_storage_account.filesync.name}.file.core.windows.net\\${azurerm_storage_share.filesync.name} /persistent:yes"
    mount_command_linux   = "sudo mount -t cifs //${azurerm_storage_account.filesync.name}.file.core.windows.net/${azurerm_storage_share.filesync.name} /mnt/azure-files -o vers=3.0,username=${azurerm_storage_account.filesync.name},password=<storage-key>,dir_mode=0777,file_mode=0777,serverino"
  }
}

# Monitoring and Management URLs
output "management_urls" {
  description = "Azure portal URLs for managing the File Sync resources"
  value = {
    resource_group_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_resource_group.filesync.id}"
    storage_account_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_storage_account.filesync.id}"
    file_share_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_storage_share.filesync.id}"
    storage_sync_service_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_storage_sync.filesync.id}"
    sync_group_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_storage_sync_group.filesync.id}"
  }
}

# Cost Information
output "estimated_monthly_costs" {
  description = "Information about estimated monthly costs for the deployed resources"
  value = {
    storage_account_note = "Storage costs vary based on data volume, access patterns, and replication type"
    file_share_note = "Azure Files pricing based on provisioned storage and transaction costs"
    sync_service_note = "Azure File Sync charges per registered server (first server free, additional servers ~$15/month)"
    data_transfer_note = "Data transfer costs apply for sync operations between on-premises and Azure"
    backup_note = "Additional costs if Azure Backup is enabled for the file share"
    pricing_calculator_url = "https://azure.microsoft.com/pricing/calculator/"
  }
}

# Security and Compliance Information
output "security_features" {
  description = "Security features enabled in the deployment"
  value = {
    https_only = azurerm_storage_account.filesync.https_traffic_only_enabled
    min_tls_version = azurerm_storage_account.filesync.min_tls_version
    encryption_in_transit = "Enabled (TLS 1.2+)"
    encryption_at_rest = "Enabled (Azure Storage Service Encryption)"
    network_access = "Configured to allow Azure services"
    shared_access_keys = "Enabled (required for Azure File Sync)"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps for completing the Azure File Sync setup"
  value = {
    step_1 = "Download and install Azure File Sync agent on Windows Server"
    step_2 = "Register Windows Server with the Storage Sync Service using the registration information above"
    step_3 = "Create server endpoints to define local folders for synchronization"
    step_4 = "Configure cloud tiering policies if desired for cost optimization"
    step_5 = "Monitor sync health and performance through Azure portal"
    documentation_url = "https://docs.microsoft.com/azure/storage/files/storage-sync-files-deployment-guide"
    agent_download_url = "https://go.microsoft.com/fwlink/?linkid=858257"
  }
}

# Terraform State Information
output "terraform_deployment_info" {
  description = "Information about the Terraform deployment"
  value = {
    deployment_time = timestamp()
    terraform_version = "Managed by Terraform"
    random_suffix_used = var.use_random_suffix
    random_suffix = var.use_random_suffix ? random_string.suffix[0].result : "none"
  }
}