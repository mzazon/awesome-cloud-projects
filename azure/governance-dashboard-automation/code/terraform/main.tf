# ===============================================
# Azure Governance Dashboard with Resource Graph and Monitor Workbooks
# ===============================================
# This Terraform configuration deploys a comprehensive governance solution
# using Azure Resource Graph for data queries and Azure Monitor Workbooks
# for visualization, with automated alerts and Logic Apps workflows.

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {}
}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Data source to get current subscription details
data "azurerm_subscription" "current" {}

# ===============================================
# Resource Group
# ===============================================

resource "azurerm_resource_group" "governance" {
  name     = var.resource_group_name
  location = var.location

  tags = var.default_tags
}

# ===============================================
# Log Analytics Workspace for Governance Data
# ===============================================

resource "azurerm_log_analytics_workspace" "governance" {
  name                = "${var.workspace_name_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.governance.location
  resource_group_name = azurerm_resource_group.governance.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days

  tags = merge(var.default_tags, {
    Purpose = "Governance Data Storage"
  })
}

# ===============================================
# Monitor Workbook for Governance Dashboard
# ===============================================

resource "azurerm_monitor_workbook" "governance_dashboard" {
  name                = "${var.workbook_name_prefix}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.governance.name
  location            = azurerm_resource_group.governance.location
  display_name        = var.workbook_display_name
  description         = var.workbook_description
  category            = "governance"

  # Workbook template with Resource Graph queries for governance insights
  serialized_data = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "# Azure Governance Dashboard\n\nThis dashboard provides comprehensive visibility into Azure resource governance, compliance, and security posture across your organization.\n\n**Key Features:**\n- Real-time compliance monitoring\n- Resource tagging analysis\n- Policy violation tracking\n- Security posture assessment"
        }
        name = "Dashboard Title"
      },
      {
        type = 9
        content = {
          version = "KqlParameterItem/1.0"
          parameters = [
            {
              id          = "subscription-param"
              version     = "KqlParameterItem/1.0"
              name        = "Subscription"
              type        = 6
              description = "Select subscription(s) to monitor"
              isRequired  = true
              multiSelect = true
              quote       = "'"
              delimiter   = ","
              value       = []
            },
            {
              id          = "timerange-param"
              version     = "KqlParameterItem/1.0"
              name        = "TimeRange"
              type        = 4
              description = "Select time range for analysis"
              isRequired  = true
              value = {
                durationMs = 86400000
              }
            }
          ]
          style         = "pills"
          queryType     = 1
          resourceType  = "microsoft.resourcegraph/resources"
        }
        name = "Dashboard Parameters"
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "resources | summarize ResourceCount=count() by Type=type | top 10 by ResourceCount desc"
          size         = 0
          title        = "Top 10 Resource Types"
          queryType    = 1
          resourceType = "microsoft.resourcegraph/resources"
          visualization = "piechart"
        }
        name = "Resource Types Chart"
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "resources | where tags !has 'Environment' or tags !has 'Owner' or tags !has 'CostCenter' | summarize NonCompliantResources=count() by ResourceGroup=resourceGroup | top 10 by NonCompliantResources desc"
          size         = 0
          title        = "Resources Missing Required Tags"
          queryType    = 1
          resourceType = "microsoft.resourcegraph/resources"
          visualization = "table"
        }
        name = "Compliance Table"
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "resources | where location !in ('${var.allowed_locations[0]}', '${var.allowed_locations[1]}', '${var.allowed_locations[2]}') | project name, type, resourceGroup, location, subscriptionId | limit 100"
          size         = 0
          title        = "Resources in Non-Compliant Locations"
          queryType    = 1
          resourceType = "microsoft.resourcegraph/resources"
          visualization = "table"
        }
        name = "Location Compliance"
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "policyresources | where type == 'microsoft.policyinsights/policystates' | summarize PolicyViolations=count() by ComplianceState=complianceState"
          size         = 0
          title        = "Policy Compliance Overview"
          queryType    = 1
          resourceType = "microsoft.resourcegraph/resources"
          visualization = "barchart"
        }
        name = "Policy Compliance Chart"
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "securityresources | where type == 'microsoft.security/assessments' | summarize SecurityFindings=count() by Severity=properties.metadata.severity"
          size         = 0
          title        = "Security Assessment Summary"
          queryType    = 1
          resourceType = "microsoft.resourcegraph/resources"
          visualization = "piechart"
        }
        name = "Security Assessment"
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "resources | summarize ResourceCount=count() by Location=location, Type=type | order by ResourceCount desc"
          size         = 0
          title        = "Resource Distribution by Location and Type"
          queryType    = 1
          resourceType = "microsoft.resourcegraph/resources"
          visualization = "table"
        }
        name = "Resource Distribution"
      }
    ]
    fallbackResourceIds = []
    fromTemplateId      = "governance-dashboard-template"
  })

  tags = merge(var.default_tags, {
    Purpose = "Governance Dashboard"
  })
}

