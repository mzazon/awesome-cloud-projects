# Smart City Infrastructure Monitoring with IoT and AI
# This Terraform configuration deploys a complete smart city monitoring solution
# using Google Cloud Pub/Sub, Vertex AI, Cloud Monitoring, and BigQuery

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  # Common naming convention with random suffix
  name_suffix = random_string.suffix.result
  
  # Resource names
  dataset_name        = "${var.resource_prefix}_data_${local.name_suffix}"
  topic_name         = "${var.resource_prefix}-telemetry-${local.name_suffix}"
  bucket_name        = "${var.resource_prefix}-ml-${local.name_suffix}"
  service_account_id = "${var.resource_prefix}-sensors-${local.name_suffix}"
  
  # Common labels applied to all resources
  common_labels = merge(var.additional_labels, {
    environment    = var.environment
    project       = "smart-city-monitoring"
    managed-by    = "terraform"
    recipe-id     = "3c7d9f8a"
    creation-date = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(var.apis_to_enable)
  
  project = var.project_id
  service = each.value
  
  # Prevent destruction of APIs to avoid breaking dependencies
  disable_on_destroy = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

# Create service account for IoT device authentication
resource "google_service_account" "iot_sensors" {
  account_id   = local.service_account_id
  display_name = var.service_account_display_name
  description  = "Service account for smart city IoT sensor data ingestion"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Grant Pub/Sub publisher role to service account
resource "google_project_iam_member" "pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.iot_sensors.email}"
}

# Grant BigQuery data editor role for function
resource "google_project_iam_member" "bigquery_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.iot_sensors.email}"
}

# Grant monitoring metric writer role
resource "google_project_iam_member" "monitoring_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.iot_sensors.email}"
}

# Create main Pub/Sub topic for sensor telemetry
resource "google_pubsub_topic" "sensor_telemetry" {
  name    = local.topic_name
  project = var.project_id
  
  labels = local.common_labels

  message_retention_duration = var.pubsub_message_retention_duration

  depends_on = [google_project_service.required_apis]
}

# Create dead letter topic for failed messages
resource "google_pubsub_topic" "dlq" {
  name    = "${local.topic_name}-dlq"
  project = var.project_id
  
  labels = local.common_labels

  message_retention_duration = var.pubsub_message_retention_duration
}

# Create subscription for BigQuery streaming
resource "google_pubsub_subscription" "bigquery_streaming" {
  name    = "${local.topic_name}-bigquery"
  topic   = google_pubsub_topic.sensor_telemetry.name
  project = var.project_id
  
  labels = local.common_labels

  ack_deadline_seconds = var.pubsub_ack_deadline_seconds

  # Dead letter policy configuration
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = var.pubsub_max_retry_delay
  }

  # Enable exactly-once delivery for data consistency
  enable_exactly_once_delivery = true
}

# Create subscription for ML processing
resource "google_pubsub_subscription" "ml_processing" {
  name    = "${local.topic_name}-ml"
  topic   = google_pubsub_topic.sensor_telemetry.name
  project = var.project_id
  
  labels = local.common_labels

  ack_deadline_seconds = 120

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq.id
    max_delivery_attempts = 3
  }

  retry_policy {
    minimum_backoff = "30s"
    maximum_backoff = var.pubsub_max_retry_delay
  }

  enable_exactly_once_delivery = true
}

# Create dead letter queue subscription
resource "google_pubsub_subscription" "dlq_subscription" {
  name    = "${local.topic_name}-dlq-sub"
  topic   = google_pubsub_topic.dlq.name
  project = var.project_id
  
  labels = local.common_labels

  ack_deadline_seconds = 300
}

# Create BigQuery dataset for sensor data analytics
resource "google_bigquery_dataset" "smart_city_data" {
  dataset_id  = local.dataset_name
  project     = var.project_id
  location    = var.bigquery_location
  description = "Smart city sensor data and analytics"

  labels = local.common_labels

  # Enable deletion protection for production data
  delete_contents_on_destroy = var.environment != "prod"

  # Access control configuration
  access {
    role          = "OWNER"
    user_by_email = google_service_account.iot_sensors.email
  }

  access {
    role          = "READER"
    special_group = "projectReaders"
  }

  access {
    role          = "WRITER"
    special_group = "projectWriters"
  }

  depends_on = [google_project_service.required_apis]
}

