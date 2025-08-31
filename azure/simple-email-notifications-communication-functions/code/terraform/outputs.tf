# Outputs for Azure Email Notifications Infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Communication Services Information
output "communication_service_name" {
  description = "Name of the Communication Services resource"
  value       = azurerm_communication_service.main.name
}

output "communication_service_endpoint" {
  description = "Endpoint URL for the Communication Services resource"
  value       = azurerm_communication_service.main.endpoint
}

output "communication_service_connection_string" {
  description = "Primary connection string for Communication Services (sensitive)"
  value       = azurerm_communication_service.main.primary_connection_string
  sensitive   = true
}

# Email Service Information
output "email_service_name" {
  description = "Name of the Email Communication Service"
  value       = azurerm_email_communication_service.main.name
}

output "managed_domain_name" {
  description = "Azure managed domain name for email sending"
  value       = azurerm_email_communication_service_domain.main.from_sender_domain
}

output "sender_email_address" {
  description = "Complete sender email address using the managed domain"
  value       = "donotreply@${azurerm_email_communication_service_domain.main.from_sender_domain}"
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account used by the Function App"
  value       = azurerm_storage_account.function_storage.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.function_storage.primary_blob_endpoint
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "Base URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_endpoint_url" {
  description = "Complete URL for the email function endpoint (requires function key)"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/index"
}

# Function App Keys (for API access)
output "function_app_master_key" {
  description = "Master key for the Function App (sensitive)"
  value       = azurerm_linux_function_app.main.master_key
  sensitive   = true
}

# App Service Plan Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_sku" {
  description = "SKU name of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# Application Insights Information (if enabled)
output "application_insights_name" {
  description = "Name of the Application Insights resource (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key (sensitive, if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application Insights application ID (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].app_id : null
}

# Testing and Validation Information
output "curl_test_command" {
  description = "Sample curl command to test the email function (requires function key)"
  value = <<-EOT
curl -X POST "https://${azurerm_linux_function_app.main.default_hostname}/api/index?code=<FUNCTION_KEY>" \
     -H "Content-Type: application/json" \
     -d '{
       "to": "your-email@example.com",
       "subject": "Test Email from Azure Functions",
       "body": "This is a test email sent from Azure Functions using Communication Services."
     }'
  EOT
}

# Resource Identifiers for Integration
output "communication_service_id" {
  description = "Azure resource ID of the Communication Services resource"
  value       = azurerm_communication_service.main.id
}

output "email_service_id" {
  description = "Azure resource ID of the Email Communication Service"
  value       = azurerm_email_communication_service.main.id
}

output "function_app_id" {
  description = "Azure resource ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "storage_account_id" {
  description = "Azure resource ID of the storage account"
  value       = azurerm_storage_account.function_storage.id
}

# Cost and Resource Management
output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

output "random_suffix" {
  description = "Random suffix used in resource naming"
  value       = local.random_suffix
}

# Monitoring and Diagnostics URLs
output "azure_portal_function_app_url" {
  description = "Direct URL to the Function App in Azure Portal"
  value       = "https://portal.azure.com/#@/resource${azurerm_linux_function_app.main.id}"
}

output "azure_portal_communication_services_url" {
  description = "Direct URL to Communication Services in Azure Portal"
  value       = "https://portal.azure.com/#@/resource${azurerm_communication_service.main.id}"
}

# Security and Access Information
output "function_app_outbound_ip_addresses" {
  description = "Outbound IP addresses of the Function App"
  value       = azurerm_linux_function_app.main.outbound_ip_addresses
}

output "function_app_possible_outbound_ip_addresses" {
  description = "All possible outbound IP addresses of the Function App"
  value       = azurerm_linux_function_app.main.possible_outbound_ip_addresses
}