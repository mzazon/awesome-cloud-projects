# Output values for the Weather API infrastructure
# These outputs provide important information about the deployed resources

output "function_url" {
  description = "The URL of the deployed Cloud Function weather API"
  value       = google_cloudfunctions2_function.weather_api.service_config[0].uri
  sensitive   = false
}

output "function_name" {
  description = "The name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.weather_api.name
  sensitive   = false
}

output "function_region" {
  description = "The region where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.weather_api.location
  sensitive   = false
}

output "cache_bucket_name" {
  description = "The name of the Cloud Storage bucket used for caching weather data"
  value       = google_storage_bucket.weather_cache.name
  sensitive   = false
}

output "cache_bucket_url" {
  description = "The URL of the Cloud Storage bucket used for caching"
  value       = google_storage_bucket.weather_cache.url
  sensitive   = false
}

output "function_service_account_email" {
  description = "The email address of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
  sensitive   = false
}

output "project_id" {
  description = "The Google Cloud project ID where resources are deployed"
  value       = var.project_id
  sensitive   = false
}

output "function_source_bucket" {
  description = "The name of the bucket containing the function source code"
  value       = google_storage_bucket.function_source.name
  sensitive   = false
}

output "monitoring_dashboard_url" {
  description = "URL to the Google Cloud Console monitoring dashboard for the function"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${var.function_name}?project=${var.project_id}&tab=monitoring"
  sensitive   = false
}

output "logs_url" {
  description = "URL to view Cloud Function logs in the Google Cloud Console"
  value       = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_function%22%0Aresource.labels.function_name%3D%22${var.function_name}%22?project=${var.project_id}"
  sensitive   = false
}

output "api_examples" {
  description = "Example API calls to test the weather service"
  value = {
    london_weather = "${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=London"
    tokyo_weather  = "${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=Tokyo"
    paris_weather  = "${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=Paris"
  }
  sensitive = false
}

output "bucket_lifecycle_policy" {
  description = "Information about the bucket lifecycle policy for cost optimization"
  value = {
    delete_after_days         = 7
    transition_to_nearline_days = 1
    versioning_enabled        = true
  }
  sensitive = false
}

output "function_configuration" {
  description = "Summary of the Cloud Function configuration"
  value = {
    memory_mb        = var.function_memory
    timeout_seconds  = var.function_timeout
    max_instances    = var.function_max_instances
    min_instances    = var.function_min_instances
    runtime         = "python312"
    entry_point     = "weather_api"
  }
  sensitive = false
}

output "security_configuration" {
  description = "Security-related configuration and recommendations"
  value = {
    service_account_email     = google_service_account.function_sa.email
    uniform_bucket_access     = true
    public_access_allowed     = true
    cors_enabled             = true
    versioning_enabled       = true
    
    recommendations = [
      "Consider implementing API key authentication for production use",
      "Review and restrict CORS origins for production deployment",
      "Monitor function invocation patterns and adjust scaling parameters",
      "Set up Cloud Monitoring alerts for error rates and performance"
    ]
  }
  sensitive = false
}

output "cost_optimization_info" {
  description = "Information about cost optimization features enabled"
  value = {
    storage_class            = var.bucket_storage_class
    lifecycle_management     = "Enabled - 7 day retention, transition to Nearline after 1 day"
    function_scaling        = "Configured for pay-per-use with ${var.min_instances} min instances"
    cache_strategy          = "Intelligent caching for ${var.cache_duration_minutes} minutes reduces external API calls"
    
    estimated_monthly_cost = {
      function_invocations_1k = "$0.0000004 per invocation"
      storage_standard_gb     = "$0.020 per GB per month"
      storage_nearline_gb     = "$0.010 per GB per month"
      api_calls_external      = "Reduced by up to 90% through caching"
    }
  }
  sensitive = false
}