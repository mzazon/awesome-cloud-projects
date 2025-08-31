# URL Safety Validation Infrastructure using Web Risk API and Cloud Functions
# This Terraform configuration deploys a complete URL safety validation system

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming prefix
  name_prefix = "${var.function_name}-${var.environment}"
  
  # Unique resource names
  function_name         = "${local.name_prefix}-${random_id.suffix.hex}"
  audit_bucket_name    = "${local.name_prefix}-audit-${random_id.suffix.hex}"
  cache_bucket_name    = "${local.name_prefix}-cache-${random_id.suffix.hex}"
  service_account_name = "${local.name_prefix}-sa-${random_id.suffix.hex}"
  
  # Common labels
  common_labels = merge(var.labels, {
    environment = var.environment
    terraform   = "true"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "webrisk.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = local.service_account_name
  display_name = "URL Validator Function Service Account"
  description  = "Service account for URL safety validation Cloud Function"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM bindings for the service account
resource "google_project_iam_member" "webrisk_user" {
  project = var.project_id
  role    = "roles/webrisk.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Cloud Storage bucket for audit logs
resource "google_storage_bucket" "audit_logs" {
  name                        = local.audit_bucket_name
  location                    = var.region
  project                     = var.project_id
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  force_destroy               = true
  
  labels = local.common_labels
  
  versioning {
    enabled = true
  }
  
  # Lifecycle policy for audit logs
  dynamic "lifecycle_rule" {
    for_each = var.audit_log_retention_days > 0 ? [1] : []
    content {
      condition {
        age = var.audit_log_retention_days
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # Lifecycle policy for old versions
  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for caching validation results
resource "google_storage_bucket" "cache" {
  name                        = local.cache_bucket_name
  location                    = var.region
  project                     = var.project_id
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  force_destroy               = true
  
  labels = local.common_labels
  
  # Lifecycle policy for cache retention
  lifecycle_rule {
    condition {
      age = var.cache_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create the function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content  = file("${path.module}/function_code/main.py")
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name                        = "${local.function_name}-source"
  location                    = var.region
  project                     = var.project_id
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Cloud Function for URL validation
resource "google_cloudfunctions_function" "url_validator" {
  name                  = local.function_name
  project               = var.project_id
  region                = var.region
  description           = "URL Safety Validation using Web Risk API"
  runtime               = "python311"
  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  entry_point           = "validate_url"
  service_account_email = google_service_account.function_sa.email
  max_instances         = var.max_instances
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }
  
  environment_variables = {
    GOOGLE_CLOUD_PROJECT = var.project_id
    AUDIT_BUCKET_NAME    = local.audit_bucket_name
    CACHE_BUCKET_NAME    = local.cache_bucket_name
    ENVIRONMENT          = var.environment
    ENABLE_CORS          = var.enable_cors
    ALLOWED_ORIGINS      = jsonencode(var.allowed_origins)
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_project_iam_member.webrisk_user,
    google_project_iam_member.storage_admin,
    google_project_iam_member.logging_writer
  ]
}

# IAM policy to allow unauthenticated invocation (if enabled)
resource "google_cloudfunctions_function_iam_member" "invoker" {
  count = var.enable_public_access ? 1 : 0
  
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.url_validator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Cloud Monitoring alert policy for function errors
resource "google_monitoring_alert_policy" "function_error_rate" {
  display_name = "${local.function_name} Error Rate Alert"
  project      = var.project_id
  
  conditions {
    display_name = "Cloud Function error rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" resource.labels.function_name=\"${local.function_name}\""
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.05  # 5% error rate
      duration        = "300s" # 5 minutes
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields = [
          "resource.labels.function_name"
        ]
      }
    }
  }
  
  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
  
  combiner = "OR"
  enabled  = true
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring alert policy for Web Risk API quota
resource "google_monitoring_alert_policy" "webrisk_quota" {
  display_name = "Web Risk API Quota Alert"
  project      = var.project_id
  
  conditions {
    display_name = "Web Risk API quota usage"
    
    condition_threshold {
      filter          = "resource.type=\"consumed_api\" resource.labels.service=\"webrisk.googleapis.com\""
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 800  # 80% of quota
      duration        = "300s"
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  alert_strategy {
    auto_close = "86400s"
  }
  
  combiner = "OR"
  enabled  = true
  
  depends_on = [google_project_service.required_apis]
}

# Log-based metric for tracking validation requests
resource "google_logging_metric" "validation_requests" {
  name    = "${local.function_name}-validation-requests"
  project = var.project_id
  
  filter = "resource.type=\"cloud_function\" resource.labels.function_name=\"${local.function_name}\" jsonPayload.url!=\"\""
  
  label_extractors = {
    "safe" = "EXTRACT(jsonPayload.safe)"
    "url"  = "EXTRACT(jsonPayload.url)"
  }
  
  metric_descriptor {
    metric_kind = "COUNTER"
    value_type  = "INT64"
    display_name = "URL Validation Requests"
  }
  
  depends_on = [google_cloudfunctions_function.url_validator]
}