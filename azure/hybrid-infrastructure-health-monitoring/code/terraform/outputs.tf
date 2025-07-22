# Output values for Azure Infrastructure Health Monitoring solution
# These outputs provide essential information for integration and verification

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all infrastructure health monitoring resources"
  value       = azurerm_resource_group.health_monitor.name
}

output "resource_group_location" {
  description = "Azure region where the infrastructure health monitoring resources are deployed"
  value       = azurerm_resource_group.health_monitor.location
}

# Azure Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App for infrastructure health monitoring"
  value       = azurerm_linux_function_app.health_monitor.name
}

output "function_app_default_hostname" {
  description = "Default hostname of the Azure Function App"
  value       = azurerm_linux_function_app.health_monitor.default_hostname
}

output "function_app_id" {
  description = "Resource ID of the Azure Function App"
  value       = azurerm_linux_function_app.health_monitor.id
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = var.enable_system_assigned_identity ? azurerm_linux_function_app.health_monitor.identity[0].principal_id : null
  sensitive   = true
}

output "function_app_service_plan_id" {
  description = "Resource ID of the Function App's service plan (Flex Consumption)"
  value       = azurerm_service_plan.health_monitor.id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account used by the Function App"
  value       = azurerm_storage_account.health_monitor.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.health_monitor.primary_blob_endpoint
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault for secure configuration storage"
  value       = azurerm_key_vault.health_monitor.name
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.health_monitor.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault for application configuration"
  value       = azurerm_key_vault.health_monitor.vault_uri
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for monitoring and logging"
  value       = azurerm_log_analytics_workspace.health_monitor.name
}

output "log_analytics_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.health_monitor.workspace_id
  sensitive   = true
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.health_monitor.primary_shared_key
  sensitive   = true
}

# Application Insights Information
output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.health_monitor[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.health_monitor[0].connection_string : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.health_monitor[0].app_id : null
}

# Event Grid Information
output "event_grid_topic_name" {
  description = "Name of the Event Grid topic for health monitoring events"
  value       = azurerm_eventgrid_topic.health_updates.name
}

output "event_grid_topic_endpoint" {
  description = "Endpoint URL of the Event Grid topic"
  value       = azurerm_eventgrid_topic.health_updates.endpoint
}

output "event_grid_topic_id" {
  description = "Resource ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.health_updates.id
}

output "event_grid_primary_access_key" {
  description = "Primary access key for the Event Grid topic"
  value       = azurerm_eventgrid_topic.health_updates.primary_access_key
  sensitive   = true
}

# Virtual Network Information
output "virtual_network_name" {
  description = "Name of the virtual network (if VNet integration is enabled)"
  value       = var.enable_vnet_integration ? azurerm_virtual_network.health_monitor[0].name : null
}

output "virtual_network_id" {
  description = "Resource ID of the virtual network (if VNet integration is enabled)"
  value       = var.enable_vnet_integration ? azurerm_virtual_network.health_monitor[0].id : null
}

output "function_subnet_id" {
  description = "Resource ID of the Function App subnet (if VNet integration is enabled)"
  value       = var.enable_vnet_integration ? azurerm_subnet.functions[0].id : null
}

# Event Grid Subscriptions Information
output "update_manager_subscription_name" {
  description = "Name of the Event Grid subscription for Update Manager events"
  value       = azurerm_eventgrid_event_subscription.update_manager_events.name
}

output "health_events_subscription_name" {
  description = "Name of the Event Grid subscription for health monitoring events"
  value       = azurerm_eventgrid_event_subscription.health_events.name
}

# Function App Webhook Endpoints
output "health_checker_webhook_url" {
  description = "Webhook URL for the HealthChecker function (for manual triggering)"
  value       = "https://${azurerm_linux_function_app.health_monitor.default_hostname}/api/HealthChecker"
}

output "update_event_handler_webhook_url" {
  description = "Webhook URL for the UpdateEventHandler function"
  value       = "https://${azurerm_linux_function_app.health_monitor.default_hostname}/runtime/webhooks/eventgrid?functionName=UpdateEventHandler"
}

# Configuration Values
output "health_check_schedule" {
  description = "CRON expression for the health check timer trigger"
  value       = var.health_check_schedule
}

output "notification_channels" {
  description = "Configured notification channels for alerts"
  value       = var.notification_channels
}

# Deployment Information
output "deployment_environment" {
  description = "Environment tag applied to all resources"
  value       = var.environment
}

output "project_name" {
  description = "Project name used for resource naming and tagging"
  value       = var.project_name
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

# Management URLs
output "azure_portal_function_app_url" {
  description = "Azure Portal URL for the Function App management"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_linux_function_app.health_monitor.id}"
}

output "azure_portal_log_analytics_url" {
  description = "Azure Portal URL for Log Analytics workspace"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_log_analytics_workspace.health_monitor.id}"
}

output "azure_portal_event_grid_url" {
  description = "Azure Portal URL for Event Grid topic management"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_eventgrid_topic.health_updates.id}"
}

# Connection Strings and Keys (marked as sensitive)
output "storage_connection_string" {
  description = "Connection string for the storage account (stored in Key Vault)"
  value       = azurerm_storage_account.health_monitor.primary_connection_string
  sensitive   = true
}

# Verification Commands
output "function_app_verification_commands" {
  description = "Azure CLI commands to verify Function App deployment"
  value = {
    status_check = "az functionapp show --name ${azurerm_linux_function_app.health_monitor.name} --resource-group ${azurerm_resource_group.health_monitor.name} --query '{name:name, state:state, hostNames:hostNames}' --output table"
    vnet_check   = var.enable_vnet_integration ? "az functionapp vnet-integration list --name ${azurerm_linux_function_app.health_monitor.name} --resource-group ${azurerm_resource_group.health_monitor.name} --output table" : "VNet integration disabled"
    logs_check   = "az functionapp log tail --name ${azurerm_linux_function_app.health_monitor.name} --resource-group ${azurerm_resource_group.health_monitor.name}"
  }
}

output "event_grid_verification_commands" {
  description = "Azure CLI commands to verify Event Grid configuration"
  value = {
    topic_status      = "az eventgrid topic show --name ${azurerm_eventgrid_topic.health_updates.name} --resource-group ${azurerm_resource_group.health_monitor.name} --query '{name:name, provisioningState:provisioningState}' --output table"
    subscriptions     = "az eventgrid event-subscription list --source-resource-id '/subscriptions/${data.azurerm_client_config.current.subscription_id}' --output table"
    test_event        = "az eventgrid event publish --topic-name ${azurerm_eventgrid_topic.health_updates.name} --resource-group ${azurerm_resource_group.health_monitor.name} --events '[{\"eventType\":\"test\",\"subject\":\"test\",\"data\":{},\"dataVersion\":\"1.0\"}]'"
  }
}