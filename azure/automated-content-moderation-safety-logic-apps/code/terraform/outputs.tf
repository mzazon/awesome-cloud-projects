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
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# Azure AI Content Safety Outputs
output "content_safety_name" {
  description = "Name of the Content Safety cognitive service"
  value       = azurerm_cognitive_account.content_safety.name
}

output "content_safety_endpoint" {
  description = "Endpoint URL for the Content Safety service"
  value       = azurerm_cognitive_account.content_safety.endpoint
  sensitive   = false
}

output "content_safety_id" {
  description = "Resource ID of the Content Safety service"
  value       = azurerm_cognitive_account.content_safety.id
}

output "content_safety_primary_key" {
  description = "Primary access key for Content Safety service"
  value       = azurerm_cognitive_account.content_safety.primary_access_key
  sensitive   = true
}

output "content_safety_secondary_key" {
  description = "Secondary access key for Content Safety service"
  value       = azurerm_cognitive_account.content_safety.secondary_access_key
  sensitive   = true
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.content_storage.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.content_storage.id
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.content_storage.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.content_storage.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.content_storage.primary_access_key
  sensitive   = true
}

output "content_container_name" {
  description = "Name of the content uploads container"
  value       = azurerm_storage_container.content_uploads.name
}

output "content_container_url" {
  description = "URL of the content uploads container"
  value       = "${azurerm_storage_account.content_storage.primary_blob_endpoint}${azurerm_storage_container.content_uploads.name}"
}

# Logic App Outputs
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
  sensitive   = false
}

output "logic_app_workflow_version" {
  description = "Version of the Logic App workflow"
  value       = azurerm_logic_app_workflow.content_moderation.workflow_version
}

output "logic_app_enabled" {
  description = "Whether the Logic App workflow is enabled"
  value       = var.enable_logic_app
}

# API Connection Outputs
output "blob_connection_name" {
  description = "Name of the Azure Blob storage API connection"
  value       = azurerm_api_connection.azureblob.name
}

output "blob_connection_id" {
  description = "Resource ID of the Azure Blob storage API connection"
  value       = azurerm_api_connection.azureblob.id
}

# Service Plan Outputs
output "app_service_plan_name" {
  description = "Name of the App Service Plan for Logic App"
  value       = azurerm_service_plan.logic_app_plan.name
}

output "app_service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.logic_app_plan.id
}

# Configuration and Deployment Information
output "deployment_configuration" {
  description = "Key configuration settings for the deployed solution"
  value = {
    environment                   = var.environment
    project_name                 = var.project_name
    content_safety_sku           = var.content_safety_sku
    storage_tier                 = var.storage_account_tier
    storage_replication          = var.storage_account_replication_type
    logic_app_plan_sku          = var.logic_app_plan_sku
    lifecycle_management_enabled = var.enable_lifecycle_management
    https_only_enabled          = var.enable_https_only
    minimum_tls_version         = var.minimum_tls_version
  }
}

output "moderation_thresholds" {
  description = "Configured content moderation severity thresholds"
  value = {
    auto_approve_max_severity = var.moderation_severity_thresholds.auto_approve_max_severity
    review_min_severity      = var.moderation_severity_thresholds.review_min_severity
    auto_reject_min_severity = var.moderation_severity_thresholds.auto_reject_min_severity
  }
}

# Cost Management Information
output "estimated_monthly_cost_info" {
  description = "Information about cost components (actual costs may vary)"
  value = {
    content_safety_sku    = var.content_safety_sku
    storage_tier         = "${var.storage_account_tier}_${var.storage_account_replication_type}"
    logic_app_plan       = var.logic_app_plan_sku
    note                = "Actual costs depend on usage patterns, storage consumption, and API calls"
    cost_optimization   = "Consider lifecycle management policies and monitoring unused resources"
  }
}

# Validation and Testing Outputs
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    test_content_safety = "az cognitiveservices account show --name ${azurerm_cognitive_account.content_safety.name} --resource-group ${azurerm_resource_group.main.name}"
    test_storage       = "az storage container show --name ${azurerm_storage_container.content_uploads.name} --account-name ${azurerm_storage_account.content_storage.name}"
    test_logic_app     = "az logic workflow show --name ${azurerm_logic_app_workflow.content_moderation.name} --resource-group ${azurerm_resource_group.main.name}"
    upload_test_file   = "az storage blob upload --file test.txt --name test-$(date +%s).txt --container-name ${azurerm_storage_container.content_uploads.name} --account-name ${azurerm_storage_account.content_storage.name}"
  }
}

# Security and Compliance Information
output "security_features" {
  description = "Security features enabled in the deployment"
  value = {
    https_only_storage           = var.enable_https_only
    minimum_tls_version         = var.minimum_tls_version
    blob_public_access_disabled = true
    storage_encryption_enabled  = true
    blob_versioning_enabled     = true
    blob_soft_delete_enabled    = true
    diagnostic_logging_enabled  = var.enable_storage_logging
  }
}

# Integration Information for External Systems
output "integration_endpoints" {
  description = "Key endpoints for integration with external systems"
  value = {
    content_safety_api_endpoint = azurerm_cognitive_account.content_safety.endpoint
    storage_blob_endpoint      = azurerm_storage_account.content_storage.primary_blob_endpoint
    content_upload_container   = "${azurerm_storage_account.content_storage.primary_blob_endpoint}${azurerm_storage_container.content_uploads.name}"
    logic_app_trigger_endpoint = azurerm_logic_app_workflow.content_moderation.access_endpoint
  }
}