# Output values for the Content Moderation Infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for content"
  value       = azurerm_storage_account.content_storage.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.content_storage.primary_blob_endpoint
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.content_storage.id
}

output "storage_containers" {
  description = "List of created storage containers"
  value = {
    uploads    = azurerm_storage_container.uploads.name
    quarantine = azurerm_storage_container.quarantine.name
    approved   = azurerm_storage_container.approved.name
  }
}

output "storage_queue_name" {
  description = "Name of the content processing queue"
  value       = azurerm_storage_queue.content_processing.name
}

# AI Content Safety Information
output "ai_content_safety_name" {
  description = "Name of the AI Content Safety service"
  value       = azurerm_cognitive_account.content_safety.name
}

output "ai_content_safety_endpoint" {
  description = "Endpoint URL for AI Content Safety service"
  value       = azurerm_cognitive_account.content_safety.endpoint
}

output "ai_content_safety_id" {
  description = "Resource ID of the AI Content Safety service"
  value       = azurerm_cognitive_account.content_safety.id
}

# Logic App Information
output "logic_app_name" {
  description = "Name of the Logic App workflow"
  value       = azurerm_logic_app_workflow.content_moderation.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic App workflow"
  value       = azurerm_logic_app_workflow.content_moderation.id
}

output "logic_app_access_endpoint" {
  description = "Access endpoint for the Logic App"
  value       = azurerm_logic_app_workflow.content_moderation.access_endpoint
}

output "logic_app_principal_id" {
  description = "Principal ID of the Logic App managed identity"
  value       = azurerm_logic_app_workflow.content_moderation.identity[0].principal_id
}

# Event Grid Information
output "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  value       = azurerm_eventgrid_topic.content_events.name
}

output "event_grid_topic_endpoint" {
  description = "Endpoint URL for the Event Grid topic"
  value       = azurerm_eventgrid_topic.content_events.endpoint
}

output "event_grid_topic_id" {
  description = "Resource ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.content_events.id
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.content_processor.name
}

output "function_app_id" {
  description = "Resource ID of the Function App"
  value       = azurerm_linux_function_app.content_processor.id
}

output "function_app_hostname" {
  description = "Hostname of the Function App"
  value       = azurerm_linux_function_app.content_processor.default_hostname
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_linux_function_app.content_processor.identity[0].principal_id
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
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

# Log Analytics Information (conditional)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

# Monitoring Information (conditional)
output "action_group_name" {
  description = "Name of the monitoring action group"
  value       = var.enable_monitoring && var.notification_email != "" ? azurerm_monitor_action_group.content_moderation_alerts[0].name : null
}

output "action_group_id" {
  description = "Resource ID of the monitoring action group"
  value       = var.enable_monitoring && var.notification_email != "" ? azurerm_monitor_action_group.content_moderation_alerts[0].id : null
}

# Configuration Information
output "content_safety_categories" {
  description = "Configured content safety categories"
  value       = var.content_safety_categories
}

output "content_safety_severity_threshold" {
  description = "Configured severity threshold for content quarantine"
  value       = var.content_safety_severity_threshold
}

# Connection Information (for integration)
output "storage_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.content_storage.primary_connection_string
  sensitive   = true
}

output "ai_content_safety_key" {
  description = "Primary access key for AI Content Safety service"
  value       = azurerm_cognitive_account.content_safety.primary_access_key
  sensitive   = true
}

output "event_grid_access_key" {
  description = "Primary access key for Event Grid topic"
  value       = azurerm_eventgrid_topic.content_events.primary_access_key
  sensitive   = true
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group      = azurerm_resource_group.main.name
    storage_account     = azurerm_storage_account.content_storage.name
    ai_content_safety   = azurerm_cognitive_account.content_safety.name
    logic_app           = azurerm_logic_app_workflow.content_moderation.name
    event_grid_topic    = azurerm_eventgrid_topic.content_events.name
    function_app        = azurerm_linux_function_app.content_processor.name
    application_insights = azurerm_application_insights.main.name
    log_analytics       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : "disabled"
    monitoring_enabled  = var.enable_monitoring
    notification_email  = var.notification_email != "" ? "configured" : "not configured"
  }
}

# Quick Start URLs
output "quick_start_urls" {
  description = "Quick start URLs for accessing deployed resources"
  value = {
    azure_portal_resource_group = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}"
    logic_app_designer         = "https://portal.azure.com/#@/resource${azurerm_logic_app_workflow.content_moderation.id}/logicApp"
    function_app_portal        = "https://portal.azure.com/#@/resource${azurerm_linux_function_app.content_processor.id}/overview"
    storage_account_portal     = "https://portal.azure.com/#@/resource${azurerm_storage_account.content_storage.id}/overview"
    ai_content_safety_portal   = "https://portal.azure.com/#@/resource${azurerm_cognitive_account.content_safety.id}/overview"
    application_insights_portal = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}/overview"
  }
}

# Data source for current subscription
data "azurerm_subscription" "current" {}

# Next Steps Instructions
output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Configure the Logic App workflow in the Azure portal",
    "2. Deploy Function App code for content processing",
    "3. Test content upload to the 'uploads' container",
    "4. Monitor workflow execution in Application Insights",
    "5. Review quarantined content in the 'quarantine' container",
    "6. Configure custom content safety policies if needed",
    "7. Set up additional notification channels in the Action Group"
  ]
}