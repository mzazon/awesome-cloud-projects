# =============================================================================
# Azure IoT Edge Analytics with Percept and Sphere
# =============================================================================
# This Terraform configuration deploys a comprehensive IoT edge analytics 
# solution using Azure Percept and Azure Sphere with enterprise-grade security,
# real-time processing, and automated monitoring capabilities.

# =============================================================================
# Data Sources
# =============================================================================

# Get current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# =============================================================================
# Resource Group
# =============================================================================

resource "azurerm_resource_group" "iot_edge_analytics" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-iot-edge-analytics-${var.environment}-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.common_tags, {
    Purpose     = "IoT Edge Analytics"
    Environment = var.environment
    Solution    = "Azure Percept and Sphere"
  })
}

# =============================================================================
# Log Analytics Workspace
# =============================================================================

resource "azurerm_log_analytics_workspace" "iot_logs" {
  name                = "law-iot-edge-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.iot_edge_analytics.location
  resource_group_name = azurerm_resource_group.iot_edge_analytics.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days

  tags = merge(var.common_tags, {
    Purpose = "IoT Analytics Logging"
  })
}

# =============================================================================
# Application Insights
# =============================================================================

resource "azurerm_application_insights" "iot_insights" {
  name                = "ai-iot-edge-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.iot_edge_analytics.location
  resource_group_name = azurerm_resource_group.iot_edge_analytics.name
  workspace_id        = azurerm_log_analytics_workspace.iot_logs.id
  application_type    = "web"

  tags = merge(var.common_tags, {
    Purpose = "IoT Analytics Monitoring"
  })
}

# =============================================================================
# Key Vault for Secure Storage
# =============================================================================

resource "azurerm_key_vault" "iot_key_vault" {
  name                = "kv-iot-edge-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.iot_edge_analytics.location
  resource_group_name = azurerm_resource_group.iot_edge_analytics.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku

  # Enable soft delete and purge protection for production environments
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  purge_protection_enabled   = var.environment == "prod" ? true : false

  # Enable RBAC for modern authorization
  enable_rbac_authorization = true

  # Network access policies
  network_acls {
    bypass                     = "AzureServices"
    default_action             = var.key_vault_network_acls_default_action
    ip_rules                   = var.key_vault_allowed_ips
    virtual_network_subnet_ids = var.key_vault_allowed_subnets
  }

  tags = merge(var.common_tags, {
    Purpose = "IoT Secrets Management"
  })
}

# =============================================================================
# Storage Account for Data Lake Gen2
# =============================================================================

resource "azurerm_storage_account" "iot_storage" {
  name                     = "stiot${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.iot_edge_analytics.name
  location                 = azurerm_resource_group.iot_edge_analytics.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"

  # Enable Data Lake Gen2 hierarchical namespace
  is_hns_enabled = true

  # Security configurations
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"
  allow_nested_items_to_be_public = false

  # Enable soft delete for blob storage
  blob_properties {
    delete_retention_policy {
      days = var.blob_soft_delete_retention_days
    }
    container_delete_retention_policy {
      days = var.container_soft_delete_retention_days
    }
  }

  # Network rules for secure access
  network_rules {
    default_action             = var.storage_network_rules_default_action
    bypass                     = ["AzureServices"]
    ip_rules                   = var.storage_allowed_ips
    virtual_network_subnet_ids = var.storage_allowed_subnets
  }

  tags = merge(var.common_tags, {
    Purpose = "IoT Data Lake Storage"
  })
}

# =============================================================================
# Storage Containers
# =============================================================================

# Container for processed telemetry data
resource "azurerm_storage_container" "processed_telemetry" {
  name                  = "processed-telemetry"
  storage_account_name  = azurerm_storage_account.iot_storage.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.iot_storage]
}

# Container for raw telemetry data
resource "azurerm_storage_container" "raw_telemetry" {
  name                  = "raw-telemetry"
  storage_account_name  = azurerm_storage_account.iot_storage.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.iot_storage]
}

# =============================================================================
# IoT Hub
# =============================================================================

