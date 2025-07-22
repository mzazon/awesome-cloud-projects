# Outputs for BigQuery Query Optimization Infrastructure
# This file defines outputs to provide important information after deployment

# Project and Environment Information
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name"
  value       = var.environment
}

output "resource_suffix" {
  description = "The random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# BigQuery Resources
output "bigquery_dataset_id" {
  description = "The BigQuery dataset ID for analytics"
  value       = google_bigquery_dataset.optimization_dataset.dataset_id
}

output "bigquery_dataset_location" {
  description = "The location of the BigQuery dataset"
  value       = google_bigquery_dataset.optimization_dataset.location
}

output "bigquery_dataset_url" {
  description = "The URL to access the BigQuery dataset in the console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.optimization_dataset.dataset_id}"
}

output "sales_transactions_table" {
  description = "The full table ID for the sales transactions table"
  value       = "${var.project_id}.${google_bigquery_dataset.optimization_dataset.dataset_id}.${google_bigquery_table.sales_transactions.table_id}"
}

output "query_performance_view" {
  description = "The full view ID for query performance metrics"
  value       = "${var.project_id}.${google_bigquery_dataset.optimization_dataset.dataset_id}.${google_bigquery_table.query_performance_view.table_id}"
}

output "optimization_recommendations_table" {
  description = "The full table ID for optimization recommendations"
  value       = "${var.project_id}.${google_bigquery_dataset.optimization_dataset.dataset_id}.${google_bigquery_table.optimization_recommendations.table_id}"
}

output "sales_summary_materialized_view" {
  description = "The full materialized view ID for sales summary"
  value       = "${var.project_id}.${google_bigquery_dataset.optimization_dataset.dataset_id}.${google_bigquery_table.sales_summary_mv.table_id}"
}

# Cloud Storage Resources
output "storage_bucket_name" {
  description = "The name of the Cloud Storage bucket"
  value       = google_storage_bucket.optimization_bucket.name
}

output "storage_bucket_url" {
  description = "The URL to access the storage bucket in the console"
  value       = google_storage_bucket.optimization_bucket.url
}

output "storage_bucket_self_link" {
  description = "The self-link of the storage bucket"
  value       = google_storage_bucket.optimization_bucket.self_link
}

# Cloud Composer Resources
output "composer_environment_name" {
  description = "The name of the Cloud Composer environment"
  value       = google_composer_environment.optimization_env.name
}

output "composer_airflow_uri" {
  description = "The URI of the Apache Airflow web interface"
  value       = google_composer_environment.optimization_env.config[0].airflow_uri
}

output "composer_gcs_bucket" {
  description = "The Cloud Storage bucket used by the Composer environment"
  value       = google_composer_environment.optimization_env.config[0].dag_gcs_prefix
}

output "composer_environment_url" {
  description = "The URL to access the Composer environment in the console"
  value       = "https://console.cloud.google.com/composer/environments/detail/${var.region}/${google_composer_environment.optimization_env.name}?project=${var.project_id}"
}

# Service Account Information
output "composer_service_account_email" {
  description = "The email of the Cloud Composer service account"
  value       = var.create_service_accounts ? google_service_account.composer_sa[0].email : "default"
}

output "bigquery_service_account_email" {
  description = "The email of the BigQuery service account"
  value       = var.create_service_accounts ? google_service_account.bigquery_sa[0].email : "default"
}

output "vertex_ai_service_account_email" {
  description = "The email of the Vertex AI service account"
  value       = var.create_service_accounts ? google_service_account.vertex_ai_sa[0].email : "default"
}

# Monitoring Resources
output "monitoring_dashboard_url" {
  description = "The URL to access the monitoring dashboard"
  value       = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.optimization_dashboard[0].id}?project=${var.project_id}" : "Monitoring disabled"
}

output "monitoring_dashboard_id" {
  description = "The ID of the monitoring dashboard"
  value       = var.enable_monitoring ? google_monitoring_dashboard.optimization_dashboard[0].id : null
}

