# Output values for GCP Intelligent Resource Optimization infrastructure
# These outputs provide essential information about deployed resources for verification and integration

# ================================
# PROJECT AND BASIC INFORMATION
# ================================

output "project_id" {
  description = "The GCP project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "zone" {
  description = "The GCP zone where resources were deployed"
  value       = var.zone
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# ================================
# BIGQUERY OUTPUTS
# ================================

output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for asset optimization analytics"
  value       = google_bigquery_dataset.asset_optimization.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.asset_optimization.location
}

output "bigquery_dataset_full_id" {
  description = "Full BigQuery dataset ID including project"
  value       = "${var.project_id}:${google_bigquery_dataset.asset_optimization.dataset_id}"
}

output "resource_optimization_view" {
  description = "Full path to the resource optimization analysis view"
  value       = "${var.project_id}.${google_bigquery_dataset.asset_optimization.dataset_id}.${google_bigquery_table.resource_optimization_analysis.table_id}"
}

output "cost_impact_summary_view" {
  description = "Full path to the cost impact summary view"
  value       = "${var.project_id}.${google_bigquery_dataset.asset_optimization.dataset_id}.${google_bigquery_table.cost_impact_summary.table_id}"
}

output "optimization_metrics_table" {
  description = "Full path to the optimization metrics table"
  value       = "${var.project_id}.${google_bigquery_dataset.asset_optimization.dataset_id}.${google_bigquery_table.optimization_metrics.table_id}"
}

# ================================
# CLOUD STORAGE OUTPUTS
# ================================

output "staging_bucket_name" {
  description = "Name of the Cloud Storage bucket for Vertex AI staging"
  value       = google_storage_bucket.agent_staging.name
}

output "staging_bucket_url" {
  description = "URL of the Cloud Storage bucket for Vertex AI staging"
  value       = google_storage_bucket.agent_staging.url
}

output "staging_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.agent_staging.self_link
}

# ================================
# SERVICE ACCOUNT OUTPUTS
# ================================

output "asset_export_service_account_email" {
  description = "Email address of the asset export scheduler service account"
  value       = google_service_account.asset_export_scheduler.email
}

output "asset_export_service_account_id" {
  description = "ID of the asset export scheduler service account"
  value       = google_service_account.asset_export_scheduler.id
}

output "vertex_ai_service_account_email" {
  description = "Email address of the Vertex AI agent service account"
  value       = google_service_account.vertex_ai_agent.email
}

output "vertex_ai_service_account_id" {
  description = "ID of the Vertex AI agent service account"
  value       = google_service_account.vertex_ai_agent.id
}

# ================================
# CLOUD FUNCTIONS OUTPUTS
# ================================

output "asset_export_function_name" {
  description = "Name of the Cloud Function for triggering asset exports"
  value       = google_cloudfunctions_function.asset_export_trigger.name
}

output "asset_export_function_url" {
  description = "HTTPS trigger URL for the asset export function"
  value       = google_cloudfunctions_function.asset_export_trigger.https_trigger_url
  sensitive   = true
}

output "asset_export_function_source_archive" {
  description = "Cloud Storage path to the function source archive"
  value       = "gs://${google_storage_bucket.agent_staging.name}/${google_storage_bucket_object.function_source.name}"
}

# ================================
# CLOUD SCHEDULER OUTPUTS
# ================================

output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for automated asset exports"
  value       = google_cloud_scheduler_job.asset_export.name
}

output "scheduler_job_id" {
  description = "ID of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.asset_export.id
}

output "scheduler_job_schedule" {
  description = "Cron schedule for the asset export job"
  value       = google_cloud_scheduler_job.asset_export.schedule
}

output "scheduler_job_timezone" {
  description = "Timezone for the scheduler job"
  value       = google_cloud_scheduler_job.asset_export.time_zone
}

# ================================
# MONITORING OUTPUTS
# ================================

output "alert_policy_name" {
  description = "Name of the monitoring alert policy for high optimization scores"
  value       = google_monitoring_alert_policy.high_optimization_score.name
}

