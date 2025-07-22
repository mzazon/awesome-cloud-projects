# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Current Azure client configuration
data "azurerm_client_config" "current" {}

# Current Azure subscription information
data "azurerm_subscription" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.tags, {
    CreatedBy = "Terraform"
    Purpose   = "Azure Service Health and Update Manager Monitoring"
  })
}

# Log Analytics Workspace for centralized monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days

  tags = merge(var.tags, {
    Component = "Monitoring"
  })
}

# Action Group for alert notifications
resource "azurerm_monitor_action_group" "service_health" {
  name                = "ag-service-health-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "SvcHealth"

  email_receiver {
    name          = "admin"
    email_address = var.alert_email_address
  }

  dynamic "webhook_receiver" {
    for_each = var.webhook_url != "" ? [1] : []
    content {
      name        = "health-webhook"
      service_uri = var.webhook_url
    }
  }

  tags = merge(var.tags, {
    Component = "Alerting"
  })
}

# Service Health Alert Rule
resource "azurerm_monitor_activity_log_alert" "service_health" {
  count               = var.enable_service_health_alerts ? 1 : 0
  name                = "Service Health Issues"
  resource_group_name = azurerm_resource_group.main.name
  description         = "Alert for Azure Service Health incidents"
  
  scopes = length(var.service_health_alert_scopes) > 0 ? var.service_health_alert_scopes : [data.azurerm_subscription.current.id]

  criteria {
    category = "ServiceHealth"
    
    service_health {
      events    = ["Incident", "Maintenance", "Informational", "ActionRequired"]
      locations = var.service_health_alert_regions
      services  = var.service_health_alert_services
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.service_health.id
  }

  tags = merge(var.tags, {
    Component = "Service Health Monitoring"
  })
}

# Update Manager Policy Assignment for periodic assessment
resource "azurerm_subscription_policy_assignment" "update_manager_assessment" {
  name                 = "Enable-UpdateManager-Assessment-${random_string.suffix.result}"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/59efceea-0c96-497e-a4a1-4eb2290dac15"
  subscription_id      = data.azurerm_subscription.current.id
  display_name         = "Enable Update Manager Assessment"
  description          = "Policy to enable periodic assessment for Update Manager"

  parameters = jsonencode({
    assessmentMode = {
      value = var.assessment_mode
    }
    assessmentSchedule = {
      value = "Daily"
    }
  })

  metadata = jsonencode({
    createdBy = "Terraform"
    purpose   = "Update Manager Assessment"
  })
}

# Maintenance Configuration for patch management
resource "azurerm_maintenance_configuration" "critical_patches" {
  name                = "critical-patches-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  scope               = "InGuestPatch"

  window {
    start_date_time      = "2025-01-15 ${format("%02d", var.patch_schedule_hour)}:00"
    duration             = "${format("%02d", var.patch_schedule_duration)}:00"
    time_zone            = "UTC"
    recur_every          = "1Week"
    reboot_setting       = "IfRequired"
  }

  install_patches {
    linux {
      classifications_to_include = ["Critical", "Security"]
      packages_name_masks_to_exclude = []
      packages_name_masks_to_include = []
    }
    
    windows {
      classifications_to_include = ["Critical", "Security", "UpdateRollup", "FeaturePack", "ServicePack", "Definition", "Tools", "Updates"]
      kb_numbers_to_exclude       = []
      kb_numbers_to_include       = []
    }
    
    reboot = "IfRequired"
  }

  tags = merge(var.tags, {
    Component = "Patch Management"
  })
}

# Logic App for automated correlation workflow
resource "azurerm_logic_app_workflow" "health_correlation" {
  name                = var.logic_app_name != "" ? var.logic_app_name : "la-health-correlation-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  workflow_schema   = "https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version  = "1.0.0.0"

  # Basic workflow definition for Service Health correlation
  workflow_parameters = jsonencode({
    "$connections" = {
      defaultValue = {}
      type         = "Object"
    }
  })

  tags = merge(var.tags, {
    Component = "Automation"
  })
}

# Logic App Trigger for Service Health webhooks
resource "azurerm_logic_app_trigger_http_request" "service_health_webhook" {
  name         = "service_health_webhook"
  logic_app_id = azurerm_logic_app_workflow.health_correlation.id

  schema = jsonencode({
    type = "object"
    properties = {
      schemaId = {
        type = "string"
      }
      data = {
        type = "object"
      }
    }
  })
}

# Automation Account for remediation workflows
resource "azurerm_automation_account" "health_remediation" {
  name                = "aa-health-remediation-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = var.automation_account_sku

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    Component = "Automation"
  })
}

