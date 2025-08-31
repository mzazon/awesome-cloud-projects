# Output values for the multi-speaker transcription infrastructure
# These outputs provide important information for verification and integration

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "input_bucket_name" {
  description = "Name of the Cloud Storage bucket for input audio files"
  value       = google_storage_bucket.input_bucket.name
}

output "input_bucket_url" {
  description = "Full URL of the input Cloud Storage bucket"
  value       = google_storage_bucket.input_bucket.url
}

output "output_bucket_name" {
  description = "Name of the Cloud Storage bucket for output transcripts"
  value       = google_storage_bucket.output_bucket.name
}

output "output_bucket_url" {
  description = "Full URL of the output Cloud Storage bucket"
  value       = google_storage_bucket.output_bucket.url
}

output "function_name" {
  description = "Name of the Cloud Function for transcription processing"
  value       = google_cloudfunctions2_function.transcription_processor.name
}

output "function_uri" {
  description = "URI of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.transcription_processor.service_config[0].uri
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "speech_model" {
  description = "Speech-to-Text model configured for transcription"
  value       = var.speech_model
}

output "speaker_diarization_enabled" {
  description = "Whether speaker diarization is enabled"
  value       = var.speaker_diarization_config.enable_speaker_diarization
}

output "supported_language_codes" {
  description = "List of language codes configured for transcription"
  value       = var.language_codes
}

output "notification_topic" {
  description = "Pub/Sub topic for notifications (if enabled)"
  value       = var.notification_topic_name != "" ? google_pubsub_topic.notifications[0].name : null
}

output "upload_instructions" {
  description = "Instructions for uploading audio files to trigger transcription"
  value = format(
    "Upload audio files to: gsutil cp your-audio-file.wav gs://%s/",
    google_storage_bucket.input_bucket.name
  )
}

output "download_instructions" {
  description = "Instructions for downloading transcription results"
  value = format(
    "Download transcripts from: gsutil cp gs://%s/transcripts/* ./",
    google_storage_bucket.output_bucket.name
  )
}

output "function_logs_command" {
  description = "Command to view Cloud Function logs"
  value = format(
    "gcloud functions logs read %s --region=%s --limit=10",
    google_cloudfunctions2_function.transcription_processor.name,
    var.region
  )
}

output "test_upload_command" {
  description = "Example command to test the transcription system"
  value = format(
    "gsutil cp sample-audio.wav gs://%s/ && sleep 30 && gsutil ls gs://%s/transcripts/",
    google_storage_bucket.input_bucket.name,
    google_storage_bucket.output_bucket.name
  )
}

output "bucket_lifecycle_days" {
  description = "Number of days before objects are automatically deleted"
  value       = var.bucket_lifecycle_age_days
}

output "function_configuration" {
  description = "Cloud Function configuration summary"
  value = {
    memory_mb       = var.function_memory
    timeout_seconds = var.function_timeout
    max_instances   = var.function_max_instances
    runtime         = "python312"
  }
}

output "storage_configuration" {
  description = "Cloud Storage configuration summary"
  value = {
    storage_class        = var.bucket_storage_class
    versioning_enabled   = var.enable_bucket_versioning
    encryption_enabled   = var.enable_bucket_encryption
    lifecycle_age_days   = var.bucket_lifecycle_age_days
  }
}

output "resource_labels" {
  description = "Labels applied to all resources"
  value       = local.common_labels
  sensitive   = false
}

output "estimated_costs" {
  description = "Estimated monthly costs for typical usage"
  value = {
    note = "Costs depend on usage. Speech-to-Text: ~$0.006-0.024 per minute. Cloud Functions: ~$0.0000004 per GB-second. Storage: ~$0.020 per GB/month."
    speech_api_pricing = "Varies by model: Chirp 3 may have premium pricing"
    storage_pricing = "Standard storage: $0.020/GB/month, operations: $0.05/10k operations"
    function_pricing = "First 2M invocations free, then $0.40/M invocations"
  }
}

# Security and compliance outputs
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    service_account_principle     = "Dedicated service account with minimal permissions"
    storage_access_control       = "Uniform bucket-level access enabled"
    function_ingress_settings     = "Internal traffic only"
    api_access_scope             = "Project-level Speech API and Storage access"
  }
}

output "monitoring_and_debugging" {
  description = "Monitoring and debugging information"
  value = {
    function_logs = format("gcloud functions logs read %s --region=%s", 
                          google_cloudfunctions2_function.transcription_processor.name, var.region)
    storage_access_logs = "Enable Cloud Audit Logs for detailed storage access monitoring"
    function_metrics = format("View metrics in Cloud Monitoring for function: %s", 
                             google_cloudfunctions2_function.transcription_processor.name)
    error_reporting = "Automatic error reporting enabled via Cloud Functions runtime"
  }
}

output "resource_names" {
  description = "Names of all created resources for reference"
  value = {
    input_bucket_name    = google_storage_bucket.input_bucket.name
    output_bucket_name   = google_storage_bucket.output_bucket.name
    function_name        = google_cloudfunctions2_function.transcription_processor.name
    service_account_name = google_service_account.function_sa.name
    random_suffix        = local.name_suffix
  }
}