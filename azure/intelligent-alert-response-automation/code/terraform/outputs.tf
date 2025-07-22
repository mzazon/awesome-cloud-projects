# Outputs for Intelligent Alert Response System with Azure Monitor Workbooks and Azure Functions
# These outputs provide important information about the deployed resources for integration,
# monitoring, and operational use. They include connection details, endpoints, and resource identifiers.

output "resource_group_name" {
  description = "Name of the resource group containing all resources"
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

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account used by Azure Functions"
  value       = azurerm_storage_account.functions.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.functions.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint of the storage account"
  value       = azurerm_storage_account.functions.primary_blob_endpoint
}

# Key Vault Outputs
output "key_vault_name" {
  description = "Name of the Key Vault storing secrets"
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

# Cosmos DB Outputs
output "cosmos_db_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_db_account_id" {
  description = "ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.id
}

output "cosmos_db_endpoint" {
  description = "Endpoint URL of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_db_database_name" {
  description = "Name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.main.name
}

output "cosmos_db_container_name" {
  description = "Name of the Cosmos DB container for alert states"
  value       = azurerm_cosmosdb_sql_container.alert_states.name
}

output "cosmos_db_connection_strings" {
  description = "Connection strings for Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.connection_strings
  sensitive   = true
}

# Event Grid Outputs
output "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.name
}

output "event_grid_topic_id" {
  description = "ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.id
}

output "event_grid_endpoint" {
  description = "Endpoint URL of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.endpoint
}

output "event_grid_primary_access_key" {
  description = "Primary access key for Event Grid topic"
  value       = azurerm_eventgrid_topic.main.primary_access_key
  sensitive   = true
}

output "event_grid_secondary_access_key" {
  description = "Secondary access key for Event Grid topic"
  value       = azurerm_eventgrid_topic.main.secondary_access_key
  sensitive   = true
}

# Azure Functions Outputs
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the Azure Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_tenant_id" {
  description = "Tenant ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].tenant_id
}

# Service Plan Outputs
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "service_plan_sku_name" {
  description = "SKU name of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# Logic App Outputs
output "logic_app_name" {
  description = "Name of the Logic App"
  value       = azurerm_logic_app_workflow.main.name
}

output "logic_app_id" {
  description = "ID of the Logic App"
  value       = azurerm_logic_app_workflow.main.id
}

output "logic_app_access_endpoint" {
  description = "Access endpoint URL of the Logic App"
  value       = azurerm_logic_app_workflow.main.access_endpoint
  sensitive   = true
}

# Log Analytics Outputs
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
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Application Insights Outputs
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
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

# Monitor Workbook Outputs
output "workbook_name" {
  description = "Name of the Azure Monitor Workbook"
  value       = azurerm_application_insights_workbook.main.name
}

output "workbook_id" {
  description = "ID of the Azure Monitor Workbook"
  value       = azurerm_application_insights_workbook.main.id
}

output "workbook_display_name" {
  description = "Display name of the Azure Monitor Workbook"
  value       = azurerm_application_insights_workbook.main.display_name
}

# Test Alert Resources Outputs
output "test_action_group_name" {
  description = "Name of the test action group"
  value       = azurerm_monitor_action_group.test.name
}

output "test_action_group_id" {
  description = "ID of the test action group"
  value       = azurerm_monitor_action_group.test.id
}

output "test_metric_alert_name" {
  description = "Name of the test metric alert rule"
  value       = azurerm_monitor_metric_alert.test.name
}

output "test_metric_alert_id" {
  description = "ID of the test metric alert rule"
  value       = azurerm_monitor_metric_alert.test.id
}

# Event Grid Subscriptions Outputs
output "function_event_subscription_name" {
  description = "Name of the Event Grid subscription for Function App"
  value       = azurerm_eventgrid_event_subscription.function_subscription.name
}

output "function_event_subscription_id" {
  description = "ID of the Event Grid subscription for Function App"
  value       = azurerm_eventgrid_event_subscription.function_subscription.id
}

output "logic_event_subscription_name" {
  description = "Name of the Event Grid subscription for Logic App"
  value       = azurerm_eventgrid_event_subscription.logic_subscription.name
}

output "logic_event_subscription_id" {
  description = "ID of the Event Grid subscription for Logic App"
  value       = azurerm_eventgrid_event_subscription.logic_subscription.id
}

# Portal URLs for easy access
output "azure_portal_urls" {
  description = "URLs for accessing resources in Azure Portal"
  value = {
    resource_group    = "https://portal.azure.com/#@/resource${azurerm_resource_group.main.id}"
    function_app      = "https://portal.azure.com/#@/resource${azurerm_linux_function_app.main.id}"
    logic_app         = "https://portal.azure.com/#@/resource${azurerm_logic_app_workflow.main.id}"
    cosmos_db         = "https://portal.azure.com/#@/resource${azurerm_cosmosdb_account.main.id}"
    key_vault         = "https://portal.azure.com/#@/resource${azurerm_key_vault.main.id}"
    event_grid        = "https://portal.azure.com/#@/resource${azurerm_eventgrid_topic.main.id}"
    workbook          = "https://portal.azure.com/#@/resource${azurerm_application_insights_workbook.main.id}"
    log_analytics     = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}"
    application_insights = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}"
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    resource_group_name = azurerm_resource_group.main.name
    location           = azurerm_resource_group.main.location
    environment        = var.environment
    resources_deployed = {
      storage_account        = azurerm_storage_account.functions.name
      key_vault            = azurerm_key_vault.main.name
      cosmos_db_account    = azurerm_cosmosdb_account.main.name
      event_grid_topic     = azurerm_eventgrid_topic.main.name
      function_app         = azurerm_linux_function_app.main.name
      logic_app            = azurerm_logic_app_workflow.main.name
      log_analytics        = azurerm_log_analytics_workspace.main.name
      application_insights = azurerm_application_insights.main.name
      workbook             = azurerm_application_insights_workbook.main.name
    }
    purpose = "Intelligent Alert Response System with automated processing, workbook visualization, and event-driven notifications"
  }
}

