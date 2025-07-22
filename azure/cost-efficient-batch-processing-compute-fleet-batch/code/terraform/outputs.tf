# Output values for Azure Batch and Compute Fleet infrastructure

# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.batch_fleet.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.batch_fleet.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.batch_fleet.location
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account for batch processing"
  value       = azurerm_storage_account.batch_storage.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.batch_storage.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint of the storage account"
  value       = azurerm_storage_account.batch_storage.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.batch_storage.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.batch_storage.primary_access_key
  sensitive   = true
}

# Storage Container Outputs
output "batch_input_container_name" {
  description = "Name of the batch input container"
  value       = azurerm_storage_container.batch_input.name
}

output "batch_output_container_name" {
  description = "Name of the batch output container"
  value       = azurerm_storage_container.batch_output.name
}

# Azure Batch Account Outputs
output "batch_account_name" {
  description = "Name of the Azure Batch account"
  value       = azurerm_batch_account.batch_processing.name
}

output "batch_account_id" {
  description = "ID of the Azure Batch account"
  value       = azurerm_batch_account.batch_processing.id
}

output "batch_account_endpoint" {
  description = "Azure Batch account endpoint URL"
  value       = azurerm_batch_account.batch_processing.account_endpoint
}

output "batch_account_primary_access_key" {
  description = "Primary access key for the Azure Batch account"
  value       = azurerm_batch_account.batch_processing.primary_access_key
  sensitive   = true
}

output "batch_account_secondary_access_key" {
  description = "Secondary access key for the Azure Batch account"
  value       = azurerm_batch_account.batch_processing.secondary_access_key
  sensitive   = true
}

# Batch Pool Outputs
output "batch_pool_id" {
  description = "ID of the created batch pool"
  value       = azurerm_batch_pool.cost_efficient_pool.id
}

output "batch_pool_name" {
  description = "Name of the created batch pool"
  value       = azurerm_batch_pool.cost_efficient_pool.name
}

output "batch_pool_vm_size" {
  description = "VM size used in the batch pool"
  value       = azurerm_batch_pool.cost_efficient_pool.vm_size
}

output "batch_pool_target_dedicated_nodes" {
  description = "Target number of dedicated nodes in the batch pool"
  value       = azurerm_batch_pool.cost_efficient_pool.target_dedicated_nodes
}

output "batch_pool_target_low_priority_nodes" {
  description = "Target number of low priority nodes in the batch pool"
  value       = azurerm_batch_pool.cost_efficient_pool.target_low_priority_nodes
}

# Monitoring Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.batch_monitoring.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.batch_monitoring.id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.batch_monitoring.primary_shared_key
  sensitive   = true
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.batch_monitoring.workspace_id
}

output "application_insights_name" {
  description = "Name of the Application Insights component"
  value       = azurerm_application_insights.batch_insights.name
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = azurerm_application_insights.batch_insights.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = azurerm_application_insights.batch_insights.connection_string
  sensitive   = true
}

# Monitoring and Alerting Outputs
output "cost_alert_action_group_id" {
  description = "ID of the cost alert action group"
  value       = azurerm_monitor_action_group.cost_alerts.id
}

output "cost_alert_action_group_name" {
  description = "Name of the cost alert action group"
  value       = azurerm_monitor_action_group.cost_alerts.name
}

output "high_cpu_alert_id" {
  description = "ID of the high CPU usage alert"
  value       = azurerm_monitor_metric_alert.high_cpu_usage.id
}

output "cost_monitoring_alert_id" {
  description = "ID of the cost monitoring alert"
  value       = azurerm_monitor_scheduled_query_rules_alert_v2.cost_monitoring.id
}

# Configuration Information
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Connection Information for External Applications
output "batch_connection_info" {
  description = "Connection information for Azure Batch"
  value = {
    account_name = azurerm_batch_account.batch_processing.name
    account_endpoint = azurerm_batch_account.batch_processing.account_endpoint
    pool_id = azurerm_batch_pool.cost_efficient_pool.id
    storage_account_name = azurerm_storage_account.batch_storage.name
  }
}

output "monitoring_connection_info" {
  description = "Connection information for monitoring services"
  value = {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.batch_monitoring.workspace_id
    application_insights_instrumentation_key = azurerm_application_insights.batch_insights.instrumentation_key
    action_group_id = azurerm_monitor_action_group.cost_alerts.id
  }
  sensitive = true
}

# Cost Optimization Information
output "cost_optimization_config" {
  description = "Cost optimization configuration details"
  value = {
    spot_capacity_percentage = var.compute_fleet_spot_capacity_percentage
    max_price_per_vm = var.compute_fleet_max_price_per_vm
    auto_scale_enabled = true
    low_priority_nodes_target = var.batch_pool_target_low_priority_nodes
    dedicated_nodes_target = var.batch_pool_target_dedicated_nodes
  }
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployment"
  value = {
    terraform_version = "~> 1.0"
    azurerm_provider_version = "~> 3.0"
    deployment_date = timestamp()
    environment = var.environment
    project_name = var.project_name
  }
}