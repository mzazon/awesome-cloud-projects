# Main Terraform configuration for Azure Performance Regression Detection

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Data source for current subscription information
data "azurerm_subscription" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_group_name}-${random_string.suffix.result}"
  location = var.location
  
  tags = merge(var.tags, {
    Component = "resource-group"
  })
}

# Log Analytics Workspace - Central repository for all performance metrics
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.log_analytics_workspace_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(var.tags, {
    Component = "log-analytics"
    Purpose   = "performance-monitoring"
  })
}

# Application Insights - Application performance monitoring
resource "azurerm_application_insights" "main" {
  name                = "${var.application_insights_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.application_insights_type
  
  tags = merge(var.tags, {
    Component = "application-insights"
    Purpose   = "app-monitoring"
  })
}

# Azure Container Registry - Store container images for the demo application
resource "azurerm_container_registry" "main" {
  name                = "${var.container_registry_name}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = true
  
  tags = merge(var.tags, {
    Component = "container-registry"
    Purpose   = "image-storage"
  })
}

# Container Apps Environment - Serverless container hosting platform
resource "azurerm_container_app_environment" "main" {
  name                       = "${var.container_app_environment_name}-${random_string.suffix.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  tags = merge(var.tags, {
    Component = "container-apps-environment"
    Purpose   = "app-hosting"
  })
}

# Container App - Demo application for performance testing
resource "azurerm_container_app" "main" {
  name                         = "${var.container_app_name}-${random_string.suffix.result}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  
  template {
    min_replicas = var.container_app_min_replicas
    max_replicas = var.container_app_max_replicas
    
    container {
      name   = "demo-app"
      image  = var.container_app_image
      cpu    = var.container_app_cpu
      memory = var.container_app_memory
      
      # Environment variables for Application Insights integration
      env {
        name  = "APPINSIGHTS_INSTRUMENTATIONKEY"
        value = azurerm_application_insights.main.instrumentation_key
      }
      
      env {
        name  = "APPINSIGHTS_CONNECTIONSTRING"
        value = azurerm_application_insights.main.connection_string
      }
    }
  }
  
  ingress {
    allow_insecure_connections = false
    external_enabled          = true
    target_port               = var.container_app_target_port
    
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
  
  tags = merge(var.tags, {
    Component = "container-app"
    Purpose   = "demo-application"
  })
}

# Azure Load Testing - Managed load testing service
resource "azurerm_load_test" "main" {
  name                = "${var.load_test_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  description         = var.load_test_description
  
  tags = merge(var.tags, {
    Component = "load-testing"
    Purpose   = "performance-validation"
  })
}

# Action Group for alert notifications
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "ag-perftest-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "perftest"
  
  # Email notification (customize as needed)
  email_receiver {
    name          = "performance-team"
    email_address = "performance-team@company.com"
  }
  
  tags = merge(var.tags, {
    Component = "monitoring"
    Purpose   = "alerting"
  })
}

