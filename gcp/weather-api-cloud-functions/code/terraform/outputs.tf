# =============================================================================
# Weather API with Cloud Functions - Terraform Outputs
# =============================================================================
# This file defines outputs that provide important information about the
# deployed resources, including URLs, resource names, and configuration details.
# =============================================================================

# =============================================================================
# CLOUD FUNCTION INFORMATION
# =============================================================================

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.weather_api.name
}

output "function_url" {
  description = "HTTPS URL of the deployed Cloud Function - use this to access the weather API"
  value       = google_cloudfunctions2_function.weather_api.service_config[0].uri
}

output "function_location" {
  description = "Google Cloud region where the function is deployed"
  value       = google_cloudfunctions2_function.weather_api.location
}

output "function_id" {
  description = "Fully qualified Cloud Function identifier"
  value       = google_cloudfunctions2_function.weather_api.id
}

output "function_state" {
  description = "Current state of the Cloud Function deployment"
  value       = google_cloudfunctions2_function.weather_api.state
}

# =============================================================================
# API ENDPOINT INFORMATION
# =============================================================================

output "api_endpoint" {
  description = "Complete API endpoint URL for testing the weather service"
  value       = "${google_cloudfunctions2_function.weather_api.service_config[0].uri}"
}

output "api_endpoint_with_city" {
  description = "Example API endpoint URL with city parameter for testing"
  value       = "${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=London"
}

output "curl_test_command" {
  description = "Ready-to-use curl command for testing the weather API"
  value       = "curl -s '${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=Paris' | jq ."
}

# =============================================================================
# SERVICE ACCOUNT INFORMATION
# =============================================================================

output "service_account_email" {
  description = "Email address of the service account used by the Cloud Function"
  value       = google_service_account.weather_api_function.email
}

output "service_account_name" {
  description = "Full name of the service account resource"
  value       = google_service_account.weather_api_function.name
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.weather_api_function.unique_id
}

# =============================================================================
# STORAGE INFORMATION
# =============================================================================

output "source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing the function source code"
  value       = google_storage_bucket.function_source.name
}

output "source_bucket_url" {
  description = "URL of the Cloud Storage bucket containing the function source code"
  value       = google_storage_bucket.function_source.url
}

output "source_object_name" {
  description = "Name of the source code archive object in Cloud Storage"
  value       = google_storage_bucket_object.function_source.name
}

# =============================================================================
# FUNCTION CONFIGURATION
# =============================================================================

output "function_runtime" {
  description = "Runtime environment used by the Cloud Function"
  value       = google_cloudfunctions2_function.weather_api.build_config[0].runtime
}

output "function_entry_point" {
  description = "Entry point function name"
  value       = google_cloudfunctions2_function.weather_api.build_config[0].entry_point
}

output "function_memory" {
  description = "Memory allocated to the Cloud Function"
  value       = google_cloudfunctions2_function.weather_api.service_config[0].available_memory
}

output "function_timeout" {
  description = "Timeout configuration for the Cloud Function (in seconds)"
  value       = google_cloudfunctions2_function.weather_api.service_config[0].timeout_seconds
}

output "function_max_instances" {
  description = "Maximum number of concurrent function instances"
  value       = google_cloudfunctions2_function.weather_api.service_config[0].max_instance_count
}

output "function_min_instances" {
  description = "Minimum number of function instances kept warm"
  value       = google_cloudfunctions2_function.weather_api.service_config[0].min_instance_count
}

# =============================================================================
# PROJECT AND ENVIRONMENT INFORMATION
# =============================================================================

output "project_id" {
  description = "Google Cloud project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region used for deployment"
  value       = var.region
}

output "environment" {
  description = "Environment label applied to resources"
  value       = var.environment
}

# =============================================================================
# MONITORING AND LOGGING
# =============================================================================

output "function_logs_url" {
  description = "URL to view Cloud Function logs in the Google Cloud Console"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.weather_api.name}/logs?project=${var.project_id}"
}

output "function_metrics_url" {
  description = "URL to view Cloud Function metrics in the Google Cloud Console"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.weather_api.name}/metrics?project=${var.project_id}"
}

output "cloud_logging_filter" {
  description = "Cloud Logging filter to view function-specific logs"
  value       = "resource.type=\"cloud_function\" resource.labels.function_name=\"${google_cloudfunctions2_function.weather_api.name}\""
}

# =============================================================================
# ENABLED SERVICES
# =============================================================================

output "enabled_services" {
  description = "List of Google Cloud services enabled for this deployment"
  value = [
    google_project_service.cloud_functions.service,
    google_project_service.cloud_build.service,
    google_project_service.artifact_registry.service,
    google_project_service.cloud_logging.service,
    google_project_service.cloud_run.service
  ]
}

# =============================================================================
# RESOURCE LABELS
# =============================================================================

output "resource_labels" {
  description = "Labels applied to the Cloud Function for organization and cost tracking"
  value       = google_cloudfunctions2_function.weather_api.labels
}

# =============================================================================
# TESTING AND VALIDATION INFORMATION
# =============================================================================

output "test_commands" {
  description = "Commands for testing the deployed weather API"
  value = {
    basic_test     = "curl -s '${google_cloudfunctions2_function.weather_api.service_config[0].uri}'"
    city_test      = "curl -s '${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=Tokyo'"
    json_formatted = "curl -s '${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=Sydney' | jq ."
    cors_test      = "curl -s -H 'Origin: https://example.com' '${google_cloudfunctions2_function.weather_api.service_config[0].uri}'"
  }
}

output "validation_endpoints" {
  description = "Endpoints for validating different aspects of the weather API"
  value = {
    default_city = "${google_cloudfunctions2_function.weather_api.service_config[0].uri}"
    london       = "${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=London"
    paris        = "${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=Paris"
    tokyo        = "${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=Tokyo"
    new_york     = "${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=New%20York"
  }
}

# =============================================================================
# DEPLOYMENT SUMMARY
# =============================================================================

output "deployment_summary" {
  description = "Summary of the deployed weather API infrastructure"
  value = {
    function_name      = google_cloudfunctions2_function.weather_api.name
    function_url       = google_cloudfunctions2_function.weather_api.service_config[0].uri
    runtime           = google_cloudfunctions2_function.weather_api.build_config[0].runtime
    memory            = google_cloudfunctions2_function.weather_api.service_config[0].available_memory
    timeout           = google_cloudfunctions2_function.weather_api.service_config[0].timeout_seconds
    region            = google_cloudfunctions2_function.weather_api.location
    environment       = var.environment
    public_access     = var.allow_unauthenticated
    monitoring_enabled = var.enable_monitoring
  }
}

# =============================================================================
# SECURITY INFORMATION
# =============================================================================

output "security_config" {
  description = "Security configuration details for the deployed function"
  value = {
    public_access      = var.allow_unauthenticated
    service_account    = google_service_account.weather_api_function.email
    ingress_settings   = google_cloudfunctions2_function.weather_api.service_config[0].ingress_settings
    cors_enabled       = length(var.cors_origins) > 0
    allowed_origins    = var.cors_origins
  }
}

# =============================================================================
# CONDITIONAL OUTPUTS (MONITORING)
# =============================================================================

output "monitoring_metrics" {
  description = "Names of log-based metrics created for monitoring (if enabled)"
  value = var.enable_monitoring ? {
    error_metric      = google_logging_metric.function_errors[0].name
    invocation_metric = google_logging_metric.function_invocations[0].name
  } : {}
}