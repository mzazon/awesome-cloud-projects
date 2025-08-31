# Output values for the Timezone Converter API Cloud Function
# These outputs provide important information about the deployed resources

output "function_name" {
  description = "The name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.timezone_converter.name
}

output "function_uri" {
  description = "The HTTPS URI for invoking the Cloud Function"
  value       = google_cloudfunctions2_function.timezone_converter.service_config[0].uri
  sensitive   = false
}

output "function_url" {
  description = "The complete URL for the Cloud Function (alias for function_uri)"
  value       = google_cloudfunctions2_function.timezone_converter.service_config[0].uri
}

output "function_id" {
  description = "The fully qualified name of the Cloud Function"
  value       = google_cloudfunctions2_function.timezone_converter.id
}

output "function_region" {
  description = "The region where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.timezone_converter.location
}

output "function_runtime" {
  description = "The runtime environment of the Cloud Function"
  value       = google_cloudfunctions2_function.timezone_converter.build_config[0].runtime
}

output "function_entry_point" {
  description = "The entry point function name"
  value       = google_cloudfunctions2_function.timezone_converter.build_config[0].entry_point
}

output "function_memory" {
  description = "The memory allocation for the Cloud Function"
  value       = google_cloudfunctions2_function.timezone_converter.service_config[0].available_memory
}

output "function_timeout" {
  description = "The timeout configuration for the Cloud Function (in seconds)"
  value       = google_cloudfunctions2_function.timezone_converter.service_config[0].timeout_seconds
}

output "function_max_instances" {
  description = "The maximum number of instances for the Cloud Function"
  value       = google_cloudfunctions2_function.timezone_converter.service_config[0].max_instance_count
}

output "function_min_instances" {
  description = "The minimum number of instances for the Cloud Function"
  value       = google_cloudfunctions2_function.timezone_converter.service_config[0].min_instance_count
}

output "storage_bucket_name" {
  description = "The name of the Cloud Storage bucket used for function source code"
  value       = google_storage_bucket.function_source.name
}

output "storage_bucket_url" {
  description = "The URL of the Cloud Storage bucket"
  value       = google_storage_bucket.function_source.url
}

output "function_labels" {
  description = "The labels applied to the Cloud Function"
  value       = google_cloudfunctions2_function.timezone_converter.labels
}

output "project_id" {
  description = "The GCP project ID where resources are deployed"
  value       = var.project_id
}

output "deployment_id" {
  description = "The unique deployment identifier"
  value       = random_id.suffix.hex
}

output "function_service_account" {
  description = "The service account email used by the Cloud Function"
  value       = google_cloudfunctions2_function.timezone_converter.service_config[0].service_account_email
}

output "log_metric_name" {
  description = "The name of the Cloud Logging metric for monitoring requests"
  value       = google_logging_metric.function_requests.name
}

output "alert_policy_name" {
  description = "The name of the monitoring alert policy for function errors"
  value       = google_monitoring_alert_policy.function_error_rate.display_name
}

# Example usage outputs for testing the deployed function
output "curl_examples" {
  description = "Example curl commands for testing the deployed function"
  value = {
    get_request = "curl \"${google_cloudfunctions2_function.timezone_converter.service_config[0].uri}?timestamp=2024-06-15T14:30:00&from_timezone=America/Los_Angeles&to_timezone=Asia/Tokyo\""
    
    post_request = "curl -X POST \"${google_cloudfunctions2_function.timezone_converter.service_config[0].uri}\" -H \"Content-Type: application/json\" -d '{\"timestamp\": \"2024-12-25T12:00:00\", \"from_timezone\": \"UTC\", \"to_timezone\": \"Australia/Sydney\"}'"
    
    current_time = "curl \"${google_cloudfunctions2_function.timezone_converter.service_config[0].uri}?from_timezone=UTC&to_timezone=America/New_York\""
    
    error_test = "curl \"${google_cloudfunctions2_function.timezone_converter.service_config[0].uri}?from_timezone=Invalid/Zone&to_timezone=UTC\""
  }
}

# Terraform state information
output "terraform_workspace" {
  description = "The Terraform workspace used for this deployment"
  value       = terraform.workspace
}

output "deployment_timestamp" {
  description = "Timestamp of when this configuration was applied"
  value       = timestamp()
}