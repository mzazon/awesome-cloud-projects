# Azure Hybrid PostgreSQL Database Replication Infrastructure
# This Terraform configuration deploys a complete hybrid PostgreSQL replication solution
# using Azure Arc-enabled Data Services, Azure Database for PostgreSQL, Event Grid, and Data Factory

# Current Azure subscription and client data
data "azurerm_client_config" "current" {}

# Generate random suffix for resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  # Generate unique resource names
  resource_group_name         = coalesce(var.resource_group_name, "rg-${var.project_name}-${random_string.suffix.result}")
  azure_postgresql_name       = "azpg-${var.project_name}-${random_string.suffix.result}"
  data_factory_name          = coalesce(var.data_factory_name, "adf-${var.project_name}-${random_string.suffix.result}")
  event_grid_topic_name      = coalesce(var.event_grid_topic_name, "eg-${var.project_name}-${random_string.suffix.result}")
  key_vault_name             = coalesce(var.key_vault_name, "kv-${var.project_name}-${random_string.suffix.result}")
  log_analytics_workspace_name = coalesce(var.log_analytics_workspace_name, "law-${var.project_name}-${random_string.suffix.result}")
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    "Environment"   = var.environment
    "Project"       = var.project_name
    "DeployedBy"    = "Terraform"
    "LastModified"  = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Create the main resource group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Log Analytics workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

# Create Key Vault for storing secrets
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  
  sku_name = var.key_vault_sku
  
  enabled_for_disk_encryption     = var.key_vault_enabled_for_disk_encryption
  enabled_for_template_deployment = var.key_vault_enabled_for_template_deployment
  purge_protection_enabled        = var.key_vault_purge_protection_enabled
  
  tags = local.common_tags
}

# Grant current user access to Key Vault
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  key_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Purge", "Recover"
  ]
  
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Purge", "Recover"
  ]
  
  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Purge", "Recover"
  ]
}

# Store PostgreSQL admin password in Key Vault
resource "azurerm_key_vault_secret" "postgresql_password" {
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  name         = "postgresql-admin-password"
  value        = var.postgresql_admin_password
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags
}

# Create Azure Database for PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "main" {
  name                = local.azure_postgresql_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  administrator_login    = var.postgresql_admin_username
  administrator_password = var.postgresql_admin_password
  
  sku_name   = var.azure_postgresql_sku
  storage_mb = var.azure_postgresql_storage_mb
  version    = var.postgresql_version
  
  backup_retention_days = var.backup_retention_days
  
  dynamic "high_availability" {
    for_each = var.high_availability_enabled ? [1] : []
    content {
      mode = "ZoneRedundant"
    }
  }
  
  tags = local.common_tags
}

# Configure PostgreSQL server parameters for logical replication
resource "azurerm_postgresql_flexible_server_configuration" "wal_level" {
  name      = "wal_level"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "logical"
}

resource "azurerm_postgresql_flexible_server_configuration" "max_wal_senders" {
  name      = "max_wal_senders"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "10"
}

resource "azurerm_postgresql_flexible_server_configuration" "max_replication_slots" {
  name      = "max_replication_slots"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "10"
}

# Configure SSL enforcement
resource "azurerm_postgresql_flexible_server_configuration" "require_secure_transport" {
  count = var.enable_ssl ? 1 : 0
  
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "on"
}

# Create firewall rules for PostgreSQL
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure_services" {
  count = var.enable_firewall_rules ? 1 : 0
  
  name             = "allow-azure-services"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "allowed_ips" {
  count = var.enable_firewall_rules ? length(var.allowed_ip_ranges) : 0
  
  name             = "allowed-ip-range-${count.index}"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = split("/", var.allowed_ip_ranges[count.index])[0]
  end_ip_address   = split("/", var.allowed_ip_ranges[count.index])[0]
}

# Create Event Grid topic for change notifications
resource "azurerm_eventgrid_topic" "main" {
  name                = local.event_grid_topic_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = local.common_tags
}

# Create Data Factory for orchestrating replication
resource "azurerm_data_factory" "main" {
  name                = local.data_factory_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  public_network_enabled                 = var.data_factory_public_network_enabled
  managed_virtual_network_enabled        = var.data_factory_managed_virtual_network_enabled
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Grant Data Factory access to Key Vault
resource "azurerm_key_vault_access_policy" "data_factory" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_data_factory.main.identity[0].principal_id
  
  secret_permissions = [
    "Get", "List"
  ]
}

# Create Data Factory linked service for Key Vault
resource "azurerm_data_factory_linked_service_key_vault" "main" {
  name            = "KeyVaultLinkedService"
  data_factory_id = azurerm_data_factory.main.id
  key_vault_id    = azurerm_key_vault.main.id
}

