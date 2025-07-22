# Output Values for Cloud Asset Governance Infrastructure
# This file defines outputs that provide important information about deployed resources
# for verification, integration, and operational use.

# Project and Organization Information
output "project_id" {
  description = "The Google Cloud project ID where governance resources were deployed"
  value       = var.project_id
}

output "organization_id" {
  description = "The Google Cloud organization ID being monitored for governance"
  value       = var.organization_id
}

output "region" {
  description = "The Google Cloud region where regional resources were deployed"
  value       = var.region
}

output "governance_suffix" {
  description = "Unique suffix used for governance resource naming"
  value       = local.governance_suffix
}

# Storage and Data Resources
output "governance_bucket_name" {
  description = "Name of the Cloud Storage bucket containing governance artifacts"
  value       = google_storage_bucket.governance_bucket.name
}

output "governance_bucket_url" {
  description = "GCS URL of the governance artifacts bucket"
  value       = google_storage_bucket.governance_bucket.url
}

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for governance analytics and compliance reporting"
  value       = google_bigquery_dataset.governance_dataset.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery governance dataset"
  value       = google_bigquery_dataset.governance_dataset.location
}

output "violations_table_id" {
  description = "Full BigQuery table ID for asset violations"
  value       = "${var.project_id}.${google_bigquery_dataset.governance_dataset.dataset_id}.${google_bigquery_table.asset_violations.table_id}"
}

output "compliance_reports_table_id" {
  description = "Full BigQuery table ID for compliance reports"
  value       = "${var.project_id}.${google_bigquery_dataset.governance_dataset.dataset_id}.${google_bigquery_table.compliance_reports.table_id}"
}

# Messaging and Event Infrastructure
output "asset_changes_topic" {
  description = "Pub/Sub topic name for asset change notifications"
  value       = google_pubsub_topic.asset_changes.name
}

output "asset_changes_topic_id" {
  description = "Full Pub/Sub topic ID for asset change notifications"
  value       = google_pubsub_topic.asset_changes.id
}

output "workflow_subscription" {
  description = "Pub/Sub subscription name for workflow processing"
  value       = google_pubsub_subscription.workflow_processor.name
}

output "dead_letter_topic" {
  description = "Pub/Sub dead letter topic for failed governance messages"
  value       = google_pubsub_topic.dead_letter.name
}

# Cloud Functions Information
output "policy_evaluator_function_name" {
  description = "Name of the Cloud Function for policy evaluation"
  value       = google_cloudfunctions2_function.policy_evaluator.name
}

output "policy_evaluator_function_url" {
  description = "HTTPS URL of the policy evaluation Cloud Function"
  value       = google_cloudfunctions2_function.policy_evaluator.service_config[0].uri
}

output "workflow_trigger_function_name" {
  description = "Name of the Cloud Function that triggers governance workflows"
  value       = google_cloudfunctions2_function.workflow_trigger.name
}

output "workflow_trigger_function_url" {
  description = "HTTPS URL of the workflow trigger Cloud Function"
  value       = google_cloudfunctions2_function.workflow_trigger.service_config[0].uri
}

# Workflow and Orchestration
output "governance_workflow_name" {
  description = "Name of the Cloud Workflow for governance orchestration"
  value       = google_workflows_workflow.governance_orchestrator.name
}

output "governance_workflow_id" {
  description = "Full resource ID of the governance workflow"
  value       = google_workflows_workflow.governance_orchestrator.id
}

# Asset Monitoring Configuration
output "asset_feed_name" {
  description = "Name of the Cloud Asset Inventory feed monitoring organization resources"
  value       = google_cloud_asset_organization_feed.governance_feed.feed_id
}

output "monitored_asset_types" {
  description = "List of asset types being monitored for governance compliance"
  value       = var.asset_types_to_monitor
}

# Security and IAM
output "governance_service_account_email" {
  description = "Email address of the governance service account"
  value       = google_service_account.governance_engine.email
}

output "governance_service_account_unique_id" {
  description = "Unique ID of the governance service account"
  value       = google_service_account.governance_engine.unique_id
}

# Encryption and Security
output "governance_kms_key_ring" {
  description = "KMS key ring used for governance data encryption"
  value       = google_kms_key_ring.governance_keyring.id
}

output "governance_kms_crypto_key" {
  description = "KMS crypto key used for governance data encryption"
  value       = google_kms_crypto_key.governance_key.id
}

