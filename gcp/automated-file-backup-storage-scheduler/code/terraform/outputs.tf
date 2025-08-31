# Output values for the automated file backup solution
# These outputs provide essential information for verification and integration

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "primary_bucket_name" {
  description = "Name of the primary storage bucket"
  value       = google_storage_bucket.primary.name
}

output "primary_bucket_url" {
  description = "URL of the primary storage bucket"
  value       = google_storage_bucket.primary.url
}

output "backup_bucket_name" {
  description = "Name of the backup storage bucket"
  value       = google_storage_bucket.backup.name
}

output "backup_bucket_url" {
  description = "URL of the backup storage bucket"
  value       = google_storage_bucket.backup.url
}

output "cloud_function_name" {
  description = "Name of the backup Cloud Function"
  value       = google_cloudfunctions2_function.backup_function.name
}

output "cloud_function_uri" {
  description = "URI of the backup Cloud Function"
  value       = google_cloudfunctions2_function.backup_function.service_config[0].uri
}

output "cloud_function_service_account" {
  description = "Service account email used by the Cloud Function"
  value       = google_service_account.backup_function.email
}

output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.backup_schedule.name
}

output "scheduler_job_schedule" {
  description = "Cron schedule for the backup job"
  value       = google_cloud_scheduler_job.backup_schedule.schedule
}

output "scheduler_service_account" {
  description = "Service account email used by Cloud Scheduler"
  value       = google_service_account.scheduler.email
}

output "backup_schedule_next_run" {
  description = "Information about the backup schedule"
  value = {
    schedule  = google_cloud_scheduler_job.backup_schedule.schedule
    time_zone = google_cloud_scheduler_job.backup_schedule.time_zone
    state     = google_cloud_scheduler_job.backup_schedule.state
  }
}

output "storage_configuration" {
  description = "Storage bucket configuration details"
  value = {
    primary_storage_class = google_storage_bucket.primary.storage_class
    backup_storage_class  = google_storage_bucket.backup.storage_class
    versioning_enabled    = var.enable_versioning
    region               = var.region
  }
}

output "function_configuration" {
  description = "Cloud Function configuration details"
  value = {
    memory_mb      = var.function_memory
    timeout_seconds = var.function_timeout
    runtime        = "python311"
    entry_point    = "backup_files"
  }
}

output "monitoring_resources" {
  description = "Monitoring and logging resources created"
  value = {
    log_metric_name    = google_logging_metric.backup_errors.name
    alert_policy_name  = google_monitoring_alert_policy.backup_failure_alert.display_name
  }
}

output "sample_files_created" {
  description = "Whether sample files were created for testing"
  value       = var.create_sample_files
}

output "verification_commands" {
  description = "Commands to verify the backup solution"
  value = {
    list_primary_files = "gcloud storage ls gs://${google_storage_bucket.primary.name}/"
    list_backup_files  = "gcloud storage ls gs://${google_storage_bucket.backup.name}/"
    check_function     = "gcloud functions describe ${google_cloudfunctions2_function.backup_function.name} --region=${var.region} --gen2"
    check_scheduler    = "gcloud scheduler jobs describe ${google_cloud_scheduler_job.backup_schedule.name} --location=${var.region}"
    test_function      = "curl -X POST '${google_cloudfunctions2_function.backup_function.service_config[0].uri}' -H 'Content-Type: application/json' -d '{}'"
    view_logs         = "gcloud functions logs read ${google_cloudfunctions2_function.backup_function.name} --region=${var.region} --gen2 --limit=10"
  }
}

output "cost_optimization_notes" {
  description = "Notes about cost optimization features"
  value = {
    primary_lifecycle_rules = "Files transition to NEARLINE after 30 days, COLDLINE after 90 days"
    backup_lifecycle_rules  = "Backups transition to COLDLINE after 60 days, ARCHIVE after 180 days"
    storage_classes = {
      primary = google_storage_bucket.primary.storage_class
      backup  = google_storage_bucket.backup.storage_class
    }
    function_scaling = "Function scales from 0 to 10 instances based on demand"
  }
}

output "security_features" {
  description = "Security features implemented"
  value = {
    uniform_bucket_access     = "Enabled on both buckets"
    public_access_prevention  = "Enforced on both buckets"
    service_account_principle = "Minimal required permissions assigned"
    function_ingress         = "Internal only (ALLOW_INTERNAL_ONLY)"
    iam_roles = {
      function_primary_bucket = "roles/storage.objectViewer"
      function_backup_bucket  = "roles/storage.objectAdmin"
      function_logging       = "roles/logging.logWriter"
      scheduler_function     = "roles/cloudfunctions.invoker"
    }
  }
}

output "cleanup_commands" {
  description = "Commands to clean up resources (use with caution)"
  value = {
    delete_scheduler = "gcloud scheduler jobs delete ${google_cloud_scheduler_job.backup_schedule.name} --location=${var.region} --quiet"
    delete_function  = "gcloud functions delete ${google_cloudfunctions2_function.backup_function.name} --region=${var.region} --gen2 --quiet"
    delete_buckets   = "gcloud storage rm -r gs://${google_storage_bucket.primary.name} gs://${google_storage_bucket.backup.name}"
    terraform_destroy = "terraform destroy -auto-approve"
  }
}