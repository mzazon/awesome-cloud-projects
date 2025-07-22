# PostgreSQL Flexible Server Disaster Recovery Infrastructure
# This file contains the main infrastructure resources for implementing automated disaster recovery
# with Azure Database for PostgreSQL Flexible Server and Azure Backup

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create primary resource group
resource "azurerm_resource_group" "primary" {
  name     = "rg-${var.resource_prefix}-${var.environment}-${random_string.suffix.result}"
  location = var.primary_location
  
  tags = merge(var.tags, {
    Purpose = "primary"
    Region  = var.primary_location
  })
}

# Create secondary resource group for disaster recovery
resource "azurerm_resource_group" "secondary" {
  name     = "rg-${var.resource_prefix}-${var.environment}-secondary-${random_string.suffix.result}"
  location = var.secondary_location
  
  tags = merge(var.tags, {
    Purpose = "secondary"
    Region  = var.secondary_location
  })
}

# Create Log Analytics workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = "law-${var.resource_prefix}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(var.tags, {
    Purpose = "monitoring"
  })
}

# Create storage account for backup artifacts
resource "azurerm_storage_account" "backup_artifacts" {
  name                     = "st${var.resource_prefix}${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.primary.name
  location                 = azurerm_resource_group.primary.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  access_tier              = var.storage_account_access_tier
  
  # Enable secure transfer and require HTTPS
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  # Configure blob properties for backup retention
  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = var.backup_policy_retention_days
    }
    
    container_delete_retention_policy {
      days = var.backup_policy_retention_days
    }
  }
  
  tags = merge(var.tags, {
    Purpose = "backup-artifacts"
  })
}

