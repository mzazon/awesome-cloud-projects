# Main Terraform configuration for GCP Text Case Converter API
# This creates a serverless HTTP API using Cloud Functions for text case conversion

# Generate a random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Disable the service when the resource is destroyed
  disable_on_destroy = false
  
  # Prevent Terraform from waiting for the service to be fully enabled
  disable_dependent_services = false
}

# Create a Cloud Storage bucket for storing function source code
resource "google_storage_bucket" "function_source_bucket" {
  name     = "${var.project_id}-${var.function_name}-source-${random_id.suffix.hex}"
  location = var.region
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false
  }
  
  # Auto-delete objects after 30 days to manage costs
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = merge(var.labels, {
    purpose = "function-source-storage"
  })

  depends_on = [google_project_service.required_apis]
}

# Create the function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  # Create source files if they don't exist
  source {
    content = templatefile("${path.module}/templates/main.py", {
      function_name = var.entry_point
    })
    filename = "main.py"
  }
  
  source {
    content = templatefile("${path.module}/templates/requirements.txt", {})
    filename = "requirements.txt"
  }
}

# Upload the function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source_object" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.function_source.output_path
  
  # Update the object when source code changes
  detect_md5hash = data.archive_file.function_source.output_md5
}

# Create the Cloud Function for text case conversion
resource "google_cloudfunctions2_function" "text_case_converter" {
  name        = var.function_name
  location    = var.region
  description = var.function_description
  
  # Build configuration
  build_config {
    runtime     = var.runtime
    entry_point = var.entry_point
    
    # Source code configuration
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.function_source_object.name
      }
    }
    
    # Environment variables available during build
    environment_variables = {
      BUILD_CONFIG_PROJECT = var.project_id
    }
  }

  # Service configuration for runtime behavior
  service_config {
    # Memory and CPU allocation
    available_memory = "${var.memory_mb}M"
    timeout_seconds  = var.timeout_seconds
    
    # Scaling configuration
    max_instance_count = var.max_instances
    min_instance_count = var.min_instances
    
    # Allow concurrent requests for better performance
    max_instance_request_concurrency = 10
    
    # Network ingress settings - allow all for public API
    ingress_settings = "ALLOW_ALL"
    
    # Ensure all traffic goes to the latest revision
    all_traffic_on_latest_revision = true
    
    # Runtime environment variables
    environment_variables = merge(var.environment_variables, {
      FUNCTION_TARGET = var.entry_point
      FUNCTION_NAME   = var.function_name
      GCP_PROJECT     = var.project_id
      GCP_REGION      = var.region
    })
  }
  
  labels = merge(var.labels, {
    function-type = "http-api"
    runtime       = var.runtime
  })

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source_object
  ]
}

# IAM policy to allow public access to the function (if enabled)
resource "google_cloudfunctions2_function_iam_member" "public_invoker" {
  count = var.allow_unauthenticated ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.text_case_converter.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Cloud Run IAM binding for public access (Cloud Functions v2 uses Cloud Run)
resource "google_cloud_run_service_iam_member" "public_run_invoker" {
  count = var.allow_unauthenticated ? 1 : 0
  
  project  = var.project_id
  location = var.region
  service  = google_cloudfunctions2_function.text_case_converter.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}