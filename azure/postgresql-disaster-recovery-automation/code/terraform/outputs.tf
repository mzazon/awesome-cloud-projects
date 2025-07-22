# Output definitions for PostgreSQL Flexible Server disaster recovery solution
# This file contains all outputs that provide important information about the deployed infrastructure

# Resource group outputs
output "primary_resource_group_name" {
  description = "Name of the primary resource group"
  value       = azurerm_resource_group.primary.name
}

output "primary_resource_group_location" {
  description = "Location of the primary resource group"
  value       = azurerm_resource_group.primary.location
}

output "secondary_resource_group_name" {
  description = "Name of the secondary resource group"
  value       = azurerm_resource_group.secondary.name
}

output "secondary_resource_group_location" {
  description = "Location of the secondary resource group"
  value       = azurerm_resource_group.secondary.location
}

# PostgreSQL primary server outputs
output "postgresql_primary_server_name" {
  description = "Name of the primary PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.primary.name
}

output "postgresql_primary_server_fqdn" {
  description = "Fully qualified domain name of the primary PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.primary.fqdn
}

output "postgresql_primary_server_id" {
  description = "Resource ID of the primary PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.primary.id
}

output "postgresql_primary_admin_username" {
  description = "Administrator username for the primary PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.primary.administrator_login
}

output "postgresql_primary_version" {
  description = "PostgreSQL version of the primary server"
  value       = azurerm_postgresql_flexible_server.primary.version
}

output "postgresql_primary_backup_retention_days" {
  description = "Backup retention period for the primary server"
  value       = azurerm_postgresql_flexible_server.primary.backup_retention_days
}

output "postgresql_primary_high_availability_enabled" {
  description = "Whether high availability is enabled for the primary server"
  value       = var.postgresql_high_availability_enabled
}

output "postgresql_primary_geo_redundant_backup_enabled" {
  description = "Whether geo-redundant backup is enabled for the primary server"
  value       = azurerm_postgresql_flexible_server.primary.geo_redundant_backup_enabled
}

# PostgreSQL replica server outputs
output "postgresql_replica_server_name" {
  description = "Name of the replica PostgreSQL server"
  value       = var.enable_read_replica ? azurerm_postgresql_flexible_server.replica[0].name : null
}

output "postgresql_replica_server_fqdn" {
  description = "Fully qualified domain name of the replica PostgreSQL server"
  value       = var.enable_read_replica ? azurerm_postgresql_flexible_server.replica[0].fqdn : null
}

output "postgresql_replica_server_id" {
  description = "Resource ID of the replica PostgreSQL server"
  value       = var.enable_read_replica ? azurerm_postgresql_flexible_server.replica[0].id : null
}

output "postgresql_replica_source_server_id" {
  description = "Source server ID for the replica PostgreSQL server"
  value       = var.enable_read_replica ? azurerm_postgresql_flexible_server.replica[0].source_server_id : null
}

# Connection string outputs
output "postgresql_primary_connection_string" {
  description = "Connection string for the primary PostgreSQL server"
  value       = "postgresql://${azurerm_postgresql_flexible_server.primary.administrator_login}:${var.postgresql_admin_password}@${azurerm_postgresql_flexible_server.primary.fqdn}:5432/${var.create_sample_data ? var.sample_database_name : "postgres"}"
  sensitive   = true
}

output "postgresql_replica_connection_string" {
  description = "Connection string for the replica PostgreSQL server (read-only)"
  value       = var.enable_read_replica ? "postgresql://${azurerm_postgresql_flexible_server.primary.administrator_login}:${var.postgresql_admin_password}@${azurerm_postgresql_flexible_server.replica[0].fqdn}:5432/${var.create_sample_data ? var.sample_database_name : "postgres"}" : null
  sensitive   = true
}

# Backup vault outputs
output "primary_backup_vault_name" {
  description = "Name of the primary backup vault"
  value       = var.enable_backup_vault ? azurerm_data_protection_backup_vault.primary[0].name : null
}

output "primary_backup_vault_id" {
  description = "Resource ID of the primary backup vault"
  value       = var.enable_backup_vault ? azurerm_data_protection_backup_vault.primary[0].id : null
}

