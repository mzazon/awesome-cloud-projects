# Multi-Stream Data Processing Workflows with Pub/Sub Lite and Application Integration
# This Terraform configuration creates a complete data streaming architecture using:
# - Pub/Sub Lite for cost-optimized partition-based messaging
# - Application Integration for workflow orchestration
# - Cloud Dataflow for stream processing
# - BigQuery for real-time analytics
# - Cloud Storage for data lake functionality

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  random_suffix = random_id.suffix.hex
  
  # Common labels for all resources
  common_labels = {
    project     = "multi-stream-data-processing"
    environment = var.environment
    terraform   = "true"
    recipe      = "pub-sub-lite-application-integration"
  }
  
  # Resource naming
  lite_topic_iot    = "iot-data-stream-${local.random_suffix}"
  lite_topic_app    = "app-events-stream-${local.random_suffix}"
  lite_topic_logs   = "system-logs-stream-${local.random_suffix}"
  subscription_prefix = "analytics-sub-${local.random_suffix}"
  dataset_name      = "streaming_analytics_${local.random_suffix}"
  bucket_name       = "data-lake-${var.project_id}-${local.random_suffix}"
  service_account_id = "app-integration-sa-${local.random_suffix}"
  
  # Topic configurations optimized for different data stream characteristics
  topics = {
    iot_data = {
      name                   = local.lite_topic_iot
      partitions            = 4
      publish_capacity      = 4
      subscribe_capacity    = 8
      per_partition_bytes   = 32212254720  # 30 GiB
      retention_duration    = "604800s"    # 7 days
      description          = "IoT sensor data stream - high frequency, small messages"
    }
    app_events = {
      name                   = local.lite_topic_app
      partitions            = 2
      publish_capacity      = 2
      subscribe_capacity    = 4
      per_partition_bytes   = 53687091200  # 50 GiB
      retention_duration    = "1209600s"   # 14 days
      description          = "Application events stream - medium frequency, structured data"
    }
    system_logs = {
      name                   = local.lite_topic_logs
      partitions            = 3
      publish_capacity      = 3
      subscribe_capacity    = 6
      per_partition_bytes   = 42949672960  # 40 GiB
      retention_duration    = "2592000s"   # 30 days
      description          = "System logs stream - variable frequency, larger messages"
    }
  }
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "pubsublite.googleapis.com",
    "integrations.googleapis.com",
    "dataflow.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Keep services enabled when destroying resources
  disable_on_destroy = false
}

# Create Pub/Sub Lite throughput reservation for cost optimization
resource "google_pubsub_lite_reservation" "reservation" {
  name   = "stream-processing-reservation-${local.random_suffix}"
  project = var.project_id
  region  = var.region
  
  # Total throughput capacity (sum of all topic publish capacities)
  throughput_capacity = var.throughput_capacity
  
  depends_on = [google_project_service.apis]
}

# Create Pub/Sub Lite topics with optimized configurations
resource "google_pubsub_lite_topic" "topics" {
  for_each = local.topics
  
  name    = each.value.name
  project = var.project_id
  region  = var.region
  
  partition_config {
    count = each.value.partitions
    capacity {
      publish_mib_per_sec   = each.value.publish_capacity
      subscribe_mib_per_sec = each.value.subscribe_capacity
    }
  }
  
  retention_config {
    per_partition_bytes = each.value.per_partition_bytes
    period             = each.value.retention_duration
  }
  
  reservation_config {
    throughput_reservation = google_pubsub_lite_reservation.reservation.name
  }
  
  depends_on = [
    google_project_service.apis,
    google_pubsub_lite_reservation.reservation
  ]
}

