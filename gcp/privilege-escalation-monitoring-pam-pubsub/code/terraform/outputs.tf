# Outputs for GCP Privilege Escalation Monitoring Infrastructure

# Project Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where regional resources were created"
  value       = var.region
}

output "environment" {
  description = "The environment name"
  value       = var.environment
}

# Resource Naming
output "resource_suffix" {
  description = "The random suffix used for resource uniqueness"
  value       = local.resource_suffix
}

# Pub/Sub Resources
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for privilege escalation alerts"
  value       = google_pubsub_topic.privilege_escalation_alerts.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.privilege_escalation_alerts.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription"
  value       = google_pubsub_subscription.privilege_monitor_subscription.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.privilege_monitor_subscription.id
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed messages"
  value       = google_pubsub_topic.dead_letter_topic.name
}

# Cloud Function
output "cloud_function_name" {
  description = "Name of the Cloud Function processing alerts"
  value       = google_cloudfunctions_function.privilege_alert_processor.name
}

output "cloud_function_url" {
  description = "HTTP trigger URL for the Cloud Function (if applicable)"
  value       = google_cloudfunctions_function.privilege_alert_processor.https_trigger_url
}

output "cloud_function_source_archive_url" {
  description = "URL of the function source archive in Cloud Storage"
  value       = google_storage_bucket_object.function_source.self_link
}

output "cloud_function_runtime" {
  description = "Runtime environment for the Cloud Function"
  value       = google_cloudfunctions_function.privilege_alert_processor.runtime
}

# Cloud Storage
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for audit log archival"
  value       = google_storage_bucket.privilege_audit_logs.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.privilege_audit_logs.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.privilege_audit_logs.self_link
}

output "storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.privilege_audit_logs.location
}

# KMS Resources
output "kms_key_ring_name" {
  description = "Name of the KMS key ring"
  value       = google_kms_key_ring.privilege_monitoring_keyring.name
}

output "kms_crypto_key_name" {
  description = "Name of the KMS crypto key for bucket encryption"
  value       = google_kms_crypto_key.bucket_key.name
}

output "kms_crypto_key_id" {
  description = "Full resource ID of the KMS crypto key"
  value       = google_kms_crypto_key.bucket_key.id
}

# Logging Resources
output "log_sink_name" {
  description = "Name of the log sink routing audit logs to Pub/Sub"
  value       = google_logging_project_sink.privilege_escalation_sink.name
}

output "log_sink_writer_identity" {
  description = "Service account identity of the log sink"
  value       = google_logging_project_sink.privilege_escalation_sink.writer_identity
  sensitive   = true
}

output "log_sink_destination" {
  description = "Destination of the log sink"
  value       = google_logging_project_sink.privilege_escalation_sink.destination
}

output "log_sink_filter" {
  description = "Filter used by the log sink to capture privilege escalation events"
  value       = google_logging_project_sink.privilege_escalation_sink.filter
}

# Service Account
output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = var.create_service_accounts ? google_service_account.function_service_account[0].email : "default"
}

output "function_service_account_id" {
  description = "Full resource ID of the function service account"
  value       = var.create_service_accounts ? google_service_account.function_service_account[0].id : null
}

# Monitoring Resources
output "monitoring_alert_policy_name" {
  description = "Name of the Cloud Monitoring alert policy"
  value       = var.enable_monitoring_alerts ? google_monitoring_alert_policy.privilege_escalation_alert[0].display_name : null
}

output "monitoring_alert_policy_id" {
  description = "ID of the Cloud Monitoring alert policy"
  value       = var.enable_monitoring_alerts ? google_monitoring_alert_policy.privilege_escalation_alert[0].name : null
}

# Security and Compliance Information
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value       = var.enable_apis ? var.required_apis : []
}

output "bucket_encryption_key" {
  description = "KMS key used for bucket encryption"
  value       = google_kms_crypto_key.bucket_key.id
}

output "uniform_bucket_level_access" {
  description = "Whether uniform bucket-level access is enabled"
  value       = google_storage_bucket.privilege_audit_logs.uniform_bucket_level_access
}

output "bucket_versioning_enabled" {
  description = "Whether bucket versioning is enabled"
  value       = var.enable_bucket_versioning
}

# Lifecycle Configuration
output "coldline_transition_days" {
  description = "Number of days after which objects transition to COLDLINE storage"
  value       = var.coldline_age_days
}

output "archive_transition_days" {
  description = "Number of days after which objects transition to ARCHIVE storage"
  value       = var.archive_age_days
}

# Configuration Summary
output "monitoring_configuration" {
  description = "Summary of monitoring configuration"
  value = {
    alerts_enabled      = var.enable_monitoring_alerts
    alert_threshold     = var.alert_threshold_value
    alert_duration      = var.alert_duration
    function_runtime    = var.function_runtime
    function_memory     = var.function_memory
    function_timeout    = var.function_timeout
    max_instances       = var.function_max_instances
  }
}

output "pubsub_configuration" {
  description = "Summary of Pub/Sub configuration"
  value = {
    ack_deadline_seconds      = var.pubsub_ack_deadline_seconds
    message_retention         = var.pubsub_message_retention_duration
    dead_letter_max_attempts  = 5
  }
}

output "labels" {
  description = "Labels applied to all resources"
  value       = local.common_labels
}

# Deployment Verification Commands
output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    check_topic = "gcloud pubsub topics describe ${google_pubsub_topic.privilege_escalation_alerts.name}"
    check_subscription = "gcloud pubsub subscriptions describe ${google_pubsub_subscription.privilege_monitor_subscription.name}"
    check_function = "gcloud functions describe ${google_cloudfunctions_function.privilege_alert_processor.name} --region=${var.region}"
    check_bucket = "gsutil ls -b gs://${google_storage_bucket.privilege_audit_logs.name}"
    check_sink = "gcloud logging sinks describe ${google_logging_project_sink.privilege_escalation_sink.name}"
    view_function_logs = "gcloud functions logs read ${google_cloudfunctions_function.privilege_alert_processor.name} --region=${var.region} --limit=10"
  }
}

# Testing Commands
output "testing_commands" {
  description = "Commands to test the privilege escalation monitoring"
  value = {
    create_test_role = "gcloud iam roles create testPrivilegeRole${local.resource_suffix} --project=${var.project_id} --title='Test Privilege Role' --description='Test role for monitoring' --permissions='storage.objects.get'"
    delete_test_role = "gcloud iam roles delete testPrivilegeRole${local.resource_suffix} --project=${var.project_id} --quiet"
    check_recent_logs = "gcloud logging read 'protoPayload.serviceName=\"iam.googleapis.com\"' --limit=5 --format='value(timestamp,protoPayload.methodName,protoPayload.authenticationInfo.principalEmail)'"
    check_stored_alerts = "gsutil ls -r gs://${google_storage_bucket.privilege_audit_logs.name}/alerts/ || echo 'No alerts stored yet'"
  }
}