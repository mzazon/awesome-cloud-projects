# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# Log Analytics Workspace Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
  sensitive   = true
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Action Group Outputs
output "action_group_name" {
  description = "Name of the action group for alerts"
  value       = azurerm_monitor_action_group.service_health.name
}

output "action_group_id" {
  description = "ID of the action group for alerts"
  value       = azurerm_monitor_action_group.service_health.id
}

output "action_group_short_name" {
  description = "Short name of the action group"
  value       = azurerm_monitor_action_group.service_health.short_name
}

# Service Health Alert Outputs
output "service_health_alert_name" {
  description = "Name of the Service Health alert rule"
  value       = var.enable_service_health_alerts ? azurerm_monitor_activity_log_alert.service_health[0].name : null
}

output "service_health_alert_id" {
  description = "ID of the Service Health alert rule"
  value       = var.enable_service_health_alerts ? azurerm_monitor_activity_log_alert.service_health[0].id : null
}

# Update Manager Policy Outputs
output "update_manager_policy_assignment_name" {
  description = "Name of the Update Manager policy assignment"
  value       = azurerm_subscription_policy_assignment.update_manager_assessment.name
}

output "update_manager_policy_assignment_id" {
  description = "ID of the Update Manager policy assignment"
  value       = azurerm_subscription_policy_assignment.update_manager_assessment.id
}

# Maintenance Configuration Outputs
output "maintenance_configuration_name" {
  description = "Name of the maintenance configuration"
  value       = azurerm_maintenance_configuration.critical_patches.name
}

output "maintenance_configuration_id" {
  description = "ID of the maintenance configuration"
  value       = azurerm_maintenance_configuration.critical_patches.id
}

output "maintenance_configuration_scope" {
  description = "Scope of the maintenance configuration"
  value       = azurerm_maintenance_configuration.critical_patches.scope
}

# Logic App Outputs
output "logic_app_name" {
  description = "Name of the Logic App workflow"
  value       = azurerm_logic_app_workflow.health_correlation.name
}

output "logic_app_id" {
  description = "ID of the Logic App workflow"
  value       = azurerm_logic_app_workflow.health_correlation.id
}

output "logic_app_access_endpoint" {
  description = "Access endpoint of the Logic App workflow"
  value       = azurerm_logic_app_workflow.health_correlation.access_endpoint
}

output "logic_app_trigger_url" {
  description = "HTTP trigger URL for the Logic App"
  value       = azurerm_logic_app_trigger_http_request.service_health_webhook.callback_url
  sensitive   = true
}

# Automation Account Outputs
output "automation_account_name" {
  description = "Name of the Automation Account"
  value       = azurerm_automation_account.health_remediation.name
}

output "automation_account_id" {
  description = "ID of the Automation Account"
  value       = azurerm_automation_account.health_remediation.id
}

output "automation_account_identity_principal_id" {
  description = "Principal ID of the Automation Account managed identity"
  value       = azurerm_automation_account.health_remediation.identity[0].principal_id
}

output "automation_account_identity_tenant_id" {
  description = "Tenant ID of the Automation Account managed identity"
  value       = azurerm_automation_account.health_remediation.identity[0].tenant_id
}

# Automation Runbook Outputs
output "automation_runbook_name" {
  description = "Name of the remediation runbook"
  value       = var.enable_automation_runbooks ? azurerm_automation_runbook.remediate_critical_patches[0].name : null
}

output "automation_runbook_id" {
  description = "ID of the remediation runbook"
  value       = var.enable_automation_runbooks ? azurerm_automation_runbook.remediate_critical_patches[0].id : null
}

# Automation Webhook Outputs
output "automation_webhook_name" {
  description = "Name of the automation webhook"
  value       = var.enable_automation_runbooks ? azurerm_automation_webhook.health_remediation[0].name : null
}

output "automation_webhook_uri" {
  description = "URI of the automation webhook"
  value       = var.enable_automation_runbooks ? azurerm_automation_webhook.health_remediation[0].uri : null
  sensitive   = true
}

# Alert Rule Outputs
output "critical_patch_alert_name" {
  description = "Name of the critical patch compliance alert"
  value       = var.enable_update_manager_alerts ? azurerm_monitor_scheduled_query_rule.critical_patch_compliance[0].name : null
}

output "critical_patch_alert_id" {
  description = "ID of the critical patch compliance alert"
  value       = var.enable_update_manager_alerts ? azurerm_monitor_scheduled_query_rule.critical_patch_compliance[0].id : null
}

output "update_failure_alert_name" {
  description = "Name of the update installation failure alert"
  value       = var.enable_update_manager_alerts ? azurerm_monitor_scheduled_query_rule.update_installation_failures[0].name : null
}

