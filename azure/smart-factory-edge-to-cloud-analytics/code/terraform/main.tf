# Main Terraform Configuration for Azure IoT Operations Manufacturing Analytics
# This file deploys a complete edge-to-cloud manufacturing analytics solution
# using Azure IoT Operations, Event Hubs, Stream Analytics, and Azure Monitor

# ==============================================================================
# LOCAL VALUES AND DATA SOURCES
# ==============================================================================

# Generate unique suffix for resource names to avoid conflicts
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Define common tags for all resources
locals {
  # Generate unique resource names
  resource_suffix = random_string.suffix.result
  resource_group_name = var.resource_group_name != null ? var.resource_group_name : "rg-${var.solution_name}-${var.environment}-${local.resource_suffix}"
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment     = var.environment
    Solution        = var.solution_name
    DeployedBy      = "Terraform"
    Purpose         = "Manufacturing Analytics"
    Architecture    = "Edge-to-Cloud IoT"
    CreatedDate     = formatdate("YYYY-MM-DD", timestamp())
    CostCenter      = "Manufacturing Operations"
    DataClassification = "Internal"
  }, var.custom_tags)
  
  # Resource naming conventions
  naming = {
    event_hubs_namespace = "eh-${var.solution_name}-${var.environment}-${local.resource_suffix}"
    event_hub_name      = "telemetry-hub"
    stream_analytics    = "sa-equipment-analytics-${local.resource_suffix}"
    log_analytics      = "law-${var.solution_name}-${var.environment}-${local.resource_suffix}"
    action_group       = "ag-manufacturing-maintenance-${local.resource_suffix}"
    app_insights       = "ai-${var.solution_name}-${var.environment}-${local.resource_suffix}"
  }
}

# ==============================================================================
# RESOURCE GROUP
# ==============================================================================

# Create resource group for all manufacturing analytics resources
resource "azurerm_resource_group" "manufacturing_analytics" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"]]
  }
}

# ==============================================================================
# LOG ANALYTICS WORKSPACE FOR MONITORING
# ==============================================================================

# Create Log Analytics workspace for centralized logging and monitoring
resource "azurerm_log_analytics_workspace" "manufacturing_monitoring" {
  name                = local.naming.log_analytics
  location            = azurerm_resource_group.manufacturing_analytics.location
  resource_group_name = azurerm_resource_group.manufacturing_analytics.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  daily_quota_gb      = var.log_analytics_sku == "Free" ? 0.5 : -1

  tags = merge(local.common_tags, {
    Component = "Monitoring"
    Service   = "Log Analytics"
  })
}

# Create Application Insights for application performance monitoring
resource "azurerm_application_insights" "manufacturing_insights" {
  name                = local.naming.app_insights
  location            = azurerm_resource_group.manufacturing_analytics.location
  resource_group_name = azurerm_resource_group.manufacturing_analytics.name
  workspace_id        = azurerm_log_analytics_workspace.manufacturing_monitoring.id
  application_type    = "other"
  sampling_percentage = var.telemetry_sample_rate

  tags = merge(local.common_tags, {
    Component = "Monitoring"
    Service   = "Application Insights"
  })
}

# ==============================================================================
# EVENT HUBS NAMESPACE AND HUB FOR TELEMETRY INGESTION
# ==============================================================================

# Create Event Hubs namespace for manufacturing telemetry ingestion
resource "azurerm_eventhub_namespace" "manufacturing_telemetry" {
  name                = local.naming.event_hubs_namespace
  location            = azurerm_resource_group.manufacturing_analytics.location
  resource_group_name = azurerm_resource_group.manufacturing_analytics.name
  sku                 = var.event_hubs_namespace_sku
  capacity            = var.event_hubs_capacity

  # Enable auto-inflate for handling traffic spikes
  auto_inflate_enabled     = var.event_hubs_auto_inflate_enabled
  maximum_throughput_units = var.event_hubs_auto_inflate_enabled ? var.event_hubs_maximum_throughput_units : null

  # Configure network access rules if IP ranges are specified
  dynamic "network_rulesets" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action                 = "Deny"
      trusted_service_access_enabled = true

      dynamic "ip_rule" {
        for_each = var.allowed_ip_ranges
        content {
          ip_mask = ip_rule.value
          action  = "Allow"
        }
      }
    }
  }

  # Enable managed identity for secure authentication
  identity {
    type = var.enable_managed_identity ? "SystemAssigned" : null
  }

  tags = merge(local.common_tags, {
    Component = "Data Ingestion"
    Service   = "Event Hubs"
  })
}

