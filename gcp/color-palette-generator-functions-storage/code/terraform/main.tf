# main.tf
# Main Terraform configuration for Color Palette Generator with Cloud Functions and Storage

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  bucket_name = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    terraform = "true"
    recipe    = "color-palette-generator"
  })
  
  # Function source directory (relative to Terraform configuration)
  function_source_dir = "${path.module}/../function-source"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_api_services ? toset([
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ]) : toset([])

  project = var.project_id
  service = each.value

  # Prevent accidental deletion of APIs
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Cloud Storage bucket for storing generated color palettes
resource "google_storage_bucket" "palette_bucket" {
  name          = local.bucket_name
  location      = var.region
  storage_class = var.storage_class
  
  # Enable uniform bucket-level access for simplified permissions
  uniform_bucket_level_access = true
  
  # Enable versioning for palette file history
  versioning {
    enabled = true
  }
  
  # Lifecycle rule to manage storage costs
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  # CORS configuration for web application access
  dynamic "cors" {
    for_each = var.enable_cors ? [1] : []
    content {
      origin          = ["*"]
      method          = ["GET", "HEAD"]
      response_header = ["*"]
      max_age_seconds = 3600
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for public read access to palette files (if enabled)
resource "google_storage_bucket_iam_member" "public_read" {
  count  = var.enable_public_access ? 1 : 0
  bucket = google_storage_bucket.palette_bucket.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Create function source directory structure
resource "local_file" "function_main" {
  filename = "${local.function_source_dir}/main.py"
  content = templatefile("${path.module}/function-templates/main.py.tpl", {
    bucket_name = google_storage_bucket.palette_bucket.name
  })
  
  # Ensure directory exists
  depends_on = [local_file.function_requirements]
}

resource "local_file" "function_requirements" {
  filename = "${local.function_source_dir}/requirements.txt"
  content  = file("${path.module}/function-templates/requirements.txt")
}

# Create ZIP archive of function source code
data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = local.function_source_dir
  output_path = "${path.module}/function-source.zip"
  
  depends_on = [
    local_file.function_main,
    local_file.function_requirements
  ]
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source_bucket" {
  name          = "${local.bucket_name}-source"
  location      = var.region
  storage_class = "STANDARD"
  
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.function_source.output_path
  
  metadata = {
    created-by = "terraform"
    version    = data.archive_file.function_source.output_md5
  }
}

# Service account for Cloud Function with least privilege permissions
resource "google_service_account" "function_sa" {
  account_id   = "${var.function_name}-sa"
  display_name = "Service Account for ${var.function_name} Cloud Function"
  description  = "Service account used by the color palette generator Cloud Function"
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for function service account to write to storage bucket
resource "google_storage_bucket_iam_member" "function_storage_admin" {
  bucket = google_storage_bucket.palette_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

# Cloud Function for color palette generation
resource "google_cloudfunctions_function" "palette_generator" {
  name        = var.function_name
  description = "HTTP Cloud Function for generating harmonious color palettes"
  region      = var.region
  
  runtime     = "python312"
  entry_point = "generate_color_palette"
  
  # Memory and timeout configuration
  available_memory_mb = var.function_memory
  timeout             = var.function_timeout
  
  # Source code configuration
  source_archive_bucket = google_storage_bucket.function_source_bucket.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  # HTTP trigger configuration
  trigger {
    https_trigger {
      url = null  # Will be generated automatically
    }
  }
  
  # Service account configuration
  service_account_email = google_service_account.function_sa.email
  
  # Environment variables
  environment_variables = {
    BUCKET_NAME = google_storage_bucket.palette_bucket.name
    CORS_ENABLED = var.enable_cors
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_iam_member.function_storage_admin
  ]
}

# IAM binding to allow unauthenticated access to the Cloud Function
resource "google_cloudfunctions_function_iam_member" "public_access" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.palette_generator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}