# Main Terraform configuration for HPC Cache and Monitor Workbooks

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  resource_prefix = "${var.environment}-${random_string.suffix.result}"
  
  # Computed resource names
  hpc_cache_name        = "${var.hpc_cache_name}-${local.resource_prefix}"
  batch_account_name    = "${var.batch_account_name}${random_string.suffix.result}"
  storage_account_name  = "${var.storage_account_name}${random_string.suffix.result}"
  workspace_name        = "${var.log_analytics_workspace_name}-${local.resource_prefix}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    CreatedBy   = "Terraform"
    Purpose     = "HPC Monitoring"
  })
}

# Data source for current subscription
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "hpc_monitoring" {
  name     = "${var.resource_group_name}-${local.resource_prefix}"
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "hpc_workspace" {
  name                = local.workspace_name
  location            = azurerm_resource_group.hpc_monitoring.location
  resource_group_name = azurerm_resource_group.hpc_monitoring.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_retention_in_days
  tags                = local.common_tags
}

# Storage Account for HPC workloads
resource "azurerm_storage_account" "hpc_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.hpc_monitoring.name
  location                 = azurerm_resource_group.hpc_monitoring.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  tags = local.common_tags
}

# Virtual Network for HPC Cache
resource "azurerm_virtual_network" "hpc_vnet" {
  name                = "hpc-vnet-${local.resource_prefix}"
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.hpc_monitoring.location
  resource_group_name = azurerm_resource_group.hpc_monitoring.name
  tags                = local.common_tags
}

# Subnet for HPC Cache
resource "azurerm_subnet" "hpc_subnet" {
  name                 = "hpc-subnet"
  resource_group_name  = azurerm_resource_group.hpc_monitoring.name
  virtual_network_name = azurerm_virtual_network.hpc_vnet.name
  address_prefixes     = [var.subnet_address_prefix]
}

# HPC Cache
resource "azurerm_hpc_cache" "hpc_cache" {
  name                = local.hpc_cache_name
  resource_group_name = azurerm_resource_group.hpc_monitoring.name
  location            = azurerm_resource_group.hpc_monitoring.location
  cache_size_in_gb    = var.hpc_cache_size_gb
  subnet_id           = azurerm_subnet.hpc_subnet.id
  sku_name            = var.hpc_cache_sku
  
  tags = local.common_tags
}

# Batch Account
resource "azurerm_batch_account" "hpc_batch" {
  name                                = local.batch_account_name
  resource_group_name                 = azurerm_resource_group.hpc_monitoring.name
  location                            = azurerm_resource_group.hpc_monitoring.location
  pool_allocation_mode                = "BatchService"
  storage_account_id                  = azurerm_storage_account.hpc_storage.id
  storage_account_authentication_mode = "StorageKeys"
  
  tags = local.common_tags
}

# Batch Pool
resource "azurerm_batch_pool" "hpc_pool" {
  name                = var.batch_pool_name
  resource_group_name = azurerm_resource_group.hpc_monitoring.name
  account_name        = azurerm_batch_account.hpc_batch.name
  display_name        = "HPC Compute Pool"
  vm_size             = var.batch_vm_size
  node_agent_sku_id   = "batch.node.ubuntu 20.04"
  
  fixed_scale {
    target_dedicated_nodes = var.batch_node_count
    resize_timeout         = "PT15M"
  }
  
  storage_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
  
  start_task {
    command_line         = "echo 'HPC Pool initialized'"
    task_retry_maximum   = 1
    wait_for_success     = true
    common_environment_properties = {
      "POOL_ID" = var.batch_pool_name
    }
    
    user_identity {
      auto_user {
        elevation_level = "NonAdmin"
        scope           = "Task"
      }
    }
  }
}

# Action Group for alerts
resource "azurerm_monitor_action_group" "hpc_alerts" {
  count               = var.enable_alerts ? 1 : 0
  name                = "hpc-alerts-${local.resource_prefix}"
  resource_group_name = azurerm_resource_group.hpc_monitoring.name
  short_name          = "hpc-alerts"
  
  email_receiver {
    name          = "admin"
    email_address = var.alert_email
  }
  
  tags = local.common_tags
}