output "secondary_backup_vault_name" {
  description = "Name of the secondary backup vault"
  value       = var.enable_backup_vault ? azurerm_data_protection_backup_vault.secondary[0].name : null
}

output "secondary_backup_vault_id" {
  description = "Resource ID of the secondary backup vault"
  value       = var.enable_backup_vault ? azurerm_data_protection_backup_vault.secondary[0].id : null
}

output "backup_policy_name" {
  description = "Name of the backup policy"
  value       = var.enable_backup_vault ? azurerm_data_protection_backup_policy_postgresql.main[0].name : null
}

output "backup_policy_id" {
  description = "Resource ID of the backup policy"
  value       = var.enable_backup_vault ? azurerm_data_protection_backup_policy_postgresql.main[0].id : null
}

# Storage account outputs
output "storage_account_name" {
  description = "Name of the storage account for backup artifacts"
  value       = azurerm_storage_account.backup_artifacts.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.backup_artifacts.id
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.backup_artifacts.primary_access_key
  sensitive   = true
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.backup_artifacts.primary_blob_endpoint
}

output "storage_containers" {
  description = "List of storage containers created"
  value = [
    azurerm_storage_container.database_backups.name,
    azurerm_storage_container.recovery_scripts.name,
    azurerm_storage_container.recovery_logs.name
  ]
}

# Log Analytics workspace outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID (Customer ID) of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].primary_shared_key : null
  sensitive   = true
}

# Monitoring and alerting outputs
output "action_group_name" {
  description = "Name of the action group for disaster recovery alerts"
  value       = var.enable_monitoring ? azurerm_monitor_action_group.disaster_recovery[0].name : null
}

output "action_group_id" {
  description = "Resource ID of the action group"
  value       = var.enable_monitoring ? azurerm_monitor_action_group.disaster_recovery[0].id : null
}

output "alert_rules" {
  description = "List of created alert rules"
  value = var.enable_monitoring ? [
    {
      name        = "PostgreSQL-ConnectionFailures"
      id          = azurerm_monitor_metric_alert.connection_failures[0].id
      description = "Alert for database connectivity issues"
      severity    = 2
    },
    var.enable_read_replica ? {
      name        = "PostgreSQL-ReplicationLag"
      id          = azurerm_monitor_metric_alert.replication_lag[0].id
      description = "Alert for high replication lag"
      severity    = 1
    } : null,
    {
      name        = "PostgreSQL-BackupFailures"
      id          = azurerm_monitor_metric_alert.backup_failures[0].id
      description = "Alert for backup failures"
      severity    = 1
    }
  ] : []
}

# Automation account outputs
output "automation_account_name" {
  description = "Name of the Azure Automation account"
  value       = var.enable_automation ? azurerm_automation_account.disaster_recovery[0].name : null
}

output "automation_account_id" {
  description = "Resource ID of the Azure Automation account"
  value       = var.enable_automation ? azurerm_automation_account.disaster_recovery[0].id : null
}

output "automation_runbook_name" {
  description = "Name of the disaster recovery runbook"
  value       = var.enable_automation ? azurerm_automation_runbook.disaster_recovery[0].name : null
}

output "automation_runbook_id" {
  description = "Resource ID of the disaster recovery runbook"
  value       = var.enable_automation ? azurerm_automation_runbook.disaster_recovery[0].id : null
}

# Sample database outputs
output "sample_database_name" {
  description = "Name of the sample database"
  value       = var.create_sample_data ? azurerm_postgresql_flexible_server_database.sample[0].name : null
}

output "sample_database_id" {
  description = "Resource ID of the sample database"
  value       = var.create_sample_data ? azurerm_postgresql_flexible_server_database.sample[0].id : null
}

# Network configuration outputs
output "allowed_ip_ranges" {
  description = "List of allowed IP ranges for PostgreSQL access"
  value       = var.allowed_ip_ranges
}

output "public_network_access_enabled" {
  description = "Whether public network access is enabled for PostgreSQL servers"
  value       = var.postgresql_public_network_access_enabled
}

