# Output Values
# This file defines the outputs returned after successful deployment

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
  description = "Azure region where resources were deployed"
  value       = azurerm_resource_group.main.location
}

# Web Application Information
output "app_name" {
  description = "Name of the deployed web application"
  value       = azurerm_linux_web_app.main.name
}

output "app_url" {
  description = "URL of the deployed web application"
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "app_default_hostname" {
  description = "Default hostname of the web application"
  value       = azurerm_linux_web_app.main.default_hostname
}

output "app_id" {
  description = "Resource ID of the web application"
  value       = azurerm_linux_web_app.main.id
}

output "app_kind" {
  description = "Kind of the web application"
  value       = azurerm_linux_web_app.main.kind
}

# App Service Plan Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "app_service_plan_sku" {
  description = "SKU name of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# Monitoring and Logging Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID (GUID) of the Log Analytics Workspace for queries"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key for the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Alert Configuration Information
output "action_group_name" {
  description = "Name of the action group for alert notifications"
  value       = azurerm_monitor_action_group.main.name
}

output "action_group_id" {
  description = "Resource ID of the action group"
  value       = azurerm_monitor_action_group.main.id
}

output "response_time_alert_name" {
  description = "Name of the response time alert rule"
  value       = azurerm_monitor_metric_alert.response_time.name
}

output "response_time_alert_id" {
  description = "Resource ID of the response time alert rule"
  value       = azurerm_monitor_metric_alert.response_time.id
}

output "http_errors_alert_name" {
  description = "Name of the HTTP errors alert rule"
  value       = azurerm_monitor_metric_alert.http_errors.name
}

output "http_errors_alert_id" {
  description = "Resource ID of the HTTP errors alert rule"
  value       = azurerm_monitor_metric_alert.http_errors.id
}

# Configuration Values
output "alert_email_address" {
  description = "Email address configured for alert notifications"
  value       = var.alert_email_address
}

output "response_time_threshold" {
  description = "Response time threshold configured for alerts (seconds)"
  value       = var.response_time_threshold
}

output "http_error_threshold" {
  description = "HTTP error threshold configured for alerts"
  value       = var.http_error_threshold
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_app_status = "az webapp show --name ${azurerm_linux_web_app.main.name} --resource-group ${azurerm_resource_group.main.name} --query \"{name:name,state:state,url:defaultHostName}\" --output table"
    test_app_response = "curl -I https://${azurerm_linux_web_app.main.default_hostname}"
    query_logs = "az monitor log-analytics query --workspace ${azurerm_log_analytics_workspace.main.workspace_id} --analytics-query \"AppServiceHTTPLogs | where TimeGenerated > ago(1h) | limit 10\" --output table"
    list_alerts = "az monitor metrics alert list --resource-group ${azurerm_resource_group.main.name} --output table"
  }
}

# Cleanup Commands
output "cleanup_commands" {
  description = "Commands to clean up the deployed resources"
  value = {
    delete_alerts = "az monitor metrics alert delete --name ${azurerm_monitor_metric_alert.response_time.name} --resource-group ${azurerm_resource_group.main.name} && az monitor metrics alert delete --name ${azurerm_monitor_metric_alert.http_errors.name} --resource-group ${azurerm_resource_group.main.name}"
    delete_action_group = "az monitor action-group delete --name ${azurerm_monitor_action_group.main.name} --resource-group ${azurerm_resource_group.main.name}"
    delete_workspace = "az monitor log-analytics workspace delete --workspace-name ${azurerm_log_analytics_workspace.main.name} --resource-group ${azurerm_resource_group.main.name} --yes"
    delete_webapp = "az webapp delete --name ${azurerm_linux_web_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
    delete_plan = "az appservice plan delete --name ${azurerm_service_plan.main.name} --resource-group ${azurerm_resource_group.main.name} --yes"
    delete_resource_group = "az group delete --name ${azurerm_resource_group.main.name} --yes --no-wait"
  }
}

# Resource Tags
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    web_app_url = "https://${azurerm_linux_web_app.main.default_hostname}"
    monitoring_workspace = azurerm_log_analytics_workspace.main.name
    alert_email = var.alert_email_address
    total_resources_created = 7
    estimated_monthly_cost = "Free tier usage - minimal cost for Log Analytics data ingestion"
  }
}