# DAG and ML Script Locations
output "optimization_dag_location" {
  description = "The Cloud Storage location of the optimization DAG"
  value       = "gs://${google_composer_environment.optimization_env.config[0].dag_gcs_prefix}/dags/query_optimization_dag.py"
}

output "ml_training_script_location" {
  description = "The Cloud Storage location of the ML training script"
  value       = "gs://${google_storage_bucket.optimization_bucket.name}/ml/query_optimization_model.py"
}

# Sample Queries for Testing
output "sample_test_query" {
  description = "A sample query to test the optimization system"
  value = "SELECT * FROM `${var.project_id}.${google_bigquery_dataset.optimization_dataset.dataset_id}.${google_bigquery_table.sales_transactions.table_id}` WHERE transaction_date >= '2024-01-01' ORDER BY amount DESC LIMIT 100"
}

output "materialized_view_test_query" {
  description = "A sample query that should benefit from the materialized view"
  value = "SELECT channel, SUM(total_amount) FROM `${var.project_id}.${google_bigquery_dataset.optimization_dataset.dataset_id}.${google_bigquery_table.sales_summary_mv.table_id}` WHERE transaction_date >= CURRENT_DATE() GROUP BY channel"
}

# Cost and Resource Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the deployed resources"
  value = {
    composer_environment = "~$150-300 (depends on node count and usage)"
    bigquery_storage     = "~$5-20 (depends on data volume)"
    bigquery_queries     = "~$20-100 (depends on query volume)"
    cloud_storage        = "~$5-15 (depends on data volume)"
    vertex_ai_training   = "~$10-50 (depends on training frequency)"
    monitoring           = "~$5-15 (depends on metrics volume)"
    total_estimated      = "~$195-500 per month"
  }
}

# Next Steps and Usage Information
output "next_steps" {
  description = "Instructions for using the deployed infrastructure"
  value = {
    step_1 = "Access the Airflow UI at: ${google_composer_environment.optimization_env.config[0].airflow_uri}"
    step_2 = "Populate sample data using: bq query --use_legacy_sql=false --destination_table=${var.project_id}:${google_bigquery_dataset.optimization_dataset.dataset_id}.sales_transactions 'CREATE TABLE...' (see recipe documentation)"
    step_3 = "Trigger the optimization DAG manually to test the pipeline"
    step_4 = "Monitor query performance in the BigQuery console and the monitoring dashboard"
    step_5 = "Review optimization recommendations in the optimization_recommendations table"
  }
}

# Important Configuration Details
output "configuration_summary" {
  description = "Summary of key configuration settings"
  value = {
    dataset_location              = google_bigquery_dataset.optimization_dataset.location
    composer_node_count          = var.composer_node_count
    composer_machine_type        = var.composer_machine_type
    materialized_view_refresh    = "${var.materialized_view_refresh_interval} minutes"
    table_expiration_enabled     = var.enable_cost_controls
    monitoring_enabled           = var.enable_monitoring
    custom_service_accounts      = var.create_service_accounts
  }
}

# API Endpoints and CLI Commands
output "useful_commands" {
  description = "Useful CLI commands for managing the infrastructure"
  value = {
    view_dataset = "bq ls ${google_bigquery_dataset.optimization_dataset.dataset_id}"
    query_performance = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.optimization_dataset.dataset_id}.query_performance_metrics` LIMIT 10'"
    check_recommendations = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.optimization_dataset.dataset_id}.optimization_recommendations` ORDER BY created_timestamp DESC LIMIT 10'"
    composer_dags = "gcloud composer environments storage dags list --environment=${google_composer_environment.optimization_env.name} --location=${var.region}"
    storage_contents = "gsutil ls -la gs://${google_storage_bucket.optimization_bucket.name}/"
  }
}

# Resource Labels for Tracking
output "resource_labels" {
  description = "Labels applied to all resources for tracking and billing"
  value       = local.common_labels
}