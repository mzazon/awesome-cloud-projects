# Output values for the Lorem Ipsum Generator Cloud Functions recipe
# These outputs provide important information for testing and integration

output "function_url" {
  description = "HTTPS URL of the deployed Cloud Function for API access"
  value       = google_cloudfunctions2_function.lorem_generator.url
  sensitive   = false
}

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.lorem_generator.name
}

output "function_location" {
  description = "Location where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.lorem_generator.location
}

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket used for caching"
  value       = google_storage_bucket.cache_bucket.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.cache_bucket.url
}

output "project_id" {
  description = "Google Cloud Project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

output "function_service_uri" {
  description = "Internal service URI for the Cloud Function (Cloud Run service)"
  value       = google_cloudfunctions2_function.lorem_generator.service_config[0].uri
}

output "function_runtime" {
  description = "Runtime version used by the Cloud Function"
  value       = google_cloudfunctions2_function.lorem_generator.build_config[0].runtime
}

output "example_api_calls" {
  description = "Example API calls to test the Lorem Ipsum Generator"
  value = {
    basic_request = "${google_cloudfunctions2_function.lorem_generator.url}?paragraphs=3&words=50"
    minimal_request = "${google_cloudfunctions2_function.lorem_generator.url}?paragraphs=1&words=10"
    maximum_request = "${google_cloudfunctions2_function.lorem_generator.url}?paragraphs=10&words=200"
    curl_example = "curl '${google_cloudfunctions2_function.lorem_generator.url}?paragraphs=2&words=30' | python3 -m json.tool"
  }
}

output "monitoring_links" {
  description = "Links to Google Cloud Console for monitoring and management"
  value = {
    function_console = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.lorem_generator.name}?project=${var.project_id}"
    storage_console = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.cache_bucket.name}?project=${var.project_id}"
    logs_console = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_function%22%0Aresource.labels.function_name%3D%22${google_cloudfunctions2_function.lorem_generator.name}%22?project=${var.project_id}"
  }
}

output "cost_estimate" {
  description = "Estimated monthly costs for typical usage patterns"
  value = {
    note = "Estimates based on Cloud Functions 2nd gen pricing and typical usage patterns"
    free_tier = "2M requests/month and 400,000 GB-seconds compute time included free"
    light_usage = "$0.00 - $2.00 USD/month (within free tier limits)"
    moderate_usage = "$2.00 - $10.00 USD/month (10M requests, cached responses)"
    storage_cost = "~$0.10 USD/month for cache storage (first 5GB free)"
  }
}

output "security_notes" {
  description = "Important security considerations for the deployed API"
  value = {
    authentication = "Function allows unauthenticated access - suitable for public lorem ipsum API"
    cors_enabled = var.enable_cors ? "CORS is enabled for cross-origin web requests" : "CORS is disabled"
    allowed_origins = var.enable_cors ? join(", ", var.cors_origins) : "N/A"
    parameter_validation = "Function validates and limits parameters to prevent abuse"
    caching = "Responses are cached to improve performance and reduce costs"
  }
}