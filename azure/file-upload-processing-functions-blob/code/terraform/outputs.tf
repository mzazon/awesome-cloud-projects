# Output values for Azure file upload processing infrastructure
# These outputs provide important information for integration and verification

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = local.resource_group_name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = local.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for file uploads"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob service endpoint URL"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_connection_string" {
  description = "Storage account connection string for applications"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

# Blob Container Information
output "blob_container_name" {
  description = "Name of the blob container for file uploads"
  value       = azurerm_storage_container.uploads.name
}

output "blob_container_url" {
  description = "Full URL to the blob container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.uploads.name}"
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

output "function_app_hostname" {
  description = "Default hostname of the function app"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "Full URL to the function app"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the function app's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

# Service Plan Information
output "service_plan_name" {
  description = "Name of the App Service Plan (Consumption)"
  value       = azurerm_service_plan.main.name
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "service_plan_kind" {
  description = "Kind of App Service Plan (consumption for serverless)"
  value       = azurerm_service_plan.main.sku_name
}

# Application Insights Information (conditional outputs)
output "application_insights_name" {
  description = "Name of Application Insights instance (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application Insights application ID (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].app_id : null
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

# Azure CLI Commands for Testing
output "test_commands" {
  description = "Azure CLI commands for testing the deployment"
  value = {
    # Command to verify function app status
    check_function_status = "az functionapp show --name ${azurerm_linux_function_app.main.name} --resource-group ${local.resource_group_name} --query 'state' --output tsv"
    
    # Command to verify storage account
    check_storage_status = "az storage account show --name ${azurerm_storage_account.main.name} --resource-group ${local.resource_group_name} --query 'provisioningState' --output tsv"
    
    # Command to list containers
    list_containers = "az storage container list --account-name ${azurerm_storage_account.main.name}"
    
    # Command to upload test file
    upload_test_file = "az storage blob upload --file test-file.txt --name 'test-file-$(date +%s).txt' --container-name ${azurerm_storage_container.uploads.name} --account-name ${azurerm_storage_account.main.name}"
    
    # Command to view function logs
    view_logs = "az webapp log tail --name ${azurerm_linux_function_app.main.name} --resource-group ${local.resource_group_name}"
    
    # Command to list functions in the app
    list_functions = "az functionapp function list --name ${azurerm_linux_function_app.main.name} --resource-group ${local.resource_group_name}"
  }
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of key configuration settings"
  value = {
    project_name              = var.project_name
    environment              = var.environment
    location                 = var.location
    storage_tier             = var.storage_account_tier
    storage_replication      = var.storage_replication_type
    function_runtime         = var.function_app_runtime
    function_runtime_version = var.function_app_runtime_version
    container_name           = var.blob_container_name
    application_insights     = var.enable_application_insights
    created_resource_group   = var.create_resource_group
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the deployed infrastructure"
  value = {
    consumption_plan = "Function runs on Consumption plan - you only pay for execution time and resource consumption"
    storage_tier = "Storage account uses ${var.storage_access_tier} access tier - consider Cool tier for infrequently accessed data"
    monitoring = var.enable_application_insights ? "Application Insights enabled - monitor usage to optimize retention period" : "Application Insights disabled - consider enabling for production workloads"
    cleanup = "Remember to delete resources when no longer needed to avoid ongoing charges"
  }
}

# Security Information
output "security_features" {
  description = "Security features enabled in the deployment"
  value = {
    storage_encryption = "Storage account encryption enabled with Microsoft-managed keys"
    https_only = "HTTPS-only traffic enforced for storage account"
    tls_version = "Minimum TLS version: ${var.min_tls_version}"
    managed_identity = "Function app uses system-assigned managed identity"
    rbac_enabled = "Role-based access control configured for storage access"
    container_access = "Blob container access level: ${var.blob_container_access_type}"
  }
}