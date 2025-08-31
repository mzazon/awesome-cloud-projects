# Primary outputs for the visitor counter infrastructure

output "function_url" {
  description = "The HTTPS URL endpoint for the visitor counter Cloud Function"
  value       = google_cloudfunctions2_function.visitor_counter.service_config[0].uri
  sensitive   = false
}

output "function_name" {
  description = "The full name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.visitor_counter.name
  sensitive   = false
}

output "function_id" {
  description = "The unique identifier of the Cloud Function"
  value       = google_cloudfunctions2_function.visitor_counter.id
  sensitive   = false
}

# Project and location information
output "project_id" {
  description = "The Google Cloud Project ID where resources were deployed"
  value       = var.project_id
  sensitive   = false
}

output "region" {
  description = "The Google Cloud region where the function is deployed"
  value       = var.region
  sensitive   = false
}

# Firestore database information
output "firestore_database_name" {
  description = "The name of the Firestore database"
  value       = google_firestore_database.visitor_counter_db.name
  sensitive   = false
}

output "firestore_database_id" {
  description = "The unique identifier of the Firestore database"
  value       = google_firestore_database.visitor_counter_db.id
  sensitive   = false
}

output "firestore_location" {
  description = "The location of the Firestore database"
  value       = google_firestore_database.visitor_counter_db.location_id
  sensitive   = false
}

# Service account information
output "function_service_account_email" {
  description = "The email address of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
  sensitive   = false
}

output "function_service_account_id" {
  description = "The unique identifier of the function's service account"
  value       = google_service_account.function_sa.unique_id
  sensitive   = false
}

# Storage bucket information
output "function_source_bucket" {
  description = "The name of the storage bucket containing the function source code"
  value       = google_storage_bucket.function_bucket.name
  sensitive   = false
}

output "function_source_bucket_url" {
  description = "The storage bucket URL containing the function source code"
  value       = google_storage_bucket.function_bucket.url
  sensitive   = false
}

# Testing and validation outputs
output "test_commands" {
  description = "Example commands to test the deployed visitor counter function"
  value = {
    curl_default_page = "curl -s ${google_cloudfunctions2_function.visitor_counter.service_config[0].uri}"
    curl_specific_page = "curl -s '${google_cloudfunctions2_function.visitor_counter.service_config[0].uri}?page=home'"
    curl_post_request = "curl -X POST -H 'Content-Type: application/json' -d '{\"page\": \"api-test\"}' ${google_cloudfunctions2_function.visitor_counter.service_config[0].uri}"
  }
  sensitive = false
}

# Resource naming information
output "resource_suffix" {
  description = "The random suffix used for unique resource naming"
  value       = local.resource_suffix
  sensitive   = false
}

output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
  sensitive   = false
}

# Function configuration details
output "function_runtime" {
  description = "The runtime environment of the Cloud Function"
  value       = var.function_runtime
  sensitive   = false
}

output "function_memory" {
  description = "The memory allocation for the Cloud Function (in MB)"
  value       = var.function_memory
  sensitive   = false
}

output "function_timeout" {
  description = "The timeout configuration for the Cloud Function (in seconds)"
  value       = var.function_timeout
  sensitive   = false
}

# Security and access information
output "function_allows_unauthenticated" {
  description = "Whether the function allows unauthenticated access"
  value       = var.allow_unauthenticated
  sensitive   = false
}

output "enabled_apis" {
  description = "List of Google Cloud APIs that were enabled for this deployment"
  value       = var.apis_to_enable
  sensitive   = false
}

# Monitoring and debugging information
output "gcloud_logs_command" {
  description = "Command to view Cloud Function logs using gcloud CLI"
  value       = "gcloud functions logs tail ${google_cloudfunctions2_function.visitor_counter.name} --region=${var.region}"
  sensitive   = false
}

output "gcloud_describe_command" {
  description = "Command to describe the Cloud Function using gcloud CLI"
  value       = "gcloud functions describe ${google_cloudfunctions2_function.visitor_counter.name} --region=${var.region}"
  sensitive   = false
}

output "firestore_query_command" {
  description = "Command to query Firestore counters collection using gcloud CLI"
  value       = "gcloud firestore documents list --collection-path=counters --format='table(name,createTime,updateTime)'"
  sensitive   = false
}

# Cleanup information
output "cleanup_commands" {
  description = "Commands to manually clean up resources if needed"
  value = {
    delete_function = "gcloud functions delete ${google_cloudfunctions2_function.visitor_counter.name} --region=${var.region} --quiet"
    delete_firestore = "gcloud firestore databases delete --database='(default)' --quiet"
    delete_bucket = "gsutil -m rm -r gs://${google_storage_bucket.function_bucket.name}"
    delete_service_account = "gcloud iam service-accounts delete ${google_service_account.function_sa.email} --quiet"
  }
  sensitive = false
}