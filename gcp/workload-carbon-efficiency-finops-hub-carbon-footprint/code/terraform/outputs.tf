# Project and configuration outputs
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were created"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Service account outputs
output "carbon_efficiency_service_account" {
  description = "Service account email for carbon efficiency monitoring"
  value       = google_service_account.carbon_efficiency.email
}

output "carbon_efficiency_service_account_id" {
  description = "Service account ID for carbon efficiency monitoring"
  value       = google_service_account.carbon_efficiency.id
}

# Cloud Functions outputs
output "carbon_efficiency_correlator_url" {
  description = "HTTPS trigger URL for the carbon efficiency correlation function"
  value       = google_cloudfunctions_function.carbon_efficiency_correlator.https_trigger_url
  sensitive   = true
}

output "carbon_efficiency_correlator_name" {
  description = "Name of the carbon efficiency correlation function"
  value       = google_cloudfunctions_function.carbon_efficiency_correlator.name
}

output "carbon_efficiency_optimizer_name" {
  description = "Name of the carbon efficiency optimization function"
  value       = google_cloudfunctions_function.carbon_efficiency_optimizer.name
}

# Pub/Sub outputs
output "carbon_optimization_topic" {
  description = "Pub/Sub topic name for carbon optimization triggers"
  value       = google_pubsub_topic.carbon_optimization.name
}

output "carbon_optimization_topic_id" {
  description = "Full resource ID of the carbon optimization Pub/Sub topic"
  value       = google_pubsub_topic.carbon_optimization.id
}

# Cloud Workflows outputs
output "carbon_efficiency_workflow_name" {
  description = "Name of the carbon efficiency workflow"
  value       = google_workflows_workflow.carbon_efficiency.name
}

output "carbon_efficiency_workflow_id" {
  description = "Full resource ID of the carbon efficiency workflow"
  value       = google_workflows_workflow.carbon_efficiency.id
}

# Cloud Scheduler outputs
output "carbon_efficiency_scheduler_name" {
  description = "Name of the carbon efficiency scheduler job"
  value       = google_cloud_scheduler_job.carbon_efficiency.name
}

output "efficiency_analysis_schedule" {
  description = "Cron schedule for automated carbon efficiency analysis"
  value       = var.efficiency_analysis_schedule
}

# BigQuery outputs (conditional)
output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for carbon efficiency data (if created)"
  value       = var.create_bigquery_dataset ? google_bigquery_dataset.carbon_efficiency[0].dataset_id : null
}

output "bigquery_dataset_location" {
  description = "BigQuery dataset location (if created)"
  value       = var.create_bigquery_dataset ? google_bigquery_dataset.carbon_efficiency[0].location : null
}

output "finops_hub_log_sink_name" {
  description = "Name of the FinOps Hub insights log sink (if created)"
  value       = var.create_bigquery_dataset ? google_logging_project_sink.finops_hub_insights[0].name : null
}

# Storage outputs
output "function_source_bucket" {
  description = "Cloud Storage bucket name for function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "Cloud Storage bucket URL for function source code"
  value       = google_storage_bucket.function_source.url
}

# Monitoring outputs
output "carbon_efficiency_dashboard_url" {
  description = "URL to access the carbon efficiency monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${split("/", google_monitoring_dashboard.carbon_efficiency.id)[3]}?project=${var.project_id}"
}

output "carbon_efficiency_metric_types" {
  description = "Custom metric types created for carbon efficiency monitoring"
  value = [
    google_monitoring_metric_descriptor.carbon_efficiency_score.type,
    google_monitoring_metric_descriptor.optimization_impact.type
  ]
}

output "carbon_efficiency_alert_policy_name" {
  description = "Name of the carbon efficiency alert policy"
  value       = google_monitoring_alert_policy.carbon_efficiency_alert.display_name
}

# FinOps Hub and Carbon Footprint URLs
output "finops_hub_url" {
  description = "URL to access FinOps Hub 2.0 in Google Cloud Console"
  value       = "https://console.cloud.google.com/billing/finops?project=${var.project_id}"
}

output "carbon_footprint_url" {
  description = "URL to access Cloud Carbon Footprint in Google Cloud Console"
  value       = "https://console.cloud.google.com/carbon?project=${var.project_id}"
}

output "recommender_url" {
  description = "URL to access Active Assist Recommender in Google Cloud Console"
  value       = "https://console.cloud.google.com/home/recommendations?project=${var.project_id}"
}

# Configuration outputs
output "carbon_efficiency_threshold" {
  description = "Carbon efficiency threshold configured for alerts"
  value       = var.carbon_efficiency_threshold
}

output "automation_enabled" {
  description = "Whether automated optimization actions are enabled"
  value       = var.enable_automation
}

output "detailed_monitoring_enabled" {
  description = "Whether detailed monitoring with custom metrics is enabled"
  value       = var.enable_detailed_monitoring
}

# Labels and tagging outputs
output "applied_labels" {
  description = "Labels applied to all created resources"
  value       = local.common_labels
}

# API endpoints for integration
output "api_endpoints" {
  description = "Important API endpoints for external integration"
  value = {
    workflow_execution = "https://workflowexecutions.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/workflows/${google_workflows_workflow.carbon_efficiency.name}/executions"
    pubsub_publish     = "https://pubsub.googleapis.com/v1/projects/${var.project_id}/topics/${google_pubsub_topic.carbon_optimization.name}:publish"
    function_invoke    = google_cloudfunctions_function.carbon_efficiency_correlator.https_trigger_url
  }
  sensitive = true
}

# Next steps guidance
output "next_steps" {
  description = "Next steps to complete the carbon efficiency setup"
  value = <<-EOT
    1. Access FinOps Hub 2.0: ${output.finops_hub_url.value}
    2. View Carbon Footprint: ${output.carbon_footprint_url.value}
    3. Monitor Dashboard: ${output.carbon_efficiency_dashboard_url.value}
    4. Configure notification channels if needed for alerts
    5. Wait 30 days for historical carbon footprint data to accumulate
    6. Test the system by triggering the workflow manually
    7. Review recommendations in Active Assist Recommender
  EOT
}