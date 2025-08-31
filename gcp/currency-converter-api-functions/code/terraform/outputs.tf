# Outputs for Currency Converter API Infrastructure
# These outputs provide important information about the deployed resources

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions_function.currency_converter.name
}

output "function_url" {
  description = "HTTPS URL for invoking the currency converter API"
  value       = google_cloudfunctions_function.currency_converter.https_trigger_url
}

output "function_region" {
  description = "Region where the Cloud Function is deployed"
  value       = google_cloudfunctions_function.currency_converter.region
}

output "function_service_account" {
  description = "Service account email used by the Cloud Function"
  value       = google_cloudfunctions_function.currency_converter.service_account_email
}

output "function_runtime" {
  description = "Runtime environment of the Cloud Function"
  value       = google_cloudfunctions_function.currency_converter.runtime
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function (MB)"
  value       = google_cloudfunctions_function.currency_converter.available_memory_mb
}

output "function_timeout" {
  description = "Timeout setting for the Cloud Function (seconds)"
  value       = google_cloudfunctions_function.currency_converter.timeout
}

output "secret_name" {
  description = "Name of the Secret Manager secret storing the API key"
  value       = google_secret_manager_secret.exchange_api_key.secret_id
}

output "secret_id" {
  description = "Full resource ID of the Secret Manager secret"
  value       = google_secret_manager_secret.exchange_api_key.id
}

output "project_id" {
  description = "Google Cloud Project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source_bucket.name
}

output "api_test_commands" {
  description = "Example curl commands for testing the deployed API"
  value = {
    get_request = "curl '${google_cloudfunctions_function.currency_converter.https_trigger_url}?from=USD&to=EUR&amount=100'"
    post_request = "curl -X POST '${google_cloudfunctions_function.currency_converter.https_trigger_url}' -H 'Content-Type: application/json' -d '{\"from\": \"GBP\", \"to\": \"JPY\", \"amount\": 50}'"
    options_request = "curl -X OPTIONS '${google_cloudfunctions_function.currency_converter.https_trigger_url}' -I"
  }
}

output "monitoring_links" {
  description = "Google Cloud Console links for monitoring the deployed resources"
  value = {
    function_logs = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.currency_converter.name}?project=${var.project_id}&tab=logs"
    function_metrics = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.currency_converter.name}?project=${var.project_id}&tab=metrics"
    secret_manager = "https://console.cloud.google.com/security/secret-manager/secret/${google_secret_manager_secret.exchange_api_key.secret_id}/versions?project=${var.project_id}"
    cloud_storage = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.function_source_bucket.name}?project=${var.project_id}"
  }
}

output "deployment_info" {
  description = "Summary information about the deployed infrastructure"
  value = {
    function_name     = google_cloudfunctions_function.currency_converter.name
    function_url      = google_cloudfunctions_function.currency_converter.https_trigger_url
    secret_name       = google_secret_manager_secret.exchange_api_key.secret_id
    project_id        = var.project_id
    region           = var.region
    public_access    = var.allow_unauthenticated
    runtime          = google_cloudfunctions_function.currency_converter.runtime
    memory_mb        = google_cloudfunctions_function.currency_converter.available_memory_mb
    timeout_seconds  = google_cloudfunctions_function.currency_converter.timeout
  }
}