# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  resource_suffix = random_id.suffix.hex
  
  # Resource names with unique suffixes
  upload_bucket_name      = "${var.application_name}-upload-${local.resource_suffix}"
  results_bucket_name     = "${var.application_name}-results-${local.resource_suffix}"
  pubsub_topic_name       = "${var.application_name}-topic-${local.resource_suffix}"
  pubsub_subscription_name = "${var.application_name}-subscription-${local.resource_suffix}"
  task_queue_name         = "${var.application_name}-queue-${local.resource_suffix}"
  upload_service_name     = "${var.application_name}-upload-${local.resource_suffix}"
  processing_service_name = "${var.application_name}-processor-${local.resource_suffix}"
  
  # Service account names
  upload_sa_name     = "${var.application_name}-upload-sa-${local.resource_suffix}"
  processing_sa_name = "${var.application_name}-processor-sa-${local.resource_suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    project     = var.project_id
    region      = var.region
    environment = var.environment
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudbuild.googleapis.com",
    "cloudtasks.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
    "pubsub.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = true
  disable_on_destroy         = false
}

# Create Artifact Registry repository for container images
resource "google_artifact_registry_repository" "container_repo" {
  repository_id = "${var.application_name}-repo"
  format        = "DOCKER"
  location      = var.region
  description   = "Container repository for file processing services"
  
  labels = local.common_labels
  
  # Enable vulnerability scanning if configured
  dynamic "vulnerability_scanning_config" {
    for_each = var.enable_vulnerability_scanning ? [1] : []
    content {
      enablement_config = "INHERITED"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for file uploads
resource "google_storage_bucket" "upload_bucket" {
  name          = local.upload_bucket_name
  location      = var.upload_bucket_location
  storage_class = var.bucket_storage_class
  
  labels = local.common_labels
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Enable versioning for data protection
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  # Enable autoclass for cost optimization
  dynamic "autoclass" {
    for_each = var.enable_bucket_autoclass ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Lifecycle management for cost optimization
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
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Public access prevention
  public_access_prevention = "enforced"
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for processed results
resource "google_storage_bucket" "results_bucket" {
  name          = local.results_bucket_name
  location      = var.results_bucket_location
  storage_class = var.bucket_storage_class
  
  labels = local.common_labels
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Enable versioning for data protection
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  # Enable autoclass for cost optimization
  dynamic "autoclass" {
    for_each = var.enable_bucket_autoclass ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Lifecycle management for cost optimization
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
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Public access prevention
  public_access_prevention = "enforced"
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub topic for file processing events
resource "google_pubsub_topic" "processing_topic" {
  name = local.pubsub_topic_name
  
  labels = local.common_labels
  
  # Message retention for durability
  message_retention_duration = "86400s" # 24 hours
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for the processing service
resource "google_pubsub_subscription" "processing_subscription" {
  name  = local.pubsub_subscription_name
  topic = google_pubsub_topic.processing_topic.name
  
  labels = local.common_labels
  
  # Acknowledgment deadline
  ack_deadline_seconds = var.pubsub_ack_deadline_seconds
  
  # Message retention
  message_retention_duration = var.pubsub_message_retention_duration
  
  # Retry policy for failed messages
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
  
  # Dead letter queue for failed messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.processing_topic.id
    max_delivery_attempts = 5
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage notification to Pub/Sub
resource "google_storage_notification" "upload_notification" {
  bucket         = google_storage_bucket.upload_bucket.name
  topic          = google_pubsub_topic.processing_topic.id
  event_types    = ["OBJECT_FINALIZE"]
  payload_format = "JSON_API_V1"
  
  depends_on = [google_pubsub_topic_iam_binding.gcs_publisher]
}

# Create Cloud Tasks queue for reliable job scheduling
resource "google_cloud_tasks_queue" "processing_queue" {
  name     = local.task_queue_name
  location = var.region
  
  # Rate limiting configuration
  rate_limits {
    max_concurrent_dispatches = var.task_queue_max_concurrent_dispatches
    max_dispatches_per_second = var.task_queue_max_dispatches_per_second
  }
  
  # Retry configuration
  retry_config {
    max_attempts       = var.task_queue_max_attempts
    max_retry_duration = "300s"
    min_backoff        = var.task_queue_min_backoff
    max_backoff        = var.task_queue_max_backoff
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for upload service
resource "google_service_account" "upload_service_sa" {
  account_id   = local.upload_sa_name
  display_name = "Upload Service Account"
  description  = "Service account for the file upload service"
}

# Create service account for processing service
resource "google_service_account" "processing_service_sa" {
  account_id   = local.processing_sa_name
  display_name = "Processing Service Account"
  description  = "Service account for the file processing service"
}

# IAM bindings for upload service
resource "google_project_iam_member" "upload_service_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.upload_service_sa.email}"
}

resource "google_project_iam_member" "upload_service_tasks" {
  project = var.project_id
  role    = "roles/cloudtasks.enqueuer"
  member  = "serviceAccount:${google_service_account.upload_service_sa.email}"
}

# IAM bindings for processing service
resource "google_project_iam_member" "processing_service_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.processing_service_sa.email}"
}

resource "google_project_iam_member" "processing_service_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.processing_service_sa.email}"
}

# IAM binding for Cloud Storage to publish to Pub/Sub
resource "google_pubsub_topic_iam_binding" "gcs_publisher" {
  topic = google_pubsub_topic.processing_topic.name
  role  = "roles/pubsub.publisher"
  
  members = [
    "serviceAccount:service-${data.google_project.project.number}@gs-project-accounts.iam.gserviceaccount.com"
  ]
}

# Data source to get project information
data "google_project" "project" {
  project_id = var.project_id
}

# Create Cloud Run service for file upload
resource "google_cloud_run_v2_service" "upload_service" {
  name     = local.upload_service_name
  location = var.region
  
  labels = local.common_labels
  
  template {
    service_account = google_service_account.upload_service_sa.email
    
    # Scaling configuration
    scaling {
      min_instance_count = 0
      max_instance_count = var.upload_service_max_instances
    }
    
    containers {
      name  = "upload-service"
      image = var.upload_service_image
      
      # Resource limits
      resources {
        limits = {
          cpu    = var.upload_service_cpu
          memory = var.upload_service_memory
        }
        startup_cpu_boost = true
      }
      
      # Environment variables
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      
      env {
        name  = "REGION"
        value = var.region
      }
      
      env {
        name  = "UPLOAD_BUCKET"
        value = google_storage_bucket.upload_bucket.name
      }
      
      env {
        name  = "TASK_QUEUE"
        value = google_cloud_tasks_queue.processing_queue.name
      }
      
      env {
        name  = "PROCESSOR_URL"
        value = "${google_cloud_run_v2_service.processing_service.uri}/process"
      }
      
      # Health check
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
      
      ports {
        name           = "http1"
        container_port = 8080
      }
    }
    
    # Execution environment
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"
    
    # Maximum request timeout
    timeout = "300s"
    
    # Session affinity
    session_affinity = false
    
    # Maximum concurrent requests per instance
    max_instance_request_concurrency = var.upload_service_concurrency
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.upload_service_storage,
    google_project_iam_member.upload_service_tasks
  ]
}

# Create Cloud Run service for file processing
resource "google_cloud_run_v2_service" "processing_service" {
  name     = local.processing_service_name
  location = var.region
  
  labels = local.common_labels
  
  template {
    service_account = google_service_account.processing_service_sa.email
    
    # Scaling configuration
    scaling {
      min_instance_count = 0
      max_instance_count = var.processing_service_max_instances
    }
    
    containers {
      name  = "processing-service"
      image = var.processing_service_image
      
      # Resource limits
      resources {
        limits = {
          cpu    = var.processing_service_cpu
          memory = var.processing_service_memory
        }
        startup_cpu_boost = true
      }
      
      # Environment variables
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      
      env {
        name  = "RESULTS_BUCKET"
        value = google_storage_bucket.results_bucket.name
      }
      
      # Health check
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
      
      ports {
        name           = "http1"
        container_port = 8080
      }
    }
    
    # Execution environment
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"
    
    # Maximum request timeout
    timeout = "600s" # Longer timeout for processing tasks
    
    # Session affinity
    session_affinity = false
    
    # Maximum concurrent requests per instance
    max_instance_request_concurrency = var.processing_service_concurrency
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.processing_service_storage,
    google_project_iam_member.processing_service_pubsub
  ]
}

# IAM policy for upload service (allow unauthenticated access if configured)
resource "google_cloud_run_v2_service_iam_binding" "upload_service_public" {
  count = var.allow_unauthenticated_upload ? 1 : 0
  
  location = google_cloud_run_v2_service.upload_service.location
  name     = google_cloud_run_v2_service.upload_service.name
  role     = "roles/run.invoker"
  
  members = [
    "allUsers"
  ]
}

# IAM policy for processing service (internal access only)
resource "google_cloud_run_v2_service_iam_binding" "processing_service_internal" {
  location = google_cloud_run_v2_service.processing_service.location
  name     = google_cloud_run_v2_service.processing_service.name
  role     = "roles/run.invoker"
  
  members = [
    "serviceAccount:${google_service_account.upload_service_sa.email}",
    "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudtasks.iam.gserviceaccount.com"
  ]
}

# Create monitoring alert policy for failed tasks (optional)
resource "google_monitoring_alert_policy" "failed_tasks" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Failed File Processing Tasks"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud Tasks - Failed task rate"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_tasks_queue\" AND resource.labels.queue_id=\"${google_cloud_tasks_queue.processing_queue.name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 5
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = []
  
  depends_on = [google_project_service.required_apis]
}

# Create monitoring dashboard for the file processing system (optional)
resource "google_monitoring_dashboard" "file_processing_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "File Processing System Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Cloud Tasks Queue Depth"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_tasks_queue\" AND resource.labels.queue_id=\"${google_cloud_tasks_queue.processing_queue.name}\""
                      aggregation = {
                        alignmentPeriod  = "60s"
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
          width  = 6
          height = 4
          widget = {
            title = "Cloud Run Request Count"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_v2_service.upload_service.name}\""
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
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}