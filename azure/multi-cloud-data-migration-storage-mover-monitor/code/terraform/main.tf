# Local values for consistent naming and tagging
locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Resource naming with random suffix for uniqueness
  storage_account_name = "st${replace(var.project_name, "-", "")}${random_id.suffix.hex}"
  storage_mover_name   = "sm-${local.name_prefix}-${random_id.suffix.hex}"
  log_workspace_name   = "log-${local.name_prefix}-${random_id.suffix.hex}"
  logic_app_name       = "logic-${local.name_prefix}-${random_id.suffix.hex}"
  
  # Common tags applied to all resources
  common_tags = merge(
    {
      Environment   = var.environment
      Project       = var.project_name
      Purpose       = "data-migration"
      Source        = "aws-s3"
      Target        = "azure-blob"
      ManagedBy     = "terraform"
      CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
    },
    var.tags
  )
}

# Random ID for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Current Azure client configuration
data "azurerm_client_config" "current" {}

# Current Azure subscription
data "azurerm_subscription" "current" {}

# Resource group for all migration resources
resource "azurerm_resource_group" "migration" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Storage account for target blob storage
resource "azurerm_storage_account" "target" {
  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.migration.name
  location            = azurerm_resource_group.migration.location
  
  account_tier              = var.storage_account_tier
  account_replication_type  = var.storage_account_replication_type
  access_tier              = var.storage_account_access_tier
  account_kind             = "StorageV2"
  
  # Security settings
  enable_https_traffic_only      = true
  min_tls_version               = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Blob properties
  blob_properties {
    # Enable versioning for data protection
    versioning_enabled = true
    
    # Enable point-in-time restore
    point_in_time_restore_enabled = true
    
    # Container delete retention policy
    container_delete_retention_policy {
      days = 7
    }
    
    # Blob delete retention policy
    delete_retention_policy {
      days = 7
    }
  }
  
  # Network rules
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
  
  tags = local.common_tags
}

# Storage container for migrated data
resource "azurerm_storage_container" "target" {
  name                  = var.target_container_name
  storage_account_name  = azurerm_storage_account.target.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.target]
}

# Log Analytics workspace for monitoring
resource "azurerm_log_analytics_workspace" "migration" {
  name                = local.log_workspace_name
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  
  sku               = var.log_analytics_sku
  retention_in_days = var.log_analytics_retention_days
  
  tags = local.common_tags
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "migration" {
  name                = "appi-${local.name_prefix}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.migration.id
  
  tags = local.common_tags
}

# Action group for notifications
resource "azurerm_monitor_action_group" "migration_alerts" {
  name                = "ag-migration-alerts"
  resource_group_name = azurerm_resource_group.migration.name
  short_name          = "migration"
  
  email_receiver {
    name          = "admin"
    email_address = var.notification_email
  }
  
  # Optional Teams webhook
  dynamic "webhook_receiver" {
    for_each = var.enable_teams_notifications && var.teams_webhook_url != "" ? [1] : []
    content {
      name        = "teams"
      service_uri = var.teams_webhook_url
    }
  }
  
  tags = local.common_tags
}

# Note: Azure Storage Mover resources are currently in preview and may not be available in all regions
# The following resources represent the intended configuration once Storage Mover is generally available

# Storage Mover resource (Preview - may require preview API version)
resource "azurerm_resource_group_template_deployment" "storage_mover" {
  name                = "storage-mover-deployment"
  resource_group_name = azurerm_resource_group.migration.name
  deployment_mode     = "Incremental"
  
  template_content = jsonencode({
    "$schema" = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    parameters = {
      storageMoverName = {
        type = "string"
        defaultValue = local.storage_mover_name
      }
      location = {
        type = "string"
        defaultValue = azurerm_resource_group.migration.location
      }
      description = {
        type = "string"
        defaultValue = var.storage_mover_description
      }
    }
    resources = [
      {
        type = "Microsoft.StorageMover/storageMovers"
        apiVersion = "2023-03-01"
        name = "[parameters('storageMoverName')]"
        location = "[parameters('location')]"
        properties = {
          description = "[parameters('description')]"
        }
        tags = local.common_tags
      }
    ]
    outputs = {
      storageMoverId = {
        type = "string"
        value = "[resourceId('Microsoft.StorageMover/storageMovers', parameters('storageMoverName'))]"
      }
    }
  })
}

# Service Plan for Logic App
resource "azurerm_service_plan" "logic_app" {
  count               = var.enable_logic_app ? 1 : 0
  name                = "plan-${local.name_prefix}-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.migration.name
  location            = azurerm_resource_group.migration.location
  
  os_type  = "Windows"
  sku_name = "WS1"
  
  tags = local.common_tags
}

# Logic App for migration automation
resource "azurerm_logic_app_standard" "migration" {
  count               = var.enable_logic_app ? 1 : 0
  name                = local.logic_app_name
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  
  service_plan_id = azurerm_service_plan.logic_app[0].id
  
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"   = "~18"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.migration.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.migration.connection_string
  }
  
  storage_account_name       = azurerm_storage_account.target.name
  storage_account_access_key = azurerm_storage_account.target.primary_access_key
  
  tags = local.common_tags
}