output "update_failure_alert_id" {
  description = "ID of the update installation failure alert"
  value       = var.enable_update_manager_alerts ? azurerm_monitor_scheduled_query_rule.update_installation_failures[0].id : null
}

output "automation_effectiveness_alert_name" {
  description = "Name of the automation effectiveness alert"
  value       = azurerm_monitor_metric_alert.automation_effectiveness.name
}

output "automation_effectiveness_alert_id" {
  description = "ID of the automation effectiveness alert"
  value       = azurerm_monitor_metric_alert.automation_effectiveness.id
}

# Workbook Dashboard Outputs
output "workbook_dashboard_name" {
  description = "Name of the workbook dashboard"
  value       = var.enable_workbook_dashboard ? azurerm_application_insights_workbook.health_dashboard[0].name : null
}

output "workbook_dashboard_id" {
  description = "ID of the workbook dashboard"
  value       = var.enable_workbook_dashboard ? azurerm_application_insights_workbook.health_dashboard[0].id : null
}

# Diagnostic Settings Outputs
output "log_analytics_diagnostics_name" {
  description = "Name of the Log Analytics diagnostic settings"
  value       = var.enable_diagnostic_settings ? azurerm_monitor_diagnostic_setting.log_analytics_diagnostics[0].name : null
}

output "automation_diagnostics_name" {
  description = "Name of the Automation Account diagnostic settings"
  value       = var.enable_diagnostic_settings ? azurerm_monitor_diagnostic_setting.automation_diagnostics[0].name : null
}

output "logic_app_diagnostics_name" {
  description = "Name of the Logic App diagnostic settings"
  value       = var.enable_diagnostic_settings ? azurerm_monitor_diagnostic_setting.logic_app_diagnostics[0].name : null
}

# Role Assignment Outputs
output "automation_update_manager_role_assignment_id" {
  description = "ID of the Update Manager role assignment for Automation Account"
  value       = azurerm_role_assignment.automation_update_manager.id
}

output "automation_log_reader_role_assignment_id" {
  description = "ID of the Log Analytics Reader role assignment for Automation Account"
  value       = azurerm_role_assignment.automation_log_reader.id
}

# Configuration Summary Outputs
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    resource_group_name          = azurerm_resource_group.main.name
    location                     = azurerm_resource_group.main.location
    log_analytics_workspace_name = azurerm_log_analytics_workspace.main.name
    action_group_name            = azurerm_monitor_action_group.service_health.name
    automation_account_name      = azurerm_automation_account.health_remediation.name
    logic_app_name               = azurerm_logic_app_workflow.health_correlation.name
    maintenance_config_name      = azurerm_maintenance_configuration.critical_patches.name
    service_health_alerts_enabled = var.enable_service_health_alerts
    update_manager_alerts_enabled = var.enable_update_manager_alerts
    diagnostic_settings_enabled   = var.enable_diagnostic_settings
    workbook_dashboard_enabled     = var.enable_workbook_dashboard
    automation_runbooks_enabled   = var.enable_automation_runbooks
  }
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Instructions for using the deployed infrastructure"
  value = <<-EOT
  
  Azure Service Health and Update Manager Monitoring Infrastructure Deployed Successfully!
  
  Key Resources Created:
  - Resource Group: ${azurerm_resource_group.main.name}
  - Log Analytics Workspace: ${azurerm_log_analytics_workspace.main.name}
  - Action Group: ${azurerm_monitor_action_group.service_health.name}
  - Logic App: ${azurerm_logic_app_workflow.health_correlation.name}
  - Automation Account: ${azurerm_automation_account.health_remediation.name}
  - Maintenance Configuration: ${azurerm_maintenance_configuration.critical_patches.name}
  
  Next Steps:
  1. Configure virtual machines to use the maintenance configuration
  2. Set up additional Logic App workflow actions for your specific requirements
  3. Customize alert thresholds based on your operational needs
  4. Review and customize the workbook dashboard
  5. Test the webhook endpoints and automation workflows
  
  Important URLs:
  - Logic App Trigger: Use the logic_app_trigger_url output (sensitive)
  - Automation Webhook: Use the automation_webhook_uri output (sensitive)
  
  Monitoring:
  - Service Health alerts are ${var.enable_service_health_alerts ? "enabled" : "disabled"}
  - Update Manager alerts are ${var.enable_update_manager_alerts ? "enabled" : "disabled"}
  - Diagnostic settings are ${var.enable_diagnostic_settings ? "enabled" : "disabled"}
  
  EOT
}

# Random Suffix for Reference
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Subscription Information
output "subscription_id" {
  description = "Azure subscription ID"
  value       = data.azurerm_subscription.current.subscription_id
}

output "tenant_id" {
  description = "Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}