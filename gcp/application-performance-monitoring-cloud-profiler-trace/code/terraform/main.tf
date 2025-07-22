# Main Terraform configuration for Application Performance Monitoring
# This configuration creates a complete observability stack with Cloud Profiler and Cloud Trace

# Generate a random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming and configuration
locals {
  resource_prefix = "${var.application_name}-${var.environment}"
  resource_suffix = random_string.suffix.result
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    terraform = "true"
    recipe    = "application-performance-monitoring-cloud-profiler-trace"
  })
  
  # List of required Google Cloud APIs
  required_apis = [
    "run.googleapis.com",
    "cloudprofiler.googleapis.com",
    "cloudtrace.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ]
  
  # Service definitions with their configurations
  services = {
    frontend = {
      image_name = "frontend-service"
      port       = 8080
      env_vars = {
        GOOGLE_CLOUD_PROJECT = var.project_id
        API_SERVICE_URL      = "https://${google_cloud_run_v2_service.services["api-gateway"].uri}"
      }
    }
    api-gateway = {
      image_name = "api-gateway-service"
      port       = 8081
      env_vars = {
        GOOGLE_CLOUD_PROJECT = var.project_id
        AUTH_SERVICE_URL     = "https://${google_cloud_run_v2_service.services["auth-service"].uri}"
        DATA_SERVICE_URL     = "https://${google_cloud_run_v2_service.services["data-service"].uri}"
      }
    }
    auth-service = {
      image_name = "auth-service"
      port       = 8082
      env_vars = {
        GOOGLE_CLOUD_PROJECT = var.project_id
      }
    }
    data-service = {
      image_name = "data-service"
      port       = 8083
      env_vars = {
        GOOGLE_CLOUD_PROJECT = var.project_id
      }
    }
  }
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(local.required_apis) : []
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

# Create Artifact Registry repository for container images
resource "google_artifact_registry_repository" "container_registry" {
  location      = var.artifact_registry_location
  repository_id = "${local.resource_prefix}-containers-${local.resource_suffix}"
  description   = "Container repository for performance monitoring microservices"
  format        = var.artifact_registry_format
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for Cloud Run services with appropriate permissions
resource "google_service_account" "profiler_trace_sa" {
  account_id   = "${var.service_account_name}-${local.resource_suffix}"
  display_name = "Cloud Profiler and Trace Service Account"
  description  = "Service account for Cloud Run services with profiling and tracing permissions"
  
  depends_on = [google_project_service.required_apis]
}

# Grant Cloud Profiler Agent role to service account
resource "google_project_iam_member" "profiler_agent" {
  project = var.project_id
  role    = "roles/cloudprofiler.agent"
  member  = "serviceAccount:${google_service_account.profiler_trace_sa.email}"
  
  depends_on = [google_service_account.profiler_trace_sa]
}

# Grant Cloud Trace Agent role to service account
resource "google_project_iam_member" "trace_agent" {
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.profiler_trace_sa.email}"
  
  depends_on = [google_service_account.profiler_trace_sa]
}

# Grant Monitoring Metric Writer role for custom metrics
resource "google_project_iam_member" "monitoring_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.profiler_trace_sa.email}"
  
  depends_on = [google_service_account.profiler_trace_sa]
}

# Grant Cloud Run Invoker role for service-to-service communication
resource "google_project_iam_member" "cloud_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.profiler_trace_sa.email}"
  
  depends_on = [google_service_account.profiler_trace_sa]
}

# Create Cloud Run services for each microservice
resource "google_cloud_run_v2_service" "services" {
  for_each = local.services
  
  name     = "${each.key}-${local.resource_suffix}"
  location = var.region
  
  deletion_protection = var.delete_protection
  
  template {
    labels = local.common_labels
    
    # Configure service account and execution environment
    service_account = google_service_account.profiler_trace_sa.email
    
    # Set timeout for long-running operations
    timeout = "${var.cloud_run_services[each.key].timeout}s"
    
    # Configure auto-scaling
    scaling {
      min_instance_count = var.cloud_run_services[each.key].min_instances
      max_instance_count = var.cloud_run_services[each.key].max_instances
    }
    
    containers {
      # Container image will be built and pushed separately
      image = "${var.artifact_registry_location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_registry.repository_id}/${each.value.image_name}:latest"
      
      # Configure container resources
      resources {
        limits = {
          cpu    = var.cloud_run_services[each.key].cpu_limit
          memory = var.cloud_run_services[each.key].memory_limit
        }
        cpu_idle = true
        startup_cpu_boost = true
      }
      
      # Configure container port
      ports {
        container_port = each.value.port
        name           = "http1"
      }
      
      # Environment variables for profiling and tracing
      dynamic "env" {
        for_each = merge(
          each.value.env_vars,
          var.cloud_profiler_enabled ? {
            GOOGLE_CLOUD_PROFILER_ENABLED = "true"
            GOOGLE_CLOUD_PROFILER_SERVICE = each.key
            GOOGLE_CLOUD_PROFILER_VERSION = "1.0.0"
          } : {},
          var.cloud_trace_enabled ? {
            GOOGLE_CLOUD_TRACE_ENABLED    = "true"
            GOOGLE_CLOUD_TRACE_SAMPLE_RATE = tostring(var.cloud_trace_sample_rate)
          } : {}
        )
        content {
          name  = env.key
          value = env.value
        }
      }
      
      # Configure startup and liveness probes
      startup_probe {
        http_get {
          path = "/health"
          port = each.value.port
        }
        initial_delay_seconds = 10
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 3
      }
      
      liveness_probe {
        http_get {
          path = "/health"
          port = each.value.port
        }
        initial_delay_seconds = 30
        timeout_seconds       = 5
        period_seconds        = 30
        failure_threshold     = 3
      }
    }
  }
  
  # Configure traffic allocation (100% to latest revision)
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_artifact_registry_repository.container_registry,
    google_service_account.profiler_trace_sa,
    google_project_iam_member.profiler_agent,
    google_project_iam_member.trace_agent
  ]
}

