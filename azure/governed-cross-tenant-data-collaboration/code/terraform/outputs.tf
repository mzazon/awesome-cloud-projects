# =============================================
# PROVIDER TENANT OUTPUTS
# =============================================

output "provider_resource_group_name" {
  description = "Name of the provider resource group"
  value       = azurerm_resource_group.provider.name
}

output "provider_storage_account_name" {
  description = "Name of the provider storage account"
  value       = azurerm_storage_account.provider.name
}

output "provider_storage_account_id" {
  description = "ID of the provider storage account"
  value       = azurerm_storage_account.provider.id
}

output "provider_storage_primary_endpoint" {
  description = "Primary endpoint of the provider storage account"
  value       = azurerm_storage_account.provider.primary_blob_endpoint
}

output "provider_data_share_account_name" {
  description = "Name of the provider Data Share account"
  value       = azurerm_data_share_account.provider.name
}

output "provider_data_share_account_id" {
  description = "ID of the provider Data Share account"
  value       = azurerm_data_share_account.provider.id
}

output "provider_purview_account_name" {
  description = "Name of the provider Purview account"
  value       = azurerm_purview_account.provider.name
}

output "provider_purview_account_id" {
  description = "ID of the provider Purview account"
  value       = azurerm_purview_account.provider.id
}

output "provider_purview_endpoint" {
  description = "Endpoint URL of the provider Purview account"
  value       = "https://${azurerm_purview_account.provider.name}.purview.azure.com"
}

output "provider_purview_managed_identity_id" {
  description = "Managed identity ID of the provider Purview account"
  value       = azurerm_purview_account.provider.identity[0].principal_id
}

# =============================================
# CONSUMER TENANT OUTPUTS
# =============================================

output "consumer_resource_group_name" {
  description = "Name of the consumer resource group"
  value       = azurerm_resource_group.consumer.name
}

output "consumer_storage_account_name" {
  description = "Name of the consumer storage account"
  value       = azurerm_storage_account.consumer.name
}

output "consumer_storage_account_id" {
  description = "ID of the consumer storage account"
  value       = azurerm_storage_account.consumer.id
}

output "consumer_storage_primary_endpoint" {
  description = "Primary endpoint of the consumer storage account"
  value       = azurerm_storage_account.consumer.primary_blob_endpoint
}

output "consumer_data_share_account_name" {
  description = "Name of the consumer Data Share account"
  value       = azurerm_data_share_account.consumer.name
}

output "consumer_data_share_account_id" {
  description = "ID of the consumer Data Share account"
  value       = azurerm_data_share_account.consumer.id
}

output "consumer_purview_account_name" {
  description = "Name of the consumer Purview account"
  value       = azurerm_purview_account.consumer.name
}

output "consumer_purview_account_id" {
  description = "ID of the consumer Purview account"
  value       = azurerm_purview_account.consumer.id
}

output "consumer_purview_endpoint" {
  description = "Endpoint URL of the consumer Purview account"
  value       = "https://${azurerm_purview_account.consumer.name}.purview.azure.com"
}

output "consumer_purview_managed_identity_id" {
  description = "Managed identity ID of the consumer Purview account"
  value       = azurerm_purview_account.consumer.identity[0].principal_id
}

# =============================================
# DATA SHARE OUTPUTS
# =============================================

output "data_share_name" {
  description = "Name of the created data share"
  value       = azurerm_data_share.main.name
}

output "data_share_id" {
  description = "ID of the created data share"
  value       = azurerm_data_share.main.id
}

output "data_share_dataset_name" {
  description = "Name of the data share dataset"
  value       = azurerm_data_share_dataset_blob_storage.main.name
}

output "shared_container_name" {
  description = "Name of the shared storage container"
  value       = azurerm_storage_container.provider_shared_datasets.name
}

# =============================================
# NETWORKING OUTPUTS
# =============================================

output "virtual_network_name" {
  description = "Name of the virtual network (if private endpoints enabled)"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].name : null
}

