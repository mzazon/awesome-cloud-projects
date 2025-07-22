# Main Terraform configuration for Edge-Based Predictive Maintenance
# This configuration deploys Azure IoT Edge with Stream Analytics for predictive maintenance

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Storage Account for Stream Analytics and telemetry archival
resource "azurerm_storage_account" "main" {
  name                     = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication
  account_kind             = "StorageV2"
  
  # Enable blob versioning for better data management
  blob_properties {
    versioning_enabled = true
    change_feed_enabled = true
    
    # Configure lifecycle management
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = var.tags
}

# Storage containers for different data types
resource "azurerm_storage_container" "stream_analytics" {
  name                  = "streamanalytics"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "telemetry_archive" {
  name                  = "telemetry-archive"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Log Analytics Workspace for monitoring and diagnostics
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = var.tags
}

# IoT Hub for device management and message routing
resource "azurerm_iothub" "main" {
  name                = "hub-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  sku {
    name     = var.iot_hub_sku
    capacity = var.iot_hub_capacity
  }
  
  # Enable device-to-cloud telemetry
  endpoint {
    type                       = "AzureIotHub.StorageContainer"
    connection_string          = azurerm_storage_account.main.primary_blob_connection_string
    name                       = "telemetry-storage"
    batch_frequency_in_seconds = 60
    max_chunk_size_in_bytes   = 10485760
    container_name            = azurerm_storage_container.telemetry_archive.name
    encoding                  = "JSON"
    file_name_format          = "{iothub}/{partition}_{YYYY}_{MM}_{DD}_{HH}_{mm}"
  }
  
  # Route telemetry to storage for archival
  route {
    name           = "telemetry-to-storage"
    source         = "DeviceMessages"
    condition      = "true"
    endpoint_names = ["telemetry-storage"]
    enabled        = true
  }
  
  # Enable cloud-to-device messaging
  cloud_to_device {
    max_delivery_count = 30
    default_ttl        = "PT1H"
    
    feedback {
      time_to_live       = "PT1H"
      max_delivery_count = 10
      lock_duration      = "PT30S"
    }
  }
  
  tags = var.tags
}

# IoT Edge Device identity
resource "azurerm_iothub_device_identity" "edge_device" {
  name           = var.edge_device_id
  iothub_name    = azurerm_iothub.main.name
  resource_group = azurerm_resource_group.main.name
  
  # Enable edge capabilities
  edge_enabled = true
  
  # Use symmetric key authentication
  authentication_type = "symmetricKey"
  
  tags = var.tags
}

# Stream Analytics Job for edge deployment
resource "azurerm_stream_analytics_job" "edge_job" {
  name                                     = "sa-${var.project_name}-${random_string.suffix.result}"
  resource_group_name                      = azurerm_resource_group.main.name
  location                                 = azurerm_resource_group.main.location
  compatibility_level                      = "1.2"
  data_locale                             = "en-GB"
  events_late_arrival_max_delay_in_seconds = 60
  events_out_of_order_max_delay_in_seconds = 50
  events_out_of_order_policy              = "Adjust"
  output_error_policy                     = "Drop"
  streaming_units                         = var.stream_analytics_streaming_units
  
  # Configure for IoT Edge deployment
  type = "Cloud"
  
  tags = var.tags
}

# Stream Analytics Job Input (from IoT Edge Hub)
resource "azurerm_stream_analytics_stream_input_iothub" "temperature_input" {
  name                         = "temperature-input"
  stream_analytics_job_name    = azurerm_stream_analytics_job.edge_job.name
  resource_group_name          = azurerm_resource_group.main.name
  endpoint                     = "messages/events"
  eventhub_consumer_group_name = "$Default"
  iothub_namespace             = azurerm_iothub.main.name
  shared_access_policy_key     = azurerm_iothub.main.shared_access_policy[0].primary_key
  shared_access_policy_name    = azurerm_iothub.main.shared_access_policy[0].name
  
  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

# Stream Analytics Job Output (back to IoT Hub)
resource "azurerm_stream_analytics_output_servicebus_queue" "anomaly_output" {
  name                      = "anomaly-output"
  stream_analytics_job_name = azurerm_stream_analytics_job.edge_job.name
  resource_group_name       = azurerm_resource_group.main.name
  queue_name                = azurerm_servicebus_queue.anomaly_alerts.name
  servicebus_namespace      = azurerm_servicebus_namespace.main.name
  shared_access_policy_key  = azurerm_servicebus_namespace.main.default_primary_key
  shared_access_policy_name = "RootManageSharedAccessKey"
  
  serialization {
    type = "Json"
  }
}

# Service Bus Namespace for alert processing
resource "azurerm_servicebus_namespace" "main" {
  name                = "sb-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  
  tags = var.tags
}

# Service Bus Queue for anomaly alerts
resource "azurerm_servicebus_queue" "anomaly_alerts" {
  name         = "anomaly-alerts"
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Configure queue properties
  enable_partitioning = true
  max_size_in_megabytes = 1024
  
  # Message time-to-live (24 hours)
  default_message_ttl = "P1D"
  
  # Enable dead lettering for expired messages
  dead_lettering_on_message_expiration = true
}

# Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  name                = "ai-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "other"
  
  tags = var.tags
}

# Action Group for alerts
resource "azurerm_monitor_action_group" "maintenance_team" {
  name                = "ag-maintenance-team"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "MaintTeam"
  
  email_receiver {
    name          = "Maintenance"
    email_address = var.alert_email
  }
  
  sms_receiver {
    name         = "OnCall"
    country_code = "1"
    phone_number = substr(var.alert_phone, 2, length(var.alert_phone) - 2)
  }
  
  tags = var.tags
}

# Metric Alert for high temperature detection
resource "azurerm_monitor_metric_alert" "high_temperature" {
  name                = "alert-high-temperature"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_iothub.main.id]
  description         = "Alert when high message volume indicates anomalies"
  
  # Alert criteria
  criteria {
    metric_namespace = "Microsoft.Devices/IotHubs"
    metric_name      = "telemetry.sent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 100
    
    # 5-minute window
    dimension {
      name     = "Result"
      operator = "Include"
      values   = ["*"]
    }
  }
  
  # Evaluation frequency and window
  frequency   = "PT1M"
  window_size = "PT5M"
  
  # Severity levels: 0=Critical, 1=Error, 2=Warning, 3=Informational
  severity = 2
  
  # Action to take when alert fires
  action {
    action_group_id = azurerm_monitor_action_group.maintenance_team.id
  }
  
  tags = var.tags
}

