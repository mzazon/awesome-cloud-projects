# Outputs for Azure distributed cache warm-up workflow infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Container Apps Information
output "container_apps_environment_id" {
  description = "ID of the Container Apps environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_apps_environment_name" {
  description = "Name of the Container Apps environment"
  value       = azurerm_container_app_environment.main.name
}

output "coordinator_job_name" {
  description = "Name of the coordinator Container App job"
  value       = azurerm_container_app_job.coordinator.name
}

output "coordinator_job_id" {
  description = "ID of the coordinator Container App job"
  value       = azurerm_container_app_job.coordinator.id
}

output "worker_job_name" {
  description = "Name of the worker Container App job"
  value       = azurerm_container_app_job.worker.name
}

output "worker_job_id" {
  description = "ID of the worker Container App job"
  value       = azurerm_container_app_job.worker.id
}

# Redis Enterprise Information
output "redis_enterprise_cluster_name" {
  description = "Name of the Redis Enterprise cluster"
  value       = azurerm_redis_enterprise_cluster.main.name
}

output "redis_enterprise_cluster_id" {
  description = "ID of the Redis Enterprise cluster"
  value       = azurerm_redis_enterprise_cluster.main.id
}

output "redis_hostname" {
  description = "Hostname of the Redis Enterprise cluster"
  value       = azurerm_redis_enterprise_cluster.main.hostname
  sensitive   = false
}

output "redis_database_port" {
  description = "Port number for the Redis Enterprise database"
  value       = azurerm_redis_enterprise_database.main.port
}

output "redis_primary_access_key" {
  description = "Primary access key for Redis Enterprise database"
  value       = azurerm_redis_enterprise_database.main.primary_access_key
  sensitive   = true
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_primary_blob_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "coordination_container_name" {
  description = "Name of the coordination blob container"
  value       = azurerm_storage_container.coordination.name
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Container Registry Information
output "container_registry_name" {
  description = "Name of the Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_id" {
  description = "ID of the Container Registry"
  value       = azurerm_container_registry.main.id
}

output "container_registry_login_server" {
  description = "Login server URL for the Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_admin_username" {
  description = "Admin username for the Container Registry"
  value       = azurerm_container_registry.main.admin_username
  sensitive   = false
}

output "container_registry_admin_password" {
  description = "Admin password for the Container Registry"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

# Managed Identity Information
output "managed_identity_name" {
  description = "Name of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.container_apps.name
}

output "managed_identity_id" {
  description = "ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.container_apps.id
}

output "managed_identity_client_id" {
  description = "Client ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.container_apps.client_id
}

output "managed_identity_principal_id" {
  description = "Principal ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.container_apps.principal_id
}

# Log Analytics Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Monitoring Information
output "action_group_name" {
  description = "Name of the monitoring action group"
  value       = var.enable_monitoring_alerts ? azurerm_monitor_action_group.main[0].name : null
}

output "action_group_id" {
  description = "ID of the monitoring action group"
  value       = var.enable_monitoring_alerts ? azurerm_monitor_action_group.main[0].id : null
}

# Connection Information for Applications
output "redis_connection_string" {
  description = "Complete Redis connection string for applications"
  value       = "Server=${azurerm_redis_enterprise_cluster.main.hostname}:${azurerm_redis_enterprise_database.main.port};Password=${azurerm_redis_enterprise_database.main.primary_access_key};Database=0;Ssl=True"
  sensitive   = true
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

output "resource_name_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.name_suffix
}

# Configuration Values
output "worker_parallelism" {
  description = "Number of parallel worker instances configured"
  value       = var.worker_parallelism
}

output "coordinator_schedule" {
  description = "Cron schedule for the coordinator job"
  value       = var.coordinator_schedule
}

# Azure CLI Commands for Management
output "cli_commands" {
  description = "Useful Azure CLI commands for managing the deployed resources"
  value = {
    start_coordinator_job = "az containerapp job start --name ${azurerm_container_app_job.coordinator.name} --resource-group ${azurerm_resource_group.main.name}"
    start_worker_job      = "az containerapp job start --name ${azurerm_container_app_job.worker.name} --resource-group ${azurerm_resource_group.main.name}"
    list_job_executions   = "az containerapp job execution list --name ${azurerm_container_app_job.coordinator.name} --resource-group ${azurerm_resource_group.main.name}"
    view_logs            = "az containerapp logs show --name ${azurerm_container_app_job.coordinator.name} --resource-group ${azurerm_resource_group.main.name}"
    redis_info           = "az redis show --name ${azurerm_redis_enterprise_cluster.main.name} --resource-group ${azurerm_resource_group.main.name}"
  }
}

# Resource URLs for Azure Portal
output "azure_portal_urls" {
  description = "Direct URLs to view resources in Azure Portal"
  value = {
    resource_group     = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/overview"
    container_apps_env = "https://portal.azure.com/#@/resource${azurerm_container_app_environment.main.id}/overview"
    redis_cluster      = "https://portal.azure.com/#@/resource${azurerm_redis_enterprise_cluster.main.id}/overview"
    key_vault         = "https://portal.azure.com/#@/resource${azurerm_key_vault.main.id}/overview"
    storage_account   = "https://portal.azure.com/#@/resource${azurerm_storage_account.main.id}/overview"
    log_analytics     = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}/overview"
  }
}