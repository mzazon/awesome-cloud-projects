# ==============================================================================
# PROJECT AND ENVIRONMENT INFORMATION OUTPUTS
# ==============================================================================

output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for globally unique resource names"
  value       = random_id.suffix.hex
}

# ==============================================================================
# BIGQUERY OUTPUTS
# ==============================================================================

output "bigquery_dataset_id" {
  description = "The ID of the BigQuery dataset for carbon intelligence data"
  value       = google_bigquery_dataset.carbon_intelligence.dataset_id
}

output "bigquery_dataset_location" {
  description = "The location of the BigQuery dataset"
  value       = google_bigquery_dataset.carbon_intelligence.location
}

output "bigquery_dataset_url" {
  description = "URL to access the BigQuery dataset in the Google Cloud Console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.carbon_intelligence.dataset_id}"
}

output "bigquery_dataset_full_id" {
  description = "The full ID of the BigQuery dataset including project"
  value       = "${var.project_id}:${google_bigquery_dataset.carbon_intelligence.dataset_id}"
}

# ==============================================================================
# ANALYTICS HUB OUTPUTS
# ==============================================================================

output "analytics_hub_data_exchange_id" {
  description = "The ID of the Analytics Hub data exchange"
  value       = var.enable_data_sharing ? google_bigquery_analytics_hub_data_exchange.sustainability_exchange[0].data_exchange_id : null
}

output "analytics_hub_data_exchange_url" {
  description = "URL to access the Analytics Hub data exchange"
  value       = var.enable_data_sharing ? "https://console.cloud.google.com/bigquery/analytics-hub/exchanges/${var.region}/${google_bigquery_analytics_hub_data_exchange.sustainability_exchange[0].data_exchange_id}?project=${var.project_id}" : null
}

output "analytics_hub_listing_id" {
  description = "The ID of the monthly emissions Analytics Hub listing"
  value       = var.enable_data_sharing ? google_bigquery_analytics_hub_listing.monthly_emissions_listing[0].listing_id : null
}

output "analytics_hub_sharing_instructions" {
  description = "Instructions for sharing Analytics Hub data with other projects"
  value = var.enable_data_sharing ? "To share data: 1) Go to the Analytics Hub URL above, 2) Select the listing, 3) Click 'Share' and add subscriber projects or users" : "Data sharing is disabled"
}

# ==============================================================================
# CLOUD STORAGE OUTPUTS
# ==============================================================================

output "reports_bucket_name" {
  description = "Name of the Cloud Storage bucket for sustainability reports"
  value       = google_storage_bucket.reports_bucket.name
}

output "reports_bucket_url" {
  description = "URL to access the reports bucket in Google Cloud Console"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.reports_bucket.name}?project=${var.project_id}"
}

output "reports_bucket_gs_url" {
  description = "gs:// URL for the reports bucket"
  value       = "gs://${google_storage_bucket.reports_bucket.name}"
}

output "reports_bucket_location" {
  description = "Location of the reports bucket"
  value       = google_storage_bucket.reports_bucket.location
}

# ==============================================================================
# PUB/SUB OUTPUTS
# ==============================================================================

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for carbon alerts"
  value       = google_pubsub_topic.carbon_alerts.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.carbon_alerts.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for carbon alerts"
  value       = google_pubsub_subscription.carbon_alerts_subscription.name
}

output "pubsub_dead_letter_topic" {
  description = "Name of the dead letter topic for failed messages"
  value       = google_pubsub_topic.carbon_alerts_dead_letter.name
}

# ==============================================================================
# CLOUD FUNCTIONS OUTPUTS
# ==============================================================================

output "data_processor_function_name" {
  description = "Name of the data processing Cloud Function"
  value       = google_cloudfunctions2_function.data_processor.name
}

output "data_processor_function_url" {
  description = "URL to access the data processing function in Google Cloud Console"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.data_processor.name}?project=${var.project_id}"
}

output "data_processor_function_uri" {
  description = "HTTP URI of the data processing function (if HTTP trigger is enabled)"
  value       = try(google_cloudfunctions2_function.data_processor.service_config[0].uri, "N/A - Function uses Pub/Sub trigger")
}

