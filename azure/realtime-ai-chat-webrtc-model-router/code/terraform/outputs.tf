# Outputs for Real-time AI Chat with WebRTC and Model Router

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Azure OpenAI Service Outputs
output "openai_service_name" {
  description = "Name of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_endpoint" {
  description = "Endpoint URL for Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_custom_subdomain" {
  description = "Custom subdomain for Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.custom_subdomain_name
}

output "openai_primary_key" {
  description = "Primary access key for Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_secondary_key" {
  description = "Secondary access key for Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.secondary_access_key
  sensitive   = true
}

# Model Deployment Information
output "gpt_4o_mini_deployment_name" {
  description = "Name of the GPT-4o-mini-realtime deployment"
  value       = azurerm_cognitive_deployment.gpt_4o_mini_realtime.name
}

output "gpt_4o_deployment_name" {
  description = "Name of the GPT-4o-realtime deployment"
  value       = azurerm_cognitive_deployment.gpt_4o_realtime.name
}

output "model_deployment_info" {
  description = "Comprehensive model deployment information"
  value = {
    gpt_4o_mini = {
      name     = azurerm_cognitive_deployment.gpt_4o_mini_realtime.name
      model    = azurerm_cognitive_deployment.gpt_4o_mini_realtime.model[0].name
      version  = azurerm_cognitive_deployment.gpt_4o_mini_realtime.model[0].version
      capacity = azurerm_cognitive_deployment.gpt_4o_mini_realtime.sku[0].capacity
    }
    gpt_4o = {
      name     = azurerm_cognitive_deployment.gpt_4o_realtime.name
      model    = azurerm_cognitive_deployment.gpt_4o_realtime.model[0].name
      version  = azurerm_cognitive_deployment.gpt_4o_realtime.model[0].version
      capacity = azurerm_cognitive_deployment.gpt_4o_realtime.sku[0].capacity
    }
  }
}

# SignalR Service Outputs
output "signalr_service_name" {
  description = "Name of the Azure SignalR service"
  value       = azurerm_signalr_service.main.name
}

output "signalr_hostname" {
  description = "Hostname of the SignalR service"
  value       = azurerm_signalr_service.main.hostname
}

output "signalr_primary_connection_string" {
  description = "Primary connection string for SignalR service"
  value       = azurerm_signalr_service.main.primary_connection_string
  sensitive   = true
}

output "signalr_secondary_connection_string" {
  description = "Secondary connection string for SignalR service"
  value       = azurerm_signalr_service.main.secondary_connection_string
  sensitive   = true
}

# Function App Outputs
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.router.name
}

output "function_app_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.router.default_hostname
}

output "function_app_url" {
  description = "Base URL of the Function App"
  value       = "https://${azurerm_linux_function_app.router.default_hostname}"
}

output "function_app_identity" {
  description = "Managed identity information for the Function App"
  value = {
    principal_id = azurerm_linux_function_app.router.identity[0].principal_id
    tenant_id    = azurerm_linux_function_app.router.identity[0].tenant_id
  }
}

# Function Endpoints
output "function_endpoints" {
  description = "URLs for the deployed function endpoints"
  value = {
    model_router    = "https://${azurerm_linux_function_app.router.default_hostname}/api/ModelRouter"
    signalr_info    = "https://${azurerm_linux_function_app.router.default_hostname}/api/SignalRInfo"
    signalr_messages = "https://${azurerm_linux_function_app.router.default_hostname}/api/SignalRMessages"
  }
}

# WebRTC Configuration
output "webrtc_endpoint" {
  description = "WebRTC endpoint URL based on deployment region"
  value = local.location_short == "eastus2" ? 
    "https://eastus2.realtimeapi-preview.ai.azure.com/v1/realtimertc" : 
    "https://swedencentral.realtimeapi-preview.ai.azure.com/v1/realtimertc"
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for Function App"
  value       = azurerm_storage_account.function_storage.name
}

output "storage_account_primary_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.function_storage.primary_access_key
  sensitive   = true
}

# Application Insights Information
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

# Log Analytics Workspace Information (if enabled)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace (if diagnostic logs enabled)"
  value       = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace (if diagnostic logs enabled)"
  value       = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

# Deployment Configuration Summary
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    resource_group     = azurerm_resource_group.main.name
    location          = azurerm_resource_group.main.location
    environment       = var.environment
    project_name      = var.project_name
    random_suffix     = local.random_suffix
    openai_models     = [
      azurerm_cognitive_deployment.gpt_4o_mini_realtime.name,
      azurerm_cognitive_deployment.gpt_4o_realtime.name
    ]
    signalr_mode      = azurerm_signalr_service.main.service_mode
    function_runtime  = "Node.js 18"
    diagnostic_logs   = var.enable_diagnostic_logs
  }
}

# Client Configuration (for application development)
output "client_configuration" {
  description = "Configuration values needed for client application development"
  value = {
    signalr_negotiate_url = "https://${azurerm_linux_function_app.router.default_hostname}/api/SignalRInfo"
    model_router_url     = "https://${azurerm_linux_function_app.router.default_hostname}/api/ModelRouter"
    webrtc_endpoint      = local.location_short == "eastus2" ? 
      "https://eastus2.realtimeapi-preview.ai.azure.com/v1/realtimertc" : 
      "https://swedencentral.realtimeapi-preview.ai.azure.com/v1/realtimertc"
    hub_name            = "ChatHub"
    api_version         = "2025-04-01-preview"
  }
}

# Cost Optimization Information
output "cost_optimization_info" {
  description = "Information about cost optimization features"
  value = {
    gpt_4o_mini_capacity = var.gpt_4o_mini_capacity
    gpt_4o_capacity     = var.gpt_4o_capacity
    estimated_cost_savings = "Up to 60% cost reduction for simple queries using GPT-4o-mini-realtime"
    monitoring_enabled   = var.enable_diagnostic_logs
    retention_days      = var.log_retention_days
  }
}