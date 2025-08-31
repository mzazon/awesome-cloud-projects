# Outputs for password generator Cloud Function deployment
# These outputs provide important information about the deployed infrastructure

# Function Information
output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.password_generator.name
}

output "function_id" {
  description = "Fully qualified ID of the Cloud Function"
  value       = google_cloudfunctions2_function.password_generator.id
}

output "function_url" {
  description = "HTTP trigger URL for the Cloud Function"
  value       = google_cloudfunctions2_function.password_generator.service_config[0].uri
  sensitive   = false
}

output "function_uri" {
  description = "URI of the Cloud Function service"
  value       = google_cloudfunctions2_function.password_generator.service_config[0].uri
}

output "function_status" {
  description = "Current status of the Cloud Function"
  value       = google_cloudfunctions2_function.password_generator.state
}

# Function Configuration Details
output "function_runtime" {
  description = "Runtime environment of the Cloud Function"
  value       = google_cloudfunctions2_function.password_generator.build_config[0].runtime
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function"
  value       = google_cloudfunctions2_function.password_generator.service_config[0].available_memory
}

output "function_timeout" {
  description = "Timeout setting for the Cloud Function"
  value       = google_cloudfunctions2_function.password_generator.service_config[0].timeout_seconds
}

output "function_max_instances" {
  description = "Maximum number of function instances"
  value       = google_cloudfunctions2_function.password_generator.service_config[0].max_instance_count
}

output "function_min_instances" {
  description = "Minimum number of function instances"
  value       = google_cloudfunctions2_function.password_generator.service_config[0].min_instance_count
}

# Service Account Information
output "function_service_account" {
  description = "Service account email used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "function_service_account_id" {
  description = "Service account ID used by the Cloud Function"
  value       = google_service_account.function_sa.unique_id
}

# Storage Information
output "source_bucket_name" {
  description = "Name of the Google Cloud Storage bucket containing the function source code"
  value       = google_storage_bucket.function_source.name
}

output "source_bucket_url" {
  description = "URL of the Google Cloud Storage bucket"
  value       = google_storage_bucket.function_source.url
}

output "source_object_name" {
  description = "Name of the source code object in the bucket"
  value       = google_storage_bucket_object.function_source.name
}

output "source_object_md5" {
  description = "MD5 hash of the source code archive"
  value       = google_storage_bucket_object.function_source.md5hash
}

# Project and Location Information
output "project_id" {
  description = "Google Cloud Project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where the function is deployed"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone configuration"
  value       = local.zone
}

# Labels and Metadata
output "function_labels" {
  description = "Labels applied to the Cloud Function"
  value       = google_cloudfunctions2_function.password_generator.labels
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

# API Testing Information
output "test_commands" {
  description = "Example commands to test the deployed function"
  value = {
    basic_test = "curl '${google_cloudfunctions2_function.password_generator.service_config[0].uri}?length=16'"
    json_test  = "curl -X POST '${google_cloudfunctions2_function.password_generator.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"length\": 12, \"include_symbols\": true}'"
    complex_test = "curl '${google_cloudfunctions2_function.password_generator.service_config[0].uri}?length=20&include_symbols=true&include_numbers=true'"
  }
}

# Monitoring and Logging URLs
output "cloud_console_function_url" {
  description = "Google Cloud Console URL for the function"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.password_generator.name}?project=${var.project_id}"
}

output "cloud_logging_url" {
  description = "Google Cloud Logging URL for function logs"
  value       = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_function%22%0Aresource.labels.function_name%3D%22${google_cloudfunctions2_function.password_generator.name}%22?project=${var.project_id}"
}

output "cloud_monitoring_url" {
  description = "Google Cloud Monitoring URL for function metrics"
  value       = "https://console.cloud.google.com/monitoring/dashboards/resourceList/cloudfunctions_function?project=${var.project_id}"
}

# Security Information
output "function_ingress_settings" {
  description = "Ingress settings for the Cloud Function"
  value       = google_cloudfunctions2_function.password_generator.service_config[0].ingress_settings
}

output "unauthenticated_access_enabled" {
  description = "Whether unauthenticated access is enabled for the function"
  value       = var.allow_unauthenticated
}

# Cost and Usage Information
output "billing_info" {
  description = "Information about potential costs and usage"
  value = {
    free_tier_invocations = "2,000,000 invocations per month"
    pricing_model        = "Pay-per-invocation after free tier"
    estimated_cost       = "$0.00-$0.40 per million invocations"
    memory_tier         = var.function_memory
  }
}

# Source Code Information
output "source_code_info" {
  description = "Information about the deployed source code"
  value = {
    source_path = var.source_code_path
    archive_md5 = data.archive_file.function_source.output_md5
    entry_point = "generate_password"
    runtime     = var.function_runtime
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    function_name    = google_cloudfunctions2_function.password_generator.name
    function_url     = google_cloudfunctions2_function.password_generator.service_config[0].uri
    project_id       = var.project_id
    region          = var.region
    environment     = var.environment
    runtime         = var.function_runtime
    memory          = var.function_memory
    timeout         = var.function_timeout
    max_instances   = var.function_max_instances
    public_access   = var.allow_unauthenticated
    bucket_name     = google_storage_bucket.function_source.name
  }
}