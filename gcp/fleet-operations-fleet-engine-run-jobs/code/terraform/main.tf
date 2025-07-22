# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming
locals {
  resource_suffix = random_id.suffix.hex
  bucket_name     = "${var.bucket_name}-${local.resource_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    fleet-name = var.fleet_name
    created-by = "terraform"
    timestamp  = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Required APIs for Fleet Engine and supporting services
  required_apis = [
    "fleetengine.googleapis.com",
    "run.googleapis.com",
    "cloudscheduler.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "firestore.googleapis.com",
    "maps-backend.googleapis.com",
    "routes.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  timeouts {
    create = "30m"
    update = "40m"
  }
  
  disable_dependent_services = true
}

# Create service account for Fleet Engine operations
resource "google_service_account" "fleet_engine_sa" {
  account_id   = "fleet-engine-sa-${local.resource_suffix}"
  display_name = "Fleet Engine Service Account"
  description  = "Service account for Fleet Engine operations and analytics processing"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Create service account key for Fleet Engine authentication
resource "google_service_account_key" "fleet_engine_key" {
  service_account_id = google_service_account.fleet_engine_sa.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

# IAM roles for Fleet Engine service account
resource "google_project_iam_member" "fleet_engine_roles" {
  for_each = toset([
    "roles/fleetengine.deliveryFleetReader",
    "roles/fleetengine.deliveryConsumer",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/storage.objectAdmin",
    "roles/datastore.user",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/run.invoker"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.fleet_engine_sa.email}"
  
  depends_on = [google_service_account.fleet_engine_sa]
}

# Cloud Storage bucket for fleet data
resource "google_storage_bucket" "fleet_data" {
  name          = local.bucket_name
  location      = var.bucket_location
  storage_class = var.bucket_storage_class
  project       = var.project_id
  
  # Enable versioning for data protection
  versioning {
    enabled = true
  }
  
  # Configure lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.enable_lifecycle_policy ? [1] : []
    content {
      condition {
        age = var.nearline_age_days
      }
      action {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
    }
  }
  
  dynamic "lifecycle_rule" {
    for_each = var.enable_lifecycle_policy ? [1] : []
    content {
      condition {
        age = var.coldline_age_days
      }
      action {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
    }
  }
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create organized folder structure in the bucket
resource "google_storage_bucket_object" "folder_structure" {
  for_each = toset([
    "vehicle-telemetry/",
    "route-histories/",
    "analytics-results/"
  ])
  
  name   = "${each.value}README.txt"
  bucket = google_storage_bucket.fleet_data.name
  content = "Fleet operations data folder: ${each.value}"
  
  depends_on = [google_storage_bucket.fleet_data]
}

# BigQuery dataset for fleet analytics
resource "google_bigquery_dataset" "fleet_analytics" {
  dataset_id    = var.dataset_name
  friendly_name = "Fleet Analytics Dataset"
  description   = "Dataset for storing and analyzing fleet operations data"
  location      = var.dataset_location
  project       = var.project_id
  
  # Set default table expiration to 1 year for cost control
  default_table_expiration_ms = 31536000000 # 1 year in milliseconds
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery table for vehicle telemetry data
resource "google_bigquery_table" "vehicle_telemetry" {
  dataset_id          = google_bigquery_dataset.fleet_analytics.dataset_id
  table_id            = "vehicle_telemetry"
  project             = var.project_id
  deletion_protection = var.table_deletion_protection
  
  description = "Vehicle telemetry and location data from Fleet Engine"
  
  schema = jsonencode([
    {
      name = "vehicle_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the vehicle"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp of the telemetry data"
    },
    {
      name = "latitude"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Vehicle latitude coordinate"
    },
    {
      name = "longitude"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Vehicle longitude coordinate"
    },
    {
      name = "speed"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Vehicle speed in km/h"
    },
    {
      name = "fuel_level"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Fuel level as percentage (0.0 to 1.0)"
    },
    {
      name = "engine_status"
      type = "STRING"
      mode = "NULLABLE"
      description = "Engine status (running, stopped, idle)"
    },
    {
      name = "driver_id"
      type = "STRING"
      mode = "NULLABLE"
      description = "Unique identifier for the driver"
    }
  ])
  
  labels = local.common_labels
}

# BigQuery table for route performance metrics
resource "google_bigquery_table" "route_performance" {
  dataset_id          = google_bigquery_dataset.fleet_analytics.dataset_id
  table_id            = "route_performance"
  project             = var.project_id
  deletion_protection = var.table_deletion_protection
  
  description = "Route performance and optimization metrics"
  
  schema = jsonencode([
    {
      name = "route_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the route"
    },
    {
      name = "vehicle_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Vehicle that completed the route"
    },
    {
      name = "start_time"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Route start timestamp"
    },
    {
      name = "end_time"
      type = "TIMESTAMP"
      mode = "NULLABLE"
      description = "Route completion timestamp"
    },
    {
      name = "distance_km"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Total route distance in kilometers"
    },
    {
      name = "fuel_consumed"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Fuel consumed during route in liters"
    },
    {
      name = "average_speed"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Average speed during route in km/h"
    },
    {
      name = "stops_count"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of stops during the route"
    },
    {
      name = "efficiency_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Route efficiency score (0.0 to 1.0)"
    }
  ])
  
  labels = local.common_labels
}

# BigQuery table for delivery tasks
resource "google_bigquery_table" "delivery_tasks" {
  dataset_id          = google_bigquery_dataset.fleet_analytics.dataset_id
  table_id            = "delivery_tasks"
  project             = var.project_id
  deletion_protection = var.table_deletion_protection
  
  description = "Delivery task tracking and completion data"
  
  schema = jsonencode([
    {
      name = "task_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the delivery task"
    },
    {
      name = "vehicle_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Vehicle assigned to the task"
    },
    {
      name = "driver_id"
      type = "STRING"
      mode = "NULLABLE"
      description = "Driver assigned to the task"
    },
    {
      name = "pickup_location"
      type = "STRING"
      mode = "NULLABLE"
      description = "Pickup location address or coordinates"
    },
    {
      name = "delivery_location"
      type = "STRING"
      mode = "NULLABLE"
      description = "Delivery location address or coordinates"
    },
    {
      name = "scheduled_time"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Scheduled delivery time"
    },
    {
      name = "completed_time"
      type = "TIMESTAMP"
      mode = "NULLABLE"
      description = "Actual completion time"
    },
    {
      name = "status"
      type = "STRING"
      mode = "REQUIRED"
      description = "Task status (pending, in_progress, completed, failed)"
    },
    {
      name = "customer_rating"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Customer satisfaction rating (1-5)"
    }
  ])
  
  labels = local.common_labels
}

# Enable Firestore database for real-time fleet state
resource "google_firestore_database" "fleet_state" {
  count       = var.enable_firestore ? 1 : 0
  project     = var.project_id
  name        = "(default)"
  location_id = var.firestore_location
  type        = "FIRESTORE_NATIVE"
  
  depends_on = [google_project_service.required_apis]
}

# Create Firestore indexes for optimized queries
resource "google_firestore_index" "vehicles_status_index" {
  count      = var.enable_firestore ? 1 : 0
  project    = var.project_id
  database   = google_firestore_database.fleet_state[0].name
  collection = "vehicles"
  
  fields {
    field_path = "status"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "last_updated"
    order      = "DESCENDING"
  }
  
  depends_on = [google_firestore_database.fleet_state]
}

resource "google_firestore_index" "delivery_tasks_index" {
  count      = var.enable_firestore ? 1 : 0
  project    = var.project_id
  database   = google_firestore_database.fleet_state[0].name
  collection = "delivery_tasks"
  
  fields {
    field_path = "vehicle_id"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "status"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "scheduled_time"
    order      = "ASCENDING"
  }
  
  depends_on = [google_firestore_database.fleet_state]
}

# Create Artifact Registry repository for container images
resource "google_artifact_registry_repository" "fleet_containers" {
  repository_id = "fleet-analytics-${local.resource_suffix}"
  format        = "DOCKER"
  location      = var.region
  project       = var.project_id
  description   = "Container repository for fleet analytics jobs"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Build trigger for analytics container
resource "google_cloudbuild_trigger" "analytics_build" {
  project     = var.project_id
  name        = "fleet-analytics-build-${local.resource_suffix}"
  description = "Build trigger for fleet analytics container"
  
  # Build from inline configuration
  build {
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t",
        "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.fleet_containers.repository_id}/${var.container_image_name}:latest",
        "."
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.fleet_containers.repository_id}/${var.container_image_name}:latest"
      ]
    }
    
    timeout = var.build_timeout
  }
  
  depends_on = [google_artifact_registry_repository.fleet_containers]
}

# Create Cloud Run Job for fleet analytics processing
resource "google_cloud_run_v2_job" "fleet_analytics" {
  name     = "${var.analytics_job_name}-${local.resource_suffix}"
  location = var.region
  project  = var.project_id
  
  template {
    template {
      # Configure job execution parameters
      timeout         = "${var.job_timeout}s"
      max_retries     = var.job_max_retries
      service_account = google_service_account.fleet_engine_sa.email
      
      containers {
        image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.fleet_containers.repository_id}/${var.container_image_name}:latest"
        
        resources {
          limits = {
            cpu    = var.job_cpu_limit
            memory = var.job_memory_limit
          }
        }
        
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        
        env {
          name  = "DATASET_NAME"
          value = var.dataset_name
        }
        
        env {
          name  = "BUCKET_NAME"
          value = google_storage_bucket.fleet_data.name
        }
        
        env {
          name  = "REGION"
          value = var.region
        }
        
        env {
          name  = "FLEET_NAME"
          value = var.fleet_name
        }
      }
    }
    
    parallelism = 1
    task_count  = 1
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_iam_member.fleet_engine_roles,
    google_artifact_registry_repository.fleet_containers
  ]
}

# Cloud Scheduler job for daily analytics processing
resource "google_cloud_scheduler_job" "daily_analytics" {
  count       = var.enable_scheduler ? 1 : 0
  name        = "fleet-analytics-daily-${local.resource_suffix}"
  description = "Daily fleet analytics processing job"
  schedule    = var.daily_schedule
  time_zone   = var.time_zone
  region      = var.region
  project     = var.project_id
  
  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.fleet_analytics.name}:run"
    
    oidc_token {
      service_account_email = google_service_account.fleet_engine_sa.email
      audience              = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.fleet_analytics.name}:run"
    }
  }
  
  retry_config {
    retry_count          = 3
    max_retry_duration   = "300s"
    min_backoff_duration = "5s"
    max_backoff_duration = "3600s"
  }
  
  depends_on = [
    google_cloud_run_v2_job.fleet_analytics,
    google_project_service.required_apis
  ]
}

# Cloud Scheduler job for hourly insights processing
resource "google_cloud_scheduler_job" "hourly_insights" {
  count       = var.enable_scheduler ? 1 : 0
  name        = "fleet-insights-hourly-${local.resource_suffix}"
  description = "Hourly fleet insights processing job"
  schedule    = var.hourly_schedule
  time_zone   = var.time_zone
  region      = var.region
  project     = var.project_id
  
  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.fleet_analytics.name}:run"
    
    oidc_token {
      service_account_email = google_service_account.fleet_engine_sa.email
      audience              = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.fleet_analytics.name}:run"
    }
  }
  
  retry_config {
    retry_count          = 3
    max_retry_duration   = "300s"
    min_backoff_duration = "5s"
    max_backoff_duration = "3600s"
  }
  
  depends_on = [
    google_cloud_run_v2_job.fleet_analytics,
    google_project_service.required_apis
  ]
}

