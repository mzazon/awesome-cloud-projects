# Output values for GCP Infrastructure Cost Optimization solution
#
# These outputs provide essential information about deployed resources including
# endpoints, resource identifiers, and configuration details needed for monitoring,
# integration, and operational management of the cost optimization infrastructure.

# ==============================================================================
# PROJECT AND IDENTITY OUTPUTS
# ==============================================================================

output "project_id" {
  description = "Google Cloud project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region used for resource deployment"
  value       = var.region
}

output "deployment_id" {
  description = "Unique deployment identifier for resource tracking"
  value       = local.resource_suffix
}

output "service_account_email" {
  description = "Email address of the cost optimization service account"
  value       = google_service_account.cost_optimizer.email
  sensitive   = false
}

output "service_account_unique_id" {
  description = "Unique ID of the cost optimization service account"
  value       = google_service_account.cost_optimizer.unique_id
}

# ==============================================================================
# STORAGE AND DATA ANALYTICS OUTPUTS
# ==============================================================================

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for cost optimization data"
  value       = google_storage_bucket.cost_optimization_data.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket for cost optimization data"
  value       = google_storage_bucket.cost_optimization_data.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.cost_optimization_data.self_link
}

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for cost analytics"
  value       = google_bigquery_dataset.cost_analytics.dataset_id
}

output "bigquery_dataset_self_link" {
  description = "Self-link of the BigQuery dataset"
  value       = google_bigquery_dataset.cost_analytics.self_link
}

output "bigquery_resource_utilization_table" {
  description = "Full table reference for resource utilization metrics"
  value       = "${var.project_id}.${google_bigquery_dataset.cost_analytics.dataset_id}.${google_bigquery_table.resource_utilization.table_id}"
}

output "bigquery_optimization_actions_table" {
  description = "Full table reference for optimization actions tracking"
  value       = "${var.project_id}.${google_bigquery_dataset.cost_analytics.dataset_id}.${google_bigquery_table.optimization_actions.table_id}"
}

output "bigquery_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.cost_analytics.location
}

# ==============================================================================
# MESSAGING AND EVENT PROCESSING OUTPUTS
# ==============================================================================

output "pubsub_cost_events_topic" {
  description = "Pub/Sub topic name for cost optimization events"
  value       = google_pubsub_topic.cost_optimization_events.name
}

output "pubsub_cost_events_subscription" {
  description = "Pub/Sub subscription name for processing cost optimization events"
  value       = google_pubsub_subscription.cost_optimization_processor.name
}

output "pubsub_batch_notifications_topic" {
  description = "Pub/Sub topic name for batch job notifications"
  value       = google_pubsub_topic.batch_job_notifications.name
}

output "pubsub_batch_notifications_subscription" {
  description = "Pub/Sub subscription name for batch job completion handling"
  value       = google_pubsub_subscription.batch_completion_handler.name
}

output "pubsub_dead_letter_topic" {
  description = "Pub/Sub dead letter queue topic name (if enabled)"
  value       = var.enable_pubsub_dead_letter ? google_pubsub_topic.dead_letter_queue[0].name : null
}

# ==============================================================================
# CLOUD FUNCTIONS OUTPUTS
# ==============================================================================

output "cost_optimizer_function_name" {
  description = "Name of the cost optimization Cloud Function"
  value       = google_cloudfunctions2_function.cost_optimizer.name
}

output "cost_optimizer_function_uri" {
  description = "URI of the cost optimization Cloud Function for HTTP triggers"
  value       = google_cloudfunctions2_function.cost_optimizer.service_config[0].uri
}

output "cost_optimizer_function_location" {
  description = "Location of the cost optimization Cloud Function"
  value       = google_cloudfunctions2_function.cost_optimizer.location
}

output "cost_optimizer_function_service_config" {
  description = "Service configuration details of the cost optimization function"
  value = {
    available_memory      = google_cloudfunctions2_function.cost_optimizer.service_config[0].available_memory
    timeout_seconds       = google_cloudfunctions2_function.cost_optimizer.service_config[0].timeout_seconds
    max_instance_count    = google_cloudfunctions2_function.cost_optimizer.service_config[0].max_instance_count
    min_instance_count    = google_cloudfunctions2_function.cost_optimizer.service_config[0].min_instance_count
    service_account_email = google_cloudfunctions2_function.cost_optimizer.service_config[0].service_account_email
  }
}

# ==============================================================================
# CLOUD BATCH OUTPUTS
# ==============================================================================

