# outputs.tf - Output values for the Weather Dashboard infrastructure
#
# This file defines all output values that provide important information about
# the deployed infrastructure, including URLs, resource identifiers, and
# configuration details needed for application operation and integration.

# Website and Application URLs
output "website_url" {
  description = "URL of the deployed weather dashboard website"
  value       = "https://storage.googleapis.com/${google_storage_bucket.website_bucket.name}/index.html"
}

output "website_bucket_url" {
  description = "Base URL of the website storage bucket"
  value       = google_storage_bucket.website_bucket.url
}

output "function_url" {
  description = "HTTPS trigger URL for the weather API Cloud Function"
  value       = google_cloudfunctions2_function.weather_api.service_config[0].uri
  sensitive   = false
}

output "function_direct_url" {
  description = "Direct invocation URL for the Cloud Function"
  value       = google_cloudfunctions2_function.weather_api.url
}

# Resource Identifiers
output "project_id" {
  description = "Google Cloud project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.weather_api.name
}

output "bucket_name" {
  description = "Name of the website hosting storage bucket"
  value       = google_storage_bucket.website_bucket.name
}

output "source_bucket_name" {
  description = "Name of the function source code storage bucket"
  value       = google_storage_bucket.function_source_bucket.name
}

# Function Configuration Details
output "function_runtime" {
  description = "Runtime environment of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.weather_api.build_config[0].runtime
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function"
  value       = google_cloudfunctions2_function.weather_api.service_config[0].available_memory
}

output "function_timeout" {
  description = "Timeout configuration for the Cloud Function"
  value       = google_cloudfunctions2_function.weather_api.service_config[0].timeout_seconds
}

output "function_max_instances" {
  description = "Maximum number of function instances"
  value       = google_cloudfunctions2_function.weather_api.service_config[0].max_instance_count
}

output "function_min_instances" {
  description = "Minimum number of function instances"
  value       = google_cloudfunctions2_function.weather_api.service_config[0].min_instance_count
}

# Storage Configuration Details
output "bucket_location" {
  description = "Geographic location of the storage bucket"
  value       = google_storage_bucket.website_bucket.location
}

output "bucket_storage_class" {
  description = "Storage class of the website bucket"
  value       = google_storage_bucket.website_bucket.storage_class
}

output "bucket_self_link" {
  description = "Self-link of the website storage bucket"
  value       = google_storage_bucket.website_bucket.self_link
}

# Security and Access Information
output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "function_ingress_settings" {
  description = "Ingress settings for the Cloud Function"
  value       = google_cloudfunctions2_function.weather_api.service_config[0].ingress_settings
}

output "bucket_public_access_prevention" {
  description = "Public access prevention setting for the bucket"
  value       = google_storage_bucket.website_bucket.public_access_prevention
}

# Application Configuration
output "default_city" {
  description = "Default city configured for weather data"
  value       = var.default_city
}

output "application_name" {
  description = "Base name of the application"
  value       = var.application_name
}

output "environment" {
  description = "Environment identifier"
  value       = var.environment
}

# Resource State Information
output "function_state" {
  description = "Current state of the Cloud Function"
  value       = google_cloudfunctions2_function.weather_api.state
}

output "function_update_time" {
  description = "Last update time of the Cloud Function"
  value       = google_cloudfunctions2_function.weather_api.update_time
}

output "bucket_time_created" {
  description = "Creation time of the storage bucket"
  value       = google_storage_bucket.website_bucket.time_created
}

# Cost and Resource Management
output "enabled_apis" {
  description = "List of APIs enabled for this deployment"
  value = [
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com"
  ]
}

output "resource_labels" {
  description = "Common labels applied to resources"
  value       = local.common_labels
}

# Deployment Information
output "deployment_info" {
  description = "Summary of deployment configuration"
  value = {
    project_id            = var.project_id
    region               = var.region
    application_name     = var.application_name
    environment          = var.environment
    function_runtime     = var.function_runtime
    function_memory      = var.function_memory
    bucket_location      = var.bucket_location
    storage_class        = var.storage_class
    cors_enabled         = var.enable_cors
    versioning_enabled   = var.enable_versioning
    public_access        = var.enable_public_bucket_access
    unauthenticated_access = var.allow_unauthenticated_function_access
  }
}

# Quick Start Instructions
output "quick_start_instructions" {
  description = "Instructions for accessing and testing the deployed application"
  value = <<-EOT
    Weather Dashboard Deployment Complete!
    
    🌤️  Website URL: https://storage.googleapis.com/${google_storage_bucket.website_bucket.name}/index.html
    🔗  API Endpoint: ${google_cloudfunctions2_function.weather_api.service_config[0].uri}
    
    Testing Commands:
    # Test the API directly
    curl "${google_cloudfunctions2_function.weather_api.service_config[0].uri}?city=London"
    
    # Check function logs
    gcloud functions logs read ${google_cloudfunctions2_function.weather_api.name} --region=${var.region}
    
    # View bucket contents
    gsutil ls gs://${google_storage_bucket.website_bucket.name}/
    
    Configuration:
    - Default City: ${var.default_city}
    - Function Runtime: ${var.function_runtime}
    - Memory: ${var.function_memory}
    - Timeout: ${var.function_timeout}s
    - Storage Class: ${var.storage_class}
    - Region: ${var.region}
  EOT
}

# Monitoring URLs (for Google Cloud Console)
output "monitoring_urls" {
  description = "URLs for monitoring the deployed resources"
  value = {
    function_console_url = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.weather_api.name}?project=${var.project_id}"
    bucket_console_url   = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.website_bucket.name}?project=${var.project_id}"
    logs_console_url     = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_function%22%0Aresource.labels.function_name%3D%22${google_cloudfunctions2_function.weather_api.name}%22?project=${var.project_id}"
    metrics_console_url  = "https://console.cloud.google.com/monitoring/dashboards/custom?project=${var.project_id}"
  }
}