# Main Terraform configuration for multi-speaker transcription with Chirp and Cloud Functions
# This file creates all the infrastructure needed for the speech transcription solution

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed names and configurations
locals {
  name_suffix        = random_id.suffix.hex
  input_bucket_name  = var.input_bucket_name != "" ? var.input_bucket_name : "${var.resource_name_prefix}-audio-input-${local.name_suffix}"
  output_bucket_name = var.output_bucket_name != "" ? var.output_bucket_name : "${var.resource_name_prefix}-transcripts-output-${local.name_suffix}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "terraform"
  })

  # Required APIs for the solution
  required_apis = [
    "speech.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "pubsub.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  count   = var.enable_apis ? length(local.required_apis) : 0
  project = var.project_id
  service = local.required_apis[count.index]

  # Don't disable API when resource is destroyed
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Cloud Storage bucket for input audio files
resource "google_storage_bucket" "input_bucket" {
  name                        = local.input_bucket_name
  location                    = var.region
  storage_class              = var.bucket_storage_class
  uniform_bucket_level_access = true
  force_destroy              = true

  labels = local.common_labels

  # Enable versioning if specified
  dynamic "versioning" {
    for_each = var.enable_bucket_versioning ? [1] : []
    content {
      enabled = true
    }
  }

  # Default encryption
  dynamic "encryption" {
    for_each = var.enable_bucket_encryption ? [1] : []
    content {
      default_kms_key_name = null
    }
  }

  # Lifecycle management
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_age_days > 0 ? [1] : []
    content {
      condition {
        age = var.bucket_lifecycle_age_days
      }
      action {
        type = "Delete"
      }
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for output transcripts
resource "google_storage_bucket" "output_bucket" {
  name                        = local.output_bucket_name
  location                    = var.region
  storage_class              = var.bucket_storage_class
  uniform_bucket_level_access = true
  force_destroy              = true

  labels = local.common_labels

  # Enable versioning if specified
  dynamic "versioning" {
    for_each = var.enable_bucket_versioning ? [1] : []
    content {
      enabled = true
    }
  }

  # Default encryption
  dynamic "encryption" {
    for_each = var.enable_bucket_encryption ? [1] : []
    content {
      default_kms_key_name = null
    }
  }

  # Lifecycle management for transcripts
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_age_days > 0 ? [1] : []
    content {
      condition {
        age = var.bucket_lifecycle_age_days
      }
      action {
        type = "Delete"
      }
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Create service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.resource_name_prefix}-func-sa-${local.name_suffix}"
  display_name = "Service Account for Speech Transcription Function"
  description  = "Service account used by the Cloud Function for speech transcription processing"
}

# Grant necessary permissions to the service account
resource "google_project_iam_member" "function_speech_access" {
  project = var.project_id
  role    = "roles/speech.editor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_storage_access" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_logging_access" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/transcription-function-${local.name_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/function-source/main.py", {
      speech_model                = var.speech_model
      enable_speaker_diarization = var.speaker_diarization_config.enable_speaker_diarization
      min_speaker_count          = var.speaker_diarization_config.min_speaker_count
      max_speaker_count          = var.speaker_diarization_config.max_speaker_count
      language_codes             = jsonencode(var.language_codes)
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function-source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to bucket
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.name_suffix}.zip"
  bucket = google_storage_bucket.output_bucket.name
  source = data.archive_file.function_source.output_path
}

# Create Pub/Sub topic for notifications (optional)
resource "google_pubsub_topic" "notifications" {
  count = var.notification_topic_name != "" ? 1 : 0
  name  = var.notification_topic_name

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create Cloud Function for processing audio transcription
resource "google_cloudfunctions2_function" "transcription_processor" {
  name        = var.function_name
  location    = var.region
  description = "Processes audio files for multi-speaker transcription using Chirp 3 model"

  build_config {
    runtime     = "python312"
    entry_point = "process_audio_upload"
    
    source {
      storage_source {
        bucket = google_storage_bucket.output_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = 0
    available_memory      = "${var.function_memory}Mi"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.function_sa.email

    environment_variables = {
      OUTPUT_BUCKET          = google_storage_bucket.output_bucket.name
      SPEECH_MODEL          = var.speech_model
      ENABLE_DIARIZATION    = var.speaker_diarization_config.enable_speaker_diarization
      MIN_SPEAKER_COUNT     = var.speaker_diarization_config.min_speaker_count
      MAX_SPEAKER_COUNT     = var.speaker_diarization_config.max_speaker_count
      LANGUAGE_CODES        = jsonencode(var.language_codes)
      NOTIFICATION_TOPIC    = var.notification_topic_name != "" ? google_pubsub_topic.notifications[0].id : ""
    }

    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.input_bucket.name
    }
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_speech_access,
    google_project_iam_member.function_storage_access,
    google_project_iam_member.function_logging_access
  ]
}

# Create IAM binding for function invoker (for Eventarc)
resource "google_cloud_run_service_iam_member" "function_invoker" {
  location = google_cloudfunctions2_function.transcription_processor.location
  service  = google_cloudfunctions2_function.transcription_processor.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.project_id}-compute@developer.gserviceaccount.com"
}

# Create sample audio directory in input bucket (optional)
resource "google_storage_bucket_object" "sample_directory" {
  name    = "samples/.keep"
  content = "Sample audio files directory"
  bucket  = google_storage_bucket.input_bucket.name
}

# Create transcripts directory in output bucket
resource "google_storage_bucket_object" "transcripts_directory" {
  name    = "transcripts/.keep"
  content = "Transcription results directory"
  bucket  = google_storage_bucket.output_bucket.name
}