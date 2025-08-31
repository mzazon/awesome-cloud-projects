# outputs.tf - Output values for the hash generator API infrastructure

output "function_name" {
  description = "The name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.hash_generator.name
}

output "function_url" {
  description = "The HTTPS URL of the Cloud Function for API calls"
  value       = google_cloudfunctions2_function.hash_generator.service_config[0].uri
}

output "function_location" {
  description = "The region where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.hash_generator.location
}

output "function_id" {
  description = "The unique identifier of the Cloud Function"
  value       = google_cloudfunctions2_function.hash_generator.id
}

output "project_id" {
  description = "The Google Cloud Project ID where resources are deployed"
  value       = var.project_id
}

output "project_number" {
  description = "The Google Cloud Project number"
  value       = data.google_project.current.number
}

output "service_account_email" {
  description = "The email address of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "service_account_id" {
  description = "The unique ID of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.unique_id
}

output "storage_bucket_name" {
  description = "The name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_bucket.name
}

output "storage_bucket_url" {
  description = "The URL of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_bucket.url
}

output "function_runtime" {
  description = "The runtime environment of the Cloud Function"
  value       = google_cloudfunctions2_function.hash_generator.build_config[0].runtime
}

output "function_memory" {
  description = "The amount of memory allocated to the Cloud Function"
  value       = google_cloudfunctions2_function.hash_generator.service_config[0].available_memory
}

output "function_timeout" {
  description = "The timeout duration of the Cloud Function in seconds"
  value       = google_cloudfunctions2_function.hash_generator.service_config[0].timeout_seconds
}

output "function_max_instances" {
  description = "The maximum number of function instances that can run simultaneously"
  value       = google_cloudfunctions2_function.hash_generator.service_config[0].max_instance_count
}

output "function_min_instances" {
  description = "The minimum number of function instances to keep warm"
  value       = google_cloudfunctions2_function.hash_generator.service_config[0].min_instance_count
}

output "enabled_apis" {
  description = "List of Google Cloud APIs that were enabled for this deployment"
  value = [
    google_project_service.cloudfunctions_api.service,
    google_project_service.cloudbuild_api.service,
    google_project_service.logging_api.service,
    google_project_service.monitoring_api.service
  ]
}

output "random_suffix" {
  description = "The random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "function_source_hash" {
  description = "MD5 hash of the function source code archive"
  value       = data.archive_file.function_source.output_md5
}

output "curl_test_command" {
  description = "Example curl command to test the deployed function"
  value = <<-EOT
    curl -X POST ${google_cloudfunctions2_function.hash_generator.service_config[0].uri} \
         -H "Content-Type: application/json" \
         -d '{"text": "Hello, World!"}'
  EOT
}

output "gcloud_logs_command" {
  description = "Command to view function logs using gcloud CLI"
  value = "gcloud functions logs read ${google_cloudfunctions2_function.hash_generator.name} --region=${var.region} --limit=10"
}

output "monitoring_alert_policy_id" {
  description = "The ID of the monitoring alert policy (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_error_rate[0].name : null
}

output "logging_sink_id" {
  description = "The ID of the logging sink (if enabled)"
  value       = var.enable_logging ? google_logging_project_sink.function_logs[0].id : null
}

output "deployment_info" {
  description = "Summary of deployed resources and configuration"
  value = {
    function_name     = google_cloudfunctions2_function.hash_generator.name
    function_url      = google_cloudfunctions2_function.hash_generator.service_config[0].uri
    project_id        = var.project_id
    region           = var.region
    runtime          = var.runtime
    memory_mb        = var.memory_mb
    timeout_seconds  = var.timeout_seconds
    max_instances    = var.max_instances
    min_instances    = var.min_instances
    public_access    = var.allow_unauthenticated
    monitoring       = var.enable_monitoring
    logging          = var.enable_logging
  }
}