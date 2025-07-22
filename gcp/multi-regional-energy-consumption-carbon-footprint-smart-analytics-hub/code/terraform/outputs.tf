# Outputs for multi-regional energy consumption carbon footprint analytics solution

# Project and Resource Identifiers
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "primary_region" {
  description = "Primary region where resources are deployed"
  value       = var.primary_region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# BigQuery Resources
output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for carbon analytics"
  value       = google_bigquery_dataset.carbon_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.carbon_analytics.location
}

output "carbon_footprint_table" {
  description = "Full table ID for carbon footprint data"
  value       = "${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.${google_bigquery_table.carbon_footprint.table_id}"
}

output "workload_schedules_table" {
  description = "Full table ID for workload scheduling data"
  value       = "${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.${google_bigquery_table.workload_schedules.table_id}"
}

output "migration_log_table" {
  description = "Full table ID for migration log data (if migration is enabled)"
  value       = var.enable_workload_migration ? "${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.${google_bigquery_table.migration_log[0].table_id}" : null
}

output "regional_carbon_summary_view" {
  description = "Full view ID for regional carbon summary analytics"
  value       = "${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.${google_bigquery_table.regional_carbon_summary.table_id}"
}

output "optimization_impact_view" {
  description = "Full view ID for optimization impact analytics"
  value       = "${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.${google_bigquery_table.optimization_impact.table_id}"
}

output "regional_efficiency_scores_table" {
  description = "Full table ID for regional efficiency scores"
  value       = "${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.${google_bigquery_table.regional_efficiency_scores.table_id}"
}

# Analytics Hub Resources
output "analytics_hub_exchange_id" {
  description = "Analytics Hub data exchange ID"
  value       = google_bigquery_analytics_hub_data_exchange.energy_optimization.data_exchange_id
}

output "analytics_hub_listing_id" {
  description = "Analytics Hub listing ID for carbon footprint data"
  value       = google_bigquery_analytics_hub_listing.carbon_footprint.listing_id
}

output "analytics_hub_exchange_name" {
  description = "Full name of the Analytics Hub data exchange"
  value       = google_bigquery_analytics_hub_data_exchange.energy_optimization.name
}

# Cloud Functions
output "carbon_collector_function_name" {
  description = "Name of the carbon data collection function"
  value       = google_cloudfunctions_function.carbon_collector.name
}

output "carbon_collector_function_url" {
  description = "HTTPS trigger URL for the carbon data collection function"
  value       = google_cloudfunctions_function.carbon_collector.https_trigger_url
}

output "workload_migration_function_name" {
  description = "Name of the workload migration function (if migration is enabled)"
  value       = var.enable_workload_migration ? google_cloudfunctions_function.workload_migration[0].name : null
}

output "function_service_account_email" {
  description = "Email of the service account used by Cloud Functions"
  value       = google_service_account.carbon_optimizer.email
}

# Cloud Scheduler
output "carbon_optimization_job_name" {
  description = "Name of the carbon optimization scheduler job"
  value       = google_cloud_scheduler_job.carbon_optimization.name
}

output "renewable_optimization_job_name" {
  description = "Name of the renewable energy optimization scheduler job"
  value       = google_cloud_scheduler_job.renewable_optimization.name
}

output "optimization_schedule" {
  description = "Cron schedule for carbon optimization"
  value       = var.carbon_optimization_schedule
}

output "renewable_schedule" {
  description = "Cron schedule for renewable energy optimization"
  value       = var.renewable_optimization_schedule
}

# Pub/Sub Resources
output "migration_topic_name" {
  description = "Name of the Pub/Sub topic for migration triggers (if migration is enabled)"
  value       = var.enable_workload_migration ? google_pubsub_topic.carbon_optimization_trigger[0].name : null
}

# Storage Resources
output "function_source_bucket" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = local.function_bucket.name
}

# Monitoring Resources
output "carbon_savings_metric_type" {
  description = "Custom metric type for carbon savings monitoring"
  value       = var.enable_monitoring ? google_monitoring_metric_descriptor.carbon_savings[0].type : null
}

