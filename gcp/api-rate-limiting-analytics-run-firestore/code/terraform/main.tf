# Main Terraform configuration for GCP API Rate Limiting and Analytics
# This file creates all the infrastructure components needed for the serverless API gateway

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed names and common configurations
locals {
  # Computed resource names with random suffix
  service_name_unique = "${var.service_name}-${random_id.suffix.hex}"
  container_image     = var.container_image != "" ? var.container_image : "gcr.io/${var.project_id}/${var.service_name}:latest"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    service     = var.service_name
    created-by  = "terraform"
  })
  
  # Required APIs for the solution
  required_apis = [
    "run.googleapis.com",
    "firestore.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "containerregistry.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(local.required_apis) : []
  
  project = var.project_id
  service = each.value
  
  # Don't disable APIs when destroying to prevent issues
  disable_dependent_services = false
  disable_on_destroy        = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Wait for APIs to be fully enabled before proceeding
resource "time_sleep" "api_enablement" {
  depends_on = [google_project_service.required_apis]
  
  create_duration = "30s"
}

# Create Firestore database in native mode
resource "google_firestore_database" "api_analytics" {
  project                           = var.project_id
  name                             = "(default)"
  location_id                      = var.firestore_config.location_id
  type                            = var.firestore_config.type
  concurrency_mode                = var.firestore_config.concurrency_mode
  app_engine_integration_mode     = var.firestore_config.app_engine_integration_mode
  point_in_time_recovery_enablement = var.firestore_config.point_in_time_recovery_enablement
  delete_protection_state         = var.firestore_config.delete_protection_state
  
  depends_on = [
    google_project_service.required_apis,
    time_sleep.api_enablement
  ]
  
  lifecycle {
    # Prevent accidental deletion of database
    prevent_destroy = false # Set to true in production
  }
}

# Create a service account for the Cloud Run service
resource "google_service_account" "api_gateway" {
  project      = var.project_id
  account_id   = "${var.service_name}-sa-${random_id.suffix.hex}"
  display_name = "API Gateway Service Account"
  description  = "Service account for the API rate limiting gateway"
  
  depends_on = [time_sleep.api_enablement]
}

# Grant Firestore permissions to the service account
resource "google_project_iam_member" "firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.api_gateway.email}"
  
  depends_on = [google_service_account.api_gateway]
}

# Grant Cloud Monitoring permissions for metrics
resource "google_project_iam_member" "monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.api_gateway.email}"
  
  depends_on = [google_service_account.api_gateway]
}

# Grant Cloud Logging permissions
resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.api_gateway.email}"
  
  depends_on = [google_service_account.api_gateway]
}

# Deploy the API Gateway to Cloud Run
resource "google_cloud_run_service" "api_gateway" {
  name     = local.service_name_unique
  location = var.region
  project  = var.project_id
  
  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"      = tostring(var.cloud_run_config.max_instances)
        "autoscaling.knative.dev/minScale"      = tostring(var.cloud_run_config.min_instances)
        "run.googleapis.com/cpu-throttling"     = "false"
        "run.googleapis.com/execution-environment" = "gen2"
      }
      
      labels = local.common_labels
    }
    
    spec {
      service_account_name  = google_service_account.api_gateway.email
      container_concurrency = var.cloud_run_config.concurrency
      timeout_seconds      = var.cloud_run_config.timeout_seconds
      
      containers {
        image = local.container_image
        
        # Resource allocation
        resources {
          limits = {
            cpu    = var.cloud_run_config.cpu_limit
            memory = var.cloud_run_config.memory_limit
          }
        }
        
        # Environment variables for the application
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        
        env {
          name  = "FIRESTORE_DATABASE"
          value = google_firestore_database.api_analytics.name
        }
        
        env {
          name  = "DEFAULT_RATE_LIMIT"
          value = tostring(var.rate_limiting_config.default_requests_per_hour)
        }
        
        env {
          name  = "RATE_WINDOW_SECONDS"
          value = tostring(var.rate_limiting_config.rate_window_seconds)
        }
        
        env {
          name  = "ENVIRONMENT"
          value = var.environment
        }
        
        # Health check port
        ports {
          name           = "http1"
          container_port = 8080
          protocol       = "TCP"
        }
        
        # Startup and liveness probes
        startup_probe {
          http_get {
            path = "/health"
            port = 8080
          }
          initial_delay_seconds = 10
          timeout_seconds      = 3
          period_seconds       = 10
          failure_threshold    = 3
        }
        
        liveness_probe {
          http_get {
            path = "/health"
            port = 8080
          }
          initial_delay_seconds = 30
          timeout_seconds      = 3
          period_seconds       = 30
          failure_threshold    = 3
        }
      }
    }
  }
  
  traffic {
    percent         = 100
    latest_revision = true
  }
  
  depends_on = [
    google_firestore_database.api_analytics,
    google_service_account.api_gateway,
    google_project_iam_member.firestore_user,
    google_project_iam_member.monitoring_writer,
    google_project_iam_member.logging_writer
  ]
  
  lifecycle {
    ignore_changes = [
      template[0].metadata[0].annotations["run.googleapis.com/operation-id"],
      template[0].metadata[0].annotations["serving.knative.dev/creator"],
      template[0].metadata[0].annotations["serving.knative.dev/lastModifier"],
      template[0].spec[0].containers[0].image
    ]
  }
}

