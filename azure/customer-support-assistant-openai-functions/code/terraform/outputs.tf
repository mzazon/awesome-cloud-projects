# Output values for Customer Support Assistant with OpenAI Assistants and Functions
# These outputs provide essential information for deployment verification and integration

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all support assistant resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "Resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account used for support data"
  value       = azurerm_storage_account.support_data.name
}

output "storage_account_id" {
  description = "Resource ID of the support data storage account"
  value       = azurerm_storage_account.support_data.id
}

output "storage_connection_string" {
  description = "Connection string for the support data storage account"
  value       = azurerm_storage_account.support_data.primary_connection_string
  sensitive   = true
}

output "storage_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.support_data.primary_access_key
  sensitive   = true
}

# Storage Services Information
output "tickets_table_name" {
  description = "Name of the storage table for tickets"
  value       = azurerm_storage_table.tickets.name
}

output "customers_table_name" {
  description = "Name of the storage table for customer data"
  value       = azurerm_storage_table.customers.name
}

output "faqs_container_name" {
  description = "Name of the blob container for FAQ documents"
  value       = azurerm_storage_container.faqs.name
}

output "escalations_queue_name" {
  description = "Name of the storage queue for escalations"
  value       = azurerm_storage_queue.escalations.name
}

# Azure OpenAI Service Information
output "openai_service_name" {
  description = "Name of the Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_service_id" {
  description = "Resource ID of the Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.id
}

output "openai_endpoint" {
  description = "Endpoint URL for the Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_primary_key" {
  description = "Primary access key for the Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_secondary_key" {
  description = "Secondary access key for the Azure OpenAI Service"  
  value       = azurerm_cognitive_account.openai.secondary_access_key
  sensitive   = true
}

output "openai_custom_domain" {
  description = "Custom subdomain name for the Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.custom_subdomain_name
}

# GPT-4o Model Deployment Information
output "gpt4o_deployment_name" {
  description = "Name of the GPT-4o model deployment"
  value       = azurerm_cognitive_deployment.gpt4o.name
}

output "gpt4o_deployment_id" {
  description = "Resource ID of the GPT-4o model deployment"
  value       = azurerm_cognitive_deployment.gpt4o.id
}

output "gpt4o_model_version" {
  description = "Version of the deployed GPT-4o model"
  value       = azurerm_cognitive_deployment.gpt4o.model[0].version
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.support_functions.name
}

output "function_app_id" {
  description = "Resource ID of the Azure Function App"
  value       = azurerm_linux_function_app.support_functions.id
}

output "function_app_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.support_functions.default_hostname
}

output "function_app_url" {
  description = "Default URL of the Function App"
  value       = "https://${azurerm_linux_function_app.support_functions.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's system-assigned managed identity"
  value       = azurerm_linux_function_app.support_functions.identity[0].principal_id
}

output "function_app_identity_tenant_id" {
  description = "Tenant ID of the Function App's system-assigned managed identity"
  value       = azurerm_linux_function_app.support_functions.identity[0].tenant_id
}

# Service Plan Information
output "service_plan_name" {
  description = "Name of the App Service Plan for the Function App"
  value       = azurerm_service_plan.function_plan.name
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.function_plan.id
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.function_insights.name
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights instance"
  value       = azurerm_application_insights.function_insights.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.function_insights.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.function_insights.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = azurerm_application_insights.function_insights.app_id
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.support_logs.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.support_logs.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.support_logs.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.support_logs.primary_shared_key
  sensitive   = true
}

# Function Endpoints (for external integration)
output "ticket_lookup_function_url" {
  description = "URL for the ticket lookup function endpoint"
  value       = "https://${azurerm_linux_function_app.support_functions.default_hostname}/api/ticketLookup"
}

output "faq_retrieval_function_url" {
  description = "URL for the FAQ retrieval function endpoint"
  value       = "https://${azurerm_linux_function_app.support_functions.default_hostname}/api/faqRetrieval"
}

output "ticket_creation_function_url" {
  description = "URL for the ticket creation function endpoint"
  value       = "https://${azurerm_linux_function_app.support_functions.default_hostname}/api/ticketCreation"
}

output "escalation_function_url" {
  description = "URL for the escalation function endpoint"
  value       = "https://${azurerm_linux_function_app.support_functions.default_hostname}/api/escalation"
}

# Configuration Values for External Use
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "deployment_timestamp" {
  description = "Timestamp when the deployment was created"
  value       = timestamp()
}

# Summary Information
output "deployment_summary" {
  description = "Summary of deployed resources and their key information"
  value = {
    resource_group_name      = azurerm_resource_group.main.name
    location                = azurerm_resource_group.main.location
    storage_account_name    = azurerm_storage_account.support_data.name
    openai_service_name     = azurerm_cognitive_account.openai.name
    function_app_name       = azurerm_linux_function_app.support_functions.name
    function_app_url        = "https://${azurerm_linux_function_app.support_functions.default_hostname}"
    openai_endpoint         = azurerm_cognitive_account.openai.endpoint
    gpt4o_deployment_name   = azurerm_cognitive_deployment.gpt4o.name
    random_suffix           = random_string.suffix.result
  }
}