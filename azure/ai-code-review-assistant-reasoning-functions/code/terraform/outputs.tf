# Outputs for AI Code Review Assistant with Reasoning and Functions
# This file defines outputs that provide important information after deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the created storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob service endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "code_files_container_name" {
  description = "Name of the blob container for code files"
  value       = azurerm_storage_container.code_files.name
}

output "review_reports_container_name" {
  description = "Name of the blob container for review reports"
  value       = azurerm_storage_container.review_reports.name
}

# Azure OpenAI Service Information
output "openai_service_name" {
  description = "Name of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_service_endpoint" {
  description = "Endpoint URL for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_service_primary_key" {
  description = "Primary access key for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_deployment_name" {
  description = "Name of the o1-mini model deployment"
  value       = azurerm_cognitive_deployment.o1_mini.name
}

output "openai_model_version" {
  description = "Version of the deployed o1-mini model"
  value       = azurerm_cognitive_deployment.o1_mini.model[0].version
}

# Function App Information
output "function_app_name" {
  description = "Name of the created Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_url" {
  description = "Default hostname of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's system-assigned managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_tenant_id" {
  description = "Tenant ID of the Function App's system-assigned managed identity"
  value       = azurerm_linux_function_app.main.identity[0].tenant_id
}

# API Endpoints
output "code_review_api_endpoint" {
  description = "HTTP endpoint for the code review API"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/review-code"
}

output "report_retrieval_api_endpoint" {
  description = "HTTP endpoint for the report retrieval API"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/get-report"
}

# Service Plan Information
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
  description = "Instrumentation key for Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# Testing and Validation Information
output "sample_curl_command" {
  description = "Sample curl command to test the code review API"
  value = <<-EOT
    # Get Function App master key first:
    az functionapp keys list --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name} --query functionKeys.default --output tsv
    
    # Then use the key in this curl command:
    curl -X POST "https://${azurerm_linux_function_app.main.default_hostname}/api/review-code?code=<FUNCTION_KEY>" \
      -H "Content-Type: application/json" \
      -d '{
        "filename": "sample.py",
        "code_content": "def hello_world():\n    print(\"Hello, World!\")\n\nhello_world()"
      }'
  EOT
}

# Resource Identifiers
output "random_suffix" {
  description = "Random suffix used in resource names"
  value       = random_string.suffix.result
}

output "subscription_id" {
  description = "Azure subscription ID where resources are deployed"
  value       = data.azurerm_client_config.current.subscription_id
}

output "tenant_id" {
  description = "Azure tenant ID where resources are deployed"
  value       = data.azurerm_client_config.current.tenant_id
}

# Cost and Resource Management
output "deployed_resources_summary" {
  description = "Summary of all deployed resources for cost tracking"
  value = {
    resource_group    = azurerm_resource_group.main.name
    storage_account   = azurerm_storage_account.main.name
    openai_service    = azurerm_cognitive_account.openai.name
    function_app      = azurerm_linux_function_app.main.name
    service_plan      = azurerm_service_plan.main.name
    app_insights      = var.enable_application_insights ? azurerm_application_insights.main[0].name : "disabled"
    total_containers  = 2
    model_deployments = 1
  }
}

# Security and Access Information
output "managed_identity_info" {
  description = "Information about the Function App's managed identity and role assignments"
  value = {
    principal_id      = azurerm_linux_function_app.main.identity[0].principal_id
    storage_role      = "Storage Blob Data Contributor"
    openai_role       = "Cognitive Services OpenAI User"
    identity_type     = "SystemAssigned"
  }
}

# Deployment Validation
output "deployment_verification_commands" {
  description = "Commands to verify the deployment is working correctly"
  value = <<-EOT
    # Verify storage containers
    az storage container list --account-name ${azurerm_storage_account.main.name} --output table
    
    # Verify OpenAI deployment
    az cognitiveservices account deployment list --name ${azurerm_cognitive_account.openai.name} --resource-group ${azurerm_resource_group.main.name} --output table
    
    # Verify Function App status
    az functionapp show --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name} --query state --output tsv
    
    # Test Function App endpoint
    az functionapp function show --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name} --function-name review-code
  EOT
}