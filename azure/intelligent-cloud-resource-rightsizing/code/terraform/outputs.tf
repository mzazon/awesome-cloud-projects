# Output values for Azure Resource Rightsizing Automation
# This file defines the output values that are returned after deployment

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
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.rightsizing_function.name
}

output "function_app_id" {
  description = "ID of the Azure Function App"
  value       = azurerm_linux_function_app.rightsizing_function.id
}

output "function_app_url" {
  description = "Default hostname of the Azure Function App"
  value       = "https://${azurerm_linux_function_app.rightsizing_function.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_linux_function_app.rightsizing_function.identity[0].principal_id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account used by the Function App"
  value       = azurerm_storage_account.function_storage.name
}

output "storage_account_id" {
  description = "ID of the storage account used by the Function App"
  value       = azurerm_storage_account.function_storage.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.function_storage.primary_blob_endpoint
}

# Log Analytics and Monitoring Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace (for queries)"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

# Logic App Information
output "logic_app_name" {
  description = "Name of the Logic App workflow"
  value       = azurerm_logic_app_workflow.rightsizing_workflow.name
}

output "logic_app_id" {
  description = "ID of the Logic App workflow"
  value       = azurerm_logic_app_workflow.rightsizing_workflow.id
}

output "logic_app_access_endpoint" {
  description = "Access endpoint of the Logic App workflow"
  value       = azurerm_logic_app_workflow.rightsizing_workflow.access_endpoint
}

# Cost Management Information
output "cost_budget_name" {
  description = "Name of the cost budget (if enabled)"
  value       = var.enable_cost_alerts ? azurerm_consumption_budget_subscription.rightsizing_budget[0].name : null
}

output "cost_budget_amount" {
  description = "Amount of the cost budget"
  value       = var.cost_budget_amount
}

output "cost_alert_threshold" {
  description = "Threshold percentage for cost alerts"
  value       = var.cost_alert_threshold
}

# Action Group Information
output "action_group_name" {
  description = "Name of the action group for alerts (if enabled)"
  value       = var.enable_cost_alerts ? azurerm_monitor_action_group.rightsizing_alerts[0].name : null
}

output "action_group_id" {
  description = "ID of the action group for alerts (if enabled)"
  value       = var.enable_cost_alerts ? azurerm_monitor_action_group.rightsizing_alerts[0].id : null
}

# Test Resources Information (if enabled)
output "test_vm_name" {
  description = "Name of the test virtual machine (if enabled)"
  value       = var.enable_test_resources ? azurerm_linux_virtual_machine.test_vm[0].name : null
}

output "test_vm_id" {
  description = "ID of the test virtual machine (if enabled)"
  value       = var.enable_test_resources ? azurerm_linux_virtual_machine.test_vm[0].id : null
}

output "test_vm_public_ip" {
  description = "Public IP address of the test virtual machine (if enabled)"
  value       = var.enable_test_resources ? azurerm_public_ip.test_vm_pip[0].ip_address : null
}

output "test_webapp_name" {
  description = "Name of the test web application (if enabled)"
  value       = var.enable_test_resources ? azurerm_linux_web_app.test_webapp[0].name : null
}

output "test_webapp_url" {
  description = "URL of the test web application (if enabled)"
  value       = var.enable_test_resources ? "https://${azurerm_linux_web_app.test_webapp[0].default_hostname}" : null
}

# Configuration Information
output "rightsizing_schedule" {
  description = "Cron expression for rightsizing analysis schedule"
  value       = var.rightsizing_schedule
}

output "cpu_thresholds" {
  description = "CPU utilization thresholds for rightsizing recommendations"
  value = {
    low  = var.cpu_threshold_low
    high = var.cpu_threshold_high
  }
}

output "analysis_period_days" {
  description = "Number of days analyzed for rightsizing recommendations"
  value       = var.analysis_period_days
}

output "auto_scaling_enabled" {
  description = "Whether automatic scaling actions are enabled"
  value       = var.enable_auto_scaling
}

output "cost_alerts_enabled" {
  description = "Whether cost management alerts are enabled"
  value       = var.enable_cost_alerts
}

output "test_resources_enabled" {
  description = "Whether test resources are deployed"
  value       = var.enable_test_resources
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

output "random_suffix" {
  description = "Random suffix used in resource names"
  value       = random_string.suffix.result
}

output "subscription_id" {
  description = "Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}

output "tenant_id" {
  description = "Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

# Next Steps Information
output "next_steps" {
  description = "Next steps after deployment"
  value = {
    "1" = "Configure Azure Developer CLI (azd) integration using the Function App URL"
    "2" = "Upload Function App code to enable rightsizing analysis"
    "3" = "Configure Logic App workflow for automated actions"
    "4" = "Set up monitoring dashboards in Azure Monitor"
    "5" = "Test the rightsizing analysis with sample workloads"
  }
}

# Azure Developer CLI Integration Information
output "azd_configuration" {
  description = "Configuration information for Azure Developer CLI integration"
  value = {
    subscription_id    = data.azurerm_client_config.current.subscription_id
    resource_group     = azurerm_resource_group.main.name
    function_app_name  = azurerm_linux_function_app.rightsizing_function.name
    logic_app_name     = azurerm_logic_app_workflow.rightsizing_workflow.name
    location           = azurerm_resource_group.main.location
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of all deployed resources"
  value = {
    resource_group       = azurerm_resource_group.main.name
    function_app         = azurerm_linux_function_app.rightsizing_function.name
    storage_account      = azurerm_storage_account.function_storage.name
    log_analytics        = azurerm_log_analytics_workspace.main.name
    application_insights = azurerm_application_insights.main.name
    logic_app           = azurerm_logic_app_workflow.rightsizing_workflow.name
    cost_budget         = var.enable_cost_alerts ? azurerm_consumption_budget_subscription.rightsizing_budget[0].name : "Not enabled"
    action_group        = var.enable_cost_alerts ? azurerm_monitor_action_group.rightsizing_alerts[0].name : "Not enabled"
    test_vm             = var.enable_test_resources ? azurerm_linux_virtual_machine.test_vm[0].name : "Not enabled"
    test_webapp         = var.enable_test_resources ? azurerm_linux_web_app.test_webapp[0].name : "Not enabled"
  }
}