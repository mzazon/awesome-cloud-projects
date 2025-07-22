# Main Terraform configuration for Azure DevOps Real-Time Monitoring Dashboard
# This file creates all Azure resources needed for the monitoring solution

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  
  # Only generate if not provided
  count = var.random_suffix == "" ? 1 : 0
}

# Use provided suffix or generated one
locals {
  suffix = var.random_suffix != "" ? var.random_suffix : random_string.suffix[0].result
  
  # Common resource naming convention
  resource_prefix = "${var.project_name}-${var.environment}"
  
  # Resource names with unique suffix
  resource_names = {
    resource_group      = var.resource_group_name
    signalr            = "signalr-${local.resource_prefix}-${local.suffix}"
    storage_account    = "st${replace(local.resource_prefix, "-", "")}${local.suffix}"
    function_app       = "func-${local.resource_prefix}-${local.suffix}"
    app_service_plan   = "asp-${local.resource_prefix}-${local.suffix}"
    web_app           = "app-${local.resource_prefix}-${local.suffix}"
    log_analytics     = "log-${local.resource_prefix}-${local.suffix}"
    application_insights = "ai-${local.resource_prefix}-${local.suffix}"
    action_group      = "ag-${local.resource_prefix}-${local.suffix}"
  }
  
  # Common tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    CreatedBy   = "Terraform"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_names.resource_group
  location = var.location
  tags     = local.common_tags
}

# Create Log Analytics Workspace for centralized logging
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.resource_names.log_analytics
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  sku                = var.log_analytics_sku
  retention_in_days  = var.log_analytics_retention_days
  
  # Security settings
  internet_ingestion_enabled = true
  internet_query_enabled     = true
  local_authentication_disabled = false
  
  tags = local.common_tags
}

# Create Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  name                = local.resource_names.application_insights
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  workspace_id       = azurerm_log_analytics_workspace.main.id
  application_type   = var.application_insights_type
  
  # Sampling settings for cost optimization
  sampling_percentage = 100
  
  tags = local.common_tags
}

# Create Storage Account for Azure Functions
resource "azurerm_storage_account" "functions" {
  name                = local.resource_names.storage_account
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind            = "StorageV2"
  
  # Security settings
  min_tls_version                = var.minimum_tls_version
  enable_https_traffic_only      = true
  allow_nested_items_to_be_public = false
  
  # Blob properties for versioning and lifecycle
  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Create Azure SignalR Service for real-time communication
resource "azurerm_signalr_service" "main" {
  name                = local.resource_names.signalr
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  
  sku {
    name     = var.signalr_sku
    capacity = var.signalr_capacity
  }
  
  # Service configuration
  service_mode                   = var.signalr_service_mode
  connectivity_logs_enabled      = true
  messaging_logs_enabled         = true
  live_trace_enabled            = true
  
  # CORS configuration for web dashboard
  cors {
    allowed_origins = ["*"]
  }
  
  # Upstream settings for Azure Functions integration
  upstream_endpoint {
    category_pattern = ["connections", "messages"]
    event_pattern    = ["*"]
    hub_pattern      = ["monitoring"]
    url_template     = "https://${local.resource_names.function_app}.azurewebsites.net/runtime/webhooks/signalr?code={hub.{event}.{category}.{connectionId}}"
  }
  
  tags = local.common_tags
}

# Create App Service Plan for hosting web applications
resource "azurerm_service_plan" "main" {
  name                = local.resource_names.app_service_plan
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  
  os_type  = var.app_service_plan_os_type
  sku_name = var.app_service_plan_sku
  
  tags = local.common_tags
}

# Create Azure Functions App for event processing
resource "azurerm_linux_function_app" "main" {
  name                = local.resource_names.function_app
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  service_plan_id    = azurerm_service_plan.main.id
  
  # Storage account for Functions runtime
  storage_account_name       = azurerm_storage_account.functions.name
  storage_account_access_key = azurerm_storage_account.functions.primary_access_key
  
  # Functions runtime configuration
  functions_extension_version = var.functions_runtime_version
  
  # Enable Application Insights
  app_insights_instrumentation_key = azurerm_application_insights.main.instrumentation_key
  app_insights_connection_string   = azurerm_application_insights.main.connection_string
  
  # Site configuration
  site_config {
    application_stack {
      node_version = var.functions_node_version
    }
    
    # Security settings
    ftps_state               = "Disabled"
    http2_enabled           = true
    minimum_tls_version     = var.minimum_tls_version
    
    # CORS configuration
    cors {
      allowed_origins = ["*"]
    }
    
    # Enable Application Insights
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
  }
  
  # Application settings
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"         = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"     = "~${var.functions_node_version}"
    "AzureSignalRConnectionString"     = azurerm_signalr_service.main.primary_connection_string
    "SIGNALR_HUB_NAME"                = "monitoring"
    "WEBSITE_RUN_FROM_PACKAGE"        = "1"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE" = "true"
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.functions.primary_connection_string
    "WEBSITE_CONTENTSHARE"            = "${local.resource_names.function_app}-content"
  }
  
  # Security settings
  https_only = true
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Create Web App for the monitoring dashboard
resource "azurerm_linux_web_app" "dashboard" {
  name                = local.resource_names.web_app
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  service_plan_id    = azurerm_service_plan.main.id
  
  # Enable Application Insights
  app_insights_instrumentation_key = azurerm_application_insights.main.instrumentation_key
  app_insights_connection_string   = azurerm_application_insights.main.connection_string
  
  # Site configuration
  site_config {
    always_on         = var.web_app_always_on
    http2_enabled     = true
    ftps_state        = "Disabled"
    minimum_tls_version = var.minimum_tls_version
    
    # Application stack configuration
    application_stack {
      node_version = var.functions_node_version
    }
    
    # Enable Application Insights
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
  }
  
  # Application settings
  app_settings = {
    "WEBSITE_NODE_DEFAULT_VERSION"     = "~${var.functions_node_version}"
    "FUNCTIONS_URL"                    = "https://${azurerm_linux_function_app.main.default_hostname}"
    "SIGNALR_CONNECTION_STRING"        = azurerm_signalr_service.main.primary_connection_string
    "SIGNALR_HUB_NAME"                = "monitoring"
    "WEBSITE_RUN_FROM_PACKAGE"        = "1"
    "SCM_DO_BUILD_DURING_DEPLOYMENT"  = "true"
    "ENABLE_ORYX_BUILD"               = "true"
  }
  
  # Security settings
  https_only = var.web_app_https_only
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Create Action Group for monitoring alerts
resource "azurerm_monitor_action_group" "main" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  name                = local.resource_names.action_group
  resource_group_name = azurerm_resource_group.main.name
  short_name         = "mon-alerts"
  
  # Email notification (if provided)
  dynamic "email_receiver" {
    for_each = var.alert_notification_email != "" ? [1] : []
    
    content {
      name          = "admin-email"
      email_address = var.alert_notification_email
    }
  }
  
  # Webhook notification to Functions
  webhook_receiver {
    name        = "functions-webhook"
    service_uri = "https://${azurerm_linux_function_app.main.default_hostname}/api/DevOpsWebhook"
  }
  
  tags = local.common_tags
}

# Create metric alert for Function App errors
resource "azurerm_monitor_metric_alert" "function_errors" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  name                = "Function App Errors - ${local.resource_names.function_app}"
  resource_group_name = azurerm_resource_group.main.name
  scopes             = [azurerm_linux_function_app.main.id]
  description        = "Alert when Function App has high error rate"
  severity           = 2
  frequency          = "PT1M"
  window_size        = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "FunctionExecutionUnits"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 1000
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
}

