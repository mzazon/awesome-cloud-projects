# Main Terraform configuration for smart content classification infrastructure
# This file creates all the necessary GCP resources for an AI-powered content classification system

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  resource_suffix = random_id.suffix.hex
  staging_bucket  = "${var.resource_prefix}-staging-${local.resource_suffix}"
  contracts_bucket = "${var.resource_prefix}-contracts-${local.resource_suffix}"
  invoices_bucket = "${var.resource_prefix}-invoices-${local.resource_suffix}"
  marketing_bucket = "${var.resource_prefix}-marketing-${local.resource_suffix}"
  misc_bucket = "${var.resource_prefix}-misc-${local.resource_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    created-by  = "terraform"
    project     = "content-classification"
  })
  
  # Required APIs for the content classification system
  required_apis = [
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudfunctions.googleapis.com",
    "eventarc.googleapis.com",
    "logging.googleapis.com",
    "storage.googleapis.com",
    "aiplatform.googleapis.com",
    "run.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
  }
}

# Service account for Cloud Function with least privilege permissions
resource "google_service_account" "content_classifier" {
  account_id   = "${var.resource_prefix}-sa-${local.resource_suffix}"
  display_name = "Content Classifier Service Account"
  description  = "Service account for AI-powered content classification functions"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM role bindings for the service account
resource "google_project_iam_member" "content_classifier_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.content_classifier.email}"
}

resource "google_project_iam_member" "content_classifier_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.content_classifier.email}"
}

resource "google_project_iam_member" "content_classifier_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.content_classifier.email}"
}

# Staging bucket for incoming files
resource "google_storage_bucket" "staging" {
  name     = local.staging_bucket
  location = var.region
  project  = var.project_id

  storage_class = var.storage_class
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = var.enable_uniform_bucket_access
  
  # Enable versioning to prevent data loss
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  # Lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lifecycle_rule.value.action.storage_class
      }
      condition {
        age                   = lifecycle_rule.value.condition.age
        created_before        = lifecycle_rule.value.condition.created_before
        with_state           = lifecycle_rule.value.condition.with_state
        matches_storage_class = lifecycle_rule.value.condition.matches_storage_class
      }
    }
  }
  
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Classification buckets for organized content storage
resource "google_storage_bucket" "contracts" {
  name     = local.contracts_bucket
  location = var.region
  project  = var.project_id

  storage_class                   = var.storage_class
  uniform_bucket_level_access     = var.enable_uniform_bucket_access
  
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lifecycle_rule.value.action.storage_class
      }
      condition {
        age                   = lifecycle_rule.value.condition.age
        created_before        = lifecycle_rule.value.condition.created_before
        with_state           = lifecycle_rule.value.condition.with_state
        matches_storage_class = lifecycle_rule.value.condition.matches_storage_class
      }
    }
  }
  
  labels = merge(local.common_labels, {
    content-type = "contracts"
  })

  depends_on = [google_project_service.required_apis]
}

resource "google_storage_bucket" "invoices" {
  name     = local.invoices_bucket
  location = var.region
  project  = var.project_id

  storage_class                   = var.storage_class
  uniform_bucket_level_access     = var.enable_uniform_bucket_access
  
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lifecycle_rule.value.action.storage_class
      }
      condition {
        age                   = lifecycle_rule.value.condition.age
        created_before        = lifecycle_rule.value.condition.created_before
        with_state           = lifecycle_rule.value.condition.with_state
        matches_storage_class = lifecycle_rule.value.condition.matches_storage_class
      }
    }
  }
  
  labels = merge(local.common_labels, {
    content-type = "invoices"
  })

  depends_on = [google_project_service.required_apis]
}

resource "google_storage_bucket" "marketing" {
  name     = local.marketing_bucket
  location = var.region
  project  = var.project_id

  storage_class                   = var.storage_class
  uniform_bucket_level_access     = var.enable_uniform_bucket_access
  
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lifecycle_rule.value.action.storage_class
      }
      condition {
        age                   = lifecycle_rule.value.condition.age
        created_before        = lifecycle_rule.value.condition.created_before
        with_state           = lifecycle_rule.value.condition.with_state
        matches_storage_class = lifecycle_rule.value.condition.matches_storage_class
      }
    }
  }
  
  labels = merge(local.common_labels, {
    content-type = "marketing"
  })

  depends_on = [google_project_service.required_apis]
}

