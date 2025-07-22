# =============================================================================
# MEDICAL IMAGING ANALYSIS INFRASTRUCTURE
# Terraform configuration for Google Cloud Healthcare API and Vision AI
# =============================================================================

# =============================================================================
# RANDOM SUFFIX FOR UNIQUE RESOURCE NAMES
# =============================================================================

resource "random_id" "suffix" {
  byte_length = 3
}

# =============================================================================
# GOOGLE CLOUD APIS
# =============================================================================

resource "google_project_service" "required_apis" {
  for_each = toset(var.required_apis)
  
  project = var.project_id
  service = each.value

  # Disable dependent services when this resource is destroyed
  disable_dependent_services = true
  # Disable the service when the resource is destroyed
  disable_on_destroy = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# =============================================================================
# SERVICE ACCOUNT FOR MEDICAL IMAGING PROCESSING
# =============================================================================

resource "google_service_account" "medical_imaging_sa" {
  account_id   = "${var.service_account_name}-${random_id.suffix.hex}"
  display_name = var.service_account_display_name
  description  = "Service account for automated medical imaging analysis with Healthcare API and Vision AI"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Healthcare API permissions
resource "google_project_iam_member" "healthcare_admin" {
  project = var.project_id
  role    = "roles/healthcare.datasetAdmin"
  member  = "serviceAccount:${google_service_account.medical_imaging_sa.email}"

  depends_on = [google_service_account.medical_imaging_sa]
}

# Vision AI permissions
resource "google_project_iam_member" "ml_developer" {
  project = var.project_id
  role    = "roles/ml.developer"
  member  = "serviceAccount:${google_service_account.medical_imaging_sa.email}"

  depends_on = [google_service_account.medical_imaging_sa]
}

# Cloud Storage permissions
resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.medical_imaging_sa.email}"

  depends_on = [google_service_account.medical_imaging_sa]
}

# Cloud Functions permissions
resource "google_project_iam_member" "functions_developer" {
  project = var.project_id
  role    = "roles/cloudfunctions.developer"
  member  = "serviceAccount:${google_service_account.medical_imaging_sa.email}"

  depends_on = [google_service_account.medical_imaging_sa]
}

# Pub/Sub permissions
resource "google_project_iam_member" "pubsub_editor" {
  project = var.project_id
  role    = "roles/pubsub.editor"
  member  = "serviceAccount:${google_service_account.medical_imaging_sa.email}"

  depends_on = [google_service_account.medical_imaging_sa]
}

# Logging permissions
resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.medical_imaging_sa.email}"

  depends_on = [google_service_account.medical_imaging_sa]
}

# =============================================================================
# CLOUD STORAGE BUCKET FOR MEDICAL IMAGES
# =============================================================================

