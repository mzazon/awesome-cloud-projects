# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_connection_string" {
  description = "Primary connection string of the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

# Storage Container Outputs
output "audio_input_container_name" {
  description = "Name of the audio input container"
  value       = azurerm_storage_container.audio_input.name
}

output "content_output_container_name" {
  description = "Name of the content output container"
  value       = azurerm_storage_container.content_output.name
}

output "audio_input_container_url" {
  description = "URL of the audio input container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.audio_input.name}"
}

output "content_output_container_url" {
  description = "URL of the content output container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.content_output.name}"
}

# Cognitive Services Outputs

# Speech Service
output "speech_service_name" {
  description = "Name of the Speech service"
  value       = azurerm_cognitive_account.speech.name
}

output "speech_service_endpoint" {
  description = "Endpoint of the Speech service"
  value       = azurerm_cognitive_account.speech.endpoint
}

output "speech_service_region" {
  description = "Region of the Speech service"
  value       = azurerm_cognitive_account.speech.location
}

output "speech_service_key" {
  description = "Primary key of the Speech service"
  value       = azurerm_cognitive_account.speech.primary_access_key
  sensitive   = true
}

output "speech_service_id" {
  description = "ID of the Speech service"
  value       = azurerm_cognitive_account.speech.id
}

# OpenAI Service
output "openai_service_name" {
  description = "Name of the OpenAI service"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_service_endpoint" {
  description = "Endpoint of the OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_service_key" {
  description = "Primary key of the OpenAI service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_service_id" {
  description = "ID of the OpenAI service"
  value       = azurerm_cognitive_account.openai.id
}

output "openai_deployments" {
  description = "Information about OpenAI model deployments"
  value = {
    for deployment_name, deployment in azurerm_cognitive_deployment.openai_models : deployment_name => {
      id           = deployment.id
      name         = deployment.name
      model_name   = deployment.model[0].name
      model_version = deployment.model[0].version
      scale_type   = deployment.scale[0].type
      scale_capacity = deployment.scale[0].capacity
    }
  }
}

# Translator Service
output "translator_service_name" {
  description = "Name of the Translator service"
  value       = azurerm_cognitive_account.translator.name
}

output "translator_service_endpoint" {
  description = "Endpoint of the Translator service"
  value       = azurerm_cognitive_account.translator.endpoint
}

output "translator_service_key" {
  description = "Primary key of the Translator service"
  value       = azurerm_cognitive_account.translator.primary_access_key
  sensitive   = true
}

output "translator_service_region" {
  description = "Region of the Translator service"
  value       = azurerm_cognitive_account.translator.location
}

output "translator_service_id" {
  description = "ID of the Translator service"
  value       = azurerm_cognitive_account.translator.id
}

# Azure Functions Outputs
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_identity_tenant_id" {
  description = "Tenant ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].tenant_id
}

output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

# Application Insights Outputs (conditional)
output "application_insights_name" {
  description = "Name of Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key of Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string of Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "App ID of Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].app_id : null
}

# Log Analytics Workspace Outputs (conditional)
output "log_analytics_workspace_name" {
  description = "Name of Log Analytics Workspace (if enabled)"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of Log Analytics Workspace (if enabled)"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of Log Analytics Workspace (if enabled)"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

# Key Vault Outputs
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Configuration Outputs for Applications
output "target_languages" {
  description = "List of configured target languages"
  value       = var.target_languages
}

output "target_languages_string" {
  description = "Comma-separated string of target languages"
  value       = local.target_languages_string
}

# Resource URLs for quick access
output "azure_portal_urls" {
  description = "Azure Portal URLs for quick access to resources"
  value = {
    resource_group    = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_resource_group.main.id}"
    storage_account   = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_storage_account.main.id}"
    function_app      = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_linux_function_app.main.id}"
    speech_service    = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_cognitive_account.speech.id}"
    openai_service    = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_cognitive_account.openai.id}"
    translator_service = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_cognitive_account.translator.id}"
    key_vault         = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_key_vault.main.id}"
  }
}

# Summary Output
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group_name     = azurerm_resource_group.main.name
    location               = azurerm_resource_group.main.location
    storage_account_name   = azurerm_storage_account.main.name
    function_app_name      = azurerm_linux_function_app.main.name
    function_app_url       = "https://${azurerm_linux_function_app.main.default_hostname}"
    speech_service_name    = azurerm_cognitive_account.speech.name
    openai_service_name    = azurerm_cognitive_account.openai.name
    translator_service_name = azurerm_cognitive_account.translator.name
    key_vault_name         = azurerm_key_vault.main.name
    monitoring_enabled     = var.enable_application_insights
    target_languages       = var.target_languages
    environment           = var.environment
    project_name          = var.project_name
  }
}

# Environment Variables for Local Development
output "environment_variables" {
  description = "Environment variables for local development and testing"
  value = {
    AZURE_RESOURCE_GROUP    = azurerm_resource_group.main.name
    AZURE_LOCATION         = azurerm_resource_group.main.location
    STORAGE_ACCOUNT_NAME   = azurerm_storage_account.main.name
    SPEECH_SERVICE_NAME    = azurerm_cognitive_account.speech.name
    SPEECH_ENDPOINT        = azurerm_cognitive_account.speech.endpoint
    SPEECH_REGION          = azurerm_cognitive_account.speech.location
    OPENAI_SERVICE_NAME    = azurerm_cognitive_account.openai.name
    OPENAI_ENDPOINT        = azurerm_cognitive_account.openai.endpoint
    TRANSLATOR_SERVICE_NAME = azurerm_cognitive_account.translator.name
    TRANSLATOR_ENDPOINT    = azurerm_cognitive_account.translator.endpoint
    TRANSLATOR_REGION      = azurerm_cognitive_account.translator.location
    FUNCTION_APP_NAME      = azurerm_linux_function_app.main.name
    KEY_VAULT_NAME         = azurerm_key_vault.main.name
    KEY_VAULT_URI          = azurerm_key_vault.main.vault_uri
    TARGET_LANGUAGES       = local.target_languages_string
  }
  sensitive = false
}

# CLI Commands for Post-Deployment Actions
output "post_deployment_commands" {
  description = "Useful CLI commands for post-deployment actions"
  value = {
    upload_test_audio = "az storage blob upload --account-name ${azurerm_storage_account.main.name} --container-name ${azurerm_storage_container.audio_input.name} --name test-audio.wav --file ./test-audio.wav"
    list_processed_content = "az storage blob list --account-name ${azurerm_storage_account.main.name} --container-name ${azurerm_storage_container.content_output.name} --output table"
    view_function_logs = "az functionapp log tail --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
    test_speech_service = "curl -X POST '${azurerm_cognitive_account.speech.endpoint}speech/recognition/conversation/cognitiveservices/v1?language=en-US' -H 'Ocp-Apim-Subscription-Key: ${azurerm_cognitive_account.speech.primary_access_key}' -H 'Content-Type: audio/wav'"
  }
}