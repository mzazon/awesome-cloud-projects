# Azure Multi-Tenant Database Architecture with Elastic Pools and Backup Vault
# This configuration creates a cost-optimized multi-tenant database architecture using Azure services

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Generate secure password for SQL Server if not provided
resource "random_password" "sql_admin_password" {
  count   = var.sql_admin_password == "" ? 1 : 0
  length  = 20
  special = true
  
  # Ensure password meets SQL Server complexity requirements
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
  min_special = 1
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with consistent prefix and random suffix
  resource_prefix = "${var.project_name}-${var.environment}"
  random_suffix   = random_string.suffix.result
  
  # Final SQL admin password (either provided or generated)
  sql_admin_password = var.sql_admin_password != "" ? var.sql_admin_password : random_password.sql_admin_password[0].result
  
  # Merged tags for all resources
  common_tags = merge(var.tags, var.additional_tags, {
    Environment = var.environment
    Project     = var.project_name
    CreatedBy   = "terraform"
    CreatedOn   = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Cost management configuration
  budget_start_date = formatdate("YYYY-MM-01", timestamp())
  budget_end_date   = formatdate("YYYY-MM-01", timeadd(timestamp(), "8760h")) # 1 year from now
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Data source to get the current subscription
data "azurerm_subscription" "current" {}

# Resource Group for all multi-tenant database resources
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.resource_prefix}-${local.random_suffix}"
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for monitoring and diagnostics
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${local.resource_prefix}-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

# Application Insights for application performance monitoring
resource "azurerm_application_insights" "main" {
  name                = "ai-${local.resource_prefix}-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = local.common_tags
}

# Azure SQL Server for hosting elastic pool and tenant databases
resource "azurerm_mssql_server" "main" {
  name                         = "sqlserver-${local.resource_prefix}-${local.random_suffix}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = local.sql_admin_password
  minimum_tls_version          = var.minimum_tls_version
  
  # Enable Azure Active Directory authentication
  azuread_administrator {
    login_username              = "sqldbadmin"
    object_id                   = data.azurerm_client_config.current.object_id
    tenant_id                   = data.azurerm_client_config.current.tenant_id
    azuread_authentication_only = false
  }
  
  # Advanced security configurations
  public_network_access_enabled = true
  outbound_network_restriction_enabled = false
  
  tags = local.common_tags
}

# SQL Server firewall rule to allow Azure services
resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Additional firewall rules for allowed IP ranges
resource "azurerm_mssql_firewall_rule" "allowed_ips" {
  count            = length(var.allowed_ip_ranges)
  name             = var.allowed_ip_ranges[count.index].name
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = var.allowed_ip_ranges[count.index].start_ip
  end_ip_address   = var.allowed_ip_ranges[count.index].end_ip
}

# Azure SQL Database Elastic Pool for cost-optimized multi-tenant architecture
resource "azurerm_mssql_elasticpool" "main" {
  name                = "elasticpool-${local.resource_prefix}-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  server_name         = azurerm_mssql_server.main.name
  license_type        = "LicenseIncluded"
  max_size_gb         = var.elastic_pool_storage_mb / 1024
  
  # DTU-based configuration for Standard tier
  sku {
    name     = "StandardPool"
    tier     = var.elastic_pool_edition
    capacity = var.elastic_pool_dtu
  }
  
  # Per-database DTU limits for cost optimization
  per_database_settings {
    min_capacity = var.database_dtu_min
    max_capacity = var.database_dtu_max
  }
  
  tags = local.common_tags
}

# Tenant databases within the elastic pool
resource "azurerm_mssql_database" "tenant_databases" {
  count               = var.tenant_count
  name                = "tenant-${count.index + 1}-db-${local.random_suffix}"
  server_id           = azurerm_mssql_server.main.id
  elastic_pool_id     = azurerm_mssql_elasticpool.main.id
  collation           = var.tenant_database_collation
  license_type        = "LicenseIncluded"
  zone_redundant      = false
  
  # Enable Query Store for performance monitoring
  query_store_settings {
    enabled                    = var.enable_query_store
    retention_period_in_days   = 30
    size_limit_in_mb          = 100
    capture_mode              = "All"
    data_flush_interval_in_minutes = 15
  }
  
  tags = merge(local.common_tags, {
    TenantId = "tenant-${count.index + 1}"
    DatabaseType = "tenant-database"
  })
}

# Configure automatic tuning for the SQL Server
resource "azurerm_mssql_server_extended_auditing_policy" "main" {
  server_id              = azurerm_mssql_server.main.id
  storage_endpoint       = azurerm_storage_account.audit.primary_blob_endpoint
  storage_account_access_key = azurerm_storage_account.audit.primary_access_key
  storage_account_access_key_is_secondary = false
  retention_in_days      = 90
  log_monitoring_enabled = true
}

# Storage account for SQL audit logs
resource "azurerm_storage_account" "audit" {
  name                     = "staudit${replace(local.resource_prefix, "-", "")}${local.random_suffix}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  
  # Security configurations
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  blob_properties {
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }
  
  tags = local.common_tags
}

# Recovery Services Vault for backup management
resource "azurerm_recovery_services_vault" "main" {
  name                = "rsv-${local.resource_prefix}-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  storage_mode_type   = var.backup_storage_redundancy
  cross_region_restore_enabled = var.backup_storage_redundancy == "GeoRedundant" ? true : false
  
  # Enhanced security features
  encryption {
    key_id                            = null
    infrastructure_encryption_enabled = true
    use_system_assigned_identity      = true
  }
  
  tags = local.common_tags
}

# Data Protection Backup Vault for modern backup capabilities
resource "azurerm_data_protection_backup_vault" "main" {
  name                = "bv-${local.resource_prefix}-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  datastore_type      = "VaultStore"
  redundancy          = var.backup_storage_redundancy
  
  # Enhanced identity configuration
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Backup policy for SQL databases
resource "azurerm_data_protection_backup_policy_postgresql" "sql_policy" {
  name     = "sql-database-policy"
  vault_id = azurerm_data_protection_backup_vault.main.id
  
  backup_repeating_time_intervals = ["R/2024-01-01T02:00:00+00:00/P1D"]
  
  retention_rule {
    name     = "Daily"
    priority = 25
    
    life_cycle {
      duration        = "P${var.backup_retention_days}D"
      data_store_type = "VaultStore"
    }
    
    criteria {
      absolute_criteria = "FirstOfDay"
    }
  }
  
  retention_rule {
    name     = "Weekly"
    priority = 20
    
    life_cycle {
      duration        = "P12W"
      data_store_type = "VaultStore"
    }
    
    criteria {
      absolute_criteria = "FirstOfWeek"
    }
  }
  
  retention_rule {
    name     = "Monthly"
    priority = 15
    
    life_cycle {
      duration        = "P12M"
      data_store_type = "VaultStore"
    }
    
    criteria {
      absolute_criteria = "FirstOfMonth"
    }
  }
}

# Consumption budget for cost management
resource "azurerm_consumption_budget_resource_group" "main" {
  name              = "budget-${local.resource_prefix}-${local.random_suffix}"
  resource_group_id = azurerm_resource_group.main.id
  
  amount     = var.monthly_budget_amount
  time_grain = "Monthly"
  
  time_period {
    start_date = local.budget_start_date
    end_date   = local.budget_end_date
  }
  
  # Budget notification at configured threshold
  notification {
    enabled        = true
    threshold      = var.budget_alert_threshold
    operator       = "GreaterThan"
    threshold_type = "Actual"
    
    contact_emails = []
    
    contact_groups = []
    contact_roles  = ["Owner", "Contributor"]
  }
  
  # Additional notification for forecasted spend
  notification {
    enabled        = true
    threshold      = var.budget_alert_threshold
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    
    contact_emails = []
    
    contact_groups = []
    contact_roles  = ["Owner", "Contributor"]
  }
}

# Monitor Action Group for alerts
resource "azurerm_monitor_action_group" "cost_alerts" {
  name                = "cost-alert-group-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "CostAlert"
  
  tags = local.common_tags
}

# Diagnostic settings for SQL Server
resource "azurerm_monitor_diagnostic_setting" "sql_server" {
  name                       = "sql-server-diagnostics"
  target_resource_id         = azurerm_mssql_server.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable all available log categories
  enabled_log {
    category = "DevOpsOperationsAudit"
  }
  
  enabled_log {
    category = "SQLSecurityAuditEvents"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
}

# Diagnostic settings for Elastic Pool
resource "azurerm_monitor_diagnostic_setting" "elastic_pool" {
  name                       = "elastic-pool-diagnostics"
  target_resource_id         = azurerm_mssql_elasticpool.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable database metrics and insights
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
  
  # Enable all metrics
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
}

# Time delay to ensure SQL Server is ready for configuration
resource "time_sleep" "sql_server_ready" {
  depends_on      = [azurerm_mssql_server.main]
  create_duration = "30s"
}

# Configure automatic tuning for performance optimization
resource "azurerm_mssql_server_automatic_tuning" "main" {
  server_id = azurerm_mssql_server.main.id
  
  # Enable automatic tuning options
  tuning_options = {
    "create_index"  = "On"
    "drop_index"    = "On"
    "force_plan"    = "On"
  }
  
  depends_on = [time_sleep.sql_server_ready]
}

# SQL Server vulnerability assessment baseline
resource "azurerm_mssql_server_vulnerability_assessment" "main" {
  server_security_alert_policy_id = azurerm_mssql_server_security_alert_policy.main.id
  storage_container_path          = "${azurerm_storage_account.audit.primary_blob_endpoint}vulnerability-assessment/"
  storage_account_access_key      = azurerm_storage_account.audit.primary_access_key
  
  recurring_scans {
    enabled                   = true
    email_subscription_admins = true
    emails                    = []
  }
}

# SQL Server security alert policy
resource "azurerm_mssql_server_security_alert_policy" "main" {
  resource_group_name = azurerm_resource_group.main.name
  server_name         = azurerm_mssql_server.main.name
  state               = "Enabled"
  
  # Enable all threat detection types
  disabled_alerts = []
  
  # Email notifications
  email_subscription_admins = true
  email_addresses          = []
  
  # Storage configuration for threat detection logs
  storage_endpoint           = azurerm_storage_account.audit.primary_blob_endpoint
  storage_account_access_key = azurerm_storage_account.audit.primary_access_key
  retention_days             = 30
}

# Sample schema deployment using null_resource (optional)
resource "null_resource" "deploy_sample_schema" {
  count = var.tenant_count > 0 ? 1 : 0
  
  # This resource will run a local script to deploy sample schema
  # In production, this would typically be handled by application deployment pipelines
  provisioner "local-exec" {
    command = <<-EOT
      echo "Sample schema deployment would happen here"
      echo "Database: ${azurerm_mssql_database.tenant_databases[0].name}"
      echo "Server: ${azurerm_mssql_server.main.name}"
      echo "This would typically involve:"
      echo "- Creating tenant-aware tables"
      echo "- Setting up indexes for multi-tenant queries"
      echo "- Configuring row-level security (if needed)"
      echo "- Deploying stored procedures and functions"
    EOT
  }
  
  depends_on = [
    azurerm_mssql_database.tenant_databases,
    azurerm_mssql_elasticpool.main
  ]
  
  triggers = {
    database_ids = jsonencode([for db in azurerm_mssql_database.tenant_databases : db.id])
  }
}