# Create Event Hub for manufacturing telemetry data
resource "azurerm_eventhub" "manufacturing_telemetry_hub" {
  name                = local.naming.event_hub_name
  namespace_name      = azurerm_eventhub_namespace.manufacturing_telemetry.name
  resource_group_name = azurerm_resource_group.manufacturing_analytics.name
  partition_count     = var.telemetry_event_hub_partition_count
  message_retention   = var.telemetry_event_hub_message_retention

  # Configure capture for long-term storage (optional)
  capture_description {
    enabled  = true
    encoding = "Avro"
    
    destination {
      name                = "EventHubArchive"
      archive_name_format = "manufacturing-telemetry/{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = "telemetry-archive"
      storage_account_id  = azurerm_storage_account.manufacturing_data.id
    }
  }
}

# Create authorization rule for IoT Operations integration
resource "azurerm_eventhub_authorization_rule" "iot_operations_access" {
  name                = "IoTOperationsPolicy"
  namespace_name      = azurerm_eventhub_namespace.manufacturing_telemetry.name
  eventhub_name       = azurerm_eventhub.manufacturing_telemetry_hub.name
  resource_group_name = azurerm_resource_group.manufacturing_analytics.name

  listen = true
  send   = true
  manage = false
}

# ==============================================================================
# STORAGE ACCOUNT FOR TELEMETRY ARCHIVE AND ANALYTICS
# ==============================================================================

# Create storage account for telemetry archival and analytics data
resource "azurerm_storage_account" "manufacturing_data" {
  name                     = "st${replace(var.solution_name, "-", "")}${var.environment}${local.resource_suffix}"
  resource_group_name      = azurerm_resource_group.manufacturing_analytics.name
  location                 = azurerm_resource_group.manufacturing_analytics.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Enable hierarchical namespace for analytics workloads
  is_hns_enabled = true

  # Configure blob properties for optimal telemetry storage
  blob_properties {
    change_feed_enabled = true
    versioning_enabled  = true
    
    delete_retention_policy {
      days = 30
    }
    
    container_delete_retention_policy {
      days = 30
    }
  }

  # Enable managed identity
  identity {
    type = var.enable_managed_identity ? "SystemAssigned" : null
  }

  tags = merge(local.common_tags, {
    Component = "Data Storage"
    Service   = "Storage Account"
  })
}

# Create container for telemetry archive
resource "azurerm_storage_container" "telemetry_archive" {
  name                  = "telemetry-archive"
  storage_account_name  = azurerm_storage_account.manufacturing_data.name
  container_access_type = "private"
}

# Create container for processed analytics data
resource "azurerm_storage_container" "analytics_data" {
  name                  = "analytics-data"
  storage_account_name  = azurerm_storage_account.manufacturing_data.name
  container_access_type = "private"
}

# ==============================================================================
# STREAM ANALYTICS JOB FOR REAL-TIME PROCESSING
# ==============================================================================

# Create Stream Analytics job for manufacturing analytics
resource "azurerm_stream_analytics_job" "manufacturing_analytics" {
  name                = local.naming.stream_analytics
  resource_group_name = azurerm_resource_group.manufacturing_analytics.name
  location            = azurerm_resource_group.manufacturing_analytics.location
  
  # Configure job properties
  compatibility_level                      = var.stream_analytics_compatibility_level
  data_locale                             = "en-US"
  events_late_arrival_max_delay_in_seconds = 60
  events_out_of_order_max_delay_in_seconds = 50
  events_out_of_order_policy              = "Adjust"
  output_error_policy                     = "Stop"
  streaming_units                         = var.stream_analytics_streaming_units

  # Configure job transformation query for manufacturing analytics
  transformation_query = file("${path.module}/manufacturing-analytics-query.sql")

  # Enable managed identity
  identity {
    type = var.enable_managed_identity ? "SystemAssigned" : null
  }

  tags = merge(local.common_tags, {
    Component = "Real-time Analytics"
    Service   = "Stream Analytics"
  })
}

