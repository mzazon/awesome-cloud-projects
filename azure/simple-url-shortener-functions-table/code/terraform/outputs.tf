# Output values for the URL shortener infrastructure
# These outputs provide important information for validation, testing, and integration

output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "storage_account_name" {
  description = "Name of the storage account used for Function App and Table Storage"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint URL for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "table_name" {
  description = "Name of the Azure Table Storage table for URL mappings"
  value       = azurerm_storage_table.url_mappings.name
}

output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_hostname" {
  description = "Hostname of the Function App for API calls"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "Full HTTPS URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "shorten_endpoint" {
  description = "Complete URL for the shorten function endpoint"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/shorten"
}

output "redirect_base_url" {
  description = "Base URL for redirect function (append short code to use)"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api"
}

output "service_plan_name" {
  description = "Name of the App Service Plan hosting the Function App"
  value       = azurerm_service_plan.main.name
}

output "service_plan_sku" {
  description = "SKU of the App Service Plan (pricing tier)"
  value       = azurerm_service_plan.main.sku_name
}

output "application_insights_name" {
  description = "Name of the Application Insights instance (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key for monitoring"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application Insights application ID"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].app_id : null
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_identity_tenant_id" {
  description = "Tenant ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].tenant_id
}

# Useful connection information for testing and integration
output "storage_connection_string" {
  description = "Connection string for the storage account (sensitive)"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "table_storage_endpoint" {
  description = "Table Storage service endpoint URL"
  value       = azurerm_storage_account.main.primary_table_endpoint
}

# Test commands for validation
output "test_shorten_command" {
  description = "Sample curl command to test URL shortening"
  value = <<-EOT
curl -X POST "${output.shorten_endpoint.value}" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}'
EOT
}

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group    = azurerm_resource_group.main.name
    location         = azurerm_resource_group.main.location
    function_app     = azurerm_linux_function_app.main.name
    storage_account  = azurerm_storage_account.main.name
    table_name       = azurerm_storage_table.url_mappings.name
    app_insights     = var.enable_application_insights ? azurerm_application_insights.main[0].name : "disabled"
    functions_deployed = [
      "shorten (/api/shorten)",
      "redirect (/api/{shortCode})"
    ]
  }
}

# Cost estimation information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD for typical development usage"
  value = {
    function_app_consumption = "Free tier: 1M requests/month, then $0.20 per 1M requests"
    storage_account         = "$0.02-0.05 per GB depending on region and redundancy"
    table_storage          = "$0.045 per 10,000 transactions"
    application_insights   = "Free tier: 1GB/month, then $2.30 per GB"
    total_estimate         = "$0.10-0.50 per month for development/testing workloads"
  }
}

# Security and compliance information
output "security_features" {
  description = "Security features enabled in this deployment"
  value = {
    https_only              = azurerm_linux_function_app.main.https_only
    minimum_tls_version     = var.minimum_tls_version
    storage_encryption      = "Enabled (Azure-managed keys)"
    managed_identity        = "System-assigned identity enabled"
    network_access         = "Public (can be restricted with additional configuration)"
    auth_level             = "Anonymous (functions accessible without keys)"
  }
}