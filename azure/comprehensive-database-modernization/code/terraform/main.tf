# Azure Database Migration Service with Azure Backup - Main Infrastructure
# This file contains the core infrastructure resources for database modernization

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Create resource group for all migration resources
resource "azurerm_resource_group" "migration" {
  name     = "${var.resource_group_name}-${random_id.suffix.hex}"
  location = var.location
  tags     = var.tags
}

# Create Log Analytics workspace for monitoring and diagnostics
resource "azurerm_log_analytics_workspace" "migration" {
  name                = "la-${var.project_name}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

# Create storage account for migration assets and backup storage
resource "azurerm_storage_account" "migration" {
  name                     = "stg${var.project_name}${random_id.suffix.hex}"
  resource_group_name      = azurerm_resource_group.migration.name
  location                 = azurerm_resource_group.migration.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  access_tier              = var.storage_account_access_tier
  
  # Enable secure transfer and disable public blob access
  enable_https_traffic_only = true
  allow_nested_items_to_be_public = false
  
  # Enable blob versioning for better data protection
  blob_properties {
    versioning_enabled = true
    change_feed_enabled = true
    
    # Configure container delete retention
    container_delete_retention_policy {
      days = 7
    }
    
    # Configure blob delete retention
    delete_retention_policy {
      days = 7
    }
  }
  
  tags = var.tags
}

# Create container for database backup files
resource "azurerm_storage_container" "database_backups" {
  name                  = "database-backups"
  storage_account_name  = azurerm_storage_account.migration.name
  container_access_type = "private"
}

# Create container for migration logs
resource "azurerm_storage_container" "migration_logs" {
  name                  = "migration-logs"
  storage_account_name  = azurerm_storage_account.migration.name
  container_access_type = "private"
}

# Create Azure SQL Server for the target database
resource "azurerm_mssql_server" "target" {
  name                         = "sql-${var.project_name}-${random_id.suffix.hex}"
  resource_group_name          = azurerm_resource_group.migration.name
  location                     = azurerm_resource_group.migration.location
  version                      = "12.0"
  administrator_login          = var.sql_server_admin_username
  administrator_login_password = var.sql_server_admin_password
  
  # Enable public network access based on variable
  public_network_access_enabled = var.enable_public_network_access
  
  # Enable Azure AD authentication
  azuread_administrator {
    login_username = data.azurerm_client_config.current.object_id
    object_id      = data.azurerm_client_config.current.object_id
  }
  
  tags = var.tags
}

# Create firewall rule to allow Azure services
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.target.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Create firewall rules for allowed IP addresses
resource "azurerm_mssql_firewall_rule" "allowed_ips" {
  count            = length(var.allowed_ip_addresses)
  name             = "AllowedIP-${count.index}"
  server_id        = azurerm_mssql_server.target.id
  start_ip_address = var.allowed_ip_addresses[count.index]
  end_ip_address   = var.allowed_ip_addresses[count.index]
}

# Create Azure SQL Database as migration target
resource "azurerm_mssql_database" "target" {
  name                        = var.sql_database_name
  server_id                   = azurerm_mssql_server.target.id
  sku_name                    = var.sql_database_sku
  backup_storage_redundancy   = var.sql_backup_storage_redundancy
  
  # Enable automatic tuning for performance optimization
  auto_pause_delay_in_minutes = -1
  
  # Configure threat detection policy
  threat_detection_policy {
    state                      = var.enable_advanced_threat_protection ? "Enabled" : "Disabled"
    email_admin_recipients     = var.enable_advanced_threat_protection ? [var.alert_email_address] : []
    retention_days             = var.enable_advanced_threat_protection ? 30 : 0
    storage_endpoint          = var.enable_advanced_threat_protection ? azurerm_storage_account.migration.primary_blob_endpoint : null
    storage_account_access_key = var.enable_advanced_threat_protection ? azurerm_storage_account.migration.primary_access_key : null
  }
  
  tags = var.tags
}

# Enable Advanced Threat Protection if requested
resource "azurerm_mssql_server_security_alert_policy" "target" {
  count               = var.enable_advanced_threat_protection ? 1 : 0
  resource_group_name = azurerm_resource_group.migration.name
  server_name         = azurerm_mssql_server.target.name
  state               = "Enabled"
  
  storage_endpoint           = azurerm_storage_account.migration.primary_blob_endpoint
  storage_account_access_key = azurerm_storage_account.migration.primary_access_key
  retention_days             = 30
  
  email_admin_recipients = [var.alert_email_address]
  
  depends_on = [azurerm_mssql_database.target]
}

# Enable vulnerability assessments if requested
resource "azurerm_mssql_server_vulnerability_assessment" "target" {
  count               = var.enable_vulnerability_assessments ? 1 : 0
  server_security_alert_policy_id = azurerm_mssql_server_security_alert_policy.target[0].id
  
  storage_container_path     = "${azurerm_storage_account.migration.primary_blob_endpoint}vulnerability-assessments/"
  storage_account_access_key = azurerm_storage_account.migration.primary_access_key
  
  recurring_scans {
    enabled                   = true
    email_subscription_admins = true
    emails                    = [var.alert_email_address]
  }
  
  depends_on = [azurerm_mssql_server_security_alert_policy.target]
}

# Create Database Migration Service
resource "azurerm_database_migration_service" "migration" {
  name                = "dms-${var.project_name}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  sku_name            = var.dms_sku_name
  
  tags = var.tags
}

# Create Recovery Services Vault for backup management
resource "azurerm_recovery_services_vault" "backup" {
  name                = "rsv-${var.project_name}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  sku                 = "Standard"
  storage_mode_type   = var.backup_vault_storage_model_type
  
  # Enable soft delete and cross region restore
  soft_delete_enabled = true
  
  tags = var.tags
}

# Create backup policy for SQL Database
resource "azurerm_backup_policy_sql" "database" {
  name                = "sql-backup-policy-${var.project_name}"
  resource_group_name = azurerm_resource_group.migration.name
  recovery_vault_name = azurerm_recovery_services_vault.backup.name
  
  settings {
    time_zone           = var.backup_policy_timezone
    compression_enabled = true
  }
  
  backup_daily {
    start_time = var.backup_policy_time
  }
  
  retention_daily {
    count = var.backup_policy_retention_days
  }
  
  retention_weekly {
    count    = 12
    weekdays = ["Sunday"]
  }
  
  retention_monthly {
    count    = 12
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }
  
  retention_yearly {
    count    = 5
    weekdays = ["Sunday"]
    weeks    = ["First"]
    months   = ["January"]
  }
}

# Create Action Group for alerts
resource "azurerm_monitor_action_group" "migration_alerts" {
  name                = "migration-alerts-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.migration.name
  short_name          = "migration"
  
  email_receiver {
    name          = "admin"
    email_address = var.alert_email_address
  }
  
  tags = var.tags
}

# Create metric alert for migration failures
resource "azurerm_monitor_metric_alert" "migration_failures" {
  name                = "migration-failure-alert-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.migration.name
  scopes              = [azurerm_database_migration_service.migration.id]
  description         = "Alert for database migration failures"
  
  criteria {
    metric_namespace = "Microsoft.DataMigration/services"
    metric_name      = "FailedMigrations"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.migration_alerts.id
  }
  
  frequency   = "PT1M"
  window_size = "PT5M"
  
  tags = var.tags
}

# Create metric alert for backup failures
resource "azurerm_monitor_metric_alert" "backup_failures" {
  name                = "backup-failure-alert-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.migration.name
  scopes              = [azurerm_recovery_services_vault.backup.id]
  description         = "Alert for backup failures"
  
  criteria {
    metric_namespace = "Microsoft.RecoveryServices/vaults"
    metric_name      = "BackupFailures"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.migration_alerts.id
  }
  
  frequency   = "PT5M"
  window_size = "PT15M"
  
  tags = var.tags
}

# Create diagnostic settings for Database Migration Service
resource "azurerm_monitor_diagnostic_setting" "dms_diagnostics" {
  name                       = "dms-diagnostics"
  target_resource_id         = azurerm_database_migration_service.migration.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.migration.id
  
  enabled_log {
    category = "DataMigrationService"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create diagnostic settings for SQL Database
resource "azurerm_monitor_diagnostic_setting" "sql_diagnostics" {
  name                       = "sql-diagnostics"
  target_resource_id         = azurerm_mssql_database.target.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.migration.id
  
  enabled_log {
    category = "SQLInsights"
  }
  
  enabled_log {
    category = "AutomaticTuning"
  }
  
  enabled_log {
    category = "QueryStoreRuntimeStatistics"
  }
  
  enabled_log {
    category = "QueryStoreWaitStatistics"
  }
  
  enabled_log {
    category = "Errors"
  }
  
  enabled_log {
    category = "DatabaseWaitStatistics"
  }
  
  enabled_log {
    category = "Timeouts"
  }
  
  enabled_log {
    category = "Blocks"
  }
  
  enabled_log {
    category = "Deadlocks"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create diagnostic settings for Recovery Services Vault
resource "azurerm_monitor_diagnostic_setting" "backup_diagnostics" {
  name                       = "backup-diagnostics"
  target_resource_id         = azurerm_recovery_services_vault.backup.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.migration.id
  
  enabled_log {
    category = "CoreAzureBackup"
  }
  
  enabled_log {
    category = "AddonAzureBackupJobs"
  }
  
  enabled_log {
    category = "AddonAzureBackupAlerts"
  }
  
  enabled_log {
    category = "AddonAzureBackupPolicy"
  }
  
  enabled_log {
    category = "AddonAzureBackupStorage"
  }
  
  enabled_log {
    category = "AddonAzureBackupProtectedInstance"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create storage container for vulnerability assessments
resource "azurerm_storage_container" "vulnerability_assessments" {
  count                 = var.enable_vulnerability_assessments ? 1 : 0
  name                  = "vulnerability-assessments"
  storage_account_name  = azurerm_storage_account.migration.name
  container_access_type = "private"
}

# Wait for resources to be fully provisioned
resource "time_sleep" "wait_for_resources" {
  depends_on = [
    azurerm_mssql_database.target,
    azurerm_database_migration_service.migration,
    azurerm_recovery_services_vault.backup,
    azurerm_log_analytics_workspace.migration
  ]
  
  create_duration = "30s"
}