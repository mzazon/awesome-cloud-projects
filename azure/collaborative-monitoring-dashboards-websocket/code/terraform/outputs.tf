# Outputs for Azure Real-Time Collaborative Dashboard Infrastructure
# These outputs provide essential information for deployment verification and application configuration

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Web PubSub Service Information
output "webpubsub_name" {
  description = "Name of the Azure Web PubSub service"
  value       = azurerm_web_pubsub.main.name
}

output "webpubsub_hostname" {
  description = "Hostname of the Azure Web PubSub service"
  value       = azurerm_web_pubsub.main.hostname
}

output "webpubsub_hub_name" {
  description = "Name of the Web PubSub hub for dashboard communication"
  value       = azurerm_web_pubsub_hub.dashboard.name
}

output "webpubsub_connection_string" {
  description = "Primary connection string for Web PubSub service"
  value       = azurerm_web_pubsub.main.primary_connection_string
  sensitive   = true
}

output "webpubsub_access_key" {
  description = "Primary access key for Web PubSub service"
  value       = azurerm_web_pubsub.main.primary_access_key
  sensitive   = true
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "HTTPS URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

# Static Web App Information
output "static_web_app_name" {
  description = "Name of the Azure Static Web App"
  value       = azurerm_static_web_app.main.name
}

output "static_web_app_default_hostname" {
  description = "Default hostname of the Static Web App"
  value       = azurerm_static_web_app.main.default_host_name
}

output "static_web_app_url" {
  description = "HTTPS URL of the Static Web App"
  value       = "https://${azurerm_static_web_app.main.default_host_name}"
}

output "static_web_app_id" {
  description = "ID of the Static Web App"
  value       = azurerm_static_web_app.main.id
}

output "static_web_app_api_key" {
  description = "API key for Static Web App deployment"
  value       = azurerm_static_web_app.main.api_key
  sensitive   = true
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
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

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = azurerm_application_insights.main.app_id
}

# Log Analytics Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_key" {
  description = "Primary shared key for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Monitoring and Alerts Information
output "action_group_id" {
  description = "ID of the monitor action group (if alerts enabled)"
  value       = var.enable_alerts && length(var.alert_email_recipients) > 0 ? azurerm_monitor_action_group.main[0].id : null
}

output "alerts_enabled" {
  description = "Whether alerts are enabled for this deployment"
  value       = var.enable_alerts
}

# Environment Configuration
output "environment_variables" {
  description = "Key environment variables for application configuration"
  value = {
    WEBPUBSUB_CONNECTION                = azurerm_web_pubsub.main.primary_connection_string
    APPINSIGHTS_INSTRUMENTATIONKEY      = azurerm_application_insights.main.instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main.connection_string
    LOG_ANALYTICS_WORKSPACE_ID          = azurerm_log_analytics_workspace.main.workspace_id
    FUNCTION_APP_URL                    = "https://${azurerm_linux_function_app.main.default_hostname}"
    STATIC_WEB_APP_URL                  = "https://${azurerm_static_web_app.main.default_host_name}"
  }
  sensitive = true
}

# Client Configuration for Frontend Applications
output "client_configuration" {
  description = "Configuration object for frontend client applications"
  value = {
    webpubsub_url        = "wss://${azurerm_web_pubsub.main.hostname}/client/hubs/${var.webpubsub_hub_name}"
    api_base_url         = "https://${azurerm_linux_function_app.main.default_hostname}/api"
    app_insights_key     = azurerm_application_insights.main.instrumentation_key
    hub_name            = var.webpubsub_hub_name
    environment         = var.environment
  }
  sensitive = true
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources and key endpoints"
  value = {
    dashboard_url        = "https://${azurerm_static_web_app.main.default_host_name}"
    api_url             = "https://${azurerm_linux_function_app.main.default_hostname}"
    webpubsub_endpoint  = azurerm_web_pubsub.main.hostname
    monitoring_workspace = azurerm_log_analytics_workspace.main.name
    resource_group      = azurerm_resource_group.main.name
    location           = azurerm_resource_group.main.location
    environment        = var.environment
    project_name       = var.project_name
  }
}

# Post-Deployment Instructions
output "next_steps" {
  description = "Post-deployment configuration steps"
  value = {
    dashboard_access    = "Visit https://${azurerm_static_web_app.main.default_host_name} to access the collaborative dashboard"
    function_deployment = "Deploy function code to ${azurerm_linux_function_app.main.name} using Azure Functions Core Tools or GitHub Actions"
    frontend_deployment = "Deploy frontend code to ${azurerm_static_web_app.main.name} using GitHub Actions or Azure CLI"
    monitoring_setup   = "Configure custom metrics and queries in ${azurerm_log_analytics_workspace.main.name}"
    alert_configuration = var.enable_alerts ? "Alerts are configured and will notify: ${join(", ", var.alert_email_recipients)}" : "Enable alerts by setting enable_alerts=true and providing alert_email_recipients"
  }
}