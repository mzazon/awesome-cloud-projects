# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Resource names with random suffix for uniqueness
  topic_name        = var.topic_name != "" ? var.topic_name : "${var.resource_prefix}-queue-${random_id.suffix.hex}"
  subscription_name = var.subscription_name != "" ? var.subscription_name : "${var.resource_prefix}-sub-${random_id.suffix.hex}"
  bucket_name       = var.bucket_name != "" ? var.bucket_name : "${var.resource_prefix}-files-${var.project_id}-${random_id.suffix.hex}"
  job_name          = var.job_name != "" ? var.job_name : "${var.resource_prefix}-worker-${random_id.suffix.hex}"
  api_service_name  = var.api_service_name != "" ? var.api_service_name : "${var.resource_prefix}-api"
  
  # Service account names
  worker_sa_name = "${var.resource_prefix}-worker-${random_id.suffix.hex}"
  api_sa_name    = "${var.resource_prefix}-api-${random_id.suffix.hex}"
  
  # Container image names
  worker_image = "${var.container_registry}/${var.project_id}/${local.job_name}"
  api_image    = "${var.container_registry}/${var.project_id}/${local.api_service_name}"
  
  # Common labels
  common_labels = merge(var.labels, {
    environment = var.environment
    component   = "background-task-processing"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "run.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "containerregistry.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "iam.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Pub/Sub topic for task queue
resource "google_pubsub_topic" "task_queue" {
  name    = local.topic_name
  project = var.project_id
  
  labels = local.common_labels
  
  # Enable message ordering if needed
  message_retention_duration = var.message_retention_duration
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for worker consumption
resource "google_pubsub_subscription" "worker_subscription" {
  name    = local.subscription_name
  topic   = google_pubsub_topic.task_queue.name
  project = var.project_id
  
  labels = local.common_labels
  
  # Configure message acknowledgment settings
  ack_deadline_seconds       = var.ack_deadline_seconds
  message_retention_duration = var.message_retention_duration
  
  # Configure retry policy for failed messages
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Configure dead letter queue policy
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = var.max_delivery_attempts
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create dead letter topic for failed messages
resource "google_pubsub_topic" "dead_letter" {
  name    = "${local.topic_name}-dlq"
  project = var.project_id
  
  labels = merge(local.common_labels, {
    purpose = "dead-letter-queue"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for file processing
resource "google_storage_bucket" "task_files" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id
  
  # Configure storage class and lifecycle
  storage_class = var.storage_class
  
  # Enable versioning for data protection
  versioning {
    enabled = true
  }
  
  # Configure lifecycle management
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age
    }
    action {
      type = "Delete"
    }
  }
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
  
  # Configure uniform bucket-level access
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for worker job
resource "google_service_account" "worker_sa" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = local.worker_sa_name
  display_name = "Background Task Worker Service Account"
  description  = "Service account for Cloud Run Job background task processing"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for API service
resource "google_service_account" "api_sa" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = local.api_sa_name
  display_name = "Task API Service Account"
  description  = "Service account for Cloud Run API service"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM bindings for worker service account
resource "google_project_iam_member" "worker_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${var.create_service_accounts ? google_service_account.worker_sa[0].email : var.existing_worker_service_account}"
}

resource "google_project_iam_member" "worker_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${var.create_service_accounts ? google_service_account.worker_sa[0].email : var.existing_worker_service_account}"
}

resource "google_project_iam_member" "worker_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${var.create_service_accounts ? google_service_account.worker_sa[0].email : var.existing_worker_service_account}"
}

# IAM bindings for API service account
resource "google_project_iam_member" "api_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${var.create_service_accounts ? google_service_account.api_sa[0].email : var.existing_api_service_account}"
}

resource "google_project_iam_member" "api_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${var.create_service_accounts ? google_service_account.api_sa[0].email : var.existing_api_service_account}"
}

resource "google_project_iam_member" "api_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${var.create_service_accounts ? google_service_account.api_sa[0].email : var.existing_api_service_account}"
}

