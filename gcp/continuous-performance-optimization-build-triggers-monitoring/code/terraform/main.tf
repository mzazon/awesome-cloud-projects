# Main Terraform Configuration for Continuous Performance Optimization
# This file creates the complete infrastructure for automated performance monitoring and optimization

# Generate random suffix for unique resource names
resource "random_hex" "suffix" {
  length = 3
}

locals {
  # Create consistent resource naming
  resource_suffix = var.resource_suffix != "" ? var.resource_suffix : random_hex.suffix.hex
  
  # Common resource names
  repo_name           = "${var.repo_name}-${local.resource_suffix}"
  service_name        = "${var.service_name}-${local.resource_suffix}"
  build_trigger_name  = "${var.build_trigger_name}-${local.resource_suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    created-by = "terraform"
    recipe     = "continuous-performance-optimization"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "cloudbuild.googleapis.com",
    "monitoring.googleapis.com",
    "sourcerepo.googleapis.com",
    "run.googleapis.com",
    "containerregistry.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ]) : toset([])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling services when resource is destroyed
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Cloud Source Repository for application code
resource "google_sourcerepo_repository" "app_repo" {
  name       = local.repo_name
  project    = var.project_id
  depends_on = [google_project_service.required_apis]
  
  # Labels for organization
  labels = local.common_labels
}

# Create Cloud Build trigger for performance optimization
resource "google_cloudbuild_trigger" "performance_trigger" {
  name        = local.build_trigger_name
  project     = var.project_id
  description = "Automated performance optimization trigger for Cloud Run deployment"
  
  # Source repository configuration
  trigger_template {
    repo_name   = google_sourcerepo_repository.app_repo.name
    branch_name = var.branch_pattern
  }
  
  # Build configuration
  build {
    timeout = "${var.build_timeout}s"
    
    # Build optimized container image
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", "gcr.io/$PROJECT_ID/${local.service_name}:$BUILD_ID",
        "-t", "gcr.io/$PROJECT_ID/${local.service_name}:latest",
        "."
      ]
      id = "build-image"
    }
    
    # Push image to Container Registry
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push", "gcr.io/$PROJECT_ID/${local.service_name}:$BUILD_ID"
      ]
      id       = "push-image"
      wait_for = ["build-image"]
    }
    
    # Deploy to Cloud Run with performance optimizations
    step {
      name = "gcr.io/cloud-builders/gcloud"
      args = [
        "run", "deploy", local.service_name,
        "--image=gcr.io/$PROJECT_ID/${local.service_name}:$BUILD_ID",
        "--region=${var.region}",
        "--platform=managed",
        "--allow-unauthenticated",
        "--memory=${var.cloud_run_memory}",
        "--cpu=${var.cloud_run_cpu}",
        "--concurrency=${var.cloud_run_concurrency}",
        "--max-instances=${var.cloud_run_max_instances}",
        "--min-instances=${var.cloud_run_min_instances}",
        "--port=8080",
        "--set-env-vars=NODE_ENV=production,OPTIMIZATION_BUILD=true"
      ]
      id       = "deploy-service"
      wait_for = ["push-image"]
    }
    
    # Verify deployment health
    step {
      name = "gcr.io/cloud-builders/curl"
      args = [
        "-f", "-s", "-o", "/dev/null",
        "-w", "Deploy verification: %{http_code} - Response time: %{time_total}s",
        "https://${local.service_name}-${var.region}-$PROJECT_ID.a.run.app/health"
      ]
      id       = "verify-deployment"
      wait_for = ["deploy-service"]
    }
    
    # Substitution variables
    substitutions = {
      _SERVICE_NAME = local.service_name
      _REGION       = var.region
    }
    
    # Build options
    options {
      logging      = "CLOUD_LOGGING_ONLY"
      machine_type = "E2_HIGHCPU_8"
    }
  }
  
  # Tags for organization
  tags = ["performance-optimization", "automated-deployment"]
  
  depends_on = [
    google_project_service.required_apis,
    google_sourcerepo_repository.app_repo
  ]
}

# Create Cloud Run service for the application
resource "google_cloud_run_service" "app_service" {
  name       = local.service_name
  location   = var.region
  project    = var.project_id
  depends_on = [google_project_service.required_apis]
  
  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"      = tostring(var.cloud_run_max_instances)
        "autoscaling.knative.dev/minScale"      = tostring(var.cloud_run_min_instances)
        "run.googleapis.com/cpu-throttling"     = "false"
        "run.googleapis.com/execution-environment" = "gen2"
      }
      
      labels = local.common_labels
    }
    
    spec {
      container_concurrency = var.cloud_run_concurrency
      service_account_name  = google_service_account.cloud_run_sa.email
      
      containers {
        image = var.container_image
        
        # Resource allocation
        resources {
          limits = {
            memory = var.cloud_run_memory
            cpu    = var.cloud_run_cpu
          }
        }
        
        # Environment variables
        dynamic "env" {
          for_each = var.environment_variables
          content {
            name  = env.key
            value = env.value
          }
        }
        
        # Health check configuration
        ports {
          container_port = 8080
          name           = "http1"
        }
        
        # Liveness probe
        liveness_probe {
          http_get {
            path = "/health"
            port = 8080
          }
          initial_delay_seconds = 30
          period_seconds        = 10
          timeout_seconds       = 5
          failure_threshold     = 3
        }
        
        # Readiness probe  
        readiness_probe {
          http_get {
            path = "/health"
            port = 8080
          }
          initial_delay_seconds = 5
          period_seconds        = 5
          timeout_seconds       = 3
          failure_threshold     = 3
        }
      }
    }
  }
  
  traffic {
    percent         = 100
    latest_revision = true
  }
  
  lifecycle {
    ignore_changes = [
      template[0].spec[0].containers[0].image,
      template[0].metadata[0].annotations["run.googleapis.com/operation-id"]
    ]
  }
}

