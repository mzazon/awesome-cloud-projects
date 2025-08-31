# Azure Communication Services Monitoring Infrastructure
# Complete infrastructure for monitoring Communication Services with Application Insights

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and tagging
locals {
  # Generate unique suffix for resource names
  name_suffix = random_id.suffix.hex
  
  # Resource naming convention: {project}-{resource-type}-{environment}-{suffix}
  resource_group_name    = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.name_suffix}"
  communication_service  = "cs-${var.project_name}-${var.environment}-${local.name_suffix}"
  log_analytics_name     = "law-${var.project_name}-${var.environment}-${local.name_suffix}"
  application_insights   = "ai-${var.project_name}-${var.environment}-${local.name_suffix}"
  action_group_name      = "ag-${var.project_name}-${var.environment}-${local.name_suffix}"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment     = var.environment
    Project         = var.project_name
    Purpose         = "communication-monitoring"
    ManagedBy       = "terraform"
    DeploymentDate  = formatdate("YYYY-MM-DD", timestamp())
    Recipe          = "communication-monitoring-services-insights"
  })
}

# Resource Group - Container for all monitoring resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
  
  lifecycle {
    ignore_changes = [tags["DeploymentDate"]]
  }
}

# Log Analytics Workspace - Central data store for monitoring telemetry
# This is the foundation for modern Azure monitoring, required for workspace-based Application Insights
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Workspace configuration
  sku               = var.log_analytics_sku
  retention_in_days = var.log_analytics_retention_days
  daily_quota_gb    = var.log_analytics_daily_quota_gb
  
  # Security and access configuration following Azure Well-Architected principles
  local_authentication_enabled    = true   # Can be disabled for enhanced security in production
  internet_ingestion_enabled       = true  # Required for Communication Services telemetry
  internet_query_enabled           = true  # Required for Application Insights queries
  allow_resource_only_permissions  = true  # Enhanced security through resource-specific permissions
  
  tags = local.common_tags
  
  lifecycle {
    ignore_changes = [tags["DeploymentDate"]]
  }
}

# Application Insights - Advanced monitoring and analytics for Communication Services
# Uses workspace-based architecture (required as of February 2024)
resource "azurerm_application_insights" "main" {
  name                = local.application_insights
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.application_insights_type
  
  # Data retention and volume management
  retention_in_days                     = var.application_insights_retention_days
  daily_data_cap_in_gb                  = var.application_insights_daily_cap_gb
  daily_data_cap_notifications_disabled = false  # Enable cost alerts
  sampling_percentage                   = var.application_insights_sampling_percentage
  
  # Security configuration for production environments
  local_authentication_disabled = false  # Can be enabled for enhanced security with managed identities
  internet_ingestion_enabled    = true   # Required for telemetry collection
  internet_query_enabled        = true   # Required for dashboard and alerting
  disable_ip_masking           = false   # Privacy compliance - keep IP masking enabled
  
  tags = local.common_tags
  
  lifecycle {
    ignore_changes = [tags["DeploymentDate"]]
  }
}

# Azure Communication Services - Core communication platform with built-in telemetry
resource "azurerm_communication_service" "main" {
  name                = local.communication_service
  resource_group_name = azurerm_resource_group.main.name
  data_location       = var.communication_service_data_location
  
  tags = local.common_tags
  
  lifecycle {
    ignore_changes = [tags["DeploymentDate"]]
  }
}

# Diagnostic Settings for Communication Services
# Configures telemetry flow from Communication Services to Log Analytics workspace
resource "azurerm_monitor_diagnostic_setting" "communication_service" {
  count                          = var.enable_diagnostic_settings ? 1 : 0
  name                           = "communication-service-diagnostics"
  target_resource_id             = azurerm_communication_service.main.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.main.id
  log_analytics_destination_type = "Dedicated"  # Enhanced security and performance
  
  # Email operational logs - captures email sending activities and delivery status
  enabled_log {
    category = "EmailSendMailOperational"
  }
  
  # Email status update logs - tracks delivery confirmations, bounces, and user interactions
  enabled_log {
    category = "EmailStatusUpdateOperational"
  }
  
  # SMS operational logs - captures SMS sending and delivery information
  enabled_log {
    category = "SMSOperational"
  }
  
  # Authentication logs - monitors API access and authentication events
  enabled_log {
    category = "AuthOperational"
  }
  
  # Usage logs - tracks service consumption and quotas
  enabled_log {
    category = "Usage"
  }
  
  # All metrics including request counts, latency, and error rates
  enabled_log {
    category = "AllLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Action Group for Alert Notifications
# Defines how alerts are delivered (email, webhook, SMS, etc.)
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_metric_alerts ? 1 : 0
  name                = local.action_group_name
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "CommAlerts"
  
  # Email receivers for alert notifications
  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name          = "admin-email-${email_receiver.key + 1}"
      email_address = email_receiver.value
    }
  }
  
  tags = local.common_tags
  
  lifecycle {
    ignore_changes = [tags["DeploymentDate"]]
  }
}

