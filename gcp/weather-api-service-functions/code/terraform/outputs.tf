# Outputs for Weather API Service with Cloud Functions
# This file defines the output values that will be displayed after terraform apply
# These outputs provide essential information for testing and integration

# Function Information Outputs
output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.weather_api.name
}

output "function_url" {
  description = "HTTP trigger URL for the weather API function"
  value       = google_cloudfunctions2_function.weather_api.service_config[0].uri
}

output "function_region" {
  description = "Region where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.weather_api.location
}

output "function_runtime" {
  description = "Runtime environment used by the Cloud Function"
  value       = google_cloudfunctions2_function.weather_api.build_config[0].runtime
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function"
  value       = google_cloudfunctions2_function.weather_api.service_config[0].available_memory
}

output "function_timeout" {
  description = "Timeout setting for the Cloud Function in seconds"
  value       = google_cloudfunctions2_function.weather_api.service_config[0].timeout_seconds
}

# Storage Information Outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket used for caching"
  value       = google_storage_bucket.weather_cache.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.weather_cache.url
}

output "storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.weather_cache.location
}

output "storage_class" {
  description = "Storage class of the Cloud Storage bucket"
  value       = google_storage_bucket.weather_cache.storage_class
}

# IAM and Security Outputs
output "function_service_account" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "function_service_account_id" {
  description = "Unique ID of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.unique_id
}

# Project and Configuration Outputs
output "project_id" {
  description = "GCP Project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "GCP region where resources are deployed"
  value       = var.region
}

# API Testing Information
output "test_urls" {
  description = "Example URLs for testing the weather API"
  value = {
    london_weather = "${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=London"
    paris_weather  = "${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=Paris"
    tokyo_weather  = "${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=Tokyo"
  }
}

# Configuration Status Outputs
output "api_key_configured" {
  description = "Whether an OpenWeatherMap API key is configured (not the actual key)"
  value       = var.openweather_api_key != "" ? "Yes (Custom API Key)" : "No (Demo Mode)"
}

output "cors_enabled" {
  description = "Whether CORS is enabled for the API"
  value       = var.enable_cors
}

output "public_access_enabled" {
  description = "Whether unauthenticated access is allowed"
  value       = var.allow_unauthenticated
}

# Resource Identifiers for External Integration
output "resource_ids" {
  description = "Resource identifiers for integration with other systems"
  value = {
    function_id          = google_cloudfunctions2_function.weather_api.id
    bucket_id            = google_storage_bucket.weather_cache.id
    service_account_id   = google_service_account.function_sa.id
    random_suffix       = random_id.resource_suffix.hex
  }
}

# Monitoring and Logging Outputs
output "monitoring_enabled" {
  description = "Whether monitoring is enabled for the function"
  value       = var.enable_function_logs
}

output "log_level" {
  description = "Configured log level for the function"
  value       = var.log_level
}

# Cache Configuration Outputs
output "cache_lifecycle_days" {
  description = "Number of days after which cached data expires"
  value       = var.cache_lifecycle_days
}

# Deployment Information
output "deployment_labels" {
  description = "Labels applied to all deployed resources"
  value       = local.common_labels
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Commands to quickly test the deployed weather API"
  value = {
    test_basic_api = "curl '${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=London'"
    test_with_json = "curl '${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=London' | jq '.'"
    check_cache    = "gsutil ls gs://${google_storage_bucket.weather_cache.name}/"
    view_logs      = "gcloud functions logs read ${google_cloudfunctions2_function.weather_api.name} --region=${var.region}"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for typical usage patterns"
  value = {
    function_invocations = "Free tier: 2M invocations/month, then $0.40 per million"
    storage_costs       = "Standard storage: $0.020 per GB/month"
    network_egress      = "Free tier: 1GB/month to most regions"
    total_estimate      = "Typical monthly cost: $0.00-$5.00 for small applications"
  }
}

# Health Check and Validation Outputs
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_function_status = "gcloud functions describe ${google_cloudfunctions2_function.weather_api.name} --region=${var.region}"
    test_function_health  = "curl -f '${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=London' && echo 'API is healthy'"
    verify_bucket_access  = "gsutil ls gs://${google_storage_bucket.weather_cache.name}/ || echo 'Bucket accessible'"
    check_iam_permissions = "gcloud projects get-iam-policy ${var.project_id} --flatten='bindings[].members' --filter='bindings.members:${google_service_account.function_sa.email}'"
  }
}