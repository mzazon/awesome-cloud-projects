# Smart Resume Screening Infrastructure with Vertex AI and Cloud Functions
# This Terraform configuration deploys a complete AI-powered resume screening system

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming and tagging
  resource_suffix = random_id.suffix.hex
  common_labels = merge(var.tags, {
    environment = var.environment
    terraform   = "true"
  })
  
  # Resource names with consistent naming convention
  bucket_name                = "${var.resource_prefix}-resumes-${local.resource_suffix}"
  function_name             = "${var.resource_prefix}-processor-${local.resource_suffix}"
  service_account_name      = "${var.resource_prefix}-sa-${local.resource_suffix}"
  firestore_collection_name = "candidates"
}

# Enable required APIs for the resume screening solution
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "firestore.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "language.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com"
  ])

  service            = each.value
  disable_on_destroy = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Firestore database for storing candidate data
resource "google_firestore_database" "candidates_db" {
  provider = google-beta
  
  name                        = "(default)"
  location_id                 = var.firestore_location
  type                        = "FIRESTORE_NATIVE"
  concurrency_mode           = "OPTIMISTIC"
  app_engine_integration_mode = "DISABLED"
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for Cloud Function with minimal permissions
resource "google_service_account" "function_sa" {
  account_id   = local.service_account_name
  display_name = "Resume Screening Function Service Account"
  description  = "Service account for the resume screening Cloud Function"
  
  depends_on = [google_project_service.required_apis]
}

# IAM bindings for the function service account
resource "google_project_iam_member" "function_sa_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_sa_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_sa_language" {
  project = var.project_id
  role    = "roles/language.client"
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

# Cloud Storage bucket for resume uploads with security and lifecycle management
resource "google_storage_bucket" "resume_uploads" {
  name                        = local.bucket_name
  location                    = var.bucket_location
  storage_class              = var.bucket_storage_class
  uniform_bucket_level_access = true
  force_destroy              = true

  # Enable versioning if specified
  dynamic "versioning" {
    for_each = var.enable_versioning ? [1] : []
    content {
      enabled = true
    }
  }

  # Lifecycle rules for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules ? [1] : []
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
    for_each = var.lifecycle_rules ? [1] : []
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

  # Security configurations
  public_access_prevention = "enforced"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket IAM for function access
resource "google_storage_bucket_iam_member" "function_bucket_access" {
  bucket = google_storage_bucket.resume_uploads.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create the function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/resume-processor-${local.resource_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/function_source/main.py.tpl", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.resume_uploads.name
  source = data.archive_file.function_source.output_path
  
  content_type = "application/zip"
}

# Cloud Function for processing uploaded resumes
resource "google_cloudfunctions2_function" "resume_processor" {
  provider = google-beta
  
  name        = local.function_name
  location    = var.region
  description = "AI-powered resume screening function using Vertex AI Natural Language API"

  build_config {
    runtime     = "python311"
    entry_point = "process_resume"
    
    source {
      storage_source {
        bucket = google_storage_bucket.resume_uploads.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count = 10
    min_instance_count = 0
    available_memory   = "${var.function_memory}Mi"
    timeout_seconds    = var.function_timeout
    
    environment_variables = {
      PROJECT_ID                = var.project_id
      REGION                   = var.region
      FIRESTORE_COLLECTION     = local.firestore_collection_name
      ALLOWED_FILE_TYPES       = join(",", var.allowed_file_types)
    }
    
    service_account_email = google_service_account.function_sa.email
    
    # Security configurations
    ingress_settings = "ALLOW_INTERNAL_ONLY"
    
    # VPC connector configuration if needed
    # vpc_connector                 = google_vpc_access_connector.connector.name
    # vpc_connector_egress_settings = "VPC_CONNECTOR_EGRESS_SETTINGS_UNSPECIFIED"
  }

  # Event trigger for Cloud Storage
  event_trigger {
    trigger_region        = var.region
    event_type           = "google.cloud.storage.object.v1.finalized"
    retry_policy         = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.function_sa.email
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.resume_uploads.name
    }
  }

  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_firestore_database.candidates_db,
    google_storage_bucket_object.function_source
  ]
}

# Create monitoring dashboard for the resume screening system
resource "google_monitoring_dashboard" "resume_screening_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Resume Screening System Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Function Executions"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Function Duration"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_times\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          width  = 12
          height = 4
          yPos   = 4
          widget = {
            title = "Storage Bucket Objects"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gcs_bucket\" AND resource.labels.bucket_name=\"${local.bucket_name}\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create notification policy for function errors if email is provided
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  
  display_name = "Resume Screening Email Notifications"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_monitoring_alert_policy" "function_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Resume Processing Function Errors"
  combiner     = "OR"
  
  conditions {
    display_name = "Function error rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 5
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  dynamic "notification_channels" {
    for_each = google_monitoring_notification_channel.email
    content {
      notification_channels = [notification_channels.value.name]
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Security: Create firewall rules if custom VPC is used
# Note: This is commented out as the default setup uses the default network
# Uncomment and configure if using a custom VPC

# resource "google_compute_firewall" "allow_function_egress" {
#   name    = "${var.resource_prefix}-allow-function-egress-${local.resource_suffix}"
#   network = google_compute_network.custom_vpc.name
#   
#   allow {
#     protocol = "tcp"
#     ports    = ["443", "80"]
#   }
#   
#   direction   = "EGRESS"
#   target_tags = ["cloud-function"]
# }

# Audit logging configuration
resource "google_project_iam_audit_config" "storage_audit" {
  count   = var.enable_audit_logs ? 1 : 0
  project = var.project_id
  service = "storage.googleapis.com"
  
  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

resource "google_project_iam_audit_config" "firestore_audit" {
  count   = var.enable_audit_logs ? 1 : 0
  project = var.project_id
  service = "firestore.googleapis.com"
  
  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}