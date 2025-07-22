# Main Terraform configuration for Azure Real-Time Geospatial Analytics
# This file defines the complete infrastructure for a fleet management
# analytics solution using Azure Maps and Azure Stream Analytics

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Combine default and additional tags
locals {
  common_tags = merge(var.default_tags, var.additional_tags, {
    Environment = var.environment
    Project     = var.project_name
  })
  
  # Resource naming with random suffix
  resource_suffix = random_string.suffix.result
  
  # Geofence polygon for Stream Analytics query
  geofence_points = join(", ", [
    for point in var.default_geofence_coordinates :
    "CreatePoint(${point.longitude}, ${point.latitude})"
  ])
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${local.resource_suffix}"
  location = var.location
  tags     = local.common_tags
}

# Storage Account for Stream Analytics and archive data
resource "azurerm_storage_account" "main" {
  name                = "st${replace(var.project_name, "-", "")}${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Storage configuration
  account_tier              = var.storage_account_tier
  account_replication_type  = var.storage_account_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  # Security settings
  enable_https_traffic_only      = true
  min_tls_version               = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Blob properties
  blob_properties {
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "HEAD"]
      allowed_origins    = ["*"]
      exposed_headers    = ["*"]
      max_age_in_seconds = 200
    }
    
    delete_retention_policy {
      days = var.backup_retention_days
    }
    
    container_delete_retention_policy {
      days = var.backup_retention_days
    }
  }
  
  tags = local.common_tags
}

# Storage containers for different data types
resource "azurerm_storage_container" "telemetry_archive" {
  name                  = "telemetry-archive"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "geofences" {
  name                  = "geofences"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Event Hub Namespace for location data ingestion
resource "azurerm_eventhub_namespace" "main" {
  name                = "ehns-${var.project_name}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Event Hub configuration
  sku                         = var.eventhub_namespace_sku
  capacity                    = var.eventhub_namespace_capacity
  auto_inflate_enabled        = var.eventhub_namespace_sku == "Standard"
  maximum_throughput_units    = var.eventhub_namespace_sku == "Standard" ? 20 : null
  
  # Network security
  public_network_access_enabled = !var.enable_private_endpoints
  
  # Enable zone redundancy for higher availability
  zone_redundant = var.eventhub_namespace_sku != "Basic"
  
  tags = local.common_tags
}

# Event Hub for vehicle location data
resource "azurerm_eventhub" "vehicle_locations" {
  name                = "vehicle-locations"
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  
  # Event Hub configuration
  partition_count   = var.eventhub_partition_count
  message_retention = var.eventhub_message_retention
  
  # Capture configuration for archival
  capture_description {
    enabled  = true
    encoding = "Avro"
    
    # Capture to storage account
    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "vehicles/{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.telemetry_archive.name
      storage_account_id  = azurerm_storage_account.main.id
    }
    
    # Capture frequency
    interval_in_seconds = 300
    size_limit_in_bytes = 314572800
  }
}

# Event Hub Authorization Rule for Stream Analytics
resource "azurerm_eventhub_authorization_rule" "stream_analytics" {
  name                = "stream-analytics-rule"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.vehicle_locations.name
  resource_group_name = azurerm_resource_group.main.name
  
  # Permissions
  listen = true
  send   = false
  manage = false
}

# Consumer Group for Stream Analytics
resource "azurerm_eventhub_consumer_group" "stream_analytics" {
  name                = "stream-analytics-consumer"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.vehicle_locations.name
  resource_group_name = azurerm_resource_group.main.name
  
  user_metadata = "Stream Analytics consumer group for geospatial processing"
}

# Cosmos DB Account for real-time data storage
resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-${var.project_name}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Database configuration
  offer_type                    = "Standard"
  kind                         = "GlobalDocumentDB"
  enable_automatic_failover    = var.cosmos_db_enable_automatic_failover
  enable_multiple_write_locations = var.cosmos_db_enable_multiple_write_locations
  
  # Consistency policy
  consistency_policy {
    consistency_level       = var.cosmos_db_consistency_level
    max_interval_in_seconds = var.cosmos_db_max_interval_in_seconds
    max_staleness_prefix    = var.cosmos_db_max_staleness_prefix
  }
  
  # Geo-location configuration
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
    zone_redundant    = false
  }
  
  # Backup configuration
  backup {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = var.backup_retention_days * 24
  }
  
  # Security settings
  public_network_access_enabled = !var.enable_private_endpoints
  
  # IP filtering
  dynamic "ip_range_filter" {
    for_each = var.allowed_ip_ranges
    content {
      ip_range_filter = ip_range_filter.value
    }
  }
  
  tags = local.common_tags
}

# Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "fleet_analytics" {
  name                = "FleetAnalytics"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  
  # Throughput configuration
  throughput = var.cosmos_db_throughput
}

# Cosmos DB Container for location events
resource "azurerm_cosmosdb_sql_container" "location_events" {
  name                = "LocationEvents"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.fleet_analytics.name
  
  # Container configuration
  partition_key_path = "/vehicleId"
  
  # Indexing policy for geospatial queries
  indexing_policy {
    indexing_mode = "consistent"
    
    # Include all paths for flexible querying
    included_path {
      path = "/*"
    }
    
    # Exclude paths that don't need indexing
    excluded_path {
      path = "/\"_etag\"/?"
    }
    
    # Spatial indexes for geospatial queries
    spatial_index {
      path  = "/location/coordinates/?"
      types = ["Point", "LineString", "Polygon", "MultiPolygon"]
    }
  }
  
  # TTL for automatic data cleanup (optional)
  default_ttl = 2592000  # 30 days
  
  # Unique key for preventing duplicate events
  unique_key {
    paths = ["/vehicleId", "/timestamp"]
  }
}

# Azure Maps Account for visualization and mapping services
resource "azurerm_maps_account" "main" {
  name                = "maps-${var.project_name}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  
  # Maps configuration
  sku_name = var.azure_maps_sku
  kind     = var.azure_maps_kind
  
  tags = local.common_tags
}

# Stream Analytics Job for real-time geospatial processing
resource "azurerm_stream_analytics_job" "main" {
  name                = "asa-${var.project_name}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Stream Analytics configuration
  streaming_units                     = var.stream_analytics_streaming_units
  transformation_query               = local.stream_analytics_query
  output_error_policy                = var.stream_analytics_output_error_policy
  events_out_of_order_policy         = "Adjust"
  events_out_of_order_max_delay_in_seconds = var.stream_analytics_events_out_of_order_max_delay
  events_late_arrival_max_delay_in_seconds = var.stream_analytics_events_late_arrival_max_delay
  
  # Job configuration
  data_locale        = "en-US"
  compatibility_level = "1.2"
  
  tags = local.common_tags
}

