# Outputs for GCP Unit Converter API Infrastructure
# This file defines all output values that will be displayed after deployment

output "function_url" {
  description = "HTTPS URL for the deployed Cloud Function API endpoint"
  value       = google_cloudfunctions_function.unit_converter.https_trigger_url
  sensitive   = false
}

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions_function.unit_converter.name
  sensitive   = false
}

output "function_region" {
  description = "Google Cloud region where the function is deployed"
  value       = google_cloudfunctions_function.unit_converter.region
  sensitive   = false
}

output "function_status" {
  description = "Current status of the Cloud Function deployment"
  value       = google_cloudfunctions_function.unit_converter.status
  sensitive   = false
}

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for conversion history"
  value       = google_storage_bucket.conversion_history.name
  sensitive   = false
}

output "storage_bucket_url" {
  description = "Full URL of the Cloud Storage bucket"
  value       = google_storage_bucket.conversion_history.url
  sensitive   = false
}

output "storage_bucket_location" {
  description = "Location/region of the Cloud Storage bucket"
  value       = google_storage_bucket.conversion_history.location
  sensitive   = false
}

output "storage_bucket_storage_class" {
  description = "Storage class of the Cloud Storage bucket"
  value       = google_storage_bucket.conversion_history.storage_class
  sensitive   = false
}

output "service_account_email" {
  description = "Email address of the Cloud Function service account"
  value       = google_service_account.function_service_account.email
  sensitive   = false
}

output "service_account_unique_id" {
  description = "Unique ID of the Cloud Function service account"
  value       = google_service_account.function_service_account.unique_id
  sensitive   = false
}

output "project_id" {
  description = "Google Cloud Project ID where resources are deployed"
  value       = var.project_id
  sensitive   = false
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
  sensitive   = false
}

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value = [
    for api in google_project_service.required_apis : api.service
  ]
  sensitive = false
}

output "function_runtime" {
  description = "Python runtime version used by the Cloud Function"
  value       = google_cloudfunctions_function.unit_converter.runtime
  sensitive   = false
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  value       = google_cloudfunctions_function.unit_converter.available_memory_mb
  sensitive   = false
}

output "function_timeout" {
  description = "Timeout setting for the Cloud Function in seconds"
  value       = google_cloudfunctions_function.unit_converter.timeout
  sensitive   = false
}

output "function_source_archive" {
  description = "Cloud Storage object containing the function source code"
  value       = google_storage_bucket_object.function_source.name
  sensitive   = false
}

output "logging_sink_name" {
  description = "Name of the Cloud Logging sink for function logs"
  value       = google_logging_project_sink.function_logs.name
  sensitive   = false
}

output "deployment_labels" {
  description = "Labels applied to all deployed resources"
  value       = var.labels
  sensitive   = false
}

# Useful commands and URLs for post-deployment verification
output "verification_commands" {
  description = "Helpful commands for testing and verifying the deployed infrastructure"
  value = {
    test_temperature_conversion = "curl -X POST '${google_cloudfunctions_function.unit_converter.https_trigger_url}' -H 'Content-Type: application/json' -d '{\"value\": 25, \"from_unit\": \"celsius\", \"to_unit\": \"fahrenheit\"}'"
    test_length_conversion     = "curl -X POST '${google_cloudfunctions_function.unit_converter.https_trigger_url}' -H 'Content-Type: application/json' -d '{\"value\": 10, \"from_unit\": \"meters\", \"to_unit\": \"feet\"}'"
    test_weight_conversion     = "curl -X POST '${google_cloudfunctions_function.unit_converter.https_trigger_url}' -H 'Content-Type: application/json' -d '{\"value\": 5, \"from_unit\": \"kilograms\", \"to_unit\": \"pounds\"}'"
    list_conversion_history    = "gcloud storage ls gs://${google_storage_bucket.conversion_history.name}/conversions/"
    view_function_logs         = "gcloud functions logs read ${google_cloudfunctions_function.unit_converter.name} --region=${google_cloudfunctions_function.unit_converter.region}"
    describe_function          = "gcloud functions describe ${google_cloudfunctions_function.unit_converter.name} --region=${google_cloudfunctions_function.unit_converter.region}"
  }
  sensitive = false
}

output "monitoring_urls" {
  description = "Google Cloud Console URLs for monitoring and managing deployed resources"
  value = {
    function_console    = "https://console.cloud.google.com/functions/details/${google_cloudfunctions_function.unit_converter.region}/${google_cloudfunctions_function.unit_converter.name}?project=${var.project_id}"
    storage_console     = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.conversion_history.name}?project=${var.project_id}"
    logs_console        = "https://console.cloud.google.com/logs/query?project=${var.project_id}&query=resource.type%3D%22cloud_function%22%0Aresource.labels.function_name%3D%22${google_cloudfunctions_function.unit_converter.name}%22"
    monitoring_console  = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    iam_console        = "https://console.cloud.google.com/iam-admin/serviceaccounts/details/${google_service_account.function_service_account.unique_id}?project=${var.project_id}"
  }
  sensitive = false
}

# Summary information for deployment success
output "deployment_summary" {
  description = "Summary of the deployed Unit Converter API infrastructure"
  value = {
    api_endpoint           = google_cloudfunctions_function.unit_converter.https_trigger_url
    storage_bucket        = google_storage_bucket.conversion_history.name
    function_name         = google_cloudfunctions_function.unit_converter.name
    service_account       = google_service_account.function_service_account.email
    deployment_region     = var.region
    supported_conversions = [
      "Temperature: Celsius ↔ Fahrenheit ↔ Kelvin",
      "Length: Meters ↔ Feet, Kilometers ↔ Miles",
      "Weight: Kilograms ↔ Pounds, Grams ↔ Ounces"
    ]
    estimated_monthly_cost = "$0.01-$0.05 for typical development usage (within free tiers)"
  }
  sensitive = false
}