output "high_carbon_alert_policy_name" {
  description = "Name of the high carbon intensity alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.high_carbon_intensity[0].name : null
}

output "notification_channel_id" {
  description = "ID of the email notification channel (if configured)"
  value       = var.enable_monitoring && var.notification_email != "" ? google_monitoring_notification_channel.email[0].id : null
}

# Configuration Values
output "carbon_intensity_threshold" {
  description = "Configured carbon intensity threshold for alerts"
  value       = var.carbon_intensity_threshold
}

output "analytics_regions" {
  description = "Regions configured for multi-regional analytics"
  value       = var.analytics_regions
}

output "environment" {
  description = "Environment name for this deployment"
  value       = var.environment
}

# Backup Resources
output "backup_dataset_id" {
  description = "BigQuery backup dataset ID (if cross-region replication is enabled)"
  value       = var.enable_cross_region_replication ? google_bigquery_dataset.carbon_analytics_backup[0].dataset_id : null
}

# Sample Queries for Analytics
output "sample_carbon_query" {
  description = "Sample BigQuery query to analyze regional carbon intensity"
  value = <<-EOT
    SELECT 
      region,
      DATE(timestamp) as date,
      AVG(carbon_intensity) as avg_carbon_intensity,
      SUM(carbon_emissions_kg) as total_emissions_kg
    FROM `${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.carbon_footprint`
    WHERE DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
    GROUP BY region, DATE(timestamp)
    ORDER BY date DESC, avg_carbon_intensity ASC
  EOT
}

output "sample_optimization_query" {
  description = "Sample BigQuery query to analyze optimization impact"
  value = <<-EOT
    SELECT 
      target_region,
      COUNT(*) as workloads_moved,
      SUM(carbon_savings_kg) as total_savings_kg,
      AVG(carbon_savings_kg) as avg_savings_per_workload
    FROM `${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.workload_schedules`
    WHERE DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
    GROUP BY target_region
    ORDER BY total_savings_kg DESC
  EOT
}

# Deployment Verification Commands
output "verify_deployment_commands" {
  description = "Commands to verify the deployment is working correctly"
  value = {
    test_function = "curl -X GET '${google_cloudfunctions_function.carbon_collector.https_trigger_url}'"
    check_bigquery_data = "bq query --use_legacy_sql=false 'SELECT COUNT(*) as records FROM `${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.carbon_footprint`'"
    list_scheduler_jobs = "gcloud scheduler jobs list --location=${var.primary_region}"
    check_analytics_hub = "bq ls --data_exchange --location=${var.dataset_location}"
  }
}

# Important URLs and Endpoints
output "important_urls" {
  description = "Important URLs for monitoring and managing the solution"
  value = {
    bigquery_console = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.carbon_analytics.dataset_id}!3sschema"
    cloud_functions_console = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
    scheduler_console = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
    analytics_hub_console = "https://console.cloud.google.com/bigquery/analytics-hub?project=${var.project_id}"
    monitoring_console = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
  }
}

# Cost Optimization Tips
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the deployed solution"
  value = [
    "Set appropriate table expiration times for BigQuery tables to manage storage costs",
    "Monitor Cloud Functions invocation patterns and adjust memory allocation if needed",
    "Use BigQuery slot reservations for predictable query workloads",
    "Consider using Cloud Storage lifecycle policies for function source code retention",
    "Review and optimize Cloud Scheduler job frequency based on business requirements",
    "Use BigQuery's partition and clustering features for large datasets to reduce query costs"
  ]
}

# Security Recommendations
output "security_recommendations" {
  description = "Security best practices for the deployed solution"
  value = [
    "Regularly review and rotate service account keys",
    "Enable VPC Service Controls for additional BigQuery security",
    "Use IAM conditions for fine-grained access control",
    "Enable audit logging for all services",
    "Consider using customer-managed encryption keys (CMEK) for sensitive data",
    "Implement network security policies for Cloud Functions",
    "Use Analytics Hub's data access controls for secure data sharing"
  ]
}