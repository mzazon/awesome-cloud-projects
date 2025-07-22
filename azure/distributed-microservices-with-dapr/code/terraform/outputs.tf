# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

# Container Apps Environment Information
output "container_apps_environment_id" {
  description = "ID of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_apps_environment_name" {
  description = "Name of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.name
}

output "container_apps_environment_default_domain" {
  description = "Default domain of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.default_domain
}

output "container_apps_environment_static_ip_address" {
  description = "Static IP address of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.static_ip_address
}

# Order Service Information
output "order_service_name" {
  description = "Name of the order service container app"
  value       = azurerm_container_app.order_service.name
}

output "order_service_fqdn" {
  description = "Fully qualified domain name of the order service"
  value       = azurerm_container_app.order_service.ingress[0].fqdn
}

output "order_service_url" {
  description = "Full HTTPS URL of the order service"
  value       = "https://${azurerm_container_app.order_service.ingress[0].fqdn}"
}

output "order_service_latest_revision_name" {
  description = "Name of the latest revision of the order service"
  value       = azurerm_container_app.order_service.latest_revision_name
}

# Inventory Service Information
output "inventory_service_name" {
  description = "Name of the inventory service container app"
  value       = azurerm_container_app.inventory_service.name
}

output "inventory_service_fqdn" {
  description = "Fully qualified domain name of the inventory service (internal)"
  value       = azurerm_container_app.inventory_service.ingress[0].fqdn
}

output "inventory_service_latest_revision_name" {
  description = "Name of the latest revision of the inventory service"
  value       = azurerm_container_app.inventory_service.latest_revision_name
}

# Service Bus Information
output "service_bus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "service_bus_namespace_fqdn" {
  description = "Fully qualified domain name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.endpoint
}

output "service_bus_topic_name" {
  description = "Name of the Service Bus topic"
  value       = azurerm_servicebus_topic.orders.name
}

output "service_bus_connection_string" {
  description = "Primary connection string for Service Bus (sensitive)"
  value       = azurerm_servicebus_namespace_authorization_rule.dapr.primary_connection_string
  sensitive   = true
}

# Cosmos DB Information
output "cosmos_db_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_db_endpoint" {
  description = "Endpoint of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_db_database_name" {
  description = "Name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.main.name
}

output "cosmos_db_container_name" {
  description = "Name of the Cosmos DB container"
  value       = azurerm_cosmosdb_sql_container.statestore.name
}

output "cosmos_db_primary_key" {
  description = "Primary key for Cosmos DB account (sensitive)"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

# Monitoring Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (sensitive)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# Dapr Component Information
output "dapr_pubsub_component_name" {
  description = "Name of the Dapr pub/sub component"
  value       = azurerm_container_app_environment_dapr_component.pubsub.name
}

output "dapr_statestore_component_name" {
  description = "Name of the Dapr state store component"
  value       = azurerm_container_app_environment_dapr_component.statestore.name
}

# Testing and Validation Information
output "order_service_test_url" {
  description = "URL for testing the order service"
  value       = "https://${azurerm_container_app.order_service.ingress[0].fqdn}/v1.0/invoke/order-service/method/orders"
}

output "dapr_service_invocation_example" {
  description = "Example of Dapr service invocation between services"
  value       = "curl -X POST http://localhost:3500/v1.0/invoke/${var.inventory_service_name}/method/check-inventory"
}

# Cost and Resource Summary
output "resource_summary" {
  description = "Summary of created Azure resources"
  value = {
    resource_group           = azurerm_resource_group.main.name
    container_apps_count     = 2
    service_bus_namespace    = azurerm_servicebus_namespace.main.name
    cosmos_db_account        = azurerm_cosmosdb_account.main.name
    key_vault               = azurerm_key_vault.main.name
    log_analytics_workspace = azurerm_log_analytics_workspace.main.name
    application_insights     = var.enable_application_insights ? azurerm_application_insights.main[0].name : "disabled"
    dapr_components_count   = 2
  }
}

# Generated Resource Names (with random suffix)
output "generated_resource_names" {
  description = "Names of resources with generated suffixes"
  value = {
    random_suffix           = random_string.suffix.result
    service_bus_namespace   = azurerm_servicebus_namespace.main.name
    cosmos_db_account       = azurerm_cosmosdb_account.main.name
    key_vault              = azurerm_key_vault.main.name
  }
}