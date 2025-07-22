# Outputs for Azure DevOps Real-Time Monitoring Dashboard solution
# These outputs provide essential information for post-deployment configuration

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

# SignalR Service Information
output "signalr_service_name" {
  description = "Name of the SignalR Service"
  value       = azurerm_signalr_service.main.name
}

output "signalr_service_hostname" {
  description = "Hostname of the SignalR Service"
  value       = azurerm_signalr_service.main.hostname
}

output "signalr_service_id" {
  description = "ID of the SignalR Service"
  value       = azurerm_signalr_service.main.id
}

output "signalr_primary_connection_string" {
  description = "Primary connection string for SignalR Service"
  value       = azurerm_signalr_service.main.primary_connection_string
  sensitive   = true
}

output "signalr_primary_access_key" {
  description = "Primary access key for SignalR Service"
  value       = azurerm_signalr_service.main.primary_access_key
  sensitive   = true
}

# Azure Functions Information
output "function_app_name" {
  description = "Name of the Azure Functions App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_hostname" {
  description = "Default hostname of the Azure Functions App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_id" {
  description = "ID of the Azure Functions App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_url" {
  description = "URL of the Azure Functions App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_webhook_url" {
  description = "Webhook URL for Azure DevOps integration"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/DevOpsWebhook"
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

# Web App Information
output "web_app_name" {
  description = "Name of the Web App"
  value       = azurerm_linux_web_app.dashboard.name
}

output "web_app_hostname" {
  description = "Default hostname of the Web App"
  value       = azurerm_linux_web_app.dashboard.default_hostname
}

output "web_app_id" {
  description = "ID of the Web App"
  value       = azurerm_linux_web_app.dashboard.id
}

output "web_app_url" {
  description = "URL of the Web App dashboard"
  value       = "https://${azurerm_linux_web_app.dashboard.default_hostname}"
}

output "web_app_principal_id" {
  description = "Principal ID of the Web App managed identity"
  value       = azurerm_linux_web_app.dashboard.identity[0].principal_id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.functions.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.functions.id
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.functions.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.functions.primary_access_key
  sensitive   = true
}

# App Service Plan Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# Log Analytics Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.main.id
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
  description = "App ID for Application Insights"
  value       = azurerm_application_insights.main.app_id
}

# Monitoring Information
output "action_group_name" {
  description = "Name of the monitoring action group"
  value       = var.enable_monitoring_alerts ? azurerm_monitor_action_group.main[0].name : null
}

output "action_group_id" {
  description = "ID of the monitoring action group"
  value       = var.enable_monitoring_alerts ? azurerm_monitor_action_group.main[0].id : null
}

# Configuration Information
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "random_suffix" {
  description = "Random suffix used for resource names"
  value       = local.suffix
}

# Integration URLs and Endpoints
output "signalr_negotiate_url" {
  description = "SignalR negotiate endpoint URL"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/negotiate"
}

output "monitoring_dashboard_url" {
  description = "URL to access the monitoring dashboard"
  value       = "https://${azurerm_linux_web_app.dashboard.default_hostname}"
}

# Azure DevOps Integration Information
output "devops_webhook_configuration" {
  description = "Information for configuring Azure DevOps webhooks"
  value = {
    webhook_url = "https://${azurerm_linux_function_app.main.default_hostname}/api/DevOpsWebhook"
    hub_name    = "monitoring"
    events      = ["build.complete", "release.deployment.completed", "work.updated"]
  }
}

# Security Information
output "managed_identities" {
  description = "Information about created managed identities"
  value = {
    function_app_principal_id = azurerm_linux_function_app.main.identity[0].principal_id
    web_app_principal_id      = azurerm_linux_web_app.dashboard.identity[0].principal_id
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    signalr_service = var.signalr_sku == "Free_F1" ? 0 : var.signalr_sku == "Standard_S1" ? 50 : 200
    function_app    = "Pay-per-use (typically $5-20/month)"
    web_app         = var.app_service_plan_sku == "B1" ? 13 : var.app_service_plan_sku == "S1" ? 56 : 112
    storage_account = "~$5/month"
    log_analytics   = "~$10-30/month (depends on ingestion)"
    total_estimate  = "~$80-250/month depending on usage"
  }
}

# Useful Commands
output "useful_commands" {
  description = "Useful commands for managing the deployment"
  value = {
    view_function_logs    = "az functionapp log tail --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
    view_webapp_logs      = "az webapp log tail --name ${azurerm_linux_web_app.dashboard.name} --resource-group ${azurerm_resource_group.main.name}"
    restart_function_app  = "az functionapp restart --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
    restart_web_app       = "az webapp restart --name ${azurerm_linux_web_app.dashboard.name} --resource-group ${azurerm_resource_group.main.name}"
    view_signalr_metrics  = "az monitor metrics list --resource ${azurerm_signalr_service.main.id} --metric ConnectionCount,MessageCount"
  }
}

# Next Steps
output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Deploy function code to: ${azurerm_linux_function_app.main.name}",
    "2. Deploy dashboard application to: ${azurerm_linux_web_app.dashboard.name}",
    "3. Configure Azure DevOps Service Hooks with webhook URL: https://${azurerm_linux_function_app.main.default_hostname}/api/DevOpsWebhook",
    "4. Access monitoring dashboard at: https://${azurerm_linux_web_app.dashboard.default_hostname}",
    "5. Monitor application performance in Application Insights: ${azurerm_application_insights.main.name}",
    "6. View logs in Log Analytics workspace: ${azurerm_log_analytics_workspace.main.name}"
  ]
}