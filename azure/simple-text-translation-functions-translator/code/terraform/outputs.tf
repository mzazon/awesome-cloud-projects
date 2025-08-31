# ==============================================================================
# Simple Text Translation with Functions and Translator - Outputs
# ==============================================================================
# Output values that provide important information about the deployed resources.
# These outputs can be used for verification, integration with other systems,
# or accessing the deployed services.

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.translation.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.translation.location
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.translation.id
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.translation_app.name
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.translation_app.id
}

output "function_app_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.translation_app.default_hostname
}

output "function_app_url" {
  description = "Base URL of the Function App"
  value       = "https://${azurerm_linux_function_app.translation_app.default_hostname}"
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.translation_app.identity[0].principal_id
}

output "function_app_tenant_id" {
  description = "Tenant ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.translation_app.identity[0].tenant_id
}

# Function App Keys (sensitive)
output "function_app_master_key" {
  description = "Master key for the Function App (use with caution)"
  value       = azurerm_linux_function_app.translation_app.site_credential[0].password
  sensitive   = true
}

output "function_app_publish_username" {
  description = "Publishing username for the Function App"
  value       = azurerm_linux_function_app.translation_app.site_credential[0].name
  sensitive   = true
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account used by the Function App"
  value       = azurerm_storage_account.function_storage.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.function_storage.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.function_storage.primary_blob_endpoint
}

# Azure AI Translator Information
output "translator_service_name" {
  description = "Name of the Azure AI Translator service"
  value       = azurerm_cognitive_account.translator.name
}

output "translator_service_id" {
  description = "ID of the Azure AI Translator service"
  value       = azurerm_cognitive_account.translator.id
}

output "translator_endpoint" {
  description = "Endpoint URL for the Azure AI Translator service"
  value       = azurerm_cognitive_account.translator.endpoint
}

output "translator_primary_key" {
  description = "Primary access key for the Azure AI Translator service"
  value       = azurerm_cognitive_account.translator.primary_access_key
  sensitive   = true
}

output "translator_secondary_key" {
  description = "Secondary access key for the Azure AI Translator service"
  value       = azurerm_cognitive_account.translator.secondary_access_key
  sensitive   = true
}

output "translator_sku" {
  description = "SKU tier of the Azure AI Translator service"
  value       = azurerm_cognitive_account.translator.sku_name
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.translation_insights.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.translation_insights.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.translation_insights.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.translation_insights.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = azurerm_application_insights.translation_insights.app_id
}

# Service Plan Information
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.translation_plan.name
}

output "service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.translation_plan.id
}

output "service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.translation_plan.sku_name
}

# Staging Slot Information (if enabled)
output "staging_slot_name" {
  description = "Name of the staging slot (if enabled)"
  value       = var.enable_staging_slot ? azurerm_linux_function_app_slot.staging[0].name : null
}

output "staging_slot_hostname" {
  description = "Hostname of the staging slot (if enabled)"
  value       = var.enable_staging_slot ? azurerm_linux_function_app_slot.staging[0].default_hostname : null
}

output "staging_slot_url" {
  description = "URL of the staging slot (if enabled)"
  value       = var.enable_staging_slot ? "https://${azurerm_linux_function_app_slot.staging[0].default_hostname}" : null
}

# API Configuration Information
output "translation_api_endpoint" {
  description = "Complete API endpoint for the translation function"
  value       = "https://${azurerm_linux_function_app.translation_app.default_hostname}/api/translate"
}

output "function_key_url" {
  description = "Instructions for retrieving function keys"
  value       = "Use 'az functionapp keys list --name ${azurerm_linux_function_app.translation_app.name} --resource-group ${azurerm_resource_group.translation.name}' to get function keys"
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group    = azurerm_resource_group.translation.name
    location         = azurerm_resource_group.translation.location
    function_app     = azurerm_linux_function_app.translation_app.name
    translator_service = azurerm_cognitive_account.translator.name
    storage_account  = azurerm_storage_account.function_storage.name
    app_insights     = azurerm_application_insights.translation_insights.name
    service_plan     = azurerm_service_plan.translation_plan.name
    staging_enabled  = var.enable_staging_slot
  }
}

# Cost and Usage Information
output "cost_information" {
  description = "Cost-related information about the deployment"
  value = {
    function_app_plan = azurerm_service_plan.translation_plan.sku_name
    translator_tier   = azurerm_cognitive_account.translator.sku_name
    storage_tier      = azurerm_storage_account.function_storage.account_tier
    estimated_monthly_cost = azurerm_service_plan.translation_plan.sku_name == "Y1" ? "~$0-20 USD (Consumption plan + F0 Translator)" : "Variable based on plan"
  }
}

# Security Information
output "security_configuration" {
  description = "Security-related configuration information"
  value = {
    managed_identity_enabled = "Yes"
    https_only              = "Yes"
    min_tls_version         = azurerm_storage_account.function_storage.min_tls_version
    cors_origins           = var.cors_allowed_origins
    auth_level             = "function"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Deploy function code using Azure CLI or Azure DevOps",
    "2. Retrieve function keys for API access",
    "3. Test the translation API endpoint",
    "4. Configure monitoring alerts in Application Insights",
    "5. Set up CI/CD pipeline for automated deployments",
    "6. Consider implementing Azure API Management for production"
  ]
}

# Testing Information
output "testing_information" {
  description = "Information for testing the deployed services"
  value = {
    curl_example = "curl -X POST 'https://${azurerm_linux_function_app.translation_app.default_hostname}/api/translate?code=FUNCTION_KEY' -H 'Content-Type: application/json' -d '{\"text\": \"Hello world\", \"to\": \"es\"}'"
    test_payload = {
      text = "Hello, how are you today?"
      to   = "es"
    }
    expected_response = {
      original   = "Hello, how are you today?"
      translated = "Hola, ¿cómo estás hoy?"
      from       = "en"
      to         = "es"
      confidence = 1.0
    }
  }
}