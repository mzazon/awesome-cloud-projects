# Output Values for Meeting Summary Generation Infrastructure
# These outputs provide important information about the deployed resources

output "project_id" {
  description = "Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "Deployment region"
  value       = var.region
}

output "bucket_name" {
  description = "Cloud Storage bucket name for meeting recordings"
  value       = google_storage_bucket.meeting_recordings.name
}

output "bucket_url" {
  description = "Cloud Storage bucket URL"
  value       = google_storage_bucket.meeting_recordings.url
}

output "bucket_self_link" {
  description = "Cloud Storage bucket self link"
  value       = google_storage_bucket.meeting_recordings.self_link
}

output "function_name" {
  description = "Cloud Function name for meeting processing"
  value       = google_cloudfunctions2_function.meeting_processor.name
}

output "function_url" {
  description = "Cloud Function trigger URL (if HTTP trigger)"
  value       = google_cloudfunctions2_function.meeting_processor.service_config[0].uri
}

output "function_id" {
  description = "Cloud Function unique identifier"
  value       = google_cloudfunctions2_function.meeting_processor.id
}

output "service_account_email" {
  description = "Service account email for the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "service_account_id" {
  description = "Service account unique ID"
  value       = google_service_account.function_sa.unique_id
}

output "upload_instructions" {
  description = "Instructions for uploading meeting recordings"
  value = <<-EOT
    To upload meeting recordings and trigger processing:
    
    1. Using gcloud CLI:
       gsutil cp your-meeting-file.wav gs://${google_storage_bucket.meeting_recordings.name}/
    
    2. Using Google Cloud Console:
       Navigate to: https://console.cloud.google.com/storage/browser/${google_storage_bucket.meeting_recordings.name}
    
    3. Supported file formats: .wav, .mp3, .flac, .m4a
    
    4. Monitor processing:
       gcloud functions logs read ${google_cloudfunctions2_function.meeting_processor.name} --region ${var.region}
  EOT
}

output "output_locations" {
  description = "Where to find processed meeting outputs"
  value = {
    transcripts = "gs://${google_storage_bucket.meeting_recordings.name}/transcripts/"
    summaries   = "gs://${google_storage_bucket.meeting_recordings.name}/summaries/"
  }
}

output "monitoring_links" {
  description = "Links to monitoring and logging dashboards"
  value = {
    function_logs = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.meeting_processor.name}?tab=logs&project=${var.project_id}"
    cloud_storage = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.meeting_recordings.name}?project=${var.project_id}"
    monitoring    = "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}"
  }
}

output "api_endpoints" {
  description = "API endpoints and service information"
  value = {
    speech_to_text = "https://speech.googleapis.com"
    vertex_ai      = "https://${var.vertex_ai_location}-aiplatform.googleapis.com"
    cloud_storage  = "https://storage.googleapis.com"
  }
}

output "configuration_summary" {
  description = "Summary of key configuration settings"
  value = {
    environment           = var.environment
    function_memory_mb    = var.function_memory
    function_timeout_sec  = var.function_timeout
    max_instances        = var.function_max_instances
    speech_language      = var.speech_language_code
    speaker_count_range  = "${var.speaker_count_min}-${local.speaker_count_max}"
    gemini_model         = var.gemini_model
    vertex_ai_location   = var.vertex_ai_location
    lifecycle_days       = var.lifecycle_age_days
    uniform_bucket_access = var.enable_uniform_bucket_level_access
  }
}

output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = <<-EOT
    Cost Optimization Tips:
    
    1. Monitor Speech-to-Text usage in Cloud Billing
    2. Use lifecycle policies (configured: ${var.lifecycle_age_days} days)
    3. Consider batch processing for multiple files
    4. Monitor Vertex AI API usage for Gemini calls
    5. Use appropriate function memory settings (current: ${var.function_memory}MB)
    6. Review and adjust max instances based on usage patterns
    
    Current lifecycle policy: Objects deleted after ${var.lifecycle_age_days} days
  EOT
}

output "security_considerations" {
  description = "Security features and recommendations"
  value = {
    uniform_bucket_access = var.enable_uniform_bucket_level_access
    service_account_email = google_service_account.function_sa.email
    iam_roles = [
      "roles/speech.editor",
      "roles/aiplatform.user", 
      "roles/storage.objectAdmin",
      "roles/logging.logWriter"
    ]
    recommendations = [
      "Enable audit logging for Cloud Storage",
      "Use VPC Service Controls for additional security",
      "Implement bucket-level IAM policies",
      "Consider using Customer-Managed Encryption Keys (CMEK)",
      "Regularly review IAM permissions"
    ]
  }
}

output "debugging_commands" {
  description = "Useful commands for debugging and monitoring"
  value = {
    function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.meeting_processor.name} --region ${var.region} --limit 50"
    function_status = "gcloud functions describe ${google_cloudfunctions2_function.meeting_processor.name} --region ${var.region}"
    bucket_contents = "gsutil ls -la gs://${google_storage_bucket.meeting_recordings.name}/"
    test_upload = "gsutil cp test-audio.wav gs://${google_storage_bucket.meeting_recordings.name}/"
  }
}

output "cleanup_commands" {
  description = "Commands for cleaning up resources"
  value = {
    delete_bucket_contents = "gsutil -m rm -r gs://${google_storage_bucket.meeting_recordings.name}/*"
    delete_function = "gcloud functions delete ${google_cloudfunctions2_function.meeting_processor.name} --region ${var.region}"
    terraform_destroy = "terraform destroy"
  }
}