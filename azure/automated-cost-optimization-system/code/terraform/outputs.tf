# outputs.tf - Output values for the cost optimization infrastructure
# This file defines all output values that can be used by other configurations or for reference

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.cost_optimization.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.cost_optimization.location
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.cost_optimization.id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account for cost data exports"
  value       = azurerm_storage_account.cost_data.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.cost_data.primary_blob_endpoint
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.cost_data.id
}

output "cost_exports_container_name" {
  description = "Name of the container for cost exports"
  value       = azurerm_storage_container.cost_exports.name
}

output "cost_reports_container_name" {
  description = "Name of the container for cost reports"
  value       = azurerm_storage_container.cost_reports.name
}

# Log Analytics Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.cost_optimization.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.cost_optimization.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.cost_optimization.primary_shared_key
  sensitive   = true
}

# Logic App Outputs
output "logic_app_name" {
  description = "Name of the Logic App for cost optimization"
  value       = azurerm_logic_app_standard.cost_optimization.name
}

output "logic_app_id" {
  description = "ID of the Logic App"
  value       = azurerm_logic_app_standard.cost_optimization.id
}

output "logic_app_default_hostname" {
  description = "Default hostname of the Logic App"
  value       = azurerm_logic_app_standard.cost_optimization.default_hostname
}

output "logic_app_trigger_url" {
  description = "Trigger URL for the Logic App workflow"
  value       = "https://${azurerm_logic_app_standard.cost_optimization.default_hostname}/api/cost-optimization/triggers/manual/invoke"
}

# Service Principal Outputs
output "service_principal_application_id" {
  description = "Application ID of the service principal for cost management"
  value       = azuread_application.cost_management.application_id
}

output "service_principal_object_id" {
  description = "Object ID of the service principal"
  value       = azuread_service_principal.cost_management.object_id
}

# Budget Outputs
output "budget_name" {
  description = "Name of the consumption budget"
  value       = azurerm_consumption_budget_subscription.cost_optimization.name
}

output "budget_amount" {
  description = "Amount of the consumption budget"
  value       = azurerm_consumption_budget_subscription.cost_optimization.amount
}

output "budget_id" {
  description = "ID of the consumption budget"
  value       = azurerm_consumption_budget_subscription.cost_optimization.id
}

# Action Group Outputs
output "action_group_name" {
  description = "Name of the action group for cost optimization alerts"
  value       = azurerm_monitor_action_group.cost_optimization.name
}

output "action_group_id" {
  description = "ID of the action group"
  value       = azurerm_monitor_action_group.cost_optimization.id
}

# Key Vault Outputs
output "key_vault_name" {
  description = "Name of the Key Vault for storing secrets"
  value       = azurerm_key_vault.cost_optimization.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.cost_optimization.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.cost_optimization.vault_uri
}

# Cost Anomaly Detection Outputs
output "cost_anomaly_alert_name" {
  description = "Name of the cost anomaly detection alert rule"
  value       = var.enable_anomaly_detection ? azurerm_monitor_metric_alert.cost_anomaly[0].name : null
}

output "cost_anomaly_alert_id" {
  description = "ID of the cost anomaly detection alert rule"
  value       = var.enable_anomaly_detection ? azurerm_monitor_metric_alert.cost_anomaly[0].id : null
}

# Azure Subscription Information
output "subscription_id" {
  description = "Azure subscription ID"
  value       = data.azurerm_subscription.current.subscription_id
}

output "tenant_id" {
  description = "Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

# Configuration Outputs for Post-deployment Setup
output "teams_webhook_configured" {
  description = "Whether Teams webhook URL was configured"
  value       = var.teams_webhook_url != ""
}

output "email_notifications_configured" {
  description = "Whether email notifications were configured"
  value       = length(var.email_notification_addresses) > 0
}

output "anomaly_detection_enabled" {
  description = "Whether cost anomaly detection is enabled"
  value       = var.enable_anomaly_detection
}

# Resource Names for Reference
output "resource_names" {
  description = "Map of all resource names created"
  value = {
    resource_group      = azurerm_resource_group.cost_optimization.name
    storage_account     = azurerm_storage_account.cost_data.name
    log_analytics       = azurerm_log_analytics_workspace.cost_optimization.name
    logic_app          = azurerm_logic_app_standard.cost_optimization.name
    action_group       = azurerm_monitor_action_group.cost_optimization.name
    budget             = azurerm_consumption_budget_subscription.cost_optimization.name
    key_vault          = azurerm_key_vault.cost_optimization.name
    service_principal  = azuread_application.cost_management.display_name
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of the deployed cost optimization infrastructure"
  value = {
    resource_group_name      = azurerm_resource_group.cost_optimization.name
    location                = azurerm_resource_group.cost_optimization.location
    budget_amount           = var.budget_amount
    budget_thresholds       = var.budget_alert_thresholds
    anomaly_detection       = var.enable_anomaly_detection
    export_frequency        = var.export_schedule_frequency
    data_retention_days     = var.cost_data_retention_days
    log_retention_days      = var.log_analytics_retention_days
    email_notifications     = length(var.email_notification_addresses)
    teams_integration       = var.teams_webhook_url != ""
  }
}

# Next Steps and Instructions
output "next_steps" {
  description = "Next steps for completing the cost optimization setup"
  value = {
    logic_app_configuration = "Configure Logic App workflows using the Azure portal or deploy workflow definitions"
    advisor_integration     = "Set up Azure Advisor API calls in the Logic App workflow"
    cost_export_setup      = "Configure cost data exports to the created storage account"
    teams_webhook_setup    = var.teams_webhook_url == "" ? "Configure Teams webhook URL in variables if needed" : "Teams webhook already configured"
    testing_instructions   = "Test the cost optimization workflow by triggering the Logic App manually"
  }
}

# Security and Access Information
output "security_configuration" {
  description = "Security configuration details"
  value = {
    service_principal_roles = ["Cost Management Reader", "Cost Management Contributor"]
    key_vault_access       = "Service principal has read access to secrets"
    storage_security       = "HTTPS only, TLS 1.2 minimum, private container access"
    rbac_enabled          = var.enable_rbac
  }
  sensitive = false
}

# Cost Optimization URLs and Endpoints
output "management_urls" {
  description = "URLs for managing the cost optimization solution"
  value = {
    resource_group_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_resource_group.cost_optimization.id}"
    logic_app_url      = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_logic_app_standard.cost_optimization.id}"
    budget_url         = "https://portal.azure.com/#blade/Microsoft_Azure_CostManagement/Menu/budgets"
    cost_analysis_url  = "https://portal.azure.com/#blade/Microsoft_Azure_CostManagement/Menu/costanalysis"
    advisor_url        = "https://portal.azure.com/#blade/Microsoft_Azure_Expert/AdvisorMenuBlade/overview"
  }
}