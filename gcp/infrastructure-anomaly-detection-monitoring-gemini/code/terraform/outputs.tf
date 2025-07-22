# Infrastructure Anomaly Detection with Cloud Monitoring and Gemini
# Terraform output definitions

# Project and resource identification outputs
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were created"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = random_id.suffix.hex
}

# Pub/Sub infrastructure outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for monitoring events"
  value       = google_pubsub_topic.monitoring_events.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.monitoring_events.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for anomaly analysis"
  value       = google_pubsub_subscription.anomaly_analysis.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.anomaly_analysis.id
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed messages"
  value       = google_pubsub_topic.dead_letter.name
}

# Cloud Function outputs
output "cloud_function_name" {
  description = "Name of the Cloud Function for anomaly detection"
  value       = google_cloudfunctions2_function.anomaly_detector.name
}

output "cloud_function_url" {
  description = "URL of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.anomaly_detector.service_config[0].uri
}

output "cloud_function_service_account" {
  description = "Service account email used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

# Test infrastructure outputs (conditional)
output "test_instance_name" {
  description = "Name of the test VM instance (if enabled)"
  value       = var.enable_test_infrastructure ? google_compute_instance.test_instance[0].name : null
}

output "test_instance_external_ip" {
  description = "External IP address of the test VM instance (if enabled)"
  value       = var.enable_test_infrastructure ? google_compute_instance.test_instance[0].network_interface[0].access_config[0].nat_ip : null
}

output "test_instance_internal_ip" {
  description = "Internal IP address of the test VM instance (if enabled)"
  value       = var.enable_test_infrastructure ? google_compute_instance.test_instance[0].network_interface[0].network_ip : null
}

output "test_instance_zone" {
  description = "Zone of the test VM instance (if enabled)"
  value       = var.enable_test_infrastructure ? google_compute_instance.test_instance[0].zone : null
}

# Monitoring and alerting outputs
output "anomaly_score_metric_name" {
  description = "Name of the custom log-based metric for anomaly scores"
  value       = google_logging_metric.anomaly_score.name
}

output "cpu_alert_policy_name" {
  description = "Name of the CPU anomaly alert policy"
  value       = google_monitoring_alert_policy.cpu_anomaly.display_name
}

output "cpu_alert_policy_id" {
  description = "ID of the CPU anomaly alert policy"
  value       = google_monitoring_alert_policy.cpu_anomaly.name
}

output "notification_channel_name" {
  description = "Name of the email notification channel"
  value       = google_monitoring_notification_channel.email.display_name
}

output "notification_channel_id" {
  description = "ID of the email notification channel"
  value       = google_monitoring_notification_channel.email.name
}

output "dashboard_id" {
  description = "ID of the monitoring dashboard"
  value       = google_monitoring_dashboard.anomaly_dashboard.id
}

# URLs and console links
output "cloud_console_function_url" {
  description = "Google Cloud Console URL for the Cloud Function"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.anomaly_detector.name}?project=${var.project_id}"
}

output "cloud_console_pubsub_url" {
  description = "Google Cloud Console URL for Pub/Sub topics"
  value       = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.monitoring_events.name}?project=${var.project_id}"
}

output "cloud_console_monitoring_url" {
  description = "Google Cloud Console URL for monitoring overview"
  value       = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
}

output "cloud_console_dashboard_url" {
  description = "Google Cloud Console URL for the anomaly detection dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.anomaly_dashboard.id}?project=${var.project_id}"
}

output "cloud_console_alerts_url" {
  description = "Google Cloud Console URL for alert policies"
  value       = "https://console.cloud.google.com/monitoring/alerting/policies?project=${var.project_id}"
}

# Storage outputs
output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.url
}

# Configuration outputs for validation
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value       = [for api in google_project_service.required_apis : api.service]
}

output "gemini_model" {
  description = "Gemini model configured for anomaly analysis"
  value       = var.gemini_model
}

output "cpu_threshold" {
  description = "CPU utilization threshold for anomaly detection"
  value       = var.cpu_threshold
}

output "notification_email" {
  description = "Email address configured for anomaly notifications"
  value       = var.notification_email
  sensitive   = true
}

# Testing and validation commands
output "test_commands" {
  description = "Commands to test the deployed infrastructure"
  value = {
    # Function logs
    view_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.anomaly_detector.name} --region=${var.region} --project=${var.project_id}"
    
    # Pub/Sub testing
    publish_test_message = "gcloud pubsub topics publish ${google_pubsub_topic.monitoring_events.name} --message='{\"metric_name\":\"test\",\"value\":0.95,\"resource\":\"test\"}' --project=${var.project_id}"
    
    # SSH to test instance (if enabled)
    ssh_to_test_instance = var.enable_test_infrastructure ? "gcloud compute ssh ${google_compute_instance.test_instance[0].name} --zone=${var.zone} --project=${var.project_id}" : "Test instance not enabled"
    
    # View monitoring metrics
    view_monitoring_metrics = "gcloud monitoring metrics list --project=${var.project_id}"
    
    # View alert policies
    view_alert_policies = "gcloud alpha monitoring policies list --project=${var.project_id}"
  }
}

# Resource summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    cloud_function          = google_cloudfunctions2_function.anomaly_detector.name
    pubsub_topic           = google_pubsub_topic.monitoring_events.name
    pubsub_subscription    = google_pubsub_subscription.anomaly_analysis.name
    service_account        = google_service_account.function_sa.email
    storage_bucket         = google_storage_bucket.function_source.name
    test_instance          = var.enable_test_infrastructure ? google_compute_instance.test_instance[0].name : "disabled"
    anomaly_metric         = google_logging_metric.anomaly_score.name
    alert_policy           = google_monitoring_alert_policy.cpu_anomaly.name
    notification_channel   = google_monitoring_notification_channel.email.name
    dashboard              = google_monitoring_dashboard.anomaly_dashboard.id
    estimated_monthly_cost = "$15-25 USD (varies by usage)"
  }
}