# Output values for the QR Code Generator infrastructure
# These outputs provide important information for verification and integration

output "service_url" {
  description = "URL of the deployed Cloud Run service"
  value       = google_cloud_run_service.qr_code_api.status[0].url
}

output "service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_service.qr_code_api.name
}

output "service_region" {
  description = "Region where the Cloud Run service is deployed"
  value       = google_cloud_run_service.qr_code_api.location
}

output "bucket_name" {
  description = "Name of the Cloud Storage bucket for QR codes"
  value       = google_storage_bucket.qr_codes.name
}

output "bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.qr_codes.url
}

output "bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.qr_codes.self_link
}

output "service_account_email" {
  description = "Email of the service account used by Cloud Run"
  value       = google_service_account.cloudrun_sa.email
}

output "service_account_id" {
  description = "ID of the service account used by Cloud Run"
  value       = google_service_account.cloudrun_sa.account_id
}

output "project_id" {
  description = "GCP project ID where resources are deployed"
  value       = var.project_id
}

output "enabled_apis" {
  description = "List of APIs that were enabled for this deployment"
  value       = var.enable_apis ? [for api in google_project_service.apis : api.service] : []
}

# API endpoints for testing
output "health_check_url" {
  description = "Health check endpoint URL"
  value       = "${google_cloud_run_service.qr_code_api.status[0].url}/"
}

output "generate_endpoint" {
  description = "QR code generation endpoint URL"
  value       = "${google_cloud_run_service.qr_code_api.status[0].url}/generate"
}

output "list_endpoint" {
  description = "QR codes listing endpoint URL"
  value       = "${google_cloud_run_service.qr_code_api.status[0].url}/list"
}

# Testing commands
output "curl_health_check" {
  description = "cURL command to test the health check endpoint"
  value       = "curl -s '${google_cloud_run_service.qr_code_api.status[0].url}/' | jq '.'"
}

output "curl_generate_qr" {
  description = "cURL command example to generate a QR code"
  value       = "curl -X POST '${google_cloud_run_service.qr_code_api.status[0].url}/generate' -H 'Content-Type: application/json' -d '{\"text\": \"https://cloud.google.com/run\"}' | jq '.'"
}

output "curl_list_qr_codes" {
  description = "cURL command to list all QR codes"
  value       = "curl -s '${google_cloud_run_service.qr_code_api.status[0].url}/list' | jq '.'"
}

# Resource identifiers for integration
output "cloud_run_service_id" {
  description = "Full resource ID of the Cloud Run service"
  value       = "projects/${var.project_id}/locations/${var.region}/services/${google_cloud_run_service.qr_code_api.name}"
}

output "storage_bucket_id" {
  description = "Full resource ID of the Cloud Storage bucket"
  value       = "projects/${var.project_id}/buckets/${google_storage_bucket.qr_codes.name}"
}

# Configuration summary
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    service_url       = google_cloud_run_service.qr_code_api.status[0].url
    bucket_name       = google_storage_bucket.qr_codes.name
    service_account   = google_service_account.cloudrun_sa.email
    region           = var.region
    project_id       = var.project_id
    public_access    = var.allow_public_access
    max_instances    = var.max_instances
    memory_limit     = var.service_memory
    cpu_limit        = var.service_cpu
  }
}