# Enterprise-Grade Multi-Database ETL Orchestration with Azure Data Factory and MySQL
# This configuration deploys a complete ETL orchestration solution

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create Resource Group
resource "azurerm_resource_group" "etl_orchestration" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "etl_monitoring" {
  name                = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "la-etl-${random_string.suffix.result}"
  location            = azurerm_resource_group.etl_orchestration.location
  resource_group_name = azurerm_resource_group.etl_orchestration.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

# Create Key Vault for secure credential management
resource "azurerm_key_vault" "etl_secrets" {
  name                        = var.key_vault_name != "" ? var.key_vault_name : "kv-etl-${random_string.suffix.result}"
  location                    = azurerm_resource_group.etl_orchestration.location
  resource_group_name         = azurerm_resource_group.etl_orchestration.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = var.key_vault_soft_delete_retention_days
  purge_protection_enabled    = true
  sku_name                    = var.key_vault_sku
  tags                        = var.tags

  # Access policy for current user/service principal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
      "List",
      "Update",
      "Create",
      "Import",
      "Delete",
      "Recover",
      "Backup",
      "Restore"
    ]

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Recover",
      "Backup",
      "Restore"
    ]

    storage_permissions = [
      "Get",
      "List",
      "Update",
      "Delete",
      "Recover",
      "Backup",
      "Restore"
    ]
  }
}

# Store MySQL connection secrets in Key Vault
resource "azurerm_key_vault_secret" "mysql_source_connection" {
  name         = "mysql-source-connection-string"
  value        = var.source_mysql_connection_string
  key_vault_id = azurerm_key_vault.etl_secrets.id
  tags         = var.tags
}

resource "azurerm_key_vault_secret" "mysql_admin_username" {
  name         = "mysql-admin-username"
  value        = var.mysql_admin_username
  key_vault_id = azurerm_key_vault.etl_secrets.id
  tags         = var.tags
}

resource "azurerm_key_vault_secret" "mysql_admin_password" {
  name         = "mysql-admin-password"
  value        = var.mysql_admin_password
  key_vault_id = azurerm_key_vault.etl_secrets.id
  tags         = var.tags
}

# Create Azure Database for MySQL Flexible Server
resource "azurerm_mysql_flexible_server" "etl_target" {
  name                   = var.mysql_server_name != "" ? var.mysql_server_name : "mysql-target-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.etl_orchestration.name
  location               = azurerm_resource_group.etl_orchestration.location
  administrator_login    = var.mysql_admin_username
  administrator_password = var.mysql_admin_password
  backup_retention_days  = var.mysql_backup_retention_days
  sku_name               = var.mysql_sku_name
  version                = var.mysql_version
  zone                   = var.mysql_zone
  tags                   = var.tags

  storage {
    size_gb = var.mysql_storage_size_gb
  }

  # Enable high availability if specified
  dynamic "high_availability" {
    for_each = var.mysql_high_availability_enabled ? [1] : []
    content {
      mode                      = "ZoneRedundant"
      standby_availability_zone = var.mysql_standby_zone
    }
  }
}

