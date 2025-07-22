# Main Terraform configuration for Azure IoT Edge and Machine Learning Anomaly Detection
# This file creates the complete infrastructure for real-time anomaly detection using Azure IoT Edge and Azure ML

# Get current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# Create Log Analytics Workspace for centralized logging and monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

# Create Application Insights for ML model monitoring
resource "azurerm_application_insights" "main" {
  name                = "ai-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.application_insights_type
  tags                = var.tags
}

# Create Key Vault for secure storage of credentials and secrets
resource "azurerm_key_vault" "main" {
  name                            = "kv-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = var.key_vault_sku
  enabled_for_disk_encryption     = var.key_vault_enabled_for_disk_encryption
  enabled_for_template_deployment = var.key_vault_enabled_for_template_deployment
  soft_delete_retention_days      = var.key_vault_soft_delete_retention_days
  purge_protection_enabled        = true
  tags                            = var.tags

  # Grant current user full access to Key Vault
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Backup", "Create", "Decrypt", "Delete", "Encrypt", "Get", "Import", "List", "Purge", "Recover", "Restore", "Sign", "UnwrapKey", "Update", "Verify", "WrapKey"
    ]

    secret_permissions = [
      "Backup", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Set"
    ]

    certificate_permissions = [
      "Backup", "Create", "Delete", "DeleteIssuers", "Get", "GetIssuers", "Import", "List", "ListIssuers", "ManageContacts", "ManageIssuers", "Purge", "Recover", "Restore", "SetIssuers", "Update"
    ]
  }
}

# Create Storage Account for ML models, data, and general storage
resource "azurerm_storage_account" "main" {
  name                     = "st${replace(var.project_name, "-", "")}${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  is_hns_enabled           = var.enable_hierarchical_namespace

  # Enable advanced threat protection
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"

  tags = var.tags
}

