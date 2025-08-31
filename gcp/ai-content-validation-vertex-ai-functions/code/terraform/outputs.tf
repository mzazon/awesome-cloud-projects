# Output Values for AI Content Validation Infrastructure
# These outputs provide important information about the deployed resources
# for integration with other systems and for operational use

# Project and Resource Identification
output "project_id" {
  description = "The GCP project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources are deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming uniqueness"
  value       = random_id.suffix.hex
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

# Cloud Storage Buckets
output "content_input_bucket_name" {
  description = "Name of the Cloud Storage bucket for content input"
  value       = google_storage_bucket.content_input.name
}

output "content_input_bucket_url" {
  description = "URL of the content input bucket"
  value       = google_storage_bucket.content_input.url
}

output "content_input_bucket_self_link" {
  description = "Self-link of the content input bucket for API references"
  value       = google_storage_bucket.content_input.self_link
}

output "validation_results_bucket_name" {
  description = "Name of the Cloud Storage bucket for validation results"
  value       = google_storage_bucket.validation_results.name
}

output "validation_results_bucket_url" {
  description = "URL of the validation results bucket"
  value       = google_storage_bucket.validation_results.url
}

output "validation_results_bucket_self_link" {
  description = "Self-link of the validation results bucket for API references"
  value       = google_storage_bucket.validation_results.self_link
}

# Cloud Function Information
output "function_name" {
  description = "Name of the content validation Cloud Function"
  value       = google_cloudfunctions2_function.content_validator.name
}

output "function_uri" {
  description = "URI of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.content_validator.service_config[0].uri
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "function_trigger_region" {
  description = "Region where the function event trigger is configured"
  value       = google_cloudfunctions2_function.content_validator.event_trigger[0].trigger_region
}

# Service Account Information
output "function_service_account_id" {
  description = "ID of the Cloud Function service account"
  value       = google_service_account.function_sa.account_id
}

output "function_service_account_unique_id" {
  description = "Unique ID of the Cloud Function service account"
  value       = google_service_account.function_sa.unique_id
}

# Configuration Information
output "vertex_ai_location" {
  description = "Location used for Vertex AI operations"
  value       = var.vertex_ai_location
}

output "gemini_model_name" {
  description = "Name of the Gemini model used for content validation"
  value       = var.gemini_model_name
}

output "safety_threshold" {
  description = "Safety threshold configured for content validation"
  value       = var.safety_threshold
}

output "function_runtime" {
  description = "Runtime environment of the Cloud Function"
  value       = var.function_runtime
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function"
  value       = var.function_memory
}

output "function_timeout" {
  description = "Timeout setting for the Cloud Function in seconds"
  value       = var.function_timeout
}

# Monitoring and Alerting
output "monitoring_enabled" {
  description = "Whether Cloud Monitoring alerts are enabled"
  value       = var.enable_monitoring
}

output "error_rate_alert_policy_name" {
  description = "Name of the error rate monitoring alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_error_rate[0].display_name : null
}

output "latency_alert_policy_name" {
  description = "Name of the latency monitoring alert policy" 
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_latency[0].display_name : null
}

# Logging Configuration
output "cloud_logging_enabled" {
  description = "Whether enhanced Cloud Logging is enabled"
  value       = var.enable_cloud_logging
}

output "log_sink_name" {
  description = "Name of the Cloud Logging sink for function logs"
  value       = var.enable_cloud_logging ? google_logging_project_sink.function_logs[0].name : null
}

output "log_sink_destination" {
  description = "Destination of the Cloud Logging sink"
  value       = var.enable_cloud_logging ? google_logging_project_sink.function_logs[0].destination : null
}

# Security and Access
output "bucket_security_configuration" {
  description = "Security configuration applied to storage buckets"
  value = {
    uniform_bucket_level_access   = var.enable_uniform_bucket_level_access
    public_access_prevention      = var.enable_public_access_prevention
    versioning_enabled           = var.bucket_versioning_enabled
    lifecycle_management_enabled = var.bucket_lifecycle_enabled
  }
}

output "function_security_configuration" {
  description = "Security configuration applied to the Cloud Function"
  value = {
    service_account_email        = google_service_account.function_sa.email
    ingress_settings            = "ALLOW_INTERNAL_AND_GCLB"
    vpc_connector_enabled       = var.enable_vpc_connector
    allowed_principals_count    = length(var.allowed_principals)
  }
}

# Cost and Performance Optimization
output "cost_optimization_features" {
  description = "Cost optimization features enabled"
  value = {
    bucket_lifecycle_enabled     = var.bucket_lifecycle_enabled
    lifecycle_age_days          = var.bucket_lifecycle_age_days
    retention_days              = var.bucket_retention_days
    min_function_instances      = var.function_min_instances
    max_function_instances      = var.function_max_instances
    cpu_boost_enabled           = var.enable_function_cpu_boost
  }
}

# API Status
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value       = local.all_apis
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the deployed content validation system"
  value = {
    upload_content = "Upload text files to gs://${google_storage_bucket.content_input.name}/ to trigger validation"
    view_results   = "Check validation results in gs://${google_storage_bucket.validation_results.name}/validation_results/"
    monitor_logs   = "View function logs in Cloud Logging with filter: resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.content_validator.name}\""
    test_command   = "gsutil cp your_content.txt gs://${google_storage_bucket.content_input.name}/"
  }
}

# Testing Commands
output "test_commands" {
  description = "Commands to test the content validation system"
  value = {
    create_test_file = "echo 'This is safe test content for validation.' > test_content.txt"
    upload_test_file = "gsutil cp test_content.txt gs://${google_storage_bucket.content_input.name}/"
    check_results    = "gsutil ls gs://${google_storage_bucket.validation_results.name}/validation_results/"
    download_result  = "gsutil cp gs://${google_storage_bucket.validation_results.name}/validation_results/test_content_results.json ./"
    view_logs        = "gcloud functions logs read ${google_cloudfunctions2_function.content_validator.name} --region ${var.region} --limit 10"
  }
}

# Resource URLs for Console Access
output "console_urls" {
  description = "Google Cloud Console URLs for managing deployed resources"
  value = {
    function_console     = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.content_validator.name}?project=${var.project_id}"
    content_bucket       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.content_input.name}?project=${var.project_id}"
    results_bucket       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.validation_results.name}?project=${var.project_id}"
    monitoring_dashboard = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    logs_explorer        = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
    vertex_ai_console    = "https://console.cloud.google.com/vertex-ai?project=${var.project_id}"
  }
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of the deployed AI content validation system"
  value = {
    system_type              = "Serverless AI Content Validation"
    ai_provider             = "Google Cloud Vertex AI"
    model_used              = var.gemini_model_name
    processing_framework    = "Cloud Functions Gen2"
    storage_provider        = "Cloud Storage"
    trigger_mechanism       = "Cloud Storage Events"
    safety_threshold        = var.safety_threshold
    estimated_monthly_cost  = "~$10-50 for moderate usage (1000 validations/month)"
    scaling_model          = "Automatic based on upload volume"
    supported_file_types   = "Text files (.txt, .md, .json, etc.)"
  }
}