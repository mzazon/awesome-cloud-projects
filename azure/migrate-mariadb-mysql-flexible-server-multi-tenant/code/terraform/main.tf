# Main Terraform Configuration for Azure MariaDB to MySQL Migration Infrastructure
# This file creates the complete infrastructure needed for migrating multi-tenant 
# database workloads from Azure Database for MariaDB to MySQL Flexible Server

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed resource names and configurations
locals {
  # Generate unique resource names with random suffix
  resource_suffix = lower(random_id.suffix.hex)
  
  # Compute resource names based on variables or generate unique names
  source_mariadb_name = var.source_mariadb_server_name != "" ? var.source_mariadb_server_name : "mariadb-source-${local.resource_suffix}"
  target_mysql_name   = var.target_mysql_server_name != "" ? var.target_mysql_server_name : "mysql-target-${local.resource_suffix}"
  
  # Storage and monitoring resource names
  storage_account_name = "migrationst${local.resource_suffix}"
  log_analytics_name   = "migration-logs-${local.resource_suffix}"
  app_insights_name    = "migration-insights-${local.resource_suffix}"
  
  # Combined tags for all resources
  tags = merge(var.common_tags, {
    Environment   = var.environment
    CreatedBy     = "Terraform"
    CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
    Migration     = "MariaDB-to-MySQL"
  })
  
  # Generate secure passwords if not provided
  mariadb_password = var.source_mariadb_admin_password != "" ? var.source_mariadb_admin_password : random_password.mariadb_admin.result
  mysql_password   = var.target_mysql_admin_password != "" ? var.target_mysql_admin_password : random_password.mysql_admin.result
}

# Generate secure random passwords for database administrators
resource "random_password" "mariadb_admin" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
}

resource "random_password" "mysql_admin" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
}

# Create Resource Group for all migration resources
resource "azurerm_resource_group" "migration" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

# Create Log Analytics Workspace for centralized logging and monitoring
resource "azurerm_log_analytics_workspace" "migration" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_retention_days
  
  tags = local.tags
}

# Create Application Insights for application performance monitoring
resource "azurerm_application_insights" "migration" {
  name                = local.app_insights_name
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  workspace_id        = azurerm_log_analytics_workspace.migration.id
  application_type    = "web"
  
  tags = local.tags
}

# Create Storage Account for migration artifacts and backups
resource "azurerm_storage_account" "migration" {
  count = var.enable_migration_storage ? 1 : 0
  
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.migration.name
  location                 = azurerm_resource_group.migration.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Enable advanced security features
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  # Configure blob properties for migration artifacts
  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.tags
}

# Create container for migration artifacts
resource "azurerm_storage_container" "migration_artifacts" {
  count = var.enable_migration_storage ? 1 : 0
  
  name                  = "migration-artifacts"
  storage_account_name  = azurerm_storage_account.migration[0].name
  container_access_type = "private"
}

# Create Source Azure Database for MariaDB Server (if needed for testing)
resource "azurerm_mariadb_server" "source" {
  name                = local.source_mariadb_name
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  
  administrator_login          = var.source_mariadb_admin_username
  administrator_login_password = local.mariadb_password
  
  sku_name   = "GP_Gen5_2"  # General Purpose, Generation 5, 2 vCores
  storage_mb = 102400       # 100 GB storage
  version    = "10.3"       # MariaDB version
  
  auto_grow_enabled                 = true
  backup_retention_days            = 7
  geo_redundant_backup_enabled     = false
  public_network_access_enabled    = var.enable_public_access
  ssl_enforcement_enabled          = true
  ssl_minimal_tls_version_enforced = "TLS1_2"
  
  tags = local.tags
}

# Create Target Azure Database for MySQL Flexible Server
resource "azurerm_mysql_flexible_server" "target" {
  name                = local.target_mysql_name
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  
  administrator_login    = var.target_mysql_admin_username
  administrator_password = local.mysql_password
  
  backup_retention_days = var.mysql_backup_retention_days
  geo_redundant_backup_enabled = false
  
  sku_name   = var.mysql_sku_name
  version    = var.mysql_version
  
  storage {
    auto_grow_enabled = var.enable_auto_grow
    size_gb          = var.mysql_storage_gb
  }
  
  # Configure high availability if enabled
  dynamic "high_availability" {
    for_each = var.enable_high_availability ? [1] : []
    content {
      mode = "ZoneRedundant"
    }
  }
  
  # Configure maintenance window
  maintenance_window {
    day_of_week  = 0  # Sunday
    start_hour   = 2  # 2 AM
    start_minute = 0
  }
  
  tags = local.tags
}

