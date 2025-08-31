# Main Terraform configuration for GCP Intelligent Document Classification
# This deploys a complete serverless document classification system using Cloud Functions and Vertex AI

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming convention
  resource_name = "${var.resource_prefix}-${var.environment}-${random_id.suffix.hex}"
  
  # Bucket names (must be globally unique)
  inbox_bucket_name      = "${local.resource_name}-inbox"
  classified_bucket_name = "${local.resource_name}-classified"
  
  # Service account name
  service_account_name = "${local.resource_name}-sa"
  
  # Function name
  function_name = "${local.resource_name}-classifier"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
    region      = var.region
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "aiplatform.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "pubsub.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = local.service_account_name
  display_name = "Document Classifier Service Account"
  description  = "Service account for intelligent document classification Cloud Function"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant necessary IAM roles to service account
resource "google_project_iam_member" "function_sa_vertex_ai" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_sa_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_sa_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_sa_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Cloud Storage bucket for document uploads (inbox)
resource "google_storage_bucket" "inbox_bucket" {
  name          = local.inbox_bucket_name
  location      = var.region
  project       = var.project_id
  storage_class = var.storage_class
  force_destroy = var.force_destroy_buckets
  
  labels = local.common_labels
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Versioning configuration
  dynamic "versioning" {
    for_each = var.enable_versioning ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Lifecycle management
  dynamic "lifecycle_rule" {
    for_each = var.enable_lifecycle ? [1] : []
    content {
      condition {
        age = var.lifecycle_age_days
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # CORS configuration for web uploads
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for classified documents
resource "google_storage_bucket" "classified_bucket" {
  name          = local.classified_bucket_name
  location      = var.region
  project       = var.project_id
  storage_class = var.storage_class
  force_destroy = var.force_destroy_buckets
  
  labels = local.common_labels
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Versioning configuration
  dynamic "versioning" {
    for_each = var.enable_versioning ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Lifecycle management for classified documents (longer retention)
  dynamic "lifecycle_rule" {
    for_each = var.enable_lifecycle ? [1] : []
    content {
      condition {
        age = var.lifecycle_age_days * 3  # Keep classified docs 3x longer
      }
      action {
        type = "Delete"
      }
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create folder structure in classified bucket using placeholder objects
resource "google_storage_bucket_object" "folder_placeholders" {
  for_each = toset(var.document_categories)
  
  name         = "${each.value}/.keep"
  content      = ""
  bucket       = google_storage_bucket.classified_bucket.name
  content_type = "text/plain"
}

# Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source_bucket" {
  name          = "${local.resource_name}-function-source"
  location      = var.region
  project       = var.project_id
  storage_class = "STANDARD"
  force_destroy = var.force_destroy_buckets
  
  labels = local.common_labels
  
  uniform_bucket_level_access = true
  
  # Lifecycle management for function source
  lifecycle_rule {
    condition {
      age = 7  # Keep function source for 7 days
    }
    action {
      type = "Delete"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create the Python function code locally
resource "local_file" "function_main" {
  filename = "${path.module}/function_source/main.py"
  content = templatefile("${path.module}/templates/main.py.tpl", {
    classified_bucket = google_storage_bucket.classified_bucket.name
    inbox_bucket     = google_storage_bucket.inbox_bucket.name
    project_id       = var.project_id
    vertex_location  = var.vertex_ai_location
    categories       = jsonencode(var.document_categories)
  })
}

resource "local_file" "function_requirements" {
  filename = "${path.module}/function_source/requirements.txt"
  content  = file("${path.module}/templates/requirements.txt")
}

# Create archive of function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function_source.zip"
  source_dir  = "${path.module}/function_source"
  
  depends_on = [
    local_file.function_main,
    local_file.function_requirements
  ]
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Cloud Function for document classification
resource "google_cloudfunctions2_function" "document_classifier" {
  name        = local.function_name
  location    = var.region
  project     = var.project_id
  description = "Intelligent document classification using Vertex AI Gemini"
  
  labels = local.common_labels
  
  build_config {
    runtime     = "python312"
    entry_point = "classify_document"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = var.max_instances
    min_instance_count               = var.min_instances
    available_memory                 = "${var.function_memory}Mi"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    environment_variables = {
      CLASSIFIED_BUCKET = google_storage_bucket.classified_bucket.name
      INBOX_BUCKET     = google_storage_bucket.inbox_bucket.name
      VERTEX_LOCATION  = var.vertex_ai_location
      DOCUMENT_CATEGORIES = jsonencode(var.document_categories)
    }
    
    service_account_email = google_service_account.function_sa.email
    
    # VPC configuration if needed
    # vpc_connector = google_vpc_access_connector.connector.id
    # vpc_connector_egress_settings = "VPC_CONNECTOR_EGRESS_SETTINGS_UNSPECIFIED"
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.inbox_bucket.name
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_sa_vertex_ai,
    google_project_iam_member.function_sa_storage,
    google_project_iam_member.function_sa_logging,
    google_storage_bucket_object.function_source
  ]
}

# Cloud Logging sink for function logs (if logging enabled)
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_logging ? 1 : 0
  
  name        = "${local.resource_name}-logs"
  destination = "storage.googleapis.com/${google_storage_bucket.classified_bucket.name}/logs"
  
  # Log all Cloud Function logs
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.document_classifier.name}\""
  
  unique_writer_identity = true
}

# Grant the logging sink permission to write to storage
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_logging ? 1 : 0
  
  bucket = google_storage_bucket.classified_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity
}

# Cloud Monitoring alert policy for function errors (if monitoring enabled)
resource "google_monitoring_alert_policy" "function_error_rate" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "${local.function_name} Error Rate Alert"
  project      = var.project_id
  
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Function error rate above threshold"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.document_classifier.name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1  # 10% error rate
      
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
}

# Cloud Monitoring dashboard for document classification metrics
resource "google_monitoring_dashboard" "document_classification" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "${local.function_name} Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Function Invocations"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.document_classifier.name}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Invocations/sec"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Function Execution Time"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.document_classifier.name}\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_time\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Execution Time (ms)"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })
  
  project = var.project_id
}

# IAM policy for public read access to classified documents (optional)
# Uncomment if you need public access to classified documents
# resource "google_storage_bucket_iam_member" "public_access" {
#   bucket = google_storage_bucket.classified_bucket.name
#   role   = "roles/storage.objectViewer"
#   member = "allUsers"
# }

# Notification topic for document classification events
resource "google_pubsub_topic" "classification_events" {
  name    = "${local.resource_name}-events"
  project = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Notification subscription for classification events
resource "google_pubsub_subscription" "classification_events" {
  name    = "${local.resource_name}-events-sub"
  topic   = google_pubsub_topic.classification_events.name
  project = var.project_id
  
  # Message retention for 7 days
  message_retention_duration = "604800s"
  
  # Acknowledge deadline
  ack_deadline_seconds = 300
  
  labels = local.common_labels
}

# Security: Enable Object Versioning and Audit Logging
resource "google_storage_bucket_iam_audit_config" "audit_config" {
  bucket = google_storage_bucket.classified_bucket.name
  
  audit_log_config {
    log_type = "ADMIN_READ"
  }
  
  audit_log_config {
    log_type = "DATA_READ"
  }
  
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}