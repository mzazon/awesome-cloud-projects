# Main Terraform Configuration for Azure Policy and Resource Graph Implementation
# This file creates a comprehensive governance solution with automated resource tagging
# and compliance enforcement using Azure Policy and Resource Graph

# Data sources for existing Azure resources
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create resource group for governance resources
resource "azurerm_resource_group" "governance" {
  name     = var.resource_group_name
  location = var.location

  tags = merge(var.common_tags, {
    CostCenter = var.cost_center_tag
  })
}

# Create Log Analytics workspace for compliance monitoring
resource "azurerm_log_analytics_workspace" "governance" {
  name                = var.log_analytics_workspace_name != null ? var.log_analytics_workspace_name : "law-governance-${random_string.suffix.result}"
  location            = azurerm_resource_group.governance.location
  resource_group_name = azurerm_resource_group.governance.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_retention_days

  tags = var.common_tags
}

# Custom Policy Definition: Require Department Tag
resource "azurerm_policy_definition" "require_department_tag" {
  name                = var.custom_policy_names.require_department_tag
  policy_type         = "Custom"
  mode                = var.policy_definition_mode
  display_name        = "Require Department Tag on Resources"
  description         = "Ensures all resources have a Department tag with a valid value"
  management_group_id = var.management_group_id

  policy_rule = jsonencode({
    if = {
      anyOf = [
        {
          field  = "tags['Department']"
          exists = "false"
        },
        {
          field = "tags['Department']"
          equals = ""
        }
      ]
    }
    then = {
      effect = "deny"
    }
  })

  parameters = jsonencode({
    tagName = {
      type = "String"
      metadata = {
        displayName = "Tag Name"
        description = "Name of the tag, such as Department"
      }
      defaultValue = "Department"
    }
    tagValue = {
      type = "String"
      metadata = {
        displayName = "Tag Value"
        description = "Value of the tag, such as IT or Finance"
      }
      defaultValue = ""
    }
  })
}

# Custom Policy Definition: Require Environment Tag
resource "azurerm_policy_definition" "require_environment_tag" {
  name                = var.custom_policy_names.require_environment_tag
  policy_type         = "Custom"
  mode                = var.policy_definition_mode
  display_name        = "Require Environment Tag on Resources"
  description         = "Ensures all resources have an Environment tag with a valid value"
  management_group_id = var.management_group_id

  policy_rule = jsonencode({
    if = {
      anyOf = [
        {
          field  = "tags['Environment']"
          exists = "false"
        },
        {
          field = "tags['Environment']"
          equals = ""
        }
      ]
    }
    then = {
      effect = "deny"
    }
  })

  parameters = jsonencode({
    tagName = {
      type = "String"
      metadata = {
        displayName = "Tag Name"
        description = "Name of the tag, such as Environment"
      }
      defaultValue = "Environment"
    }
    allowedValues = {
      type = "Array"
      metadata = {
        displayName = "Allowed Values"
        description = "The list of allowed values for the Environment tag"
      }
      defaultValue = ["Development", "Testing", "Staging", "Production"]
    }
  })
}

# Custom Policy Definition: Inherit CostCenter Tag from Resource Group
resource "azurerm_policy_definition" "inherit_costcenter_tag" {
  name                = var.custom_policy_names.inherit_costcenter_tag
  policy_type         = "Custom"
  mode                = var.policy_definition_mode
  display_name        = "Inherit CostCenter Tag from Resource Group"
  description         = "Automatically applies CostCenter tag from parent resource group to resources"
  management_group_id = var.management_group_id

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "tags['CostCenter']"
          exists = "false"
        },
        {
          value    = "[resourceGroup().tags['CostCenter']]"
          notEquals = ""
        }
      ]
    }
    then = {
      effect = "modify"
      details = {
        roleDefinitionIds = [
          "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
        ]
        operations = [
          {
            operation = "add"
            field     = "tags['CostCenter']"
            value     = "[resourceGroup().tags['CostCenter']]"
          }
        ]
      }
    }
  })

  parameters = jsonencode({
    tagName = {
      type = "String"
      metadata = {
        displayName = "Tag Name"
        description = "Name of the tag to inherit, such as CostCenter"
      }
      defaultValue = "CostCenter"
    }
  })
}