# ===============================================
# Logic App for Governance Automation
# ===============================================

resource "azurerm_logic_app_workflow" "governance_automation" {
  name                = "${var.logic_app_name_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.governance.location
  resource_group_name = azurerm_resource_group.governance.name

  tags = merge(var.default_tags, {
    Purpose = "Governance Automation"
  })
}

# Logic App Trigger for HTTP requests
resource "azurerm_logic_app_trigger_http_request" "governance_trigger" {
  name         = "governance-alert-trigger"
  logic_app_id = azurerm_logic_app_workflow.governance_automation.id

  schema = jsonencode({
    type = "object"
    properties = {
      alertType = {
        type = "string"
      }
      resourceId = {
        type = "string"
      }
      severity = {
        type = "string"
      }
      subscriptionId = {
        type = "string"
      }
      resourceGroup = {
        type = "string"
      }
      timestamp = {
        type = "string"
      }
    }
    required = ["alertType", "resourceId", "severity"]
  })
}

# Logic App Action for sending notifications
resource "azurerm_logic_app_action_http" "send_notification" {
  name         = "send-governance-notification"
  logic_app_id = azurerm_logic_app_workflow.governance_automation.id

  method = "POST"
  uri    = var.notification_webhook_url

  headers = {
    "Content-Type" = "application/json"
  }

  body = jsonencode({
    text = "🚨 *Governance Alert*\n*Type:* @{triggerBody()?['alertType']}\n*Resource:* @{triggerBody()?['resourceId']}\n*Severity:* @{triggerBody()?['severity']}\n*Subscription:* @{triggerBody()?['subscriptionId']}\n*Time:* @{triggerBody()?['timestamp']}"
  })

  depends_on = [azurerm_logic_app_trigger_http_request.governance_trigger]
}

# ===============================================
# Action Group for Governance Alerts
# ===============================================

resource "azurerm_monitor_action_group" "governance_alerts" {
  name                = "${var.action_group_name_prefix}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.governance.name
  short_name          = "gov-alerts"

  # Webhook action to trigger Logic App
  webhook_receiver {
    name                    = "governance-webhook"
    service_uri             = azurerm_logic_app_trigger_http_request.governance_trigger.callback_url
    use_common_alert_schema = true
  }

  # Email notification for critical alerts
  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name          = "governance-email-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }

  tags = var.default_tags
}

# ===============================================
# Scheduled Query Rules for Governance Monitoring
# ===============================================

# Alert for resources missing required tags
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "missing_tags_alert" {
  name                = "${var.alert_rule_name_prefix}-missing-tags-${random_string.suffix.result}"
  location            = azurerm_resource_group.governance.location
  resource_group_name = azurerm_resource_group.governance.name

  description    = "Alert for resources missing required tags"
  enabled        = var.enable_governance_alerts
  severity       = 2
  evaluation_frequency = "PT15M"
  window_duration     = "PT15M"
  scopes             = [data.azurerm_subscription.current.id]

  criteria {
    query                   = <<-QUERY
      resources
      | where tags !has 'Environment' or tags !has 'Owner' or tags !has 'CostCenter'
      | summarize count() by bin(TimeGenerated, 15m)
      | where count_ > 0
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
    action_groups = [azurerm_monitor_action_group.governance_alerts.id]
  }

  tags = var.default_tags
}

# Alert for resources in non-compliant locations
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "location_compliance_alert" {
  name                = "${var.alert_rule_name_prefix}-location-compliance-${random_string.suffix.result}"
  location            = azurerm_resource_group.governance.location
  resource_group_name = azurerm_resource_group.governance.name

  description    = "Alert for resources deployed in non-compliant locations"
  enabled        = var.enable_governance_alerts
  severity       = 1
  evaluation_frequency = "PT5M"
  window_duration     = "PT5M"
  scopes             = [data.azurerm_subscription.current.id]

  criteria {
    query                   = <<-QUERY
      resources
      | where location !in ('${join("', '", var.allowed_locations)}')
      | summarize count() by bin(TimeGenerated, 5m)
      | where count_ > 0
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
    action_groups = [azurerm_monitor_action_group.governance_alerts.id]
  }

  tags = var.default_tags
}

