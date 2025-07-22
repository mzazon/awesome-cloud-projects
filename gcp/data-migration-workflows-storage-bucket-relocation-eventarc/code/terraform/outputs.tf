# Outputs for GCP Data Migration Workflows with Storage Bucket Relocation and Eventarc

# Project and basic configuration outputs
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where regional resources were created"
  value       = var.region
}

output "source_region" {
  description = "The GCP region of the source storage bucket"
  value       = var.source_region
}

output "destination_region" {
  description = "The GCP region of the destination storage bucket"
  value       = var.destination_region
}

# Storage bucket outputs
output "source_bucket_name" {
  description = "Name of the source storage bucket"
  value       = google_storage_bucket.source_bucket.name
}

output "source_bucket_url" {
  description = "URL of the source storage bucket"
  value       = google_storage_bucket.source_bucket.url
}

output "source_bucket_self_link" {
  description = "Self-link of the source storage bucket"
  value       = google_storage_bucket.source_bucket.self_link
}

output "destination_bucket_name" {
  description = "Name of the destination storage bucket"
  value       = google_storage_bucket.destination_bucket.name
}

output "destination_bucket_url" {
  description = "URL of the destination storage bucket"
  value       = google_storage_bucket.destination_bucket.url
}

output "destination_bucket_self_link" {
  description = "Self-link of the destination storage bucket"
  value       = google_storage_bucket.destination_bucket.self_link
}

output "function_source_bucket_name" {
  description = "Name of the bucket containing Cloud Function source code"
  value       = google_storage_bucket.function_source_bucket.name
}

# Service Account outputs
output "migration_automation_service_account_email" {
  description = "Email address of the migration automation service account"
  value       = google_service_account.migration_automation_sa.email
}

output "migration_automation_service_account_id" {
  description = "ID of the migration automation service account"
  value       = google_service_account.migration_automation_sa.account_id
}

output "migration_automation_service_account_unique_id" {
  description = "Unique ID of the migration automation service account"
  value       = google_service_account.migration_automation_sa.unique_id
}

# Cloud Functions outputs
output "pre_migration_validator_function_name" {
  description = "Name of the pre-migration validation Cloud Function"
  value       = google_cloudfunctions2_function.pre_migration_validator.name
}

output "pre_migration_validator_function_uri" {
  description = "URI of the pre-migration validation Cloud Function"
  value       = google_cloudfunctions2_function.pre_migration_validator.service_config[0].uri
}

output "migration_progress_monitor_function_name" {
  description = "Name of the migration progress monitor Cloud Function"
  value       = google_cloudfunctions2_function.migration_progress_monitor.name
}

output "migration_progress_monitor_function_uri" {
  description = "URI of the migration progress monitor Cloud Function"
  value       = google_cloudfunctions2_function.migration_progress_monitor.service_config[0].uri
}

output "post_migration_validator_function_name" {
  description = "Name of the post-migration validation Cloud Function"
  value       = google_cloudfunctions2_function.post_migration_validator.name
}

output "post_migration_validator_function_uri" {
  description = "URI of the post-migration validation Cloud Function"
  value       = google_cloudfunctions2_function.post_migration_validator.service_config[0].uri
}

# Eventarc triggers outputs
output "bucket_admin_trigger_name" {
  description = "Name of the bucket administrative events Eventarc trigger"
  value       = google_eventarc_trigger.bucket_admin_trigger.name
}

output "bucket_admin_trigger_uid" {
  description = "UID of the bucket administrative events Eventarc trigger"
  value       = google_eventarc_trigger.bucket_admin_trigger.uid
}

output "object_event_trigger_name" {
  description = "Name of the object-level events Eventarc trigger"
  value       = google_eventarc_trigger.object_event_trigger.name
}

output "object_event_trigger_uid" {
  description = "UID of the object-level events Eventarc trigger"
  value       = google_eventarc_trigger.object_event_trigger.uid
}

# BigQuery outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for audit logs"
  value       = google_bigquery_dataset.migration_audit.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset for audit logs"
  value       = google_bigquery_dataset.migration_audit.location
}

output "bigquery_dataset_self_link" {
  description = "Self-link of the BigQuery dataset for audit logs"
  value       = google_bigquery_dataset.migration_audit.self_link
}

# Logging outputs
output "migration_audit_sink_name" {
  description = "Name of the migration audit log sink"
  value       = google_logging_project_sink.migration_audit_sink.name
}

output "migration_audit_sink_writer_identity" {
  description = "Writer identity of the migration audit log sink"
  value       = google_logging_project_sink.migration_audit_sink.writer_identity
}

# Monitoring outputs
output "migration_alert_policy_name" {
  description = "Name of the migration alert policy"
  value       = google_monitoring_alert_policy.migration_alert_policy.name
}

output "migration_alert_policy_id" {
  description = "ID of the migration alert policy"
  value       = google_monitoring_alert_policy.migration_alert_policy.id
}

# Sample data outputs
output "sample_objects_created" {
  description = "List of sample objects created in the source bucket"
  value = [
    google_storage_bucket_object.sample_critical_data.name,
    google_storage_bucket_object.sample_archive_data.name,
    google_storage_bucket_object.sample_application_log.name
  ]
}

# Migration commands for manual execution
output "bucket_relocation_command" {
  description = "Command to initiate bucket relocation (run manually)"
  value       = "gcloud storage buckets relocate gs://${google_storage_bucket.source_bucket.name} --location=${var.destination_region}"
}

