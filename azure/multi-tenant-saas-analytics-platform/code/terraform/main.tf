# Main Terraform configuration for Azure multi-tenant SaaS performance and cost analytics solution
# This solution implements Application Insights, Data Explorer, and Cost Management for comprehensive analytics

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Local values for resource naming and tagging
locals {
  # Generate unique resource names with suffix
  resource_group_name        = var.resource_group_name != null ? var.resource_group_name : "rg-${var.solution_name}-${random_string.suffix.result}"
  log_analytics_name         = "la-${var.solution_name}-${random_string.suffix.result}"
  application_insights_name  = "ai-${var.solution_name}-${random_string.suffix.result}"
  data_explorer_cluster_name = "adx-${var.solution_name}-${random_string.suffix.result}"
  data_explorer_database_name = "SaaSAnalytics"
  action_group_name          = "ag-cost-alert-${random_string.suffix.result}"
  budget_name               = "budget-${var.solution_name}-${random_string.suffix.result}"
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment     = var.environment
    Solution        = var.solution_name
    Project         = var.project_name
    CostCenter      = var.cost_center
    Owner           = var.owner
    Purpose         = "saas-analytics"
    TenantEnabled   = "true"
    DeployedBy      = "terraform"
    DeployedAt      = timestamp()
  }, var.additional_tags)
}

# Resource Group for all analytics resources
resource "azurerm_resource_group" "analytics" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for centralized logging and telemetry storage
resource "azurerm_log_analytics_workspace" "analytics" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.analytics.location
  resource_group_name = azurerm_resource_group.analytics.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  daily_quota_gb      = var.log_analytics_daily_quota_gb
  
  tags = merge(local.common_tags, {
    Service = "log-analytics"
    Purpose = "centralized-logging"
  })
}

# Application Insights for application performance monitoring with tenant context
resource "azurerm_application_insights" "analytics" {
  name                = local.application_insights_name
  location            = azurerm_resource_group.analytics.location
  resource_group_name = azurerm_resource_group.analytics.name
  workspace_id        = azurerm_log_analytics_workspace.analytics.id
  application_type    = var.application_insights_type
  sampling_percentage = var.application_insights_sampling_percentage
  
  tags = merge(local.common_tags, {
    Service     = "application-insights"
    Purpose     = "performance-monitoring"
    MultiTenant = "true"
  })
}

# Azure Data Explorer Cluster for advanced analytics and real-time insights
resource "azurerm_kusto_cluster" "analytics" {
  name                         = local.data_explorer_cluster_name
  location                     = azurerm_resource_group.analytics.location
  resource_group_name          = azurerm_resource_group.analytics.name
  public_network_access_enabled = var.enable_public_network_access
  disk_encryption_enabled       = var.disk_encryption_enabled
  streaming_ingestion_enabled   = var.enable_streaming_ingest
  purge_enabled                = var.enable_purge
  double_encryption_enabled     = var.enable_double_encryption
  trusted_external_tenants      = var.trusted_external_tenants
  
  sku {
    name     = var.data_explorer_sku_name
    capacity = var.optimized_auto_scale ? null : var.data_explorer_capacity
  }
  
  # Configure auto-scaling if enabled
  dynamic "optimized_auto_scale" {
    for_each = var.optimized_auto_scale ? [1] : []
    content {
      minimum_instances = var.auto_scale_minimum
      maximum_instances = var.auto_scale_maximum
    }
  }
  
  # Identity configuration for managed identity access
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.common_tags, {
    Service = "data-explorer"
    Purpose = "advanced-analytics"
    Tier    = var.data_explorer_sku_tier
  })
}

# Azure Data Explorer Database for tenant analytics data
resource "azurerm_kusto_database" "analytics" {
  name                = local.data_explorer_database_name
  resource_group_name = azurerm_resource_group.analytics.name
  location            = azurerm_resource_group.analytics.location
  cluster_name        = azurerm_kusto_cluster.analytics.name
  hot_cache_period    = var.data_explorer_hot_cache_period
  soft_delete_period  = var.data_explorer_soft_delete_period
  
  tags = merge(local.common_tags, {
    Service = "data-explorer-database"
    Purpose = "tenant-analytics"
  })
}

# Data Connection from Application Insights to Data Explorer
resource "azurerm_kusto_eventgrid_data_connection" "app_insights" {
  name                = "AppInsightsConnection"
  resource_group_name = azurerm_resource_group.analytics.name
  location            = azurerm_resource_group.analytics.location
  cluster_name        = azurerm_kusto_cluster.analytics.name
  database_name       = azurerm_kusto_database.analytics.name
  
  # Event Hub configuration for streaming data
  eventhub_id                = azurerm_eventhub.analytics.id
  eventhub_consumer_group_id = azurerm_eventhub_consumer_group.analytics.id
  
  # Data format and mapping
  table_name        = "TenantMetrics"
  mapping_rule_name = "TenantMetricsMapping"
  data_format       = "JSON"
  
  depends_on = [
    azurerm_kusto_script.tenant_metrics_table,
    azurerm_eventhub_consumer_group.analytics
  ]
}

