# Output Values for Multi-Channel Communication Platform
# These outputs provide essential information for accessing and managing the deployed infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "The name of the resource group containing all communication platform resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "The Azure region where the resource group and resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Azure Communication Services Outputs
output "communication_service_name" {
  description = "The name of the Azure Communication Services resource"
  value       = azurerm_communication_service.main.name
}

output "communication_service_connection_string" {
  description = "The primary connection string for Azure Communication Services (sensitive)"
  value       = azurerm_communication_service.main.primary_connection_string
  sensitive   = true
}

output "communication_service_primary_key" {
  description = "The primary access key for Azure Communication Services (sensitive)"
  value       = azurerm_communication_service.main.primary_key
  sensitive   = true
}

output "communication_service_data_location" {
  description = "The data residency location for Azure Communication Services"
  value       = azurerm_communication_service.main.data_location
}

# Event Grid Topic Outputs
output "eventgrid_topic_name" {
  description = "The name of the Event Grid topic for communication events"
  value       = azurerm_eventgrid_topic.communication_events.name
}

output "eventgrid_topic_endpoint" {
  description = "The endpoint URL for the Event Grid topic"
  value       = azurerm_eventgrid_topic.communication_events.endpoint
}

output "eventgrid_topic_primary_key" {
  description = "The primary access key for the Event Grid topic (sensitive)"
  value       = azurerm_eventgrid_topic.communication_events.primary_access_key
  sensitive   = true
}

output "eventgrid_topic_id" {
  description = "The resource ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.communication_events.id
}

# Azure Function App Outputs
output "function_app_name" {
  description = "The name of the Azure Function App for message processing"
  value       = azurerm_linux_function_app.message_processor.name
}

output "function_app_hostname" {
  description = "The default hostname of the Function App"
  value       = azurerm_linux_function_app.message_processor.default_hostname
}

output "function_app_url" {
  description = "The HTTPS URL of the Function App"
  value       = "https://${azurerm_linux_function_app.message_processor.default_hostname}"
}

output "function_app_principal_id" {
  description = "The managed identity principal ID of the Function App"
  value       = azurerm_linux_function_app.message_processor.identity[0].principal_id
}

output "function_app_resource_id" {
  description = "The resource ID of the Function App"
  value       = azurerm_linux_function_app.message_processor.id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "The name of the storage account for Function App runtime"
  value       = azurerm_storage_account.function_storage.name
}

output "storage_account_primary_endpoint" {
  description = "The primary blob endpoint of the storage account"
  value       = azurerm_storage_account.function_storage.primary_blob_endpoint
}

output "storage_account_connection_string" {
  description = "The primary connection string for the storage account (sensitive)"
  value       = azurerm_storage_account.function_storage.primary_connection_string
  sensitive   = true
}

# Cosmos DB Outputs
output "cosmos_db_account_name" {
  description = "The name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_db_endpoint" {
  description = "The endpoint for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_db_primary_key" {
  description = "The primary master key for the Cosmos DB account (sensitive)"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

output "cosmos_db_connection_strings" {
  description = "The connection strings for the Cosmos DB account (sensitive)"
  value       = azurerm_cosmosdb_account.main.connection_strings
  sensitive   = true
}

output "cosmos_db_database_name" {
  description = "The name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.communication_db.name
}

output "cosmos_db_conversations_container" {
  description = "The name of the Conversations container in Cosmos DB"
  value       = azurerm_cosmosdb_sql_container.conversations.name
}

output "cosmos_db_messages_container" {
  description = "The name of the Messages container in Cosmos DB"
  value       = azurerm_cosmosdb_sql_container.messages.name
}

# Application Insights Outputs (conditional based on whether it's enabled)
output "application_insights_name" {
  description = "The name of the Application Insights instance (if enabled)"
  value       = var.enable_function_app_insights ? azurerm_application_insights.function_insights[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key for Application Insights (sensitive, if enabled)"
  value       = var.enable_function_app_insights ? azurerm_application_insights.function_insights[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The connection string for Application Insights (sensitive, if enabled)"
  value       = var.enable_function_app_insights ? azurerm_application_insights.function_insights[0].connection_string : null
  sensitive   = true
}

# Service Plan Outputs
output "app_service_plan_name" {
  description = "The name of the App Service Plan for the Function App"
  value       = azurerm_service_plan.function_plan.name
}

output "app_service_plan_sku" {
  description = "The SKU of the App Service Plan"
  value       = azurerm_service_plan.function_plan.sku_name
}

# Event Grid Subscription Outputs
output "eventgrid_subscription_name" {
  description = "The name of the Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.function_subscription.name
}

output "eventgrid_subscription_id" {
  description = "The resource ID of the Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.function_subscription.id
}

# Infrastructure Summary
output "deployment_summary" {
  description = "Summary of the deployed multi-channel communication platform"
  value = {
    resource_group    = azurerm_resource_group.main.name
    location         = azurerm_resource_group.main.location
    environment      = var.environment
    project_name     = var.project_name
    
    services = {
      communication_services = azurerm_communication_service.main.name
      event_grid_topic      = azurerm_eventgrid_topic.communication_events.name
      function_app          = azurerm_linux_function_app.message_processor.name
      cosmos_db_account     = azurerm_cosmosdb_account.main.name
      storage_account       = azurerm_storage_account.function_storage.name
    }
    
    endpoints = {
      function_app_url       = "https://${azurerm_linux_function_app.message_processor.default_hostname}"
      cosmos_db_endpoint     = azurerm_cosmosdb_account.main.endpoint
      eventgrid_endpoint     = azurerm_eventgrid_topic.communication_events.endpoint
      storage_blob_endpoint  = azurerm_storage_account.function_storage.primary_blob_endpoint
    }
  }
}

# Connection Information for External Applications
output "connection_information" {
  description = "Essential connection information for integrating with the communication platform"
  value = {
    # For application integration
    communication_endpoint = azurerm_communication_service.main.endpoint
    function_app_base_url  = "https://${azurerm_linux_function_app.message_processor.default_hostname}/api"
    eventgrid_topic_name   = azurerm_eventgrid_topic.communication_events.name
    
    # For data access
    cosmos_database_name           = azurerm_cosmosdb_sql_database.communication_db.name
    cosmos_conversations_container = azurerm_cosmosdb_sql_container.conversations.name
    cosmos_messages_container      = azurerm_cosmosdb_sql_container.messages.name
    
    # For monitoring (if enabled)
    application_insights_name = var.enable_function_app_insights ? azurerm_application_insights.function_insights[0].name : "Not enabled"
  }
}

# Random Suffix Used for Resource Names
output "resource_suffix" {
  description = "The random suffix used for resource names to ensure uniqueness"
  value       = random_string.suffix.result
}

# Tags Applied to Resources
output "applied_tags" {
  description = "The tags applied to all resources in this deployment"
  value       = local.common_tags
}