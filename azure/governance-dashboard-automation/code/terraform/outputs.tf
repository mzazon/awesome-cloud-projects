# ===============================================
# Outputs for Azure Governance Dashboard Infrastructure
# ===============================================
# This file defines all output values that provide important information
# about the deployed governance infrastructure, including URLs, IDs,
# and connection details for accessing and managing the solution.

# ===============================================
# Resource Group Information
# ===============================================

output "resource_group_name" {
  description = "Name of the resource group containing governance dashboard resources"
  value       = azurerm_resource_group.governance.name
}

output "resource_group_id" {
  description = "Resource ID of the governance dashboard resource group"
  value       = azurerm_resource_group.governance.id
}

output "resource_group_location" {
  description = "Azure region where governance dashboard resources are deployed"
  value       = azurerm_resource_group.governance.location
}

# ===============================================
# Log Analytics Workspace Information
# ===============================================

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for governance data"
  value       = azurerm_log_analytics_workspace.governance.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.governance.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.governance.workspace_id
  sensitive   = true
}

output "log_analytics_workspace_primary_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.governance.primary_shared_key
  sensitive   = true
}

output "log_analytics_workspace_secondary_key" {
  description = "Secondary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.governance.secondary_shared_key
  sensitive   = true
}

# ===============================================
# Monitor Workbook Information
# ===============================================

output "workbook_name" {
  description = "Name of the governance dashboard workbook"
  value       = azurerm_monitor_workbook.governance_dashboard.name
}

output "workbook_id" {
  description = "Resource ID of the governance dashboard workbook"
  value       = azurerm_monitor_workbook.governance_dashboard.id
}

output "workbook_display_name" {
  description = "Display name of the governance dashboard workbook"
  value       = azurerm_monitor_workbook.governance_dashboard.display_name
}

output "workbook_url" {
  description = "Direct URL to access the governance dashboard workbook in Azure Portal"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_monitor_workbook.governance_dashboard.id}/workbook"
}

# ===============================================
# Logic App Information
# ===============================================

output "logic_app_name" {
  description = "Name of the governance automation Logic App"
  value       = azurerm_logic_app_workflow.governance_automation.name
}

output "logic_app_id" {
  description = "Resource ID of the governance automation Logic App"
  value       = azurerm_logic_app_workflow.governance_automation.id
}

output "logic_app_trigger_url" {
  description = "HTTP trigger URL for the governance automation Logic App"
  value       = azurerm_logic_app_trigger_http_request.governance_trigger.callback_url
  sensitive   = true
}

output "logic_app_access_endpoint" {
  description = "Access endpoint for the Logic App workflow"
  value       = azurerm_logic_app_workflow.governance_automation.access_endpoint
}

# ===============================================
# Action Group Information
# ===============================================

output "action_group_name" {
  description = "Name of the governance alerts action group"
  value       = azurerm_monitor_action_group.governance_alerts.name
}

output "action_group_id" {
  description = "Resource ID of the governance alerts action group"
  value       = azurerm_monitor_action_group.governance_alerts.id
}

output "action_group_short_name" {
  description = "Short name of the governance alerts action group"
  value       = azurerm_monitor_action_group.governance_alerts.short_name
}

# ===============================================
# Alert Rules Information
# ===============================================

output "missing_tags_alert_id" {
  description = "Resource ID of the missing tags alert rule"
  value       = azurerm_monitor_scheduled_query_rules_alert_v2.missing_tags_alert.id
}

output "missing_tags_alert_name" {
  description = "Name of the missing tags alert rule"
  value       = azurerm_monitor_scheduled_query_rules_alert_v2.missing_tags_alert.name
}

output "location_compliance_alert_id" {
  description = "Resource ID of the location compliance alert rule"
  value       = azurerm_monitor_scheduled_query_rules_alert_v2.location_compliance_alert.id
}

output "location_compliance_alert_name" {
  description = "Name of the location compliance alert rule"
  value       = azurerm_monitor_scheduled_query_rules_alert_v2.location_compliance_alert.name
}

# ===============================================
# Policy Assignment Information
# ===============================================

output "require_tags_policy_assignment_id" {
  description = "Resource ID of the require tags policy assignment"
  value       = azurerm_policy_assignment.require_tags.id
}

output "require_tags_policy_assignment_name" {
  description = "Name of the require tags policy assignment"
  value       = azurerm_policy_assignment.require_tags.name
}

output "allowed_locations_policy_assignment_id" {
  description = "Resource ID of the allowed locations policy assignment"
  value       = azurerm_policy_assignment.allowed_locations.id
}

output "allowed_locations_policy_assignment_name" {
  description = "Name of the allowed locations policy assignment"
  value       = azurerm_policy_assignment.allowed_locations.name
}

# ===============================================
# Data Collection Rule Information
# ===============================================

