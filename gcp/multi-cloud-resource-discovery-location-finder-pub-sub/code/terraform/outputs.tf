# Outputs for Multi-Cloud Resource Discovery Infrastructure
# This file defines all output values that provide useful information
# about the deployed infrastructure for integration and verification

# Project and basic configuration outputs
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were created"
  value       = var.region
}

output "resource_suffix" {
  description = "The unique suffix applied to all resource names"
  value       = random_id.suffix.hex
}

# Pub/Sub infrastructure outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for location discovery messages"
  value       = google_pubsub_topic.location_discovery.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.location_discovery.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for message processing"
  value       = google_pubsub_subscription.location_discovery_sub.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.location_discovery_sub.id
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed messages"
  value       = google_pubsub_topic.dead_letter.name
}

# Cloud Function outputs
output "function_name" {
  description = "Name of the Cloud Function for location data processing"
  value       = google_cloudfunctions_function.location_processor.name
}

output "function_url" {
  description = "HTTP trigger URL for the Cloud Function (if applicable)"
  value       = google_cloudfunctions_function.location_processor.https_trigger_url
}

output "function_status" {
  description = "Deployment status of the Cloud Function"
  value       = google_cloudfunctions_function.location_processor.status
}

output "function_service_account_email" {
  description = "Email address of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

# Cloud Storage outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for location reports"
  value       = google_storage_bucket.location_reports.name
}

output "storage_bucket_url" {
  description = "Full URL of the Cloud Storage bucket"
  value       = google_storage_bucket.location_reports.url
}

output "storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.location_reports.location
}

output "storage_bucket_class" {
  description = "Storage class of the Cloud Storage bucket"
  value       = google_storage_bucket.location_reports.storage_class
}

# Cloud Scheduler outputs
output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for automated discovery"
  value       = google_cloud_scheduler_job.location_discovery_scheduler.name
}

output "scheduler_job_schedule" {
  description = "Schedule configuration for the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.location_discovery_scheduler.schedule
}

output "scheduler_job_timezone" {
  description = "Timezone configuration for the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.location_discovery_scheduler.time_zone
}

# Monitoring outputs (conditional based on monitoring enablement)
output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_dashboard.location_discovery_dashboard[0].id : null
}

output "function_failure_alert_policy_id" {
  description = "ID of the function failure alert policy (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_failure_alert[0].name : null
}

output "pubsub_delay_alert_policy_id" {
  description = "ID of the Pub/Sub delay alert policy (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.pubsub_delay_alert[0].name : null
}

# API enablement status
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = var.enable_apis ? [for api in google_project_service.required_apis : api.service] : []
}

# Access information for integration
output "pubsub_topic_publish_command" {
  description = "Command to manually publish a message to the Pub/Sub topic"
  value = format(
    "gcloud pubsub topics publish %s --message='%s'",
    google_pubsub_topic.location_discovery.name,
    jsonencode({
      trigger   = "manual_test"
      timestamp = timestamp()
    })
  )
}

output "storage_bucket_list_command" {
  description = "Command to list contents of the storage bucket"
  value       = "gsutil ls -la gs://${google_storage_bucket.location_reports.name}/"
}

output "function_logs_command" {
  description = "Command to view Cloud Function logs"
  value       = "gcloud functions logs read ${google_cloudfunctions_function.location_processor.name} --region=${var.region} --limit=50"
}

# Resource URLs for Google Cloud Console access
output "console_urls" {
  description = "Google Cloud Console URLs for easy access to resources"
  value = {
    project = "https://console.cloud.google.com/home/dashboard?project=${var.project_id}"
    
    pubsub_topic = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.location_discovery.name}?project=${var.project_id}"
    
    pubsub_subscription = "https://console.cloud.google.com/cloudpubsub/subscription/detail/${google_pubsub_subscription.location_discovery_sub.name}?project=${var.project_id}"
    
    cloud_function = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.location_processor.name}?project=${var.project_id}"
    
    storage_bucket = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.location_reports.name}?project=${var.project_id}"
    
    scheduler_job = "https://console.cloud.google.com/cloudscheduler/jobs/detail/${var.region}/${google_cloud_scheduler_job.location_discovery_scheduler.name}?project=${var.project_id}"
    
    monitoring_dashboard = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.location_discovery_dashboard[0].id}?project=${var.project_id}" : null
    
    monitoring_alerting = "https://console.cloud.google.com/monitoring/alerting?project=${var.project_id}"
  }
}

# Cost estimation information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (approximate)"
  value = {
    cloud_function_invocations = "2-5 USD (based on 4 executions per day)"
    pubsub_messages           = "0.01-0.10 USD (based on message volume)"
    cloud_storage            = "1-3 USD (based on 1GB storage with lifecycle policies)"
    cloud_scheduler          = "0.10 USD (1 job with 120 executions per month)"
    monitoring               = "0-1 USD (based on custom metrics usage)"
    total_estimated          = "3-9 USD per month"
    note                     = "Costs depend on actual usage patterns and data volumes"
  }
}

# Security and IAM information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    service_account           = google_service_account.function_sa.email
    uniform_bucket_access     = var.enable_uniform_bucket_level_access
    function_iam_roles        = ["pubsub.subscriber", "storage.objectAdmin", "monitoring.metricWriter", "cloudlocationfinder.viewer"]
    pubsub_message_retention  = var.pubsub_message_retention
    dead_letter_topic_enabled = true
  }
}

# Operational commands for management
output "management_commands" {
  description = "Useful commands for managing the deployed infrastructure"
  value = {
    trigger_scheduler_job = "gcloud scheduler jobs run ${google_cloud_scheduler_job.location_discovery_scheduler.name} --location=${var.region}"
    
    view_function_logs = "gcloud functions logs read ${google_cloudfunctions_function.location_processor.name} --region=${var.region}"
    
    list_pubsub_messages = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.location_discovery_sub.name} --auto-ack --limit=10"
    
    view_storage_reports = "gsutil ls gs://${google_storage_bucket.location_reports.name}/reports/"
    
    test_function_manually = "gcloud pubsub topics publish ${google_pubsub_topic.location_discovery.name} --message='{\"trigger\":\"manual_test\"}'"
  }
}