# Create storage containers for different backup types
resource "azurerm_storage_container" "database_backups" {
  name                  = "database-backups"
  storage_account_name  = azurerm_storage_account.backup_artifacts.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "recovery_scripts" {
  name                  = "recovery-scripts"
  storage_account_name  = azurerm_storage_account.backup_artifacts.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "recovery_logs" {
  name                  = "recovery-logs"
  storage_account_name  = azurerm_storage_account.backup_artifacts.name
  container_access_type = "private"
}

# Create primary PostgreSQL Flexible Server with high availability
resource "azurerm_postgresql_flexible_server" "primary" {
  name                = "psql-${var.resource_prefix}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.primary.name
  location            = azurerm_resource_group.primary.location
  version             = var.postgresql_version
  
  # Administrator credentials
  administrator_login    = var.postgresql_admin_username
  administrator_password = var.postgresql_admin_password
  
  # Server configuration
  sku_name   = var.postgresql_sku_name
  storage_mb = var.postgresql_storage_mb
  
  # High availability configuration
  dynamic "high_availability" {
    for_each = var.postgresql_high_availability_enabled ? [1] : []
    content {
      mode = "ZoneRedundant"
    }
  }
  
  # Backup configuration
  backup_retention_days        = var.postgresql_backup_retention_days
  geo_redundant_backup_enabled = var.postgresql_geo_redundant_backup_enabled
  
  # Storage configuration
  auto_grow_enabled = var.postgresql_storage_auto_grow_enabled
  
  # Network configuration
  public_network_access_enabled = var.postgresql_public_network_access_enabled
  
  # Maintenance window (perform maintenance during low-usage hours)
  maintenance_window {
    day_of_week  = 0  # Sunday
    start_hour   = 2  # 2 AM
    start_minute = 0
  }
  
  tags = merge(var.tags, {
    Purpose = "primary-database"
    Role    = "primary"
  })
  
  depends_on = [azurerm_resource_group.primary]
}

# Create firewall rules for PostgreSQL primary server
resource "azurerm_postgresql_flexible_server_firewall_rule" "primary_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.primary.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Create firewall rules for allowed IP ranges
resource "azurerm_postgresql_flexible_server_firewall_rule" "primary_allowed_ips" {
  count = length(var.allowed_ip_ranges)
  
  name             = "AllowedIPs-${count.index}"
  server_id        = azurerm_postgresql_flexible_server.primary.id
  start_ip_address = split("-", var.allowed_ip_ranges[count.index])[0]
  end_ip_address   = split("-", var.allowed_ip_ranges[count.index])[1]
}

# Create read replica in secondary region for disaster recovery
resource "azurerm_postgresql_flexible_server" "replica" {
  count = var.enable_read_replica ? 1 : 0
  
  name                = "psql-${var.resource_prefix}-${var.environment}-replica-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.secondary.name
  location            = azurerm_resource_group.secondary.location
  
  # Replica configuration
  create_mode               = "Replica"
  source_server_id          = azurerm_postgresql_flexible_server.primary.id
  replication_role          = "AsyncReplica"
  
  tags = merge(var.tags, {
    Purpose = "replica-database"
    Role    = "replica"
  })
  
  depends_on = [azurerm_resource_group.secondary, azurerm_postgresql_flexible_server.primary]
}

# Create firewall rules for PostgreSQL replica server
resource "azurerm_postgresql_flexible_server_firewall_rule" "replica_azure_services" {
  count = var.enable_read_replica ? 1 : 0
  
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.replica[0].id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Create firewall rules for replica allowed IP ranges
resource "azurerm_postgresql_flexible_server_firewall_rule" "replica_allowed_ips" {
  count = var.enable_read_replica ? length(var.allowed_ip_ranges) : 0
  
  name             = "AllowedIPs-${count.index}"
  server_id        = azurerm_postgresql_flexible_server.replica[0].id
  start_ip_address = split("-", var.allowed_ip_ranges[count.index])[0]
  end_ip_address   = split("-", var.allowed_ip_ranges[count.index])[1]
}

# Create primary backup vault for long-term retention
resource "azurerm_data_protection_backup_vault" "primary" {
  count = var.enable_backup_vault ? 1 : 0
  
  name                = "bv-${var.resource_prefix}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.primary.name
  location            = azurerm_resource_group.primary.location
  datastore_type      = "VaultStore"
  redundancy          = var.backup_vault_redundancy
  
  tags = merge(var.tags, {
    Purpose = "backup-vault"
    Role    = "primary"
  })
}

# Create secondary backup vault for cross-region backup
resource "azurerm_data_protection_backup_vault" "secondary" {
  count = var.enable_backup_vault ? 1 : 0
  
  name                = "bv-${var.resource_prefix}-${var.environment}-secondary-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.secondary.name
  location            = azurerm_resource_group.secondary.location
  datastore_type      = "VaultStore"
  redundancy          = var.backup_vault_redundancy
  
  tags = merge(var.tags, {
    Purpose = "backup-vault"
    Role    = "secondary"
  })
}

# Create backup policy for PostgreSQL
resource "azurerm_data_protection_backup_policy_postgresql" "main" {
  count = var.enable_backup_vault ? 1 : 0
  
  name     = "PostgreSQLBackupPolicy"
  vault_id = azurerm_data_protection_backup_vault.primary[0].id
  
  backup_repeating_time_intervals = ["R/2024-01-01T02:00:00+00:00/P1D"]
  
  default_retention_duration = "P${var.backup_policy_retention_days}D"
  
  time_zone = "UTC"
  
  retention_rule {
    name     = "Daily"
    duration = "P${var.backup_policy_retention_days}D"
    priority = 25
    
    criteria {
      absolute_criteria = "FirstOfDay"
    }
  }
  
  retention_rule {
    name     = "Weekly"
    duration = "P${var.backup_policy_retention_days * 4}D"
    priority = 20
    
    criteria {
      absolute_criteria = "FirstOfWeek"
    }
  }
  
  retention_rule {
    name     = "Monthly"
    duration = "P${var.backup_policy_retention_days * 12}D"
    priority = 15
    
    criteria {
      absolute_criteria = "FirstOfMonth"
    }
  }
}

# Configure diagnostic settings for PostgreSQL primary server
resource "azurerm_monitor_diagnostic_setting" "postgresql_primary" {
  count = var.enable_monitoring ? 1 : 0
  
  name                       = "PostgreSQLDiagnostics"
  target_resource_id         = azurerm_postgresql_flexible_server.primary.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  # Enable all log categories
  enabled_log {
    category_group = "allLogs"
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
  
  # Enable all metrics
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
}

# Configure diagnostic settings for PostgreSQL replica server
resource "azurerm_monitor_diagnostic_setting" "postgresql_replica" {
  count = var.enable_monitoring && var.enable_read_replica ? 1 : 0
  
  name                       = "PostgreSQLReplicaDiagnostics"
  target_resource_id         = azurerm_postgresql_flexible_server.replica[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  # Enable all log categories
  enabled_log {
    category_group = "allLogs"
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
  
  # Enable all metrics
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
}

# Create action group for disaster recovery notifications
resource "azurerm_monitor_action_group" "disaster_recovery" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = "DisasterRecoveryAlerts"
  resource_group_name = azurerm_resource_group.primary.name
  short_name          = "DRAlerts"
  
  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name                    = "DRTeam-${email_receiver.key}"
      email_address          = email_receiver.value
      use_common_alert_schema = true
    }
  }
  
  tags = merge(var.tags, {
    Purpose = "alerting"
  })
}

# Create alert rule for database connectivity issues
resource "azurerm_monitor_metric_alert" "connection_failures" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = "PostgreSQL-ConnectionFailures"
  resource_group_name = azurerm_resource_group.primary.name
  scopes              = [azurerm_postgresql_flexible_server.primary.id]
  description         = "Alert when PostgreSQL connection failures exceed threshold"
  
  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "connections_failed"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.connection_failures_threshold
  }
  
  window_size        = "PT5M"
  frequency          = "PT1M"
  severity           = 2
  
  action {
    action_group_id = azurerm_monitor_action_group.disaster_recovery[0].id
  }
  
  tags = merge(var.tags, {
    Purpose = "alerting"
    Type    = "connection-monitoring"
  })
}

# Create alert rule for high replication lag
resource "azurerm_monitor_metric_alert" "replication_lag" {
  count = var.enable_monitoring && var.enable_read_replica ? 1 : 0
  
  name                = "PostgreSQL-ReplicationLag"
  resource_group_name = azurerm_resource_group.primary.name
  scopes              = [azurerm_postgresql_flexible_server.primary.id]
  description         = "Alert when replication lag exceeds threshold"
  
  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "replica_lag"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.replication_lag_threshold_seconds
  }
  
  window_size        = "PT5M"
  frequency          = "PT1M"
  severity           = 1
  
  action {
    action_group_id = azurerm_monitor_action_group.disaster_recovery[0].id
  }
  
  tags = merge(var.tags, {
    Purpose = "alerting"
    Type    = "replication-monitoring"
  })
}