resource "azurerm_iothub" "iot_hub" {
  name                = "iot-hub-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.iot_edge_analytics.name
  location            = azurerm_resource_group.iot_edge_analytics.location

  # IoT Hub SKU configuration
  sku {
    name     = var.iothub_sku_name
    capacity = var.iothub_sku_capacity
  }

  # Event Hub properties for device-to-cloud messages
  event_hub_retention_in_days = var.iothub_event_hub_retention_days
  event_hub_partition_count   = var.iothub_event_hub_partition_count

  # Cloud-to-device messaging configuration
  cloud_to_device {
    max_delivery_count = var.iothub_cloud_to_device_max_delivery_count
    default_ttl        = var.iothub_cloud_to_device_default_ttl
    feedback {
      time_to_live       = var.iothub_feedback_time_to_live
      max_delivery_count = var.iothub_feedback_max_delivery_count
    }
  }

  # File upload configuration
  file_upload {
    connection_string  = azurerm_storage_account.iot_storage.primary_blob_connection_string
    container_name     = azurerm_storage_container.raw_telemetry.name
    default_ttl        = var.iothub_file_upload_default_ttl
    max_delivery_count = var.iothub_file_upload_max_delivery_count
  }

  # Device-to-cloud routing configuration
  route {
    name           = "TelemetryRoute"
    source         = "DeviceMessages"
    condition      = "true"
    endpoint_names = ["TelemetryEndpoint"]
    enabled        = true
  }

  # Storage endpoint for telemetry data
  endpoint {
    type                       = "AzureIotHub.StorageContainer"
    connection_string          = azurerm_storage_account.iot_storage.primary_blob_connection_string
    name                       = "TelemetryEndpoint"
    batch_frequency_in_seconds = var.iothub_telemetry_batch_frequency
    max_chunk_size_in_bytes    = var.iothub_telemetry_max_chunk_size
    container_name             = azurerm_storage_container.raw_telemetry.name
    encoding                   = "JSON"
    file_name_format           = "{iothub}/{partition}/{YYYY}/{MM}/{DD}/{HH}/{mm}"
  }

  tags = merge(var.common_tags, {
    Purpose = "IoT Device Management"
  })
}

# =============================================================================
# IoT Hub Consumer Group for Stream Analytics
# =============================================================================

resource "azurerm_iothub_consumer_group" "stream_analytics" {
  name                   = "streamanalytics"
  iothub_name           = azurerm_iothub.iot_hub.name
  eventhub_endpoint_name = "events"
  resource_group_name   = azurerm_resource_group.iot_edge_analytics.name
}

# =============================================================================
# Stream Analytics Job
# =============================================================================

resource "azurerm_stream_analytics_job" "iot_stream_analytics" {
  name                                     = "sa-iot-edge-${var.environment}-${random_string.suffix.result}"
  resource_group_name                      = azurerm_resource_group.iot_edge_analytics.name
  location                                 = azurerm_resource_group.iot_edge_analytics.location
  compatibility_level                      = var.stream_analytics_compatibility_level
  data_locale                              = var.stream_analytics_data_locale
  events_late_arrival_max_delay_in_seconds = var.stream_analytics_events_late_arrival_max_delay
  events_out_of_order_max_delay_in_seconds = var.stream_analytics_events_out_of_order_max_delay
  events_out_of_order_policy              = var.stream_analytics_events_out_of_order_policy
  output_error_policy                      = var.stream_analytics_output_error_policy
  streaming_units                          = var.stream_analytics_streaming_units

  tags = merge(var.common_tags, {
    Purpose = "IoT Real-time Analytics"
  })
}

# =============================================================================
# Stream Analytics Input (IoT Hub)
# =============================================================================

