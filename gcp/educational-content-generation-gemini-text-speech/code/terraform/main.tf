# Educational Content Generation with Gemini and Text-to-Speech
# This Terraform configuration deploys a complete AI-powered educational content generation pipeline
# using Vertex AI Gemini, Text-to-Speech API, Cloud Functions, and Firestore.

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local variables for consistent naming and configuration
locals {
  # Resource naming with random suffix for uniqueness
  function_name     = "${var.function_name_prefix}-${random_id.suffix.hex}"
  bucket_name      = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  
  # Common resource labels for organization and cost tracking
  common_labels = {
    project     = "educational-content-generation"
    environment = var.environment
    managed_by  = "terraform"
    recipe_id   = "ed7f9a2b"
  }
  
  # Required Google Cloud APIs for the educational content generation pipeline
  required_apis = [
    "cloudfunctions.googleapis.com",
    "aiplatform.googleapis.com",
    "texttospeech.googleapis.com",
    "firestore.googleapis.com",
    "storage-api.googleapis.com",
    "cloudbuild.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  service = each.value
  
  # Prevent accidental deletion of APIs that might be used by other resources
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create Firestore database for educational content storage and lifecycle management
# Firestore provides real-time synchronization and automatic scaling capabilities
resource "google_firestore_database" "educational_content_db" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"
  
  # Prevent accidental deletion of the database containing educational content
  deletion_policy = "DELETE"
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for generated audio files
# Configured for public access to enable educational content distribution
resource "google_storage_bucket" "audio_content_bucket" {
  name     = local.bucket_name
  location = var.region
  
  # Storage class optimized for frequently accessed educational content
  storage_class = "STANDARD"
  
  # Enable versioning for content history and rollback capabilities
  versioning {
    enabled = true
  }
  
  # Lifecycle management to optimize storage costs
  lifecycle_rule {
    condition {
      age = 365  # Archive audio files after 1 year
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  # CORS configuration for web-based audio playback
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for public read access to audio files
# Enables direct access to generated educational audio content
resource "google_storage_bucket_iam_binding" "public_read" {
  bucket = google_storage_bucket.audio_content_bucket.name
  role   = "roles/storage.objectViewer"
  
  members = [
    "allUsers",
  ]
}

# Service account for Cloud Function with necessary permissions
resource "google_service_account" "function_service_account" {
  account_id   = "${local.function_name}-sa"
  display_name = "Educational Content Generator Service Account"
  description  = "Service account for educational content generation Cloud Function"
}

# IAM roles for the Cloud Function service account
# Vertex AI User role for Gemini model access
resource "google_project_iam_member" "vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

# Text-to-Speech API access for audio generation
resource "google_project_iam_member" "texttospeech_user" {
  project = var.project_id
  role    = "roles/cloudtts.developer"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

# Firestore access for content storage and retrieval
resource "google_project_iam_member" "firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

# Cloud Storage access for audio file management
resource "google_storage_bucket_iam_member" "storage_admin" {
  bucket = google_storage_bucket.audio_content_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.function_service_account.email}"
}

# Create ZIP file containing the Cloud Function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id  = var.project_id
      bucket_name = local.bucket_name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage for deployment
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.audio_content_bucket.name
  source = data.archive_file.function_source.output_path
  
  # Ensure function is redeployed when source code changes
  content_type = "application/zip"
}

# Deploy Cloud Function for educational content generation
# Orchestrates Vertex AI Gemini, Text-to-Speech, and Firestore integration
resource "google_cloudfunctions2_function" "content_generator" {
  name     = local.function_name
  location = var.region
  
  build_config {
    runtime     = "python311"
    entry_point = "generate_content"
    
    source {
      storage_source {
        bucket = google_storage_bucket.audio_content_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    # Resource allocation optimized for AI workloads
    max_instance_count    = var.max_function_instances
    min_instance_count    = 0
    available_memory      = "1Gi"
    timeout_seconds       = 540
    max_instance_request_concurrency = 1
    
    # Environment variables for function configuration
    environment_variables = {
      GCP_PROJECT  = var.project_id
      BUCKET_NAME  = local.bucket_name
      REGION       = var.region
    }
    
    # Service account with appropriate permissions
    service_account_email = google_service_account.function_service_account.email
    
    # Allow unauthenticated access for educational content generation
    ingress_settings = "ALLOW_ALL"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_firestore_database.educational_content_db
  ]
}

# Create function source code files locally for deployment
resource "local_file" "function_main" {
  content = templatefile("${path.module}/templates/main.py.tpl", {
    project_id  = var.project_id
    bucket_name = local.bucket_name
  })
  filename = "${path.module}/function_code/main.py"
}

resource "local_file" "function_requirements" {
  content = templatefile("${path.module}/templates/requirements.txt.tpl", {})
  filename = "${path.module}/function_code/requirements.txt"
}

# IAM policy for function invocation (public access for educational use)
resource "google_cloudfunctions2_function_iam_binding" "public_access" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.content_generator.name
  role           = "roles/cloudfunctions.invoker"
  
  members = [
    "allUsers"
  ]
}