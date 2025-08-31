# Output values for Azure Audio Summarization Infrastructure
# These outputs provide essential information for deployment verification and integration

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account for audio files"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob storage endpoint"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_connection_string" {
  description = "Primary connection string for storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "audio_input_container_name" {
  description = "Name of the container for audio input files"
  value       = azurerm_storage_container.audio_input.name
}

output "audio_output_container_name" {
  description = "Name of the container for processed output files"
  value       = azurerm_storage_container.audio_output.name
}

# Azure OpenAI Service Outputs
output "openai_account_name" {
  description = "Name of the Azure OpenAI cognitive services account"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_endpoint" {
  description = "Endpoint URL for Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_primary_key" {
  description = "Primary access key for Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_secondary_key" {
  description = "Secondary access key for Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.secondary_access_key
  sensitive   = true
}

output "openai_subdomain" {
  description = "Custom subdomain for Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.custom_subdomain_name
}

# Model Deployment Outputs
output "whisper_deployment_name" {
  description = "Name of the deployed Whisper model for transcription"
  value       = azurerm_cognitive_deployment.whisper.name
}

output "gpt_deployment_name" {
  description = "Name of the deployed GPT model for summarization"
  value       = azurerm_cognitive_deployment.gpt.name
}

output "whisper_model_info" {
  description = "Information about the deployed Whisper model"
  value = {
    name     = azurerm_cognitive_deployment.whisper.model[0].name
    version  = azurerm_cognitive_deployment.whisper.model[0].version
    format   = azurerm_cognitive_deployment.whisper.model[0].format
    capacity = azurerm_cognitive_deployment.whisper.scale[0].capacity
  }
}

output "gpt_model_info" {
  description = "Information about the deployed GPT model"
  value = {
    name     = azurerm_cognitive_deployment.gpt.model[0].name
    version  = azurerm_cognitive_deployment.gpt.model[0].version
    format   = azurerm_cognitive_deployment.gpt.model[0].format
    capacity = azurerm_cognitive_deployment.gpt.scale[0].capacity
  }
}

# Function App Outputs
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "Full HTTPS URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_identity_tenant_id" {
  description = "Tenant ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].tenant_id
}

# App Service Plan Outputs
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "service_plan_sku" {
  description = "SKU name of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# Application Insights Outputs (conditional)
output "application_insights_name" {
  description = "Name of Application Insights instance (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application Insights application ID (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].app_id : null
}

# Deployment Information
output "deployment_info" {
  description = "Summary of deployment information for reference"
  value = {
    resource_group     = azurerm_resource_group.main.name
    location          = azurerm_resource_group.main.location
    storage_account   = azurerm_storage_account.main.name
    function_app      = azurerm_linux_function_app.main.name
    openai_account    = azurerm_cognitive_account.openai.name
    whisper_model     = azurerm_cognitive_deployment.whisper.name
    gpt_model         = azurerm_cognitive_deployment.gpt.name
    python_version    = var.function_runtime_version
    functions_version = var.functions_extension_version
    deployment_time   = timestamp()
  }
}

# Configuration for CLI commands (helpful for deployment scripts)
output "cli_commands" {
  description = "Useful Azure CLI commands for managing the deployment"
  value = {
    # Storage commands
    upload_audio_file = "az storage blob upload --container-name ${azurerm_storage_container.audio_input.name} --file <local-file> --name <blob-name> --connection-string '<connection-string>'"
    list_output_files = "az storage blob list --container-name ${azurerm_storage_container.audio_output.name} --connection-string '<connection-string>' --output table"
    
    # Function app commands
    view_function_logs = "az webapp log tail --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
    restart_function_app = "az functionapp restart --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
    
    # OpenAI commands
    list_deployments = "az cognitiveservices account deployment list --name ${azurerm_cognitive_account.openai.name} --resource-group ${azurerm_resource_group.main.name}"
    
    # Monitoring commands
    view_metrics = "az monitor metrics list --resource ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name} --resource-type Microsoft.Web/sites --metric FunctionExecutionCount"
  }
}

# Resource URLs for easy access
output "resource_urls" {
  description = "Azure Portal URLs for direct access to resources"
  value = {
    resource_group = "https://portal.azure.com/#@/resource/subscriptions/SUBSCRIPTION_ID/resourceGroups/${azurerm_resource_group.main.name}/overview"
    storage_account = "https://portal.azure.com/#@/resource/subscriptions/SUBSCRIPTION_ID/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Storage/storageAccounts/${azurerm_storage_account.main.name}/overview"
    function_app = "https://portal.azure.com/#@/resource/subscriptions/SUBSCRIPTION_ID/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Web/sites/${azurerm_linux_function_app.main.name}/appServices"
    openai_account = "https://portal.azure.com/#@/resource/subscriptions/SUBSCRIPTION_ID/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.CognitiveServices/accounts/${azurerm_cognitive_account.openai.name}/overview"
  }
}

# Testing and Validation Information
output "testing_information" {
  description = "Information for testing the deployed solution"
  value = {
    instructions = "Upload an audio file to the '${azurerm_storage_container.audio_input.name}' container to trigger processing"
    sample_audio_url = "https://github.com/Azure-Samples/cognitive-services-speech-sdk/raw/master/sampledata/audiofiles/wikipediaOcelot.wav"
    expected_output_location = "Check the '${azurerm_storage_container.audio_output.name}' container for processed results"
    processing_time = "Allow 30-60 seconds for audio processing to complete"
    log_monitoring = "Monitor function execution logs using Azure CLI or Azure Portal"
  }
}