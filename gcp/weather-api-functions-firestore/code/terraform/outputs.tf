# Output Values for Weather API Infrastructure
# These outputs provide important information for verification and integration

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.weather_api.name
}

output "function_url" {
  description = "HTTP trigger URL for the weather API function"
  value       = google_cloudfunctions2_function.weather_api.service_config[0].uri
  sensitive   = false
}

output "function_region" {
  description = "Region where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.weather_api.location
}

output "firestore_database_name" {
  description = "Name of the Firestore database used for caching"
  value       = google_firestore_database.weather_cache.name
}

output "firestore_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.weather_cache.location_id
}

output "service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "project_id" {
  description = "GCP Project ID where resources are deployed"
  value       = var.project_id
}

output "function_source_bucket" {
  description = "Cloud Storage bucket containing the function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_memory_mb" {
  description = "Memory allocation for the Cloud Function in MB"
  value       = var.function_memory
}

output "function_timeout_seconds" {
  description = "Timeout setting for the Cloud Function in seconds"
  value       = var.function_timeout
}

output "cache_ttl_minutes" {
  description = "Cache TTL setting for weather data in Firestore"
  value       = var.cache_ttl_minutes
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

output "cors_enabled" {
  description = "Whether CORS is enabled for the function"
  value       = var.enable_cors
}

output "public_access_enabled" {
  description = "Whether public unauthenticated access is enabled"
  value       = var.enable_public_access
}

# API Testing Information
output "api_test_commands" {
  description = "Example commands to test the deployed weather API"
  value = {
    test_london = "curl '${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=London'"
    test_paris  = "curl '${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=Paris'"
    test_json   = "curl '${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=Tokyo' | jq '.'"
  }
}

# Resource Information for Monitoring
output "monitoring_resources" {
  description = "Information for setting up monitoring and alerting"
  value = {
    function_resource_name = "projects/${var.project_id}/locations/${google_cloudfunctions2_function.weather_api.location}/functions/${google_cloudfunctions2_function.weather_api.name}"
    firestore_database     = "projects/${var.project_id}/databases/${google_firestore_database.weather_cache.name}"
    logs_filter           = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.weather_api.name}\""
  }
}

# Cleanup Information
output "cleanup_info" {
  description = "Information about resources that may require manual cleanup"
  value = {
    firestore_note = "Firestore database deletion may require manual confirmation"
    storage_note   = "Function source bucket will be automatically cleaned up"
    api_note       = "Enabled APIs will remain active to prevent service disruption"
  }
}

# Cost Estimation Information
output "cost_estimates" {
  description = "Estimated costs for the deployed resources (USD per month)"
  value = {
    cloud_functions = "~$0.40 per 1M requests + $0.0000025 per 100ms execution time"
    firestore       = "~$0.18 per 100K reads, $0.54 per 100K writes, $1.08/GB storage"
    cloud_storage   = "~$0.020/GB for Standard storage (function source)"
    total_estimate  = "~$1-5/month for typical usage patterns"
    free_tier_note  = "Most usage will fall within GCP Free Tier limits"
  }
}