output "validation_trigger_command" {
  description = "Command to trigger pre-migration validation (run manually)"
  value       = "gcloud functions call ${google_cloudfunctions2_function.pre_migration_validator.name} --region=${var.region}"
}

# Useful gcloud commands
output "useful_commands" {
  description = "Useful gcloud commands for managing the migration"
  value = {
    list_source_bucket_objects = "gsutil ls -la gs://${google_storage_bucket.source_bucket.name}"
    list_destination_bucket_objects = "gsutil ls -la gs://${google_storage_bucket.destination_bucket.name}"
    check_bucket_location = "gsutil ls -L -b gs://${google_storage_bucket.source_bucket.name} | grep 'Location constraint'"
    view_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.migration_progress_monitor.name} --region=${var.region}"
    view_audit_logs = "gcloud logging read 'resource.type=\"gcs_bucket\" AND resource.labels.bucket_name=\"${google_storage_bucket.source_bucket.name}\"' --limit=10"
    query_bigquery_logs = "bq query --use_legacy_sql=false 'SELECT timestamp, protopayload_auditlog.methodName, protopayload_auditlog.resourceName FROM `${var.project_id}.${google_bigquery_dataset.migration_audit.dataset_id}.cloudaudit_googleapis_com_activity_*` WHERE protopayload_auditlog.serviceName = \"storage.googleapis.com\" ORDER BY timestamp DESC LIMIT 10'"
    check_eventarc_triggers = "gcloud eventarc triggers list --location=${var.region}"
    monitor_migration_progress = "gcloud storage operations list --filter='metadata.verb=relocate'"
  }
}

# Configuration summary
output "migration_configuration_summary" {
  description = "Summary of the migration configuration"
  value = {
    source_bucket = {
      name     = google_storage_bucket.source_bucket.name
      location = google_storage_bucket.source_bucket.location
      versioning_enabled = google_storage_bucket.source_bucket.versioning[0].enabled
      uniform_bucket_level_access = google_storage_bucket.source_bucket.uniform_bucket_level_access
    }
    destination_bucket = {
      name     = google_storage_bucket.destination_bucket.name
      location = google_storage_bucket.destination_bucket.location
      versioning_enabled = google_storage_bucket.destination_bucket.versioning[0].enabled
      uniform_bucket_level_access = google_storage_bucket.destination_bucket.uniform_bucket_level_access
    }
    automation_functions = {
      pre_migration_validator = google_cloudfunctions2_function.pre_migration_validator.name
      progress_monitor = google_cloudfunctions2_function.migration_progress_monitor.name
      post_migration_validator = google_cloudfunctions2_function.post_migration_validator.name
    }
    eventarc_triggers = {
      bucket_admin_trigger = google_eventarc_trigger.bucket_admin_trigger.name
      object_event_trigger = google_eventarc_trigger.object_event_trigger.name
    }
    monitoring_and_logging = {
      bigquery_dataset = google_bigquery_dataset.migration_audit.dataset_id
      audit_sink = google_logging_project_sink.migration_audit_sink.name
      alert_policy = google_monitoring_alert_policy.migration_alert_policy.name
    }
  }
}

# Resource URLs for easy access
output "resource_urls" {
  description = "URLs for accessing created resources in the GCP Console"
  value = {
    source_bucket_console = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.source_bucket.name}?project=${var.project_id}"
    destination_bucket_console = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.destination_bucket.name}?project=${var.project_id}"
    functions_console = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
    eventarc_console = "https://console.cloud.google.com/eventarc/triggers?project=${var.project_id}"
    bigquery_console = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!8m2!1s${var.project_id}!2s${google_bigquery_dataset.migration_audit.dataset_id}"
    monitoring_console = "https://console.cloud.google.com/monitoring/alerting/policies?project=${var.project_id}"
    logging_console = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
  }
}

# Security and compliance information
output "security_configuration" {
  description = "Security and compliance configuration details"
  value = {
    service_account_email = google_service_account.migration_automation_sa.email
    uniform_bucket_level_access_enabled = google_storage_bucket.source_bucket.uniform_bucket_level_access
    public_access_prevention_enabled = google_storage_bucket.source_bucket.public_access_prevention
    versioning_enabled = google_storage_bucket.source_bucket.versioning[0].enabled
    soft_delete_retention_days = var.soft_delete_retention_days
    audit_logging_enabled = true
    monitoring_alerts_enabled = true
  }
}

# Cost estimation information
output "cost_estimation_notes" {
  description = "Notes about cost estimation for the migration solution"
  value = {
    storage_costs = "Storage costs depend on data volume and storage class. Monitor usage in Cloud Billing."
    function_costs = "Cloud Functions are billed based on invocations, compute time, and memory usage."
    eventarc_costs = "Eventarc is billed based on the number of events processed."
    bigquery_costs = "BigQuery storage and query costs apply for audit log analysis."
    monitoring_costs = "Cloud Monitoring charges apply for custom metrics and alerting."
    cost_optimization_tips = [
      "Use lifecycle policies to transition objects to cheaper storage classes",
      "Set appropriate retention periods for audit logs",
      "Monitor and optimize Cloud Function memory allocation",
      "Consider using committed use discounts for sustained workloads"
    ]
  }
}