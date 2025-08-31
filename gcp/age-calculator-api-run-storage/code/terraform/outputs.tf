# Outputs for Age Calculator API with Cloud Run and Storage
# This file defines all output values that will be displayed after deployment

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "service_name" {
  description = "Name of the deployed Cloud Run service"
  value       = google_cloud_run_service.age_calculator_api.name
}

output "service_url" {
  description = "URL of the deployed Cloud Run service"
  value       = google_cloud_run_service.age_calculator_api.status[0].url
}

output "service_location" {
  description = "Location of the Cloud Run service"
  value       = google_cloud_run_service.age_calculator_api.location
}

output "bucket_name" {
  description = "Name of the Cloud Storage bucket for request logs"
  value       = google_storage_bucket.request_logs.name
}

output "bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.request_logs.url
}

output "bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.request_logs.self_link
}

output "service_account_email" {
  description = "Email of the service account used by Cloud Run"
  value       = google_service_account.cloud_run_sa.email
}

output "service_account_name" {
  description = "Name of the service account used by Cloud Run"
  value       = google_service_account.cloud_run_sa.name
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.cloud_run_sa.unique_id
}

# API endpoint examples for testing
output "health_check_url" {
  description = "URL for health check endpoint"
  value       = "${google_cloud_run_service.age_calculator_api.status[0].url}/health"
}

output "calculate_age_url" {
  description = "URL for age calculation endpoint (POST)"
  value       = "${google_cloud_run_service.age_calculator_api.status[0].url}/calculate-age"
}

# Container and deployment information
output "container_image" {
  description = "Container image used by the Cloud Run service"
  value       = var.container_image != "" ? var.container_image : "gcr.io/cloudrun/hello (placeholder - update with actual image)"
}

output "service_revision" {
  description = "Current revision of the Cloud Run service"
  value       = google_cloud_run_service.age_calculator_api.status[0].latest_ready_revision_name
}

# Resource configuration details
output "memory_allocation" {
  description = "Memory allocated to each Cloud Run instance"
  value       = var.memory
}

output "cpu_allocation" {
  description = "CPU allocated to each Cloud Run instance"
  value       = var.cpu
}

output "max_instances" {
  description = "Maximum number of Cloud Run instances"
  value       = var.max_instances
}

output "concurrency" {
  description = "Maximum concurrent requests per instance"
  value       = var.concurrency
}

output "timeout_seconds" {
  description = "Request timeout in seconds"
  value       = var.timeout_seconds
}

# Storage configuration
output "storage_class" {
  description = "Storage class of the request logs bucket"
  value       = google_storage_bucket.request_logs.storage_class
}

output "bucket_lifecycle_enabled" {
  description = "Whether lifecycle rules are enabled for the bucket"
  value       = var.lifecycle_rules
}

# Security and access information
output "public_access_enabled" {
  description = "Whether public access is enabled for the Cloud Run service"
  value       = var.allow_unauthenticated
}

output "bucket_uniform_access" {
  description = "Whether uniform bucket-level access is enabled"
  value       = google_storage_bucket.request_logs.uniform_bucket_level_access
}

# Testing commands
output "curl_health_check_command" {
  description = "cURL command to test the health check endpoint"
  value       = "curl -X GET \"${google_cloud_run_service.age_calculator_api.status[0].url}/health\" -H \"Content-Type: application/json\""
}

output "curl_age_calculation_command" {
  description = "Example cURL command to test age calculation"
  value       = "curl -X POST \"${google_cloud_run_service.age_calculator_api.status[0].url}/calculate-age\" -H \"Content-Type: application/json\" -d '{\"birth_date\": \"1990-05-15T00:00:00Z\"}'"
}

# Resource management information
output "resource_labels" {
  description = "Labels applied to resources"
  value       = var.labels
}

output "random_suffix" {
  description = "Random suffix used for unique resource names"
  value       = random_id.suffix.hex
}

# Monitoring and logging
output "logs_command" {
  description = "Command to view Cloud Run service logs"
  value       = "gcloud logging read \"resource.type=cloud_run_revision AND resource.labels.service_name=${google_cloud_run_service.age_calculator_api.name}\" --limit 50 --format json"
}

output "bucket_logs_list_command" {
  description = "Command to list request logs in the bucket"
  value       = "gsutil ls -r gs://${google_storage_bucket.request_logs.name}/requests/"
}

# Cost optimization information
output "estimated_monthly_cost_info" {
  description = "Information about estimated monthly costs"
  value = {
    cloud_run = "Based on actual usage: ~$0.00-$2.00/month for low traffic"
    storage   = "~$0.02/GB/month for Standard storage class"
    note      = "Costs depend on actual usage patterns and data volumes"
  }
}