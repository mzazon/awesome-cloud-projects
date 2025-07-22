# Resource Group outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

# App Configuration outputs
output "app_configuration_name" {
  description = "Name of the Azure App Configuration store"
  value       = azurerm_app_configuration.main.name
}

output "app_configuration_id" {
  description = "ID of the Azure App Configuration store"
  value       = azurerm_app_configuration.main.id
}

output "app_configuration_endpoint" {
  description = "Endpoint URL of the Azure App Configuration store"
  value       = azurerm_app_configuration.main.endpoint
}

output "app_configuration_primary_read_key" {
  description = "Primary read key for the Azure App Configuration store"
  value       = azurerm_app_configuration.main.primary_read_key
  sensitive   = true
}

output "app_configuration_secondary_read_key" {
  description = "Secondary read key for the Azure App Configuration store"
  value       = azurerm_app_configuration.main.secondary_read_key
  sensitive   = true
}

# Key Vault outputs
output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Azure Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_tenant_id" {
  description = "Tenant ID of the Azure Key Vault"
  value       = azurerm_key_vault.main.tenant_id
}

# App Service Plan outputs
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# Web App outputs
output "web_app_name" {
  description = "Name of the Azure Web App"
  value       = azurerm_linux_web_app.main.name
}

output "web_app_id" {
  description = "ID of the Azure Web App"
  value       = azurerm_linux_web_app.main.id
}

output "web_app_default_hostname" {
  description = "Default hostname of the Azure Web App"
  value       = azurerm_linux_web_app.main.default_hostname
}

output "web_app_url" {
  description = "Full URL of the Azure Web App"
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "web_app_identity_principal_id" {
  description = "Principal ID of the Web App's managed identity"
  value       = azurerm_linux_web_app.main.identity[0].principal_id
}

output "web_app_identity_tenant_id" {
  description = "Tenant ID of the Web App's managed identity"
  value       = azurerm_linux_web_app.main.identity[0].tenant_id
}

# Application Insights outputs
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
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

# Configuration summary outputs
output "configuration_summary" {
  description = "Summary of the deployed configuration management solution"
  value = {
    resource_group          = azurerm_resource_group.main.name
    app_configuration_store = azurerm_app_configuration.main.name
    key_vault              = azurerm_key_vault.main.name
    web_app                = azurerm_linux_web_app.main.name
    web_app_url            = "https://${azurerm_linux_web_app.main.default_hostname}"
    environment            = var.environment
    location               = azurerm_resource_group.main.location
  }
}

# Deployment instructions
output "deployment_instructions" {
  description = "Instructions for validating and testing the deployment"
  value = <<-EOT
    Deployment completed successfully! 
    
    To validate your deployment:
    1. Visit the Web App URL: https://${azurerm_linux_web_app.main.default_hostname}
    2. Check App Configuration settings:
       az appconfig kv list --name ${azurerm_app_configuration.main.name}
    3. Verify Key Vault secrets:
       az keyvault secret list --vault-name ${azurerm_key_vault.main.name}
    4. Test feature flags:
       az appconfig feature list --name ${azurerm_app_configuration.main.name}
    
    For Application Insights monitoring, visit:
    - Azure Portal > Application Insights > ${azurerm_application_insights.main.name}
    
    To clean up resources:
    terraform destroy
  EOT
}

# Random suffix for reference
output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

# Created secrets list (names only for security)
output "created_secrets" {
  description = "List of secrets created in Key Vault"
  value       = keys(azurerm_key_vault_secret.secrets)
}

# Created configuration keys list
output "created_configuration_keys" {
  description = "List of configuration keys created in App Configuration"
  value       = keys(azurerm_app_configuration_key.app_settings)
}

# Created feature flags list
output "created_feature_flags" {
  description = "List of feature flags created in App Configuration"
  value       = keys(azurerm_app_configuration_feature.feature_flags)
}

# Cost estimation note
output "cost_estimation" {
  description = "Estimated monthly cost for the deployed resources"
  value = <<-EOT
    Estimated monthly costs (USD):
    - App Configuration (Standard): ~$1.00
    - Key Vault (Standard): ~$0.03 + secret operations
    - App Service Plan (${var.app_service_sku}): ~$13.00
    - Application Insights: ~$2.30 (first 5GB free)
    
    Total estimated monthly cost: ~$16-20 USD
    
    Note: Costs may vary based on usage patterns and Azure pricing changes.
    Always refer to Azure Pricing Calculator for current rates.
  EOT
}

# Security notes
output "security_notes" {
  description = "Important security considerations for the deployment"
  value = <<-EOT
    Security Configuration Applied:
    ✓ Managed Identity enabled for Web App
    ✓ Key Vault soft delete enabled (${var.soft_delete_retention_days} days)
    ✓ Least privilege access policies configured
    ✓ App Configuration Data Reader role assigned
    ✓ Key Vault secrets access limited to Get/List
    ✓ All resources tagged for compliance
    
    Production Recommendations:
    - Enable Key Vault purge protection
    - Configure network restrictions (Private Link)
    - Implement Azure Policy for compliance
    - Set up monitoring and alerting
    - Regular access review and rotation
  EOT
}