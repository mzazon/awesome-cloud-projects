# Outputs for the Website Status Monitor Cloud Function

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.website_monitor.name
}

output "function_url" {
  description = "HTTP trigger URL for the Cloud Function"
  value       = google_cloudfunctions2_function.website_monitor.service_config[0].uri
}

output "function_region" {
  description = "Region where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.website_monitor.location
}

output "function_status" {
  description = "Current status of the Cloud Function"
  value       = google_cloudfunctions2_function.website_monitor.state
}

output "function_runtime" {
  description = "Runtime environment of the Cloud Function"
  value       = google_cloudfunctions2_function.website_monitor.build_config[0].runtime
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function"
  value       = google_cloudfunctions2_function.website_monitor.service_config[0].available_memory
}

output "function_timeout" {
  description = "Timeout setting for the Cloud Function"
  value       = google_cloudfunctions2_function.website_monitor.service_config[0].timeout_seconds
}

output "function_max_instances" {
  description = "Maximum number of function instances"
  value       = google_cloudfunctions2_function.website_monitor.service_config[0].max_instance_count
}

output "function_min_instances" {
  description = "Minimum number of function instances"
  value       = google_cloudfunctions2_function.website_monitor.service_config[0].min_instance_count
}

output "source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "source_bucket_url" {
  description = "URL of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.url
}

output "project_id" {
  description = "GCP Project ID where resources are deployed"
  value       = var.project_id
}

output "project_number" {
  description = "GCP Project Number"
  value       = data.google_project.current.number
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value = [
    google_project_service.cloud_functions_api.service,
    google_project_service.cloud_build_api.service,
    google_project_service.cloud_run_api.service,
    google_project_service.logging_api.service,
    google_project_service.monitoring_api.service
  ]
}

output "curl_test_commands" {
  description = "Example curl commands to test the deployed function"
  value = {
    get_request = "curl '${google_cloudfunctions2_function.website_monitor.service_config[0].uri}?url=https://www.google.com'"
    post_request = "curl -X POST '${google_cloudfunctions2_function.website_monitor.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"url\": \"https://httpbin.org/status/200\"}'"
    error_test = "curl '${google_cloudfunctions2_function.website_monitor.service_config[0].uri}?url=https://httpbin.org/status/500'"
    timeout_test = "curl '${google_cloudfunctions2_function.website_monitor.service_config[0].uri}?url=https://httpbin.org/delay/2'"
  }
}

output "monitoring_resources" {
  description = "Monitoring and logging resources created"
  value = {
    log_sink_name = var.enable_logging ? google_logging_project_sink.function_logs[0].name : null
    alert_policy_name = var.enable_logging ? google_monitoring_alert_policy.function_error_rate[0].display_name : null
  }
}

output "function_labels" {
  description = "Labels applied to the Cloud Function"
  value       = google_cloudfunctions2_function.website_monitor.labels
}

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    function_name = google_cloudfunctions2_function.website_monitor.name
    function_url = google_cloudfunctions2_function.website_monitor.service_config[0].uri
    region = google_cloudfunctions2_function.website_monitor.location
    runtime = google_cloudfunctions2_function.website_monitor.build_config[0].runtime
    memory = google_cloudfunctions2_function.website_monitor.service_config[0].available_memory
    timeout = google_cloudfunctions2_function.website_monitor.service_config[0].timeout_seconds
    public_access = var.enable_unauthenticated_access
    logging_enabled = var.enable_logging
  }
}