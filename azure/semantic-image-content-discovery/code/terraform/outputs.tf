# Output Values for Intelligent Image Content Discovery Infrastructure
# This file defines the outputs that provide important information about deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for image repository"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_primary_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "image_container_name" {
  description = "Name of the blob container for image storage"
  value       = azurerm_storage_container.images.name
}

output "image_container_url" {
  description = "URL of the image container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.images.name}/"
}

# Azure AI Vision Service Information
output "ai_vision_name" {
  description = "Name of the Azure AI Vision service"
  value       = azurerm_cognitive_account.vision.name
}

output "ai_vision_id" {
  description = "Resource ID of the Azure AI Vision service"
  value       = azurerm_cognitive_account.vision.id
}

output "ai_vision_endpoint" {
  description = "Endpoint URL for the Azure AI Vision service"
  value       = azurerm_cognitive_account.vision.endpoint
}

output "ai_vision_primary_key" {
  description = "Primary access key for the Azure AI Vision service"
  value       = azurerm_cognitive_account.vision.primary_access_key
  sensitive   = true
}

output "ai_vision_kind" {
  description = "Kind of the Azure AI Vision service"
  value       = azurerm_cognitive_account.vision.kind
}

output "ai_vision_sku" {
  description = "SKU of the Azure AI Vision service"
  value       = azurerm_cognitive_account.vision.sku_name
}

# Azure AI Search Service Information
output "search_service_name" {
  description = "Name of the Azure AI Search service"
  value       = azurerm_search_service.main.name
}

output "search_service_id" {
  description = "Resource ID of the Azure AI Search service"
  value       = azurerm_search_service.main.id
}

output "search_service_url" {
  description = "URL of the Azure AI Search service"
  value       = "https://${azurerm_search_service.main.name}.search.windows.net"
}

output "search_primary_key" {
  description = "Primary admin key for the Azure AI Search service"
  value       = azurerm_search_service.main.primary_key
  sensitive   = true
}

output "search_query_keys" {
  description = "Query keys for the Azure AI Search service"
  value       = azurerm_search_service.main.query_keys
  sensitive   = true
}

output "search_index_name" {
  description = "Name of the search index for image content"
  value       = var.search_index_name
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "Resource ID of the Azure Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Azure Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "URL of the Azure Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

# Application Insights Information (conditional)
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

# Service Plan Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

# Testing and Demo Information
output "sample_image_upload_command" {
  description = "Sample Azure CLI command to upload an image for testing"
  value = <<-EOT
    az storage blob upload \
      --account-name ${azurerm_storage_account.main.name} \
      --container-name ${azurerm_storage_container.images.name} \
      --name test-image.jpg \
      --file /path/to/your/image.jpg \
      --auth-mode key
  EOT
}

output "search_api_example" {
  description = "Example curl command to search for images"
  value = <<-EOT
    curl -X POST "https://${azurerm_search_service.main.name}.search.windows.net/indexes/${var.search_index_name}/docs/search?api-version=2024-05-01-preview" \
      -H "Content-Type: application/json" \
      -H "api-key: YOUR_SEARCH_KEY" \
      -d '{
        "search": "your search query",
        "top": 10,
        "searchMode": "all",
        "queryType": "semantic"
      }'
  EOT
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    resource_group        = azurerm_resource_group.main.name
    storage_account      = azurerm_storage_account.main.name
    ai_vision_service    = azurerm_cognitive_account.vision.name
    search_service       = azurerm_search_service.main.name
    function_app         = azurerm_linux_function_app.main.name
    application_insights = var.enable_application_insights ? azurerm_application_insights.main[0].name : "disabled"
    image_container      = azurerm_storage_container.images.name
    search_index         = var.search_index_name
    deployment_region    = azurerm_resource_group.main.location
  }
}

# Security Information
output "managed_identities" {
  description = "Managed identities created for secure service access"
  value = {
    function_app_principal_id = azurerm_linux_function_app.main.identity[0].principal_id
    ai_vision_principal_id   = azurerm_cognitive_account.vision.identity[0].principal_id
    search_service_principal_id = azurerm_search_service.main.identity[0].principal_id
  }
}

# Connectivity Information
output "service_endpoints" {
  description = "Service endpoints for external integrations"
  value = {
    storage_blob_endpoint = azurerm_storage_account.main.primary_blob_endpoint
    ai_vision_endpoint   = azurerm_cognitive_account.vision.endpoint
    search_service_url   = "https://${azurerm_search_service.main.name}.search.windows.net"
    function_app_url     = "https://${azurerm_linux_function_app.main.default_hostname}"
  }
}

# Cost Management Information
output "cost_management_info" {
  description = "Information for cost monitoring and optimization"
  value = {
    storage_tier          = "${azurerm_storage_account.main.account_tier}-${azurerm_storage_account.main.account_replication_type}"
    ai_vision_sku        = azurerm_cognitive_account.vision.sku_name
    search_service_sku   = azurerm_search_service.main.sku
    function_app_plan    = "Consumption (Y1)"
    estimated_monthly_cost = "Varies based on usage - Monitor via Azure Cost Management"
  }
}

# Random suffix for reference
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Resource tags applied
output "applied_tags" {
  description = "Tags applied to all resources"
  value       = local.tags
}