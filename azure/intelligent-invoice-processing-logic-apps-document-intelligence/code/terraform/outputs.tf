# Resource Group outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Storage Account outputs
output "storage_account_name" {
  description = "Name of the storage account for invoice documents"
  value       = azurerm_storage_account.invoices.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.invoices.primary_blob_endpoint
}

output "invoices_container_name" {
  description = "Name of the invoices container"
  value       = azurerm_storage_container.invoices.name
}

output "processed_container_name" {
  description = "Name of the processed invoices container"
  value       = azurerm_storage_container.processed.name
}

output "failed_container_name" {
  description = "Name of the failed processing container"
  value       = azurerm_storage_container.failed.name
}

# Azure AI Document Intelligence outputs
output "document_intelligence_name" {
  description = "Name of the Azure AI Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.name
}

output "document_intelligence_endpoint" {
  description = "Endpoint URL for the Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.endpoint
}

output "document_intelligence_id" {
  description = "Resource ID of the Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.id
}

# Service Bus outputs
output "service_bus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "service_bus_namespace_id" {
  description = "Resource ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.id
}

output "invoice_processing_topic_name" {
  description = "Name of the invoice processing topic"
  value       = azurerm_servicebus_topic.invoice_processing.name
}

output "processed_invoices_queue_name" {
  description = "Name of the processed invoices queue"
  value       = azurerm_servicebus_queue.processed_invoices.name
}

output "approval_queue_name" {
  description = "Name of the approval queue"
  value       = azurerm_servicebus_queue.approval_queue.name
}

# Logic App outputs
output "logic_app_name" {
  description = "Name of the Logic App workflow"
  value       = azurerm_logic_app_workflow.invoice_processor.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic App workflow"
  value       = azurerm_logic_app_workflow.invoice_processor.id
}

output "logic_app_callback_url" {
  description = "Callback URL for the Logic App trigger"
  value       = "https://${azurerm_logic_app_workflow.invoice_processor.name}.logic.azure.com"
  sensitive   = false
}

# Function App outputs
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.invoice_processor.name
}

output "function_app_id" {
  description = "Resource ID of the Function App"
  value       = azurerm_linux_function_app.invoice_processor.id
}

output "function_app_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.invoice_processor.default_hostname
}

# Application Insights outputs (conditional)
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# Event Grid outputs
output "eventgrid_system_topic_name" {
  description = "Name of the Event Grid system topic"
  value       = azurerm_eventgrid_system_topic.storage_events.name
}

output "eventgrid_subscription_name" {
  description = "Name of the Event Grid event subscription"
  value       = azurerm_eventgrid_event_subscription.blob_created.name
}

# Key Vault outputs
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

# API Connection outputs
output "blob_api_connection_name" {
  description = "Name of the blob storage API connection"
  value       = azurerm_api_connection.blob_connection.name
}

output "servicebus_api_connection_name" {
  description = "Name of the Service Bus API connection"
  value       = azurerm_api_connection.servicebus_connection.name
}

output "office365_api_connection_name" {
  description = "Name of the Office 365 API connection"
  value       = azurerm_api_connection.office365_connection.name
}

# Configuration outputs for integration
output "invoice_upload_instructions" {
  description = "Instructions for uploading invoices"
  value = <<-EOT
    To upload invoices for processing:
    1. Access the storage account: ${azurerm_storage_account.invoices.name}
    2. Upload files to the '${azurerm_storage_container.invoices.name}' container
    3. Supported formats: PDF, JPEG, PNG, TIFF
    4. Processing will begin automatically via Event Grid triggers
    
    Storage Account URL: ${azurerm_storage_account.invoices.primary_blob_endpoint}
    Container Path: ${azurerm_storage_account.invoices.primary_blob_endpoint}${azurerm_storage_container.invoices.name}/
  EOT
}

output "monitoring_dashboard_url" {
  description = "URL to monitor invoice processing workflows"
  value       = var.enable_monitoring ? "https://portal.azure.com/#@/resource${azurerm_application_insights.main[0].id}/overview" : "Monitoring not enabled"
}

output "logic_app_designer_url" {
  description = "URL to open Logic App in designer"
  value       = "https://portal.azure.com/#@/resource${azurerm_logic_app_workflow.invoice_processor.id}/logicApp"
}

# Summary output with key information
output "deployment_summary" {
  description = "Summary of deployed resources and next steps"
  value = {
    resource_group    = azurerm_resource_group.main.name
    storage_account   = azurerm_storage_account.invoices.name
    upload_container  = azurerm_storage_container.invoices.name
    logic_app        = azurerm_logic_app_workflow.invoice_processor.name
    function_app     = azurerm_linux_function_app.invoice_processor.name
    document_ai      = azurerm_cognitive_account.document_intelligence.name
    service_bus      = azurerm_servicebus_namespace.main.name
    key_vault        = azurerm_key_vault.main.name
    approval_threshold = var.invoice_approval_threshold
    approver_email   = var.approver_email
    next_steps = [
      "1. Configure Office 365 connection for email notifications",
      "2. Upload test invoice documents to the '${azurerm_storage_container.invoices.name}' container",
      "3. Monitor Logic App execution in Azure portal",
      "4. Review processed invoices in the '${azurerm_storage_container.processed.name}' container",
      "5. Configure additional approval workflows as needed"
    ]
  }
}

# Sensitive outputs (marked as sensitive)
output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.invoices.primary_access_key
  sensitive   = true
}

output "document_intelligence_primary_key" {
  description = "Primary access key for the Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.primary_access_key
  sensitive   = true
}

output "service_bus_primary_connection_string" {
  description = "Primary connection string for the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.default_primary_connection_string
  sensitive   = true
}