# Create Data Factory linked service for Azure PostgreSQL
resource "azurerm_data_factory_linked_service_postgresql" "azure_postgresql" {
  name            = "AzurePostgreSQLLinkedService"
  data_factory_id = azurerm_data_factory.main.id
  
  connection_string = "Host=${azurerm_postgresql_flexible_server.main.fqdn};Database=postgres;Username=${var.postgresql_admin_username};Port=5432;SSL Mode=Require;Trust Server Certificate=true"
  
  key_vault_password {
    linked_service_name = azurerm_data_factory_linked_service_key_vault.main.name
    secret_name         = azurerm_key_vault_secret.postgresql_password.name
  }
}

# Create Data Factory dataset for Azure PostgreSQL
resource "azurerm_data_factory_dataset_postgresql" "azure_postgresql" {
  name            = "AzurePostgreSQLDataset"
  data_factory_id = azurerm_data_factory.main.id
  linked_service_name = azurerm_data_factory_linked_service_postgresql.azure_postgresql.name
  
  table_name = "replicated_tables"
}

# Create Data Factory pipeline for replication
resource "azurerm_data_factory_pipeline" "replication" {
  name            = "HybridPostgreSQLReplicationPipeline"
  data_factory_id = azurerm_data_factory.main.id
  
  description = "Pipeline for replicating data from Arc-enabled PostgreSQL to Azure Database for PostgreSQL"
  
  parameters = {
    "lastSyncTime" = "2024-01-01T00:00:00Z"
    "sourceTable"  = "replicated_tables"
    "targetTable"  = "replicated_tables"
  }
  
  activities_json = jsonencode([
    {
      name = "CheckSourceData"
      type = "Lookup"
      typeProperties = {
        source = {
          type = "PostgreSqlSource"
          query = "SELECT COUNT(*) as record_count FROM @{pipeline().parameters.sourceTable} WHERE last_modified > '@{pipeline().parameters.lastSyncTime}'"
        }
        dataset = {
          referenceName = "ArcPostgreSQLDataset"
          type = "DatasetReference"
        }
      }
    },
    {
      name = "CopyData"
      type = "Copy"
      dependsOn = [
        {
          activity = "CheckSourceData"
          dependencyConditions = ["Succeeded"]
        }
      ]
      policy = {
        timeout = "7.00:00:00"
        retry = 3
        retryIntervalInSeconds = 30
      }
      typeProperties = {
        source = {
          type = "PostgreSqlSource"
          query = "SELECT * FROM @{pipeline().parameters.sourceTable} WHERE last_modified > '@{pipeline().parameters.lastSyncTime}'"
        }
        sink = {
          type = "AzurePostgreSqlSink"
          writeBatchSize = 10000
          writeBatchTimeout = "00:30:00"
          upsertSettings = {
            useTempDB = false
            interimSchemaName = "interim"
            keys = ["id"]
          }
        }
        enableStaging = false
        enableSkipIncompatibleRow = true
        logSettings = {
          enableCopyActivityLog = true
          logLevel = "Info"
        }
      }
      inputs = [
        {
          referenceName = "ArcPostgreSQLDataset"
          type = "DatasetReference"
        }
      ]
      outputs = [
        {
          referenceName = azurerm_data_factory_dataset_postgresql.azure_postgresql.name
          type = "DatasetReference"
        }
      ]
    }
  ])
}

# Create Data Factory trigger for scheduled replication
resource "azurerm_data_factory_trigger_schedule" "replication" {
  name            = "ReplicationScheduleTrigger"
  data_factory_id = azurerm_data_factory.main.id
  
  description = "Scheduled trigger for hybrid PostgreSQL replication"
  
  schedule {
    frequency = "Minute"
    interval  = 5
  }
  
  pipeline_name = azurerm_data_factory_pipeline.replication.name
  
  pipeline_parameters = {
    "lastSyncTime" = "@trigger().scheduledTime"
  }
  
  activated = true
}

# Create service principal for Arc Data Controller (if enabled)
resource "azuread_application" "arc_data_controller" {
  count = var.create_service_principal ? 1 : 0
  
  display_name = "sp-arc-dc-${var.project_name}-${random_string.suffix.result}"
  
  description = "Service principal for Azure Arc Data Controller"
}

resource "azuread_service_principal" "arc_data_controller" {
  count = var.create_service_principal ? 1 : 0
  
  client_id = azuread_application.arc_data_controller[0].client_id
  
  description = "Service principal for Azure Arc Data Controller"
}

resource "azuread_service_principal_password" "arc_data_controller" {
  count = var.create_service_principal ? 1 : 0
  
  service_principal_id = azuread_service_principal.arc_data_controller[0].id
  
  description = "Password for Arc Data Controller service principal"
}

# Assign Contributor role to service principal
resource "azurerm_role_assignment" "arc_data_controller" {
  count = var.create_service_principal ? 1 : 0
  
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.arc_data_controller[0].id
}

