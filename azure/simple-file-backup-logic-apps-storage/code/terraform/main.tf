# Azure File Backup Automation Infrastructure
# This Terraform configuration creates a complete backup solution using
# Azure Logic Apps and Blob Storage for automated file backup operations.

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group for all backup-related resources
resource "azurerm_resource_group" "backup" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.common_tags
}

# Create Storage Account for backup file storage
# Uses cool access tier for cost-effective backup storage
resource "azurerm_storage_account" "backup" {
  name                     = var.storage_account_name != "" ? var.storage_account_name : "st${var.workload}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.backup.name
  location                 = azurerm_resource_group.backup.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  access_tier              = var.storage_access_tier
  
  # Security configurations following Azure best practices
  https_traffic_enabled      = var.enable_https_traffic_only
  min_tls_version           = var.min_tls_version
  allow_nested_items_to_be_public = var.allow_blob_public_access
  
  # Enable versioning and soft delete for data protection
  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  # Network access rules for security
  network_rules {
    default_action = "Allow"
    # In production, consider restricting to specific IP ranges
    # ip_rules       = ["100.0.0.1"]
    # virtual_network_subnet_ids = [azurerm_subnet.example.id]
  }
  
  tags = merge(var.common_tags, {
    Component = "Storage"
    Purpose   = "BackupFiles"
  })
}

# Create blob container for backup files with private access
resource "azurerm_storage_container" "backup_files" {
  name                  = var.container_name
  storage_account_name  = azurerm_storage_account.backup.name
  container_access_type = "private"
  
  # Container metadata for identification and management
  metadata = {
    purpose     = "backup"
    created     = timestamp()
    environment = var.environment
  }
  
  depends_on = [azurerm_storage_account.backup]
}

# Create Log Analytics Workspace for monitoring (if logging is enabled)
resource "azurerm_log_analytics_workspace" "backup" {
  count               = var.enable_storage_logging || var.enable_logic_apps_logging ? 1 : 0
  name                = "law-${var.workload}-${random_string.suffix.result}"
  location            = azurerm_resource_group.backup.location
  resource_group_name = azurerm_resource_group.backup.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  
  tags = merge(var.common_tags, {
    Component = "Monitoring"
    Purpose   = "Logging"
  })
}

# Logic Apps Workflow for backup automation
# Creates a consumption-based Logic App with scheduled triggers
resource "azurerm_logic_app_workflow" "backup" {
  name                = var.logic_app_name != "" ? var.logic_app_name : "la-${var.workload}-${random_string.suffix.result}"
  location            = azurerm_resource_group.backup.location
  resource_group_name = azurerm_resource_group.backup.name
  
  # Workflow definition with recurrence trigger and backup actions
  workflow_schema   = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version  = "1.0.0.0"
  
  # Parameters can be used to pass configuration values to the workflow
  workflow_parameters = {
    "$connections" = {
      "type" = "Object"
      "value" = {}
    }
    "storageAccountName" = {
      "type" = "String"
      "value" = azurerm_storage_account.backup.name
    }
    "containerName" = {
      "type" = "String"
      "value" = azurerm_storage_container.backup_files.name
    }
  }
  
  tags = merge(var.common_tags, {
    Component = "Automation"
    Purpose   = "BackupWorkflow"
  })
}

# Logic Apps Trigger for scheduled backup execution
resource "azurerm_logic_app_trigger_recurrence" "backup_schedule" {
  name         = "BackupScheduleTrigger"
  logic_app_id = azurerm_logic_app_workflow.backup.id
  frequency    = var.backup_schedule_frequency
  interval     = var.backup_schedule_interval
  time_zone    = var.time_zone
  
  # Schedule backup to run at specified time
  schedule {
    hours   = [var.backup_time_hour]
    minutes = [var.backup_time_minute]
  }
}

