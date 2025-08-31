# Output values for the website uptime monitoring infrastructure
# These outputs provide important information about created resources
# and can be used for verification and integration with other systems

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were created"
  value       = var.region
}

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic receiving uptime alerts"
  value       = google_pubsub_topic.uptime_alerts.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.uptime_alerts.id
}

output "cloud_function_name" {
  description = "Name of the Cloud Function processing uptime alerts"
  value       = google_cloudfunctions2_function.uptime_processor.name
}

output "cloud_function_url" {
  description = "URL of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.uptime_processor.service_config[0].uri
}

output "notification_channel_id" {
  description = "ID of the Cloud Monitoring notification channel"
  value       = google_monitoring_notification_channel.pubsub_alerts.name
}

output "alert_policy_id" {
  description = "ID of the Cloud Monitoring alert policy"
  value       = google_monitoring_alert_policy.uptime_failures.name
}

output "uptime_check_ids" {
  description = "Map of website URLs to their uptime check IDs"
  value = {
    for url, check in google_monitoring_uptime_check_config.website_checks :
    url => check.uptime_check_id
  }
}

output "uptime_check_names" {
  description = "Map of website URLs to their uptime check display names"
  value = {
    for url, check in google_monitoring_uptime_check_config.website_checks :
    url => check.display_name
  }
}

output "dashboard_url" {
  description = "URL to view the uptime monitoring dashboard in Google Cloud Console"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${split("/", google_monitoring_dashboard.uptime_dashboard.id)[3]}?project=${var.project_id}"
}

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket storing function source code"
  value       = google_storage_bucket.function_source.name
}

output "service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "monitored_websites" {
  description = "List of websites being monitored for uptime"
  value       = var.websites_to_monitor
}

output "alert_configuration" {
  description = "Summary of alert configuration settings"
  value = {
    check_period_seconds     = var.uptime_check_period
    check_timeout_seconds    = var.uptime_check_timeout
    alert_threshold_count    = var.alert_threshold_count
    auto_close_duration_seconds = var.auto_close_duration
    checker_regions          = var.checker_regions
  }
}

output "function_configuration" {
  description = "Summary of Cloud Function configuration"
  value = {
    runtime           = "python312"
    memory_mb         = var.function_memory
    timeout_seconds   = var.function_timeout
    max_instances     = var.function_max_instances
    entry_point       = "process_uptime_alert"
  }
}

output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
  sensitive   = false
}

output "quick_start_commands" {
  description = "Commands to test and verify the monitoring setup"
  value = {
    test_pubsub = "gcloud pubsub topics publish ${google_pubsub_topic.uptime_alerts.name} --message='{\"test\": \"message\"}'"
    view_logs   = "gcloud functions logs read ${google_cloudfunctions2_function.uptime_processor.name} --region=${var.region} --limit=10"
    list_checks = "gcloud monitoring uptime list --filter='displayName:${var.resource_prefix}-check-*'"
    view_alerts = "gcloud alpha monitoring policies list --filter='displayName:${google_monitoring_alert_policy.uptime_failures.display_name}'"
  }
}

output "cost_optimization_notes" {
  description = "Information about cost optimization for the monitoring solution"
  value = {
    free_tier_info = "Cloud Monitoring includes free tier for uptime checks and basic alerting"
    cost_factors = [
      "Number of uptime checks and frequency",
      "Cloud Function invocations and execution time", 
      "Pub/Sub message volume",
      "Cloud Storage for function source code"
    ]
    optimization_tips = [
      "Adjust uptime_check_period to reduce check frequency",
      "Monitor alert volume to optimize notification costs",
      "Use lifecycle policies on storage bucket to manage costs"
    ]
  }
}