# GCP Digital Twin Manufacturing Resilience Infrastructure
# This Terraform configuration deploys a comprehensive digital twin system for manufacturing
# resilience using Google Cloud Platform services including Pub/Sub, BigQuery, Cloud Storage,
# Vertex AI, and Cloud Functions.

# Random string for unique resource naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Local values for resource naming and common configurations
locals {
  resource_prefix = "manufacturing-twin-${var.environment}"
  storage_bucket_name = "${local.resource_prefix}-storage-${random_string.suffix.result}"
  
  # Common labels to apply to all resources
  common_labels = merge(var.labels, {
    resource-prefix = local.resource_prefix
    random-suffix   = random_string.suffix.result
  })
  
  # Pub/Sub topic names
  pubsub_topics = {
    sensor_data        = "manufacturing-sensor-data"
    simulation_events  = "failure-simulation-events"
    recovery_commands  = "recovery-commands"
  }
  
  # BigQuery table schemas
  sensor_data_schema = [
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    },
    {
      name = "equipment_id"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "sensor_type"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "value"
      type = "FLOAT"
      mode = "REQUIRED"
    },
    {
      name = "unit"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "location"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "processing_timestamp"
      type = "TIMESTAMP"
      mode = "NULLABLE"
    }
  ]
  
  simulation_results_schema = [
    {
      name = "simulation_id"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    },
    {
      name = "scenario"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "equipment_id"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "predicted_outcome"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "confidence"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "recovery_time"
      type = "INTEGER"
      mode = "NULLABLE"
    }
  ]
  
  equipment_metadata_schema = [
    {
      name = "equipment_id"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "equipment_type"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "manufacturer"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "model"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "installation_date"
      type = "DATE"
      mode = "NULLABLE"
    },
    {
      name = "criticality_level"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "location"
      type = "STRING"
      mode = "NULLABLE"
    }
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "pubsub.googleapis.com",
    "dataflow.googleapis.com",
    "bigquery.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com"
  ]) : []
  
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ============================================================================
# PUB/SUB RESOURCES - Messaging infrastructure for IoT data ingestion
# ============================================================================

# Pub/Sub topics for different data streams
resource "google_pubsub_topic" "topics" {
  for_each = local.pubsub_topics
  
  name    = each.value
  project = var.project_id
  labels  = local.common_labels
  
  message_retention_duration = var.pubsub_message_retention_duration
  
  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscriptions for data processing
resource "google_pubsub_subscription" "sensor_data_processing" {
  name    = "sensor-data-processing"
  topic   = google_pubsub_topic.topics["sensor_data"].name
  project = var.project_id
  labels  = local.common_labels
  
  # Configure message acknowledgment deadline
  ack_deadline_seconds = 60
  
  # Configure retry policy for failed message processing
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Configure dead letter queue for unprocessable messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_pubsub_subscription" "simulation_processing" {
  name    = "simulation-processing"
  topic   = google_pubsub_topic.topics["simulation_events"].name
  project = var.project_id
  labels  = local.common_labels
  
  ack_deadline_seconds = 60
  
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  
  depends_on = [google_project_service.required_apis]
}

# Dead letter topic for failed message processing
resource "google_pubsub_topic" "dead_letter" {
  name    = "digital-twin-dead-letter"
  project = var.project_id
  labels  = local.common_labels
  
  message_retention_duration = "604800s" # 7 days
  
  depends_on = [google_project_service.required_apis]
}

# ============================================================================
# CLOUD STORAGE RESOURCES - Object storage for model artifacts and data
# ============================================================================

# Primary storage bucket for model artifacts, training data, and pipeline assets
resource "google_storage_bucket" "digital_twin_storage" {
  name                        = local.storage_bucket_name
  location                    = var.storage_bucket_location
  storage_class               = var.storage_bucket_class
  project                     = var.project_id
  force_destroy               = true
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  # Configure versioning for model artifact management
  versioning {
    enabled = true
  }
  
  # Configure lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.storage_lifecycle_rules.enabled ? [1] : []
    content {
      action {
        type          = var.storage_lifecycle_rules.action.type
        storage_class = var.storage_lifecycle_rules.action.storage_class
      }
      condition {
        age = var.storage_lifecycle_rules.condition.age
      }
    }
  }
  
  # Configure CORS for web-based access
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  depends_on = [google_project_service.required_apis]
}

