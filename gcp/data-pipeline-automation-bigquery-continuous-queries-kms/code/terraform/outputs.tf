# Output values for GCP data pipeline automation infrastructure

#------------------------------------------------------------------------------
# Project and Regional Information
#------------------------------------------------------------------------------

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

#------------------------------------------------------------------------------
# Cloud KMS Outputs
#------------------------------------------------------------------------------

output "kms_keyring_name" {
  description = "The name of the Cloud KMS key ring"
  value       = google_kms_key_ring.pipeline_keyring.name
}

output "kms_keyring_id" {
  description = "The full resource ID of the Cloud KMS key ring"
  value       = google_kms_key_ring.pipeline_keyring.id
}

output "data_encryption_key_name" {
  description = "The name of the primary data encryption key"
  value       = google_kms_crypto_key.data_encryption_key.name
}

output "data_encryption_key_id" {
  description = "The full resource ID of the primary data encryption key"
  value       = google_kms_crypto_key.data_encryption_key.id
  sensitive   = true
}

output "column_encryption_key_name" {
  description = "The name of the column-level encryption key"
  value       = google_kms_crypto_key.column_encryption_key.name
}

output "column_encryption_key_id" {
  description = "The full resource ID of the column-level encryption key"
  value       = google_kms_crypto_key.column_encryption_key.id
  sensitive   = true
}

output "key_rotation_period" {
  description = "The automatic rotation period for KMS keys"
  value       = var.key_rotation_period
}

#------------------------------------------------------------------------------
# BigQuery Outputs
#------------------------------------------------------------------------------

output "bigquery_dataset_id" {
  description = "The ID of the BigQuery dataset"
  value       = google_bigquery_dataset.streaming_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "The location of the BigQuery dataset"
  value       = google_bigquery_dataset.streaming_analytics.location
}

output "bigquery_dataset_friendly_name" {
  description = "The friendly name of the BigQuery dataset"
  value       = google_bigquery_dataset.streaming_analytics.friendly_name
}

output "raw_events_table_id" {
  description = "The ID of the raw events table"
  value       = google_bigquery_table.raw_events.table_id
}

output "processed_events_table_id" {
  description = "The ID of the processed events table"
  value       = google_bigquery_table.processed_events.table_id
}

output "encrypted_user_data_table_id" {
  description = "The ID of the encrypted user data table"
  value       = google_bigquery_table.encrypted_user_data.table_id
}

output "bigquery_tables" {
  description = "Map of all BigQuery tables created"
  value = {
    raw_events         = google_bigquery_table.raw_events.table_id
    processed_events   = google_bigquery_table.processed_events.table_id
    encrypted_user_data = google_bigquery_table.encrypted_user_data.table_id
  }
}

#------------------------------------------------------------------------------
# Cloud Pub/Sub Outputs
#------------------------------------------------------------------------------

output "pubsub_topic_name" {
  description = "The name of the main Pub/Sub topic"
  value       = google_pubsub_topic.streaming_events.name
}

output "pubsub_topic_id" {
  description = "The full resource ID of the main Pub/Sub topic"
  value       = google_pubsub_topic.streaming_events.id
}

output "pubsub_subscription_name" {
  description = "The name of the BigQuery streaming subscription"
  value       = google_pubsub_subscription.bq_streaming_sub.name
}

output "pubsub_subscription_id" {
  description = "The full resource ID of the BigQuery streaming subscription"
  value       = google_pubsub_subscription.bq_streaming_sub.id
}

output "pubsub_dlq_topic_name" {
  description = "The name of the dead letter queue topic"
  value       = google_pubsub_topic.streaming_events_dlq.name
}

output "message_retention_duration" {
  description = "The message retention duration for Pub/Sub topics"
  value       = var.pubsub_message_retention_duration
}

#------------------------------------------------------------------------------
# Cloud Storage Outputs
#------------------------------------------------------------------------------

