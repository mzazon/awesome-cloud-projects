# Outputs for the Automated Storage Lifecycle Management solution
# These outputs provide important information about the created infrastructure

output "bucket_name" {
  description = "Name of the main Cloud Storage bucket with lifecycle policies"
  value       = google_storage_bucket.lifecycle_bucket.name
}

output "bucket_url" {
  description = "URL of the main Cloud Storage bucket"
  value       = google_storage_bucket.lifecycle_bucket.url
}

output "bucket_self_link" {
  description = "Self-link of the main Cloud Storage bucket"
  value       = google_storage_bucket.lifecycle_bucket.self_link
}

output "logs_bucket_name" {
  description = "Name of the logs storage bucket (if monitoring is enabled)"
  value       = var.enable_monitoring ? google_storage_bucket.logs_bucket[0].name : null
}

output "logs_bucket_url" {
  description = "URL of the logs storage bucket (if monitoring is enabled)"
  value       = var.enable_monitoring ? google_storage_bucket.logs_bucket[0].url : null
}

output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for lifecycle automation"
  value       = google_cloud_scheduler_job.lifecycle_job.name
}

output "scheduler_job_id" {
  description = "Full resource ID of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.lifecycle_job.id
}

output "logging_sink_name" {
  description = "Name of the Cloud Logging sink (if monitoring is enabled)"
  value       = var.enable_monitoring ? google_logging_project_sink.storage_lifecycle_sink[0].name : null
}

output "logging_sink_writer_identity" {
  description = "Writer identity of the logging sink (if monitoring is enabled)"
  value       = var.enable_monitoring ? google_logging_project_sink.storage_lifecycle_sink[0].writer_identity : null
}

output "lifecycle_rules_summary" {
  description = "Summary of configured lifecycle rules"
  value = {
    nearline_transition_days = var.lifecycle_rules.nearline_age_days
    coldline_transition_days = var.lifecycle_rules.coldline_age_days
    archive_transition_days  = var.lifecycle_rules.archive_age_days
    deletion_age_days       = var.lifecycle_rules.delete_age_days
  }
}

output "sample_files_created" {
  description = "List of sample files created for testing (if enabled)"
  value       = var.enable_sample_data ? keys(google_storage_bucket_object.sample_files) : []
}

output "project_id" {
  description = "Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources were created"
  value       = var.region
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Useful commands for post-deployment validation
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    list_bucket_contents = "gcloud storage ls -L gs://${google_storage_bucket.lifecycle_bucket.name}/"
    describe_bucket     = "gcloud storage buckets describe gs://${google_storage_bucket.lifecycle_bucket.name}"
    check_scheduler_job = "gcloud scheduler jobs describe ${google_cloud_scheduler_job.lifecycle_job.name} --location=${var.region}"
    view_logs          = var.enable_monitoring ? "gcloud logging read 'resource.type=\"gcs_bucket\" AND resource.labels.bucket_name=\"${google_storage_bucket.lifecycle_bucket.name}\"' --limit=10" : "Monitoring not enabled"
  }
}

# Web console URLs for easy access
output "console_urls" {
  description = "Google Cloud Console URLs for managing resources"
  value = {
    storage_bucket = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.lifecycle_bucket.name}"
    scheduler_jobs = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
    logging        = var.enable_monitoring ? "https://console.cloud.google.com/logs/viewer?project=${var.project_id}" : "Monitoring not enabled"
    monitoring     = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
  }
}

# Cost optimization insights
output "cost_optimization_info" {
  description = "Information about cost optimization through lifecycle policies"
  value = {
    storage_classes = {
      standard = "Immediate access, highest cost"
      nearline = "Access < 1/month, 50% cost reduction"
      coldline = "Access < 1/quarter, 75% cost reduction" 
      archive  = "Access < 1/year, 80% cost reduction"
    }
    transition_schedule = "Standard -> Nearline (${var.lifecycle_rules.nearline_age_days}d) -> Coldline (${var.lifecycle_rules.coldline_age_days}d) -> Archive (${var.lifecycle_rules.archive_age_days}d) -> Delete (${var.lifecycle_rules.delete_age_days}d)"
    estimated_savings  = "Up to 80% storage cost reduction through automated lifecycle management"
  }
}

# Security and compliance information
output "security_features" {
  description = "Security and compliance features configured"
  value = {
    uniform_bucket_level_access = var.enable_uniform_bucket_level_access
    versioning_enabled         = var.enable_versioning
    retention_policy_days      = var.retention_policy_days > 0 ? var.retention_policy_days : "Not configured"
    monitoring_enabled         = var.enable_monitoring
    encryption_at_rest        = "Google-managed encryption keys (default)"
    data_classification       = "Automated based on access patterns and age"
  }
}