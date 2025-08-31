# Outputs for Azure QR Code Generator Infrastructure
# Provides essential information for accessing and managing the deployed resources

output "resource_group_name" {
  description = "Name of the created resource group containing all QR generator resources"
  value       = azurerm_resource_group.qr_generator.name
}

output "resource_group_location" {
  description = "Azure region where the resource group and resources are deployed"
  value       = azurerm_resource_group.qr_generator.location
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account used for QR code image storage"
  value       = azurerm_storage_account.qr_storage.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob service endpoint URL for the storage account"
  value       = azurerm_storage_account.qr_storage.primary_blob_endpoint
}

output "storage_connection_string" {
  description = "Primary connection string for the storage account (sensitive)"
  value       = azurerm_storage_account.qr_storage.primary_connection_string
  sensitive   = true
}

output "blob_container_name" {
  description = "Name of the blob container storing QR code images"
  value       = azurerm_storage_container.qr_codes.name
}

output "blob_container_url" {
  description = "Public URL for accessing the QR codes blob container"
  value       = "${azurerm_storage_account.qr_storage.primary_blob_endpoint}${azurerm_storage_container.qr_codes.name}/"
}

# Function App Outputs
output "function_app_name" {
  description = "Name of the Azure Functions app hosting the QR generator"
  value       = azurerm_linux_function_app.qr_generator.name
}

output "function_app_hostname" {
  description = "Default hostname of the Function App for HTTP access"
  value       = azurerm_linux_function_app.qr_generator.default_hostname
}

output "function_app_url" {
  description = "Complete HTTPS URL for accessing the Function App"
  value       = "https://${azurerm_linux_function_app.qr_generator.default_hostname}"
}

output "qr_generator_endpoint" {
  description = "Complete URL for the QR code generation API endpoint"
  value       = "https://${azurerm_linux_function_app.qr_generator.default_hostname}/api/generate-qr"
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's system-assigned managed identity"
  value       = azurerm_linux_function_app.qr_generator.identity[0].principal_id
}

# Service Plan Outputs
output "app_service_plan_name" {
  description = "Name of the App Service Plan (Consumption plan) for the Function App"
  value       = azurerm_service_plan.qr_generator.name
}

output "app_service_plan_sku" {
  description = "SKU tier of the App Service Plan"
  value       = azurerm_service_plan.qr_generator.sku_name
}

# Application Insights Outputs (conditional)
output "application_insights_name" {
  description = "Name of the Application Insights instance for monitoring"
  value       = var.enable_application_insights ? azurerm_application_insights.qr_generator[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive)"
  value       = var.enable_application_insights ? azurerm_application_insights.qr_generator[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.qr_generator[0].app_id : null
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Testing and Validation Outputs
output "curl_test_command" {
  description = "Example curl command to test the QR code generation endpoint"
  value = <<-EOT
curl -X POST "${azurerm_linux_function_app.qr_generator.default_hostname}/api/generate-qr" \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello Azure Functions!"}'
EOT
}

output "azure_cli_test_commands" {
  description = "Azure CLI commands to verify the deployment"
  value = {
    check_function_status = "az functionapp show --name ${azurerm_linux_function_app.qr_generator.name} --resource-group ${azurerm_resource_group.qr_generator.name} --query '{name:name,state:state,hostNames:defaultHostName}' --output table"
    list_blob_containers  = "az storage container list --account-name ${azurerm_storage_account.qr_storage.name} --output table"
    list_qr_codes        = "az storage blob list --container-name ${azurerm_storage_container.qr_codes.name} --account-name ${azurerm_storage_account.qr_storage.name} --output table"
  }
}

# Resource Cleanup Information
output "cleanup_commands" {
  description = "Commands to clean up the deployed resources"
  value = {
    delete_resource_group = "az group delete --name ${azurerm_resource_group.qr_generator.name} --yes --no-wait"
    terraform_destroy     = "terraform destroy -auto-approve"
  }
}

# Cost and Monitoring Information
output "cost_monitoring_tags" {
  description = "Tags applied to resources for cost tracking and management"
  value       = local.common_tags
}

output "monitoring_dashboard_url" {
  description = "URL to view the Function App in Azure Portal"
  value       = "https://portal.azure.com/#@/resource${azurerm_linux_function_app.qr_generator.id}/overview"
}