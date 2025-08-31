# Outputs for Location-Aware Content Generation with Gemini and Maps Infrastructure
# This file defines all output values that will be displayed after successful deployment

# Project and Location Information
output "project_id" {
  description = "Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources were deployed"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone configuration"
  value       = var.zone
}

# Cloud Function Outputs
output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.content_generator.name
}

output "function_url" {
  description = "HTTP trigger URL for the Cloud Function"
  value       = google_cloudfunctions2_function.content_generator.service_config[0].uri
  sensitive   = false
}

output "function_status" {
  description = "Current status of the Cloud Function"
  value       = google_cloudfunctions2_function.content_generator.state
}

output "function_runtime" {
  description = "Runtime environment of the Cloud Function"
  value       = google_cloudfunctions2_function.content_generator.build_config[0].runtime
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function"
  value       = google_cloudfunctions2_function.content_generator.service_config[0].memory
}

output "function_timeout" {
  description = "Timeout configuration for the Cloud Function"
  value       = "${google_cloudfunctions2_function.content_generator.service_config[0].timeout_seconds}s"
}

# Service Account Outputs
output "service_account_email" {
  description = "Email address of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "service_account_name" {
  description = "Full name of the service account"
  value       = google_service_account.function_sa.name
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.function_sa.unique_id
}

# Cloud Storage Outputs
output "content_bucket_name" {
  description = "Name of the Cloud Storage bucket for generated content"
  value       = google_storage_bucket.content_bucket.name
}

output "content_bucket_url" {
  description = "URL of the Cloud Storage bucket for generated content"
  value       = google_storage_bucket.content_bucket.url
}

output "content_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.content_bucket.location
}

output "logs_bucket_name" {
  description = "Name of the Cloud Storage bucket for function logs"
  value       = google_storage_bucket.function_logs.name
}

output "logs_bucket_url" {
  description = "URL of the Cloud Storage bucket for function logs"
  value       = google_storage_bucket.function_logs.url
}

# API Configuration Outputs
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this project"
  value       = local.required_apis
}

output "vertex_ai_region" {
  description = "Region configured for Vertex AI services"
  value       = var.region
}

# Security and Access Outputs
output "public_access_enabled" {
  description = "Whether public access is enabled for the Cloud Function"
  value       = var.allow_unauthenticated
}

output "service_account_roles" {
  description = "IAM roles assigned to the service account"
  value       = local.service_account_roles
}

# Resource Identification Outputs
output "resource_labels" {
  description = "Labels applied to resources for identification and management"
  value       = var.labels
}

output "random_suffix" {
  description = "Random suffix used for globally unique resource names"
  value       = random_id.suffix.hex
}

# Testing and Validation Outputs
output "curl_test_command" {
  description = "Sample curl command to test the deployed function"
  value = <<-EOT
    curl -X POST '${google_cloudfunctions2_function.content_generator.service_config[0].uri}' \
      -H 'Content-Type: application/json' \
      -d '{
        "location": "Golden Gate Bridge, San Francisco",
        "content_type": "travel",
        "audience": "photographers"
      }'
  EOT
}

output "gcloud_function_info_command" {
  description = "Command to get detailed function information"
  value = "gcloud functions describe ${google_cloudfunctions2_function.content_generator.name} --region=${var.region} --gen2"
}

output "gsutil_list_content_command" {
  description = "Command to list generated content in Cloud Storage"
  value = "gsutil ls -la gs://${google_storage_bucket.content_bucket.name}/content/"
}

# Cost and Usage Monitoring Outputs
output "monitoring_dashboard_url" {
  description = "URL to view function metrics in Google Cloud Console"
  value = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.content_generator.name}?project=${var.project_id}"
}

output "storage_usage_command" {
  description = "Command to check storage usage and costs"
  value = "gsutil du -sh gs://${google_storage_bucket.content_bucket.name}"
}

# Development and Debugging Outputs
output "function_logs_command" {
  description = "Command to view function logs"
  value = "gcloud functions logs read ${google_cloudfunctions2_function.content_generator.name} --region=${var.region} --gen2 --limit=50"
}

output "function_source_location" {
  description = "Location of the function source code in Cloud Storage"
  value = "gs://${google_storage_bucket.content_bucket.name}/${google_storage_bucket_object.function_source.name}"
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    function_name    = google_cloudfunctions2_function.content_generator.name
    function_url     = google_cloudfunctions2_function.content_generator.service_config[0].uri
    content_bucket   = google_storage_bucket.content_bucket.name
    logs_bucket      = google_storage_bucket.function_logs.name
    service_account  = google_service_account.function_sa.email
    project_id       = var.project_id
    region          = var.region
  }
}