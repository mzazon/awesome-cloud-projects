# Output values for GCP smart document summarization infrastructure
# These outputs provide important information for verification and integration

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where regional resources were created"
  value       = var.region
}

output "bucket_name" {
  description = "Name of the Cloud Storage bucket for document processing"
  value       = google_storage_bucket.document_bucket.name
}

output "bucket_url" {
  description = "Full URL of the Cloud Storage bucket"
  value       = "gs://${google_storage_bucket.document_bucket.name}"
}

output "bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.document_bucket.self_link
}

output "function_name" {
  description = "Name of the Cloud Function for document processing"
  value       = google_cloudfunctions2_function.document_processor.name
}

output "function_url" {
  description = "HTTP trigger URL of the Cloud Function"
  value       = google_cloudfunctions2_function.document_processor.service_config[0].uri
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "function_trigger_region" {
  description = "Region where the function trigger is configured"
  value       = google_cloudfunctions2_function.document_processor.event_trigger[0].trigger_region
}

output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = [for api in google_project_service.required_apis : api.service]
}

output "vertex_ai_location" {
  description = "Location configured for Vertex AI services"
  value       = var.vertex_ai_location
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

output "monitoring_alert_policy_name" {
  description = "Name of the Cloud Monitoring alert policy for function errors"
  value       = google_monitoring_alert_policy.function_errors.name
}

output "logging_sink_name" {
  description = "Name of the Cloud Logging sink for function logs"
  value       = google_logging_project_sink.function_logs.name
}

# Test commands for validation
output "test_upload_command" {
  description = "Command to test document upload to the bucket"
  value       = "gsutil cp your-document.txt gs://${google_storage_bucket.document_bucket.name}/"
}

output "test_list_summaries_command" {
  description = "Command to list generated summaries"
  value       = "gsutil ls gs://${google_storage_bucket.document_bucket.name}/*_summary.txt"
}

output "function_logs_command" {
  description = "Command to view Cloud Function logs"
  value       = "gcloud functions logs read ${google_cloudfunctions2_function.document_processor.name} --region=${var.region} --gen2 --limit=20"
}

# Resource URLs for the Google Cloud Console
output "console_urls" {
  description = "Google Cloud Console URLs for created resources"
  value = {
    bucket = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.document_bucket.name}?project=${var.project_id}"
    function = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.document_processor.name}?project=${var.project_id}"
    vertex_ai = "https://console.cloud.google.com/vertex-ai?project=${var.project_id}"
    monitoring = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    logs = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
  }
}

# Cost estimation information
output "cost_estimate_info" {
  description = "Information about potential costs for the deployed resources"
  value = {
    storage_cost = "Cloud Storage: ~$0.023/GB/month for STANDARD class"
    function_cost = "Cloud Functions: ~$0.0000004/invocation + ~$0.0000025/GB-second"
    vertex_ai_cost = "Vertex AI Gemini: Variable based on token usage"
    note = "Costs vary based on usage. Monitor through Cloud Billing console."
  }
}

# Security and access information
output "security_info" {
  description = "Security configuration summary"
  value = {
    bucket_access = "Uniform bucket-level access enabled"
    function_service_account = google_service_account.function_sa.email
    iam_roles = ["aiplatform.user", "storage.objectAdmin", "logging.logWriter", "monitoring.metricWriter"]
    function_ingress = "Internal only"
  }
}