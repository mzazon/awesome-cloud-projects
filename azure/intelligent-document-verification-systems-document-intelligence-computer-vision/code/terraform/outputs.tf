# Output values for Azure Document Verification System

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the resource group containing all resources"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for document processing"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account for document processing"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint URL for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_containers" {
  description = "List of storage containers created for document processing"
  value       = azurerm_storage_container.containers[*].name
}

# Azure Document Intelligence Information
output "document_intelligence_name" {
  description = "Name of the Azure Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.name
}

output "document_intelligence_id" {
  description = "ID of the Azure Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.id
}

output "document_intelligence_endpoint" {
  description = "Endpoint URL for the Azure Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.endpoint
}

output "document_intelligence_location" {
  description = "Location of the Azure Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.location
}

# Azure Computer Vision Information
output "computer_vision_name" {
  description = "Name of the Azure Computer Vision service"
  value       = azurerm_cognitive_account.computer_vision.name
}

output "computer_vision_id" {
  description = "ID of the Azure Computer Vision service"
  value       = azurerm_cognitive_account.computer_vision.id
}

output "computer_vision_endpoint" {
  description = "Endpoint URL for the Azure Computer Vision service"
  value       = azurerm_cognitive_account.computer_vision.endpoint
}

output "computer_vision_location" {
  description = "Location of the Azure Computer Vision service"
  value       = azurerm_cognitive_account.computer_vision.location
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the Azure Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_url" {
  description = "URL of the Azure Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_api_endpoint" {
  description = "API endpoint for document verification function"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/DocumentVerificationFunction"
}

# Service Plan Information
output "service_plan_name" {
  description = "Name of the service plan for the Function App"
  value       = azurerm_service_plan.function_app.name
}

output "service_plan_id" {
  description = "ID of the service plan for the Function App"
  value       = azurerm_service_plan.function_app.id
}

output "service_plan_sku" {
  description = "SKU of the service plan for the Function App"
  value       = azurerm_service_plan.function_app.sku_name
}

# Cosmos DB Information
output "cosmos_db_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_db_account_id" {
  description = "ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.id
}

output "cosmos_db_endpoint" {
  description = "Endpoint URL for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_db_database_name" {
  description = "Name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.main.name
}

output "cosmos_db_container_name" {
  description = "Name of the Cosmos DB container for verification results"
  value       = azurerm_cosmosdb_sql_container.verification_results.name
}

output "cosmos_db_read_endpoints" {
  description = "List of read endpoints for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.read_endpoints
}

output "cosmos_db_write_endpoints" {
  description = "List of write endpoints for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.write_endpoints
}

# Logic App Information (conditional)
output "logic_app_name" {
  description = "Name of the Logic App workflow"
  value       = var.logic_app_enabled ? azurerm_logic_app_workflow.main[0].name : null
}

output "logic_app_id" {
  description = "ID of the Logic App workflow"
  value       = var.logic_app_enabled ? azurerm_logic_app_workflow.main[0].id : null
}

output "logic_app_access_endpoint" {
  description = "Access endpoint for the Logic App workflow"
  value       = var.logic_app_enabled ? azurerm_logic_app_workflow.main[0].access_endpoint : null
}

# API Management Information (conditional)
output "api_management_name" {
  description = "Name of the API Management service"
  value       = var.api_management_enabled ? azurerm_api_management.main[0].name : null
}

output "api_management_id" {
  description = "ID of the API Management service"
  value       = var.api_management_enabled ? azurerm_api_management.main[0].id : null
}

output "api_management_gateway_url" {
  description = "Gateway URL for the API Management service"
  value       = var.api_management_enabled ? azurerm_api_management.main[0].gateway_url : null
}

output "api_management_developer_portal_url" {
  description = "Developer portal URL for the API Management service"
  value       = var.api_management_enabled ? azurerm_api_management.main[0].developer_portal_url : null
}

output "api_management_management_api_url" {
  description = "Management API URL for the API Management service"
  value       = var.api_management_enabled ? azurerm_api_management.main[0].management_api_url : null
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault for storing secrets"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Key Vault for storing secrets"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault for storing secrets"
  value       = azurerm_key_vault.main.vault_uri
}

# Application Insights Information (conditional)
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].id : null
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

# Log Analytics Information (conditional)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

# Configuration Information
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = local.resource_suffix
}

# Connection Information for Integration
output "storage_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "cosmos_connection_string" {
  description = "Connection string for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.connection_strings[0]
  sensitive   = true
}

# Security Information
output "document_intelligence_principal_id" {
  description = "Principal ID of the Document Intelligence managed identity"
  value       = azurerm_cognitive_account.document_intelligence.identity[0].principal_id
}

output "computer_vision_principal_id" {
  description = "Principal ID of the Computer Vision managed identity"
  value       = azurerm_cognitive_account.computer_vision.identity[0].principal_id
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

output "terraform_version" {
  description = "Terraform version used for deployment"
  value       = "~> 1.0"
}

output "azurerm_provider_version" {
  description = "AzureRM provider version used for deployment"
  value       = "~> 3.0"
}

# Quick Start Information
output "quick_start_guide" {
  description = "Quick start guide for using the deployed system"
  value = {
    "1_upload_document" = "Upload a document to the '${azurerm_storage_container.containers[0].name}' container in storage account '${azurerm_storage_account.main.name}'"
    "2_trigger_processing" = var.logic_app_enabled ? "Document processing will be triggered automatically via Logic App" : "Call the Function App API endpoint to process documents"
    "3_api_endpoint" = "https://${azurerm_linux_function_app.main.default_hostname}/api/DocumentVerificationFunction"
    "4_check_results" = "View verification results in Cosmos DB database '${azurerm_cosmosdb_sql_database.main.name}' container '${azurerm_cosmosdb_sql_container.verification_results.name}'"
    "5_monitor" = var.enable_application_insights ? "Monitor application performance in Application Insights '${azurerm_application_insights.main[0].name}'" : "Monitoring disabled - enable Application Insights for detailed monitoring"
    "6_api_management" = var.api_management_enabled ? "Access secure API through API Management gateway: ${azurerm_api_management.main[0].gateway_url}" : "API Management disabled - Function App endpoint is directly accessible"
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the deployed resources"
  value = {
    "storage_account" = "Consider using lifecycle management policies to automatically transition blobs to cooler storage tiers"
    "cosmos_db" = "Monitor RU/s usage and adjust throughput based on actual needs. Consider serverless for unpredictable workloads"
    "function_app" = "Consumption plan scales to zero when not in use. Monitor execution times and memory usage"
    "cognitive_services" = "Free tier available for development and testing. Monitor usage to avoid unexpected charges"
    "application_insights" = "Configure data retention policies and sampling to control costs"
  }
}

# Security Configuration Status
output "security_configuration" {
  description = "Current security configuration status"
  value = {
    "managed_identities" = "Enabled for Function App and Cognitive Services"
    "key_vault" = "Enabled for secure secret storage"
    "private_endpoints" = var.enable_private_endpoints ? "Enabled" : "Disabled - consider enabling for production"
    "network_restrictions" = length(var.allowed_ip_ranges) > 0 ? "IP restrictions configured" : "No IP restrictions - consider adding for production"
    "tls_version" = "Minimum TLS 1.2 enforced on storage account"
    "rbac" = "Role-based access control configured for service-to-service communication"
  }
}