output "storage_bucket_name" {
  description = "The name of the Cloud Storage bucket"
  value       = google_storage_bucket.pipeline_data.name
}

output "storage_bucket_url" {
  description = "The URL of the Cloud Storage bucket"
  value       = google_storage_bucket.pipeline_data.url
}

output "storage_bucket_location" {
  description = "The location of the Cloud Storage bucket"
  value       = google_storage_bucket.pipeline_data.location
}

output "storage_bucket_class" {
  description = "The storage class of the Cloud Storage bucket"
  value       = google_storage_bucket.pipeline_data.storage_class
}

output "storage_directories" {
  description = "The directory structure created in the storage bucket"
  value = {
    schemas    = google_storage_bucket_object.schemas_directory.name
    exports    = google_storage_bucket_object.exports_directory.name
    audit_logs = google_storage_bucket_object.audit_logs_directory.name
  }
}

#------------------------------------------------------------------------------
# Cloud Functions Outputs
#------------------------------------------------------------------------------

output "security_audit_function_name" {
  description = "The name of the security audit Cloud Function"
  value       = google_cloudfunctions_function.security_audit.name
}

output "security_audit_function_url" {
  description = "The trigger URL of the security audit Cloud Function"
  value       = google_cloudfunctions_function.security_audit.trigger[0].https_trigger[0].url
  sensitive   = true
}

output "encryption_function_name" {
  description = "The name of the data encryption Cloud Function"
  value       = google_cloudfunctions_function.encrypt_sensitive_data.name
}

output "encryption_function_url" {
  description = "The trigger URL of the data encryption Cloud Function"
  value       = google_cloudfunctions_function.encrypt_sensitive_data.trigger[0].https_trigger[0].url
  sensitive   = true
}

#------------------------------------------------------------------------------
# Cloud Scheduler Outputs
#------------------------------------------------------------------------------

output "security_audit_job_name" {
  description = "The name of the security audit scheduled job"
  value       = var.monitoring_enabled ? google_cloud_scheduler_job.security_audit_daily[0].name : null
}

output "security_audit_schedule" {
  description = "The cron schedule for security audits"
  value       = var.security_audit_schedule
}

#------------------------------------------------------------------------------
# Monitoring and Logging Outputs
#------------------------------------------------------------------------------

output "kms_usage_metric_name" {
  description = "The name of the KMS usage log-based metric"
  value       = var.monitoring_enabled ? google_logging_metric.kms_key_usage[0].name : null
}

output "continuous_query_metric_name" {
  description = "The name of the continuous query performance metric"
  value       = var.monitoring_enabled ? google_logging_metric.continuous_query_performance[0].name : null
}

output "security_audit_sink_name" {
  description = "The name of the security audit log sink"
  value       = var.monitoring_enabled ? google_logging_project_sink.security_audit_sink[0].name : null
}

output "security_audit_sink_destination" {
  description = "The destination of the security audit log sink"
  value       = var.monitoring_enabled ? google_logging_project_sink.security_audit_sink[0].destination : null
}

#------------------------------------------------------------------------------
# Security and IAM Outputs
#------------------------------------------------------------------------------

output "current_user_email" {
  description = "The email of the current authenticated user"
  value       = data.google_client_openid_userinfo.me.email
  sensitive   = true
}

output "project_number" {
  description = "The project number for service account references"
  value       = data.google_project.current.number
}

output "bigquery_service_account" {
  description = "The BigQuery service account for KMS permissions"
  value       = "bq-${data.google_project.current.number}@bigquery-encryption.iam.gserviceaccount.com"
}

