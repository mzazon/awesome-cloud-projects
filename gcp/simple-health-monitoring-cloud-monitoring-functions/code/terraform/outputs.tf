# Output Values for Simple Health Monitoring Infrastructure
# These outputs provide important information about the created resources

output "project_id" {
  description = "The Google Cloud Platform project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name used for resource naming"
  value       = var.environment
}

# Pub/Sub Configuration Outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for alert notifications"
  value       = google_pubsub_topic.alert_notifications.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.alert_notifications.id
}

# Cloud Function Configuration Outputs
output "cloud_function_name" {
  description = "Name of the Cloud Function processing alerts"
  value       = google_cloudfunctions_function.alert_notifier.name
}

output "cloud_function_url" {
  description = "URL of the deployed Cloud Function (if HTTP trigger was used)"
  value       = try(google_cloudfunctions_function.alert_notifier.https_trigger_url, "N/A - Pub/Sub triggered function")
}

output "cloud_function_region" {
  description = "Region where the Cloud Function is deployed"
  value       = google_cloudfunctions_function.alert_notifier.region
}

output "cloud_function_runtime" {
  description = "Runtime version used by the Cloud Function"
  value       = google_cloudfunctions_function.alert_notifier.runtime
}

# Storage Configuration Outputs
output "function_source_bucket" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.function_source.url
}

# Monitoring Configuration Outputs
output "uptime_check_id" {
  description = "ID of the uptime check configuration"
  value       = google_monitoring_uptime_check_config.website_check.uptime_check_id
}

output "uptime_check_name" {
  description = "Display name of the uptime check"
  value       = google_monitoring_uptime_check_config.website_check.display_name
}

output "monitored_url" {
  description = "The URL being monitored for uptime"
  value       = var.monitored_url
}

output "uptime_check_period" {
  description = "How often the uptime check runs"
  value       = google_monitoring_uptime_check_config.website_check.period
}

output "uptime_check_timeout" {
  description = "Timeout duration for uptime checks"
  value       = google_monitoring_uptime_check_config.website_check.timeout
}

# Alert Policy Configuration Outputs
output "alert_policy_name" {
  description = "Display name of the alert policy"
  value       = google_monitoring_alert_policy.uptime_alert.display_name
}

output "alert_policy_id" {
  description = "ID of the alert policy"
  value       = google_monitoring_alert_policy.uptime_alert.name
}

output "alert_threshold_duration" {
  description = "Duration threshold for triggering alerts"
  value       = var.alert_threshold_duration
}

# Notification Channel Configuration Outputs
output "notification_channel_name" {
  description = "Display name of the notification channel"
  value       = google_monitoring_notification_channel.pubsub_channel.display_name
}

output "notification_channel_id" {
  description = "ID of the notification channel"
  value       = google_monitoring_notification_channel.pubsub_channel.name
}

output "notification_channel_type" {
  description = "Type of the notification channel"
  value       = google_monitoring_notification_channel.pubsub_channel.type
}

# Resource Naming Outputs
output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.resource_suffix
  sensitive   = false
}

output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = local.resource_prefix
}

# Configuration Summary Outputs
output "monitoring_summary" {
  description = "Summary of the monitoring configuration"
  value = {
    monitored_url           = var.monitored_url
    check_frequency        = google_monitoring_uptime_check_config.website_check.period
    alert_threshold        = var.alert_threshold_duration
    function_timeout       = "${var.function_timeout}s"
    function_memory        = "${var.function_memory}MB"
    ssl_validation_enabled = var.enable_ssl_validation
    environment           = var.environment
  }
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployment"
  value = {
    terraform_version = "~> 1.5"
    google_provider_version = "~> 5.0"
    deployed_at = timestamp()
    managed_by = "terraform"
  }
}

# Verification Commands
output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    check_uptime_status = "gcloud alpha monitoring uptime list --project=${var.project_id}"
    check_function_logs = "gcloud functions logs read ${google_cloudfunctions_function.alert_notifier.name} --region=${var.region} --project=${var.project_id}"
    test_pubsub_topic = "gcloud pubsub topics list --project=${var.project_id} --filter='name:${google_pubsub_topic.alert_notifications.name}'"
    check_alert_policies = "gcloud alpha monitoring policies list --project=${var.project_id}"
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = {
    function_billing = "Cloud Functions are billed per invocation and execution time"
    monitoring_free_tier = "Cloud Monitoring includes free tier for basic uptime checks"
    pubsub_free_tier = "Pub/Sub includes 10GB of messages per month in free tier"
    storage_lifecycle = "Function source bucket has 30-day lifecycle policy"
  }
}