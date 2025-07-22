# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming
locals {
  # Resource naming with environment and random suffix
  name_prefix = "${var.application_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Full resource names
  code_review_service_name    = "${local.name_prefix}-${var.code_review_service_name}-${local.name_suffix}"
  docs_service_name          = "${local.name_prefix}-${var.docs_service_name}-${local.name_suffix}"
  notification_service_name  = "${local.name_prefix}-${var.notification_service_name}-${local.name_suffix}"
  pubsub_topic_name         = "${local.name_prefix}-${var.pubsub_topic_name}-${local.name_suffix}"
  pubsub_subscription_name  = "${local.name_prefix}-${var.pubsub_subscription_name}-${local.name_suffix}"
  storage_bucket_name       = "${local.name_prefix}-${var.storage_bucket_name}-${local.name_suffix}"
  service_account_name      = "${local.name_prefix}-${var.service_account_name}-${local.name_suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    environment     = var.environment
    application     = var.application_name
    terraform       = "true"
    random-suffix   = local.name_suffix
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(var.required_apis) : toset([])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling on destroy to avoid breaking other resources
  disable_on_destroy = false
  
  # Disable dependent services when this API is disabled
  disable_dependent_services = false
}

# Create service account for Google Workspace API access
resource "google_service_account" "workspace_automation" {
  account_id   = local.service_account_name
  display_name = "Workspace Automation Service Account"
  description  = "Service account for automated code review workflows with Google Workspace APIs"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Generate service account key for Google Workspace API access
resource "google_service_account_key" "workspace_automation_key" {
  service_account_id = google_service_account.workspace_automation.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

# Store service account key in Secret Manager
resource "google_secret_manager_secret" "workspace_credentials" {
  secret_id = "workspace-credentials"
  project   = var.project_id
  
  labels = local.common_labels
  
  replication {
    auto {}
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "workspace_credentials" {
  secret      = google_secret_manager_secret.workspace_credentials.id
  secret_data = base64decode(google_service_account_key.workspace_automation_key.private_key)
}

# Grant IAM permissions to service account
resource "google_project_iam_member" "workspace_automation_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.workspace_automation.email}"
}

resource "google_project_iam_member" "workspace_automation_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.workspace_automation.email}"
}

resource "google_project_iam_member" "workspace_automation_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.workspace_automation.email}"
}

resource "google_project_iam_member" "workspace_automation_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.workspace_automation.email}"
}

