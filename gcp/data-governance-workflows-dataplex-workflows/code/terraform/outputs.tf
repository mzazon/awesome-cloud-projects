# Outputs for Data Governance Workflows Infrastructure

# Project and basic information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were created"
  value       = var.region
}

output "environment" {
  description = "The environment name"
  value       = var.environment
}

output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = random_string.suffix.result
}

# Service Account
output "governance_service_account_email" {
  description = "Email address of the governance service account"
  value       = google_service_account.governance_sa.email
}

output "governance_service_account_id" {
  description = "ID of the governance service account"
  value       = google_service_account.governance_sa.id
}

# Cloud Storage
output "data_lake_bucket_name" {
  description = "Name of the data lake Cloud Storage bucket"
  value       = google_storage_bucket.data_lake.name
}

output "data_lake_bucket_url" {
  description = "URL of the data lake Cloud Storage bucket"
  value       = google_storage_bucket.data_lake.url
}

output "data_lake_bucket_self_link" {
  description = "Self-link of the data lake Cloud Storage bucket"
  value       = google_storage_bucket.data_lake.self_link
}

# KMS
output "kms_keyring_name" {
  description = "Name of the KMS key ring"
  value       = google_kms_key_ring.governance_keyring.name
}

output "kms_key_name" {
  description = "Name of the KMS encryption key"
  value       = google_kms_crypto_key.governance_key.name
}

output "kms_key_id" {
  description = "ID of the KMS encryption key"
  value       = google_kms_crypto_key.governance_key.id
}

# BigQuery
output "bigquery_dataset_id" {
  description = "ID of the BigQuery governance analytics dataset"
  value       = google_bigquery_dataset.governance_analytics.dataset_id
}

output "bigquery_dataset_self_link" {
  description = "Self-link of the BigQuery governance analytics dataset"
  value       = google_bigquery_dataset.governance_analytics.self_link
}

output "data_quality_metrics_table_id" {
  description = "ID of the data quality metrics table"
  value       = google_bigquery_table.data_quality_metrics.table_id
}

output "compliance_reports_table_id" {
  description = "ID of the compliance reports table"
  value       = google_bigquery_table.compliance_reports.table_id
}

output "governance_audit_log_table_id" {
  description = "ID of the governance audit log table"
  value       = google_bigquery_table.governance_audit_log.table_id
}

# Dataplex
output "dataplex_lake_name" {
  description = "Name of the Dataplex lake"
  value       = google_dataplex_lake.governance_lake.name
}

output "dataplex_lake_id" {
  description = "ID of the Dataplex lake"
  value       = google_dataplex_lake.governance_lake.id
}

output "raw_data_zone_name" {
  description = "Name of the raw data zone"
  value       = google_dataplex_zone.raw_data_zone.name
}

output "raw_data_zone_id" {
  description = "ID of the raw data zone"
  value       = google_dataplex_zone.raw_data_zone.id
}

output "curated_data_zone_name" {
  description = "Name of the curated data zone"
  value       = google_dataplex_zone.curated_data_zone.name
}

output "curated_data_zone_id" {
  description = "ID of the curated data zone"
  value       = google_dataplex_zone.curated_data_zone.id
}

output "storage_asset_name" {
  description = "Name of the storage asset"
  value       = google_dataplex_asset.storage_asset.name
}

output "bigquery_asset_name" {
  description = "Name of the BigQuery asset"
  value       = google_dataplex_asset.bigquery_asset.name
}

# Cloud DLP
output "dlp_inspection_template_name" {
  description = "Name of the DLP inspection template"
  value       = google_data_loss_prevention_inspect_template.governance_template.name
}

output "dlp_inspection_template_id" {
  description = "ID of the DLP inspection template"
  value       = google_data_loss_prevention_inspect_template.governance_template.id
}

output "dlp_job_trigger_name" {
  description = "Name of the DLP job trigger"
  value       = google_data_loss_prevention_job_trigger.governance_trigger.name
}

output "dlp_job_trigger_id" {
  description = "ID of the DLP job trigger"
  value       = google_data_loss_prevention_job_trigger.governance_trigger.id
}

# Cloud Functions
output "data_quality_function_name" {
  description = "Name of the data quality assessment function"
  value       = google_cloudfunctions_function.data_quality_assessor.name
}

output "data_quality_function_id" {
  description = "ID of the data quality assessment function"
  value       = google_cloudfunctions_function.data_quality_assessor.id
}

output "data_quality_function_https_trigger_url" {
  description = "HTTPS trigger URL for the data quality assessment function"
  value       = google_cloudfunctions_function.data_quality_assessor.https_trigger_url
}

output "function_source_bucket_name" {
  description = "Name of the function source bucket"
  value       = google_storage_bucket.function_source_bucket.name
}

# Cloud Workflows
output "governance_workflow_name" {
  description = "Name of the governance workflow"
  value       = google_workflows_workflow.governance_workflow.name
}

output "governance_workflow_id" {
  description = "ID of the governance workflow"
  value       = google_workflows_workflow.governance_workflow.id
}

output "governance_workflow_revision_id" {
  description = "Revision ID of the governance workflow"
  value       = google_workflows_workflow.governance_workflow.revision_id
}

# Cloud Monitoring
output "data_quality_alert_policy_name" {
  description = "Name of the data quality alert policy"
  value       = google_monitoring_alert_policy.data_quality_alert.name
}

