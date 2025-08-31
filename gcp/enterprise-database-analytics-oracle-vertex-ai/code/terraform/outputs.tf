# Output values for Oracle Database@Google Cloud Enterprise Analytics with Vertex AI
# This file defines all output values that will be displayed after deployment

# ==============================================================================
# PROJECT AND INFRASTRUCTURE OUTPUTS
# ==============================================================================

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The primary Google Cloud region for deployed resources"
  value       = var.region
}

output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# ==============================================================================
# ORACLE DATABASE@GOOGLE CLOUD OUTPUTS
# ==============================================================================

output "oracle_exadata_infrastructure_id" {
  description = "ID of the Oracle Cloud Exadata Infrastructure"
  value       = google_oracle_database_cloud_exadata_infrastructure.main.cloud_exadata_infrastructure_id
}

output "oracle_exadata_infrastructure_state" {
  description = "Current state of the Oracle Cloud Exadata Infrastructure"
  value       = google_oracle_database_cloud_exadata_infrastructure.main.properties[0].lifecycle_state
}

output "oracle_exadata_shape" {
  description = "Shape of the Oracle Exadata infrastructure"
  value       = google_oracle_database_cloud_exadata_infrastructure.main.properties[0].shape
}

output "oracle_exadata_compute_count" {
  description = "Number of compute nodes in the Exadata infrastructure"
  value       = google_oracle_database_cloud_exadata_infrastructure.main.properties[0].compute_count
}

output "oracle_exadata_storage_count" {
  description = "Number of storage servers in the Exadata infrastructure"
  value       = google_oracle_database_cloud_exadata_infrastructure.main.properties[0].storage_count
}

output "autonomous_database_id" {
  description = "ID of the Oracle Autonomous Database"
  value       = google_oracle_database_autonomous_database.analytics_db.autonomous_database_id
}

output "autonomous_database_state" {
  description = "Current state of the Oracle Autonomous Database"
  value       = google_oracle_database_autonomous_database.analytics_db.properties[0].lifecycle_state
}

output "autonomous_database_connection_strings" {
  description = "Connection strings for the Oracle Autonomous Database"
  value = {
    high   = try(google_oracle_database_autonomous_database.analytics_db.properties[0].connection_strings[0].high, "")
    low    = try(google_oracle_database_autonomous_database.analytics_db.properties[0].connection_strings[0].low, "")
    medium = try(google_oracle_database_autonomous_database.analytics_db.properties[0].connection_strings[0].medium, "")
  }
  sensitive = true
}

output "autonomous_database_ocpu_count" {
  description = "Number of OCPU cores allocated to the Autonomous Database"
  value       = google_oracle_database_autonomous_database.analytics_db.properties[0].compute_count
}

output "autonomous_database_storage_size_tbs" {
  description = "Storage size in terabytes for the Autonomous Database"
  value       = google_oracle_database_autonomous_database.analytics_db.properties[0].storage_size_tbs
}

output "autonomous_database_workload_type" {
  description = "Workload type of the Autonomous Database"
  value       = google_oracle_database_autonomous_database.analytics_db.properties[0].workload_type
}

# ==============================================================================
# VERTEX AI OUTPUTS
# ==============================================================================

output "vertex_ai_dataset_id" {
  description = "ID of the Vertex AI dataset"
  value       = google_vertex_ai_dataset.oracle_analytics_dataset.name
}

output "vertex_ai_dataset_display_name" {
  description = "Display name of the Vertex AI dataset"
  value       = google_vertex_ai_dataset.oracle_analytics_dataset.display_name
}

output "vertex_ai_region" {
  description = "Region where Vertex AI resources are deployed"
  value       = var.vertex_ai_region
}

output "vertex_ai_endpoint_id" {
  description = "ID of the Vertex AI model endpoint"
  value       = google_vertex_ai_endpoint.oracle_ml_endpoint.name
}

output "vertex_ai_endpoint_display_name" {
  description = "Display name of the Vertex AI model endpoint"
  value       = google_vertex_ai_endpoint.oracle_ml_endpoint.display_name
}

