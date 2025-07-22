# outputs.tf
# Output values for Azure real-time search application infrastructure

#------------------------------------------------------------
# Resource Group Information
#------------------------------------------------------------

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

#------------------------------------------------------------
# Azure Cognitive Search Service Outputs
#------------------------------------------------------------

output "search_service_name" {
  description = "Name of the Azure Cognitive Search service"
  value       = azurerm_search_service.main.name
}

output "search_service_endpoint" {
  description = "Endpoint URL for the Azure Cognitive Search service"
  value       = "https://${azurerm_search_service.main.name}.search.windows.net"
}

output "search_service_id" {
  description = "ID of the Azure Cognitive Search service"
  value       = azurerm_search_service.main.id
}

output "search_service_primary_key" {
  description = "Primary admin key for the Azure Cognitive Search service"
  value       = azurerm_search_service.main.primary_key
  sensitive   = true
}

output "search_service_secondary_key" {
  description = "Secondary admin key for the Azure Cognitive Search service"
  value       = azurerm_search_service.main.secondary_key
  sensitive   = true
}

output "search_service_query_keys" {
  description = "Query keys for the Azure Cognitive Search service"
  value       = azurerm_search_service.main.query_keys
  sensitive   = true
}

#------------------------------------------------------------
# Azure SignalR Service Outputs
#------------------------------------------------------------

output "signalr_service_name" {
  description = "Name of the Azure SignalR Service"
  value       = azurerm_signalr_service.main.name
}

output "signalr_service_hostname" {
  description = "Hostname of the Azure SignalR Service"
  value       = azurerm_signalr_service.main.hostname
}

output "signalr_service_id" {
  description = "ID of the Azure SignalR Service"
  value       = azurerm_signalr_service.main.id
}

output "signalr_service_public_port" {
  description = "Public port of the Azure SignalR Service"
  value       = azurerm_signalr_service.main.public_port
}

output "signalr_service_server_port" {
  description = "Server port of the Azure SignalR Service"
  value       = azurerm_signalr_service.main.server_port
}

output "signalr_primary_connection_string" {
  description = "Primary connection string for the Azure SignalR Service"
  value       = azurerm_signalr_service.main.primary_connection_string
  sensitive   = true
}

output "signalr_secondary_connection_string" {
  description = "Secondary connection string for the Azure SignalR Service"
  value       = azurerm_signalr_service.main.secondary_connection_string
  sensitive   = true
}

output "signalr_primary_access_key" {
  description = "Primary access key for the Azure SignalR Service"
  value       = azurerm_signalr_service.main.primary_access_key
  sensitive   = true
}

output "signalr_secondary_access_key" {
  description = "Secondary access key for the Azure SignalR Service"
  value       = azurerm_signalr_service.main.secondary_access_key
  sensitive   = true
}

#------------------------------------------------------------
# Azure Cosmos DB Outputs
#------------------------------------------------------------

