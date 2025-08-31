# GCP URL Shortener Infrastructure - Main Configuration
# Creates a serverless URL shortening service using Cloud Functions and Firestore

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for computed resource names and configurations
locals {
  # Generate unique names to avoid conflicts
  source_bucket_name = var.source_bucket_name != "" ? "${var.project_id}-${var.source_bucket_name}" : "${var.project_id}-url-shortener-source-${random_id.suffix.hex}"
  function_name      = "${var.function_name}-${random_id.suffix.hex}"
  
  # Function source code directory
  function_source_dir = "${path.module}/function-source/"
  
  # Security rules for Firestore
  firestore_rules = <<EOF
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow read access to url-mappings for redirects
    match /url-mappings/{shortId} {
      allow read: if true;
      allow write: if false; // Only Cloud Function can write
    }
    
    // Deny all other access
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
EOF
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "firestore.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])
  
  project = var.project_id
  service = each.key
  
  # Prevent destruction of services to avoid issues
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Service Account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "url-shortener-function-sa"
  display_name = "URL Shortener Function Service Account"
  description  = "Service account for URL Shortener Cloud Function with Firestore access"
  project      = var.project_id
}

# IAM role binding for Firestore access
resource "google_project_iam_member" "function_firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
  
  depends_on = [google_service_account.function_sa]
}

# IAM role binding for logging
resource "google_project_iam_member" "function_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
  
  depends_on = [google_service_account.function_sa]
}

# Firestore Database
resource "google_firestore_database" "url_shortener_db" {
  project     = var.project_id
  name        = var.firestore_database_id
  location_id = var.firestore_location
  type        = "FIRESTORE_NATIVE"
  
  # Optional features based on variables
  point_in_time_recovery_enablement = var.enable_point_in_time_recovery ? "POINT_IN_TIME_RECOVERY_ENABLED" : "POINT_IN_TIME_RECOVERY_DISABLED"
  delete_protection_state          = var.enable_delete_protection ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
  
  # Set deletion policy - allows destruction via Terraform
  deletion_policy = "DELETE"
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name                        = local.source_bucket_name
  location                    = var.source_bucket_location
  project                     = var.project_id
  force_destroy              = true
  uniform_bucket_level_access = true
  
  # Lifecycle rule to clean up old versions
  lifecycle_rule {
    condition {
      age = 7 # Delete objects older than 7 days
    }
    action {
      type = "Delete"
    }
  }
  
  labels = var.resource_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  source_dir  = local.function_source_dir
  
  # Archive includes all files in the function-source directory
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = var.source_archive_name
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  # Trigger redeployment when source code changes
  source_md5hash = data.archive_file.function_source.output_md5
  
  depends_on = [
    google_storage_bucket.function_source,
    data.archive_file.function_source
  ]
}

# Cloud Function for URL Shortening
resource "google_cloudfunctions2_function" "url_shortener" {
  name        = local.function_name
  location    = var.region
  project     = var.project_id
  description = "Serverless URL shortener using Cloud Functions and Firestore"
  
  # Build configuration
  build_config {
    runtime     = var.runtime
    entry_point = var.function_entry_point
    
    # Source configuration
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
    
    # Environment variables for build
    environment_variables = {
      BUILD_CONFIG_PROJECT_ID = var.project_id
      BUILD_CONFIG_REGION     = var.region
    }
  }
  
  # Service configuration
  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count              = var.function_min_instances
    available_memory                = var.function_memory
    timeout_seconds                 = var.function_timeout
    max_instance_request_concurrency = 1000
    
    # Security configuration
    service_account_email           = google_service_account.function_sa.email
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
    
    # Environment variables for runtime
    environment_variables = {
      PROJECT_ID         = var.project_id
      FIRESTORE_DATABASE = google_firestore_database.url_shortener_db.name
      CORS_ORIGINS       = join(",", var.cors_allowed_origins)
      CORS_METHODS       = join(",", var.cors_allowed_methods)
    }
  }
  
  labels = var.resource_labels
  
  depends_on = [
    google_storage_bucket_object.function_source,
    google_service_account.function_sa,
    google_project_iam_member.function_firestore_user,
    google_project_iam_member.function_log_writer,
    google_firestore_database.url_shortener_db
  ]
}

# IAM binding to allow unauthenticated invocation (if enabled)
resource "google_cloudfunctions2_function_iam_member" "public_access" {
  count = var.allow_unauthenticated_access ? 1 : 0
  
  project        = google_cloudfunctions2_function.url_shortener.project
  location       = google_cloudfunctions2_function.url_shortener.location
  cloud_function = google_cloudfunctions2_function.url_shortener.name
  role          = "roles/cloudfunctions.invoker"
  member        = "allUsers"
  
  depends_on = [google_cloudfunctions2_function.url_shortener]
}

# Cloud Run service IAM binding for public access (required for HTTP functions)
resource "google_cloud_run_service_iam_member" "public_access" {
  count = var.allow_unauthenticated_access ? 1 : 0
  
  project  = google_cloudfunctions2_function.url_shortener.project
  location = google_cloudfunctions2_function.url_shortener.location
  service  = google_cloudfunctions2_function.url_shortener.name
  role     = "roles/run.invoker"
  member   = "allUsers"
  
  depends_on = [google_cloudfunctions2_function.url_shortener]
}

# Note: Function source files (index.js and package.json) are provided
# in the function-source directory as part of this Terraform module

# Output deployment status
resource "null_resource" "deployment_complete" {
  provisioner "local-exec" {
    command = "echo 'URL Shortener deployed successfully! Function URL: ${google_cloudfunctions2_function.url_shortener.service_config[0].uri}'"
  }
  
  depends_on = [
    google_cloudfunctions2_function.url_shortener,
    google_cloudfunctions2_function_iam_member.public_access
  ]
}