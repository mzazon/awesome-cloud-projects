# Main Terraform Configuration for Custom Music Generation with Vertex AI and Storage
# This file defines all the infrastructure resources needed for the music generation solution

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate resource names with optional suffix and random ID for uniqueness
  random_suffix        = random_id.suffix.hex
  resource_suffix      = var.resource_suffix != "" ? var.resource_suffix : local.random_suffix
  input_bucket_name    = var.input_bucket_name != "" ? var.input_bucket_name : "music-prompts-${local.resource_suffix}"
  output_bucket_name   = var.output_bucket_name != "" ? var.output_bucket_name : "generated-music-${local.resource_suffix}"
  generator_function   = var.generator_function_name != "" ? var.generator_function_name : "music-generator-${local.resource_suffix}"
  api_function         = var.api_function_name != "" ? var.api_function_name : "music-api-${local.resource_suffix}"
  
  # Combine default labels with user-provided labels
  common_labels = merge(
    var.labels,
    {
      environment = var.environment
      region      = var.region
    }
  )
}

# Data source to get project information
data "google_project" "project" {
  project_id = var.project_id
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "aiplatform.googleapis.com",
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Don't disable these services when destroying this resource
  disable_on_destroy = false
}

# Cloud Storage bucket for input prompts and metadata
resource "google_storage_bucket" "input_bucket" {
  name          = local.input_bucket_name
  location      = var.region
  project       = var.project_id
  storage_class = var.storage_class
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Enable versioning for data protection
  versioning {
    enabled = var.enable_versioning
  }
  
  # CORS configuration for web application access
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  # Labels for resource management
  labels = local.common_labels
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for generated music files
resource "google_storage_bucket" "output_bucket" {
  name          = local.output_bucket_name
  location      = var.region
  project       = var.project_id
  storage_class = var.storage_class
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Enable versioning for data protection
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.lifecycle_age_nearline
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = var.lifecycle_age_coldline
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # CORS configuration for content delivery
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  # Labels for resource management
  labels = local.common_labels
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create source code archive for music generator function
data "archive_file" "generator_function_source" {
  type        = "zip"
  output_path = "${path.module}/generator_function_source.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/generator_main.py", {
      output_bucket = google_storage_bucket.output_bucket.name
      project_id    = var.project_id
      region        = var.region
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_templates/generator_requirements.txt")
    filename = "requirements.txt"
  }
}

# Create source code archive for API function
data "archive_file" "api_function_source" {
  type        = "zip"
  output_path = "${path.module}/api_function_source.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/api_main.py", {
      input_bucket = google_storage_bucket.input_bucket.name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_templates/api_requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage object for generator function source code
resource "google_storage_bucket_object" "generator_function_source" {
  name   = "functions/generator-${local.random_suffix}.zip"
  bucket = google_storage_bucket.output_bucket.name
  source = data.archive_file.generator_function_source.output_path
  
  depends_on = [google_storage_bucket.output_bucket]
}

# Cloud Storage object for API function source code
resource "google_storage_bucket_object" "api_function_source" {
  name   = "functions/api-${local.random_suffix}.zip"
  bucket = google_storage_bucket.output_bucket.name
  source = data.archive_file.api_function_source.output_path
  
  depends_on = [google_storage_bucket.output_bucket]
}

# Service account for Cloud Functions
resource "google_service_account" "function_service_account" {
  account_id   = "music-gen-functions-${local.random_suffix}"
  display_name = "Music Generation Functions Service Account"
  description  = "Service account for music generation Cloud Functions with Vertex AI and Storage access"
  project      = var.project_id
}

# IAM roles for the function service account
resource "google_project_iam_member" "function_vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

# Cloud Function for music generation (2nd gen)
resource "google_cloudfunctions2_function" "music_generator" {
  name        = local.generator_function
  location    = var.region
  project     = var.project_id
  description = "Processes music generation requests using Vertex AI Lyria 2 model"
  
  build_config {
    runtime     = var.python_runtime
    entry_point = "generate_music"
    
    source {
      storage_source {
        bucket = google_storage_bucket.output_bucket.name
        object = google_storage_bucket_object.generator_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 10
    min_instance_count               = 0
    available_memory                 = "${var.function_memory}M"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    environment_variables = {
      OUTPUT_BUCKET = google_storage_bucket.output_bucket.name
      GCP_PROJECT   = var.project_id
      GCP_REGION    = var.region
    }
    
    service_account_email = google_service_account.function_service_account.email
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
    google_project_iam_member.function_vertex_ai_user,
    google_project_iam_member.function_storage_admin
  ]
}

# Cloud Function for API endpoint (2nd gen)
resource "google_cloudfunctions2_function" "music_api" {
  name        = local.api_function
  location    = var.region
  project     = var.project_id
  description = "REST API endpoint for submitting music generation requests"
  
  build_config {
    runtime     = var.python_runtime
    entry_point = "music_api"
    
    source {
      storage_source {
        bucket = google_storage_bucket.output_bucket.name
        object = google_storage_bucket_object.api_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 50
    min_instance_count               = 0
    available_memory                 = "${var.api_function_memory}M"
    timeout_seconds                  = var.api_function_timeout
    max_instance_request_concurrency = 1000
    available_cpu                    = "1"
    
    environment_variables = {
      INPUT_BUCKET = google_storage_bucket.input_bucket.name
    }
    
    service_account_email = google_service_account.function_service_account.email
    
    # Enable all traffic to go to latest revision
    ingress_settings = var.enable_public_access ? "ALLOW_ALL" : "ALLOW_INTERNAL_ONLY"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_storage_admin
  ]
}

# IAM policy for public access to API function (if enabled)
resource "google_cloudfunctions2_function_iam_member" "api_public_access" {
  count = var.enable_public_access ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.music_api.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# IAM policy for specific members access to API function (if not public)
resource "google_cloudfunctions2_function_iam_member" "api_member_access" {
  for_each = var.enable_public_access ? toset([]) : toset(var.allowed_members)
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.music_api.name
  role           = "roles/cloudfunctions.invoker"
  member         = each.value
}

# Cloud Logging configuration (if enabled)
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_cloud_logging ? 1 : 0
  
  name        = "music-generation-logs-${local.random_suffix}"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.output_bucket.name}/logs"
  
  filter = <<EOF
resource.type="cloud_function"
resource.labels.function_name="${local.generator_function}" OR
resource.labels.function_name="${local.api_function}"
EOF
  
  unique_writer_identity = true
}

# Grant logging sink permission to write to storage bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_cloud_logging ? 1 : 0
  
  bucket = google_storage_bucket.output_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity
}