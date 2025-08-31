# Outputs for Content Approval Workflows Infrastructure

# Resource Group Information
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

# Azure AD Application Information
output "power_platform_application_id" {
  description = "Application ID for Power Platform integration"
  value       = azuread_application.power_platform.application_id
  sensitive   = false
}

output "power_platform_application_object_id" {
  description = "Object ID of the Power Platform application"
  value       = azuread_application.power_platform.object_id
}

output "service_principal_id" {
  description = "Service Principal ID for the Power Platform application"
  value       = azuread_service_principal.power_platform.id
}

output "service_principal_object_id" {
  description = "Object ID of the service principal"
  value       = azuread_service_principal.power_platform.object_id
}

# Tenant Information
output "tenant_id" {
  description = "Azure AD Tenant ID"
  value       = data.azuread_client_config.current.tenant_id
  sensitive   = false
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

# Storage Account Information
output "storage_account_name" {
  description = "Name of the workflow storage account"
  value       = azurerm_storage_account.workflow_storage.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.workflow_storage.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.workflow_storage.primary_blob_endpoint
}

output "storage_containers" {
  description = "Names of created storage containers"
  value = {
    document_processing = azurerm_storage_container.document_processing.name
    workflow_logs      = azurerm_storage_container.workflow_logs.name
  }
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.workflow_functions.name
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.workflow_functions.id
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.workflow_functions.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.workflow_functions.identity[0].principal_id
}

# Monitoring Resources
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.monitoring_settings.enable_log_analytics ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.monitoring_settings.enable_log_analytics ? azurerm_log_analytics_workspace.main[0].id : null
}

output "application_insights_name" {
  description = "Name of Application Insights"
  value       = var.monitoring_settings.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = var.monitoring_settings.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = var.monitoring_settings.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# Alert and Monitoring Configuration
output "action_group_id" {
  description = "ID of the monitoring action group"
  value       = var.monitoring_settings.enable_alerts ? azurerm_monitor_action_group.main[0].id : null
}

output "budget_name" {
  description = "Name of the cost budget"
  value       = azurerm_consumption_budget_resource_group.main.name
}

# SharePoint Configuration
output "sharepoint_configuration" {
  description = "SharePoint configuration for Power Platform setup"
  value = {
    site_name           = var.sharepoint_site_name
    document_library    = var.document_library_name
    tenant_domain      = "${replace(data.azuread_client_config.current.tenant_id, "-", "")}.onmicrosoft.com"
  }
}

# Power Platform Configuration
output "power_platform_environment_config" {
  description = "Configuration values for Power Platform environment setup"
  value = {
    display_name        = var.power_platform_settings.environment_display_name
    description         = var.power_platform_settings.environment_description
    enable_ai_builder   = var.power_platform_settings.enable_ai_builder
    enable_premium      = var.power_platform_settings.enable_power_automate_premium
    dlp_policy         = var.power_platform_settings.data_loss_prevention_policy
  }
}

# Workflow Settings
output "approval_workflow_configuration" {
  description = "Approval workflow configuration settings"
  value       = var.approval_workflow_settings
}

output "teams_integration_settings" {
  description = "Microsoft Teams integration settings"
  value       = var.teams_integration
}

# Security Configuration
output "security_configuration" {
  description = "Security settings applied to the solution"
  value = {
    audit_logging_enabled     = var.security_settings.enable_audit_logging
    dlp_enabled              = var.security_settings.enable_data_loss_prevention
    encryption_enabled       = var.security_settings.enable_encryption_at_rest
    conditional_access       = var.security_settings.enable_conditional_access
    retention_days           = var.security_settings.retention_period_days
  }
}

# Deployment Information
output "deployment_info" {
  description = "Important deployment information and next steps"
  value = {
    environment           = var.environment
    random_suffix        = random_string.suffix.result
    configuration_file   = "power-platform-config.json"
    next_steps = [
      "1. Configure SharePoint site using the provided site name",
      "2. Set up Power Platform environment with the application ID",
      "3. Create AI Builder prompts using the tenant configuration",
      "4. Build Power Automate workflows with the provided endpoints",
      "5. Configure Teams integration using the service principal",
      "6. Test the complete workflow with sample documents"
    ]
  }
}

# Connection Strings and Endpoints
output "connection_information" {
  description = "Connection strings and endpoints for integration"
  value = {
    key_vault_url       = azurerm_key_vault.main.vault_uri
    storage_connection  = azurerm_storage_account.workflow_storage.primary_connection_string
    function_app_url    = "https://${azurerm_linux_function_app.workflow_functions.default_hostname}"
    tenant_id          = data.azuread_client_config.current.tenant_id
    application_id     = azuread_application.power_platform.application_id
  }
  sensitive = true
}

# Resource URLs for Power Platform Configuration
output "power_platform_urls" {
  description = "URLs needed for Power Platform configuration"
  value = {
    power_apps_url       = "https://make.powerapps.com/"
    power_automate_url   = "https://make.powerautomate.com/"
    sharepoint_admin_url = "https://${replace(data.azuread_client_config.current.tenant_id, "-", "")}-admin.sharepoint.com/"
    teams_admin_url      = "https://admin.teams.microsoft.com/"
    azure_portal_url     = "https://portal.azure.com/"
  }
}

# Tags Applied
output "applied_tags" {
  description = "Tags applied to all resources"
  value       = var.tags
}