# Create Pub/Sub Lite subscriptions for analytics processing
resource "google_pubsub_lite_subscription" "analytics_subscriptions" {
  for_each = local.topics
  
  name     = "${local.subscription_prefix}-analytics-${each.key}"
  project  = var.project_id
  region   = var.region
  topic    = google_pubsub_lite_topic.topics[each.key].name
  
  delivery_config {
    delivery_requirement = "DELIVER_IMMEDIATELY"
  }
  
  depends_on = [google_pubsub_lite_topic.topics]
}

# Create additional workflow subscriptions for critical data streams
resource "google_pubsub_lite_subscription" "workflow_subscriptions" {
  for_each = {
    iot_data   = local.topics.iot_data
    app_events = local.topics.app_events
  }
  
  name     = "${local.subscription_prefix}-workflow-${each.key}"
  project  = var.project_id
  region   = var.region
  topic    = google_pubsub_lite_topic.topics[each.key].name
  
  delivery_config {
    delivery_requirement = "DELIVER_AFTER_STORED"
  }
  
  depends_on = [google_pubsub_lite_topic.topics]
}

# Create BigQuery dataset for analytics
resource "google_bigquery_dataset" "analytics_dataset" {
  dataset_id  = local.dataset_name
  project     = var.project_id
  location    = var.dataset_location
  description = "Streaming analytics dataset for multi-stream data processing"
  
  # Data retention and lifecycle management
  default_table_expiration_ms = var.retention_days * 24 * 60 * 60 * 1000
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Create BigQuery tables with partitioning and clustering for optimal performance
resource "google_bigquery_table" "iot_sensor_data" {
  dataset_id = google_bigquery_dataset.analytics_dataset.dataset_id
  table_id   = "iot_sensor_data"
  project    = var.project_id
  
  description = "IoT sensor data with time partitioning and device clustering"
  
  # Time partitioning configuration
  time_partitioning {
    type                     = "DAY"
    field                   = "timestamp"
    expiration_ms           = var.retention_days * 24 * 60 * 60 * 1000
    require_partition_filter = true
  }
  
  # Clustering for query performance optimization
  clustering = ["device_id", "sensor_type"]
  
  schema = jsonencode([
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Sensor reading timestamp"
    },
    {
      name = "device_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique device identifier"
    },
    {
      name = "sensor_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of sensor (temperature, humidity, pressure)"
    },
    {
      name = "value"
      type = "FLOAT64"
      mode = "REQUIRED"
      description = "Sensor reading value"
    },
    {
      name = "location"
      type = "GEOGRAPHY"
      mode = "NULLABLE"
      description = "Device geographic location"
    },
    {
      name = "metadata"
      type = "JSON"
      mode = "NULLABLE"
      description = "Additional sensor metadata"
    }
  ])
  
  labels = local.common_labels
}

resource "google_bigquery_table" "application_events" {
  dataset_id = google_bigquery_dataset.analytics_dataset.dataset_id
  table_id   = "application_events"
  project    = var.project_id
  
  description = "Application events with time partitioning and user clustering"
  
  # Time partitioning configuration
  time_partitioning {
    type                     = "DAY"
    field                   = "event_timestamp"
    expiration_ms           = var.retention_days * 24 * 60 * 60 * 1000
    require_partition_filter = true
  }
  
  # Clustering for query performance optimization
  clustering = ["user_id", "event_type"]
  
  schema = jsonencode([
    {
      name = "event_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Event occurrence timestamp"
    },
    {
      name = "user_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "User identifier"
    },
    {
      name = "event_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of event (click, view, purchase, etc.)"
    },
    {
      name = "session_id"
      type = "STRING"
      mode = "NULLABLE"
      description = "User session identifier"
    },
    {
      name = "properties"
      type = "JSON"
      mode = "NULLABLE"
      description = "Event properties and metadata"
    },
    {
      name = "revenue"
      type = "FLOAT64"
      mode = "NULLABLE"
      description = "Revenue associated with event"
    }
  ])
  
  labels = local.common_labels
}

