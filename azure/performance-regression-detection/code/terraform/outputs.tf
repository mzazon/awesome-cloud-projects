# Outputs for Azure Performance Regression Detection Infrastructure

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
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Load Testing Information
output "load_test_name" {
  description = "Name of the Azure Load Testing resource"
  value       = azurerm_load_test.main.name
}

output "load_test_id" {
  description = "ID of the Azure Load Testing resource"
  value       = azurerm_load_test.main.id
}

output "load_test_data_plane_uri" {
  description = "Data plane URI for the Azure Load Testing resource"
  value       = azurerm_load_test.main.dataplane_uri
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

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights resource"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights resource"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = azurerm_application_insights.main.app_id
}

# Container Registry Information
output "container_registry_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_id" {
  description = "ID of the Azure Container Registry"
  value       = azurerm_container_registry.main.id
}

output "container_registry_login_server" {
  description = "Login server URL for the Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_admin_username" {
  description = "Admin username for the Azure Container Registry"
  value       = azurerm_container_registry.main.admin_username
}

output "container_registry_admin_password" {
  description = "Admin password for the Azure Container Registry"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

# Container Apps Information
output "container_app_environment_name" {
  description = "Name of the Container Apps environment"
  value       = azurerm_container_app_environment.main.name
}

output "container_app_environment_id" {
  description = "ID of the Container Apps environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_app_name" {
  description = "Name of the Container App"
  value       = azurerm_container_app.main.name
}

output "container_app_id" {
  description = "ID of the Container App"
  value       = azurerm_container_app.main.id
}

output "container_app_fqdn" {
  description = "Fully qualified domain name of the Container App"
  value       = azurerm_container_app.main.ingress[0].fqdn
}

output "container_app_url" {
  description = "Complete URL of the Container App"
  value       = "https://${azurerm_container_app.main.ingress[0].fqdn}"
}

# Monitoring Information
output "action_group_id" {
  description = "ID of the monitoring action group"
  value       = var.enable_monitoring_alerts ? azurerm_monitor_action_group.main[0].id : null
}

output "response_time_alert_id" {
  description = "ID of the response time alert rule"
  value       = var.enable_monitoring_alerts ? azurerm_monitor_metric_alert.response_time[0].id : null
}

output "error_rate_alert_id" {
  description = "ID of the error rate alert rule"
  value       = var.enable_monitoring_alerts ? azurerm_monitor_metric_alert.error_rate[0].id : null
}

# Workbook Information
output "performance_workbook_id" {
  description = "ID of the performance monitoring workbook"
  value       = var.create_performance_workbook ? azurerm_application_insights_workbook.performance_dashboard[0].id : null
}

output "performance_workbook_name" {
  description = "Name of the performance monitoring workbook"
  value       = var.create_performance_workbook ? azurerm_application_insights_workbook.performance_dashboard[0].name : null
}

# Configuration Templates
output "load_test_config_content" {
  description = "Generated load test configuration content"
  value       = var.create_sample_load_test ? local.load_test_config_content : null
}

output "jmeter_test_script_content" {
  description = "Generated JMeter test script content"
  value       = var.create_sample_load_test ? local.jmeter_test_script_content : null
}

output "azure_pipeline_content" {
  description = "Generated Azure DevOps pipeline content"
  value       = var.create_sample_load_test ? local.azure_pipeline_content : null
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group           = azurerm_resource_group.main.name
    load_testing_resource   = azurerm_load_test.main.name
    container_app_url       = "https://${azurerm_container_app.main.ingress[0].fqdn}"
    monitoring_enabled      = var.enable_monitoring_alerts
    workbook_created        = var.create_performance_workbook
    sample_tests_created    = var.create_sample_load_test
  }
}

# Azure CLI Commands for Quick Access
output "useful_commands" {
  description = "Useful Azure CLI commands for managing the deployed resources"
  value = {
    view_load_test = "az load show --name ${azurerm_load_test.main.name} --resource-group ${azurerm_resource_group.main.name}"
    view_container_app = "az containerapp show --name ${azurerm_container_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
    view_logs = "az monitor log-analytics query --workspace ${azurerm_log_analytics_workspace.main.workspace_id} --analytics-query 'requests | limit 100'"
    test_app = "curl -s https://${azurerm_container_app.main.ingress[0].fqdn}"
  }
}

# Performance Testing URLs
output "performance_testing_urls" {
  description = "URLs for performance testing and monitoring"
  value = {
    application_url = "https://${azurerm_container_app.main.ingress[0].fqdn}"
    azure_portal_load_testing = "https://portal.azure.com/#resource${azurerm_load_test.main.id}"
    azure_portal_app_insights = "https://portal.azure.com/#resource${azurerm_application_insights.main.id}"
    azure_portal_container_app = "https://portal.azure.com/#resource${azurerm_container_app.main.id}"
  }
}

# Resource Tags
output "resource_tags" {
  description = "Tags applied to all resources"
  value       = var.tags
}

# Random Suffix (for reference)
output "random_suffix" {
  description = "Random suffix used in resource names"
  value       = random_string.suffix.result
}