# Configure IAM policy for Cloud Run services (allow unauthenticated access if enabled)
resource "google_cloud_run_v2_service_iam_member" "allow_unauthenticated" {
  for_each = var.cloud_run_allow_unauthenticated ? local.services : {}
  
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.services[each.key].name
  role     = "roles/run.invoker"
  member   = "allUsers"
  
  depends_on = [google_cloud_run_v2_service.services]
}

# Create Cloud Monitoring dashboard for application performance
resource "google_monitoring_dashboard" "performance_dashboard" {
  count = var.monitoring_dashboard_enabled ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Application Performance Monitoring Dashboard"
    mosaicLayout = {
      tiles = [
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
                      filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"${local.resource_prefix}-.*\""
                      aggregation = {
                        alignmentPeriod     = "60s"
                        perSeriesAligner    = "ALIGN_MEAN"
                        crossSeriesReducer  = "REDUCE_MEAN"
                        groupByFields       = ["resource.label.service_name"]
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Latency (seconds)"
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
            title = "Cloud Trace Request Count"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"${local.resource_prefix}-.*\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields      = ["resource.label.service_name"]
                      }
                    }
                  }
                  plotType = "STACKED_AREA"
                }
              ]
              yAxis = {
                label = "Requests per second"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 12
          height = 4
          yPos   = 4
          widget = {
            title = "Service CPU Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"${local.resource_prefix}-.*\" AND metric.type=\"run.googleapis.com/container/cpu/utilizations\""
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
              yAxis = {
                label = "CPU Utilization (%)"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 12
          height = 4
          yPos   = 8
          widget = {
            title = "Memory Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"${local.resource_prefix}-.*\" AND metric.type=\"run.googleapis.com/container/memory/utilizations\""
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
              yAxis = {
                label = "Memory Utilization (%)"
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

# Create alert policy for high application latency
resource "google_monitoring_alert_policy" "high_latency_alert" {
  count = var.alert_policies_enabled ? 1 : 0
  
  display_name = "High Application Latency Alert - ${local.resource_prefix}"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Cloud Run request latency above threshold"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"${local.resource_prefix}-.*\" AND metric.type=\"run.googleapis.com/request_latencies\""
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = var.high_latency_threshold
      duration       = "300s"
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.label.service_name"]
      }
      
      trigger {
        count = 1
      }
    }
  }
  
  # Configure notification channels if provided
  dynamic "notification_channels" {
    for_each = var.notification_channels
    content {
      name = notification_channels.value
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
    
    notification_rate_limit {
      period = "300s"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create alert policy for high error rate
resource "google_monitoring_alert_policy" "high_error_rate_alert" {
  count = var.alert_policies_enabled ? 1 : 0
  
  display_name = "High Error Rate Alert - ${local.resource_prefix}"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Cloud Run error rate above threshold"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"${local.resource_prefix}-.*\" AND metric.type=\"run.googleapis.com/request_count\""
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 0.05  # 5% error rate
      duration       = "300s"
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.service_name", "metric.label.response_code_class"]
      }
      
      trigger {
        count = 1
      }
    }
  }
  
  # Configure notification channels if provided
  dynamic "notification_channels" {
    for_each = var.notification_channels
    content {
      name = notification_channels.value
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
    
    notification_rate_limit {
      period = "300s"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create log-based metric for custom application metrics
resource "google_logging_metric" "application_performance_metric" {
  name   = "${local.resource_prefix}-performance-metric"
  filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"${local.resource_prefix}-.*\" AND textPayload:\"processing_time_ms\""
  
  label_extractors = {
    "service_name" = "EXTRACT(resource.labels.service_name)"
  }
  
  value_extractor = "EXTRACT(jsonPayload.processing_time_ms)"
  
  bucket_options {
    exponential_buckets {
      num_finite_buckets = 64
      growth_factor      = 2.0
      scale              = 1.0
    }
  }
  
  depends_on = [google_project_service.required_apis]
}