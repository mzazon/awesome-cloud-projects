# Azure Cost Optimization Infrastructure with Azure Copilot and Azure Monitor
# This Terraform configuration deploys a complete cost optimization solution

# Data sources for current subscription and client configuration
data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and tagging
locals {
  suffix = random_id.suffix.hex
  
  # Resource naming convention
  resource_prefix = "${var.project_name}-${var.environment}"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment     = var.environment
    Project         = var.project_name
    Purpose         = "cost-optimization"
    ManagedBy      = "terraform"
    DeploymentDate = timestamp()
  })
  
  # Resource group name with fallback to generated name
  resource_group_name = var.resource_group_name != null ? var.resource_group_name : "rg-${local.resource_prefix}-${local.suffix}"
}

# Resource Group for all cost optimization resources
resource "azurerm_resource_group" "cost_optimization" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for centralized monitoring and logging
resource "azurerm_log_analytics_workspace" "cost_optimization" {
  name                = "law-${local.resource_prefix}-${local.suffix}"
  location            = azurerm_resource_group.cost_optimization.location
  resource_group_name = azurerm_resource_group.cost_optimization.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(local.common_tags, {
    Component = "monitoring"
  })
}

# Azure Automation Account for cost optimization runbooks
resource "azurerm_automation_account" "cost_optimization" {
  name                = "aa-${local.resource_prefix}-${local.suffix}"
  location            = azurerm_resource_group.cost_optimization.location
  resource_group_name = azurerm_resource_group.cost_optimization.name
  sku_name           = var.automation_account_sku
  
  # Enable system-assigned managed identity for secure authentication
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.common_tags, {
    Component = "automation"
  })
}

# PowerShell runbook for VM cost optimization
resource "azurerm_automation_runbook" "vm_optimization" {
  count = var.enable_vm_optimization ? 1 : 0
  
  name                    = "Optimize-VMSize"
  location                = azurerm_resource_group.cost_optimization.location
  resource_group_name     = azurerm_resource_group.cost_optimization.name
  automation_account_name = azurerm_automation_account.cost_optimization.name
  log_verbose             = true
  log_progress            = true
  runbook_type           = "PowerShell"
  
  # VM optimization runbook content
  content = templatefile("${path.module}/runbooks/vm-optimization.ps1", {
    subscription_id = data.azurerm_subscription.current.subscription_id
  })
  
  tags = merge(local.common_tags, {
    Component = "automation"
    Purpose   = "vm-optimization"
  })
}

# PowerShell runbook for storage cost optimization
resource "azurerm_automation_runbook" "storage_optimization" {
  count = var.enable_storage_optimization ? 1 : 0
  
  name                    = "Optimize-StorageTiers"
  location                = azurerm_resource_group.cost_optimization.location
  resource_group_name     = azurerm_resource_group.cost_optimization.name
  automation_account_name = azurerm_automation_account.cost_optimization.name
  log_verbose             = true
  log_progress            = true
  runbook_type           = "PowerShell"
  
  # Storage optimization runbook content
  content = templatefile("${path.module}/runbooks/storage-optimization.ps1", {
    subscription_id = data.azurerm_subscription.current.subscription_id
  })
  
  tags = merge(local.common_tags, {
    Component = "automation"
    Purpose   = "storage-optimization"
  })
}

# Schedule for automated cost optimization
resource "azurerm_automation_schedule" "optimization_schedule" {
  name                    = "DailyCostOptimization"
  resource_group_name     = azurerm_resource_group.cost_optimization.name
  automation_account_name = azurerm_automation_account.cost_optimization.name
  frequency               = "Day"
  interval                = 1
  timezone                = "UTC"
  start_time              = "2024-01-01T02:00:00Z"
  description             = "Daily schedule for automated cost optimization"
}

# Link VM optimization runbook to schedule
resource "azurerm_automation_job_schedule" "vm_optimization_schedule" {
  count = var.enable_vm_optimization ? 1 : 0
  
  resource_group_name     = azurerm_resource_group.cost_optimization.name
  automation_account_name = azurerm_automation_account.cost_optimization.name
  schedule_name           = azurerm_automation_schedule.optimization_schedule.name
  runbook_name           = azurerm_automation_runbook.vm_optimization[0].name
}

