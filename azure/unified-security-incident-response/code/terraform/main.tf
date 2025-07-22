# Data sources for current Azure context
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  count   = var.use_random_suffix ? 1 : 0
  length  = var.random_suffix_length
  special = false
  upper   = false
}

locals {
  # Generate suffix for resource names
  suffix = var.use_random_suffix ? random_string.suffix[0].result : ""
  
  # Resource names with suffix
  resource_group_name           = var.use_random_suffix ? "${var.resource_group_name}-${local.suffix}" : var.resource_group_name
  log_analytics_workspace_name  = var.use_random_suffix ? "${var.log_analytics_workspace_name}-${local.suffix}" : var.log_analytics_workspace_name
  logic_app_name               = var.use_random_suffix ? "${var.logic_app_name}-${local.suffix}" : var.logic_app_name
  playbook_name                = var.use_random_suffix ? "${var.playbook_name}-${local.suffix}" : var.playbook_name
  
  # Combined tags
  common_tags = merge(var.tags, {
    "terraform-managed" = "true"
    "created-date"      = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Resource Group for Security Operations
resource "azurerm_resource_group" "security_ops" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for Security Data
resource "azurerm_log_analytics_workspace" "security_workspace" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.security_ops.location
  resource_group_name = azurerm_resource_group.security_ops.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(local.common_tags, {
    component = "security-workspace"
  })
}

# Microsoft Sentinel (SecurityInsights) Solution
resource "azurerm_log_analytics_solution" "sentinel" {
  solution_name         = var.sentinel_solution_name
  location              = azurerm_resource_group.security_ops.location
  resource_group_name   = azurerm_resource_group.security_ops.name
  workspace_resource_id = azurerm_log_analytics_workspace.security_workspace.id
  workspace_name        = azurerm_log_analytics_workspace.security_workspace.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/SecurityInsights"
  }
  
  tags = merge(local.common_tags, {
    component = "sentinel-solution"
  })
}

# Microsoft Sentinel Workspace Configuration
resource "azurerm_sentinel_log_analytics_workspace_onboarding" "sentinel_onboarding" {
  workspace_id                 = azurerm_log_analytics_workspace.security_workspace.id
  customer_managed_key_enabled = false
  
  depends_on = [azurerm_log_analytics_solution.sentinel]
}

# UEBA (User and Entity Behavior Analytics) Settings
resource "azurerm_sentinel_data_connector_ueba" "ueba_settings" {
  count                        = var.enable_ueba ? 1 : 0
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.security_workspace.id
  
  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel_onboarding]
}

# Azure Active Directory Data Connector
resource "azurerm_sentinel_data_connector_azure_active_directory" "aad_connector" {
  count                        = var.enable_azure_ad_connector ? 1 : 0
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.security_workspace.id
  
  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel_onboarding]
}

# Azure Activity Data Connector
resource "azurerm_sentinel_data_connector_azure_activity_log" "activity_connector" {
  count                        = var.enable_azure_activity_connector ? 1 : 0
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.security_workspace.id
  subscription_id              = data.azurerm_subscription.current.subscription_id
  
  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel_onboarding]
}

# Security Events Data Connector
resource "azurerm_sentinel_data_connector_security_events" "security_events_connector" {
  count                        = var.enable_security_events_connector ? 1 : 0
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.security_workspace.id
  
  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel_onboarding]
}

# Office 365 Data Connector
resource "azurerm_sentinel_data_connector_office_365" "office365_connector" {
  count                        = var.enable_office365_connector ? 1 : 0
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.security_workspace.id
  
  exchange_enabled   = true
  sharepoint_enabled = true
  teams_enabled      = true
  
  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel_onboarding]
}

# Microsoft Defender XDR Connector
resource "azurerm_sentinel_data_connector_microsoft_defender_advanced_threat_protection" "defender_connector" {
  count                        = var.enable_defender_connector ? 1 : 0
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.security_workspace.id
  
  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel_onboarding]
}

