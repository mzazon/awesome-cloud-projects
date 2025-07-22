# Azure Database Migration Service with Azure Backup - Outputs
# This file defines all output values for the database modernization infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all migration resources"
  value       = azurerm_resource_group.migration.name
}

output "resource_group_id" {
  description = "ID of the resource group containing all migration resources"
  value       = azurerm_resource_group.migration.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.migration.location
}

# SQL Server and Database Information
output "sql_server_name" {
  description = "Name of the Azure SQL Server"
  value       = azurerm_mssql_server.target.name
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of the Azure SQL Server"
  value       = azurerm_mssql_server.target.fully_qualified_domain_name
}

output "sql_database_name" {
  description = "Name of the Azure SQL Database"
  value       = azurerm_mssql_database.target.name
}

output "sql_database_id" {
  description = "ID of the Azure SQL Database"
  value       = azurerm_mssql_database.target.id
}

output "sql_database_connection_string" {
  description = "Connection string for the Azure SQL Database"
  value       = "Server=tcp:${azurerm_mssql_server.target.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.target.name};Persist Security Info=False;User ID=${var.sql_server_admin_username};Password=${var.sql_server_admin_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  sensitive   = true
}

# Database Migration Service Information
output "dms_service_name" {
  description = "Name of the Azure Database Migration Service"
  value       = azurerm_database_migration_service.migration.name
}

output "dms_service_id" {
  description = "ID of the Azure Database Migration Service"
  value       = azurerm_database_migration_service.migration.id
}

output "dms_service_sku" {
  description = "SKU of the Azure Database Migration Service"
  value       = azurerm_database_migration_service.migration.sku_name
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for migration assets"
  value       = azurerm_storage_account.migration.name
}

output "storage_account_id" {
  description = "ID of the storage account for migration assets"
  value       = azurerm_storage_account.migration.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.migration.primary_blob_endpoint
}

output "storage_account_primary_key" {
  description = "Primary access key of the storage account"
  value       = azurerm_storage_account.migration.primary_access_key
  sensitive   = true
}

output "database_backups_container_name" {
  description = "Name of the storage container for database backups"
  value       = azurerm_storage_container.database_backups.name
}

output "migration_logs_container_name" {
  description = "Name of the storage container for migration logs"
  value       = azurerm_storage_container.migration_logs.name
}

# Recovery Services Vault Information
output "recovery_services_vault_name" {
  description = "Name of the Recovery Services Vault for backup"
  value       = azurerm_recovery_services_vault.backup.name
}

output "recovery_services_vault_id" {
  description = "ID of the Recovery Services Vault for backup"
  value       = azurerm_recovery_services_vault.backup.id
}

output "backup_policy_name" {
  description = "Name of the backup policy for SQL Database"
  value       = azurerm_backup_policy_sql.database.name
}

output "backup_policy_id" {
  description = "ID of the backup policy for SQL Database"
  value       = azurerm_backup_policy_sql.database.id
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for monitoring"
  value       = azurerm_log_analytics_workspace.migration.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace for monitoring"
  value       = azurerm_log_analytics_workspace.migration.id
}

output "log_analytics_workspace_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.migration.primary_shared_key
  sensitive   = true
}

# Monitoring and Alerting Information
output "action_group_name" {
  description = "Name of the action group for alerts"
  value       = azurerm_monitor_action_group.migration_alerts.name
}

output "action_group_id" {
  description = "ID of the action group for alerts"
  value       = azurerm_monitor_action_group.migration_alerts.id
}

output "migration_failure_alert_name" {
  description = "Name of the migration failure alert"
  value       = azurerm_monitor_metric_alert.migration_failures.name
}

output "backup_failure_alert_name" {
  description = "Name of the backup failure alert"
  value       = azurerm_monitor_metric_alert.backup_failures.name
}

# Security Information
output "advanced_threat_protection_enabled" {
  description = "Whether Advanced Threat Protection is enabled for SQL Database"
  value       = var.enable_advanced_threat_protection
}

output "vulnerability_assessments_enabled" {
  description = "Whether vulnerability assessments are enabled for SQL Database"
  value       = var.enable_vulnerability_assessments
}

# Migration Connection Information
output "source_connection_template" {
  description = "Template for source database connection configuration"
  value = {
    data_source    = "your-source-server.domain.com"
    server_name    = "your-source-server"
    authentication = "SqlAuthentication"
    user_name      = "your-source-username"
    password       = "your-source-password"
    encrypt_connection = true
    trust_server_certificate = true
  }
}

output "target_connection_info" {
  description = "Target database connection configuration for migration"
  value = {
    data_source    = azurerm_mssql_server.target.fully_qualified_domain_name
    server_name    = azurerm_mssql_server.target.name
    authentication = "SqlAuthentication"
    user_name      = var.sql_server_admin_username
    password       = var.sql_server_admin_password
    encrypt_connection = true
    trust_server_certificate = false
  }
  sensitive = true
}

# Resource URLs for Azure Portal
output "azure_portal_urls" {
  description = "Azure Portal URLs for key resources"
  value = {
    resource_group = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_resource_group.migration.id}"
    sql_server     = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_mssql_server.target.id}"
    sql_database   = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_mssql_database.target.id}"
    dms_service    = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_database_migration_service.migration.id}"
    backup_vault   = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_recovery_services_vault.backup.id}"
    log_analytics  = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_log_analytics_workspace.migration.id}"
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources for database modernization"
  value = {
    environment                = var.environment
    project_name              = var.project_name
    resource_group_name       = azurerm_resource_group.migration.name
    location                  = azurerm_resource_group.migration.location
    sql_server_name           = azurerm_mssql_server.target.name
    sql_database_name         = azurerm_mssql_database.target.name
    dms_service_name          = azurerm_database_migration_service.migration.name
    storage_account_name      = azurerm_storage_account.migration.name
    backup_vault_name         = azurerm_recovery_services_vault.backup.name
    log_analytics_workspace_name = azurerm_log_analytics_workspace.migration.name
    advanced_threat_protection = var.enable_advanced_threat_protection
    vulnerability_assessments = var.enable_vulnerability_assessments
    alert_email_address       = var.alert_email_address
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps for completing the database migration"
  value = [
    "1. Configure source database connection in DMS using the source_connection_template output",
    "2. Create migration project in Azure Database Migration Service",
    "3. Run database assessment to identify migration compatibility issues",
    "4. Configure schema migration task in DMS",
    "5. Execute schema migration from source to target database",
    "6. Configure data migration task with appropriate settings",
    "7. Execute data migration and monitor progress through Azure Portal",
    "8. Verify migrated data integrity and application connectivity",
    "9. Configure backup protection for the migrated database",
    "10. Monitor migration progress and backup status through Azure Monitor"
  ]
}