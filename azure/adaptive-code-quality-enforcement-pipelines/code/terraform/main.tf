# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get current client configuration
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Log Analytics Workspace for Application Insights
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.application_insights_retention_days
  
  tags = merge(var.tags, {
    Name = "log-${var.project_name}-${var.environment}"
  })
}

# Application Insights for performance monitoring
resource "azurerm_application_insights" "main" {
  name                = "ai-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.application_insights_type
  retention_in_days   = var.application_insights_retention_days
  
  tags = merge(var.tags, {
    Name = "ai-${var.project_name}-${var.environment}"
  })
}

# Storage Account for Logic Apps
resource "azurerm_storage_account" "logic_apps" {
  name                     = "st${var.project_name}${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  min_tls_version          = var.min_tls_version
  
  # Security settings
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  
  tags = merge(var.tags, {
    Name = "st-${var.project_name}-${var.environment}"
  })
}

# App Service Plan for Logic Apps
resource "azurerm_service_plan" "logic_apps" {
  name                = "plan-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Windows"
  sku_name            = "WS1"
  
  tags = merge(var.tags, {
    Name = "plan-${var.project_name}-${var.environment}"
  })
}

# Logic App for intelligent feedback loops
resource "azurerm_logic_app_workflow" "quality_feedback" {
  name                = "la-${var.project_name}-feedback-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  workflow_schema   = "https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version  = "1.0.0.0"
  
  parameters = {
    qualityThreshold = var.quality_threshold
    appInsightsKey   = azurerm_application_insights.main.instrumentation_key
  }
  
  tags = merge(var.tags, {
    Name = "la-${var.project_name}-feedback-${var.environment}"
  })
}

# Logic App Workflow definition
resource "azurerm_logic_app_trigger_http_request" "quality_trigger" {
  name         = "quality-evaluation-trigger"
  logic_app_id = azurerm_logic_app_workflow.quality_feedback.id
  
  schema = jsonencode({
    properties = {
      qualityScore = {
        type = "number"
      }
      testResults = {
        type = "string"
      }
      performanceMetrics = {
        type = "object"
        properties = {
          buildTime = {
            type = "string"
          }
          testCoverage = {
            type = "number"
          }
          codeComplexity = {
            type = "number"
          }
        }
      }
      repositoryInfo = {
        type = "object"
        properties = {
          repository = {
            type = "string"
          }
          branch = {
            type = "string"
          }
          commitId = {
            type = "string"
          }
        }
      }
    }
    required = ["qualityScore", "testResults"]
    type = "object"
  })
}

# Logic App Action - Quality Score Evaluation
resource "azurerm_logic_app_action_custom" "evaluate_quality" {
  name         = "evaluate-quality-score"
  logic_app_id = azurerm_logic_app_workflow.quality_feedback.id
  
  body = jsonencode({
    type = "If"
    expression = "@greater(triggerBody().qualityScore, parameters('qualityThreshold'))"
    actions = {
      success_response = {
        type = "Response"
        inputs = {
          statusCode = 200
          headers = {
            "Content-Type" = "application/json"
          }
          body = {
            status = "success"
            message = "Quality threshold met - proceeding with deployment"
            qualityScore = "@{triggerBody().qualityScore}"
            threshold = "@{parameters('qualityThreshold')}"
            timestamp = "@{utcNow()}"
          }
        }
      }
      log_success = {
        type = "Http"
        inputs = {
          method = "POST"
          uri = "https://api.applicationinsights.io/v1/apps/@{parameters('appInsightsKey')}/events"
          headers = {
            "Content-Type" = "application/json"
          }
          body = {
            name = "QualityGateSuccess"
            properties = {
              qualityScore = "@{triggerBody().qualityScore}"
              repository = "@{triggerBody().repositoryInfo.repository}"
              branch = "@{triggerBody().repositoryInfo.branch}"
            }
          }
        }
      }
    }
    else = {
      actions = {
        failure_response = {
          type = "Response"
          inputs = {
            statusCode = 400
            headers = {
              "Content-Type" = "application/json"
            }
            body = {
              status = "failure"
              message = "Quality threshold not met - blocking deployment"
              qualityScore = "@{triggerBody().qualityScore}"
              threshold = "@{parameters('qualityThreshold')}"
              timestamp = "@{utcNow()}"
              recommendations = [
                "Review static analysis results",
                "Increase test coverage",
                "Address code complexity issues"
              ]
            }
          }
        }
        log_failure = {
          type = "Http"
          inputs = {
            method = "POST"
            uri = "https://api.applicationinsights.io/v1/apps/@{parameters('appInsightsKey')}/events"
            headers = {
              "Content-Type" = "application/json"
            }
            body = {
              name = "QualityGateFailure"
              properties = {
                qualityScore = "@{triggerBody().qualityScore}"
                repository = "@{triggerBody().repositoryInfo.repository}"
                branch = "@{triggerBody().repositoryInfo.branch}"
              }
            }
          }
        }
      }
    }
  })
  
  depends_on = [azurerm_logic_app_trigger_http_request.quality_trigger]
}

