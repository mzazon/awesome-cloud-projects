# Outputs for AI-Powered Cost Analytics with BigQuery Analytics Hub and Vertex AI
# These outputs provide important resource information for verification and integration

# Project and Configuration Outputs
output "project_id" {
  description = "Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region used for regional resources"
  value       = var.region
}

output "deployment_id" {
  description = "Unique deployment identifier for this instance"
  value       = random_id.suffix.hex
}

# Storage Outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for model artifacts and data"
  value       = google_storage_bucket.model_artifacts.name
}

output "storage_bucket_url" {
  description = "Full URL of the Cloud Storage bucket"
  value       = google_storage_bucket.model_artifacts.url
}

output "storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.model_artifacts.location
}

# BigQuery Outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for cost analytics"
  value       = google_bigquery_dataset.cost_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.cost_analytics.location
}

output "bigquery_dataset_url" {
  description = "Console URL for the BigQuery dataset"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.cost_analytics.dataset_id}"
}

output "billing_data_table_id" {
  description = "Full ID of the billing data table"
  value       = "${var.project_id}.${google_bigquery_dataset.cost_analytics.dataset_id}.${google_bigquery_table.billing_data.table_id}"
}

output "daily_cost_summary_view" {
  description = "Full ID of the daily cost summary view"
  value       = "${var.project_id}.${google_bigquery_dataset.cost_analytics.dataset_id}.${google_bigquery_table.daily_cost_summary.table_id}"
}

output "cost_trends_view" {
  description = "Full ID of the cost trends analysis view"
  value       = "${var.project_id}.${google_bigquery_dataset.cost_analytics.dataset_id}.${google_bigquery_table.cost_trends.table_id}"
}

output "cost_anomalies_view" {
  description = "Full ID of the cost anomalies detection view"
  value       = "${var.project_id}.${google_bigquery_dataset.cost_analytics.dataset_id}.${google_bigquery_table.cost_anomalies.table_id}"
}

# Analytics Hub Outputs
output "analytics_hub_exchange_id" {
  description = "ID of the Analytics Hub data exchange"
  value       = google_bigquery_analytics_hub_data_exchange.cost_exchange.data_exchange_id
}

output "analytics_hub_exchange_name" {
  description = "Full name of the Analytics Hub data exchange"
  value       = google_bigquery_analytics_hub_data_exchange.cost_exchange.name
}

output "analytics_hub_listing_id" {
  description = "ID of the billing data feed listing"
  value       = google_bigquery_analytics_hub_listing.billing_feed.listing_id
}

output "analytics_hub_console_url" {
  description = "Console URL for the Analytics Hub exchange"
  value       = "https://console.cloud.google.com/bigquery/analytics-hub/exchanges/${var.bigquery_location}/${google_bigquery_analytics_hub_data_exchange.cost_exchange.data_exchange_id}?project=${var.project_id}"
}

# Service Account Outputs
output "vertex_ai_service_account_email" {
  description = "Email address of the Vertex AI service account"
  value       = google_service_account.vertex_ai_service_account.email
}

output "vertex_ai_service_account_id" {
  description = "Unique ID of the Vertex AI service account"
  value       = google_service_account.vertex_ai_service_account.unique_id
}

# Monitoring Outputs
output "monitoring_enabled" {
  description = "Whether Cloud Monitoring and alerting is enabled"
  value       = var.enable_monitoring
}

output "notification_email" {
  description = "Email address configured for notifications (if any)"
  value       = var.notification_email != "" ? var.notification_email : "Not configured"
  sensitive   = true
}

output "monitoring_alert_policy_ids" {
  description = "IDs of created monitoring alert policies"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.cost_anomaly_alert[*].name : []
}

output "notification_channel_ids" {
  description = "IDs of created notification channels"
  value       = var.enable_monitoring && var.notification_email != "" ? google_monitoring_notification_channel.email[*].name : []
}

# Configuration Outputs
output "sample_data_rows" {
  description = "Number of sample billing data rows generated"
  value       = var.sample_data_rows
}

output "anomaly_threshold" {
  description = "Configured threshold for cost anomaly detection"
  value       = var.anomaly_threshold
}

# Query Examples
output "useful_queries" {
  description = "Useful BigQuery queries for cost analysis"
  value = {
    total_cost_by_service = "SELECT service_description, SUM(cost) as total_cost FROM `${var.project_id}.${var.dataset_id}.billing_data` GROUP BY service_description ORDER BY total_cost DESC"
    
    recent_anomalies = "SELECT * FROM `${var.project_id}.${var.dataset_id}.cost_anomalies` WHERE usage_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) ORDER BY anomaly_score DESC LIMIT 10"
    
    cost_trends_last_30_days = "SELECT usage_date, service_description, daily_cost, seven_day_avg, growth_rate_pct FROM `${var.project_id}.${var.dataset_id}.cost_trends` WHERE usage_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY) ORDER BY usage_date DESC, daily_cost DESC"
    
    daily_summary = "SELECT * FROM `${var.project_id}.${var.dataset_id}.daily_cost_summary` WHERE usage_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) ORDER BY usage_date DESC, total_cost DESC LIMIT 20"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Recommended next steps after infrastructure deployment"
  value = {
    1 = "Connect your actual Cloud Billing export to the billing_data table"
    2 = "Train a Vertex AI model using the BigQuery ML model as a starting point"
    3 = "Create custom dashboards in Looker Studio or Data Studio"
    4 = "Set up scheduled queries for automated data processing"
    5 = "Configure additional monitoring and alerting rules"
    6 = "Integrate with existing cost management workflows"
  }
}

# Cost Estimation
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for running this solution (USD)"
  value = {
    bigquery_storage = "~$10-20 per TB stored"
    bigquery_compute = "~$5 per TB processed"
    cloud_storage = "~$1-3 for model artifacts"
    cloud_monitoring = "~$1-5 for basic monitoring"
    vertex_ai_endpoint = "~$50-200 for continuous deployment"
    total_estimate = "~$67-228 per month for typical usage"
  }
}

# Security Information
output "security_notes" {
  description = "Important security considerations for this deployment"
  value = {
    service_account = "Dedicated service account created with minimal required permissions"
    bigquery_access = "Dataset access controlled via IAM and BigQuery ACLs"
    storage_security = "Uniform bucket-level access enabled for Cloud Storage"
    data_encryption = "All data encrypted at rest and in transit by default"
    monitoring_access = "Alert notifications require proper IAM permissions"
  }
}