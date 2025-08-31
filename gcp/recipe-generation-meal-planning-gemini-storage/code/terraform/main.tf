# Main Terraform Configuration for Recipe Generation and Meal Planning System
# This file contains all the primary infrastructure resources for the AI-powered recipe system

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  # Common resource name prefix
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Unique suffix for bucket and other globally unique resources
  unique_suffix = lower(random_id.suffix.hex)
  
  # Common labels applied to all resources
  common_labels = var.enable_cost_labels ? {
    environment  = var.environment
    project      = var.project_name
    cost_center  = var.cost_center
    owner        = var.owner
    managed_by   = "terraform"
    purpose      = "ai-recipe-generation"
  } : {}
  
  # Function source code paths (assumed to be in the same directory structure)
  generator_source_dir = "${path.module}/../functions/generator"
  retriever_source_dir = "${path.module}/../functions/retriever"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_api_services ? toset([
    "aiplatform.googleapis.com",     # Vertex AI for Gemini models
    "cloudfunctions.googleapis.com", # Cloud Functions for serverless API
    "storage.googleapis.com",        # Cloud Storage for recipe data
    "cloudbuild.googleapis.com",     # Cloud Build for function deployment
    "logging.googleapis.com",        # Cloud Logging for function logs
    "monitoring.googleapis.com",     # Cloud Monitoring for observability
  ]) : toset([])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Cloud Storage bucket for storing generated recipes and user preferences
resource "google_storage_bucket" "recipe_storage" {
  name     = "recipe-storage-${local.unique_suffix}"
  location = var.region
  project  = var.project_id

  # Storage configuration optimized for AI-generated content
  storage_class               = var.bucket_storage_class
  uniform_bucket_level_access = true
  
  # Enable versioning for data protection and audit trails
  versioning {
    enabled = var.bucket_versioning_enabled
  }

  # Lifecycle management to control storage costs
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age
    }
    action {
      type = "Delete"
    }
  }

  # Additional lifecycle rule for managing noncurrent versions
  dynamic "lifecycle_rule" {
    for_each = var.bucket_versioning_enabled ? [1] : []
    content {
      condition {
        num_newer_versions = 3
      }
      action {
        type = "Delete"
      }
    }
  }

  # CORS configuration for web application access
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  # Apply common labels for cost tracking and resource management
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create initial folder structure and sample data files in the bucket
resource "google_storage_bucket_object" "initial_recipes_file" {
  name    = "data/recipes.json"
  bucket  = google_storage_bucket.recipe_storage.name
  content = jsonencode({
    recipes     = []
    preferences = {}
  })
  content_type = "application/json"
}

resource "google_storage_bucket_object" "initial_preferences_file" {
  name    = "data/preferences.json"
  bucket  = google_storage_bucket.recipe_storage.name
  content = jsonencode({
    users = {}
  })
  content_type = "application/json"
}

