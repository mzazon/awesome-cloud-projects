# Outputs for Azure Cost Budget Tracking Infrastructure
# These outputs provide important information about created resources
# and access details for monitoring and management

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group for cost tracking resources"
  value       = azurerm_resource_group.cost_tracking.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.cost_tracking.id
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.cost_tracking.location
}

# Action Group Information
output "action_group_name" {
  description = "Name of the Azure Monitor Action Group for cost alerts"
  value       = azurerm_monitor_action_group.cost_alerts.name
}

output "action_group_id" {
  description = "ID of the Azure Monitor Action Group"
  value       = azurerm_monitor_action_group.cost_alerts.id
}

output "action_group_short_name" {
  description = "Short name of the Action Group (used in SMS messages)"
  value       = azurerm_monitor_action_group.cost_alerts.short_name
}

# Budget Information
output "main_budget_name" {
  description = "Name of the main subscription budget"
  value       = azurerm_consumption_budget_subscription.main_budget.name
}

output "main_budget_id" {
  description = "ID of the main subscription budget"
  value       = azurerm_consumption_budget_subscription.main_budget.id
}

output "main_budget_amount" {
  description = "Budget amount in USD"
  value       = azurerm_consumption_budget_subscription.main_budget.amount
}

output "main_budget_time_grain" {
  description = "Time period for budget tracking"
  value       = azurerm_consumption_budget_subscription.main_budget.time_grain
}

output "filtered_budget_name" {
  description = "Name of the resource group filtered budget (if enabled)"
  value       = var.enable_resource_group_filter ? azurerm_consumption_budget_subscription.filtered_budget[0].name : null
}

output "filtered_budget_id" {
  description = "ID of the resource group filtered budget (if enabled)"
  value       = var.enable_resource_group_filter ? azurerm_consumption_budget_subscription.filtered_budget[0].id : null
}

# Configuration Information
output "email_recipients" {
  description = "List of email addresses configured to receive budget alerts"
  value       = var.email_addresses
  sensitive   = true  # Mark as sensitive to protect email addresses
}

output "alert_thresholds" {
  description = "Configured alert thresholds and their settings"
  value = [
    for threshold in var.alert_thresholds : {
      threshold      = threshold.threshold
      threshold_type = threshold.threshold_type
      operator       = threshold.operator
    }
  ]
}

output "contact_roles" {
  description = "Azure RBAC roles configured to receive notifications"
  value       = var.contact_roles
}

# Budget Time Period Information
output "budget_start_date" {
  description = "Start date of the budget period"
  value       = local.budget_start_date
}

output "budget_end_date" {
  description = "End date of the budget period"
  value       = local.budget_end_date
}

# Azure Portal Links
output "cost_management_portal_url" {
  description = "Direct link to Azure Cost Management in the portal"
  value       = "https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/overview"
}

output "budgets_portal_url" {
  description = "Direct link to budgets view in Azure Cost Management"
  value       = "https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/budgets"
}

output "action_group_portal_url" {
  description = "Direct link to the Action Group in Azure Monitor"
  value       = "https://portal.azure.com/#@/resource${azurerm_monitor_action_group.cost_alerts.id}"
}

# Subscription Information
output "subscription_id" {
  description = "ID of the Azure subscription being monitored"
  value       = data.azurerm_subscription.current.subscription_id
}

output "subscription_display_name" {
  description = "Display name of the Azure subscription"
  value       = data.azurerm_subscription.current.display_name
}

# Resource Filtering Information
output "resource_group_filtering_enabled" {
  description = "Whether resource group filtering is enabled for budget"
  value       = var.enable_resource_group_filter
}

output "filtered_resource_groups" {
  description = "List of resource groups being monitored (if filtering enabled)"
  value       = var.enable_resource_group_filter ? (length(var.filter_resource_groups) > 0 ? var.filter_resource_groups : [azurerm_resource_group.cost_tracking.name]) : null
}

# Deployment Information
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.random_suffix
}

output "deployment_tags" {
  description = "Tags applied to all resources"
  value       = var.tags
}

# Instructions for Users
output "next_steps" {
  description = "Next steps after deployment"
  value = <<-EOT
    Cost Budget Tracking has been successfully deployed!
    
    Next Steps:
    1. Visit the Azure Cost Management portal: ${local.cost_management_portal_url}
    2. Check your email for test notifications from: azure-noreply@microsoft.com
    3. Monitor budget performance and cost trends in the portal
    4. Adjust alert thresholds if needed using Terraform variables
    
    Budget Details:
    - Budget Amount: $${var.budget_amount}
    - Time Period: ${var.budget_time_grain}
    - Alert Thresholds: ${join(", ", [for t in var.alert_thresholds : "${t.threshold}%"])}
    
    Email Recipients: ${length(var.email_addresses)} configured
    Resource Group Filter: ${var.enable_resource_group_filter ? "Enabled" : "Disabled"}
  EOT
}

# Local values for URLs (used in outputs)
locals {
  cost_management_portal_url = "https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/overview"
}