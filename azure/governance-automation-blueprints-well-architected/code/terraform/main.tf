# Main Terraform configuration for Azure Governance Automation with Blueprints

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data sources for current Azure context
data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

data "azuread_user" "current" {}

# Resource Group for governance resources
resource "azurerm_resource_group" "governance" {
  name     = "${var.resource_group_name}-${random_string.suffix.result}"
  location = var.location
  
  tags = merge(var.governance_tags, {
    Environment = var.environment
    CostCenter  = var.cost_center
    Owner       = var.owner
  })
}

# Log Analytics Workspace for governance monitoring
resource "azurerm_log_analytics_workspace" "governance" {
  name                = "${var.log_analytics_workspace_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.governance.location
  resource_group_name = azurerm_resource_group.governance.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(var.governance_tags, {
    Environment = var.environment
    CostCenter  = var.cost_center
    Owner       = var.owner
  })
}

# Custom Policy Definition for Required Tags (Cost Optimization pillar)
resource "azurerm_policy_definition" "require_tags" {
  name                = "require-resource-tags"
  policy_type         = "Custom"
  mode                = "All"
  display_name        = "Require specific tags on resources"
  description         = "Enforces required tags for cost tracking and governance"
  management_group_id = data.azurerm_client_config.current.tenant_id
  
  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.Resources/subscriptions/resourceGroups"
        },
        {
          anyOf = [
            for tag in var.required_tags : {
              field  = "tags['${tag}']"
              exists = "false"
            }
          ]
        }
      ]
    }
    then = {
      effect = "deny"
    }
  })
  
  parameters = jsonencode({
    requiredTags = {
      type = "Array"
      metadata = {
        displayName = "Required Tags"
        description = "List of required tags for resources"
      }
      defaultValue = var.required_tags
    }
  })
}

# Policy Initiative (Policy Set) for Enterprise Security and Governance
resource "azurerm_policy_set_definition" "enterprise_security" {
  name                = "enterprise-security-initiative"
  policy_type         = "Custom"
  display_name        = "Enterprise Security and Governance Initiative"
  description         = "Comprehensive security policies aligned with Well-Architected Framework"
  management_group_id = data.azurerm_client_config.current.tenant_id
  
  policy_definition_reference {
    policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/404c3081-a854-4457-ae30-26a93ef643f9"
    reference_id         = "secure-transfer-storage"
  }
  
  policy_definition_reference {
    policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/1e30110a-5ceb-460c-a204-c1c3969c6d62"
    reference_id         = "storage-account-public-access"
  }
  
  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.require_tags.id
    reference_id         = "require-tags"
  }
}

# Blueprint Definition
resource "azurerm_blueprint" "enterprise_governance" {
  name                = var.blueprint_name
  display_name        = "Enterprise Governance Blueprint"
  description         = "Comprehensive governance blueprint implementing Well-Architected Framework"
  target_scope        = "subscription"
  subscription_id     = data.azurerm_subscription.current.subscription_id
}

# ARM Template artifact for compliant storage account
resource "azurerm_blueprint_artifact_template" "storage_template" {
  name                = "compliant-storage-template"
  display_name        = "Compliant Storage Account Template"
  description         = "ARM template for deploying compliant storage account"
  blueprint_id        = azurerm_blueprint.enterprise_governance.id
  resource_group_name = "rg-blueprint-resources"
  
  template = jsonencode({
    "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    parameters = {
      storageAccountName = {
        type = "string"
        metadata = {
          description = "Name of the storage account"
        }
      }
      location = {
        type = "string"
        defaultValue = "[resourceGroup().location]"
        metadata = {
          description = "Location for the storage account"
        }
      }
    }
    variables = {
      storageAccountName = "[parameters('storageAccountName')]"
    }
    resources = [
      {
        type       = "Microsoft.Storage/storageAccounts"
        apiVersion = "2023-01-01"
        name       = "[variables('storageAccountName')]"
        location   = "[parameters('location')]"
        tags = {
          Environment = var.environment
          CostCenter  = var.cost_center
          Owner       = var.owner
          Compliance  = "Required"
        }
        sku = {
          name = "Standard_LRS"
        }
        kind = "StorageV2"
        properties = {
          supportsHttpsTrafficOnly = var.enable_https_traffic_only
          encryption = {
            services = {
              file = {
                enabled = true
              }
              blob = {
                enabled = true
              }
            }
            keySource = "Microsoft.Storage"
          }
          accessTier         = var.storage_account_tier
          minimumTlsVersion  = var.minimum_tls_version
        }
      }
    ]
    outputs = {
      storageAccountId = {
        type  = "string"
        value = "[resourceId('Microsoft.Storage/storageAccounts', variables('storageAccountName'))]"
      }
    }
  })
  
  parameters = jsonencode({
    storageAccountName = {
      value = "${var.storage_account_name_prefix}${random_string.suffix.result}"
    }
  })
}

# Policy Assignment artifact for blueprint
resource "azurerm_blueprint_artifact_policy" "security_policy" {
  name                 = "security-policy-assignment"
  display_name         = "Security Policy Assignment"
  description          = "Assigns security policies for governance"
  blueprint_id         = azurerm_blueprint.enterprise_governance.id
  policy_definition_id = azurerm_policy_set_definition.enterprise_security.id
  resource_group_name  = "rg-blueprint-resources"
}

