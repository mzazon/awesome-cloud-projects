# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Azure OpenAI Service Information
output "openai_account_name" {
  description = "Name of the Azure OpenAI account"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_endpoint" {
  description = "Endpoint URL for Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_account_id" {
  description = "Resource ID of the Azure OpenAI account"
  value       = azurerm_cognitive_account.openai.id
}

output "openai_custom_subdomain" {
  description = "Custom subdomain for Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.custom_subdomain_name
}

# OpenAI Model Deployment Information
output "gpt_model_deployment_name" {
  description = "Name of the deployed GPT model"
  value       = azurerm_cognitive_deployment.gpt_model.name
}

output "gpt_model_deployment_id" {
  description = "Resource ID of the GPT model deployment"
  value       = azurerm_cognitive_deployment.gpt_model.id
}

# Azure Functions Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_url" {
  description = "Default hostname of the Azure Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_id" {
  description = "Resource ID of the Azure Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_possible_outbound_ip_addresses" {
  description = "Possible outbound IP addresses of the Function App"
  value       = split(",", azurerm_linux_function_app.main.possible_outbound_ip_addresses)
}

# Function endpoints for the AI assistant (constructed URLs)
output "customer_info_function_url" {
  description = "URL for the GetCustomerInfo function"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/GetCustomerInfo"
}

output "analytics_function_url" {
  description = "URL for the AnalyzeMetrics function"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/AnalyzeMetrics"
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

output "storage_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_containers" {
  description = "Names of created storage containers"
  value = {
    conversations  = azurerm_storage_container.conversations.name
    sessions      = azurerm_storage_container.sessions.name
    assistant_data = azurerm_storage_container.assistant_data.name
  }
}

# Application Insights Information (conditional)
output "application_insights_name" {
  description = "Name of Application Insights instance"
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

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

# Log Analytics Workspace Information (conditional)
output "log_analytics_workspace_name" {
  description = "Name of Log Analytics workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of Log Analytics workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].id : null
}

# Service Plan Information
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

# Connection Information for AI Assistant Setup
output "assistant_configuration" {
  description = "Configuration values needed for AI assistant setup"
  value = {
    openai_endpoint     = azurerm_cognitive_account.openai.endpoint
    openai_deployment   = azurerm_cognitive_deployment.gpt_model.name
    function_app_url    = "https://${azurerm_linux_function_app.main.default_hostname}"
    storage_account     = azurerm_storage_account.main.name
    resource_group      = azurerm_resource_group.main.name
    key_vault_uri       = azurerm_key_vault.main.vault_uri
  }
}

# Environment Variables for Function App Development
output "function_app_environment_variables" {
  description = "Environment variables configured for the Function App"
  value = {
    OPENAI_ENDPOINT           = azurerm_cognitive_account.openai.endpoint
    OPENAI_DEPLOYMENT_NAME    = azurerm_cognitive_deployment.gpt_model.name
    STORAGE_ACCOUNT_NAME      = azurerm_storage_account.main.name
    FUNCTIONS_EXTENSION_VERSION = var.functions_extension_version
    PYTHON_VERSION            = var.python_version
  }
}

# Sensitive Connection Strings (marked as sensitive)
output "storage_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "openai_primary_key" {
  description = "Primary access key for Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

# Resource Tags
output "resource_tags" {
  description = "Tags applied to all resources"
  value = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources for AI Assistant solution"
  value = {
    resource_group      = azurerm_resource_group.main.name
    location           = azurerm_resource_group.main.location
    openai_service     = azurerm_cognitive_account.openai.name
    function_app       = azurerm_linux_function_app.main.name
    storage_account    = azurerm_storage_account.main.name
    key_vault          = azurerm_key_vault.main.name
    monitoring_enabled = var.enable_application_insights
    containers_created = [
      azurerm_storage_container.conversations.name,
      azurerm_storage_container.sessions.name,
      azurerm_storage_container.assistant_data.name
    ]
    deployment_timestamp = timestamp()
  }
}

# Cost Estimation Information
output "cost_optimization_info" {
  description = "Information about cost optimization features enabled"
  value = {
    consumption_plan_enabled = true
    auto_scaling_enabled     = var.enable_auto_scale
    daily_memory_quota       = var.daily_memory_time_quota == 0 ? "unlimited" : "${var.daily_memory_time_quota} MB-seconds"
    storage_tier            = var.storage_account_tier
    storage_replication     = var.storage_replication_type
    openai_sku             = var.openai_sku_name
    log_retention_days     = var.log_retention_days
  }
}

# Security Configuration Summary
output "security_configuration" {
  description = "Summary of security configurations applied"
  value = {
    https_only_enabled      = var.enable_https_only
    minimum_tls_version     = var.minimum_tls_version
    managed_identity_enabled = true
    key_vault_integration   = true
    rbac_assignments       = [
      "Cognitive Services OpenAI User",
      "Storage Blob Data Contributor"
    ]
    network_security = {
      public_access_enabled = true
      cors_configured      = true
      allowed_origins      = var.allowed_origins
    }
  }
}