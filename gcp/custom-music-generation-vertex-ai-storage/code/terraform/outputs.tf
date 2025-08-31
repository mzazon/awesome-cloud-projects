# Outputs for Custom Music Generation with Vertex AI and Storage
# These outputs provide important information about the deployed infrastructure

# Project and Basic Information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

# Storage Bucket Information
output "input_bucket_name" {
  description = "Name of the Cloud Storage bucket for input prompts"
  value       = google_storage_bucket.input_bucket.name
}

output "input_bucket_url" {
  description = "URL of the input bucket for Cloud Storage operations"
  value       = google_storage_bucket.input_bucket.url
}

output "output_bucket_name" {
  description = "Name of the Cloud Storage bucket for generated music files"
  value       = google_storage_bucket.output_bucket.name
}

output "output_bucket_url" {
  description = "URL of the output bucket for Cloud Storage operations"
  value       = google_storage_bucket.output_bucket.url
}

# Cloud Functions Information
output "music_generator_function_name" {
  description = "Name of the music generator Cloud Function"
  value       = google_cloudfunctions2_function.music_generator.name
}

output "music_generator_function_url" {
  description = "URL of the music generator Cloud Function"
  value       = google_cloudfunctions2_function.music_generator.service_config[0].uri
}

output "music_api_function_name" {
  description = "Name of the music API Cloud Function"
  value       = google_cloudfunctions2_function.music_api.name
}

output "music_api_function_url" {
  description = "URL of the music API Cloud Function for HTTP requests"
  value       = google_cloudfunctions2_function.music_api.service_config[0].uri
}

output "music_api_endpoint" {
  description = "The HTTP endpoint URL for the music generation API"
  value       = google_cloudfunctions2_function.music_api.service_config[0].uri
}

# Service Account Information
output "function_service_account_email" {
  description = "Email of the service account used by Cloud Functions"
  value       = google_service_account.function_service_account.email
}

output "function_service_account_id" {
  description = "ID of the service account used by Cloud Functions"
  value       = google_service_account.function_service_account.unique_id
}

# IAM and Security Information
output "api_function_public_access" {
  description = "Whether the API function allows public access"
  value       = var.enable_public_access
}

output "allowed_members" {
  description = "List of members allowed to invoke the API function (when not public)"
  value       = var.enable_public_access ? [] : var.allowed_members
}

# Resource Names and Identifiers
output "resource_suffix" {
  description = "The random suffix used for resource naming"
  value       = local.random_suffix
}

output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# API Testing Information
output "api_test_command" {
  description = "Sample curl command to test the music generation API"
  value = var.enable_public_access ? format(
    "curl -X POST %s -H 'Content-Type: application/json' -d '{\"prompt\": \"Peaceful ambient sounds for focus\", \"style\": \"ambient\", \"duration_seconds\": 30}'",
    google_cloudfunctions2_function.music_api.service_config[0].uri
  ) : "API requires authentication. Use gcloud auth or service account credentials."
}

# Storage Access Commands
output "input_bucket_commands" {
  description = "Useful gsutil commands for managing the input bucket"
  value = {
    list_objects     = "gsutil ls gs://${google_storage_bucket.input_bucket.name}/"
    upload_file      = "gsutil cp local-file.json gs://${google_storage_bucket.input_bucket.name}/requests/"
    view_object      = "gsutil cat gs://${google_storage_bucket.input_bucket.name}/requests/filename.json"
    download_object  = "gsutil cp gs://${google_storage_bucket.input_bucket.name}/requests/filename.json ."
  }
}

output "output_bucket_commands" {
  description = "Useful gsutil commands for managing the output bucket"
  value = {
    list_objects     = "gsutil ls gs://${google_storage_bucket.output_bucket.name}/"
    list_audio       = "gsutil ls gs://${google_storage_bucket.output_bucket.name}/audio/"
    list_metadata    = "gsutil ls gs://${google_storage_bucket.output_bucket.name}/metadata/"
    download_audio   = "gsutil cp gs://${google_storage_bucket.output_bucket.name}/audio/filename.wav ."
    view_metadata    = "gsutil cat gs://${google_storage_bucket.output_bucket.name}/metadata/filename.json"
  }
}

# Monitoring and Logging
output "function_logs_commands" {
  description = "Commands to view Cloud Function logs"
  value = {
    generator_logs = "gcloud functions logs read ${google_cloudfunctions2_function.music_generator.name} --gen2 --region=${var.region} --limit=10"
    api_logs       = "gcloud functions logs read ${google_cloudfunctions2_function.music_api.name} --gen2 --region=${var.region} --limit=10"
    tail_logs      = "gcloud functions logs tail ${google_cloudfunctions2_function.music_generator.name} --gen2 --region=${var.region}"
  }
}

# Cost Estimation Information
output "estimated_costs" {
  description = "Estimated monthly costs for this deployment (approximate)"
  value = {
    description = "Costs vary based on usage. Estimates for moderate usage:"
    storage     = "~$1-5/month for storage (depends on data volume and retention)"
    functions   = "~$5-15/month for Cloud Functions (depends on requests and execution time)"
    vertex_ai   = "~$10-50/month for Vertex AI (depends on generation frequency)"
    total       = "~$16-70/month total (highly dependent on usage patterns)"
    note        = "Enable budget alerts in Google Cloud Console to monitor actual costs"
  }
}

# Vertex AI Information
output "vertex_ai_model_info" {
  description = "Information about the Vertex AI model being used"
  value = {
    model_name    = "lyria-002"
    model_family  = "Lyria 2"
    capabilities  = "High-fidelity music generation from text prompts"
    max_duration  = "30 seconds per request"
    supported_formats = "WAV, 48kHz sample rate"
    pricing_note  = "Vertex AI charges per inference request - monitor usage in Cloud Console"
  }
}

# Next Steps and Usage Instructions
output "next_steps" {
  description = "Next steps after deployment"
  value = {
    step1 = "Test the API endpoint using the provided curl command"
    step2 = "Check Cloud Function logs to verify successful deployment"
    step3 = "Upload test JSON files to the input bucket to trigger music generation"
    step4 = "Monitor generated outputs in the output bucket under audio/ and metadata/ folders"
    step5 = "Set up monitoring and alerting in Google Cloud Console"
    step6 = "Configure custom domain and SSL if needed for production use"
  }
}

# Cleanup Instructions
output "cleanup_instructions" {
  description = "Instructions for cleaning up resources"
  value = {
    terraform_destroy = "Run 'terraform destroy' to remove all resources"
    manual_cleanup    = "Manually verify all storage objects are deleted if needed"
    cost_monitoring   = "Check final billing to ensure all charges have stopped"
    logs_retention    = "Cloud Function logs may persist beyond resource deletion"
  }
}