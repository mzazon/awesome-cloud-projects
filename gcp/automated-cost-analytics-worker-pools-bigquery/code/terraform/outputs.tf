# Outputs for GCP Automated Cost Analytics Infrastructure
# This file defines all output values that will be displayed after successful deployment

# Core Infrastructure Outputs
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where regional resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment label applied to all resources"
  value       = var.environment
}

# BigQuery Outputs
output "bigquery_dataset_id" {
  description = "The BigQuery dataset ID for cost analytics data"
  value       = google_bigquery_dataset.cost_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "The location of the BigQuery dataset"
  value       = google_bigquery_dataset.cost_analytics.location
}

output "bigquery_dataset_full_id" {
  description = "The full BigQuery dataset ID including project"
  value       = "${var.project_id}.${google_bigquery_dataset.cost_analytics.dataset_id}"
}

output "daily_costs_table_id" {
  description = "The BigQuery table ID for daily cost data"
  value       = google_bigquery_table.daily_costs.table_id
}

output "monthly_summary_view_id" {
  description = "The BigQuery view ID for monthly cost summaries"
  value       = google_bigquery_table.monthly_cost_summary.table_id
}

output "trend_analysis_view_id" {
  description = "The BigQuery view ID for cost trend analysis"
  value       = google_bigquery_table.cost_trend_analysis.table_id
}

# Cloud Run Outputs
output "cloud_run_service_name" {
  description = "The name of the deployed Cloud Run service"
  value       = google_cloud_run_service.cost_worker.name
}

output "cloud_run_service_url" {
  description = "The URL of the deployed Cloud Run service"
  value       = google_cloud_run_service.cost_worker.status[0].url
  sensitive   = false
}

output "cloud_run_service_location" {
  description = "The location of the Cloud Run service"
  value       = google_cloud_run_service.cost_worker.location
}

output "cloud_run_latest_revision" {
  description = "The latest revision name of the Cloud Run service"
  value       = google_cloud_run_service.cost_worker.status[0].latest_revision_name
}

# Pub/Sub Outputs
output "pubsub_topic_name" {
  description = "The name of the Pub/Sub topic for cost processing events"
  value       = google_pubsub_topic.cost_processing.name
}

output "pubsub_topic_id" {
  description = "The full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.cost_processing.id
}

output "pubsub_subscription_name" {
  description = "The name of the Pub/Sub subscription"
  value       = google_pubsub_subscription.cost_processing.name
}

output "pubsub_subscription_id" {
  description = "The full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.cost_processing.id
}

# Cloud Scheduler Outputs
output "scheduler_job_name" {
  description = "The name of the Cloud Scheduler job for automated processing"
  value       = google_cloud_scheduler_job.daily_cost_analysis.name
}

output "scheduler_job_id" {
  description = "The full resource ID of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.daily_cost_analysis.id
}

output "scheduler_cron_schedule" {
  description = "The cron schedule for the automated cost processing"
  value       = google_cloud_scheduler_job.daily_cost_analysis.schedule
}

output "scheduler_timezone" {
  description = "The timezone used for the scheduler job"
  value       = google_cloud_scheduler_job.daily_cost_analysis.time_zone
}

# Service Account Outputs
output "service_account_id" {
  description = "The ID of the service account used by the cost worker"
  value       = google_service_account.cost_worker.account_id
}

output "service_account_email" {
  description = "The email address of the service account used by the cost worker"
  value       = google_service_account.cost_worker.email
}

output "service_account_unique_id" {
  description = "The unique ID of the service account"
  value       = google_service_account.cost_worker.unique_id
}

# Resource Naming Outputs
output "name_suffix" {
  description = "The random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "resource_labels" {
  description = "The common labels applied to all resources"
  value       = local.common_labels
}

# Configuration Outputs
output "enabled_apis" {
  description = "List of GCP APIs that were enabled for this deployment"
  value       = local.required_apis
}

# BigQuery Connection Information
output "bigquery_connection_info" {
  description = "Information for connecting to BigQuery resources"
  value = {
    project_id     = var.project_id
    dataset_id     = google_bigquery_dataset.cost_analytics.dataset_id
    daily_costs_table = "${var.project_id}.${google_bigquery_dataset.cost_analytics.dataset_id}.${google_bigquery_table.daily_costs.table_id}"
    monthly_summary_view = "${var.project_id}.${google_bigquery_dataset.cost_analytics.dataset_id}.${google_bigquery_table.monthly_cost_summary.table_id}"
    trend_analysis_view = "${var.project_id}.${google_bigquery_dataset.cost_analytics.dataset_id}.${google_bigquery_table.cost_trend_analysis.table_id}"
  }
}

# Monitoring and Operations Outputs
output "monitoring_info" {
  description = "Information for monitoring and operations"
  value = {
    cloud_run_service_name = google_cloud_run_service.cost_worker.name
    cloud_run_url         = google_cloud_run_service.cost_worker.status[0].url
    pubsub_topic          = google_pubsub_topic.cost_processing.name
    scheduler_job         = google_cloud_scheduler_job.daily_cost_analysis.name
    service_account       = google_service_account.cost_worker.email
  }
}

# Sample Commands Output
output "sample_commands" {
  description = "Sample commands for testing and validation"
  value = {
    trigger_manual_processing = "gcloud pubsub topics publish ${google_pubsub_topic.cost_processing.name} --message '{\"test\":\"manual_trigger\",\"timestamp\":\"$(date -Iseconds)\"}'"
    query_daily_costs = "bq query --use_legacy_sql=false 'SELECT COUNT(*) as record_count, MIN(usage_date) as earliest_date, MAX(usage_date) as latest_date, SUM(cost) as total_cost FROM \\`${var.project_id}.${google_bigquery_dataset.cost_analytics.dataset_id}.${google_bigquery_table.daily_costs.table_id}\\`'"
    view_cloud_run_logs = "gcloud logs read \"resource.type=cloud_run_revision\" --filter=\"resource.labels.service_name=${google_cloud_run_service.cost_worker.name}\" --limit=10"
    check_scheduler_status = "gcloud scheduler jobs describe ${google_cloud_scheduler_job.daily_cost_analysis.name} --location=${var.region}"
  }
}

# Cost Estimation Output
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the deployed infrastructure"
  value = {
    cloud_run        = "~$2-5 (based on actual usage, serverless pricing)"
    bigquery_storage = "~$1-3 (depends on data volume)"
    pubsub          = "~$0.50-1 (based on message volume)"
    cloud_scheduler = "~$0.10 (minimal cost for scheduled jobs)"
    total_estimated = "~$3.60-9.10 per month (highly dependent on usage patterns)"
    note           = "Costs are estimates and will vary based on actual usage patterns and data volumes"
  }
}

# Next Steps Output
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Build and deploy the cost processing worker container image to Cloud Run",
    "2. Configure the billing account ID in the Cloud Run environment variables",
    "3. Test the pipeline by publishing a message to the Pub/Sub topic",
    "4. Verify BigQuery tables are populated with cost data",
    "5. Set up monitoring and alerting for the cost analytics pipeline",
    "6. Create additional BigQuery views or dashboards for cost analysis"
  ]
}