# Connection Information for Integration
output "integration_endpoints" {
  description = "Endpoints and connection information for system integration"
  value = {
    event_grid_endpoint     = azurerm_eventgrid_topic.main.endpoint
    function_app_url        = "https://${azurerm_linux_function_app.main.default_hostname}"
    logic_app_trigger_url   = azurerm_logic_app_workflow.main.access_endpoint
    cosmos_db_endpoint      = azurerm_cosmosdb_account.main.endpoint
    key_vault_uri          = azurerm_key_vault.main.vault_uri
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.workspace_id
  }
  sensitive = true
}

# Resource Tags Summary
output "resource_tags" {
  description = "Tags applied to all resources"
  value = {
    purpose     = "intelligent-alerts"
    environment = var.environment
    project     = "alert-response-system"
  }
}

# Security and Access Information
output "security_info" {
  description = "Security-related information for the deployed resources"
  value = {
    key_vault_rbac_enabled = azurerm_key_vault.main.enable_rbac_authorization
    storage_https_only     = azurerm_storage_account.functions.https_traffic_only_enabled
    function_managed_identity = azurerm_linux_function_app.main.identity[0].type
    cosmos_db_consistency_level = azurerm_cosmosdb_account.main.consistency_policy[0].consistency_level
  }
}

# Monitoring and Diagnostics
output "monitoring_info" {
  description = "Monitoring and diagnostics configuration"
  value = {
    log_analytics_retention_days = azurerm_log_analytics_workspace.main.retention_in_days
    application_insights_type    = azurerm_application_insights.main.application_type
    cosmos_db_throughput        = azurerm_cosmosdb_sql_container.alert_states.throughput
  }
}

# Cost Management Information
output "cost_info" {
  description = "Cost-related information for the deployed resources"
  value = {
    service_plan_sku = azurerm_service_plan.main.sku_name
    storage_tier     = azurerm_storage_account.functions.account_tier
    storage_replication = azurerm_storage_account.functions.account_replication_type
    cosmos_db_throughput = azurerm_cosmosdb_sql_container.alert_states.throughput
    log_analytics_sku = azurerm_log_analytics_workspace.main.sku
  }
}