# Create Policy Initiative (Policy Set Definition)
resource "azurerm_policy_set_definition" "mandatory_tagging" {
  name                = var.custom_policy_names.policy_initiative
  policy_type         = "Custom"
  display_name        = "Mandatory Resource Tagging Initiative"
  description         = "Comprehensive tagging policy initiative for governance and compliance"
  management_group_id = var.management_group_id

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.require_department_tag.id
    reference_id         = "require-department-tag"
    parameter_values = jsonencode({
      tagName = {
        value = "Department"
      }
    })
  }

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.require_environment_tag.id
    reference_id         = "require-environment-tag"
    parameter_values = jsonencode({
      tagName = {
        value = "Environment"
      }
      allowedValues = {
        value = ["Development", "Testing", "Staging", "Production", "Demo"]
      }
    })
  }

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.inherit_costcenter_tag.id
    reference_id         = "inherit-costcenter-tag"
    parameter_values = jsonencode({
      tagName = {
        value = "CostCenter"
      }
    })
  }

  parameters = jsonencode({
    excludedResourceTypes = {
      type = "Array"
      metadata = {
        displayName = "Excluded Resource Types"
        description = "Resource types to exclude from tagging requirements"
      }
      defaultValue = var.excluded_resource_types
    }
  })
}

# Get the appropriate scope for policy assignment
locals {
  assignment_scope = var.policy_assignment_scope == "subscription" ? "/subscriptions/${data.azurerm_subscription.current.subscription_id}" : var.policy_assignment_scope == "resource_group" ? azurerm_resource_group.governance.id : var.policy_assignment_scope == "management_group" ? "/providers/Microsoft.Management/managementGroups/${var.management_group_id}" : "/subscriptions/${data.azurerm_subscription.current.subscription_id}"
}

# Create Policy Assignment at the specified scope
resource "azurerm_policy_assignment" "mandatory_tagging" {
  name                 = "enforce-mandatory-tags-${random_string.suffix.result}"
  scope                = local.assignment_scope
  policy_definition_id = azurerm_policy_set_definition.mandatory_tagging.id
  description          = "Subscription-wide enforcement of mandatory tagging requirements"
  display_name         = "Enforce Mandatory Tags - ${title(var.policy_assignment_scope)} Level"
  enforce              = var.policy_enforcement_mode == "Default"
  location             = var.location

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    excludedResourceTypes = {
      value = var.excluded_resource_types
    }
  })
}

# Create Role Assignment for Policy Assignment Identity
resource "azurerm_role_assignment" "policy_assignment_contributor" {
  scope                = local.assignment_scope
  role_definition_name = "Contributor"
  principal_id         = azurerm_policy_assignment.mandatory_tagging.identity[0].principal_id
}

# Create Policy Remediation Task for existing non-compliant resources
resource "azurerm_policy_remediation" "inherit_costcenter_remediation" {
  count                = var.enable_remediation_tasks ? 1 : 0
  name                 = "remediate-missing-tags-${random_string.suffix.result}"
  scope                = local.assignment_scope
  policy_assignment_id = azurerm_policy_assignment.mandatory_tagging.id
  policy_definition_reference_id = "inherit-costcenter-tag"
  resource_discovery_mode = var.remediation_mode

  depends_on = [
    azurerm_role_assignment.policy_assignment_contributor
  ]
}

# Create Application Insights for additional monitoring
resource "azurerm_application_insights" "governance" {
  name                = "ai-governance-${random_string.suffix.result}"
  location            = azurerm_resource_group.governance.location
  resource_group_name = azurerm_resource_group.governance.name
  workspace_id        = azurerm_log_analytics_workspace.governance.id
  application_type    = "other"

  tags = var.common_tags
}

# Create Action Group for policy violation alerts
resource "azurerm_monitor_action_group" "governance_alerts" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "ag-governance-alerts-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.governance.name
  short_name          = "govAlerts"

  # Email notification (configure with actual email addresses)
  email_receiver {
    name          = "governance-team"
    email_address = "governance@example.com"
  }

  # Webhook notification for integration with external systems
  webhook_receiver {
    name        = "governance-webhook"
    service_uri = "https://example.com/webhook"
  }

  tags = var.common_tags
}

