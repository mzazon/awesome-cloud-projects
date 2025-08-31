# Main Terraform configuration for GCP smart document summarization with Vertex AI and Cloud Functions
# This creates a serverless document processing pipeline with AI-powered summarization

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com"
  ])

  project = var.project_id
  service = each.key

  # Prevent automatic disabling when resource is destroyed
  disable_dependent_services = false
  disable_on_destroy         = false

  timeouts {
    create = "30m"
    update = "40m"
  }
}

# Create Cloud Storage bucket for document processing
resource "google_storage_bucket" "document_bucket" {
  name     = "${var.bucket_name}-${random_id.suffix.hex}"
  location = var.region
  
  # Storage configuration
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  
  # Enable versioning for document protection
  versioning {
    enabled = var.enable_versioning
  }

  # Lifecycle rules to manage costs
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

  # CORS configuration for web uploads
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  # Apply labels
  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Create a ready file to establish bucket structure
resource "google_storage_bucket_object" "ready_file" {
  name   = "ready.txt"
  bucket = google_storage_bucket.document_bucket.name
  content = "Document processing pipeline ready - ${timestamp()}"
}

# Create Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function-source/main.py", {
      project_id = var.project_id
      region     = var.vertex_ai_location
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function-source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.document_bucket.name
  source = data.archive_file.function_source.output_path
}

# Service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.function_name}-sa"
  display_name = "Service Account for ${var.function_name} Cloud Function"
  description  = "Service account used by the document summarization Cloud Function"
}

# IAM roles for the Cloud Function service account
resource "google_project_iam_member" "function_vertex_ai" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Cloud Function (2nd generation) for document processing
resource "google_cloudfunctions2_function" "document_processor" {
  name     = var.function_name
  location = var.region

  build_config {
    runtime     = var.python_runtime
    entry_point = "summarize_document"
    
    source {
      storage_source {
        bucket = google_storage_bucket.document_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count = var.max_instances
    min_instance_count = 0
    
    available_memory   = "${var.function_memory}Mi"
    timeout_seconds    = var.function_timeout
    
    environment_variables = {
      GCP_PROJECT = var.project_id
      REGION      = var.vertex_ai_location
    }
    
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.function_sa.email
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.document_bucket.name
    }
  }

  labels = var.labels

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_vertex_ai,
    google_project_iam_member.function_storage,
    google_project_iam_member.function_logs,
    google_project_iam_member.function_monitoring
  ]
}

# Eventarc trigger for Cloud Storage events (automatically created with event_trigger)
# The function's event_trigger configuration handles this automatically

# Cloud Monitoring alert policy for function errors
resource "google_monitoring_alert_policy" "function_errors" {
  display_name = "${var.function_name} Error Rate Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud Function Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${var.function_name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.1  # Alert if error rate > 10%
      
      duration = "300s"  # 5 minutes
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = []
  
  alert_strategy {
    auto_close = "1800s"  # 30 minutes
  }

  depends_on = [google_cloudfunctions2_function.document_processor]
}

# Cloud Logging sink for function logs (optional)
resource "google_logging_project_sink" "function_logs" {
  name        = "${var.function_name}-logs"
  destination = "storage.googleapis.com/${google_storage_bucket.document_bucket.name}"
  
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${var.function_name}\""
  
  unique_writer_identity = true
}

# Grant the logging sink permission to write to the bucket
resource "google_storage_bucket_iam_member" "logs_writer" {
  bucket = google_storage_bucket.document_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs.writer_identity
}