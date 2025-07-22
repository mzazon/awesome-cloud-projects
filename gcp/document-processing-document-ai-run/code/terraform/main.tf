# Document Processing Infrastructure with Document AI and Cloud Run
# This configuration creates a complete document processing pipeline using
# Google Cloud Document AI, Cloud Run, Pub/Sub, and Cloud Storage

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Compute derived values and resource names
  resource_suffix = random_id.suffix.hex
  bucket_name     = "${var.resource_prefix}-uploads-${local.resource_suffix}"
  topic_name      = "${var.resource_prefix}-processing"
  subscription_name = "${var.resource_prefix}-worker"
  service_name    = "${var.resource_prefix}-processor"
  processor_name  = "${var.resource_prefix}-form-parser-${local.resource_suffix}"
  service_account_name = "${var.resource_prefix}-processor-sa"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    resource-group = "document-processing"
    terraform      = "true"
  })
}

# Data source to get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "documentai.googleapis.com",
    "run.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling services on destroy to avoid disrupting other resources
  disable_on_destroy = false
}

# Document AI Processor for form parsing and document extraction
resource "google_document_ai_processor" "form_processor" {
  location     = var.region
  display_name = local.processor_name
  type         = var.document_ai_processor_type
  
  depends_on = [google_project_service.apis]
  
  labels = local.common_labels
}