# Create Diagnostic Settings for Policy Evaluation Logs
resource "azurerm_monitor_diagnostic_setting" "policy_logs" {
  count              = var.enable_diagnostic_settings ? 1 : 0
  name               = "policy-compliance-logs"
  target_resource_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.governance.id

  enabled_log {
    category = "Policy"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create Scheduled Query Rules for Policy Violation Alerts
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "policy_violations" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "policy-violations-alert-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.governance.name
  location            = azurerm_resource_group.governance.location
  
  evaluation_frequency = "PT${var.alert_frequency_minutes}M"
  window_duration      = "PT${var.alert_window_size_minutes}M"
  scopes               = [azurerm_log_analytics_workspace.governance.id]
  severity             = var.alert_severity
  
  criteria {
    query = <<-QUERY
      PolicyInsights
      | where ComplianceState == "NonCompliant"
      | where PolicyDefinitionName contains "tag"
      | summarize count() by bin(TimeGenerated, 5m)
      | where count_ > 5
    QUERY
    
    time_aggregation_method = "Count"
    threshold               = 5
    operator                = "GreaterThan"
    
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }
  
  auto_mitigation_enabled = true
  description             = "Alert when tag policy violations exceed threshold"
  display_name            = "Tag Policy Violations Alert"
  enabled                 = true
  
  action {
    action_groups = [azurerm_monitor_action_group.governance_alerts[0].id]
  }

  tags = var.common_tags
}

# Create Azure Automation Account for remediation workflows
resource "azurerm_automation_account" "governance" {
  count               = var.enable_automation_account ? 1 : 0
  name                = "aa-governance-${random_string.suffix.result}"
  location            = azurerm_resource_group.governance.location
  resource_group_name = azurerm_resource_group.governance.name
  sku_name            = var.automation_account_sku

  identity {
    type = "SystemAssigned"
  }

  tags = var.common_tags
}

# Create Role Assignment for Automation Account
resource "azurerm_role_assignment" "automation_contributor" {
  count                = var.enable_automation_account ? 1 : 0
  scope                = local.assignment_scope
  role_definition_name = "Contributor"
  principal_id         = azurerm_automation_account.governance[0].identity[0].principal_id
}

# Create PowerShell Runbook for Tag Remediation
resource "azurerm_automation_runbook" "tag_remediation" {
  count                   = var.enable_automation_account ? 1 : 0
  name                    = "Remediate-Missing-Tags"
  location                = azurerm_resource_group.governance.location
  resource_group_name     = azurerm_resource_group.governance.name
  automation_account_name = azurerm_automation_account.governance[0].name
  log_verbose             = true
  log_progress            = true
  description             = "Automatically remediate missing tags on resources"
  runbook_type            = "PowerShell"

  content = <<-CONTENT
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$TagName,
        [string]$TagValue
    )

    # Connect to Azure using managed identity
    try {
        Connect-AzAccount -Identity
        Set-AzContext -SubscriptionId $SubscriptionId
        Write-Output "Successfully connected to Azure subscription: $SubscriptionId"
    }
    catch {
        Write-Error "Failed to connect to Azure: $($_.Exception.Message)"
        exit 1
    }

    # Get resources missing the required tag
    try {
        $resources = Get-AzResource -ResourceGroupName $ResourceGroupName | Where-Object {
            $_.Tags.$TagName -eq $null -or $_.Tags.$TagName -eq ""
        }
        
        Write-Output "Found $($resources.Count) resources missing tag: $TagName"
    }
    catch {
        Write-Error "Failed to get resources: $($_.Exception.Message)"
        exit 1
    }

    # Apply missing tags to resources
    $successCount = 0
    $errorCount = 0

    foreach ($resource in $resources) {
        try {
            $tags = $resource.Tags
            if ($tags -eq $null) { $tags = @{} }
            $tags[$TagName] = $TagValue
            
            Set-AzResource -ResourceId $resource.ResourceId -Tag $tags -Force
            Write-Output "Applied tag $TagName=$TagValue to resource: $($resource.Name)"
            $successCount++
        }
        catch {
            Write-Error "Failed to apply tag to resource $($resource.Name): $($_.Exception.Message)"
            $errorCount++
        }
    }

    Write-Output "Remediation completed. Success: $successCount, Errors: $errorCount"
  CONTENT

  tags = var.common_tags
}