resource "google_storage_bucket" "medical_imaging_bucket" {
  name          = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  location      = var.bucket_location
  storage_class = var.bucket_storage_class
  project       = var.project_id

  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access

  # Enable versioning for data protection
  versioning {
    enabled = var.enable_bucket_versioning
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  # Lifecycle rule for test data cleanup
  lifecycle_rule {
    condition {
      matches_prefix = ["test/", "sample/"]
      age           = 7
    }
    action {
      type = "Delete"
    }
  }

  # CORS configuration for web access if needed
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  # Labels for resource management
  labels = merge(var.common_labels, {
    purpose = "medical-image-storage"
    type    = "healthcare-data"
  })

  depends_on = [google_project_service.required_apis]
}

# Create organized folder structure in the bucket
resource "google_storage_bucket_object" "incoming_folder" {
  name    = "incoming/.keep"
  content = "# This folder stores incoming DICOM images for processing"
  bucket  = google_storage_bucket.medical_imaging_bucket.name
}

resource "google_storage_bucket_object" "processed_folder" {
  name    = "processed/.keep"
  content = "# This folder stores successfully processed images"
  bucket  = google_storage_bucket.medical_imaging_bucket.name
}

resource "google_storage_bucket_object" "failed_folder" {
  name    = "failed/.keep"
  content = "# This folder stores images that failed processing"
  bucket  = google_storage_bucket.medical_imaging_bucket.name
}

# =============================================================================
# HEALTHCARE DATASET AND STORES
# =============================================================================

# Healthcare dataset - container for all medical data
resource "google_healthcare_dataset" "medical_imaging_dataset" {
  name     = var.dataset_id
  location = var.region
  project  = var.project_id

  labels = merge(var.common_labels, {
    purpose    = "medical-imaging-analysis"
    data-type  = "healthcare"
    compliance = "hipaa"
  })

  depends_on = [google_project_service.required_apis]
}

# DICOM store for medical imaging data
resource "google_healthcare_dicom_store" "medical_dicom_store" {
  name    = var.dicom_store_id
  dataset = google_healthcare_dataset.medical_imaging_dataset.id

  # Configure Pub/Sub notifications for new DICOM instances
  notification_config {
    pubsub_topic = google_pubsub_topic.medical_image_processing.id
  }

  labels = merge(var.common_labels, {
    purpose   = "dicom-storage"
    data-type = "medical-images"
  })

  depends_on = [
    google_healthcare_dataset.medical_imaging_dataset,
    google_pubsub_topic.medical_image_processing
  ]
}

# FHIR store for analysis results and metadata
resource "google_healthcare_fhir_store" "medical_fhir_store" {
  name    = var.fhir_store_id
  dataset = google_healthcare_dataset.medical_imaging_dataset.id
  version = var.fhir_version

  # Enable search for efficient querying
  enable_update_create = true
  
  # Configure notifications for FHIR resources
  notification_configs {
    pubsub_topic   = google_pubsub_topic.medical_image_processing.id
    send_full_resource = false
    send_previous_resource_on_delete = false
  }

  labels = merge(var.common_labels, {
    purpose   = "fhir-storage"
    data-type = "medical-results"
  })

  depends_on = [
    google_healthcare_dataset.medical_imaging_dataset,
    google_pubsub_topic.medical_image_processing
  ]
}

# =============================================================================
# PUB/SUB FOR EVENT-DRIVEN PROCESSING
# =============================================================================

# Pub/Sub topic for medical image processing events
resource "google_pubsub_topic" "medical_image_processing" {
  name    = var.pubsub_topic_name
  project = var.project_id

  # Message retention for debugging and replay
  message_retention_duration = "86400s" # 24 hours

  labels = merge(var.common_labels, {
    purpose = "medical-image-events"
    type    = "event-processing"
  })

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for Cloud Functions
resource "google_pubsub_subscription" "medical_image_processor_sub" {
  name    = var.pubsub_subscription_name
  topic   = google_pubsub_topic.medical_image_processing.name
  project = var.project_id

  # Acknowledgment deadline
  ack_deadline_seconds = var.subscription_ack_deadline

  # Retry policy for failed messages
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # Dead letter queue configuration
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.medical_image_processing_dlq.id
    max_delivery_attempts = 5
  }

  # Message ordering for consistency
  enable_message_ordering = false

  labels = merge(var.common_labels, {
    purpose = "medical-image-subscription"
    type    = "event-processing"
  })

  depends_on = [google_pubsub_topic.medical_image_processing]
}

# Dead letter queue for failed processing
resource "google_pubsub_topic" "medical_image_processing_dlq" {
  name    = "${var.pubsub_topic_name}-dlq"
  project = var.project_id

  labels = merge(var.common_labels, {
    purpose = "medical-image-dlq"
    type    = "error-handling"
  })

  depends_on = [google_project_service.required_apis]
}

# =============================================================================
# CLOUD FUNCTION FOR IMAGE ANALYSIS
# =============================================================================

# Create source code archive for Cloud Function
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/medical-image-function.zip"
  
  source {
    content = file("${path.module}/function_source/main.py")
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "functions/medical-image-processor-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.medical_imaging_bucket.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# Cloud Function for processing medical images
resource "google_cloudfunctions2_function" "medical_image_processor" {
  name        = "${var.function_name}-${random_id.suffix.hex}"
  location    = var.region
  description = "Processes medical images using Healthcare API and Vision AI"
  project     = var.project_id

  build_config {
    runtime     = var.function_runtime
    entry_point = "process_medical_image"
    
    source {
      storage_source {
        bucket = google_storage_bucket.medical_imaging_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count = 10
    min_instance_count = 0
    available_memory   = "${var.function_memory}Mi"
    timeout_seconds    = var.function_timeout
    
    # Configure environment variables
    environment_variables = {
      PROJECT_ID      = var.project_id
      DATASET_ID      = var.dataset_id
      DICOM_STORE_ID  = var.dicom_store_id
      FHIR_STORE_ID   = var.fhir_store_id
      REGION          = var.region
      BUCKET_NAME     = google_storage_bucket.medical_imaging_bucket.name
    }

    # Use the medical imaging service account
    service_account_email = google_service_account.medical_imaging_sa.email

    # Configure ingress and egress
    ingress_settings = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
  }

  # Configure Pub/Sub trigger
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.medical_image_processing.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  labels = merge(var.common_labels, {
    purpose = "medical-image-processing"
    type    = "serverless-function"
  })

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_service_account.medical_imaging_sa,
    google_pubsub_topic.medical_image_processing
  ]
}

# =============================================================================
# MONITORING AND ALERTING
# =============================================================================

# Log-based metric for successful medical image processing
resource "google_logging_metric" "medical_image_processing_success" {
  count = var.enable_monitoring ? 1 : 0
  
  name    = "medical_image_processing_success"
  project = var.project_id
  
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${google_cloudfunctions2_function.medical_image_processor.name}"
    textPayload:"Successfully processed image"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    display_name = "Medical Image Processing Success Count"
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.medical_image_processor
  ]
}

# Log-based metric for failed medical image processing
resource "google_logging_metric" "medical_image_processing_failure" {
  count = var.enable_monitoring ? 1 : 0
  
  name    = "medical_image_processing_failure"
  project = var.project_id
  
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${google_cloudfunctions2_function.medical_image_processor.name}"
    severity>=ERROR
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    display_name = "Medical Image Processing Failure Count"
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.medical_image_processor
  ]
}

# Notification channel for alerts (if email provided)
resource "google_monitoring_notification_channel" "email_alert" {
  count = var.enable_monitoring && var.alert_email != "" ? 1 : 0
  
  display_name = "Medical Imaging Alert Email"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = var.alert_email
  }

  depends_on = [google_project_service.required_apis]
}

