# Output values for the automated video analysis infrastructure
# These outputs provide key information needed for validation, integration, and management

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all video analysis resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where the resource group is deployed"
  value       = azurerm_resource_group.main.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for video files and insights"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob service endpoint for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_connection_string" {
  description = "Connection string for the storage account (sensitive)"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "video_container_name" {
  description = "Name of the blob container for uploading videos"
  value       = azurerm_storage_container.videos.name
}

output "insights_container_name" {
  description = "Name of the blob container for storing analysis insights"
  value       = azurerm_storage_container.insights.name
}

output "video_upload_url" {
  description = "Full URL for the video upload container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${local.video_container_name}"
}

output "insights_download_url" {
  description = "Full URL for the insights container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${local.insights_container_name}"
}

# Video Indexer Information
output "video_indexer_account_name" {
  description = "Name of the Azure AI Video Indexer account"
  value       = azurerm_cognitive_account.video_indexer.name
}

output "video_indexer_account_id" {
  description = "Account ID for the Video Indexer service"
  value       = azurerm_cognitive_account.video_indexer.custom_subdomain_name
}

output "video_indexer_endpoint" {
  description = "Endpoint URL for the Video Indexer service"
  value       = azurerm_cognitive_account.video_indexer.endpoint
}

output "video_indexer_location" {
  description = "Azure region for the Video Indexer account"
  value       = azurerm_cognitive_account.video_indexer.location
}

output "video_indexer_access_key" {
  description = "Primary access key for Video Indexer API (sensitive)"
  value       = azurerm_cognitive_account.video_indexer.primary_access_key
  sensitive   = true
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App for video processing"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_hostname" {
  description = "Default hostname for the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "Full URL for the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_identity_tenant_id" {
  description = "Tenant ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].tenant_id
}

# Service Plan Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan hosting the Function App"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# Application Insights Information (conditional)
output "application_insights_name" {
  description = "Name of the Application Insights instance (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive, if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (sensitive, if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID for Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].app_id : null
}

# Configuration and Testing Information
output "unique_suffix" {
  description = "Unique suffix used for resource naming"
  value       = local.unique_suffix
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Management and Monitoring URLs
output "azure_portal_resource_group_url" {
  description = "Direct link to the resource group in Azure Portal"
  value       = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/overview"
}

output "storage_account_portal_url" {
  description = "Direct link to the storage account in Azure Portal"
  value       = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Storage/storageAccounts/${azurerm_storage_account.main.name}/overview"
}

output "video_indexer_portal_url" {
  description = "Direct link to the Video Indexer account in Azure Portal"
  value       = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.CognitiveServices/accounts/${azurerm_cognitive_account.video_indexer.name}/overview"
}

output "function_app_portal_url" {
  description = "Direct link to the Function App in Azure Portal"
  value       = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Web/sites/${azurerm_linux_function_app.main.name}/appServices"
}

output "video_indexer_web_portal_url" {
  description = "Direct link to the Video Indexer web portal for video management"
  value       = "https://www.videoindexer.ai/media/library"
}

# Azure CLI Commands for Management
output "azure_cli_upload_command" {
  description = "Azure CLI command to upload a test video"
  value = join(" ", [
    "az storage blob upload",
    "--account-name ${azurerm_storage_account.main.name}",
    "--container-name ${local.video_container_name}",
    "--name test-video.mp4",
    "--file /path/to/your/video.mp4",
    "--auth-mode login"
  ])
}

output "azure_cli_list_insights_command" {
  description = "Azure CLI command to list generated insights"
  value = join(" ", [
    "az storage blob list",
    "--account-name ${azurerm_storage_account.main.name}",
    "--container-name ${local.insights_container_name}",
    "--output table",
    "--auth-mode login"
  ])
}

output "azure_cli_download_insights_command" {
  description = "Azure CLI command to download insights file"
  value = join(" ", [
    "az storage blob download",
    "--account-name ${azurerm_storage_account.main.name}",
    "--container-name ${local.insights_container_name}",
    "--name [insight-file-name].json",
    "--file ./downloaded-insights.json",
    "--auth-mode login"
  ])
}

output "azure_cli_function_logs_command" {
  description = "Azure CLI command to view Function App logs"
  value = join(" ", [
    "az functionapp log tail",
    "--name ${azurerm_linux_function_app.main.name}",
    "--resource-group ${azurerm_resource_group.main.name}"
  ])
}

# PowerShell Commands for Windows Users
output "powershell_upload_command" {
  description = "PowerShell command to upload a test video using Azure PowerShell"
  value = join(" ", [
    "Set-AzStorageBlobContent",
    "-File 'C:\\path\\to\\your\\video.mp4'",
    "-Container '${local.video_container_name}'",
    "-Blob 'test-video.mp4'",
    "-Context (Get-AzStorageAccount -ResourceGroupName '${azurerm_resource_group.main.name}' -Name '${azurerm_storage_account.main.name}').Context"
  ])
}

# REST API Information
output "video_indexer_api_base_url" {
  description = "Base URL for Video Indexer REST API"
  value       = "https://api.videoindexer.ai/${var.location}/Accounts/${azurerm_cognitive_account.video_indexer.custom_subdomain_name}"
}

output "storage_rest_api_base_url" {
  description = "Base URL for Azure Storage REST API"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

# Cost Management Information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (approximate, based on minimal usage)"
  value = {
    storage_account    = "5-10 USD (depends on storage volume and operations)"
    video_indexer     = "Variable based on processing minutes"
    function_app      = "0-5 USD (consumption plan, depends on executions)"
    application_insights = var.enable_application_insights ? "0-10 USD (depends on data ingestion)" : "Not enabled"
    total_estimated   = "10-50 USD per month (highly variable based on usage)"
    note             = "Costs vary significantly based on video processing volume and storage retention"
  }
}

# Health Check and Validation Information
output "deployment_validation_steps" {
  description = "Steps to validate the deployment"
  value = [
    "1. Check that all resources are created: az group show --name ${azurerm_resource_group.main.name}",
    "2. Verify Function App is running: az functionapp show --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name} --query state",
    "3. Test video upload: Upload a small video file to the '${local.video_container_name}' container",
    "4. Monitor processing: Check Function App logs and Video Indexer portal",
    "5. Verify insights generation: Check for JSON files in the '${local.insights_container_name}' container",
    "6. Review costs: Monitor spending in Azure Cost Management"
  ]
}

output "troubleshooting_resources" {
  description = "Resources for troubleshooting common issues"
  value = {
    function_logs        = "View logs at: https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Web/sites/${azurerm_linux_function_app.main.name}/logFiles"
    application_insights = var.enable_application_insights ? "Monitor at: https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Insights/components/${azurerm_application_insights.main[0].name}/overview" : "Not enabled"
    video_indexer_portal = "Check processing status at: https://www.videoindexer.ai/media/library"
    storage_explorer     = "Browse storage at: https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Storage/storageAccounts/${azurerm_storage_account.main.name}/storageExplorer"
  }
}