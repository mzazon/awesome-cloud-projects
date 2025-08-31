# Output values for the Azure Static Web Apps service status infrastructure
# These outputs provide essential information for deployment verification and integration

# Resource Group Information
output "resource_group_name" {
  description = "The name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "The resource ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "The Azure region where resources were deployed"
  value       = azurerm_resource_group.main.location
}

# Static Web App Information
output "static_web_app_name" {
  description = "The name of the created Static Web App"
  value       = azurerm_static_web_app.status_page.name
}

output "static_web_app_id" {
  description = "The resource ID of the Static Web App"
  value       = azurerm_static_web_app.status_page.id
}

output "static_web_app_url" {
  description = "The default URL of the Static Web App (primary endpoint for the status page)"
  value       = "https://${azurerm_static_web_app.status_page.default_host_name}"
}

output "static_web_app_hostname" {
  description = "The default hostname of the Static Web App"
  value       = azurerm_static_web_app.status_page.default_host_name
}

# API and Functions Information
output "api_endpoint" {
  description = "The API endpoint URL for status checks"
  value       = "https://${azurerm_static_web_app.status_page.default_host_name}/api/status"
}

output "functions_runtime" {
  description = "The configured runtime version for Azure Functions"
  value       = var.functions_runtime
}

# Deployment Information
output "deployment_token" {
  description = "The deployment token for Static Web App (sensitive - use for CI/CD)"
  value       = azurerm_static_web_app.status_page.api_key
  sensitive   = true
}

# Custom Domain Information (when enabled)
output "custom_domain_validation_token" {
  description = "DNS TXT validation token for custom domain (when custom domains are enabled)"
  value       = var.enable_custom_domains && var.sku_tier == "Standard" ? azurerm_static_web_app_custom_domain.main[0].validation_token : null
}

output "custom_domain_name" {
  description = "The configured custom domain name (when custom domains are enabled)"
  value       = var.enable_custom_domains && var.sku_tier == "Standard" ? azurerm_static_web_app_custom_domain.main[0].domain_name : null
}

# Monitoring and Observability Information
output "application_insights_name" {
  description = "The name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

# Storage Account Information
output "storage_account_name" {
  description = "The name of the storage account for persistent data"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "The primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_connection_string" {
  description = "The connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "status_history_container_name" {
  description = "The name of the storage container for status history"
  value       = azurerm_storage_container.status_history.name
}

output "status_logs_table_name" {
  description = "The name of the storage table for status logs"
  value       = azurerm_storage_table.status_logs.name
}

# Configuration Information
output "monitored_services" {
  description = "The list of services being monitored for status"
  value       = var.monitored_services
}

output "environment" {
  description = "The deployment environment"
  value       = var.environment
}

output "sku_tier" {
  description = "The SKU tier of the Static Web App"
  value       = var.sku_tier
}

# Alerting Information
output "action_group_name" {
  description = "The name of the monitor action group for alerts"
  value       = azurerm_monitor_action_group.main.name
}

output "availability_alert_name" {
  description = "The name of the availability metric alert"
  value       = azurerm_monitor_metric_alert.availability.name
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Instructions for deploying the application code"
  value = <<-EOT
    To deploy your application code to this Static Web App:
    
    1. Install the Azure Static Web Apps CLI:
       npm install -g @azure/static-web-apps-cli
    
    2. Deploy using the deployment token:
       swa deploy ./public --api-location ./api --deployment-token "${azurerm_static_web_app.status_page.api_key}"
    
    3. Access your status page at:
       ${azurerm_static_web_app.status_page.default_host_name}
    
    4. Test the API endpoint:
       curl https://${azurerm_static_web_app.status_page.default_host_name}/api/status
  EOT
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the deployed resources"
  value = <<-EOT
    Estimated Monthly Costs (USD):
    - Static Web App (${var.sku_tier}): ${var.sku_tier == "Free" ? "$0" : "$9"}
    - Application Insights: $0-5 (based on data volume)
    - Log Analytics: $0-2 (based on data retention)
    - Storage Account: $0-1 (minimal usage)
    - Total Estimated: ${var.sku_tier == "Free" ? "$0-8" : "$10-17"} per month
    
    Note: Costs may vary based on actual usage and Azure region pricing.
  EOT
}