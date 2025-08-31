# Azure Resource Monitoring Dashboard with Workbooks
# This Terraform configuration creates a comprehensive monitoring solution using Azure Monitor Workbooks

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and tagging
locals {
  # Generate unique names if not provided
  resource_group_name           = var.resource_group_name != "" ? var.resource_group_name : "rg-monitoring-${random_string.suffix.result}"
  log_analytics_workspace_name  = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "log-workspace-${random_string.suffix.result}"
  storage_account_name         = var.storage_account_name != "" ? var.storage_account_name : "stor${random_string.suffix.result}"
  app_service_plan_name        = var.app_service_plan_name != "" ? var.app_service_plan_name : "asp-monitoring-${random_string.suffix.result}"
  web_app_name                 = var.web_app_name != "" ? var.web_app_name : "webapp-monitoring-${random_string.suffix.result}"
  
  # Common tags applied to all resources
  common_tags = {
    Environment     = var.environment
    Purpose         = var.purpose
    Owner          = var.owner
    ManagedBy      = "terraform"
    LastUpdated    = formatdate("YYYY-MM-DD", timestamp())
    ResourceGroup  = local.resource_group_name
  }
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create the main resource group for all monitoring resources
resource "azurerm_resource_group" "monitoring" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Log Analytics Workspace for centralized logging and monitoring
# This workspace collects and analyzes data from all Azure resources
resource "azurerm_log_analytics_workspace" "monitoring" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.monitoring.location
  resource_group_name = azurerm_resource_group.monitoring.name
  
  # Configure workspace pricing and retention
  sku               = var.log_analytics_sku
  retention_in_days = var.log_analytics_retention_days
  
  # Enable daily data cap (optional - helps control costs)
  daily_quota_gb = var.log_analytics_sku == "Free" ? 0.5 : -1
  
  tags = merge(local.common_tags, {
    ResourceType = "LogAnalytics"
    Purpose      = "CentralizedLogging"
  })
}

# Create Storage Account for demonstration and monitoring
# This generates storage metrics that will be visualized in the workbook
resource "azurerm_storage_account" "demo" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.monitoring.name
  location                 = azurerm_resource_group.monitoring.location
  
  # Storage account configuration
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind            = "StorageV2"
  
  # Enable blob versioning and change feed for monitoring
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    # Configure blob lifecycle management
    delete_retention_policy {
      days = 7
    }
  }
  
  tags = merge(local.common_tags, {
    ResourceType = "Storage"
    Purpose      = "DemoResource"
  })
}

# Create App Service Plan for web application hosting
resource "azurerm_service_plan" "demo" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location
  
  # Configure the service plan SKU
  os_type  = "Linux"
  sku_name = var.app_service_plan_sku_size
  
  tags = merge(local.common_tags, {
    ResourceType = "AppServicePlan"
    Purpose      = "DemoResource"
  })
}

# Create Web App for demonstration and monitoring
# This generates application metrics that will be visualized in the workbook
resource "azurerm_linux_web_app" "demo" {
  name                = local.web_app_name
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location
  service_plan_id     = azurerm_service_plan.demo.id
  
  # Configure web app settings
  site_config {
    # Use a simple Node.js runtime for demonstration
    application_stack {
      node_version = "18-lts"
    }
    
    # Enable application logging
    application_logs {
      file_system_level = "Information"
    }
    
    # Configure HTTP logging
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }
  
  # Configure app settings for monitoring
  app_settings = {
    "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.monitoring.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.monitoring.connection_string
  }
  
  tags = merge(local.common_tags, {
    ResourceType = "WebApp"
    Purpose      = "DemoResource"
  })
}

# Create Application Insights for application performance monitoring
resource "azurerm_application_insights" "monitoring" {
  name                = "appi-monitoring-${random_string.suffix.result}"
  location            = azurerm_resource_group.monitoring.location
  resource_group_name = azurerm_resource_group.monitoring.name
  
  # Link to Log Analytics workspace
  workspace_id     = azurerm_log_analytics_workspace.monitoring.id
  application_type = "web"
  
  tags = merge(local.common_tags, {
    ResourceType = "ApplicationInsights"
    Purpose      = "ApplicationMonitoring"
  })
}

# Enable diagnostic settings for Storage Account (if enabled)
resource "azurerm_monitor_diagnostic_setting" "storage_diagnostics" {
  count              = var.enable_diagnostic_settings ? 1 : 0
  name               = "storage-diagnostics"
  target_resource_id = azurerm_storage_account.demo.id
  
  # Send logs and metrics to Log Analytics workspace
  log_analytics_workspace_id = azurerm_log_analytics_workspace.monitoring.id
  
  # Enable storage account metrics
  enabled_log {
    category = "StorageRead"
  }
  
  enabled_log {
    category = "StorageWrite"
  }
  
  enabled_log {
    category = "StorageDelete"
  }
  
  # Enable all available metrics
  metric {
    category = "Transaction"
    enabled  = true
  }
  
  metric {
    category = "Capacity"
    enabled  = true
  }
}