# Analytics Rule: Suspicious Sign-in Attempts
resource "azurerm_sentinel_alert_rule_scheduled" "suspicious_signin" {
  count                        = var.enable_analytics_rules && var.analytics_rules_config.suspicious_signin.enabled ? 1 : 0
  name                         = "Multiple Failed Sign-in Attempts"
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.security_workspace.id
  display_name                 = "Multiple Failed Sign-in Attempts"
  description                  = "Detects multiple failed sign-in attempts from same user within a short time window"
  severity                     = var.analytics_rules_config.suspicious_signin.severity
  enabled                      = true
  
  query = <<-EOT
    SigninLogs
    | where TimeGenerated >= ago(5m)
    | where ResultType != 0
    | summarize FailedAttempts = count() by UserPrincipalName, bin(TimeGenerated, 5m)
    | where FailedAttempts >= 5
    | extend AccountEntity = UserPrincipalName
  EOT
  
  query_frequency    = var.analytics_rules_config.suspicious_signin.query_frequency
  query_period       = var.analytics_rules_config.suspicious_signin.query_period
  trigger_operator   = "GreaterThan"
  trigger_threshold  = var.analytics_rules_config.suspicious_signin.trigger_threshold
  
  suppression_duration = "PT1H"
  suppression_enabled  = false
  
  tactics = ["CredentialAccess"]
  
  event_grouping {
    aggregation_method = "SingleAlert"
  }
  
  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel_onboarding]
}

# Analytics Rule: Privilege Escalation Detection
resource "azurerm_sentinel_alert_rule_scheduled" "privilege_escalation" {
  count                        = var.enable_analytics_rules && var.analytics_rules_config.privilege_escalation.enabled ? 1 : 0
  name                         = "Privilege Escalation Detected"
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.security_workspace.id
  display_name                 = "Privilege Escalation Detected"
  description                  = "Detects potential privilege escalation activities in Azure AD"
  severity                     = var.analytics_rules_config.privilege_escalation.severity
  enabled                      = true
  
  query = <<-EOT
    AuditLogs
    | where TimeGenerated >= ago(10m)
    | where OperationName in ("Add member to role", "Add app role assignment")
    | where ResultType == "success"
    | extend InitiatedBy = tostring(InitiatedBy.user.userPrincipalName)
    | extend TargetUser = tostring(TargetResources[0].userPrincipalName)
  EOT
  
  query_frequency    = var.analytics_rules_config.privilege_escalation.query_frequency
  query_period       = var.analytics_rules_config.privilege_escalation.query_period
  trigger_operator   = "GreaterThan"
  trigger_threshold  = var.analytics_rules_config.privilege_escalation.trigger_threshold
  
  suppression_duration = "PT1H"
  suppression_enabled  = false
  
  tactics = ["PrivilegeEscalation"]
  
  event_grouping {
    aggregation_method = "AlertPerResult"
  }
  
  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel_onboarding]
}

# Service Principal for Logic Apps
resource "azuread_application" "logic_app_sp" {
  count        = var.enable_automation ? 1 : 0
  display_name = "LogicApp-SecurityOperations-${local.suffix}"
  
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
    
    resource_access {
      id   = "62a82d76-70ea-41e2-9197-370581804d09" # Group.ReadWrite.All
      type = "Role"
    }
    
    resource_access {
      id   = "19dbc75e-c2e2-444c-a770-ec69d8559fc7" # Directory.ReadWrite.All
      type = "Role"
    }
  }
}

resource "azuread_service_principal" "logic_app_sp" {
  count          = var.enable_automation ? 1 : 0
  application_id = azuread_application.logic_app_sp[0].application_id
}

resource "azuread_application_password" "logic_app_sp" {
  count                = var.enable_automation ? 1 : 0
  application_object_id = azuread_application.logic_app_sp[0].object_id
}