# Event Hub Namespace for streaming telemetry data
resource "azurerm_eventhub_namespace" "analytics" {
  name                = "ehns-${var.solution_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.analytics.location
  resource_group_name = azurerm_resource_group.analytics.name
  sku                 = "Standard"
  capacity            = 2
  
  # Enable auto-inflate for scaling
  auto_inflate_enabled     = true
  maximum_throughput_units = 10
  
  tags = merge(local.common_tags, {
    Service = "event-hub"
    Purpose = "telemetry-streaming"
  })
}

# Event Hub for Application Insights telemetry
resource "azurerm_eventhub" "analytics" {
  name                = "eh-app-insights-${random_string.suffix.result}"
  namespace_name      = azurerm_eventhub_namespace.analytics.name
  resource_group_name = azurerm_resource_group.analytics.name
  partition_count     = 4
  message_retention   = 7
  
  # Configure capture for long-term storage
  capture_description {
    enabled             = true
    encoding            = "Avro"
    interval_in_seconds = 300
    size_limit_in_bytes = 314572800
    
    destination {
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.analytics.name
      name                = "EventHubArchive.AzureBlockBlob"
      storage_account_id  = azurerm_storage_account.analytics.id
    }
  }
}

# Event Hub Consumer Group for Data Explorer
resource "azurerm_eventhub_consumer_group" "analytics" {
  name                = "dataexplorer"
  namespace_name      = azurerm_eventhub_namespace.analytics.name
  eventhub_name       = azurerm_eventhub.analytics.name
  resource_group_name = azurerm_resource_group.analytics.name
}

# Storage Account for Event Hub capture and analytics data
resource "azurerm_storage_account" "analytics" {
  name                     = "st${var.solution_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.analytics.name
  location                 = azurerm_resource_group.analytics.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # Security configuration
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Advanced threat protection
  queue_encryption_key_type = "Service"
  table_encryption_key_type = "Service"
  
  tags = merge(local.common_tags, {
    Service = "storage"
    Purpose = "analytics-data"
  })
}

# Storage Container for captured telemetry data
resource "azurerm_storage_container" "analytics" {
  name                  = "telemetry-capture"
  storage_account_name  = azurerm_storage_account.analytics.name
  container_access_type = "private"
}

# Kusto Script to create TenantMetrics table
resource "azurerm_kusto_script" "tenant_metrics_table" {
  name                = "CreateTenantMetricsTable"
  database_id         = azurerm_kusto_database.analytics.id
  continue_on_errors_enabled = false
  force_an_update_when_value_changed = true
  
  script_content = <<-EOT
.create table TenantMetrics (
    Timestamp: datetime,
    TenantId: string,
    MetricName: string,
    MetricValue: real,
    ResourceId: string,
    Location: string,
    CostCenter: string,
    CustomDimensions: dynamic,
    OperationName: string,
    ResultCode: string,
    Duration: real,
    ItemCount: long
)

.create table TenantMetrics ingestion json mapping 'TenantMetricsMapping' '[
    {"column":"Timestamp","path":"$.timestamp","datatype":"datetime"},
    {"column":"TenantId","path":"$.customDimensions.TenantId","datatype":"string"},
    {"column":"MetricName","path":"$.name","datatype":"string"},
    {"column":"MetricValue","path":"$.value","datatype":"real"},
    {"column":"ResourceId","path":"$.cloud.resourceId","datatype":"string"},
    {"column":"Location","path":"$.cloud.location","datatype":"string"},
    {"column":"CostCenter","path":"$.customDimensions.CostCenter","datatype":"string"},
    {"column":"CustomDimensions","path":"$.customDimensions","datatype":"dynamic"},
    {"column":"OperationName","path":"$.operation.name","datatype":"string"},
    {"column":"ResultCode","path":"$.resultCode","datatype":"string"},
    {"column":"Duration","path":"$.duration","datatype":"real"},
    {"column":"ItemCount","path":"$.itemCount","datatype":"long"}
]'
EOT
}

