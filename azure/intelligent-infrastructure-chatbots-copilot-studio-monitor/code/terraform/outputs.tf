# Outputs for Azure Infrastructure Chatbot Solution
# These outputs provide essential information for Azure Copilot Studio integration
# and monitoring configuration

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

# Function App Configuration for Copilot Studio Integration
output "function_app_name" {
  description = "Name of the Azure Functions app for query processing"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_hostname" {
  description = "Default hostname of the Function App for webhook configuration"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "Base URL of the Function App for API endpoint configuration"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "query_processor_endpoint" {
  description = "Complete endpoint URL for the QueryProcessor function (use in Copilot Studio)"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/QueryProcessor"
}

output "function_app_id" {
  description = "Resource ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

# Authentication and Security
output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = var.enable_managed_identity ? azurerm_linux_function_app.main.identity[0].principal_id : null
}

output "function_app_keys_command" {
  description = "Azure CLI command to retrieve function keys for authentication"
  value       = "az functionapp keys list --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_linux_function_app.main.name}"
}

# Log Analytics and Monitoring
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for data queries"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Workspace ID for Log Analytics (use in Function App configuration)"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_resource_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

# Application Insights (if enabled)
output "application_insights_name" {
  description = "Name of the Application Insights resource"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key for telemetry"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string for advanced telemetry"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application Insights application ID for programmatic access"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].app_id : null
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account used by the Function App"
  value       = azurerm_storage_account.functions.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.functions.primary_blob_endpoint
}

# Alert Management
output "action_group_name" {
  description = "Name of the action group for alert management"
  value       = azurerm_monitor_action_group.chatbot_alerts.name
}

output "action_group_id" {
  description = "Resource ID of the action group"
  value       = azurerm_monitor_action_group.chatbot_alerts.id
}

# Configuration for Azure Copilot Studio
output "copilot_studio_configuration" {
  description = "Configuration details for Azure Copilot Studio integration"
  value = {
    function_endpoint     = "https://${azurerm_linux_function_app.main.default_hostname}/api/QueryProcessor"
    workspace_id         = azurerm_log_analytics_workspace.main.workspace_id
    resource_group       = azurerm_resource_group.main.name
    subscription_id      = data.azurerm_client_config.current.subscription_id
    function_app_name    = azurerm_linux_function_app.main.name
    authentication_type  = "function_key"
  }
}

# Deployment Information
output "deployment_info" {
  description = "Important deployment information and next steps"
  value = {
    message = "Azure infrastructure deployed successfully for intelligent chatbot solution"
    next_steps = [
      "Retrieve function keys using: az functionapp keys list --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_linux_function_app.main.name}",
      "Configure Azure Copilot Studio with endpoint: https://${azurerm_linux_function_app.main.default_hostname}/api/QueryProcessor",
      "Test the deployment using the validation commands in the recipe documentation",
      "Set up conversational topics in Azure Copilot Studio Power Platform portal"
    ]
    estimated_monthly_cost = "Approximately $10-50 USD depending on usage (Consumption plan + Log Analytics)"
    security_notes = [
      "Function App uses managed identity for secure Azure Monitor access",
      "Storage account has secure transfer enabled and public access disabled",
      "HTTPS is enforced for all Function App endpoints",
      "Minimum TLS version set to 1.2 for enhanced security"
    ]
  }
}

# Sample KQL Queries for Testing
output "sample_kql_queries" {
  description = "Sample KQL queries for testing the chatbot functionality"
  value = {
    cpu_usage = "Perf | where CounterName == \"% Processor Time\" | where TimeGenerated > ago(1h) | summarize avg(CounterValue) by Computer"
    memory_usage = "Perf | where CounterName == \"Available MBytes\" | where TimeGenerated > ago(1h) | summarize avg(CounterValue) by Computer"
    disk_space = "Perf | where CounterName == \"% Free Space\" | where TimeGenerated > ago(1h) | summarize avg(CounterValue) by Computer"
    heartbeat = "Heartbeat | where TimeGenerated > ago(1h) | summarize count() by Computer"
  }
}

# Resource Tags Applied
output "applied_tags" {
  description = "Tags applied to all resources for governance and cost management"
  value       = var.tags
}