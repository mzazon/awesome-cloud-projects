# outputs.tf
# Output values for the Azure Logic Apps schedule reminder solution
# These outputs provide important information for verification and integration

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
  description = "Resource ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# Logic App Information
output "logic_app_name" {
  description = "Name of the created Logic App workflow"
  value       = azurerm_logic_app_workflow.reminder.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic App workflow"
  value       = azurerm_logic_app_workflow.reminder.id
}

output "logic_app_state" {
  description = "Current state of the Logic App workflow (Enabled/Disabled)"
  value       = azurerm_logic_app_workflow.reminder.enabled ? "Enabled" : "Disabled"
}

output "logic_app_access_endpoint" {
  description = "Access endpoint URL for the Logic App workflow"
  value       = azurerm_logic_app_workflow.reminder.access_endpoint
}

output "logic_app_callback_url" {
  description = "Callback URL for manually triggering the Logic App (sensitive)"
  value       = azurerm_logic_app_workflow.reminder.callback_url
  sensitive   = true
}

# Office 365 Connection Information
output "office365_connection_name" {
  description = "Name of the Office 365 Outlook connection"
  value       = azurerm_api_connection.office365.name
}

output "office365_connection_id" {
  description = "Resource ID of the Office 365 Outlook connection"
  value       = azurerm_api_connection.office365.id
}

output "office365_connection_status" {
  description = "Connection status of the Office 365 Outlook connector"
  value       = azurerm_api_connection.office365.connection_status
}

# Schedule Configuration
output "reminder_schedule" {
  description = "Configured schedule for the reminder notifications"
  value = {
    frequency = var.recurrence_frequency
    interval  = var.recurrence_interval
    hours     = var.schedule_hours
    minutes   = var.schedule_minutes
    weekdays  = var.recurrence_frequency == "Week" ? var.schedule_weekdays : null
  }
}

# Email Configuration
output "email_recipient" {
  description = "Email address configured to receive reminders"
  value       = var.email_recipient
}

output "email_subject" {
  description = "Subject line configured for reminder emails"
  value       = var.email_subject
}

# Azure Portal URLs for Management
output "azure_portal_urls" {
  description = "Azure Portal URLs for managing the deployed resources"
  value = {
    resource_group = "https://portal.azure.com/#@/resource${azurerm_resource_group.main.id}/overview"
    logic_app      = "https://portal.azure.com/#@/resource${azurerm_logic_app_workflow.reminder.id}/overview"
    logic_app_runs = "https://portal.azure.com/#@/resource${azurerm_logic_app_workflow.reminder.id}/runs"
    office365_connection = "https://portal.azure.com/#@/resource${azurerm_api_connection.office365.id}/overview"
  }
}

# Monitoring Information (when enabled)
output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace (if created)"
  value       = length(azurerm_log_analytics_workspace.monitoring) > 0 ? azurerm_log_analytics_workspace.monitoring[0].id : null
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if created)"
  value       = length(azurerm_log_analytics_workspace.monitoring) > 0 ? azurerm_log_analytics_workspace.monitoring[0].name : null
}

# Cost Estimation Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost in USD based on Azure Logic Apps consumption pricing"
  value = {
    logic_app_executions = "~$0.05-0.10 for weekly executions"
    api_connections     = "No additional cost for Office 365 Outlook connector"
    log_analytics       = length(azurerm_log_analytics_workspace.monitoring) > 0 ? "~$2.30 per GB ingested" : "Not enabled"
    total_estimate      = "~$0.05-0.15 per month for basic usage"
  }
}

# Workflow Information for CLI Access
output "workflow_trigger_info" {
  description = "Information needed to manually trigger the workflow via CLI"
  value = {
    resource_group = azurerm_resource_group.main.name
    workflow_name  = azurerm_logic_app_workflow.reminder.name
    trigger_name   = "Recurrence"
    cli_command    = "az logic workflow trigger run --resource-group ${azurerm_resource_group.main.name} --workflow-name ${azurerm_logic_app_workflow.reminder.name} --trigger-name Recurrence"
  }
}

# Resource Tags
output "applied_tags" {
  description = "Tags applied to all created resources"
  value       = local.common_tags
}

# Connection Setup Instructions
output "post_deployment_instructions" {
  description = "Instructions for completing the Office 365 connection setup"
  value = {
    step1 = "Navigate to the Azure Portal using the office365_connection URL in azure_portal_urls"
    step2 = "Click on 'Edit API connection' or look for authentication status"
    step3 = "If authentication is required, click 'Authorize' and sign in with your Office 365 account"
    step4 = "Verify the connection status shows as 'Connected'"
    step5 = "Test the Logic App using the CLI command provided in workflow_trigger_info"
    note  = "The Office 365 connection requires manual authentication for security reasons"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration applied to the Logic App"
  value = {
    access_control_enabled = var.workflow_access_control != {} ? true : false
    connection_authentication = "OAuth 2.0 with Office 365"
    https_only = true
    managed_identity = "System-assigned (for Azure resource access)"
  }
}

# Next Steps and Management
output "management_commands" {
  description = "Useful Azure CLI commands for managing the deployed resources"
  value = {
    check_logic_app_status = "az logic workflow show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_logic_app_workflow.reminder.name} --query '{name:name, state:state, location:location}' --output table"
    view_run_history      = "az logic workflow run list --resource-group ${azurerm_resource_group.main.name} --workflow-name ${azurerm_logic_app_workflow.reminder.name} --top 5 --query '[].{status:status, startTime:startTime, endTime:endTime}' --output table"
    disable_logic_app     = "az logic workflow update --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_logic_app_workflow.reminder.name} --state Disabled"
    enable_logic_app      = "az logic workflow update --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_logic_app_workflow.reminder.name} --state Enabled"
  }
}