# Create Azure Dashboard for Compliance Monitoring
resource "azurerm_dashboard" "compliance" {
  count                = var.enable_dashboard ? 1 : 0
  name                 = var.dashboard_name
  resource_group_name  = azurerm_resource_group.governance.name
  location             = azurerm_resource_group.governance.location
  dashboard_properties = jsonencode({
    lenses = {
      "0" = {
        order = 0
        parts = {
          "0" = {
            position = {
              x        = 0
              y        = 0
              rowSpan  = 4
              colSpan  = 6
            }
            metadata = {
              inputs = [
                {
                  name  = "resourceType"
                  value = "microsoft.operationalinsights/workspaces"
                },
                {
                  name = "query"
                  value = "PolicyInsights | where ComplianceState == 'NonCompliant' | summarize count() by ResourceType | order by count_ desc"
                }
              ]
              type = "Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/LogsDashboardPart"
            }
          }
          "1" = {
            position = {
              x        = 6
              y        = 0
              rowSpan  = 4
              colSpan  = 6
            }
            metadata = {
              inputs = [
                {
                  name  = "resourceType"
                  value = "microsoft.operationalinsights/workspaces"
                },
                {
                  name = "query"
                  value = "PolicyInsights | where ComplianceState == 'NonCompliant' | summarize count() by PolicyDefinitionName | order by count_ desc"
                }
              ]
              type = "Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/LogsDashboardPart"
            }
          }
        }
      }
    }
  })

  tags = var.common_tags
}

# Add delay to ensure policy propagation before remediation
resource "time_sleep" "policy_propagation" {
  depends_on = [azurerm_policy_assignment.mandatory_tagging]
  create_duration = "60s"
}

# Create Resource Graph shared queries for compliance monitoring
resource "azurerm_resource_graph_query" "tag_compliance" {
  count       = var.enable_resource_graph_queries ? 1 : 0
  name        = "tag-compliance-monitoring"
  location    = azurerm_resource_group.governance.location
  description = "Comprehensive tag compliance monitoring query"
  query       = <<-QUERY
    Resources
    | where type !in ('microsoft.resources/subscriptions', 'microsoft.resources/resourcegroups')
    | extend compliance = case(
        tags.Department != '' and isnotempty(tags.Department) and 
        tags.Environment != '' and isnotempty(tags.Environment) and
        tags.CostCenter != '' and isnotempty(tags.CostCenter), 'Fully Compliant',
        tags.Department != '' and isnotempty(tags.Department) or 
        tags.Environment != '' and isnotempty(tags.Environment) or
        tags.CostCenter != '' and isnotempty(tags.CostCenter), 'Partially Compliant',
        'Non-Compliant'
    )
    | summarize count() by compliance, type
    | order by compliance desc
  QUERY

  tags = var.common_tags
}

resource "azurerm_resource_graph_query" "missing_tags" {
  count       = var.enable_resource_graph_queries ? 1 : 0
  name        = "resources-missing-tags"
  location    = azurerm_resource_group.governance.location
  description = "Query to identify resources missing required tags"
  query       = <<-QUERY
    Resources
    | where type !in ('microsoft.resources/subscriptions', 'microsoft.resources/resourcegroups')
    | where tags.Department == '' or isempty(tags.Department) or 
            tags.Environment == '' or isempty(tags.Environment) or
            tags.CostCenter == '' or isempty(tags.CostCenter)
    | project name, type, resourceGroup, location, tags
    | limit 100
  QUERY

  tags = var.common_tags
}

# Create Storage Account for automation and logging
resource "azurerm_storage_account" "governance" {
  name                     = "stgovern${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.governance.name
  location                 = azurerm_resource_group.governance.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # Apply required tags to demonstrate compliance
  tags = merge(var.common_tags, {
    Department  = "IT"
    Environment = var.environment
    CostCenter  = var.cost_center_tag
  })
}

# Create Storage Container for runbook logs
resource "azurerm_storage_container" "runbook_logs" {
  name                  = "runbook-logs"
  storage_account_name  = azurerm_storage_account.governance.name
  container_access_type = "private"
}