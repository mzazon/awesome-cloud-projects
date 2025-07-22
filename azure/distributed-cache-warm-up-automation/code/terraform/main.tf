# Main Terraform configuration for Azure distributed cache warm-up workflow

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Local values for resource naming and configuration
locals {
  # Resource naming with optional suffix
  name_suffix = var.resource_name_suffix != "" ? var.resource_name_suffix : random_string.suffix.result
  
  # Resource names
  resource_group_name         = "rg-${var.project_name}-${local.name_suffix}"
  container_env_name         = "env-${var.project_name}-${local.name_suffix}"
  coordinator_job_name       = "job-coordinator-${local.name_suffix}"
  worker_job_name           = "job-worker-${local.name_suffix}"
  redis_name                = "redis-${var.project_name}-${local.name_suffix}"
  storage_account_name      = "st${var.project_name}${local.name_suffix}"
  key_vault_name           = "kv-${var.project_name}-${local.name_suffix}"
  log_analytics_name       = "log-${var.project_name}-${local.name_suffix}"
  container_registry_name  = "cr${var.project_name}${local.name_suffix}"
  action_group_name        = "ag-${var.project_name}-${local.name_suffix}"
  
  # Common tags merged with variable tags
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    CreatedBy   = "terraform"
    CreatedOn   = timestamp()
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_in_days
  tags                = local.common_tags
}

# Container Registry for custom images
resource "azurerm_container_registry" "main" {
  name                = local.container_registry_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = var.container_registry_admin_enabled
  tags                = local.common_tags
}

# Container Apps Environment
resource "azurerm_container_app_environment" "main" {
  name                       = local.container_env_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.common_tags
}

# Storage Account for job coordination
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  access_tier              = var.storage_access_tier
  
  # Enable blob versioning and soft delete for data protection
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Storage Container for job coordination
resource "azurerm_storage_container" "coordination" {
  name                  = "coordination"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Key Vault for secrets management
resource "azurerm_key_vault" "main" {
  name                            = local.key_vault_name
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  enabled_for_disk_encryption     = var.key_vault_enabled_for_disk_encryption
  enabled_for_deployment          = var.key_vault_enabled_for_deployment
  enabled_for_template_deployment = var.key_vault_enabled_for_template_deployment
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days      = 7
  purge_protection_enabled        = false
  sku_name                        = var.key_vault_sku_name
  
  # Network ACLs for security
  network_acls {
    bypass         = "AzureServices"
    default_action = "Allow"  # Set to "Deny" and configure ip_rules for production
    ip_rules       = var.allowed_ip_ranges
  }
  
  tags = local.common_tags
}

# Key Vault Access Policy for current user/service principal
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Recover",
    "Backup",
    "Restore",
    "Purge"
  ]
  
  key_permissions = [
    "Get",
    "List",
    "Create",
    "Delete",
    "Update",
    "Import",
    "Backup",
    "Restore"
  ]
}

# Azure Redis Enterprise
resource "azurerm_redis_enterprise_cluster" "main" {
  name                = local.redis_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku_name            = var.redis_sku_name
  
  tags = local.common_tags
}

# Redis Enterprise Database
resource "azurerm_redis_enterprise_database" "main" {
  name                = "default"
  resource_group_name = azurerm_resource_group.main.name
  cluster_id          = azurerm_redis_enterprise_cluster.main.id
  
  # Client protocol and authentication
  client_protocol   = "Encrypted"
  clustering_policy = "EnterpriseCluster"
  eviction_policy   = "VolatileLRU"
  port              = 10000
  
  # Enable modules for enhanced Redis functionality
  module {
    name = "RedisBloom"
  }
  
  module {
    name = "RedisTimeSeries"
  }
  
  module {
    name = "RediSearch"
  }
}

# Store Redis connection string in Key Vault
resource "azurerm_key_vault_secret" "redis_connection_string" {
  name         = "redis-connection-string"
  value        = "Server=${azurerm_redis_enterprise_cluster.main.hostname}:${azurerm_redis_enterprise_database.main.port};Password=${azurerm_redis_enterprise_database.main.primary_access_key};Database=0;Ssl=True"
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  tags = local.common_tags
}

# Store Storage Account connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  tags = local.common_tags
}

# User Assigned Managed Identity for Container Apps
resource "azurerm_user_assigned_identity" "container_apps" {
  name                = "id-${var.project_name}-containerapp-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Role assignment for Managed Identity to access Key Vault
resource "azurerm_key_vault_access_policy" "container_apps" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = azurerm_user_assigned_identity.container_apps.tenant_id
  object_id    = azurerm_user_assigned_identity.container_apps.principal_id
  
  secret_permissions = [
    "Get",
    "List"
  ]
}