# Create alert rule for backup failures
resource "azurerm_monitor_metric_alert" "backup_failures" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = "PostgreSQL-BackupFailures"
  resource_group_name = azurerm_resource_group.primary.name
  scopes              = [azurerm_postgresql_flexible_server.primary.id]
  description         = "Alert when backup failures occur"
  
  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "backup_failures"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.backup_failures_threshold
  }
  
  window_size        = "PT15M"
  frequency          = "PT5M"
  severity           = 1
  
  action {
    action_group_id = azurerm_monitor_action_group.disaster_recovery[0].id
  }
  
  tags = merge(var.tags, {
    Purpose = "alerting"
    Type    = "backup-monitoring"
  })
}

# Create Azure Automation account for disaster recovery workflows
resource "azurerm_automation_account" "disaster_recovery" {
  count = var.enable_automation ? 1 : 0
  
  name                = "aa-${var.resource_prefix}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name
  sku_name            = var.automation_account_sku
  
  tags = merge(var.tags, {
    Purpose = "automation"
  })
}

# Create automation credential for PostgreSQL admin
resource "azurerm_automation_credential" "postgresql_admin" {
  count = var.enable_automation ? 1 : 0
  
  name                    = "PostgreSQLAdmin"
  resource_group_name     = azurerm_resource_group.primary.name
  automation_account_name = azurerm_automation_account.disaster_recovery[0].name
  username                = var.postgresql_admin_username
  password                = var.postgresql_admin_password
  description             = "PostgreSQL administrator credentials for disaster recovery"
}

# Create disaster recovery PowerShell runbook
resource "azurerm_automation_runbook" "disaster_recovery" {
  count = var.enable_automation ? 1 : 0
  
  name                    = "PostgreSQL-DisasterRecovery"
  location                = azurerm_resource_group.primary.location
  resource_group_name     = azurerm_resource_group.primary.name
  automation_account_name = azurerm_automation_account.disaster_recovery[0].name
  log_verbose             = true
  log_progress            = true
  description             = "Automated disaster recovery runbook for PostgreSQL"
  runbook_type            = "PowerShell"
  
  content = templatefile("${path.module}/scripts/disaster-recovery-runbook.ps1", {
    resource_group_primary   = azurerm_resource_group.primary.name
    resource_group_secondary = azurerm_resource_group.secondary.name
    replica_server_name      = var.enable_read_replica ? azurerm_postgresql_flexible_server.replica[0].name : ""
    primary_server_name      = azurerm_postgresql_flexible_server.primary.name
    storage_account_name     = azurerm_storage_account.backup_artifacts.name
  })
  
  tags = merge(var.tags, {
    Purpose = "automation"
    Type    = "disaster-recovery"
  })
}

# Create sample database with test data (if enabled)
resource "azurerm_postgresql_flexible_server_database" "sample" {
  count = var.create_sample_data ? 1 : 0
  
  name      = var.sample_database_name
  server_id = azurerm_postgresql_flexible_server.primary.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# Create sample tables and data using null_resource with local-exec
resource "null_resource" "sample_data" {
  count = var.create_sample_data ? 1 : 0
  
  depends_on = [
    azurerm_postgresql_flexible_server_database.sample,
    azurerm_postgresql_flexible_server_firewall_rule.primary_azure_services
  ]
  
  provisioner "local-exec" {
    command = templatefile("${path.module}/scripts/create-sample-data.sh", {
      server_fqdn    = azurerm_postgresql_flexible_server.primary.fqdn
      admin_username = var.postgresql_admin_username
      admin_password = var.postgresql_admin_password
      database_name  = var.sample_database_name
    })
    
    interpreter = ["bash", "-c"]
  }
  
  # Trigger recreation if database changes
  triggers = {
    database_id = azurerm_postgresql_flexible_server_database.sample[0].id
  }
}