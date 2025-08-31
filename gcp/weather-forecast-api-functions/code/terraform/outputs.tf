# Function endpoint and access information
output "function_url" {
  description = "The HTTPS URL endpoint for the weather forecast function"
  value       = google_cloud_run_v2_service.weather_function.uri
}

output "function_name" {
  description = "The name of the deployed Cloud Run service"
  value       = google_cloud_run_v2_service.weather_function.name
}

output "function_region" {
  description = "The region where the function is deployed"
  value       = google_cloud_run_v2_service.weather_function.location
}

# Service account information
output "service_account_email" {
  description = "Email address of the service account used by the function"
  value       = google_service_account.function_sa.email
}

output "service_account_id" {
  description = "The unique ID of the service account"
  value       = google_service_account.function_sa.unique_id
}

# Storage and source code information
output "source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "source_bucket_url" {
  description = "URL of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.url
}

output "source_archive_object" {
  description = "Name of the source code archive object in Cloud Storage"
  value       = google_storage_bucket_object.function_archive.name
}

# Function configuration details
output "function_memory_limit" {
  description = "Memory allocation for the function"
  value       = var.memory_limit
}

output "function_cpu_limit" {
  description = "CPU allocation for the function"
  value       = var.cpu_limit
}

output "function_timeout" {
  description = "Request timeout for the function in seconds"
  value       = var.timeout_seconds
}

output "function_max_instances" {
  description = "Maximum number of function instances"
  value       = var.max_instances
}

output "function_min_instances" {
  description = "Minimum number of function instances"
  value       = var.min_instances
}

# Testing and validation information
output "test_commands" {
  description = "Example curl commands to test the deployed function"
  value = {
    basic_request = "curl '${google_cloud_run_v2_service.weather_function.uri}'"
    city_request  = "curl '${google_cloud_run_v2_service.weather_function.uri}?city=Tokyo'"
    cors_preflight = "curl -X OPTIONS '${google_cloud_run_v2_service.weather_function.uri}' -H 'Access-Control-Request-Method: GET'"
  }
}

# Monitoring and logging outputs (conditional)
output "log_based_metric_name" {
  description = "Name of the log-based metric for function invocations"
  value       = var.enable_logging ? google_logging_metric.function_invocations[0].name : null
}

output "alert_policy_name" {
  description = "Name of the Cloud Monitoring alert policy for function errors"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_error_rate[0].display_name : null
}

output "log_sink_name" {
  description = "Name of the log sink for long-term log storage"
  value       = var.enable_logging ? google_logging_project_sink.function_logs[0].name : null
}

output "log_storage_bucket" {
  description = "Name of the Cloud Storage bucket for long-term log storage"
  value       = var.enable_logging ? google_storage_bucket.function_logs[0].name : null
}

# Project and resource identification
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.resource_suffix
}

# API and external service configuration
output "openweather_api_configured" {
  description = "Whether OpenWeatherMap API key is configured (not 'demo_key')"
  value       = var.openweather_api_key != "demo_key"
  sensitive   = false
}

# Security and access information
output "public_access_enabled" {
  description = "Whether the function allows unauthenticated public access"
  value       = var.allow_unauthenticated
}

output "ingress_setting" {
  description = "Ingress traffic setting for the Cloud Run service"
  value       = var.ingress
}

# Cloud Run service status and metadata
output "service_generation" {
  description = "The generation of the Cloud Run service"
  value       = google_cloud_run_v2_service.weather_function.generation
}

output "service_creation_timestamp" {
  description = "Timestamp when the Cloud Run service was created"
  value       = google_cloud_run_v2_service.weather_function.create_time
}

output "service_update_timestamp" {
  description = "Timestamp when the Cloud Run service was last updated" 
  value       = google_cloud_run_v2_service.weather_function.update_time
}

# Deployment guidance
output "deployment_notes" {
  description = "Important notes about the deployment"
  value = {
    api_key_notice = var.openweather_api_key == "demo_key" ? "Using demo API key - requests will return 401 errors. Set openweather_api_key variable for production use." : "Production OpenWeatherMap API key configured."
    public_access  = var.allow_unauthenticated ? "Function is publicly accessible without authentication." : "Function requires authentication to access."
    cost_estimate  = "Function uses pay-per-request pricing. First 2 million invocations per month are free."
    testing_tip    = "Test the function using the curl commands in the test_commands output."
  }
}

# Health check and monitoring URLs
output "monitoring_urls" {
  description = "URLs for monitoring and managing the deployed function"
  value = var.enable_monitoring ? {
    cloud_run_console  = "https://console.cloud.google.com/run/detail/${var.region}/${google_cloud_run_v2_service.weather_function.name}/metrics?project=${var.project_id}"
    cloud_logging     = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_run_revision%22%0Aresource.labels.service_name%3D%22${var.function_name}%22?project=${var.project_id}"
    cloud_monitoring  = "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}"
  } : null
}