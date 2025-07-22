# Main Terraform configuration for Azure intelligent disaster recovery orchestration
# This configuration deploys a comprehensive disaster recovery solution using
# Azure Backup Center, Recovery Services Vaults, Azure Monitor, and Logic Apps

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ================================================================
# RESOURCE GROUPS
# ================================================================

# Primary resource group for disaster recovery infrastructure
resource "azurerm_resource_group" "primary" {
  name     = "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.primary_location

  tags = merge(var.tags, {
    Name   = "Primary DR Resource Group"
    Region = "primary"
  })
}

# Backup resource group for Recovery Services Vaults
resource "azurerm_resource_group" "backup" {
  name     = "rg-${var.project_name}-backup-${var.environment}-${random_string.suffix.result}"
  location = var.primary_location

  tags = merge(var.tags, {
    Name    = "Backup Resource Group"
    Purpose = "backup-storage"
  })
}

# ================================================================
# LOG ANALYTICS WORKSPACE
# ================================================================

# Log Analytics Workspace for centralized monitoring and logging
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_retention_days

  # Enable additional solutions for comprehensive monitoring
  tags = merge(var.tags, {
    Name = "Disaster Recovery Log Analytics Workspace"
    Type = "monitoring"
  })
}

# Enable Azure Backup solution in Log Analytics
resource "azurerm_log_analytics_solution" "backup" {
  solution_name         = "AzureBackup"
  location              = azurerm_resource_group.primary.location
  resource_group_name   = azurerm_resource_group.primary.name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  workspace_name        = azurerm_log_analytics_workspace.main.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/AzureBackup"
  }

  tags = var.tags
}

# ================================================================
# RECOVERY SERVICES VAULTS
# ================================================================

# Primary Recovery Services Vault for backup operations
resource "azurerm_recovery_services_vault" "primary" {
  name                = "rsv-${var.project_name}-primary-${random_string.suffix.result}"
  location            = azurerm_resource_group.backup.location
  resource_group_name = azurerm_resource_group.backup.name
  sku                 = "Standard"

  # Configure storage settings for disaster recovery
  storage_mode_type                     = var.backup_storage_redundancy
  cross_region_restore_enabled          = var.enable_cross_region_restore
  soft_delete_enabled                   = true
  public_network_access_enabled         = true
  immutability                         = "Disabled"

  # Enable monitoring settings
  monitoring {
    alerts_for_critical_operation_failures_enabled = true
    alerts_for_all_job_failures_enabled           = true
  }

  tags = merge(var.tags, {
    Name   = "Primary Recovery Services Vault"
    Region = "primary"
    Type   = "backup-vault"
  })
}

# Secondary Recovery Services Vault for cross-region disaster recovery
resource "azurerm_recovery_services_vault" "secondary" {
  name                = "rsv-${var.project_name}-secondary-${random_string.suffix.result}"
  location            = var.secondary_location
  resource_group_name = azurerm_resource_group.backup.name
  sku                 = "Standard"

  # Configure storage settings for disaster recovery
  storage_mode_type                     = var.backup_storage_redundancy
  cross_region_restore_enabled          = var.enable_cross_region_restore
  soft_delete_enabled                   = true
  public_network_access_enabled         = true
  immutability                         = "Disabled"

  # Enable monitoring settings
  monitoring {
    alerts_for_critical_operation_failures_enabled = true
    alerts_for_all_job_failures_enabled           = true
  }

  tags = merge(var.tags, {
    Name   = "Secondary Recovery Services Vault"
    Region = "secondary"
    Type   = "backup-vault"
  })
}

# ================================================================
# BACKUP POLICIES
# ================================================================

# Backup policy for Virtual Machine protection
resource "azurerm_backup_policy_vm" "vm_policy" {
  name                = "DRVMPolicy"
  resource_group_name = azurerm_resource_group.backup.name
  recovery_vault_name = azurerm_recovery_services_vault.primary.name

  # Configure backup schedule
  backup {
    frequency = var.vm_backup_frequency
    time      = var.vm_backup_time
  }

  # Configure retention policies for comprehensive protection
  retention_daily {
    count = var.vm_backup_retention_days
  }

  retention_weekly {
    count    = var.vm_weekly_retention_weeks
    weekdays = ["Sunday"]
  }

  retention_monthly {
    count    = 12
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }

  retention_yearly {
    count    = 7
    weekdays = ["Sunday"]
    weeks    = ["First"]
    months   = ["January"]
  }

  tags = var.tags
}

# ================================================================
# DIAGNOSTIC SETTINGS
# ================================================================