# Action Group for monitoring alerts
resource "azurerm_monitor_action_group" "quality_alerts" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "ag-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "qualityalert"
  
  email_receiver {
    name          = "quality-admin"
    email_address = var.alert_email
  }
  
  tags = merge(var.tags, {
    Name = "ag-${var.project_name}-${var.environment}"
  })
}

# Metric Alert for Application Insights
resource "azurerm_monitor_metric_alert" "app_insights_exceptions" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "alert-${var.project_name}-exceptions-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights.main.id]
  description         = "Alert when exceptions exceed threshold"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Insights/components"
    metric_name      = "exceptions/count"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 5
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.quality_alerts[0].id
  }
  
  tags = merge(var.tags, {
    Name = "alert-${var.project_name}-exceptions-${var.environment}"
  })
}

# Metric Alert for Logic App failures
resource "azurerm_monitor_metric_alert" "logic_app_failures" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "alert-${var.project_name}-logicapp-failures-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_logic_app_workflow.quality_feedback.id]
  description         = "Alert when Logic App failures exceed threshold"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Logic/workflows"
    metric_name      = "RunsFailed"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 1
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.quality_alerts[0].id
  }
  
  tags = merge(var.tags, {
    Name = "alert-${var.project_name}-logicapp-failures-${var.environment}"
  })
}

# Key Vault for storing secrets
resource "azurerm_key_vault" "main" {
  name                       = "kv-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  
  # Enable for Azure services
  enabled_for_deployment          = true
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true
  
  # Network ACLs - restrict to specific networks in production
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
  
  tags = merge(var.tags, {
    Name = "kv-${var.project_name}-${var.environment}"
  })
}

# Key Vault Access Policy for current user
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  key_permissions = [
    "Create",
    "Delete",
    "Get",
    "List",
    "Update",
    "Recover",
    "Purge"
  ]
  
  secret_permissions = [
    "Delete",
    "Get",
    "List",
    "Set",
    "Recover",
    "Purge"
  ]
  
  certificate_permissions = [
    "Create",
    "Delete",
    "Get",
    "List",
    "Update",
    "Recover",
    "Purge"
  ]
}

# Store Application Insights Instrumentation Key in Key Vault
resource "azurerm_key_vault_secret" "app_insights_key" {
  name         = "app-insights-instrumentation-key"
  value        = azurerm_application_insights.main.instrumentation_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  tags = merge(var.tags, {
    Name = "app-insights-key"
  })
}

# Store Application Insights Connection String in Key Vault
resource "azurerm_key_vault_secret" "app_insights_connection_string" {
  name         = "app-insights-connection-string"
  value        = azurerm_application_insights.main.connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  tags = merge(var.tags, {
    Name = "app-insights-connection-string"
  })
}

# Store Logic App Trigger URL in Key Vault
resource "azurerm_key_vault_secret" "logic_app_trigger_url" {
  name         = "logic-app-trigger-url"
  value        = azurerm_logic_app_trigger_http_request.quality_trigger.callback_url
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  tags = merge(var.tags, {
    Name = "logic-app-trigger-url"
  })
}

# Dashboard for monitoring quality metrics
resource "azurerm_dashboard" "quality_dashboard" {
  name                = "dashboard-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  dashboard_properties = jsonencode({
    lenses = {
      "0" = {
        order = 0
        parts = {
          "0" = {
            position = {
              x = 0
              y = 0
              rowSpan = 4
              colSpan = 6
            }
            metadata = {
              inputs = [
                {
                  name = "resourceId"
                  value = azurerm_application_insights.main.id
                }
              ]
              type = "Extension/Microsoft_Azure_Monitoring/PartType/AppInsightsMetricChartPart"
            }
          }
          "1" = {
            position = {
              x = 6
              y = 0
              rowSpan = 4
              colSpan = 6
            }
            metadata = {
              inputs = [
                {
                  name = "resourceId"
                  value = azurerm_logic_app_workflow.quality_feedback.id
                }
              ]
              type = "Extension/Microsoft_Azure_Monitoring/PartType/LogicAppMetricsPart"
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
        filterLocale = {
          value = "en-us"
        }
        filters = {
          value = {
            MsPortalFx_TimeRange = {
              model = {
                format = "utc"
                granularity = "auto"
                relative = "24h"
              }
              displayCache = {
                name = "UTC Time"
                value = "Past 24 hours"
              }
              filteredPartIds = ["0", "1"]
            }
          }
        }
      }
    }
  })
  
  tags = merge(var.tags, {
    Name = "dashboard-${var.project_name}-${var.environment}"
  })
}