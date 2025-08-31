# Output Values for Azure File Backup Solution
# These outputs provide important information about the deployed infrastructure
# that can be used for verification, integration, and management purposes.

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.backup.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.backup.location
}

output "resource_group_id" {
  description = "Resource ID of the resource group"
  value       = azurerm_resource_group.backup.id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the created storage account"
  value       = azurerm_storage_account.backup.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.backup.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob service endpoint of the storage account"
  value       = azurerm_storage_account.backup.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.backup.primary_access_key
  sensitive   = true
}

output "storage_account_secondary_access_key" {
  description = "Secondary access key for the storage account"
  value       = azurerm_storage_account.backup.secondary_access_key
  sensitive   = true
}

output "storage_account_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.backup.primary_connection_string
  sensitive   = true
}

# Storage Container Information
output "backup_container_name" {
  description = "Name of the backup files container"
  value       = azurerm_storage_container.backup_files.name
}

output "backup_container_url" {
  description = "URL of the backup container"
  value       = "${azurerm_storage_account.backup.primary_blob_endpoint}${azurerm_storage_container.backup_files.name}"
}

# Logic Apps Information
output "logic_app_name" {
  description = "Name of the Logic Apps workflow"
  value       = azurerm_logic_app_workflow.backup.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic Apps workflow"
  value       = azurerm_logic_app_workflow.backup.id
}

output "logic_app_access_endpoint" {
  description = "Access endpoint URL for the Logic Apps workflow"
  value       = azurerm_logic_app_workflow.backup.access_endpoint
  sensitive   = true
}

output "logic_app_callback_url" {
  description = "Callback URL for manually triggering the Logic Apps workflow"
  value       = "https://management.azure.com${azurerm_logic_app_workflow.backup.id}/triggers/BackupScheduleTrigger/listCallbackUrl?api-version=2016-06-01"
  sensitive   = true
}

# Managed Identity Information
output "logic_app_principal_id" {
  description = "Principal ID of the Logic Apps managed identity"
  value       = try(azurerm_logic_app_workflow.backup_with_identity.identity[0].principal_id, null)
}

output "logic_app_tenant_id" {
  description = "Tenant ID of the Logic Apps managed identity"
  value       = try(azurerm_logic_app_workflow.backup_with_identity.identity[0].tenant_id, null)
}

# Backup Schedule Information
output "backup_schedule_frequency" {
  description = "Configured backup schedule frequency"
  value       = var.backup_schedule_frequency
}

output "backup_schedule_interval" {
  description = "Configured backup schedule interval"
  value       = var.backup_schedule_interval
}

output "backup_schedule_time" {
  description = "Configured backup execution time"
  value       = format("%02d:%02d %s", var.backup_time_hour, var.backup_time_minute, var.time_zone)
}

# Monitoring Information (if enabled)
output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace (if created)"
  value       = try(azurerm_log_analytics_workspace.backup[0].id, null)
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if created)"
  value       = try(azurerm_log_analytics_workspace.backup[0].name, null)
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace (if created)"
  value       = try(azurerm_log_analytics_workspace.backup[0].primary_shared_key, null)
  sensitive   = true
}

# Security Configuration Information
output "storage_https_traffic_enabled" {
  description = "Whether HTTPS traffic is enforced for the storage account"
  value       = azurerm_storage_account.backup.https_traffic_enabled
}

output "storage_min_tls_version" {
  description = "Minimum TLS version required for the storage account"
  value       = azurerm_storage_account.backup.min_tls_version
}

output "storage_allow_blob_public_access" {
  description = "Whether blob public access is allowed for the storage account"
  value       = azurerm_storage_account.backup.allow_nested_items_to_be_public
}

# Resource Tags
output "applied_tags" {
  description = "Tags applied to the resources"
  value       = var.common_tags
}

# Generated Values
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# CLI Commands for Management
output "azure_cli_commands" {
  description = "Useful Azure CLI commands for managing the backup solution"
  value = {
    # Storage account management
    list_containers = "az storage container list --account-name ${azurerm_storage_account.backup.name} --account-key <STORAGE_KEY>"
    list_blobs      = "az storage blob list --container-name ${azurerm_storage_container.backup_files.name} --account-name ${azurerm_storage_account.backup.name} --account-key <STORAGE_KEY>"
    
    # Logic Apps management
    list_workflows      = "az logic workflow list --resource-group ${azurerm_resource_group.backup.name}"
    show_workflow       = "az logic workflow show --resource-group ${azurerm_resource_group.backup.name} --name ${azurerm_logic_app_workflow.backup.name}"
    list_workflow_runs  = "az logic workflow run list --resource-group ${azurerm_resource_group.backup.name} --workflow-name ${azurerm_logic_app_workflow.backup.name}"
    
    # Monitoring
    view_logs = try(
      "az monitor log-analytics query --workspace ${azurerm_log_analytics_workspace.backup[0].id} --analytics-query \"AzureDiagnostics | where Category == 'WorkflowRuntime' | limit 50\"",
      "Log Analytics workspace not enabled"
    )
  }
}

# Cost Estimation Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the solution (USD)"
  value = {
    logic_apps_consumption = "~$0.50-2.00 (based on execution frequency)"
    storage_account_cool   = "~$0.01-1.00 per GB stored"
    log_analytics         = var.enable_storage_logging || var.enable_logic_apps_logging ? "~$2.30 per GB ingested" : "Not enabled"
    total_estimate        = "$2-5 per month for typical small business usage"
    note                  = "Actual costs depend on usage patterns, data volume, and execution frequency"
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployed infrastructure"
  value = {
    test_storage_connection = "az storage container show --name ${azurerm_storage_container.backup_files.name} --account-name ${azurerm_storage_account.backup.name}"
    check_logic_app_status  = "az logic workflow show --resource-group ${azurerm_resource_group.backup.name} --name ${azurerm_logic_app_workflow.backup.name} --query 'state'"
    upload_test_file       = "echo 'Test backup file' | az storage blob upload --container-name ${azurerm_storage_container.backup_files.name} --name test-backup-$(date +%Y%m%d).txt --account-name ${azurerm_storage_account.backup.name} --data @-"
  }
}