# Create Cloud Storage bucket for artifacts and logs
resource "google_storage_bucket" "code_artifacts" {
  name     = local.storage_bucket_name
  location = var.storage_bucket_location
  project  = var.project_id
  
  # Prevent accidental deletion
  force_destroy = false
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Configure lifecycle management
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
      age = 365
    }
    action {
      type = "Delete"
    }
  }
  
  # Enable versioning
  versioning {
    enabled = true
  }
  
  # Apply labels
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub topic for event processing
resource "google_pubsub_topic" "code_events" {
  name    = local.pubsub_topic_name
  project = var.project_id
  
  labels = local.common_labels
  
  # Configure message storage policy
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for Cloud Run services
resource "google_pubsub_subscription" "code_processing" {
  name    = local.pubsub_subscription_name
  topic   = google_pubsub_topic.code_events.name
  project = var.project_id
  
  labels = local.common_labels
  
  # Configure message retention and acknowledgment
  message_retention_duration = var.pubsub_message_retention_duration
  ack_deadline_seconds      = var.pubsub_ack_deadline_seconds
  
  # Configure retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Enable message ordering if needed
  enable_message_ordering = false
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Run service for code review analysis
resource "google_cloud_run_v2_service" "code_review_service" {
  name     = local.code_review_service_name
  location = var.region
  project  = var.project_id
  
  labels = local.common_labels
  
  template {
    # Service account for the Cloud Run service
    service_account = google_service_account.workspace_automation.email
    
    # Configure scaling
    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }
    
    containers {
      # Placeholder image - replace with actual application image
      image = "${var.container_registry}/${var.project_id}/code-review-service:latest"
      
      # Configure resource limits
      resources {
        limits = {
          cpu    = var.cloud_run_cpu_limit
          memory = var.cloud_run_memory_limit
        }
        cpu_idle = true
      }
      
      # Configure container port
      ports {
        container_port = 8080
        name          = "http1"
      }
      
      # Environment variables
      env {
        name  = "BUCKET_NAME"
        value = google_storage_bucket.code_artifacts.name
      }
      
      env {
        name  = "TOPIC_NAME"
        value = google_pubsub_topic.code_events.name
      }
      
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
      
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      
      # Configure startup and liveness probes
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 10
        timeout_seconds      = 5
        period_seconds       = 10
        failure_threshold    = 3
      }
      
      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds      = 5
        period_seconds       = 30
        failure_threshold    = 3
      }
    }
    
    # Configure request timeout
    timeout = "${var.cloud_run_timeout_seconds}s"
  }
  
  # Configure traffic allocation
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Run service for documentation updates
resource "google_cloud_run_v2_service" "docs_service" {
  name     = local.docs_service_name
  location = var.region
  project  = var.project_id
  
  labels = local.common_labels
  
  template {
    service_account = google_service_account.workspace_automation.email
    
    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }
    
    containers {
      image = "${var.container_registry}/${var.project_id}/docs-service:latest"
      
      resources {
        limits = {
          cpu    = var.cloud_run_cpu_limit
          memory = var.cloud_run_memory_limit
        }
        cpu_idle = true
      }
      
      ports {
        container_port = 8080
        name          = "http1"
      }
      
      env {
        name  = "BUCKET_NAME"
        value = google_storage_bucket.code_artifacts.name
      }
      
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
      
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 10
        timeout_seconds      = 5
        period_seconds       = 10
        failure_threshold    = 3
      }
      
      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds      = 5
        period_seconds       = 30
        failure_threshold    = 3
      }
    }
    
    timeout = "${var.cloud_run_timeout_seconds}s"
  }
  
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Run service for notifications
resource "google_cloud_run_v2_service" "notification_service" {
  name     = local.notification_service_name
  location = var.region
  project  = var.project_id
  
  labels = local.common_labels
  
  template {
    service_account = google_service_account.workspace_automation.email
    
    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }
    
    containers {
      image = "${var.container_registry}/${var.project_id}/notification-service:latest"
      
      resources {
        limits = {
          cpu    = var.cloud_run_cpu_limit
          memory = var.cloud_run_memory_limit
        }
        cpu_idle = true
      }
      
      ports {
        container_port = 8080
        name          = "http1"
      }
      
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
      
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      
      env {
        name  = "WORKSPACE_DOMAIN"
        value = var.workspace_domain
      }
      
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 10
        timeout_seconds      = 5
        period_seconds       = 10
        failure_threshold    = 3
      }
      
      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds      = 5
        period_seconds       = 30
        failure_threshold    = 3
      }
    }
    
    timeout = "180s"
  }
  
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Configure IAM for Cloud Run services to allow unauthenticated access
resource "google_cloud_run_v2_service_iam_member" "code_review_service_invoker" {
  name     = google_cloud_run_v2_service.code_review_service.name
  location = google_cloud_run_v2_service.code_review_service.location
  project  = var.project_id
  role     = "roles/run.invoker"
  member   = "allUsers"
  
  # Only allow if configured for public access
  count = var.allowed_ingress == "all" ? 1 : 0
}

resource "google_cloud_run_v2_service_iam_member" "docs_service_invoker" {
  name     = google_cloud_run_v2_service.docs_service.name
  location = google_cloud_run_v2_service.docs_service.location
  project  = var.project_id
  role     = "roles/run.invoker"
  member   = "allUsers"
  
  count = var.allowed_ingress == "all" ? 1 : 0
}

resource "google_cloud_run_v2_service_iam_member" "notification_service_invoker" {
  name     = google_cloud_run_v2_service.notification_service.name
  location = google_cloud_run_v2_service.notification_service.location
  project  = var.project_id
  role     = "roles/run.invoker"
  member   = "allUsers"
  
  count = var.allowed_ingress == "all" ? 1 : 0
}

