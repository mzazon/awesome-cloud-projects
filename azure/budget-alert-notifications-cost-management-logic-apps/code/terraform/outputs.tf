# Output Values for Budget Alert Notifications Infrastructure
# This file defines all output values that provide important information after deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all budget monitoring resources"
  value       = azurerm_resource_group.budget_alerts.name
}

output "resource_group_location" {
  description = "Azure region where the resource group is deployed"
  value       = azurerm_resource_group.budget_alerts.location
}

output "resource_group_id" {
  description = "Fully qualified resource ID of the resource group"
  value       = azurerm_resource_group.budget_alerts.id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account used by Logic App"
  value       = azurerm_storage_account.logic_app_storage.name
}

output "storage_account_id" {
  description = "Fully qualified resource ID of the storage account"
  value       = azurerm_storage_account.logic_app_storage.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.logic_app_storage.primary_blob_endpoint
}

# Logic App Information
output "logic_app_name" {
  description = "Name of the Logic App that processes budget alerts"
  value       = azurerm_logic_app_standard.budget_processor.name
}

output "logic_app_id" {
  description = "Fully qualified resource ID of the Logic App"
  value       = azurerm_logic_app_standard.budget_processor.id
}

output "logic_app_default_hostname" {
  description = "Default hostname of the Logic App for webhook configuration"
  value       = azurerm_logic_app_standard.budget_processor.default_hostname
}

output "logic_app_webhook_url" {
  description = "Webhook URL for budget alert processing (customize the path as needed)"
  value       = "https://${azurerm_logic_app_standard.budget_processor.default_hostname}/api/budget-alert-webhook"
}

output "logic_app_portal_url" {
  description = "Azure Portal URL for managing the Logic App"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_logic_app_standard.budget_processor.id}"
}

# App Service Plan Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan hosting the Logic App"
  value       = azurerm_service_plan.logic_app_plan.name
}

output "app_service_plan_id" {
  description = "Fully qualified resource ID of the App Service Plan"
  value       = azurerm_service_plan.logic_app_plan.id
}

output "app_service_plan_sku" {
  description = "SKU name of the App Service Plan"
  value       = azurerm_service_plan.logic_app_plan.sku_name
}

# Action Group Information
output "action_group_name" {
  description = "Name of the Action Group for budget alert notifications"
  value       = azurerm_monitor_action_group.budget_alerts.name
}

output "action_group_id" {
  description = "Fully qualified resource ID of the Action Group"
  value       = azurerm_monitor_action_group.budget_alerts.id
}

output "action_group_short_name" {
  description = "Short name of the Action Group used in notifications"
  value       = azurerm_monitor_action_group.budget_alerts.short_name
}

# Budget Information
output "budget_name" {
  description = "Name of the consumption budget monitoring spending"
  value       = azurerm_consumption_budget_subscription.monthly_budget.name
}

output "budget_id" {
  description = "Fully qualified resource ID of the consumption budget"
  value       = azurerm_consumption_budget_subscription.monthly_budget.id
}

output "budget_amount" {
  description = "Monthly budget amount in USD"
  value       = azurerm_consumption_budget_subscription.monthly_budget.amount
}

output "budget_start_date" {
  description = "Budget monitoring start date"
  value       = var.budget_start_date
}

output "budget_end_date" {
  description = "Budget monitoring end date"
  value       = var.budget_end_date
}

# Alert Threshold Information
output "alert_thresholds" {
  description = "Configured alert thresholds for budget monitoring"
  value = {
    for key, threshold in var.alert_thresholds : key => {
      enabled   = threshold.enabled
      threshold = threshold.threshold
      operator  = threshold.operator
      type     = startswith(key, "actual") ? "Actual" : "Forecasted"
    }
  }
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights resource for monitoring"
  value       = azurerm_application_insights.budget_monitoring.name
}

