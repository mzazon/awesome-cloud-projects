# Output values for the GCP Podcast Content Generation Infrastructure

output "project_id" {
  description = "The Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for podcast content"
  value       = google_storage_bucket.podcast_content.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.podcast_content.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.podcast_content.self_link
}

output "function_name" {
  description = "Name of the Cloud Function for podcast processing"
  value       = google_cloudfunctions_function.podcast_processor.name
}

output "function_trigger_url" {
  description = "HTTPS trigger URL for the Cloud Function"
  value       = google_cloudfunctions_function.podcast_processor.https_trigger_url
}

output "function_source_archive_url" {
  description = "URL of the function source archive in Cloud Storage"
  value       = "gs://${google_storage_bucket_object.function_source.bucket}/${google_storage_bucket_object.function_source.name}"
}

output "service_account_email" {
  description = "Email address of the service account for podcast generation"
  value       = google_service_account.podcast_generator.email
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.podcast_generator.unique_id
}

output "service_account_key_id" {
  description = "ID of the service account key"
  value       = google_service_account_key.podcast_generator_key.name
  sensitive   = true
}

output "service_account_private_key" {
  description = "Private key for the service account (base64 encoded)"
  value       = google_service_account_key.podcast_generator_key.private_key
  sensitive   = true
}

output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = [for api in google_project_service.enabled_apis : api.service]
}

output "storage_bucket_folders" {
  description = "List of created folder structure in the storage bucket"
  value = [
    google_storage_bucket_object.input_folder.name,
    google_storage_bucket_object.processed_folder.name,
    google_storage_bucket_object.audio_folder.name
  ]
}

output "sample_content_files" {
  description = "List of sample content files created for testing"
  value = [
    google_storage_bucket_object.sample_content.name,
    google_storage_bucket_object.tech_news_content.name
  ]
}

output "function_source_bucket_name" {
  description = "Name of the bucket containing the function source code"
  value       = var.function_source_bucket != "" ? var.function_source_bucket : try(google_storage_bucket.function_source[0].name, "")
}

output "monitoring_enabled" {
  description = "Whether monitoring is enabled for the infrastructure"
  value       = var.enable_monitoring
}

output "logging_metric_name" {
  description = "Name of the log-based metric for monitoring podcast generation"
  value       = var.enable_monitoring ? google_logging_metric.podcast_generation_count[0].name : null
}

output "alert_policy_name" {
  description = "Name of the monitoring alert policy for function errors"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_errors[0].name : null
}

output "notification_channel_name" {
  description = "Name of the monitoring notification channel"
  value       = var.enable_monitoring ? google_monitoring_notification_channel.email[0].name : null
}

# Convenient URLs for accessing resources
output "console_urls" {
  description = "Convenient URLs for accessing resources in Google Cloud Console"
  value = {
    storage_bucket    = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.podcast_content.name}"
    cloud_function    = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.podcast_processor.name}"
    service_account   = "https://console.cloud.google.com/iam-admin/serviceaccounts/details/${google_service_account.podcast_generator.unique_id}"
    monitoring        = "https://console.cloud.google.com/monitoring"
    logging          = "https://console.cloud.google.com/logs"
    text_to_speech   = "https://console.cloud.google.com/ai-platform/speech"
    natural_language = "https://console.cloud.google.com/ai-platform/language"
  }
}

# API endpoint information for integration
output "api_endpoints" {
  description = "API endpoints for external integration"
  value = {
    function_url       = google_cloudfunctions_function.podcast_processor.https_trigger_url
    storage_api_url    = "https://storage.googleapis.com/storage/v1/b/${google_storage_bucket.podcast_content.name}"
    tts_api_url        = "https://texttospeech.googleapis.com/v1/text:synthesize"
    language_api_url   = "https://language.googleapis.com/v1/documents:analyzeSentiment"
  }
}

# Resource naming information
output "resource_naming" {
  description = "Information about resource naming and identification"
  value = {
    resource_suffix = random_id.suffix.hex
    environment     = var.environment
    labels          = local.common_labels
  }
}

# Configuration details for client applications
output "client_configuration" {
  description = "Configuration details for client applications and scripts"
  value = {
    bucket_name           = google_storage_bucket.podcast_content.name
    function_name         = google_cloudfunctions_function.podcast_processor.name
    function_url          = google_cloudfunctions_function.podcast_processor.https_trigger_url
    project_id           = var.project_id
    region               = var.region
    service_account_email = google_service_account.podcast_generator.email
    input_folder         = "input/"
    processed_folder     = "processed/"
    audio_folder         = "audio/"
  }
}

# Cost optimization information
output "cost_optimization" {
  description = "Information for cost optimization and monitoring"
  value = {
    bucket_storage_class  = var.bucket_storage_class
    bucket_lifecycle_days = var.lifecycle_age_days
    function_memory_mb    = var.function_memory
    function_timeout_s    = var.function_timeout
    function_min_instances = var.function_min_instances
    function_max_instances = var.function_max_instances
    versioning_enabled    = var.enable_versioning
  }
}

# Security and access information
output "security_configuration" {
  description = "Security and access configuration details"
  value = {
    service_account_roles = [
      "roles/storage.admin",
      "roles/ml.developer",
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter"
    ]
    function_security_level = "SECURE_ALWAYS"
    bucket_access_control   = "uniform_bucket_level_access"
    function_auth_required  = false
  }
}

# Deployment validation information
output "deployment_validation" {
  description = "Information for validating the deployment"
  value = {
    test_function_command = "curl -X POST ${google_cloudfunctions_function.podcast_processor.https_trigger_url} -H 'Content-Type: application/json' -d '{\"bucket_name\": \"${google_storage_bucket.podcast_content.name}\", \"file_name\": \"sample-article.txt\"}'"
    check_bucket_command  = "gsutil ls gs://${google_storage_bucket.podcast_content.name}/"
    check_apis_command    = "gcloud services list --enabled --project=${var.project_id}"
    function_logs_command = "gcloud functions logs read ${google_cloudfunctions_function.podcast_processor.name} --region=${var.region} --limit=10"
  }
}