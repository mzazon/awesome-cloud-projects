# Output Values for Azure Accessible AI-Powered Customer Service Bot Infrastructure
# This file defines outputs that provide important information about the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# Bot Service Information
output "bot_service_name" {
  description = "Name of the Azure Bot Service"
  value       = azurerm_bot_service_azure_bot.main.name
}

output "bot_service_endpoint" {
  description = "Endpoint URL for the bot service"
  value       = azurerm_bot_service_azure_bot.main.endpoint
}

output "bot_app_id" {
  description = "Microsoft App ID for the bot"
  value       = azuread_application.bot.application_id
  sensitive   = true
}

output "bot_web_chat_url" {
  description = "Web Chat URL for testing the bot"
  value       = "https://webchat.botframework.com/embed/${azurerm_bot_service_azure_bot.main.name}?s=${azurerm_bot_channel_web_chat.main.site_names[0]}"
}

# App Service Information
output "app_service_name" {
  description = "Name of the App Service hosting the bot"
  value       = local.app_service.name
}

output "app_service_url" {
  description = "URL of the App Service"
  value       = "https://${local.app_service.default_hostname}"
}

output "app_service_hostname" {
  description = "Default hostname of the App Service"
  value       = local.app_service.default_hostname
}

output "app_service_id" {
  description = "ID of the App Service"
  value       = local.app_service.id
}

output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

# Cognitive Services Information
output "immersive_reader_name" {
  description = "Name of the Immersive Reader cognitive service"
  value       = azurerm_cognitive_service.immersive_reader.name
}

output "immersive_reader_endpoint" {
  description = "Endpoint URL for the Immersive Reader service"
  value       = azurerm_cognitive_service.immersive_reader.endpoint
}

output "immersive_reader_key" {
  description = "Primary access key for the Immersive Reader service"
  value       = azurerm_cognitive_service.immersive_reader.primary_access_key
  sensitive   = true
}

output "immersive_reader_subdomain" {
  description = "Custom subdomain for the Immersive Reader service"
  value       = azurerm_cognitive_service.immersive_reader.custom_subdomain_name
}

output "luis_authoring_name" {
  description = "Name of the LUIS authoring service"
  value       = azurerm_cognitive_service.luis_authoring.name
}

output "luis_authoring_endpoint" {
  description = "Endpoint URL for the LUIS authoring service"
  value       = azurerm_cognitive_service.luis_authoring.endpoint
}

output "luis_authoring_key" {
  description = "Primary access key for the LUIS authoring service"
  value       = azurerm_cognitive_service.luis_authoring.primary_access_key
  sensitive   = true
}

output "luis_runtime_name" {
  description = "Name of the LUIS runtime service"
  value       = azurerm_cognitive_service.luis_runtime.name
}

output "luis_runtime_endpoint" {
  description = "Endpoint URL for the LUIS runtime service"
  value       = azurerm_cognitive_service.luis_runtime.endpoint
}

output "luis_runtime_key" {
  description = "Primary access key for the LUIS runtime service"
  value       = azurerm_cognitive_service.luis_runtime.primary_access_key
  sensitive   = true
}

# Key Vault Information
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

output "key_vault_secrets" {
  description = "List of secrets stored in Key Vault"
  value = [
    azurerm_key_vault_secret.immersive_reader_key.name,
    azurerm_key_vault_secret.immersive_reader_endpoint.name,
    azurerm_key_vault_secret.luis_authoring_key.name,
    azurerm_key_vault_secret.luis_authoring_endpoint.name,
    azurerm_key_vault_secret.luis_runtime_key.name,
    azurerm_key_vault_secret.luis_runtime_endpoint.name,
    azurerm_key_vault_secret.storage_connection_string.name,
    azurerm_key_vault_secret.bot_app_id.name,
    azurerm_key_vault_secret.bot_app_password.name
  ]
}

# Storage Account Information
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
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights resource"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights resource"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "App ID for Application Insights"
  value       = azurerm_application_insights.main.app_id
}

# Azure AD Application Information
output "azure_ad_application_id" {
  description = "ID of the Azure AD application for the bot"
  value       = azuread_application.bot.application_id
  sensitive   = true
}

output "azure_ad_application_object_id" {
  description = "Object ID of the Azure AD application for the bot"
  value       = azuread_application.bot.object_id
}

output "azure_ad_service_principal_id" {
  description = "ID of the service principal for the bot"
  value       = azuread_service_principal.bot.id
}

