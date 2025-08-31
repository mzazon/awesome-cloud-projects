# Outputs for URL Safety Validation Infrastructure
# These outputs provide important information about the deployed resources

output "function_url" {
  description = "The HTTPS trigger URL for the Cloud Function"
  value       = google_cloudfunctions_function.url_validator.https_trigger_url
  sensitive   = false
}

output "function_name" {
  description = "The name of the deployed Cloud Function"
  value       = google_cloudfunctions_function.url_validator.name
  sensitive   = false
}

output "function_region" {
  description = "The region where the Cloud Function is deployed"
  value       = google_cloudfunctions_function.url_validator.region
  sensitive   = false
}

output "audit_bucket_name" {
  description = "The name of the Cloud Storage bucket for audit logs"
  value       = google_storage_bucket.audit_logs.name
  sensitive   = false
}

output "cache_bucket_name" {
  description = "The name of the Cloud Storage bucket for caching validation results"
  value       = google_storage_bucket.cache.name
  sensitive   = false
}

output "audit_bucket_url" {
  description = "The URL of the audit logs bucket"
  value       = google_storage_bucket.audit_logs.url
  sensitive   = false
}

output "cache_bucket_url" {
  description = "The URL of the cache bucket"
  value       = google_storage_bucket.cache.url
  sensitive   = false
}

output "service_account_email" {
  description = "The email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
  sensitive   = false
}

output "service_account_id" {
  description = "The unique ID of the service account"
  value       = google_service_account.function_sa.unique_id
  sensitive   = false
}

output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
  sensitive   = false
}

output "region" {
  description = "The deployment region"
  value       = var.region
  sensitive   = false
}

output "environment" {
  description = "The deployment environment"
  value       = var.environment
  sensitive   = false
}

output "function_memory" {
  description = "The memory allocation for the Cloud Function in MB"
  value       = google_cloudfunctions_function.url_validator.available_memory_mb
  sensitive   = false
}

output "function_timeout" {
  description = "The timeout for the Cloud Function in seconds"
  value       = google_cloudfunctions_function.url_validator.timeout
  sensitive   = false
}

output "max_instances" {
  description = "The maximum number of function instances"
  value       = google_cloudfunctions_function.url_validator.max_instances
  sensitive   = false
}

output "monitoring_alert_policies" {
  description = "The monitoring alert policies created for the function"
  value = {
    error_rate_policy = google_monitoring_alert_policy.function_error_rate.name
    quota_policy      = google_monitoring_alert_policy.webrisk_quota.name
  }
  sensitive = false
}

output "log_metric_name" {
  description = "The name of the log-based metric for validation requests"
  value       = google_logging_metric.validation_requests.name
  sensitive   = false
}

output "enabled_apis" {
  description = "The Google Cloud APIs enabled for this deployment"
  value = [
    for api in google_project_service.required_apis : api.service
  ]
  sensitive = false
}

output "function_source_bucket" {
  description = "The name of the bucket storing the function source code"
  value       = google_storage_bucket.function_source.name
  sensitive   = false
}

output "cache_retention_days" {
  description = "The number of days cached results are retained"
  value       = var.cache_retention_days
  sensitive   = false
}

output "audit_log_retention_days" {
  description = "The number of days audit logs are retained (0 = indefinite)"
  value       = var.audit_log_retention_days
  sensitive   = false
}

output "public_access_enabled" {
  description = "Whether unauthenticated access to the function is enabled"
  value       = var.enable_public_access
  sensitive   = false
}

output "cors_enabled" {
  description = "Whether CORS is enabled for the function"
  value       = var.enable_cors
  sensitive   = false
}

output "allowed_origins" {
  description = "The allowed origins for CORS requests"
  value       = var.allowed_origins
  sensitive   = false
}

output "storage_class" {
  description = "The storage class used for Cloud Storage buckets"
  value       = var.storage_class
  sensitive   = false
}

output "common_labels" {
  description = "The common labels applied to all resources"
  value       = local.common_labels
  sensitive   = false
}

# Output for testing the deployed function
output "test_command" {
  description = "Sample curl command to test the deployed function"
  value = <<-EOF
    curl -X POST ${google_cloudfunctions_function.url_validator.https_trigger_url} \
      -H "Content-Type: application/json" \
      -d '{"url": "https://www.google.com", "cache": true}'
  EOF
  sensitive = false
}

# Output for viewing audit logs
output "audit_logs_command" {
  description = "Command to view audit logs in Cloud Storage"
  value       = "gsutil ls -r gs://${google_storage_bucket.audit_logs.name}/audit/"
  sensitive   = false
}

# Output for viewing cached results
output "cache_logs_command" {
  description = "Command to view cached results in Cloud Storage"
  value       = "gsutil ls -r gs://${google_storage_bucket.cache.name}/cache/"
  sensitive   = false
}

# Output for monitoring function logs
output "function_logs_command" {
  description = "Command to view Cloud Function logs"
  value = <<-EOF
    gcloud functions logs read ${google_cloudfunctions_function.url_validator.name} \
      --region=${google_cloudfunctions_function.url_validator.region} \
      --limit=50
  EOF
  sensitive = false
}