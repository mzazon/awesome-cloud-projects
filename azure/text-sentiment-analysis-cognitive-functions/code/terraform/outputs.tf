# Outputs for the text sentiment analysis solution
# These outputs provide essential information for verification and integration

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

# Azure Cognitive Services Language Information
output "cognitive_services_name" {
  description = "Name of the Azure Cognitive Services Language resource"
  value       = azurerm_cognitive_account.language.name
}

output "cognitive_services_endpoint" {
  description = "Endpoint URL for the Azure Cognitive Services Language API"
  value       = azurerm_cognitive_account.language.endpoint
}

output "cognitive_services_id" {
  description = "ID of the Cognitive Services resource"
  value       = azurerm_cognitive_account.language.id
}

output "cognitive_services_primary_key" {
  description = "Primary access key for the Cognitive Services resource"
  value       = azurerm_cognitive_account.language.primary_access_key
  sensitive   = true
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account used by the Function App"
  value       = azurerm_storage_account.function_storage.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.function_storage.primary_blob_endpoint
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.function_storage.id
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.function_storage.primary_connection_string
  sensitive   = true
}

# App Service Plan Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.function_plan.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.function_plan.id
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.function_plan.sku_name
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.sentiment_function.name
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.sentiment_function.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.sentiment_function.default_hostname
}

output "function_app_site_credential" {
  description = "Site credentials for the Function App"
  value = {
    username = azurerm_linux_function_app.sentiment_function.site_credential[0].name
    password = azurerm_linux_function_app.sentiment_function.site_credential[0].password
  }
  sensitive = true
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.sentiment_function.identity[0].principal_id
}

output "function_app_identity_tenant_id" {
  description = "Tenant ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.sentiment_function.identity[0].tenant_id
}

# Function URLs (these would be available after function deployment)
output "function_base_url" {
  description = "Base URL for the Function App (functions need to be deployed separately)"
  value       = "https://${azurerm_linux_function_app.sentiment_function.default_hostname}"
}

output "sentiment_analysis_function_url" {
  description = "Expected URL for the sentiment analysis function (after deployment)"
  value       = "https://${azurerm_linux_function_app.sentiment_function.default_hostname}/api/analyze"
}

# Application Insights Information (conditional)
output "application_insights_name" {
  description = "Name of the Application Insights resource"
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

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].app_id : null
}

# Log Analytics Workspace Information (conditional)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

# Deployment Information
output "deployment_info" {
  description = "Summary of deployment information"
  value = {
    resource_group        = azurerm_resource_group.main.name
    location             = azurerm_resource_group.main.location
    function_app         = azurerm_linux_function_app.sentiment_function.name
    cognitive_services   = azurerm_cognitive_account.language.name
    storage_account      = azurerm_storage_account.function_storage.name
    python_version       = var.python_version
    sku                  = var.cognitive_services_sku
    function_timeout     = var.function_timeout_duration
    application_insights = var.enable_application_insights
  }
}

# Testing Information
output "testing_commands" {
  description = "Commands to test the sentiment analysis function"
  value = {
    positive_test = "curl -X POST '${azurerm_linux_function_app.sentiment_function.default_hostname}/api/analyze' -H 'Content-Type: application/json' -d '{\"text\": \"I love this product!\"}'"
    negative_test = "curl -X POST '${azurerm_linux_function_app.sentiment_function.default_hostname}/api/analyze' -H 'Content-Type: application/json' -d '{\"text\": \"This service is terrible.\"}'"
    mixed_test    = "curl -X POST '${azurerm_linux_function_app.sentiment_function.default_hostname}/api/analyze' -H 'Content-Type: application/json' -d '{\"text\": \"The product is great but delivery was slow.\"}'"
  }
}

# Cost Optimization Information
output "cost_optimization_notes" {
  description = "Notes about cost optimization for this deployment"
  value = {
    consumption_plan   = "Function App uses consumption plan - only pay for execution time"
    cognitive_services = "Language API SKU: ${var.cognitive_services_sku} - consider F0 (free tier) for development"
    storage_tier      = "Storage account uses ${var.storage_account_tier} tier with ${var.storage_account_replication_type} replication"
    monitoring        = var.enable_application_insights ? "Application Insights enabled - monitor costs" : "Application Insights disabled - cost optimized"
  }
}