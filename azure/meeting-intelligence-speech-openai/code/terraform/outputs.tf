# Output values for Azure Meeting Intelligence Infrastructure
# These outputs provide essential information for integrating with the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group and deployed resources"
  value       = azurerm_resource_group.main.location
}

output "deployment_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.suffix
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for meeting recordings"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "meeting_recordings_container_name" {
  description = "Name of the blob container for meeting recordings"
  value       = azurerm_storage_container.meeting_recordings.name
}

output "meeting_recordings_container_url" {
  description = "URL of the blob container for meeting recordings"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.meeting_recordings.name}"
}

# Speech Services Information
output "speech_service_name" {
  description = "Name of the Azure Speech Services resource"
  value       = azurerm_cognitive_account.speech.name
}

output "speech_service_endpoint" {
  description = "Endpoint URL for Azure Speech Services"
  value       = azurerm_cognitive_account.speech.endpoint
}

output "speech_service_location" {
  description = "Location of the Speech Services resource"
  value       = azurerm_cognitive_account.speech.location
}

output "speech_service_key" {
  description = "Primary access key for Azure Speech Services"
  value       = azurerm_cognitive_account.speech.primary_access_key
  sensitive   = true
}

output "speech_service_custom_subdomain" {
  description = "Custom subdomain for Speech Services API access"
  value       = azurerm_cognitive_account.speech.custom_subdomain_name
}

# Azure OpenAI Service Information
output "openai_service_name" {
  description = "Name of the Azure OpenAI Service resource"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_service_endpoint" {
  description = "Endpoint URL for Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_service_location" {
  description = "Location of the OpenAI Service resource"
  value       = azurerm_cognitive_account.openai.location
}

output "openai_service_key" {
  description = "Primary access key for Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_deployment_name" {
  description = "Name of the GPT-4 model deployment"
  value       = azurerm_cognitive_deployment.gpt4.name
}

output "openai_model_info" {
  description = "Information about the deployed OpenAI model"
  value = {
    model_name    = azurerm_cognitive_deployment.gpt4.model[0].name
    model_version = azurerm_cognitive_deployment.gpt4.model[0].version
    model_format  = azurerm_cognitive_deployment.gpt4.model[0].format
    capacity      = azurerm_cognitive_deployment.gpt4.scale[0].capacity
  }
}

# Service Bus Information
output "servicebus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "servicebus_namespace_endpoint" {
  description = "Service Bus namespace endpoint"
  value       = "https://${azurerm_servicebus_namespace.main.name}.servicebus.windows.net/"
}

output "servicebus_connection_string" {
  description = "Primary connection string for Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "transcript_queue_name" {
  description = "Name of the transcript processing queue"
  value       = azurerm_servicebus_queue.transcript_processing.name
}

output "results_topic_name" {
  description = "Name of the meeting insights topic"
  value       = azurerm_servicebus_topic.meeting_insights.name
}

output "notification_subscription_name" {
  description = "Name of the notification subscription"
  value       = azurerm_servicebus_subscription.notifications.name
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_default_hostname" {
  description = "Default hostname for the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "Full URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_kind" {
  description = "Kind of the Function App (Linux function app)"
  value       = azurerm_linux_function_app.main.kind
}

output "function_app_identity" {
  description = "System-assigned managed identity of the Function App"
  value = {
    type         = azurerm_linux_function_app.main.identity[0].type
    principal_id = azurerm_linux_function_app.main.identity[0].principal_id
    tenant_id    = azurerm_linux_function_app.main.identity[0].tenant_id
  }
}

# App Service Plan Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

output "app_service_plan_os_type" {
  description = "Operating system type of the App Service Plan"
  value       = azurerm_service_plan.main.os_type
}

# Monitoring and Logging Information
output "application_insights_name" {
  description = "Name of the Application Insights resource"
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

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

# Configuration Information for Client Applications
output "function_app_configuration" {
  description = "Key configuration values for Function App integration"
  value = {
    speech_endpoint     = azurerm_cognitive_account.speech.endpoint
    openai_endpoint     = azurerm_cognitive_account.openai.endpoint
    deployment_name     = azurerm_cognitive_deployment.gpt4.name
    servicebus_endpoint = "https://${azurerm_servicebus_namespace.main.name}.servicebus.windows.net/"
    transcript_queue    = azurerm_servicebus_queue.transcript_processing.name
    results_topic       = azurerm_servicebus_topic.meeting_insights.name
    storage_account     = azurerm_storage_account.main.name
    container_name      = azurerm_storage_container.meeting_recordings.name
  }
  sensitive = false
}

# Resource URLs for Azure Portal Access
output "azure_portal_urls" {
  description = "Direct URLs to resources in Azure Portal"
  value = {
    resource_group = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/overview"
    function_app   = "https://portal.azure.com/#@/resource${azurerm_linux_function_app.main.id}/overview"
    storage_account = "https://portal.azure.com/#@/resource${azurerm_storage_account.main.id}/overview"
    speech_service = "https://portal.azure.com/#@/resource${azurerm_cognitive_account.speech.id}/overview"
    openai_service = "https://portal.azure.com/#@/resource${azurerm_cognitive_account.openai.id}/overview"
    servicebus     = "https://portal.azure.com/#@/resource${azurerm_servicebus_namespace.main.id}/overview"
    app_insights   = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}/overview"
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the deployed solution"
  value = {
    storage_tier = "Consider using 'Cool' or 'Archive' tiers for long-term meeting storage"
    function_plan = "Current plan: ${azurerm_service_plan.main.sku_name}. Consider Premium plans for consistent performance."
    cognitive_services = "Monitor usage to optimize Speech Services and OpenAI costs"
    retention_policy = "Review log retention settings to balance compliance and cost"
  }
}

# Security Recommendations
output "security_recommendations" {
  description = "Security recommendations for the deployed infrastructure"
  value = {
    network_access = "Consider implementing VNet integration and private endpoints for production"
    key_vault = "Store sensitive keys in Azure Key Vault instead of app settings"
    managed_identity = "Managed identity is enabled for Function App - use instead of keys where possible"
    tls_version = "TLS 1.2 is enforced for all services"
  }
}

# Testing Information
output "testing_instructions" {
  description = "Instructions for testing the deployed meeting intelligence solution"
  value = {
    upload_endpoint = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.meeting_recordings.name}"
    monitoring_url = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}/logs"
    function_logs = "Monitor Function App logs at: https://portal.azure.com/#@/resource${azurerm_linux_function_app.main.id}/logstream"
    service_bus_monitor = "Monitor Service Bus at: https://portal.azure.com/#@/resource${azurerm_servicebus_namespace.main.id}/overview"
  }
}

# Data source for current Azure configuration
data "azurerm_client_config" "current" {}