# Outputs for Azure MariaDB to MySQL Migration Infrastructure
# This file defines all output values that provide important information
# about the created infrastructure resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.migration.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.migration.location
}

# Source MariaDB Server Information
output "source_mariadb_server_name" {
  description = "Name of the source Azure Database for MariaDB server"
  value       = azurerm_mariadb_server.source.name
}

output "source_mariadb_fqdn" {
  description = "Fully Qualified Domain Name of the source MariaDB server"
  value       = azurerm_mariadb_server.source.fqdn
}

output "source_mariadb_admin_username" {
  description = "Administrator username for source MariaDB server"
  value       = azurerm_mariadb_server.source.administrator_login
  sensitive   = true
}

output "source_mariadb_version" {
  description = "Version of the source MariaDB server"
  value       = azurerm_mariadb_server.source.version
}

# Target MySQL Flexible Server Information
output "target_mysql_server_name" {
  description = "Name of the target Azure Database for MySQL Flexible Server"
  value       = azurerm_mysql_flexible_server.target.name
}

output "target_mysql_fqdn" {
  description = "Fully Qualified Domain Name of the target MySQL Flexible Server"
  value       = azurerm_mysql_flexible_server.target.fqdn
}

output "target_mysql_admin_username" {
  description = "Administrator username for target MySQL Flexible Server"
  value       = azurerm_mysql_flexible_server.target.administrator_login
  sensitive   = true
}

output "target_mysql_version" {
  description = "Version of the target MySQL Flexible Server"
  value       = azurerm_mysql_flexible_server.target.version
}

output "target_mysql_sku_name" {
  description = "SKU name of the target MySQL Flexible Server"
  value       = azurerm_mysql_flexible_server.target.sku_name
}

output "target_mysql_storage_gb" {
  description = "Storage size in GB of the target MySQL Flexible Server"
  value       = azurerm_mysql_flexible_server.target.storage[0].size_gb
}

# Read Replica Information
output "mysql_replica_server_name" {
  description = "Name of the MySQL Flexible Server read replica"
  value       = azurerm_mysql_flexible_server.replica.name
}

output "mysql_replica_fqdn" {
  description = "Fully Qualified Domain Name of the MySQL read replica"
  value       = azurerm_mysql_flexible_server.replica.fqdn
}

# Database Information
output "tenant_databases_mariadb" {
  description = "List of tenant databases created on MariaDB server"
  value       = azurerm_mariadb_database.tenant_databases[*].name
}

output "tenant_databases_mysql" {
  description = "List of tenant databases created on MySQL Flexible Server"
  value       = azurerm_mysql_flexible_database.target_databases[*].name
}

# Storage Account Information
output "migration_storage_account_name" {
  description = "Name of the storage account for migration artifacts"
  value       = var.enable_migration_storage ? azurerm_storage_account.migration[0].name : null
}

output "migration_storage_primary_endpoint" {
  description = "Primary blob endpoint of the migration storage account"
  value       = var.enable_migration_storage ? azurerm_storage_account.migration[0].primary_blob_endpoint : null
}

output "migration_storage_connection_string" {
  description = "Connection string for the migration storage account"
  value       = var.enable_migration_storage ? azurerm_storage_account.migration[0].primary_connection_string : null
  sensitive   = true
}

# Monitoring and Logging Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.migration.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.migration.workspace_id
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.migration.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.migration.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.migration.connection_string
  sensitive   = true
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault for storing credentials"
  value       = azurerm_key_vault.migration.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.migration.vault_uri
}

# Alert Configuration Information
output "monitoring_alerts_enabled" {
  description = "Whether monitoring alerts are enabled"
  value       = var.enable_alerts
}

output "cpu_alert_threshold" {
  description = "CPU usage threshold for alerts"
  value       = var.cpu_alert_threshold
}

output "connection_alert_threshold" {
  description = "Connection count threshold for alerts"
  value       = var.connection_alert_threshold
}

output "storage_alert_threshold" {
  description = "Storage usage threshold for alerts"
  value       = var.storage_alert_threshold
}

# Connection Information for Applications
output "mariadb_connection_info" {
  description = "Connection information for MariaDB server"
  value = {
    server   = azurerm_mariadb_server.source.fqdn
    port     = 3306
    username = azurerm_mariadb_server.source.administrator_login
    ssl_mode = "REQUIRED"
  }
  sensitive = true
}

output "mysql_connection_info" {
  description = "Connection information for MySQL Flexible Server"
  value = {
    server   = azurerm_mysql_flexible_server.target.fqdn
    port     = 3306
    username = azurerm_mysql_flexible_server.target.administrator_login
    ssl_mode = "REQUIRED"
  }
  sensitive = true
}

# High Availability Configuration
output "mysql_high_availability_enabled" {
  description = "Whether high availability is enabled for MySQL Flexible Server"
  value       = var.enable_high_availability
}

output "mysql_backup_retention_days" {
  description = "Backup retention period for MySQL Flexible Server"
  value       = azurerm_mysql_flexible_server.target.backup_retention_days
}

# Migration Configuration Summary
output "migration_configuration_summary" {
  description = "Summary of migration configuration"
  value = {
    source_server_type    = "Azure Database for MariaDB"
    target_server_type    = "Azure Database for MySQL Flexible Server"
    source_version        = azurerm_mariadb_server.source.version
    target_version        = azurerm_mysql_flexible_server.target.version
    tenant_databases      = length(azurerm_mariadb_database.tenant_databases)
    high_availability     = var.enable_high_availability
    monitoring_enabled    = true
    alerts_enabled        = var.enable_alerts
    storage_auto_grow     = var.enable_auto_grow
    backup_retention_days = var.mysql_backup_retention_days
  }
}

# Resource Tags
output "resource_tags" {
  description = "Tags applied to all resources"
  value       = local.tags
}

# Migration Helper Scripts (to be created separately)
output "migration_script_commands" {
  description = "Example commands for performing the migration"
  value = {
    # MyDumper export command
    export_command = "mydumper --host=${azurerm_mariadb_server.source.fqdn} --user=${azurerm_mariadb_server.source.administrator_login} --port=3306 --outputdir=./migration-data --compress --build-empty-files --routines --events --triggers --complete-insert --single-transaction --less-locking --threads=4"
    
    # MyLoader import command
    import_command = "myloader --host=${azurerm_mysql_flexible_server.target.fqdn} --user=${azurerm_mysql_flexible_server.target.administrator_login} --port=3306 --directory=./migration-data --queries-per-transaction=1000 --threads=4 --compress-protocol --enable-binlog --overwrite-tables"
    
    # Connection test commands
    test_mariadb = "mysql -h ${azurerm_mariadb_server.source.fqdn} -u ${azurerm_mariadb_server.source.administrator_login} -p -e 'SELECT VERSION(); SHOW DATABASES;'"
    test_mysql   = "mysql -h ${azurerm_mysql_flexible_server.target.fqdn} -u ${azurerm_mysql_flexible_server.target.administrator_login} -p -e 'SELECT VERSION(); SHOW DATABASES;'"
  }
  sensitive = true
}

# Cost Optimization Information
output "cost_optimization_notes" {
  description = "Information about cost optimization features"
  value = {
    auto_grow_enabled     = var.enable_auto_grow
    backup_retention_days = var.mysql_backup_retention_days
    storage_tier         = var.storage_account_tier
    sku_name            = var.mysql_sku_name
    high_availability   = var.enable_high_availability ? "Zone-redundant (99.99% SLA)" : "Standard (99.9% SLA)"
  }
}