output "data_quality_alert_policy_id" {
  description = "ID of the data quality alert policy"
  value       = google_monitoring_alert_policy.data_quality_alert.id
}

output "governance_workflow_metric_name" {
  description = "Name of the governance workflow execution metric"
  value       = google_logging_metric.governance_workflow_executions.name
}

# Connection information for external tools
output "bigquery_connection_string" {
  description = "Connection string for BigQuery dataset"
  value       = "${var.project_id}.${google_bigquery_dataset.governance_analytics.dataset_id}"
}

output "gcs_data_lake_path" {
  description = "Full GCS path to the data lake"
  value       = "gs://${google_storage_bucket.data_lake.name}/"
}

output "dataplex_lake_resource_name" {
  description = "Full resource name of the Dataplex lake"
  value       = "projects/${var.project_id}/locations/${var.region}/lakes/${google_dataplex_lake.governance_lake.name}"
}

# Workflow execution command
output "workflow_execution_command" {
  description = "Command to execute the governance workflow"
  value       = "gcloud workflows run ${google_workflows_workflow.governance_workflow.name} --location=${var.region} --data='{\"trigger\": \"manual\", \"scope\": \"full_scan\"}'"
}

# Data validation queries
output "data_quality_validation_query" {
  description = "BigQuery query to validate data quality metrics"
  value       = "SELECT COUNT(*) as total_assessments, AVG(quality_score) as avg_quality FROM `${var.project_id}.${google_bigquery_dataset.governance_analytics.dataset_id}.data_quality_metrics`"
}

output "compliance_status_query" {
  description = "BigQuery query to check compliance status"
  value       = "SELECT compliance_status, COUNT(*) as count FROM `${var.project_id}.${google_bigquery_dataset.governance_analytics.dataset_id}.compliance_reports` GROUP BY compliance_status"
}

# Resource URLs for console access
output "dataplex_console_url" {
  description = "URL to access Dataplex lake in Google Cloud Console"
  value       = "https://console.cloud.google.com/dataplex/lakes/${google_dataplex_lake.governance_lake.name}/overview?project=${var.project_id}&region=${var.region}"
}

output "bigquery_console_url" {
  description = "URL to access BigQuery dataset in Google Cloud Console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.governance_analytics.dataset_id}"
}

output "workflows_console_url" {
  description = "URL to access Cloud Workflows in Google Cloud Console"
  value       = "https://console.cloud.google.com/workflows/workflow/${var.region}/${google_workflows_workflow.governance_workflow.name}?project=${var.project_id}"
}

output "monitoring_console_url" {
  description = "URL to access Cloud Monitoring in Google Cloud Console"
  value       = "https://console.cloud.google.com/monitoring/alerting/policies/${google_monitoring_alert_policy.data_quality_alert.name}?project=${var.project_id}"
}

# Summary output
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    dataplex_lake            = google_dataplex_lake.governance_lake.name
    raw_zone                 = google_dataplex_zone.raw_data_zone.name
    curated_zone            = google_dataplex_zone.curated_data_zone.name
    data_lake_bucket        = google_storage_bucket.data_lake.name
    bigquery_dataset        = google_bigquery_dataset.governance_analytics.dataset_id
    governance_workflow     = google_workflows_workflow.governance_workflow.name
    data_quality_function   = google_cloudfunctions_function.data_quality_assessor.name
    dlp_template           = google_data_loss_prevention_inspect_template.governance_template.name
    service_account        = google_service_account.governance_sa.email
    kms_key                = google_kms_crypto_key.governance_key.id
  }
}

# Testing and validation outputs
output "test_commands" {
  description = "Commands to test the deployed infrastructure"
  value = {
    check_dataplex_lake   = "gcloud dataplex lakes describe ${google_dataplex_lake.governance_lake.name} --location=${var.region} --project=${var.project_id}"
    check_workflow        = "gcloud workflows describe ${google_workflows_workflow.governance_workflow.name} --location=${var.region} --project=${var.project_id}"
    run_workflow          = "gcloud workflows run ${google_workflows_workflow.governance_workflow.name} --location=${var.region} --data='{\"test\": true}' --project=${var.project_id}"
    check_bigquery_data   = "bq query --use_legacy_sql=false --project_id=${var.project_id} \"SELECT COUNT(*) FROM \\`${var.project_id}.${google_bigquery_dataset.governance_analytics.dataset_id}.data_quality_metrics\\`\""
    test_function         = "curl -X POST ${google_cloudfunctions_function.data_quality_assessor.https_trigger_url} -H 'Content-Type: application/json' -d '{\"asset_name\": \"test-asset\", \"zone\": \"raw-data-zone\"}'"
  }
}

# Next steps guidance
output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Upload sample data to the data lake bucket: gsutil cp sample-data.csv gs://${google_storage_bucket.data_lake.name}/",
    "2. Execute the governance workflow: ${google_workflows_workflow.governance_workflow.name}",
    "3. Monitor data quality metrics in BigQuery dataset: ${google_bigquery_dataset.governance_analytics.dataset_id}",
    "4. Check Dataplex lake discovery results in the console",
    "5. Review DLP scan results for sensitive data detection",
    "6. Set up notification channels for monitoring alerts",
    "7. Customize governance policies based on your requirements"
  ]
}