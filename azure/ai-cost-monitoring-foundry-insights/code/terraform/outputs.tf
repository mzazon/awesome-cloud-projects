# Output values for Azure AI Cost Monitoring with Foundry and Application Insights
# These outputs provide important resource information after deployment

# ==============================================================================
# CORE RESOURCE INFORMATION
# ==============================================================================

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# ==============================================================================
# AI FOUNDRY WORKSPACE INFORMATION
# ==============================================================================

output "ai_hub_name" {
  description = "Name of the Azure AI Foundry Hub"
  value       = azurerm_machine_learning_workspace.hub.name
}

output "ai_hub_id" {
  description = "ID of the Azure AI Foundry Hub"
  value       = azurerm_machine_learning_workspace.hub.id
}

output "ai_hub_workspace_id" {
  description = "Workspace ID of the Azure AI Foundry Hub"
  value       = azurerm_machine_learning_workspace.hub.workspace_id
}

output "ai_project_name" {
  description = "Name of the Azure AI Foundry Project"
  value       = azurerm_machine_learning_workspace.project.name
}

output "ai_project_id" {
  description = "ID of the Azure AI Foundry Project"
  value       = azurerm_machine_learning_workspace.project.id
}

output "ai_project_workspace_id" {
  description = "Workspace ID of the Azure AI Foundry Project"
  value       = azurerm_machine_learning_workspace.project.workspace_id
}

# ==============================================================================
# MONITORING AND ANALYTICS INFORMATION
# ==============================================================================

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
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

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key for Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# ==============================================================================
# STORAGE ACCOUNT INFORMATION
# ==============================================================================

output "storage_account_name" {
  description = "Name of the Storage Account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the Storage Account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint of the Storage Account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the Storage Account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

# ==============================================================================
# KEY VAULT INFORMATION
# ==============================================================================

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

# ==============================================================================
# COST MANAGEMENT INFORMATION
# ==============================================================================

output "budget_name" {
  description = "Name of the consumption budget"
  value       = azurerm_consumption_budget_resource_group.ai_budget.name
}

output "budget_amount" {
  description = "Monthly budget amount in USD"
  value       = azurerm_consumption_budget_resource_group.ai_budget.amount
}

output "action_group_name" {
  description = "Name of the Action Group for alerts"
  value       = azurerm_monitor_action_group.cost_alerts.name
}

output "action_group_id" {
  description = "ID of the Action Group for alerts"
  value       = azurerm_monitor_action_group.cost_alerts.id
}

# ==============================================================================
# MONITORING DASHBOARD INFORMATION
# ==============================================================================

output "workbook_name" {
  description = "Name of the Azure Monitor Workbook"
  value       = azurerm_application_insights_workbook.ai_cost_dashboard.display_name
}

output "workbook_id" {
  description = "ID of the Azure Monitor Workbook"
  value       = azurerm_application_insights_workbook.ai_cost_dashboard.id
}

# ==============================================================================
# ALERT CONFIGURATION INFORMATION
# ==============================================================================

output "metric_alert_request_rate_name" {
  description = "Name of the high request rate metric alert"
  value       = azurerm_monitor_metric_alert.high_request_rate.name
}

output "metric_alert_exception_rate_name" {
  description = "Name of the high exception rate metric alert"
  value       = azurerm_monitor_metric_alert.high_exception_rate.name
}

# ==============================================================================
# INTEGRATION ENDPOINTS AND URLS
# ==============================================================================

output "azure_portal_resource_group_url" {
  description = "Azure Portal URL for the resource group"
  value       = "https://portal.azure.com/#@/resource${azurerm_resource_group.main.id}"
}

output "azure_ml_studio_hub_url" {
  description = "Azure ML Studio URL for the AI Foundry Hub"
  value       = "https://ml.azure.com/workspaces/${azurerm_machine_learning_workspace.hub.workspace_id}/overview"
}

output "azure_ml_studio_project_url" {
  description = "Azure ML Studio URL for the AI Foundry Project"
  value       = "https://ml.azure.com/workspaces/${azurerm_machine_learning_workspace.project.workspace_id}/overview"
}

output "application_insights_portal_url" {
  description = "Azure Portal URL for Application Insights"
  value       = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}/overview"
}

# ==============================================================================
# SAMPLE CONFIGURATION FOR CLIENT APPLICATIONS
# ==============================================================================

output "sample_application_config" {
  description = "Sample configuration for client applications"
  value = {
    application_insights = {
      connection_string     = azurerm_application_insights.main.connection_string
      instrumentation_key  = azurerm_application_insights.main.instrumentation_key
    }
    ai_foundry = {
      hub_name           = azurerm_machine_learning_workspace.hub.name
      project_name       = azurerm_machine_learning_workspace.project.name
      hub_workspace_id   = azurerm_machine_learning_workspace.hub.workspace_id
      project_workspace_id = azurerm_machine_learning_workspace.project.workspace_id
    }
    storage = {
      account_name = azurerm_storage_account.main.name
      blob_endpoint = azurerm_storage_account.main.primary_blob_endpoint
    }
  }
  sensitive = true
}

# ==============================================================================
# RESOURCE TAGS FOR REFERENCE
# ==============================================================================

output "applied_tags" {
  description = "Tags applied to all resources"
  value       = local.tags
}

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group           = azurerm_resource_group.main.name
    ai_foundry_hub          = azurerm_machine_learning_workspace.hub.name
    ai_foundry_project      = azurerm_machine_learning_workspace.project.name
    application_insights    = azurerm_application_insights.main.name
    log_analytics_workspace = azurerm_log_analytics_workspace.main.name
    storage_account         = azurerm_storage_account.main.name
    key_vault              = azurerm_key_vault.main.name
    budget_amount          = "${azurerm_consumption_budget_resource_group.ai_budget.amount} USD"
    action_group           = azurerm_monitor_action_group.cost_alerts.name
    workbook               = azurerm_application_insights_workbook.ai_cost_dashboard.display_name
    location               = azurerm_resource_group.main.location
  }
}