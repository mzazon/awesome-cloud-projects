# Output values for the Text-to-Speech converter infrastructure
# These outputs provide essential information for using the deployed resources

output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "bucket_name" {
  description = "Name of the Cloud Storage bucket for audio files"
  value       = google_storage_bucket.audio_storage.name
}

output "bucket_url" {
  description = "Full URL of the Cloud Storage bucket"
  value       = google_storage_bucket.audio_storage.url
}

output "bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.audio_storage.self_link
}

output "bucket_public_url" {
  description = "Public HTTP URL for accessing bucket contents (if public access is enabled)"
  value       = var.enable_public_access ? "https://storage.googleapis.com/${google_storage_bucket.audio_storage.name}" : "Not available - public access disabled"
}

output "service_account_email" {
  description = "Email address of the Text-to-Speech service account"
  value       = google_service_account.tts_service_account.email
}

output "service_account_id" {
  description = "Unique ID of the Text-to-Speech service account"
  value       = google_service_account.tts_service_account.unique_id
}

output "service_account_key_id" {
  description = "ID of the service account key (for reference only)"
  value       = google_service_account_key.tts_key.id
  sensitive   = true
}

output "service_account_private_key" {
  description = "Base64 encoded private key for the service account (use with caution)"
  value       = google_service_account_key.tts_key.private_key
  sensitive   = true
}

output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = local.required_apis
}

output "bucket_lifecycle_enabled" {
  description = "Whether lifecycle management is enabled for the bucket"
  value       = var.bucket_lifecycle_enabled
}

output "bucket_public_access_enabled" {
  description = "Whether public access is enabled for the bucket"
  value       = var.enable_public_access
}

output "bucket_storage_class" {
  description = "Storage class of the Cloud Storage bucket"
  value       = google_storage_bucket.audio_storage.storage_class
}

output "example_curl_command" {
  description = "Example curl command to test public access to the bucket (if enabled)"
  value = var.enable_public_access ? "curl -I https://storage.googleapis.com/${google_storage_bucket.audio_storage.name}/README.txt" : "Public access disabled - use authenticated requests"
}

output "gcloud_bucket_commands" {
  description = "Useful gcloud commands for working with the bucket"
  value = {
    list_files    = "gcloud storage ls gs://${google_storage_bucket.audio_storage.name}/"
    upload_file   = "gcloud storage cp <local-file> gs://${google_storage_bucket.audio_storage.name}/"
    download_file = "gcloud storage cp gs://${google_storage_bucket.audio_storage.name}/<file> ./"
    bucket_info   = "gcloud storage buckets describe gs://${google_storage_bucket.audio_storage.name}"
  }
}

output "python_environment_variables" {
  description = "Environment variables to set for the Python Text-to-Speech script"
  value = {
    GOOGLE_CLOUD_PROJECT        = var.project_id
    GOOGLE_APPLICATION_CREDENTIALS = "path/to/service-account-key.json"
    TTS_BUCKET_NAME            = google_storage_bucket.audio_storage.name
    TTS_REGION                 = var.region
  }
}

output "deployment_summary" {
  description = "Summary of deployed resources and their configuration"
  value = {
    bucket_name           = google_storage_bucket.audio_storage.name
    bucket_location       = google_storage_bucket.audio_storage.location
    bucket_storage_class  = google_storage_bucket.audio_storage.storage_class
    public_access_enabled = var.enable_public_access
    lifecycle_enabled     = var.bucket_lifecycle_enabled
    versioning_enabled    = var.enable_versioning
    uniform_access        = var.enable_uniform_bucket_level_access
    service_account       = google_service_account.tts_service_account.email
    enabled_apis          = local.required_apis
  }
}