output "alert_policy_id" {
  description = "ID of the monitoring alert policy"
  value       = google_monitoring_alert_policy.high_optimization_score.id
}

# ================================
# VERTEX AI CONFIGURATION OUTPUTS
# ================================

output "vertex_ai_staging_bucket" {
  description = "Cloud Storage bucket URI for Vertex AI staging"
  value       = "gs://${google_storage_bucket.agent_staging.name}"
}

output "vertex_ai_model" {
  description = "Vertex AI model configured for the agent"
  value       = var.vertex_ai_model
}

output "agent_requirements_path" {
  description = "Cloud Storage path to agent requirements file"
  value       = "gs://${google_storage_bucket.agent_staging.name}/${google_storage_bucket_object.agent_requirements.name}"
}

output "agent_implementation_path" {
  description = "Cloud Storage path to agent implementation file"
  value       = "gs://${google_storage_bucket.agent_staging.name}/${google_storage_bucket_object.agent_implementation.name}"
}

# ================================
# CONFIGURATION OUTPUTS
# ================================

output "asset_types" {
  description = "List of asset types configured for inventory export"
  value       = var.asset_types
}

output "organization_id" {
  description = "GCP organization ID used for asset inventory"
  value       = var.organization_id
  sensitive   = true
}

output "environment" {
  description = "Environment name for this deployment"
  value       = var.environment
}

# ================================
# QUICK ACCESS COMMANDS
# ================================

output "bigquery_query_command" {
  description = "BigQuery CLI command to query optimization analysis"
  value = join(" ", [
    "bq query --use_legacy_sql=false",
    "\"SELECT optimization_category, COUNT(*) as count, AVG(optimization_score) as avg_score",
    "FROM \\`${var.project_id}.${google_bigquery_dataset.asset_optimization.dataset_id}.${google_bigquery_table.resource_optimization_analysis.table_id}\\`",
    "GROUP BY optimization_category\""
  ])
}

output "scheduler_status_command" {
  description = "gcloud command to check scheduler job status"
  value = "gcloud scheduler jobs describe ${google_cloud_scheduler_job.asset_export.name} --location=${var.region}"
}

output "function_logs_command" {
  description = "gcloud command to view function logs"
  value = "gcloud functions logs read ${google_cloudfunctions_function.asset_export_trigger.name} --region=${var.region}"
}

# ================================
# DEPLOYMENT VERIFICATION
# ================================

output "deployment_summary" {
  description = "Summary of deployed resources for verification"
  value = {
    bigquery_dataset     = google_bigquery_dataset.asset_optimization.dataset_id
    storage_bucket      = google_storage_bucket.agent_staging.name
    cloud_function      = google_cloudfunctions_function.asset_export_trigger.name
    scheduler_job       = google_cloud_scheduler_job.asset_export.name
    service_accounts    = [
      google_service_account.asset_export_scheduler.email,
      google_service_account.vertex_ai_agent.email
    ]
    monitoring_policy   = google_monitoring_alert_policy.high_optimization_score.display_name
  }
}

# ================================
# POST-DEPLOYMENT INSTRUCTIONS
# ================================

output "next_steps" {
  description = "Next steps to complete the setup"
  value = [
    "1. Verify BigQuery dataset creation: bq ls -d ${var.project_id}:${google_bigquery_dataset.asset_optimization.dataset_id}",
    "2. Check scheduler job status: gcloud scheduler jobs describe ${google_cloud_scheduler_job.asset_export.name} --location=${var.region}",
    "3. Monitor asset export function: gcloud functions logs read ${google_cloudfunctions_function.asset_export_trigger.name} --region=${var.region}",
    "4. Deploy Vertex AI Agent using the Python SDK with staging bucket: gs://${google_storage_bucket.agent_staging.name}",
    "5. Query optimization data: bq query --use_legacy_sql=false 'SELECT COUNT(*) FROM `${var.project_id}.${google_bigquery_dataset.asset_optimization.dataset_id}.asset_inventory`'",
    "6. Review monitoring alerts in the Cloud Console under Monitoring > Alerting"
  ]
}