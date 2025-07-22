# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Azure OpenAI Service Outputs
output "openai_service_name" {
  description = "Name of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_endpoint" {
  description = "Endpoint URL for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_primary_key" {
  description = "Primary access key for Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_deployment_name" {
  description = "Name of the text embedding model deployment"
  value       = azurerm_cognitive_deployment.text_embedding.name
}

# PostgreSQL Database Outputs
output "postgresql_server_name" {
  description = "Name of the PostgreSQL flexible server"
  value       = azurerm_postgresql_flexible_server.main.name
}

output "postgresql_server_fqdn" {
  description = "Fully qualified domain name of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "postgresql_admin_username" {
  description = "Administrator username for PostgreSQL"
  value       = azurerm_postgresql_flexible_server.main.administrator_login
}

output "postgresql_connection_string" {
  description = "Connection string for PostgreSQL database"
  value       = "host=${azurerm_postgresql_flexible_server.main.fqdn} port=5432 dbname=postgres user=${azurerm_postgresql_flexible_server.main.administrator_login} password=${var.postgresql_admin_password} sslmode=require"
  sensitive   = true
}

# Azure AI Search Service Outputs
output "search_service_name" {
  description = "Name of the Azure AI Search service"
  value       = azurerm_search_service.main.name
}

output "search_service_endpoint" {
  description = "Endpoint URL for the Azure AI Search service"
  value       = "https://${azurerm_search_service.main.name}.search.windows.net"
}

output "search_service_primary_key" {
  description = "Primary admin key for Azure AI Search service"
  value       = azurerm_search_service.main.primary_key
  sensitive   = true
}

# Azure Functions Outputs
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_url" {
  description = "URL of the Azure Function App"
  value       = "https://${azurerm_linux_function_app.main.name}.azurewebsites.net"
}

output "function_app_identity" {
  description = "Managed identity of the Function App"
  value       = azurerm_linux_function_app.main.identity
}

# Storage Account Outputs
output "function_storage_account_name" {
  description = "Name of the Function App storage account"
  value       = azurerm_storage_account.function_storage.name
}

output "document_storage_account_name" {
  description = "Name of the document storage account"
  value       = azurerm_storage_account.document_storage.name
}

output "document_storage_connection_string" {
  description = "Connection string for document storage account"
  value       = azurerm_storage_account.document_storage.primary_connection_string
  sensitive   = true
}

output "document_container_name" {
  description = "Name of the document storage container"
  value       = azurerm_storage_container.documents.name
}

# Key Vault Outputs
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Monitoring Outputs (if enabled)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
}

output "application_insights_name" {
  description = "Name of the Application Insights resource"
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

# Network Outputs (if private endpoints are enabled)
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].name : null
}

output "private_endpoints_subnet_name" {
  description = "Name of the private endpoints subnet"
  value       = var.enable_private_endpoints ? azurerm_subnet.private_endpoints[0].name : null
}

# API Endpoints for Testing
output "process_document_endpoint" {
  description = "Endpoint for document processing API"
  value       = "https://${azurerm_linux_function_app.main.name}.azurewebsites.net/api/process_document"
}

output "hybrid_search_endpoint" {
  description = "Endpoint for hybrid search API"
  value       = "https://${azurerm_linux_function_app.main.name}.azurewebsites.net/api/hybrid_search"
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group       = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    openai_service      = azurerm_cognitive_account.openai.name
    postgresql_server   = azurerm_postgresql_flexible_server.main.name
    search_service      = azurerm_search_service.main.name
    function_app        = azurerm_linux_function_app.main.name
    storage_accounts    = [
      azurerm_storage_account.function_storage.name,
      azurerm_storage_account.document_storage.name
    ]
    key_vault           = azurerm_key_vault.main.name
    monitoring_enabled  = var.enable_monitoring
    private_endpoints   = var.enable_private_endpoints
    environment         = var.environment
  }
}

# Environment Variables for Function App
output "function_app_environment_variables" {
  description = "Environment variables configured for the Function App"
  value = {
    OPENAI_ENDPOINT               = azurerm_cognitive_account.openai.endpoint
    POSTGRES_HOST                 = azurerm_postgresql_flexible_server.main.fqdn
    POSTGRES_USER                 = var.postgresql_admin_username
    POSTGRES_DATABASE             = "postgres"
    SEARCH_ENDPOINT               = "https://${azurerm_search_service.main.name}.search.windows.net"
    SEARCH_INDEX_NAME             = "documents-index"
    DOCUMENT_CONTAINER_NAME       = azurerm_storage_container.documents.name
    ENVIRONMENT                   = var.environment
    PROJECT_NAME                  = var.project_name
  }
}

# Database Connection Information
output "database_connection_info" {
  description = "Information for connecting to the PostgreSQL database"
  value = {
    host     = azurerm_postgresql_flexible_server.main.fqdn
    port     = 5432
    database = "postgres"
    username = var.postgresql_admin_username
    ssl_mode = "require"
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Quick start commands for testing the deployment"
  value = {
    test_document_processing = "curl -X POST 'https://${azurerm_linux_function_app.main.name}.azurewebsites.net/api/process_document' -H 'Content-Type: application/json' -d '{\"title\": \"Test Document\", \"content\": \"This is a test document for the hybrid search system.\", \"content_type\": \"text/plain\"}'"
    test_hybrid_search      = "curl -X POST 'https://${azurerm_linux_function_app.main.name}.azurewebsites.net/api/hybrid_search' -H 'Content-Type: application/json' -d '{\"query\": \"test document\", \"top_k\": 5}'"
    connect_to_postgres     = "psql 'host=${azurerm_postgresql_flexible_server.main.fqdn} port=5432 dbname=postgres user=${azurerm_postgresql_flexible_server.main.administrator_login} password=${var.postgresql_admin_password} sslmode=require'"
  }
}