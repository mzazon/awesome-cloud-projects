# Output values for the stateful container workloads deployment

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

output "storage_account_name" {
  description = "Name of the created storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "file_share_name" {
  description = "Name of the Azure Files share"
  value       = azurerm_storage_share.main.name
}

output "file_share_url" {
  description = "URL of the Azure Files share"
  value       = azurerm_storage_share.main.url
}

output "container_registry_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_login_server" {
  description = "Login server URL for the Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_admin_username" {
  description = "Admin username for the Azure Container Registry"
  value       = azurerm_container_registry.main.admin_username
}

output "container_registry_admin_password" {
  description = "Admin password for the Azure Container Registry"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

output "postgres_container_group_name" {
  description = "Name of the PostgreSQL container group"
  value       = azurerm_container_group.postgres.name
}

output "postgres_container_ip_address" {
  description = "IP address of the PostgreSQL container group"
  value       = azurerm_container_group.postgres.ip_address
}

output "app_container_group_name" {
  description = "Name of the application container group"
  value       = azurerm_container_group.app.name
}

output "app_container_ip_address" {
  description = "IP address of the application container group"
  value       = azurerm_container_group.app.ip_address
}

output "app_container_fqdn" {
  description = "Fully qualified domain name of the application container"
  value       = azurerm_container_group.app.fqdn
}

output "app_container_url" {
  description = "URL to access the application container"
  value       = "http://${azurerm_container_group.app.fqdn}"
}

output "worker_container_group_name" {
  description = "Name of the worker container group"
  value       = azurerm_container_group.worker.name
}

output "worker_container_ip_address" {
  description = "IP address of the worker container group"
  value       = azurerm_container_group.worker.ip_address
}

output "monitored_app_container_group_name" {
  description = "Name of the monitored application container group"
  value       = azurerm_container_group.monitored_app.name
}

output "monitored_app_container_ip_address" {
  description = "IP address of the monitored application container group"
  value       = azurerm_container_group.monitored_app.ip_address
}

output "monitored_app_container_fqdn" {
  description = "Fully qualified domain name of the monitored application container"
  value       = azurerm_container_group.monitored_app.fqdn
}

output "monitored_app_container_url" {
  description = "URL to access the monitored application container"
  value       = "http://${azurerm_container_group.monitored_app.fqdn}"
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_log_analytics ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_log_analytics ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "deployment_summary" {
  description = "Summary of the deployed resources"
  value = {
    resource_group       = azurerm_resource_group.main.name
    storage_account     = azurerm_storage_account.main.name
    file_share          = azurerm_storage_share.main.name
    container_registry  = azurerm_container_registry.main.name
    postgres_container  = azurerm_container_group.postgres.name
    app_container       = azurerm_container_group.app.name
    worker_container    = azurerm_container_group.worker.name
    monitored_app       = azurerm_container_group.monitored_app.name
    log_analytics       = var.enable_log_analytics ? azurerm_log_analytics_workspace.main[0].name : "disabled"
    app_url            = "http://${azurerm_container_group.app.fqdn}"
    monitored_app_url  = "http://${azurerm_container_group.monitored_app.fqdn}"
  }
}

# Connection strings and configuration for applications
output "postgres_connection_string" {
  description = "Connection string for PostgreSQL database (without password)"
  value       = "postgresql://postgres@${azurerm_container_group.postgres.ip_address}:5432/${var.postgres_database}"
}

output "azure_files_mount_command" {
  description = "Command to mount Azure Files share locally for testing"
  value       = "sudo mount -t cifs //${azurerm_storage_account.main.name}.file.core.windows.net/${azurerm_storage_share.main.name} /mnt/azurefiles -o vers=3.0,username=${azurerm_storage_account.main.name},password=${azurerm_storage_account.main.primary_access_key},dir_mode=0777,file_mode=0777,serverino"
  sensitive   = true
}

output "container_logs_commands" {
  description = "Azure CLI commands to view container logs"
  value = {
    postgres_logs    = "az container logs --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_container_group.postgres.name}"
    app_logs         = "az container logs --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_container_group.app.name}"
    worker_logs      = "az container logs --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_container_group.worker.name}"
    monitored_logs   = "az container logs --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_container_group.monitored_app.name}"
  }
}

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    test_app_endpoint     = "curl -I http://${azurerm_container_group.app.fqdn}"
    test_monitored_endpoint = "curl -I http://${azurerm_container_group.monitored_app.fqdn}"
    check_file_share     = "az storage file list --share-name ${azurerm_storage_share.main.name} --account-name ${azurerm_storage_account.main.name} --output table"
    check_containers     = "az container list --resource-group ${azurerm_resource_group.main.name} --query '[].{Name:name,Status:containers[0].instanceView.currentState.state}' --output table"
  }
}