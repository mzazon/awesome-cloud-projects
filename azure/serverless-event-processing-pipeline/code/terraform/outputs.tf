# Output values for the real-time data processing infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Event Hub Information
output "eventhub_namespace_name" {
  description = "Name of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.main.name
}

output "eventhub_namespace_hostname" {
  description = "Hostname of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "eventhub_name" {
  description = "Name of the Event Hub"
  value       = azurerm_eventhub.events.name
}

output "eventhub_partition_count" {
  description = "Number of partitions in the Event Hub"
  value       = azurerm_eventhub.events.partition_count
}

output "eventhub_message_retention_days" {
  description = "Message retention period in days"
  value       = azurerm_eventhub.events.message_retention
}

# Event Hub Connection Strings
output "eventhub_connection_string_function" {
  description = "Event Hub connection string for Function App (listen permissions)"
  value       = azurerm_eventhub_authorization_rule.function_access.primary_connection_string
  sensitive   = true
}

output "eventhub_connection_string_sender" {
  description = "Event Hub connection string for sending events (send permissions)"
  value       = azurerm_eventhub_authorization_rule.sender_access.primary_connection_string
  sensitive   = true
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account used by Function App"
  value       = azurerm_storage_account.function_storage.name
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint of the storage account"
  value       = azurerm_storage_account.function_storage.primary_blob_endpoint
}

output "storage_account_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.function_storage.primary_connection_string
  sensitive   = true
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.processor.name
}

output "function_app_hostname" {
  description = "Hostname of the Function App"
  value       = azurerm_linux_function_app.processor.default_hostname
}

output "function_app_url" {
  description = "HTTPS URL of the Function App"
  value       = "https://${azurerm_linux_function_app.processor.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_linux_function_app.processor.identity[0].principal_id
}

output "function_app_identity_tenant_id" {
  description = "Tenant ID of the Function App managed identity"
  value       = azurerm_linux_function_app.processor.identity[0].tenant_id
}

# Service Plan Information
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.function_plan.name
}

output "service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.function_plan.sku_name
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].app_id : null
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

# Consumer Group Information
output "consumer_group_name" {
  description = "Name of the Event Hub consumer group"
  value       = azurerm_eventhub_consumer_group.function_consumer.name
}

# Environment Information
output "environment_name" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

# Configuration Values for Client Applications
output "client_configuration" {
  description = "Configuration values for client applications"
  value = {
    eventhub_namespace = azurerm_eventhub_namespace.main.name
    eventhub_name      = azurerm_eventhub.events.name
    consumer_group     = azurerm_eventhub_consumer_group.function_consumer.name
    function_app_url   = "https://${azurerm_linux_function_app.processor.default_hostname}"
    storage_account    = azurerm_storage_account.function_storage.name
    resource_group     = azurerm_resource_group.main.name
    location           = azurerm_resource_group.main.location
  }
}

# Connection Information for Testing
output "test_connection_info" {
  description = "Connection information for testing the deployment"
  value = {
    send_events_command = "Use the sender connection string to send events to ${azurerm_eventhub.events.name}"
    monitor_function    = "Monitor function execution in Application Insights: ${var.enable_application_insights ? azurerm_application_insights.main[0].name : "Not enabled"}"
    view_logs          = "View logs in the Function App or Log Analytics workspace"
  }
  sensitive = false
}

# Resource Tags
output "applied_tags" {
  description = "Tags applied to the resources"
  value       = var.tags
}

# Cost Information
output "cost_optimization_notes" {
  description = "Notes about cost optimization"
  value = {
    eventhub_sku           = "Event Hub SKU: ${var.eventhub_namespace_sku}"
    function_plan          = "Function App plan: ${var.function_app_service_plan_tier}"
    storage_tier           = "Storage tier: ${var.storage_account_tier}"
    retention_days         = "Application Insights retention: ${var.application_insights_retention_days} days"
    auto_scale_enabled     = var.enable_auto_scale
    recommendations        = "Consider Basic Event Hub tier for development, Standard/Premium for production"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    https_only                = var.enable_https_only
    storage_https_only        = azurerm_storage_account.function_storage.enable_https_traffic_only
    tls_version              = "1.2"
    managed_identity_enabled = true
    rbac_configured          = true
  }
}

# Monitoring URLs
output "monitoring_urls" {
  description = "URLs for monitoring and management"
  value = var.enable_application_insights ? {
    application_insights = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Insights/components/${azurerm_application_insights.main[0].name}"
    function_app        = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Web/sites/${azurerm_linux_function_app.processor.name}"
    eventhub_namespace  = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.EventHub/namespaces/${azurerm_eventhub_namespace.main.name}"
    log_analytics       = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.OperationalInsights/workspaces/${azurerm_log_analytics_workspace.main[0].name}"
  } : null
}

# Data source for current Azure configuration
data "azurerm_client_config" "current" {}

# Next Steps
output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Deploy your Function App code using Azure Functions Core Tools or Azure DevOps",
    "2. Test event processing by sending events to the Event Hub",
    "3. Monitor function execution in Application Insights",
    "4. Configure alerts and notifications as needed",
    "5. Scale resources based on your workload requirements"
  ]
}