# Create monitoring notification channel for alerts
resource "google_monitoring_notification_channel" "email_alerts" {
  count        = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  display_name = "Fleet Operations Email Alerts"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create monitoring alert policy for failed analytics jobs
resource "google_monitoring_alert_policy" "job_failure_alert" {
  count               = var.enable_monitoring ? 1 : 0
  display_name        = "Fleet Analytics Job Failures"
  combiner           = "OR"
  enabled            = true
  project            = var.project_id
  
  conditions {
    display_name = "Analytics Job Failure Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${google_cloud_run_v2_job.fleet_analytics.name}\" AND metric.type=\"run.googleapis.com/job/failed_execution_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email_alerts[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
  
  depends_on = [
    google_cloud_run_v2_job.fleet_analytics,
    google_project_service.required_apis
  ]
}

# Create monitoring dashboard for fleet operations
resource "google_monitoring_dashboard" "fleet_operations" {
  count        = var.enable_monitoring ? 1 : 0
  project      = var.project_id
  dashboard_json = jsonencode({
    displayName = "Fleet Operations Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width = 6
          height = 4
          widget = {
            title = "Fleet Engine API Requests"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"consumed_api\" AND resource.label.service=\"fleetengine.googleapis.com\""
                      aggregation = {
                        alignmentPeriod = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }
              ]
              yAxis = {
                label = "Requests per second"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          xPos = 6
          widget = {
            title = "Cloud Run Job Executions"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_job\" AND resource.label.job_name=\"${google_cloud_run_v2_job.fleet_analytics.name}\""
                      aggregation = {
                        alignmentPeriod = "300s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }
              ]
              yAxis = {
                label = "Executions per second"
              }
            }
          }
        },
        {
          width = 12
          height = 4
          yPos = 4
          widget = {
            title = "BigQuery Query Performance"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"bigquery_project\""
                      aggregation = {
                        alignmentPeriod = "300s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }
              ]
              yAxis = {
                label = "Queries per second"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [
    google_project_service.required_apis,
    google_cloud_run_v2_job.fleet_analytics
  ]
}