# Main Terraform configuration for Location-Aware Content Generation with Gemini and Maps
# This file creates all the necessary GCP resources for the content generation system

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for commonly used expressions
locals {
  bucket_name      = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  function_archive = "function-source.zip"
  
  # Required APIs for the project
  required_apis = [
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com", 
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com"
  ]
  
  # IAM roles required for the service account
  service_account_roles = [
    "roles/viewer",
    "roles/aiplatform.user",
    "roles/storage.admin"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs on destroy to avoid dependency issues
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create service account for the Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = var.service_account_name
  display_name = "Location Content Generator Service Account"
  description  = "Service account for location-aware content generation with Gemini and Maps grounding"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant required IAM roles to the service account
resource "google_project_iam_member" "function_sa_roles" {
  for_each = toset(local.service_account_roles)
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
  
  depends_on = [google_service_account.function_sa]
}

# Create Cloud Storage bucket for generated content
resource "google_storage_bucket" "content_bucket" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Enable versioning for content history
  versioning {
    enabled = var.enable_versioning
  }
  
  # CORS configuration for web access
  cors {
    origin          = var.cors_origins
    method          = ["GET", "POST", "PUT", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  # Lifecycle management to control costs
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
  
  # Apply labels for resource management
  labels = var.labels
  
  depends_on = [google_project_service.required_apis]
}

# Grant the service account access to the storage bucket
resource "google_storage_bucket_iam_member" "bucket_admin" {
  bucket = google_storage_bucket.content_bucket.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.function_sa.email}"
  
  depends_on = [google_storage_bucket.content_bucket, google_service_account.function_sa]
}

# Create the function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = local.function_archive
  
  # Include the Python function source files
  source {
    content = file("${path.module}/function-source/main.py")
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function-source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source/${local.function_archive}"
  bucket = google_storage_bucket.content_bucket.name
  source = data.archive_file.function_source.output_path
  
  # Update when source code changes
  detect_md5hash = true
  
  depends_on = [
    google_storage_bucket.content_bucket,
    data.archive_file.function_source
  ]
}

# Deploy Cloud Function Gen2 for content generation
resource "google_cloudfunctions2_function" "content_generator" {
  name     = var.function_name
  location = var.region
  project  = var.project_id
  
  description = "Location-aware content generation using Gemini with Google Maps grounding"
  
  build_config {
    runtime     = "python312"
    entry_point = "generate_location_content"
    
    source {
      storage_source {
        bucket = google_storage_bucket.content_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
    
    # Environment variables for build process
    environment_variables = {
      GOOGLE_FUNCTION_SOURCE = "main.py"
    }
  }
  
  service_config {
    # Resource allocation
    memory                     = var.function_memory
    timeout_seconds           = var.function_timeout
    max_instance_count        = var.function_max_instances
    min_instance_count        = var.function_min_instances
    
    # Execution environment
    available_cpu             = "1"
    service_account_email     = google_service_account.function_sa.email
    ingress_settings         = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
    
    # Environment variables for the function runtime
    environment_variables = {
      GCP_PROJECT  = var.project_id
      BUCKET_NAME  = google_storage_bucket.content_bucket.name
      REGION       = var.region
    }
  }
  
  # Apply labels for resource management
  labels = var.labels
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.function_sa,
    google_project_iam_member.function_sa_roles,
    google_storage_bucket_object.function_source
  ]
}

# Configure IAM for the Cloud Function (allow public access for demo)
resource "google_cloudfunctions2_function_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.content_generator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
  
  depends_on = [google_cloudfunctions2_function.content_generator]
}

# Create a Cloud Storage bucket for function logs (optional)
resource "google_storage_bucket" "function_logs" {
  name     = "${local.bucket_name}-logs"
  location = var.region
  project  = var.project_id
  
  uniform_bucket_level_access = true
  
  # Lifecycle management for logs
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = merge(var.labels, {
    purpose = "function-logs"
  })
  
  depends_on = [google_project_service.required_apis]
}