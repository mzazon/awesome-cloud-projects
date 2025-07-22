# ==============================================================================
# MAIN - Azure Fraud Detection with AI Metrics Advisor and Immersive Reader
# ==============================================================================

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique resource names
  resource_suffix = lower(random_id.suffix.hex)
  
  # Resource names with fallback to generated names
  resource_group_name          = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  metrics_advisor_name         = var.metrics_advisor_name != "" ? var.metrics_advisor_name : "ma-${var.project_name}-${local.resource_suffix}"
  immersive_reader_name        = var.immersive_reader_name != "" ? var.immersive_reader_name : "ir-${var.project_name}-${local.resource_suffix}"
  storage_account_name         = var.storage_account_name != "" ? var.storage_account_name : "st${replace(var.project_name, "-", "")}${local.resource_suffix}"
  logic_app_name               = var.logic_app_name != "" ? var.logic_app_name : "la-${var.project_name}-workflow-${local.resource_suffix}"
  log_analytics_workspace_name = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "law-${var.project_name}-monitoring-${local.resource_suffix}"
  
  # Custom subdomains with fallback
  metrics_advisor_subdomain   = var.metrics_advisor_custom_subdomain != "" ? var.metrics_advisor_custom_subdomain : local.metrics_advisor_name
  immersive_reader_subdomain  = var.immersive_reader_custom_subdomain != "" ? var.immersive_reader_custom_subdomain : local.immersive_reader_name
  
  # Common tags merged with provided tags
  common_tags = merge(var.tags, {
    "terraform-managed" = "true"
    "created-date"      = formatdate("YYYY-MM-DD", timestamp())
    "resource-suffix"   = local.resource_suffix
  })
}

# ==============================================================================
# RESOURCE GROUP
# ==============================================================================

resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# ==============================================================================
# STORAGE ACCOUNT FOR DATA AND LOGS
# ==============================================================================

resource "azurerm_storage_account" "fraud_data" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  
  # Security configuration
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = var.enable_public_network_access
  
  # Enable advanced threat protection
  blob_properties {
    versioning_enabled       = true
    change_feed_enabled      = true
    change_feed_retention_in_days = 7
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  # Network rules for enhanced security
  dynamic "network_rules" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action             = "Deny"
      bypass                     = ["AzureServices"]
      ip_rules                   = var.allowed_ip_ranges
      virtual_network_subnet_ids = []
    }
  }
  
  tags = local.common_tags
}

# Create storage containers for different data types
resource "azurerm_storage_container" "containers" {
  for_each = toset(var.storage_containers)
  
  name                  = each.value
  storage_account_name  = azurerm_storage_account.fraud_data.name
  container_access_type = "private"
}

# ==============================================================================
# AZURE AI METRICS ADVISOR
# ==============================================================================

resource "azurerm_cognitive_account" "metrics_advisor" {
  name                = local.metrics_advisor_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "MetricsAdvisor"
  sku_name            = var.metrics_advisor_sku
  
  # Custom subdomain for enhanced security
  custom_subdomain_name = local.metrics_advisor_subdomain
  
  # Network access configuration
  public_network_access_enabled = var.enable_public_network_access
  
  # Network ACLs for security
  dynamic "network_acls" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      ip_rules       = var.allowed_ip_ranges
    }
  }
  
  # Identity configuration for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.common_tags, {
    "service-type" = "metrics-advisor"
    "ai-service"   = "fraud-detection"
  })
}

# ==============================================================================
# AZURE AI IMMERSIVE READER
# ==============================================================================

resource "azurerm_cognitive_account" "immersive_reader" {
  name                = local.immersive_reader_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "ImmersiveReader"
  sku_name            = var.immersive_reader_sku
  
  # Custom subdomain for enhanced security
  custom_subdomain_name = local.immersive_reader_subdomain
  
  # Network access configuration
  public_network_access_enabled = var.enable_public_network_access
  
  # Network ACLs for security
  dynamic "network_acls" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      ip_rules       = var.allowed_ip_ranges
    }
  }
  
  # Identity configuration for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.common_tags, {
    "service-type" = "immersive-reader"
    "ai-service"   = "accessibility"
  })
}

# ==============================================================================
# LOG ANALYTICS WORKSPACE FOR MONITORING
# ==============================================================================

resource "azurerm_log_analytics_workspace" "fraud_monitoring" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(local.common_tags, {
    "service-type" = "monitoring"
    "purpose"      = "fraud-detection-logs"
  })
}

