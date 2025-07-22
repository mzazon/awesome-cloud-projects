# Azure Storage Lifecycle Management Infrastructure
# This Terraform configuration implements automated blob storage lifecycle management
# with Azure Storage Accounts, Azure Monitor, and Logic Apps for comprehensive
# data governance and cost optimization.

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Merge common tags with additional tags
locals {
  all_tags = merge(var.common_tags, var.additional_tags, {
    Environment = var.environment
    CreatedBy   = "terraform"
    CreatedAt   = timestamp()
  })
}

# Create Resource Group for all lifecycle management resources
resource "azurerm_resource_group" "lifecycle_rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.all_tags
}

# Create Storage Account with lifecycle management capabilities
resource "azurerm_storage_account" "lifecycle_storage" {
  name                = "${var.storage_account_name_prefix}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.lifecycle_rg.name
  location            = azurerm_resource_group.lifecycle_rg.location
  
  # Storage account configuration
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = var.storage_account_kind
  access_tier              = var.storage_account_access_tier
  
  # Enable features required for lifecycle management
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  # Network access rules for security
  public_network_access_enabled = true
  
  # Blob storage features
  blob_properties {
    # Enable versioning for better lifecycle management
    versioning_enabled = var.enable_blob_versioning
    
    # Configure soft delete for blob protection
    delete_retention_policy {
      days = var.blob_soft_delete_retention_days
    }
    
    # Enable container soft delete
    container_delete_retention_policy {
      days = var.container_soft_delete_retention_days
    }
  }
  
  # Identity configuration for monitoring integration
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.all_tags
  
  lifecycle {
    ignore_changes = [
      # Ignore changes to these attributes after creation
      tags["CreatedAt"]
    ]
  }
}

# Create storage containers for different data types
resource "azurerm_storage_container" "containers" {
  for_each = { for container in var.storage_containers : container.name => container }
  
  name                  = each.value.name
  storage_account_name  = azurerm_storage_account.lifecycle_storage.name
  container_access_type = each.value.container_access_type
  
  depends_on = [azurerm_storage_account.lifecycle_storage]
}

# Create Log Analytics Workspace for storage monitoring
resource "azurerm_log_analytics_workspace" "storage_monitoring" {
  name                = var.log_analytics_workspace_name
  location            = azurerm_resource_group.lifecycle_rg.location
  resource_group_name = azurerm_resource_group.lifecycle_rg.name
  
  sku               = var.log_analytics_sku
  retention_in_days = var.log_analytics_retention_in_days
  
  tags = local.all_tags
}

# Configure storage account diagnostics to send data to Log Analytics
resource "azurerm_monitor_diagnostic_setting" "storage_diagnostics" {
  count = var.enable_storage_monitoring ? 1 : 0
  
  name                       = "storage-diagnostics"
  target_resource_id         = "${azurerm_storage_account.lifecycle_storage.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.storage_monitoring.id
  
  # Enable storage metrics
  enabled_log {
    category = "StorageRead"
    
    retention_policy {
      enabled = true
      days    = var.diagnostic_logs_retention_days
    }
  }
  
  enabled_log {
    category = "StorageWrite"
    
    retention_policy {
      enabled = true
      days    = var.diagnostic_logs_retention_days
    }
  }
  
  enabled_log {
    category = "StorageDelete"
    
    retention_policy {
      enabled = true
      days    = var.diagnostic_logs_retention_days
    }
  }
  
  # Enable storage capacity and transaction metrics
  metric {
    category = "Transaction"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.diagnostic_logs_retention_days
    }
  }
  
  metric {
    category = "Capacity"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.diagnostic_logs_retention_days
    }
  }
  
  depends_on = [
    azurerm_storage_account.lifecycle_storage,
    azurerm_log_analytics_workspace.storage_monitoring
  ]
}

# Create Action Group for alert notifications
resource "azurerm_monitor_action_group" "storage_alerts" {
  name                = var.action_group_name
  resource_group_name = azurerm_resource_group.lifecycle_rg.name
  short_name          = var.action_group_short_name
  
  tags = local.all_tags
}

# Create Logic App for automated alerting and workflow automation
resource "azurerm_logic_app_workflow" "storage_alerts" {
  count = var.enable_logic_app_alerts ? 1 : 0
  
  name                = var.logic_app_name
  location            = azurerm_resource_group.lifecycle_rg.location
  resource_group_name = azurerm_resource_group.lifecycle_rg.name
  
  # Enable system-assigned managed identity for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.all_tags
}

# Create metric alert for high storage capacity
resource "azurerm_monitor_metric_alert" "high_storage_capacity" {
  count = var.enable_capacity_alerts ? 1 : 0
  
  name                = "HighStorageCapacity"
  resource_group_name = azurerm_resource_group.lifecycle_rg.name
  scopes              = [azurerm_storage_account.lifecycle_storage.id]
  description         = "Alert when storage capacity exceeds defined threshold"
  severity            = 2
  frequency           = var.alert_evaluation_frequency
  window_size         = var.alert_window_size
  
  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts"
    metric_name      = "UsedCapacity"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.storage_capacity_alert_threshold
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.storage_alerts.id
  }
  
  tags = local.all_tags
  
  depends_on = [azurerm_storage_account.lifecycle_storage]
}