# Cloud Run Job for background task processing
resource "google_cloud_run_v2_job" "background_worker" {
  name     = local.job_name
  location = var.region
  project  = var.project_id
  
  labels = local.common_labels
  
  template {
    labels = local.common_labels
    
    # Configure job-level settings
    parallelism = var.job_parallelism
    task_count  = var.job_task_count
    
    template {
      # Configure service account
      service_account = var.create_service_accounts ? google_service_account.worker_sa[0].email : var.existing_worker_service_account
      
      # Configure timeout and retry policy
      max_retries = var.job_max_retries
      
      containers {
        # Container image (placeholder - needs to be built and pushed)
        image = local.worker_image
        
        # Resource allocation
        resources {
          limits = {
            cpu    = var.job_cpu
            memory = var.job_memory
          }
        }
        
        # Environment variables for worker configuration
        env {
          name  = "GOOGLE_CLOUD_PROJECT"
          value = var.project_id
        }
        
        env {
          name  = "SUBSCRIPTION_NAME"
          value = google_pubsub_subscription.worker_subscription.name
        }
        
        env {
          name  = "BUCKET_NAME"
          value = google_storage_bucket.task_files.name
        }
        
        env {
          name  = "MAX_MESSAGES"
          value = "10"
        }
        
        env {
          name  = "ENVIRONMENT"
          value = var.environment
        }
      }
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_pubsub_subscription.worker_subscription,
    google_storage_bucket.task_files
  ]
  
  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image
    ]
  }
}

# Cloud Run service for task submission API
resource "google_cloud_run_v2_service" "task_api" {
  name     = local.api_service_name
  location = var.region
  project  = var.project_id
  
  labels = local.common_labels
  
  template {
    labels = local.common_labels
    
    # Configure service account
    service_account = var.create_service_accounts ? google_service_account.api_sa[0].email : var.existing_api_service_account
    
    # Configure scaling
    scaling {
      min_instance_count = var.api_min_instances
      max_instance_count = var.api_max_instances
    }
    
    containers {
      # Container image (placeholder - needs to be built and pushed)
      image = local.api_image
      
      # Resource allocation
      resources {
        limits = {
          cpu    = var.api_cpu
          memory = var.api_memory
        }
        
        cpu_idle = true
        startup_cpu_boost = true
      }
      
      # Configure container port
      ports {
        container_port = 8080
        name          = "http1"
      }
      
      # Environment variables for API configuration
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
      
      env {
        name  = "TOPIC_NAME"
        value = google_pubsub_topic.task_queue.name
      }
      
      env {
        name  = "PORT"
        value = "8080"
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
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 3
      }
      
      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds       = 5
        period_seconds        = 30
        failure_threshold     = 3
      }
    }
  }
  
  # Configure traffic allocation
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_pubsub_topic.task_queue
  ]
  
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image
    ]
  }
}

# IAM policy for public access to API service (if enabled)
resource "google_cloud_run_service_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0
  
  location = google_cloud_run_v2_service.task_api.location
  project  = google_cloud_run_v2_service.task_api.project
  service  = google_cloud_run_v2_service.task_api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Cloud Logging sinks (if enabled)
resource "google_logging_project_sink" "task_processing_logs" {
  count = var.enable_cloud_logging ? 1 : 0
  
  name        = "${var.resource_prefix}-task-logs-${random_id.suffix.hex}"
  destination = "storage.googleapis.com/${google_storage_bucket.logs[0].name}"
  
  # Filter for Cloud Run and Pub/Sub logs
  filter = <<-EOT
    resource.type="cloud_run_revision" OR 
    resource.type="cloud_run_job" OR 
    resource.type="pubsub_topic" OR 
    resource.type="pubsub_subscription"
  EOT
  
  unique_writer_identity = true
  
  depends_on = [google_project_service.required_apis]
}

# Storage bucket for logs (if logging is enabled)
resource "google_storage_bucket" "logs" {
  count = var.enable_cloud_logging ? 1 : 0
  
  name     = "${local.bucket_name}-logs"
  location = var.region
  project  = var.project_id
  
  storage_class = "NEARLINE"
  
  # Configure lifecycle for log retention
  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  uniform_bucket_level_access = true
  
  labels = merge(local.common_labels, {
    purpose = "logging"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Grant Cloud Logging write access to logs bucket
resource "google_storage_bucket_iam_member" "logs_writer" {
  count = var.enable_cloud_logging ? 1 : 0
  
  bucket = google_storage_bucket.logs[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.task_processing_logs[0].writer_identity
}

# Monitoring dashboard for background task processing
resource "google_monitoring_dashboard" "task_processing" {
  dashboard_json = jsonencode({
    displayName = "Background Task Processing Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Pub/Sub Message Backlog"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"pubsub_subscription\" AND resource.labels.subscription_id=\"${google_pubsub_subscription.worker_subscription.name}\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
                unitOverride = "1"
              }
              gaugeView = {
                lowerBound = 0
                upperBound = 1000
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
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${google_cloud_run_v2_job.background_worker.name}\""
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_RATE"
                  }
                }
                unitOverride = "1/s"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}