# Storage bucket objects for organizing data structure
resource "google_storage_bucket_object" "folder_structure" {
  for_each = toset([
    "models/.keep",
    "training-data/.keep",
    "simulation-configs/.keep",
    "dataflow/.keep",
    "temp/.keep"
  ])
  
  name   = each.value
  bucket = google_storage_bucket.digital_twin_storage.name
  content = "# This file maintains folder structure in Cloud Storage"
}

# Upload sample training data for Vertex AI
resource "google_storage_bucket_object" "training_data" {
  name   = "training-data/training_data.jsonl"
  bucket = google_storage_bucket.digital_twin_storage.name
  content = jsonencode({
    lines = [
      {"equipment_id": "pump_001", "temperature": 75.2, "vibration": 0.3, "pressure": 150.5, "failure_in_hours": 0},
      {"equipment_id": "pump_001", "temperature": 78.1, "vibration": 0.4, "pressure": 148.2, "failure_in_hours": 0},
      {"equipment_id": "pump_001", "temperature": 82.3, "vibration": 0.7, "pressure": 145.1, "failure_in_hours": 24},
      {"equipment_id": "pump_001", "temperature": 85.4, "vibration": 1.2, "pressure": 142.8, "failure_in_hours": 12},
      {"equipment_id": "compressor_002", "temperature": 68.5, "vibration": 0.2, "pressure": 200.1, "failure_in_hours": 0},
      {"equipment_id": "compressor_002", "temperature": 71.2, "vibration": 0.5, "pressure": 195.3, "failure_in_hours": 48}
    ]
  })
}

# ============================================================================
# BIGQUERY RESOURCES - Data warehouse for analytics and ML training
# ============================================================================

