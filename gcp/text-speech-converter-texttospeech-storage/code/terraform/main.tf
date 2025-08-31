# Main Terraform configuration for Text-to-Speech Converter with Cloud Storage
# This configuration creates the infrastructure needed for a text-to-speech conversion service

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for computed configurations
locals {
  # Generate unique bucket name if not provided
  bucket_name = var.bucket_name != null ? var.bucket_name : "tts-audio-${var.project_id}-${random_id.suffix.hex}"
  
  # Common labels to apply to all resources
  common_labels = merge(var.labels, {
    created-by = "terraform"
    recipe     = "text-speech-converter-texttospeech-storage"
  })
  
  # Required APIs for the text-to-speech solution
  required_apis = [
    "texttospeech.googleapis.com",
    "storage.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying resources
  disable_dependent_services = false
  disable_on_destroy         = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

# Create Cloud Storage bucket for storing audio files
resource "google_storage_bucket" "audio_storage" {
  name                        = local.bucket_name
  location                    = var.region
  storage_class               = var.bucket_storage_class
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  labels                      = local.common_labels
  
  # Prevent accidental deletion if specified
  lifecycle {
    prevent_destroy = var.prevent_destroy
  }
  
  # Enable versioning if specified
  dynamic "versioning" {
    for_each = var.enable_versioning ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Configure CORS for web applications
  dynamic "cors" {
    for_each = var.enable_cors ? [1] : []
    content {
      origin          = ["*"]
      method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
      response_header = ["*"]
      max_age_seconds = var.cors_max_age_seconds
    }
  }
  
  # Configure lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_enabled && var.lifecycle_delete_age > 0 ? [1] : []
    content {
      condition {
        age = var.lifecycle_delete_age
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # Ensure APIs are enabled before creating the bucket
  depends_on = [
    google_project_service.required_apis
  ]
}

# Configure public access to the bucket if enabled
resource "google_storage_bucket_iam_member" "public_access" {
  count = var.enable_public_access ? 1 : 0
  
  bucket = google_storage_bucket.audio_storage.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
  
  depends_on = [google_storage_bucket.audio_storage]
}

# Create a service account for Text-to-Speech operations (optional but recommended)
resource "google_service_account" "tts_service_account" {
  account_id   = "tts-converter-${random_id.suffix.hex}"
  display_name = "Text-to-Speech Converter Service Account"
  description  = "Service account for Text-to-Speech API operations and Cloud Storage access"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant Text-to-Speech API permissions to the service account
resource "google_project_iam_member" "tts_api_user" {
  project = var.project_id
  role    = "roles/cloudtranslate.user"
  member  = "serviceAccount:${google_service_account.tts_service_account.email}"
}

# Grant Cloud Storage permissions to the service account
resource "google_storage_bucket_iam_member" "storage_admin" {
  bucket = google_storage_bucket.audio_storage.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.tts_service_account.email}"
}

# Create service account key for authentication (use with caution in production)
resource "google_service_account_key" "tts_key" {
  service_account_id = google_service_account.tts_service_account.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

# Optional: Create a Cloud Storage notification for monitoring uploads
resource "google_storage_notification" "audio_upload_notification" {
  count = 0 # Disabled by default, enable if Pub/Sub integration is needed
  
  bucket         = google_storage_bucket.audio_storage.name
  payload_format = "JSON_API_V1"
  topic          = "projects/${var.project_id}/topics/audio-uploads"
  
  event_types = [
    "OBJECT_FINALIZE",
    "OBJECT_DELETE"
  ]
  
  custom_attributes = {
    source = "text-to-speech-converter"
  }
  
  depends_on = [google_storage_bucket.audio_storage]
}

# Create example files for testing (optional)
resource "google_storage_bucket_object" "readme" {
  name         = "README.txt"
  bucket       = google_storage_bucket.audio_storage.name
  content      = <<-EOT
    Text-to-Speech Audio Storage
    ===========================
    
    This bucket stores audio files generated by the Google Cloud Text-to-Speech API.
    
    Usage:
    - Upload text files or use the Python converter script
    - Generated audio files will be stored as MP3 format
    - Files are publicly accessible if public access is enabled
    
    Bucket Configuration:
    - Location: ${var.region}
    - Storage Class: ${var.bucket_storage_class}
    - Lifecycle Management: ${var.bucket_lifecycle_enabled ? "Enabled" : "Disabled"}
    - Public Access: ${var.enable_public_access ? "Enabled" : "Disabled"}
    
    Generated by Terraform on ${timestamp()}
  EOT
  content_type = "text/plain"
  
  depends_on = [google_storage_bucket.audio_storage]
}