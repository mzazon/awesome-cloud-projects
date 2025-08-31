# Output values for the Learning Assessment Generator infrastructure
# These outputs provide essential information for application deployment and integration

# Resource Group Information
output "resource_group_name" {
  description = "The name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "The location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "The ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Storage Account Information
output "storage_account_name" {
  description = "The name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "The primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_connection_string" {
  description = "The primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "documents_container_name" {
  description = "The name of the documents storage container"
  value       = azurerm_storage_container.documents.name
}

output "documents_container_url" {
  description = "The URL of the documents container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.documents.name}"
}

# Document Intelligence Service Information
output "document_intelligence_name" {
  description = "The name of the Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.name
}

output "document_intelligence_endpoint" {
  description = "The endpoint URL for the Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.endpoint
}

output "document_intelligence_key" {
  description = "The primary access key for the Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.primary_access_key
  sensitive   = true
}

output "document_intelligence_id" {
  description = "The ID of the Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.id
}

# Azure OpenAI Service Information
output "openai_account_name" {
  description = "The name of the Azure OpenAI account"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_endpoint" {
  description = "The endpoint URL for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_key" {
  description = "The primary access key for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_deployment_name" {
  description = "The name of the deployed OpenAI model"
  value       = azurerm_cognitive_deployment.gpt_model.name
}

output "openai_model_info" {
  description = "Information about the deployed OpenAI model"
  value = {
    model_name    = var.openai_model_name
    model_version = var.openai_model_version
    capacity      = var.openai_deployment_capacity
  }
}

# Cosmos DB Information
output "cosmosdb_account_name" {
  description = "The name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmosdb_endpoint" {
  description = "The endpoint URL for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmosdb_primary_key" {
  description = "The primary key for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

output "cosmosdb_connection_strings" {
  description = "The connection strings for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.connection_strings
  sensitive   = true
}

output "cosmosdb_database_name" {
  description = "The name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.main.name
}

output "cosmosdb_containers" {
  description = "Information about the Cosmos DB containers"
  value = {
    documents = {
      name           = azurerm_cosmosdb_sql_container.documents.name
      partition_key  = azurerm_cosmosdb_sql_container.documents.partition_key_path
    }
    assessments = {
      name           = azurerm_cosmosdb_sql_container.assessments.name
      partition_key  = azurerm_cosmosdb_sql_container.assessments.partition_key_path
    }
  }
}

# Function App Information
output "function_app_name" {
  description = "The name of the Function App"
  value       = var.function_app_os_type == "Linux" ? azurerm_linux_function_app.main[0].name : azurerm_windows_function_app.main[0].name
}

output "function_app_default_hostname" {
  description = "The default hostname of the Function App"
  value       = var.function_app_os_type == "Linux" ? azurerm_linux_function_app.main[0].default_hostname : azurerm_windows_function_app.main[0].default_hostname
}

output "function_app_url" {
  description = "The URL of the Function App"
  value       = "https://${var.function_app_os_type == "Linux" ? azurerm_linux_function_app.main[0].default_hostname : azurerm_windows_function_app.main[0].default_hostname}"
}

output "function_app_id" {
  description = "The ID of the Function App"
  value       = var.function_app_os_type == "Linux" ? azurerm_linux_function_app.main[0].id : azurerm_windows_function_app.main[0].id
}

output "function_app_identity" {
  description = "The managed identity information of the Function App"
  value = var.enable_managed_identity ? {
    type         = "SystemAssigned"
    principal_id = var.function_app_os_type == "Linux" ? azurerm_linux_function_app.main[0].identity[0].principal_id : azurerm_windows_function_app.main[0].identity[0].principal_id
    tenant_id    = var.function_app_os_type == "Linux" ? azurerm_linux_function_app.main[0].identity[0].tenant_id : azurerm_windows_function_app.main[0].identity[0].tenant_id
  } : null
}

# App Service Plan Information
output "app_service_plan_name" {
  description = "The name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "The ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

# Application Insights Information (conditional)
output "application_insights_name" {
  description = "The name of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_connection_string" {
  description = "The connection string for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "The application ID for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].app_id : null
}

# API Endpoints for Integration
output "api_endpoints" {
  description = "API endpoints for the learning assessment system"
  value = {
    base_url              = "https://${var.function_app_os_type == "Linux" ? azurerm_linux_function_app.main[0].default_hostname : azurerm_windows_function_app.main[0].default_hostname}"
    assessments_endpoint  = "https://${var.function_app_os_type == "Linux" ? azurerm_linux_function_app.main[0].default_hostname : azurerm_windows_function_app.main[0].default_hostname}/api/assessments"
    document_upload_url   = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.documents.name}"
  }
}

# Resource Configuration Summary
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    resource_group        = azurerm_resource_group.main.name
    location             = azurerm_resource_group.main.location
    storage_account      = azurerm_storage_account.main.name
    document_intelligence = azurerm_cognitive_account.document_intelligence.name
    openai_account       = azurerm_cognitive_account.openai.name
    cosmosdb_account     = azurerm_cosmosdb_account.main.name
    function_app         = var.function_app_os_type == "Linux" ? azurerm_linux_function_app.main[0].name : azurerm_windows_function_app.main[0].name
    app_insights         = var.enable_application_insights ? azurerm_application_insights.main[0].name : "disabled"
  }
}

# Cost Estimation Information
output "cost_estimation_info" {
  description = "Information for cost estimation and monitoring"
  value = {
    consumption_plan        = "Y1 (Consumption)"
    storage_tier           = var.storage_account_tier
    storage_replication    = var.storage_replication_type
    document_intelligence_sku = var.document_intelligence_sku
    openai_sku            = var.openai_sku
    openai_capacity       = var.openai_deployment_capacity
    cosmosdb_mode         = "Serverless"
    estimated_monthly_cost = "$15-25 for development/testing usage"
  }
}

# Security Configuration Summary
output "security_configuration" {
  description = "Summary of security configurations applied"
  value = {
    https_only            = var.enable_https_only
    minimum_tls_version   = var.minimum_tls_version
    managed_identity      = var.enable_managed_identity
    public_network_access = var.enable_public_network_access
    storage_encryption    = "AES-256 (Azure default)"
    cosmosdb_encryption   = "AES-256 (Azure default)"
    key_management        = "Azure-managed keys"
  }
}

# Deployment Verification Information
output "deployment_verification" {
  description = "Commands and URLs for verifying the deployment"
  value = {
    storage_check_command = "az storage blob list --container-name ${azurerm_storage_container.documents.name} --account-name ${azurerm_storage_account.main.name}"
    function_app_health   = "https://${var.function_app_os_type == "Linux" ? azurerm_linux_function_app.main[0].default_hostname : azurerm_windows_function_app.main[0].default_hostname}/api/health"
    cosmos_check_command  = "az cosmosdb database show --account-name ${azurerm_cosmosdb_account.main.name} --name ${azurerm_cosmosdb_sql_database.main.name} --resource-group ${azurerm_resource_group.main.name}"
  }
}

# Environment Variables for Local Development
output "local_development_env_vars" {
  description = "Environment variables for local development and testing"
  value = {
    DOC_INTEL_ENDPOINT = azurerm_cognitive_account.document_intelligence.endpoint
    OPENAI_ENDPOINT    = azurerm_cognitive_account.openai.endpoint
    COSMOS_ENDPOINT    = azurerm_cosmosdb_account.main.endpoint
    COSMOS_DATABASE    = azurerm_cosmosdb_sql_database.main.name
    STORAGE_ACCOUNT    = azurerm_storage_account.main.name
    CONTAINER_NAME     = azurerm_storage_container.documents.name
  }
  sensitive = false
}

# Next Steps Information
output "next_steps" {
  description = "Next steps for completing the deployment"
  value = {
    "1" = "Upload the Function App code to ${var.function_app_os_type == "Linux" ? azurerm_linux_function_app.main[0].name : azurerm_windows_function_app.main[0].name}"
    "2" = "Test document upload to the storage container: ${azurerm_storage_container.documents.name}"
    "3" = "Verify Function App triggers are working by checking Application Insights"
    "4" = "Test the assessments API endpoint for retrieving generated questions"
    "5" = "Configure any additional security policies or network restrictions as needed"
  }
}