output "cosmos_account_name" {
  description = "Name of the Azure Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_account_id" {
  description = "ID of the Azure Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.id
}

output "cosmos_account_endpoint" {
  description = "Endpoint URL of the Azure Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_database_name" {
  description = "Name of the Cosmos DB SQL database"
  value       = azurerm_cosmosdb_sql_database.main.name
}

output "cosmos_container_name" {
  description = "Name of the Cosmos DB SQL container"
  value       = azurerm_cosmosdb_sql_container.products.name
}

output "cosmos_primary_key" {
  description = "Primary key for the Azure Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

output "cosmos_secondary_key" {
  description = "Secondary key for the Azure Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.secondary_key
  sensitive   = true
}

output "cosmos_primary_readonly_key" {
  description = "Primary readonly key for the Azure Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.primary_readonly_key
  sensitive   = true
}

output "cosmos_secondary_readonly_key" {
  description = "Secondary readonly key for the Azure Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.secondary_readonly_key
  sensitive   = true
}

output "cosmos_connection_strings" {
  description = "Connection strings for the Azure Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.connection_strings
  sensitive   = true
}

output "cosmos_primary_sql_connection_string" {
  description = "Primary SQL connection string for the Azure Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.primary_sql_connection_string
  sensitive   = true
}

output "cosmos_secondary_sql_connection_string" {
  description = "Secondary SQL connection string for the Azure Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.secondary_sql_connection_string
  sensitive   = true
}

#------------------------------------------------------------
# Azure Storage Account Outputs
#------------------------------------------------------------

output "storage_account_name" {
  description = "Name of the Azure Storage Account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the Azure Storage Account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the Azure Storage Account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the Azure Storage Account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_account_secondary_connection_string" {
  description = "Secondary connection string for the Azure Storage Account"
  value       = azurerm_storage_account.main.secondary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the Azure Storage Account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_account_secondary_access_key" {
  description = "Secondary access key for the Azure Storage Account"
  value       = azurerm_storage_account.main.secondary_access_key
  sensitive   = true
}

#------------------------------------------------------------
# Azure Event Grid Outputs
#------------------------------------------------------------

output "event_grid_topic_name" {
  description = "Name of the Azure Event Grid topic"
  value       = azurerm_eventgrid_topic.main.name
}

output "event_grid_topic_id" {
  description = "ID of the Azure Event Grid topic"
  value       = azurerm_eventgrid_topic.main.id
}

output "event_grid_topic_endpoint" {
  description = "Endpoint of the Azure Event Grid topic"
  value       = azurerm_eventgrid_topic.main.endpoint
}

output "event_grid_topic_primary_access_key" {
  description = "Primary access key for the Azure Event Grid topic"
  value       = azurerm_eventgrid_topic.main.primary_access_key
  sensitive   = true
}

output "event_grid_topic_secondary_access_key" {
  description = "Secondary access key for the Azure Event Grid topic"
  value       = azurerm_eventgrid_topic.main.secondary_access_key
  sensitive   = true
}

output "event_grid_system_topic_id" {
  description = "ID of the Azure Event Grid system topic for storage"
  value       = var.enable_event_grid_system_topic ? azurerm_eventgrid_system_topic.storage[0].id : null
}

#------------------------------------------------------------
# Azure Function App Outputs
#------------------------------------------------------------

output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = local.function_app_name
}

output "function_app_id" {
  description = "ID of the Azure Function App"
  value       = var.function_app_os_type == "linux" ? azurerm_linux_function_app.main[0].id : azurerm_windows_function_app.main[0].id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Azure Function App"
  value       = var.function_app_os_type == "linux" ? azurerm_linux_function_app.main[0].default_hostname : azurerm_windows_function_app.main[0].default_hostname
}

output "function_app_outbound_ip_addresses" {
  description = "Outbound IP addresses of the Azure Function App"
  value       = var.function_app_os_type == "linux" ? azurerm_linux_function_app.main[0].outbound_ip_addresses : azurerm_windows_function_app.main[0].outbound_ip_addresses
}

output "function_app_possible_outbound_ip_addresses" {
  description = "Possible outbound IP addresses of the Azure Function App"
  value       = var.function_app_os_type == "linux" ? azurerm_linux_function_app.main[0].possible_outbound_ip_addresses : azurerm_windows_function_app.main[0].possible_outbound_ip_addresses
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = local.function_app_principal_id
}

output "function_app_tenant_id" {
  description = "Tenant ID of the Function App's managed identity"
  value       = var.function_app_os_type == "linux" ? azurerm_linux_function_app.main[0].identity[0].tenant_id : azurerm_windows_function_app.main[0].identity[0].tenant_id
}

#------------------------------------------------------------
# Azure App Service Plan Outputs
#------------------------------------------------------------

output "app_service_plan_name" {
  description = "Name of the Azure App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "ID of the Azure App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "app_service_plan_kind" {
  description = "Kind of the Azure App Service Plan"
  value       = azurerm_service_plan.main.kind
}

#------------------------------------------------------------
# Application Insights Outputs
#------------------------------------------------------------

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].id : null
}

output "application_insights_app_id" {
  description = "App ID of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].app_id : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

#------------------------------------------------------------
# Log Analytics Workspace Outputs
#------------------------------------------------------------

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].primary_shared_key : null
  sensitive   = true
}

output "log_analytics_workspace_secondary_shared_key" {
  description = "Secondary shared key of the Log Analytics workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].secondary_shared_key : null
  sensitive   = true
}

#------------------------------------------------------------
# Networking Outputs (if private endpoints enabled)
#------------------------------------------------------------

output "virtual_network_id" {
  description = "ID of the virtual network (if private endpoints enabled)"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].id : null
}

