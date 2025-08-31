# Output values for the Business Intelligence Query Assistant infrastructure

# ================================
# Resource Group Information
# ================================

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# ================================
# Azure OpenAI Service Outputs
# ================================

output "openai_service_name" {
  description = "Name of the Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_endpoint" {
  description = "Endpoint URL for the Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_deployment_name" {
  description = "Name of the deployed OpenAI model"
  value       = azurerm_cognitive_deployment.gpt_model.name
}

output "openai_model_version" {
  description = "Version of the deployed OpenAI model"
  value       = azurerm_cognitive_deployment.gpt_model.model[0].version
}

# ================================
# SQL Database Outputs
# ================================

output "sql_server_name" {
  description = "Name of the SQL Server"
  value       = azurerm_mssql_server.main.name
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of the SQL Server"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_database_name" {
  description = "Name of the SQL Database"
  value       = azurerm_mssql_database.main.name
}

output "sql_admin_username" {
  description = "SQL Server administrator username"
  value       = var.sql_admin_username
}

# ================================
# Function App Outputs
# ================================

output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_url" {
  description = "Default hostname of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = var.enable_managed_identity ? azurerm_linux_function_app.main.identity[0].principal_id : null
}

# ================================
# Storage Account Outputs
# ================================

output "storage_account_name" {
  description = "Name of the storage account used by Function App"
  value       = azurerm_storage_account.function_storage.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.function_storage.primary_blob_endpoint
}

# ================================
# Application Insights Outputs
# ================================

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# ================================
# Network Configuration Outputs
# ================================

output "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access SQL Database"
  value       = var.allowed_ip_ranges
}

output "sql_firewall_rules" {
  description = "Names of created SQL firewall rules"
  value = concat(
    [azurerm_mssql_firewall_rule.allow_azure_services.name],
    [for rule in azurerm_mssql_firewall_rule.allowed_ips : rule.name]
  )
}

# ================================
# API Access Information
# ================================

output "query_processor_endpoint" {
  description = "Endpoint URL for the QueryProcessor function"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/QueryProcessor"
}

# ================================
# Configuration Summary
# ================================

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    resource_group     = azurerm_resource_group.main.name
    location          = azurerm_resource_group.main.location
    environment       = var.environment
    project_name      = var.project_name
    
    # Service endpoints
    openai_endpoint   = azurerm_cognitive_account.openai.endpoint
    function_app_url  = "https://${azurerm_linux_function_app.main.default_hostname}"
    sql_server_fqdn   = azurerm_mssql_server.main.fully_qualified_domain_name
    
    # Configuration details
    openai_model      = "${var.openai_model_name} (${var.openai_model_version})"
    sql_database_sku  = var.sql_database_sku
    runtime_stack     = "${var.function_app_runtime} ${var.function_app_runtime_version}"
    
    # Security features
    managed_identity_enabled = var.enable_managed_identity
    monitoring_enabled       = var.enable_application_insights
    
    # Cost optimization
    storage_replication = var.storage_account_replication_type
    function_plan_type  = "Consumption"
  }
}

# ================================
# Connection Strings (Sensitive)
# ================================

output "sql_connection_string" {
  description = "Connection string for SQL Database (for application configuration)"
  value       = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.main.name};Persist Security Info=False;User ID=${var.sql_admin_username};Password=${local.sql_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  sensitive   = true
}

# ================================
# Testing and Validation Information
# ================================

output "testing_instructions" {
  description = "Instructions for testing the deployed solution"
  value = {
    function_app_test_url = "https://${azurerm_linux_function_app.main.default_hostname}/api/QueryProcessor"
    sample_query = jsonencode({
      query = "Show me total revenue by country for all customers"
    })
    curl_example = "curl -X POST '${azurerm_linux_function_app.main.default_hostname}/api/QueryProcessor?code=<FUNCTION_KEY>' -H 'Content-Type: application/json' -d '{\"query\": \"Show me total revenue by country for all customers\"}'"
  }
}

# ================================
# Cost Estimation Information
# ================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD, approximate)"
  value = {
    azure_openai_service = "~$10-30 (depending on usage)"
    sql_database        = var.sql_database_sku == "Basic" ? "~$5" : "~$15-100+"
    function_app        = "~$0-20 (consumption based)"
    storage_account     = "~$1-5"
    application_insights = var.enable_application_insights ? "~$2-10" : "$0"
    total_estimated     = "~$18-165 per month"
    note               = "Costs vary based on usage patterns and selected SKUs"
  }
}

# ================================
# Resource Tags
# ================================

output "resource_tags" {
  description = "Tags applied to all resources"
  value       = local.common_tags
}