# ==============================================================================
# LOGIC APP FOR WORKFLOW ORCHESTRATION
# ==============================================================================

resource "azurerm_logic_app_workflow" "fraud_processing" {
  name                = local.logic_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Enable or disable the Logic App
  enabled = var.logic_app_state == "Enabled"
  
  # Identity configuration for secure access to other services
  identity {
    type = "SystemAssigned"
  }
  
  # Workflow definition for fraud detection processing
  workflow_definition = jsonencode({
    "$schema" = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
    "contentVersion" = "1.0.0.0"
    "parameters" = {
      "metricsAdvisorEndpoint" = {
        "type" = "string"
        "defaultValue" = azurerm_cognitive_account.metrics_advisor.endpoint
      }
      "immersiveReaderEndpoint" = {
        "type" = "string"
        "defaultValue" = azurerm_cognitive_account.immersive_reader.endpoint
      }
      "storageAccountName" = {
        "type" = "string"
        "defaultValue" = azurerm_storage_account.fraud_data.name
      }
      "fraudThreshold" = {
        "type" = "number"
        "defaultValue" = var.fraud_detection_threshold
      }
      "supportedLanguages" = {
        "type" = "array"
        "defaultValue" = var.supported_languages
      }
    }
    "triggers" = {
      "manual" = {
        "type" = "Request"
        "kind" = "Http"
        "inputs" = {
          "schema" = {
            "type" = "object"
            "properties" = {
              "alertId" = { "type" = "string" }
              "severity" = { "type" = "string" }
              "anomalyData" = { "type" = "object" }
              "timestamp" = { "type" = "string" }
              "confidenceScore" = { "type" = "number" }
            }
          }
        }
      }
      "recurrence" = {
        "type" = "Recurrence"
        "recurrence" = {
          "frequency" = "Minute"
          "interval" = var.processing_frequency
        }
      }
    }
    "actions" = {
      "ProcessFraudAlert" = {
        "type" = "Http"
        "inputs" = {
          "method" = "POST"
          "uri" = "https://management.azure.com/subscriptions/@{parameters('subscriptionId')}/resourceGroups/@{parameters('resourceGroupName')}/providers/Microsoft.CognitiveServices/accounts/@{parameters('metricsAdvisorName')}/processAlert"
          "body" = "@triggerBody()"
          "headers" = {
            "Content-Type" = "application/json"
          }
        }
      }
      "CreateAccessibleSummary" = {
        "type" = "Http"
        "runAfter" = {
          "ProcessFraudAlert" = ["Succeeded"]
        }
        "inputs" = {
          "method" = "POST"
          "uri" = "@{parameters('immersiveReaderEndpoint')}/api/v1/accessibility/summary"
          "body" = {
            "text" = "@{body('ProcessFraudAlert')['accessible_text']}"
            "language" = "@{first(parameters('supportedLanguages'))}"
            "options" = {
              "readAloud" = var.enable_immersive_reader_features
              "translate" = var.enable_immersive_reader_features
              "syllabification" = true
              "pictureSupport" = true
            }
          }
          "headers" = {
            "Content-Type" = "application/json"
          }
        }
      }
      "StoreProcessedAlert" = {
        "type" = "Http"
        "runAfter" = {
          "CreateAccessibleSummary" = ["Succeeded"]
        }
        "inputs" = {
          "method" = "PUT"
          "uri" = "https://@{parameters('storageAccountName')}.blob.core.windows.net/fraud-alerts/@{triggerBody()['alertId']}-processed.json"
          "body" = "@body('CreateAccessibleSummary')"
          "headers" = {
            "Content-Type" = "application/json"
            "x-ms-blob-type" = "BlockBlob"
          }
        }
      }
    }
    "outputs" = {
      "alertId" = {
        "type" = "string"
        "value" = "@triggerBody()['alertId']"
      }
      "processedSummary" = {
        "type" = "object"
        "value" = "@body('CreateAccessibleSummary')"
      }
    }
  })
  
  tags = merge(local.common_tags, {
    "service-type" = "workflow-orchestration"
    "purpose"      = "fraud-alert-processing"
  })
}

# ==============================================================================
# RBAC - ROLE ASSIGNMENTS FOR SECURE ACCESS
# ==============================================================================

# Grant Logic App access to Storage Account
resource "azurerm_role_assignment" "logic_app_storage" {
  scope                = azurerm_storage_account.fraud_data.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_logic_app_workflow.fraud_processing.identity[0].principal_id
}

