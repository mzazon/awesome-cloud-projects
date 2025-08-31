# Outputs for Azure Tutorial Generator Infrastructure
# These outputs provide essential information for accessing and managing the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all tutorial generator resources"
  value       = azurerm_resource_group.tutorial_generator.name
}

output "resource_group_location" {
  description = "Azure region where the resources are deployed"
  value       = azurerm_resource_group.tutorial_generator.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for tutorial content"
  value       = azurerm_storage_account.tutorial_storage.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.tutorial_storage.primary_blob_endpoint
}

output "storage_account_primary_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.tutorial_storage.primary_access_key
  sensitive   = true
}

output "tutorials_container_url" {
  description = "URL for the tutorials container (publicly accessible content)"
  value       = "${azurerm_storage_account.tutorial_storage.primary_blob_endpoint}${azurerm_storage_container.tutorials.name}"
}

output "metadata_container_url" {
  description = "URL for the metadata container (private content)"
  value       = "${azurerm_storage_account.tutorial_storage.primary_blob_endpoint}${azurerm_storage_container.metadata.name}"
}

# Azure OpenAI Information
output "openai_account_name" {
  description = "Name of the Azure OpenAI service account"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_endpoint" {
  description = "Endpoint URL for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_primary_key" {
  description = "Primary access key for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_model_deployment_name" {
  description = "Name of the deployed GPT model"
  value       = azurerm_cognitive_deployment.gpt_model.name
}

output "openai_model_version" {
  description = "Version of the deployed GPT model"
  value       = azurerm_cognitive_deployment.gpt_model.model[0].version
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.tutorial_generator.name
}

output "function_app_url" {
  description = "Default hostname/URL of the Function App"
  value       = "https://${azurerm_linux_function_app.tutorial_generator.default_hostname}"
}

output "function_app_id" {
  description = "Resource ID of the Function App"
  value       = azurerm_linux_function_app.tutorial_generator.id
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.tutorial_generator.identity[0].principal_id
}

# API Endpoints
output "tutorial_generation_endpoint" {
  description = "API endpoint for generating new tutorials"
  value       = "https://${azurerm_linux_function_app.tutorial_generator.default_hostname}/api/generate"
}

output "tutorial_retrieval_endpoint" {
  description = "API endpoint for retrieving tutorials (append tutorial ID)"
  value       = "https://${azurerm_linux_function_app.tutorial_generator.default_hostname}/api/tutorial/{tutorial_id}"
}

# Service Plan Information
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.tutorial_plan.name
}

output "service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.tutorial_plan.sku_name
}

# Application Insights Information (conditional)
output "application_insights_name" {
  description = "Name of the Application Insights instance (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.tutorial_insights[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.tutorial_insights[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.tutorial_insights[0].connection_string : null
  sensitive   = true
}

# Resource Configuration Summary
output "deployment_summary" {
  description = "Summary of deployed resources and their configuration"
  value = {
    resource_group    = azurerm_resource_group.tutorial_generator.name
    location          = azurerm_resource_group.tutorial_generator.location
    storage_account   = azurerm_storage_account.tutorial_storage.name
    openai_service    = azurerm_cognitive_account.openai.name
    function_app      = azurerm_linux_function_app.tutorial_generator.name
    model_deployment  = azurerm_cognitive_deployment.gpt_model.name
    python_version    = var.python_version
    function_runtime  = var.function_runtime_version
    environment       = var.environment
    created_by        = "Terraform"
  }
}

# Testing and Validation Commands
output "testing_commands" {
  description = "Commands for testing the deployed infrastructure"
  value = {
    test_function_app = "curl -X GET https://${azurerm_linux_function_app.tutorial_generator.default_hostname}/api/health"
    generate_tutorial = "curl -X POST https://${azurerm_linux_function_app.tutorial_generator.default_hostname}/api/generate -H 'Content-Type: application/json' -d '{\"topic\":\"Python Functions\",\"difficulty\":\"beginner\",\"language\":\"python\"}'"
    list_tutorials = "az storage blob list --container-name tutorials --account-name ${azurerm_storage_account.tutorial_storage.name} --output table"
    check_openai = "az cognitiveservices account show --name ${azurerm_cognitive_account.openai.name} --resource-group ${azurerm_resource_group.tutorial_generator.name}"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    note = "Costs depend on usage patterns and selected SKUs"
    storage_account = "~$1-5/month (depends on storage usage)"
    openai_service = "Pay-per-token (varies by usage, typically $10-50/month for development)"
    function_app_consumption = "$0 for first 1M executions, then ~$0.20 per million executions"
    function_app_premium = var.function_app_service_plan_sku != "Y1" ? "~$50-200/month depending on SKU" : "N/A"
    application_insights = var.enable_application_insights ? "~$2-10/month for basic telemetry" : "N/A"
    total_estimated = "~$15-25/month for moderate usage with Consumption plan"
  }
}

# Security and Access Information
output "security_configuration" {
  description = "Security settings and access control information"
  value = {
    storage_public_access = var.enable_public_access
    function_cors_origins = var.cors_allowed_origins
    openai_network_access = "Public (with API key authentication)"
    managed_identity_enabled = "Yes (for Function App)"
    rbac_assignments = "Function App has Cognitive Services OpenAI User and Storage Blob Data Contributor roles"
  }
}