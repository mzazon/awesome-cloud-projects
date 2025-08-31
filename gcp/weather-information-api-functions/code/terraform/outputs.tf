# Cloud Function Outputs
output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions_function.weather_api.name
}

output "function_url" {
  description = "HTTPS trigger URL of the weather API function"
  value       = google_cloudfunctions_function.weather_api.https_trigger_url
}

output "function_region" {
  description = "Region where the Cloud Function is deployed"
  value       = google_cloudfunctions_function.weather_api.region
}

output "function_runtime" {
  description = "Runtime version of the Cloud Function"
  value       = google_cloudfunctions_function.weather_api.runtime
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function (MB)"
  value       = google_cloudfunctions_function.weather_api.available_memory_mb
}

output "function_timeout" {
  description = "Timeout setting for the Cloud Function (seconds)"
  value       = google_cloudfunctions_function.weather_api.timeout
}

output "function_max_instances" {
  description = "Maximum number of function instances"
  value       = google_cloudfunctions_function.weather_api.max_instances
}

# Service Account Outputs
output "service_account_email" {
  description = "Email address of the service account used by the function"
  value       = var.create_service_account ? google_service_account.weather_function_sa[0].email : null
}

output "service_account_id" {
  description = "ID of the service account used by the function"
  value       = var.create_service_account ? google_service_account.weather_function_sa[0].id : null
}

# Storage Outputs
output "source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "source_bucket_url" {
  description = "URL of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.url
}

output "source_archive_object" {
  description = "Name of the source archive object in the storage bucket"
  value       = google_storage_bucket_object.function_source.name
}

# Security and Access Outputs
output "public_access_enabled" {
  description = "Whether public access is enabled for the function"
  value       = var.enable_public_access
}

output "ingress_settings" {
  description = "Ingress settings configured for the function"
  value       = google_cloudfunctions_function.weather_api.ingress_settings
}

# Monitoring Outputs
output "uptime_check_id" {
  description = "ID of the uptime monitoring check"
  value       = google_monitoring_uptime_check_config.weather_api_uptime.name
}

output "alert_policy_id" {
  description = "ID of the error rate alert policy"
  value       = google_monitoring_alert_policy.function_error_rate.name
}

output "logging_sink_id" {
  description = "ID of the logging sink (if logging is enabled)"
  value       = var.enable_logging ? google_logging_project_sink.function_logs[0].id : null
}

# Configuration Outputs
output "environment_variables" {
  description = "Environment variables configured for the function (sensitive values masked)"
  value = {
    LOG_LEVEL    = var.log_level
    CORS_ORIGINS = join(",", var.cors_origins)
    # Weather API key is masked for security
    WEATHER_API_KEY_SET = var.weather_api_key != "demo_key_please_replace"
  }
}

output "labels" {
  description = "Labels applied to the function resources"
  value       = local.common_labels
}

# Testing and Validation Outputs
output "test_url_london" {
  description = "Test URL to query weather for London"
  value       = "${google_cloudfunctions_function.weather_api.https_trigger_url}?city=London"
}

output "test_url_new_york" {
  description = "Test URL to query weather for New York"
  value       = "${google_cloudfunctions_function.weather_api.https_trigger_url}?city=New%20York"
}

output "test_commands" {
  description = "Curl commands to test the weather API function"
  value = {
    test_london = "curl '${google_cloudfunctions_function.weather_api.https_trigger_url}?city=London'"
    test_error  = "curl '${google_cloudfunctions_function.weather_api.https_trigger_url}'"
    test_cors   = "curl -H 'Origin: https://example.com' '${google_cloudfunctions_function.weather_api.https_trigger_url}?city=Paris'"
  }
}

# Resource Information Outputs
output "project_id" {
  description = "GCP project ID where resources are deployed"
  value       = var.project_id
}

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    cloud_function    = google_cloudfunctions_function.weather_api.name
    storage_bucket    = google_storage_bucket.function_source.name
    service_account   = var.create_service_account ? google_service_account.weather_function_sa[0].email : "default"
    uptime_check     = google_monitoring_uptime_check_config.weather_api_uptime.display_name
    alert_policy     = google_monitoring_alert_policy.function_error_rate.display_name
    enabled_apis     = join(", ", keys(google_project_service.required_apis))
  }
}

# Cost Estimation Outputs
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD, approximate)"
  value = {
    note = "Costs are estimates based on typical usage patterns"
    cloud_function = {
      invocations_2m_free = "First 2 million invocations per month are free"
      additional_per_1m   = "$0.40 per million invocations beyond free tier"
      compute_time_400k_free = "First 400,000 GB-seconds per month are free"
      additional_per_gb_sec = "$0.0000025 per GB-second beyond free tier"
    }
    cloud_storage = {
      standard_storage = "$0.020 per GB per month"
      operations       = "$0.05 per 10,000 operations"
    }
    cloud_logging = {
      first_50gb_free = "First 50 GB per project per month are free"
      additional      = "$0.50 per GB per month beyond free tier"
    }
    monitoring = {
      basic_free = "Basic monitoring metrics are free"
      uptime_checks = "First 100 uptime check requests per month are free"
    }
  }
}

# Documentation Links
output "documentation_links" {
  description = "Useful documentation links for the deployed resources"
  value = {
    cloud_functions     = "https://cloud.google.com/functions/docs"
    monitoring         = "https://cloud.google.com/monitoring/docs"
    cloud_storage      = "https://cloud.google.com/storage/docs"
    service_accounts   = "https://cloud.google.com/iam/docs/service-accounts"
    python_runtime     = "https://cloud.google.com/functions/docs/concepts/python-runtime"
    best_practices     = "https://cloud.google.com/functions/docs/bestpractices"
    troubleshooting    = "https://cloud.google.com/functions/docs/troubleshooting"
  }
}