# Create metric alert for SignalR connection count
resource "azurerm_monitor_metric_alert" "signalr_connections" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  name                = "SignalR Low Connections - ${local.resource_names.signalr}"
  resource_group_name = azurerm_resource_group.main.name
  scopes             = [azurerm_signalr_service.main.id]
  description        = "Alert when SignalR has no active connections"
  severity           = 3
  frequency          = "PT5M"
  window_size        = "PT15M"
  
  criteria {
    metric_namespace = "Microsoft.SignalRService/SignalR"
    metric_name      = "ConnectionCount"
    aggregation      = "Maximum"
    operator         = "LessThan"
    threshold        = 1
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
}

# Create metric alert for Web App availability
resource "azurerm_monitor_metric_alert" "webapp_availability" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  name                = "Web App Down - ${local.resource_names.web_app}"
  resource_group_name = azurerm_resource_group.main.name
  scopes             = [azurerm_linux_web_app.dashboard.id]
  description        = "Alert when Web App is not responding"
  severity           = 1
  frequency          = "PT1M"
  window_size        = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
}

# Configure diagnostic settings for SignalR Service
resource "azurerm_monitor_diagnostic_setting" "signalr" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name                       = "signalr-diagnostics"
  target_resource_id         = azurerm_signalr_service.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "AllLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Configure diagnostic settings for Function App
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name                       = "function-app-diagnostics"
  target_resource_id         = azurerm_linux_function_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Configure diagnostic settings for Web App
resource "azurerm_monitor_diagnostic_setting" "web_app" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name                       = "web-app-diagnostics"
  target_resource_id         = azurerm_linux_web_app.dashboard.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "AppServiceHTTPLogs"
  }
  
  enabled_log {
    category = "AppServiceConsoleLog"
  }
  
  enabled_log {
    category = "AppServiceAppLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Role assignment for Function App to access SignalR Service
resource "azurerm_role_assignment" "function_signalr" {
  scope                = azurerm_signalr_service.main.id
  role_definition_name = "SignalR App Server"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Role assignment for Web App to access SignalR Service
resource "azurerm_role_assignment" "webapp_signalr" {
  scope                = azurerm_signalr_service.main.id
  role_definition_name = "SignalR Service Reader"
  principal_id         = azurerm_linux_web_app.dashboard.identity[0].principal_id
}