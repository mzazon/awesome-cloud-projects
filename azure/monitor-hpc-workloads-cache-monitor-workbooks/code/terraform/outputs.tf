# Output values for Azure HPC Cache and Monitor Workbooks deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.hpc_monitoring.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.hpc_monitoring.location
}

# HPC Cache Information
output "hpc_cache_name" {
  description = "Name of the HPC Cache"
  value       = azurerm_hpc_cache.hpc_cache.name
}

output "hpc_cache_id" {
  description = "Resource ID of the HPC Cache"
  value       = azurerm_hpc_cache.hpc_cache.id
}

output "hpc_cache_mount_addresses" {
  description = "Mount addresses for the HPC Cache"
  value       = azurerm_hpc_cache.hpc_cache.mount_addresses
}

output "hpc_cache_size_gb" {
  description = "Size of the HPC Cache in GB"
  value       = azurerm_hpc_cache.hpc_cache.cache_size_in_gb
}

output "hpc_cache_sku" {
  description = "SKU of the HPC Cache"
  value       = azurerm_hpc_cache.hpc_cache.sku_name
}

# Batch Account Information
output "batch_account_name" {
  description = "Name of the Batch Account"
  value       = azurerm_batch_account.hpc_batch.name
}

output "batch_account_id" {
  description = "Resource ID of the Batch Account"
  value       = azurerm_batch_account.hpc_batch.id
}

output "batch_account_endpoint" {
  description = "Endpoint URL of the Batch Account"
  value       = azurerm_batch_account.hpc_batch.account_endpoint
}

output "batch_pool_name" {
  description = "Name of the Batch Pool"
  value       = azurerm_batch_pool.hpc_pool.name
}

output "batch_pool_vm_size" {
  description = "VM size of the Batch Pool nodes"
  value       = azurerm_batch_pool.hpc_pool.vm_size
}

output "batch_pool_node_count" {
  description = "Number of nodes in the Batch Pool"
  value       = azurerm_batch_pool.hpc_pool.fixed_scale[0].target_dedicated_nodes
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the Storage Account"
  value       = azurerm_storage_account.hpc_storage.name
}

output "storage_account_id" {
  description = "Resource ID of the Storage Account"
  value       = azurerm_storage_account.hpc_storage.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the Storage Account"
  value       = azurerm_storage_account.hpc_storage.primary_blob_endpoint
}

output "storage_container_name" {
  description = "Name of the HPC data container"
  value       = azurerm_storage_container.hpc_container.name
}

# Networking Information
output "virtual_network_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.hpc_vnet.name
}

output "virtual_network_id" {
  description = "Resource ID of the Virtual Network"
  value       = azurerm_virtual_network.hpc_vnet.id
}

output "subnet_name" {
  description = "Name of the HPC subnet"
  value       = azurerm_subnet.hpc_subnet.name
}

output "subnet_id" {
  description = "Resource ID of the HPC subnet"
  value       = azurerm_subnet.hpc_subnet.id
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.hpc_workspace.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.hpc_workspace.id
}

output "log_analytics_workspace_resource_id" {
  description = "The Workspace (or Customer) ID for the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.hpc_workspace.workspace_id
}

# Workbook Information
output "workbook_name" {
  description = "Name of the Azure Monitor Workbook"
  value       = azurerm_application_insights_workbook.hpc_workbook.name
}

output "workbook_id" {
  description = "Resource ID of the Azure Monitor Workbook"
  value       = azurerm_application_insights_workbook.hpc_workbook.id
}

output "workbook_display_name" {
  description = "Display name of the Azure Monitor Workbook"
  value       = azurerm_application_insights_workbook.hpc_workbook.display_name
}

# Monitoring Information
output "action_group_name" {
  description = "Name of the Action Group for alerts"
  value       = var.enable_alerts ? azurerm_monitor_action_group.hpc_alerts[0].name : null
}

output "action_group_id" {
  description = "Resource ID of the Action Group"
  value       = var.enable_alerts ? azurerm_monitor_action_group.hpc_alerts[0].id : null
}

output "cache_hit_rate_alert_name" {
  description = "Name of the cache hit rate alert"
  value       = var.enable_alerts ? azurerm_monitor_metric_alert.low_cache_hit_rate[0].name : null
}

output "compute_utilization_alert_name" {
  description = "Name of the compute utilization alert"
  value       = var.enable_alerts ? azurerm_monitor_metric_alert.high_compute_utilization[0].name : null
}

# Connection Information
output "hpc_cache_connection_info" {
  description = "Connection information for HPC Cache"
  value = {
    cache_name      = azurerm_hpc_cache.hpc_cache.name
    mount_addresses = azurerm_hpc_cache.hpc_cache.mount_addresses
    namespace_path  = "/hpc-data"
  }
}

output "batch_connection_info" {
  description = "Connection information for Batch Account"
  value = {
    account_name = azurerm_batch_account.hpc_batch.name
    endpoint     = azurerm_batch_account.hpc_batch.account_endpoint
    pool_name    = azurerm_batch_pool.hpc_pool.name
  }
  sensitive = true
}

# Monitoring Dashboard URLs
output "azure_portal_workbook_url" {
  description = "URL to access the workbook in Azure Portal"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_application_insights_workbook.hpc_workbook.id}"
}

output "azure_portal_resource_group_url" {
  description = "URL to access the resource group in Azure Portal"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.hpc_monitoring.name}"
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    resource_group          = azurerm_resource_group.hpc_monitoring.name
    location               = azurerm_resource_group.hpc_monitoring.location
    hpc_cache_name         = azurerm_hpc_cache.hpc_cache.name
    hpc_cache_size_gb      = azurerm_hpc_cache.hpc_cache.cache_size_in_gb
    batch_account_name     = azurerm_batch_account.hpc_batch.name
    batch_pool_name        = azurerm_batch_pool.hpc_pool.name
    batch_node_count       = azurerm_batch_pool.hpc_pool.fixed_scale[0].target_dedicated_nodes
    storage_account_name   = azurerm_storage_account.hpc_storage.name
    workspace_name         = azurerm_log_analytics_workspace.hpc_workspace.name
    workbook_name          = azurerm_application_insights_workbook.hpc_workbook.display_name
    monitoring_enabled     = var.enable_monitoring
    alerts_enabled         = var.enable_alerts
    alert_email           = var.alert_email
  }
}

# CLI Commands for Validation
output "validation_commands" {
  description = "CLI commands to validate the deployment"
  value = {
    check_hpc_cache = "az hpc-cache show --resource-group ${azurerm_resource_group.hpc_monitoring.name} --name ${azurerm_hpc_cache.hpc_cache.name}"
    check_batch_pool = "az batch pool show --pool-id ${azurerm_batch_pool.hpc_pool.name} --account-name ${azurerm_batch_account.hpc_batch.name} --resource-group ${azurerm_resource_group.hpc_monitoring.name}"
    check_storage = "az storage account show --name ${azurerm_storage_account.hpc_storage.name} --resource-group ${azurerm_resource_group.hpc_monitoring.name}"
    check_workspace = "az monitor log-analytics workspace show --resource-group ${azurerm_resource_group.hpc_monitoring.name} --workspace-name ${azurerm_log_analytics_workspace.hpc_workspace.name}"
  }
}