# Outputs for Azure sustainable workload optimization infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group created for carbon optimization"
  value       = azurerm_resource_group.carbon_optimization.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.carbon_optimization.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.carbon_optimization.id
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.carbon_optimization.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.carbon_optimization.id
}

output "log_analytics_workspace_resource_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.carbon_optimization.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.carbon_optimization.primary_shared_key
  sensitive   = true
}

output "log_analytics_workspace_secondary_shared_key" {
  description = "Secondary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.carbon_optimization.secondary_shared_key
  sensitive   = true
}

# Azure Automation Account Information
output "automation_account_name" {
  description = "Name of the Azure Automation account"
  value       = azurerm_automation_account.carbon_optimization.name
}

output "automation_account_id" {
  description = "ID of the Azure Automation account"
  value       = azurerm_automation_account.carbon_optimization.id
}

output "automation_account_endpoint" {
  description = "Endpoint URL of the Azure Automation account"
  value       = azurerm_automation_account.carbon_optimization.endpoint
}

output "automation_account_identity_principal_id" {
  description = "Principal ID of the Automation account's managed identity"
  value       = azurerm_automation_account.carbon_optimization.identity[0].principal_id
}

output "automation_account_identity_tenant_id" {
  description = "Tenant ID of the Automation account's managed identity"
  value       = azurerm_automation_account.carbon_optimization.identity[0].tenant_id
}

# Runbook Information
output "carbon_monitoring_runbook_name" {
  description = "Name of the carbon monitoring runbook"
  value       = var.enable_automation ? azurerm_automation_runbook.carbon_monitoring[0].name : null
}

output "automated_remediation_runbook_name" {
  description = "Name of the automated remediation runbook"
  value       = var.enable_automation ? azurerm_automation_runbook.automated_remediation[0].name : null
}

# Schedule Information
output "monitoring_schedule_name" {
  description = "Name of the monitoring schedule"
  value       = var.enable_automation ? azurerm_automation_schedule.daily_monitoring[0].name : null
}

output "monitoring_schedule_next_run" {
  description = "Next run time for the monitoring schedule"
  value       = var.enable_automation ? azurerm_automation_schedule.daily_monitoring[0].start_time : null
}

# Action Group Information
output "action_group_name" {
  description = "Name of the action group for carbon optimization alerts"
  value       = var.enable_alerts ? azurerm_monitor_action_group.carbon_optimization[0].name : null
}

output "action_group_id" {
  description = "ID of the action group"
  value       = var.enable_alerts ? azurerm_monitor_action_group.carbon_optimization[0].id : null
}

# Alert Information
output "high_carbon_impact_alert_name" {
  description = "Name of the high carbon impact alert"
  value       = var.enable_alerts ? azurerm_monitor_metric_alert.high_carbon_impact[0].name : null
}

output "carbon_optimization_opportunities_alert_name" {
  description = "Name of the carbon optimization opportunities alert"
  value       = var.enable_alerts ? azurerm_monitor_scheduled_query_rules_alert_v2.carbon_optimization_opportunities[0].name : null
}

# Workbook Information
output "carbon_optimization_workbook_name" {
  description = "Name of the carbon optimization workbook"
  value       = var.enable_workbook ? azurerm_application_insights_workbook.carbon_optimization[0].name : null
}

output "carbon_optimization_workbook_id" {
  description = "ID of the carbon optimization workbook"
  value       = var.enable_workbook ? azurerm_application_insights_workbook.carbon_optimization[0].id : null
}

# Subscription and Tenant Information
output "subscription_id" {
  description = "ID of the Azure subscription"
  value       = data.azurerm_subscription.current.subscription_id
}

output "tenant_id" {
  description = "ID of the Azure tenant"
  value       = data.azurerm_client_config.current.tenant_id
}

# Resource URLs for easy access
output "log_analytics_workspace_url" {
  description = "URL to access the Log Analytics workspace in Azure portal"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_log_analytics_workspace.carbon_optimization.id}"
}

output "automation_account_url" {
  description = "URL to access the Automation account in Azure portal"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_automation_account.carbon_optimization.id}"
}

output "carbon_optimization_workbook_url" {
  description = "URL to access the carbon optimization workbook in Azure portal"
  value       = var.enable_workbook ? "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_application_insights_workbook.carbon_optimization[0].id}" : null
}

# Configuration Information
output "carbon_optimization_configuration" {
  description = "Configuration summary for carbon optimization setup"
  value = {
    environment                    = var.environment
    project_name                  = var.project_name
    location                      = var.location
    carbon_optimization_threshold = var.carbon_optimization_threshold
    monitoring_schedule_frequency = var.monitoring_schedule_frequency
    monitoring_schedule_interval  = var.monitoring_schedule_interval
    automation_enabled            = var.enable_automation
    alerts_enabled                = var.enable_alerts
    workbook_enabled              = var.enable_workbook
    rbac_enabled                  = var.enable_rbac
    log_retention_days            = var.log_analytics_retention_days
  }
}

# Commands for manual operations
output "azure_cli_commands" {
  description = "Useful Azure CLI commands for managing carbon optimization"
  value = {
    # View carbon optimization data
    view_carbon_data = "az rest --method GET --url 'https://management.azure.com/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Sustainability/carbonEmissions?api-version=2023-11-01-preview'"
    
    # Start carbon monitoring runbook
    start_monitoring = var.enable_automation ? "az automation runbook start --resource-group ${azurerm_resource_group.carbon_optimization.name} --automation-account-name ${azurerm_automation_account.carbon_optimization.name} --name ${azurerm_automation_runbook.carbon_monitoring[0].name}" : null
    
    # Query Log Analytics for carbon optimization data
    query_carbon_data = "az monitor log-analytics query --workspace ${azurerm_log_analytics_workspace.carbon_optimization.workspace_id} --analytics-query 'CarbonOptimization_CL | take 10'"
    
    # Check automation account jobs
    check_jobs = "az automation job list --resource-group ${azurerm_resource_group.carbon_optimization.name} --automation-account-name ${azurerm_automation_account.carbon_optimization.name}"
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for carbon optimization infrastructure"
  value = {
    log_analytics_workspace = "Based on data ingestion and retention (typically $2-5 per GB ingested)"
    automation_account      = var.automation_account_sku == "Free" ? "$0 (Free tier - 500 minutes/month)" : "$5-15 per month"
    monitoring_alerts       = "$0.10 per alert rule per month"
    workbook               = "$0 (included with Log Analytics)"
    total_estimated        = "$15-25 per month (depends on data volume and usage)"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration details"
  value = {
    managed_identity_enabled = "Yes - System-assigned managed identity for secure authentication"
    rbac_enabled            = var.enable_rbac
    role_assignments = var.enable_rbac ? {
      carbon_optimization_reader = "Reader role assigned to managed identity"
      resource_contributor       = var.enable_automation ? "Contributor role assigned to managed identity" : "Not assigned"
    } : {}
    sensitive_data_protection = "Log Analytics workspace keys are marked as sensitive"
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    step_1 = "Access the Azure portal using the provided URLs to verify resource deployment"
    step_2 = "Configure additional email recipients in the action group if needed"
    step_3 = "Customize the carbon optimization workbook with your specific KPIs"
    step_4 = "Set up additional alert rules based on your organization's sustainability goals"
    step_5 = "Review and customize the PowerShell runbooks for your specific remediation needs"
    step_6 = "Schedule regular reviews of carbon optimization recommendations"
  }
}