output "data_collection_rule_name" {
  description = "Name of the governance metrics data collection rule"
  value       = azurerm_monitor_data_collection_rule.governance_metrics.name
}

output "data_collection_rule_id" {
  description = "Resource ID of the governance metrics data collection rule"
  value       = azurerm_monitor_data_collection_rule.governance_metrics.id
}

# ===============================================
# Security and Access Information
# ===============================================

output "subscription_id" {
  description = "Azure subscription ID where resources are deployed"
  value       = data.azurerm_subscription.current.subscription_id
}

output "tenant_id" {
  description = "Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "client_id" {
  description = "Client ID of the service principal used for deployment"
  value       = data.azurerm_client_config.current.client_id
}

# ===============================================
# Configuration Summary
# ===============================================

output "governance_configuration_summary" {
  description = "Summary of governance dashboard configuration settings"
  value = {
    resource_group_name     = azurerm_resource_group.governance.name
    location               = azurerm_resource_group.governance.location
    workbook_display_name  = azurerm_monitor_workbook.governance_dashboard.display_name
    log_analytics_sku      = azurerm_log_analytics_workspace.governance.sku
    log_retention_days     = azurerm_log_analytics_workspace.governance.retention_in_days
    required_tags          = var.required_tags
    allowed_locations      = var.allowed_locations
    alerts_enabled         = var.enable_governance_alerts
    policy_enforcement     = var.policy_enforcement_mode
    notification_configured = var.notification_webhook_url != "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
  }
}

# ===============================================
# Resource Graph Queries Information
# ===============================================

output "sample_resource_graph_queries" {
  description = "Sample Resource Graph queries for governance monitoring"
  value = {
    missing_required_tags = "resources | where tags !has 'Environment' or tags !has 'Owner' or tags !has 'CostCenter' | project name, type, resourceGroup, subscriptionId, location, tags | limit 1000"
    non_compliant_locations = "resources | where location !in ('${join("', '", var.allowed_locations)}') | project name, type, resourceGroup, location, subscriptionId | limit 1000"
    policy_compliance = "policyresources | where type == 'microsoft.policyinsights/policystates' | project resourceId, policyAssignmentName, policyDefinitionName, complianceState, timestamp | summarize count() by complianceState"
    security_assessments = "securityresources | where type == 'microsoft.security/assessments' | project resourceId, displayName, status, severity | summarize count() by status.code"
    resource_distribution = "resources | summarize count() by type, location | order by count_ desc"
  }
}

# ===============================================
# Next Steps and Usage Information
# ===============================================

output "next_steps" {
  description = "Next steps for configuring and using the governance dashboard"
  value = {
    access_dashboard = "Navigate to: ${azurerm_monitor_workbook.governance_dashboard.display_name} in Azure Portal"
    configure_notifications = var.notification_webhook_url == "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK" ? "Update notification_webhook_url variable with your actual webhook URL" : "Notifications are configured"
    setup_email_alerts = length(var.alert_email_addresses) == 0 ? "Add email addresses to alert_email_addresses variable to receive email notifications" : "Email alerts are configured"
    review_policies = "Review and customize Azure Policy assignments based on your organization's requirements"
    customize_queries = "Add custom Resource Graph queries using the custom_workbook_queries variable"
    monitor_compliance = "Monitor governance compliance through the workbook dashboard and alert notifications"
  }
}

# ===============================================
# Cost Estimation Information
# ===============================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for governance dashboard resources"
  value = {
    log_analytics_workspace = "~$2-10/month (depending on data ingestion volume)"
    logic_app_executions = "~$0.10-2/month (depending on execution frequency)"
    monitor_alerts = "~$0.10-1/month (first 1000 alerts free)"
    monitor_workbooks = "Free (no additional charges)"
    total_estimated = "~$2-15/month (varies by usage and data volume)"
    note = "Costs may vary based on data ingestion volume, alert frequency, and Logic App executions"
  }
}

# ===============================================
# Validation and Testing Information
# ===============================================

output "validation_commands" {
  description = "Commands to validate the governance dashboard deployment"
  value = {
    test_workbook = "az monitor app-insights workbook show --resource-group ${azurerm_resource_group.governance.name} --name ${azurerm_monitor_workbook.governance_dashboard.name}"
    test_logic_app = "az logic workflow show --resource-group ${azurerm_resource_group.governance.name} --name ${azurerm_logic_app_workflow.governance_automation.name} --query state"
    test_alerts = "az monitor metrics alert list --resource-group ${azurerm_resource_group.governance.name}"
    test_resource_graph = "az graph query --graph-query 'resources | summarize count() by type | top 10 by count_'"
    view_policies = "az policy assignment list --scope /subscriptions/${data.azurerm_subscription.current.subscription_id}"
  }
}