# Diagnostic settings for primary Recovery Services Vault
resource "azurerm_monitor_diagnostic_setting" "rsv_primary" {
  name                       = "DiagnosticSettings-${azurerm_recovery_services_vault.primary.name}"
  target_resource_id         = azurerm_recovery_services_vault.primary.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Enable comprehensive logging for backup operations
  enabled_log {
    category = "AddonAzureBackupJobs"
  }

  enabled_log {
    category = "AddonAzureBackupAlerts"
  }

  enabled_log {
    category = "AddonAzureBackupPolicy"
  }

  enabled_log {
    category = "AddonAzureBackupStorage"
  }

  enabled_log {
    category = "AddonAzureBackupProtectedInstance"
  }

  # Enable metrics monitoring
  metric {
    category = "Health"
    enabled  = true
  }
}

# Diagnostic settings for secondary Recovery Services Vault
resource "azurerm_monitor_diagnostic_setting" "rsv_secondary" {
  name                       = "DiagnosticSettings-${azurerm_recovery_services_vault.secondary.name}"
  target_resource_id         = azurerm_recovery_services_vault.secondary.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Enable comprehensive logging for backup operations
  enabled_log {
    category = "AddonAzureBackupJobs"
  }

  enabled_log {
    category = "AddonAzureBackupAlerts"
  }

  enabled_log {
    category = "AddonAzureBackupPolicy"
  }

  enabled_log {
    category = "AddonAzureBackupStorage"
  }

  enabled_log {
    category = "AddonAzureBackupProtectedInstance"
  }

  # Enable metrics monitoring
  metric {
    category = "Health"
    enabled  = true
  }
}

# ================================================================
# ACTION GROUPS FOR ALERTING
# ================================================================

# Action Group for disaster recovery notifications
resource "azurerm_monitor_action_group" "dr_alerts" {
  name                = "ag-${var.project_name}-alerts-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.primary.name
  short_name          = "DR-Alerts"

  # Email notification action
  email_receiver {
    name          = "admin-email"
    email_address = var.admin_email
  }

  # SMS notification action
  sms_receiver {
    name         = "admin-sms"
    country_code = substr(var.admin_phone, 1, 1)
    phone_number = substr(var.admin_phone, 2, -1)
  }

  # Webhook action for Logic Apps integration (if enabled)
  dynamic "webhook_receiver" {
    for_each = var.enable_logic_apps ? [1] : []
    content {
      name        = "dr-webhook"
      service_uri = var.enable_logic_apps ? azurerm_logic_app_workflow.dr_orchestration[0].access_endpoint : ""
    }
  }

  tags = merge(var.tags, {
    Name = "Disaster Recovery Action Group"
    Type = "alerting"
  })
}

# ================================================================
# AZURE MONITOR ALERT RULES
# ================================================================

# Alert rule for backup job failures
resource "azurerm_monitor_metric_alert" "backup_job_failure" {
  name                = "BackupJobFailureAlert"
  resource_group_name = azurerm_resource_group.primary.name
  scopes              = [azurerm_recovery_services_vault.primary.id]
  description         = "Alert when backup jobs fail"
  severity            = 2
  frequency           = "PT${var.alert_evaluation_frequency}M"
  window_size         = "PT${var.alert_window_size}M"

  criteria {
    metric_namespace = "Microsoft.RecoveryServices/vaults"
    metric_name      = "BackupHealthEvent"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = azurerm_monitor_action_group.dr_alerts.id
  }

  tags = var.tags
}

# Alert rule for Recovery Services Vault health
resource "azurerm_monitor_metric_alert" "vault_health" {
  name                = "RecoveryVaultHealthAlert"
  resource_group_name = azurerm_resource_group.primary.name
  scopes              = [azurerm_recovery_services_vault.primary.id]
  description         = "Alert when Recovery Services Vault becomes unhealthy"
  severity            = 1
  frequency           = "PT${var.alert_evaluation_frequency}M"
  window_size         = "PT${var.alert_window_size}M"

  criteria {
    metric_namespace = "Microsoft.RecoveryServices/vaults"
    metric_name      = "Health"
    aggregation      = "Count"
    operator         = "LessThan"
    threshold        = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.dr_alerts.id
  }

  tags = var.tags
}

# Scheduled query alert for backup storage consumption
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "storage_consumption" {
  count               = var.enable_advanced_monitoring ? 1 : 0
  name                = "BackupStorageConsumptionAlert"
  resource_group_name = azurerm_resource_group.primary.name
  location            = azurerm_resource_group.primary.location
  
  evaluation_frequency = "PT60M"
  window_duration     = "PT60M"
  scopes              = [azurerm_log_analytics_workspace.main.id]
  severity            = 3
  description         = "Alert when backup storage consumption exceeds threshold"

  criteria {
    query                   = <<-QUERY
      AzureBackupReport
      | where TimeGenerated > ago(1h)
      | where StorageConsumedInMBs > 100000
      | summarize count()
    QUERY
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.dr_alerts.id]
  }

  tags = var.tags
}

