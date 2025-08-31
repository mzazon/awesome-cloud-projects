# Outputs for Real-time Status Notifications with SignalR and Functions
# These outputs provide essential information for verification, testing, and client configuration

# Resource Group Information
output "resource_group_name" {
  description = "The name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "The Azure region where all resources are deployed"
  value       = azurerm_resource_group.main.location
}

# SignalR Service Outputs
output "signalr_service_name" {
  description = "The name of the Azure SignalR service"
  value       = azurerm_signalr_service.main.name
}

output "signalr_hostname" {
  description = "The fully qualified domain name (FQDN) of the SignalR service"
  value       = azurerm_signalr_service.main.hostname
}

output "signalr_service_mode" {
  description = "The service mode of the SignalR service (should be 'Serverless')"
  value       = azurerm_signalr_service.main.service_mode
}

output "signalr_sku_name" {
  description = "The SKU name of the SignalR service"
  value       = azurerm_signalr_service.main.sku[0].name
}

output "signalr_capacity" {
  description = "The capacity (number of units) of the SignalR service"
  value       = azurerm_signalr_service.main.sku[0].capacity
}

# SignalR Connection Information (Sensitive)
output "signalr_primary_connection_string" {
  description = "The primary connection string for the SignalR service (used by Functions)"
  value       = azurerm_signalr_service.main.primary_connection_string
  sensitive   = true
}

output "signalr_secondary_connection_string" {
  description = "The secondary connection string for the SignalR service (backup)"
  value       = azurerm_signalr_service.main.secondary_connection_string
  sensitive   = true
}

output "signalr_primary_access_key" {
  description = "The primary access key for the SignalR service"
  value       = azurerm_signalr_service.main.primary_access_key
  sensitive   = true
}

# Function App Outputs
output "function_app_name" {
  description = "The name of the Azure Function App"
  value       = azurerm_windows_function_app.main.name
}

output "function_app_default_hostname" {
  description = "The default hostname of the Function App (used for API endpoints)"
  value       = azurerm_windows_function_app.main.default_hostname
}

output "function_app_url" {
  description = "The complete HTTPS URL of the Function App"
  value       = "https://${azurerm_windows_function_app.main.default_hostname}"
}

output "negotiate_endpoint_url" {
  description = "The URL for the negotiate endpoint used by SignalR clients"
  value       = "https://${azurerm_windows_function_app.main.default_hostname}/api/negotiate"
}

output "function_app_kind" {
  description = "The kind of Function App deployed"
  value       = azurerm_windows_function_app.main.kind
}

output "function_app_outbound_ip_addresses" {
  description = "List of outbound IP addresses for the Function App"
  value       = azurerm_windows_function_app.main.outbound_ip_address_list
}

# Function App Identity
output "function_app_principal_id" {
  description = "The Principal ID of the Function App's system-assigned managed identity"
  value       = azurerm_windows_function_app.main.identity[0].principal_id
}

output "function_app_tenant_id" {
  description = "The Tenant ID of the Function App's system-assigned managed identity"
  value       = azurerm_windows_function_app.main.identity[0].tenant_id
}

# Storage Account Information
output "storage_account_name" {
  description = "The name of the storage account used by the Function App"
  value       = azurerm_storage_account.function_storage.name
}

output "storage_account_primary_endpoint" {
  description = "The primary blob endpoint of the storage account"
  value       = azurerm_storage_account.function_storage.primary_blob_endpoint
}

# App Service Plan Information
output "app_service_plan_name" {
  description = "The name of the App Service Plan hosting the Function App"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_sku" {
  description = "The SKU of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

output "app_service_plan_os_type" {
  description = "The operating system type of the App Service Plan"
  value       = azurerm_service_plan.main.os_type
}

# Application Insights Information (conditional outputs)
output "application_insights_name" {
  description = "The name of the Application Insights instance (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_app_id" {
  description = "The Application ID of Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].app_id : null
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key for Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The connection string for Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# Log Analytics Workspace Information (conditional outputs)
output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace (if Application Insights is enabled)"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace (if Application Insights is enabled)"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

# Testing and Client Configuration
output "signalr_client_endpoint" {
  description = "The client endpoint URL for SignalR connections"
  value       = "wss://${azurerm_signalr_service.main.hostname}/client/"
}

output "cors_allowed_origins" {
  description = "The CORS allowed origins configured for the Function App"
  value       = var.enable_cors_for_all_origins ? ["*"] : var.cors_allowed_origins
}

# Deployment Information
output "deployment_tags" {
  description = "The tags applied to all resources in this deployment"
  value       = var.tags
}

output "random_suffix" {
  description = "The random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Summary for Quick Reference
output "deployment_summary" {
  description = "Summary of the deployed resources and key endpoints"
  value = {
    resource_group        = azurerm_resource_group.main.name
    location             = azurerm_resource_group.main.location
    signalr_service      = azurerm_signalr_service.main.name
    signalr_hostname     = azurerm_signalr_service.main.hostname
    function_app         = azurerm_windows_function_app.main.name
    function_app_url     = "https://${azurerm_windows_function_app.main.default_hostname}"
    negotiate_endpoint   = "https://${azurerm_windows_function_app.main.default_hostname}/api/negotiate"
    storage_account      = azurerm_storage_account.function_storage.name
    app_insights_enabled = var.enable_application_insights
    random_suffix        = random_string.suffix.result
  }
}