resource "google_storage_bucket" "miscellaneous" {
  name     = local.misc_bucket
  location = var.region
  project  = var.project_id

  storage_class                   = var.storage_class
  uniform_bucket_level_access     = var.enable_uniform_bucket_access
  
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lifecycle_rule.value.action.storage_class
      }
      condition {
        age                   = lifecycle_rule.value.condition.age
        created_before        = lifecycle_rule.value.condition.created_before
        with_state           = lifecycle_rule.value.condition.with_state
        matches_storage_class = lifecycle_rule.value.condition.matches_storage_class
      }
    }
  }
  
  labels = merge(local.common_labels, {
    content-type = "miscellaneous"
  })

  depends_on = [google_project_service.required_apis]
}

# Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_source/main.py", {
      gemini_model = var.gemini_model
      max_file_size_mb = var.max_file_size_mb
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = "${var.resource_prefix}-function-source-${local.resource_suffix}"
  location = var.region
  project  = var.project_id

  uniform_bucket_level_access = true
  
  labels = merge(local.common_labels, {
    purpose = "function-source"
  })

  depends_on = [google_project_service.required_apis]
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

# Cloud Function for content classification
resource "google_cloudfunctions2_function" "content_classifier" {
  name     = "${var.resource_prefix}-classifier-${local.resource_suffix}"
  location = var.region
  project  = var.project_id

  description = "AI-powered content classification using Gemini 2.5"

  build_config {
    runtime     = "python39"
    entry_point = "content_classifier"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count = var.function_max_instances
    available_memory   = "${var.function_memory}Mi"
    timeout_seconds    = var.function_timeout
    
    environment_variables = {
      CONTRACTS_BUCKET = google_storage_bucket.contracts.name
      INVOICES_BUCKET  = google_storage_bucket.invoices.name
      MARKETING_BUCKET = google_storage_bucket.marketing.name
      MISC_BUCKET      = google_storage_bucket.miscellaneous.name
      GEMINI_MODEL     = var.gemini_model
      MAX_FILE_SIZE_MB = var.max_file_size_mb
    }
    
    service_account_email = google_service_account.content_classifier.email
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.staging.name
    }
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.content_classifier_ai_user,
    google_project_iam_member.content_classifier_storage_admin,
    google_project_iam_member.content_classifier_log_writer
  ]
}

# Cloud Logging sink for function logs (if logging is enabled)
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_logging ? 1 : 0
  
  name = "${var.resource_prefix}-function-logs-${local.resource_suffix}"
  
  destination = "storage.googleapis.com/${google_storage_bucket.function_logs[0].name}"
  
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.content_classifier.name}\""
  
  unique_writer_identity = true
}

# Cloud Storage bucket for function logs (if logging is enabled)
resource "google_storage_bucket" "function_logs" {
  count = var.enable_logging ? 1 : 0
  
  name     = "${var.resource_prefix}-function-logs-${local.resource_suffix}"
  location = var.region
  project  = var.project_id

  uniform_bucket_level_access = true
  
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = var.log_retention_days
    }
  }
  
  labels = merge(local.common_labels, {
    purpose = "logging"
  })

  depends_on = [google_project_service.required_apis]
}

# IAM binding for logging sink to write to storage bucket
resource "google_storage_bucket_iam_member" "function_logs_writer" {
  count = var.enable_logging ? 1 : 0
  
  bucket = google_storage_bucket.function_logs[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity
}

# Cloud Monitoring alert policy for function errors (if notification email is provided)
resource "google_monitoring_alert_policy" "function_errors" {
  count = var.notification_email != "" ? 1 : 0
  
  display_name = "${var.resource_prefix} Function Error Rate"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud Function error rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.label.function_name=\"${google_cloudfunctions2_function.content_classifier.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.1
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields    = ["resource.label.function_name"]
      }
    }
  }
  
  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  documentation {
    content = "Alert when Cloud Function error rate exceeds 10% for 5 minutes"
  }
}

# Email notification channel (if notification email is provided)
resource "google_monitoring_notification_channel" "email" {
  count = var.notification_email != "" ? 1 : 0
  
  display_name = "Email Notifications"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
}