output "azure_ad_service_principal_object_id" {
  description = "Object ID of the service principal for the bot"
  value       = azuread_service_principal.bot.object_id
}

# Network and Security Information
output "app_service_outbound_ip_addresses" {
  description = "Outbound IP addresses of the App Service"
  value       = split(",", local.app_service.outbound_ip_addresses)
}

output "app_service_possible_outbound_ip_addresses" {
  description = "Possible outbound IP addresses of the App Service"
  value       = split(",", local.app_service.possible_outbound_ip_addresses)
}

output "app_service_managed_identity_principal_id" {
  description = "Principal ID of the App Service managed identity"
  value       = local.app_service.identity[0].principal_id
}

output "app_service_managed_identity_tenant_id" {
  description = "Tenant ID of the App Service managed identity"
  value       = local.app_service.identity[0].tenant_id
}

# Configuration Information
output "key_vault_reference_format" {
  description = "Format for Key Vault references in App Service settings"
  value       = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=SECRET_NAME)"
}

output "immersive_reader_sdk_endpoint" {
  description = "Endpoint for Immersive Reader SDK integration"
  value       = "https://${azurerm_cognitive_service.immersive_reader.custom_subdomain_name}.cognitiveservices.azure.com/"
}

# Monitoring Information
output "monitoring_enabled" {
  description = "Whether monitoring and alerts are enabled"
  value       = var.enable_monitoring_alerts
}

output "diagnostic_logs_enabled" {
  description = "Whether diagnostic logs are enabled"
  value       = var.enable_diagnostic_logs
}

output "action_group_id" {
  description = "ID of the monitoring action group (if enabled)"
  value       = var.enable_monitoring_alerts ? azurerm_monitor_action_group.main[0].id : null
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

output "terraform_version" {
  description = "Version of Terraform used for deployment"
  value       = "~> 1.0"
}

output "azurerm_provider_version" {
  description = "Version of AzureRM provider used"
  value       = "~> 3.0"
}

# Resource Tags
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.tags
}

# Quick Start Information
output "quick_start_info" {
  description = "Quick start information for the deployed bot"
  value = {
    bot_name               = azurerm_bot_service_azure_bot.main.name
    web_chat_url          = "https://webchat.botframework.com/embed/${azurerm_bot_service_azure_bot.main.name}"
    app_service_url       = "https://${local.app_service.default_hostname}"
    key_vault_name        = azurerm_key_vault.main.name
    storage_account_name  = azurerm_storage_account.main.name
    resource_group_name   = azurerm_resource_group.main.name
    location             = azurerm_resource_group.main.location
  }
}

# Security Information
output "security_information" {
  description = "Security-related information about the deployment"
  value = {
    key_vault_rbac_enabled        = var.enable_rbac_authorization
    public_network_access_enabled = var.enable_public_network_access
    tls_version                   = "1.2"
    managed_identity_enabled      = true
    soft_delete_enabled           = true
    purge_protection_enabled      = false
  }
}

# Cost Information
output "cost_information" {
  description = "Cost-related information about the deployed resources"
  value = {
    app_service_plan_sku     = var.app_service_plan_sku
    storage_account_tier     = var.storage_account_tier
    cognitive_services_sku   = var.cognitive_services_sku
    luis_authoring_sku       = var.luis_authoring_sku
    key_vault_sku           = var.key_vault_sku
    bot_service_sku         = "F0"
    estimated_monthly_cost  = "Varies based on usage - see Azure pricing calculator"
  }
}

# Next Steps
output "next_steps" {
  description = "Next steps after deployment"
  value = {
    step_1 = "Configure your bot application code and deploy to App Service"
    step_2 = "Create and train LUIS applications for natural language understanding"
    step_3 = "Implement Immersive Reader integration in your bot responses"
    step_4 = "Test the bot using the Web Chat channel"
    step_5 = "Configure additional channels (Teams, Slack, etc.) as needed"
    step_6 = "Set up monitoring and alerting for production use"
  }
}

# Troubleshooting Information
output "troubleshooting" {
  description = "Troubleshooting information"
  value = {
    app_service_logs_location = "https://portal.azure.com/#@/resource${local.app_service.id}/logStream"
    application_insights_url  = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}/overview"
    key_vault_access_url     = "https://portal.azure.com/#@/resource${azurerm_key_vault.main.id}/overview"
    bot_service_test_url     = "https://portal.azure.com/#@/resource${azurerm_bot_service_azure_bot.main.id}/test"
  }
}