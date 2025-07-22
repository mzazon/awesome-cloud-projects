# Resource Group Information
output "resource_group_id" {
  description = "The ID of the resource group containing all migration resources"
  value       = azurerm_resource_group.migration.id
}

output "resource_group_name" {
  description = "The name of the resource group containing all migration resources"
  value       = azurerm_resource_group.migration.name
}

output "resource_group_location" {
  description = "The location of the resource group"
  value       = azurerm_resource_group.migration.location
}

# Storage Account Information
output "storage_account_id" {
  description = "The ID of the target storage account"
  value       = azurerm_storage_account.target.id
}

output "storage_account_name" {
  description = "The name of the target storage account"
  value       = azurerm_storage_account.target.name
}

output "storage_account_primary_endpoint" {
  description = "The primary blob endpoint of the target storage account"
  value       = azurerm_storage_account.target.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "The primary access key of the target storage account"
  value       = azurerm_storage_account.target.primary_access_key
  sensitive   = true
}

output "storage_account_connection_string" {
  description = "The connection string for the target storage account"
  value       = azurerm_storage_account.target.primary_connection_string
  sensitive   = true
}

# Storage Container Information
output "target_container_name" {
  description = "The name of the target storage container"
  value       = azurerm_storage_container.target.name
}

output "target_container_url" {
  description = "The URL of the target storage container"
  value       = "${azurerm_storage_account.target.primary_blob_endpoint}${azurerm_storage_container.target.name}"
}

# Storage Mover Information
output "storage_mover_id" {
  description = "The ID of the Storage Mover resource"
  value       = azurerm_resource_group_template_deployment.storage_mover.id
}

output "storage_mover_name" {
  description = "The name of the Storage Mover resource"
  value       = local.storage_mover_name
}

# Log Analytics Workspace Information
output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.migration.id
}

output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.migration.name
}

output "log_analytics_workspace_customer_id" {
  description = "The customer ID (workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.migration.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "The primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.migration.primary_shared_key
  sensitive   = true
}

# Application Insights Information
output "application_insights_id" {
  description = "The ID of the Application Insights resource"
  value       = azurerm_application_insights.migration.id
}

output "application_insights_name" {
  description = "The name of the Application Insights resource"
  value       = azurerm_application_insights.migration.name
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key of the Application Insights resource"
  value       = azurerm_application_insights.migration.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The connection string of the Application Insights resource"
  value       = azurerm_application_insights.migration.connection_string
  sensitive   = true
}

# Action Group Information
output "action_group_id" {
  description = "The ID of the action group for migration alerts"
  value       = azurerm_monitor_action_group.migration_alerts.id
}

output "action_group_name" {
  description = "The name of the action group for migration alerts"
  value       = azurerm_monitor_action_group.migration_alerts.name
}

# Logic App Information (conditional)
output "logic_app_id" {
  description = "The ID of the Logic App (if enabled)"
  value       = var.enable_logic_app ? azurerm_logic_app_standard.migration[0].id : null
}

output "logic_app_name" {
  description = "The name of the Logic App (if enabled)"
  value       = var.enable_logic_app ? azurerm_logic_app_standard.migration[0].name : null
}

output "logic_app_default_hostname" {
  description = "The default hostname of the Logic App (if enabled)"
  value       = var.enable_logic_app ? azurerm_logic_app_standard.migration[0].default_hostname : null
}

output "service_plan_id" {
  description = "The ID of the service plan for Logic App (if enabled)"
  value       = var.enable_logic_app ? azurerm_service_plan.logic_app[0].id : null
}

# Alert Information
output "migration_failure_alert_id" {
  description = "The ID of the migration failure alert"
  value       = azurerm_monitor_metric_alert.migration_failure.id
}

output "migration_success_alert_id" {
  description = "The ID of the migration success alert"
  value       = azurerm_monitor_metric_alert.migration_success.id
}

output "high_transfer_rate_alert_id" {
  description = "The ID of the high transfer rate alert"
  value       = azurerm_monitor_metric_alert.high_transfer_rate.id
}

# Azure Subscription Information
output "subscription_id" {
  description = "The ID of the Azure subscription"
  value       = data.azurerm_subscription.current.subscription_id
}

output "tenant_id" {
  description = "The ID of the Azure tenant"
  value       = data.azurerm_client_config.current.tenant_id
}

# Migration Configuration Information
output "aws_source_bucket" {
  description = "The name of the AWS S3 source bucket"
  value       = var.aws_s3_bucket_name
}

output "aws_source_region" {
  description = "The AWS region of the source S3 bucket"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "The AWS account ID for the source S3 bucket"
  value       = var.aws_account_id
}

output "migration_project_name" {
  description = "The name of the migration project"
  value       = var.migration_project_name
}

output "migration_copy_mode" {
  description = "The copy mode for the migration job"
  value       = var.migration_copy_mode
}

# Useful CLI Commands
output "cli_commands" {
  description = "Useful Azure CLI commands for managing the migration"
  value = {
    check_storage_mover_status = "az storage-mover show --resource-group ${azurerm_resource_group.migration.name} --name ${local.storage_mover_name}"
    list_containers = "az storage container list --account-name ${azurerm_storage_account.target.name} --auth-mode login"
    query_migration_logs = "az monitor log-analytics query --workspace ${azurerm_log_analytics_workspace.migration.workspace_id} --analytics-query 'StorageMoverLogs_CL | where TimeGenerated > ago(1h) | project TimeGenerated, JobName_s, JobStatus_s, TransferredBytes_d'"
    test_connectivity = "az storage blob list --container-name ${azurerm_storage_container.target.name} --account-name ${azurerm_storage_account.target.name} --auth-mode login"
  }
}

# Resource URLs for Azure Portal
output "portal_urls" {
  description = "URLs to access resources in the Azure Portal"
  value = {
    resource_group = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.migration.name}/overview"
    storage_account = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.migration.name}/providers/Microsoft.Storage/storageAccounts/${azurerm_storage_account.target.name}/overview"
    log_analytics = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.migration.name}/providers/Microsoft.OperationalInsights/workspaces/${azurerm_log_analytics_workspace.migration.name}/overview"
    application_insights = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.migration.name}/providers/Microsoft.Insights/components/${azurerm_application_insights.migration.name}/overview"
    logic_app = var.enable_logic_app ? "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.migration.name}/providers/Microsoft.Web/sites/${azurerm_logic_app_standard.migration[0].name}/overview" : null
  }
}

# Common Tags Applied
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Next Steps Information
output "next_steps" {
  description = "Next steps to configure the migration"
  value = {
    step_1 = "Configure AWS credentials and permissions for cross-cloud access"
    step_2 = "Create Storage Mover endpoints for source (AWS S3) and target (Azure Blob)"
    step_3 = "Define migration job with source and target endpoints"
    step_4 = "Configure Azure Arc connector for AWS access (if required)"
    step_5 = "Test migration with a small dataset before full migration"
    step_6 = "Monitor migration progress through Azure Monitor and Log Analytics"
    step_7 = "Verify data integrity after migration completion"
  }
}

# Cost Optimization Recommendations
output "cost_optimization_tips" {
  description = "Cost optimization recommendations for the migration"
  value = {
    storage_tier = "Consider using Cool or Archive tier for infrequently accessed data"
    log_retention = "Adjust Log Analytics retention period based on compliance requirements"
    alert_frequency = "Optimize alert evaluation frequency to balance monitoring and costs"
    cleanup = "Remove resources after migration completion to avoid ongoing charges"
    transfer_timing = "Schedule large transfers during off-peak hours to reduce costs"
  }
}