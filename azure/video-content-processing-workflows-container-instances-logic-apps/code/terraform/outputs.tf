# Outputs for Azure video processing workflow infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.video_workflow.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.video_workflow.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for video files"
  value       = azurerm_storage_account.video_storage.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.video_storage.id
}

output "storage_primary_blob_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.video_storage.primary_blob_endpoint
}

output "storage_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.video_storage.primary_access_key
  sensitive   = true
}

output "storage_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.video_storage.primary_connection_string
  sensitive   = true
}

# Storage Container Information
output "input_container_name" {
  description = "Name of the input videos container"
  value       = azurerm_storage_container.input_videos.name
}

output "output_container_name" {
  description = "Name of the output videos container"
  value       = azurerm_storage_container.output_videos.name
}

output "input_container_url" {
  description = "URL of the input videos container"
  value       = "${azurerm_storage_account.video_storage.primary_blob_endpoint}${azurerm_storage_container.input_videos.name}"
}

output "output_container_url" {
  description = "URL of the output videos container"
  value       = "${azurerm_storage_account.video_storage.primary_blob_endpoint}${azurerm_storage_container.output_videos.name}"
}

# Event Grid Information
output "eventgrid_topic_name" {
  description = "Name of the Event Grid topic"
  value       = azurerm_eventgrid_topic.video_events.name
}

output "eventgrid_topic_id" {
  description = "Resource ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.video_events.id
}

output "eventgrid_topic_endpoint" {
  description = "Endpoint URL of the Event Grid topic"
  value       = azurerm_eventgrid_topic.video_events.endpoint
}

output "eventgrid_primary_access_key" {
  description = "Primary access key for the Event Grid topic"
  value       = azurerm_eventgrid_topic.video_events.primary_access_key
  sensitive   = true
}

# Logic App Information
output "logic_app_name" {
  description = "Name of the Logic App workflow"
  value       = azurerm_logic_app_workflow.video_processor.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic App workflow"
  value       = azurerm_logic_app_workflow.video_processor.id
}

output "logic_app_trigger_url" {
  description = "HTTP trigger URL for the Logic App"
  value       = "https://management.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.video_workflow.name}/providers/Microsoft.Logic/workflows/${azurerm_logic_app_workflow.video_processor.name}/triggers/manual/paths/invoke"
}

# Managed Identity Information
output "container_identity_id" {
  description = "Resource ID of the container managed identity"
  value       = azurerm_user_assigned_identity.container_identity.id
}

output "container_identity_principal_id" {
  description = "Principal ID of the container managed identity"
  value       = azurerm_user_assigned_identity.container_identity.principal_id
}

output "container_identity_client_id" {
  description = "Client ID of the container managed identity"
  value       = azurerm_user_assigned_identity.container_identity.client_id
}

# Application Insights Information (if enabled)
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = var.enable_monitoring ? azurerm_application_insights.video_monitoring[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.video_monitoring[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.video_monitoring[0].connection_string : null
  sensitive   = true
}

# CDN Information (if enabled)
output "cdn_profile_name" {
  description = "Name of the CDN profile"
  value       = var.enable_cdn ? azurerm_cdn_profile.video_cdn[0].name : null
}

output "cdn_endpoint_name" {
  description = "Name of the CDN endpoint"
  value       = var.enable_cdn ? azurerm_cdn_endpoint.video_distribution[0].name : null
}

output "cdn_endpoint_fqdn" {
  description = "Fully qualified domain name of the CDN endpoint"
  value       = var.enable_cdn ? azurerm_cdn_endpoint.video_distribution[0].fqdn : null
}

output "cdn_endpoint_url" {
  description = "URL of the CDN endpoint for video distribution"
  value       = var.enable_cdn ? "https://${azurerm_cdn_endpoint.video_distribution[0].fqdn}" : null
}

# Deployment Information
output "deployment_random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "azure_subscription_id" {
  description = "Azure subscription ID used for deployment"
  value       = data.azurerm_client_config.current.subscription_id
}

output "azure_tenant_id" {
  description = "Azure tenant ID used for deployment"
  value       = data.azurerm_client_config.current.tenant_id
}

# Container Processing Information
output "container_group_template_name" {
  description = "Template name for container group creation"
  value       = "cg-video-ffmpeg-${random_string.suffix.result}"
}

output "ffmpeg_docker_image" {
  description = "Docker image used for FFmpeg processing"
  value       = var.ffmpeg_image
}

output "video_processing_formats" {
  description = "Video formats configured for processing"
  value       = var.video_formats
}

output "video_processing_resolutions" {
  description = "Video resolutions configured for processing"
  value       = var.video_resolutions
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the video processing workflow"
  value = <<-EOT
    Video Processing Workflow Deployed Successfully!
    
    To upload videos for processing:
    1. Upload video files to: ${azurerm_storage_account.video_storage.primary_blob_endpoint}${azurerm_storage_container.input_videos.name}
    2. The workflow will automatically trigger via Event Grid
    3. Processed videos will appear in: ${azurerm_storage_account.video_storage.primary_blob_endpoint}${azurerm_storage_container.output_videos.name}
    
    Azure CLI Upload Example:
    az storage blob upload \
      --account-name ${azurerm_storage_account.video_storage.name} \
      --container-name ${azurerm_storage_container.input_videos.name} \
      --name "my-video.mp4" \
      --file "local-video.mp4"
    
    Monitor workflow execution:
    - Logic App: https://portal.azure.com/#@/resource${azurerm_logic_app_workflow.video_processor.id}
    - Storage Account: https://portal.azure.com/#@/resource${azurerm_storage_account.video_storage.id}
    ${var.enable_monitoring ? "- Application Insights: https://portal.azure.com/#@/resource${azurerm_application_insights.video_monitoring[0].id}" : ""}
    ${var.enable_cdn ? "- CDN Endpoint: https://${azurerm_cdn_endpoint.video_distribution[0].fqdn}" : ""}
  EOT
}

# Monitoring and Alerts
output "action_group_name" {
  description = "Name of the action group for notifications"
  value       = var.notification_email != "" ? azurerm_monitor_action_group.video_notifications[0].name : null
}

# Security Information
output "security_notes" {
  description = "Important security considerations"
  value = <<-EOT
    Security Configuration:
    - Storage account uses HTTPS-only traffic
    - Minimum TLS version: 1.2
    - Blob soft delete enabled for ${var.retention_days} days
    - Container access via managed identity
    - Private storage containers (no public access)
    
    Next Steps:
    1. Configure Logic App workflow definition with complete processing logic
    2. Test video upload and processing workflow
    3. Set up monitoring alerts for processing failures
    4. Configure backup and disaster recovery if needed
    ${var.enable_cdn ? "5. Configure CDN custom domain and SSL certificate" : ""}
  EOT
}