# Create storage containers for ML models and anomaly data
resource "azurerm_storage_container" "ml_models" {
  name                  = "ml-models"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "anomaly_data" {
  name                  = "anomaly-data"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Create IoT Hub for device management and telemetry ingestion
resource "azurerm_iothub" "main" {
  name                = "iot-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags

  sku {
    name     = var.iot_hub_sku
    capacity = "1"
  }

  endpoint {
    type                       = "AzureIotHub.EventHub"
    connection_string          = azurerm_eventhub_authorization_rule.main.primary_connection_string
    name                       = "export"
    batch_frequency_in_seconds = 60
    max_chunk_size_in_bytes    = 10485760
    container_name             = azurerm_storage_container.anomaly_data.name
    encoding                   = "Avro"
    file_name_format           = "{iothub}/{partition}_{YYYY}_{MM}_{DD}_{HH}_{mm}"
  }

  route {
    name           = "export"
    source         = "DeviceMessages"
    condition      = "true"
    endpoint_names = ["export"]
    enabled        = true
  }

  # Configure message retention and partitioning
  event_hub_partition_count   = var.iot_hub_partition_count
  event_hub_retention_in_days = var.iot_hub_retention_days
}

# Create Event Hub namespace for Stream Analytics integration
resource "azurerm_eventhub_namespace" "main" {
  name                = "evhns-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
  capacity            = 1
  tags                = var.tags
}

# Create Event Hub for processed anomaly data
resource "azurerm_eventhub" "main" {
  name                = "anomaly-events"
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = 2
  message_retention   = 1
}

# Create Event Hub authorization rule for Stream Analytics
resource "azurerm_eventhub_authorization_rule" "main" {
  name                = "stream-analytics-rule"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.main.name
  resource_group_name = azurerm_resource_group.main.name
  listen              = true
  send                = true
  manage              = false
}

# Create Machine Learning Workspace
resource "azurerm_machine_learning_workspace" "main" {
  name                    = "ml-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  application_insights_id = azurerm_application_insights.main.id
  key_vault_id            = azurerm_key_vault.main.id
  storage_account_id      = azurerm_storage_account.main.id
  tags                    = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# Create Machine Learning Compute Instance for model training
resource "azurerm_machine_learning_compute_instance" "main" {
  name                          = "ml-compute-${random_string.suffix.result}"
  location                      = azurerm_resource_group.main.location
  machine_learning_workspace_id = azurerm_machine_learning_workspace.main.id
  virtual_machine_size          = var.ml_compute_instance_size
  authorization_type            = "personal"
  description                   = "Compute instance for anomaly detection model training"
  tags                          = var.tags
}

# Create Machine Learning Compute Cluster for scalable training
resource "azurerm_machine_learning_compute_cluster" "main" {
  name                          = "ml-cluster-${random_string.suffix.result}"
  location                      = azurerm_resource_group.main.location
  machine_learning_workspace_id = azurerm_machine_learning_workspace.main.id
  vm_priority                   = "Dedicated"
  vm_size                       = var.ml_compute_instance_size
  description                   = "Compute cluster for anomaly detection model training"
  tags                          = var.tags

  scale_settings {
    min_node_count                       = var.ml_compute_min_instances
    max_node_count                       = var.ml_compute_max_instances
    scale_down_nodes_after_idle_duration = "PT30S"
  }

  identity {
    type = "SystemAssigned"
  }
}

# Create Stream Analytics Job for real-time anomaly detection
resource "azurerm_stream_analytics_job" "main" {
  name                                     = "asa-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name                      = azurerm_resource_group.main.name
  location                                 = azurerm_resource_group.main.location
  compatibility_level                      = var.stream_analytics_compatibility_level
  data_locale                             = "en-US"
  events_late_arrival_max_delay_in_seconds = 60
  events_out_of_order_max_delay_in_seconds = 50
  events_out_of_order_policy               = "Adjust"
  output_error_policy                      = "Drop"
  streaming_units                          = var.stream_analytics_streaming_units
  tags                                     = var.tags

  transformation_query = <<QUERY
WITH AnomalyDetectionStep AS
(
    SELECT
        deviceId,
        temperature,
        pressure,
        vibration,
        ANOMALYDETECTION(temperature) OVER (PARTITION BY deviceId LIMIT DURATION(minute, ${var.anomaly_detection_window_minutes})) AS temp_scores,
        ANOMALYDETECTION(pressure) OVER (PARTITION BY deviceId LIMIT DURATION(minute, ${var.anomaly_detection_window_minutes})) AS pressure_scores,
        ANOMALYDETECTION(vibration) OVER (PARTITION BY deviceId LIMIT DURATION(minute, ${var.anomaly_detection_window_minutes})) AS vibration_scores,
        System.Timestamp() AS eventTime
    FROM sensorInput
)
SELECT
    deviceId,
    temperature,
    pressure,
    vibration,
    temp_scores,
    pressure_scores,
    vibration_scores,
    eventTime
INTO output
FROM AnomalyDetectionStep
WHERE
    CAST(GetRecordPropertyValue(temp_scores, 'BiLevelChangeScore') AS FLOAT) > ${var.anomaly_detection_threshold}
    OR CAST(GetRecordPropertyValue(pressure_scores, 'BiLevelChangeScore') AS FLOAT) > ${var.anomaly_detection_threshold}
    OR CAST(GetRecordPropertyValue(vibration_scores, 'BiLevelChangeScore') AS FLOAT) > ${var.anomaly_detection_threshold}
QUERY
}

# Create Stream Analytics Job Input (IoT Hub)
resource "azurerm_stream_analytics_stream_input_iothub" "main" {
  name                         = "sensorInput"
  stream_analytics_job_name    = azurerm_stream_analytics_job.main.name
  resource_group_name          = azurerm_resource_group.main.name
  endpoint                     = "messages/events"
  eventhub_consumer_group_name = "$Default"
  iothub_namespace             = azurerm_iothub.main.name
  shared_access_policy_key     = azurerm_iothub_shared_access_policy.main.primary_key
  shared_access_policy_name    = azurerm_iothub_shared_access_policy.main.name

  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

# Create Stream Analytics Job Output (Event Hub)
resource "azurerm_stream_analytics_output_eventhub" "main" {
  name                      = "output"
  stream_analytics_job_name = azurerm_stream_analytics_job.main.name
  resource_group_name       = azurerm_resource_group.main.name
  eventhub_name             = azurerm_eventhub.main.name
  servicebus_namespace      = azurerm_eventhub_namespace.main.name
  shared_access_policy_key  = azurerm_eventhub_authorization_rule.main.primary_key
  shared_access_policy_name = azurerm_eventhub_authorization_rule.main.name

  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

# Create IoT Hub Shared Access Policy for Stream Analytics
resource "azurerm_iothub_shared_access_policy" "main" {
  name                = "stream-analytics-policy"
  resource_group_name = azurerm_resource_group.main.name
  iothub_name         = azurerm_iothub.main.name
  service_connect     = true
  device_connect      = false
  registry_read       = true
  registry_write      = false
}

# Register IoT Edge Device
resource "azurerm_iothub_device" "edge_device" {
  name               = var.edge_device_id
  resource_group_name = azurerm_resource_group.main.name
  iothub_name        = azurerm_iothub.main.name
  device_id          = var.edge_device_id

  # Configure as IoT Edge device
  edge_enabled = true

  # Use symmetric key authentication
  authentication {
    type = "sas"
  }

  tags = var.tags
}

# Create diagnostic settings for IoT Hub monitoring
resource "azurerm_monitor_diagnostic_setting" "iothub" {
  name                       = "iothub-diagnostics"
  target_resource_id         = azurerm_iothub.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

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

  metric {
    category = "AllMetrics"
  }
}

# Create diagnostic settings for Stream Analytics monitoring
resource "azurerm_monitor_diagnostic_setting" "stream_analytics" {
  name                       = "stream-analytics-diagnostics"
  target_resource_id         = azurerm_stream_analytics_job.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "Execution"
  }

  enabled_log {
    category = "Authoring"
  }

  metric {
    category = "AllMetrics"
  }
}

# Create diagnostic settings for Machine Learning workspace monitoring
resource "azurerm_monitor_diagnostic_setting" "ml_workspace" {
  name                       = "ml-workspace-diagnostics"
  target_resource_id         = azurerm_machine_learning_workspace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "AmlComputeClusterEvent"
  }

  enabled_log {
    category = "AmlComputeClusterNodeEvent"
  }

  enabled_log {
    category = "AmlComputeJobEvent"
  }

  metric {
    category = "AllMetrics"
  }
}

# Create Action Group for alerts
resource "azurerm_monitor_action_group" "main" {
  name                = "ag-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "anomaly-ag"
  tags                = var.tags

  email_receiver {
    name          = "admin-email"
    email_address = "admin@example.com"  # Replace with actual email
  }
}

# Create metric alert for high anomaly detection rate
resource "azurerm_monitor_metric_alert" "high_anomaly_rate" {
  name                = "high-anomaly-rate"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_stream_analytics_job.main.id]
  description         = "Alert when anomaly detection rate is high"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.StreamAnalytics/streamingjobs"
    metric_name      = "OutputEvents"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 100
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}

# Create metric alert for IoT Hub connectivity issues
resource "azurerm_monitor_metric_alert" "iothub_connectivity" {
  name                = "iothub-connectivity-issues"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_iothub.main.id]
  description         = "Alert when IoT Hub has connectivity issues"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Devices/IotHubs"
    metric_name      = "c2d.commands.egress.abandon.success"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}

# Store IoT device connection string in Key Vault
resource "azurerm_key_vault_secret" "device_connection_string" {
  name         = "edge-device-connection-string"
  value        = azurerm_iothub_device.edge_device.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  tags         = var.tags

  depends_on = [azurerm_key_vault.main]
}

# Store Storage Account connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  tags         = var.tags

  depends_on = [azurerm_key_vault.main]
}

# Store Event Hub connection string in Key Vault
resource "azurerm_key_vault_secret" "eventhub_connection_string" {
  name         = "eventhub-connection-string"
  value        = azurerm_eventhub_authorization_rule.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  tags         = var.tags

  depends_on = [azurerm_key_vault.main]
}