# Configure MySQL server firewall rules
resource "azurerm_mysql_flexible_server_firewall_rule" "allow_azure_services" {
  name                = "AllowAzureServices"
  resource_group_name = azurerm_resource_group.etl_orchestration.name
  server_name         = azurerm_mysql_flexible_server.etl_target.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

# Create firewall rules for allowed IP ranges
resource "azurerm_mysql_flexible_server_firewall_rule" "allowed_ips" {
  count               = length(var.allowed_ip_ranges)
  name                = "AllowedIP-${count.index}"
  resource_group_name = azurerm_resource_group.etl_orchestration.name
  server_name         = azurerm_mysql_flexible_server.etl_target.name
  start_ip_address    = split("/", var.allowed_ip_ranges[count.index])[0]
  end_ip_address      = split("/", var.allowed_ip_ranges[count.index])[0]
}

# Create target database for consolidated data
resource "azurerm_mysql_flexible_database" "consolidated_data" {
  name                = var.target_database_name
  resource_group_name = azurerm_resource_group.etl_orchestration.name
  server_name         = azurerm_mysql_flexible_server.etl_target.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

# Create Azure Data Factory
resource "azurerm_data_factory" "etl_orchestration" {
  name                = var.data_factory_name != "" ? var.data_factory_name : "adf-etl-${random_string.suffix.result}"
  location            = azurerm_resource_group.etl_orchestration.location
  resource_group_name = azurerm_resource_group.etl_orchestration.name
  tags                = var.tags

  # Enable managed identity for secure authentication
  identity {
    type = "SystemAssigned"
  }

  # Configure public network access
  public_network_enabled = true
}

# Grant Data Factory access to Key Vault
resource "azurerm_key_vault_access_policy" "data_factory_access" {
  key_vault_id = azurerm_key_vault.etl_secrets.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_data_factory.etl_orchestration.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List"
  ]
}

# Create Self-Hosted Integration Runtime
resource "azurerm_data_factory_integration_runtime_self_hosted" "on_premises" {
  name            = var.self_hosted_ir_name
  data_factory_id = azurerm_data_factory.etl_orchestration.id
  description     = "Integration Runtime for on-premises MySQL connectivity"
}

# Create Key Vault Linked Service for Data Factory
resource "azurerm_data_factory_linked_service_key_vault" "etl_keyvault" {
  name            = "AzureKeyVaultLinkedService"
  data_factory_id = azurerm_data_factory.etl_orchestration.id
  key_vault_id    = azurerm_key_vault.etl_secrets.id
}

# Create MySQL Source Linked Service (On-premises)
resource "azurerm_data_factory_linked_service_mysql" "source_mysql" {
  name                     = "MySQLSourceLinkedService"
  data_factory_id          = azurerm_data_factory.etl_orchestration.id
  integration_runtime_name = azurerm_data_factory_integration_runtime_self_hosted.on_premises.name

  connection_string = "@{linkedService().connectionString}"
  
  parameters = {
    connectionString = "dummy" # This will be overridden by Key Vault reference
  }
}

# Create Azure MySQL Target Linked Service
resource "azurerm_data_factory_linked_service_mysql" "target_mysql" {
  name            = "MySQLTargetLinkedService"
  data_factory_id = azurerm_data_factory.etl_orchestration.id
  
  connection_string = "server=${azurerm_mysql_flexible_server.etl_target.fqdn};port=3306;database=${azurerm_mysql_flexible_database.consolidated_data.name};uid=${var.mysql_admin_username};pwd=${var.mysql_admin_password};sslmode=required"
}

# Create datasets for source and target
resource "azurerm_data_factory_dataset_mysql" "source_dataset" {
  name                = "MySQLSourceDataset"
  data_factory_id     = azurerm_data_factory.etl_orchestration.id
  linked_service_name = azurerm_data_factory_linked_service_mysql.source_mysql.name
  table_name          = "customers"
}

resource "azurerm_data_factory_dataset_mysql" "target_dataset" {
  name                = "MySQLTargetDataset"
  data_factory_id     = azurerm_data_factory.etl_orchestration.id
  linked_service_name = azurerm_data_factory_linked_service_mysql.target_mysql.name
  table_name          = "consolidated_customers"
}

# Create ETL Pipeline
resource "azurerm_data_factory_pipeline" "multi_database_etl" {
  name            = "MultiDatabaseETLPipeline"
  data_factory_id = azurerm_data_factory.etl_orchestration.id
  description     = "Enterprise ETL pipeline for multi-database orchestration"
  folder          = "ETL-Pipelines"

  parameters = {
    sourceServer = "onprem-mysql.domain.com"
    targetServer = azurerm_mysql_flexible_server.etl_target.fqdn
  }

  activities_json = jsonencode([
    {
      name = "CopyCustomerData"
      type = "Copy"
      dependsOn = []
      policy = {
        timeout = "7.00:00:00"
        retry   = 3
        retryIntervalInSeconds = 30
      }
      typeProperties = {
        source = {
          type  = "MySqlSource"
          query = "SELECT customer_id, customer_name, email, registration_date, last_login FROM customers WHERE last_modified >= DATE_SUB(NOW(), INTERVAL 1 DAY)"
        }
        sink = {
          type          = "MySqlSink"
          writeBehavior = "insert"
        }
        enableStaging  = false
        parallelCopies = 4
        dataIntegrationUnits = 8
      }
      inputs = [
        {
          referenceName = azurerm_data_factory_dataset_mysql.source_dataset.name
          type          = "DatasetReference"
        }
      ]
      outputs = [
        {
          referenceName = azurerm_data_factory_dataset_mysql.target_dataset.name
          type          = "DatasetReference"
        }
      ]
    }
  ])
}

# Create scheduled trigger for daily ETL operations
resource "azurerm_data_factory_trigger_schedule" "daily_etl" {
  name                = "DailyETLTrigger"
  data_factory_id     = azurerm_data_factory.etl_orchestration.id
  pipeline_name       = azurerm_data_factory_pipeline.multi_database_etl.name
  description         = "Daily ETL execution at 2 AM UTC"
  start_time          = "2025-01-01T02:00:00Z"
  time_zone           = "UTC"
  frequency           = "Day"
  interval            = 1
  
  schedule {
    hours   = [2]
    minutes = [0]
  }
  
  activated = true
}

# Configure diagnostic settings for Data Factory (if enabled)
resource "azurerm_monitor_diagnostic_setting" "data_factory_diagnostics" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "DataFactoryDiagnostics"
  target_resource_id         = azurerm_data_factory.etl_orchestration.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.etl_monitoring.id

  enabled_log {
    category = "PipelineRuns"
  }

  enabled_log {
    category = "ActivityRuns"
  }

  enabled_log {
    category = "TriggerRuns"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Configure diagnostic settings for MySQL server
resource "azurerm_monitor_diagnostic_setting" "mysql_diagnostics" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "MySQLDiagnostics"
  target_resource_id         = azurerm_mysql_flexible_server.etl_target.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.etl_monitoring.id

  enabled_log {
    category = "MySqlSlowLogs"
  }

  enabled_log {
    category = "MySqlAuditLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create action group for alert notifications (if email addresses provided)
resource "azurerm_monitor_action_group" "etl_alerts" {
  count               = length(var.alert_email_addresses) > 0 ? 1 : 0
  name                = "ETL-Alert-Group"
  resource_group_name = azurerm_resource_group.etl_orchestration.name
  short_name          = "ETL-Alerts"
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name          = "Email-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }
}

# Create metric alert for pipeline failures
resource "azurerm_monitor_metric_alert" "pipeline_failure_alert" {
  count               = var.enable_pipeline_failure_alert ? 1 : 0
  name                = "ETL-Pipeline-Failure-Alert"
  resource_group_name = azurerm_resource_group.etl_orchestration.name
  scopes              = [azurerm_data_factory.etl_orchestration.id]
  description         = "Alert when ETL pipeline fails"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.DataFactory/factories"
    metric_name      = "PipelineFailedRuns"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }

  dynamic "action" {
    for_each = length(var.alert_email_addresses) > 0 ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.etl_alerts[0].id
    }
  }
}

# Create Application Insights for additional monitoring
resource "azurerm_application_insights" "etl_insights" {
  name                = "ai-etl-${random_string.suffix.result}"
  location            = azurerm_resource_group.etl_orchestration.location
  resource_group_name = azurerm_resource_group.etl_orchestration.name
  workspace_id        = azurerm_log_analytics_workspace.etl_monitoring.id
  application_type    = "other"
  tags                = var.tags
}