# Store service principal credentials in Key Vault
resource "azurerm_key_vault_secret" "arc_sp_client_id" {
  count = var.create_service_principal ? 1 : 0
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  name         = "arc-sp-client-id"
  value        = azuread_application.arc_data_controller[0].client_id
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags
}

resource "azurerm_key_vault_secret" "arc_sp_client_secret" {
  count = var.create_service_principal ? 1 : 0
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  name         = "arc-sp-client-secret"
  value        = azuread_service_principal_password.arc_data_controller[0].value
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags
}

resource "azurerm_key_vault_secret" "arc_sp_tenant_id" {
  count = var.create_service_principal ? 1 : 0
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  name         = "arc-sp-tenant-id"
  value        = data.azurerm_client_config.current.tenant_id
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags
}

# Create Kubernetes namespace for Arc data services
resource "kubernetes_namespace" "arc_data" {
  metadata {
    name = var.kubernetes_namespace
    
    labels = {
      name        = var.kubernetes_namespace
      environment = var.environment
      project     = var.project_name
    }
  }
}

# Create Kubernetes secret for Arc Data Controller service principal
resource "kubernetes_secret" "arc_sp_credentials" {
  count = var.create_service_principal ? 1 : 0
  
  metadata {
    name      = "arc-sp-credentials"
    namespace = kubernetes_namespace.arc_data.metadata[0].name
  }
  
  data = {
    client_id     = azuread_application.arc_data_controller[0].client_id
    client_secret = azuread_service_principal_password.arc_data_controller[0].value
    tenant_id     = data.azurerm_client_config.current.tenant_id
  }
  
  type = "Opaque"
}

# Create Kubernetes ConfigMap for Arc PostgreSQL configuration
resource "kubernetes_config_map" "arc_postgres_config" {
  metadata {
    name      = "arc-postgres-config"
    namespace = kubernetes_namespace.arc_data.metadata[0].name
  }
  
  data = {
    "postgres-config.yaml" = templatefile("${path.module}/templates/postgres-config.yaml.tpl", {
      postgres_name              = var.arc_postgres_name
      postgres_version           = var.postgresql_version
      replicas                   = var.arc_postgres_replicas
      cpu_requests               = var.arc_postgres_cpu_requests
      cpu_limits                 = var.arc_postgres_cpu_limits
      memory_requests            = var.arc_postgres_memory_requests
      memory_limits              = var.arc_postgres_memory_limits
      storage_size               = var.arc_postgres_storage_size
      logs_storage_size          = var.arc_postgres_logs_storage_size
      storage_class              = var.kubernetes_storage_class
      admin_password             = var.postgresql_admin_password
      kubernetes_namespace       = var.kubernetes_namespace
    })
  }
}

# Create Azure Monitor alert for replication lag
resource "azurerm_monitor_metric_alert" "replication_lag" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = "alert-replication-lag-${var.project_name}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_postgresql_flexible_server.main.id]
  
  description = "Alert when replication lag exceeds threshold"
  
  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "replica_lag_in_seconds"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.replication_lag_threshold_seconds
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
}

# Create Azure Monitor action group for alerts
resource "azurerm_monitor_action_group" "main" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = "ag-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "ag-${substr(var.project_name, 0, 8)}"
  
  tags = local.common_tags
}

# Configure diagnostic settings for Azure PostgreSQL
resource "azurerm_monitor_diagnostic_setting" "postgresql" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name               = "postgresql-diagnostics"
  target_resource_id = azurerm_postgresql_flexible_server.main.id
  log_analytics_workspace_id = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
  
  enabled_log {
    category = "PostgreSQLLogs"
  }
  
  enabled_log {
    category = "PostgreSQLFlexQueryStoreRuntime"
  }
  
  enabled_log {
    category = "PostgreSQLFlexQueryStoreWaitStats"
  }
  
  enabled_log {
    category = "PostgreSQLFlexTableStats"
  }
  
  enabled_log {
    category = "PostgreSQLFlexDatabaseXacts"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = var.enable_metrics
  }
}

# Configure diagnostic settings for Data Factory
resource "azurerm_monitor_diagnostic_setting" "data_factory" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name               = "data-factory-diagnostics"
  target_resource_id = azurerm_data_factory.main.id
  log_analytics_workspace_id = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
  
  enabled_log {
    category = "ActivityRuns"
  }
  
  enabled_log {
    category = "PipelineRuns"
  }
  
  enabled_log {
    category = "TriggerRuns"
  }
  
  enabled_log {
    category = "SandboxPipelineRuns"
  }
  
  enabled_log {
    category = "SandboxActivityRuns"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = var.enable_metrics
  }
}

# Wait for resources to be fully deployed
resource "time_sleep" "wait_for_deployment" {
  depends_on = [
    azurerm_postgresql_flexible_server.main,
    azurerm_data_factory.main,
    azurerm_eventgrid_topic.main,
    kubernetes_namespace.arc_data
  ]
  
  create_duration = "30s"
}