# Diagnostic Settings for HPC Cache
resource "azurerm_monitor_diagnostic_setting" "hpc_cache_diagnostics" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "hpc-cache-diagnostics"
  target_resource_id         = azurerm_hpc_cache.hpc_cache.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hpc_workspace.id
  
  enabled_log {
    category = "ServiceLog"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic Settings for Batch Account
resource "azurerm_monitor_diagnostic_setting" "batch_diagnostics" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "batch-diagnostics"
  target_resource_id         = azurerm_batch_account.hpc_batch.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hpc_workspace.id
  
  enabled_log {
    category = "ServiceLog"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic Settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage_diagnostics" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "storage-diagnostics"
  target_resource_id         = azurerm_storage_account.hpc_storage.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hpc_workspace.id
  
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

# Alert Rule for Low Cache Hit Rate
resource "azurerm_monitor_metric_alert" "low_cache_hit_rate" {
  count               = var.enable_alerts ? 1 : 0
  name                = "low-cache-hit-rate-${local.resource_prefix}"
  resource_group_name = azurerm_resource_group.hpc_monitoring.name
  scopes              = [azurerm_hpc_cache.hpc_cache.id]
  description         = "Alert when cache hit rate drops below ${var.cache_hit_rate_threshold}%"
  enabled             = true
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.StorageCache/caches"
    metric_name      = "CacheHitPercent"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.cache_hit_rate_threshold
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.hpc_alerts[0].id
  }
  
  tags = local.common_tags
}

# Alert Rule for High Compute Utilization
resource "azurerm_monitor_metric_alert" "high_compute_utilization" {
  count               = var.enable_alerts ? 1 : 0
  name                = "high-compute-utilization-${local.resource_prefix}"
  resource_group_name = azurerm_resource_group.hpc_monitoring.name
  scopes              = [azurerm_batch_account.hpc_batch.id]
  description         = "Alert when compute nodes exceed ${var.compute_utilization_threshold}% utilization"
  enabled             = true
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Batch/batchAccounts"
    metric_name      = "RunningNodeCount"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.compute_utilization_threshold
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.hpc_alerts[0].id
  }
  
  tags = local.common_tags
}

# Azure Monitor Workbook for HPC monitoring
resource "azurerm_application_insights_workbook" "hpc_workbook" {
  name                = "hpc-monitoring-workbook-${local.resource_prefix}"
  resource_group_name = azurerm_resource_group.hpc_monitoring.name
  location            = azurerm_resource_group.hpc_monitoring.location
  display_name        = var.workbook_display_name
  description         = "Comprehensive monitoring dashboard for HPC Cache and Batch workloads"
  
  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "## HPC Cache Performance Dashboard\n\nThis dashboard provides comprehensive monitoring for Azure HPC Cache, Batch compute clusters, and storage performance metrics."
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query   = "AzureMetrics\n| where ResourceProvider == \"MICROSOFT.STORAGECACHE\"\n| where MetricName == \"CacheHitPercent\"\n| summarize avg(Average) by bin(TimeGenerated, 5m)\n| render timechart"
          size    = 0
          title   = "Cache Hit Rate Over Time"
          timeContext = {
            durationMs = 3600000
          }
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query   = "AzureMetrics\n| where ResourceProvider == \"MICROSOFT.BATCH\"\n| where MetricName == \"RunningNodeCount\"\n| summarize avg(Average) by bin(TimeGenerated, 5m)\n| render timechart"
          size    = 0
          title   = "Active Compute Nodes"
          timeContext = {
            durationMs = 3600000
          }
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query   = "AzureMetrics\n| where ResourceProvider == \"MICROSOFT.STORAGECACHE\"\n| where MetricName == \"TotalReadThroughput\"\n| summarize avg(Average) by bin(TimeGenerated, 5m)\n| render timechart"
          size    = 0
          title   = "Storage Read Throughput"
          timeContext = {
            durationMs = 3600000
          }
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query   = "AzureMetrics\n| where ResourceProvider == \"MICROSOFT.STORAGECACHE\"\n| where MetricName == \"TotalWriteThroughput\"\n| summarize avg(Average) by bin(TimeGenerated, 5m)\n| render timechart"
          size    = 0
          title   = "Storage Write Throughput"
          timeContext = {
            durationMs = 3600000
          }
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query   = "AzureMetrics\n| where ResourceProvider == \"MICROSOFT.BATCH\"\n| where MetricName == \"TaskCompleteEvent\"\n| summarize count() by bin(TimeGenerated, 5m)\n| render timechart"
          size    = 0
          title   = "Batch Task Completion Rate"
          timeContext = {
            durationMs = 3600000
          }
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query   = "AzureMetrics\n| where ResourceProvider == \"MICROSOFT.STORAGE\"\n| where MetricName == \"Transactions\"\n| summarize sum(Total) by bin(TimeGenerated, 5m)\n| render timechart"
          size    = 0
          title   = "Storage Transaction Volume"
          timeContext = {
            durationMs = 3600000
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Storage Target for HPC Cache (Azure Blob Storage)
resource "azurerm_hpc_cache_blob_storage_target" "hpc_storage_target" {
  name                 = "hpc-storage-target"
  resource_group_name  = azurerm_resource_group.hpc_monitoring.name
  cache_name           = azurerm_hpc_cache.hpc_cache.name
  storage_container_id = "${azurerm_storage_account.hpc_storage.id}/blobServices/default/containers/hpc-data"
  namespace_path       = "/hpc-data"
  
  depends_on = [azurerm_storage_container.hpc_container]
}

# Storage Container for HPC data
resource "azurerm_storage_container" "hpc_container" {
  name                  = "hpc-data"
  storage_account_name  = azurerm_storage_account.hpc_storage.name
  container_access_type = "private"
}