# Kusto Script to create cost analysis function
resource "azurerm_kusto_script" "cost_analysis_function" {
  name                = "CreateCostAnalysisFunction"
  database_id         = azurerm_kusto_database.analytics.id
  continue_on_errors_enabled = false
  force_an_update_when_value_changed = true
  
  script_content = <<-EOT
.create function TenantCostAnalysis(startTime: datetime = ago(30d), endTime: datetime = now()) {
    TenantMetrics
    | where Timestamp between (startTime .. endTime)
    | where isnotempty(TenantId)
    | extend EstimatedCost = case(
        MetricName == "requests", MetricValue * 0.001,
        MetricName == "dependencies", MetricValue * 0.0005,
        MetricName == "exceptions", MetricValue * 0.002,
        MetricName == "pageViews", MetricValue * 0.0001,
        0.0
    )
    | summarize 
        TotalOperations = sum(MetricValue),
        EstimatedTotalCost = sum(EstimatedCost),
        AvgDuration = avg(Duration),
        P95Duration = percentile(Duration, 95),
        FailureRate = countif(ResultCode startswith "4" or ResultCode startswith "5") * 100.0 / count(),
        UniqueOperations = dcount(OperationName)
    by TenantId, bin(Timestamp, 1d)
    | order by Timestamp desc, EstimatedTotalCost desc
}

.create function TenantPerformanceAnalysis(tenantId: string = "", startTime: datetime = ago(24h)) {
    TenantMetrics
    | where Timestamp > startTime
    | where isempty(tenantId) or TenantId == tenantId
    | summarize 
        RequestCount = countif(MetricName == "requests"),
        AvgDuration = avg(Duration),
        P50Duration = percentile(Duration, 50),
        P95Duration = percentile(Duration, 95),
        P99Duration = percentile(Duration, 99),
        FailureRate = countif(ResultCode startswith "4" or ResultCode startswith "5") * 100.0 / count(),
        ExceptionCount = countif(MetricName == "exceptions"),
        DependencyCount = countif(MetricName == "dependencies")
    by TenantId, bin(Timestamp, 1h)
    | order by Timestamp desc
}
EOT

  depends_on = [azurerm_kusto_script.tenant_metrics_table]
}

# Action Group for cost management alerts
resource "azurerm_monitor_action_group" "cost_alerts" {
  name                = local.action_group_name
  resource_group_name = azurerm_resource_group.analytics.name
  short_name          = "CostAlert"
  
  email_receiver {
    name          = "admin"
    email_address = var.budget_alert_email
  }
  
  tags = merge(local.common_tags, {
    Service = "monitor"
    Purpose = "cost-alerting"
  })
}

# Consumption Budget for cost management
resource "azurerm_consumption_budget_resource_group" "analytics" {
  name              = local.budget_name
  resource_group_id = azurerm_resource_group.analytics.id
  
  amount     = var.budget_amount
  time_grain = "Monthly"
  
  time_period {
    start_date = formatdate("YYYY-MM-01'T'hh:mm:ssZ", timestamp())
  }
  
  filter {
    dimension {
      name = "ResourceGroupName"
      values = [azurerm_resource_group.analytics.name]
    }
  }
  
  # Create notifications for each threshold
  dynamic "notification" {
    for_each = var.budget_alert_thresholds
    content {
      enabled   = true
      threshold = notification.value
      operator  = "GreaterThan"
      
      contact_emails = [var.budget_alert_email]
      
      contact_groups = [azurerm_monitor_action_group.cost_alerts.id]
    }
  }
}

# Role assignment for Data Explorer to access Log Analytics
resource "azurerm_role_assignment" "data_explorer_log_analytics" {
  scope                = azurerm_log_analytics_workspace.analytics.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_kusto_cluster.analytics.identity[0].principal_id
}

# Role assignment for Application Insights continuous export
resource "azurerm_role_assignment" "app_insights_eventhub" {
  scope                = azurerm_eventhub.analytics.id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = azurerm_application_insights.analytics.id
}

# Diagnostic settings for Application Insights
resource "azurerm_monitor_diagnostic_setting" "app_insights" {
  name                       = "app-insights-diagnostics"
  target_resource_id         = azurerm_application_insights.analytics.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.analytics.id
  
  enabled_log {
    category = "AppAvailabilityResults"
  }
  
  enabled_log {
    category = "AppBrowserTimings"
  }
  
  enabled_log {
    category = "AppDependencies"
  }
  
  enabled_log {
    category = "AppEvents"
  }
  
  enabled_log {
    category = "AppExceptions"
  }
  
  enabled_log {
    category = "AppMetrics"
  }
  
  enabled_log {
    category = "AppPageViews"
  }
  
  enabled_log {
    category = "AppPerformanceCounters"
  }
  
  enabled_log {
    category = "AppRequests"
  }
  
  enabled_log {
    category = "AppSystemEvents"
  }
  
  enabled_log {
    category = "AppTraces"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Monitor Activity Log Alert for Data Explorer scaling events
resource "azurerm_monitor_activity_log_alert" "data_explorer_scaling" {
  name                = "adx-scaling-alert-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.analytics.name
  scopes              = [azurerm_kusto_cluster.analytics.id]
  description         = "Alert when Data Explorer cluster scales up or down"
  
  criteria {
    resource_id    = azurerm_kusto_cluster.analytics.id
    operation_name = "Microsoft.Kusto/clusters/write"
    category       = "Administrative"
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.cost_alerts.id
  }
  
  tags = local.common_tags
}