# Role Assignment artifact for governance team
resource "azurerm_blueprint_artifact_role_assignment" "governance_role" {
  name                 = "governance-role-assignment"
  display_name         = "Governance Team Role Assignment"
  description          = "Assigns Policy Contributor role to governance team"
  blueprint_id         = azurerm_blueprint.enterprise_governance.id
  role_definition_id   = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
  principal_ids        = [data.azuread_user.current.object_id]
  resource_group_name  = "rg-blueprint-resources"
}

# Publish Blueprint Version
resource "azurerm_blueprint_published_version" "v1" {
  blueprint_id   = azurerm_blueprint.enterprise_governance.id
  version        = var.blueprint_version
  change_notes   = "Initial enterprise governance blueprint with Well-Architected Framework alignment"
  depends_on = [
    azurerm_blueprint_artifact_template.storage_template,
    azurerm_blueprint_artifact_policy.security_policy,
    azurerm_blueprint_artifact_role_assignment.governance_role
  ]
}

# Blueprint Assignment
resource "azurerm_blueprint_assignment" "enterprise_governance" {
  name                 = "enterprise-governance-assignment"
  display_name         = "Enterprise Governance Assignment"
  description          = "Applies enterprise governance controls to subscription"
  blueprint_id         = azurerm_blueprint_published_version.v1.id
  target_subscription_id = data.azurerm_subscription.current.subscription_id
  location             = var.location
  
  identity {
    type = "SystemAssigned"
  }
  
  depends_on = [azurerm_blueprint_published_version.v1]
}

# Action Group for governance alerts
resource "azurerm_monitor_action_group" "governance_alerts" {
  count               = var.enable_advisor_alerts ? 1 : 0
  name                = "governance-alerts"
  resource_group_name = azurerm_resource_group.governance.name
  short_name          = "govAlert"
  
  email_receiver {
    name                    = "governance-team"
    email_address           = var.governance_email
    use_common_alert_schema = true
  }
  
  tags = merge(var.governance_tags, {
    Environment = var.environment
    CostCenter  = var.cost_center
    Owner       = var.owner
  })
}

# Activity Log Alert for high-impact security recommendations
resource "azurerm_monitor_activity_log_alert" "advisor_security_alert" {
  count               = var.enable_advisor_alerts ? 1 : 0
  name                = "advisor-security-alert"
  resource_group_name = azurerm_resource_group.governance.name
  scopes              = [data.azurerm_subscription.current.id]
  description         = "Alert for high-impact security recommendations"
  
  criteria {
    category = "Recommendation"
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.governance_alerts[0].id
  }
  
  tags = merge(var.governance_tags, {
    Environment = var.environment
    CostCenter  = var.cost_center
    Owner       = var.owner
  })
}

# Dashboard for governance monitoring
resource "azurerm_portal_dashboard" "governance_dashboard" {
  count                = var.enable_governance_dashboard ? 1 : 0
  name                 = "enterprise-governance-dashboard"
  resource_group_name  = azurerm_resource_group.governance.name
  location             = azurerm_resource_group.governance.location
  display_name         = "Enterprise Governance Dashboard"
  
  dashboard_properties = jsonencode({
    lenses = {
      "0" = {
        order = 0
        parts = {
          "0" = {
            position = {
              x        = 0
              y        = 0
              colSpan  = 6
              rowSpan  = 4
            }
            metadata = {
              inputs = []
              type   = "Extension/HubsExtension/PartType/MonitorChartPart"
              settings = {
                content = {
                  options = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = {
                            id = data.azurerm_subscription.current.id
                          }
                          name            = "PolicyViolations"
                          aggregationType = "Count"
                          namespace       = "Microsoft.PolicyInsights/policyStates"
                        }
                      ]
                      title = "Policy Compliance Overview"
                      titleKind = 1
                      visualization = {
                        chartType = 3
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    metadata = {
      model = {
        timeRange = {
          value = {
            relative = {
              duration = 24
              timeUnit = 1
            }
          }
          type = "MsPortalFx.Composition.Configuration.ValueTypes.TimeRange"
        }
      }
    }
  })
  
  tags = merge(var.governance_tags, {
    Environment = var.environment
    CostCenter  = var.cost_center
    Owner       = var.owner
    "hidden-title" = "Enterprise Governance Dashboard"
  })
}

# Application Insights for governance monitoring
resource "azurerm_application_insights" "governance" {
  name                = "appi-governance-${random_string.suffix.result}"
  location            = azurerm_resource_group.governance.location
  resource_group_name = azurerm_resource_group.governance.name
  workspace_id        = azurerm_log_analytics_workspace.governance.id
  application_type    = "web"
  
  tags = merge(var.governance_tags, {
    Environment = var.environment
    CostCenter  = var.cost_center
    Owner       = var.owner
  })
}

# Diagnostic Settings for subscription-level monitoring
resource "azurerm_monitor_diagnostic_setting" "subscription" {
  name                           = "subscription-diagnostics"
  target_resource_id             = data.azurerm_subscription.current.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.governance.id
  
  enabled_log {
    category = "Policy"
  }
  
  enabled_log {
    category = "Administrative"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}