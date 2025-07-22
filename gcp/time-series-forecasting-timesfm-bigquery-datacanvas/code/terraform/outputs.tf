# Outputs for TimesFM BigQuery DataCanvas Time Series Forecasting Infrastructure

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

# BigQuery Dataset and Tables
output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for financial forecasting"
  value       = google_bigquery_dataset.financial_forecasting.dataset_id
}

output "bigquery_dataset_location" {
  description = "BigQuery dataset location"
  value       = google_bigquery_dataset.financial_forecasting.location
}

output "stock_prices_table_id" {
  description = "Full table ID for stock prices table"
  value       = "${var.project_id}.${google_bigquery_dataset.financial_forecasting.dataset_id}.${google_bigquery_table.stock_prices.table_id}"
}

output "timesfm_forecasts_table_id" {
  description = "Full table ID for TimesFM forecasts table"
  value       = "${var.project_id}.${google_bigquery_dataset.financial_forecasting.dataset_id}.${google_bigquery_table.timesfm_forecasts.table_id}"
}

output "forecast_analytics_view_id" {
  description = "Full view ID for forecast analytics (DataCanvas ready)"
  value       = "${var.project_id}.${google_bigquery_dataset.financial_forecasting.dataset_id}.${google_bigquery_table.forecast_analytics_view.table_id}"
}

output "trend_analysis_view_id" {
  description = "Full view ID for trend analysis"
  value       = "${var.project_id}.${google_bigquery_dataset.financial_forecasting.dataset_id}.${google_bigquery_table.trend_analysis_view.table_id}"
}

output "forecast_metrics_table_id" {
  description = "Full table ID for forecast accuracy metrics"
  value       = "${var.project_id}.${google_bigquery_dataset.financial_forecasting.dataset_id}.${google_bigquery_table.forecast_metrics.table_id}"
}

output "alert_conditions_view_id" {
  description = "Full view ID for alert conditions monitoring"
  value       = "${var.project_id}.${google_bigquery_dataset.financial_forecasting.dataset_id}.${google_bigquery_table.alert_conditions_view.table_id}"
}

# Cloud Function
output "cloud_function_name" {
  description = "Name of the Cloud Function for data processing"
  value       = google_cloudfunctions2_function.forecast_processor.name
}

output "cloud_function_url" {
  description = "HTTPS URL of the Cloud Function"
  value       = google_cloudfunctions2_function.forecast_processor.service_config[0].uri
}

output "cloud_function_service_account" {
  description = "Email of the service account used by Cloud Function"
  value       = google_service_account.function_sa.email
}

# Cloud Storage
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.function_source.url
}

# Cloud Scheduler
output "daily_forecast_job_name" {
  description = "Name of the daily forecast Cloud Scheduler job"
  value       = google_cloud_scheduler_job.daily_forecast.name
}

output "forecast_monitor_job_name" {
  description = "Name of the forecast monitoring Cloud Scheduler job"
  value       = google_cloud_scheduler_job.forecast_monitor.name
}

output "daily_forecast_schedule" {
  description = "Schedule for daily forecasting"
  value       = var.daily_forecast_schedule
}

output "monitoring_schedule" {
  description = "Schedule for forecast accuracy monitoring"
  value       = var.monitoring_schedule
}

# Configuration
output "forecast_symbols" {
  description = "List of stock symbols included in automated forecasting"
  value       = var.forecast_symbols
}

output "forecast_horizon_days" {
  description = "Number of days to forecast ahead"
  value       = var.forecast_horizon_days
}

output "confidence_level" {
  description = "Confidence level for prediction intervals"
  value       = var.confidence_level
}

# BigQuery Studio DataCanvas URLs
output "bigquery_studio_url" {
  description = "URL to access BigQuery Studio for DataCanvas"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.financial_forecasting.dataset_id}"
}

output "datacanvas_dataset_url" {
  description = "Direct URL to the dataset in BigQuery Studio for DataCanvas creation"
  value       = "https://console.cloud.google.com/bigquery/canvas?project=${var.project_id}&dataset=${google_bigquery_dataset.financial_forecasting.dataset_id}"
}

# Sample queries for testing
output "sample_data_insertion_curl" {
  description = "Sample curl command to insert test data via Cloud Function"
  value = <<-EOT
curl -X POST ${google_cloudfunctions2_function.forecast_processor.service_config[0].uri} \
     -H "Content-Type: application/json" \
     -d '{
       "symbol": "TSLA",
       "date": "2024-01-15",
       "close_price": 238.45,
       "volume": 95847000,
       "market_cap": 758000000000
     }'
EOT
}

output "sample_forecast_trigger_curl" {
  description = "Sample curl command to trigger daily forecasting"
  value = <<-EOT
curl -X POST ${google_cloudfunctions2_function.forecast_processor.service_config[0].uri} \
     -H "Content-Type: application/json" \
     -d '{
       "action": "daily_forecast",
       "symbols": ["AAPL", "GOOGL", "MSFT", "AMZN"]
     }'
EOT
}

# BigQuery commands for validation
output "bigquery_validation_commands" {
  description = "BigQuery commands to validate the deployment"
  value = {
    check_dataset = "bq ls ${var.project_id}:${google_bigquery_dataset.financial_forecasting.dataset_id}"
    check_tables  = "bq ls ${var.project_id}:${google_bigquery_dataset.financial_forecasting.dataset_id}"
    sample_query  = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.financial_forecasting.dataset_id}.${google_bigquery_table.stock_prices.table_id}` LIMIT 10'"
  }
}

# Monitoring and alerting
output "monitoring_dashboard_url" {
  description = "URL to create monitoring dashboard for the forecasting system"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom?project=${var.project_id}"
}

output "logs_url" {
  description = "URL to view Cloud Function logs"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.forecast_processor.name}?project=${var.project_id}&tab=logs"
}

# Resource labels applied
output "resource_labels" {
  description = "Labels applied to all resources"
  value       = local.common_labels
}

# Cost estimation note
output "cost_estimation_note" {
  description = "Information about expected costs"
  value = <<-EOT
Expected monthly costs (approximate):
- BigQuery: $10-50 (depending on data volume and query frequency)
- Cloud Functions: $5-20 (based on 1000+ invocations/month)
- Cloud Storage: $1-5 (for function source code storage)
- Cloud Scheduler: $0.10 (for 2 jobs)
- Total estimated: $16-75/month

Costs may vary based on:
- Data volume and query complexity
- Forecast frequency and symbol count
- Function execution time and memory usage
- BigQuery DataCanvas usage patterns
EOT
}