# Configure IAM policy for Cloud Run service (allow unauthenticated access if specified)
resource "google_cloud_run_service_iam_member" "public_access" {
  count = var.cloud_run_config.allow_unauthenticated ? 1 : 0
  
  service  = google_cloud_run_service.api_gateway.name
  location = google_cloud_run_service.api_gateway.location
  role     = "roles/run.invoker"
  member   = "allUsers"
  
  depends_on = [google_cloud_run_service.api_gateway]
}

# Create Cloud Monitoring dashboard for API analytics
resource "google_monitoring_dashboard" "api_analytics" {
  count = var.monitoring_config.enable_dashboard ? 1 : 0
  
  project        = var.project_id
  dashboard_json = jsonencode({
    displayName = "API Gateway Analytics - ${var.environment}"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "API Request Rate"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_service.api_gateway.name}\""
                      aggregation = {
                        alignmentPeriod     = "60s"
                        perSeriesAligner   = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                      }
                    }
                  }
                  plotType   = "LINE"
                  targetAxis = "Y1"
                }
              ]
              yAxis = {
                label = "Requests/sec"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Response Status Codes"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_service.api_gateway.name}\" AND metric.type=\"run.googleapis.com/request_count\""
                      aggregation = {
                        alignmentPeriod     = "60s"
                        perSeriesAligner   = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields      = ["metric.labels.response_code"]
                      }
                    }
                  }
                  plotType   = "LINE"
                  targetAxis = "Y1"
                }
              ]
              yAxis = {
                label = "Requests/sec"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 12
          height = 4
          widget = {
            title = "Request Latency"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_service.api_gateway.name}\" AND metric.type=\"run.googleapis.com/request_latencies\""
                      aggregation = {
                        alignmentPeriod     = "60s"
                        perSeriesAligner   = "ALIGN_DELTA"
                        crossSeriesReducer = "REDUCE_PERCENTILE_95"
                      }
                    }
                  }
                  plotType   = "LINE"
                  targetAxis = "Y1"
                }
              ]
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
  
  depends_on = [google_cloud_run_service.api_gateway]
}

# Create notification channel for alerts (if email provided)
resource "google_monitoring_notification_channel" "email" {
  count = var.monitoring_config.enable_alerts && var.monitoring_config.alert_email != "" ? 1 : 0
  
  project      = var.project_id
  display_name = "API Gateway Alerts - ${var.environment}"
  type         = "email"
  
  labels = {
    email_address = var.monitoring_config.alert_email
  }
  
  description = "Email notification channel for API gateway alerts"
}

# Create alerting policy for high error rates
resource "google_monitoring_alert_policy" "high_error_rate" {
  count = var.monitoring_config.enable_alerts ? 1 : 0
  
  project      = var.project_id
  display_name = "API Gateway High Error Rate - ${var.environment}"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "High 4xx/5xx Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_service.api_gateway.name}\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.labels.response_code>=400"
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 10
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
      
      trigger {
        count = 1
      }
    }
  }
  
  # Add notification channels if available
  dynamic "notification_channels" {
    for_each = var.monitoring_config.alert_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  documentation {
    content   = "API Gateway is experiencing high error rates. Check the service logs and health status."
    mime_type = "text/markdown"
  }
  
  depends_on = [google_cloud_run_service.api_gateway]
}

# Create alerting policy for high latency
resource "google_monitoring_alert_policy" "high_latency" {
  count = var.monitoring_config.enable_alerts ? 1 : 0
  
  project      = var.project_id
  display_name = "API Gateway High Latency - ${var.environment}"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "High Request Latency"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_service.api_gateway.name}\" AND metric.type=\"run.googleapis.com/request_latencies\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5000 # 5 seconds in milliseconds
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_PERCENTILE_95"
      }
      
      trigger {
        count = 1
      }
    }
  }
  
  # Add notification channels if available
  dynamic "notification_channels" {
    for_each = var.monitoring_config.alert_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  documentation {
    content   = "API Gateway is experiencing high request latency. Check service performance and scaling."
    mime_type = "text/markdown"
  }
  
  depends_on = [google_cloud_run_service.api_gateway]
}

# Create Cloud Storage bucket for application source code (optional)
resource "google_storage_bucket" "source_code" {
  name     = "${var.project_id}-${var.service_name}-source-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id
  
  # Enable versioning for source code
  versioning {
    enabled = true
  }
  
  # Configure lifecycle to manage old versions
  lifecycle_rule {
    condition {
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }
  
  # Security settings
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [time_sleep.api_enablement]
}

# Create Firestore security rules (as a local file for reference)
resource "local_file" "firestore_rules" {
  content = <<-EOT
    rules_version = '2';
    service cloud.firestore {
      match /databases/{database}/documents {
        // Rate limits collection - restrict access to service account
        match /rate_limits/{document} {
          allow read, write: if request.auth != null && request.auth.token.email == '${google_service_account.api_gateway.email}';
        }
        
        // API analytics collection - allow writes from service account, reads for analytics
        match /api_analytics/{document} {
          allow write: if request.auth != null && request.auth.token.email == '${google_service_account.api_gateway.email}';
          allow read: if request.auth != null;
        }
      }
    }
  EOT
  
  filename = "${path.module}/firestore.rules"
  
  depends_on = [google_service_account.api_gateway]
}