# ===============================================
# Data Collection Rule for Governance Metrics
# ===============================================

resource "azurerm_monitor_data_collection_rule" "governance_metrics" {
  name                = "${var.dcr_name_prefix}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.governance.name
  location            = azurerm_resource_group.governance.location
  description         = "Data collection rule for governance metrics and compliance data"

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.governance.id
      name                  = "governance-workspace"
    }
  }

  # Custom data sources for governance metrics
  data_flow {
    streams      = ["Microsoft-Event"]
    destinations = ["governance-workspace"]
  }

  tags = var.default_tags
}

# ===============================================
# Azure Policy Assignment for Governance
# ===============================================

# Policy to require specific tags on resources
resource "azurerm_policy_assignment" "require_tags" {
  name                 = "${var.policy_assignment_name_prefix}-require-tags-${random_string.suffix.result}"
  scope                = data.azurerm_subscription.current.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/1e30110a-5ceb-460c-a204-c1c3969c6d62"
  description          = "Require specific tags on all resources for governance compliance"
  display_name         = "Require Environment, Owner, and CostCenter tags"

  parameters = jsonencode({
    tagNames = {
      value = var.required_tags
    }
  })

  identity {
    type = "SystemAssigned"
  }

  location = azurerm_resource_group.governance.location

  enforcement_mode = var.policy_enforcement_mode
}

# Policy to restrict allowed locations
resource "azurerm_policy_assignment" "allowed_locations" {
  name                 = "${var.policy_assignment_name_prefix}-allowed-locations-${random_string.suffix.result}"
  scope                = data.azurerm_subscription.current.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
  description          = "Restrict resource deployment to approved Azure regions"
  display_name         = "Allowed Locations for Resources"

  parameters = jsonencode({
    listOfAllowedLocations = {
      value = var.allowed_locations
    }
  })

  identity {
    type = "SystemAssigned"
  }

  location = azurerm_resource_group.governance.location

  enforcement_mode = var.policy_enforcement_mode
}

# ===============================================
# Resource Graph Query Examples
# ===============================================

# Store sample governance queries as a local file for reference
resource "local_file" "governance_queries" {
  filename = "${path.module}/governance-queries.kql"
  content  = <<-EOF
    // ===============================================
    // Azure Resource Graph Governance Queries
    // ===============================================
    // These queries provide insights into resource governance,
    // compliance, and security posture across Azure subscriptions.

    // Query 1: Resources without required tags
    resources
    | where tags !has "Environment" or tags !has "Owner" or tags !has "CostCenter"
    | project name, type, resourceGroup, subscriptionId, location, tags
    | limit 1000

    // Query 2: Non-compliant resource locations
    resources
    | where location !in ("${join("\", \"", var.allowed_locations)}")
    | project name, type, resourceGroup, location, subscriptionId
    | limit 1000

    // Query 3: Resources by compliance state
    policyresources
    | where type == "microsoft.policyinsights/policystates"
    | project resourceId, policyAssignmentName, policyDefinitionName, complianceState, timestamp
    | summarize count() by complianceState

    // Query 4: Security center recommendations
    securityresources
    | where type == "microsoft.security/assessments"
    | project resourceId, displayName, status, severity
    | summarize count() by status.code

    // Query 5: Resource count by type and location
    resources
    | summarize count() by type, location
    | order by count_ desc

    // Query 6: Recently created resources
    resources
    | where timestamp >= ago(7d)
    | project name, type, resourceGroup, location, createdTime
    | order by createdTime desc

    // Query 7: Resources with public IP addresses
    resources
    | where type contains "publicip" or properties contains "publicip"
    | project name, type, resourceGroup, location, properties

    // Query 8: Storage accounts without encryption
    resources
    | where type == "microsoft.storage/storageaccounts"
    | where properties.encryption.services.blob.enabled != true
    | project name, resourceGroup, location, subscriptionId

    // Query 9: Virtual machines without backup
    resources
    | where type == "microsoft.compute/virtualmachines"
    | where properties !has "backupPolicy"
    | project name, resourceGroup, location, subscriptionId

    // Query 10: Resource groups by resource count
    resources
    | summarize ResourceCount = count() by ResourceGroup = resourceGroup
    | order by ResourceCount desc
  EOF
}