# Create sensor readings table with optimized schema
resource "google_bigquery_table" "sensor_readings" {
  dataset_id          = google_bigquery_dataset.smart_city_data.dataset_id
  table_id            = "sensor_readings"
  project             = var.project_id
  description         = "Real-time sensor readings from city infrastructure"
  deletion_protection = var.environment == "prod"

  labels = local.common_labels

  # Time partitioning for query performance
  time_partitioning {
    type                     = "DAY"
    field                    = "timestamp"
    expiration_ms           = var.bigquery_partition_expiration_ms
    require_partition_filter = true
  }

  # Clustering for query optimization
  clustering = ["sensor_type", "location"]

  # Table expiration
  expiration_time = var.bigquery_table_expiration_ms

  schema = jsonencode([
    {
      name        = "device_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Unique identifier for the IoT device"
    },
    {
      name        = "sensor_type"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Type of sensor (traffic, air_quality, energy, etc.)"
    },
    {
      name        = "location"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Physical location of the sensor"
    },
    {
      name        = "timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Timestamp when the reading was taken"
    },
    {
      name        = "value"
      type        = "FLOAT"
      mode        = "REQUIRED"
      description = "Sensor reading value"
    },
    {
      name        = "unit"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Unit of measurement for the sensor value"
    },
    {
      name        = "metadata"
      type        = "JSON"
      mode        = "NULLABLE"
      description = "Additional metadata associated with the reading"
    },
    {
      name        = "ingestion_time"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Timestamp when the data was ingested into BigQuery"
    }
  ])
}

# Create anomalies table for ML results
resource "google_bigquery_table" "anomalies" {
  dataset_id          = google_bigquery_dataset.smart_city_data.dataset_id
  table_id            = "anomalies"
  project             = var.project_id
  description         = "Anomaly detection results from ML models"
  deletion_protection = var.environment == "prod"

  labels = local.common_labels

  time_partitioning {
    type                     = "DAY"
    field                    = "timestamp"
    expiration_ms           = var.bigquery_partition_expiration_ms
    require_partition_filter = true
  }

  schema = jsonencode([
    {
      name        = "device_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Device that generated the anomaly"
    },
    {
      name        = "timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Timestamp of the anomalous reading"
    },
    {
      name        = "anomaly_score"
      type        = "FLOAT"
      mode        = "REQUIRED"
      description = "Anomaly score from ML model (0-1)"
    },
    {
      name        = "anomaly_type"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Type of anomaly detected"
    },
    {
      name        = "confidence"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "Model confidence in the anomaly detection"
    },
    {
      name        = "model_version"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Version of the ML model used"
    }
  ])
}

# Create aggregated metrics table for dashboards
resource "google_bigquery_table" "sensor_metrics" {
  dataset_id          = google_bigquery_dataset.smart_city_data.dataset_id
  table_id            = "sensor_metrics"
  project             = var.project_id
  description         = "Aggregated sensor metrics for dashboard visualization"
  deletion_protection = var.environment == "prod"

  labels = local.common_labels

  schema = jsonencode([
    {
      name        = "sensor_type"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Type of sensor"
    },
    {
      name        = "location"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Sensor location"
    },
    {
      name        = "date"
      type        = "DATE"
      mode        = "REQUIRED"
      description = "Date for the aggregated metrics"
    },
    {
      name        = "avg_value"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "Average sensor value for the day"
    },
    {
      name        = "min_value"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "Minimum sensor value for the day"
    },
    {
      name        = "max_value"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "Maximum sensor value for the day"
    },
    {
      name        = "anomaly_count"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Number of anomalies detected for the day"
    }
  ])
}

