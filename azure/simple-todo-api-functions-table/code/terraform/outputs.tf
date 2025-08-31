# =============================================================================
# Output Values
# =============================================================================
# This file defines the output values that will be displayed after deployment
# and can be used by other Terraform configurations or for integration purposes.

# Resource Group Outputs
output "resource_group_name" {
  description = "The name of the resource group containing all resources"
  value       = azurerm_resource_group.todo_api.name
}

output "resource_group_location" {
  description = "The Azure region where resources are deployed"
  value       = azurerm_resource_group.todo_api.location
}

output "resource_group_id" {
  description = "The resource ID of the resource group"
  value       = azurerm_resource_group.todo_api.id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "The name of the storage account"
  value       = azurerm_storage_account.todo_api.name
}

output "storage_account_id" {
  description = "The resource ID of the storage account"
  value       = azurerm_storage_account.todo_api.id
}

output "storage_account_primary_blob_endpoint" {
  description = "The primary blob endpoint for the storage account"
  value       = azurerm_storage_account.todo_api.primary_blob_endpoint
}

output "storage_account_primary_table_endpoint" {
  description = "The primary table endpoint for the storage account"
  value       = azurerm_storage_account.todo_api.primary_table_endpoint
}

output "storage_account_primary_connection_string" {
  description = "The primary connection string for the storage account"
  value       = azurerm_storage_account.todo_api.primary_connection_string
  sensitive   = true
}

# Table Storage Outputs
output "storage_table_name" {
  description = "The name of the storage table for todo items"
  value       = azurerm_storage_table.todos.name
}

output "storage_table_id" {
  description = "The resource ID of the storage table"
  value       = azurerm_storage_table.todos.id
}

output "storage_table_url" {
  description = "The URL of the storage table"
  value       = "https://${azurerm_storage_account.todo_api.name}.table.core.windows.net/${azurerm_storage_table.todos.name}"
}

# Function App Service Plan Outputs
output "service_plan_name" {
  description = "The name of the App Service Plan"
  value       = azurerm_service_plan.todo_api.name
}

output "service_plan_id" {
  description = "The resource ID of the App Service Plan"
  value       = azurerm_service_plan.todo_api.id
}

output "service_plan_sku_name" {
  description = "The SKU name of the App Service Plan"
  value       = azurerm_service_plan.todo_api.sku_name
}

output "service_plan_kind" {
  description = "The kind of the App Service Plan"
  value       = azurerm_service_plan.todo_api.kind
}

# Function App Outputs
output "function_app_name" {
  description = "The name of the Function App"
  value       = azurerm_windows_function_app.todo_api.name
}

output "function_app_id" {
  description = "The resource ID of the Function App"
  value       = azurerm_windows_function_app.todo_api.id
}

output "function_app_default_hostname" {
  description = "The default hostname for the Function App"
  value       = azurerm_windows_function_app.todo_api.default_hostname
}

output "function_app_url" {
  description = "The HTTPS URL of the Function App"
  value       = "https://${azurerm_windows_function_app.todo_api.default_hostname}"
}

output "function_app_api_base_url" {
  description = "The base URL for the Todo API endpoints"
  value       = "https://${azurerm_windows_function_app.todo_api.default_hostname}/api"
}

output "function_app_possible_outbound_ip_addresses" {
  description = "The possible outbound IP addresses for the Function App"
  value       = azurerm_windows_function_app.todo_api.possible_outbound_ip_addresses
}

output "function_app_site_credential" {
  description = "The site credentials for the Function App (for deployment)"
  value = {
    name     = azurerm_windows_function_app.todo_api.site_credential[0].name
    password = azurerm_windows_function_app.todo_api.site_credential[0].password
  }
  sensitive = true
}

# Application Insights Outputs (if enabled)
output "application_insights_name" {
  description = "The name of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.todo_api[0].name : null
}

output "application_insights_id" {
  description = "The resource ID of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.todo_api[0].id : null
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.todo_api[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The connection string for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.todo_api[0].connection_string : null
  sensitive   = true
}

output "application_insights_app_url" {
  description = "The URL to access Application Insights in the Azure portal"
  value       = var.enable_application_insights ? "https://portal.azure.com/#@/resource${azurerm_application_insights.todo_api[0].id}/overview" : null
}

# API Endpoint Documentation
output "api_endpoints" {
  description = "Documentation of available API endpoints"
  value = {
    create_todo = {
      method      = "POST"
      url         = "https://${azurerm_windows_function_app.todo_api.default_hostname}/api/todos"
      description = "Create a new todo item"
      body_example = jsonencode({
        title       = "Learn Azure Functions"
        description = "Complete the serverless tutorial"
        completed   = false
      })
    }
    get_todos = {
      method      = "GET"
      url         = "https://${azurerm_windows_function_app.todo_api.default_hostname}/api/todos"
      description = "Retrieve all todo items"
    }
    update_todo = {
      method      = "PUT"
      url         = "https://${azurerm_windows_function_app.todo_api.default_hostname}/api/todos/{id}"
      description = "Update an existing todo item by ID"
      body_example = jsonencode({
        title       = "Learn Azure Functions"
        description = "Complete the serverless tutorial"
        completed   = true
      })
    }
    delete_todo = {
      method      = "DELETE"
      url         = "https://${azurerm_windows_function_app.todo_api.default_hostname}/api/todos/{id}"
      description = "Delete a todo item by ID"
    }
  }
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployment"
  value = {
    project_name              = var.project_name
    environment              = var.environment
    location                 = var.location
    node_version             = var.node_version
    functions_runtime_version = var.functions_extension_version
    storage_replication      = var.storage_replication_type
    table_name               = var.table_name
    deployment_timestamp     = timestamp()
  }
}

# Cost Estimation Information
output "cost_estimation_info" {
  description = "Information to help estimate costs"
  value = {
    function_app_plan_type = var.function_app_service_plan_sku == "Y1" ? "Consumption (Pay-per-execution)" : "Dedicated/Premium"
    storage_tier          = var.storage_account_tier
    storage_replication   = var.storage_replication_type
    estimated_monthly_cost = var.function_app_service_plan_sku == "Y1" ? "$0.10-$2.00 for development workloads" : "Varies based on plan size"
  }
}

# Quick Access URLs for Azure Portal
output "azure_portal_urls" {
  description = "Quick access URLs to view resources in Azure Portal"
  value = {
    resource_group  = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.todo_api.name}/overview"
    function_app    = "https://portal.azure.com/#@/resource${azurerm_windows_function_app.todo_api.id}/overview"
    storage_account = "https://portal.azure.com/#@/resource${azurerm_storage_account.todo_api.id}/overview"
    storage_table   = "https://portal.azure.com/#@/resource${azurerm_storage_account.todo_api.id}/tableService"
  }
}

# Security and Configuration Summary
output "security_summary" {
  description = "Security configuration summary"
  value = {
    https_only_enabled              = var.https_only
    min_tls_version                = var.min_tls_version
    public_network_access_enabled  = var.public_network_access_enabled
    shared_access_key_enabled      = var.shared_access_key_enabled
    client_certificate_enabled     = var.client_certificate_enabled
    cors_allowed_origins           = var.cors_allowed_origins
  }
}