# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.ai_governance.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.ai_governance.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.ai_governance.id
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.ai_governance.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.ai_governance.workspace_id
}

output "log_analytics_workspace_resource_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.ai_governance.id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.ai_governance.primary_shared_key
  sensitive   = true
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.ai_governance.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.ai_governance.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.ai_governance.vault_uri
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.ai_governance.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.ai_governance.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.ai_governance.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.ai_governance.primary_access_key
  sensitive   = true
}

# Storage Container Information
output "reports_container_name" {
  description = "Name of the reports blob container"
  value       = azurerm_storage_container.reports.name
}

output "audit_logs_container_name" {
  description = "Name of the audit logs blob container"
  value       = azurerm_storage_container.audit_logs.name
}

# Managed Identity Information
output "logic_app_identity_id" {
  description = "ID of the Logic Apps managed identity"
  value       = azurerm_user_assigned_identity.logic_app_identity.id
}

output "logic_app_identity_principal_id" {
  description = "Principal ID of the Logic Apps managed identity"
  value       = azurerm_user_assigned_identity.logic_app_identity.principal_id
}

output "logic_app_identity_client_id" {
  description = "Client ID of the Logic Apps managed identity"
  value       = azurerm_user_assigned_identity.logic_app_identity.client_id
}

# Logic Apps Information
output "logic_app_lifecycle_name" {
  description = "Name of the agent lifecycle Logic App"
  value       = azurerm_logic_app_workflow.agent_lifecycle.name
}

output "logic_app_lifecycle_id" {
  description = "ID of the agent lifecycle Logic App"
  value       = azurerm_logic_app_workflow.agent_lifecycle.id
}

output "logic_app_lifecycle_endpoint" {
  description = "Access endpoint for the agent lifecycle Logic App"
  value       = azurerm_logic_app_workflow.agent_lifecycle.access_endpoint
  sensitive   = true
}

output "logic_app_compliance_monitoring_name" {
  description = "Name of the compliance monitoring Logic App"
  value       = var.logic_app_compliance_monitoring_enabled ? azurerm_logic_app_workflow.compliance_monitoring[0].name : null
}

output "logic_app_compliance_monitoring_id" {
  description = "ID of the compliance monitoring Logic App"
  value       = var.logic_app_compliance_monitoring_enabled ? azurerm_logic_app_workflow.compliance_monitoring[0].id : null
}

output "logic_app_compliance_monitoring_endpoint" {
  description = "Access endpoint for the compliance monitoring Logic App"
  value       = var.logic_app_compliance_monitoring_enabled ? azurerm_logic_app_workflow.compliance_monitoring[0].access_endpoint : null
  sensitive   = true
}

output "logic_app_access_control_name" {
  description = "Name of the access control Logic App"
  value       = var.logic_app_access_control_enabled ? azurerm_logic_app_workflow.access_control[0].name : null
}

output "logic_app_access_control_id" {
  description = "ID of the access control Logic App"
  value       = var.logic_app_access_control_enabled ? azurerm_logic_app_workflow.access_control[0].id : null
}

output "logic_app_access_control_endpoint" {
  description = "Access endpoint for the access control Logic App"
  value       = var.logic_app_access_control_enabled ? azurerm_logic_app_workflow.access_control[0].access_endpoint : null
  sensitive   = true
}

output "logic_app_audit_reporting_name" {
  description = "Name of the audit reporting Logic App"
  value       = azurerm_logic_app_workflow.audit_reporting.name
}

output "logic_app_audit_reporting_id" {
  description = "ID of the audit reporting Logic App"
  value       = azurerm_logic_app_workflow.audit_reporting.id
}

output "logic_app_audit_reporting_endpoint" {
  description = "Access endpoint for the audit reporting Logic App"
  value       = azurerm_logic_app_workflow.audit_reporting.access_endpoint
  sensitive   = true
}

output "logic_app_performance_monitoring_name" {
  description = "Name of the performance monitoring Logic App"
  value       = azurerm_logic_app_workflow.performance_monitoring.name
}

output "logic_app_performance_monitoring_id" {
  description = "ID of the performance monitoring Logic App"
  value       = azurerm_logic_app_workflow.performance_monitoring.id
}

