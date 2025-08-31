# Output values for AI-powered email marketing solution
# This file defines the output values that will be displayed after terraform apply

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.marketing.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.marketing.location
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

output "openai_deployment_name" {
  description = "Name of the GPT-4o model deployment"
  value       = azurerm_cognitive_deployment.gpt4o.name
}

output "openai_model_info" {
  description = "Information about the deployed OpenAI model"
  value = {
    name     = azurerm_cognitive_deployment.gpt4o.model[0].name
    version  = azurerm_cognitive_deployment.gpt4o.model[0].version
    capacity = azurerm_cognitive_deployment.gpt4o.sku[0].capacity
  }
}

# Function App (Logic Apps Standard) Outputs
output "function_app_name" {
  description = "Name of the Function App hosting Logic Apps workflows"
  value       = azurerm_linux_function_app.marketing.name
}

output "function_app_url" {
  description = "Default hostname of the Function App"
  value       = "https://${azurerm_linux_function_app.marketing.default_hostname}"
}

output "function_app_identity" {
  description = "Managed identity information for the Function App"
  value = var.enable_managed_identity ? {
    principal_id = azurerm_linux_function_app.marketing.identity[0].principal_id
    tenant_id    = azurerm_linux_function_app.marketing.identity[0].tenant_id
  } : null
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account for Function App runtime"
  value       = azurerm_storage_account.marketing.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.marketing.primary_blob_endpoint
}

# Communication Services Outputs
output "communication_service_name" {
  description = "Name of the Azure Communication Services resource"
  value       = azurerm_communication_service.marketing.name
}

output "email_service_name" {
  description = "Name of the Email Communication Services resource"
  value       = azurerm_email_communication_service.marketing.name
}

output "sender_email_address" {
  description = "Sender email address for marketing campaigns"
  value       = local.sender_email_address
}

output "email_domain_info" {
  description = "Information about the configured email domain"
  value = {
    domain_name            = azurerm_email_communication_service_domain.marketing.name
    domain_management      = azurerm_email_communication_service_domain.marketing.domain_management
    from_sender_domain     = azurerm_email_communication_service_domain.marketing.from_sender_domain
    mail_from_sender_domain = azurerm_email_communication_service_domain.marketing.mail_from_sender_domain
  }
}

# Key Vault Outputs (if enabled)
output "key_vault_name" {
  description = "Name of the Key Vault for secure secret storage"
  value       = var.enable_managed_identity ? azurerm_key_vault.marketing[0].name : null
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = var.enable_managed_identity ? azurerm_key_vault.marketing[0].vault_uri : null
}

# Application Insights Outputs (if enabled)
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.marketing[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.marketing[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.marketing[0].connection_string : null
  sensitive   = true
}

# Monitoring Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.marketing[0].name : null
}

output "action_group_name" {
  description = "Name of the Monitor Action Group for alerts"
  value       = var.enable_application_insights ? azurerm_monitor_action_group.marketing[0].name : null
}

# Configuration and Testing Information
output "ai_configuration" {
  description = "AI content generation configuration parameters"
  value = {
    max_tokens      = var.ai_max_tokens
    temperature     = var.ai_temperature
    model_name      = var.openai_model_name
    model_version   = var.openai_model_version
  }
}

output "workflow_configuration" {
  description = "Workflow scheduling configuration"
  value = {
    frequency      = var.workflow_schedule_frequency
    interval       = var.workflow_schedule_interval
    start_time     = var.workflow_start_time
  }
}

output "test_configuration" {
  description = "Testing configuration information"
  value = {
    test_email_recipient = var.test_email_recipient
    sender_email        = local.sender_email_address
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of the deployed AI email marketing solution"
  value = {
    resource_group          = azurerm_resource_group.marketing.name
    location               = azurerm_resource_group.marketing.location
    openai_service         = azurerm_cognitive_account.openai.name
    openai_endpoint        = azurerm_cognitive_account.openai.endpoint
    function_app           = azurerm_linux_function_app.marketing.name
    function_app_url       = "https://${azurerm_linux_function_app.marketing.default_hostname}"
    communication_service  = azurerm_communication_service.marketing.name
    email_service         = azurerm_email_communication_service.marketing.name
    sender_email          = local.sender_email_address
    storage_account       = azurerm_storage_account.marketing.name
    managed_identity_enabled = var.enable_managed_identity
    monitoring_enabled    = var.enable_application_insights
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps for completing the email marketing solution setup"
  value = {
    step_1 = "Deploy your Logic Apps workflow definition to the Function App"
    step_2 = "Configure your customer database connection in the workflow"
    step_3 = "Test the AI content generation with sample prompts"
    step_4 = "Set up email recipient lists for your marketing campaigns"
    step_5 = "Monitor the solution using Application Insights dashboards"
    step_6 = "Scale the OpenAI deployment capacity based on usage patterns"
  }
}

# Connection Information for Manual Testing
output "testing_endpoints" {
  description = "Endpoints and information for manual testing"
  value = {
    openai_test_url = "${azurerm_cognitive_account.openai.endpoint}openai/deployments/${azurerm_cognitive_deployment.gpt4o.name}/chat/completions?api-version=2024-08-01-preview"
    function_app_scm_url = "https://${azurerm_linux_function_app.marketing.name}.scm.azurewebsites.net"
    storage_account_url = azurerm_storage_account.marketing.primary_web_endpoint
  }
}

# Security Information
output "security_notes" {
  description = "Important security considerations for the deployed solution"
  value = {
    managed_identity = var.enable_managed_identity ? "Enabled - Function App uses managed identity for secure access" : "Disabled - Using connection strings in app settings"
    key_vault       = var.enable_managed_identity ? "Secrets stored in Key Vault" : "Secrets stored in Function App settings"
    storage_security = "Storage account configured with HTTPS-only and minimum TLS 1.2"
    openai_access   = "OpenAI service configured with public network access enabled"
    monitoring      = var.enable_application_insights ? "Application Insights enabled for monitoring" : "No monitoring configured"
  }
}

# Cost Estimation Information
output "cost_considerations" {
  description = "Cost considerations for the deployed resources"
  value = {
    openai_pricing      = "Pay-per-token usage with ${var.openai_deployment_capacity} tokens/minute capacity"
    function_app_tier   = "Running on ${var.function_app_service_plan_sku} pricing tier"
    storage_tier        = "${var.storage_account_tier} ${var.storage_account_replication_type} storage"
    communication_cost  = "Pay-per-email sent through Communication Services"
    monitoring_cost     = var.enable_application_insights ? "Application Insights data ingestion charges apply" : "No monitoring costs"
  }
}