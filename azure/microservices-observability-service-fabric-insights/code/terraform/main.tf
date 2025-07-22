# Main Terraform configuration for Azure Service Fabric and Application Insights monitoring solution

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  resource_suffix = random_id.suffix.hex
  
  # Resource names with unique suffix
  resource_group_name        = "${var.resource_group_name}-${local.resource_suffix}"
  app_insights_name         = "${var.app_insights_name}-${local.resource_suffix}"
  log_analytics_name        = "${var.log_analytics_name}-${local.resource_suffix}"
  event_hub_namespace_name  = "${var.event_hub_namespace_name}-${local.resource_suffix}"
  sf_cluster_name           = "${var.sf_cluster_name}-${local.resource_suffix}"
  function_app_name         = "${var.function_app_name}-${local.resource_suffix}"
  storage_account_name      = "${var.storage_account_name}${local.resource_suffix}"
  service_plan_name         = "${var.function_app_service_plan_name}-${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(var.tags, {
    "terraform"    = "true"
    "created-date" = formatdate("YYYY-MM-DD", timestamp())
    "environment"  = var.environment
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

# Application Insights
resource "azurerm_application_insights" "main" {
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.app_insights_type
  
  tags = local.common_tags
}

# Event Hub Namespace
resource "azurerm_eventhub_namespace" "main" {
  name                     = local.event_hub_namespace_name
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  sku                      = var.event_hub_namespace_sku
  capacity                 = var.event_hub_namespace_capacity
  auto_inflate_enabled     = var.event_hub_auto_inflate_enabled
  maximum_throughput_units = var.event_hub_maximum_throughput_units
  
  tags = local.common_tags
}

# Event Hub
resource "azurerm_eventhub" "service_events" {
  name                = var.event_hub_name
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = var.event_hub_partition_count
  message_retention   = var.event_hub_message_retention
}

# Event Hub Authorization Rule for Functions
resource "azurerm_eventhub_authorization_rule" "function_app" {
  name                = "function-app-access"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.service_events.name
  resource_group_name = azurerm_resource_group.main.name
  
  listen = true
  send   = true
  manage = false
}

# Storage Account for Function App
resource "azurerm_storage_account" "function_app" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Enable secure transfer and blob versioning
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Service Plan for Function App (Consumption Plan)
resource "azurerm_service_plan" "function_app" {
  name                = local.service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1"
  
  tags = local.common_tags
}

# Function App
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.function_app.id
  
  storage_account_name       = azurerm_storage_account.function_app.name
  storage_account_access_key = azurerm_storage_account.function_app.primary_access_key
  
  functions_extension_version = "~${var.function_app_functions_version}"
  
  site_config {
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    
    application_stack {
      node_version = var.function_app_runtime_version
    }
    
    # Enable remote debugging and detailed errors for troubleshooting
    remote_debugging_enabled = false
    detailed_error_logging_enabled = true
    
    # CORS settings
    cors {
      allowed_origins = ["*"]
    }
  }
  
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"                   = var.function_app_runtime
    "WEBSITE_NODE_DEFAULT_VERSION"               = "~${var.function_app_runtime_version}"
    "APPINSIGHTS_INSTRUMENTATIONKEY"             = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING"      = azurerm_application_insights.main.connection_string
    "EventHubConnectionString"                   = azurerm_eventhub_authorization_rule.function_app.primary_connection_string
    "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
    "FUNCTIONS_EXTENSION_VERSION"                = "~${var.function_app_functions_version}"
    "WEBSITE_RUN_FROM_PACKAGE"                   = "1"
    
    # Additional settings for monitoring and performance
    "APPINSIGHTS_SAMPLING_PERCENTAGE" = "100"
    "APPINSIGHTS_PROFILERFEATURE_VERSION" = "1.0.0"
    "APPINSIGHTS_SNAPSHOTFEATURE_VERSION" = "1.0.0"
    "DiagnosticServices_EXTENSION_VERSION" = "~3"
    "InstrumentationEngine_EXTENSION_VERSION" = "disabled"
    "SnapshotDebugger_EXTENSION_VERSION" = "disabled"
    "XDT_MicrosoftApplicationInsights_BaseExtensions" = "disabled"
    "XDT_MicrosoftApplicationInsights_Mode" = "recommended"
    "XDT_MicrosoftApplicationInsights_PreemptSdk" = "disabled"
    "APPLICATIONINSIGHTS_ENABLE_AGENT" = "true"
  }
  
  tags = local.common_tags
}

