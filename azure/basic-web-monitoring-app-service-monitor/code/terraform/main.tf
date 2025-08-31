# Main Terraform Configuration
# This file contains the primary infrastructure resources for basic web app monitoring

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed names and tags
locals {
  # Generate unique names if not provided
  resource_group_name          = var.resource_group_name != null ? var.resource_group_name : "rg-recipe-${random_id.suffix.hex}"
  app_name                    = var.app_name != null ? var.app_name : "webapp-${random_id.suffix.hex}"
  app_service_plan_name       = var.app_service_plan_name != null ? var.app_service_plan_name : "plan-${random_id.suffix.hex}"
  log_analytics_workspace_name = var.log_analytics_workspace_name != null ? var.log_analytics_workspace_name : "logs-${random_id.suffix.hex}"
  action_group_name           = "WebAppAlerts-${random_id.suffix.hex}"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    environment    = var.environment
    recipe        = "basic-web-monitoring-app-service-monitor"
    deployment    = "terraform"
    created_date  = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Resource Group
# Container for all related resources in this deployment
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace
# Centralized repository for log data from multiple Azure resources
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  
  tags = local.common_tags
}

# App Service Plan
# Defines the compute resources and features available to web applications
resource "azurerm_service_plan" {
  name                = local.app_service_plan_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku
  
  tags = local.common_tags
}

# Linux Web App
# The main web application hosted on App Service
resource "azurerm_linux_web_app" "main" {
  name                = local.app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  
  # Configure the web app to use a Docker container
  site_config {
    always_on = var.app_service_plan_sku != "F1" ? true : false # Free tier doesn't support always_on
    
    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = "https://mcr.microsoft.com"
    }
    
    # Enable detailed error messages and failed request tracing
    detailed_error_logging_enabled = true
    failed_request_tracing_enabled  = true
    
    # Configure HTTP logging
    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }
  
  # Application settings for the web app
  app_settings = {
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    "DOCKER_REGISTRY_SERVER_URL"          = "https://mcr.microsoft.com"
    "WEBSITES_PORT"                       = "8080"
  }
  
  # Configure application logging
  logs {
    detailed_error_messages = true
    failed_request_tracing  = true
    
    application_logs {
      file_system_level = "Information"
    }
    
    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }
  
  tags = local.common_tags
  
  depends_on = [azurerm_service_plan.main]
}

# Diagnostic Settings for App Service
# Routes application logs and metrics to Log Analytics workspace
resource "azurerm_monitor_diagnostic_setting" "app_service" {
  name                       = "AppServiceDiagnostics"
  target_resource_id         = azurerm_linux_web_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable application logs
  enabled_log {
    category = "AppServiceHTTPLogs"
  }
  
  enabled_log {
    category = "AppServiceConsoleLogs"
  }
  
  enabled_log {
    category = "AppServiceAppLogs"
  }
  
  # Enable all metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
  
  depends_on = [
    azurerm_linux_web_app.main,
    azurerm_log_analytics_workspace.main
  ]
}

# Action Group for Alert Notifications
# Defines how alerts notify team members when triggered
resource "azurerm_monitor_action_group" "main" {
  name                = local.action_group_name
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "WebAlert"
  
  # Email notification configuration
  email_receiver {
    name          = "Admin"
    email_address = var.alert_email_address
  }
  
  tags = local.common_tags
}

# Metric Alert Rule: High Response Time
# Monitors application response time and alerts when threshold is exceeded
resource "azurerm_monitor_metric_alert" "response_time" {
  name                = "HighResponseTime-${local.app_name}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_web_app.main.id]
  description         = "Alert when average response time exceeds ${var.response_time_threshold} seconds"
  severity            = 2
  frequency           = var.alert_evaluation_frequency
  window_size         = var.alert_window_size
  
  # Alert criteria configuration
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "AverageResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.response_time_threshold
  }
  
  # Link to action group for notifications
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_linux_web_app.main,
    azurerm_monitor_action_group.main
  ]
}

# Metric Alert Rule: HTTP 5xx Errors
# Monitors server errors and alerts when threshold is exceeded
resource "azurerm_monitor_metric_alert" "http_errors" {
  name                = "HTTP5xxErrors-${local.app_name}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_web_app.main.id]
  description         = "Alert when HTTP 5xx errors exceed ${var.http_error_threshold} in ${var.alert_window_size}"
  severity            = 1
  frequency           = var.alert_evaluation_frequency
  window_size         = var.alert_window_size
  
  # Alert criteria configuration
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.http_error_threshold
  }
  
  # Link to action group for notifications
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_linux_web_app.main,
    azurerm_monitor_action_group.main
  ]
}