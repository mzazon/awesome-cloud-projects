# Outputs for Interview Practice Assistant Infrastructure
# These outputs provide important information about the deployed resources

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for audio files"
  value       = google_storage_bucket.audio_bucket.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.audio_bucket.url
}

output "storage_bucket_self_link" {
  description = "Self link of the Cloud Storage bucket"
  value       = google_storage_bucket.audio_bucket.self_link
}

output "service_account_email" {
  description = "Email address of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.email
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.function_sa.unique_id
}

# Cloud Function outputs
output "speech_function_name" {
  description = "Name of the Speech-to-Text Cloud Function"
  value       = google_cloudfunctions_function.speech_function.name
}

output "speech_function_url" {
  description = "HTTP trigger URL for the Speech-to-Text function"
  value       = google_cloudfunctions_function.speech_function.https_trigger_url
}

output "speech_function_source_archive" {
  description = "Source archive location for the Speech-to-Text function"
  value       = "gs://${google_storage_bucket.audio_bucket.name}/${google_storage_bucket_object.speech_function_source.name}"
}

output "analysis_function_name" {
  description = "Name of the Gemini Analysis Cloud Function"
  value       = google_cloudfunctions_function.analysis_function.name
}

output "analysis_function_url" {
  description = "HTTP trigger URL for the Gemini Analysis function"
  value       = google_cloudfunctions_function.analysis_function.https_trigger_url
}

output "analysis_function_source_archive" {
  description = "Source archive location for the Analysis function"
  value       = "gs://${google_storage_bucket.audio_bucket.name}/${google_storage_bucket_object.analysis_function_source.name}"
}

output "orchestration_function_name" {
  description = "Name of the Orchestration Cloud Function"
  value       = google_cloudfunctions_function.orchestration_function.name
}

output "orchestration_function_url" {
  description = "HTTP trigger URL for the Orchestration function (main entry point)"
  value       = google_cloudfunctions_function.orchestration_function.https_trigger_url
  sensitive   = false
}

output "orchestration_function_source_archive" {
  description = "Source archive location for the Orchestration function"
  value       = "gs://${google_storage_bucket.audio_bucket.name}/${google_storage_bucket_object.orchestration_function_source.name}"
}

# Configuration outputs
output "gemini_model" {
  description = "Vertex AI Gemini model being used for analysis"
  value       = var.gemini_model
}

output "speech_model" {
  description = "Speech-to-Text model being used for transcription"
  value       = var.speech_model
}

output "speech_language_code" {
  description = "Language code for Speech-to-Text processing"
  value       = var.speech_language_code
}

output "bucket_lifecycle_days" {
  description = "Number of days after which bucket objects are deleted"
  value       = var.bucket_lifecycle_age_days
}

# Sample data outputs
output "sample_questions_available" {
  description = "Whether sample interview questions were created"
  value       = var.create_sample_data
}

output "sample_questions_location" {
  description = "Location of sample interview questions (if created)"
  value       = var.create_sample_data ? "gs://${google_storage_bucket.audio_bucket.name}/interview_questions.json" : "Not created"
}

# Security outputs
output "functions_allow_unauthenticated" {
  description = "Whether Cloud Functions allow unauthenticated access"
  value       = var.allow_unauthenticated_functions
}

output "required_iam_roles" {
  description = "IAM roles granted to the service account"
  value = [
    "roles/speech.client",
    "roles/aiplatform.user", 
    "roles/storage.objectAdmin"
  ]
}

# Testing and integration outputs
output "test_curl_commands" {
  description = "Sample curl commands for testing the functions"
  value = {
    speech_function = "curl -X POST ${google_cloudfunctions_function.speech_function.https_trigger_url} -H 'Content-Type: application/json' -d '{\"bucket\":\"${google_storage_bucket.audio_bucket.name}\",\"file\":\"test_audio.wav\"}'"
    
    analysis_function = "curl -X POST ${google_cloudfunctions_function.analysis_function.https_trigger_url} -H 'Content-Type: application/json' -d '{\"transcription\":\"I am a software engineer with five years of experience.\",\"question\":\"Tell me about yourself\",\"confidence\":0.95}'"
    
    orchestration_function = "curl -X POST ${google_cloudfunctions_function.orchestration_function.https_trigger_url} -H 'Content-Type: application/json' -d '{\"bucket\":\"${google_storage_bucket.audio_bucket.name}\",\"file\":\"test_audio.wav\",\"question\":\"Tell me about yourself\"}'"
  }
}

output "gsutil_upload_example" {
  description = "Example gsutil command to upload audio files"
  value       = "gsutil cp your_audio_file.wav gs://${google_storage_bucket.audio_bucket.name}/"
}

output "function_logs_commands" {
  description = "Commands to view Cloud Function logs"
  value = {
    speech_function = "gcloud functions logs read ${google_cloudfunctions_function.speech_function.name} --region=${var.region}"
    analysis_function = "gcloud functions logs read ${google_cloudfunctions_function.analysis_function.name} --region=${var.region}"
    orchestration_function = "gcloud functions logs read ${google_cloudfunctions_function.orchestration_function.name} --region=${var.region}"
  }
}

# Cost monitoring outputs
output "estimated_monthly_cost_info" {
  description = "Information about estimated monthly costs"
  value = {
    note = "Costs depend on usage. This solution uses pay-per-use pricing."
    components = [
      "Cloud Functions: $0.40 per 1M invocations + $0.0000025 per GB-second",
      "Cloud Storage: $0.026 per GB per month (Standard class)",
      "Speech-to-Text: $0.024 per minute (enhanced models)",
      "Vertex AI Gemini: Variable pricing based on tokens processed"
    ]
    optimization_tips = [
      "Use lifecycle policies to automatically delete old audio files",
      "Monitor function execution times to optimize memory allocation",
      "Consider using Gemini Flash model for cost optimization",
      "Implement caching for frequently used interview questions"
    ]
  }
}

# Deployment validation outputs
output "deployment_status" {
  description = "Status of key deployment components"
  value = {
    apis_enabled = var.enable_apis
    bucket_created = true
    service_account_created = true
    functions_deployed = 3
    iam_configured = true
    sample_data_created = var.create_sample_data
  }
}

# Next steps guidance
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test the analysis function first using the provided curl command",
    "2. Upload a sample audio file to test the complete workflow",
    "3. Review Cloud Function logs for any issues",
    "4. Set up monitoring and alerting for production use",
    "5. Configure authentication if removing unauthenticated access",
    "6. Consider implementing a frontend application"
  ]
}