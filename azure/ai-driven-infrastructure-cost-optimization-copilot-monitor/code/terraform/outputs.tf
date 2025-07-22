# Output values for the Azure Cost Optimization infrastructure
# These outputs provide important information for verification and integration

output "resource_group_name" {
  description = "Name of the resource group containing all cost optimization resources"
  value       = azurerm_resource_group.cost_optimization.name
}

output "resource_group_id" {
  description = "Resource ID of the cost optimization resource group"
  value       = azurerm_resource_group.cost_optimization.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for cost monitoring"
  value       = azurerm_log_analytics_workspace.cost_optimization.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.cost_optimization.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) for Log Analytics queries"
  value       = azurerm_log_analytics_workspace.cost_optimization.workspace_id
  sensitive   = true
}

output "log_analytics_primary_key" {
  description = "Primary shared key for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.cost_optimization.primary_shared_key
  sensitive   = true
}

output "automation_account_name" {
  description = "Name of the Azure Automation Account"
  value       = azurerm_automation_account.cost_optimization.name
}

output "automation_account_id" {
  description = "Resource ID of the Azure Automation Account"
  value       = azurerm_automation_account.cost_optimization.id
}

output "automation_account_identity_principal_id" {
  description = "Principal ID of the Automation Account's managed identity"
  value       = azurerm_automation_account.cost_optimization.identity[0].principal_id
}

output "vm_optimization_runbook_name" {
  description = "Name of the VM optimization runbook"
  value       = var.enable_vm_optimization ? azurerm_automation_runbook.vm_optimization[0].name : null
}

output "storage_optimization_runbook_name" {
  description = "Name of the storage optimization runbook"
  value       = var.enable_storage_optimization ? azurerm_automation_runbook.storage_optimization[0].name : null
}

output "optimization_schedule_name" {
  description = "Name of the automation schedule for cost optimization"
  value       = azurerm_automation_schedule.optimization_schedule.name
}

output "action_group_name" {
  description = "Name of the monitor action group for cost alerts"
  value       = azurerm_monitor_action_group.cost_alerts.name
}

output "action_group_id" {
  description = "Resource ID of the monitor action group"
  value       = azurerm_monitor_action_group.cost_alerts.id
}

output "cost_anomaly_alert_name" {
  description = "Name of the cost anomaly detection alert"
  value       = var.enable_cost_anomaly_detection ? azurerm_monitor_metric_alert.cost_anomaly[0].name : null
}

output "automation_webhook_uri" {
  description = "URI of the automation webhook for cost optimization"
  value       = azurerm_automation_webhook.cost_optimization.uri
  sensitive   = true
}

output "logic_app_workflow_name" {
  description = "Name of the Logic App workflow for cost optimization"
  value       = azurerm_logic_app_workflow.cost_optimization.name
}

output "logic_app_workflow_id" {
  description = "Resource ID of the Logic App workflow"
  value       = azurerm_logic_app_workflow.cost_optimization.id
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.cost_optimization.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.cost_optimization.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.cost_optimization.connection_string
  sensitive   = true
}

# Configuration outputs for easy reference
output "configuration_summary" {
  description = "Summary of the deployed cost optimization configuration"
  value = {
    environment                   = var.environment
    location                     = var.location
    log_retention_days           = var.log_analytics_retention_days
    budget_amount               = var.budget_amount
    cost_alert_threshold        = var.cost_alert_threshold
    vm_optimization_enabled     = var.enable_vm_optimization
    storage_optimization_enabled = var.enable_storage_optimization
    cost_anomaly_detection_enabled = var.enable_cost_anomaly_detection
    optimization_schedule       = var.optimization_schedule
    alert_recipients           = length(var.alert_email_addresses)
  }
}

# Azure Portal URLs for easy access
output "azure_portal_urls" {
  description = "Azure Portal URLs for accessing deployed resources"
  value = {
    resource_group = "https://portal.azure.com/#@/resource${azurerm_resource_group.cost_optimization.id}"
    log_analytics  = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.cost_optimization.id}"
    automation_account = "https://portal.azure.com/#@/resource${azurerm_automation_account.cost_optimization.id}"
    cost_management = "https://portal.azure.com/#blade/Microsoft_Azure_CostManagement/Menu/overview"
    azure_advisor   = "https://portal.azure.com/#blade/Microsoft_Azure_Expert/AdvisorMenuBlade/overview"
    azure_copilot   = "https://portal.azure.com/#blade/Microsoft_Azure_Copilot/CopilotBlade"
  }
}

# Monitoring and alerting information
output "monitoring_info" {
  description = "Information about monitoring and alerting configuration"
  value = {
    log_analytics_workspace = azurerm_log_analytics_workspace.cost_optimization.name
    action_group           = azurerm_monitor_action_group.cost_alerts.name
    cost_alert_threshold   = "${var.cost_alert_threshold}% of $${var.budget_amount}"
    alert_recipients       = var.alert_email_addresses
    automation_schedule    = var.optimization_schedule
  }
}

# Next steps for users
output "next_steps" {
  description = "Next steps to complete the cost optimization setup"
  value = [
    "1. Access Azure Portal and navigate to Azure Copilot",
    "2. Review and configure cost budgets in Azure Cost Management",
    "3. Test automation runbooks in the Azure Automation Account",
    "4. Configure additional alert rules based on your specific requirements",
    "5. Review Azure Advisor recommendations for additional optimization opportunities",
    "6. Set up recurring cost reviews using the Logic App workflow"
  ]
}