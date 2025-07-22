# Output values for the data locality optimization infrastructure
# These outputs provide important information for verification and integration

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "primary_region" {
  description = "The primary region where resources are deployed"
  value       = var.primary_region
}

output "secondary_region" {
  description = "The secondary region configured for potential bucket relocation"
  value       = var.secondary_region
}

# Cloud Storage outputs
output "bucket_name" {
  description = "Name of the Cloud Storage bucket for data locality optimization"
  value       = google_storage_bucket.data_locality_bucket.name
}

output "bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.data_locality_bucket.url
}

output "bucket_location" {
  description = "Current location of the Cloud Storage bucket"
  value       = google_storage_bucket.data_locality_bucket.location
}

output "bucket_storage_class" {
  description = "Storage class of the Cloud Storage bucket"
  value       = google_storage_bucket.data_locality_bucket.storage_class
}

# Cloud Function outputs
output "function_name" {
  description = "Name of the bucket relocation Cloud Function"
  value       = google_cloudfunctions_function.bucket_relocator.name
}

output "function_url" {
  description = "HTTPS trigger URL for the bucket relocation function"
  value       = google_cloudfunctions_function.bucket_relocator.https_trigger_url
  sensitive   = true
}

output "function_service_account" {
  description = "Service account email used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

# Pub/Sub outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for relocation notifications"
  value       = google_pubsub_topic.relocation_alerts.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.relocation_alerts.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for monitoring relocation events"
  value       = google_pubsub_subscription.relocation_monitor.name
}

# Cloud Scheduler outputs
output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for periodic analysis"
  value       = google_cloud_scheduler_job.locality_analyzer.name
}

output "scheduler_cron" {
  description = "Cron expression for the periodic analysis schedule"
  value       = google_cloud_scheduler_job.locality_analyzer.schedule
}

output "scheduler_timezone" {
  description = "Timezone configured for the scheduler job"
  value       = google_cloud_scheduler_job.locality_analyzer.time_zone
}

# Monitoring outputs
output "custom_metric_type" {
  description = "Type of the custom metric for regional access latency"
  value       = var.enable_detailed_monitoring ? google_monitoring_metric_descriptor.regional_access_latency[0].type : null
}

output "alert_policy_names" {
  description = "Names of created monitoring alert policies"
  value = compact([
    var.enable_detailed_monitoring ? google_monitoring_alert_policy.storage_latency_alert[0].display_name : null,
    var.enable_detailed_monitoring && var.notification_email != "" ? google_monitoring_alert_policy.storage_latency_alert_with_notifications[0].display_name : null
  ])
}

output "notification_channel_id" {
  description = "ID of the email notification channel (if configured)"
  value       = var.notification_email != "" ? google_monitoring_notification_channel.email_notification[0].id : null
}

# Resource identification outputs
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Deployment information outputs
output "deployment_timestamp" {
  description = "Timestamp of the Terraform deployment"
  value       = timestamp()
}

output "terraform_workspace" {
  description = "Terraform workspace used for this deployment"
  value       = terraform.workspace
}

# Service account outputs
output "service_accounts" {
  description = "Service accounts created for the data locality optimization system"
  value = {
    function_sa = {
      email       = google_service_account.function_sa.email
      unique_id   = google_service_account.function_sa.unique_id
      description = google_service_account.function_sa.description
    }
    scheduler_sa = {
      email       = google_service_account.scheduler_sa.email
      unique_id   = google_service_account.scheduler_sa.unique_id
      description = google_service_account.scheduler_sa.description
    }
  }
}

# API services outputs
output "enabled_apis" {
  description = "Google Cloud APIs enabled for this deployment"
  value       = [for api in google_project_service.required_apis : api.service]
}

# Configuration summary outputs
output "configuration_summary" {
  description = "Summary of key configuration settings"
  value = {
    environment                = var.environment
    enable_detailed_monitoring = var.enable_detailed_monitoring
    alert_threshold_ms        = var.alert_threshold_ms
    function_memory_mb        = var.function_memory
    function_timeout_seconds  = var.function_timeout
    bucket_storage_class      = var.bucket_storage_class
    uniform_bucket_access     = var.enable_uniform_bucket_access
    notification_email        = var.notification_email != "" ? "configured" : "not_configured"
  }
}

# Resource URLs for quick access
output "resource_urls" {
  description = "URLs for accessing key resources in the Google Cloud Console"
  value = {
    bucket_console_url = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.data_locality_bucket.name}"
    function_console_url = "https://console.cloud.google.com/functions/details/${var.primary_region}/${google_cloudfunctions_function.bucket_relocator.name}"
    monitoring_console_url = "https://console.cloud.google.com/monitoring"
    pubsub_console_url = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.relocation_alerts.name}"
    scheduler_console_url = "https://console.cloud.google.com/cloudscheduler"
  }
}

# Testing and validation outputs
output "validation_commands" {
  description = "Commands for validating the deployment"
  value = {
    test_function = "curl -X GET '${google_cloudfunctions_function.bucket_relocator.https_trigger_url}'"
    check_bucket = "gsutil ls -L -b gs://${google_storage_bucket.data_locality_bucket.name}"
    pull_messages = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.relocation_monitor.name} --limit=5"
    check_scheduler = "gcloud scheduler jobs describe ${google_cloud_scheduler_job.locality_analyzer.name} --location=${var.primary_region}"
  }
}