resource "azurerm_stream_analytics_stream_input_iothub" "iot_input" {
  name                         = "IoTHubInput"
  stream_analytics_job_name    = azurerm_stream_analytics_job.iot_stream_analytics.name
  resource_group_name          = azurerm_resource_group.iot_edge_analytics.name
  endpoint                     = "messages/events"
  eventhub_consumer_group_name = azurerm_iothub_consumer_group.stream_analytics.name
  iothub_namespace             = azurerm_iothub.iot_hub.name
  shared_access_policy_key     = azurerm_iothub.iot_hub.shared_access_policy[0].primary_key
  shared_access_policy_name    = azurerm_iothub.iot_hub.shared_access_policy[0].key_name

  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

# =============================================================================
# Stream Analytics Output (Blob Storage)
# =============================================================================

resource "azurerm_stream_analytics_output_blob" "processed_output" {
  name                      = "StorageOutput"
  stream_analytics_job_name = azurerm_stream_analytics_job.iot_stream_analytics.name
  resource_group_name       = azurerm_resource_group.iot_edge_analytics.name
  storage_account_name      = azurerm_storage_account.iot_storage.name
  storage_account_key       = azurerm_storage_account.iot_storage.primary_access_key
  storage_container_name    = azurerm_storage_container.processed_telemetry.name
  path_pattern              = "year={datetime:yyyy}/month={datetime:MM}/day={datetime:dd}/hour={datetime:HH}"
  date_format               = "yyyy/MM/dd"
  time_format               = "HH"

  serialization {
    type     = "Json"
    encoding = "UTF8"
    format   = "LineSeparated"
  }
}

# =============================================================================
# Stream Analytics Transformation Query
# =============================================================================

resource "azurerm_stream_analytics_transformation" "iot_transformation" {
  name                     = "ProcessTelemetry"
  stream_analytics_job_name = azurerm_stream_analytics_job.iot_stream_analytics.name
  resource_group_name      = azurerm_resource_group.iot_edge_analytics.name
  streaming_units          = var.stream_analytics_streaming_units

  query = <<QUERY
WITH AnomalyDetection AS (
    SELECT
        deviceId,
        timestamp,
        temperature,
        humidity,
        vibration,
        pressure,
        AnomalyDetection_SpikeAndDip(temperature, 95, 120, 'spikesanddips')
            OVER(LIMIT DURATION(minute, 2)) AS temperatureAnomaly,
        AnomalyDetection_SpikeAndDip(vibration, 95, 120, 'spikesanddips')
            OVER(LIMIT DURATION(minute, 2)) AS vibrationAnomaly,
        AnomalyDetection_SpikeAndDip(pressure, 95, 120, 'spikesanddips')
            OVER(LIMIT DURATION(minute, 2)) AS pressureAnomaly
    FROM IoTHubInput
    WHERE deviceId IN ('${var.percept_device_id}', '${var.sphere_device_id}')
),
AggregatedData AS (
    SELECT
        deviceId,
        System.Timestamp AS windowEnd,
        AVG(temperature) AS avgTemperature,
        MAX(temperature) AS maxTemperature,
        MIN(temperature) AS minTemperature,
        AVG(humidity) AS avgHumidity,
        MAX(humidity) AS maxHumidity,
        MIN(humidity) AS minHumidity,
        AVG(vibration) AS avgVibration,
        MAX(vibration) AS maxVibration,
        MIN(vibration) AS minVibration,
        AVG(pressure) AS avgPressure,
        MAX(pressure) AS maxPressure,
        MIN(pressure) AS minPressure,
        COUNT(*) AS messageCount
    FROM IoTHubInput
    WHERE deviceId IN ('${var.percept_device_id}', '${var.sphere_device_id}')
    GROUP BY deviceId, TumblingWindow(minute, 5)
),
AlertConditions AS (
    SELECT
        ad.deviceId,
        ad.timestamp,
        ad.temperature,
        ad.humidity,
        ad.vibration,
        ad.pressure,
        ad.temperatureAnomaly,
        ad.vibrationAnomaly,
        ad.pressureAnomaly,
        ag.avgTemperature,
        ag.maxTemperature,
        ag.minTemperature,
        ag.avgHumidity,
        ag.maxHumidity,
        ag.minHumidity,
        ag.avgVibration,
        ag.maxVibration,
        ag.minVibration,
        ag.avgPressure,
        ag.maxPressure,
        ag.minPressure,
        ag.messageCount,
        CASE
            WHEN ad.temperatureAnomaly.IsAnomaly = 1 THEN 'TEMPERATURE_ANOMALY'
            WHEN ad.vibrationAnomaly.IsAnomaly = 1 THEN 'VIBRATION_ANOMALY'
            WHEN ad.pressureAnomaly.IsAnomaly = 1 THEN 'PRESSURE_ANOMALY'
            WHEN ad.temperature > ${var.temperature_threshold_high} THEN 'HIGH_TEMPERATURE'
            WHEN ad.temperature < ${var.temperature_threshold_low} THEN 'LOW_TEMPERATURE'
            WHEN ad.vibration > ${var.vibration_threshold_high} THEN 'HIGH_VIBRATION'
            WHEN ad.pressure > ${var.pressure_threshold_high} THEN 'HIGH_PRESSURE'
            WHEN ad.pressure < ${var.pressure_threshold_low} THEN 'LOW_PRESSURE'
            ELSE 'NORMAL'
        END AS alertType,
        CASE
            WHEN ad.temperatureAnomaly.IsAnomaly = 1 OR ad.vibrationAnomaly.IsAnomaly = 1 OR ad.pressureAnomaly.IsAnomaly = 1 THEN 'CRITICAL'
            WHEN ad.temperature > ${var.temperature_threshold_high} OR ad.temperature < ${var.temperature_threshold_low} THEN 'WARNING'
            WHEN ad.vibration > ${var.vibration_threshold_high} THEN 'WARNING'
            WHEN ad.pressure > ${var.pressure_threshold_high} OR ad.pressure < ${var.pressure_threshold_low} THEN 'WARNING'
            ELSE 'INFO'
        END AS alertSeverity
    FROM AnomalyDetection ad
    INNER JOIN AggregatedData ag ON ad.deviceId = ag.deviceId
        AND DATEDIFF(minute, ad, ag.windowEnd) BETWEEN 0 AND 5
)

SELECT
    deviceId,
    timestamp,
    temperature,
    humidity,
    vibration,
    pressure,
    temperatureAnomaly,
    vibrationAnomaly,
    pressureAnomaly,
    avgTemperature,
    maxTemperature,
    minTemperature,
    avgHumidity,
    maxHumidity,
    minHumidity,
    avgVibration,
    maxVibration,
    minVibration,
    avgPressure,
    maxPressure,
    minPressure,
    messageCount,
    alertType,
    alertSeverity
INTO StorageOutput
FROM AlertConditions
WHERE alertSeverity IN ('CRITICAL', 'WARNING') OR alertType != 'NORMAL'
QUERY
}

# =============================================================================
# Action Group for Alerting
# =============================================================================

resource "azurerm_monitor_action_group" "iot_alerts" {
  name                = "ag-iot-edge-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.iot_edge_analytics.name
  short_name          = "IoTAlerts"

  # Email notifications
  dynamic "email_receiver" {
    for_each = var.alert_email_receivers
    content {
      name          = email_receiver.value.name
      email_address = email_receiver.value.email_address
    }
  }

  # SMS notifications (optional)
  dynamic "sms_receiver" {
    for_each = var.alert_sms_receivers
    content {
      name         = sms_receiver.value.name
      country_code = sms_receiver.value.country_code
      phone_number = sms_receiver.value.phone_number
    }
  }

  # Webhook notifications (optional)
  dynamic "webhook_receiver" {
    for_each = var.alert_webhook_receivers
    content {
      name                    = webhook_receiver.value.name
      service_uri             = webhook_receiver.value.service_uri
      use_common_alert_schema = webhook_receiver.value.use_common_alert_schema
    }
  }

  tags = merge(var.common_tags, {
    Purpose = "IoT Alert Management"
  })
}

# =============================================================================
# Metric Alerts
# =============================================================================

# Alert for Stream Analytics runtime errors
resource "azurerm_monitor_metric_alert" "stream_analytics_errors" {
  name                = "alert-stream-analytics-errors-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.iot_edge_analytics.name
  scopes              = [azurerm_stream_analytics_job.iot_stream_analytics.id]
  description         = "Alert when Stream Analytics job encounters runtime errors"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.StreamAnalytics/streamingjobs"
    metric_name      = "Errors"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = azurerm_monitor_action_group.iot_alerts.id
  }

  tags = merge(var.common_tags, {
    Purpose = "Stream Analytics Monitoring"
  })
}

