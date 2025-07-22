# Output Values for Azure Cost Anomaly Detection Infrastructure
# This file defines all output values that will be displayed after deployment

# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the created resource group"
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

# Function App Outputs
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_identity_tenant_id" {
  description = "Tenant ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].tenant_id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint URL of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

# Cosmos DB Outputs
output "cosmosdb_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmosdb_endpoint" {
  description = "Endpoint URL of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmosdb_database_name" {
  description = "Name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.main.name
}

output "cosmosdb_daily_costs_container_name" {
  description = "Name of the daily costs container"
  value       = azurerm_cosmosdb_sql_container.daily_costs.name
}

output "cosmosdb_anomaly_results_container_name" {
  description = "Name of the anomaly results container"
  value       = azurerm_cosmosdb_sql_container.anomaly_results.name
}

# Logic App Outputs (conditional)
output "logic_app_name" {
  description = "Name of the Logic App (if enabled)"
  value       = var.logic_app_enabled ? azurerm_logic_app_workflow.main[0].name : null
}

output "logic_app_access_endpoint" {
  description = "Access endpoint of the Logic App (if enabled)"
  value       = var.logic_app_enabled ? azurerm_logic_app_workflow.main[0].access_endpoint : null
}

# Application Insights Outputs
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID of the Application Insights instance"
  value       = azurerm_application_insights.main.app_id
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

# Configuration Outputs
output "anomaly_threshold" {
  description = "Configured anomaly detection threshold percentage"
  value       = var.anomaly_threshold
}

output "lookback_days" {
  description = "Configured lookback period for baseline calculation"
  value       = var.lookback_days
}

output "monitored_subscription_ids" {
  description = "List of monitored subscription IDs"
  value       = var.monitored_subscription_ids
}

# Cost Management Outputs
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for the infrastructure (USD)"
  value = {
    function_app_consumption = "~$0.20 per 1M executions"
    storage_account_lrs      = "~$0.02 per GB"
    cosmos_db_400_ru         = "~$24.00 per month"
    application_insights     = "~$2.30 per GB"
    log_analytics           = "~$2.30 per GB"
    total_estimated         = "~$30-50 per month (low-medium usage)"
  }
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

output "terraform_version" {
  description = "Version of Terraform used for deployment"
  value       = "~> 1.0"
}

# Security Outputs
output "managed_identity_enabled" {
  description = "Whether managed identity is enabled for Function App"
  value       = var.enable_managed_identity
}

output "https_only_enabled" {
  description = "Whether HTTPS only is enabled for Function App"
  value       = var.enable_https_only
}

# Function App Configuration Summary
output "function_app_configuration" {
  description = "Summary of Function App configuration"
  value = {
    runtime_version    = var.function_app_runtime_version
    service_plan_sku   = var.function_app_service_plan_sku
    timeout_minutes    = var.function_timeout_minutes
    managed_identity   = var.enable_managed_identity
    https_only         = var.enable_https_only
  }
}

# Database Configuration Summary
output "cosmosdb_configuration" {
  description = "Summary of Cosmos DB configuration"
  value = {
    consistency_level     = var.cosmosdb_consistency_level
    throughput           = var.cosmosdb_throughput
    automatic_failover   = var.cosmosdb_enable_automatic_failover
    backup_type         = var.cosmosdb_backup_type
  }
}

# Monitoring Configuration Summary
output "monitoring_configuration" {
  description = "Summary of monitoring configuration"
  value = {
    application_insights_retention = var.application_insights_retention_days
    log_analytics_retention       = var.log_analytics_retention_days
    diagnostic_logs_enabled       = var.enable_diagnostic_logs
    sampling_percentage          = var.application_insights_sampling_percentage
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Deploy the Function App code using Azure Functions Core Tools or VS Code",
    "2. Configure notification channels (email, Teams webhook) if not done during deployment",
    "3. Test the cost data collection function manually",
    "4. Verify Cosmos DB containers are populated with cost data",
    "5. Test anomaly detection with sample data",
    "6. Configure Logic App workflows for advanced alerting",
    "7. Set up dashboards in Azure Monitor for cost visualization",
    "8. Review and adjust anomaly thresholds based on your spending patterns"
  ]
}

# Troubleshooting Information
output "troubleshooting_resources" {
  description = "Resources for troubleshooting"
  value = {
    function_app_logs    = "https://portal.azure.com/#@/resource${azurerm_linux_function_app.main.id}/logs"
    application_insights = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}/overview"
    cosmos_db_data_explorer = "https://portal.azure.com/#@/resource${azurerm_cosmosdb_account.main.id}/dataExplorer"
    log_analytics_queries = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}/logs"
  }
}