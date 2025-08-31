# Generate random suffix for resource names to ensure uniqueness
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent naming and configuration
locals {
  # Naming convention: {prefix}-{component}-{environment}-{random_suffix}
  resource_suffix    = random_id.suffix.hex
  bucket_name        = "${var.resource_prefix}-docs-${var.environment}-${local.resource_suffix}"
  function_name      = "${var.resource_prefix}-analyzer-${var.environment}-${local.resource_suffix}"
  processor_name     = "${var.resource_prefix}-processor-${var.environment}-${local.resource_suffix}"
  service_account    = "${var.resource_prefix}-sa-${var.environment}-${local.resource_suffix}"
  
  # Merge default labels with user-provided labels
  common_labels = merge(var.labels, {
    environment     = var.environment
    resource-suffix = local.resource_suffix
    component      = "accessibility-compliance"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of APIs
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = local.service_account
  display_name = "Accessibility Compliance Analyzer Service Account"
  description  = "Service account for Cloud Function that processes documents for accessibility compliance"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM bindings for service account
resource "google_project_iam_member" "function_sa_roles" {
  for_each = toset([
    "roles/storage.objectAdmin",           # Full access to Cloud Storage objects
    "roles/documentai.apiUser",            # Use Document AI processors
    "roles/aiplatform.user",               # Use Vertex AI services
    "roles/logging.logWriter",             # Write to Cloud Logging
    "roles/monitoring.metricWriter",       # Write metrics to Cloud Monitoring
    "roles/eventarc.eventReceiver"         # Receive Eventarc events
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
  
  depends_on = [google_service_account.function_sa]
}

# Cloud Storage bucket for document processing
resource "google_storage_bucket" "document_bucket" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id
  
  # Storage configuration
  storage_class               = var.storage_class
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Security configuration
  public_access_prevention = var.enable_public_access_prevention ? "enforced" : "inherited"
  
  # Versioning configuration
  versioning {
    enabled = var.bucket_versioning_enabled
  }
  
  # Lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_enabled ? [1] : []
    content {
      condition {
        age = 90
      }
      action {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
    }
  }
  
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_enabled ? [1] : []
    content {
      condition {
        age = 365
      }
      action {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
    }
  }
  
  # Delete old versions after 30 days
  dynamic "lifecycle_rule" {
    for_each = var.bucket_versioning_enabled ? [1] : []
    content {
      condition {
        age                   = 30
        with_state           = "ARCHIVED"
        num_newer_versions   = 3
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # Apply labels
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create folder structure in bucket using objects
resource "google_storage_bucket_object" "folder_structure" {
  for_each = toset(["uploads/", "reports/", "processed/"])
  
  name   = "${each.value}.placeholder"
  bucket = google_storage_bucket.document_bucket.name
  content = "This file creates the folder structure for accessibility compliance processing"
  
  depends_on = [google_storage_bucket.document_bucket]
}

# Document AI processor for OCR and layout analysis
resource "google_document_ai_processor" "accessibility_processor" {
  location     = var.document_ai_location
  display_name = local.processor_name
  type         = var.document_ai_processor_type
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id   = var.project_id
      region       = var.region
      processor_id = google_document_ai_processor.accessibility_processor.name
      gemini_model = var.gemini_model
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.document_bucket.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [
    google_storage_bucket.document_bucket,
    data.archive_file.function_source
  ]
}

# Cloud Function for accessibility compliance processing
resource "google_cloudfunctions2_function" "accessibility_analyzer" {
  name     = local.function_name
  location = var.region
  project  = var.project_id
  
  build_config {
    runtime     = "python311"
    entry_point = "process_accessibility_compliance"
    
    source {
      storage_source {
        bucket = google_storage_bucket.document_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count               = var.function_min_instances
    available_memory                 = var.function_memory
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    environment_variables = {
      PROJECT_ID    = var.project_id
      REGION        = var.region
      PROCESSOR_ID  = google_document_ai_processor.accessibility_processor.name
      GEMINI_MODEL  = var.gemini_model
      BUCKET_NAME   = google_storage_bucket.document_bucket.name
    }
    
    service_account_email = google_service_account.function_sa.email
    
    # Enable all traffic for the function
    ingress_settings = "ALLOW_ALL"
  }
  
  # Event trigger configuration for Cloud Storage
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.document_bucket.name
    }
    
    event_filters {
      attribute = "eventType"
      value     = "google.cloud.storage.object.v1.finalized"
    }
    
    service_account_email = google_service_account.function_sa.email
  }
  
  # Apply labels
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.function_sa,
    google_project_iam_member.function_sa_roles,
    google_storage_bucket_object.function_source,
    google_document_ai_processor.accessibility_processor
  ]
}

# Cloud Function IAM binding for Eventarc
resource "google_cloud_run_service_iam_member" "function_eventarc_invoker" {
  project  = var.project_id
  location = var.region
  service  = google_cloudfunctions2_function.accessibility_analyzer.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.function_sa.email}"
  
  depends_on = [google_cloudfunctions2_function.accessibility_analyzer]
}

# Enable Vertex AI API for the project location
resource "google_vertex_ai_endpoint" "gemini_endpoint" {
  count = 0 # Gemini models use managed endpoints, so we don't need to create one
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring alert policy for function errors
resource "google_monitoring_alert_policy" "function_error_rate" {
  display_name = "Accessibility Function Error Rate"
  project      = var.project_id
  
  conditions {
    display_name = "Function error rate too high"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = 0.1
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields = ["resource.label.function_name"]
      }
    }
  }
  
  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
  }
  
  combiner     = "OR"
  enabled      = true
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.accessibility_analyzer
  ]
}

# Log sink for function logs (optional, for centralized logging)
resource "google_logging_project_sink" "function_logs" {
  name        = "${local.function_name}-logs"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.document_bucket.name}"
  
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
  
  unique_writer_identity = true
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket.document_bucket,
    google_cloudfunctions2_function.accessibility_analyzer
  ]
}

# Grant log sink permission to write to bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.document_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs.writer_identity
  
  depends_on = [google_logging_project_sink.function_logs]
}