# Automation Runbook for remediation actions
resource "azurerm_automation_runbook" "remediate_critical_patches" {
  count                   = var.enable_automation_runbooks ? 1 : 0
  name                    = "Remediate-Critical-Patches"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.health_remediation.name
  log_verbose             = true
  log_progress            = true
  description             = "Automated remediation for critical patch issues"
  runbook_type            = "PowerShell"

  content = <<-CONTENT
    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory=$true)]
        [string]$VirtualMachineName
    )

    Write-Output "Starting critical patch remediation for VM: $VirtualMachineName"

    try {
        # Connect using system-assigned managed identity
        Connect-AzAccount -Identity
        
        # Get VM information
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VirtualMachineName
        
        if ($vm) {
            Write-Output "VM found. Initiating update assessment..."
            
            # Trigger update assessment
            Start-AzVMUpdateAssessment -ResourceGroupName $ResourceGroupName -VMName $VirtualMachineName
            
            Write-Output "Update assessment initiated successfully"
        } else {
            Write-Error "VM not found: $VirtualMachineName"
        }
    }
    catch {
        Write-Error "Error during remediation: $($_.Exception.Message)"
        throw
    }
  CONTENT

  tags = merge(var.tags, {
    Component = "Automation"
  })
}

# Automation Webhook for runbook triggering
resource "azurerm_automation_webhook" "health_remediation" {
  count                   = var.enable_automation_runbooks ? 1 : 0
  name                    = "health-remediation-webhook"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.health_remediation.name
  expiry_time             = "2026-01-01T00:00:00Z"
  enabled                 = true
  runbook_name            = azurerm_automation_runbook.remediate_critical_patches[0].name
}

# Scheduled Query Alert for Critical Patch Compliance
resource "azurerm_monitor_scheduled_query_rule" "critical_patch_compliance" {
  count               = var.enable_update_manager_alerts ? 1 : 0
  name                = "Critical-Patch-Compliance-Alert"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  action {
    action_groups = [azurerm_monitor_action_group.service_health.id]
  }
  
  data_source_id = azurerm_log_analytics_workspace.main.id
  description    = "Alert when VMs have critical patches missing"
  enabled        = true
  
  query                = <<-QUERY
    UpdateSummary
    | where Classification == "Critical Updates" 
    | where Computer != "" 
    | where UpdateState == "Needed"
    | distinct Computer
  QUERY
  
  severity    = 2
  frequency   = "PT${var.alert_evaluation_frequency}M"
  time_window = "PT${var.alert_window_size}M"
  
  trigger {
    operator  = "GreaterThan"
    threshold = var.critical_alert_threshold
  }

  tags = merge(var.tags, {
    Component = "Update Manager Monitoring"
  })
}