# Link storage optimization runbook to schedule
resource "azurerm_automation_job_schedule" "storage_optimization_schedule" {
  count = var.enable_storage_optimization ? 1 : 0
  
  resource_group_name     = azurerm_resource_group.cost_optimization.name
  automation_account_name = azurerm_automation_account.cost_optimization.name
  schedule_name           = azurerm_automation_schedule.optimization_schedule.name
  runbook_name           = azurerm_automation_runbook.storage_optimization[0].name
}

# Action Group for cost alert notifications
resource "azurerm_monitor_action_group" "cost_alerts" {
  name                = "ag-${local.resource_prefix}-cost-alerts-${local.suffix}"
  resource_group_name = azurerm_resource_group.cost_optimization.name
  short_name          = "CostAlerts"
  
  # Email notifications for cost alerts
  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name          = "admin-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }
  
  # Webhook to trigger automation runbooks
  webhook_receiver {
    name        = "automation-webhook"
    service_uri = azurerm_automation_webhook.cost_optimization.uri
  }
  
  tags = merge(local.common_tags, {
    Component = "monitoring"
  })
}

# Automation webhook for cost alert responses
resource "azurerm_automation_webhook" "cost_optimization" {
  name                    = "CostOptimizationWebhook"
  resource_group_name     = azurerm_resource_group.cost_optimization.name
  automation_account_name = azurerm_automation_account.cost_optimization.name
  expiry_time            = timeadd(timestamp(), "8760h") # 1 year from now
  enabled                = true
  runbook_name           = var.enable_vm_optimization ? azurerm_automation_runbook.vm_optimization[0].name : null
}

# Monitor metric alert for cost anomaly detection
resource "azurerm_monitor_metric_alert" "cost_anomaly" {
  count = var.enable_cost_anomaly_detection ? 1 : 0
  
  name                = "alert-${local.resource_prefix}-cost-anomaly-${local.suffix}"
  resource_group_name = azurerm_resource_group.cost_optimization.name
  scopes              = [data.azurerm_subscription.current.id]
  description         = "Alert for unusual cost spikes indicating potential optimization opportunities"
  
  criteria {
    metric_namespace = "Microsoft.Consumption/budgets"
    metric_name      = "ActualCost"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.budget_amount * (var.cost_alert_threshold / 100)
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.cost_alerts.id
  }
  
  frequency   = "PT1H"
  window_size = "PT1H"
  severity    = 2
  
  tags = merge(local.common_tags, {
    Component = "monitoring"
    AlertType = "cost-anomaly"
  })
}

# Diagnostic settings for activity log monitoring
resource "azurerm_monitor_diagnostic_setting" "subscription_logs" {
  name           = "diag-${local.resource_prefix}-subscription-${local.suffix}"
  target_resource_id = data.azurerm_subscription.current.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.cost_optimization.id
  
  # Enable relevant log categories for cost optimization
  enabled_log {
    category = "Administrative"
  }
  
  enabled_log {
    category = "ServiceHealth"
  }
  
  enabled_log {
    category = "ResourceHealth"
  }
  
  enabled_log {
    category = "Alert"
  }
  
  enabled_log {
    category = "Recommendation"
  }
}

# Role assignment for Automation Account managed identity
resource "azurerm_role_assignment" "automation_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_automation_account.cost_optimization.identity[0].principal_id
}

# Additional role assignment for cost management
resource "azurerm_role_assignment" "automation_cost_management" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Cost Management Reader"
  principal_id         = azurerm_automation_account.cost_optimization.identity[0].principal_id
}

# Logic App for advanced cost optimization workflows
resource "azurerm_logic_app_workflow" "cost_optimization" {
  name                = "logic-${local.resource_prefix}-costopt-${local.suffix}"
  location            = azurerm_resource_group.cost_optimization.location
  resource_group_name = azurerm_resource_group.cost_optimization.name
  
  # Workflow definition for cost optimization automation
  workflow_schema   = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version  = "1.0.0.0"
  
  tags = merge(local.common_tags, {
    Component = "automation"
    Purpose   = "workflow-orchestration"
  })
}

# Application Insights for monitoring automation performance
resource "azurerm_application_insights" "cost_optimization" {
  name                = "appi-${local.resource_prefix}-${local.suffix}"
  location            = azurerm_resource_group.cost_optimization.location
  resource_group_name = azurerm_resource_group.cost_optimization.name
  workspace_id        = azurerm_log_analytics_workspace.cost_optimization.id
  application_type    = "web"
  
  tags = merge(local.common_tags, {
    Component = "monitoring"
  })
}