# Logic App for Incident Response Automation
resource "azurerm_logic_app_workflow" "incident_response" {
  count               = var.enable_automation ? 1 : 0
  name                = local.logic_app_name
  location            = azurerm_resource_group.security_ops.location
  resource_group_name = azurerm_resource_group.security_ops.name
  
  workflow_schema    = "https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json"
  workflow_version   = "1.0.0.0"
  
  parameters = {
    "$connections" = jsonencode({
      azuresentinel = {
        connectionId = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.security_ops.name}/providers/Microsoft.Web/connections/azuresentinel-${local.suffix}"
        connectionName = "azuresentinel-${local.suffix}"
        id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Web/locations/${var.location}/managedApis/azuresentinel"
      }
    })
  }
  
  workflow_parameters = {
    "$connections" = {
      type         = "Object"
      defaultValue = {}
    }
  }
  
  tags = merge(local.common_tags, {
    component = "incident-response-automation"
  })
}

# Logic App Trigger Definition
resource "azurerm_logic_app_trigger_http_request" "incident_trigger" {
  count        = var.enable_automation ? 1 : 0
  name         = "When_a_response_to_an_Azure_Sentinel_alert_is_triggered"
  logic_app_id = azurerm_logic_app_workflow.incident_response[0].id
  
  schema = jsonencode({
    type = "object"
    properties = {
      IncidentId = {
        type = "string"
      }
      Title = {
        type = "string"
      }
      Severity = {
        type = "string"
      }
      Status = {
        type = "string"
      }
      UserPrincipalName = {
        type = "string"
      }
    }
  })
}

# Security Playbook for User Response
resource "azurerm_logic_app_workflow" "security_playbook" {
  count               = var.enable_automation ? 1 : 0
  name                = local.playbook_name
  location            = azurerm_resource_group.security_ops.location
  resource_group_name = azurerm_resource_group.security_ops.name
  
  workflow_schema    = "https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json"
  workflow_version   = "1.0.0.0"
  
  tags = merge(local.common_tags, {
    component = "security-playbook"
  })
}

# Security Playbook HTTP Trigger
resource "azurerm_logic_app_trigger_http_request" "playbook_trigger" {
  count        = var.enable_automation ? 1 : 0
  name         = "manual"
  logic_app_id = azurerm_logic_app_workflow.security_playbook[0].id
  
  schema = jsonencode({
    type = "object"
    properties = {
      incidentId = {
        type = "string"
      }
      userPrincipalName = {
        type = "string"
      }
      action = {
        type = "string"
      }
    }
  })
}

# Azure Monitor Workbook for Security Operations Dashboard
resource "azurerm_application_insights_workbook" "security_dashboard" {
  count               = var.enable_security_workbook ? 1 : 0
  name                = "security-ops-workbook-${local.suffix}"
  resource_group_name = azurerm_resource_group.security_ops.name
  location            = azurerm_resource_group.security_ops.location
  display_name        = var.workbook_name
  
  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "## Security Operations Overview\n\nThis dashboard provides real-time visibility into security incidents, threat trends, and response metrics."
        }
        name = "text - 0"
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "SecurityIncident\n| where TimeGenerated >= ago(24h)\n| summarize Count = count() by Severity\n| render piechart"
          size = 0
          title = "Incidents by Severity (24h)"
          queryType = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          crossComponentResources = [
            azurerm_log_analytics_workspace.security_workspace.id
          ]
        }
        name = "query - 1"
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "SigninLogs\n| where TimeGenerated >= ago(24h)\n| where ResultType != 0\n| summarize FailedSignins = count() by bin(TimeGenerated, 1h)\n| render timechart"
          size = 0
          title = "Failed Sign-ins Trend (24h)"
          queryType = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          crossComponentResources = [
            azurerm_log_analytics_workspace.security_workspace.id
          ]
        }
        name = "query - 2"
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "SecurityIncident\n| where TimeGenerated >= ago(7d)\n| summarize IncidentCount = count() by Status\n| render barchart"
          size = 0
          title = "Incident Status Distribution (7d)"
          queryType = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          crossComponentResources = [
            azurerm_log_analytics_workspace.security_workspace.id
          ]
        }
        name = "query - 3"
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "AuditLogs\n| where TimeGenerated >= ago(24h)\n| where OperationName contains \"role\"\n| summarize RoleChanges = count() by bin(TimeGenerated, 1h)\n| render timechart"
          size = 0
          title = "Role Changes Over Time (24h)"
          queryType = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          crossComponentResources = [
            azurerm_log_analytics_workspace.security_workspace.id
          ]
        }
        name = "query - 4"
      }
    ]
    fallbackResourceIds = [
      azurerm_log_analytics_workspace.security_workspace.id
    ]
    fromTemplateId = "sentinel-UserAndEntityBehaviorAnalytics"
  })
  
  tags = merge(local.common_tags, {
    component = "security-dashboard"
  })
}