output "pubsub_service_account" {
  description = "The Pub/Sub service account for KMS permissions"
  value       = "service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

output "storage_service_account" {
  description = "The Cloud Storage service account for KMS permissions"
  value       = "service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
}

#------------------------------------------------------------------------------
# Configuration and Settings Outputs
#------------------------------------------------------------------------------

output "environment" {
  description = "The environment label applied to resources"
  value       = var.environment
}

output "deletion_protection_enabled" {
  description = "Whether deletion protection is enabled for critical resources"
  value       = var.deletion_protection
}

output "monitoring_enabled" {
  description = "Whether monitoring and logging resources are enabled"
  value       = var.monitoring_enabled
}

output "apis_enabled" {
  description = "List of Google Cloud APIs that were enabled"
  value = var.enable_apis ? [
    "bigquery.googleapis.com",
    "cloudkms.googleapis.com",
    "cloudscheduler.googleapis.com",
    "logging.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "monitoring.googleapis.com"
  ] : []
}

#------------------------------------------------------------------------------
# Usage Instructions and Next Steps
#------------------------------------------------------------------------------

output "getting_started_commands" {
  description = "Commands to get started with the deployed infrastructure"
  value = {
    # BigQuery commands
    view_dataset = "bq show ${var.project_id}:${var.dataset_id}"
    list_tables  = "bq ls ${var.project_id}:${var.dataset_id}"
    
    # Pub/Sub commands
    publish_test_message = "gcloud pubsub topics publish ${google_pubsub_topic.streaming_events.name} --message='{\"test\": \"message\"}'"
    pull_messages       = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.bq_streaming_sub.name} --limit=1"
    
    # Cloud Storage commands
    list_bucket_contents = "gsutil ls -la gs://${google_storage_bucket.pipeline_data.name}/"
    
    # KMS commands
    list_keys = "gcloud kms keys list --location=${var.region} --keyring=${google_kms_key_ring.pipeline_keyring.name}"
    
    # Security audit
    trigger_security_audit = "curl -X POST ${google_cloudfunctions_function.security_audit.trigger[0].https_trigger[0].url}"
  }
}

output "continuous_query_template" {
  description = "Template SQL for creating a BigQuery Continuous Query"
  value = <<-EOT
-- Example BigQuery Continuous Query
-- Replace placeholders with actual values before running

EXPORT DATA
OPTIONS (
  uri = 'gs://${google_storage_bucket.pipeline_data.name}/exports/processed_events_*.json',
  format = 'JSON',
  overwrite = false
) AS
SELECT 
  event_id,
  CURRENT_TIMESTAMP() as processed_timestamp,
  user_id,
  event_type,
  JSON_OBJECT(
    'original_metadata', metadata,
    'processing_time', CURRENT_TIMESTAMP(),
    'data_source', 'continuous_query'
  ) as enriched_data,
  CASE 
    WHEN event_type = 'login_failure' THEN 0.8
    WHEN event_type = 'unusual_activity' THEN 0.9
    WHEN event_type = 'data_access' THEN 0.3
    ELSE 0.1
  END as risk_score
FROM `${var.project_id}.${var.dataset_id}.${google_bigquery_table.raw_events.table_id}`
WHERE timestamp >= CURRENT_TIMESTAMP() - INTERVAL 1 HOUR
EOT
}

output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    security = {
      kms_keyring        = "Centralized key management with automatic rotation"
      encryption_keys    = "Table-level and column-level encryption keys"
      iam_bindings      = "Service account permissions for CMEK operations"
    }
    data_processing = {
      bigquery_dataset   = "Analytics dataset with customer-managed encryption"
      bigquery_tables    = "Tables for raw events, processed events, and encrypted user data"
      pubsub_topic      = "Encrypted messaging for real-time data ingestion"
      storage_bucket    = "Encrypted data lake for exports and artifacts"
    }
    automation = {
      cloud_functions   = "Security audit and data encryption functions"
      cloud_scheduler   = "Automated security operations scheduling"
      monitoring       = "Log-based metrics and audit trail collection"
    }
    next_steps = [
      "Configure BigQuery Continuous Queries using the provided template",
      "Set up data ingestion pipelines to Pub/Sub topic",
      "Configure monitoring dashboards and alerting policies",
      "Test encryption/decryption workflows with Cloud Functions",
      "Implement additional security policies as needed"
    ]
  }
}