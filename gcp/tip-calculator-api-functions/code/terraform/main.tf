# Main Terraform configuration for GCP tip calculator API using Cloud Functions
# This configuration creates a serverless HTTP API for tip calculations and bill splitting

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent resource naming and configuration
locals {
  # Create unique names for resources to avoid conflicts
  function_name_unique = "${var.function_name}-${random_id.suffix.hex}"
  storage_bucket_name  = "${var.project_id}-functions-${random_id.suffix.hex}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    project     = var.project_id
    region      = var.region
    created-by  = "terraform"
    recipe-name = "tip-calculator-api-functions"
  })
  
  # Required Google Cloud APIs for Cloud Functions
  required_apis = var.enable_apis ? [
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com", 
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com",
    "eventarc.googleapis.com"
  ] : []
}

# Enable required Google Cloud APIs
# These APIs are necessary for Cloud Functions deployment and operation
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create a Cloud Storage bucket for storing function source code
# Cloud Functions requires source code to be uploaded to Cloud Storage
resource "google_storage_bucket" "function_source" {
  name                        = local.storage_bucket_name
  location                    = var.region
  project                     = var.project_id
  force_destroy              = true
  uniform_bucket_level_access = true
  
  # Lifecycle rule to automatically delete old function versions
  lifecycle_rule {
    condition {
      age = 7 # Delete objects older than 7 days
    }
    action {
      type = "Delete"
    }
  }
  
  # Versioning for function source code management
  versioning {
    enabled = true
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create ZIP archive of the function source code
# This packages the Python function code and dependencies for deployment
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  # Include main function file
  source {
    content = templatefile("${path.module}/function-source/main.py", {
      # Template variables can be inserted here if needed
    })
    filename = "main.py"
  }
  
  # Include requirements file
  source {
    content  = file("${path.module}/function-source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload the function source ZIP to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "tip-calculator-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  # Content type for ZIP files
  content_type = "application/zip"
  
  # Metadata for tracking
  metadata = {
    created-by    = "terraform"
    function-name = var.function_name
    runtime       = var.runtime
  }
}

# Create the Cloud Function for tip calculation
# This is the main serverless function that handles HTTP requests
resource "google_cloudfunctions_function" "tip_calculator" {
  name        = local.function_name_unique
  description = var.function_description
  project     = var.project_id
  region      = var.region
  
  # Runtime configuration
  runtime               = var.runtime
  available_memory_mb   = var.memory
  timeout               = var.timeout
  entry_point          = var.entry_point
  max_instances        = var.max_instances
  min_instances        = var.min_instances
  
  # Source code configuration
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  # HTTP trigger configuration
  trigger {
    http_trigger {
      url = null # Will be generated automatically
      security_level = "SECURE_ALWAYS" # Require HTTPS
    }
  }
  
  # Environment variables for the function
  environment_variables = merge(var.environment_variables, {
    FUNCTION_NAME = local.function_name_unique
    DEPLOYMENT_METHOD = "terraform"
  })
  
  # Ingress settings to control access
  ingress_settings = var.ingress_settings
  
  # VPC connector configuration (optional)
  dynamic "vpc_connector" {
    for_each = var.vpc_connector_egress_settings != null ? [1] : []
    content {
      egress_settings = var.vpc_connector_egress_settings
    }
  }
  
  # Labels for organization and billing
  labels = local.common_labels
  
  # Ensure APIs are enabled before creating the function
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
  
  # Lifecycle management
  lifecycle {
    # Prevent destruction during updates unless explicitly planned
    prevent_destroy = false
    
    # Re-create function if source code changes
    replace_triggered_by = [
      google_storage_bucket_object.function_source
    ]
  }
}

# IAM policy to allow public access to the function
# This enables the function to be called without authentication
resource "google_cloudfunctions_function_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0
  
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.tip_calculator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
  
  depends_on = [google_cloudfunctions_function.tip_calculator]
}

# Create log sink for function monitoring (optional enhancement)
# This enables structured logging and monitoring for the function
resource "google_logging_project_sink" "function_logs" {
  name        = "${local.function_name_unique}-logs"
  destination = "logging.googleapis.com/projects/${var.project_id}/logs/tip-calculator-function"
  
  # Log filter for Cloud Functions
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${google_cloudfunctions_function.tip_calculator.name}"
    resource.labels.region="${var.region}"
  EOT
  
  # Include metadata in logs
  unique_writer_identity = true
  
  depends_on = [google_cloudfunctions_function.tip_calculator]
}