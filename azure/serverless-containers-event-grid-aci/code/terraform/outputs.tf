# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources were created"
  value       = azurerm_resource_group.main.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the created storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the created storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_key" {
  description = "Primary access key of the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_containers" {
  description = "Names of the created storage containers"
  value = {
    input      = azurerm_storage_container.input.name
    output     = azurerm_storage_container.output.name
    deadletter = azurerm_storage_container.deadletter.name
  }
}

# Container Registry Information
output "container_registry_name" {
  description = "Name of the created container registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_id" {
  description = "ID of the created container registry"
  value       = azurerm_container_registry.main.id
}

output "container_registry_login_server" {
  description = "Login server of the container registry"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_admin_username" {
  description = "Admin username of the container registry"
  value       = azurerm_container_registry.main.admin_username
}

output "container_registry_admin_password" {
  description = "Admin password of the container registry"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

# Event Grid Topic Information
output "event_grid_topic_name" {
  description = "Name of the created Event Grid topic"
  value       = azurerm_eventgrid_topic.main.name
}

output "event_grid_topic_id" {
  description = "ID of the created Event Grid topic"
  value       = azurerm_eventgrid_topic.main.id
}

output "event_grid_topic_endpoint" {
  description = "Endpoint of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.endpoint
}

output "event_grid_topic_primary_access_key" {
  description = "Primary access key of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.primary_access_key
  sensitive   = true
}

# Function App Information
output "function_app_name" {
  description = "Name of the created function app"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the created function app"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the function app"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_webhook_url" {
  description = "Webhook URL for Event Grid integration"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/ProcessStorageEvent"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the function app managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

# Container Instance Information
output "container_instances" {
  description = "Information about created container instances"
  value = {
    event_processor = {
      name      = azurerm_container_group.event_processor.name
      id        = azurerm_container_group.event_processor.id
      fqdn      = azurerm_container_group.event_processor.fqdn
      ip_address = azurerm_container_group.event_processor.ip_address
    }
    image_processor = {
      name = azurerm_container_group.image_processor.name
      id   = azurerm_container_group.image_processor.id
    }
  }
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the created Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the created Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the created Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the created Application Insights instance"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key of the Application Insights instance"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string of the Application Insights instance"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# Event Grid Event Subscription Information
output "event_grid_subscription_name" {
  description = "Name of the created Event Grid event subscription"
  value       = azurerm_eventgrid_event_subscription.blob_events.name
}

output "event_grid_subscription_id" {
  description = "ID of the created Event Grid event subscription"
  value       = azurerm_eventgrid_event_subscription.blob_events.id
}

# Monitoring Information
output "action_group_name" {
  description = "Name of the created action group for alerts"
  value       = azurerm_monitor_action_group.container_alerts.name
}

output "action_group_id" {
  description = "ID of the created action group for alerts"
  value       = azurerm_monitor_action_group.container_alerts.id
}

output "metric_alerts" {
  description = "Information about created metric alerts"
  value = {
    cpu_usage = {
      name = azurerm_monitor_metric_alert.container_cpu_usage.name
      id   = azurerm_monitor_metric_alert.container_cpu_usage.id
    }
    memory_usage = {
      name = azurerm_monitor_metric_alert.container_memory_usage.name
      id   = azurerm_monitor_metric_alert.container_memory_usage.id
    }
  }
}

# Container Template Information
output "container_template_blob_url" {
  description = "URL of the container template stored in blob storage"
  value       = azurerm_storage_blob.container_template.url
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of key configuration values"
  value = {
    random_suffix                = random_string.suffix.result
    container_cpu               = var.container_cpu
    container_memory           = var.container_memory
    container_restart_policy   = var.container_restart_policy
    event_retention_time       = var.event_grid_event_retention_time
    max_delivery_attempts      = var.event_grid_max_delivery_attempts
    container_insights_enabled = var.enable_container_insights
    storage_encryption_enabled = var.enable_storage_encryption
    https_only_enabled         = var.enable_https_traffic_only
  }
}

# Testing Information
output "testing_information" {
  description = "Information useful for testing the deployed solution"
  value = {
    upload_test_file_command = "az storage blob upload --account-name ${azurerm_storage_account.main.name} --container-name input --name test-file.txt --file ./test-file.txt --auth-mode key"
    monitor_events_command   = "az monitor metrics list --resource ${azurerm_eventgrid_topic.main.id} --metric 'PublishedEvents' --interval PT1M"
    container_logs_command   = "az container logs --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_container_group.event_processor.name}"
    function_logs_command    = "az functionapp logs tail --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_linux_function_app.main.name}"
  }
}

# Cleanup Information
output "cleanup_information" {
  description = "Information for cleaning up resources"
  value = {
    resource_group_name = azurerm_resource_group.main.name
    cleanup_command     = "az group delete --name ${azurerm_resource_group.main.name} --yes --no-wait"
  }
}