# Role Assignment for Logic Apps to access Sentinel
resource "azurerm_role_assignment" "logic_app_sentinel_contributor" {
  count                = var.enable_automation ? 1 : 0
  scope                = azurerm_log_analytics_workspace.security_workspace.id
  role_definition_name = "Microsoft Sentinel Contributor"
  principal_id         = azuread_service_principal.logic_app_sp[0].object_id
}

# Role Assignment for Logic Apps to read Azure AD
resource "azurerm_role_assignment" "logic_app_directory_reader" {
  count                = var.enable_automation ? 1 : 0
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}"
  role_definition_name = "Directory Readers"
  principal_id         = azuread_service_principal.logic_app_sp[0].object_id
}

# Storage Account for Logic Apps diagnostics and state
resource "azurerm_storage_account" "logic_apps_storage" {
  count                    = var.enable_automation ? 1 : 0
  name                     = "stlogicapps${local.suffix}"
  resource_group_name      = azurerm_resource_group.security_ops.name
  location                 = azurerm_resource_group.security_ops.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }
  
  tags = merge(local.common_tags, {
    component = "logic-apps-storage"
  })
}

# Diagnostic Settings for Log Analytics Workspace
resource "azurerm_monitor_diagnostic_setting" "workspace_diagnostics" {
  name                       = "workspace-diagnostics"
  target_resource_id         = azurerm_log_analytics_workspace.security_workspace.id
  storage_account_id         = var.enable_automation ? azurerm_storage_account.logic_apps_storage[0].id : null
  
  dynamic "enabled_log" {
    for_each = [
      "Audit",
    ]
    content {
      category = enabled_log.value
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# Action Group for Security Alerts
resource "azurerm_monitor_action_group" "security_alerts" {
  name                = "security-alerts-${local.suffix}"
  resource_group_name = azurerm_resource_group.security_ops.name
  short_name          = "SecAlert"
  
  dynamic "logic_app_receiver" {
    for_each = var.enable_automation ? [1] : []
    content {
      name                    = "SecurityPlaybook"
      resource_id             = azurerm_logic_app_workflow.security_playbook[0].id
      callback_url            = "https://management.azure.com/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.security_ops.name}/providers/Microsoft.Logic/workflows/${local.playbook_name}/triggers/manual/paths/invoke"
      use_common_alert_schema = true
    }
  }
  
  tags = merge(local.common_tags, {
    component = "security-alerts"
  })
}

# Budget Alert for Cost Management
resource "azurerm_consumption_budget_resource_group" "security_ops_budget" {
  count           = var.enable_cost_alerts ? 1 : 0
  name            = "security-ops-budget-${local.suffix}"
  resource_group_id = azurerm_resource_group.security_ops.id
  
  amount     = var.monthly_budget_limit
  time_grain = "Monthly"
  
  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
    end_date   = formatdate("YYYY-MM-01'T'00:00:00'Z'", timeadd(timestamp(), "8760h")) # 1 year
  }
  
  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    
    contact_emails = ["security-team@company.com"]
  }
  
  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    
    contact_emails = ["security-team@company.com"]
  }
}