# Create Stream Analytics input for Event Hubs telemetry
resource "azurerm_stream_analytics_stream_input_eventhub" "manufacturing_telemetry_input" {
  name                         = "ManufacturingTelemetryInput"
  stream_analytics_job_name    = azurerm_stream_analytics_job.manufacturing_analytics.name
  resource_group_name          = azurerm_resource_group.manufacturing_analytics.name
  eventhub_consumer_group_name = "$Default"
  eventhub_name                = azurerm_eventhub.manufacturing_telemetry_hub.name
  servicebus_namespace         = azurerm_eventhub_namespace.manufacturing_telemetry.name
  shared_access_policy_key     = azurerm_eventhub_authorization_rule.iot_operations_access.primary_key
  shared_access_policy_name    = azurerm_eventhub_authorization_rule.iot_operations_access.name

  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

# Create Stream Analytics output for processed alerts
resource "azurerm_stream_analytics_output_eventhub" "manufacturing_alerts_output" {
  name                      = "ManufacturingAlertsOutput"
  stream_analytics_job_name = azurerm_stream_analytics_job.manufacturing_analytics.name
  resource_group_name       = azurerm_resource_group.manufacturing_analytics.name
  eventhub_name            = azurerm_eventhub.manufacturing_alerts_hub.name
  servicebus_namespace     = azurerm_eventhub_namespace.manufacturing_telemetry.name
  shared_access_policy_key = azurerm_eventhub_authorization_rule.iot_operations_access.primary_key
  shared_access_policy_name = azurerm_eventhub_authorization_rule.iot_operations_access.name

  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

# Create Stream Analytics output for OEE metrics
resource "azurerm_stream_analytics_output_blob" "oee_metrics_output" {
  name                      = "OEEMetricsOutput"
  stream_analytics_job_name = azurerm_stream_analytics_job.manufacturing_analytics.name
  resource_group_name       = azurerm_resource_group.manufacturing_analytics.name
  storage_account_name      = azurerm_storage_account.manufacturing_data.name
  storage_account_key       = azurerm_storage_account.manufacturing_data.primary_access_key
  storage_container_name    = azurerm_storage_container.analytics_data.name
  path_pattern              = "oee-metrics/{date}/{time}"
  date_format               = "yyyy/MM/dd"
  time_format               = "HH"

  serialization {
    type            = "Json"
    encoding        = "UTF8"
    format          = "LineSeparated"
  }
}

# Create Event Hub for manufacturing alerts
resource "azurerm_eventhub" "manufacturing_alerts_hub" {
  name                = "alerts-hub"
  namespace_name      = azurerm_eventhub_namespace.manufacturing_telemetry.name
  resource_group_name = azurerm_resource_group.manufacturing_analytics.name
  partition_count     = 2
  message_retention   = 1
}

# ==============================================================================
# ACTION GROUP AND ALERTS FOR PREDICTIVE MAINTENANCE
# ==============================================================================

# Create action group for manufacturing maintenance team notifications
resource "azurerm_monitor_action_group" "manufacturing_maintenance" {
  count               = var.enable_alerts ? 1 : 0
  name                = local.naming.action_group
  resource_group_name = azurerm_resource_group.manufacturing_analytics.name
  short_name          = "MaintTeam"

  # Configure email notifications
  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name          = "MaintenanceEmail${email_receiver.key + 1}"
      email_address = email_receiver.value
    }
  }

  # Configure SMS notifications
  dynamic "sms_receiver" {
    for_each = var.alert_phone_numbers
    content {
      name         = "MaintenanceSMS${sms_receiver.key + 1}"
      country_code = "1"
      phone_number = replace(sms_receiver.value, "+1", "")
    }
  }

  tags = merge(local.common_tags, {
    Component = "Alerting"
    Service   = "Action Group"
  })
}

