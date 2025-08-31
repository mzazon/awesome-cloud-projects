# Outputs for Azure Resource Monitoring Dashboard with Workbooks
# These outputs provide essential information for verification and integration

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.monitoring.name
}

output "resource_group_id" {
  description = "Resource ID of the created resource group"
  value       = azurerm_resource_group.monitoring.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.monitoring.location
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.monitoring.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.monitoring.id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.monitoring.primary_shared_key
  sensitive   = true
}

output "log_analytics_workspace_secondary_shared_key" {
  description = "Secondary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.monitoring.secondary_shared_key
  sensitive   = true
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.monitoring.workspace_id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the created storage account"
  value       = azurerm_storage_account.demo.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.demo.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.demo.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.demo.primary_access_key
  sensitive   = true
}

# App Service Plan Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.demo.name
}

output "app_service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.demo.id
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.demo.sku_name
}

# Web App Information
output "web_app_name" {
  description = "Name of the Web App"
  value       = azurerm_linux_web_app.demo.name
}

output "web_app_id" {
  description = "Resource ID of the Web App"
  value       = azurerm_linux_web_app.demo.id
}

output "web_app_default_hostname" {
  description = "Default hostname of the Web App"
  value       = azurerm_linux_web_app.demo.default_hostname
}

output "web_app_url" {
  description = "URL of the Web App"
  value       = "https://${azurerm_linux_web_app.demo.default_hostname}"
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights component"
  value       = azurerm_application_insights.monitoring.name
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights component"
  value       = azurerm_application_insights.monitoring.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.monitoring.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.monitoring.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = azurerm_application_insights.monitoring.app_id
}

# Workbook Information
output "workbook_created" {
  description = "Indicates whether the Azure Monitor Workbook was created"
  value       = var.enable_workbook_creation
}

output "workbook_display_name" {
  description = "Display name of the created workbook"
  value       = var.enable_workbook_creation ? var.workbook_display_name : "Not created"
}

# Storage Container Information
output "storage_container_name" {
  description = "Name of the created storage container"
  value       = azurerm_storage_container.demo.name
}

# Portal URLs for Easy Access
output "azure_portal_resource_group_url" {
  description = "URL to view the resource group in Azure portal"
  value       = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.monitoring.name}/overview"
}

output "azure_portal_log_analytics_url" {
  description = "URL to view the Log Analytics workspace in Azure portal"
  value       = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.monitoring.id}/overview"
}

output "azure_portal_workbooks_url" {
  description = "URL to access Azure Monitor Workbooks in Azure portal"
  value       = "https://portal.azure.com/#view/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/~/workbooks"
}

output "azure_portal_application_insights_url" {
  description = "URL to view Application Insights in Azure portal"
  value       = "https://portal.azure.com/#@/resource${azurerm_application_insights.monitoring.id}/overview"
}

# Cost Estimation Information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD for all created resources"
  value = {
    log_analytics_workspace = "5-20 USD (depending on data ingestion)"
    storage_account        = "1-5 USD (depending on usage)"
    app_service_plan      = "0 USD (F1 Free tier)"
    web_app               = "0 USD (included in App Service Plan)"
    application_insights  = "0-10 USD (depending on telemetry volume)"
    workbook              = "0 USD (free service)"
    total_estimated       = "6-35 USD per month"
  }
}

# Resource Tags
output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Diagnostic Settings Status
output "diagnostic_settings_enabled" {
  description = "Status of diagnostic settings for resources"
  value = {
    enabled           = var.enable_diagnostic_settings
    storage_account   = var.enable_diagnostic_settings ? "Enabled" : "Disabled"
    web_app          = var.enable_diagnostic_settings ? "Enabled" : "Disabled"
  }
}

# Random Suffix Used
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Subscription Information
output "subscription_id" {
  description = "Azure subscription ID where resources are deployed"
  value       = data.azurerm_client_config.current.subscription_id
}

output "tenant_id" {
  description = "Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}