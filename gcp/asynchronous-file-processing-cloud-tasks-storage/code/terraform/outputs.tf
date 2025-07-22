# Project and region information
output "project_id" {
  description = "The GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "The GCP zone where resources are deployed"
  value       = var.zone
}

# Storage bucket outputs
output "upload_bucket_name" {
  description = "Name of the Cloud Storage bucket for file uploads"
  value       = google_storage_bucket.upload_bucket.name
}

output "upload_bucket_url" {
  description = "URL of the Cloud Storage bucket for file uploads"
  value       = google_storage_bucket.upload_bucket.url
}

output "results_bucket_name" {
  description = "Name of the Cloud Storage bucket for processed results"
  value       = google_storage_bucket.results_bucket.name
}

output "results_bucket_url" {
  description = "URL of the Cloud Storage bucket for processed results"
  value       = google_storage_bucket.results_bucket.url
}

# Container registry outputs
output "artifact_registry_repository" {
  description = "Name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_repo.name
}

output "artifact_registry_repository_url" {
  description = "URL of the Artifact Registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.repository_id}"
}

# Pub/Sub outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for file processing events"
  value       = google_pubsub_topic.processing_topic.name
}

output "pubsub_topic_id" {
  description = "Full ID of the Pub/Sub topic"
  value       = google_pubsub_topic.processing_topic.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription"
  value       = google_pubsub_subscription.processing_subscription.name
}

output "pubsub_subscription_id" {
  description = "Full ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.processing_subscription.id
}

# Cloud Tasks outputs
output "task_queue_name" {
  description = "Name of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.processing_queue.name
}

output "task_queue_id" {
  description = "Full ID of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.processing_queue.id
}

output "task_queue_location" {
  description = "Location of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.processing_queue.location
}

# Cloud Run service outputs
output "upload_service_name" {
  description = "Name of the upload Cloud Run service"
  value       = google_cloud_run_v2_service.upload_service.name
}

output "upload_service_url" {
  description = "URL of the upload Cloud Run service"
  value       = google_cloud_run_v2_service.upload_service.uri
}

output "upload_service_endpoint" {
  description = "Upload endpoint URL"
  value       = "${google_cloud_run_v2_service.upload_service.uri}/upload"
}

output "processing_service_name" {
  description = "Name of the processing Cloud Run service"
  value       = google_cloud_run_v2_service.processing_service.name
}

output "processing_service_url" {
  description = "URL of the processing Cloud Run service"
  value       = google_cloud_run_v2_service.processing_service.uri
}

output "processing_service_endpoint" {
  description = "Processing endpoint URL"
  value       = "${google_cloud_run_v2_service.processing_service.uri}/process"
}

# Service account outputs
output "upload_service_account_email" {
  description = "Email of the upload service account"
  value       = google_service_account.upload_service_sa.email
}

output "processing_service_account_email" {
  description = "Email of the processing service account"
  value       = google_service_account.processing_service_sa.email
}

# Monitoring outputs
output "monitoring_dashboard_id" {
  description = "ID of the monitoring dashboard (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_dashboard.file_processing_dashboard[0].id : null
}

output "monitoring_alert_policy_id" {
  description = "ID of the monitoring alert policy (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.failed_tasks[0].id : null
}

# Resource naming outputs
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Configuration outputs for deployment scripts
output "deployment_configuration" {
  description = "Configuration values for deployment scripts"
  value = {
    project_id                = var.project_id
    region                    = var.region
    zone                      = var.zone
    upload_bucket_name        = google_storage_bucket.upload_bucket.name
    results_bucket_name       = google_storage_bucket.results_bucket.name
    pubsub_topic_name         = google_pubsub_topic.processing_topic.name
    task_queue_name           = google_cloud_tasks_queue.processing_queue.name
    upload_service_name       = google_cloud_run_v2_service.upload_service.name
    processing_service_name   = google_cloud_run_v2_service.processing_service.name
    upload_service_url        = google_cloud_run_v2_service.upload_service.uri
    processing_service_url    = google_cloud_run_v2_service.processing_service.uri
    artifact_registry_repo    = google_artifact_registry_repository.container_repo.name
    resource_suffix           = local.resource_suffix
  }
  sensitive = false
}

# Environment variables for Cloud Run services
output "upload_service_env_vars" {
  description = "Environment variables for the upload service"
  value = {
    PROJECT_ID    = var.project_id
    REGION        = var.region
    UPLOAD_BUCKET = google_storage_bucket.upload_bucket.name
    TASK_QUEUE    = google_cloud_tasks_queue.processing_queue.name
    PROCESSOR_URL = "${google_cloud_run_v2_service.processing_service.uri}/process"
  }
  sensitive = false
}

output "processing_service_env_vars" {
  description = "Environment variables for the processing service"
  value = {
    PROJECT_ID      = var.project_id
    RESULTS_BUCKET  = google_storage_bucket.results_bucket.name
  }
  sensitive = false
}

# Service URLs for testing
output "service_endpoints" {
  description = "All service endpoints for testing and integration"
  value = {
    upload_health_check     = "${google_cloud_run_v2_service.upload_service.uri}/health"
    upload_endpoint         = "${google_cloud_run_v2_service.upload_service.uri}/upload"
    processing_health_check = "${google_cloud_run_v2_service.processing_service.uri}/health"
    processing_endpoint     = "${google_cloud_run_v2_service.processing_service.uri}/process"
  }
}

# IAM and security information
output "security_configuration" {
  description = "Security configuration details"
  value = {
    upload_service_account    = google_service_account.upload_service_sa.email
    processing_service_account = google_service_account.processing_service_sa.email
    upload_service_public     = var.allow_unauthenticated_upload
    bucket_public_access      = "enforced" # Always enforced for security
    vulnerability_scanning    = var.enable_vulnerability_scanning
  }
}

# Cost monitoring information
output "cost_monitoring" {
  description = "Information for cost monitoring and optimization"
  value = {
    upload_bucket_storage_class   = var.bucket_storage_class
    results_bucket_storage_class  = var.bucket_storage_class
    bucket_autoclass_enabled      = var.enable_bucket_autoclass
    bucket_versioning_enabled     = var.enable_bucket_versioning
    upload_service_max_instances  = var.upload_service_max_instances
    processing_service_max_instances = var.processing_service_max_instances
    monitoring_enabled            = var.enable_monitoring
  }
}