output "virtual_network_id" {
  description = "ID of the virtual network (if private endpoints enabled)"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].id : null
}

output "storage_subnet_id" {
  description = "ID of the storage subnet (if private endpoints enabled)"
  value       = var.enable_private_endpoints ? azurerm_subnet.storage[0].id : null
}

output "purview_subnet_id" {
  description = "ID of the Purview subnet (if private endpoints enabled)"
  value       = var.enable_private_endpoints ? azurerm_subnet.purview[0].id : null
}

# =============================================
# MONITORING OUTPUTS
# =============================================

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if created)"
  value       = var.enable_diagnostic_settings && var.log_analytics_workspace_id == null ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace (if created)"
  value       = var.enable_diagnostic_settings && var.log_analytics_workspace_id == null ? azurerm_log_analytics_workspace.main[0].id : null
}

# =============================================
# CONFIGURATION OUTPUTS
# =============================================

output "tenant_configuration" {
  description = "Tenant configuration information for cross-tenant setup"
  value = {
    provider_tenant_id     = var.provider_tenant_id
    consumer_tenant_id     = var.consumer_tenant_id
    provider_subscription  = var.provider_subscription_id
    consumer_subscription  = var.consumer_subscription_id
    location              = var.location
    environment           = var.environment
  }
}

output "next_steps" {
  description = "Next steps for completing the cross-tenant data collaboration setup"
  value = {
    manual_steps = [
      "Configure cross-tenant access settings in Azure AD",
      "Set up B2B collaboration between tenants",
      "Configure Purview data sources and scanning",
      "Create data share invitations",
      "Set up automated synchronization schedules",
      "Configure data lineage tracking"
    ]
    azure_portal_links = {
      provider_purview_studio = "https://${azurerm_purview_account.provider.name}.purview.azure.com",
      consumer_purview_studio = "https://${azurerm_purview_account.consumer.name}.purview.azure.com",
      azure_ad_external_identities = "https://portal.azure.com/#blade/Microsoft_AAD_IAM/CompanyRelationshipsMenuBlade/CrossTenantAccessSettings"
    }
  }
}

# =============================================
# COST ESTIMATION OUTPUTS
# =============================================

output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    note = "Actual costs may vary based on usage patterns and region"
    components = {
      purview_accounts = "~$400-800/month (2 Standard_4 instances)"
      storage_accounts = "~$10-50/month (depends on data volume)"
      data_share_costs = "~$10-100/month (depends on sharing frequency)"
      log_analytics = "~$5-20/month (depends on log volume)"
      networking = var.enable_private_endpoints ? "~$20-50/month (private endpoints)" : "$0/month"
    }
    total_estimated_range = "$445-1020/month"
  }
}

# =============================================
# SECURITY CONFIGURATION OUTPUTS
# =============================================

output "security_configuration" {
  description = "Security configuration details"
  value = {
    storage_encryption = "Enabled (Microsoft-managed keys)"
    tls_version = "TLS 1.2 minimum"
    soft_delete_enabled = var.enable_soft_delete
    soft_delete_retention_days = var.soft_delete_retention_days
    versioning_enabled = var.enable_versioning
    private_endpoints_enabled = var.enable_private_endpoints
    managed_identities = {
      provider_purview = azurerm_purview_account.provider.identity[0].principal_id
      consumer_purview = azurerm_purview_account.consumer.identity[0].principal_id
      provider_datashare = azurerm_data_share_account.provider.identity[0].principal_id
      consumer_datashare = azurerm_data_share_account.consumer.identity[0].principal_id
    }
  }
}

# =============================================
# SAMPLE DATA OUTPUTS
# =============================================

output "sample_data_info" {
  description = "Information about the sample data created for testing"
  value = {
    blob_name = azurerm_storage_blob.sample_data.name
    blob_url = azurerm_storage_blob.sample_data.url
    container_name = azurerm_storage_container.provider_shared_datasets.name
    storage_account = azurerm_storage_account.provider.name
  }
}