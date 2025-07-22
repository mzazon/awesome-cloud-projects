# Outputs for the Azure Service Fabric and Application Insights monitoring solution

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# Service Fabric Cluster Information
output "service_fabric_cluster_name" {
  description = "Name of the Service Fabric managed cluster"
  value       = azurerm_service_fabric_managed_cluster.main.name
}

output "service_fabric_cluster_id" {
  description = "ID of the Service Fabric managed cluster"
  value       = azurerm_service_fabric_managed_cluster.main.id
}

output "service_fabric_cluster_endpoint" {
  description = "Service Fabric cluster management endpoint"
  value       = "https://${azurerm_service_fabric_managed_cluster.main.dns_name}:${azurerm_service_fabric_managed_cluster.main.http_gateway_port}"
}

output "service_fabric_cluster_client_connection_endpoint" {
  description = "Service Fabric cluster client connection endpoint"
  value       = "${azurerm_service_fabric_managed_cluster.main.dns_name}:${azurerm_service_fabric_managed_cluster.main.client_connection_port}"
}

output "service_fabric_cluster_fqdn" {
  description = "Fully qualified domain name of the Service Fabric cluster"
  value       = azurerm_service_fabric_managed_cluster.main.dns_name
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application Insights application ID"
  value       = azurerm_application_insights.main.app_id
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# Event Hub Information
output "event_hub_namespace_name" {
  description = "Name of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.main.name
}

output "event_hub_namespace_id" {
  description = "ID of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.main.id
}

output "event_hub_name" {
  description = "Name of the Event Hub"
  value       = azurerm_eventhub.service_events.name
}

output "event_hub_connection_string" {
  description = "Connection string for the Event Hub"
  value       = azurerm_eventhub_authorization_rule.function_app.primary_connection_string
  sensitive   = true
}

output "event_hub_primary_key" {
  description = "Primary key for the Event Hub authorization rule"
  value       = azurerm_eventhub_authorization_rule.function_app.primary_key
  sensitive   = true
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.function_app.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.function_app.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.function_app.primary_blob_endpoint
}

# Service Plan Information
output "service_plan_name" {
  description = "Name of the service plan"
  value       = azurerm_service_plan.function_app.name
}

output "service_plan_id" {
  description = "ID of the service plan"
  value       = azurerm_service_plan.function_app.id
}

# Monitoring and Alerting Information
output "metric_alert_id" {
  description = "ID of the metric alert for cluster health"
  value       = azurerm_monitor_metric_alert.cluster_health.id
}

output "query_alert_id" {
  description = "ID of the scheduled query alert for error rate"
  value       = azurerm_monitor_scheduled_query_rules_alert_v2.high_error_rate.id
}

output "action_group_id" {
  description = "ID of the action group for alerts"
  value       = azurerm_monitor_action_group.main.id
}

output "diagnostic_setting_id" {
  description = "ID of the diagnostic setting for Service Fabric cluster"
  value       = azurerm_monitor_diagnostic_setting.sf_cluster.id
}

# Dashboard Information
output "dashboard_name" {
  description = "Name of the monitoring dashboard"
  value       = azurerm_dashboard.main.name
}

output "dashboard_id" {
  description = "ID of the monitoring dashboard"
  value       = azurerm_dashboard.main.id
}

output "dashboard_url" {
  description = "URL to access the monitoring dashboard"
  value       = "https://portal.azure.com/#@/dashboard/arm${azurerm_dashboard.main.id}"
}

# Solution Information
output "service_fabric_solution_id" {
  description = "ID of the Service Fabric Log Analytics solution"
  value       = azurerm_log_analytics_solution.service_fabric.id
}

output "application_insights_solution_id" {
  description = "ID of the Application Insights Log Analytics solution"
  value       = azurerm_log_analytics_solution.application_insights.id
}

# Useful URLs and Connection Information
output "azure_portal_resource_group_url" {
  description = "URL to the resource group in Azure portal"
  value       = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}"
}

output "service_fabric_explorer_url" {
  description = "URL to the Service Fabric Explorer"
  value       = "https://${azurerm_service_fabric_managed_cluster.main.dns_name}:${azurerm_service_fabric_managed_cluster.main.http_gateway_port}/Explorer"
}

output "application_insights_portal_url" {
  description = "URL to Application Insights in Azure portal"
  value       = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}"
}

output "log_analytics_portal_url" {
  description = "URL to Log Analytics workspace in Azure portal"
  value       = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}"
}

# Configuration values for applications
output "distributed_tracing_config" {
  description = "Configuration object for distributed tracing setup"
  value = {
    applicationInsights = {
      connectionString = azurerm_application_insights.main.connection_string
      instrumentationKey = azurerm_application_insights.main.instrumentation_key
      sampling = {
        percentage = 100
        excludedTypes = "Trace"
      }
      enableLiveMetrics = true
      enableDependencyTracking = true
    }
    eventHub = {
      connectionString = azurerm_eventhub_authorization_rule.function_app.primary_connection_string
      eventHubName = azurerm_eventhub.service_events.name
    }
    correlationSettings = {
      enableW3CTraceContext = true
      enableRequestIdGeneration = true
      enableActivityTracking = true
    }
  }
  sensitive = true
}

# Summary information
output "deployment_summary" {
  description = "Summary of the deployed resources"
  value = {
    resource_group = azurerm_resource_group.main.name
    location = azurerm_resource_group.main.location
    service_fabric_cluster = azurerm_service_fabric_managed_cluster.main.name
    application_insights = azurerm_application_insights.main.name
    log_analytics_workspace = azurerm_log_analytics_workspace.main.name
    event_hub_namespace = azurerm_eventhub_namespace.main.name
    function_app = azurerm_linux_function_app.main.name
    storage_account = azurerm_storage_account.function_app.name
    dashboard = azurerm_dashboard.main.name
    alerts_configured = 2
    solutions_deployed = 2
  }
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Random suffix used for unique naming
output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# Environment and tagging information
output "environment" {
  description = "Environment name used for tagging"
  value       = var.environment
}

output "applied_tags" {
  description = "Tags applied to all resources"
  value       = local.common_tags
}