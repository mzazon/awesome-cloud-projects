# Resource Group outputs
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

# Application Insights outputs
output "application_insights_name" {
  description = "Name of the Application Insights resource"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights resource"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = azurerm_application_insights.main.app_id
}

# Log Analytics Workspace outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# Logic App outputs
output "logic_app_name" {
  description = "Name of the Logic App workflow"
  value       = azurerm_logic_app_workflow.quality_feedback.name
}

output "logic_app_id" {
  description = "ID of the Logic App workflow"
  value       = azurerm_logic_app_workflow.quality_feedback.id
}

output "logic_app_trigger_url" {
  description = "HTTP trigger URL for the Logic App"
  value       = azurerm_logic_app_trigger_http_request.quality_trigger.callback_url
  sensitive   = true
}

output "logic_app_access_endpoint" {
  description = "Access endpoint for the Logic App"
  value       = azurerm_logic_app_workflow.quality_feedback.access_endpoint
}

# Storage Account outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.logic_apps.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.logic_apps.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint of the storage account"
  value       = azurerm_storage_account.logic_apps.primary_blob_endpoint
}

output "storage_account_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.logic_apps.primary_connection_string
  sensitive   = true
}

# App Service Plan outputs
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.logic_apps.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.logic_apps.id
}

# Key Vault outputs
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Dashboard outputs
output "dashboard_name" {
  description = "Name of the monitoring dashboard"
  value       = azurerm_dashboard.quality_dashboard.name
}

output "dashboard_id" {
  description = "ID of the monitoring dashboard"
  value       = azurerm_dashboard.quality_dashboard.id
}

# Monitoring outputs
output "action_group_name" {
  description = "Name of the action group for alerts"
  value       = var.enable_monitoring ? azurerm_monitor_action_group.quality_alerts[0].name : "Not created"
}

output "action_group_id" {
  description = "ID of the action group for alerts"
  value       = var.enable_monitoring ? azurerm_monitor_action_group.quality_alerts[0].id : "Not created"
}

# Configuration outputs for Azure DevOps integration
output "devops_integration_config" {
  description = "Configuration values for Azure DevOps integration"
  value = {
    organization_name    = var.devops_organization_name
    project_name        = var.devops_project_name
    project_visibility  = var.devops_project_visibility
    quality_threshold   = var.quality_threshold
    environment        = var.environment
  }
}

# Quality pipeline configuration
output "quality_pipeline_config" {
  description = "Configuration for the quality pipeline"
  value = {
    logic_app_trigger_url_secret_name = azurerm_key_vault_secret.logic_app_trigger_url.name
    app_insights_key_secret_name     = azurerm_key_vault_secret.app_insights_key.name
    app_insights_connection_secret_name = azurerm_key_vault_secret.app_insights_connection_string.name
    quality_threshold               = var.quality_threshold
    key_vault_name                 = azurerm_key_vault.main.name
  }
}

# Security and compliance outputs
output "security_config" {
  description = "Security configuration summary"
  value = {
    min_tls_version                = var.min_tls_version
    https_only_enabled            = var.enable_https_only
    storage_public_access_blocked = true
    key_vault_soft_delete_enabled = true
  }
}

# Cost optimization outputs
output "cost_optimization_config" {
  description = "Cost optimization configuration"
  value = {
    auto_scaling_enabled     = var.enable_auto_scaling
    backup_retention_days    = var.backup_retention_days
    storage_tier            = var.storage_account_tier
    storage_replication     = var.storage_account_replication_type
    app_insights_retention  = var.application_insights_retention_days
  }
}

# Resource summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    resource_group          = azurerm_resource_group.main.name
    application_insights    = azurerm_application_insights.main.name
    logic_app              = azurerm_logic_app_workflow.quality_feedback.name
    storage_account        = azurerm_storage_account.logic_apps.name
    log_analytics_workspace = azurerm_log_analytics_workspace.main.name
    key_vault              = azurerm_key_vault.main.name
    dashboard              = azurerm_dashboard.quality_dashboard.name
    monitoring_enabled     = var.enable_monitoring
  }
}

# URLs and endpoints for easy access
output "access_urls" {
  description = "URLs for accessing the deployed resources"
  value = {
    azure_portal_dashboard = "https://portal.azure.com/#@/dashboard/arm${azurerm_dashboard.quality_dashboard.id}"
    application_insights   = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}"
    logic_app             = "https://portal.azure.com/#@/resource${azurerm_logic_app_workflow.quality_feedback.id}"
    key_vault             = "https://portal.azure.com/#@/resource${azurerm_key_vault.main.id}"
    log_analytics         = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}"
  }
}

# Next steps and integration guidance
output "next_steps" {
  description = "Next steps for completing the setup"
  value = {
    azure_devops_setup = "Configure Azure DevOps project with name: ${var.devops_project_name}"
    pipeline_integration = "Use the Logic App trigger URL from Key Vault in your Azure DevOps pipeline"
    monitoring_setup = "Configure alerts and notifications using the Action Group: ${var.enable_monitoring ? azurerm_monitor_action_group.quality_alerts[0].name : "Not created"}"
    dashboard_access = "Access the monitoring dashboard through the Azure Portal"
  }
}