# Scheduled Query Alert for Update Installation Failures
resource "azurerm_monitor_scheduled_query_rule" "update_installation_failures" {
  count               = var.enable_update_manager_alerts ? 1 : 0
  name                = "Update-Installation-Failures"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  action {
    action_groups = [azurerm_monitor_action_group.service_health.id]
  }
  
  data_source_id = azurerm_log_analytics_workspace.main.id
  description    = "Alert when update installations fail"
  enabled        = true
  
  query                = <<-QUERY
    UpdateRunProgress
    | where InstallationStatus == "Failed"
    | distinct Computer
  QUERY
  
  severity    = 1
  frequency   = "PT5M"
  time_window = "PT5M"
  
  trigger {
    operator  = "GreaterThan"
    threshold = 0
  }

  tags = merge(var.tags, {
    Component = "Update Manager Monitoring"
  })
}

# Metric Alert for Automation Effectiveness
resource "azurerm_monitor_metric_alert" "automation_effectiveness" {
  name                = "Automation-Effectiveness-Metric"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_automation_account.health_remediation.id]
  description         = "Alert when automation success rate drops below threshold"
  severity            = 3
  frequency           = "PT5M"
  window_size         = "PT15M"
  
  criteria {
    metric_namespace = "Microsoft.Automation/automationAccounts"
    metric_name      = "TotalJob"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.automation_success_rate_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.service_health.id
  }

  tags = merge(var.tags, {
    Component = "Automation Monitoring"
  })
}

# Azure Workbook for Health Monitoring Dashboard
resource "azurerm_application_insights_workbook" "health_dashboard" {
  count               = var.enable_workbook_dashboard ? 1 : 0
  name                = "Health-Monitoring-Dashboard"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  display_name        = "Infrastructure Health Monitoring"
  description         = "Comprehensive dashboard for service health and patch compliance"
  category            = "health-monitoring"

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query   = "ServiceHealthResources | where type == \"microsoft.resourcehealth/events\" | summarize count() by tostring(properties.eventType)"
          size    = 0
          title   = "Service Health Events Summary"
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query   = "UpdateSummary | where Classification == \"Critical Updates\" | summarize count() by UpdateState"
          size    = 0
          title   = "Critical Patch Compliance Status"
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query   = "UpdateRunProgress | where TimeGenerated >= ago(7d) | summarize count() by InstallationStatus"
          size    = 0
          title   = "Update Installation Results (Last 7 Days)"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Component = "Dashboard"
  })
}

# Role Assignment for Automation Account to manage Update Manager
resource "azurerm_role_assignment" "automation_update_manager" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Update Manager Contributor"
  principal_id         = azurerm_automation_account.health_remediation.identity[0].principal_id
}

# Role Assignment for Automation Account to read Log Analytics
resource "azurerm_role_assignment" "automation_log_reader" {
  scope                = azurerm_log_analytics_workspace.main.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_automation_account.health_remediation.identity[0].principal_id
}

# Diagnostic Settings for Log Analytics Workspace
resource "azurerm_monitor_diagnostic_setting" "log_analytics_diagnostics" {
  count              = var.enable_diagnostic_settings ? 1 : 0
  name               = "log-analytics-diagnostics"
  target_resource_id = azurerm_log_analytics_workspace.main.id
  
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "Audit"
  }

  metric {
    category = "AllMetrics"
  }
}

# Diagnostic Settings for Automation Account
resource "azurerm_monitor_diagnostic_setting" "automation_diagnostics" {
  count              = var.enable_diagnostic_settings ? 1 : 0
  name               = "automation-diagnostics"
  target_resource_id = azurerm_automation_account.health_remediation.id
  
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "JobLogs"
  }

  enabled_log {
    category = "JobStreams"
  }

  enabled_log {
    category = "DscNodeStatus"
  }

  metric {
    category = "AllMetrics"
  }
}

# Diagnostic Settings for Logic App
resource "azurerm_monitor_diagnostic_setting" "logic_app_diagnostics" {
  count              = var.enable_diagnostic_settings ? 1 : 0
  name               = "logic-app-diagnostics"
  target_resource_id = azurerm_logic_app_workflow.health_correlation.id
  
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "WorkflowRuntime"
  }

  metric {
    category = "AllMetrics"
  }
}