# Create metric alert for critical equipment conditions
resource "azurerm_monitor_metric_alert" "critical_equipment_alert" {
  count               = var.enable_alerts ? 1 : 0
  name                = "CriticalEquipmentAlert"
  resource_group_name = azurerm_resource_group.manufacturing_analytics.name
  scopes              = [azurerm_eventhub_namespace.manufacturing_telemetry.id]
  description         = "Alert when manufacturing equipment requires immediate attention"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.EventHub/namespaces"
    metric_name      = "IncomingMessages"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 1000
  }

  action {
    action_group_id = azurerm_monitor_action_group.manufacturing_maintenance[0].id
  }

  tags = merge(local.common_tags, {
    Component = "Alerting"
    Service   = "Metric Alert"
  })
}

# Create activity log alert for Stream Analytics job failures
resource "azurerm_monitor_activity_log_alert" "stream_analytics_failure" {
  count               = var.enable_alerts ? 1 : 0
  name                = "StreamAnalyticsJobFailure"
  resource_group_name = azurerm_resource_group.manufacturing_analytics.name
  scopes              = [azurerm_resource_group.manufacturing_analytics.id]
  description         = "Alert when Stream Analytics job fails or stops"

  criteria {
    resource_id    = azurerm_stream_analytics_job.manufacturing_analytics.id
    operation_name = "Microsoft.StreamAnalytics/streamingjobs/stop/action"
    category       = "Administrative"
  }

  action {
    action_group_id = azurerm_monitor_action_group.manufacturing_maintenance[0].id
  }

  tags = merge(local.common_tags, {
    Component = "Alerting"
    Service   = "Activity Log Alert"
  })
}

# ==============================================================================
# DIAGNOSTIC SETTINGS FOR ALL RESOURCES
# ==============================================================================

# Configure diagnostic settings for Event Hubs namespace
resource "azurerm_monitor_diagnostic_setting" "event_hubs_diagnostics" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "EventHubsDiagnostics"
  target_resource_id         = azurerm_eventhub_namespace.manufacturing_telemetry.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.manufacturing_monitoring.id

  enabled_log {
    category = "ArchiveLogs"
  }

  enabled_log {
    category = "OperationalLogs"
  }

  enabled_log {
    category = "AutoScaleLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Configure diagnostic settings for Stream Analytics job
resource "azurerm_monitor_diagnostic_setting" "stream_analytics_diagnostics" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "StreamAnalyticsDiagnostics"
  target_resource_id         = azurerm_stream_analytics_job.manufacturing_analytics.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.manufacturing_monitoring.id

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

# Configure diagnostic settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage_diagnostics" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "StorageDiagnostics"
  target_resource_id         = azurerm_storage_account.manufacturing_data.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.manufacturing_monitoring.id

  metric {
    category = "Transaction"
    enabled  = true
  }

  metric {
    category = "Capacity"
    enabled  = true
  }
}

# ==============================================================================
# AZURE IOT OPERATIONS CONFIGURATION (PLACEHOLDER)
# ==============================================================================

# Note: Azure IoT Operations requires an Azure Arc-enabled Kubernetes cluster
# and is deployed using Azure CLI or ARM templates, not Terraform AzureRM provider
# This section provides configuration placeholders for IoT Operations deployment