# Logic Apps Action to initialize backup status variable
resource "azurerm_logic_app_action_custom" "initialize_backup_status" {
  name         = "InitializeBackupStatus"
  logic_app_id = azurerm_logic_app_workflow.backup.id
  
  body = jsonencode({
    type = "InitializeVariable"
    inputs = {
      variables = [
        {
          name  = "BackupStatus"
          type  = "String"
          value = "Starting backup process at @{utcNow()}"
        }
      ]
    }
    runAfter = {}
  })
  
  depends_on = [azurerm_logic_app_trigger_recurrence.backup_schedule]
}

# Logic Apps Action to create backup log entry
resource "azurerm_logic_app_action_http" "create_backup_log" {
  name         = "CreateBackupLog"
  logic_app_id = azurerm_logic_app_workflow.backup.id
  method       = "PUT"
  uri          = "https://${azurerm_storage_account.backup.name}.blob.core.windows.net/${azurerm_storage_container.backup_files.name}/backup-log-@{formatDateTime(utcNow(), 'yyyy-MM-dd-HH-mm')}.txt"
  
  headers = {
    "x-ms-blob-type" = "BlockBlob"
    "Content-Type"   = "text/plain"
    "x-ms-version"   = "2019-12-12"
  }
  
  body = "Backup process initiated at @{utcNow()} - Status: @{variables('BackupStatus')}"
  
  run_after {
    action_name   = azurerm_logic_app_action_custom.initialize_backup_status.name
    action_result = "Succeeded"
  }
}

# Storage Account diagnostic settings for monitoring (if enabled)
resource "azurerm_monitor_diagnostic_setting" "storage" {
  count              = var.enable_storage_logging ? 1 : 0
  name               = "storage-diagnostics"
  target_resource_id = "${azurerm_storage_account.backup.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.backup[0].id
  
  # Enable storage metrics and logs
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
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
  
  metric {
    category = "Capacity"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
}

# Logic Apps diagnostic settings for monitoring (if enabled)
resource "azurerm_monitor_diagnostic_setting" "logic_app" {
  count              = var.enable_logic_apps_logging ? 1 : 0
  name               = "logicapp-diagnostics"
  target_resource_id = azurerm_logic_app_workflow.backup.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.backup[0].id
  
  # Enable Logic Apps workflow logs
  enabled_log {
    category = "WorkflowRuntime"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
}

# Role Assignment for Logic Apps to access Storage Account
# Uses Storage Blob Data Contributor role for read/write access
resource "azurerm_role_assignment" "logic_app_storage" {
  scope              = azurerm_storage_account.backup.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id       = azurerm_logic_app_workflow.backup.identity[0].principal_id
  
  depends_on = [
    azurerm_logic_app_workflow.backup,
    azurerm_storage_account.backup
  ]
}

# Enable system-assigned managed identity for Logic Apps
resource "azurerm_logic_app_workflow" "backup_with_identity" {
  name                = azurerm_logic_app_workflow.backup.name
  location            = azurerm_logic_app_workflow.backup.location
  resource_group_name = azurerm_logic_app_workflow.backup.resource_group_name
  
  # Enable managed identity for secure authentication
  identity {
    type = "SystemAssigned"
  }
  
  # Use the same configuration as the original workflow
  workflow_schema      = azurerm_logic_app_workflow.backup.workflow_schema
  workflow_version     = azurerm_logic_app_workflow.backup.workflow_version
  workflow_parameters  = azurerm_logic_app_workflow.backup.workflow_parameters
  
  tags = azurerm_logic_app_workflow.backup.tags
  
  # This resource replaces the original workflow to add managed identity
  lifecycle {
    replace_triggered_by = [
      azurerm_logic_app_workflow.backup
    ]
  }
}

# Time delay to ensure resources are fully provisioned
resource "time_sleep" "wait_for_resources" {
  depends_on = [
    azurerm_storage_account.backup,
    azurerm_storage_container.backup_files,
    azurerm_logic_app_workflow.backup
  ]
  
  create_duration = "30s"
}