# Service Fabric Managed Cluster
resource "azurerm_service_fabric_managed_cluster" "main" {
  name                = local.sf_cluster_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  sku = var.sf_cluster_sku
  
  http_gateway_port         = var.sf_http_gateway_port
  client_connection_port    = var.sf_client_connection_port
  dns_name                  = "${local.sf_cluster_name}.${azurerm_resource_group.main.location}.cloudapp.azure.com"
  
  # Authentication configuration
  authentication {
    certificate {
      thumbprint      = "example-thumbprint"
      type            = "ClientCertificate"
      common_name     = "example.com"
    }
  }
  
  tags = local.common_tags
  
  # Enable backup and monitoring
  backup_service_enabled = true
  dns_service_enabled    = true
  
  # Custom fabric settings for monitoring
  custom_fabric_setting {
    section   = "Diagnostics"
    parameter = "ConsumerInstances"
    value     = "1"
  }
  
  custom_fabric_setting {
    section   = "Diagnostics"
    parameter = "ProducerInstances"
    value     = "1"
  }
  
  # Enable diagnostics
  custom_fabric_setting {
    section   = "Diagnostics"
    parameter = "EnableTelemetry"
    value     = "true"
  }
}

# Add node type to Service Fabric cluster
resource "azurerm_service_fabric_managed_cluster_node_type" "primary" {
  name                 = "primary"
  service_fabric_managed_cluster_id = azurerm_service_fabric_managed_cluster.main.id
  primary              = true
  vm_size              = "Standard_D2s_v3"
  vm_instance_count    = 3
  
  # Enable auto-scaling
  auto_scale_rule {
    name                = "scale-out"
    metric_name         = "Percentage CPU"
    time_grain          = "PT1M"
    statistic           = "Average"
    time_window         = "PT5M"
    time_aggregation    = "Average"
    operator            = "GreaterThan"
    threshold           = 70
    direction           = "Increase"
    type                = "ChangeCount"
    value               = 1
    cooldown            = "PT10M"
  }
  
  auto_scale_rule {
    name                = "scale-in"
    metric_name         = "Percentage CPU"
    time_grain          = "PT1M"
    statistic           = "Average"
    time_window         = "PT5M"
    time_aggregation    = "Average"
    operator            = "LessThan"
    threshold           = 30
    direction           = "Decrease"
    type                = "ChangeCount"
    value               = 1
    cooldown            = "PT10M"
  }
  
  # VM extensions for monitoring
  vm_extension {
    name                 = "MicrosoftMonitoringAgent"
    publisher            = "Microsoft.EnterpriseCloud.Monitoring"
    type                 = "MicrosoftMonitoringAgent"
    type_handler_version = "1.0"
    auto_upgrade_minor_version = true
    
    settings = jsonencode({
      workspaceId = azurerm_log_analytics_workspace.main.workspace_id
    })
    
    protected_settings = jsonencode({
      workspaceKey = azurerm_log_analytics_workspace.main.primary_shared_key
    })
  }
}

