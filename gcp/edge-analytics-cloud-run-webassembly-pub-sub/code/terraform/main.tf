# Edge Analytics Infrastructure with Cloud Run WebAssembly and Pub/Sub
# Terraform configuration for deploying IoT edge analytics platform on Google Cloud

# Local values for resource naming and configuration
locals {
  # Generate random suffix for unique resource names if enabled
  suffix = var.use_random_suffix ? random_id.suffix[0].hex : ""
  
  # Resource names with optional random suffix
  bucket_name       = var.use_random_suffix ? "${var.resource_prefix}-data-${local.suffix}" : "${var.resource_prefix}-data"
  topic_name        = var.use_random_suffix ? "${var.resource_prefix}-sensor-data-${local.suffix}" : "${var.resource_prefix}-sensor-data"
  subscription_name = var.use_random_suffix ? "${var.resource_prefix}-subscription-${local.suffix}" : "${var.resource_prefix}-subscription"
  service_name      = var.use_random_suffix ? "${var.resource_prefix}-service-${local.suffix}" : "${var.resource_prefix}-service"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
    region      = var.region
  })
  
  # APIs to enable
  required_apis = var.enable_apis ? [
    "run.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "firestore.googleapis.com",
    "logging.googleapis.com"
  ] : []
}

# Generate random suffix for resource names
resource "random_id" "suffix" {
  count       = var.use_random_suffix ? 1 : 0
  byte_length = 3
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Wait for APIs to be fully enabled
resource "time_sleep" "wait_for_apis" {
  count = var.enable_apis ? 1 : 0
  
  depends_on = [google_project_service.required_apis]
  
  create_duration = "60s"
}

# Cloud Storage bucket for analytics data lake
resource "google_storage_bucket" "analytics_data_lake" {
  name     = local.bucket_name
  location = var.storage_location
  
  # Storage class for cost optimization
  storage_class = var.storage_class
  
  # Enable versioning for data protection
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.enable_lifecycle_management ? [1] : []
    
    content {
      # Transition to Nearline storage after specified days
      condition {
        age = var.lifecycle_age_nearline
      }
      action {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
    }
  }
  
  dynamic "lifecycle_rule" {
    for_each = var.enable_lifecycle_management ? [1] : []
    
    content {
      # Transition to Coldline storage after specified days
      condition {
        age = var.lifecycle_age_coldline
      }
      action {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
    }
  }
  
  # Security settings
  uniform_bucket_level_access = true
  
  # Public access prevention
  public_access_prevention = "enforced"
  
  # Labels for resource management
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Pub/Sub topic for IoT sensor data ingestion
resource "google_pubsub_topic" "iot_sensor_data" {
  name = local.topic_name
  
  # Message retention for reliability
  message_retention_duration = var.message_retention_duration
  
  # Labels for resource management
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Service account for Cloud Run service
resource "google_service_account" "cloud_run_sa" {
  account_id   = "${var.resource_prefix}-run-sa${var.use_random_suffix ? "-${local.suffix}" : ""}"
  display_name = "Cloud Run Service Account for Edge Analytics"
  description  = "Service account for Cloud Run edge analytics service with WebAssembly"
  
  depends_on = [time_sleep.wait_for_apis]
}

# IAM role binding for Cloud Run service account - Storage access
resource "google_project_iam_member" "cloud_run_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# IAM role binding for Cloud Run service account - Firestore access
resource "google_project_iam_member" "cloud_run_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# IAM role binding for Cloud Run service account - Monitoring access
resource "google_project_iam_member" "cloud_run_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# IAM role binding for Cloud Run service account - Logging access
resource "google_project_iam_member" "cloud_run_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Firestore database for analytics metadata
resource "google_firestore_database" "analytics_metadata" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.firestore_location
  type        = var.firestore_type
  
  depends_on = [time_sleep.wait_for_apis]
}

# Cloud Run service for edge analytics with WebAssembly
resource "google_cloud_run_v2_service" "edge_analytics" {
  name     = local.service_name
  location = var.region
  
  # Service configuration
  template {
    # Scaling configuration
    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }
    
    # Container configuration
    containers {
      # Use placeholder image if none provided
      image = var.container_image != "" ? var.container_image : "gcr.io/cloudrun/hello"
      
      # Resource allocation
      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
      }
      
      # Environment variables
      env {
        name  = "BUCKET_NAME"
        value = google_storage_bucket.analytics_data_lake.name
      }
      
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
      
      env {
        name  = "PUBSUB_TOPIC"
        value = google_pubsub_topic.iot_sensor_data.name
      }
      
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      
      # Health check configuration
      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds       = 10
        period_seconds        = 30
        failure_threshold     = 3
      }
      
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 10
        timeout_seconds       = 10
        period_seconds        = 10
        failure_threshold     = 5
      }
      
      # Port configuration
      ports {
        container_port = 8080
      }
    }
    
    # Service account
    service_account = google_service_account.cloud_run_sa.email
    
    # Execution environment
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"
    
    # Request timeout
    timeout = "${var.cloud_run_timeout}s"
    
    # Session affinity
    session_affinity = false
    
    # Max concurrent requests per instance
    max_instance_request_concurrency = var.cloud_run_concurrency
    
    # Labels
    labels = local.common_labels
  }
  
  # Traffic configuration
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  # Ingress configuration
  ingress = var.ingress
  
  # Binary Authorization
  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? [1] : []
    
    content {
      use_default = true
    }
  }
  
  depends_on = [
    google_project_iam_member.cloud_run_storage,
    google_project_iam_member.cloud_run_firestore,
    google_project_iam_member.cloud_run_monitoring,
    google_project_iam_member.cloud_run_logging,
    time_sleep.wait_for_apis
  ]
}

