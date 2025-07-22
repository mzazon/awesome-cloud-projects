# Output values for Azure multi-language content localization workflow
# These outputs provide important information about the deployed resources

output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.localization.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.localization.location
}

output "storage_account_name" {
  description = "Name of the storage account for documents"
  value       = azurerm_storage_account.documents.name
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.documents.primary_access_key
  sensitive   = true
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.documents.primary_connection_string
  sensitive   = true
}

output "storage_containers" {
  description = "Names of the storage containers created for the workflow"
  value = {
    source_documents      = azurerm_storage_container.source_documents.name
    processing_workspace  = azurerm_storage_container.processing_workspace.name
    localized_output     = azurerm_storage_container.localized_output.name
    workflow_logs        = azurerm_storage_container.workflow_logs.name
  }
}

output "translator_service_name" {
  description = "Name of the Azure Translator service"
  value       = azurerm_cognitive_account.translator.name
}

output "translator_service_endpoint" {
  description = "Endpoint URL for the Azure Translator service"
  value       = azurerm_cognitive_account.translator.endpoint
}

output "translator_service_key" {
  description = "Primary access key for the Azure Translator service"
  value       = azurerm_cognitive_account.translator.primary_access_key
  sensitive   = true
}

output "translator_service_region" {
  description = "Region where the Azure Translator service is deployed"
  value       = azurerm_cognitive_account.translator.location
}

output "document_intelligence_service_name" {
  description = "Name of the Azure Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.name
}

output "document_intelligence_service_endpoint" {
  description = "Endpoint URL for the Azure Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.endpoint
}

output "document_intelligence_service_key" {
  description = "Primary access key for the Azure Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.primary_access_key
  sensitive   = true
}

output "document_intelligence_service_region" {
  description = "Region where the Azure Document Intelligence service is deployed"
  value       = azurerm_cognitive_account.document_intelligence.location
}

output "logic_app_name" {
  description = "Name of the Logic App workflow"
  value       = azurerm_logic_app_workflow.localization.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic App workflow"
  value       = azurerm_logic_app_workflow.localization.id
}

output "logic_app_access_endpoint" {
  description = "Access endpoint for the Logic App workflow"
  value       = azurerm_logic_app_workflow.localization.access_endpoint
}

output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.localization.name
}

output "subnet_name" {
  description = "Name of the subnet for localization services"
  value       = azurerm_subnet.localization.name
}

output "api_connections" {
  description = "Information about the API connections"
  value = {
    blob_storage = {
      name = azurerm_api_connection.blob_storage.name
      id   = azurerm_api_connection.blob_storage.id
    }
    cognitive_services = {
      name = azurerm_api_connection.cognitive_services.name
      id   = azurerm_api_connection.cognitive_services.id
    }
  }
}

output "target_languages" {
  description = "List of target languages configured for translation"
  value       = var.target_languages
}

output "application_insights_name" {
  description = "Name of the Application Insights instance (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.localization[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.localization[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.localization[0].connection_string : null
  sensitive   = true
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.localization[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.localization[0].workspace_id : null
}

output "monitoring_alerts" {
  description = "Information about configured monitoring alerts (if monitoring enabled)"
  value = var.enable_monitoring ? {
    translator_high_usage = {
      name = azurerm_monitor_metric_alert.translator_high_usage[0].name
      id   = azurerm_monitor_metric_alert.translator_high_usage[0].id
    }
    document_intelligence_errors = {
      name = azurerm_monitor_metric_alert.document_intelligence_errors[0].name
      id   = azurerm_monitor_metric_alert.document_intelligence_errors[0].id
    }
  } : null
}

output "deployment_summary" {
  description = "Summary of the deployed localization workflow"
  value = {
    resource_group        = azurerm_resource_group.localization.name
    location             = azurerm_resource_group.localization.location
    storage_account      = azurerm_storage_account.documents.name
    translator_service   = azurerm_cognitive_account.translator.name
    document_intelligence = azurerm_cognitive_account.document_intelligence.name
    logic_app           = azurerm_logic_app_workflow.localization.name
    target_languages    = var.target_languages
    monitoring_enabled  = var.enable_monitoring
    diagnostic_logs     = var.enable_diagnostic_logs
  }
}

output "next_steps" {
  description = "Next steps for using the deployed localization workflow"
  value = {
    upload_documents = "Upload documents to the '${azurerm_storage_container.source_documents.name}' container in storage account '${azurerm_storage_account.documents.name}'"
    monitor_workflow = "Monitor the Logic App '${azurerm_logic_app_workflow.localization.name}' for processing status"
    retrieve_translations = "Retrieve translated documents from the '${azurerm_storage_container.localized_output.name}' container"
    view_logs = "Check workflow logs in the '${azurerm_storage_container.workflow_logs.name}' container"
    azure_portal = "Visit the Azure portal to view and manage the deployed resources"
  }
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the deployed services"
  value = {
    translator_service = "Varies by usage - ${var.translator_sku} tier provides 2M characters/month"
    document_intelligence = "Varies by usage - ${var.document_intelligence_sku} tier pricing applies"
    storage_account = "Approximately $5-20/month depending on storage and transactions"
    logic_app = "Approximately $10-50/month depending on executions"
    monitoring = var.enable_monitoring ? "Approximately $10-30/month for Application Insights and Log Analytics" : "Monitoring disabled"
    total_estimate = "Estimated range: $25-125/month for typical usage patterns"
  }
}

output "security_considerations" {
  description = "Important security considerations for the deployed workflow"
  value = {
    access_keys = "Store service keys securely and rotate them regularly"
    network_security = "Virtual network and service endpoints configured for secure communication"
    data_encryption = "Data is encrypted at rest and in transit by default"
    monitoring = var.enable_monitoring ? "Monitoring and alerting configured for security events" : "Consider enabling monitoring for security visibility"
    compliance = "Ensure compliance with data protection regulations when processing documents"
  }
}