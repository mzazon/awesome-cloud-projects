# Output Values for Event Grid and Functions Infrastructure
# These outputs provide important information about deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Event Grid Topic Information
output "event_grid_topic_name" {
  description = "Name of the Event Grid custom topic"
  value       = azurerm_eventgrid_topic.main.name
}

output "event_grid_topic_endpoint" {
  description = "Endpoint URL for the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.endpoint
}

output "event_grid_topic_id" {
  description = "Resource ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.id
}

output "event_grid_topic_hostname" {
  description = "Hostname of the Event Grid topic endpoint"
  value       = replace(azurerm_eventgrid_topic.main.endpoint, "https://", "")
}

# Event Grid Topic Access Keys (Sensitive)
output "event_grid_topic_primary_key" {
  description = "Primary access key for the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.primary_access_key
  sensitive   = true
}

output "event_grid_topic_secondary_key" {
  description = "Secondary access key for the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.secondary_access_key
  sensitive   = true
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = var.enable_function_app ? azurerm_linux_function_app.main[0].name : null
}

output "function_app_id" {
  description = "Resource ID of the Function App"
  value       = var.enable_function_app ? azurerm_linux_function_app.main[0].id : null
}

output "function_app_hostname" {
  description = "Default hostname of the Function App"
  value       = var.enable_function_app ? azurerm_linux_function_app.main[0].default_hostname : null
}

output "function_app_url" {
  description = "Full HTTPS URL of the Function App"
  value       = var.enable_function_app ? "https://${azurerm_linux_function_app.main[0].default_hostname}" : null
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = var.enable_function_app ? azurerm_linux_function_app.main[0].identity[0].principal_id : null
}

# Event Grid Event Subscription Information
output "event_subscription_name" {
  description = "Name of the Event Grid event subscription"
  value       = var.enable_function_app ? azurerm_eventgrid_event_subscription.function_subscription[0].name : null
}

output "event_subscription_id" {
  description = "Resource ID of the Event Grid event subscription"
  value       = var.enable_function_app ? azurerm_eventgrid_event_subscription.function_subscription[0].id : null
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account used by Function App"
  value       = azurerm_storage_account.function_storage.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.function_storage.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.function_storage.primary_blob_endpoint
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights component"
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
  description = "Resource ID of the Log Analytics workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].id : null
}

# Azure Portal URLs for Easy Access
output "azure_portal_urls" {
  description = "Azure Portal URLs for easy access to deployed resources"
  value = {
    resource_group = "https://portal.azure.com/#@/resource/subscriptions/current/resourceGroups/${azurerm_resource_group.main.name}"
    event_grid_topic = "https://portal.azure.com/#@/resource${azurerm_eventgrid_topic.main.id}"
    function_app = var.enable_function_app ? "https://portal.azure.com/#@/resource${azurerm_linux_function_app.main[0].id}" : null
    application_insights = var.enable_application_insights ? "https://portal.azure.com/#@/resource${azurerm_application_insights.main[0].id}" : null
    storage_account = "https://portal.azure.com/#@/resource${azurerm_storage_account.function_storage.id}"
  }
}

# Configuration for Testing
output "curl_test_command" {
  description = "Sample curl command to test the Event Grid topic"
  value = <<-EOT
    curl -X POST \
      -H "aeg-sas-key: ${azurerm_eventgrid_topic.main.primary_access_key}" \
      -H "Content-Type: application/json" \
      -d '[{
        "id": "$(uuidgen)",
        "source": "terraform-test",
        "specversion": "1.0",
        "type": "notification.created",
        "subject": "demo/notifications",
        "time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "data": {
          "message": "Hello from Terraform-deployed Event Grid!",
          "priority": "high",
          "category": "terraform-demo",
          "userId": "terraform-user"
        }
      }]' \
      "${azurerm_eventgrid_topic.main.endpoint}/api/events"
  EOT
  sensitive = true
}

# Resource Naming Information
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Event Grid System Topic Information
output "storage_system_topic_name" {
  description = "Name of the Event Grid system topic for storage events"
  value       = azurerm_eventgrid_system_topic.storage_events.name
}

output "storage_system_topic_id" {
  description = "Resource ID of the Event Grid system topic"
  value       = azurerm_eventgrid_system_topic.storage_events.id
}

# Service Plan Information
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = var.enable_function_app ? azurerm_service_plan.main[0].name : null
}

output "service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = var.enable_function_app ? azurerm_service_plan.main[0].sku_name : null
}

# Function App Staging Slot Information (if created)
output "function_app_staging_slot_hostname" {
  description = "Hostname of the Function App staging slot"
  value       = var.enable_function_app && var.environment == "production" ? azurerm_linux_function_app_slot.staging[0].default_hostname : null
}

# Monitoring and Logging URLs
output "monitoring_urls" {
  description = "URLs for monitoring and logging"
  value = var.enable_application_insights ? {
    application_insights_overview = "https://portal.azure.com/#@/resource${azurerm_application_insights.main[0].id}/overview"
    application_insights_logs     = "https://portal.azure.com/#@/resource${azurerm_application_insights.main[0].id}/logs"
    function_app_monitor         = var.enable_function_app ? "https://portal.azure.com/#@/resource${azurerm_linux_function_app.main[0].id}/monitor" : null
    log_analytics_workspace      = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main[0].id}/logs"
  } : null
}

# Summary Information
output "deployment_summary" {
  description = "Summary of deployed resources and key information"
  value = {
    resource_group_name     = azurerm_resource_group.main.name
    location               = azurerm_resource_group.main.location
    event_grid_topic       = azurerm_eventgrid_topic.main.name
    function_app_name      = var.enable_function_app ? azurerm_linux_function_app.main[0].name : "disabled"
    storage_account_name   = azurerm_storage_account.function_storage.name
    application_insights   = var.enable_application_insights ? azurerm_application_insights.main[0].name : "disabled"
    resource_suffix        = random_string.suffix.result
    total_estimated_cost   = "$2-$5 per month for low-volume usage"
  }
}