output "recommendations_function_name" {
  description = "Name of the recommendations engine Cloud Function"
  value       = google_cloudfunctions2_function.recommendations_engine.name
}

output "recommendations_function_url" {
  description = "URL to access the recommendations function in Google Cloud Console"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.recommendations_engine.name}?project=${var.project_id}"
}

output "recommendations_function_uri" {
  description = "HTTP URI of the recommendations engine function"
  value       = google_cloudfunctions2_function.recommendations_engine.service_config[0].uri
}

# ==============================================================================
# SERVICE ACCOUNTS OUTPUTS
# ==============================================================================

output "data_processor_service_account" {
  description = "Email of the service account used by the data processor function"
  value       = var.create_service_accounts ? google_service_account.data_processor_sa[0].email : "Default Compute Service Account"
}

output "recommendations_service_account" {
  description = "Email of the service account used by the recommendations engine function"
  value       = var.create_service_accounts ? google_service_account.recommendations_sa[0].email : "Default Compute Service Account"
}

output "looker_studio_service_account" {
  description = "Email of the service account for Looker Studio access"
  value       = google_service_account.looker_studio_sa.email
}

output "looker_studio_setup_instructions" {
  description = "Instructions for connecting Looker Studio to BigQuery"
  value       = "To connect Looker Studio: 1) Go to lookerstudio.google.com, 2) Create new data source, 3) Select BigQuery, 4) Use service account: ${google_service_account.looker_studio_sa.email}, 5) Connect to dataset: ${google_bigquery_dataset.carbon_intelligence.dataset_id}"
}

# ==============================================================================
# CLOUD SCHEDULER OUTPUTS
# ==============================================================================

output "recommendations_schedule_job_name" {
  description = "Name of the Cloud Scheduler job for weekly recommendations"
  value       = google_cloud_scheduler_job.recommendations_weekly.name
}

output "data_processing_schedule_job_name" {
  description = "Name of the Cloud Scheduler job for monthly data processing"
  value       = google_cloud_scheduler_job.data_processing_monthly.name
}

output "scheduler_timezone" {
  description = "Timezone configured for Cloud Scheduler jobs"
  value       = var.scheduler_timezone
}

output "recommendations_schedule" {
  description = "Cron schedule for recommendations generation"
  value       = var.recommendations_schedule
}

output "data_processing_schedule" {
  description = "Cron schedule for data processing"
  value       = var.data_processing_schedule
}

# ==============================================================================
# MONITORING AND CONFIGURATION OUTPUTS
# ==============================================================================

output "carbon_increase_threshold" {
  description = "Configured threshold for carbon emission increase alerts (percentage)"
  value       = var.carbon_increase_threshold
}

output "monitoring_window_months" {
  description = "Number of months configured for carbon emission trend analysis"
  value       = var.monitoring_window_months
}

output "data_retention_days" {
  description = "Number of days configured for data retention in BigQuery"
  value       = var.data_retention_days
}

# ==============================================================================
# CARBON FOOTPRINT DATA TRANSFER OUTPUTS
# ==============================================================================

output "carbon_footprint_transfer_config" {
  description = "Information about the Carbon Footprint data transfer configuration"
  value = var.billing_account_id != "" ? {
    display_name    = google_bigquery_data_transfer_config.carbon_footprint_transfer[0].display_name
    schedule        = google_bigquery_data_transfer_config.carbon_footprint_transfer[0].schedule
    billing_account = var.billing_account_id
    status          = "Configured - Data will be available monthly after the 15th"
  } : {
    status = "Not configured - billing_account_id variable is empty"
    instructions = "Set billing_account_id variable and re-apply to enable automated carbon footprint data collection"
  }
}