output "vertex_workbench_instance_name" {
  description = "Name of the Vertex AI Workbench instance"
  value       = google_notebooks_instance.oracle_ml_workbench.name
}

output "vertex_workbench_proxy_uri" {
  description = "Proxy URI for accessing the Vertex AI Workbench instance"
  value       = google_notebooks_instance.oracle_ml_workbench.proxy_uri
}

output "vertex_workbench_machine_type" {
  description = "Machine type of the Vertex AI Workbench instance"
  value       = google_notebooks_instance.oracle_ml_workbench.machine_type
}

# ==============================================================================
# BIGQUERY OUTPUTS
# ==============================================================================

output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset"
  value       = google_bigquery_dataset.oracle_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.oracle_analytics.location
}

output "bigquery_dataset_friendly_name" {
  description = "Friendly name of the BigQuery dataset"
  value       = google_bigquery_dataset.oracle_analytics.friendly_name
}

output "bigquery_sales_analytics_table_id" {
  description = "ID of the BigQuery sales analytics table"
  value       = google_bigquery_table.sales_analytics.table_id
}

output "bigquery_oracle_connection_id" {
  description = "ID of the BigQuery connection to Oracle database"
  value       = google_bigquery_connection.oracle_connection.connection_id
}

output "bigquery_project_dataset_table" {
  description = "Fully qualified BigQuery table reference"
  value       = "${var.project_id}.${google_bigquery_dataset.oracle_analytics.dataset_id}.${google_bigquery_table.sales_analytics.table_id}"
}

# ==============================================================================
# STORAGE OUTPUTS
# ==============================================================================

output "vertex_ai_staging_bucket_name" {
  description = "Name of the Cloud Storage bucket for Vertex AI staging"
  value       = google_storage_bucket.vertex_ai_staging.name
}

output "vertex_ai_staging_bucket_url" {
  description = "URL of the Cloud Storage bucket for Vertex AI staging"
  value       = google_storage_bucket.vertex_ai_staging.url
}

output "cloud_functions_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for Cloud Functions source code"
  value       = google_storage_bucket.cloud_functions_source.name
}

# ==============================================================================
# CLOUD FUNCTIONS AND SCHEDULER OUTPUTS
# ==============================================================================

output "cloud_function_name" {
  description = "Name of the Cloud Function for data pipeline"
  value       = google_cloudfunctions2_function.oracle_analytics_pipeline.name
}

output "cloud_function_uri" {
  description = "URI of the Cloud Function for data pipeline"
  value       = google_cloudfunctions2_function.oracle_analytics_pipeline.service_config[0].uri
}

output "cloud_function_service_account_email" {
  description = "Email of the Cloud Function service account"
  value       = google_service_account.cloud_function_service_account.email
}

output "cloud_scheduler_job_name" {
  description = "Name of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.oracle_analytics_schedule.name
}

output "cloud_scheduler_schedule" {
  description = "Cron schedule for the automated pipeline"
  value       = google_cloud_scheduler_job.oracle_analytics_schedule.schedule
}

output "cloud_scheduler_timezone" {
  description = "Timezone for the Cloud Scheduler"
  value       = google_cloud_scheduler_job.oracle_analytics_schedule.time_zone
}

# ==============================================================================
# SERVICE ACCOUNT OUTPUTS
# ==============================================================================

output "vertex_ai_service_account_email" {
  description = "Email of the Vertex AI service account"
  value       = google_service_account.vertex_ai_service_account.email
}

output "analytics_service_account_email" {
  description = "Email of the analytics service account"
  value       = google_service_account.analytics_service_account.email
}

output "service_accounts" {
  description = "Map of all service accounts created"
  value = {
    vertex_ai         = google_service_account.vertex_ai_service_account.email
    analytics         = google_service_account.analytics_service_account.email
    cloud_function    = google_service_account.cloud_function_service_account.email
  }
}

# ==============================================================================
# MONITORING OUTPUTS
# ==============================================================================