# Create Cloud Scheduler jobs for periodic maintenance
resource "google_cloud_scheduler_job" "weekly_doc_review" {
  count       = var.enable_scheduler ? 1 : 0
  name        = "${local.name_prefix}-weekly-doc-review-${local.name_suffix}"
  description = "Weekly documentation review trigger"
  schedule    = var.weekly_review_schedule
  time_zone   = "UTC"
  region      = var.region
  project     = var.project_id
  
  http_target {
    http_method = "GET"
    uri         = "${google_cloud_run_v2_service.docs_service.uri}/health"
    
    oidc_token {
      service_account_email = google_service_account.workspace_automation.email
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_cloud_scheduler_job" "monthly_cleanup" {
  count       = var.enable_scheduler ? 1 : 0
  name        = "${local.name_prefix}-monthly-cleanup-${local.name_suffix}"
  description = "Monthly cleanup and maintenance"
  schedule    = var.monthly_cleanup_schedule
  time_zone   = "UTC"
  region      = var.region
  project     = var.project_id
  
  http_target {
    http_method = "GET"
    uri         = "${google_cloud_run_v2_service.code_review_service.uri}/health"
    
    oidc_token {
      service_account_email = google_service_account.workspace_automation.email
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_cloud_scheduler_job" "weekly_summary" {
  count       = var.enable_scheduler ? 1 : 0
  name        = "${local.name_prefix}-weekly-summary-${local.name_suffix}"
  description = "Weekly maintenance trigger"
  schedule    = var.weekly_summary_schedule
  time_zone   = "UTC"
  region      = var.region
  project     = var.project_id
  
  pubsub_target {
    topic_name = google_pubsub_topic.code_events.id
    data       = base64encode(jsonencode({
      type   = "maintenance"
      action = "weekly_summary"
    }))
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create monitoring dashboard for observability
resource "google_monitoring_dashboard" "code_review_automation" {
  count        = var.enable_monitoring ? 1 : 0
  project      = var.project_id
  display_name = "Code Review Automation Dashboard"
  
  dashboard_json = jsonencode({
    displayName = "Code Review Automation Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width = 6
          height = 4
          widget = {
            title = "Cloud Run Request Count"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=~\"${local.name_prefix}.*\""
                    aggregation = {
                      alignmentPeriod = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields = ["resource.label.service_name"]
                    }
                  }
                }
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Requests/second"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          widget = {
            title = "Cloud Run Response Latency"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=~\"${local.name_prefix}.*\" AND metric.type=\"run.googleapis.com/request_latencies\""
                    aggregation = {
                      alignmentPeriod = "60s"
                      perSeriesAligner = "ALIGN_PERCENTILE_95"
                      crossSeriesReducer = "REDUCE_MEAN"
                      groupByFields = ["resource.label.service_name"]
                    }
                  }
                }
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Latency (ms)"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          widget = {
            title = "Pub/Sub Messages Published"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"pubsub_topic\" AND resource.label.topic_id=\"${google_pubsub_topic.code_events.name}\" AND metric.type=\"pubsub.googleapis.com/topic/send_message_operation_count\""
                    aggregation = {
                      alignmentPeriod = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Messages/second"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          widget = {
            title = "Storage Bucket Objects"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gcs_bucket\" AND resource.label.bucket_name=\"${google_storage_bucket.code_artifacts.name}\" AND metric.type=\"storage.googleapis.com/storage/object_count\""
                    aggregation = {
                      alignmentPeriod = "300s"
                      perSeriesAligner = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Object Count"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create alerting policy for service errors
resource "google_monitoring_alert_policy" "code_review_service_errors" {
  count        = var.enable_monitoring ? 1 : 0
  project      = var.project_id
  display_name = "Code Review Service Errors"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Cloud Run Error Rate"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=~\"${local.name_prefix}.*\" AND metric.type=\"run.googleapis.com/request_count\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields    = ["resource.label.service_name"]
      }
      
      trigger {
        count = 1
      }
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  # Add notification channels if provided
  dynamic "notification_channels" {
    for_each = var.alert_notification_channels
    content {
      name = notification_channels.value
    }
  }
  
  depends_on = [google_project_service.required_apis]
}