output "batch_job_template_name" {
  description = "Name of the Cloud Batch job template for infrastructure analysis"
  value       = google_batch_job.infrastructure_analysis_template.name
}

output "batch_job_template_location" {
  description = "Location of the Cloud Batch job template"
  value       = google_batch_job.infrastructure_analysis_template.location
}

output "batch_job_template_uid" {
  description = "Unique identifier of the Cloud Batch job template"
  value       = google_batch_job.infrastructure_analysis_template.uid
}

output "batch_job_configuration" {
  description = "Configuration summary of the Cloud Batch job template"
  value = {
    machine_type           = var.batch_machine_type
    parallelism           = var.batch_parallelism
    timeout_seconds       = var.batch_job_timeout
    preemptible_instances = var.enable_preemptible_instances
    max_retry_count       = 3
  }
}

# ==============================================================================
# CLOUD SCHEDULER OUTPUTS
# ==============================================================================

output "daily_optimization_scheduler" {
  description = "Details of the daily cost optimization scheduler job"
  value = var.enable_scheduler_jobs ? {
    name     = google_cloud_scheduler_job.daily_optimization[0].name
    schedule = google_cloud_scheduler_job.daily_optimization[0].schedule
    region   = google_cloud_scheduler_job.daily_optimization[0].region
    time_zone = google_cloud_scheduler_job.daily_optimization[0].time_zone
  } : null
}

output "weekly_batch_scheduler" {
  description = "Details of the weekly batch analysis scheduler job"
  value = var.enable_scheduler_jobs ? {
    name     = google_cloud_scheduler_job.weekly_batch_analysis[0].name
    schedule = google_cloud_scheduler_job.weekly_batch_analysis[0].schedule
    region   = google_cloud_scheduler_job.weekly_batch_analysis[0].region
    time_zone = google_cloud_scheduler_job.weekly_batch_analysis[0].time_zone
  } : null
}

# ==============================================================================
# CLOUD MONITORING OUTPUTS
# ==============================================================================

output "cpu_utilization_alert_policy" {
  description = "CPU utilization monitoring alert policy details"
  value = var.enable_monitoring_alerts ? {
    name         = google_monitoring_alert_policy.high_cost_low_utilization[0].name
    display_name = google_monitoring_alert_policy.high_cost_low_utilization[0].display_name
    enabled      = google_monitoring_alert_policy.high_cost_low_utilization[0].enabled
    threshold    = var.cpu_utilization_threshold
  } : null
}

output "memory_utilization_alert_policy" {
  description = "Memory utilization monitoring alert policy details"
  value = var.enable_monitoring_alerts ? {
    name         = google_monitoring_alert_policy.memory_underutilization[0].name
    display_name = google_monitoring_alert_policy.memory_underutilization[0].display_name
    enabled      = google_monitoring_alert_policy.memory_underutilization[0].enabled
    threshold    = var.memory_utilization_threshold
  } : null
}

# ==============================================================================
# CONFIGURATION AND OPERATIONAL OUTPUTS
# ==============================================================================

output "optimization_thresholds" {
  description = "Cost optimization threshold configuration"
  value = {
    cpu_utilization_threshold    = var.cpu_utilization_threshold
    memory_utilization_threshold = var.memory_utilization_threshold
    monitoring_duration_seconds  = var.monitoring_duration
    data_retention_days          = var.data_retention_days
  }
}

output "enabled_features" {
  description = "Summary of enabled cost optimization features"
  value = {
    monitoring_alerts        = var.enable_monitoring_alerts
    scheduler_jobs          = var.enable_scheduler_jobs
    pubsub_dead_letter      = var.enable_pubsub_dead_letter
    cost_anomaly_detection  = var.enable_cost_anomaly_detection
    audit_logging           = var.enable_audit_logging
    preemptible_instances   = var.enable_preemptible_instances
    storage_versioning      = var.enable_versioning
  }
}

output "resource_labels" {
  description = "Common labels applied to all cost optimization resources"
  value       = local.common_labels
  sensitive   = false
}

output "api_endpoints" {
  description = "Important API endpoints for cost optimization operations"
  value = {
    batch_api_endpoint      = "https://batch.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}"
    bigquery_api_endpoint   = "https://bigquery.googleapis.com/bigquery/v2/projects/${var.project_id}/datasets/${google_bigquery_dataset.cost_analytics.dataset_id}"
    storage_api_endpoint    = "https://storage.googleapis.com/storage/v1/b/${google_storage_bucket.cost_optimization_data.name}"
    function_trigger_url    = google_cloudfunctions2_function.cost_optimizer.service_config[0].uri
  }
}