# Alert Rule for Response Time Regression
resource "azurerm_monitor_metric_alert" "response_time" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "ResponseTimeRegression-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights.main.id]
  description         = "Alert when response time exceeds baseline threshold"
  severity            = 2
  frequency           = "PT${var.alert_evaluation_frequency}M"
  window_size         = "PT${var.alert_window_size}M"
  
  criteria {
    metric_namespace = "Microsoft.Insights/components"
    metric_name      = "requests/duration"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.response_time_threshold_ms
    
    dimension {
      name     = "request/name"
      operator = "Include"
      values   = ["*"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = merge(var.tags, {
    Component = "monitoring"
    Purpose   = "regression-detection"
    AlertType = "response-time"
  })
}

# Alert Rule for Error Rate Regression
resource "azurerm_monitor_metric_alert" "error_rate" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "ErrorRateRegression-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights.main.id]
  description         = "Alert when error rate exceeds acceptable threshold"
  severity            = 2
  frequency           = "PT${var.alert_evaluation_frequency}M"
  window_size         = "PT${var.alert_window_size}M"
  
  criteria {
    metric_namespace = "Microsoft.Insights/components"
    metric_name      = "requests/failed"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = var.error_rate_threshold_percent
    
    dimension {
      name     = "request/name"
      operator = "Include"
      values   = ["*"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = merge(var.tags, {
    Component = "monitoring"
    Purpose   = "regression-detection"
    AlertType = "error-rate"
  })
}

# Performance Monitoring Workbook
resource "azurerm_application_insights_workbook" "performance_dashboard" {
  count               = var.create_performance_workbook ? 1 : 0
  name                = "performance-dashboard-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  display_name        = "Performance Regression Detection Dashboard"
  source_id           = azurerm_application_insights.main.id
  category            = "performance"
  
  # Workbook template with performance monitoring queries
  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "# Performance Regression Detection Dashboard\n\nThis dashboard provides real-time monitoring of application performance metrics and helps identify potential regressions during load testing.\n\n## Key Metrics\n- Response Time Trends\n- Error Rate Analysis\n- Throughput Monitoring\n- Resource Utilization"
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = <<-EOT
            requests
            | where timestamp > ago(1h)
            | summarize 
                AvgResponseTime = avg(duration),
                P95ResponseTime = percentile(duration, 95),
                P99ResponseTime = percentile(duration, 99)
                by bin(timestamp, 5m)
            | render timechart
          EOT
          size = 0
          title = "Response Time Trends"
          timeContext = {
            durationMs = 3600000
          }
          queryType = 0
          resourceType = "microsoft.insights/components"
          visualization = "timechart"
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = <<-EOT
            requests
            | where timestamp > ago(1h)
            | summarize 
                TotalRequests = count(),
                FailedRequests = countif(success == false),
                ErrorRate = round(countif(success == false) * 100.0 / count(), 2)
                by bin(timestamp, 5m)
            | render timechart
          EOT
          size = 0
          title = "Error Rate Analysis"
          timeContext = {
            durationMs = 3600000
          }
          queryType = 0
          resourceType = "microsoft.insights/components"
          visualization = "timechart"
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = <<-EOT
            requests
            | where timestamp > ago(1h)
            | summarize RequestsPerMinute = count() by bin(timestamp, 1m)
            | render timechart
          EOT
          size = 0
          title = "Throughput (Requests per Minute)"
          timeContext = {
            durationMs = 3600000
          }
          queryType = 0
          resourceType = "microsoft.insights/components"
          visualization = "timechart"
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = <<-EOT
            performanceCounters
            | where timestamp > ago(1h)
            | where category == "Processor" and counter == "% Processor Time"
            | summarize AvgCPU = avg(value) by bin(timestamp, 5m)
            | render timechart
          EOT
          size = 0
          title = "CPU Utilization"
          timeContext = {
            durationMs = 3600000
          }
          queryType = 0
          resourceType = "microsoft.insights/components"
          visualization = "timechart"
        }
      }
    ]
  })
  
  tags = merge(var.tags, {
    Component = "workbook"
    Purpose   = "performance-visualization"
  })
}

# Local values for template rendering
locals {
  load_test_config_content = var.create_sample_load_test ? templatefile("${path.module}/templates/loadtest-config.yaml.tpl", {
    app_url                  = "https://${azurerm_container_app.main.ingress[0].fqdn}"
    response_time_threshold  = var.response_time_threshold_ms
    error_rate_threshold     = var.error_rate_threshold_percent
    test_duration_seconds    = 300
    virtual_users            = 50
    ramp_up_time_seconds     = 60
  }) : ""
  
  jmeter_test_script_content = var.create_sample_load_test ? templatefile("${path.module}/templates/loadtest.jmx.tpl", {
    app_url              = azurerm_container_app.main.ingress[0].fqdn
    virtual_users        = 50
    ramp_up_time_seconds = 60
    test_duration_seconds = 300
  }) : ""
  
  azure_pipeline_content = var.create_sample_load_test ? templatefile("${path.module}/templates/azure-pipelines.yml.tpl", {
    load_test_resource       = azurerm_load_test.main.name
    resource_group_name      = azurerm_resource_group.main.name
    container_app_url        = "https://${azurerm_container_app.main.ingress[0].fqdn}"
    subscription_id          = data.azurerm_subscription.current.subscription_id
  }) : ""
}