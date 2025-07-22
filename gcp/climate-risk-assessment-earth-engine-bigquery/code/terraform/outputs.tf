# Project Information
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# BigQuery Resources
output "bigquery_dataset_id" {
  description = "The BigQuery dataset ID for climate data"
  value       = google_bigquery_dataset.climate_dataset.dataset_id
}

output "bigquery_dataset_location" {
  description = "The BigQuery dataset location"
  value       = google_bigquery_dataset.climate_dataset.location
}

output "bigquery_dataset_url" {
  description = "URL to view the BigQuery dataset in the console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.climate_dataset.dataset_id}"
}

output "climate_indicators_table_id" {
  description = "The BigQuery table ID for climate indicators"
  value       = google_bigquery_table.climate_indicators.table_id
}

output "climate_indicators_table_full_id" {
  description = "The full BigQuery table ID for climate indicators"
  value       = "${var.project_id}.${google_bigquery_dataset.climate_dataset.dataset_id}.${google_bigquery_table.climate_indicators.table_id}"
}

output "climate_extremes_table_id" {
  description = "The BigQuery table ID for climate extremes"
  value       = google_bigquery_table.climate_extremes.table_id
}

output "climate_extremes_table_full_id" {
  description = "The full BigQuery table ID for climate extremes"
  value       = "${var.project_id}.${google_bigquery_dataset.climate_dataset.dataset_id}.${google_bigquery_table.climate_extremes.table_id}"
}

output "risk_assessments_table_id" {
  description = "The BigQuery table ID for risk assessments"
  value       = google_bigquery_table.risk_assessments.table_id
}

output "risk_assessments_table_full_id" {
  description = "The full BigQuery table ID for risk assessments"
  value       = "${var.project_id}.${google_bigquery_dataset.climate_dataset.dataset_id}.${google_bigquery_table.risk_assessments.table_id}"
}

output "climate_risk_analysis_view_id" {
  description = "The BigQuery view ID for climate risk analysis"
  value       = google_bigquery_table.climate_risk_analysis_view.table_id
}

output "risk_dashboard_summary_view_id" {
  description = "The BigQuery view ID for dashboard summary"
  value       = google_bigquery_table.risk_dashboard_summary_view.table_id
}

# Cloud Storage Resources
output "storage_bucket_name" {
  description = "The name of the Cloud Storage bucket for climate data"
  value       = google_storage_bucket.climate_data.name
}

output "storage_bucket_url" {
  description = "The URL of the Cloud Storage bucket"
  value       = google_storage_bucket.climate_data.url
}

output "storage_bucket_self_link" {
  description = "The self link of the Cloud Storage bucket"
  value       = google_storage_bucket.climate_data.self_link
}

# Cloud Functions
output "climate_processor_function_name" {
  description = "The name of the climate processor Cloud Function"
  value       = google_cloudfunctions_function.climate_processor.name
}

output "climate_processor_function_url" {
  description = "The HTTPS trigger URL for the climate processor function"
  value       = google_cloudfunctions_function.climate_processor.https_trigger_url
}

output "climate_processor_function_source_archive_url" {
  description = "The source archive URL for the climate processor function"
  value       = google_cloudfunctions_function.climate_processor.source_archive_url
}

output "climate_monitor_function_name" {
  description = "The name of the climate monitor Cloud Function"
  value       = google_cloudfunctions_function.climate_monitor.name
}

output "climate_monitor_function_url" {
  description = "The HTTPS trigger URL for the climate monitor function"
  value       = google_cloudfunctions_function.climate_monitor.https_trigger_url
}

output "climate_monitor_function_source_archive_url" {
  description = "The source archive URL for the climate monitor function"
  value       = google_cloudfunctions_function.climate_monitor.source_archive_url
}

# Service Account
output "service_account_email" {
  description = "The email address of the service account used by Cloud Functions"
  value       = google_service_account.climate_functions_sa.email
}

output "service_account_id" {
  description = "The ID of the service account used by Cloud Functions"
  value       = google_service_account.climate_functions_sa.account_id
}

output "service_account_unique_id" {
  description = "The unique ID of the service account used by Cloud Functions"
  value       = google_service_account.climate_functions_sa.unique_id
}

