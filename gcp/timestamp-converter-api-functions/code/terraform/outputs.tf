# Terraform Outputs for Timestamp Converter API Infrastructure
# This file defines outputs that provide important information about deployed resources

# Cloud Function Information
output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.timestamp_converter.name
}

output "function_url" {
  description = "HTTP trigger URL for the Cloud Function"
  value       = google_cloudfunctions2_function.timestamp_converter.service_config[0].uri
}

output "function_status" {
  description = "Current state/status of the Cloud Function"
  value       = google_cloudfunctions2_function.timestamp_converter.state
}

output "function_location" {
  description = "GCP region where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.timestamp_converter.location
}

output "function_runtime" {
  description = "Runtime environment of the Cloud Function"
  value       = google_cloudfunctions2_function.timestamp_converter.build_config[0].runtime
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function"
  value       = google_cloudfunctions2_function.timestamp_converter.service_config[0].available_memory
}

output "function_timeout" {
  description = "Timeout setting for the Cloud Function in seconds"
  value       = google_cloudfunctions2_function.timestamp_converter.service_config[0].timeout_seconds
}

output "function_max_instances" {
  description = "Maximum number of function instances allowed"
  value       = google_cloudfunctions2_function.timestamp_converter.service_config[0].max_instance_count
}

output "function_min_instances" {
  description = "Minimum number of function instances to keep warm"
  value       = google_cloudfunctions2_function.timestamp_converter.service_config[0].min_instance_count
}

# Cloud Storage Information
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.function_source.url
}

output "storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.function_source.location
}

output "storage_bucket_storage_class" {
  description = "Storage class of the Cloud Storage bucket"
  value       = google_storage_bucket.function_source.storage_class
}

output "source_archive_object" {
  description = "Name of the source code archive object in Cloud Storage"
  value       = google_storage_bucket_object.function_source.name
}

# Service Account Information
output "function_service_account_email" {
  description = "Email address of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "function_service_account_id" {
  description = "Unique ID of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.unique_id
}

# Security and Access Information
output "public_access_enabled" {
  description = "Whether unauthenticated access is enabled for the Cloud Function"
  value       = var.allow_unauthenticated_invocations
}

output "ingress_settings" {
  description = "Ingress settings configured for the Cloud Function"
  value       = google_cloudfunctions2_function.timestamp_converter.service_config[0].ingress_settings
}

# Project and Resource Information
output "project_id" {
  description = "GCP project ID where resources are deployed"
  value       = var.project_id
}

output "deployment_region" {
  description = "GCP region used for resource deployment"
  value       = var.region
}

output "deployment_id" {
  description = "Unique deployment identifier (random suffix)"
  value       = random_id.suffix.hex
}

# API Testing Information
output "test_urls" {
  description = "Example URLs for testing the timestamp converter API"
  value = {
    current_timestamp = "${google_cloudfunctions2_function.timestamp_converter.service_config[0].uri}?timestamp=now&timezone=UTC&format=human"
    specific_timestamp = "${google_cloudfunctions2_function.timestamp_converter.service_config[0].uri}?timestamp=1609459200&timezone=US/Eastern&format=iso"
    custom_format = "${google_cloudfunctions2_function.timestamp_converter.service_config[0].uri}?timestamp=1641024000&timezone=Europe/London&format=rfc"
  }
}

# Cost and Usage Information
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = var.required_apis
}

output "resource_labels" {
  description = "Labels applied to resources for organization and billing"
  value       = local.common_labels
}

# Function Configuration Summary
output "function_configuration_summary" {
  description = "Summary of key Cloud Function configuration parameters"
  value = {
    name                    = google_cloudfunctions2_function.timestamp_converter.name
    runtime                = google_cloudfunctions2_function.timestamp_converter.build_config[0].runtime
    memory                 = google_cloudfunctions2_function.timestamp_converter.service_config[0].available_memory
    timeout                = google_cloudfunctions2_function.timestamp_converter.service_config[0].timeout_seconds
    max_instances          = google_cloudfunctions2_function.timestamp_converter.service_config[0].max_instance_count
    min_instances          = google_cloudfunctions2_function.timestamp_converter.service_config[0].min_instance_count
    concurrent_requests    = google_cloudfunctions2_function.timestamp_converter.service_config[0].max_instance_request_concurrency
    ingress_settings      = google_cloudfunctions2_function.timestamp_converter.service_config[0].ingress_settings
    public_access         = var.allow_unauthenticated_invocations
  }
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Instructions for using the deployed timestamp converter API"
  value = <<-EOT
    
    🎉 Timestamp Converter API Successfully Deployed!
    
    Function URL: ${google_cloudfunctions2_function.timestamp_converter.service_config[0].uri}
    
    Usage Examples:
    
    1. Convert current timestamp:
       curl "${google_cloudfunctions2_function.timestamp_converter.service_config[0].uri}?timestamp=now&timezone=UTC&format=human"
    
    2. Convert specific timestamp with timezone:
       curl "${google_cloudfunctions2_function.timestamp_converter.service_config[0].uri}?timestamp=1609459200&timezone=US/Eastern&format=iso"
    
    3. Get all formats for a timestamp:
       curl "${google_cloudfunctions2_function.timestamp_converter.service_config[0].uri}?timestamp=1641024000&timezone=Europe/London"
    
    Available Parameters:
    - timestamp: Unix timestamp (seconds) or "now" for current time
    - timezone: Timezone name (e.g., UTC, US/Eastern, Europe/London) 
    - format: Output format (iso, rfc, human, date, time)
    
    Storage Bucket: ${google_storage_bucket.function_source.name}
    Service Account: ${google_service_account.function_sa.email}
    
    💡 Monitor function performance in Cloud Monitoring
    💡 View function logs in Cloud Logging
    
  EOT
}