# Diagnostic Settings for Service Fabric Cluster
resource "azurerm_monitor_diagnostic_setting" "sf_cluster" {
  name                       = var.diagnostic_setting_name
  target_resource_id         = azurerm_service_fabric_managed_cluster.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable operational channel logs
  enabled_log {
    category = "OperationalChannel"
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
  
  # Enable reliable service actor channel logs
  enabled_log {
    category = "ReliableServiceActorChannel"
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
  
  # Enable all metrics
  metric {
    category = "AllMetrics"
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
}

# Action Group for Alerts
resource "azurerm_monitor_action_group" "main" {
  name                = "ag-microservices-monitoring"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "sf-alerts"
  
  # Email notifications
  email_receiver {
    name          = "admin-email"
    email_address = "admin@example.com"
  }
  
  # SMS notifications
  sms_receiver {
    name         = "admin-sms"
    country_code = "1"
    phone_number = "1234567890"
  }
  
  # Webhook notifications
  webhook_receiver {
    name        = "webhook-alert"
    service_uri = "https://example.com/webhook"
  }
  
  tags = local.common_tags
}

# Metric Alert for Service Fabric Cluster Health
resource "azurerm_monitor_metric_alert" "cluster_health" {
  name                = var.metric_alert_name
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_service_fabric_managed_cluster.main.id]
  description         = "Alert when Service Fabric cluster health degrades"
  severity            = var.alert_severity
  frequency           = var.alert_evaluation_frequency
  window_size         = var.alert_window_size
  
  criteria {
    metric_namespace = "Microsoft.ServiceFabric/managedClusters"
    metric_name      = "ClusterHealthState"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 3
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  tags = local.common_tags
}

# Scheduled Query Alert for High Error Rate
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "high_error_rate" {
  name                = var.query_alert_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  evaluation_frequency = var.alert_evaluation_frequency
  window_duration      = var.alert_window_size
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = var.alert_severity
  
  criteria {
    query                   = <<-QUERY
      exceptions
      | where timestamp > ago(5m)
      | summarize count()
    QUERY
    time_aggregation_method = "Count"
    threshold               = var.error_threshold
    operator                = "GreaterThan"
    
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }
  
  action {
    action_groups = [azurerm_monitor_action_group.main.id]
  }
  
  tags = local.common_tags
}

# Wait for Service Fabric cluster to be ready
resource "time_sleep" "wait_for_sf_cluster" {
  depends_on = [azurerm_service_fabric_managed_cluster.main]
  
  create_duration = "5m"
}

# Azure Dashboard for Monitoring
resource "azurerm_dashboard" "main" {
  name                = var.dashboard_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  tags = local.common_tags
  
  dashboard_properties = jsonencode({
    lenses = {
      "0" = {
        order = 0
        parts = {
          "0" = {
            position = {
              x        = 0
              y        = 0
              colSpan  = 6
              rowSpan  = 4
            }
            metadata = {
              inputs = [{
                name = "resourceGroup"
                value = azurerm_resource_group.main.name
              }]
              type = "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
              settings = {
                content = {
                  chartTitle = "Service Fabric Cluster Health"
                  visualization = {
                    chartType = "lineChart"
                  }
                }
              }
            }
          }
          "1" = {
            position = {
              x        = 6
              y        = 0
              colSpan  = 6
              rowSpan  = 4
            }
            metadata = {
              inputs = [{
                name = "resourceGroup"
                value = azurerm_resource_group.main.name
              }]
              type = "Extension/Microsoft_Azure_Monitoring/PartType/LogsDashboardPart"
              settings = {
                content = {
                  gridColumnsWidth = {
                    timestamp = "150px"
                    message   = "auto"
                  }
                  query = "traces | where timestamp > ago(1h) | order by timestamp desc"
                }
              }
            }
          }
          "2" = {
            position = {
              x        = 0
              y        = 4
              colSpan  = 12
              rowSpan  = 4
            }
            metadata = {
              inputs = [{
                name = "resourceGroup"
                value = azurerm_resource_group.main.name
              }]
              type = "Extension/Microsoft_Azure_Monitoring/PartType/LogsDashboardPart"
              settings = {
                content = {
                  gridColumnsWidth = {
                    timestamp = "150px"
                    name      = "200px"
                    target    = "200px"
                    count_    = "100px"
                  }
                  query = "dependencies | where timestamp > ago(1h) | summarize count() by cloud_RoleName, name, target | order by count_ desc"
                }
              }
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
        }
      }
    }
  })
}

# Log Analytics Solutions for enhanced monitoring
resource "azurerm_log_analytics_solution" "service_fabric" {
  solution_name         = "ServiceFabric"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  workspace_name        = azurerm_log_analytics_workspace.main.name
  
  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ServiceFabric"
  }
  
  tags = local.common_tags
}

resource "azurerm_log_analytics_solution" "application_insights" {
  solution_name         = "ApplicationInsights"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  workspace_name        = azurerm_log_analytics_workspace.main.name
  
  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ApplicationInsights"
  }
  
  tags = local.common_tags
}