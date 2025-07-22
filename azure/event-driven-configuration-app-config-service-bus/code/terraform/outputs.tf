# Output Values for Event-Driven Configuration Management Solution
# These outputs provide essential information for verification, integration, and management

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Azure App Configuration Outputs
output "app_configuration_name" {
  description = "Name of the Azure App Configuration store"
  value       = azurerm_app_configuration.main.name
}

output "app_configuration_id" {
  description = "ID of the Azure App Configuration store"
  value       = azurerm_app_configuration.main.id
}

output "app_configuration_endpoint" {
  description = "Endpoint URL of the Azure App Configuration store"
  value       = azurerm_app_configuration.main.endpoint
}

output "app_configuration_primary_read_key" {
  description = "Primary read-only access key for App Configuration"
  value       = azurerm_app_configuration.main.primary_read_key[0].connection_string
  sensitive   = true
}

output "app_configuration_primary_write_key" {
  description = "Primary read-write access key for App Configuration"
  value       = azurerm_app_configuration.main.primary_write_key[0].connection_string
  sensitive   = true
}

# Service Bus Namespace Outputs
output "service_bus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "service_bus_namespace_id" {
  description = "ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.id
}

output "service_bus_namespace_connection_string" {
  description = "Primary connection string for Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "service_bus_namespace_hostname" {
  description = "Hostname of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.hostname
}

# Service Bus Topic Outputs
output "service_bus_topic_name" {
  description = "Name of the Service Bus topic for configuration changes"
  value       = azurerm_servicebus_topic.configuration_changes.name
}

output "service_bus_topic_id" {
  description = "ID of the Service Bus topic"
  value       = azurerm_servicebus_topic.configuration_changes.id
}

# Service Bus Subscription Outputs
output "service_bus_subscriptions" {
  description = "Names of the Service Bus subscriptions"
  value = {
    web_services    = azurerm_servicebus_subscription.web_services.name
    api_services    = azurerm_servicebus_subscription.api_services.name
    worker_services = azurerm_servicebus_subscription.worker_services.name
  }
}

# Function App Outputs
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.config_processor.name
}

output "function_app_id" {
  description = "ID of the Azure Function App"
  value       = azurerm_linux_function_app.config_processor.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.config_processor.default_hostname
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.config_processor.identity[0].principal_id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account for Function App"
  value       = azurerm_storage_account.functions.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.functions.id
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.functions.primary_blob_endpoint
}

# Application Insights Outputs
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# Logic App Outputs (if enabled)
output "logic_app_name" {
  description = "Name of the Logic App workflow (if enabled)"
  value       = var.logic_app_enabled ? azurerm_logic_app_workflow.config_workflow[0].name : null
}

output "logic_app_id" {
  description = "ID of the Logic App workflow (if enabled)"
  value       = var.logic_app_enabled ? azurerm_logic_app_workflow.config_workflow[0].id : null
}

output "logic_app_trigger_url" {
  description = "Trigger URL for the Logic App workflow (if enabled)"
  value       = var.logic_app_enabled ? azurerm_logic_app_workflow.config_workflow[0].access_endpoint : null
  sensitive   = true
}

# Event Grid Outputs
output "event_grid_system_topic_name" {
  description = "Name of the Event Grid system topic"
  value       = azurerm_eventgrid_system_topic.app_config.name
}

output "event_grid_system_topic_id" {
  description = "ID of the Event Grid system topic"
  value       = azurerm_eventgrid_system_topic.app_config.id
}

output "event_grid_subscription_name" {
  description = "Name of the Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.config_changes_to_servicebus.name
}

# Sample Configuration Data
output "sample_configuration_keys" {
  description = "Sample configuration keys created in App Configuration"
  value = {
    for key, config in var.sample_configuration_keys : key => {
      value        = config.value
      content_type = config.content_type
    }
  }
}

output "sample_feature_flags" {
  description = "Sample feature flags created in App Configuration"
  value = {
    for key, flag in var.feature_flags : key => {
      enabled     = flag.enabled
      description = flag.description
    }
  }
}

# Random Suffix for Reference
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Connection Strings for Applications
output "connection_strings" {
  description = "Essential connection strings for application integration"
  value = {
    app_configuration = azurerm_app_configuration.main.primary_read_key[0].connection_string
    service_bus      = azurerm_servicebus_namespace.main.default_primary_connection_string
    application_insights = azurerm_application_insights.main.connection_string
  }
  sensitive = true
}

# Azure CLI Commands for Testing
output "testing_commands" {
  description = "Azure CLI commands for testing the deployed solution"
  value = {
    list_config_keys = "az appconfig kv list --name ${azurerm_app_configuration.main.name}"
    show_topic_status = "az servicebus topic show --name ${azurerm_servicebus_topic.configuration_changes.name} --namespace-name ${azurerm_servicebus_namespace.main.name} --resource-group ${azurerm_resource_group.main.name}"
    view_function_logs = "az functionapp logs tail --name ${azurerm_linux_function_app.config_processor.name} --resource-group ${azurerm_resource_group.main.name}"
    update_config_test = "az appconfig kv set --name ${azurerm_app_configuration.main.name} --key 'config/test/example' --value 'test-value'"
  }
}

# Resource URLs for Management
output "management_urls" {
  description = "Azure Portal URLs for managing deployed resources"
  value = {
    resource_group = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/overview"
    app_configuration = "https://portal.azure.com/#@/resource${azurerm_app_configuration.main.id}/overview"
    service_bus = "https://portal.azure.com/#@/resource${azurerm_servicebus_namespace.main.id}/overview"
    function_app = "https://portal.azure.com/#@/resource${azurerm_linux_function_app.config_processor.id}/overview"
    application_insights = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}/overview"
    logic_app = var.logic_app_enabled ? "https://portal.azure.com/#@/resource${azurerm_logic_app_workflow.config_workflow[0].id}/overview" : null
  }
}