# Create service account for Cloud Run
resource "google_service_account" "cloud_run_sa" {
  account_id   = "${local.service_name}-sa"
  display_name = "Cloud Run Service Account for ${local.service_name}"
  description  = "Service account for Cloud Run service with monitoring permissions"
  project      = var.project_id
}

# Grant necessary permissions to Cloud Run service account
resource "google_project_iam_member" "cloud_run_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "cloud_run_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Allow public access to Cloud Run service
resource "google_cloud_run_service_iam_policy" "public_access" {
  location = google_cloud_run_service.app_service.location
  project  = google_cloud_run_service.app_service.project
  service  = google_cloud_run_service.app_service.name
  
  policy_data = data.google_iam_policy.public_access.policy_data
}

data "google_iam_policy" "public_access" {
  binding {
    role    = "roles/run.invoker"
    members = ["allUsers"]
  }
}

# Create monitoring alert policy for response time
resource "google_monitoring_alert_policy" "response_time_alert" {
  display_name = "Performance Optimization - High Response Time"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true
  
  documentation {
    content   = "Triggers performance optimization builds when response time exceeds thresholds"
    mime_type = "text/markdown"
  }
  
  conditions {
    display_name = "High Response Time"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_latencies\" AND resource.labels.service_name=\"${local.service_name}\""
      duration       = var.alert_duration
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = var.response_time_threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields    = ["resource.label.service_name"]
      }
    }
  }
  
  # Notification channels
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].name] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  # Alert strategy
  alert_strategy {
    auto_close = "1800s"  # 30 minutes
    
    notification_rate_limit {
      period = "300s"  # 5 minutes
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloud_run_service.app_service
  ]
}

# Create monitoring alert policy for memory usage
resource "google_monitoring_alert_policy" "memory_alert" {
  display_name = "Performance Optimization - High Memory Usage"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true
  
  documentation {
    content   = "Triggers performance optimization builds when memory usage exceeds thresholds"
    mime_type = "text/markdown"
  }
  
  conditions {
    display_name = "High Memory Usage"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/container/memory/utilizations\" AND resource.labels.service_name=\"${local.service_name}\""
      duration       = "180s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = var.memory_threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields    = ["resource.label.service_name"]
      }
    }
  }
  
  # Notification channels
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].name] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  # Alert strategy
  alert_strategy {
    auto_close = "1800s"  # 30 minutes
    
    notification_rate_limit {
      period = "300s"  # 5 minutes
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloud_run_service.app_service
  ]
}

# Create email notification channel (optional)
resource "google_monitoring_notification_channel" "email" {
  count        = var.notification_email != "" ? 1 : 0
  display_name = "Performance Optimization Email Notifications"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create webhook notification channel for build triggers
resource "google_monitoring_notification_channel" "webhook" {
  display_name = "Performance Optimization Webhook"
  type         = "webhook_tokenauth"
  project      = var.project_id
  
  labels = {
    url = "https://cloudbuild.googleapis.com/v1/projects/${var.project_id}/triggers/${google_cloudbuild_trigger.performance_trigger.trigger_id}:webhook"
  }
  
  user_labels = {
    purpose   = "performance-optimization"
    component = "automated-builds"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudbuild_trigger.performance_trigger
  ]
}

# Create custom log-based metrics for performance monitoring
resource "google_logging_metric" "response_time_metric" {
  name    = "performance_response_time"
  project = var.project_id
  filter  = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${local.service_name}\" AND jsonPayload.responseTime EXISTS"
  
  label_extractors = {
    service_name = "EXTRACT(resource.labels.service_name)"
  }
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    unit        = "s"
    display_name = "Application Response Time"
  }
  
  value_extractor = "EXTRACT(jsonPayload.responseTime)"
  
  depends_on = [
    google_project_service.required_apis,
    google_cloud_run_service.app_service
  ]
}

# Create log sink for performance metrics
resource "google_logging_project_sink" "performance_sink" {
  name        = "performance-metrics-sink"
  project     = var.project_id
  destination = "logging.googleapis.com/projects/${var.project_id}/logs/performance-metrics"
  
  filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${local.service_name}\" AND (jsonPayload.responseTime EXISTS OR jsonPayload.errorRate EXISTS)"
  
  unique_writer_identity = true
  
  depends_on = [
    google_project_service.required_apis,
    google_cloud_run_service.app_service
  ]
}

# Create dashboard for performance monitoring
resource "google_monitoring_dashboard" "performance_dashboard" {
  project        = var.project_id
  dashboard_json = jsonencode({
    displayName = "Performance Optimization Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Response Time"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_latencies\" AND resource.labels.service_name=\"${local.service_name}\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_MEAN"
                        groupByFields      = ["resource.label.service_name"]
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "seconds"
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
            title = "Memory Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/container/memory/utilizations\" AND resource.labels.service_name=\"${local.service_name}\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_MEAN"
                        groupByFields      = ["resource.label.service_name"]
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "utilization"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          yPos   = 4
          widget = {
            title = "Request Count"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\" AND resource.labels.service_name=\"${local.service_name}\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields      = ["resource.label.service_name"]
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "requests/second"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          yPos   = 4
          widget = {
            title = "Instance Count"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/container/instance_count\" AND resource.labels.service_name=\"${local.service_name}\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields      = ["resource.label.service_name"]
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "instances"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [
    google_project_service.required_apis,
    google_cloud_run_service.app_service
  ]
}