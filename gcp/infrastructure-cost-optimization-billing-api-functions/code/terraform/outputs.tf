# Project and resource identification outputs
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region used for resources"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# BigQuery outputs
output "bigquery_dataset_id" {
  description = "The BigQuery dataset ID for cost optimization data"
  value       = google_bigquery_dataset.cost_optimization.dataset_id
}

output "bigquery_dataset_location" {
  description = "The BigQuery dataset location"
  value       = google_bigquery_dataset.cost_optimization.location
}

output "cost_anomalies_table_id" {
  description = "The BigQuery table ID for cost anomaly tracking"
  value       = google_bigquery_table.cost_anomalies.table_id
}

output "bigquery_dataset_url" {
  description = "BigQuery dataset URL for easy access"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.cost_optimization.dataset_id}"
}

# Service Account outputs
output "service_account_email" {
  description = "Email address of the cost optimization service account"
  value       = google_service_account.cost_optimization.email
}

output "service_account_id" {
  description = "Unique ID of the cost optimization service account"
  value       = google_service_account.cost_optimization.unique_id
}

# Pub/Sub outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for cost optimization alerts"
  value       = google_pubsub_topic.cost_optimization_alerts.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.cost_optimization_alerts.id
}

output "budget_alerts_subscription" {
  description = "Name of the budget alerts Pub/Sub subscription"
  value       = google_pubsub_subscription.budget_alerts.name
}

output "anomaly_detection_subscription" {
  description = "Name of the anomaly detection Pub/Sub subscription"
  value       = google_pubsub_subscription.anomaly_detection.name
}

# Cloud Functions outputs
output "cost_analysis_function_name" {
  description = "Name of the cost analysis Cloud Function"
  value       = google_cloudfunctions2_function.cost_analysis.name
}

output "cost_analysis_function_uri" {
  description = "URI of the cost analysis Cloud Function"
  value       = google_cloudfunctions2_function.cost_analysis.service_config[0].uri
}

output "anomaly_detection_function_name" {
  description = "Name of the anomaly detection Cloud Function"
  value       = google_cloudfunctions2_function.anomaly_detection.name
}

output "anomaly_detection_function_uri" {
  description = "URI of the anomaly detection Cloud Function"
  value       = google_cloudfunctions2_function.anomaly_detection.service_config[0].uri
}

output "optimization_function_name" {
  description = "Name of the resource optimization Cloud Function"
  value       = google_cloudfunctions2_function.optimization.name
}

output "optimization_function_uri" {
  description = "URI of the resource optimization Cloud Function"
  value       = google_cloudfunctions2_function.optimization.service_config[0].uri
}

# Cloud Storage outputs
output "function_source_bucket" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.url
}

# Cloud Scheduler outputs
output "cost_analysis_scheduler_name" {
  description = "Name of the cost analysis scheduler job"
  value       = google_cloud_scheduler_job.cost_analysis.name
}

output "optimization_scheduler_name" {
  description = "Name of the optimization scheduler job"
  value       = google_cloud_scheduler_job.optimization.name
}

output "cost_analysis_schedule" {
  description = "Schedule for the cost analysis job"
  value       = google_cloud_scheduler_job.cost_analysis.schedule
}

output "optimization_schedule" {
  description = "Schedule for the optimization job"
  value       = google_cloud_scheduler_job.optimization.schedule
}

# Budget outputs
output "billing_budget_name" {
  description = "Display name of the billing budget"
  value       = google_billing_budget.cost_optimization.display_name
}

output "budget_amount" {
  description = "Budget amount in USD"
  value       = var.budget_amount
}

output "budget_thresholds" {
  description = "Budget alert thresholds"
  value       = var.budget_thresholds
}

# Monitoring outputs
output "alert_policy_name" {
  description = "Name of the cost anomaly alert policy"
  value       = google_monitoring_alert_policy.high_cost_anomaly.display_name
}

# Eventarc outputs
output "anomaly_detection_trigger_name" {
  description = "Name of the Eventarc trigger for anomaly detection"
  value       = google_eventarc_trigger.anomaly_detection_trigger.name
}

# Useful URLs for monitoring and management
output "cloud_console_urls" {
  description = "Useful Google Cloud Console URLs for monitoring the cost optimization system"
  value = {
    bigquery_console     = "https://console.cloud.google.com/bigquery?project=${var.project_id}"
    functions_console    = "https://console.cloud.google.com/functions?project=${var.project_id}"
    pubsub_console      = "https://console.cloud.google.com/cloudpubsub?project=${var.project_id}"
    monitoring_console  = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    billing_console     = "https://console.cloud.google.com/billing"
    scheduler_console   = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
  }
}

# Cost optimization system configuration summary
output "system_configuration" {
  description = "Summary of the cost optimization system configuration"
  value = {
    dataset_name           = local.dataset_name
    function_prefix        = local.function_prefix
    function_runtime       = var.function_runtime
    function_memory        = var.function_memory
    cost_analysis_schedule = var.cost_analysis_schedule
    optimization_schedule  = var.optimization_schedule
    budget_amount         = var.budget_amount
    budget_thresholds     = var.budget_thresholds
  }
}

# Next steps and recommendations
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Set up billing data export to BigQuery: https://cloud.google.com/billing/docs/how-to/export-data-bigquery",
    "2. Configure notification channels in Cloud Monitoring for alerts",
    "3. Test the cost analysis function manually using the provided URI",
    "4. Review and customize budget thresholds based on your spending patterns",
    "5. Set up additional monitoring dashboards in Cloud Monitoring or Looker Studio",
    "6. Consider implementing automated remediation actions based on optimization recommendations"
  ]
}