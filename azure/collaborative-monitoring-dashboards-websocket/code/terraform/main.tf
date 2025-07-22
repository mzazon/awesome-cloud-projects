# Azure Real-Time Collaborative Dashboard Infrastructure
# This Terraform configuration deploys a complete collaborative monitoring dashboard
# using Azure Web PubSub, Azure Monitor, and Azure Static Web Apps

# Data sources for current Azure configuration
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = var.random_suffix_length / 2
}

locals {
  # Consistent naming convention across all resources
  resource_suffix = random_id.suffix.hex
  
  # Merged tags for all resources
  tags = merge(var.common_tags, var.additional_tags, {
    Environment = var.environment
    Project     = var.project_name
  })
  
  # Resource naming patterns
  resource_group_name     = "rg-${var.project_name}-${var.environment}"
  storage_account_name    = "st${replace(var.project_name, "-", "")}${local.resource_suffix}"
  webpubsub_name         = "wps-${var.project_name}-${local.resource_suffix}"
  function_app_name      = "func-${var.project_name}-${local.resource_suffix}"
  static_web_app_name    = "swa-${var.project_name}-${local.resource_suffix}"
  app_insights_name      = "appi-${var.project_name}-${local.resource_suffix}"
  log_analytics_name     = "log-${var.project_name}-${local.resource_suffix}"
  app_service_plan_name  = "asp-${var.project_name}-${local.resource_suffix}"
}

# Resource Group for all dashboard infrastructure
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

# Log Analytics Workspace for centralized monitoring and logging
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = local.tags
}

# Application Insights for application performance monitoring
resource "azurerm_application_insights" "main" {
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  
  # Enhanced telemetry configuration
  retention_in_days                 = 90
  daily_data_cap_in_gb             = 1
  daily_data_cap_notifications_disabled = false
  
  tags = local.tags
}

# Storage Account for Function App and static content
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # Security hardening
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Network access configuration
  public_network_access_enabled = var.enable_public_network_access
  
  # CORS configuration for Static Web Apps integration
  blob_properties {
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "POST", "PUT"]
      allowed_origins    = var.allowed_origins
      exposed_headers    = ["*"]
      max_age_in_seconds = 86400
    }
  }
  
  tags = local.tags
}

# Azure Web PubSub for real-time WebSocket communication
resource "azurerm_web_pubsub" "main" {
  name                = local.webpubsub_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  sku      = var.webpubsub_sku.name
  capacity = var.webpubsub_sku.capacity
  
  # Enable public network access
  public_network_access_enabled = var.enable_public_network_access
  
  # CORS configuration for web clients
  cors {
    allowed_origins = var.allowed_origins
  }
  
  # Identity configuration for managed identity access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.tags
}

# Web PubSub Hub configuration for dashboard communication
resource "azurerm_web_pubsub_hub" "dashboard" {
  name           = var.webpubsub_hub_name
  web_pubsub_id  = azurerm_web_pubsub.main.id
  
  # Event handler configuration for Function App integration
  event_handler {
    url_template       = "https://${azurerm_linux_function_app.main.default_hostname}/api/eventhandler"
    user_event_pattern = "*"
    system_events      = ["connect", "connected", "disconnected"]
    
    # Authentication configuration
    auth {
      type = "None"
    }
  }
  
  # Anonymous connection policy for simplified client access
  anonymous_connection_enabled = true
  
  depends_on = [azurerm_linux_function_app.main]
}

# App Service Plan for Function App hosting
resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.function_app_sku
  
  tags = local.tags
}

