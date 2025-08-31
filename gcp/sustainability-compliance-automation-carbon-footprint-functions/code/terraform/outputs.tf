# Outputs for the sustainability compliance automation solution
# This file defines the output values that will be displayed after deployment
# and can be used by other Terraform configurations or for verification

# Project and resource identification outputs
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# BigQuery dataset and table outputs
output "bigquery_dataset_id" {
  description = "The ID of the BigQuery dataset for carbon footprint data"
  value       = google_bigquery_dataset.carbon_footprint.dataset_id
}

output "bigquery_dataset_location" {
  description = "The location of the BigQuery dataset"
  value       = google_bigquery_dataset.carbon_footprint.location
}

output "sustainability_metrics_table" {
  description = "Full table reference for the sustainability metrics table"
  value       = "${var.project_id}.${google_bigquery_dataset.carbon_footprint.dataset_id}.${google_bigquery_table.sustainability_metrics.table_id}"
}

# Cloud Functions outputs
output "process_function_name" {
  description = "Name of the data processing Cloud Function"
  value       = google_cloudfunctions_function.process_carbon_data.name
}

output "process_function_url" {
  description = "HTTPS trigger URL for the data processing function"
  value       = google_cloudfunctions_function.process_carbon_data.https_trigger_url
  sensitive   = true
}

output "report_function_name" {
  description = "Name of the ESG report generation Cloud Function"
  value       = google_cloudfunctions_function.generate_esg_report.name
}

output "report_function_url" {
  description = "HTTPS trigger URL for the report generation function"
  value       = google_cloudfunctions_function.generate_esg_report.https_trigger_url
  sensitive   = true
}

output "alert_function_name" {
  description = "Name of the carbon alert Cloud Function (if enabled)"
  value       = var.enable_alerts ? google_cloudfunctions_function.carbon_alerts[0].name : null
}

output "alert_function_url" {
  description = "HTTPS trigger URL for the alert function (if enabled)"
  value       = var.enable_alerts ? google_cloudfunctions_function.carbon_alerts[0].https_trigger_url : null
  sensitive   = true
}

# Service account outputs
output "functions_service_account_email" {
  description = "Email address of the service account used by Cloud Functions"
  value       = google_service_account.functions_sa.email
}

output "functions_service_account_id" {
  description = "ID of the service account used by Cloud Functions"
  value       = google_service_account.functions_sa.account_id
}

# Cloud Storage outputs
output "esg_reports_bucket_name" {
  description = "Name of the Cloud Storage bucket for ESG reports"
  value       = google_storage_bucket.esg_reports.name
}

output "esg_reports_bucket_url" {
  description = "URL of the Cloud Storage bucket for ESG reports"
  value       = google_storage_bucket.esg_reports.url
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

# Cloud Scheduler outputs
output "scheduled_jobs" {
  description = "List of Cloud Scheduler job names (if enabled)"
  value = var.enable_scheduled_processing ? [
    google_cloud_scheduler_job.process_carbon_data[0].name,
    google_cloud_scheduler_job.generate_esg_reports[0].name,
    var.enable_alerts ? google_cloud_scheduler_job.carbon_alerts_check[0].name : null
  ] : []
}

output "data_processing_schedule" {
  description = "Schedule for data processing job"
  value       = var.enable_scheduled_processing ? google_cloud_scheduler_job.process_carbon_data[0].schedule : null
}

output "report_generation_schedule" {
  description = "Schedule for report generation job"
  value       = var.enable_scheduled_processing ? google_cloud_scheduler_job.generate_esg_reports[0].schedule : null
}

output "alert_check_schedule" {
  description = "Schedule for alert checking job"
  value       = var.enable_scheduled_processing && var.enable_alerts ? google_cloud_scheduler_job.carbon_alerts_check[0].schedule : null
}

# Data transfer configuration outputs
output "carbon_footprint_transfer_config_name" {
  description = "Name of the BigQuery Data Transfer configuration for Carbon Footprint"
  value       = google_bigquery_data_transfer_config.carbon_footprint_export.display_name
}

output "carbon_footprint_transfer_schedule" {
  description = "Schedule for the Carbon Footprint data transfer"
  value       = google_bigquery_data_transfer_config.carbon_footprint_export.schedule
}

# Configuration summary outputs
output "sustainability_monitoring_summary" {
  description = "Summary of sustainability monitoring configuration"
  value = {
    dataset_name                = local.dataset_name
    functions_deployed          = 3
    alerts_enabled             = var.enable_alerts
    scheduled_processing       = var.enable_scheduled_processing
    monthly_threshold_kg_co2e  = var.monthly_emissions_threshold
    growth_threshold_percent   = var.growth_threshold * 100
    storage_class              = var.storage_class
  }
}

# Quick start commands
output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    check_dataset = "gcloud auth login && bq ls ${var.project_id}:${google_bigquery_dataset.carbon_footprint.dataset_id}"
    list_functions = "gcloud functions list --regions=${var.region} --filter='name:${local.function_prefix}'"
    check_scheduler_jobs = var.enable_scheduled_processing ? "gcloud scheduler jobs list --location=${var.region} --filter='name:${random_id.suffix.hex}'" : "Scheduled jobs not enabled"
    test_process_function = "curl -X POST '${google_cloudfunctions_function.process_carbon_data.https_trigger_url}' -H 'Content-Type: application/json' -d '{\"test\": true}'"
  }
}

# Cost estimation information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the solution (USD, approximate)"
  value = {
    bigquery_storage = "~$0.02 per GB stored"
    bigquery_queries = "~$5 per TB processed"
    cloud_functions = "~$0.40 per million invocations"
    cloud_storage = "~$0.02 per GB stored (STANDARD class)"
    cloud_scheduler = "~$0.10 per job per month"
    total_estimate = "$5-15 per month for typical usage"
  }
}

# Security and compliance information
output "security_configuration" {
  description = "Security and compliance configuration summary"
  value = {
    service_account_principle = "Least privilege IAM roles assigned"
    data_encryption = "Data encrypted at rest and in transit"
    bucket_access = "Uniform bucket-level access enabled"
    function_authentication = "Functions require authentication"
    audit_logging = "Cloud Audit Logs enabled"
    data_retention = "1-year lifecycle policy on reports"
  }
}