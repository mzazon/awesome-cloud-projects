# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data sources for current configuration
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = var.log_analytics_workspace_name != null ? var.log_analytics_workspace_name : "law-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

# Application Insights for API monitoring
resource "azurerm_application_insights" "main" {
  name                = var.application_insights_name != null ? var.application_insights_name : "appi-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.tags
}

# Azure API Center for centralized API governance
resource "azurerm_api_center" "main" {
  name                = var.api_center_name != null ? var.api_center_name : "apic-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  tags = var.tags
}

# API Center Metadata Schema for API lifecycle management
resource "azurerm_api_center_metadata_schema" "lifecycle" {
  name            = "api-lifecycle"
  api_center_id   = azurerm_api_center.main.id
  
  schema = jsonencode({
    type = "object"
    properties = {
      lifecycleStage = {
        type = "string"
        enum = ["design", "development", "testing", "production", "deprecated"]
      }
      businessDomain = {
        type = "string"
        enum = ["finance", "hr", "operations", "customer", "analytics"]
      }
      dataClassification = {
        type = "string"
        enum = ["public", "internal", "confidential", "restricted"]
      }
    }
  })
}

# Register sample APIs in API Center
resource "azurerm_api_center_api" "sample_apis" {
  for_each = { for api in var.sample_apis : api.id => api }
  
  name          = each.value.id
  api_center_id = azurerm_api_center.main.id
  title         = each.value.title
  description   = each.value.description
  kind          = each.value.type
  
  depends_on = [azurerm_api_center_metadata_schema.lifecycle]
}

# Create API versions for each sample API
resource "azurerm_api_center_api_version" "sample_versions" {
  for_each = merge([
    for api in var.sample_apis : {
      for version in api.versions : "${api.id}-${version.id}" => {
        api_id          = api.id
        version_id      = version.id
        title           = version.title
        lifecycle_stage = version.lifecycle_stage
      }
    }
  ]...)
  
  name    = each.value.version_id
  api_id  = azurerm_api_center_api.sample_apis[each.value.api_id].id
  title   = each.value.title
  lifecycle_stage = each.value.lifecycle_stage
}

# Azure OpenAI Service for AI-powered documentation
resource "azurerm_cognitive_account" "openai" {
  name                = var.openai_name != null ? var.openai_name : "openai-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = var.openai_sku
  
  custom_subdomain_name = var.openai_name != null ? var.openai_name : "openai-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  
  tags = var.tags
}

# OpenAI Model Deployments
resource "azurerm_cognitive_deployment" "openai_models" {
  for_each = { for deployment in var.openai_model_deployments : deployment.name => deployment }
  
  name                 = each.value.name
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = each.value.model_name
    version = each.value.model_version
  }
  
  scale {
    type     = each.value.scale_type
    capacity = each.value.scale_capacity
  }
}

# Anomaly Detector for intelligent monitoring
resource "azurerm_cognitive_account" "anomaly_detector" {
  name                = var.anomaly_detector_name != null ? var.anomaly_detector_name : "anomaly-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "AnomalyDetector"
  sku_name            = var.anomaly_detector_sku
  
  custom_subdomain_name = var.anomaly_detector_name != null ? var.anomaly_detector_name : "anomaly-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  
  tags = var.tags
}

# Azure API Management (optional)
resource "azurerm_api_management" "main" {
  count = var.create_api_management ? 1 : 0
  
  name                = var.api_management_name != null ? var.api_management_name : "apim-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = var.api_management_publisher_name
  publisher_email     = var.api_management_publisher_email
  sku_name            = var.api_management_sku
  
  tags = var.tags
}

# Storage Account for portal assets
resource "azurerm_storage_account" "portal" {
  name                     = var.storage_account_name != null ? var.storage_account_name : "st${var.project_name}${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  static_website {
    index_document     = "index.html"
    error_404_document = "error.html"
  }
  
  tags = var.tags
}

# Logic App for automation workflows
resource "azurerm_logic_app_workflow" "documentation_automation" {
  name                = var.logic_app_name != null ? var.logic_app_name : "logic-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = var.tags
}

# Action Group for alerts
resource "azurerm_monitor_action_group" "main" {
  count = var.enable_alerts ? 1 : 0
  
  name                = "ag-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "apialerts"
  
  dynamic "email_receiver" {
    for_each = var.alert_email_receivers
    content {
      name          = "email-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }
  
  tags = var.tags
}

# Metric Alert for API anomalies
resource "azurerm_monitor_metric_alert" "api_anomaly" {
  count = var.enable_alerts ? 1 : 0
  
  name                = "api-anomaly-alert-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_api_center.main.id]
  description         = "Alert triggered when API performance anomalies are detected"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  
  criteria {
    metric_namespace = "Microsoft.ApiCenter/services"
    metric_name      = "RequestCount"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 1000
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = var.tags
}

# Diagnostic settings for API Center
resource "azurerm_monitor_diagnostic_setting" "api_center" {
  name                       = "diag-api-center-${random_string.suffix.result}"
  target_resource_id         = azurerm_api_center.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "ApiCenterLogs"
  }
  
  metric {
    category = "AllMetrics"
  }
}

# Diagnostic settings for OpenAI
resource "azurerm_monitor_diagnostic_setting" "openai" {
  name                       = "diag-openai-${random_string.suffix.result}"
  target_resource_id         = azurerm_cognitive_account.openai.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "Audit"
  }
  
  enabled_log {
    category = "RequestResponse"
  }
  
  metric {
    category = "AllMetrics"
  }
}

# Diagnostic settings for Anomaly Detector
resource "azurerm_monitor_diagnostic_setting" "anomaly_detector" {
  name                       = "diag-anomaly-${random_string.suffix.result}"
  target_resource_id         = azurerm_cognitive_account.anomaly_detector.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "Audit"
  }
  
  enabled_log {
    category = "RequestResponse"
  }
  
  metric {
    category = "AllMetrics"
  }
}

# Diagnostic settings for API Management (if created)
resource "azurerm_monitor_diagnostic_setting" "api_management" {
  count = var.create_api_management ? 1 : 0
  
  name                       = "diag-apim-${random_string.suffix.result}"
  target_resource_id         = azurerm_api_management.main[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "GatewayLogs"
  }
  
  enabled_log {
    category = "WebSocketConnectionLogs"
  }
  
  metric {
    category = "AllMetrics"
  }
}

# Role assignment for API Center to access OpenAI
resource "azurerm_role_assignment" "api_center_openai" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_api_center.main.identity[0].principal_id
}

# Role assignment for Logic App to access API Center
resource "azurerm_role_assignment" "logic_app_api_center" {
  scope                = azurerm_api_center.main.id
  role_definition_name = "API Center Service Contributor"
  principal_id         = azurerm_logic_app_workflow.documentation_automation.identity[0].principal_id
}