# BigQuery dataset for manufacturing data
resource "google_bigquery_dataset" "manufacturing_data" {
  dataset_id                  = var.dataset_name
  project                     = var.project_id
  friendly_name              = "Manufacturing Digital Twin Data"
  description                = "Dataset containing sensor data, simulation results, and equipment metadata for digital twin operations"
  location                    = var.bigquery_location
  default_table_expiration_ms = var.bigquery_table_expiration_ms
  
  labels = local.common_labels
  
  # Configure access control
  access {
    role          = "OWNER"
    user_by_email = data.google_client_openid_userinfo.me.email
  }
  
  access {
    role         = "READER"
    special_group = "projectReaders"
  }
  
  access {
    role         = "WRITER"
    special_group = "projectWriters"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Get current user info for BigQuery access
data "google_client_openid_userinfo" "me" {}

# BigQuery table for sensor data
resource "google_bigquery_table" "sensor_data" {
  dataset_id          = google_bigquery_dataset.manufacturing_data.dataset_id
  table_id            = "sensor_data"
  project             = var.project_id
  deletion_protection = false
  
  friendly_name = "Manufacturing Sensor Data"
  description   = "Time-series sensor data from manufacturing equipment"
  
  labels = local.common_labels
  
  # Configure table schema
  schema = jsonencode(local.sensor_data_schema)
  
  # Configure time partitioning for performance
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
  
  # Configure clustering for query optimization
  clustering = ["equipment_id", "sensor_type"]
}

# BigQuery table for simulation results
resource "google_bigquery_table" "simulation_results" {
  dataset_id          = google_bigquery_dataset.manufacturing_data.dataset_id
  table_id            = "simulation_results"
  project             = var.project_id
  deletion_protection = false
  
  friendly_name = "Digital Twin Simulation Results"
  description   = "Results from digital twin failure simulation scenarios"
  
  labels = local.common_labels
  
  schema = jsonencode(local.simulation_results_schema)
  
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
  
  clustering = ["equipment_id", "scenario"]
}

# BigQuery table for equipment metadata
resource "google_bigquery_table" "equipment_metadata" {
  dataset_id          = google_bigquery_dataset.manufacturing_data.dataset_id
  table_id            = "equipment_metadata"
  project             = var.project_id
  deletion_protection = false
  
  friendly_name = "Manufacturing Equipment Metadata"
  description   = "Metadata and configuration information for manufacturing equipment"
  
  labels = local.common_labels
  
  schema = jsonencode(local.equipment_metadata_schema)
  
  clustering = ["equipment_type", "criticality_level"]
}

# ============================================================================
# VERTEX AI RESOURCES - Machine learning platform for failure prediction
# ============================================================================

# Vertex AI dataset for failure prediction model training
resource "google_vertex_ai_dataset" "failure_prediction" {
  display_name        = var.vertex_ai_dataset_display_name
  metadata_schema_uri = "gs://google-cloud-aiplatform/schema/dataset/metadata/tabular_1.0.0.yaml"
  project             = var.project_id
  region              = var.vertex_ai_region
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# ============================================================================
# CLOUD FUNCTIONS RESOURCES - Serverless compute for digital twin simulation
# ============================================================================

# Create source code archive for Cloud Function
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_source/main.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source/digital-twin-simulator-${random_string.suffix.result}.zip"
  bucket = google_storage_bucket.digital_twin_storage.name
  source = data.archive_file.function_source.output_path
}

# Service account for Cloud Function with appropriate permissions
resource "google_service_account" "function_service_account" {
  account_id   = "digital-twin-function-sa"
  display_name = "Digital Twin Cloud Function Service Account"
  description  = "Service account for digital twin simulation Cloud Function"
  project      = var.project_id
}

# IAM bindings for Cloud Function service account
resource "google_project_iam_member" "function_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_bigquery_user" {
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_storage_object_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

# Cloud Function for digital twin simulation
resource "google_cloudfunctions2_function" "digital_twin_simulator" {
  name        = "digital-twin-simulator"
  location    = var.region
  project     = var.project_id
  description = "Digital twin simulation engine for manufacturing resilience testing"
  
  build_config {
    runtime     = "python311"
    entry_point = "simulate_failure_scenario"
    
    source {
      storage_source {
        bucket = google_storage_bucket.digital_twin_storage.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 100
    min_instance_count    = 0
    available_memory      = "${var.cloud_function_memory}Mi"
    timeout_seconds       = var.cloud_function_timeout
    service_account_email = google_service_account.function_service_account.email
    
    environment_variables = {
      PROJECT_ID    = var.project_id
      DATASET_NAME  = var.dataset_name
      BUCKET_NAME   = google_storage_bucket.digital_twin_storage.name
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# Function IAM policy for public HTTP access
resource "google_cloud_run_service_iam_member" "function_invoker" {
  location = google_cloudfunctions2_function.digital_twin_simulator.location
  service  = google_cloudfunctions2_function.digital_twin_simulator.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ============================================================================
# MONITORING RESOURCES - Observability for digital twin operations
# ============================================================================

# Monitoring dashboard for digital twin operations
resource "google_monitoring_dashboard" "digital_twin_dashboard" {
  count = var.monitoring_dashboard_enabled ? 1 : 0
  
  display_name = "Manufacturing Digital Twin Dashboard"
  project      = var.project_id
  
  dashboard_json = jsonencode({
    displayName = "Manufacturing Digital Twin Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Sensor Data Ingestion Rate"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    unitOverride = "1/s"
                    timeSeriesFilter = {
                      filter = "resource.type=\"pubsub_topic\""
                      aggregation = {
                        alignmentPeriod  = "60s"
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
          width  = 6
          height = 4
          widget = {
            title = "Cloud Function Execution Metrics"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_function\""
                      aggregation = {
                        alignmentPeriod  = "300s"
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
          width  = 12
          height = 4
          widget = {
            title = "BigQuery Data Processing"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"bigquery_dataset\""
                      aggregation = {
                        alignmentPeriod  = "300s"
                        perSeriesAligner = "ALIGN_RATE"
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
  
  depends_on = [google_project_service.required_apis]
}

# Alert policies for monitoring critical system health
resource "google_monitoring_alert_policy" "high_error_rate" {
  display_name = "Digital Twin High Error Rate"
  project      = var.project_id
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud Function error rate"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"digital-twin-simulator\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# ============================================================================
# IAM AND SECURITY RESOURCES
# ============================================================================

# Custom IAM role for digital twin operations
resource "google_project_iam_custom_role" "digital_twin_operator" {
  role_id     = "digitalTwinOperator"
  title       = "Digital Twin Operator"
  description = "Custom role for digital twin system operations"
  project     = var.project_id
  
  permissions = [
    "pubsub.messages.ack",
    "pubsub.messages.get",
    "pubsub.subscriptions.consume",
    "bigquery.datasets.get",
    "bigquery.tables.get",
    "bigquery.tables.getData",
    "bigquery.jobs.create",
    "storage.objects.get",
    "storage.objects.list",
    "aiplatform.datasets.get",
    "aiplatform.datasets.list",
    "monitoring.dashboards.get",
    "monitoring.dashboards.list"
  ]
}