# Create MySQL Flexible Server Read Replica for migration support
resource "azurerm_mysql_flexible_server" "replica" {
  name                = "${local.target_mysql_name}-replica"
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  
  source_server_id = azurerm_mysql_flexible_server.target.id
  
  tags = local.tags
}

# Configure MySQL Flexible Server parameters for multi-tenant workloads
resource "azurerm_mysql_flexible_server_configuration" "max_connections" {
  name                = "max_connections"
  resource_group_name = azurerm_resource_group.migration.name
  server_name         = azurerm_mysql_flexible_server.target.name
  value               = "1000"
}

resource "azurerm_mysql_flexible_server_configuration" "innodb_buffer_pool_size" {
  name                = "innodb_buffer_pool_size"
  resource_group_name = azurerm_resource_group.migration.name
  server_name         = azurerm_mysql_flexible_server.target.name
  value               = "1073741824"  # 1GB
}

resource "azurerm_mysql_flexible_server_configuration" "query_cache_size" {
  name                = "query_cache_size"
  resource_group_name = azurerm_resource_group.migration.name
  server_name         = azurerm_mysql_flexible_server.target.name
  value               = "67108864"    # 64MB
}

resource "azurerm_mysql_flexible_server_configuration" "slow_query_log" {
  name                = "slow_query_log"
  resource_group_name = azurerm_resource_group.migration.name
  server_name         = azurerm_mysql_flexible_server.target.name
  value               = "ON"
}

resource "azurerm_mysql_flexible_server_configuration" "long_query_time" {
  name                = "long_query_log"
  resource_group_name = azurerm_resource_group.migration.name
  server_name         = azurerm_mysql_flexible_server.target.name
  value               = "2"
}

# Create firewall rules for database access
resource "azurerm_mariadb_firewall_rule" "source_rules" {
  count = length(var.allowed_ip_ranges)
  
  name                = var.allowed_ip_ranges[count.index].name
  resource_group_name = azurerm_resource_group.migration.name
  server_name         = azurerm_mariadb_server.source.name
  start_ip_address    = var.allowed_ip_ranges[count.index].start_ip
  end_ip_address      = var.allowed_ip_ranges[count.index].end_ip
}

resource "azurerm_mysql_flexible_server_firewall_rule" "target_rules" {
  count = length(var.allowed_ip_ranges)
  
  name             = var.allowed_ip_ranges[count.index].name
  resource_group_name = azurerm_resource_group.migration.name
  server_name      = azurerm_mysql_flexible_server.target.name
  start_ip_address = var.allowed_ip_ranges[count.index].start_ip
  end_ip_address   = var.allowed_ip_ranges[count.index].end_ip
}

