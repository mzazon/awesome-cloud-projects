# Outputs for the intelligent document processing solution

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for document storage"
  value       = azurerm_storage_account.documents.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.documents.primary_blob_endpoint
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.documents.id
}

output "input_container_name" {
  description = "Name of the input documents container"
  value       = azurerm_storage_container.input.name
}

output "processed_container_name" {
  description = "Name of the processed documents container"
  value       = azurerm_storage_container.processed.name
}

# Document Intelligence Information
output "document_intelligence_name" {
  description = "Name of the Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.name
}

output "document_intelligence_endpoint" {
  description = "Endpoint URL of the Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.endpoint
}

output "document_intelligence_id" {
  description = "Resource ID of the Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.id
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

# Logic App Information
output "logic_app_name" {
  description = "Name of the Logic App workflow"
  value       = azurerm_logic_app_workflow.main.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic App workflow"
  value       = azurerm_logic_app_workflow.main.id
}

output "logic_app_access_endpoint" {
  description = "Access endpoint of the Logic App workflow"
  value       = azurerm_logic_app_workflow.main.access_endpoint
}

output "logic_app_callback_url" {
  description = "Callback URL of the Logic App workflow"
  value       = azurerm_logic_app_workflow.main.callback_url
  sensitive   = true
}

output "logic_app_principal_id" {
  description = "Principal ID of the Logic App's managed identity"
  value       = azurerm_logic_app_workflow.main.identity[0].principal_id
}

# Service Bus Information
output "service_bus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "service_bus_namespace_id" {
  description = "Resource ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.id
}

output "service_bus_queue_name" {
  description = "Name of the Service Bus queue for processed documents"
  value       = azurerm_servicebus_queue.processed_docs.name
}

output "service_bus_queue_id" {
  description = "Resource ID of the Service Bus queue"
  value       = azurerm_servicebus_queue.processed_docs.id
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

# API Connection Information
output "blob_storage_connection_id" {
  description = "Resource ID of the Blob Storage API connection"
  value       = azurerm_api_connection.blob_storage.id
}

output "key_vault_connection_id" {
  description = "Resource ID of the Key Vault API connection"
  value       = azurerm_api_connection.key_vault.id
}

output "service_bus_connection_id" {
  description = "Resource ID of the Service Bus API connection"
  value       = azurerm_api_connection.service_bus.id
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# URLs for Quick Access
output "azure_portal_urls" {
  description = "Quick access URLs for Azure Portal"
  value = {
    resource_group        = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/overview"
    storage_account       = "https://portal.azure.com/#@/resource${azurerm_storage_account.documents.id}/overview"
    document_intelligence = "https://portal.azure.com/#@/resource${azurerm_cognitive_account.document_intelligence.id}/overview"
    key_vault            = "https://portal.azure.com/#@/resource${azurerm_key_vault.main.id}/overview"
    logic_app            = "https://portal.azure.com/#@/resource${azurerm_logic_app_workflow.main.id}/overview"
    service_bus          = "https://portal.azure.com/#@/resource${azurerm_servicebus_namespace.main.id}/overview"
  }
}

# Test Command Examples
output "test_commands" {
  description = "Example commands for testing the deployed solution"
  value = {
    upload_test_document = "az storage blob upload --account-name ${azurerm_storage_account.documents.name} --container-name ${azurerm_storage_container.input.name} --file sample-document.pdf --name test-document.pdf"
    check_queue_messages = "az servicebus queue show --name ${azurerm_servicebus_queue.processed_docs.name} --namespace-name ${azurerm_servicebus_namespace.main.name} --resource-group ${azurerm_resource_group.main.name} --query messageCount"
    view_logic_app_runs  = "az logic workflow show --name ${azurerm_logic_app_workflow.main.name} --resource-group ${azurerm_resource_group.main.name}"
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = {
    document_intelligence_free_tier = "Document Intelligence offers 500 free pages per month"
    storage_lifecycle_management   = "Configure storage lifecycle policies to move old documents to cool/archive tiers"
    logic_app_consumption_model    = "Logic App uses consumption-based pricing - you only pay for executions"
    service_bus_scaling           = "Consider Basic tier for Service Bus if advanced features are not needed"
    monitoring_costs              = "Application Insights charges based on data ingestion - configure sampling to reduce costs"
  }
}