# Azure Load Testing and Azure DevOps Performance Testing Infrastructure
# This Terraform configuration deploys a complete performance testing solution
# integrating Azure Load Testing with Azure DevOps CI/CD pipelines

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  count   = var.generate_random_suffix ? 1 : 0
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for consistent naming and tagging
locals {
  # Generate suffix for unique naming when enabled
  suffix = var.generate_random_suffix ? random_string.suffix[0].result : ""
  
  # Consistent naming convention with optional suffix
  resource_group_name           = var.generate_random_suffix ? "${var.resource_group_name}-${local.suffix}" : var.resource_group_name
  load_test_name               = var.generate_random_suffix ? "${var.load_test_name}-${local.suffix}" : var.load_test_name
  app_insights_name            = var.generate_random_suffix ? "${var.app_insights_name}-${local.suffix}" : var.app_insights_name
  log_analytics_workspace_name = var.generate_random_suffix ? "${var.log_analytics_workspace_name}-${local.suffix}" : var.log_analytics_workspace_name
  service_principal_name       = var.generate_random_suffix ? "${var.service_principal_name}-${local.suffix}" : var.service_principal_name
  action_group_name           = var.generate_random_suffix ? "${var.action_group_name}-${local.suffix}" : var.action_group_name
  
  # Common tags applied to all resources
  common_tags = {
    Environment  = var.environment
    Project      = var.project
    CostCenter   = var.cost_center
    Owner        = var.owner
    Purpose      = "performance-testing"
    ManagedBy    = "terraform"
    CreatedDate  = formatdate("YYYY-MM-DD", timestamp())
  }
}

# Resource Group
# Central container for all performance testing resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace
# Centralized logging and monitoring for all performance testing activities
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_workspace_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                = var.log_analytics_sku
  retention_in_days  = var.log_analytics_retention_in_days
  
  tags = merge(local.common_tags, {
    ResourceType = "log-analytics"
    Description  = "Centralized logging for performance testing infrastructure"
  })
}

# Application Insights
# Application performance monitoring and telemetry collection
resource "azurerm_application_insights" "main" {
  name                = local.app_insights_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id       = azurerm_log_analytics_workspace.main.id
  application_type   = var.app_insights_application_type
  retention_in_days  = var.app_insights_retention_in_days
  
  tags = merge(local.common_tags, {
    ResourceType = "application-insights"
    Description  = "Application performance monitoring for load testing targets"
  })
}

# Azure Load Testing Resource
# Managed load testing service for executing JMeter-based performance tests
resource "azurerm_load_test" "main" {
  name                = local.load_test_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  description        = var.load_test_description
  
  # Enable system-assigned managed identity for secure access to Azure resources
  dynamic "identity" {
    for_each = var.enable_managed_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
  
  tags = merge(local.common_tags, {
    ResourceType = "load-test"
    Description  = "Azure Load Testing service for automated performance validation"
  })
  
  depends_on = [azurerm_resource_group.main]
}

# Diagnostic Settings for Load Testing Resource
# Enable comprehensive logging and monitoring for the load testing service
resource "azurerm_monitor_diagnostic_setting" "load_test" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                      = "diag-${local.load_test_name}"
  target_resource_id        = azurerm_load_test.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable all available log categories for comprehensive monitoring
  enabled_log {
    category = "LoadTestRuns"
  }
  
  # Enable all available metrics for performance monitoring
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# Azure AD Application for Service Principal
# Application registration for Azure DevOps service connection
resource "azuread_application" "devops_sp" {
  display_name = local.service_principal_name
  description  = "Service Principal for Azure DevOps Load Testing integration"
  
  # Configure application for service-to-service authentication
  sign_in_audience = "AzureADMyOrg"
  
  # Application metadata
  tags = ["devops", "automation", "load-testing", var.environment]
}

# Service Principal for Azure DevOps Authentication
# Security principal that enables Azure DevOps to access Azure resources
resource "azuread_service_principal" "devops_sp" {
  client_id                    = azuread_application.devops_sp.client_id
  app_role_assignment_required = false
  description                  = "Service principal for Azure DevOps pipeline authentication"
  
  tags = ["devops", "automation", "load-testing", var.environment]
}

# Client Secret for Service Principal Authentication
# Secure credential for Azure DevOps service connection (valid for 2 years)
resource "azuread_application_password" "devops_sp" {
  application_id = azuread_application.devops_sp.id
  display_name   = "Azure DevOps Load Testing Key"
  end_date      = timeadd(timestamp(), "17520h") # 2 years from creation
}

# Role Assignment: Load Test Contributor
# Grant Azure DevOps service principal permission to manage load tests
resource "azurerm_role_assignment" "load_test_contributor" {
  scope                = azurerm_load_test.main.id
  role_definition_name = "Load Test Contributor"
  principal_id         = azuread_service_principal.devops_sp.object_id
  
  depends_on = [azurerm_load_test.main, azuread_service_principal.devops_sp]
}

# Role Assignment: Monitoring Contributor
# Allow service principal to access monitoring data and create alerts
resource "azurerm_role_assignment" "monitoring_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Monitoring Contributor"
  principal_id         = azuread_service_principal.devops_sp.object_id
  
  depends_on = [azurerm_resource_group.main, azuread_service_principal.devops_sp]
}