# Create ZIP archive for recipe generator function
data "archive_file" "generator_function_zip" {
  type        = "zip"
  output_path = "${path.module}/generator-function.zip"
  
  # Generator function Python code
  source {
    content = templatefile("${path.module}/function-templates/generator-main.py.tpl", {
      project_id = var.project_id
      model_name = var.gemini_model_name
    })
    filename = "main.py"
  }
  
  # Requirements file for Python dependencies
  source {
    content  = file("${path.module}/function-templates/generator-requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage object for generator function source code
resource "google_storage_bucket_object" "generator_function_source" {
  name   = "functions/generator-${data.archive_file.generator_function_zip.output_md5}.zip"
  bucket = google_storage_bucket.recipe_storage.name
  source = data.archive_file.generator_function_zip.output_path
}

# Recipe Generator Cloud Function
resource "google_cloudfunctions_function" "recipe_generator" {
  name        = "${local.name_prefix}-generator"
  description = "AI-powered recipe generator using Vertex AI Gemini models"
  runtime     = var.function_runtime
  region      = var.region
  project     = var.project_id

  # Function deployment configuration
  available_memory_mb   = var.generator_function_memory
  timeout               = var.generator_function_timeout
  entry_point          = "generate_recipe"
  source_archive_bucket = google_storage_bucket.recipe_storage.name
  source_archive_object = google_storage_bucket_object.generator_function_source.name

  # HTTP trigger configuration for REST API access
  trigger {
    http_trigger {}
  }

  # Environment variables for function configuration
  environment_variables = {
    BUCKET_NAME     = google_storage_bucket.recipe_storage.name
    GCP_PROJECT     = var.project_id
    VERTEX_LOCATION = var.vertex_ai_location
    MODEL_NAME      = var.gemini_model_name
  }

  # Apply common labels
  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.generator_function_source
  ]
}

# Create ZIP archive for recipe retriever function
data "archive_file" "retriever_function_zip" {
  type        = "zip"
  output_path = "${path.module}/retriever-function.zip"
  
  # Retriever function Python code
  source {
    content  = file("${path.module}/function-templates/retriever-main.py")
    filename = "main.py"
  }
  
  # Requirements file for Python dependencies
  source {
    content  = file("${path.module}/function-templates/retriever-requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage object for retriever function source code
resource "google_storage_bucket_object" "retriever_function_source" {
  name   = "functions/retriever-${data.archive_file.retriever_function_zip.output_md5}.zip"
  bucket = google_storage_bucket.recipe_storage.name
  source = data.archive_file.retriever_function_zip.output_path
}

# Recipe Retriever Cloud Function
resource "google_cloudfunctions_function" "recipe_retriever" {
  name        = "${local.name_prefix}-retriever"
  description = "Recipe retrieval and search API with filtering capabilities"
  runtime     = var.function_runtime
  region      = var.region
  project     = var.project_id

  # Function deployment configuration optimized for data retrieval
  available_memory_mb   = var.retriever_function_memory
  timeout               = var.retriever_function_timeout
  entry_point          = "retrieve_recipes"
  source_archive_bucket = google_storage_bucket.recipe_storage.name
  source_archive_object = google_storage_bucket_object.retriever_function_source.name

  # HTTP trigger configuration for REST API access
  trigger {
    http_trigger {}
  }

  # Environment variables for function configuration
  environment_variables = {
    BUCKET_NAME = google_storage_bucket.recipe_storage.name
    GCP_PROJECT = var.project_id
  }

  # Apply common labels
  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.retriever_function_source
  ]
}

# IAM policy binding for public access to Cloud Functions (if enabled)
resource "google_cloudfunctions_function_iam_member" "generator_public_access" {
  count = var.allow_unauthenticated ? 1 : 0

  project        = var.project_id
  region         = google_cloudfunctions_function.recipe_generator.region
  cloud_function = google_cloudfunctions_function.recipe_generator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloudfunctions_function_iam_member" "retriever_public_access" {
  count = var.allow_unauthenticated ? 1 : 0

  project        = var.project_id
  region         = google_cloudfunctions_function.recipe_retriever.region
  cloud_function = google_cloudfunctions_function.recipe_retriever.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Service account for Cloud Functions with least privilege access
data "google_app_engine_default_service_account" "default" {
  project = var.project_id
}

# IAM binding for Vertex AI access (AI Platform User role)
resource "google_project_iam_member" "functions_vertex_ai_access" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${data.google_app_engine_default_service_account.default.email}"
}

# IAM binding for Cloud Storage access (Storage Object Admin role)
resource "google_project_iam_member" "functions_storage_access" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${data.google_app_engine_default_service_account.default.email}"
}

# Additional IAM members for bucket access (if specified)
resource "google_storage_bucket_iam_member" "additional_members" {
  for_each = toset(var.additional_iam_members)
  
  bucket = google_storage_bucket.recipe_storage.name
  role   = "roles/storage.objectViewer"
  member = each.value
}

# Cloud Logging configuration for function monitoring
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_function_logging ? 1 : 0

  name        = "${local.name_prefix}-function-logs"
  destination = "storage.googleapis.com/${google_storage_bucket.recipe_storage.name}/logs"
  
  # Log filter for Cloud Functions only
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name:("${google_cloudfunctions_function.recipe_generator.name}" OR "${google_cloudfunctions_function.recipe_retriever.name}")
  EOT

  # Automatically create the bucket if it doesn't exist
  unique_writer_identity = true
}

# Grant logging sink permission to write to storage bucket
resource "google_storage_bucket_iam_member" "logging_sink_writer" {
  count = var.enable_function_logging ? 1 : 0

  bucket = google_storage_bucket.recipe_storage.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity
}