# Output Values for Azure Configuration Management Solution
# These outputs provide important information about the deployed resources
# that can be used for verification, integration, or by other Terraform configurations

# Resource Group Information
output "resource_group_name" {
  description = "The name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "The Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "The ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Azure App Configuration Outputs
output "app_configuration_name" {
  description = "The name of the Azure App Configuration store"
  value       = azurerm_app_configuration.main.name
}

output "app_configuration_id" {
  description = "The ID of the Azure App Configuration store"
  value       = azurerm_app_configuration.main.id
}

output "app_configuration_endpoint" {
  description = "The endpoint URL of the Azure App Configuration store"
  value       = azurerm_app_configuration.main.endpoint
}

output "app_configuration_primary_read_key" {
  description = "The primary read key for the App Configuration store (sensitive)"
  value       = var.app_config_local_auth_enabled ? azurerm_app_configuration.main.primary_read_key[0].key : null
  sensitive   = true
}

output "app_configuration_primary_write_key" {
  description = "The primary write key for the App Configuration store (sensitive)"
  value       = var.app_config_local_auth_enabled ? azurerm_app_configuration.main.primary_write_key[0].key : null
  sensitive   = true
}

output "app_configuration_sku" {
  description = "The SKU (pricing tier) of the App Configuration store"
  value       = azurerm_app_configuration.main.sku
}

# App Service Plan Outputs
output "app_service_plan_name" {
  description = "The name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "The ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "app_service_plan_sku" {
  description = "The SKU (pricing tier) of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

output "app_service_plan_os_type" {
  description = "The operating system type of the App Service Plan"
  value       = azurerm_service_plan.main.os_type
}

# App Service Outputs
output "app_service_name" {
  description = "The name of the Azure App Service"
  value       = var.app_service_os_type == "Linux" ? azurerm_linux_web_app.main[0].name : azurerm_windows_web_app.main[0].name
}

output "app_service_id" {
  description = "The ID of the Azure App Service"
  value       = var.app_service_os_type == "Linux" ? azurerm_linux_web_app.main[0].id : azurerm_windows_web_app.main[0].id
}

output "app_service_default_hostname" {
  description = "The default hostname of the Azure App Service"
  value       = var.app_service_os_type == "Linux" ? azurerm_linux_web_app.main[0].default_hostname : azurerm_windows_web_app.main[0].default_hostname
}

output "app_service_url" {
  description = "The HTTPS URL of the Azure App Service"
  value       = var.app_service_os_type == "Linux" ? "https://${azurerm_linux_web_app.main[0].default_hostname}" : "https://${azurerm_windows_web_app.main[0].default_hostname}"
}

output "app_service_outbound_ip_addresses" {
  description = "The outbound IP addresses of the Azure App Service"
  value       = var.app_service_os_type == "Linux" ? azurerm_linux_web_app.main[0].outbound_ip_addresses : azurerm_windows_web_app.main[0].outbound_ip_addresses
}

output "app_service_possible_outbound_ip_addresses" {
  description = "All possible outbound IP addresses of the Azure App Service"
  value       = var.app_service_os_type == "Linux" ? azurerm_linux_web_app.main[0].possible_outbound_ip_addresses : azurerm_windows_web_app.main[0].possible_outbound_ip_addresses
}

# Managed Identity Outputs
output "app_service_managed_identity_principal_id" {
  description = "The Principal ID of the App Service's system-assigned managed identity"
  value       = var.managed_identity_enabled ? (var.app_service_os_type == "Linux" ? azurerm_linux_web_app.main[0].identity[0].principal_id : azurerm_windows_web_app.main[0].identity[0].principal_id) : null
}

output "app_service_managed_identity_tenant_id" {
  description = "The Tenant ID of the App Service's system-assigned managed identity"
  value       = var.managed_identity_enabled ? (var.app_service_os_type == "Linux" ? azurerm_linux_web_app.main[0].identity[0].tenant_id : azurerm_windows_web_app.main[0].identity[0].tenant_id) : null
}

# Application Insights Outputs
output "application_insights_name" {
  description = "The name of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_id" {
  description = "The ID of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].id : null
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key of Application Insights (sensitive)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The connection string of Application Insights (sensitive)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "The App ID of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].app_id : null
}

# Configuration Values Outputs
output "configuration_keys" {
  description = "List of configuration keys stored in App Configuration"
  value       = keys(var.configuration_values)
}

output "configuration_count" {
  description = "Number of configuration key-value pairs stored"
  value       = length(var.configuration_values)
}

# Deployment Slot Outputs (if applicable)
output "staging_slot_name" {
  description = "The name of the staging deployment slot"
  value       = var.app_service_os_type == "Linux" && var.app_service_plan_sku != "F1" && var.app_service_plan_sku != "D1" && var.environment == "prod" ? azurerm_linux_web_app_slot.staging[0].name : null
}

output "staging_slot_url" {
  description = "The HTTPS URL of the staging deployment slot"
  value       = var.app_service_os_type == "Linux" && var.app_service_plan_sku != "F1" && var.app_service_plan_sku != "D1" && var.environment == "prod" ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

# Resource Tags
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Cost and Resource Information
output "deployment_summary" {
  description = "Summary of deployed resources and their key properties"
  value = {
    resource_group = {
      name     = azurerm_resource_group.main.name
      location = azurerm_resource_group.main.location
    }
    app_configuration = {
      name     = azurerm_app_configuration.main.name
      sku      = azurerm_app_configuration.main.sku
      endpoint = azurerm_app_configuration.main.endpoint
    }
    app_service = {
      name         = var.app_service_os_type == "Linux" ? azurerm_linux_web_app.main[0].name : azurerm_windows_web_app.main[0].name
      plan_sku     = azurerm_service_plan.main.sku_name
      os_type      = azurerm_service_plan.main.os_type
      url          = var.app_service_os_type == "Linux" ? "https://${azurerm_linux_web_app.main[0].default_hostname}" : "https://${azurerm_windows_web_app.main[0].default_hostname}"
      dotnet_version = var.dotnet_version
    }
    features = {
      managed_identity      = var.managed_identity_enabled
      application_insights  = var.enable_application_insights
      https_only           = var.https_only
      staging_slot         = var.app_service_os_type == "Linux" && var.app_service_plan_sku != "F1" && var.app_service_plan_sku != "D1" && var.environment == "prod"
    }
  }
}

# Quick Access URLs and Commands
output "quick_access" {
  description = "Quick access information for testing and management"
  value = {
    app_url = var.app_service_os_type == "Linux" ? "https://${azurerm_linux_web_app.main[0].default_hostname}" : "https://${azurerm_windows_web_app.main[0].default_hostname}"
    azure_portal_urls = {
      resource_group    = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/overview"
      app_configuration = "https://portal.azure.com/#@/resource${azurerm_app_configuration.main.id}/keyValues"
      app_service       = "https://portal.azure.com/#@/resource${var.app_service_os_type == "Linux" ? azurerm_linux_web_app.main[0].id : azurerm_windows_web_app.main[0].id}/overview"
    }
    cli_commands = {
      view_app_config   = "az appconfig kv list --name ${azurerm_app_configuration.main.name}"
      restart_app       = "az webapp restart --name ${var.app_service_os_type == "Linux" ? azurerm_linux_web_app.main[0].name : azurerm_windows_web_app.main[0].name} --resource-group ${azurerm_resource_group.main.name}"
      view_logs         = "az webapp log tail --name ${var.app_service_os_type == "Linux" ? azurerm_linux_web_app.main[0].name : azurerm_windows_web_app.main[0].name} --resource-group ${azurerm_resource_group.main.name}"
      update_config     = "az appconfig kv set --name ${azurerm_app_configuration.main.name} --key 'DemoApp:Settings:Message' --value 'Updated via CLI'"
    }
  }
}