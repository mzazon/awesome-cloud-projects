# Output values for Azure Security Governance Infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.security_governance.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.security_governance.id
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.security_governance.location
}

# Event Grid Information
output "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  value       = azurerm_eventgrid_topic.security_governance.name
}

output "event_grid_topic_id" {
  description = "ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.security_governance.id
}

output "event_grid_topic_endpoint" {
  description = "Endpoint URL of the Event Grid topic"
  value       = azurerm_eventgrid_topic.security_governance.endpoint
}

output "event_grid_topic_hostname" {
  description = "Hostname of the Event Grid topic"
  value       = azurerm_eventgrid_topic.security_governance.hostname
}

# Event Grid Access Keys (Sensitive)
output "event_grid_primary_access_key" {
  description = "Primary access key for Event Grid topic"
  value       = azurerm_eventgrid_topic.security_governance.primary_access_key
  sensitive   = true
}

output "event_grid_secondary_access_key" {
  description = "Secondary access key for Event Grid topic"
  value       = azurerm_eventgrid_topic.security_governance.secondary_access_key
  sensitive   = true
}

# Event Grid Subscription Information
output "event_grid_subscription_name" {
  description = "Name of the Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.security_governance.name
}

output "event_grid_subscription_id" {
  description = "ID of the Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.security_governance.id
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.security_governance.name
}

output "function_app_id" {
  description = "ID of the Azure Function App"
  value       = azurerm_linux_function_app.security_governance.id
}

output "function_app_hostname" {
  description = "Hostname of the Azure Function App"
  value       = azurerm_linux_function_app.security_governance.default_hostname
}

output "function_app_url" {
  description = "Default URL of the Azure Function App"
  value       = "https://${azurerm_linux_function_app.security_governance.default_hostname}"
}

# Managed Identity Information
output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.security_governance.identity[0].principal_id
}

output "function_app_tenant_id" {
  description = "Tenant ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.security_governance.identity[0].tenant_id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.security_governance.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.security_governance.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.security_governance.primary_blob_endpoint
}

# Storage Account Connection String (Sensitive)
output "storage_account_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.security_governance.primary_connection_string
  sensitive   = true
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.security_governance.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.security_governance.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.security_governance.workspace_id
}

# Log Analytics Primary Shared Key (Sensitive)
output "log_analytics_primary_shared_key" {
  description = "Primary shared key for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.security_governance.primary_shared_key
  sensitive   = true
}

# Application Insights Information (if enabled)
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.security_governance[0].name : null
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.security_governance[0].id : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.security_governance[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.security_governance[0].connection_string : null
  sensitive   = true
}

# Monitor Action Group Information
output "action_group_name" {
  description = "Name of the Azure Monitor Action Group"
  value       = azurerm_monitor_action_group.security_governance.name
}

output "action_group_id" {
  description = "ID of the Azure Monitor Action Group"
  value       = azurerm_monitor_action_group.security_governance.id
}

# Alert Rules Information
output "security_violation_alert_name" {
  description = "Name of the security violation alert rule"
  value       = azurerm_monitor_metric_alert.security_violations.name
}

output "security_violation_alert_id" {
  description = "ID of the security violation alert rule"
  value       = azurerm_monitor_metric_alert.security_violations.id
}

output "function_failure_alert_name" {
  description = "Name of the function failure alert rule"
  value       = azurerm_monitor_metric_alert.function_failures.name
}

output "function_failure_alert_id" {
  description = "ID of the function failure alert rule"
  value       = azurerm_monitor_metric_alert.function_failures.id
}

# Service Plan Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.security_governance.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.security_governance.id
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.security_governance.sku_name
}

# Security Function Information
output "security_function_name" {
  description = "Name of the security event processor function"
  value       = azurerm_function_app_function.security_event_processor.name
}

output "security_function_id" {
  description = "ID of the security event processor function"
  value       = azurerm_function_app_function.security_event_processor.id
}

output "security_function_url" {
  description = "URL of the security event processor function"
  value       = azurerm_function_app_function.security_event_processor.invocation_url
  sensitive   = true
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of the deployed resources"
  value = {
    resource_group          = azurerm_resource_group.security_governance.name
    location               = azurerm_resource_group.security_governance.location
    event_grid_topic       = azurerm_eventgrid_topic.security_governance.name
    function_app           = azurerm_linux_function_app.security_governance.name
    storage_account        = azurerm_storage_account.security_governance.name
    log_analytics_workspace = azurerm_log_analytics_workspace.security_governance.name
    action_group           = azurerm_monitor_action_group.security_governance.name
    managed_identity       = azurerm_linux_function_app.security_governance.identity[0].principal_id
    environment           = var.environment
    deployment_time       = timestamp()
  }
}

# Monitoring URLs
output "monitoring_urls" {
  description = "URLs for monitoring and management"
  value = {
    function_app_portal = "https://portal.azure.com/#@${azurerm_linux_function_app.security_governance.identity[0].tenant_id}/resource${azurerm_linux_function_app.security_governance.id}"
    event_grid_portal  = "https://portal.azure.com/#@${azurerm_linux_function_app.security_governance.identity[0].tenant_id}/resource${azurerm_eventgrid_topic.security_governance.id}"
    log_analytics_portal = "https://portal.azure.com/#@${azurerm_linux_function_app.security_governance.identity[0].tenant_id}/resource${azurerm_log_analytics_workspace.security_governance.id}"
    application_insights_portal = var.enable_application_insights ? "https://portal.azure.com/#@${azurerm_linux_function_app.security_governance.identity[0].tenant_id}/resource${azurerm_application_insights.security_governance[0].id}" : null
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_function_app = "az functionapp show --name ${azurerm_linux_function_app.security_governance.name} --resource-group ${azurerm_resource_group.security_governance.name}"
    check_event_grid   = "az eventgrid topic show --name ${azurerm_eventgrid_topic.security_governance.name} --resource-group ${azurerm_resource_group.security_governance.name}"
    check_subscription = "az eventgrid event-subscription show --name ${azurerm_eventgrid_event_subscription.security_governance.name} --source-resource-id ${azurerm_resource_group.security_governance.id}"
    check_managed_identity = "az functionapp identity show --name ${azurerm_linux_function_app.security_governance.name} --resource-group ${azurerm_resource_group.security_governance.name}"
    check_role_assignments = "az role assignment list --assignee ${azurerm_linux_function_app.security_governance.identity[0].principal_id}"
    test_function_logs     = "az functionapp logs tail --name ${azurerm_linux_function_app.security_governance.name} --resource-group ${azurerm_resource_group.security_governance.name}"
  }
}

# Security Information
output "security_information" {
  description = "Security-related information for the deployment"
  value = {
    managed_identity_enabled = true
    rbac_roles_assigned     = ["Security Reader", "Contributor", "Monitoring Contributor"]
    https_only_enabled      = true
    advanced_threat_protection = var.enable_advanced_threat_protection
    application_insights_enabled = var.enable_application_insights
    tls_version            = "1.2"
    storage_encryption     = "Microsoft.Storage"
  }
}