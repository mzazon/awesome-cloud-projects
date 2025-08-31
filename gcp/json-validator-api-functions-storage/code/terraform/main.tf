# Main Terraform configuration for GCP JSON Validator API
# This creates a serverless JSON validation API using Cloud Functions and Cloud Storage

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "eventarc.googleapis.com"
  ]) : toset([])

  service = each.value

  # Prevent accidental deletion of APIs
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Cloud Storage bucket for JSON file processing
resource "google_storage_bucket" "json_files" {
  name          = "${var.bucket_name}-${var.project_id}-${random_id.suffix.hex}"
  location      = var.region
  storage_class = var.storage_class
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Enable versioning for data protection
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management to optimize costs
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
  
  # CORS configuration for web applications
  cors {
    origin          = ["*"]
    method          = ["GET", "POST", "PUT", "DELETE"]
    response_header = ["Content-Type", "Access-Control-Allow-Origin"]
    max_age_seconds = 3600
  }
  
  labels = var.labels
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for public read access (if enabled)
resource "google_storage_bucket_iam_member" "public_read" {
  count  = var.enable_public_access ? 1 : 0
  bucket = google_storage_bucket.json_files.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Create service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.function_name}-sa-${random_id.suffix.hex}"
  display_name = "Service Account for JSON Validator Function"
  description  = "Service account used by the JSON validator Cloud Function"
}

# Grant storage access to the function service account
resource "google_storage_bucket_iam_member" "function_storage_access" {
  bucket = google_storage_bucket.json_files.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant logging permissions to the function service account
resource "google_project_iam_member" "function_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant monitoring permissions to the function service account
resource "google_project_iam_member" "function_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function-source/main.py", {
      bucket_name = google_storage_bucket.json_files.name
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
  bucket = google_storage_bucket.json_files.name  # Reuse the same bucket for simplicity
  source = data.archive_file.function_source.output_path
  
  # Ensure the source code is updated when it changes
  metadata = {
    source_hash = data.archive_file.function_source.output_base64sha256
  }
}

# Create the Cloud Function for JSON validation
resource "google_cloudfunctions2_function" "json_validator" {
  name        = "${var.function_name}-${random_id.suffix.hex}"
  location    = var.region
  description = "Serverless JSON validation and formatting API"
  
  build_config {
    runtime     = "python311"
    entry_point = "json_validator_api"
    
    source {
      storage_source {
        bucket = google_storage_bucket.json_files.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = var.max_instances
    min_instance_count    = var.min_instances
    available_memory      = "${var.function_memory}M"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.function_sa.email
    
    # Environment variables for the function
    environment_variables = {
      PROJECT_ID   = var.project_id
      BUCKET_NAME  = google_storage_bucket.json_files.name
      REGION       = var.region
      FUNCTION_ENV = "production"
    }
    
    # Allow all traffic (for public API)
    ingress_settings = "ALLOW_ALL"
    
    # Configure for HTTP trigger
    all_traffic_on_latest_revision = true
  }
  
  labels = var.labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# Create Cloud Function IAM policy for public access
resource "google_cloudfunctions2_function_iam_member" "public_access" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.json_validator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create sample JSON files for testing
resource "google_storage_bucket_object" "sample_valid_json" {
  name   = "samples/valid-sample.json"
  bucket = google_storage_bucket.json_files.name
  content = jsonencode({
    users = [
      {
        id     = 1
        name   = "John Doe"
        email  = "john@example.com"
        active = true
        roles  = ["admin", "user"]
      },
      {
        id     = 2
        name   = "Jane Smith"
        email  = "jane@example.com"
        active = false
        roles  = ["user"]
      }
    ]
    metadata = {
      total   = 2
      created = "2025-01-15T10:00:00Z"
    }
  })
  content_type = "application/json"
}

resource "google_storage_bucket_object" "sample_invalid_json" {
  name         = "samples/invalid-sample.json"
  bucket       = google_storage_bucket.json_files.name
  content      = "{\n  \"users\": [\n    {\n      \"id\": 1,\n      \"name\": \"John Doe\",\n      \"email\": \"john@example.com\",\n      \"active\": true,\n      \"roles\": [\"admin\", \"user\"]\n    },\n    {\n      \"id\": 2,\n      \"name\": \"Jane Smith\",\n      \"email\": \"jane@example.com\",\n      \"active\": false,\n      \"roles\": [\"user\"]\n    }\n  ],\n  \"metadata\": {\n    \"total\": 2,\n    \"created\": \"2025-01-15T10:00:00Z\"\n  }\n  // Missing closing brace and invalid comment"
  content_type = "text/plain"
}

# Create log-based alerting policy (if notification email is provided)
resource "google_monitoring_alert_policy" "function_errors" {
  count        = var.notification_email != "" ? 1 : 0
  display_name = "JSON Validator Function Errors"
  combiner     = "OR"
  
  conditions {
    display_name = "Function execution errors"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.json_validator.name}\" AND severity>=ERROR"
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 5
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create dashboard for monitoring
resource "google_monitoring_dashboard" "json_validator_dashboard" {
  dashboard_json = jsonencode({
    displayName = "JSON Validator API Dashboard"
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
                    filter = "metric.type=\"cloudfunctions.googleapis.com/function/executions\" resource.type=\"cloud_function\" resource.label.function_name=\"${google_cloudfunctions2_function.json_validator.name}\""
                  }
                  unitOverride = "1"
                }
                plotType = "LINE"
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Invocations"
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
                    filter = "metric.type=\"cloudfunctions.googleapis.com/function/execution_times\" resource.type=\"cloud_function\" resource.label.function_name=\"${google_cloudfunctions2_function.json_validator.name}\""
                  }
                  unitOverride = "ms"
                }
                plotType = "LINE"
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Execution Time (ms)"
                scale = "LINEAR"
              }
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
                    filter = "metric.type=\"storage.googleapis.com/storage/object_count\" resource.type=\"gcs_bucket\" resource.label.bucket_name=\"${google_storage_bucket.json_files.name}\""
                  }
                  unitOverride = "1"
                }
                plotType = "LINE"
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Object Count"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}