# Create Cloud Storage bucket for ML models and artifacts
resource "google_storage_bucket" "ml_artifacts" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id

  labels = local.common_labels

  # Security configuration
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention    = var.enable_public_access_prevention ? "enforced" : "inherited"

  # Versioning for ML model management
  versioning {
    enabled = var.enable_storage_versioning
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age_days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age_days * 3
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Create organized folder structure in Cloud Storage
resource "google_storage_bucket_object" "ml_folders" {
  for_each = toset([
    "models/.gitkeep",
    "training-data/.gitkeep", 
    "pipelines/.gitkeep",
    "monitoring/.gitkeep"
  ])

  name    = each.value
  bucket  = google_storage_bucket.ml_artifacts.name
  content = "Created by Terraform for smart city monitoring solution"
}

# Create archive for Cloud Function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/sensor-processor-${local.name_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/function_source/main.py", {
      project_id   = var.project_id
      dataset_name = local.dataset_name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source/sensor-processor-${local.name_suffix}.zip"
  bucket = google_storage_bucket.ml_artifacts.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# Deploy Cloud Function for sensor data processing
resource "google_cloudfunctions_function" "sensor_processor" {
  name    = "process-sensor-data-${local.name_suffix}"
  project = var.project_id
  region  = var.region

  description = "Process IoT sensor data with validation and BigQuery insertion"
  runtime     = var.function_runtime

  available_memory_mb   = var.function_memory_mb
  timeout               = var.function_timeout_seconds
  max_instances        = var.function_max_instances
  source_archive_bucket = google_storage_bucket.ml_artifacts.name
  source_archive_object = google_storage_bucket_object.function_source.name
  entry_point          = "process_sensor_data"

  labels = local.common_labels

  # Pub/Sub trigger configuration
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.sensor_telemetry.name
  }

  # Environment variables for function configuration
  environment_variables = {
    PROJECT_ID   = var.project_id
    DATASET_NAME = local.dataset_name
    ENVIRONMENT  = var.environment
  }

  # Service account for secure access
  service_account_email = google_service_account.iot_sensors.email

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# Create Vertex AI dataset for ML training
resource "google_vertex_ai_dataset" "sensor_data" {
  display_name   = "smart-city-sensor-data-${local.name_suffix}"
  metadata_schema_uri = "gs://google-cloud-aiplatform/schema/dataset/metadata/tabular_1.0.0.yaml"
  region         = var.vertex_ai_region
  project        = var.project_id

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create monitoring dashboard for smart city infrastructure
resource "google_monitoring_dashboard" "smart_city_dashboard" {
  count = var.dashboard_enabled ? 1 : 0

  dashboard_json = templatefile("${path.module}/monitoring/dashboard.json", {
    project_id = var.project_id
    topic_name = local.topic_name
  })

  project = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Create alert policy for high message rates
resource "google_monitoring_alert_policy" "high_message_rate" {
  count = var.alert_policy_enabled ? 1 : 0

  display_name = "Smart City - High Sensor Message Rate"
  project      = var.project_id
  
  documentation {
    content = "Alert when sensor message rate exceeds threshold, indicating potential data spike or system issues"
  }

  conditions {
    display_name = "High message rate condition"
    
    condition_threshold {
      filter          = "resource.type=\"pubsub_topic\" AND resource.labels.topic_id=\"${local.topic_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 1000
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  enabled = true

  depends_on = [google_project_service.required_apis]
}

# Create alert policy for Cloud Function errors
resource "google_monitoring_alert_policy" "function_errors" {
  count = var.alert_policy_enabled ? 1 : 0

  display_name = "Smart City - Cloud Function Errors"
  project      = var.project_id
  
  documentation {
    content = "Alert when Cloud Function error rate exceeds threshold"
  }

  conditions {
    display_name = "Function error rate condition"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions_function.sensor_processor.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.05 # 5% error rate
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
      }
    }
  }

  enabled = true

  depends_on = [google_project_service.required_apis]
}

# Create budget alert for cost management
resource "google_billing_budget" "smart_city_budget" {
  count = var.budget_amount > 0 ? 1 : 0

  billing_account = data.google_billing_account.account.id
  display_name    = "Smart City Monitoring Budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]
    
    labels = {
      "managed-by" = ["terraform"]
      "project"    = ["smart-city-monitoring"]
    }
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
    spend_basis      = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.8
    spend_basis      = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis      = "CURRENT_SPEND"
  }

  depends_on = [google_project_service.required_apis]
}

# Data source for billing account
data "google_billing_account" "account" {
  open = true
}

# Create log sink for centralized logging
resource "google_logging_project_sink" "smart_city_logs" {
  name        = "smart-city-logs-${local.name_suffix}"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.ml_artifacts.name}"

  # Filter for relevant logs
  filter = <<-EOT
    (resource.type="cloud_function" AND resource.labels.function_name="${google_cloudfunctions_function.sensor_processor.name}")
    OR (resource.type="pubsub_topic" AND resource.labels.topic_id="${local.topic_name}")
    OR (resource.type="bigquery_table" AND resource.labels.table_id="sensor_readings")
  EOT

  # Use unique writer identity
  unique_writer_identity = true

  depends_on = [google_project_service.required_apis]
}

# Grant storage admin to log sink writer
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.ml_artifacts.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.smart_city_logs.writer_identity
}