# Role Assignment: Application Insights Component Contributor
# Enable service principal to access Application Insights data
resource "azurerm_role_assignment" "app_insights_contributor" {
  scope                = azurerm_application_insights.main.id
  role_definition_name = "Application Insights Component Contributor"
  principal_id         = azuread_service_principal.devops_sp.object_id
  
  depends_on = [azurerm_application_insights.main, azuread_service_principal.devops_sp]
}

# Action Group for Performance Alerts
# Notification system for performance degradation alerts
resource "azurerm_monitor_action_group" "performance_alerts" {
  name                = local.action_group_name
  resource_group_name = azurerm_resource_group.main.name
  short_name          = var.action_group_short_name
  
  # Email notification configuration
  email_receiver {
    name          = "DevOpsTeam"
    email_address = var.alert_email_receiver
    use_common_alert_schema = true
  }
  
  tags = merge(local.common_tags, {
    ResourceType = "action-group"
    Description  = "Alert notifications for performance testing"
  })
}

# Metric Alert: High Response Time
# Alert when average response time exceeds the configured threshold
resource "azurerm_monitor_metric_alert" "high_response_time" {
  name                = "alert-high-response-time"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_load_test.main.id]
  description         = "Alert when average response time exceeds ${var.response_time_threshold_ms}ms"
  severity            = 2
  frequency           = var.alert_evaluation_frequency
  window_size         = var.alert_window_size
  enabled             = true
  
  # Alert criteria: Average response time threshold
  criteria {
    metric_namespace = "Microsoft.LoadTestService/loadtests"
    metric_name      = "ResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.response_time_threshold_ms
    
    # Additional filtering can be added here for specific test runs
  }
  
  # Action to trigger when alert fires
  action {
    action_group_id = azurerm_monitor_action_group.performance_alerts.id
    
    # Custom webhook properties for enhanced alert context
    webhook_properties = {
      alert_type = "response_time"
      threshold  = tostring(var.response_time_threshold_ms)
      severity   = "high"
    }
  }
  
  tags = merge(local.common_tags, {
    ResourceType = "metric-alert"
    AlertType    = "response-time"
    Description  = "Performance alert for response time degradation"
  })
  
  depends_on = [azurerm_load_test.main, azurerm_monitor_action_group.performance_alerts]
}

# Metric Alert: High Error Rate
# Alert when error percentage exceeds the configured threshold
resource "azurerm_monitor_metric_alert" "high_error_rate" {
  name                = "alert-high-error-rate"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_load_test.main.id]
  description         = "Alert when error rate exceeds ${var.error_rate_threshold_percent}%"
  severity            = 1  # High severity for error rate issues
  frequency           = var.alert_evaluation_frequency
  window_size         = var.alert_window_size
  enabled             = true
  
  # Alert criteria: Error percentage threshold
  criteria {
    metric_namespace = "Microsoft.LoadTestService/loadtests"
    metric_name      = "ErrorPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.error_rate_threshold_percent
  }
  
  # Action to trigger when alert fires
  action {
    action_group_id = azurerm_monitor_action_group.performance_alerts.id
    
    # Custom webhook properties for enhanced alert context
    webhook_properties = {
      alert_type = "error_rate"
      threshold  = tostring(var.error_rate_threshold_percent)
      severity   = "critical"
    }
  }
  
  tags = merge(local.common_tags, {
    ResourceType = "metric-alert"
    AlertType    = "error-rate"
    Description  = "Performance alert for error rate threshold breach"
  })
  
  depends_on = [azurerm_load_test.main, azurerm_monitor_action_group.performance_alerts]
}

# Diagnostic Settings for Application Insights
# Enable comprehensive logging for application performance monitoring
resource "azurerm_monitor_diagnostic_setting" "app_insights" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                      = "diag-${local.app_insights_name}"
  target_resource_id        = azurerm_application_insights.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable audit logs for Application Insights
  enabled_log {
    category = "Audit"
  }
  
  # Enable request logs for detailed request tracking
  enabled_log {
    category = "Request"
  }
  
  # Enable all metrics for comprehensive monitoring
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}