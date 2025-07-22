# Project and organization information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "organization_id" {
  description = "The Google Cloud organization ID used for policies"
  value       = var.organization_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

# BigQuery dataset information
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for cost allocation analytics"
  value       = google_bigquery_dataset.cost_allocation.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.cost_allocation.location
}

output "bigquery_dataset_url" {
  description = "Console URL for the BigQuery dataset"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.cost_allocation.dataset_id}"
}

# BigQuery table information
output "tag_compliance_table_id" {
  description = "ID of the tag compliance tracking table"
  value       = google_bigquery_table.tag_compliance.table_id
}

output "cost_allocation_table_id" {
  description = "ID of the cost allocation table"
  value       = google_bigquery_table.cost_allocation.table_id
}

output "cost_allocation_summary_view" {
  description = "ID of the cost allocation summary view"
  value       = google_bigquery_table.cost_allocation_summary.table_id
}

output "compliance_summary_view" {
  description = "ID of the compliance summary view"
  value       = google_bigquery_table.compliance_summary.table_id
}

# Cloud Asset Inventory information
output "asset_feed_name" {
  description = "Name of the Cloud Asset Inventory feed"
  value = var.organization_id != "" ? (
    length(google_cloud_asset_folder_feed.resource_compliance) > 0 ? 
    google_cloud_asset_folder_feed.resource_compliance[0].name : null
  ) : (
    length(google_cloud_asset_project_feed.resource_compliance_project) > 0 ?
    google_cloud_asset_project_feed.resource_compliance_project[0].name : null
  )
}

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for asset change notifications"
  value       = google_pubsub_topic.asset_changes.name
}

output "pubsub_topic_id" {
  description = "ID of the Pub/Sub topic for asset change notifications"
  value       = google_pubsub_topic.asset_changes.id
}

# Cloud Functions information
output "tag_compliance_function_name" {
  description = "Name of the tag compliance monitoring Cloud Function"
  value       = google_cloudfunctions2_function.tag_compliance.name
}

output "tag_compliance_function_url" {
  description = "Console URL for the tag compliance function"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.tag_compliance.name}?project=${var.project_id}"
}

output "cost_reporting_function_name" {
  description = "Name of the cost reporting Cloud Function (if enabled)"
  value = var.enable_automated_reporting ? (
    length(google_cloudfunctions2_function.cost_allocation_reporter) > 0 ?
    google_cloudfunctions2_function.cost_allocation_reporter[0].name : null
  ) : null
}

output "cost_reporting_function_url" {
  description = "Console URL for the cost reporting function (if enabled)"
  value = var.enable_automated_reporting ? (
    length(google_cloudfunctions2_function.cost_allocation_reporter) > 0 ?
    "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.cost_allocation_reporter[0].name}?project=${var.project_id}" : null
  ) : null
}

# Storage information
output "billing_export_bucket_name" {
  description = "Name of the Cloud Storage bucket for billing export"
  value       = google_storage_bucket.billing_export.name
}

output "billing_export_bucket_url" {
  description = "Console URL for the billing export bucket"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.billing_export.name}?project=${var.project_id}"
}

# Service account information
output "function_service_account_email" {
  description = "Email of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.email
}

output "function_service_account_id" {
  description = "ID of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.account_id
}

# Organization policy information
output "org_policy_constraint_name" {
  description = "Name of the organization policy constraint (if created)"
  value = var.enforce_org_policy && var.organization_id != "" ? (
    length(google_org_policy_custom_constraint.mandatory_tags) > 0 ?
    google_org_policy_custom_constraint.mandatory_tags[0].name : null
  ) : null
}

output "org_policy_enabled" {
  description = "Whether organization policy enforcement is enabled"
  value       = var.enforce_org_policy && var.organization_id != ""
}

# Scheduler information
output "cost_report_scheduler_name" {
  description = "Name of the Cloud Scheduler job for automated reporting (if enabled)"
  value = var.enable_automated_reporting ? (
    length(google_cloud_scheduler_job.cost_allocation_report) > 0 ?
    google_cloud_scheduler_job.cost_allocation_report[0].name : null
  ) : null
}

output "cost_report_schedule" {
  description = "Schedule for automated cost reporting (if enabled)"
  value = var.enable_automated_reporting ? var.report_schedule : null
}

# Configuration values
output "mandatory_labels" {
  description = "List of mandatory labels required on resources"
  value       = var.mandatory_labels
}

output "monitored_asset_types" {
  description = "List of asset types being monitored"
  value       = var.monitored_asset_types
}

# SQL queries for manual execution
output "sample_compliance_query" {
  description = "Sample BigQuery query to check tag compliance"
  value = <<-EOT
SELECT 
  resource_type,
  department,
  COUNT(*) as total_resources,
  SUM(CASE WHEN compliant THEN 1 ELSE 0 END) as compliant_resources,
  ROUND(100.0 * SUM(CASE WHEN compliant THEN 1 ELSE 0 END) / COUNT(*), 2) as compliance_percentage
FROM `${var.project_id}.${google_bigquery_dataset.cost_allocation.dataset_id}.tag_compliance`
WHERE DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY resource_type, department
ORDER BY compliance_percentage ASC;
EOT
}

output "sample_cost_query" {
  description = "Sample BigQuery query for cost allocation analysis"
  value = <<-EOT
SELECT 
  billing_date,
  department,
  cost_center,
  service,
  SUM(cost) as total_cost,
  currency
FROM `${var.project_id}.${google_bigquery_dataset.cost_allocation.dataset_id}.cost_allocation`
WHERE billing_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY billing_date, department, cost_center, service, currency
ORDER BY billing_date DESC, total_cost DESC;
EOT
}

# Next steps information
output "next_steps" {
  description = "Next steps to complete the setup"
  value = <<-EOT
To complete the cost allocation setup:

1. Configure Cloud Billing export:
   - Go to Cloud Billing > Billing export in the console
   - Enable BigQuery export to dataset: ${google_bigquery_dataset.cost_allocation.dataset_id}
   - Configure export to include detailed usage cost data

2. Test tag compliance:
   - Create a test resource with required labels: ${join(", ", var.mandatory_labels)}
   - Verify compliance tracking in BigQuery table: ${google_bigquery_table.tag_compliance.table_id}

3. Monitor asset changes:
   - Check Pub/Sub topic for messages: ${google_pubsub_topic.asset_changes.name}
   - Review Cloud Function logs: ${google_cloudfunctions2_function.tag_compliance.name}

4. Set up alerting:
   - Create Cloud Monitoring alerts for compliance violations
   - Configure notification channels for cost threshold breaches

5. Access analytics:
   - BigQuery dataset: ${google_bigquery_dataset.cost_allocation.dataset_id}
   - Cost allocation view: ${google_bigquery_table.cost_allocation_summary.table_id}
   - Compliance view: ${google_bigquery_table.compliance_summary.table_id}

Console URLs:
- BigQuery: https://console.cloud.google.com/bigquery?project=${var.project_id}
- Cloud Functions: https://console.cloud.google.com/functions?project=${var.project_id}
- Cloud Storage: https://console.cloud.google.com/storage/browser/${google_storage_bucket.billing_export.name}?project=${var.project_id}
EOT
}

# Random suffix for reference
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}