# Outputs for Azure AI Foundry and Compute Fleet ML Scaling Infrastructure
# These outputs provide essential information for connecting to and managing the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

output "deployment_id" {
  description = "Unique deployment identifier"
  value       = local.suffix
}

# AI Foundry Hub Information
output "ai_foundry_hub_id" {
  description = "Resource ID of the AI Foundry hub"
  value       = azurerm_machine_learning_workspace.ai_foundry_hub.id
}

output "ai_foundry_hub_name" {
  description = "Name of the AI Foundry hub"
  value       = azurerm_machine_learning_workspace.ai_foundry_hub.name
}

output "ai_foundry_hub_workspace_url" {
  description = "URL of the AI Foundry hub workspace"
  value       = azurerm_machine_learning_workspace.ai_foundry_hub.workspace_url
}

output "ai_foundry_hub_discovery_url" {
  description = "Discovery URL of the AI Foundry hub"
  value       = azurerm_machine_learning_workspace.ai_foundry_hub.discovery_url
}

# AI Foundry Project Information
output "ai_foundry_project_id" {
  description = "Resource ID of the AI Foundry project"
  value       = azurerm_machine_learning_workspace.ai_foundry_project.id
}

output "ai_foundry_project_name" {
  description = "Name of the AI Foundry project"
  value       = azurerm_machine_learning_workspace.ai_foundry_project.name
}

output "ai_foundry_project_workspace_url" {
  description = "URL of the AI Foundry project workspace"
  value       = azurerm_machine_learning_workspace.ai_foundry_project.workspace_url
}

# Machine Learning Workspace Information
output "ml_workspace_id" {
  description = "Resource ID of the Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.ml_workspace.id
}

output "ml_workspace_name" {
  description = "Name of the Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.ml_workspace.name
}

output "ml_workspace_url" {
  description = "URL of the Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.ml_workspace.workspace_url
}

# Compute Fleet Information
output "compute_fleet_id" {
  description = "Resource ID of the Azure Compute Fleet"
  value       = azapi_resource.compute_fleet.id
}

output "compute_fleet_name" {
  description = "Name of the Azure Compute Fleet"
  value       = local.compute_fleet_name
}

# Storage Account Information
output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.ml_storage.id
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.ml_storage.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.ml_storage.primary_blob_endpoint
}

output "storage_account_primary_dfs_endpoint" {
  description = "Primary DFS endpoint of the storage account (Data Lake)"
  value       = azurerm_storage_account.ml_storage.primary_dfs_endpoint
}

# Key Vault Information
output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.ml_keyvault.id
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.ml_keyvault.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.ml_keyvault.vault_uri
}

# Application Insights Information
output "application_insights_id" {
  description = "Resource ID of Application Insights"
  value       = azurerm_application_insights.ml_insights.id
}

output "application_insights_name" {
  description = "Name of Application Insights"
  value       = azurerm_application_insights.ml_insights.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.ml_insights.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.ml_insights.connection_string
  sensitive   = true
}

# Log Analytics Workspace Information
output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.ml_logs.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.ml_logs.name
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.ml_logs.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.ml_logs.primary_shared_key
  sensitive   = true
}

# Container Registry Information
output "container_registry_id" {
  description = "Resource ID of the Container Registry"
  value       = azurerm_container_registry.ml_registry.id
}

output "container_registry_name" {
  description = "Name of the Container Registry"
  value       = azurerm_container_registry.ml_registry.name
}

output "container_registry_login_server" {
  description = "Login server URL of the Container Registry"
  value       = azurerm_container_registry.ml_registry.login_server
}

output "container_registry_admin_username" {
  description = "Admin username for the Container Registry"
  value       = azurerm_container_registry.ml_registry.admin_username
  sensitive   = true
}

output "container_registry_admin_password" {
  description = "Admin password for the Container Registry"
  value       = azurerm_container_registry.ml_registry.admin_password
  sensitive   = true
}

# Monitoring Information
output "action_group_id" {
  description = "Resource ID of the monitoring action group"
  value       = azurerm_monitor_action_group.ml_scaling_actions.id
}

output "action_group_name" {
  description = "Name of the monitoring action group"
  value       = azurerm_monitor_action_group.ml_scaling_actions.name
}

output "cpu_utilization_alert_id" {
  description = "Resource ID of the CPU utilization metric alert"
  value       = azurerm_monitor_metric_alert.cpu_utilization_alert.id
}

output "scaling_dashboard_id" {
  description = "Resource ID of the ML scaling dashboard workbook"
  value       = azurerm_application_insights_workbook.ml_scaling_dashboard.id
}

# Network Information (if private endpoints are enabled)
output "virtual_network_id" {
  description = "Resource ID of the virtual network (if created)"
  value       = var.network_configuration.enable_private_endpoints ? azurerm_virtual_network.ml_vnet[0].id : null
}

output "compute_subnet_id" {
  description = "Resource ID of the compute subnet (if created)"
  value       = var.network_configuration.enable_private_endpoints ? azurerm_subnet.compute_subnet[0].id : null
}

# Configuration Information
output "scaling_configuration" {
  description = "Applied scaling configuration"
  value       = var.scaling_configuration
}

output "agent_model_configuration" {
  description = "Applied agent model configuration"
  value       = var.agent_model_configuration
}

output "spot_instance_configuration" {
  description = "Applied spot instance configuration"
  value       = var.spot_instance_config
}

output "regular_instance_configuration" {
  description = "Applied regular instance configuration"
  value       = var.regular_instance_config
}

# Connection Information for CLI usage
output "cli_connection_info" {
  description = "Information for connecting via Azure CLI"
  value = {
    subscription_id      = data.azurerm_client_config.current.subscription_id
    tenant_id           = data.azurerm_client_config.current.tenant_id
    resource_group_name = azurerm_resource_group.main.name
    location           = azurerm_resource_group.main.location
    ai_foundry_hub     = azurerm_machine_learning_workspace.ai_foundry_hub.name
    ai_foundry_project = azurerm_machine_learning_workspace.ai_foundry_project.name
    ml_workspace       = azurerm_machine_learning_workspace.ml_workspace.name
    compute_fleet      = local.compute_fleet_name
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Azure CLI commands to get started with the deployed infrastructure"
  value = {
    set_subscription = "az account set --subscription ${data.azurerm_client_config.current.subscription_id}"
    list_workspaces = "az ml workspace list --resource-group ${azurerm_resource_group.main.name}"
    show_ai_foundry_hub = "az ml workspace show --name ${azurerm_machine_learning_workspace.ai_foundry_hub.name} --resource-group ${azurerm_resource_group.main.name}"
    show_compute_fleet = "az vm fleet show --name ${local.compute_fleet_name} --resource-group ${azurerm_resource_group.main.name}"
    view_logs = "az monitor log-analytics query --workspace ${azurerm_log_analytics_workspace.ml_logs.workspace_id} --analytics-query 'AzureActivity | limit 10'"
  }
}