# Disaster recovery configuration outputs
output "disaster_recovery_configuration" {
  description = "Summary of disaster recovery configuration"
  value = {
    primary_region                    = var.primary_location
    secondary_region                  = var.secondary_location
    high_availability_enabled        = var.postgresql_high_availability_enabled
    geo_redundant_backup_enabled     = var.postgresql_geo_redundant_backup_enabled
    read_replica_enabled             = var.enable_read_replica
    backup_retention_days            = var.postgresql_backup_retention_days
    backup_vault_enabled             = var.enable_backup_vault
    backup_vault_redundancy          = var.backup_vault_redundancy
    monitoring_enabled               = var.enable_monitoring
    automation_enabled               = var.enable_automation
    alert_email_addresses           = var.alert_email_addresses
    connection_failures_threshold    = var.connection_failures_threshold
    replication_lag_threshold_seconds = var.replication_lag_threshold_seconds
    backup_failures_threshold        = var.backup_failures_threshold
  }
}

# Cost optimization outputs
output "cost_optimization_recommendations" {
  description = "Cost optimization recommendations for the disaster recovery solution"
  value = {
    storage_account_tier              = var.storage_account_tier
    storage_account_replication_type  = var.storage_account_replication_type
    postgresql_sku_name              = var.postgresql_sku_name
    postgresql_storage_mb            = var.postgresql_storage_mb
    log_analytics_retention_days     = var.log_analytics_retention_days
    backup_policy_retention_days     = var.backup_policy_retention_days
    recommendations = [
      "Consider using Cool storage tier for long-term backup artifacts",
      "Review Log Analytics retention period based on compliance requirements",
      "Monitor PostgreSQL storage usage and adjust as needed",
      "Consider scaling down replica server if not used for production reads"
    ]
  }
}

# Security configuration outputs
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    https_traffic_only_enabled       = azurerm_storage_account.backup_artifacts.enable_https_traffic_only
    min_tls_version                 = azurerm_storage_account.backup_artifacts.min_tls_version
    geo_redundant_backup_enabled    = azurerm_postgresql_flexible_server.primary.geo_redundant_backup_enabled
    high_availability_mode          = var.postgresql_high_availability_enabled ? "ZoneRedundant" : "Disabled"
    backup_vault_redundancy         = var.backup_vault_redundancy
    storage_account_replication     = var.storage_account_replication_type
    public_network_access_enabled   = var.postgresql_public_network_access_enabled
    firewall_rules_configured       = true
  }
}

# Validation outputs for testing
output "validation_commands" {
  description = "Commands to validate the disaster recovery setup"
  value = {
    test_primary_connectivity = "psql \"postgresql://${azurerm_postgresql_flexible_server.primary.administrator_login}:${var.postgresql_admin_password}@${azurerm_postgresql_flexible_server.primary.fqdn}:5432/${var.create_sample_data ? var.sample_database_name : "postgres"}\" -c \"SELECT version();\""
    test_replica_connectivity = var.enable_read_replica ? "psql \"postgresql://${azurerm_postgresql_flexible_server.primary.administrator_login}:${var.postgresql_admin_password}@${azurerm_postgresql_flexible_server.replica[0].fqdn}:5432/${var.create_sample_data ? var.sample_database_name : "postgres"}\" -c \"SELECT version();\"" : null
    check_backup_retention = "az postgres flexible-server show --name ${azurerm_postgresql_flexible_server.primary.name} --resource-group ${azurerm_resource_group.primary.name} --query backup"
    check_high_availability = "az postgres flexible-server show --name ${azurerm_postgresql_flexible_server.primary.name} --resource-group ${azurerm_resource_group.primary.name} --query highAvailability"
    check_replication_lag = var.enable_read_replica ? "az monitor metrics list --resource ${azurerm_postgresql_flexible_server.primary.id} --metric replica_lag --interval PT1M" : null
    list_alert_rules = var.enable_monitoring ? "az monitor metrics alert list --resource-group ${azurerm_resource_group.primary.name}" : null
  }
}

# Random suffix for reference
output "random_suffix" {
  description = "Random suffix used for unique resource names"
  value       = random_string.suffix.result
}