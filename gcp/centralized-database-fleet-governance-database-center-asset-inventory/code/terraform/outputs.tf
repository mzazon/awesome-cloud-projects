# Outputs for Centralized Database Fleet Governance Infrastructure
# Provides essential information for governance operations and integration

# =============================================================================
# PROJECT AND BASIC CONFIGURATION OUTPUTS
# =============================================================================

output "project_id" {
  description = "Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources were deployed"
  value       = var.region
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# =============================================================================
# SERVICE ACCOUNT AND IAM OUTPUTS
# =============================================================================

output "governance_service_account_email" {
  description = "Email address of the governance service account for automation"
  value       = google_service_account.governance_sa.email
}

output "governance_service_account_id" {
  description = "Unique ID of the governance service account"
  value       = google_service_account.governance_sa.unique_id
}

# =============================================================================
# DATA LAYER OUTPUTS
# =============================================================================

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for database governance data"
  value       = google_bigquery_dataset.database_governance.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.database_governance.location
}

output "asset_inventory_table_id" {
  description = "BigQuery table ID for Cloud Asset Inventory exports"
  value       = google_bigquery_table.asset_inventory.table_id
}

output "governance_storage_bucket_name" {
  description = "Cloud Storage bucket name for governance assets and reports"
  value       = google_storage_bucket.governance_assets.name
}

output "governance_storage_bucket_url" {
  description = "Cloud Storage bucket URL for governance assets"
  value       = google_storage_bucket.governance_assets.url
}

output "pubsub_topic_name" {
  description = "Pub/Sub topic name for database asset change notifications"
  value       = google_pubsub_topic.database_asset_changes.name
}

output "pubsub_subscription_name" {
  description = "Pub/Sub subscription name for governance automation"
  value       = google_pubsub_subscription.governance_automation.name
}

# =============================================================================
# DATABASE FLEET OUTPUTS (Conditional)
# =============================================================================

output "cloud_sql_instance_name" {
  description = "Cloud SQL instance name for governance testing (if created)"
  value       = var.create_sample_databases ? google_sql_database_instance.fleet_sql[0].name : null
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name for private access (if created)"
  value       = var.create_sample_databases ? google_sql_database_instance.fleet_sql[0].connection_name : null
}

output "cloud_sql_private_ip" {
  description = "Cloud SQL private IP address (if created)"
  value       = var.create_sample_databases ? google_sql_database_instance.fleet_sql[0].private_ip_address : null
}

output "spanner_instance_name" {
  description = "Spanner instance name for governance testing (if created)"
  value       = var.create_sample_databases ? google_spanner_instance.fleet_spanner[0].name : null
}

output "bigtable_instance_name" {
  description = "Bigtable instance name for governance testing (if created)"  
  value       = var.create_sample_databases ? google_bigtable_instance.fleet_bigtable[0].name : null
}

output "vpc_network_name" {
  description = "VPC network name for database private access (if created)"
  value       = var.create_sample_databases ? google_compute_network.governance_vpc[0].name : null
}

# =============================================================================
# GOVERNANCE AUTOMATION OUTPUTS
# =============================================================================

output "governance_workflow_name" {
  description = "Cloud Workflows name for database governance automation (if enabled)"
  value       = var.enable_workflows ? google_workflows_workflow.database_governance[0].name : null
}

output "governance_workflow_id" {
  description = "Cloud Workflows ID for governance automation (if enabled)"
  value       = var.enable_workflows ? google_workflows_workflow.database_governance[0].id : null
}

output "compliance_function_name" {
  description = "Cloud Function name for compliance reporting"
  value       = google_cloudfunctions_function.compliance_reporter.name
}

output "compliance_function_url" {
  description = "Cloud Function HTTPS trigger URL for compliance reporting"
  value       = google_cloudfunctions_function.compliance_reporter.https_trigger_url
}

output "governance_scheduler_name" {
  description = "Cloud Scheduler job name for continuous governance checks"
  value       = google_cloud_scheduler_job.governance_scheduler.name
}

# =============================================================================
# MONITORING AND ALERTING OUTPUTS
# =============================================================================

output "compliance_score_metric_name" {
  description = "Log-based metric name for database compliance scoring"
  value       = google_logging_metric.database_compliance_score.name
}

