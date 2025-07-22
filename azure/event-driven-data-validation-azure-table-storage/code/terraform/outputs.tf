# Outputs for Azure Real-Time Data Validation Workflow
# This file defines all output values that provide important information
# about the deployed infrastructure resources

# ============================================================================
# Resource Group Outputs
# ============================================================================

output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the resource group containing all resources"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# ============================================================================
# Storage Account Outputs
# ============================================================================

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_table_endpoint" {
  description = "Table service endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_table_endpoint
}

output "storage_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "table_names" {
  description = "Names of the created tables"
  value       = [for table in azurerm_storage_table.tables : table.name]
}

# ============================================================================
# Event Grid Outputs
# ============================================================================

output "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.name
}

output "event_grid_topic_id" {
  description = "ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.id
}

output "event_grid_topic_endpoint" {
  description = "Endpoint URL of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.endpoint
}

output "event_grid_topic_hostname" {
  description = "Hostname of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.hostname
}

output "event_grid_topic_access_key" {
  description = "Primary access key for the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.primary_access_key
  sensitive   = true
}

output "event_grid_system_topic_name" {
  description = "Name of the Event Grid system topic for storage events"
  value       = azurerm_eventgrid_system_topic.storage.name
}

output "event_grid_system_topic_id" {
  description = "ID of the Event Grid system topic for storage events"
  value       = azurerm_eventgrid_system_topic.storage.id
}

# ============================================================================
# Function App Outputs
# ============================================================================

output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "URL of the Function App"
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

output "function_service_plan_name" {
  description = "Name of the Function App service plan"
  value       = azurerm_service_plan.function_app.name
}

output "function_service_plan_id" {
  description = "ID of the Function App service plan"
  value       = azurerm_service_plan.function_app.id
}

# ============================================================================
# Logic App Outputs
# ============================================================================

output "logic_app_name" {
  description = "Name of the Logic App"
  value       = azurerm_logic_app_standard.main.name
}

output "logic_app_id" {
  description = "ID of the Logic App"
  value       = azurerm_logic_app_standard.main.id
}

output "logic_app_default_hostname" {
  description = "Default hostname of the Logic App"
  value       = azurerm_logic_app_standard.main.default_hostname
}

output "logic_app_url" {
  description = "URL of the Logic App"
  value       = "https://${azurerm_logic_app_standard.main.default_hostname}"
}

output "logic_app_principal_id" {
  description = "Principal ID of the Logic App's managed identity"
  value       = azurerm_logic_app_standard.main.identity[0].principal_id
}

output "logic_app_tenant_id" {
  description = "Tenant ID of the Logic App's managed identity"
  value       = azurerm_logic_app_standard.main.identity[0].tenant_id
}

output "logic_app_service_plan_name" {
  description = "Name of the Logic App service plan"
  value       = azurerm_service_plan.logic_app.name
}

output "logic_app_service_plan_id" {
  description = "ID of the Logic App service plan"
  value       = azurerm_service_plan.logic_app.id
}

# ============================================================================
# Monitoring Outputs
# ============================================================================

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key of the Application Insights instance"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string of the Application Insights instance"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "App ID of the Application Insights instance"
  value       = azurerm_application_insights.main.app_id
}

# ============================================================================
# Event Grid Subscription Outputs
# ============================================================================

output "function_event_subscription_name" {
  description = "Name of the Function App Event Grid subscription"
  value       = azurerm_eventgrid_system_topic_event_subscription.function_subscription.name
}

output "function_event_subscription_id" {
  description = "ID of the Function App Event Grid subscription"
  value       = azurerm_eventgrid_system_topic_event_subscription.function_subscription.id
}

output "logic_app_event_subscription_name" {
  description = "Name of the Logic App Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.logic_app_subscription.name
}

output "logic_app_event_subscription_id" {
  description = "ID of the Logic App Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.logic_app_subscription.id
}

# ============================================================================
# Security and Access Outputs
# ============================================================================

output "dead_letter_container_name" {
  description = "Name of the dead letter storage container"
  value       = azurerm_storage_container.dead_letters.name
}

