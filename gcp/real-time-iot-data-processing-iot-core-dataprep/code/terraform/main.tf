# Main Terraform Configuration for IoT Data Processing Pipeline
# This file creates the complete infrastructure for real-time IoT data processing
# using Google Cloud IoT Core, Pub/Sub, Dataprep, and BigQuery

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent resource naming and configuration
locals {
  # Common resource naming with environment and random suffix
  resource_suffix = "${var.environment}-${random_id.suffix.hex}"
  
  # Merge default and custom labels
  common_labels = merge(var.labels, {
    terraform   = "true"
    environment = var.environment
    created     = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Full resource names with suffix
  iot_registry_full_name       = "${var.iot_registry_name}-${local.resource_suffix}"
  pubsub_topic_full_name       = "${var.pubsub_topic_name}-${local.resource_suffix}"
  pubsub_subscription_full_name = "${var.pubsub_subscription_name}-${local.resource_suffix}"
  bigquery_dataset_full_name   = "${var.bigquery_dataset_name}_${random_id.suffix.hex}"
  storage_bucket_full_name     = "${var.project_id}-${var.storage_bucket_name}-${local.resource_suffix}"
  dataprep_sa_full_name        = "${var.dataprep_service_account_name}-${local.resource_suffix}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of critical APIs
  disable_on_destroy = false
  
  # Add dependency management for proper ordering
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Pub/Sub topic for IoT telemetry data
resource "google_pubsub_topic" "iot_telemetry" {
  name    = local.pubsub_topic_full_name
  project = var.project_id
  
  labels = local.common_labels
  
  # Configure message retention and storage policy
  message_retention_duration = var.message_retention_duration
  
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
  
  # Schema configuration for IoT data validation
  schema_settings {
    schema   = google_pubsub_schema.iot_telemetry_schema.id
    encoding = "JSON"
  }
  
  depends_on = [google_project_service.apis]
}

# Define schema for IoT telemetry messages
resource "google_pubsub_schema" "iot_telemetry_schema" {
  name       = "iot-telemetry-schema-${local.resource_suffix}"
  type       = "AVRO"
  definition = jsonencode({
    type = "record"
    name = "IoTTelemetry"
    fields = [
      {
        name = "device_id"
        type = "string"
      },
      {
        name = "timestamp"
        type = "string"
      },
      {
        name = "temperature"
        type = ["null", "float"]
        default = null
      },
      {
        name = "humidity"
        type = ["null", "float"]
        default = null
      },
      {
        name = "pressure"
        type = ["null", "float"]
        default = null
      },
      {
        name = "location"
        type = "string"
      },
      {
        name = "data_quality_score"
        type = "float"
      }
    ]
  })
  
  depends_on = [google_project_service.apis]
}

# Create Pub/Sub subscription for data processing
resource "google_pubsub_subscription" "iot_data_subscription" {
  name  = local.pubsub_subscription_full_name
  topic = google_pubsub_topic.iot_telemetry.name
  
  labels = local.common_labels
  
  # Configure acknowledgment deadline and message retention
  ack_deadline_seconds       = var.ack_deadline_seconds
  retain_acked_messages      = true
  message_retention_duration = var.message_retention_duration
  
  # Configure exponential backoff for retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Configure dead letter policy for failed messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  
  # Enable exactly-once delivery for data consistency
  enable_exactly_once_delivery = true
  
  depends_on = [google_project_service.apis]
}

# Create dead letter topic for failed messages
resource "google_pubsub_topic" "dead_letter" {
  name    = "${local.pubsub_topic_full_name}-dead-letter"
  project = var.project_id
  
  labels = merge(local.common_labels, {
    purpose = "dead-letter"
  })
  
  depends_on = [google_project_service.apis]
}

# Create IoT Core device registry
resource "google_cloudiot_registry" "iot_registry" {
  name   = local.iot_registry_full_name
  region = var.region
  
  # Configure telemetry routing to Pub/Sub
  event_notification_configs {
    pubsub_topic_name = google_pubsub_topic.iot_telemetry.id
  }
  
  # Configure state change notifications
  state_notification_config = {
    pubsub_topic_name = google_pubsub_topic.iot_telemetry.id
  }
  
  # Configure MQTT and HTTP protocols
  mqtt_config = {
    mqtt_enabled_state = "MQTT_ENABLED"
  }
  
  http_config = {
    http_enabled_state = "HTTP_ENABLED"
  }
  
  # Configure logging for debugging
  log_level = var.enable_logging ? "INFO" : "NONE"
  
  depends_on = [google_project_service.apis]
}

# Generate TLS private key for IoT device authentication
resource "tls_private_key" "device_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate self-signed certificate for IoT device
resource "tls_self_signed_cert" "device_cert" {
  private_key_pem = tls_private_key.device_key.private_key_pem
  
  subject {
    common_name  = var.device_name
    organization = "IoT Data Processing Demo"
  }
  
  validity_period_hours = 8760 # 1 year
  
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth",
  ]
}

# Create IoT device with certificate authentication
resource "google_cloudiot_device" "iot_device" {
  name     = var.device_name
  registry = google_cloudiot_registry.iot_registry.id
  
  credentials {
    public_key {
      format      = "RSA_X509_PEM"
      key         = tls_self_signed_cert.device_cert.cert_pem
    }
  }
  
  # Configure device metadata
  metadata = {
    device_type = "temperature_sensor"
    location    = "warehouse"
    model       = "TempSensor-v1.0"
  }
  
  # Block device configuration updates
  blocked = false
  
  depends_on = [google_cloudiot_registry.iot_registry]
}

# Create BigQuery dataset for IoT analytics
resource "google_bigquery_dataset" "iot_analytics" {
  dataset_id  = local.bigquery_dataset_full_name
  project     = var.project_id
  location    = var.bigquery_location
  
  friendly_name   = "IoT Analytics Dataset"
  description     = "Dataset for storing and analyzing IoT sensor data"
  
  labels = local.common_labels
  
  # Configure dataset access and permissions
  access {
    role          = "OWNER"
    user_by_email = "terraform@${var.project_id}.iam.gserviceaccount.com"
  }
  
  access {
    role          = "READER"
    special_group = "projectReaders"
  }
  
  access {
    role          = "WRITER"
    special_group = "projectWriters"
  }
  
  # Configure default table expiration (90 days)
  default_table_expiration_ms = 7776000000
  
  depends_on = [google_project_service.apis]
}

# Create BigQuery table for sensor readings
resource "google_bigquery_table" "sensor_readings" {
  dataset_id = google_bigquery_dataset.iot_analytics.dataset_id
  table_id   = var.bigquery_table_name
  project    = var.project_id
  
  friendly_name = "Sensor Readings Table"
  description   = "Table for storing processed IoT sensor readings"
  
  labels = local.common_labels
  
  # Configure time partitioning for optimal query performance
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
  
  # Configure clustering for improved query performance
  clustering = ["device_id", "location"]
  
  # Define table schema optimized for IoT data
  schema = jsonencode([
    {
      name = "device_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the IoT device"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when the sensor reading was taken"
    },
    {
      name = "temperature"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Temperature reading in Celsius"
    },
    {
      name = "humidity"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Humidity reading as percentage"
    },
    {
      name = "pressure"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Atmospheric pressure reading in hPa"
    },
    {
      name = "location"
      type = "STRING"
      mode = "REQUIRED"
      description = "Physical location of the sensor"
    },
    {
      name = "data_quality_score"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Quality score for the sensor reading (0.0 to 1.0)"
    }
  ])
  
  depends_on = [google_bigquery_dataset.iot_analytics]
}

# Create Cloud Storage bucket for Dataprep staging
resource "google_storage_bucket" "dataprep_staging" {
  name     = local.storage_bucket_full_name
  location = var.region
  project  = var.project_id
  
  labels = local.common_labels
  
  # Configure storage class for cost optimization
  storage_class = var.storage_class
  
  # Configure versioning for data protection
  versioning {
    enabled = true
  }
  
  # Configure lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Configure uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Configure encryption
  encryption {
    default_kms_key_name = google_kms_crypto_key.dataprep_key.id
  }
  
  depends_on = [google_project_service.apis]
}

# Create KMS key ring for encryption
resource "google_kms_key_ring" "iot_keyring" {
  name     = "iot-pipeline-keyring-${local.resource_suffix}"
  location = var.region
  project  = var.project_id
  
  depends_on = [google_project_service.apis]
}

# Create KMS crypto key for Dataprep encryption
resource "google_kms_crypto_key" "dataprep_key" {
  name     = "dataprep-key"
  key_ring = google_kms_key_ring.iot_keyring.id
  
  purpose = "ENCRYPT_DECRYPT"
  
  # Configure key rotation
  rotation_period = "2592000s" # 30 days
  
  depends_on = [google_kms_key_ring.iot_keyring]
}

# Create service account for Dataprep operations
resource "google_service_account" "dataprep_sa" {
  account_id   = local.dataprep_sa_full_name
  display_name = "Dataprep Pipeline Service Account"
  description  = "Service account for Dataprep data processing operations"
  project      = var.project_id
  
  depends_on = [google_project_service.apis]
}

# Grant necessary IAM roles to Dataprep service account
resource "google_project_iam_member" "dataprep_roles" {
  for_each = toset([
    "roles/dataprep.serviceAgent",
    "roles/bigquery.dataEditor",
    "roles/pubsub.subscriber",
    "roles/storage.objectAdmin",
    "roles/dataflow.worker",
    "roles/monitoring.editor"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.dataprep_sa.email}"
  
  depends_on = [google_service_account.dataprep_sa]
}

# Grant KMS encryption/decryption permissions to Dataprep service account
resource "google_kms_crypto_key_iam_member" "dataprep_kms" {
  crypto_key_id = google_kms_crypto_key.dataprep_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.dataprep_sa.email}"
  
  depends_on = [google_service_account.dataprep_sa]
}

# Create Cloud Monitoring dashboard for IoT pipeline
resource "google_monitoring_dashboard" "iot_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "IoT Data Pipeline Dashboard"
  project      = var.project_id
  
  dashboard_json = jsonencode({
    displayName = "IoT Data Pipeline Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width = 6
          height = 4
          widget = {
            title = "Pub/Sub Message Rate"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"pubsub_topic\" AND resource.labels.topic_id=\"${google_pubsub_topic.iot_telemetry.name}\""
                      aggregation = {
                        alignmentPeriod = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width = 6
          height = 4
          widget = {
            title = "BigQuery Query Count"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"bigquery_dataset\" AND resource.labels.dataset_id=\"${google_bigquery_dataset.iot_analytics.dataset_id}\""
                      aggregation = {
                        alignmentPeriod = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width = 6
          height = 4
          widget = {
            title = "IoT Core Device Connections"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloudiot_device\""
                      aggregation = {
                        alignmentPeriod = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width = 6
          height = 4
          widget = {
            title = "Storage Bucket Usage"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gcs_bucket\" AND resource.labels.bucket_name=\"${google_storage_bucket.dataprep_staging.name}\""
                      aggregation = {
                        alignmentPeriod = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                }
              ]
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.apis]
}

# Create alerting policy for low message throughput
resource "google_monitoring_alert_policy" "low_throughput_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "IoT Pipeline Low Throughput Alert"
  project      = var.project_id
  
  combiner = "OR"
  
  conditions {
    display_name = "Low message rate"
    
    condition_threshold {
      filter         = "resource.type=\"pubsub_topic\" AND resource.labels.topic_id=\"${google_pubsub_topic.iot_telemetry.name}\""
      duration       = "300s"
      comparison     = "COMPARISON_LESS_THAN"
      threshold_value = 10
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  alert_strategy {
    auto_close = "86400s"
  }
  
  depends_on = [google_project_service.apis]
}

# Create sample data file for Dataprep configuration
resource "google_storage_bucket_object" "sample_data" {
  name         = "sample_iot_data.json"
  bucket       = google_storage_bucket.dataprep_staging.name
  content_type = "application/json"
  
  content = jsonencode([
    {
      device_id = "sensor-001"
      timestamp = "2025-07-12T10:00:00Z"
      temperature = 23.5
      humidity = 45.2
      pressure = 1013.25
      location = "warehouse_a"
      data_quality_score = 0.95
    },
    {
      device_id = "sensor-001"
      timestamp = "2025-07-12T10:01:00Z"
      temperature = null
      humidity = 47.8
      pressure = 1012.80
      location = "warehouse_a"
      data_quality_score = 0.70
    },
    {
      device_id = "sensor-001"
      timestamp = "2025-07-12T10:02:00Z"
      temperature = 85.5
      humidity = 46.1
      pressure = 1013.10
      location = "warehouse_a"
      data_quality_score = 0.60
    }
  ])
  
  depends_on = [google_storage_bucket.dataprep_staging]
}