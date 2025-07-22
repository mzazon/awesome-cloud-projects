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
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for video uploads and results"
  value       = azurerm_storage_account.video_storage.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.video_storage.primary_blob_endpoint
}

output "storage_account_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.video_storage.primary_connection_string
  sensitive   = true
}

output "videos_container_url" {
  description = "URL of the videos container"
  value       = "${azurerm_storage_account.video_storage.primary_blob_endpoint}${azurerm_storage_container.videos.name}"
}

output "results_container_url" {
  description = "URL of the results container"
  value       = "${azurerm_storage_account.video_storage.primary_blob_endpoint}${azurerm_storage_container.results.name}"
}

# Cosmos DB Information
output "cosmos_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_endpoint" {
  description = "Endpoint URL of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_database_name" {
  description = "Name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.video_analytics.name
}

output "cosmos_container_name" {
  description = "Name of the Cosmos DB container for video metadata"
  value       = azurerm_cosmosdb_sql_container.video_metadata.name
}

output "cosmos_connection_string" {
  description = "Primary SQL connection string for Cosmos DB"
  value       = azurerm_cosmosdb_account.main.primary_sql_connection_string
  sensitive   = true
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = var.function_app_os_type == "linux" ? azurerm_linux_function_app.video_processor[0].name : azurerm_windows_function_app.video_processor[0].name
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = var.function_app_os_type == "linux" ? azurerm_linux_function_app.video_processor[0].default_hostname : azurerm_windows_function_app.video_processor[0].default_hostname
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = var.function_app_os_type == "linux" ? "https://${azurerm_linux_function_app.video_processor[0].default_hostname}" : "https://${azurerm_windows_function_app.video_processor[0].default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = var.function_app_os_type == "linux" ? azurerm_linux_function_app.video_processor[0].identity[0].principal_id : azurerm_windows_function_app.video_processor[0].identity[0].principal_id
}

# Event Grid Information
output "eventgrid_storage_topic_name" {
  description = "Name of the Event Grid system topic for storage events"
  value       = azurerm_eventgrid_system_topic.storage.name
}

output "eventgrid_storage_topic_endpoint" {
  description = "Endpoint of the Event Grid system topic for storage events"
  value       = azurerm_eventgrid_system_topic.storage.metric_arm_resource_id
}

output "eventgrid_video_indexer_topic_name" {
  description = "Name of the Event Grid topic for Video Indexer events"
  value       = azurerm_eventgrid_topic.video_indexer.name
}

output "eventgrid_video_indexer_topic_endpoint" {
  description = "Endpoint of the Event Grid topic for Video Indexer events"
  value       = azurerm_eventgrid_topic.video_indexer.endpoint
}

output "eventgrid_video_indexer_topic_access_key" {
  description = "Primary access key for the Video Indexer Event Grid topic"
  value       = azurerm_eventgrid_topic.video_indexer.primary_access_key
  sensitive   = true
}

# Event Grid Subscriptions
output "blob_upload_subscription_name" {
  description = "Name of the blob upload event subscription"
  value       = azurerm_eventgrid_event_subscription.blob_upload.name
}

output "video_results_subscription_name" {
  description = "Name of the video results event subscription"
  value       = azurerm_eventgrid_event_subscription.video_results.name
}

# Application Insights Information (if enabled)
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

# Log Analytics Workspace Information (if enabled)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

# Video Indexer Configuration
output "video_indexer_account_id" {
  description = "Azure Video Indexer Account ID (configured)"
  value       = var.video_indexer_account_id != "" ? "Configured" : "Not configured - manual setup required"
  sensitive   = false
}

output "video_indexer_location" {
  description = "Video Indexer API location"
  value       = var.video_indexer_location
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

# Generated suffix for unique naming
output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

# Quick start information
output "quick_start_instructions" {
  description = "Quick start instructions for using the deployed infrastructure"
  value = <<-EOT
    Infrastructure deployed successfully! Here's how to get started:
    
    1. Video Upload:
       - Upload videos to: ${azurerm_storage_account.video_storage.primary_blob_endpoint}${azurerm_storage_container.videos.name}
       - Use Azure Storage Explorer or Azure CLI
    
    2. Function App:
       - Deployed at: ${var.function_app_os_type == "linux" ? "https://${azurerm_linux_function_app.video_processor[0].default_hostname}" : "https://${azurerm_windows_function_app.video_processor[0].default_hostname}"}
       - Deploy function code using Azure Functions Core Tools
    
    3. Monitoring:
       ${var.enable_application_insights ? "- Application Insights: ${azurerm_application_insights.main[0].name}" : "- Application Insights: Not enabled"}
    
    4. Video Indexer Setup:
       ${var.video_indexer_account_id != "" ? "- Account ID: Configured" : "- Create account at: https://www.videoindexer.ai/"}
       ${var.video_indexer_account_id != "" ? "" : "- Update terraform.tfvars with your account details"}
    
    5. Results Storage:
       - Check processed results in: ${azurerm_storage_account.video_storage.primary_blob_endpoint}${azurerm_storage_container.results.name}
       - Query metadata in Cosmos DB: ${azurerm_cosmosdb_account.main.name}
  EOT
}

# Cost optimization recommendations
output "cost_optimization_notes" {
  description = "Recommendations for cost optimization"
  value = <<-EOT
    Cost Optimization Tips:
    
    1. Storage Lifecycle Management: ${var.storage_lifecycle_management_enabled ? "Enabled" : "Disabled"}
       ${var.storage_lifecycle_management_enabled ? "- Videos move to Cool storage after ${var.cool_storage_days} days" : "- Consider enabling lifecycle management"}
       ${var.storage_lifecycle_management_enabled ? "- Videos move to Archive after ${var.archive_storage_days} days" : ""}
       ${var.storage_lifecycle_management_enabled ? "- Videos deleted after ${var.delete_storage_days} days" : ""}
    
    2. Cosmos DB: ${var.cosmos_enable_serverless ? "Serverless mode (pay-per-use)" : "Provisioned throughput"}
    
    3. Function App: Consumption plan (pay-per-execution)
    
    4. Video Indexer: Monitor usage to stay within free tier (10 hours/month)
    
    5. Application Insights: ${var.enable_application_insights ? "Enabled - monitor data ingestion costs" : "Disabled"}
  EOT
}

# Security recommendations
output "security_recommendations" {
  description = "Security best practices and recommendations"
  value = <<-EOT
    Security Recommendations:
    
    1. Storage Account:
       - Public access: Disabled ✓
       - Shared access keys: Consider rotating regularly
       - Soft delete: ${var.enable_soft_delete ? "Enabled ✓" : "Consider enabling"}
    
    2. Function App:
       - Managed identity: Enabled ✓
       - RBAC permissions: Configured ✓
       - Consider enabling authentication for production use
    
    3. Event Grid:
       - Local auth: ${var.event_grid_local_auth_enabled ? "Enabled" : "Disabled"}
       - Consider using managed identity for authentication
    
    4. Cosmos DB:
       - Connection strings: Stored securely in Function App settings ✓
       - Consider enabling Azure Active Directory authentication
    
    5. Network Security:
       - Consider implementing private endpoints for production
       - Review firewall rules and network access policies
  EOT
}