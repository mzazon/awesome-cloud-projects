# Output values for basic application logging with Cloud Functions infrastructure
# These outputs provide essential information for testing and integration

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "function_name" {
  description = "The name of the deployed Cloud Function"
  value       = google_cloudfunctions_function.logging_demo.name
}

output "function_url" {
  description = "The HTTPS trigger URL for the Cloud Function"
  value       = google_cloudfunctions_function.logging_demo.https_trigger_url
}

output "function_status" {
  description = "The current status of the Cloud Function"
  value       = google_cloudfunctions_function.logging_demo.status
}

output "function_runtime" {
  description = "The runtime environment of the Cloud Function"
  value       = google_cloudfunctions_function.logging_demo.runtime
}

output "function_memory" {
  description = "The memory allocation for the Cloud Function in MB"
  value       = google_cloudfunctions_function.logging_demo.available_memory_mb
}

output "function_timeout" {
  description = "The timeout setting for the Cloud Function in seconds"
  value       = google_cloudfunctions_function.logging_demo.timeout
}

output "storage_bucket_name" {
  description = "The name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "storage_bucket_url" {
  description = "The URL of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.url
}

output "log_sink_name" {
  description = "The name of the log sink for structured function logs"
  value       = google_logging_project_sink.function_logs.name
}

output "log_sink_destination" {
  description = "The destination for the log sink"
  value       = google_logging_project_sink.function_logs.destination
}

output "log_sink_writer_identity" {
  description = "The writer identity for the log sink"
  value       = google_logging_project_sink.function_logs.writer_identity
}

output "log_metric_name" {
  description = "The name of the log-based metric for function invocations"
  value       = google_logging_metric.function_invocations.name
}

output "enabled_apis" {
  description = "List of Google Cloud APIs that were enabled"
  value = compact([
    var.enable_functions ? "cloudfunctions.googleapis.com" : "",
    var.enable_logging ? "logging.googleapis.com" : "",
    var.enable_cloudbuild ? "cloudbuild.googleapis.com" : ""
  ])
}

output "resource_labels" {
  description = "Labels applied to all resources"
  value       = var.labels
}

# Testing and validation outputs
output "test_commands" {
  description = "Commands to test the deployed Cloud Function"
  value = {
    basic_test = "curl -s '${google_cloudfunctions_function.logging_demo.https_trigger_url}'"
    test_mode  = "curl -s '${google_cloudfunctions_function.logging_demo.https_trigger_url}?mode=test'"
    json_test  = "curl -s '${google_cloudfunctions_function.logging_demo.https_trigger_url}' | jq"
  }
}

output "log_query_commands" {
  description = "Commands to query structured logs from the function"
  value = {
    all_logs = "gcloud logging read \"resource.type=\\\"cloud_function\\\" AND resource.labels.function_name=\\\"${google_cloudfunctions_function.logging_demo.name}\\\"\" --limit=10"
    start_events = "gcloud logging read \"resource.type=\\\"cloud_function\\\" AND jsonPayload.event_type=\\\"function_start\\\"\" --limit=5"
    component_logs = "gcloud logging read \"resource.type=\\\"cloud_function\\\" AND jsonPayload.component=\\\"log-demo-function\\\"\" --limit=5"
  }
}

output "monitoring_links" {
  description = "Direct links to Google Cloud Console for monitoring"
  value = {
    function_details = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.logging_demo.name}?project=${var.project_id}"
    logs_explorer    = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
    monitoring       = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
  }
}