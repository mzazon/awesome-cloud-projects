# Project and resource identification outputs
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were created"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# BigQuery resource outputs
output "bigquery_dataset_id" {
  description = "The ID of the created BigQuery dataset"
  value       = google_bigquery_dataset.retail_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "The location of the BigQuery dataset"
  value       = google_bigquery_dataset.retail_analytics.location
}

output "sales_data_table_id" {
  description = "The ID of the sales data table"
  value       = google_bigquery_table.sales_data.table_id
}

output "dashboard_data_view_id" {
  description = "The ID of the materialized view for dashboard data"
  value       = google_bigquery_table.dashboard_data.table_id
}

output "bigquery_dataset_url" {
  description = "URL to access the BigQuery dataset in the Google Cloud Console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.retail_analytics.dataset_id}"
}

# BigQuery Data Canvas access information
output "data_canvas_url" {
  description = "URL to access BigQuery Data Canvas for this dataset"
  value       = "https://console.cloud.google.com/bigquery/canvas?project=${var.project_id}&dataset=${google_bigquery_dataset.retail_analytics.dataset_id}"
}

# Looker Studio connection information
output "looker_studio_connection_info" {
  description = "Information needed to connect Looker Studio to the BigQuery dataset"
  value = {
    project_id       = var.project_id
    dataset_id       = google_bigquery_dataset.retail_analytics.dataset_id
    table_id         = google_bigquery_table.dashboard_data.table_id
    connection_url   = "https://lookerstudio.google.com/datasources/create?connectorId=bigQuery"
    table_reference  = "${var.project_id}.${google_bigquery_dataset.retail_analytics.dataset_id}.${google_bigquery_table.dashboard_data.table_id}"
  }
}

# Cloud Function outputs
output "cloud_function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions_function.storytelling_function.name
}

output "cloud_function_url" {
  description = "HTTPS trigger URL for the Cloud Function"
  value       = google_cloudfunctions_function.storytelling_function.https_trigger_url
  sensitive   = true
}

output "cloud_function_service_account" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

# Cloud Scheduler outputs
output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.storytelling_job.name
}

output "scheduler_cron_schedule" {
  description = "Cron schedule for the automated reports"
  value       = google_cloud_scheduler_job.storytelling_job.schedule
}

output "scheduler_timezone" {
  description = "Timezone for the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.storytelling_job.time_zone
}

# Storage outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for function code and temporary files"
  value       = google_storage_bucket.function_bucket.name
}

output "storage_bucket_url" {
  description = "URL to access the Cloud Storage bucket in the Google Cloud Console"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.function_bucket.name}"
}

# Sample data loading status
output "sample_data_loaded" {
  description = "Whether sample data was loaded into the BigQuery table"
  value       = var.load_sample_data
}

output "sample_data_records_count" {
  description = "Number of sample data records configured to be loaded"
  value       = var.sample_data_records
}

# Service URLs and access points
output "google_cloud_console_urls" {
  description = "URLs to access various services in the Google Cloud Console"
  value = {
    bigquery_dataset  = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.retail_analytics.dataset_id}"
    cloud_functions   = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.storytelling_function.name}?project=${var.project_id}"
    cloud_scheduler   = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
    storage_bucket    = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.function_bucket.name}?project=${var.project_id}"
    vertex_ai         = "https://console.cloud.google.com/vertex-ai?project=${var.project_id}"
  }
}

# Testing and validation commands
output "validation_commands" {
  description = "Commands to validate the deployed infrastructure"
  value = {
    test_bigquery_data = "bq query --use_legacy_sql=false \"SELECT COUNT(*) as total_records, SUM(revenue) as total_revenue FROM \\`${var.project_id}.${google_bigquery_dataset.retail_analytics.dataset_id}.sales_data\\`\""
    test_cloud_function = "curl -X POST '${google_cloudfunctions_function.storytelling_function.https_trigger_url}' -H 'Content-Type: application/json' -d '{\"test\": true}'"
    check_scheduler_job = "gcloud scheduler jobs describe ${google_cloud_scheduler_job.storytelling_job.name} --location=${var.region}"
    view_function_logs = "gcloud functions logs read ${google_cloudfunctions_function.storytelling_function.name} --region=${var.region} --limit=10"
  }
}

# Analytics insights and quick start guide
output "getting_started_guide" {
  description = "Quick start guide for using the deployed data storytelling infrastructure"
  value = {
    step_1_access_bigquery = "Navigate to BigQuery in the Google Cloud Console and explore the ${google_bigquery_dataset.retail_analytics.dataset_id} dataset"
    step_2_data_canvas    = "Open BigQuery Data Canvas to start AI-powered data exploration: https://console.cloud.google.com/bigquery/canvas?project=${var.project_id}&dataset=${google_bigquery_dataset.retail_analytics.dataset_id}"
    step_3_test_function  = "Test the Cloud Function by calling its HTTPS trigger URL with a POST request"
    step_4_looker_studio  = "Connect Looker Studio to the materialized view table: ${var.project_id}.${google_bigquery_dataset.retail_analytics.dataset_id}.${google_bigquery_table.dashboard_data.table_id}"
    step_5_schedule_reports = "The Cloud Scheduler job will automatically generate reports based on the configured cron schedule: ${google_cloud_scheduler_job.storytelling_job.schedule}"
  }
}

# Resource costs and optimization information
output "cost_optimization_info" {
  description = "Information about resource costs and optimization opportunities"
  value = {
    bigquery_dataset_location = "Dataset location affects query costs - current location: ${google_bigquery_dataset.retail_analytics.location}"
    function_memory_mb       = "Cloud Function memory allocation affects costs - current: ${var.function_memory}MB"
    scheduler_frequency      = "Scheduler frequency affects function execution costs - current: ${google_cloud_scheduler_job.storytelling_job.schedule}"
    storage_class           = "Storage bucket class affects costs - current: ${google_storage_bucket.function_bucket.storage_class}"
    materialized_view_refresh = "Materialized view auto-refresh may incur additional costs"
  }
}

# Security and access information
output "security_information" {
  description = "Security-related information for the deployed resources"
  value = {
    function_service_account    = google_service_account.function_sa.email
    scheduler_service_account   = google_service_account.scheduler_sa.email
    bucket_uniform_access      = google_storage_bucket.function_bucket.uniform_bucket_level_access
    function_security_level    = "HTTPS only (SECURE_ALWAYS)"
    bigquery_dataset_access    = "Dataset access controlled through IAM and dataset-level permissions"
  }
}

# Next steps and extension opportunities
output "next_steps" {
  description = "Suggested next steps and extension opportunities"
  value = {
    vertex_ai_integration = "Enable Vertex AI integration by setting enable_vertex_ai = true for advanced AI-powered insights"
    custom_analytics     = "Add custom BigQuery routines and views for specific business analytics needs"
    dashboard_creation   = "Create interactive Looker Studio dashboards using the materialized view data"
    alert_configuration  = "Set up Cloud Monitoring alerts for function errors and data quality issues"
    data_governance     = "Implement column-level and row-level security for sensitive business data"
  }
}