# Create metric alert for high transaction count
resource "azurerm_monitor_metric_alert" "high_transaction_count" {
  count = var.enable_transaction_alerts ? 1 : 0
  
  name                = "HighTransactionCount"
  resource_group_name = azurerm_resource_group.lifecycle_rg.name
  scopes              = [azurerm_storage_account.lifecycle_storage.id]
  description         = "Alert when transaction count exceeds defined threshold"
  severity            = 3
  frequency           = var.alert_evaluation_frequency
  window_size         = var.alert_window_size
  
  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts"
    metric_name      = "Transactions"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.transaction_count_alert_threshold
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.storage_alerts.id
  }
  
  tags = local.all_tags
  
  depends_on = [azurerm_storage_account.lifecycle_storage]
}

# Create storage management policy for automated lifecycle management
resource "azurerm_storage_management_policy" "lifecycle_policy" {
  count = var.lifecycle_policy_enabled ? 1 : 0
  
  storage_account_id = azurerm_storage_account.lifecycle_storage.id
  
  # Lifecycle rule for documents container
  rule {
    name    = "DocumentLifecycle"
    enabled = true
    
    filters {
      prefix_match = ["documents/"]
      blob_types   = ["blockBlob"]
    }
    
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = var.document_lifecycle_rules.tier_to_cool_days
        tier_to_archive_after_days_since_modification_greater_than = var.document_lifecycle_rules.tier_to_archive_days
        delete_after_days_since_modification_greater_than          = var.document_lifecycle_rules.delete_after_days
      }
    }
  }
  
  # Lifecycle rule for logs container
  rule {
    name    = "LogLifecycle"
    enabled = true
    
    filters {
      prefix_match = ["logs/"]
      blob_types   = ["blockBlob"]
    }
    
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = var.log_lifecycle_rules.tier_to_cool_days
        tier_to_archive_after_days_since_modification_greater_than = var.log_lifecycle_rules.tier_to_archive_days
        delete_after_days_since_modification_greater_than          = var.log_lifecycle_rules.delete_after_days
      }
    }
  }
  
  depends_on = [
    azurerm_storage_account.lifecycle_storage,
    azurerm_storage_container.containers
  ]
}

# Create sample data for testing lifecycle management (optional)
resource "azurerm_storage_blob" "sample_data" {
  count = var.create_sample_data ? length(var.sample_data_files) : 0
  
  name                   = var.sample_data_files[count.index].blob_name
  storage_account_name   = azurerm_storage_account.lifecycle_storage.name
  storage_container_name = var.sample_data_files[count.index].container_name
  type                   = "Block"
  source_content         = var.sample_data_files[count.index].content
  
  depends_on = [
    azurerm_storage_container.containers
  ]
}

# Create additional monitoring resources for comprehensive observability
resource "azurerm_monitor_metric_alert" "storage_availability" {
  name                = "StorageAvailability"
  resource_group_name = azurerm_resource_group.lifecycle_rg.name
  scopes              = [azurerm_storage_account.lifecycle_storage.id]
  description         = "Alert when storage availability drops below threshold"
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"
  
  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts"
    metric_name      = "Availability"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 99
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.storage_alerts.id
  }
  
  tags = local.all_tags
  
  depends_on = [azurerm_storage_account.lifecycle_storage]
}

# Create storage account network rules for enhanced security
resource "azurerm_storage_account_network_rules" "lifecycle_storage_rules" {
  storage_account_id = azurerm_storage_account.lifecycle_storage.id
  
  default_action = "Allow"
  
  # Allow Azure services to access the storage account
  bypass = ["AzureServices"]
  
  depends_on = [azurerm_storage_account.lifecycle_storage]
}

# Create role assignment for Log Analytics workspace to read storage metrics
resource "azurerm_role_assignment" "storage_monitoring_reader" {
  scope                = azurerm_storage_account.lifecycle_storage.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_log_analytics_workspace.storage_monitoring.identity[0].principal_id
  
  depends_on = [
    azurerm_storage_account.lifecycle_storage,
    azurerm_log_analytics_workspace.storage_monitoring
  ]
}

# Create custom log queries for storage monitoring
resource "azurerm_log_analytics_saved_search" "storage_capacity_trend" {
  name                       = "StorageCapacityTrend"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.storage_monitoring.id
  category                   = "Storage Monitoring"
  display_name               = "Storage Capacity Trend"
  
  query = <<-EOT
    StorageBlobLogs
    | where TimeGenerated > ago(7d)
    | summarize TotalCapacity = sum(ResponseBodySize) by bin(TimeGenerated, 1h)
    | render timechart
  EOT
}

resource "azurerm_log_analytics_saved_search" "lifecycle_transitions" {
  name                       = "LifecycleTransitions"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.storage_monitoring.id
  category                   = "Storage Monitoring"
  display_name               = "Lifecycle Transitions"
  
  query = <<-EOT
    StorageBlobLogs
    | where OperationName contains "SetBlobTier"
    | summarize TransitionCount = count() by AccessTier, bin(TimeGenerated, 1d)
    | render columnchart
  EOT
}