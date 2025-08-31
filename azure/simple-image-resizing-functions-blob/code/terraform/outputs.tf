# Outputs for Azure Simple Image Resizing Infrastructure
# This file defines the output values that will be displayed after deployment

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
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_primary_endpoint" {
  description = "Primary blob service endpoint URL"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_connection_string" {
  description = "Storage account connection string"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

# Storage Container Information
output "original_images_container_name" {
  description = "Name of the original images container"
  value       = azurerm_storage_container.original_images.name
}

output "thumbnails_container_name" {
  description = "Name of the thumbnails container"
  value       = azurerm_storage_container.thumbnails.name
}

output "medium_images_container_name" {
  description = "Name of the medium images container"
  value       = azurerm_storage_container.medium_images.name
}

# Container URLs for direct access
output "original_images_url" {
  description = "URL for original images container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.original_images.name}"
}

output "thumbnails_url" {
  description = "URL for thumbnails container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.thumbnails.name}"
}

output "medium_images_url" {
  description = "URL for medium images container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.medium_images.name}"
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "Resource ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_hostname" {
  description = "Hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

# Service Plan Information
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# Log Analytics Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

# Event Grid Information
output "eventgrid_system_topic_name" {
  description = "Name of the Event Grid system topic"
  value       = azurerm_eventgrid_system_topic.storage.name
}

output "eventgrid_subscription_name" {
  description = "Name of the Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.blob_trigger.name
}

# Image Processing Configuration
output "image_processing_settings" {
  description = "Image processing configuration settings"
  value = {
    thumbnail_width  = var.thumbnail_width
    thumbnail_height = var.thumbnail_height
    medium_width     = var.medium_width
    medium_height    = var.medium_height
  }
}

# Function App Configuration
output "function_app_settings" {
  description = "Key Function App configuration settings"
  value = {
    runtime         = var.function_app_runtime
    runtime_version = var.function_app_runtime_version
    os_type         = var.function_app_os_type
  }
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployment"
  value = {
    environment   = var.environment
    project_name  = var.project_name
    random_suffix = random_string.suffix.result
    location      = var.location
  }
}

# URLs for testing the solution
output "testing_urls" {
  description = "URLs for testing the image resizing solution"
  value = {
    upload_images_to    = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.original_images.name}"
    view_thumbnails_at  = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.thumbnails.name}"
    view_medium_images_at = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.medium_images.name}"
  }
}

# CLI Commands for quick testing
output "cli_commands" {
  description = "Useful CLI commands for testing and management"
  value = {
    upload_test_image = "az storage blob upload --container-name ${azurerm_storage_container.original_images.name} --name test-image.jpg --file /path/to/test-image.jpg --account-name ${azurerm_storage_account.main.name}"
    list_thumbnails   = "az storage blob list --container-name ${azurerm_storage_container.thumbnails.name} --account-name ${azurerm_storage_account.main.name} --output table"
    view_function_logs = "az monitor log-analytics query --workspace ${azurerm_log_analytics_workspace.main.id} --analytics-query 'traces | where timestamp > ago(1h) | order by timestamp desc'"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for this solution"
  value = {
    consumption_plan = "~$0.00 - $5.00/month (based on usage)"
    storage_account  = "~$0.50 - $2.00/month (based on storage and transactions)"
    app_insights     = "~$0.00 - $1.00/month (based on telemetry volume)"
    log_analytics    = "~$0.00 - $0.50/month (based on log ingestion)"
    total_estimated  = "~$0.50 - $8.50/month for development workloads"
  }
}