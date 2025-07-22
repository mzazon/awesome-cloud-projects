# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Resource naming with random suffix
  resource_suffix = random_id.suffix.hex
  
  # Naming convention: {application_name}-{resource_type}-{environment}-{suffix}
  pubsub_topic_name      = "${var.application_name}-${var.pubsub_topic_name}-${var.environment}-${local.resource_suffix}"
  subscription_name      = "${var.application_name}-${var.pubsub_subscription_name}-${var.environment}-${local.resource_suffix}"
  worker_pool_name       = "${var.application_name}-${var.worker_pool_name}-${var.environment}-${local.resource_suffix}"
  service_account_name   = "${var.application_name}-processor-${var.environment}-${local.resource_suffix}"
  artifact_repo_name     = "${var.application_name}-${var.artifact_registry_repository}-${var.environment}"
  firestore_db_name      = "${var.firestore_database_name}-${var.environment}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment   = var.environment
    application   = var.application_name
    managed-by    = "terraform"
    resource-type = "behavioral-analytics"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "run.googleapis.com",
    "firestore.googleapis.com",
    "pubsub.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "logging.googleapis.com",
    "secretmanager.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Prevent accidental deletion of APIs
  disable_on_destroy = false
}

# Create Artifact Registry repository for container images
resource "google_artifact_registry_repository" "behavioral_analytics" {
  location      = var.region
  repository_id = local.artifact_repo_name
  description   = "Container images for behavioral analytics system"
  format        = "DOCKER"

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create service account for the behavioral analytics processor
resource "google_service_account" "analytics_processor" {
  account_id   = local.service_account_name
  display_name = "Behavioral Analytics Processor"
  description  = "Service account for Cloud Run worker pool processing behavioral events"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Grant Pub/Sub subscriber permissions to the service account
resource "google_project_iam_member" "pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.analytics_processor.email}"

  depends_on = [google_service_account.analytics_processor]
}

# Grant Firestore user permissions to the service account
resource "google_project_iam_member" "firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.analytics_processor.email}"

  depends_on = [google_service_account.analytics_processor]
}

# Grant Cloud Monitoring metric writer permissions to the service account
resource "google_project_iam_member" "monitoring_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.analytics_processor.email}"

  depends_on = [google_service_account.analytics_processor]
}

# Grant Cloud Logging writer permissions to the service account
resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.analytics_processor.email}"

  depends_on = [google_service_account.analytics_processor]
}

# Create Firestore database in Native mode
resource "google_firestore_database" "behavioral_analytics" {
  project     = var.project_id
  name        = local.firestore_db_name
  location_id = var.firestore_location
  type        = "FIRESTORE_NATIVE"

  # Prevent accidental deletion
  deletion_policy = "DELETE"

  depends_on = [google_project_service.required_apis]
}

# Create Firestore composite indexes for optimized analytics queries
resource "google_firestore_index" "user_events_by_user_timestamp" {
  project    = var.project_id
  database   = google_firestore_database.behavioral_analytics.name
  collection = "user_events"

  fields {
    field_path = "user_id"
    order      = "ASCENDING"
  }

  fields {
    field_path = "timestamp"
    order      = "DESCENDING"
  }

  depends_on = [google_firestore_database.behavioral_analytics]
}

resource "google_firestore_index" "user_events_by_type_timestamp" {
  project    = var.project_id
  database   = google_firestore_database.behavioral_analytics.name
  collection = "user_events"

  fields {
    field_path = "event_type"
    order      = "ASCENDING"
  }

  fields {
    field_path = "timestamp"
    order      = "DESCENDING"
  }

  depends_on = [google_firestore_database.behavioral_analytics]
}

resource "google_firestore_index" "analytics_aggregates_by_period" {
  project    = var.project_id
  database   = google_firestore_database.behavioral_analytics.name
  collection = "analytics_aggregates"

  fields {
    field_path = "period"
    order      = "ASCENDING"
  }

  fields {
    field_path = "last_updated"
    order      = "DESCENDING"
  }

  depends_on = [google_firestore_database.behavioral_analytics]
}

# Create Pub/Sub topic for user events
resource "google_pubsub_topic" "user_events" {
  name    = local.pubsub_topic_name
  project = var.project_id

  labels = local.common_labels

  # Enable message ordering for accurate behavioral analysis
  message_ordering = true

  # Message storage policy
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }

  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for worker pool processing
resource "google_pubsub_subscription" "analytics_processor" {
  name    = local.subscription_name
  topic   = google_pubsub_topic.user_events.name
  project = var.project_id

  labels = local.common_labels

  # Configure subscription for optimal processing
  ack_deadline_seconds       = var.ack_deadline_seconds
  message_retention_duration = var.message_retention_duration
  enable_message_ordering    = true

  # Configure exponential backoff for failed messages
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # Configure dead letter topic for failed messages (optional)
  # Uncomment and configure if you want dead letter handling
  # dead_letter_policy {
  #   dead_letter_topic     = google_pubsub_topic.dead_letter.id
  #   max_delivery_attempts = 5
  # }

  depends_on = [google_pubsub_topic.user_events]
}