resource "google_bigquery_table" "system_logs_summary" {
  dataset_id = google_bigquery_dataset.analytics_dataset.dataset_id
  table_id   = "system_logs_summary"
  project    = var.project_id
  
  description = "System logs aggregation with time partitioning and service clustering"
  
  # Time partitioning configuration
  time_partitioning {
    type                     = "DAY"
    field                   = "log_timestamp"
    expiration_ms           = var.retention_days * 24 * 60 * 60 * 1000
    require_partition_filter = true
  }
  
  # Clustering for query performance optimization
  clustering = ["service_name", "log_level"]
  
  schema = jsonencode([
    {
      name = "log_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Log entry timestamp"
    },
    {
      name = "service_name"
      type = "STRING"
      mode = "REQUIRED"
      description = "Service generating the log"
    },
    {
      name = "log_level"
      type = "STRING"
      mode = "REQUIRED"
      description = "Log severity level"
    },
    {
      name = "error_count"
      type = "INT64"
      mode = "NULLABLE"
      description = "Number of errors in time window"
    },
    {
      name = "response_time_ms"
      type = "FLOAT64"
      mode = "NULLABLE"
      description = "Average response time in milliseconds"
    },
    {
      name = "request_count"
      type = "INT64"
      mode = "NULLABLE"
      description = "Number of requests in time window"
    }
  ])
  
  labels = local.common_labels
}

# Create Cloud Storage bucket for data lake
resource "google_storage_bucket" "data_lake" {
  name          = local.bucket_name
  location      = var.region
  project       = var.project_id
  storage_class = var.storage_class
  
  # Enable versioning for data protection
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = var.retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Create folder structure in Cloud Storage for organized data management
resource "google_storage_bucket_object" "dataflow_folders" {
  for_each = toset([
    "dataflow-temp/",
    "dataflow-staging/",
    "templates/"
  ])
  
  name   = each.value
  bucket = google_storage_bucket.data_lake.name
  content = " "  # Empty content for folder creation
  
  depends_on = [google_storage_bucket.data_lake]
}

# Create service account for Application Integration
resource "google_service_account" "app_integration_sa" {
  account_id   = local.service_account_id
  display_name = "Application Integration Service Account"
  description  = "Service account for data processing workflows and Application Integration"
  project      = var.project_id
  
  depends_on = [google_project_service.apis]
}

# IAM bindings for the service account following least privilege principle
resource "google_project_iam_member" "app_integration_permissions" {
  for_each = toset([
    "roles/pubsublite.editor",
    "roles/bigquery.dataEditor",
    "roles/storage.objectAdmin",
    "roles/dataflow.admin",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.app_integration_sa.email}"
  
  depends_on = [google_service_account.app_integration_sa]
}

# Create Cloud Monitoring dashboard for pipeline observability
resource "google_monitoring_dashboard" "pipeline_dashboard" {
  project        = var.project_id
  dashboard_json = jsonencode({
    displayName = "Multi-Stream Data Processing Pipeline"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Pub/Sub Lite Message Rate"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"pubsub_lite_topic\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Messages/sec"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "BigQuery Streaming Inserts"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"bigquery_table\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Rows/sec"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 12
          height = 4
          widget = {
            title = "Cloud Storage Usage"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gcs_bucket\""
                      aggregation = {
                        alignmentPeriod  = "300s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Bytes"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.apis]
}

# Create alert policy for high message backlog
resource "google_monitoring_alert_policy" "high_message_backlog" {
  project      = var.project_id
  display_name = "High Pub/Sub Lite Message Backlog"
  
  conditions {
    display_name = "Message backlog too high"
    condition_threshold {
      filter         = "resource.type=\"pubsub_lite_subscription\""
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 10000
      duration       = "300s"
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  alert_strategy {
    auto_close = "604800s"  # 7 days
  }
  
  combiner = "OR"
  enabled  = true
  
  notification_channels = var.notification_channels
  
  depends_on = [google_project_service.apis]
}