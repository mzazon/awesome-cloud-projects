#
# Outputs for Azure simple daily quote generator
# These outputs provide important information about the deployed resources
#

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_table_endpoint
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "Resource ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "HTTPS URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

# Quote API Endpoint
output "quote_api_endpoint" {
  description = "Full URL to the quote API endpoint"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/quote-function"
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights resource"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# App Service Plan Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# Table Storage Information
output "quotes_table_name" {
  description = "Name of the quotes table in Table Storage"
  value       = azurerm_storage_table.quotes.name
}

output "quotes_table_url" {
  description = "URL of the quotes table"
  value       = "${azurerm_storage_account.main.primary_table_endpoint}${azurerm_storage_table.quotes.name}"
}

# Sample Data Information
output "sample_quotes_count" {
  description = "Number of sample quotes inserted into Table Storage"
  value       = length(azurerm_storage_table_entity.sample_quotes)
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of the deployed resources"
  value = {
    resource_group    = azurerm_resource_group.main.name
    storage_account   = azurerm_storage_account.main.name
    function_app      = azurerm_linux_function_app.main.name
    api_endpoint      = "https://${azurerm_linux_function_app.main.default_hostname}/api/quote-function"
    quotes_table      = azurerm_storage_table.quotes.name
    sample_quotes     = length(azurerm_storage_table_entity.sample_quotes)
    app_insights      = azurerm_application_insights.main.name
    location          = azurerm_resource_group.main.location
    resource_suffix   = local.resource_suffix
  }
}

# Testing Commands
output "testing_commands" {
  description = "Commands to test the deployed API"
  value = {
    curl_test         = "curl -s https://${azurerm_linux_function_app.main.default_hostname}/api/quote-function"
    curl_formatted    = "curl -s https://${azurerm_linux_function_app.main.default_hostname}/api/quote-function | jq '.'"
    function_logs     = "az functionapp log tail --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
    storage_entities  = "az storage entity query --table-name quotes --account-name ${azurerm_storage_account.main.name}"
  }
}

# Cost Management Information
output "cost_tags" {
  description = "Tags applied to resources for cost tracking"
  value       = local.common_tags
}

# Security Information
output "security_features" {
  description = "Security features enabled on the deployment"
  value = {
    https_only            = azurerm_storage_account.main.enable_https_traffic_only
    min_tls_version      = azurerm_storage_account.main.min_tls_version
    public_access_blocked = !azurerm_storage_account.main.allow_nested_items_to_be_public
    cors_enabled         = var.enable_cors
    cors_origins         = var.enable_cors ? var.cors_allowed_origins : []
    function_auth_level  = "anonymous"
  }
}