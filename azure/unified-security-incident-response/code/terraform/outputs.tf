# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.security_ops.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.security_ops.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.security_ops.location
}

# Log Analytics Workspace Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.security_workspace.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.security_workspace.id
}

output "log_analytics_workspace_resource_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.security_workspace.id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.security_workspace.primary_shared_key
  sensitive   = true
}

output "log_analytics_workspace_secondary_shared_key" {
  description = "Secondary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.security_workspace.secondary_shared_key
  sensitive   = true
}

# Microsoft Sentinel Outputs
output "sentinel_solution_name" {
  description = "Name of the Microsoft Sentinel solution"
  value       = azurerm_log_analytics_solution.sentinel.solution_name
}

output "sentinel_workspace_id" {
  description = "Microsoft Sentinel workspace ID"
  value       = azurerm_log_analytics_workspace.security_workspace.id
}

output "sentinel_portal_url" {
  description = "URL to access Microsoft Sentinel in the Azure portal"
  value       = "https://portal.azure.com/#blade/Microsoft_Azure_Security_Insights/MainMenuBlade/0/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.security_ops.name}/providers/Microsoft.OperationalInsights/workspaces/${azurerm_log_analytics_workspace.security_workspace.name}"
}

output "unified_security_portal_url" {
  description = "URL to access the unified security operations portal"
  value       = "https://security.microsoft.com"
}

# Analytics Rules Outputs
output "suspicious_signin_rule_id" {
  description = "ID of the suspicious sign-in analytics rule"
  value       = var.enable_analytics_rules && var.analytics_rules_config.suspicious_signin.enabled ? azurerm_sentinel_alert_rule_scheduled.suspicious_signin[0].id : null
}

output "privilege_escalation_rule_id" {
  description = "ID of the privilege escalation analytics rule"
  value       = var.enable_analytics_rules && var.analytics_rules_config.privilege_escalation.enabled ? azurerm_sentinel_alert_rule_scheduled.privilege_escalation[0].id : null
}

# Data Connectors Status
output "data_connectors_enabled" {
  description = "Status of enabled data connectors"
  value = {
    azure_ad_connector         = var.enable_azure_ad_connector
    azure_activity_connector   = var.enable_azure_activity_connector
    security_events_connector  = var.enable_security_events_connector
    office365_connector        = var.enable_office365_connector
    defender_connector         = var.enable_defender_connector
  }
}

# Logic Apps Outputs
output "logic_app_incident_response_name" {
  description = "Name of the incident response Logic App"
  value       = var.enable_automation ? azurerm_logic_app_workflow.incident_response[0].name : null
}

output "logic_app_incident_response_id" {
  description = "ID of the incident response Logic App"
  value       = var.enable_automation ? azurerm_logic_app_workflow.incident_response[0].id : null
}

output "logic_app_incident_response_access_endpoint" {
  description = "Access endpoint URL for the incident response Logic App"
  value       = var.enable_automation ? azurerm_logic_app_workflow.incident_response[0].access_endpoint : null
}

output "security_playbook_name" {
  description = "Name of the security playbook Logic App"
  value       = var.enable_automation ? azurerm_logic_app_workflow.security_playbook[0].name : null
}

output "security_playbook_id" {
  description = "ID of the security playbook Logic App"
  value       = var.enable_automation ? azurerm_logic_app_workflow.security_playbook[0].id : null
}

output "security_playbook_trigger_url" {
  description = "Trigger URL for the security playbook"
  value       = var.enable_automation ? azurerm_logic_app_trigger_http_request.playbook_trigger[0].callback_url : null
  sensitive   = true
}

# Service Principal Outputs
output "logic_app_service_principal_application_id" {
  description = "Application ID of the Logic Apps service principal"
  value       = var.enable_automation ? azuread_application.logic_app_sp[0].application_id : null
}

output "logic_app_service_principal_object_id" {
  description = "Object ID of the Logic Apps service principal"
  value       = var.enable_automation ? azuread_service_principal.logic_app_sp[0].object_id : null
}

# Azure Monitor Workbook Outputs
output "security_workbook_name" {
  description = "Name of the security operations workbook"
  value       = var.enable_security_workbook ? azurerm_application_insights_workbook.security_dashboard[0].display_name : null
}