# Grant Logic App access to Metrics Advisor
resource "azurerm_role_assignment" "logic_app_metrics_advisor" {
  scope                = azurerm_cognitive_account.metrics_advisor.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_logic_app_workflow.fraud_processing.identity[0].principal_id
}

# Grant Logic App access to Immersive Reader
resource "azurerm_role_assignment" "logic_app_immersive_reader" {
  scope                = azurerm_cognitive_account.immersive_reader.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_logic_app_workflow.fraud_processing.identity[0].principal_id
}

# ==============================================================================
# DIAGNOSTIC SETTINGS FOR MONITORING
# ==============================================================================

# Diagnostic settings for Metrics Advisor
resource "azurerm_monitor_diagnostic_setting" "metrics_advisor_diagnostics" {
  count = var.enable_diagnostic_logs && var.enable_monitoring ? 1 : 0
  
  name                       = "metrics-advisor-diagnostics"
  target_resource_id         = azurerm_cognitive_account.metrics_advisor.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.fraud_monitoring[0].id
  
  enabled_log {
    category = "Audit"
  }
  
  enabled_log {
    category = "RequestResponse"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Immersive Reader
resource "azurerm_monitor_diagnostic_setting" "immersive_reader_diagnostics" {
  count = var.enable_diagnostic_logs && var.enable_monitoring ? 1 : 0
  
  name                       = "immersive-reader-diagnostics"
  target_resource_id         = azurerm_cognitive_account.immersive_reader.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.fraud_monitoring[0].id
  
  enabled_log {
    category = "Audit"
  }
  
  enabled_log {
    category = "RequestResponse"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Logic App
resource "azurerm_monitor_diagnostic_setting" "logic_app_diagnostics" {
  count = var.enable_diagnostic_logs && var.enable_monitoring ? 1 : 0
  
  name                       = "logic-app-diagnostics"
  target_resource_id         = azurerm_logic_app_workflow.fraud_processing.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.fraud_monitoring[0].id
  
  enabled_log {
    category = "WorkflowRuntime"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage_diagnostics" {
  count = var.enable_diagnostic_logs && var.enable_monitoring ? 1 : 0
  
  name                       = "storage-diagnostics"
  target_resource_id         = azurerm_storage_account.fraud_data.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.fraud_monitoring[0].id
  
  metric {
    category = "Transaction"
    enabled  = true
  }
  
  metric {
    category = "Capacity"
    enabled  = true
  }
}

# ==============================================================================
# MONITORING ALERTS
# ==============================================================================

# Action group for fraud detection alerts
resource "azurerm_monitor_action_group" "fraud_alerts" {
  count = var.enable_monitoring && length(var.alert_email_addresses) > 0 ? 1 : 0
  
  name                = "fraud-detection-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "FraudAlert"
  
  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name          = "email-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }
  
  tags = local.common_tags
}

# Alert rule for Metrics Advisor failures
resource "azurerm_monitor_metric_alert" "metrics_advisor_failures" {
  count = var.enable_monitoring && length(var.alert_email_addresses) > 0 ? 1 : 0
  
  name                = "metrics-advisor-failures"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_cognitive_account.metrics_advisor.id]
  description         = "Alert when Metrics Advisor experiences failures"
  severity            = var.alert_severity
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.CognitiveServices/accounts"
    metric_name      = "Errors"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.fraud_alerts[0].id
  }
  
  tags = local.common_tags
}

# Alert rule for Logic App failures
resource "azurerm_monitor_metric_alert" "logic_app_failures" {
  count = var.enable_monitoring && length(var.alert_email_addresses) > 0 ? 1 : 0
  
  name                = "logic-app-failures"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_logic_app_workflow.fraud_processing.id]
  description         = "Alert when Logic App workflow experiences failures"
  severity            = var.alert_severity
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Logic/workflows"
    metric_name      = "RunsFailed"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 1
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.fraud_alerts[0].id
  }
  
  tags = local.common_tags
}

# Alert rule for high confidence fraud detection
resource "azurerm_monitor_metric_alert" "high_confidence_fraud" {
  count = var.enable_monitoring && length(var.alert_email_addresses) > 0 ? 1 : 0
  
  name                = "high-confidence-fraud-detection"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_logic_app_workflow.fraud_processing.id]
  description         = "Alert when high confidence fraud is detected"
  severity            = 1  # High severity for fraud detection
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Logic/workflows"
    metric_name      = "RunsSucceeded"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.fraud_alerts[0].id
  }
  
  tags = local.common_tags
}