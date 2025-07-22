# Output values for Azure disaster recovery infrastructure
# These outputs provide essential information for accessing and managing
# the deployed disaster recovery infrastructure

# ================================================================
# RESOURCE GROUP OUTPUTS
# ================================================================

output "primary_resource_group_name" {
  description = "Name of the primary resource group containing DR infrastructure"
  value       = azurerm_resource_group.primary.name
}

output "primary_resource_group_id" {
  description = "Resource ID of the primary resource group"
  value       = azurerm_resource_group.primary.id
}

output "backup_resource_group_name" {
  description = "Name of the backup resource group containing Recovery Services Vaults"
  value       = azurerm_resource_group.backup.name
}

output "backup_resource_group_id" {
  description = "Resource ID of the backup resource group"
  value       = azurerm_resource_group.backup.id
}

# ================================================================
# RECOVERY SERVICES VAULT OUTPUTS
# ================================================================

output "primary_recovery_vault_name" {
  description = "Name of the primary Recovery Services Vault"
  value       = azurerm_recovery_services_vault.primary.name
}

output "primary_recovery_vault_id" {
  description = "Resource ID of the primary Recovery Services Vault"
  value       = azurerm_recovery_services_vault.primary.id
}

output "secondary_recovery_vault_name" {
  description = "Name of the secondary Recovery Services Vault"
  value       = azurerm_recovery_services_vault.secondary.name
}

output "secondary_recovery_vault_id" {
  description = "Resource ID of the secondary Recovery Services Vault"
  value       = azurerm_recovery_services_vault.secondary.id
}

output "cross_region_restore_enabled" {
  description = "Whether cross-region restore is enabled for the vaults"
  value       = var.enable_cross_region_restore
}

# ================================================================
# LOG ANALYTICS WORKSPACE OUTPUTS
# ================================================================

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for DR monitoring"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# ================================================================
# BACKUP POLICY OUTPUTS
# ================================================================

output "vm_backup_policy_name" {
  description = "Name of the VM backup policy"
  value       = azurerm_backup_policy_vm.vm_policy.name
}

output "vm_backup_policy_id" {
  description = "Resource ID of the VM backup policy"
  value       = azurerm_backup_policy_vm.vm_policy.id
}

# ================================================================
# MONITORING AND ALERTING OUTPUTS
# ================================================================

output "action_group_name" {
  description = "Name of the Action Group for DR alerts"
  value       = azurerm_monitor_action_group.dr_alerts.name
}

output "action_group_id" {
  description = "Resource ID of the Action Group"
  value       = azurerm_monitor_action_group.dr_alerts.id
}

output "backup_job_failure_alert_id" {
  description = "Resource ID of the backup job failure alert rule"
  value       = azurerm_monitor_metric_alert.backup_job_failure.id
}

output "vault_health_alert_id" {
  description = "Resource ID of the vault health alert rule"
  value       = azurerm_monitor_metric_alert.vault_health.id
}

output "storage_consumption_alert_id" {
  description = "Resource ID of the storage consumption alert rule (if enabled)"
  value       = var.enable_advanced_monitoring ? azurerm_monitor_scheduled_query_rules_alert_v2.storage_consumption[0].id : null
}

# ================================================================
# LOGIC APPS OUTPUTS
# ================================================================

output "logic_app_name" {
  description = "Name of the Logic Apps workflow for DR orchestration"
  value       = var.enable_logic_apps ? azurerm_logic_app_workflow.dr_orchestration[0].name : null
}

output "logic_app_id" {
  description = "Resource ID of the Logic Apps workflow"
  value       = var.enable_logic_apps ? azurerm_logic_app_workflow.dr_orchestration[0].id : null
}

output "logic_app_access_endpoint" {
  description = "Access endpoint URL for the Logic Apps workflow"
  value       = var.enable_logic_apps ? azurerm_logic_app_workflow.dr_orchestration[0].access_endpoint : null
  sensitive   = true
}

output "logic_app_managed_identity_principal_id" {
  description = "Principal ID of the Logic Apps managed identity"
  value       = var.enable_logic_apps ? azurerm_logic_app_workflow.dr_orchestration[0].identity[0].principal_id : null
}

# ================================================================
# STORAGE ACCOUNT OUTPUTS
# ================================================================

output "storage_account_name" {
  description = "Name of the storage account for Logic Apps"
  value       = var.enable_logic_apps ? azurerm_storage_account.logic_apps[0].name : null
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = var.enable_logic_apps ? azurerm_storage_account.logic_apps[0].id : null
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = var.enable_logic_apps ? azurerm_storage_account.logic_apps[0].primary_connection_string : null
  sensitive   = true
}

# ================================================================
# WORKBOOK OUTPUTS
# ================================================================

output "workbook_name" {
  description = "Name of the disaster recovery monitoring workbook"
  value       = var.enable_workbooks ? azurerm_application_insights_workbook.dr_dashboard[0].display_name : null
}

output "workbook_id" {
  description = "Resource ID of the disaster recovery monitoring workbook"
  value       = var.enable_workbooks ? azurerm_application_insights_workbook.dr_dashboard[0].id : null
}

# ================================================================
# CONFIGURATION OUTPUTS
# ================================================================

output "deployment_configuration" {
  description = "Summary of the deployment configuration"
  value = {
    environment                  = var.environment
    project_name                = var.project_name
    primary_location            = var.primary_location
    secondary_location          = var.secondary_location
    backup_storage_redundancy   = var.backup_storage_redundancy
    cross_region_restore        = var.enable_cross_region_restore
    logic_apps_enabled          = var.enable_logic_apps
    workbooks_enabled           = var.enable_workbooks
    advanced_monitoring_enabled = var.enable_advanced_monitoring
  }
}

# ================================================================
# AZURE PORTAL LINKS
# ================================================================

output "azure_portal_links" {
  description = "Direct links to Azure Portal resources for easy access"
  value = {
    backup_center = "https://portal.azure.com/#view/Microsoft_Azure_DataProtection/BackupCenterMenuBlade/~/overview"
    primary_vault = "https://portal.azure.com/#@/resource${azurerm_recovery_services_vault.primary.id}/overview"
    secondary_vault = "https://portal.azure.com/#@/resource${azurerm_recovery_services_vault.secondary.id}/overview"
    log_analytics = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}/overview"
    action_group = "https://portal.azure.com/#@/resource${azurerm_monitor_action_group.dr_alerts.id}/overview"
    logic_app = var.enable_logic_apps ? "https://portal.azure.com/#@/resource${azurerm_logic_app_workflow.dr_orchestration[0].id}/overview" : null
    workbook = var.enable_workbooks ? "https://portal.azure.com/#@/resource${azurerm_application_insights_workbook.dr_dashboard[0].id}/overview" : null
  }
}

# ================================================================
# NEXT STEPS GUIDANCE
# ================================================================

output "next_steps" {
  description = "Guidance for next steps after infrastructure deployment"
  value = {
    backup_setup = "Configure backup protection for your VMs using the deployed backup policy in Azure Backup Center"
    monitoring_setup = "Review and customize alert rules based on your specific monitoring requirements"
    logic_apps_config = var.enable_logic_apps ? "Complete Logic Apps workflow configuration with your specific automation requirements" : "Enable Logic Apps in variables to deploy automated orchestration"
    testing = "Perform disaster recovery testing using Azure Site Recovery test failover capabilities"
    documentation = "Update your disaster recovery runbooks with the new infrastructure details"
  }
}

# ================================================================
# RANDOM SUFFIX OUTPUT
# ================================================================

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}