# Configure diagnostic settings for source MariaDB server
resource "azurerm_monitor_diagnostic_setting" "mariadb_diagnostics" {
  name                       = "mariadb-diagnostics"
  target_resource_id         = azurerm_mariadb_server.source.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.migration.id
  
  # Enable audit logs
  enabled_log {
    category = "MySqlAuditLogs"
  }
  
  # Enable slow query logs
  enabled_log {
    category = "MySqlSlowLogs"
  }
  
  # Enable all metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Configure diagnostic settings for target MySQL Flexible Server
resource "azurerm_monitor_diagnostic_setting" "mysql_diagnostics" {
  name                       = "mysql-diagnostics"
  target_resource_id         = azurerm_mysql_flexible_server.target.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.migration.id
  
  # Enable audit logs
  enabled_log {
    category = "MySqlAuditLogs"
  }
  
  # Enable slow query logs
  enabled_log {
    category = "MySqlSlowLogs"
  }
  
  # Enable all metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create monitoring alerts for MySQL Flexible Server
resource "azurerm_monitor_metric_alert" "mysql_cpu_high" {
  count = var.enable_alerts ? 1 : 0
  
  name                = "MySQL-CPU-High"
  resource_group_name = azurerm_resource_group.migration.name
  scopes              = [azurerm_mysql_flexible_server.target.id]
  description         = "High CPU usage on MySQL Flexible Server"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.DBforMySQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_alert_threshold
  }
  
  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "mysql_connections_high" {
  count = var.enable_alerts ? 1 : 0
  
  name                = "MySQL-Connections-High"
  resource_group_name = azurerm_resource_group.migration.name
  scopes              = [azurerm_mysql_flexible_server.target.id]
  description         = "High connection count on MySQL Flexible Server"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.DBforMySQL/flexibleServers"
    metric_name      = "active_connections"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.connection_alert_threshold
  }
  
  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "mysql_storage_high" {
  count = var.enable_alerts ? 1 : 0
  
  name                = "MySQL-Storage-High"
  resource_group_name = azurerm_resource_group.migration.name
  scopes              = [azurerm_mysql_flexible_server.target.id]
  description         = "High storage usage on MySQL Flexible Server"
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"
  
  criteria {
    metric_namespace = "Microsoft.DBforMySQL/flexibleServers"
    metric_name      = "storage_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.storage_alert_threshold
  }
  
  tags = local.tags
}

# Create Action Group for alert notifications (email/SMS can be configured)
resource "azurerm_monitor_action_group" "migration_alerts" {
  count = var.enable_alerts ? 1 : 0
  
  name                = "migration-alerts"
  resource_group_name = azurerm_resource_group.migration.name
  short_name          = "migration"
  
  # Email notification configuration (customize as needed)
  email_receiver {
    name                    = "database-team"
    email_address          = "database-team@company.com"
    use_common_alert_schema = true
  }
  
  tags = local.tags
}

# Associate action group with metric alerts
resource "azurerm_monitor_metric_alert" "mysql_cpu_high_with_action" {
  count = var.enable_alerts ? 1 : 0
  
  name                = "MySQL-CPU-High-Action"
  resource_group_name = azurerm_resource_group.migration.name
  scopes              = [azurerm_mysql_flexible_server.target.id]
  description         = "High CPU usage on MySQL Flexible Server with action"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.DBforMySQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_alert_threshold
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.migration_alerts[0].id
  }
  
  tags = local.tags
}

# Create example databases on both servers for testing
resource "azurerm_mariadb_database" "tenant_databases" {
  count = 3  # Create 3 example tenant databases
  
  name                = "tenant_${count.index + 1}_db"
  resource_group_name = azurerm_resource_group.migration.name
  server_name         = azurerm_mariadb_server.source.name
  charset             = "utf8"
  collation          = "utf8_general_ci"
}

resource "azurerm_mysql_flexible_database" "target_databases" {
  count = 3  # Create corresponding databases on target
  
  name                = "tenant_${count.index + 1}_db"
  resource_group_name = azurerm_resource_group.migration.name
  server_name         = azurerm_mysql_flexible_server.target.name
  charset             = "utf8"
  collation          = "utf8_general_ci"
}

# Create Key Vault for storing database credentials securely
resource "azurerm_key_vault" "migration" {
  name                = "kv-migration-${local.resource_suffix}"
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  # Enable advanced security features
  enable_rbac_authorization       = true
  enabled_for_disk_encryption     = true
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  purge_protection_enabled        = false  # Set to true for production
  
  # Configure network access
  network_acls {
    default_action = "Allow"  # Restrict to specific networks in production
    bypass         = "AzureServices"
  }
  
  tags = local.tags
}

# Store database credentials in Key Vault
resource "azurerm_key_vault_secret" "mariadb_password" {
  name         = "mariadb-admin-password"
  value        = local.mariadb_password
  key_vault_id = azurerm_key_vault.migration.id
  
  tags = local.tags
}

resource "azurerm_key_vault_secret" "mysql_password" {
  name         = "mysql-admin-password"
  value        = local.mysql_password
  key_vault_id = azurerm_key_vault.migration.id
  
  tags = local.tags
}