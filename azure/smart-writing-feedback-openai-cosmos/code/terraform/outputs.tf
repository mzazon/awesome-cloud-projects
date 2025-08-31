# Outputs for Azure Smart Writing Feedback System
# This file defines output values that can be used for verification and integration

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

# Azure OpenAI Service Outputs
output "openai_service_name" {
  description = "Name of the Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_endpoint" {
  description = "Endpoint URL for Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_service_id" {
  description = "ID of the Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.id
}

output "gpt_model_deployment_name" {
  description = "Name of the deployed GPT model"
  value       = azurerm_cognitive_deployment.gpt_model.name
}

# Azure Cosmos DB Outputs
output "cosmos_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_endpoint" {
  description = "Endpoint URL for Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_database_name" {
  description = "Name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.main.name
}

output "cosmos_container_name" {
  description = "Name of the Cosmos DB container"
  value       = azurerm_cosmosdb_sql_container.feedback.name
}

output "cosmos_account_id" {
  description = "ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.id
}

# Azure Functions Outputs
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account for Functions"
  value       = azurerm_storage_account.functions.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.functions.id
}

# Application Insights Outputs (conditional)
output "application_insights_name" {
  description = "Name of Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : "Not enabled"
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : "Not enabled"
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : "Not enabled"
  sensitive   = true
}

# Service Plan Outputs
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.functions.name
}

output "service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.functions.id
}

# API Endpoints for Testing
output "analyze_writing_endpoint" {
  description = "HTTP endpoint for the writing analysis function"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/analyzeWriting"
}

# Sensitive Outputs for Integration
output "openai_primary_key" {
  description = "Primary access key for OpenAI Service (sensitive)"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "cosmos_primary_key" {
  description = "Primary access key for Cosmos DB (sensitive)"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

output "storage_primary_access_key" {
  description = "Primary access key for storage account (sensitive)"
  value       = azurerm_storage_account.functions.primary_access_key
  sensitive   = true
}

# Resource Tags
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group    = azurerm_resource_group.main.name
    location         = azurerm_resource_group.main.location
    openai_service   = azurerm_cognitive_account.openai.name
    cosmos_account   = azurerm_cosmosdb_account.main.name
    function_app     = azurerm_linux_function_app.main.name
    storage_account  = azurerm_storage_account.functions.name
    gpt_model        = azurerm_cognitive_deployment.gpt_model.name
    cosmos_database  = azurerm_cosmosdb_sql_database.main.name
    cosmos_container = azurerm_cosmosdb_sql_container.feedback.name
    environment      = var.environment
    project          = var.project_name
  }
}

# Connection Strings for Application Configuration
output "connection_strings" {
  description = "Connection strings for external integration (sensitive)"
  value = {
    openai_endpoint   = azurerm_cognitive_account.openai.endpoint
    cosmos_endpoint   = azurerm_cosmosdb_account.main.endpoint
    function_endpoint = "https://${azurerm_linux_function_app.main.default_hostname}"
  }
  sensitive = false
}

# Cost Estimation Information
output "cost_estimation_notes" {
  description = "Notes about cost estimation for deployed resources"
  value = {
    openai_sku            = var.openai_sku_name
    gpt_capacity          = var.gpt_deployment_capacity
    cosmos_db_throughput  = var.cosmos_database_throughput
    cosmos_container_throughput = var.cosmos_container_throughput
    function_plan         = "Consumption (Y1)"
    storage_tier          = var.storage_account_tier
    estimated_monthly_cost = "Estimated $15-25/month for development workloads"
  }
}