# Alert for IoT Hub device connectivity
resource "azurerm_monitor_metric_alert" "iot_hub_connectivity" {
  name                = "alert-iot-hub-connectivity-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.iot_edge_analytics.name
  scopes              = [azurerm_iothub.iot_hub.id]
  description         = "Alert when IoT Hub connected device count drops below threshold"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT10M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.Devices/IotHubs"
    metric_name      = "devices.connectedDevices.allProtocols"
    aggregation      = "Maximum"
    operator         = "LessThan"
    threshold        = var.minimum_connected_devices_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.iot_alerts.id
  }

  tags = merge(var.common_tags, {
    Purpose = "IoT Hub Connectivity Monitoring"
  })
}

# Alert for high message throttling
resource "azurerm_monitor_metric_alert" "iot_hub_throttling" {
  name                = "alert-iot-hub-throttling-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.iot_edge_analytics.name
  scopes              = [azurerm_iothub.iot_hub.id]
  description         = "Alert when IoT Hub message throttling is high"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.Devices/IotHubs"
    metric_name      = "d2c.telemetry.ingress.sendThrottle"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.throttling_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.iot_alerts.id
  }

  tags = merge(var.common_tags, {
    Purpose = "IoT Hub Throttling Monitoring"
  })
}

# =============================================================================
# Diagnostic Settings
# =============================================================================