# Role assignment for Managed Identity to access Storage Account
resource "azurerm_role_assignment" "storage_blob_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.container_apps.principal_id
}

# Container App Job for Coordinator
resource "azurerm_container_app_job" "coordinator" {
  name                         = local.coordinator_job_name
  location                     = azurerm_resource_group.main.location
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  replica_timeout_in_seconds   = 1800
  replica_retry_limit          = 1
  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }
  
  # Scheduled trigger - runs every 6 hours by default
  schedule_trigger_config {
    cron_expression                = var.coordinator_schedule
    parallelism                    = 1
    replica_completion_count       = 1
  }
  
  template {
    container {
      name   = "coordinator"
      image  = var.coordinator_image
      cpu    = var.container_apps_cpu
      memory = var.container_apps_memory
      
      # Environment variables for coordinator
      env {
        name  = "RESOURCE_GROUP"
        value = azurerm_resource_group.main.name
      }
      
      env {
        name  = "SUBSCRIPTION_ID"
        value = data.azurerm_client_config.current.subscription_id
      }
      
      env {
        name  = "STORAGE_ACCOUNT_NAME"
        value = azurerm_storage_account.main.name
      }
      
      env {
        name  = "KEY_VAULT_NAME"
        value = azurerm_key_vault.main.name
      }
      
      env {
        name  = "WORKER_JOB_NAME"
        value = local.worker_job_name
      }
      
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.container_apps.client_id
      }
    }
  }
  
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.container_apps.id]
  }
  
  tags = local.common_tags
}

# Container App Job for Workers
resource "azurerm_container_app_job" "worker" {
  name                         = local.worker_job_name
  location                     = azurerm_resource_group.main.location
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  replica_timeout_in_seconds   = 3600
  replica_retry_limit          = 2
  
  manual_trigger_config {
    parallelism              = var.worker_parallelism
    replica_completion_count = var.worker_parallelism
  }
  
  template {
    container {
      name   = "worker"
      image  = var.worker_image
      cpu    = var.container_apps_cpu / 2  # Workers use less CPU
      memory = var.container_apps_memory
      
      # Environment variables for workers
      env {
        name  = "STORAGE_ACCOUNT_NAME"
        value = azurerm_storage_account.main.name
      }
      
      env {
        name  = "KEY_VAULT_NAME"
        value = azurerm_key_vault.main.name
      }
      
      env {
        name  = "WORKER_ID"
        value = "$AZURE_CONTAINER_APP_REPLICA_NAME"
      }
      
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.container_apps.client_id
      }
    }
  }
  
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.container_apps.id]
  }
  
  tags = local.common_tags
}

# Action Group for monitoring alerts
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = local.action_group_name
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "CacheWarmup"
  
  email_receiver {
    name          = "admin"
    email_address = var.alert_email_address
  }
  
  tags = local.common_tags
}

# Metric Alert for Container App Job Failures
resource "azurerm_monitor_metric_alert" "job_failures" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "Cache Warmup Job Failures"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app_job.coordinator.id]
  description         = "Alert when cache warm-up coordinator job fails"
  frequency           = "PT1M"
  window_size         = "PT5M"
  severity            = 2
  
  criteria {
    metric_namespace = "Microsoft.App/jobs"
    metric_name      = "JobExecutionCount"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 0
    
    dimension {
      name     = "Result"
      operator = "Include"
      values   = ["Failed"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
}

# Metric Alert for Redis High Memory Usage
resource "azurerm_monitor_metric_alert" "redis_memory" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "Redis High Memory Usage"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_redis_enterprise_cluster.main.id]
  description         = "Alert when Redis memory usage exceeds 80%"
  frequency           = "PT5M"
  window_size         = "PT15M"
  severity            = 2
  
  criteria {
    metric_namespace = "Microsoft.Cache/redisEnterprise"
    metric_name      = "usedmemorypercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
}

# Diagnostic settings for Container Apps Environment
resource "azurerm_monitor_diagnostic_setting" "container_env" {
  name                       = "diag-${local.container_env_name}"
  target_resource_id         = azurerm_container_app_environment.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "ContainerAppConsoleLogs"
  }
  
  enabled_log {
    category = "ContainerAppSystemLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Redis Enterprise
resource "azurerm_monitor_diagnostic_setting" "redis" {
  name                       = "diag-${local.redis_name}"
  target_resource_id         = azurerm_redis_enterprise_cluster.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage" {
  name                       = "diag-${local.storage_account_name}"
  target_resource_id         = azurerm_storage_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "StorageRead"
  }
  
  enabled_log {
    category = "StorageWrite"
  }
  
  enabled_log {
    category = "StorageDelete"
  }
  
  metric {
    category = "Transaction"
    enabled  = true
  }
  
  metric {
    category = "Capacity"
    enabled  = true
  }
}