# ==============================================================================
# COST AND USAGE ESTIMATES
# ==============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the sustainability intelligence solution"
  value = {
    bigquery_storage    = "~$5-15 (depends on data volume)"
    bigquery_queries    = "~$10-25 (depends on query frequency)"
    cloud_functions     = "~$5-10 (depends on execution frequency)"
    cloud_storage       = "~$2-5 (depends on report volume)"
    pubsub             = "~$1-3 (depends on message volume)"
    cloud_scheduler    = "~$1 (fixed cost for 2 jobs)"
    total_estimate     = "~$24-59 per month"
    cost_optimization  = "Costs scale with usage - actual costs may be lower for development environments"
  }
}

# ==============================================================================
# NEXT STEPS AND OPERATIONAL GUIDANCE
# ==============================================================================

output "next_steps" {
  description = "Next steps to complete the sustainability intelligence setup"
  value = [
    "1. Enable Carbon Footprint API: https://console.cloud.google.com/marketplace/product/google/carbonfootprint.googleapis.com",
    "2. Configure billing account in carbon footprint transfer (if not already set)",
    "3. Create Looker Studio dashboard using the service account provided",
    "4. Wait for first carbon footprint data export (processed monthly on the 15th)",
    "5. Test the system by triggering the recommendations function manually",
    "6. Set up additional monitoring and alerting as needed",
    "7. Review and customize the carbon increase threshold and monitoring parameters"
  ]
}

output "monitoring_links" {
  description = "Useful links for monitoring and managing the solution"
  value = {
    cloud_functions_logs    = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_function%22?project=${var.project_id}"
    bigquery_console       = "https://console.cloud.google.com/bigquery?project=${var.project_id}"
    cloud_scheduler_console = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
    carbon_footprint_console = "https://console.cloud.google.com/carbon?project=${var.project_id}"
    pub_sub_console        = "https://console.cloud.google.com/cloudpubsub?project=${var.project_id}"
    storage_console        = "https://console.cloud.google.com/storage?project=${var.project_id}"
  }
}

output "sustainability_reporting_guidance" {
  description = "Guidance for using the system for sustainability reporting"
  value = {
    gri_standards_support   = "Data structure supports GRI 305 (Emissions) reporting requirements"
    tcfd_alignment         = "Monthly trend analysis supports TCFD risk assessment frameworks"
    scope_2_reporting      = "Both location-based and market-based emissions available for Scope 2 reporting"
    data_export_formats    = "Data can be exported from BigQuery in CSV, JSON, or Parquet formats"
    audit_trail           = "Complete audit trail maintained through BigQuery and Cloud Storage versioning"
    recommendation_cadence = "Weekly recommendations with monthly comprehensive analysis"
  }
}

# ==============================================================================
# TROUBLESHOOTING OUTPUTS
# ==============================================================================

output "troubleshooting_guides" {
  description = "Common troubleshooting steps and solutions"
  value = {
    no_carbon_data = "If no carbon footprint data appears: 1) Verify Carbon Footprint API is enabled, 2) Check billing account permissions, 3) Wait until after the 15th of the month for data processing"
    function_errors = "Check Cloud Functions logs in Cloud Logging. Common issues: service account permissions, BigQuery dataset access"
    scheduler_failures = "Verify Cloud Scheduler service account has necessary permissions to invoke functions"
    analytics_hub_access = "Ensure Analytics Hub API is enabled and users have appropriate IAM roles for data sharing"
    high_costs = "Monitor BigQuery query patterns and consider adjusting data retention or query optimization"
  }
}

output "security_considerations" {
  description = "Security best practices and considerations for the solution"
  value = {
    service_account_principle = "All functions use dedicated service accounts with least privilege access"
    data_encryption = "All data encrypted at rest and in transit using Google-managed keys"
    network_security = "Functions configured with VPC connector for private network access"
    access_logging = "BigQuery access and Cloud Function invocations logged in Cloud Audit Logs"
    data_sharing_controls = "Analytics Hub provides controlled data sharing with audit trails"
    recommendations = [
      "Regularly review service account permissions",
      "Monitor access patterns through Cloud Audit Logs",
      "Consider implementing VPC Service Controls for additional network security",
      "Review and update data retention policies based on compliance requirements"
    ]
  }
}