# IAM policy for Cloud Run service - allow unauthenticated access if enabled
resource "google_cloud_run_service_iam_member" "public_access" {
  count = var.enable_cloud_run_all_users ? 1 : 0
  
  location = google_cloud_run_v2_service.edge_analytics.location
  project  = google_cloud_run_v2_service.edge_analytics.project
  service  = google_cloud_run_v2_service.edge_analytics.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Service account for Pub/Sub push subscription
resource "google_service_account" "pubsub_publisher" {
  account_id   = "${var.resource_prefix}-pubsub-sa${var.use_random_suffix ? "-${local.suffix}" : ""}"
  display_name = "Pub/Sub Publisher Service Account"
  description  = "Service account for Pub/Sub to invoke Cloud Run service"
  
  depends_on = [time_sleep.wait_for_apis]
}

# IAM binding for Pub/Sub to invoke Cloud Run
resource "google_project_iam_member" "pubsub_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.pubsub_publisher.email}"
}

# Pub/Sub push subscription to trigger Cloud Run
resource "google_pubsub_subscription" "analytics_subscription" {
  name  = local.subscription_name
  topic = google_pubsub_topic.iot_sensor_data.name
  
  # Push configuration to Cloud Run service
  push_config {
    push_endpoint = "${google_cloud_run_v2_service.edge_analytics.uri}/process"
    
    # Attributes for authentication
    attributes = {
      x-goog-version = "v1"
    }
    
    # OAuth token for authentication
    oidc_token {
      service_account_email = google_service_account.pubsub_publisher.email
    }
  }
  
  # Message configuration
  ack_deadline_seconds       = var.subscription_ack_deadline
  message_retention_duration = var.message_retention_duration
  
  # Retry policy for failed deliveries
  retry_policy {
    maximum_backoff = "${var.max_retry_delay}s"
    minimum_backoff = "${var.min_retry_delay}s"
  }
  
  # Dead letter policy for undeliverable messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 10
  }
  
  # Labels for resource management
  labels = local.common_labels
  
  depends_on = [
    google_cloud_run_v2_service.edge_analytics,
    google_project_iam_member.pubsub_invoker
  ]
}

# Dead letter topic for failed message processing
resource "google_pubsub_topic" "dead_letter" {
  name = "${local.topic_name}-dead-letter"
  
  message_retention_duration = "7d"
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Cloud Monitoring dashboard for edge analytics
resource "google_monitoring_dashboard" "edge_analytics" {
  dashboard_json = jsonencode({
    displayName = "Edge Analytics Dashboard - ${var.environment}"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Data Processing Rate"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"custom.googleapis.com/iot/data_processed\" resource.type=\"generic_node\""
                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Messages/Second"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Anomaly Detection Rate"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"custom.googleapis.com/iot/anomaly_detected\" resource.type=\"generic_node\""
                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Anomalies/Second"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Cloud Run Request Count"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" resource.label.service_name=\"${local.service_name}\""
                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Requests/Second"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Cloud Run Request Latency"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"run.googleapis.com/request_latencies\" resource.type=\"cloud_run_revision\" resource.label.service_name=\"${local.service_name}\""
                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_DELTA"
                        crossSeriesReducer = "REDUCE_PERCENTILE_95"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Latency (ms)"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [time_sleep.wait_for_apis]
}

# Alert policy for anomaly detection
resource "google_monitoring_alert_policy" "anomaly_detection" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  display_name = "Edge Analytics - High Anomaly Detection Rate"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Anomaly Rate High"
    
    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/iot/anomaly_detected\" resource.type=\"generic_node\""
      duration        = var.alert_duration
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.anomaly_threshold
      
      aggregations {
        alignment_period   = var.alert_duration
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  # Notification channels
  notification_channels = var.notification_channels
  
  # Alert strategy
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Alert policy for data processing rate
resource "google_monitoring_alert_policy" "data_processing_rate" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  display_name = "Edge Analytics - Low Data Processing Rate"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Data Processing Rate Low"
    
    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/iot/data_processed\" resource.type=\"generic_node\""
      duration        = var.alert_duration
      comparison      = "COMPARISON_LESS_THAN"
      threshold_value = 1
      
      aggregations {
        alignment_period   = var.alert_duration
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = var.notification_channels
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Alert policy for Cloud Run service errors
resource "google_monitoring_alert_policy" "service_errors" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  display_name = "Edge Analytics - Service Error Rate High"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Service Error Rate High"
    
    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" resource.label.service_name=\"${local.service_name}\" metric.label.response_code_class!=\"2xx\""
      duration        = var.alert_duration
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 5
      
      aggregations {
        alignment_period   = var.alert_duration
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = var.notification_channels
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Log sink for Cloud Run service logs
resource "google_logging_project_sink" "cloud_run_logs" {
  name        = "${var.resource_prefix}-cloud-run-logs${var.use_random_suffix ? "-${local.suffix}" : ""}"
  destination = "storage.googleapis.com/${google_storage_bucket.analytics_data_lake.name}/logs"
  
  filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${local.service_name}\""
  
  # Grant writer permission to the sink
  unique_writer_identity = true
  
  depends_on = [time_sleep.wait_for_apis]
}

# IAM binding for log sink to write to storage bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.analytics_data_lake.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.cloud_run_logs.writer_identity
}