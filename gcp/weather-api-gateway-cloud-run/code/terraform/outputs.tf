# Output values for Weather API Gateway infrastructure
# These outputs provide important information for verification and integration

output "service_url" {
  description = "URL of the deployed Cloud Run service"
  value       = google_cloud_run_service.weather_api_gateway.status[0].url
}

output "service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_service.weather_api_gateway.name
}

output "service_location" {
  description = "Location (region) of the Cloud Run service"
  value       = google_cloud_run_service.weather_api_gateway.location
}

output "bucket_name" {
  description = "Name of the Cloud Storage bucket used for caching"
  value       = google_storage_bucket.weather_cache.name
}

output "bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.weather_cache.url
}

output "service_account_email" {
  description = "Email of the service account used by Cloud Run"
  value       = google_service_account.cloud_run_service.email
}

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

# API endpoints for testing
output "weather_api_endpoint" {
  description = "Full URL for the weather API endpoint"
  value       = "${google_cloud_run_service.weather_api_gateway.status[0].url}/weather"
}

output "health_check_endpoint" {
  description = "Full URL for the health check endpoint"
  value       = "${google_cloud_run_service.weather_api_gateway.status[0].url}/health"
}

# Resource identifiers for management
output "service_id" {
  description = "Full resource ID of the Cloud Run service"
  value       = google_cloud_run_service.weather_api_gateway.id
}

output "bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.weather_cache.self_link
}