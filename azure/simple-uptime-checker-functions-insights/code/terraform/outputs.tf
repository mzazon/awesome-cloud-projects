# Output Values for Simple Uptime Checker Infrastructure
# These outputs provide important information about the deployed resources
# for verification, integration, and management purposes

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where the resource group and resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Azure resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Function App Information
output "function_app_name" {
  description = "Name of the deployed Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "Azure resource ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_url" {
  description = "Default hostname/URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App (without https://)"
  value       = azurerm_linux_function_app.main.default_hostname
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account used by the Function App"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "Azure resource ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob service endpoint for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance for monitoring"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "Azure resource ID of the Application Insights instance"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive)"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (sensitive)"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID of the Application Insights instance"
  value       = azurerm_application_insights.main.app_id
}

# App Service Plan Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan (Consumption plan)"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "Azure resource ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan (should be Y1 for Consumption)"
  value       = azurerm_service_plan.main.sku_name
}

# Monitoring and Alerting Information
output "action_group_name" {
  description = "Name of the Action Group for alert notifications (if alerting enabled)"
  value       = var.enable_alerting ? azurerm_monitor_action_group.main[0].name : null
}

output "action_group_id" {
  description = "Azure resource ID of the Action Group (if alerting enabled)"
  value       = var.enable_alerting ? azurerm_monitor_action_group.main[0].id : null
}

output "alert_rule_name" {
  description = "Name of the downtime detection alert rule (if alerting enabled)"
  value       = var.enable_alerting ? azurerm_monitor_scheduled_query_rules_alert_v2.downtime_alert[0].name : null
}

output "alert_rule_id" {
  description = "Azure resource ID of the alert rule (if alerting enabled)"
  value       = var.enable_alerting ? azurerm_monitor_scheduled_query_rules_alert_v2.downtime_alert[0].id : null
}

# Configuration Information
output "monitored_websites" {
  description = "List of websites being monitored for uptime"
  value       = var.websites_to_monitor
}

output "monitoring_frequency" {
  description = "CRON expression defining how often uptime checks are performed"
  value       = var.monitoring_frequency
}

output "function_timeout_minutes" {
  description = "Function execution timeout in minutes"
  value       = var.function_timeout
}

output "app_insights_retention_days" {
  description = "Number of days Application Insights retains telemetry data"
  value       = var.app_insights_retention_days
}

# Random Suffix for Resource Names
output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.resource_suffix
}

# Environment and Project Information
output "environment" {
  description = "Environment tag applied to all resources"
  value       = var.environment
}

output "project_name" {
  description = "Project name used for resource naming and tagging"
  value       = var.project_name
}

# Quick Access URLs for Management
output "azure_portal_function_app_url" {
  description = "Direct URL to the Function App in Azure Portal"
  value       = "https://portal.azure.com/#@/resource${azurerm_linux_function_app.main.id}"
}

output "azure_portal_app_insights_url" {
  description = "Direct URL to Application Insights in Azure Portal"
  value       = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}"
}

output "azure_portal_resource_group_url" {
  description = "Direct URL to the Resource Group in Azure Portal"
  value       = "https://portal.azure.com/#@/resource${azurerm_resource_group.main.id}"
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources and their key properties"
  value = {
    resource_group = {
      name     = azurerm_resource_group.main.name
      location = azurerm_resource_group.main.location
    }
    function_app = {
      name     = azurerm_linux_function_app.main.name
      url      = "https://${azurerm_linux_function_app.main.default_hostname}"
      runtime  = "nodejs18"
    }
    monitoring = {
      app_insights_name    = azurerm_application_insights.main.name
      retention_days       = var.app_insights_retention_days
      alerting_enabled     = var.enable_alerting
    }
    uptime_monitoring = {
      websites_count      = length(var.websites_to_monitor)
      check_frequency     = var.monitoring_frequency
      timeout_minutes     = var.function_timeout
    }
  }
}

# Cost Estimation Information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (approximate, for planning purposes)"
  value = {
    function_app_consumption = "~$0.10-$2.00"
    application_insights     = "~$2.30-$5.00"
    storage_account         = "~$0.50-$1.00"
    total_estimated         = "~$3.00-$8.00"
    note                    = "Actual costs depend on execution frequency, data retention, and usage patterns"
  }
}