# ================================================================
# STORAGE ACCOUNT FOR LOGIC APPS
# ================================================================

# Storage account for Logic Apps state management
resource "azurerm_storage_account" "logic_apps" {
  count                    = var.enable_logic_apps ? 1 : 0
  name                     = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.primary.name
  location                 = azurerm_resource_group.primary.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"

  # Enable security features
  enable_https_traffic_only       = true
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false

  # Configure blob properties for secure access
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = merge(var.tags, {
    Name = "Logic Apps Storage Account"
    Type = "storage"
  })
}

# ================================================================
# LOGIC APPS WORKFLOW
# ================================================================

# Logic Apps workflow for disaster recovery orchestration
resource "azurerm_logic_app_workflow" "dr_orchestration" {
  count               = var.enable_logic_apps ? 1 : 0
  name                = "la-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name

  # Enable managed identity for secure Azure resource access
  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    Name = "Disaster Recovery Orchestration Logic App"
    Type = "automation"
  })
}

# Logic Apps workflow definition for disaster recovery automation
resource "azurerm_logic_app_trigger_http_request" "dr_trigger" {
  count        = var.enable_logic_apps ? 1 : 0
  name         = "manual"
  logic_app_id = azurerm_logic_app_workflow.dr_orchestration[0].id

  schema = <<SCHEMA
{
    "type": "object",
    "properties": {
        "data": {
            "type": "object",
            "properties": {
                "context": {
                    "type": "object",
                    "properties": {
                        "subscriptionId": {
                            "type": "string"
                        },
                        "resourceGroupName": {
                            "type": "string"
                        },
                        "resourceName": {
                            "type": "string"
                        }
                    }
                }
            }
        }
    }
}
SCHEMA
}

# ================================================================
# AZURE MONITOR WORKBOOKS
# ================================================================

# Disaster Recovery monitoring workbook
resource "azurerm_application_insights_workbook" "dr_dashboard" {
  count               = var.enable_workbooks ? 1 : 0
  name                = "disaster-recovery-dashboard-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.primary.name
  location            = azurerm_resource_group.primary.location
  display_name        = "Disaster Recovery Dashboard"
  description         = "Comprehensive disaster recovery monitoring and reporting dashboard"

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "# Disaster Recovery Dashboard\n\nThis dashboard provides comprehensive visibility into backup operations, recovery readiness, and disaster recovery metrics across all protected resources."
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "AzureBackupReport | where TimeGenerated > ago(24h) | summarize BackupJobs = count() by BackupItemType, JobStatus | render piechart"
          size = 0
          title = "Backup Job Status by Resource Type"
          queryType = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          visualization = "piechart"
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "AzureBackupReport | where TimeGenerated > ago(7d) | summarize TotalStorageGB = sum(StorageConsumedInMBs)/1024 by bin(TimeGenerated, 1d) | render timechart"
          size = 0
          title = "Storage Consumption Trend"
          queryType = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          visualization = "timechart"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "DR Monitoring Workbook"
    Type = "visualization"
  })
}

# ================================================================
# RBAC ASSIGNMENTS
# ================================================================

# Assign Backup Contributor role to Logic Apps managed identity
resource "azurerm_role_assignment" "logic_apps_backup" {
  count                = var.enable_logic_apps ? 1 : 0
  scope                = azurerm_recovery_services_vault.primary.id
  role_definition_name = "Backup Contributor"
  principal_id         = azurerm_logic_app_workflow.dr_orchestration[0].identity[0].principal_id
}

# Assign Backup Contributor role to Logic Apps for secondary vault
resource "azurerm_role_assignment" "logic_apps_backup_secondary" {
  count                = var.enable_logic_apps ? 1 : 0
  scope                = azurerm_recovery_services_vault.secondary.id
  role_definition_name = "Backup Contributor"
  principal_id         = azurerm_logic_app_workflow.dr_orchestration[0].identity[0].principal_id
}

# Assign Monitoring Contributor role to Logic Apps
resource "azurerm_role_assignment" "logic_apps_monitoring" {
  count                = var.enable_logic_apps ? 1 : 0
  scope                = azurerm_resource_group.primary.id
  role_definition_name = "Monitoring Contributor"
  principal_id         = azurerm_logic_app_workflow.dr_orchestration[0].identity[0].principal_id
}