# Linux Function App for serverless backend processing
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Function App configuration
  site_config {
    # Node.js runtime configuration
    application_stack {
      node_version = var.function_app_runtime.version
    }
    
    # CORS configuration for Static Web Apps
    cors {
      allowed_origins = var.allowed_origins
    }
    
    # Enhanced security settings
    ftps_state                = "Disabled"
    http2_enabled            = true
    minimum_tls_version      = "1.2"
    scm_minimum_tls_version  = "1.2"
    
    # Application Insights integration
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
  }
  
  # Application settings for runtime configuration
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"                    = var.function_app_runtime.name
    "WEBSITE_NODE_DEFAULT_VERSION"                = "~${var.function_app_runtime.version}"
    "AzureWebJobsFeatureFlags"                   = "EnableWorkerIndexing"
    "WEBPUBSUB_CONNECTION"                       = azurerm_web_pubsub.main.primary_connection_string
    "APPINSIGHTS_INSTRUMENTATIONKEY"             = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING"       = azurerm_application_insights.main.connection_string
    "LOG_ANALYTICS_WORKSPACE_ID"                 = azurerm_log_analytics_workspace.main.workspace_id
    "LOG_ANALYTICS_WORKSPACE_KEY"                = azurerm_log_analytics_workspace.main.primary_shared_key
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE"           = "true"
    "WEBSITE_RUN_FROM_PACKAGE"                   = "1"
  }
  
  # Managed identity for secure Azure service access
  identity {
    type = "SystemAssigned"
  }
  
  # Enhanced security with HTTPS only
  https_only                 = true
  public_network_access_enabled = var.enable_public_network_access
  
  tags = local.tags
  
  depends_on = [
    azurerm_application_insights.main,
    azurerm_web_pubsub.main
  ]
}

# Static Web App for dashboard frontend hosting
resource "azurerm_static_web_app" "main" {
  name                = local.static_web_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku_tier            = var.static_web_app_sku
  sku_size            = var.static_web_app_sku
  
  # Identity configuration for backend integration
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.tags
}

# Link Function App as backend API for Static Web App
resource "azurerm_static_web_app_function_app_registration" "main" {
  static_web_app_id = azurerm_static_web_app.main.id
  function_app_id   = azurerm_linux_function_app.main.id
}

# Diagnostic Settings for Web PubSub monitoring
resource "azurerm_monitor_diagnostic_setting" "webpubsub" {
  name                       = "webpubsub-diagnostics"
  target_resource_id         = azurerm_web_pubsub.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable all available log categories
  enabled_log {
    category = "ConnectivityLogs"
  }
  
  enabled_log {
    category = "MessagingLogs"
  }
  
  enabled_log {
    category = "HttpRequestLogs"
  }
  
  # Enable all metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic Settings for Function App monitoring
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  name                       = "function-app-diagnostics"
  target_resource_id         = azurerm_linux_function_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable Function App logs
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  # Enable all metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Action Group for alert notifications (created only if email recipients provided)
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_alerts && length(var.alert_email_recipients) > 0 ? 1 : 0
  name                = "ag-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "dashboard"
  
  # Email notifications for alerts
  dynamic "email_receiver" {
    for_each = var.alert_email_recipients
    content {
      name          = "email-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }
  
  tags = local.tags
}

# Metric Alert for high WebSocket connection count
resource "azurerm_monitor_metric_alert" "high_connections" {
  count               = var.enable_alerts ? 1 : 0
  name                = "High WebSocket Connections"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_web_pubsub.main.id]
  description         = "Alert when WebSocket connections exceed threshold"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.SignalRService/WebPubSub"
    metric_name      = "ConnectionCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 1000
  }
  
  dynamic "action" {
    for_each = var.enable_alerts && length(var.alert_email_recipients) > 0 ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.main[0].id
    }
  }
  
  tags = local.tags
}

# Metric Alert for Function App errors
resource "azurerm_monitor_metric_alert" "function_errors" {
  count               = var.enable_alerts ? 1 : 0
  name                = "Function App High Error Rate"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_function_app.main.id]
  description         = "Alert when Function App error rate is high"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }
  
  dynamic "action" {
    for_each = var.enable_alerts && length(var.alert_email_recipients) > 0 ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.main[0].id
    }
  }
  
  tags = local.tags
}

# RBAC: Grant Function App managed identity access to Web PubSub
resource "azurerm_role_assignment" "function_to_webpubsub" {
  scope                = azurerm_web_pubsub.main.id
  role_definition_name = "Web PubSub Service Owner"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# RBAC: Grant Function App managed identity access to Log Analytics
resource "azurerm_role_assignment" "function_to_logs" {
  scope                = azurerm_log_analytics_workspace.main.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}