# Outputs for Azure Expense Tracker Infrastructure
# This file defines the key information returned after successful deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# Cosmos DB Information
output "cosmos_db_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.expenses.name
}

output "cosmos_db_endpoint" {
  description = "Endpoint URL for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.expenses.endpoint
}

output "cosmos_db_database_name" {
  description = "Name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.expenses_db.name
}

output "cosmos_db_container_name" {
  description = "Name of the Cosmos DB container for expenses"
  value       = azurerm_cosmosdb_sql_container.expenses_container.name
}

output "cosmos_db_account_id" {
  description = "ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.expenses.id
}

# Cosmos DB Connection Information (Sensitive)
output "cosmos_db_primary_key" {
  description = "Primary key for Cosmos DB account (sensitive)"
  value       = azurerm_cosmosdb_account.expenses.primary_key
  sensitive   = true
}

output "cosmos_db_connection_string" {
  description = "Primary SQL connection string for Cosmos DB (sensitive)"
  value       = azurerm_cosmosdb_account.expenses.primary_sql_connection_string
  sensitive   = true
}

output "cosmos_db_secondary_key" {
  description = "Secondary key for Cosmos DB account (sensitive)"
  value       = azurerm_cosmosdb_account.expenses.secondary_key
  sensitive   = true
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account used by Function App"
  value       = azurerm_storage_account.functions.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.functions.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.functions.primary_blob_endpoint
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.expenses.name
}

output "function_app_hostname" {
  description = "Hostname of the Function App"
  value       = azurerm_linux_function_app.expenses.default_hostname
}

output "function_app_url" {
  description = "HTTPS URL of the Function App"
  value       = "https://${azurerm_linux_function_app.expenses.default_hostname}"
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.expenses.id
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.expenses.identity[0].principal_id
}

output "function_app_identity_tenant_id" {
  description = "Tenant ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.expenses.identity[0].tenant_id
}

# Service Plan Information
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.functions.name
}

output "service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.functions.id
}

output "service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.functions.sku_name
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance (if enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.functions[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive)"
  value       = var.enable_monitoring ? azurerm_application_insights.functions[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (sensitive)"
  value       = var.enable_monitoring ? azurerm_application_insights.functions[0].connection_string : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.functions[0].app_id : null
}

# Deployment Configuration Information
output "deployment_configuration" {
  description = "Key configuration information for application deployment"
  value = {
    function_app_name           = azurerm_linux_function_app.expenses.name
    cosmos_db_endpoint         = azurerm_cosmosdb_account.expenses.endpoint
    cosmos_db_database         = azurerm_cosmosdb_sql_database.expenses_db.name
    cosmos_db_container        = azurerm_cosmosdb_sql_container.expenses_container.name
    resource_group_name        = azurerm_resource_group.main.name
    location                   = azurerm_resource_group.main.location
    monitoring_enabled         = var.enable_monitoring
  }
}

# Function URLs (Available after function deployment)
output "function_endpoints" {
  description = "Information about Function App endpoints"
  value = {
    base_url = "https://${azurerm_linux_function_app.expenses.default_hostname}"
    api_endpoints = {
      create_expense = "https://${azurerm_linux_function_app.expenses.default_hostname}/api/CreateExpense"
      get_expenses   = "https://${azurerm_linux_function_app.expenses.default_hostname}/api/GetExpenses"
    }
    note = "Function URLs will be available after deploying function code"
  }
}

# Cost Management Information
output "cost_information" {
  description = "Information about the deployed resources for cost estimation"
  value = {
    cosmos_db_mode     = "Serverless (pay-per-request)"
    function_app_plan  = "Consumption (pay-per-execution)"
    storage_account    = "${var.storage_account_tier}_${var.storage_account_replication_type}"
    monitoring         = var.enable_monitoring ? "Application Insights enabled" : "Monitoring disabled"
    estimated_monthly_cost = "Approximately $1-5 USD for light usage patterns"
  }
}

# Security and Access Information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    cosmos_db_security = {
      network_access     = "Public (configure network rules as needed)"
      encryption_at_rest = "Enabled by default"
      backup_policy      = "Periodic (4 hours interval, 8 hours retention)"
    }
    function_app_security = {
      https_only         = azurerm_linux_function_app.expenses.https_only
      managed_identity   = "System-assigned identity enabled"
      auth_level        = "Function key required for API access"
    }
    storage_security = {
      min_tls_version   = azurerm_storage_account.functions.min_tls_version
      public_access     = "Disabled"
    }
  }
}

# Tags Applied
output "applied_tags" {
  description = "Tags applied to all resources"
  value       = local.common_tags
}