# IoT Hub diagnostic settings
resource "azurerm_monitor_diagnostic_setting" "iot_hub_diagnostics" {
  name                       = "diag-iot-hub-${var.environment}-${random_string.suffix.result}"
  target_resource_id         = azurerm_iothub.iot_hub.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.iot_logs.id

  enabled_log {
    category = "Connections"
  }

  enabled_log {
    category = "DeviceTelemetry"
  }

  enabled_log {
    category = "C2DCommands"
  }

  enabled_log {
    category = "DeviceIdentityOperations"
  }

  enabled_log {
    category = "FileUploadOperations"
  }

  enabled_log {
    category = "Routes"
  }

  enabled_log {
    category = "D2CTwinOperations"
  }

  enabled_log {
    category = "C2DTwinOperations"
  }

  enabled_log {
    category = "TwinQueries"
  }

  enabled_log {
    category = "JobsOperations"
  }

  enabled_log {
    category = "DirectMethods"
  }

  enabled_log {
    category = "DistributedTracing"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Stream Analytics diagnostic settings
resource "azurerm_monitor_diagnostic_setting" "stream_analytics_diagnostics" {
  name                       = "diag-stream-analytics-${var.environment}-${random_string.suffix.result}"
  target_resource_id         = azurerm_stream_analytics_job.iot_stream_analytics.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.iot_logs.id

  enabled_log {
    category = "Execution"
  }

  enabled_log {
    category = "Authoring"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Storage Account diagnostic settings
resource "azurerm_monitor_diagnostic_setting" "storage_diagnostics" {
  name                       = "diag-storage-${var.environment}-${random_string.suffix.result}"
  target_resource_id         = azurerm_storage_account.iot_storage.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.iot_logs.id

  metric {
    category = "Transaction"
    enabled  = true
  }

  metric {
    category = "Capacity"
    enabled  = true
  }
}

# =============================================================================
# Key Vault Secrets
# =============================================================================

# Store IoT Hub connection string
resource "azurerm_key_vault_secret" "iot_hub_connection_string" {
  name         = "iot-hub-connection-string"
  value        = azurerm_iothub.iot_hub.shared_access_policy[0].connection_string
  key_vault_id = azurerm_key_vault.iot_key_vault.id

  tags = merge(var.common_tags, {
    Purpose = "IoT Hub Connection String"
  })

  depends_on = [azurerm_key_vault.iot_key_vault]
}

# Store Storage Account connection string
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.iot_storage.primary_connection_string
  key_vault_id = azurerm_key_vault.iot_key_vault.id

  tags = merge(var.common_tags, {
    Purpose = "Storage Account Connection String"
  })

  depends_on = [azurerm_key_vault.iot_key_vault]
}