output "security_workbook_id" {
  description = "ID of the security operations workbook"
  value       = var.enable_security_workbook ? azurerm_application_insights_workbook.security_dashboard[0].id : null
}

output "security_workbook_url" {
  description = "URL to access the security operations workbook"
  value       = var.enable_security_workbook ? "https://portal.azure.com/#blade/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/workbooks" : null
}

# Storage Account Outputs
output "logic_apps_storage_account_name" {
  description = "Name of the Logic Apps storage account"
  value       = var.enable_automation ? azurerm_storage_account.logic_apps_storage[0].name : null
}

output "logic_apps_storage_account_id" {
  description = "ID of the Logic Apps storage account"
  value       = var.enable_automation ? azurerm_storage_account.logic_apps_storage[0].id : null
}

output "logic_apps_storage_account_primary_key" {
  description = "Primary access key of the Logic Apps storage account"
  value       = var.enable_automation ? azurerm_storage_account.logic_apps_storage[0].primary_access_key : null
  sensitive   = true
}

# Action Group Outputs
output "security_alerts_action_group_name" {
  description = "Name of the security alerts action group"
  value       = azurerm_monitor_action_group.security_alerts.name
}

output "security_alerts_action_group_id" {
  description = "ID of the security alerts action group"
  value       = azurerm_monitor_action_group.security_alerts.id
}

# Cost Management Outputs
output "budget_name" {
  description = "Name of the cost management budget"
  value       = var.enable_cost_alerts ? azurerm_consumption_budget_resource_group.security_ops_budget[0].name : null
}

output "budget_amount" {
  description = "Budget amount in USD"
  value       = var.enable_cost_alerts ? var.monthly_budget_limit : null
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of the deployed security operations infrastructure"
  value = {
    resource_group_name           = azurerm_resource_group.security_ops.name
    log_analytics_workspace_name  = azurerm_log_analytics_workspace.security_workspace.name
    sentinel_enabled              = true
    ueba_enabled                  = var.enable_ueba
    automation_enabled            = var.enable_automation
    workbook_enabled              = var.enable_security_workbook
    unified_operations_enabled    = var.enable_unified_operations
    cost_alerts_enabled           = var.enable_cost_alerts
    random_suffix                 = var.use_random_suffix ? local.suffix : "none"
  }
}

# Access Instructions
output "access_instructions" {
  description = "Instructions for accessing the deployed security operations platform"
  value = {
    sentinel_portal = "Access Microsoft Sentinel at: https://portal.azure.com -> Microsoft Sentinel -> Select workspace: ${azurerm_log_analytics_workspace.security_workspace.name}"
    unified_portal  = "Access unified security operations at: https://security.microsoft.com"
    workbook_access = var.enable_security_workbook ? "Access security workbook at: Azure Portal -> Monitor -> Workbooks -> ${var.workbook_name}" : "Workbook not enabled"
    logic_apps_access = var.enable_automation ? "Access Logic Apps at: Azure Portal -> Logic Apps -> ${local.logic_app_name}" : "Logic Apps not enabled"
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Configure additional data connectors based on your environment",
    "2. Customize analytics rules to match your security requirements",
    "3. Set up notification endpoints for Logic Apps automation",
    "4. Configure RBAC permissions for security operations team",
    "5. Test incident response workflows and playbooks",
    "6. Review and customize the security operations workbook",
    "7. Monitor costs and adjust budget alerts as needed",
    "8. Enable additional Microsoft Defender services as required"
  ]
}

# Important Notes
output "important_notes" {
  description = "Important information about the deployment"
  value = [
    "⚠️  This deployment creates security-sensitive resources that require proper RBAC configuration",
    "⚠️  Some data connectors may require additional configuration in the Azure portal",
    "⚠️  Logic Apps automation requires webhook URLs to be configured for notifications",
    "⚠️  Monitor costs regularly as log ingestion and retention can impact billing",
    "⚠️  Ensure compliance with your organization's security policies and procedures",
    "⚠️  Regular review and tuning of analytics rules is recommended to reduce false positives"
  ]
}