# Create Cloud Run worker pool for background processing
resource "google_cloud_run_v2_job" "behavioral_processor" {
  provider = google-beta
  name     = local.worker_pool_name
  location = var.region
  project  = var.project_id

  labels = local.common_labels

  template {
    labels = local.common_labels

    template {
      # Configure service account
      service_account = google_service_account.analytics_processor.email

      # Configure container specifications
      containers {
        image = var.container_image

        # Resource allocation
        resources {
          limits = {
            cpu    = var.worker_pool_cpu
            memory = var.worker_pool_memory
          }
        }

        # Environment variables for the application
        env {
          name  = "GOOGLE_CLOUD_PROJECT"
          value = var.project_id
        }

        env {
          name  = "PUBSUB_SUBSCRIPTION"
          value = google_pubsub_subscription.analytics_processor.id
        }

        env {
          name  = "FIRESTORE_DATABASE"
          value = google_firestore_database.behavioral_analytics.name
        }

        env {
          name  = "GOOGLE_CLOUD_REGION"
          value = var.region
        }

        env {
          name  = "ENVIRONMENT"
          value = var.environment
        }

        # Configure startup and liveness probes
        startup_probe {
          initial_delay_seconds = 10
          timeout_seconds      = 5
          period_seconds       = 10
          failure_threshold    = 3

          tcp_socket {
            port = 8080
          }
        }

        liveness_probe {
          initial_delay_seconds = 30
          timeout_seconds      = 5
          period_seconds       = 30
          failure_threshold    = 3

          tcp_socket {
            port = 8080
          }
        }
      }

      # Configure scaling
      max_retries = 3
      
      # Configure execution environment
      execution_environment = "EXECUTION_ENVIRONMENT_GEN2"
    }
  }

  depends_on = [
    google_service_account.analytics_processor,
    google_pubsub_subscription.analytics_processor,
    google_firestore_database.behavioral_analytics,
    google_project_iam_member.pubsub_subscriber,
    google_project_iam_member.firestore_user,
    google_project_iam_member.monitoring_metric_writer
  ]
}

# Create Cloud Monitoring dashboard for behavioral analytics
resource "google_monitoring_dashboard" "behavioral_analytics" {
  count = var.enable_monitoring_dashboard ? 1 : 0

  dashboard_json = jsonencode({
    displayName = "Behavioral Analytics Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Events Processed Per Minute"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"custom.googleapis.com/behavioral_analytics/events_processed\""
                    aggregation = {
                      alignmentPeriod   = "60s"
                      perSeriesAligner  = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "LINE"
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Events/min"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Cloud Run Job Executions"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_run_job\" AND metric.type=\"run.googleapis.com/job/completed_execution_count\""
                    aggregation = {
                      alignmentPeriod   = "60s"
                      perSeriesAligner  = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          yPos   = 4
          widget = {
            title = "Pub/Sub Message Backlog"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"pubsub_subscription\" AND metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\""
                    aggregation = {
                      alignmentPeriod   = "60s"
                      perSeriesAligner  = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          yPos   = 4
          widget = {
            title = "Firestore Operations"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"firestore_database\" AND metric.type=\"firestore.googleapis.com/api/request_count\""
                    aggregation = {
                      alignmentPeriod   = "60s"
                      perSeriesAligner  = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        }
      ]
    }
  })

  depends_on = [google_project_service.required_apis]
}

# Create alert policy for high Pub/Sub message lag
resource "google_monitoring_alert_policy" "high_pubsub_lag" {
  count = var.enable_alert_policies ? 1 : 0

  display_name = "High Pub/Sub Message Lag"
  combiner     = "OR"

  conditions {
    display_name = "Pub/Sub subscription message lag is high"

    condition_threshold {
      filter          = "resource.type=\"pubsub_subscription\" AND resource.labels.subscription_id=\"${local.subscription_name}\" AND metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 100

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  notification_channels = var.notification_channels

  documentation {
    content   = "Alert when Pub/Sub subscription has high message lag indicating processing issues"
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.required_apis]
}

# Create alert policy for Cloud Run job failures
resource "google_monitoring_alert_policy" "cloud_run_job_failures" {
  count = var.enable_alert_policies ? 1 : 0

  display_name = "Cloud Run Job Failures"
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run job failure rate is high"

    condition_threshold {
      filter          = "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${local.worker_pool_name}\" AND metric.type=\"run.googleapis.com/job/completed_execution_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["metric.labels.result"]
      }

      # Filter for failed executions
      trigger {
        count = 1
      }
    }
  }

  notification_channels = var.notification_channels

  documentation {
    content   = "Alert when Cloud Run job failure rate exceeds threshold"
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.required_apis]
}

# Optional: Create VPC connector if enabled
resource "google_vpc_access_connector" "behavioral_analytics" {
  count = var.enable_vpc_connector ? 1 : 0

  name          = "${local.worker_pool_name}-connector"
  ip_cidr_range = "10.8.0.0/28"
  network       = var.vpc_network_name
  region        = var.region

  depends_on = [google_project_service.required_apis]
}

# Create log sink for structured logging to BigQuery (optional)
resource "google_logging_project_sink" "behavioral_analytics_logs" {
  name        = "${local.worker_pool_name}-logs"
  destination = "storage.googleapis.com/${google_storage_bucket.log_storage.name}"

  # Filter for behavioral analytics related logs
  filter = "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${local.worker_pool_name}\""

  # Use a unique writer identity for this sink
  unique_writer_identity = true

  depends_on = [google_cloud_run_v2_job.behavioral_processor]
}

# Create Cloud Storage bucket for log storage
resource "google_storage_bucket" "log_storage" {
  name          = "${var.project_id}-${local.worker_pool_name}-logs"
  location      = var.region
  force_destroy = true

  labels = local.common_labels

  # Configure lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  # Enable versioning
  versioning {
    enabled = true
  }

  # Configure uniform bucket-level access
  uniform_bucket_level_access = true

  depends_on = [google_project_service.required_apis]
}

# Grant log sink permission to write to storage bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.log_storage.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.behavioral_analytics_logs.writer_identity

  depends_on = [google_logging_project_sink.behavioral_analytics_logs]
}