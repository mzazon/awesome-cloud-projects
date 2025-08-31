# Output values for the Key Vault and App Service secrets management solution
# These outputs provide important information for validation and integration

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "Resource ID of the Azure Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_rbac_enabled" {
  description = "Whether RBAC authorization is enabled for the Key Vault"
  value       = azurerm_key_vault.main.enable_rbac_authorization
}

# Key Vault Secrets Information
output "database_secret_name" {
  description = "Name of the database connection secret in Key Vault"
  value       = azurerm_key_vault_secret.database_connection.name
}

output "database_secret_id" {
  description = "ID of the database connection secret in Key Vault"
  value       = azurerm_key_vault_secret.database_connection.id
}

output "api_key_secret_name" {
  description = "Name of the API key secret in Key Vault"
  value       = azurerm_key_vault_secret.external_api_key.name
}

output "api_key_secret_id" {
  description = "ID of the API key secret in Key Vault"
  value       = azurerm_key_vault_secret.external_api_key.id
}

# App Service Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "app_service_plan_sku" {
  description = "SKU tier and size of the App Service Plan"
  value = {
    tier = var.app_service_sku.tier
    size = var.app_service_sku.size
  }
}

output "web_app_name" {
  description = "Name of the web application"
  value       = azurerm_linux_web_app.main.name
}

output "web_app_id" {
  description = "Resource ID of the web application"
  value       = azurerm_linux_web_app.main.id
}

output "web_app_url" {
  description = "HTTPS URL of the web application"
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "web_app_default_hostname" {
  description = "Default hostname of the web application"
  value       = azurerm_linux_web_app.main.default_hostname
}

# Managed Identity Information
output "web_app_managed_identity_principal_id" {
  description = "Principal ID of the web app's system-assigned managed identity"
  value       = azurerm_linux_web_app.main.identity[0].principal_id
}

output "web_app_managed_identity_tenant_id" {
  description = "Tenant ID of the web app's system-assigned managed identity"
  value       = azurerm_linux_web_app.main.identity[0].tenant_id
}

# Key Vault References Configuration
output "key_vault_references" {
  description = "Key Vault reference strings used in app settings"
  value = {
    database_connection = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=${azurerm_key_vault_secret.database_connection.name})"
    api_key            = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=${azurerm_key_vault_secret.external_api_key.name})"
  }
}

# Security Configuration
output "security_configuration" {
  description = "Security settings applied to the infrastructure"
  value = {
    key_vault_rbac_enabled     = azurerm_key_vault.main.enable_rbac_authorization
    key_vault_purge_protection = azurerm_key_vault.main.purge_protection_enabled
    web_app_https_only        = azurerm_linux_web_app.main.https_only
    managed_identity_enabled   = true
  }
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployed infrastructure"
  value = {
    environment       = var.environment
    project_name      = var.project_name
    random_suffix     = random_id.suffix.hex
    deployment_region = var.location
    node_version      = var.node_version
  }
}

# Validation Commands
output "validation_commands" {
  description = "CLI commands to validate the deployment"
  value = {
    list_key_vault_secrets = "az keyvault secret list --vault-name ${azurerm_key_vault.main.name} --query '[].{Name:name, Enabled:attributes.enabled}' --output table"
    check_managed_identity = "az webapp identity show --name ${azurerm_linux_web_app.main.name} --resource-group ${azurerm_resource_group.main.name} --query '{Type:type, PrincipalId:principalId}'"
    test_web_app          = "curl -s https://${azurerm_linux_web_app.main.default_hostname}"
    check_app_settings    = "az webapp config appsettings list --name ${azurerm_linux_web_app.main.name} --resource-group ${azurerm_resource_group.main.name} --query \"[?contains(name, 'DATABASE_CONNECTION') || contains(name, 'API_KEY')].{Name:name, Value:value}\" --output table"
  }
}

# Cost Information
output "cost_information" {
  description = "Estimated cost information for the deployed resources"
  value = {
    app_service_plan_tier = var.app_service_sku.tier
    key_vault_sku        = var.key_vault_sku
    estimated_monthly_cost = "Approximately $56 USD/month for B1 App Service Plan + minimal Key Vault operations costs"
    cost_optimization_tips = [
      "Use Free tier App Service Plan for development/testing",
      "Monitor Key Vault operations to optimize costs",
      "Consider App Service Plan sharing across multiple apps",
      "Enable auto-shutdown for non-production environments"
    ]
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Visit the web application URL to verify Key Vault integration",
    "Review the managed identity configuration in Azure Portal",
    "Test secret rotation using Azure Key Vault",
    "Configure monitoring and alerting for the application",
    "Implement additional security measures for production use"
  ]
}