output "virtual_network_name" {
  description = "Name of the virtual network (if private endpoints enabled)"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].name : null
}

output "private_endpoints_subnet_id" {
  description = "ID of the private endpoints subnet (if private endpoints enabled)"
  value       = var.enable_private_endpoints ? azurerm_subnet.private_endpoints[0].id : null
}

output "search_private_endpoint_id" {
  description = "ID of the search service private endpoint (if private endpoints enabled)"
  value       = var.enable_private_endpoints ? azurerm_private_endpoint.search[0].id : null
}

output "signalr_private_endpoint_id" {
  description = "ID of the SignalR service private endpoint (if private endpoints enabled)"
  value       = var.enable_private_endpoints ? azurerm_private_endpoint.signalr[0].id : null
}

output "cosmos_private_endpoint_id" {
  description = "ID of the Cosmos DB private endpoint (if private endpoints enabled)"
  value       = var.enable_private_endpoints ? azurerm_private_endpoint.cosmos[0].id : null
}

#------------------------------------------------------------
# Deployment Summary Outputs
#------------------------------------------------------------

output "deployment_summary" {
  description = "Summary of deployed resources and their key endpoints"
  value = {
    resource_group_name      = azurerm_resource_group.main.name
    location                = azurerm_resource_group.main.location
    search_service_endpoint  = "https://${azurerm_search_service.main.name}.search.windows.net"
    signalr_service_hostname = azurerm_signalr_service.main.hostname
    cosmos_account_endpoint  = azurerm_cosmosdb_account.main.endpoint
    function_app_hostname    = var.function_app_os_type == "linux" ? azurerm_linux_function_app.main[0].default_hostname : azurerm_windows_function_app.main[0].default_hostname
    storage_account_endpoint = azurerm_storage_account.main.primary_blob_endpoint
    event_grid_topic_endpoint = azurerm_eventgrid_topic.main.endpoint
    application_insights_enabled = var.enable_application_insights
    private_endpoints_enabled = var.enable_private_endpoints
  }
}

#------------------------------------------------------------
# Next Steps Output
#------------------------------------------------------------

output "next_steps" {
  description = "Instructions for next steps after deployment"
  value = {
    step_1 = "Create search index using: az search index create --service-name ${azurerm_search_service.main.name} --name products-index"
    step_2 = "Deploy Function App code using: func azure functionapp publish ${local.function_app_name}"
    step_3 = "Test document upload to Cosmos DB container: ${azurerm_cosmosdb_sql_container.products.name}"
    step_4 = "Connect to SignalR endpoint: https://${azurerm_signalr_service.main.hostname}"
    step_5 = "Monitor logs in Application Insights: ${var.enable_application_insights ? azurerm_application_insights.main[0].app_id : "Not enabled"}"
  }
}

#------------------------------------------------------------
# Configuration URLs for Client Applications
#------------------------------------------------------------

output "client_configuration" {
  description = "Configuration endpoints and keys for client applications"
  value = {
    search_endpoint       = "https://${azurerm_search_service.main.name}.search.windows.net"
    signalr_negotiate_url = "https://${var.function_app_os_type == "linux" ? azurerm_linux_function_app.main[0].default_hostname : azurerm_windows_function_app.main[0].default_hostname}/api/negotiate"
    cosmos_endpoint       = azurerm_cosmosdb_account.main.endpoint
    function_app_base_url = "https://${var.function_app_os_type == "linux" ? azurerm_linux_function_app.main[0].default_hostname : azurerm_windows_function_app.main[0].default_hostname}"
  }
  sensitive = false
}