# ==============================================================================
# COST TRACKING AND BILLING OUTPUTS
# ==============================================================================

output "cost_tracking_labels" {
  description = "Labels that can be used for cost tracking and billing analysis"
  value = {
    cost_center     = var.cost_center
    owner          = var.owner
    environment    = var.environment
    application    = var.application_name
    solution_type  = "cost-optimization"
    managed_by     = "terraform"
  }
}

output "resource_inventory" {
  description = "Summary of all deployed resources for inventory tracking"
  value = {
    storage_buckets     = 1
    bigquery_datasets   = 1
    bigquery_tables     = 2
    cloud_functions     = 1
    service_accounts    = 1
    pubsub_topics       = var.enable_pubsub_dead_letter ? 3 : 2
    pubsub_subscriptions = 2
    batch_jobs          = 1
    scheduler_jobs      = var.enable_scheduler_jobs ? 2 : 0
    alert_policies      = var.enable_monitoring_alerts ? 2 : 0
    iam_role_bindings   = 8  # Approximate count of IAM bindings
  }
}

# ==============================================================================
# OPERATIONAL COMMANDS AND REFERENCES
# ==============================================================================

output "useful_commands" {
  description = "Useful gcloud commands for managing the cost optimization infrastructure"
  value = {
    # BigQuery commands
    query_resource_utilization = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.cost_analytics.dataset_id}.${google_bigquery_table.resource_utilization.table_id}` LIMIT 10'"
    query_optimization_actions = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.cost_analytics.dataset_id}.${google_bigquery_table.optimization_actions.table_id}` ORDER BY timestamp DESC LIMIT 10'"
    
    # Cloud Function commands
    trigger_optimization = "gcloud functions call ${google_cloudfunctions2_function.cost_optimizer.name} --region=${var.region}"
    view_function_logs  = "gcloud functions logs read ${google_cloudfunctions2_function.cost_optimizer.name} --region=${var.region} --limit=50"
    
    # Batch job commands
    list_batch_jobs     = "gcloud batch jobs list --location=${var.region}"
    submit_batch_job    = "gcloud batch jobs submit new-analysis-job --location=${var.region} --config=${google_batch_job.infrastructure_analysis_template.name}"
    
    # Monitoring commands
    list_alert_policies = "gcloud alpha monitoring policies list --filter='displayName:*Cost*'"
    view_metrics        = "gcloud logging read 'resource.type=cloud_function AND resource.labels.function_name=${google_cloudfunctions2_function.cost_optimizer.name}' --limit=20"
    
    # Storage commands
    list_analysis_data  = "gsutil ls gs://${google_storage_bucket.cost_optimization_data.name}/analysis/"
    download_latest     = "gsutil cp gs://${google_storage_bucket.cost_optimization_data.name}/analysis/*.json ."
  }
}

output "dashboard_links" {
  description = "Direct links to Google Cloud Console dashboards for cost optimization monitoring"
  value = {
    bigquery_dataset    = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.cost_analytics.dataset_id}"
    cloud_functions     = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.cost_optimizer.name}?project=${var.project_id}"
    cloud_batch         = "https://console.cloud.google.com/batch/jobs?project=${var.project_id}"
    cloud_monitoring    = "https://console.cloud.google.com/monitoring/alerting?project=${var.project_id}"
    cloud_scheduler     = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
    storage_bucket      = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.cost_optimization_data.name}?project=${var.project_id}"
    cost_management     = "https://console.cloud.google.com/billing?project=${var.project_id}"
  }
}

# ==============================================================================
# TROUBLESHOOTING AND DEBUG OUTPUTS
# ==============================================================================

output "troubleshooting_info" {
  description = "Information useful for troubleshooting deployment and operational issues"
  value = {
    terraform_version   = "~> 1.0"
    google_provider_version = "~> 6.44"
    deployment_region   = var.region
    deployment_zone     = var.zone
    required_apis = [
      "batch.googleapis.com",
      "cloudfunctions.googleapis.com",
      "cloudscheduler.googleapis.com",
      "monitoring.googleapis.com",
      "pubsub.googleapis.com",
      "bigquery.googleapis.com",
      "storage.googleapis.com"
    ]
    common_issues_checklist = [
      "Verify all required APIs are enabled",
      "Check IAM permissions for service account",
      "Confirm Cloud Function deployment completed",
      "Validate BigQuery dataset location matches region",
      "Ensure storage bucket names are globally unique",
      "Check scheduler job permissions and authentication"
    ]
  }
}