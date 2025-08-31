# Outputs for SMS notifications with Azure Communication Services and Functions
# These outputs provide essential information for deployment verification and integration

# Resource Group Information
output "resource_group_name" {
  description = "The name of the resource group containing all SMS notification resources"
  value       = azurerm_resource_group.sms_rg.name
}

output "resource_group_location" {
  description = "The Azure region where the resource group is deployed"
  value       = azurerm_resource_group.sms_rg.location
}

output "resource_group_id" {
  description = "The unique identifier of the resource group"
  value       = azurerm_resource_group.sms_rg.id
}

# Azure Communication Services Information
output "communication_service_name" {
  description = "The name of the Azure Communication Services resource"
  value       = azurerm_communication_service.sms_communication.name
}

output "communication_service_id" {
  description = "The unique identifier of the Communication Services resource"
  value       = azurerm_communication_service.sms_communication.id
}

output "communication_service_hostname" {
  description = "The hostname of the Communication Services resource"
  value       = azurerm_communication_service.sms_communication.hostname
}

output "communication_service_primary_connection_string" {
  description = "The primary connection string for Communication Services (sensitive)"
  value       = azurerm_communication_service.sms_communication.primary_connection_string
  sensitive   = true
}

output "communication_service_secondary_connection_string" {
  description = "The secondary connection string for Communication Services (sensitive)"
  value       = azurerm_communication_service.sms_communication.secondary_connection_string
  sensitive   = true
}

output "communication_service_primary_key" {
  description = "The primary access key for Communication Services (sensitive)"
  value       = azurerm_communication_service.sms_communication.primary_key
  sensitive   = true
}

output "communication_service_secondary_key" {
  description = "The secondary access key for Communication Services (sensitive)"
  value       = azurerm_communication_service.sms_communication.secondary_key
  sensitive   = true
}

# Storage Account Information
output "storage_account_name" {
  description = "The name of the storage account used by the Function App"
  value       = azurerm_storage_account.sms_storage.name
}

output "storage_account_id" {
  description = "The unique identifier of the storage account"
  value       = azurerm_storage_account.sms_storage.id
}

output "storage_account_primary_connection_string" {
  description = "The primary connection string for the storage account (sensitive)"
  value       = azurerm_storage_account.sms_storage.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_blob_endpoint" {
  description = "The primary blob endpoint for the storage account"
  value       = azurerm_storage_account.sms_storage.primary_blob_endpoint
}

# App Service Plan Information
output "service_plan_name" {
  description = "The name of the App Service Plan"
  value       = azurerm_service_plan.sms_plan.name
}

output "service_plan_id" {
  description = "The unique identifier of the App Service Plan"
  value       = azurerm_service_plan.sms_plan.id
}

output "service_plan_sku_name" {
  description = "The SKU name of the App Service Plan"
  value       = azurerm_service_plan.sms_plan.sku_name
}

output "service_plan_os_type" {
  description = "The operating system type of the App Service Plan"
  value       = azurerm_service_plan.sms_plan.os_type
}

# Azure Function App Information
output "function_app_name" {
  description = "The name of the Azure Function App"
  value       = azurerm_linux_function_app.sms_function.name
}

output "function_app_id" {
  description = "The unique identifier of the Function App"
  value       = azurerm_linux_function_app.sms_function.id
}

output "function_app_default_hostname" {
  description = "The default hostname of the Function App"
  value       = azurerm_linux_function_app.sms_function.default_hostname
}

output "function_app_kind" {
  description = "The kind of Function App"
  value       = azurerm_linux_function_app.sms_function.kind
}

output "function_app_outbound_ip_addresses" {
  description = "The outbound IP addresses of the Function App"
  value       = azurerm_linux_function_app.sms_function.outbound_ip_addresses
}

output "function_app_possible_outbound_ip_addresses" {
  description = "All possible outbound IP addresses of the Function App"
  value       = azurerm_linux_function_app.sms_function.possible_outbound_ip_addresses
}

output "function_app_site_credential" {
  description = "The publish profile credentials for the Function App (sensitive)"
  value = {
    name     = azurerm_linux_function_app.sms_function.site_credential[0].name
    password = azurerm_linux_function_app.sms_function.site_credential[0].password
  }
  sensitive = true
}

# Function App Identity Information
output "function_app_identity_principal_id" {
  description = "The Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.sms_function.identity[0].principal_id
}

output "function_app_identity_tenant_id" {
  description = "The Tenant ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.sms_function.identity[0].tenant_id
}

# Application Insights Information (conditional outputs)
output "application_insights_name" {
  description = "The name of the Application Insights resource (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.sms_insights[0].name : null
}

output "application_insights_id" {
  description = "The unique identifier of the Application Insights resource (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.sms_insights[0].id : null
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key for Application Insights (sensitive, if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.sms_insights[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The connection string for Application Insights (sensitive, if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.sms_insights[0].connection_string : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "The App ID of the Application Insights resource (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.sms_insights[0].app_id : null
}

# Log Analytics Workspace Information (conditional outputs)
output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace (if Application Insights is enabled)"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.sms_workspace[0].name : null
}

output "log_analytics_workspace_id" {
  description = "The unique identifier of the Log Analytics workspace (if Application Insights is enabled)"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.sms_workspace[0].id : null
}

output "log_analytics_workspace_workspace_id" {
  description = "The workspace ID of the Log Analytics workspace (if Application Insights is enabled)"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.sms_workspace[0].workspace_id : null
}

# Deployment Information
output "deployment_info" {
  description = "Summary information about the deployment"
  value = {
    resource_group_name     = azurerm_resource_group.sms_rg.name
    location               = azurerm_resource_group.sms_rg.location
    function_app_name      = azurerm_linux_function_app.sms_function.name
    function_app_url       = "https://${azurerm_linux_function_app.sms_function.default_hostname}"
    communication_service  = azurerm_communication_service.sms_communication.name
    environment           = var.environment
    project_name          = var.project_name
    application_insights_enabled = var.enable_application_insights
    node_version          = var.node_version
    functions_runtime     = var.function_runtime_version
  }
}

# Function URLs (these will be available after function deployment)
output "function_endpoints" {
  description = "Information about function endpoints and how to access them"
  value = {
    base_url = "https://${azurerm_linux_function_app.sms_function.default_hostname}"
    sms_function_url = "https://${azurerm_linux_function_app.sms_function.default_hostname}/api/sendSMS"
    scm_url = "https://${azurerm_linux_function_app.sms_function.name}.scm.azurewebsites.net"
  }
}

# Resource Names (useful for external references)
output "resource_names" {
  description = "All resource names created by this deployment"
  value = {
    resource_group      = azurerm_resource_group.sms_rg.name
    communication_service = azurerm_communication_service.sms_communication.name
    storage_account     = azurerm_storage_account.sms_storage.name
    service_plan        = azurerm_service_plan.sms_plan.name
    function_app        = azurerm_linux_function_app.sms_function.name
    application_insights = var.enable_application_insights ? azurerm_application_insights.sms_insights[0].name : null
    log_analytics_workspace = var.enable_application_insights ? azurerm_log_analytics_workspace.sms_workspace[0].name : null
  }
}