# Stream Analytics Input from Event Hub
resource "azurerm_stream_analytics_stream_input_eventhub" "vehicle_input" {
  name                         = "VehicleInput"
  stream_analytics_job_name    = azurerm_stream_analytics_job.main.name
  resource_group_name          = azurerm_resource_group.main.name
  
  # Event Hub connection details
  eventhub_consumer_group_name = azurerm_eventhub_consumer_group.stream_analytics.name
  eventhub_name                = azurerm_eventhub.vehicle_locations.name
  servicebus_namespace         = azurerm_eventhub_namespace.main.name
  shared_access_policy_key     = azurerm_eventhub_authorization_rule.stream_analytics.primary_key
  shared_access_policy_name    = azurerm_eventhub_authorization_rule.stream_analytics.name
  
  # Serialization configuration
  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

# Stream Analytics Output to Cosmos DB
resource "azurerm_stream_analytics_output_cosmosdb" "vehicle_output" {
  name                      = "VehicleOutput"
  stream_analytics_job_name = azurerm_stream_analytics_job.main.name
  resource_group_name       = azurerm_resource_group.main.name
  
  # Cosmos DB connection details
  cosmosdb_account_key = azurerm_cosmosdb_account.main.primary_key
  cosmosdb_database    = azurerm_cosmosdb_sql_database.fleet_analytics.name
  cosmosdb_container   = azurerm_cosmosdb_sql_container.location_events.name
  document_id          = "id"
  
  # Partitioning
  partition_key = "vehicleId"
}

# Stream Analytics Output to Blob Storage for archival
resource "azurerm_stream_analytics_output_blob" "archive_output" {
  name                      = "ArchiveOutput"
  stream_analytics_job_name = azurerm_stream_analytics_job.main.name
  resource_group_name       = azurerm_resource_group.main.name
  
  # Storage account connection
  storage_account_name = azurerm_storage_account.main.name
  storage_account_key  = azurerm_storage_account.main.primary_access_key
  storage_container_name = azurerm_storage_container.telemetry_archive.name
  
  # Path pattern for time-based partitioning
  path_pattern = "vehicles/{date}/{time}"
  date_format  = "yyyy/MM/dd"
  time_format  = "HH"
  
  # Serialization configuration
  serialization {
    type     = "Json"
    encoding = "UTF8"
    format   = "LineSeparated"
  }
}

# Stream Analytics Query for geospatial processing
locals {
  stream_analytics_query = <<-EOT
    WITH GeofencedData AS (
        SELECT
            vehicleId,
            location,
            speed,
            timestamp,
            ST_WITHIN(
                CreatePoint(CAST(location.longitude AS float), 
                          CAST(location.latitude AS float)),
                CreatePolygon(
                    ${local.geofence_points}
                )
            ) AS isInZone,
            ST_DISTANCE(
                CreatePoint(CAST(location.longitude AS float), 
                          CAST(location.latitude AS float)),
                CreatePoint(${var.depot_location.longitude}, ${var.depot_location.latitude})
            ) AS distanceFromDepot,
            System.Timestamp() AS ProcessingTime
        FROM VehicleInput
        WHERE location IS NOT NULL
          AND location.longitude IS NOT NULL
          AND location.latitude IS NOT NULL
    )
    SELECT
        vehicleId,
        location,
        speed,
        timestamp,
        ProcessingTime,
        isInZone,
        distanceFromDepot,
        CASE 
            WHEN speed > ${var.speed_limit_threshold} THEN 'Speeding Alert'
            WHEN isInZone = 0 THEN 'Outside Geofence'
            WHEN distanceFromDepot > 50000 THEN 'Far from Depot'
            ELSE 'Normal'
        END AS alertType,
        UDF.generateId() AS id
    INTO VehicleOutput
    FROM GeofencedData;
    
    -- Archive all events for historical analysis
    SELECT 
        vehicleId,
        location,
        speed,
        timestamp,
        System.Timestamp() AS ProcessingTime
    INTO ArchiveOutput
    FROM VehicleInput
    WHERE location IS NOT NULL;
  EOT
}

# User-Defined Function for generating unique IDs
resource "azurerm_stream_analytics_function_javascript_udf" "generate_id" {
  name                      = "generateId"
  stream_analytics_job_name = azurerm_stream_analytics_job.main.name
  resource_group_name       = azurerm_resource_group.main.name
  
  script = <<-EOT
    function main() {
        return Math.random().toString(36).substring(2, 15) + 
               Math.random().toString(36).substring(2, 15);
    }
  EOT
  
  input {
    type = "any"
  }
  
  output {
    type = "nvarchar(max)"
  }
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "law-${var.project_name}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Workspace configuration
  sku               = "PerGB2018"
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "ai-${var.project_name}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Application Insights configuration
  application_type    = "web"
  workspace_id       = azurerm_log_analytics_workspace.main[0].id
  retention_in_days  = var.log_retention_days
  
  tags = local.common_tags
}

# Diagnostic Settings for Event Hub
resource "azurerm_monitor_diagnostic_setting" "eventhub" {
  count              = var.enable_diagnostic_logs && var.enable_monitoring ? 1 : 0
  name               = "eventhub-diagnostics"
  target_resource_id = azurerm_eventhub_namespace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  # Enable logs
  enabled_log {
    category = "ArchiveLogs"
  }
  
  enabled_log {
    category = "AutoScaleLogs"
  }
  
  enabled_log {
    category = "CustomerManagedKeyUserLogs"
  }
  
  enabled_log {
    category = "EventHubVNetConnectionEvent"
  }
  
  enabled_log {
    category = "KafkaCoordinatorLogs"
  }
  
  enabled_log {
    category = "KafkaUserErrorLogs"
  }
  
  enabled_log {
    category = "OperationalLogs"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic Settings for Stream Analytics
resource "azurerm_monitor_diagnostic_setting" "stream_analytics" {
  count              = var.enable_diagnostic_logs && var.enable_monitoring ? 1 : 0
  name               = "stream-analytics-diagnostics"
  target_resource_id = azurerm_stream_analytics_job.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  # Enable logs
  enabled_log {
    category = "Execution"
  }
  
  enabled_log {
    category = "Authoring"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic Settings for Cosmos DB
resource "azurerm_monitor_diagnostic_setting" "cosmosdb" {
  count              = var.enable_diagnostic_logs && var.enable_monitoring ? 1 : 0
  name               = "cosmosdb-diagnostics"
  target_resource_id = azurerm_cosmosdb_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  # Enable logs
  enabled_log {
    category = "DataPlaneRequests"
  }
  
  enabled_log {
    category = "QueryRuntimeStatistics"
  }
  
  enabled_log {
    category = "PartitionKeyStatistics"
  }
  
  enabled_log {
    category = "PartitionKeyRUConsumption"
  }
  
  enabled_log {
    category = "ControlPlaneRequests"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Action Group for alerts
resource "azurerm_monitor_action_group" "fleet_alerts" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "fleet-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "FleetOps"
  
  # Email notifications (can be extended with webhook, SMS, etc.)
  email_receiver {
    name          = "fleet-ops-email"
    email_address = "fleet-ops@example.com"
  }
  
  tags = local.common_tags
}

# Metric Alert for high processing latency
resource "azurerm_monitor_metric_alert" "high_latency" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "high-processing-latency"
  resource_group_name = azurerm_resource_group.main.name
  
  # Alert configuration
  description  = "Alert when Stream Analytics processing latency exceeds threshold"
  severity     = 2
  frequency    = "PT1M"
  window_size  = "PT5M"
  
  # Scope - Stream Analytics job
  scopes = [azurerm_stream_analytics_job.main.id]
  
  # Criteria
  criteria {
    metric_namespace = "Microsoft.StreamAnalytics/StreamingJobs"
    metric_name      = "OutputWatermarkDelaySeconds"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 10
  }
  
  # Action
  action {
    action_group_id = azurerm_monitor_action_group.fleet_alerts[0].id
  }
  
  tags = local.common_tags
}

# Metric Alert for Event Hub throttling
resource "azurerm_monitor_metric_alert" "eventhub_throttling" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "eventhub-throttling"
  resource_group_name = azurerm_resource_group.main.name
  
  # Alert configuration
  description  = "Alert when Event Hub experiences throttling"
  severity     = 1
  frequency    = "PT1M"
  window_size  = "PT5M"
  
  # Scope - Event Hub namespace
  scopes = [azurerm_eventhub_namespace.main.id]
  
  # Criteria
  criteria {
    metric_namespace = "Microsoft.EventHub/namespaces"
    metric_name      = "ThrottledRequests"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }
  
  # Action
  action {
    action_group_id = azurerm_monitor_action_group.fleet_alerts[0].id
  }
  
  tags = local.common_tags
}

# Metric Alert for Cosmos DB high RU consumption
resource "azurerm_monitor_metric_alert" "cosmosdb_high_ru" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "cosmosdb-high-ru"
  resource_group_name = azurerm_resource_group.main.name
  
  # Alert configuration
  description  = "Alert when Cosmos DB RU consumption is consistently high"
  severity     = 2
  frequency    = "PT5M"
  window_size  = "PT15M"
  
  # Scope - Cosmos DB account
  scopes = [azurerm_cosmosdb_account.main.id]
  
  # Criteria
  criteria {
    metric_namespace = "Microsoft.DocumentDB/databaseAccounts"
    metric_name      = "NormalizedRUConsumption"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }
  
  # Action
  action {
    action_group_id = azurerm_monitor_action_group.fleet_alerts[0].id
  }
  
  tags = local.common_tags
}

# Time delay to ensure resources are fully provisioned before starting Stream Analytics
resource "time_sleep" "wait_for_resources" {
  depends_on = [
    azurerm_stream_analytics_stream_input_eventhub.vehicle_input,
    azurerm_stream_analytics_output_cosmosdb.vehicle_output,
    azurerm_stream_analytics_output_blob.archive_output,
    azurerm_stream_analytics_function_javascript_udf.generate_id
  ]
  
  create_duration = "30s"
}