# Cloud Storage bucket for document uploads and processing results
resource "google_storage_bucket" "document_uploads" {
  name                        = local.bucket_name
  location                    = var.bucket_location
  force_destroy              = true
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Enable versioning for data protection
  versioning {
    enabled = var.enable_storage_versioning
  }
  
  # Lifecycle rule to manage old versions and temporary files
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Lifecycle rule for processed files
  lifecycle_rule {
    condition {
      matches_prefix = ["processed/"]
      age           = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Create subdirectories in the bucket for organization
resource "google_storage_bucket_object" "processed_folder" {
  name    = "processed/"
  bucket  = google_storage_bucket.document_uploads.name
  content = " "
}

# Pub/Sub topic for document processing events
resource "google_pubsub_topic" "document_processing" {
  name = local.topic_name
  
  # Enable message ordering for better processing control
  enable_message_ordering = false
  
  # Message retention policy
  message_retention_duration = var.pubsub_message_retention_duration
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Pub/Sub subscription for Cloud Run service
resource "google_pubsub_subscription" "document_worker" {
  name  = local.subscription_name
  topic = google_pubsub_topic.document_processing.name
  
  # Configure acknowledgment deadline for processing time
  ack_deadline_seconds = var.pubsub_ack_deadline
  
  # Message retention configuration
  message_retention_duration = var.pubsub_message_retention_duration
  retain_acked_messages      = false
  
  # Configure push delivery to Cloud Run service
  push_config {
    push_endpoint = google_cloud_run_v2_service.document_processor.uri
    
    # Authentication configuration for push endpoint
    oidc_token {
      service_account_email = google_service_account.cloud_run_sa.email
    }
  }
  
  # Retry policy for failed message delivery
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Dead letter policy for problematic messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  
  labels = local.common_labels
  
  depends_on = [google_cloud_run_v2_service.document_processor]
}

# Dead letter topic for failed message processing
resource "google_pubsub_topic" "dead_letter" {
  name = "${local.topic_name}-dead-letter"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Service account for Cloud Run service with least privilege permissions
resource "google_service_account" "cloud_run_sa" {
  account_id   = local.service_account_name
  display_name = "Document Processor Service Account"
  description  = "Service account for document processing Cloud Run service"
}

# IAM binding for Document AI API access
resource "google_project_iam_member" "documentai_user" {
  project = var.project_id
  role    = "roles/documentai.apiUser"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# IAM binding for Cloud Storage access
resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# IAM binding for Cloud Logging
resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# IAM binding for Cloud Monitoring
resource "google_project_iam_member" "monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Create the application source code as a zip file
data "archive_file" "source_code" {
  type        = "zip"
  output_path = "${path.module}/source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id   = var.project_id
      region      = var.region
      processor_id = google_document_ai_processor.form_processor.id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
  
  source {
    content  = file("${path.module}/function_code/Dockerfile")
    filename = "Dockerfile"
  }
}

# Upload source code to Cloud Storage for Cloud Build
resource "google_storage_bucket_object" "source_code" {
  name   = "source/source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.document_uploads.name
  source = data.archive_file.source_code.output_path
  
  # Ensure the source code is updated when changed
  depends_on = [data.archive_file.source_code]
}

# Cloud Run v2 service for document processing
resource "google_cloud_run_v2_service" "document_processor" {
  name     = local.service_name
  location = var.region
  
  # Prevent accidental deletion in production
  deletion_protection = false
  
  # Configure ingress and launch stage
  ingress      = var.cloud_run_ingress
  launch_stage = "GA"
  
  template {
    # Configure service account
    service_account = google_service_account.cloud_run_sa.email
    
    # Configure scaling
    scaling {
      max_instance_count = var.cloud_run_max_instances
      min_instance_count = 0
    }
    
    # Set request timeout
    timeout = "${var.cloud_run_timeout}s"
    
    # Configure the container
    containers {
      # Use a placeholder image initially - will be updated by Cloud Build
      image = "gcr.io/cloudrun/hello"
      
      # Resource allocation
      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
        cpu_idle = true
      }
      
      # Environment variables for the application
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      
      env {
        name  = "REGION"
        value = var.region
      }
      
      env {
        name  = "PROCESSOR_ID"
        value = google_document_ai_processor.form_processor.id
      }
      
      env {
        name  = "BUCKET_NAME"
        value = google_storage_bucket.document_uploads.name
      }
      
      # Configure health checks
      startup_probe {
        http_get {
          path = "/"
          port = 8080
        }
        initial_delay_seconds = 10
        timeout_seconds       = 1
        period_seconds        = 3
        failure_threshold     = 3
      }
      
      liveness_probe {
        http_get {
          path = "/"
          port = 8080
        }
        timeout_seconds   = 1
        period_seconds    = 10
        failure_threshold = 3
      }
    }
    
    # Configure annotations for specific Cloud Run features
    annotations = {
      "autoscaling.knative.dev/maxScale" = tostring(var.cloud_run_max_instances)
      "run.googleapis.com/execution-environment" = "gen2"
    }
    
    # Apply labels to the revision template
    labels = local.common_labels
  }
  
  # Configure traffic allocation
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_service_account.cloud_run_sa,
    google_project_iam_member.documentai_user,
    google_project_iam_member.storage_admin,
    google_project_iam_member.logging_writer
  ]
}

# Cloud Storage notification configuration to trigger Pub/Sub
resource "google_storage_notification" "document_notification" {
  bucket         = google_storage_bucket.document_uploads.name
  payload_format = "JSON_API_V1"
  topic          = google_pubsub_topic.document_processing.id
  event_types    = ["OBJECT_FINALIZE"]
  
  # Only trigger for specific file types and exclude processed files
  custom_attributes = {
    "description" = "Document upload notification"
  }
  
  depends_on = [google_pubsub_topic_iam_member.storage_publisher]
}

# IAM permission for Cloud Storage to publish to Pub/Sub
resource "google_pubsub_topic_iam_member" "storage_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.document_processing.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
}

# Allow Cloud Run service to be invoked by Pub/Sub
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  project  = var.project_id
  location = google_cloud_run_v2_service.document_processor.location
  name     = google_cloud_run_v2_service.document_processor.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Cloud Build trigger for automatic deployments (optional)
resource "google_cloudbuild_trigger" "document_processor_build" {
  count    = 0  # Set to 1 to enable automatic builds
  name     = "${local.service_name}-build"
  location = var.region
  
  # Manual trigger configuration
  trigger_template {
    branch_name = "main"
    repo_name   = "document-processor-repo"  # Replace with actual repo
  }
  
  build {
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t",
        "gcr.io/${var.project_id}/${local.service_name}:$BUILD_ID",
        "."
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "gcr.io/${var.project_id}/${local.service_name}:$BUILD_ID"
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/gcloud"
      args = [
        "run",
        "deploy",
        local.service_name,
        "--image=gcr.io/${var.project_id}/${local.service_name}:$BUILD_ID",
        "--region=${var.region}",
        "--platform=managed",
        "--allow-unauthenticated"
      ]
    }
  }
  
  tags = ["document-processor", "cloud-run"]
}

# Monitoring alert policy for failed document processing
resource "google_monitoring_alert_policy" "document_processing_errors" {
  display_name = "Document Processing Errors"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud Run Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${local.service_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.1  # 10% error rate
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = []  # Add notification channels as needed
  
  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
  }
  
  depends_on = [google_project_service.apis]
}

# Log-based metric for document processing success rate
resource "google_logging_metric" "document_processing_success" {
  name   = "document_processing_success_rate"
  filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${local.service_name}\" AND textPayload=\"Successfully processed\""
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Document Processing Success Rate"
  }
  
  depends_on = [google_project_service.apis]
}