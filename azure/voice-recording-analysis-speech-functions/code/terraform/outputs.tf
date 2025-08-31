# Azure Voice Recording Analysis - Output Values
# This file defines the output values that will be displayed after deployment

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.voice_storage.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.voice_storage.primary_blob_endpoint
}

output "storage_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.voice_storage.primary_connection_string
  sensitive   = true
}

output "audio_input_container_name" {
  description = "Name of the audio input container"
  value       = azurerm_storage_container.audio_input.name
}

output "transcripts_container_name" {
  description = "Name of the transcripts output container"
  value       = azurerm_storage_container.transcripts.name
}

output "speech_service_name" {
  description = "Name of the Azure AI Speech service"
  value       = azurerm_cognitive_account.speech_service.name
}

output "speech_service_endpoint" {
  description = "Endpoint URL for the Azure AI Speech service"
  value       = azurerm_cognitive_account.speech_service.endpoint
}

output "speech_service_region" {
  description = "Region of the Azure AI Speech service"
  value       = azurerm_cognitive_account.speech_service.location
}

output "speech_service_key" {
  description = "Primary access key for the Azure AI Speech service"
  value       = azurerm_cognitive_account.speech_service.primary_access_key
  sensitive   = true
}

output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.voice_processor.name
}

output "function_app_hostname" {
  description = "Hostname of the Azure Function App"
  value       = azurerm_linux_function_app.voice_processor.default_hostname
}

output "function_app_url" {
  description = "HTTPS URL of the Azure Function App"
  value       = "https://${azurerm_linux_function_app.voice_processor.default_hostname}"
}

output "function_app_id" {
  description = "Resource ID of the Azure Function App"
  value       = azurerm_linux_function_app.voice_processor.id
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.voice_processor.identity[0].principal_id
}

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

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace (if Application Insights is enabled)"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].id : null
}

output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.function_plan.name
}

output "service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.function_plan.sku_name
}

# Deployment Summary Information
output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    resource_group = {
      name     = azurerm_resource_group.main.name
      location = azurerm_resource_group.main.location
      purpose  = "Container for all voice analysis resources"
    }
    storage_account = {
      name    = azurerm_storage_account.voice_storage.name
      purpose = "Stores audio input files and transcript outputs"
      containers = {
        audio_input = azurerm_storage_container.audio_input.name
        transcripts = azurerm_storage_container.transcripts.name
      }
    }
    speech_service = {
      name     = azurerm_cognitive_account.speech_service.name
      endpoint = azurerm_cognitive_account.speech_service.endpoint
      purpose  = "Provides AI-powered speech-to-text transcription"
    }
    function_app = {
      name     = azurerm_linux_function_app.voice_processor.name
      url      = "https://${azurerm_linux_function_app.voice_processor.default_hostname}"
      purpose  = "Processes audio files and orchestrates transcription workflow"
    }
    monitoring = {
      application_insights = var.enable_application_insights ? azurerm_application_insights.main[0].name : "Not enabled"
      log_analytics       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].name : "Not enabled"
      purpose            = "Provides monitoring and logging for the solution"
    }
  }
}

# Environment Variables for Local Testing
output "environment_variables" {
  description = "Environment variables for local development and testing"
  value = {
    SPEECH_KEY              = "Use 'terraform output -raw speech_service_key'"
    SPEECH_REGION          = azurerm_cognitive_account.speech_service.location
    SPEECH_ENDPOINT        = azurerm_cognitive_account.speech_service.endpoint
    STORAGE_CONNECTION     = "Use 'terraform output -raw storage_connection_string'"
    STORAGE_ACCOUNT_NAME   = azurerm_storage_account.voice_storage.name
    FUNCTIONS_WORKER_RUNTIME = "python"
  }
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the deployed voice analysis solution"
  value = {
    step_1 = "Upload audio files to the '${azurerm_storage_container.audio_input.name}' container in storage account '${azurerm_storage_account.voice_storage.name}'"
    step_2 = "Call the Function App at: https://${azurerm_linux_function_app.voice_processor.default_hostname}/api/transcribe"
    step_3 = "Include filename in POST request body: {\"filename\": \"your-audio.wav\", \"language\": \"en-US\"}"
    step_4 = "Download transcription results from the '${azurerm_storage_container.transcripts.name}' container"
    note   = "Function requires authentication. Use function keys or configure authentication in production."
  }
}

# Security Considerations
output "security_notes" {
  description = "Important security considerations for the deployed solution"
  value = {
    authentication = "Function App currently allows anonymous access. Configure authentication for production use."
    network_access = "All services allow public access. Consider VNet integration and private endpoints for production."
    key_management = "Service keys are managed by Azure. Consider using Azure Key Vault for additional security."
    data_encryption = "Data is encrypted at rest and in transit using Azure's built-in encryption."
    managed_identity = "Function App uses system-assigned managed identity for secure access to Azure services."
  }
}

# Cost Optimization Tips
output "cost_optimization" {
  description = "Tips for optimizing costs in the voice analysis solution"
  value = {
    speech_service = "Using ${var.speech_service_sku} tier. Consider F0 (free) for development, S0 for production."
    function_app   = "Using ${var.function_app_service_plan_sku} hosting plan. Consumption plan charges only for execution time."
    storage        = "Using ${var.storage_account_tier}_${var.storage_replication_type}. Consider lifecycle policies for long-term data."
    monitoring     = var.enable_application_insights ? "Application Insights enabled. Monitor data ingestion costs." : "Application Insights disabled to reduce costs."
    recommendation = "Monitor usage patterns and adjust service tiers based on actual demand."
  }
}