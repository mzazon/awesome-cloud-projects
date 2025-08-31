# Output values for GCP content performance optimization infrastructure
# These outputs provide important resource information for integration and verification

output "project_id" {
  description = "Google Cloud project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where regional resources were deployed"
  value       = var.region
}

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for content analytics"
  value       = google_bigquery_dataset.content_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "BigQuery dataset location"
  value       = google_bigquery_dataset.content_analytics.location
}

output "bigquery_table_id" {
  description = "BigQuery table ID for performance data"
  value       = google_bigquery_table.performance_data.table_id
}

output "bigquery_table_self_link" {
  description = "BigQuery table self link for API access"
  value       = google_bigquery_table.performance_data.self_link
}

output "performance_summary_view_id" {
  description = "BigQuery view ID for performance summary analytics"
  value       = google_bigquery_table.performance_summary_view.table_id
}

output "content_rankings_view_id" {
  description = "BigQuery view ID for content rankings"
  value       = google_bigquery_table.content_rankings_view.table_id
}

output "storage_bucket_name" {
  description = "Cloud Storage bucket name for content assets"
  value       = google_storage_bucket.content_optimization.name
}

output "storage_bucket_url" {
  description = "Cloud Storage bucket URL for content assets"
  value       = google_storage_bucket.content_optimization.url
}

output "storage_bucket_self_link" {
  description = "Cloud Storage bucket self link for API access"
  value       = google_storage_bucket.content_optimization.self_link
}

output "cloud_function_name" {
  description = "Cloud Function name for content analysis"
  value       = google_cloudfunctions2_function.content_analyzer.name
}

output "cloud_function_url" {
  description = "Cloud Function HTTP trigger URL for content analysis"
  value       = google_cloudfunctions2_function.content_analyzer.service_config[0].uri
  sensitive   = false
}

output "cloud_function_location" {
  description = "Cloud Function deployment location"
  value       = google_cloudfunctions2_function.content_analyzer.location
}

output "service_account_email" {
  description = "Service account email for Cloud Function authentication"
  value       = google_service_account.content_analyzer.email
}

output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value = var.enable_apis ? [
    "cloudfunctions.googleapis.com",
    "aiplatform.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com"
  ] : []
}

output "bigquery_connection_string" {
  description = "BigQuery connection string for applications"
  value       = "${var.project_id}.${google_bigquery_dataset.content_analytics.dataset_id}.${google_bigquery_table.performance_data.table_id}"
}

output "deployment_summary" {
  description = "Summary of deployed resources for content performance optimization"
  value = {
    project_id          = var.project_id
    region              = var.region
    dataset_name        = google_bigquery_dataset.content_analytics.dataset_id
    table_name          = google_bigquery_table.performance_data.table_id
    bucket_name         = google_storage_bucket.content_optimization.name
    function_name       = google_cloudfunctions2_function.content_analyzer.name
    function_url        = google_cloudfunctions2_function.content_analyzer.service_config[0].uri
    service_account     = google_service_account.content_analyzer.email
    sample_data_loaded  = var.enable_sample_data
    gemini_model        = var.gemini_model
  }
}

output "testing_commands" {
  description = "Commands to test the deployed content analysis system"
  value = {
    bigquery_list_datasets = "bq ls ${var.project_id}:${google_bigquery_dataset.content_analytics.dataset_id}"
    bigquery_show_table    = "bq show ${var.project_id}:${google_bigquery_dataset.content_analytics.dataset_id}.${google_bigquery_table.performance_data.table_id}"
    cloud_function_test    = "curl -X POST ${google_cloudfunctions2_function.content_analyzer.service_config[0].uri} -H 'Content-Type: application/json' -d '{\"trigger\": \"manual_analysis\"}'"
    storage_list_buckets   = "gsutil ls gs://${google_storage_bucket.content_optimization.name}/"
    performance_summary    = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.content_analytics.dataset_id}.content_performance_summary`'"
    content_rankings       = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.content_analytics.dataset_id}.content_rankings` LIMIT 5'"
  }
}

output "resource_urls" {
  description = "Direct URLs to access deployed resources in Google Cloud Console"
  value = {
    bigquery_console    = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.content_analytics.dataset_id}!3s${google_bigquery_table.performance_data.table_id}"
    storage_console     = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.content_optimization.name}?project=${var.project_id}"
    function_console    = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.content_analyzer.name}?project=${var.project_id}"
    vertex_ai_console   = "https://console.cloud.google.com/vertex-ai?project=${var.project_id}"
  }
}