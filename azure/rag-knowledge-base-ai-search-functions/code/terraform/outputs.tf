# Outputs for Azure RAG Knowledge Base Infrastructure

# Resource Group
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.rag_kb.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.rag_kb.location
}

# Storage Account
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.rag_kb.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.rag_kb.id
}

output "storage_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.rag_kb.primary_connection_string
  sensitive   = true
}

output "documents_container_name" {
  description = "Name of the documents container"
  value       = azurerm_storage_container.documents.name
}

output "documents_container_url" {
  description = "URL of the documents container"
  value       = "https://${azurerm_storage_account.rag_kb.name}.blob.core.windows.net/${azurerm_storage_container.documents.name}"
}

# Azure AI Search Service
output "search_service_name" {
  description = "Name of the AI Search service"
  value       = azurerm_search_service.rag_kb.name
}

output "search_service_id" {
  description = "ID of the AI Search service"
  value       = azurerm_search_service.rag_kb.id
}

output "search_service_endpoint" {
  description = "Endpoint URL of the AI Search service"
  value       = "https://${azurerm_search_service.rag_kb.name}.search.windows.net"
}

output "search_service_primary_key" {
  description = "Primary admin key for the AI Search service"
  value       = azurerm_search_service.rag_kb.primary_key
  sensitive   = true
}

output "search_service_query_keys" {
  description = "Query keys for the AI Search service"
  value       = azurerm_search_service.rag_kb.query_keys
  sensitive   = true
}

output "search_index_name" {
  description = "Name of the search index"
  value       = var.search_index_name
}

output "search_datasource_name" {
  description = "Name of the search data source"
  value       = var.search_datasource_name
}

output "search_indexer_name" {
  description = "Name of the search indexer"
  value       = var.search_indexer_name
}

# Azure OpenAI Service
output "openai_service_name" {
  description = "Name of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_service_id" {
  description = "ID of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.id
}

output "openai_endpoint" {
  description = "Endpoint URL of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_primary_key" {
  description = "Primary access key for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_deployment_name" {
  description = "Name of the OpenAI model deployment"
  value       = azurerm_cognitive_deployment.gpt4o.name
}

output "openai_model_name" {
  description = "Name of the deployed OpenAI model"
  value       = azurerm_cognitive_deployment.gpt4o.model[0].name
}

output "openai_model_version" {
  description = "Version of the deployed OpenAI model"
  value       = azurerm_cognitive_deployment.gpt4o.model[0].version
}

# Function App
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.rag_kb.name
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.rag_kb.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.rag_kb.default_hostname
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.rag_kb.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.rag_kb.identity[0].principal_id
}

output "function_app_identity_tenant_id" {
  description = "Tenant ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.rag_kb.identity[0].tenant_id
}

# Application Insights
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.rag_kb.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.rag_kb.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.rag_kb.connection_string
  sensitive   = true
}

# Service Plan
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.rag_kb.name
}

output "service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.rag_kb.id
}

# Sample documents (only if created)
output "sample_documents_created" {
  description = "Whether sample documents were created"
  value       = var.create_sample_documents
}

output "sample_document_urls" {
  description = "URLs of the sample documents (if created)"
  value = var.create_sample_documents ? [
    "https://${azurerm_storage_account.rag_kb.name}.blob.core.windows.net/${azurerm_storage_container.documents.name}/${azurerm_storage_blob.sample_doc1[0].name}",
    "https://${azurerm_storage_account.rag_kb.name}.blob.core.windows.net/${azurerm_storage_container.documents.name}/${azurerm_storage_blob.sample_doc2[0].name}"
  ] : []
}

# Configuration information for testing
output "rag_api_test_curl_command" {
  description = "Sample curl command to test the RAG API (requires function key)"
  value = <<-EOT
    # First, get the function key:
    az functionapp keys list --name ${azurerm_linux_function_app.rag_kb.name} --resource-group ${azurerm_resource_group.rag_kb.name} --query functionKeys.default --output tsv

    # Then test the API:
    curl -X POST "https://${azurerm_linux_function_app.rag_kb.default_hostname}/api/rag_query?code=<FUNCTION_KEY>" \
      -H "Content-Type: application/json" \
      -d '{"query": "What are the key features of Azure Functions?"}'
  EOT
}

# Search service test commands
output "search_service_test_commands" {
  description = "Commands to test the AI Search service directly"
  value = <<-EOT
    # Check document count:
    curl -X GET "https://${azurerm_search_service.rag_kb.name}.search.windows.net/indexes/${var.search_index_name}/docs/\$count?api-version=2023-11-01" \
      -H "api-key: ${azurerm_search_service.rag_kb.primary_key}"

    # Search for content:
    curl -X POST "https://${azurerm_search_service.rag_kb.name}.search.windows.net/indexes/${var.search_index_name}/docs/search?api-version=2023-11-01" \
      -H "Content-Type: application/json" \
      -H "api-key: ${azurerm_search_service.rag_kb.primary_key}" \
      -d '{"search": "Azure Functions", "top": 3}'
  EOT
  sensitive = true
}

# Deployment summary
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group     = azurerm_resource_group.rag_kb.name
    location          = azurerm_resource_group.rag_kb.location
    storage_account   = azurerm_storage_account.rag_kb.name
    search_service    = azurerm_search_service.rag_kb.name
    search_sku        = azurerm_search_service.rag_kb.sku
    openai_service    = azurerm_cognitive_account.openai.name
    openai_model      = "${azurerm_cognitive_deployment.gpt4o.model[0].name}:${azurerm_cognitive_deployment.gpt4o.model[0].version}"
    function_app      = azurerm_linux_function_app.rag_kb.name
    function_runtime  = "Python ${var.function_python_version}"
    search_index      = var.search_index_name
    estimated_monthly_cost = "Consumption Plan: ~$5-15, Basic Search: ~$250, OpenAI S0: ~$10+ per deployment"
  }
}

# Security and access information
output "security_information" {
  description = "Security and access configuration summary"
  value = {
    function_managed_identity = azurerm_linux_function_app.rag_kb.identity[0].principal_id
    search_public_access     = var.search_public_access
    openai_public_access     = var.openai_public_access
    storage_encryption       = "Enabled (default)"
    https_only              = "Enabled for Function App"
    cors_origins            = var.function_cors_origins
  }
}