# Diagnostic Settings for IoT Hub
resource "azurerm_monitor_diagnostic_setting" "iothub_diagnostics" {
  name                       = "iothub-diagnostics"
  target_resource_id         = azurerm_iothub.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "Connections"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  enabled_log {
    category = "DeviceTelemetry"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  enabled_log {
    category = "DeviceIdentityOperations"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  metric {
    category = "AllMetrics"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# Diagnostic Settings for Stream Analytics
resource "azurerm_monitor_diagnostic_setting" "stream_analytics_diagnostics" {
  name                       = "stream-analytics-diagnostics"
  target_resource_id         = azurerm_stream_analytics_job.edge_job.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "Execution"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  enabled_log {
    category = "Authoring"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  metric {
    category = "AllMetrics"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# Create the anomaly detection query as a local file
resource "local_file" "anomaly_query" {
  filename = "${path.module}/anomaly_detection_query.sql"
  content  = <<EOF
SELECT
    'maintenance_required' AS alertType,
    System.Timestamp() AS alertTime,
    AVG(temperature) AS avgTemperature,
    MAX(temperature) AS maxTemperature,
    COUNT(*) AS readingCount
INTO
    [anomaly-output]
FROM
    [temperature-input] TIMESTAMP BY timeCreated
GROUP BY
    TumblingWindow(second, 30)
HAVING
    AVG(temperature) > ${var.temperature_alert_threshold_avg} OR MAX(temperature) > ${var.temperature_alert_threshold_max}
EOF
}

# Create deployment manifest template for IoT Edge
resource "local_file" "edge_deployment_manifest" {
  filename = "${path.module}/deployment_manifest.json"
  content  = jsonencode({
    modulesContent = {
      "$edgeAgent" = {
        "properties.desired" = {
          runtime = {
            type = "docker"
            settings = {
              minDockerVersion = "v1.25"
            }
          }
          modules = {
            SimulatedTemperatureSensor = {
              type           = "docker"
              status         = "running"
              restartPolicy  = "always"
              settings = {
                image         = "mcr.microsoft.com/azureiotedge-simulated-temperature-sensor:1.0"
                createOptions = "{}"
              }
            }
            StreamAnalytics = {
              type           = "docker"
              status         = "running"
              restartPolicy  = "always"
              settings = {
                image         = "mcr.microsoft.com/azure-stream-analytics/azureiotedge:1.0.9-linux-amd64"
                createOptions = "{}"
              }
            }
          }
        }
      }
      "$edgeHub" = {
        "properties.desired" = {
          routes = {
            sensorToAnalytics = "FROM /messages/modules/SimulatedTemperatureSensor/outputs/temperatureOutput INTO BrokeredEndpoint('/modules/StreamAnalytics/inputs/temperature-input')"
            analyticsToHub    = "FROM /messages/modules/StreamAnalytics/outputs/anomaly-output INTO $upstream"
          }
        }
      }
    }
  })
}