output "governance_events_metric_name" {
  description = "Log-based metric name for governance events counting"
  value       = google_logging_metric.governance_events.name
}

output "notification_channel_name" {
  description = "Monitoring notification channel name for governance alerts (if enabled)"
  value       = var.enable_monitoring_alerts && length(google_monitoring_notification_channel.governance_alerts) > 0 ? google_monitoring_notification_channel.governance_alerts[0].name : null
}

output "alert_policy_name" {
  description = "Alert policy name for governance violations (if enabled)"
  value       = var.enable_monitoring_alerts && length(google_monitoring_alert_policy.governance_violations) > 0 ? google_monitoring_alert_policy.governance_violations[0].name : null
}

# =============================================================================
# INTEGRATION AND ACCESS OUTPUTS
# =============================================================================

output "database_center_url" {
  description = "URL to access Database Center dashboard for AI-powered fleet management"
  value       = "https://console.cloud.google.com/database-center?project=${var.project_id}"
}

output "cloud_console_monitoring_url" {
  description = "URL to access Cloud Monitoring dashboard for governance metrics"
  value       = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
}

output "bigquery_console_url" {
  description = "URL to access BigQuery datasets for governance data analysis"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&d=${google_bigquery_dataset.database_governance.dataset_id}"
}

output "cloud_storage_console_url" {
  description = "URL to access Cloud Storage bucket for governance reports"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.governance_assets.name}?project=${var.project_id}"
}

# =============================================================================
# OPERATIONAL COMMANDS AND INSTRUCTIONS
# =============================================================================

output "manual_asset_export_command" {
  description = "Command to manually trigger Cloud Asset Inventory export to BigQuery"
  value = "gcloud asset export --project=${var.project_id} --bigquery-table=//bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.database_governance.dataset_id}/tables/${google_bigquery_table.asset_inventory.table_id} --content-type=resource --asset-types=\"sqladmin.googleapis.com/Instance,spanner.googleapis.com/Instance,bigtableadmin.googleapis.com/Instance\""
}

output "workflow_execution_command" {
  description = "Command to manually execute governance workflow (if enabled)"
  value = var.enable_workflows ? "gcloud workflows execute ${google_workflows_workflow.database_governance[0].name} --region=${var.region} --data='{\"trigger\": \"manual\", \"project\": \"${var.project_id}\"}'" : null
}

output "compliance_report_test_command" {
  description = "Command to test compliance reporting function"
  value = "curl -X GET \"${google_cloudfunctions_function.compliance_reporter.https_trigger_url}?project_id=${var.project_id}&suffix=${random_id.suffix.hex}\""
}

# =============================================================================
# SUMMARY INFORMATION
# =============================================================================

output "deployment_summary" {
  description = "Summary of deployed governance infrastructure components"
  value = {
    project_id               = var.project_id
    region                  = var.region
    sample_databases_created = var.create_sample_databases
    workflows_enabled       = var.enable_workflows
    monitoring_alerts       = var.enable_monitoring_alerts
    gemini_integration      = var.enable_gemini_integration
    governance_components = {
      bigquery_dataset    = google_bigquery_dataset.database_governance.dataset_id
      storage_bucket      = google_storage_bucket.governance_assets.name
      pubsub_topic       = google_pubsub_topic.database_asset_changes.name
      compliance_function = google_cloudfunctions_function.compliance_reporter.name
      scheduler_job      = google_cloud_scheduler_job.governance_scheduler.name
    }
  }
}

# =============================================================================
# SECURITY AND COMPLIANCE OUTPUTS
# =============================================================================

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for database governance"
  value       = local.required_apis
}

output "iam_roles_granted" {
  description = "IAM roles granted to governance service account"
  value = [
    "roles/cloudasset.viewer",
    "roles/workflows.invoker", 
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/bigquery.dataEditor",
    "roles/storage.objectAdmin",
    "roles/pubsub.publisher",
    "roles/cloudsql.viewer",
    "roles/spanner.databaseReader",
    "roles/bigtable.reader"
  ]
}

output "governance_labels" {
  description = "Common labels applied to all governance resources"
  value       = local.common_labels
}