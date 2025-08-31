# Output values for Azure Data Collection API infrastructure
# These outputs provide essential information for testing and integration

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Function App outputs
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the Azure Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "api_base_url" {
  description = "Base URL for the REST API endpoints"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api"
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
  sensitive   = false
}

# Cosmos DB outputs
output "cosmos_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_account_id" {
  description = "ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.id
}

output "cosmos_endpoint" {
  description = "Endpoint URL of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_database_name" {
  description = "Name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.main.name
}

output "cosmos_container_name" {
  description = "Name of the Cosmos DB container"
  value       = azurerm_cosmosdb_sql_container.records.name
}

output "cosmos_primary_key" {
  description = "Primary access key for Cosmos DB"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

output "cosmos_connection_string" {
  description = "Primary SQL connection string for Cosmos DB"
  value       = azurerm_cosmosdb_account.main.primary_sql_connection_string
  sensitive   = true
}

output "cosmos_read_endpoints" {
  description = "Read endpoints for Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.read_endpoints
}

output "cosmos_write_endpoints" {
  description = "Write endpoints for Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.write_endpoints
}

# Storage Account outputs
output "storage_account_name" {
  description = "Name of the storage account for Functions"
  value       = azurerm_storage_account.functions.name
}

output "storage_account_id" {
  description = "ID of the storage account for Functions"
  value       = azurerm_storage_account.functions.id
}

output "storage_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.functions.primary_blob_endpoint
}

# Application Insights outputs
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
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

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = azurerm_application_insights.main.app_id
}

# Service Plan outputs
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# API Testing outputs
output "curl_test_commands" {
  description = "Example curl commands for testing the API"
  value = {
    create_record = "curl -X POST \"https://${azurerm_linux_function_app.main.default_hostname}/api/records\" -H \"Content-Type: application/json\" -d '{\"name\": \"Test Record\", \"category\": \"test\", \"description\": \"Testing the API\"}'"
    get_all_records = "curl -X GET \"https://${azurerm_linux_function_app.main.default_hostname}/api/records\""
    get_record = "curl -X GET \"https://${azurerm_linux_function_app.main.default_hostname}/api/records/{id}\""
    update_record = "curl -X PUT \"https://${azurerm_linux_function_app.main.default_hostname}/api/records/{id}\" -H \"Content-Type: application/json\" -d '{\"name\": \"Updated Record\", \"category\": \"updated\"}'"
    delete_record = "curl -X DELETE \"https://${azurerm_linux_function_app.main.default_hostname}/api/records/{id}\""
  }
}

# Resource tags
output "resource_tags" {
  description = "Tags applied to all resources"
  value       = var.tags
}

# Random suffix used for unique naming
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Summary information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group    = azurerm_resource_group.main.name
    function_app      = azurerm_linux_function_app.main.name
    cosmos_account    = azurerm_cosmosdb_account.main.name
    storage_account   = azurerm_storage_account.functions.name
    app_insights      = azurerm_application_insights.main.name
    api_url          = "https://${azurerm_linux_function_app.main.default_hostname}/api"
    location         = azurerm_resource_group.main.location
  }
}