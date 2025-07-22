# Resource Group outputs
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Container Apps Environment outputs
output "container_app_environment_name" {
  description = "Name of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.name
}

output "container_app_environment_id" {
  description = "ID of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_app_environment_fqdn" {
  description = "FQDN of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.default_domain
}

# Container Apps Job outputs
output "unit_test_job_name" {
  description = "Name of the unit test job"
  value       = azurerm_container_app_job.unit_test.name
}

output "unit_test_job_id" {
  description = "ID of the unit test job"
  value       = azurerm_container_app_job.unit_test.id
}

output "integration_test_job_name" {
  description = "Name of the integration test job"
  value       = azurerm_container_app_job.integration_test.name
}

output "integration_test_job_id" {
  description = "ID of the integration test job"
  value       = azurerm_container_app_job.integration_test.id
}

output "performance_test_job_name" {
  description = "Name of the performance test job"
  value       = azurerm_container_app_job.performance_test.name
}

output "performance_test_job_id" {
  description = "ID of the performance test job"
  value       = azurerm_container_app_job.performance_test.id
}

output "security_test_job_name" {
  description = "Name of the security test job"
  value       = azurerm_container_app_job.security_test.name
}

output "security_test_job_id" {
  description = "ID of the security test job"
  value       = azurerm_container_app_job.security_test.id
}

# Azure Load Testing outputs
output "load_test_name" {
  description = "Name of the Azure Load Testing resource"
  value       = azurerm_load_test.main.name
}

output "load_test_id" {
  description = "ID of the Azure Load Testing resource"
  value       = azurerm_load_test.main.id
}

output "load_test_data_plane_uri" {
  description = "Data plane URI of the Azure Load Testing resource"
  value       = azurerm_load_test.main.dataplane_uri
}

# Log Analytics Workspace outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Storage Account outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string of the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key of the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

# Storage Container outputs
output "load_test_scripts_container_name" {
  description = "Name of the load test scripts container"
  value       = azurerm_storage_container.load_test_scripts.name
}

output "monitoring_templates_container_name" {
  description = "Name of the monitoring templates container"
  value       = azurerm_storage_container.monitoring_templates.name
}

# Application Insights outputs
output "application_insights_name" {
  description = "Name of the Application Insights resource"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights resource"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key of Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string of Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# Monitoring outputs
output "action_group_name" {
  description = "Name of the action group"
  value       = azurerm_monitor_action_group.main.name
}

output "action_group_id" {
  description = "ID of the action group"
  value       = azurerm_monitor_action_group.main.id
}

output "job_failure_alert_name" {
  description = "Name of the job failure alert"
  value       = azurerm_monitor_metric_alert.job_failure.name
}

output "job_failure_alert_id" {
  description = "ID of the job failure alert"
  value       = azurerm_monitor_metric_alert.job_failure.id
}

# Deployment information
output "deployment_info" {
  description = "Deployment information and next steps"
  value = {
    resource_group        = azurerm_resource_group.main.name
    location             = azurerm_resource_group.main.location
    container_environment = azurerm_container_app_environment.main.name
    load_testing_resource = azurerm_load_test.main.name
    jobs_created = [
      azurerm_container_app_job.unit_test.name,
      azurerm_container_app_job.integration_test.name,
      azurerm_container_app_job.performance_test.name,
      azurerm_container_app_job.security_test.name
    ]
    monitoring_workspace = azurerm_log_analytics_workspace.main.name
    storage_account      = azurerm_storage_account.main.name
    next_steps = [
      "Configure Azure DevOps pipeline using the provided template",
      "Upload JMeter scripts to the load-test-scripts container",
      "Configure Container Apps Jobs with your specific test frameworks",
      "Set up alerts and notifications in Azure Monitor",
      "Review and customize job configurations based on your requirements"
    ]
  }
}

# CLI commands for validation
output "validation_commands" {
  description = "Azure CLI commands for validating the deployment"
  value = {
    check_resource_group = "az group show --name ${azurerm_resource_group.main.name}"
    list_container_jobs  = "az containerapp job list --resource-group ${azurerm_resource_group.main.name} --query '[].{name:name,status:properties.provisioningState}' --output table"
    check_load_testing   = "az load show --name ${azurerm_load_test.main.name} --resource-group ${azurerm_resource_group.main.name}"
    start_unit_test      = "az containerapp job start --name ${azurerm_container_app_job.unit_test.name} --resource-group ${azurerm_resource_group.main.name}"
    monitor_logs         = "az monitor log-analytics query --workspace ${azurerm_log_analytics_workspace.main.workspace_id} --analytics-query 'ContainerAppConsoleLogs_CL | where TimeGenerated > ago(1h) | take 10'"
  }
}