# Alert policy for function execution failures
resource "google_monitoring_alert_policy" "function_failure_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Medical Image Processing Failures"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Function execution failures"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" resource.label.function_name=\"${google_cloudfunctions2_function.medical_image_processor.name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  # Add notification channels if email is provided
  dynamic "notification_channels" {
    for_each = var.alert_email != "" ? [1] : []
    content {
      notification_channels = [google_monitoring_notification_channel.email_alert[0].id]
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.medical_image_processor
  ]
}

# =============================================================================
# SECURITY CONFIGURATIONS
# =============================================================================

# IAM policy for Healthcare dataset access
resource "google_healthcare_dataset_iam_member" "dataset_viewer" {
  dataset_id = google_healthcare_dataset.medical_imaging_dataset.id
  role       = "roles/healthcare.datasetViewer"
  member     = "serviceAccount:${google_service_account.medical_imaging_sa.email}"

  depends_on = [
    google_healthcare_dataset.medical_imaging_dataset,
    google_service_account.medical_imaging_sa
  ]
}

# IAM policy for DICOM store access
resource "google_healthcare_dicom_store_iam_member" "dicom_editor" {
  dicom_store_id = google_healthcare_dicom_store.medical_dicom_store.id
  role           = "roles/healthcare.dicomEditor"
  member         = "serviceAccount:${google_service_account.medical_imaging_sa.email}"

  depends_on = [
    google_healthcare_dicom_store.medical_dicom_store,
    google_service_account.medical_imaging_sa
  ]
}

# IAM policy for FHIR store access
resource "google_healthcare_fhir_store_iam_member" "fhir_editor" {
  fhir_store_id = google_healthcare_fhir_store.medical_fhir_store.id
  role          = "roles/healthcare.fhirResourceEditor"
  member        = "serviceAccount:${google_service_account.medical_imaging_sa.email}"

  depends_on = [
    google_healthcare_fhir_store.medical_fhir_store,
    google_service_account.medical_imaging_sa
  ]
}

# =============================================================================
# SAMPLE DATA PREPARATION
# =============================================================================

# Sample DICOM metadata for testing
resource "google_storage_bucket_object" "sample_study_metadata" {
  name   = "incoming/sample_study.json"
  bucket = google_storage_bucket.medical_imaging_bucket.name
  
  content = jsonencode({
    PatientID          = "TEST001"
    StudyDate          = "20250112"
    Modality           = "CT"
    StudyDescription   = "Chest CT for routine screening"
    SeriesDescription  = "Axial chest images"
    InstitutionName    = "Test Medical Center"
    ManufacturerModel  = "Test CT Scanner"
  })

  content_type = "application/json"

  depends_on = [google_storage_bucket.medical_imaging_bucket]
}