# Monitoring and Alerting
output "monitoring_notification_channel" {
  description = "Cloud Monitoring notification channel for governance alerts"
  value       = var.notification_email != "" ? google_monitoring_notification_channel.governance_email[0].name : "No email notification configured"
}

output "high_severity_alert_policy" {
  description = "Alert policy for high severity governance violations"
  value       = var.enable_monitoring_alerts ? google_monitoring_alert_policy.high_severity_violations[0].name : "Monitoring alerts disabled"
}

# Operational URLs and Endpoints
output "bigquery_console_url" {
  description = "Google Cloud Console URL for BigQuery governance dataset"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.governance_dataset.dataset_id}!3sviolations"
}

output "cloud_functions_console_url" {
  description = "Google Cloud Console URL for viewing Cloud Functions"
  value       = "https://console.cloud.google.com/functions/list?project=${var.project_id}&region=${var.region}"
}

output "workflows_console_url" {
  description = "Google Cloud Console URL for viewing Cloud Workflows"
  value       = "https://console.cloud.google.com/workflows?project=${var.project_id}&region=${var.region}"
}

output "pubsub_console_url" {
  description = "Google Cloud Console URL for viewing Pub/Sub topics"
  value       = "https://console.cloud.google.com/cloudpubsub/topic/list?project=${var.project_id}"
}

output "asset_inventory_console_url" {
  description = "Google Cloud Console URL for Cloud Asset Inventory"
  value       = "https://console.cloud.google.com/security/asset-inventory?project=${var.project_id}"
}

# Configuration Summary
output "governance_configuration_summary" {
  description = "Summary of key governance system configuration settings"
  value = {
    message_retention_days    = var.message_retention_days
    function_memory          = var.function_memory
    function_timeout         = var.function_timeout
    max_function_instances   = var.max_function_instances
    storage_class           = var.storage_class
    bucket_versioning       = var.enable_bucket_versioning
    monitoring_alerts       = var.enable_monitoring_alerts
    content_type            = var.content_type
    bigquery_location       = var.bigquery_location
  }
}

# Resource Labels Applied
output "resource_labels" {
  description = "Common labels applied to all governance resources"
  value       = local.common_labels
}

# Quick Start Commands
output "verification_commands" {
  description = "Commands to verify the governance system deployment"
  value = {
    check_asset_feed = "gcloud asset feeds list --organization=${var.organization_id}"
    check_pubsub     = "gcloud pubsub topics list --filter='name:${local.asset_topic_name}'"
    check_functions  = "gcloud functions list --region=${var.region} --filter='name:governance'"
    check_workflow   = "gcloud workflows list --location=${var.region} --filter='name:governance'"
    check_bigquery   = "bq ls ${local.bq_dataset_id}"
  }
}

output "sample_queries" {
  description = "Sample BigQuery queries for governance analysis"
  value = {
    recent_violations = "SELECT * FROM `${var.project_id}.${local.bq_dataset_id}.asset_violations` WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR) ORDER BY timestamp DESC"
    
    violations_by_severity = "SELECT severity, COUNT(*) as violation_count FROM `${var.project_id}.${local.bq_dataset_id}.asset_violations` WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY) GROUP BY severity ORDER BY violation_count DESC"
    
    top_violating_projects = "SELECT project_id, COUNT(*) as violation_count FROM `${var.project_id}.${local.bq_dataset_id}.asset_violations` WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY) GROUP BY project_id ORDER BY violation_count DESC LIMIT 10"
    
    compliance_trend = "SELECT DATE(timestamp) as date, COUNT(*) as daily_violations FROM `${var.project_id}.${local.bq_dataset_id}.asset_violations` WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY) GROUP BY DATE(timestamp) ORDER BY date"
  }
}

# Cost Estimation Information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for governance system components (USD)"
  value = {
    note = "Costs vary based on usage. These are estimates for moderate activity levels."
    cloud_functions = "$10-50 (based on executions and compute time)"
    bigquery_storage = "$5-25 (based on data volume stored)"
    bigquery_queries = "$5-20 (based on query frequency and data processed)"
    pubsub = "$2-10 (based on message volume)"
    cloud_storage = "$2-8 (based on governance artifacts stored)"
    workflows = "$1-5 (based on workflow executions)"
    monitoring = "$1-3 (based on metrics and alerts)"
    kms = "$1-2 (for key operations)"
    estimated_total = "$27-123 per month for moderate governance activity"
  }
}