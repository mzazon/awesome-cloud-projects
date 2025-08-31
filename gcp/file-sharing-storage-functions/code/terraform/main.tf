# Main Terraform configuration for GCP file sharing infrastructure
# This configuration creates a serverless file sharing system using Cloud Storage and Cloud Functions

# Generate random suffix to ensure unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  resource_prefix = "${var.project_id}-${var.environment}"
  random_suffix   = random_id.suffix.hex
  
  # Resource names with unique suffixes
  file_bucket_name     = "${local.resource_prefix}-files-${local.random_suffix}"
  source_bucket_name   = "${local.resource_prefix}-source-${local.random_suffix}"
  upload_function_name = "${local.resource_prefix}-upload-${local.random_suffix}"
  link_function_name   = "${local.resource_prefix}-link-${local.random_suffix}"
  service_account_id   = "${var.environment}-file-sharing-sa-${local.random_suffix}"
  
  # Combined labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    created_by  = "terraform"
    purpose     = "file-sharing"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
}

# Service account for Cloud Functions
resource "google_service_account" "function_service_account" {
  account_id   = local.service_account_id
  display_name = "File Sharing Function Service Account"
  description  = "Service account for file sharing Cloud Functions with least privilege access"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for Cloud Function to access storage bucket
resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
  
  depends_on = [google_service_account.function_service_account]
}

# IAM binding for Cloud Function to create signed URLs
resource "google_project_iam_member" "function_storage_signer" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
  
  depends_on = [google_service_account.function_service_account]
}

# Cloud Storage bucket for storing shared files
resource "google_storage_bucket" "file_bucket" {
  name          = local.file_bucket_name
  location      = var.region
  storage_class = var.file_storage_class
  project       = var.project_id
  
  # Enable uniform bucket-level access for consistent IAM
  uniform_bucket_level_access = var.enable_uniform_bucket_access
  
  # CORS configuration for web-based uploads
  cors {
    origin          = var.cors_origins
    method          = var.cors_methods
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  # Versioning configuration
  versioning {
    enabled = var.enable_bucket_versioning
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
  
  # Public access prevention
  public_access_prevention = "enforced"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "source_bucket" {
  name          = local.source_bucket_name
  location      = var.region
  storage_class = "STANDARD"
  project       = var.project_id
  
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create ZIP archive for upload function source code
data "archive_file" "upload_function_source" {
  type        = "zip"
  output_path = "${path.module}/upload-function.zip"
  
  source {
    content = templatefile("${path.module}/function-templates/upload_function.py", {
      bucket_name     = local.file_bucket_name
      max_file_size   = var.max_file_size_mb
      allowed_extensions = jsonencode(var.allowed_file_extensions)
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function-templates/requirements.txt")
    filename = "requirements.txt"
  }
}

# Create ZIP archive for link generation function source code
data "archive_file" "link_function_source" {
  type        = "zip"
  output_path = "${path.module}/link-function.zip"
  
  source {
    content = templatefile("${path.module}/function-templates/link_function.py", {
      bucket_name       = local.file_bucket_name
      expiration_hours = var.signed_url_expiration_hours
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function-templates/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "upload_function_source" {
  name   = "upload-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.source_bucket.name
  source = data.archive_file.upload_function_source.output_path
  
  depends_on = [data.archive_file.upload_function_source]
}

# Upload link function source code to Cloud Storage
resource "google_storage_bucket_object" "link_function_source" {
  name   = "link-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.source_bucket.name
  source = data.archive_file.link_function_source.output_path
  
  depends_on = [data.archive_file.link_function_source]
}

# Cloud Function for file uploads (Generation 2)
resource "google_cloudfunctions2_function" "upload_function" {
  name        = local.upload_function_name
  location    = var.region
  description = "HTTP-triggered function for handling file uploads to Cloud Storage"
  project     = var.project_id
  
  build_config {
    runtime     = "python312"
    entry_point = "upload_file"
    
    source {
      storage_source {
        bucket = google_storage_bucket.source_bucket.name
        object = google_storage_bucket_object.upload_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = var.max_instance_count
    min_instance_count               = 0
    available_memory                 = var.function_memory
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 80
    available_cpu                    = "1"
    
    environment_variables = {
      BUCKET_NAME           = google_storage_bucket.file_bucket.name
      MAX_FILE_SIZE_MB      = var.max_file_size_mb
      ALLOWED_EXTENSIONS    = jsonencode(var.allowed_file_extensions)
      GCP_PROJECT           = var.project_id
    }
    
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.function_service_account.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.upload_function_source,
    google_project_iam_member.function_storage_admin
  ]
}

# Cloud Function for generating shareable links (Generation 2)
resource "google_cloudfunctions2_function" "link_function" {
  name        = local.link_function_name
  location    = var.region
  description = "HTTP-triggered function for generating signed URLs for file downloads"
  project     = var.project_id
  
  build_config {
    runtime     = "python312"
    entry_point = "generate_link"
    
    source {
      storage_source {
        bucket = google_storage_bucket.source_bucket.name
        object = google_storage_bucket_object.link_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = var.max_instance_count
    min_instance_count               = 0
    available_memory                 = var.function_memory
    timeout_seconds                  = 30
    max_instance_request_concurrency = 80
    available_cpu                    = "1"
    
    environment_variables = {
      BUCKET_NAME       = google_storage_bucket.file_bucket.name
      EXPIRATION_HOURS  = var.signed_url_expiration_hours
      GCP_PROJECT       = var.project_id
    }
    
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.function_service_account.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.link_function_source,
    google_project_iam_member.function_storage_admin,
    google_project_iam_member.function_storage_signer
  ]
}

# IAM policy to allow public access to upload function
resource "google_cloudfunctions2_function_iam_member" "upload_invoker" {
  project        = var.project_id
  location       = google_cloudfunctions2_function.upload_function.location
  cloud_function = google_cloudfunctions2_function.upload_function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
  
  depends_on = [google_cloudfunctions2_function.upload_function]
}

# IAM policy to allow public access to link generation function
resource "google_cloudfunctions2_function_iam_member" "link_invoker" {
  project        = var.project_id
  location       = google_cloudfunctions2_function.link_function.location
  cloud_function = google_cloudfunctions2_function.link_function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
  
  depends_on = [google_cloudfunctions2_function.link_function]
}

# Cloud Run IAM policies (Cloud Functions v2 runs on Cloud Run)
resource "google_cloud_run_service_iam_member" "upload_run_invoker" {
  project  = var.project_id
  location = google_cloudfunctions2_function.upload_function.location
  service  = google_cloudfunctions2_function.upload_function.name
  role     = "roles/run.invoker"
  member   = "allUsers"
  
  depends_on = [google_cloudfunctions2_function.upload_function]
}

resource "google_cloud_run_service_iam_member" "link_run_invoker" {
  project  = var.project_id
  location = google_cloudfunctions2_function.link_function.location
  service  = google_cloudfunctions2_function.link_function.name
  role     = "roles/run.invoker"
  member   = "allUsers"
  
  depends_on = [google_cloudfunctions2_function.link_function]
}