# Enable diagnostic settings for Web App (if enabled)
resource "azurerm_monitor_diagnostic_setting" "webapp_diagnostics" {
  count              = var.enable_diagnostic_settings ? 1 : 0
  name               = "webapp-diagnostics"
  target_resource_id = azurerm_linux_web_app.demo.id
  
  # Send logs and metrics to Log Analytics workspace
  log_analytics_workspace_id = azurerm_log_analytics_workspace.monitoring.id
  
  # Enable web app logs
  enabled_log {
    category = "AppServiceHTTPLogs"
  }
  
  enabled_log {
    category = "AppServiceConsoleLogs"
  }
  
  enabled_log {
    category = "AppServiceAppLogs"
  }
  
  enabled_log {
    category = "AppServiceAuditLogs"
  }
  
  # Enable web app metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create Azure Monitor Workbook with pre-configured monitoring queries
resource "azurerm_template_deployment" "workbook" {
  count               = var.enable_workbook_creation ? 1 : 0
  name                = "monitoring-workbook-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.monitoring.name
  deployment_mode     = "Incremental"
  
  # ARM template for creating the workbook (as Terraform doesn't have native workbook resource)
  template_body = jsonencode({
    "$schema" = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    "contentVersion" = "1.0.0.0"
    "parameters" = {}
    "variables" = {}
    "resources" = [
      {
        "type" = "microsoft.insights/workbooks"
        "apiVersion" = "2022-04-01"
        "name" = "[newGuid()]"
        "location" = var.location
        "kind" = "shared"
        "properties" = {
          "displayName" = var.workbook_display_name
          "serializedData" = jsonencode({
            "version" = "Notebook/1.0"
            "items" = [
              {
                "type" = 1
                "content" = {
                  "json" = "# ${var.workbook_display_name}\n\nThis workbook provides comprehensive monitoring for Azure resources including health status, performance metrics, and cost analysis.\n\n---"
                }
                "name" = "title-text"
              }
              {
                "type" = 3
                "content" = {
                  "version" = "KqlItem/1.0"
                  "query" = "AzureActivity\n| where TimeGenerated >= ago(1h)\n| where ActivityStatusValue in (\"Success\", \"Failed\", \"Warning\")\n| summarize \n    SuccessfulOperations = countif(ActivityStatusValue == \"Success\"),\n    FailedOperations = countif(ActivityStatusValue == \"Failed\"),\n    WarningOperations = countif(ActivityStatusValue == \"Warning\"),\n    TotalOperations = count()\n| extend HealthPercentage = round((SuccessfulOperations * 100.0) / TotalOperations, 1)\n| project SuccessfulOperations, FailedOperations, WarningOperations, TotalOperations, HealthPercentage"
                  "size" = 3
                  "title" = "Resource Health Overview (Last Hour)"
                  "queryType" = 0
                  "visualization" = "tiles"
                  "tileSettings" = {
                    "titleContent" = {
                      "columnMatch" = "HealthPercentage"
                      "formatter" = 12
                      "formatOptions" = {
                        "palette" = "greenRed"
                        "aggregation" = "Sum"
                      }
                    }
                    "subtitleContent" = {
                      "columnMatch" = "TotalOperations"
                      "formatter" = 1
                    }
                  }
                }
                "name" = "resource-health-query"
              }
              {
                "type" = 3
                "content" = {
                  "version" = "KqlItem/1.0"
                  "query" = "AzureMetrics\n| where TimeGenerated >= ago(4h)\n| where MetricName in (\"Transactions\", \"Availability\", \"SuccessE2ELatency\")\n| summarize \n    AvgTransactions = avg(Average),\n    AvgAvailability = avg(Average),\n    AvgLatency = avg(Average)\nby Resource, MetricName, bin(TimeGenerated, 15m)\n| render timechart"
                  "size" = 0
                  "title" = "Performance Metrics (Last 4 Hours)"
                  "queryType" = 0
                  "visualization" = "linechart"
                }
                "name" = "performance-metrics-query"
              }
              {
                "type" = 3
                "content" = {
                  "version" = "KqlItem/1.0"
                  "query" = "Resources\n| where subscriptionId =~ '${data.azurerm_client_config.current.subscription_id}'\n| where resourceGroup =~ '${azurerm_resource_group.monitoring.name}'\n| extend EstimatedMonthlyCost = case(\n    type contains \"Microsoft.Storage\", 5.0,\n    type contains \"Microsoft.Web/sites\", 10.0,\n    type contains \"Microsoft.Web/serverfarms\", 15.0,\n    type contains \"Microsoft.OperationalInsights\", 20.0,\n    type contains \"Microsoft.Insights\", 8.0,\n    1.0)\n| project name, type, location, resourceGroup, EstimatedMonthlyCost\n| order by EstimatedMonthlyCost desc"
                  "size" = 0
                  "title" = "Resource Cost Analysis"
                  "queryType" = 1
                  "visualization" = "table"
                }
                "name" = "cost-analysis-query"
              }
            ]
            "isLocked" = false
            "fallbackResourceIds" = [
              "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.monitoring.name}"
            ]
          })
          "category" = "workbook"
          "sourceId" = azurerm_log_analytics_workspace.monitoring.id
        }
        "tags" = local.common_tags
      }
    ]
  })
  
  depends_on = [
    azurerm_log_analytics_workspace.monitoring,
    azurerm_storage_account.demo,
    azurerm_linux_web_app.demo
  ]
}

# Create a storage container for demonstration
resource "azurerm_storage_container" "demo" {
  name                  = "monitoring-demo"
  storage_account_name  = azurerm_storage_account.demo.name
  container_access_type = "private"
}