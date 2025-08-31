# Meeting Summary Generation Infrastructure
# This file creates the complete infrastructure for automated meeting processing
# using Speech-to-Text, Vertex AI Gemini, Cloud Storage, and Cloud Functions

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  # Resource naming with random suffix for uniqueness
  bucket_name         = "meeting-recordings-${random_id.suffix.hex}"
  function_name       = "process-meeting-${random_id.suffix.hex}"
  service_account_id  = "meeting-processor-${random_id.suffix.hex}"
  
  # Use provided bucket location or fall back to region
  bucket_location = coalesce(var.bucket_location, var.region)
  
  # Validate speaker count configuration
  speaker_count_max = max(var.speaker_count_max, var.speaker_count_min)
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    component = "meeting-summary-generation"
    version   = "1.1"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",    # Cloud Functions API
    "speech.googleapis.com",            # Speech-to-Text API
    "aiplatform.googleapis.com",        # Vertex AI API
    "storage.googleapis.com",           # Cloud Storage API
    "cloudbuild.googleapis.com",        # Cloud Build API for function deployment
    "run.googleapis.com",               # Cloud Run API (required for Gen2 functions)
    "eventarc.googleapis.com",          # Eventarc API for function triggers
    "pubsub.googleapis.com"             # Pub/Sub API for event handling
  ])

  project                    = var.project_id
  service                   = each.value
  disable_dependent_services = false
  disable_on_destroy        = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create service account for Cloud Function
resource "google_service_account" "function_sa" {
  project      = var.project_id
  account_id   = local.service_account_id
  display_name = "Meeting Processor Function Service Account"
  description  = "Service account for the meeting processing Cloud Function with minimal required permissions"

  depends_on = [google_project_service.required_apis]
}

# IAM binding for Speech-to-Text API access
resource "google_project_iam_member" "speech_user" {
  project = var.project_id
  role    = "roles/speech.editor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Vertex AI access
resource "google_project_iam_member" "vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Storage access
resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Logging
resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create Cloud Storage bucket for meeting recordings
resource "google_storage_bucket" "meeting_recordings" {
  name                        = local.bucket_name
  location                    = local.bucket_location
  storage_class              = var.bucket_storage_class
  force_destroy              = true
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access

  # Enable versioning if specified
  dynamic "versioning" {
    for_each = var.enable_versioning ? [1] : []
    content {
      enabled = true
    }
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.lifecycle_age_days
    }
    action {
      type = "Delete"
    }
  }

  # Additional lifecycle rule for multipart uploads cleanup
  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }

  # CORS configuration for web uploads (optional)
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create directories structure in the bucket using empty objects
resource "google_storage_bucket_object" "transcripts_folder" {
  name   = "transcripts/.keep"
  bucket = google_storage_bucket.meeting_recordings.name
  source = "/dev/null"
}

resource "google_storage_bucket_object" "summaries_folder" {
  name   = "summaries/.keep"
  bucket = google_storage_bucket.meeting_recordings.name
  source = "/dev/null"
}

# Create function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  source {
    content = templatefile("${path.module}/function-source/main.py", {
      speech_language_code = var.speech_language_code
      speaker_count_min    = var.speaker_count_min
      speaker_count_max    = local.speaker_count_max
      vertex_ai_location   = var.vertex_ai_location
      gemini_model         = var.gemini_model
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
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.meeting_recordings.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# Deploy Cloud Function (Generation 2)
resource "google_cloudfunctions2_function" "meeting_processor" {
  name     = local.function_name
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "python311"
    entry_point = "process_meeting"
    
    source {
      storage_source {
        bucket = google_storage_bucket.meeting_recordings.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count              = 0
    available_memory                = "${var.function_memory}Mi"
    timeout_seconds                 = var.function_timeout
    max_instance_request_concurrency = 1
    available_cpu                   = "1"
    
    environment_variables = {
      GCP_PROJECT         = var.project_id
      VERTEX_AI_LOCATION  = var.vertex_ai_location
      GEMINI_MODEL        = var.gemini_model
      SPEECH_LANGUAGE     = var.speech_language_code
      SPEAKER_COUNT_MIN   = tostring(var.speaker_count_min)
      SPEAKER_COUNT_MAX   = tostring(local.speaker_count_max)
    }

    service_account_email = google_service_account.function_sa.email
  }

  # Event trigger configuration for Cloud Storage
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.meeting_recordings.name
    }
    
    # Optional: Filter for specific file types
    event_filters {
      attribute = "name"
      value     = "*.wav"
      operator  = "match-path-pattern"
    }
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_project_iam_member.speech_user,
    google_project_iam_member.vertex_ai_user,
    google_project_iam_member.storage_admin,
    google_project_iam_member.logging_writer
  ]
}

# Additional event triggers for different audio formats
resource "google_cloudfunctions2_function" "meeting_processor_mp3" {
  name     = "${local.function_name}-mp3"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "python311"
    entry_point = "process_meeting"
    
    source {
      storage_source {
        bucket = google_storage_bucket.meeting_recordings.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count              = 0
    available_memory                = "${var.function_memory}Mi"
    timeout_seconds                 = var.function_timeout
    max_instance_request_concurrency = 1
    available_cpu                   = "1"
    
    environment_variables = {
      GCP_PROJECT         = var.project_id
      VERTEX_AI_LOCATION  = var.vertex_ai_location
      GEMINI_MODEL        = var.gemini_model
      SPEECH_LANGUAGE     = var.speech_language_code
      SPEAKER_COUNT_MIN   = tostring(var.speaker_count_min)
      SPEAKER_COUNT_MAX   = tostring(local.speaker_count_max)
    }

    service_account_email = google_service_account.function_sa.email
  }

  # Event trigger for MP3 files
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.meeting_recordings.name
    }
    
    event_filters {
      attribute = "name"
      value     = "*.mp3"
      operator  = "match-path-pattern"
    }
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_project_iam_member.speech_user,
    google_project_iam_member.vertex_ai_user,
    google_project_iam_member.storage_admin,
    google_project_iam_member.logging_writer
  ]
}

# Cloud Monitoring Alert Policy for function errors
resource "google_monitoring_alert_policy" "function_error_rate" {
  display_name = "High Error Rate - Meeting Processor Function"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Error rate > 10%"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields    = ["resource.label.function_name"]
      }
    }
  }

  notification_channels = []

  documentation {
    content = "The meeting processor function is experiencing a high error rate. Check the function logs for details."
  }

  depends_on = [
    google_cloudfunctions2_function.meeting_processor,
    google_project_service.required_apis
  ]
}

# Cloud Logging sink for function logs (optional, for centralized logging)
resource "google_logging_project_sink" "function_logs" {
  name                   = "meeting-processor-logs-${random_id.suffix.hex}"
  destination           = "storage.googleapis.com/${google_storage_bucket.meeting_recordings.name}"
  filter                = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
  unique_writer_identity = true

  depends_on = [google_cloudfunctions2_function.meeting_processor]
}

# IAM binding for logging sink to write to bucket
resource "google_storage_bucket_iam_member" "logs_writer" {
  bucket = google_storage_bucket.meeting_recordings.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs.writer_identity
}