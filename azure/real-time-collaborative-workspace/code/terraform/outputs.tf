# Outputs for Azure real-time collaborative applications infrastructure
# This file defines all outputs that will be displayed after deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Azure Communication Services Outputs
output "acs_name" {
  description = "Name of the Azure Communication Services resource"
  value       = azurerm_communication_service.main.name
}

output "acs_connection_string" {
  description = "Connection string for Azure Communication Services"
  value       = azurerm_communication_service.main.primary_connection_string
  sensitive   = true
}

output "acs_primary_key" {
  description = "Primary access key for Azure Communication Services"
  value       = azurerm_communication_service.main.primary_key
  sensitive   = true
}

output "acs_secondary_key" {
  description = "Secondary access key for Azure Communication Services"
  value       = azurerm_communication_service.main.secondary_key
  sensitive   = true
}

# Azure Fluid Relay Outputs
output "fluid_relay_name" {
  description = "Name of the Azure Fluid Relay service"
  value       = azurerm_fluid_relay_server.main.name
}

output "fluid_relay_orderer_endpoint" {
  description = "Orderer endpoint for Azure Fluid Relay"
  value       = azurerm_fluid_relay_server.main.orderer_endpoints[0]
}

output "fluid_relay_storage_endpoint" {
  description = "Storage endpoint for Azure Fluid Relay"
  value       = azurerm_fluid_relay_server.main.storage_endpoints[0]
}

output "fluid_relay_tenant_id" {
  description = "Tenant ID for Azure Fluid Relay"
  value       = azurerm_fluid_relay_server.main.frs_tenant_id
}

output "fluid_relay_primary_key" {
  description = "Primary key for Azure Fluid Relay"
  value       = azurerm_fluid_relay_server.main.primary_key
  sensitive   = true
}

output "fluid_relay_secondary_key" {
  description = "Secondary key for Azure Fluid Relay"
  value       = azurerm_fluid_relay_server.main.secondary_key
  sensitive   = true
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_account_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_containers" {
  description = "Names of created storage containers"
  value       = [for container in azurerm_storage_container.main : container.name]
}

# Key Vault Outputs
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

# Azure Functions Outputs
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_hostname" {
  description = "Default hostname for the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "HTTPS URL for the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_tenant_id" {
  description = "Tenant ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].tenant_id
}

# Application Insights Outputs
output "app_insights_name" {
  description = "Name of the Application Insights resource"
  value       = azurerm_application_insights.main.name
}

output "app_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "app_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "app_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = azurerm_application_insights.main.app_id
}

# API Endpoints for Client Applications
output "api_endpoints" {
  description = "API endpoints for client applications to use"
  value = {
    acs_token_endpoint           = "https://${azurerm_linux_function_app.main.default_hostname}/api/GetAcsToken"
    fluid_token_endpoint         = "https://${azurerm_linux_function_app.main.default_hostname}/api/GetFluidToken"
    user_management_endpoint     = "https://${azurerm_linux_function_app.main.default_hostname}/api/UserManagement"
    whiteboard_storage_endpoint  = "https://${azurerm_linux_function_app.main.default_hostname}/api/WhiteboardStorage"
  }
}

# Connection Information for Client SDKs
output "client_configuration" {
  description = "Configuration information for client applications"
  value = {
    fluid_relay_service_endpoint = azurerm_fluid_relay_server.main.orderer_endpoints[0]
    fluid_relay_tenant_id        = azurerm_fluid_relay_server.main.frs_tenant_id
    storage_account_endpoint     = azurerm_storage_account.main.primary_blob_endpoint
    function_app_base_url        = "https://${azurerm_linux_function_app.main.default_hostname}"
  }
  sensitive = false
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployment"
  value = {
    terraform_version = "~> 1.0"
    azurerm_version  = "~> 3.80"
    deployment_time  = timestamp()
    environment      = var.environment
    location         = var.location
    project_name     = var.project_name
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Approximate monthly cost estimates for deployed resources"
  value = {
    acs_estimated_cost          = "$10-50/month (depends on usage)"
    fluid_relay_estimated_cost  = "$5-20/month (depends on usage)"
    function_app_estimated_cost = "$10-30/month (consumption plan)"
    storage_estimated_cost      = "$5-15/month (depends on data volume)"
    key_vault_estimated_cost    = "$1-5/month (depends on operations)"
    app_insights_estimated_cost = "$5-20/month (depends on telemetry volume)"
    total_estimated_range       = "$36-140/month"
    note                       = "Costs vary based on usage patterns and data volume"
  }
}

# Security Information
output "security_info" {
  description = "Security-related information for the deployment"
  value = {
    managed_identity_enabled     = true
    key_vault_rbac_enabled      = true
    storage_https_only          = true
    function_app_https_only     = true
    soft_delete_retention_days  = var.key_vault_soft_delete_retention
    cors_configuration          = var.enable_cors_all_origins ? "All origins (development only)" : "Restricted origins"
  }
}

# Monitoring and Diagnostics
output "monitoring_info" {
  description = "Monitoring and diagnostics information"
  value = {
    app_insights_enabled        = true
    app_insights_retention_days = var.app_insights_retention_days
    log_analytics_workspace     = azurerm_log_analytics_workspace.main.name
    diagnostic_settings_enabled = true
    alerts_configured           = false
    note                       = "Configure alerts based on your monitoring requirements"
  }
}