# Monitoring Resources
output "monitoring_alert_policy_id" {
  description = "The ID of the monitoring alert policy for high climate risk"
  value       = var.enable_monitoring_alerts ? google_monitoring_alert_policy.high_climate_risk[0].name : "Not created"
}

output "monitoring_dashboard_id" {
  description = "The ID of the monitoring dashboard for climate risk"
  value       = google_monitoring_dashboard.climate_risk_dashboard.id
}

output "monitoring_dashboard_url" {
  description = "URL to view the monitoring dashboard in the console"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.climate_risk_dashboard.id}?project=${var.project_id}"
}

# API Status
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = var.enable_apis
}

# Configuration Values
output "default_analysis_region" {
  description = "Default geographic region for climate analysis"
  value       = var.default_analysis_region
  sensitive   = false
}

output "default_analysis_start_date" {
  description = "Default start date for climate analysis"
  value       = var.default_analysis_start_date
}

output "default_analysis_end_date" {
  description = "Default end date for climate analysis"
  value       = var.default_analysis_end_date
}

# Quick Start Information
output "quick_start_commands" {
  description = "Commands to get started with the climate risk assessment system"
  value = {
    "trigger_climate_processing" = "curl -X POST '${google_cloudfunctions_function.climate_processor.https_trigger_url}' -H 'Content-Type: application/json' -d '{\"region_bounds\": ${jsonencode(var.default_analysis_region)}, \"start_date\": \"${var.default_analysis_start_date}\", \"end_date\": \"${var.default_analysis_end_date}\", \"dataset_id\": \"${google_bigquery_dataset.climate_dataset.dataset_id}\"}'"
    
    "monitor_climate_risks" = "curl -X POST '${google_cloudfunctions_function.climate_monitor.https_trigger_url}' -H 'Content-Type: application/json' -d '{\"dataset_id\": \"${google_bigquery_dataset.climate_dataset.dataset_id}\"}'"
    
    "query_climate_data" = "bq query --use_legacy_sql=false 'SELECT COUNT(*) as record_count FROM `${var.project_id}.${google_bigquery_dataset.climate_dataset.dataset_id}.climate_indicators`'"
    
    "view_risk_analysis" = "bq query --use_legacy_sql=false 'SELECT risk_category, COUNT(*) as locations, AVG(composite_risk_score) as avg_score FROM `${var.project_id}.${google_bigquery_dataset.climate_dataset.dataset_id}.climate_risk_analysis` GROUP BY risk_category ORDER BY avg_score DESC'"
  }
}

# Resource Management
output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Cost Management
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the climate risk assessment system"
  value = {
    "bigquery_cost_control" = "Use partitioning and clustering to reduce query costs. Set table expiration for temporary data."
    "storage_cost_optimization" = "Use lifecycle policies to automatically delete old data. Consider using Nearline or Coldline storage for archival."
    "function_cost_optimization" = "Monitor function execution time and memory usage. Use smaller memory allocations if possible."
    "monitoring_cost_management" = "Set up billing alerts to monitor costs. Use Cloud Monitoring efficiently to avoid unnecessary charges."
  }
}

# Security Information
output "security_considerations" {
  description = "Important security considerations for the deployed resources"
  value = {
    "service_account_permissions" = "Service account has admin permissions for BigQuery and Storage. Review and restrict as needed for production."
    "function_security" = "Functions use HTTPS triggers with secure SSL. Consider adding authentication for production use."
    "data_security" = "Storage bucket uses uniform bucket-level access. Data is encrypted at rest by default."
    "network_security" = "All resources are deployed in the specified region. Consider VPC-based deployment for enhanced security."
  }
}

# Troubleshooting Information
output "troubleshooting_commands" {
  description = "Commands for troubleshooting common issues"
  value = {
    "check_function_logs" = "gcloud functions logs read ${google_cloudfunctions_function.climate_processor.name} --region=${var.region}"
    "check_bigquery_jobs" = "bq ls -j --max_results=10"
    "verify_apis_enabled" = "gcloud services list --enabled"
    "check_iam_permissions" = "gcloud projects get-iam-policy ${var.project_id}"
  }
}