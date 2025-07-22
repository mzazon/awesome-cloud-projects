# Output values for Azure PWA infrastructure
# These outputs provide essential information for accessing and managing the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all PWA resources"
  value       = azurerm_resource_group.pwa.name
}

output "resource_group_location" {
  description = "Azure region where the resource group is located"
  value       = azurerm_resource_group.pwa.location
}

output "resource_group_id" {
  description = "Resource ID of the resource group"
  value       = azurerm_resource_group.pwa.id
}

# Static Web App Information
output "static_web_app_name" {
  description = "Name of the Azure Static Web App"
  value       = azurerm_static_web_app.pwa.name
}

output "static_web_app_default_hostname" {
  description = "Default hostname of the Static Web App"
  value       = azurerm_static_web_app.pwa.default_host_name
}

output "static_web_app_url" {
  description = "Complete URL of the Static Web App"
  value       = "https://${azurerm_static_web_app.pwa.default_host_name}"
}

output "static_web_app_id" {
  description = "Resource ID of the Static Web App"
  value       = azurerm_static_web_app.pwa.id
}

output "static_web_app_api_key" {
  description = "API key for the Static Web App (sensitive)"
  value       = azurerm_static_web_app.pwa.api_key
  sensitive   = true
}

# CDN Information
output "cdn_profile_name" {
  description = "Name of the CDN profile"
  value       = azurerm_cdn_profile.pwa.name
}

output "cdn_endpoint_name" {
  description = "Name of the CDN endpoint"
  value       = azurerm_cdn_endpoint.pwa.name
}

output "cdn_endpoint_hostname" {
  description = "Hostname of the CDN endpoint"
  value       = azurerm_cdn_endpoint.pwa.host_name
}

output "cdn_endpoint_url" {
  description = "Complete URL of the CDN endpoint"
  value       = "https://${azurerm_cdn_endpoint.pwa.host_name}"
}

output "cdn_endpoint_id" {
  description = "Resource ID of the CDN endpoint"
  value       = azurerm_cdn_endpoint.pwa.id
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.pwa.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive)"
  value       = azurerm_application_insights.pwa.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (sensitive)"
  value       = azurerm_application_insights.pwa.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = azurerm_application_insights.pwa.app_id
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights instance"
  value       = azurerm_application_insights.pwa.id
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.pwa.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.pwa.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.pwa.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace (sensitive)"
  value       = azurerm_log_analytics_workspace.pwa.primary_shared_key
  sensitive   = true
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.pwa.name
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.pwa.default_hostname
}

output "function_app_url" {
  description = "Complete URL of the Function App"
  value       = "https://${azurerm_linux_function_app.pwa.default_hostname}"
}

output "function_app_id" {
  description = "Resource ID of the Function App"
  value       = azurerm_linux_function_app.pwa.id
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's system-assigned identity"
  value       = azurerm_linux_function_app.pwa.identity[0].principal_id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for Function App"
  value       = azurerm_storage_account.pwa_functions.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.pwa_functions.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.pwa_functions.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string of the storage account (sensitive)"
  value       = azurerm_storage_account.pwa_functions.primary_connection_string
  sensitive   = true
}

# Service Plan Information
output "service_plan_name" {
  description = "Name of the Service Plan"
  value       = azurerm_service_plan.pwa.name
}

output "service_plan_id" {
  description = "Resource ID of the Service Plan"
  value       = azurerm_service_plan.pwa.id
}

output "service_plan_sku_name" {
  description = "SKU name of the Service Plan"
  value       = azurerm_service_plan.pwa.sku_name
}

# Custom Domain Information (if enabled)
output "custom_domain_name" {
  description = "Custom domain name for the Static Web App"
  value       = var.enable_custom_domain && var.custom_domain_name != "" ? var.custom_domain_name : null
}

output "custom_domain_configured" {
  description = "Whether custom domain is configured"
  value       = var.enable_custom_domain && var.custom_domain_name != ""
}

# Monitoring Information
output "action_group_name" {
  description = "Name of the monitoring action group"
  value       = azurerm_monitor_action_group.pwa.name
}

output "action_group_id" {
  description = "Resource ID of the monitoring action group"
  value       = azurerm_monitor_action_group.pwa.id
}

output "availability_test_name" {
  description = "Name of the availability test"
  value       = azurerm_application_insights_web_test.pwa.name
}

output "availability_test_id" {
  description = "Resource ID of the availability test"
  value       = azurerm_application_insights_web_test.pwa.id
}

# Configuration Information
output "deployment_configuration" {
  description = "Deployment configuration summary"
  value = {
    project_name            = var.project_name
    environment            = var.environment
    location               = var.location
    static_web_app_sku     = var.static_web_app_sku
    cdn_sku                = var.cdn_sku
    compression_enabled    = var.enable_compression
    custom_domain_enabled  = var.enable_custom_domain
    staging_environments   = var.enable_staging_environments
    application_insights_retention = var.application_insights_retention_days
  }
}

# GitHub Integration Information
output "github_integration_configured" {
  description = "Whether GitHub integration is configured"
  value       = var.github_repository_url != ""
}

output "github_repository_url" {
  description = "GitHub repository URL"
  value       = var.github_repository_url
}

output "github_branch" {
  description = "GitHub branch used for deployment"
  value       = var.github_branch
}

# Useful Commands
output "useful_commands" {
  description = "Useful Azure CLI commands for managing the PWA"
  value = {
    view_static_web_app = "az staticwebapp show --name ${azurerm_static_web_app.pwa.name} --resource-group ${azurerm_resource_group.pwa.name}"
    view_cdn_endpoint   = "az cdn endpoint show --name ${azurerm_cdn_endpoint.pwa.name} --profile-name ${azurerm_cdn_profile.pwa.name} --resource-group ${azurerm_resource_group.pwa.name}"
    view_app_insights   = "az monitor app-insights component show --app ${azurerm_application_insights.pwa.name} --resource-group ${azurerm_resource_group.pwa.name}"
    purge_cdn_cache     = "az cdn endpoint purge --name ${azurerm_cdn_endpoint.pwa.name} --profile-name ${azurerm_cdn_profile.pwa.name} --resource-group ${azurerm_resource_group.pwa.name} --content-paths '/*'"
    view_function_logs  = "az functionapp log tail --name ${azurerm_linux_function_app.pwa.name} --resource-group ${azurerm_resource_group.pwa.name}"
  }
}

# Next Steps
output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Configure your GitHub repository with the source code",
    "2. Push your PWA code to trigger the first deployment",
    "3. Configure custom domain DNS settings (if enabled)",
    "4. Set up monitoring alerts and notifications",
    "5. Test PWA functionality including offline capabilities",
    "6. Configure push notifications if needed",
    "7. Monitor performance through Application Insights",
    "8. Set up CI/CD pipeline optimizations"
  ]
}

# Cost Optimization Tips
output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = [
    "1. Use Free tier for Static Web Apps during development",
    "2. Monitor CDN bandwidth usage and optimize caching",
    "3. Set up budget alerts for Application Insights",
    "4. Use consumption plan for Function Apps",
    "5. Configure appropriate data retention policies",
    "6. Monitor storage account usage for Function Apps",
    "7. Use appropriate CDN SKU for your traffic patterns",
    "8. Implement efficient caching strategies"
  ]
}