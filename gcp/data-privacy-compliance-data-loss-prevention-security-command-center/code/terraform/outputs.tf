# Outputs for GCP data privacy compliance infrastructure
# These outputs provide essential information for verification, integration, and management

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were deployed"
  value       = var.region
}

output "resource_prefix" {
  description = "The prefix used for naming resources"
  value       = local.resource_name
}

# DLP Configuration Outputs
output "dlp_inspect_template_name" {
  description = "Full resource name of the DLP inspection template"
  value       = google_data_loss_prevention_inspect_template.privacy_compliance.name
}

output "dlp_inspect_template_id" {
  description = "ID of the DLP inspection template for use in scan jobs"
  value       = google_data_loss_prevention_inspect_template.privacy_compliance.id
}

output "sensitive_info_types" {
  description = "List of sensitive information types configured for DLP scanning"
  value       = var.sensitive_info_types
}

# Cloud Storage Outputs
output "test_data_bucket_name" {
  description = "Name of the Cloud Storage bucket containing test data for DLP scanning"
  value       = google_storage_bucket.dlp_test_data.name
}

output "test_data_bucket_url" {
  description = "URL of the Cloud Storage bucket containing test data"
  value       = google_storage_bucket.dlp_test_data.url
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing Cloud Function source code"
  value       = google_storage_bucket.function_source.name
}

# Pub/Sub Configuration Outputs
output "dlp_findings_topic_name" {
  description = "Name of the Pub/Sub topic for DLP findings"
  value       = google_pubsub_topic.dlp_findings.name
}

output "dlp_findings_topic_id" {
  description = "Full resource ID of the Pub/Sub topic for DLP findings"
  value       = google_pubsub_topic.dlp_findings.id
}

output "dlp_findings_subscription_name" {
  description = "Name of the Pub/Sub subscription for processing DLP findings"
  value       = google_pubsub_subscription.dlp_processor.name
}

output "dlp_scan_trigger_topic_name" {
  description = "Name of the Pub/Sub topic for triggering DLP scans"
  value       = google_pubsub_topic.dlp_scan_trigger.name
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed message processing"
  value       = google_pubsub_topic.dlp_dead_letter.name
}

# Cloud Function Outputs
output "dlp_processor_function_name" {
  description = "Name of the Cloud Function for processing DLP findings"
  value       = google_cloudfunctions2_function.dlp_processor.name
}

output "dlp_processor_function_url" {
  description = "URL of the Cloud Function for processing DLP findings"
  value       = google_cloudfunctions2_function.dlp_processor.service_config[0].uri
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.dlp_function_sa.email
}

# Scheduler Configuration Outputs
output "dlp_scan_schedule" {
  description = "Cron schedule for automated DLP scans"
  value       = var.dlp_scan_schedule
}

output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for DLP scans"
  value       = google_cloud_scheduler_job.dlp_scan_scheduler.name
}

# Monitoring Outputs
output "monitoring_enabled" {
  description = "Whether monitoring alerts are enabled"
  value       = var.enable_monitoring_alerts
}

output "notification_email" {
  description = "Email address configured for monitoring alerts"
  value       = var.notification_email
  sensitive   = true
}

output "alert_policy_name" {
  description = "Name of the monitoring alert policy for DLP findings"
  value       = var.enable_monitoring_alerts ? google_monitoring_alert_policy.dlp_findings_alert[0].name : null
}

output "log_metric_name" {
  description = "Name of the log-based metric for DLP findings count"
  value       = google_logging_metric.dlp_findings_count.name
}

# Security Configuration Outputs
output "security_command_center_enabled" {
  description = "Whether Security Command Center integration is enabled"
  value       = var.enable_security_command_center
}

output "audit_logging_enabled" {
  description = "Whether audit logging is enabled for DLP operations"
  value       = var.enable_audit_logging
}

# Resource Labels
output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of key configuration parameters"
  value = {
    environment                  = var.environment
    dlp_min_likelihood          = var.dlp_min_likelihood
    dlp_max_findings_per_request = var.dlp_max_findings_per_request
    function_memory             = var.function_memory
    function_timeout            = var.function_timeout
    pubsub_ack_deadline         = var.pubsub_ack_deadline
    storage_lifecycle_age_days  = var.storage_lifecycle_age_days
    monitoring_alert_threshold  = var.monitoring_alert_threshold
  }
}

# Deployment Verification Commands
output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    check_dlp_template = "gcloud dlp inspect-templates describe ${google_data_loss_prevention_inspect_template.privacy_compliance.name}"
    check_function     = "gcloud functions describe ${google_cloudfunctions2_function.dlp_processor.name} --region=${var.region} --gen2"
    check_pubsub_topic = "gcloud pubsub topics describe ${google_pubsub_topic.dlp_findings.name}"
    check_scheduler    = "gcloud scheduler jobs describe ${google_cloud_scheduler_job.dlp_scan_scheduler.name} --location=${var.region}"
    test_dlp_scan      = "gsutil ls gs://${google_storage_bucket.dlp_test_data.name}/"
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Run a test DLP scan: gcloud dlp jobs create --location=${var.region} --template-file=dlp-job.json",
    "2. Check function logs: gcloud functions logs read ${google_cloudfunctions2_function.dlp_processor.name} --region=${var.region}",
    "3. Monitor Pub/Sub messages: gcloud pubsub subscriptions pull ${google_pubsub_subscription.dlp_processor.name} --limit=5",
    "4. Review Security Command Center findings in the Google Cloud Console",
    "5. Configure additional notification channels in Cloud Monitoring if needed"
  ]
}