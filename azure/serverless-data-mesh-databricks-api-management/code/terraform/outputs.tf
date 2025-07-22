# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources were created"
  value       = azurerm_resource_group.main.location
}

# Databricks Workspace Information
output "databricks_workspace_name" {
  description = "Name of the Databricks workspace"
  value       = azurerm_databricks_workspace.main.name
}

output "databricks_workspace_id" {
  description = "ID of the Databricks workspace"
  value       = azurerm_databricks_workspace.main.id
}

output "databricks_workspace_url" {
  description = "URL of the Databricks workspace"
  value       = "https://${azurerm_databricks_workspace.main.workspace_url}"
}

output "databricks_managed_resource_group_id" {
  description = "ID of the managed resource group created for Databricks"
  value       = azurerm_databricks_workspace.main.managed_resource_group_id
}

# API Management Information
output "api_management_name" {
  description = "Name of the API Management service"
  value       = azurerm_api_management.main.name
}

output "api_management_id" {
  description = "ID of the API Management service"
  value       = azurerm_api_management.main.id
}

output "api_management_gateway_url" {
  description = "Gateway URL of the API Management service"
  value       = azurerm_api_management.main.gateway_url
}

output "api_management_developer_portal_url" {
  description = "Developer portal URL of the API Management service"
  value       = azurerm_api_management.main.developer_portal_url
}

output "api_management_management_url" {
  description = "Management URL of the API Management service"
  value       = azurerm_api_management.main.management_api_url
}

output "api_management_portal_url" {
  description = "Portal URL of the API Management service"
  value       = azurerm_api_management.main.portal_url
}

output "api_management_scm_url" {
  description = "SCM URL of the API Management service"
  value       = azurerm_api_management.main.scm_url
}

output "api_management_public_ip_addresses" {
  description = "Public IP addresses of the API Management service"
  value       = azurerm_api_management.main.public_ip_addresses
}

# Data Product API Information
output "data_product_apis" {
  description = "Information about created data product APIs"
  value = {
    for api_name, api in azurerm_api_management_api.data_products : api_name => {
      name         = api.name
      display_name = api.display_name
      path         = api.path
      api_id       = api.id
      service_url  = "${azurerm_api_management.main.gateway_url}/${api.path}"
    }
  }
}

output "data_product_api_subscriptions" {
  description = "Subscription information for data product APIs"
  value = {
    for subscription_name, subscription in azurerm_api_management_subscription.data_consumers : subscription_name => {
      subscription_id = subscription.subscription_id
      display_name    = subscription.display_name
      primary_key     = subscription.primary_key
      secondary_key   = subscription.secondary_key
      state           = subscription.state
    }
  }
  sensitive = true
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

# Event Grid Information
output "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.name
}

output "event_grid_topic_id" {
  description = "ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.id
}

output "event_grid_topic_endpoint" {
  description = "Endpoint of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.endpoint
}

output "event_grid_topic_primary_access_key" {
  description = "Primary access key for the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.primary_access_key
  sensitive   = true
}

output "event_grid_topic_secondary_access_key" {
  description = "Secondary access key for the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.secondary_access_key
  sensitive   = true
}

# Service Principal Information
output "databricks_service_principal_application_id" {
  description = "Application ID of the Databricks service principal"
  value       = azuread_service_principal.databricks.application_id
}

output "databricks_service_principal_object_id" {
  description = "Object ID of the Databricks service principal"
  value       = azuread_service_principal.databricks.object_id
}

output "databricks_service_principal_display_name" {
  description = "Display name of the Databricks service principal"
  value       = azuread_service_principal.databricks.display_name
}

# Monitoring Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
}

output "application_insights_name" {
  description = "Name of the Application Insights component"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# Configuration Information
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    project_name             = var.project_name
    environment              = var.environment
    location                 = var.location
    databricks_sku           = var.databricks_sku
    api_management_sku       = var.apim_sku_name
    key_vault_sku           = var.key_vault_sku
    monitoring_enabled       = var.enable_monitoring
    private_endpoints_enabled = var.enable_private_endpoints
    rbac_enabled            = var.key_vault_enable_rbac
    no_public_ip_enabled    = var.databricks_enable_no_public_ip
    data_product_count      = length(var.data_product_apis)
  }
}

# Unity Catalog Information
output "unity_catalog_configuration" {
  description = "Unity Catalog configuration details"
  value = {
    catalog_name = var.unity_catalog_name
    schema_name  = var.unity_catalog_schema_name
    databricks_url = "https://${azurerm_databricks_workspace.main.workspace_url}"
  }
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Instructions for accessing and using the deployed resources"
  value = {
    databricks_access = "Navigate to https://${azurerm_databricks_workspace.main.workspace_url} to access the Databricks workspace"
    api_management_portal = "Visit ${azurerm_api_management.main.developer_portal_url} to explore the API developer portal"
    key_vault_access = "Access Key Vault at https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_key_vault.main.id}"
    event_grid_monitoring = "Monitor Event Grid events through the Azure portal at https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_eventgrid_topic.main.id}"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration details"
  value = {
    key_vault_rbac_enabled = var.key_vault_enable_rbac
    databricks_no_public_ip = var.databricks_enable_no_public_ip
    api_management_identity = var.enable_system_assigned_identity ? "SystemAssigned" : "None"
    allowed_ip_ranges = var.allowed_ip_ranges
  }
}

# Cost Management Information
output "cost_management_tags" {
  description = "Tags applied to resources for cost management"
  value       = local.common_tags
}

# Sample API Call Examples
output "sample_api_calls" {
  description = "Sample API calls for testing data products"
  value = {
    for api_name, api in azurerm_api_management_api.data_products : api_name => {
      curl_command = "curl -X GET '${azurerm_api_management.main.gateway_url}/${api.path}/metrics?dateFrom=2024-01-01' -H 'Ocp-Apim-Subscription-Key: ${azurerm_api_management_subscription.data_consumers[api_name].primary_key}'"
      api_url = "${azurerm_api_management.main.gateway_url}/${api.path}"
    }
  }
  sensitive = true
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Configure Unity Catalog in the Databricks workspace",
    "2. Create sample data products using the provided notebook template",
    "3. Test API endpoints using the developer portal",
    "4. Set up Event Grid subscriptions for data product notifications",
    "5. Configure monitoring and alerting for the data mesh infrastructure",
    "6. Implement authentication and authorization for API consumers",
    "7. Create additional data product APIs for different domains"
  ]
}