# IoT Operations configuration data for manual deployment
locals {
  iot_operations_config = var.enable_iot_operations && var.arc_cluster_name != null ? {
    instance_name = "iot-ops-${local.resource_suffix}"
    arc_cluster_resource_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.arc_cluster_resource_group}/providers/Microsoft.Kubernetes/connectedClusters/${var.arc_cluster_name}"
    
    # MQTT broker configuration
    mqtt_broker = {
      listener_port = 1883
      authentication_method = "x509"
      topics = [
        "manufacturing/+/telemetry",
        "manufacturing/+/alerts"
      ]
    }
    
    # Data flow configurations
    dataflows = [
      {
        name = "opc-ua-to-eventhub"
        source_type = "opcua"
        source_endpoint = "opc.tcp://manufacturing-server:4840"
        destination_type = "eventhub"
        destination_connection_string = azurerm_eventhub_authorization_rule.iot_operations_access.primary_connection_string
        destination_event_hub = azurerm_eventhub.manufacturing_telemetry_hub.name
      },
      {
        name = "mqtt-to-eventhub"
        source_type = "mqtt"
        source_topic = "manufacturing/+/telemetry"
        destination_type = "eventhub"
        destination_connection_string = azurerm_eventhub_authorization_rule.iot_operations_access.primary_connection_string
        destination_event_hub = azurerm_eventhub.manufacturing_telemetry_hub.name
      }
    ]
  } : null
}

# Configuration file for IoT Operations deployment
resource "local_file" "iot_operations_config" {
  count = var.enable_iot_operations && var.arc_cluster_name != null ? 1 : 0
  
  filename = "${path.module}/iot-operations-config.yaml"
  content = yamlencode({
    apiVersion = "v1"
    kind = "ConfigMap"
    metadata = {
      name = "manufacturing-iot-config"
      namespace = "azure-iot-operations"
    }
    data = {
      "mqtt-broker-config" = yamlencode({
        listener = {
          name = "manufacturing-listener"
          port = local.iot_operations_config.mqtt_broker.listener_port
          protocol = "mqtt"
        }
        authentication = {
          method = local.iot_operations_config.mqtt_broker.authentication_method
        }
        topics = [for topic in local.iot_operations_config.mqtt_broker.topics : {
          name = topic
          qos = topic == "manufacturing/+/alerts" ? 2 : 1
        }]
      })
      "dataflow-config" = yamlencode({
        sources = [
          {
            name = "opc-ua-source"
            type = "opcua"
            endpoint = local.iot_operations_config.dataflows[0].source_endpoint
          },
          {
            name = "mqtt-source"
            type = "mqtt"
            topic = local.iot_operations_config.dataflows[1].source_topic
          }
        ]
        transforms = [
          {
            name = "anomaly-detection"
            type = "function"
            function = "detectAnomalies"
          },
          {
            name = "oee-calculation"
            type = "aggregate"
            window = "5m"
          }
        ]
        destinations = [
          {
            name = "cloud-eventhub"
            type = "eventhub"
            connectionString = local.iot_operations_config.dataflows[0].destination_connection_string
          }
        ]
      })
    }
  })
}

# ==============================================================================
# RBAC ASSIGNMENTS FOR MANAGED IDENTITIES
# ==============================================================================

# Assign Event Hubs Data Sender role to Stream Analytics managed identity
resource "azurerm_role_assignment" "stream_analytics_eventhubs_sender" {
  count                = var.enable_managed_identity ? 1 : 0
  scope                = azurerm_eventhub_namespace.manufacturing_telemetry.id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = azurerm_stream_analytics_job.manufacturing_analytics.identity[0].principal_id
}

# Assign Storage Blob Data Contributor role to Stream Analytics managed identity
resource "azurerm_role_assignment" "stream_analytics_storage_contributor" {
  count                = var.enable_managed_identity ? 1 : 0
  scope                = azurerm_storage_account.manufacturing_data.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_stream_analytics_job.manufacturing_analytics.identity[0].principal_id
}

# ==============================================================================
# OUTPUT CONFIGURATION
# ==============================================================================

# Add timing for resource creation sequencing
resource "time_sleep" "wait_for_resources" {
  depends_on = [
    azurerm_eventhub_namespace.manufacturing_telemetry,
    azurerm_stream_analytics_job.manufacturing_analytics,
    azurerm_log_analytics_workspace.manufacturing_monitoring
  ]
  create_duration = "30s"
}