output "logic_app_performance_monitoring_endpoint" {
  description = "Access endpoint for the performance monitoring Logic App"
  value       = azurerm_logic_app_workflow.performance_monitoring.access_endpoint
  sensitive   = true
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.ai_governance[0].name : null
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.ai_governance[0].id : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.ai_governance[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.ai_governance[0].connection_string : null
  sensitive   = true
}

# API Connections Information
output "api_connection_log_analytics_name" {
  description = "Name of the Log Analytics API connection"
  value       = azurerm_api_connection.log_analytics.name
}

output "api_connection_log_analytics_id" {
  description = "ID of the Log Analytics API connection"
  value       = azurerm_api_connection.log_analytics.id
}

output "api_connection_azuread_name" {
  description = "Name of the Azure AD API connection"
  value       = azurerm_api_connection.azuread.name
}

output "api_connection_azuread_id" {
  description = "ID of the Azure AD API connection"
  value       = azurerm_api_connection.azuread.id
}

output "api_connection_storage_blob_name" {
  description = "Name of the Storage Blob API connection"
  value       = azurerm_api_connection.storage_blob.name
}

output "api_connection_storage_blob_id" {
  description = "ID of the Storage Blob API connection"
  value       = azurerm_api_connection.storage_blob.id
}

# Monitoring and Alerting Information
output "monitor_action_group_name" {
  description = "Name of the Azure Monitor action group"
  value       = azurerm_monitor_action_group.ai_governance.name
}

output "monitor_action_group_id" {
  description = "ID of the Azure Monitor action group"
  value       = azurerm_monitor_action_group.ai_governance.id
}

output "logic_app_failures_alert_name" {
  description = "Name of the Logic App failures alert"
  value       = azurerm_monitor_metric_alert.logic_app_failures.name
}

output "logic_app_failures_alert_id" {
  description = "ID of the Logic App failures alert"
  value       = azurerm_monitor_metric_alert.logic_app_failures.id
}

output "keyvault_access_alert_name" {
  description = "Name of the Key Vault access alert"
  value       = azurerm_monitor_metric_alert.keyvault_access.name
}

output "keyvault_access_alert_id" {
  description = "ID of the Key Vault access alert"
  value       = azurerm_monitor_metric_alert.keyvault_access.id
}

# Cost Management Information
output "cost_management_budget_name" {
  description = "Name of the cost management budget"
  value       = var.enable_cost_alerts ? azurerm_consumption_budget_resource_group.ai_governance[0].name : null
}

output "cost_management_budget_id" {
  description = "ID of the cost management budget"
  value       = var.enable_cost_alerts ? azurerm_consumption_budget_resource_group.ai_governance[0].id : null
}

# Azure Context Information
output "subscription_id" {
  description = "Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}

output "tenant_id" {
  description = "Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "client_id" {
  description = "Azure client ID"
  value       = data.azurerm_client_config.current.client_id
}

# Random Suffix for Reference
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Management URLs
output "azure_portal_resource_group_url" {
  description = "Azure Portal URL for the resource group"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_resource_group.ai_governance.id}/overview"
}

output "azure_portal_key_vault_url" {
  description = "Azure Portal URL for the Key Vault"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_key_vault.ai_governance.id}/overview"
}

output "azure_portal_log_analytics_url" {
  description = "Azure Portal URL for the Log Analytics workspace"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_log_analytics_workspace.ai_governance.id}/overview"
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources for AI governance"
  value = {
    resource_group_name     = azurerm_resource_group.ai_governance.name
    log_analytics_workspace = azurerm_log_analytics_workspace.ai_governance.name
    key_vault_name         = azurerm_key_vault.ai_governance.name
    storage_account_name   = azurerm_storage_account.ai_governance.name
    logic_apps_count       = (var.logic_app_compliance_monitoring_enabled ? 1 : 0) + (var.logic_app_access_control_enabled ? 1 : 0) + 3 # Base 3 always created
    monitoring_enabled     = var.enable_application_insights
    cost_alerts_enabled    = var.enable_cost_alerts
  }
}