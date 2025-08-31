# Output Values for Smart Model Selection Infrastructure
# These outputs provide important information about the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

# AI Foundry (Cognitive Services) Information
output "ai_foundry_name" {
  description = "Name of the AI Foundry (Cognitive Services) resource"
  value       = azurerm_cognitive_account.ai_foundry.name
}

output "ai_foundry_endpoint" {
  description = "Endpoint URL for the AI Foundry resource"
  value       = azurerm_cognitive_account.ai_foundry.endpoint
}

output "ai_foundry_resource_id" {
  description = "Resource ID of the AI Foundry resource"
  value       = azurerm_cognitive_account.ai_foundry.id
}

# AI Foundry Keys (Sensitive)
output "ai_foundry_primary_key" {
  description = "Primary access key for AI Foundry"
  value       = azurerm_cognitive_account.ai_foundry.primary_access_key
  sensitive   = true
}

output "ai_foundry_secondary_key" {
  description = "Secondary access key for AI Foundry"
  value       = azurerm_cognitive_account.ai_foundry.secondary_access_key
  sensitive   = true
}

# Model Router Deployment Information
output "model_router_deployment_name" {
  description = "Name of the Model Router deployment"
  value       = azurerm_cognitive_deployment.model_router.name
}

output "model_router_deployment_id" {
  description = "Resource ID of the Model Router deployment"
  value       = azurerm_cognitive_deployment.model_router.id
}

output "model_router_capacity" {
  description = "Capacity of the Model Router deployment"
  value       = azurerm_cognitive_deployment.model_router.scale[0].capacity
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_resource_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_table_endpoint" {
  description = "Primary table endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_table_endpoint
}

# Storage Connection String (Sensitive)
output "storage_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

# Storage Tables Information
output "model_metrics_table_name" {
  description = "Name of the model metrics storage table"
  value       = azurerm_storage_table.model_metrics.name
}

output "cost_tracking_table_name" {
  description = "Name of the cost tracking storage table"
  value       = azurerm_storage_table.cost_tracking.name
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_resource_id" {
  description = "Resource ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "Base URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

# Function App URLs for API endpoints
output "model_selection_endpoint_url" {
  description = "URL for the ModelSelection function endpoint"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/ModelSelection"
}

output "analytics_dashboard_endpoint_url" {
  description = "URL for the AnalyticsDashboard function endpoint"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/AnalyticsDashboard"
}

# Service Plan Information
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# Application Insights Information (Conditional)
output "application_insights_name" {
  description = "Name of the Application Insights resource"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_resource_id" {
  description = "Resource ID of the Application Insights resource"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].id : null
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

# Managed Identity Information
output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = var.enable_system_assigned_identity ? azurerm_linux_function_app.main.identity[0].principal_id : null
}

output "function_app_tenant_id" {
  description = "Tenant ID of the Function App's managed identity"
  value       = var.enable_system_assigned_identity ? azurerm_linux_function_app.main.identity[0].tenant_id : null
}

# Private Endpoints Information (Conditional)
output "ai_foundry_private_endpoint_id" {
  description = "Resource ID of the AI Foundry private endpoint"
  value       = var.enable_private_endpoints ? azurerm_private_endpoint.ai_foundry[0].id : null
}

output "storage_private_endpoint_id" {
  description = "Resource ID of the Storage Account private endpoint"
  value       = var.enable_private_endpoints ? azurerm_private_endpoint.storage[0].id : null
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Environment and Configuration Information
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = var.location
}

# Cost and Resource Information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (approximate)"
  value = {
    ai_services = var.ai_services_sku == "S0" ? "Variable based on usage (Model Router pricing)" : "Free tier"
    function_app = var.function_app_plan_sku == "Y1" ? "First 1M executions free, then pay-per-use" : "Fixed monthly cost based on plan"
    storage_account = "~$1-5 per month for standard usage"
    application_insights = var.enable_application_insights ? "First 5GB free per month, then pay-per-GB" : "Not enabled"
  }
}

# Security and Compliance Information
output "security_features_enabled" {
  description = "Security features that are enabled"
  value = {
    managed_identity = var.enable_system_assigned_identity
    private_endpoints = var.enable_private_endpoints
    application_insights = var.enable_application_insights
    storage_encryption = "Enabled by default"
    tls_version = "TLS 1.2 minimum"
    blob_versioning = "Enabled"
    soft_delete = "7 days retention"
  }
}

# Testing and Validation Information
output "testing_commands" {
  description = "Commands to test the deployed infrastructure"
  value = {
    model_selection_test = "curl -X POST '${azurerm_linux_function_app.main.default_hostname}/api/ModelSelection' -H 'Content-Type: application/json' -d '{\"message\": \"What is Azure?\", \"user_id\": \"test_user\"}'"
    analytics_dashboard_test = "curl '${azurerm_linux_function_app.main.default_hostname}/api/AnalyticsDashboard?days=7'"
    storage_table_check = "az storage entity query --table-name modelmetrics --connection-string '<connection_string>'"
  }
}

# Resource Tags
output "resource_tags" {
  description = "Tags applied to all resources"
  value       = var.tags
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of the deployed configuration"
  value = {
    ai_foundry_endpoint = azurerm_cognitive_account.ai_foundry.endpoint
    function_app_url = "https://${azurerm_linux_function_app.main.default_hostname}"
    model_router_deployed = true
    analytics_enabled = true
    monitoring_enabled = var.enable_application_insights
    private_networking = var.enable_private_endpoints
    backup_enabled = var.enable_backup
  }
}