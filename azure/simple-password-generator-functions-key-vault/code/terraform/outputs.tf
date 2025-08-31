# Output Values for Azure Password Generator Infrastructure
# This file defines outputs that provide essential information about the deployed infrastructure

# Resource Group Information

output "resource_group_name" {
  description = "Name of the created Azure Resource Group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Full resource ID of the Resource Group"
  value       = azurerm_resource_group.main.id
}

# Function App Information

output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_url" {
  description = "Default hostname/URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_id" {
  description = "Full resource ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's system-assigned managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
  sensitive   = true
}

output "function_app_tenant_id" {
  description = "Tenant ID of the Function App's system-assigned managed identity"
  value       = azurerm_linux_function_app.main.identity[0].tenant_id
}

# Function App Access Information

output "function_app_master_key" {
  description = "Master key for Function App access (use with caution)"
  value       = "Use 'az functionapp keys list --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name}' to retrieve"
  sensitive   = true
}

output "password_generator_endpoint" {
  description = "Endpoint URL for the password generator function"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/generatePassword"
}

# Key Vault Information

output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_id" {
  description = "Full resource ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

# Storage Account Information

output "storage_account_name" {
  description = "Name of the storage account used by the Function App"
  value       = azurerm_storage_account.function_storage.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.function_storage.primary_blob_endpoint
}

# Application Insights Information (if enabled)

output "application_insights_name" {
  description = "Name of the Application Insights component (if enabled)"
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

# App Service Plan Information

output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "Full resource ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

# Security and Access Information

output "managed_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity for RBAC assignments"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
  sensitive   = true
}

output "key_vault_rbac_role_assignment_id" {
  description = "ID of the RBAC role assignment for Key Vault access"
  value       = azurerm_role_assignment.function_keyvault_secrets.id
}

# Deployment and Testing Information

output "deployment_commands" {
  description = "Commands to deploy function code and test the solution"
  value = {
    # Function code deployment command
    deploy_function = "func azure functionapp publish ${azurerm_linux_function_app.main.name}"
    
    # Test password generation command
    test_password_generation = "curl -X POST 'https://${azurerm_linux_function_app.main.default_hostname}/api/generatePassword?code=<FUNCTION_KEY>' -H 'Content-Type: application/json' -d '{\"secretName\": \"test-password\", \"length\": 16}'"
    
    # List Key Vault secrets command
    list_secrets = "az keyvault secret list --vault-name ${azurerm_key_vault.main.name}"
    
    # Get function keys command
    get_function_keys = "az functionapp keys list --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
  }
}

# Resource Naming Information

output "resource_naming" {
  description = "Generated resource names and random suffix used"
  value = {
    random_suffix        = local.random_suffix
    resource_group      = local.resource_group_name
    function_app        = local.function_app_name
    key_vault          = local.key_vault_name
    storage_account    = local.storage_account_name
    app_service_plan   = local.app_service_plan_name
    application_insights = var.enable_application_insights ? local.app_insights_name : null
  }
}

# Configuration Summary

output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    environment              = var.environment
    project_name            = var.project_name
    location               = var.location
    key_vault_sku          = var.key_vault_sku
    function_runtime       = var.function_app_runtime
    runtime_version        = var.function_app_runtime_version
    https_only             = var.enable_https_only
    application_insights   = var.enable_application_insights
    purge_protection      = var.enable_purge_protection
  }
}

# Next Steps Information

output "next_steps" {
  description = "Next steps to complete the deployment"
  value = [
    "1. Deploy function code using Azure Functions Core Tools: func azure functionapp publish ${azurerm_linux_function_app.main.name}",
    "2. Retrieve function access keys: az functionapp keys list --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name}",
    "3. Test the password generator endpoint: POST https://${azurerm_linux_function_app.main.default_hostname}/api/generatePassword",
    "4. Monitor function execution in Application Insights (if enabled)",
    "5. View generated passwords in Key Vault: https://portal.azure.com/#@/resource${azurerm_key_vault.main.id}"
  ]
}