# Metric alert for migration job failures
resource "azurerm_monitor_metric_alert" "migration_failure" {
  name                = "alert-migration-job-failure"
  resource_group_name = azurerm_resource_group.migration.name
  scopes              = [azurerm_resource_group_template_deployment.storage_mover.id]
  
  description   = "Alert when migration job fails"
  severity      = 1
  frequency     = var.metric_alert_evaluation_frequency
  window_size   = var.metric_alert_window_size
  
  criteria {
    metric_namespace = "Microsoft.StorageMover/storageMovers"
    metric_name      = "JobStatus"
    aggregation      = "Count"
    operator         = "GreaterThanOrEqual"
    threshold        = 1
    
    dimension {
      name     = "Status"
      operator = "Include"
      values   = ["Failed"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.migration_alerts.id
  }
  
  tags = local.common_tags
}

# Metric alert for migration job success
resource "azurerm_monitor_metric_alert" "migration_success" {
  name                = "alert-migration-job-success"
  resource_group_name = azurerm_resource_group.migration.name
  scopes              = [azurerm_resource_group_template_deployment.storage_mover.id]
  
  description   = "Alert when migration job completes successfully"
  severity      = 3
  frequency     = var.metric_alert_evaluation_frequency
  window_size   = var.metric_alert_window_size
  
  criteria {
    metric_namespace = "Microsoft.StorageMover/storageMovers"
    metric_name      = "JobStatus"
    aggregation      = "Count"
    operator         = "GreaterThanOrEqual"
    threshold        = 1
    
    dimension {
      name     = "Status"
      operator = "Include"
      values   = ["Succeeded"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.migration_alerts.id
  }
  
  tags = local.common_tags
}

# Metric alert for high data transfer rates
resource "azurerm_monitor_metric_alert" "high_transfer_rate" {
  name                = "alert-high-transfer-rate"
  resource_group_name = azurerm_resource_group.migration.name
  scopes              = [azurerm_storage_account.target.id]
  
  description   = "Alert when data transfer rate is unusually high"
  severity      = 2
  frequency     = var.metric_alert_evaluation_frequency
  window_size   = "PT15M"
  
  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts"
    metric_name      = "Ingress"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10737418240 # 10 GB in bytes
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.migration_alerts.id
  }
  
  tags = local.common_tags
}

# Diagnostic settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  count                      = var.enable_diagnostic_logs ? 1 : 0
  name                       = "diag-${azurerm_storage_account.target.name}"
  target_resource_id         = azurerm_storage_account.target.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.migration.id
  
  # Metrics
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
    
    retention_policy {
      enabled = true
      days    = 7
    }
  }
  
  metric {
    category = "Capacity"
    
    retention_policy {
      enabled = true
      days    = 7
    }
  }
}

# Diagnostic settings for Blob service
resource "azurerm_monitor_diagnostic_setting" "blob_service" {
  count                      = var.enable_diagnostic_logs ? 1 : 0
  name                       = "diag-${azurerm_storage_account.target.name}-blob"
  target_resource_id         = "${azurerm_storage_account.target.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.migration.id
  
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
    
    retention_policy {
      enabled = true
      days    = 7
    }
  }
  
  metric {
    category = "Capacity"
    
    retention_policy {
      enabled = true
      days    = 7
    }
  }
}

# Data source for existing Azure Arc agents (if any)
data "azurerm_arc_machine" "existing" {
  count               = 0  # This would be used if Arc agents already exist
  name                = "arc-agent-name"
  resource_group_name = azurerm_resource_group.migration.name
}

# Role assignment for Storage Mover to access storage account
resource "azurerm_role_assignment" "storage_mover_contributor" {
  scope                = azurerm_storage_account.target.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  
  depends_on = [azurerm_resource_group_template_deployment.storage_mover]
}

# Role assignment for Logic App to access Storage Mover
resource "azurerm_role_assignment" "logic_app_contributor" {
  count                = var.enable_logic_app ? 1 : 0
  scope                = azurerm_resource_group_template_deployment.storage_mover.id
  role_definition_name = "Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Storage account for Logic App (if different from target storage)
resource "azurerm_storage_account" "logic_app" {
  count               = var.enable_logic_app ? 1 : 0
  name                = "stlogic${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.migration.name
  location            = azurerm_resource_group.migration.location
  
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  tags = local.common_tags
}

# Time delay to allow for resource propagation
resource "time_sleep" "wait_for_deployment" {
  depends_on = [
    azurerm_resource_group_template_deployment.storage_mover,
    azurerm_storage_account.target,
    azurerm_log_analytics_workspace.migration
  ]
  
  create_duration = "60s"
}