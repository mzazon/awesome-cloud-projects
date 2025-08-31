# Outputs for License Compliance Scanner Infrastructure
# This file defines outputs that provide important information after deployment

# Project and Location Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "zone" {
  description = "The GCP zone where resources were deployed"
  value       = var.zone
}

# Cloud Storage Outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for compliance reports"
  value       = google_storage_bucket.compliance_reports.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.compliance_reports.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.compliance_reports.self_link
}

output "reports_path" {
  description = "Path where compliance reports are stored in the bucket"
  value       = "${google_storage_bucket.compliance_reports.url}/reports/"
}

# Cloud Source Repository Outputs
output "repository_name" {
  description = "Name of the Cloud Source Repository"
  value       = google_sourcerepo_repository.sample_app.name
}

output "repository_url" {
  description = "URL for cloning the Cloud Source Repository"
  value       = google_sourcerepo_repository.sample_app.url
}

output "repository_clone_url_http" {
  description = "HTTP clone URL for the Cloud Source Repository"
  value       = "https://source.developers.google.com/p/${var.project_id}/r/${google_sourcerepo_repository.sample_app.name}"
}

output "repository_clone_url_ssh" {
  description = "SSH clone URL for the Cloud Source Repository"
  value       = "ssh://source.developers.google.com:2022/p/${var.project_id}/r/${google_sourcerepo_repository.sample_app.name}"
}

# Cloud Function Outputs
output "function_name" {
  description = "Name of the license scanner Cloud Function"
  value       = google_cloudfunctions_function.license_scanner.name
}

output "function_url" {
  description = "HTTPS trigger URL for the Cloud Function"
  value       = google_cloudfunctions_function.license_scanner.https_trigger_url
}

output "function_source_archive_url" {
  description = "Source archive URL for the Cloud Function"
  value       = google_cloudfunctions_function.license_scanner.source_archive_url
}

output "function_status" {
  description = "Current status of the Cloud Function"
  value       = google_cloudfunctions_function.license_scanner.status
}

output "function_runtime" {
  description = "Runtime environment of the Cloud Function"
  value       = google_cloudfunctions_function.license_scanner.runtime
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function"
  value       = "${google_cloudfunctions_function.license_scanner.available_memory_mb}MB"
}

output "function_timeout" {
  description = "Timeout setting for the Cloud Function"
  value       = "${google_cloudfunctions_function.license_scanner.timeout}s"
}

# Service Account Outputs
output "service_account_email" {
  description = "Email address of the Cloud Function service account"
  value       = var.create_service_account ? google_service_account.function_sa[0].email : null
}

output "service_account_id" {
  description = "ID of the Cloud Function service account"
  value       = var.create_service_account ? google_service_account.function_sa[0].id : null
}

output "service_account_unique_id" {
  description = "Unique ID of the Cloud Function service account"
  value       = var.create_service_account ? google_service_account.function_sa[0].unique_id : null
}

# Cloud Scheduler Outputs
output "daily_scheduler_job_name" {
  description = "Name of the daily license scan scheduler job"
  value       = google_cloud_scheduler_job.daily_scan.name
}

output "daily_scheduler_job_id" {
  description = "ID of the daily license scan scheduler job"
  value       = google_cloud_scheduler_job.daily_scan.id
}

output "daily_scan_schedule" {
  description = "Cron schedule for daily license scans"
  value       = google_cloud_scheduler_job.daily_scan.schedule
}

output "weekly_scheduler_job_name" {
  description = "Name of the weekly license scan scheduler job"
  value       = google_cloud_scheduler_job.weekly_scan.name
}

output "weekly_scheduler_job_id" {
  description = "ID of the weekly license scan scheduler job"
  value       = google_cloud_scheduler_job.weekly_scan.id
}

output "weekly_scan_schedule" {
  description = "Cron schedule for weekly license scans"
  value       = google_cloud_scheduler_job.weekly_scan.schedule
}

output "scheduler_timezone" {
  description = "Timezone configured for scheduler jobs"
  value       = var.scheduler_timezone
}

# API Services Outputs
output "enabled_apis" {
  description = "List of Google Cloud APIs that were enabled"
  value       = [for api in google_project_service.required_apis : api.service]
}

# Random Identifier Outputs
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Environment Configuration Outputs
output "environment" {
  description = "Environment name for this deployment"
  value       = var.environment
}

output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = var.resource_prefix
}

# Security Configuration Outputs
output "function_allow_unauthenticated" {
  description = "Whether the Cloud Function allows unauthenticated access"
  value       = var.function_allow_unauthenticated
}

output "bucket_versioning_enabled" {
  description = "Whether versioning is enabled on the storage bucket"
  value       = var.enable_bucket_versioning
}

# Monitoring and Logging Outputs
output "log_retention_days" {
  description = "Number of days logs are retained"
  value       = var.log_retention_days
}

output "monitoring_enabled" {
  description = "Whether monitoring is enabled for the function"
  value       = var.enable_monitoring
}

# Testing and Validation Outputs
output "test_function_command" {
  description = "Command to test the license scanner function"
  value       = "curl -X POST ${google_cloudfunctions_function.license_scanner.https_trigger_url} -H 'Content-Type: application/json' -d '{\"test\": true}'"
}

output "list_reports_command" {
  description = "Command to list compliance reports in the bucket"
  value       = "gsutil ls gs://${google_storage_bucket.compliance_reports.name}/reports/"
}

output "download_latest_report_command" {
  description = "Command to download the latest compliance report"
  value       = "gsutil cp $(gsutil ls gs://${google_storage_bucket.compliance_reports.name}/reports/ | tail -1) ./latest-report.json"
}

# Resource URLs for Management
output "cloud_console_function_url" {
  description = "Google Cloud Console URL for the Cloud Function"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.license_scanner.name}?project=${var.project_id}"
}

output "cloud_console_storage_url" {
  description = "Google Cloud Console URL for the Storage bucket"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.compliance_reports.name}?project=${var.project_id}"
}

output "cloud_console_scheduler_url" {
  description = "Google Cloud Console URL for Cloud Scheduler"
  value       = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
}

output "cloud_console_source_repo_url" {
  description = "Google Cloud Console URL for Source Repository"
  value       = "https://console.cloud.google.com/code/develop/browse/${google_sourcerepo_repository.sample_app.name}?project=${var.project_id}"
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources and their configuration"
  value = {
    project_id                = var.project_id
    region                   = var.region
    environment              = var.environment
    storage_bucket           = google_storage_bucket.compliance_reports.name
    repository_name          = google_sourcerepo_repository.sample_app.name
    function_name            = google_cloudfunctions_function.license_scanner.name
    function_url             = google_cloudfunctions_function.license_scanner.https_trigger_url
    daily_scan_schedule      = google_cloud_scheduler_job.daily_scan.schedule
    weekly_scan_schedule     = google_cloud_scheduler_job.weekly_scan.schedule
    service_account_email    = var.create_service_account ? google_service_account.function_sa[0].email : null
    unauthenticated_access   = var.function_allow_unauthenticated
    versioning_enabled       = var.enable_bucket_versioning
    monitoring_enabled       = var.enable_monitoring
  }
}