output "dead_letter_container_url" {
  description = "URL of the dead letter storage container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.dead_letters.name}"
}

# ============================================================================
# Monitoring and Alerting Outputs
# ============================================================================

output "monitor_action_group_name" {
  description = "Name of the monitoring action group"
  value       = azurerm_monitor_action_group.main.name
}

output "monitor_action_group_id" {
  description = "ID of the monitoring action group"
  value       = azurerm_monitor_action_group.main.id
}

output "function_failure_alert_name" {
  description = "Name of the Function App failure alert"
  value       = azurerm_monitor_metric_alert.function_failures.name
}

output "function_failure_alert_id" {
  description = "ID of the Function App failure alert"
  value       = azurerm_monitor_metric_alert.function_failures.id
}

output "eventgrid_failure_alert_name" {
  description = "Name of the Event Grid failure alert"
  value       = azurerm_monitor_metric_alert.eventgrid_failures.name
}

output "eventgrid_failure_alert_id" {
  description = "ID of the Event Grid failure alert"
  value       = azurerm_monitor_metric_alert.eventgrid_failures.id
}

# ============================================================================
# Configuration Outputs
# ============================================================================

output "configuration_summary" {
  description = "Summary of key configuration values"
  value = {
    project_name      = var.project_name
    environment       = var.environment
    location          = var.location
    function_runtime  = var.function_app_runtime
    function_version  = var.function_app_runtime_version
    storage_tier      = var.storage_account_tier
    storage_replication = var.storage_account_replication_type
    monitoring_enabled = var.enable_advanced_monitoring
    https_only        = var.enable_https_only
    backup_enabled    = var.enable_backup
  }
}

# ============================================================================
# Deployment Information
# ============================================================================

output "deployment_info" {
  description = "Information about the deployment"
  value = {
    terraform_version    = "> 1.0"
    azurerm_version     = "~> 3.0"
    resource_count      = "25+"
    estimated_monthly_cost = "$15-30 (development)"
    deployment_time     = "5-10 minutes"
  }
}

# ============================================================================
# Quick Start Commands
# ============================================================================

output "quick_start_commands" {
  description = "Quick start commands for testing the deployment"
  value = {
    # Test Function App
    test_function_app = "curl -X GET https://${azurerm_linux_function_app.main.default_hostname}"
    
    # Test Logic App
    test_logic_app = "curl -X GET https://${azurerm_logic_app_standard.main.default_hostname}"
    
    # View logs
    view_logs = "az monitor log-analytics query -w ${azurerm_log_analytics_workspace.main.workspace_id} --analytics-query 'requests | limit 10'"
    
    # Test storage connection
    test_storage = "az storage table list --connection-string '${azurerm_storage_account.main.primary_connection_string}'"
    
    # Monitor Event Grid
    monitor_eventgrid = "az eventgrid topic show --name ${azurerm_eventgrid_topic.main.name} --resource-group ${azurerm_resource_group.main.name}"
  }
  
  # Mark as sensitive since it contains connection strings
  sensitive = true
}

# ============================================================================
# Resource URLs for Easy Access
# ============================================================================

output "resource_urls" {
  description = "URLs for accessing deployed resources"
  value = {
    # Azure Portal URLs
    resource_group_url = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/overview"
    storage_account_url = "https://portal.azure.com/#@/resource${azurerm_storage_account.main.id}/overview"
    function_app_url = "https://portal.azure.com/#@/resource${azurerm_linux_function_app.main.id}/overview"
    logic_app_url = "https://portal.azure.com/#@/resource${azurerm_logic_app_standard.main.id}/overview"
    event_grid_url = "https://portal.azure.com/#@/resource${azurerm_eventgrid_topic.main.id}/overview"
    application_insights_url = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}/overview"
    log_analytics_url = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}/overview"
    
    # Direct service URLs
    function_app_service_url = "https://${azurerm_linux_function_app.main.default_hostname}"
    logic_app_service_url = "https://${azurerm_logic_app_standard.main.default_hostname}"
  }
}