# Metric Alert for Communication Service API Request Failures
# Monitors API request errors and high failure rates
resource "azurerm_monitor_metric_alert" "communication_service_errors" {
  count               = var.enable_metric_alerts ? 1 : 0
  name                = "communication-service-errors"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_communication_service.main.id]
  description         = "Alert when Communication Services API requests exceed error threshold"
  
  # Alert configuration
  severity    = 2                              # Warning level (0=Critical, 1=Error, 2=Warning, 3=Informational, 4=Verbose)
  frequency   = var.alert_evaluation_frequency # How often to evaluate the condition
  window_size = var.alert_window_size          # Time window for metric aggregation
  enabled     = true
  
  # Metric criteria - triggers when API request count exceeds threshold
  criteria {
    metric_namespace = "Microsoft.Communication/communicationServices"
    metric_name      = "APIRequestCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.communication_service_error_threshold
    
    # Dimension filter to focus on error status codes (4xx and 5xx)
    dimension {
      name     = "StatusCode"
      operator = "Include"
      values   = ["4*", "5*"]  # Client errors (4xx) and server errors (5xx)
    }
  }
  
  # Action to take when alert is triggered
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
  
  lifecycle {
    ignore_changes = [tags["DeploymentDate"]]
  }
}

# Metric Alert for Communication Service High Request Volume
# Monitors for unusual traffic spikes that might indicate issues or abuse
resource "azurerm_monitor_metric_alert" "communication_service_volume" {
  count               = var.enable_metric_alerts ? 1 : 0
  name                = "communication-service-volume"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_communication_service.main.id]
  description         = "Alert when Communication Services request volume is unusually high"
  
  severity    = 3  # Informational - high volume might not be an error
  frequency   = var.alert_evaluation_frequency
  window_size = var.alert_window_size
  enabled     = true
  
  criteria {
    metric_namespace = "Microsoft.Communication/communicationServices"
    metric_name      = "APIRequestCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.communication_service_error_threshold * 10  # 10x the error threshold
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
  
  lifecycle {
    ignore_changes = [tags["DeploymentDate"]]
  }
}

# Metric Alert for Application Insights Availability
# Monitors application availability and uptime metrics
resource "azurerm_monitor_metric_alert" "application_insights_availability" {
  count               = var.enable_metric_alerts ? 1 : 0
  name                = "appinsights-availability-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights.main.id]
  description         = "Alert when application availability drops below acceptable threshold"
  
  severity    = 1  # Error level - availability issues are critical
  frequency   = "PT1M"   # Check every minute for availability
  window_size = "PT5M"   # 5-minute window for availability calculation
  enabled     = true
  
  criteria {
    metric_namespace = "Microsoft.Insights/components"
    metric_name      = "availabilityResults/availabilityPercentage"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 95  # Alert if availability drops below 95%
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
  
  lifecycle {
    ignore_changes = [tags["DeploymentDate"]]
  }
}

# Metric Alert for Application Insights Request Duration
# Monitors application performance and response times
resource "azurerm_monitor_metric_alert" "application_insights_performance" {
  count               = var.enable_metric_alerts ? 1 : 0
  name                = "appinsights-performance-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights.main.id]
  description         = "Alert when average application response time exceeds threshold"
  
  severity    = 2  # Warning level - performance degradation
  frequency   = var.alert_evaluation_frequency
  window_size = var.alert_window_size
  enabled     = true
  
  criteria {
    metric_namespace = "Microsoft.Insights/components"
    metric_name      = "requests/duration"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 5000  # Alert if average response time exceeds 5 seconds (5000ms)
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
  
  lifecycle {
    ignore_changes = [tags["DeploymentDate"]]
  }
}