output "monitoring_alert_policies" {
  description = "List of monitoring alert policy names"
  value = var.enable_monitoring_alerts ? [
    try(google_monitoring_alert_policy.oracle_cpu_alert[0].name, ""),
    try(google_monitoring_alert_policy.vertex_ai_latency_alert[0].name, "")
  ] : []
}

output "oracle_cpu_alert_threshold" {
  description = "CPU utilization threshold for Oracle database alerts"
  value       = var.oracle_cpu_alert_threshold
}

output "vertex_ai_latency_alert_threshold_ms" {
  description = "Response time threshold for Vertex AI model alerts"
  value       = var.vertex_ai_latency_alert_threshold_ms
}

# ==============================================================================
# NETWORK AND SECURITY OUTPUTS
# ==============================================================================

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value       = local.required_apis
}

output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# ==============================================================================
# COST AND RESOURCE MANAGEMENT OUTPUTS
# ==============================================================================

output "cost_optimization_enabled" {
  description = "Whether cost optimization features are enabled"
  value       = var.enable_cost_optimization
}

output "auto_scaling_enabled" {
  description = "Whether auto-scaling is enabled for applicable resources"
  value       = var.enable_auto_scaling
}

output "backup_retention_days" {
  description = "Number of days for backup retention"
  value       = var.backup_retention_days
}

# ==============================================================================
# CONNECTION AND ACCESS INFORMATION
# ==============================================================================

output "getting_started_commands" {
  description = "Commands to get started with the deployed infrastructure"
  value = {
    "Access Vertex AI Workbench" = "gcloud notebooks instances describe ${google_notebooks_instance.oracle_ml_workbench.name} --location=${var.zone}"
    "Query BigQuery dataset"     = "bq query --use_legacy_sql=false 'SELECT COUNT(*) FROM `${var.project_id}.${google_bigquery_dataset.oracle_analytics.dataset_id}.${google_bigquery_table.sales_analytics.table_id}`'"
    "Trigger pipeline manually"  = "gcloud functions call ${google_cloudfunctions2_function.oracle_analytics_pipeline.name} --region=${var.region}"
    "View Oracle database info"  = "gcloud oracle-database autonomous-databases describe ${google_oracle_database_autonomous_database.analytics_db.autonomous_database_id} --location=${var.region}"
  }
}

output "dashboard_links" {
  description = "Links to Google Cloud console dashboards"
  value = {
    "Oracle Database@Google Cloud" = "https://console.cloud.google.com/oracledatabase/autonomous-databases?project=${var.project_id}"
    "Vertex AI"                    = "https://console.cloud.google.com/vertex-ai?project=${var.project_id}"
    "BigQuery"                     = "https://console.cloud.google.com/bigquery?project=${var.project_id}"
    "Cloud Functions"              = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
    "Cloud Monitoring"             = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    "Cloud Scheduler"              = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
  }
}

# ==============================================================================
# IMPORTANT NOTES AND NEXT STEPS
# ==============================================================================

output "important_notes" {
  description = "Important notes about the deployed infrastructure"
  value = {
    "Oracle Database Provisioning" = "Oracle Database@Google Cloud infrastructure provisioning may take 15-30 minutes to complete"
    "Connection Configuration"     = "BigQuery connection to Oracle database requires manual configuration with actual connection details"
    "Security Considerations"      = "Review IAM permissions and network access controls for production environments"
    "Cost Management"             = "Monitor resource usage and consider enabling cost optimization features for non-production environments"
    "ML Model Deployment"         = "Deploy ML models to the Vertex AI endpoint using Vertex AI SDK or console"
  }
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Wait for Oracle infrastructure to be fully provisioned",
    "Configure Oracle database connection details in BigQuery connection",
    "Upload sample data to Oracle database for testing",
    "Deploy ML models to the Vertex AI endpoint",
    "Test the data pipeline by triggering the Cloud Function",
    "Set up monitoring notification channels for alerts",
    "Configure network security rules for production access",
    "Review and optimize cost settings based on usage patterns"
  ]
}