output "application_insights_id" {
  description = "Fully qualified resource ID of Application Insights"
  value       = azurerm_application_insights.budget_monitoring.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive)"
  value       = azurerm_application_insights.budget_monitoring.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (sensitive)"
  value       = azurerm_application_insights.budget_monitoring.connection_string
  sensitive   = true
}

output "application_insights_portal_url" {
  description = "Azure Portal URL for Application Insights dashboard"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_application_insights.budget_monitoring.id}"
}

# Log Analytics Workspace Information (if enabled)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace (if diagnostic settings enabled)"
  value       = var.enable_diagnostic_settings ? azurerm_log_analytics_workspace.budget_monitoring[0].name : null
}

output "log_analytics_workspace_id" {
  description = "Fully qualified resource ID of Log Analytics Workspace (if enabled)"
  value       = var.enable_diagnostic_settings ? azurerm_log_analytics_workspace.budget_monitoring[0].id : null
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of Log Analytics Workspace for queries (if enabled)"
  value       = var.enable_diagnostic_settings ? azurerm_log_analytics_workspace.budget_monitoring[0].workspace_id : null
}

# Subscription and Tenant Information
output "subscription_id" {
  description = "Azure subscription ID where resources are deployed"
  value       = data.azurerm_subscription.current.subscription_id
}

output "tenant_id" {
  description = "Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    resource_group = {
      name     = azurerm_resource_group.budget_alerts.name
      location = azurerm_resource_group.budget_alerts.location
      purpose  = "Container for all budget monitoring resources"
    }
    storage_account = {
      name    = azurerm_storage_account.logic_app_storage.name
      purpose = "Runtime storage for Logic App workflows"
    }
    logic_app = {
      name    = azurerm_logic_app_standard.budget_processor.name
      purpose = "Automated processing of budget alerts and notifications"
    }
    action_group = {
      name    = azurerm_monitor_action_group.budget_alerts.name
      purpose = "Route budget alerts to automated workflows"
    }
    budget = {
      name    = azurerm_consumption_budget_subscription.monthly_budget.name
      amount  = azurerm_consumption_budget_subscription.monthly_budget.amount
      purpose = "Monitor subscription spending and trigger alerts"
    }
    monitoring = {
      application_insights = azurerm_application_insights.budget_monitoring.name
      log_analytics       = var.enable_diagnostic_settings ? azurerm_log_analytics_workspace.budget_monitoring[0].name : "disabled"
      purpose            = "Monitor and troubleshoot budget alert system"
    }
  }
}

# Next Steps and Configuration Guidance
output "next_steps" {
  description = "Instructions for completing the budget alert configuration"
  value = {
    logic_app_configuration = [
      "1. Navigate to the Logic App in Azure Portal: https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_logic_app_standard.budget_processor.id}",
      "2. Create a new workflow named 'budget-alert-webhook'",
      "3. Configure HTTP Request trigger to accept POST requests",
      "4. Add Parse JSON action to process budget alert payload",
      "5. Configure Office 365 Outlook connector for email notifications",
      "6. Test the workflow with sample budget alert data",
      "7. Enable the workflow and monitor execution history"
    ]
    testing_instructions = [
      "1. Monitor current subscription spending in Cost Management",
      "2. Create test spending to trigger alert thresholds (if safe to do so)",
      "3. Verify Action Group receives alerts and triggers Logic App",
      "4. Check Logic App execution history for successful runs",
      "5. Confirm email notifications are delivered correctly",
      "6. Review Application Insights for any errors or performance issues"
    ]
    cost_optimization = [
      "1. Monitor Logic App execution frequency and costs",
      "2. Adjust App Service Plan SKU based on actual usage",
      "3. Review storage account usage and costs",
      "4. Configure storage lifecycle policies if needed",
      "5. Set up budget alerts for the monitoring infrastructure itself"
    ]
  }
}

# Resource Tags Applied
output "applied_tags" {
  description = "Tags applied to all resources for governance and cost tracking"
  value       = local.common_tags
}