# Project and Environment Information
output "project_id" {
  description = "The Google Cloud project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "Environment name for this deployment"
  value       = var.environment
}

# Compute Instance Information
output "web_app_instance_name" {
  description = "Name of the sample web application Compute Engine instance"
  value       = google_compute_instance.web_app.name
}

output "web_app_instance_zone" {
  description = "Zone where the web application instance is deployed"
  value       = google_compute_instance.web_app.zone
}

output "web_app_public_ip" {
  description = "Public IP address of the web application instance"
  value       = google_compute_instance.web_app.network_interface[0].access_config[0].nat_ip
}

output "web_app_private_ip" {
  description = "Private IP address of the web application instance"
  value       = google_compute_instance.web_app.network_interface[0].network_ip
}

output "web_app_url" {
  description = "URL to access the sample web application"
  value       = "http://${google_compute_instance.web_app.network_interface[0].access_config[0].nat_ip}:5000"
}

output "web_app_api_endpoint" {
  description = "API endpoint for testing monitoring and alerts"
  value       = "http://${google_compute_instance.web_app.network_interface[0].access_config[0].nat_ip}:5000/api/data"
}

output "web_app_health_endpoint" {
  description = "Health check endpoint for the web application"
  value       = "http://${google_compute_instance.web_app.network_interface[0].access_config[0].nat_ip}:5000/health"
}

output "web_app_load_test_endpoint" {
  description = "Load test endpoint to trigger high response times for alert testing"
  value       = "http://${google_compute_instance.web_app.network_interface[0].access_config[0].nat_ip}:5000/load-test"
}

# Pub/Sub Information
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for performance alerts"
  value       = google_pubsub_topic.performance_alerts.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.performance_alerts.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for alert processing"
  value       = google_pubsub_subscription.performance_alerts_subscription.name
}

# Cloud Function Information
output "cloud_function_name" {
  description = "Name of the performance optimization Cloud Function"
  value       = google_cloudfunctions_function.performance_optimizer.name
}

output "cloud_function_url" {
  description = "HTTP trigger URL for the Cloud Function (if applicable)"
  value       = try(google_cloudfunctions_function.performance_optimizer.https_trigger_url, "N/A - Event triggered function")
}

output "cloud_function_source_bucket" {
  description = "Storage bucket containing the Cloud Function source code"
  value       = google_storage_bucket.function_source.name
}

# Service Account Information
output "monitoring_service_account_email" {
  description = "Email address of the monitoring service account"
  value       = google_service_account.monitoring_sa.email
}

output "function_service_account_email" {
  description = "Email address of the Cloud Function service account"
  value       = google_service_account.function_sa.email
}

# Monitoring Configuration
output "alert_policy_name" {
  description = "Name of the alert policy for high response times"
  value       = google_monitoring_alert_policy.high_response_time.display_name
}

output "alert_policy_id" {
  description = "Full resource ID of the alert policy"
  value       = google_monitoring_alert_policy.high_response_time.name
}

output "notification_channel_name" {
  description = "Name of the Pub/Sub notification channel"
  value       = google_monitoring_notification_channel.pubsub_channel.display_name
}

output "notification_channel_id" {
  description = "Full resource ID of the notification channel"
  value       = google_monitoring_notification_channel.pubsub_channel.name
}

# Dashboard Information
output "monitoring_dashboard_url" {
  description = "URL to access the performance monitoring dashboard in Google Cloud Console"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${basename(google_monitoring_dashboard.performance_dashboard.id)}?project=${var.project_id}"
}

output "monitoring_dashboard_id" {
  description = "Full resource ID of the monitoring dashboard"
  value       = google_monitoring_dashboard.performance_dashboard.id
}

# Security Configuration
output "firewall_rule_name" {
  description = "Name of the firewall rule allowing web application access"
  value       = google_compute_firewall.allow_web_app.name
}

output "allowed_source_ranges" {
  description = "CIDR blocks allowed to access the web application"
  value       = var.allowed_source_ranges
}

# Configuration Values
output "alert_threshold_seconds" {
  description = "Response time threshold configured for alerts"
  value       = var.alert_threshold_seconds
}

output "alert_duration" {
  description = "Duration threshold for alert triggering"
  value       = var.alert_duration
}

output "function_memory_mb" {
  description = "Memory allocation for the Cloud Function"
  value       = var.function_memory_mb
}

output "function_timeout_seconds" {
  description = "Timeout configuration for the Cloud Function"
  value       = var.function_timeout_seconds
}

# Resource Names for Reference
output "resource_names" {
  description = "Map of all created resource names for easy reference"
  value = {
    instance_name         = google_compute_instance.web_app.name
    pubsub_topic         = google_pubsub_topic.performance_alerts.name
    pubsub_subscription  = google_pubsub_subscription.performance_alerts_subscription.name
    function_name        = google_cloudfunctions_function.performance_optimizer.name
    storage_bucket       = google_storage_bucket.function_source.name
    firewall_rule        = google_compute_firewall.allow_web_app.name
    monitoring_sa        = google_service_account.monitoring_sa.account_id
    function_sa          = google_service_account.function_sa.account_id
    alert_policy         = google_monitoring_alert_policy.high_response_time.name
    notification_channel = google_monitoring_notification_channel.pubsub_channel.name
    dashboard           = google_monitoring_dashboard.performance_dashboard.id
  }
}

# Testing and Validation Commands
output "testing_commands" {
  description = "Commands to test and validate the monitoring setup"
  value = {
    test_api = "curl -s ${google_compute_instance.web_app.network_interface[0].access_config[0].nat_ip}:5000/api/data"
    
    health_check = "curl -s ${google_compute_instance.web_app.network_interface[0].access_config[0].nat_ip}:5000/health"
    
    load_test = "for i in {1..10}; do curl -s ${google_compute_instance.web_app.network_interface[0].access_config[0].nat_ip}:5000/load-test & done; wait"
    
    check_metrics = "gcloud monitoring metrics list --filter='metric.type:custom.googleapis.com/api/response_time' --project=${var.project_id}"
    
    view_logs = "gcloud functions logs read ${google_cloudfunctions_function.performance_optimizer.name} --limit=10 --project=${var.project_id}"
    
    check_alerts = "gcloud alpha monitoring policies list --filter='displayName:\"High API Response Time Alert\"' --project=${var.project_id}"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    access_dashboard = "Visit the monitoring dashboard: https://console.cloud.google.com/monitoring/dashboards/custom/${basename(google_monitoring_dashboard.performance_dashboard.id)}?project=${var.project_id}"
    
    test_monitoring = "Generate test traffic: curl -s ${google_compute_instance.web_app.network_interface[0].access_config[0].nat_ip}:5000/api/data"
    
    trigger_alerts = "Test alert system: curl -s ${google_compute_instance.web_app.network_interface[0].access_config[0].nat_ip}:5000/load-test"
    
    view_traces = "View distributed traces: https://console.cloud.google.com/traces/list?project=${var.project_id}"
    
    check_functions = "Monitor function executions: https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.performance_optimizer.name}?project=${var.project_id}"
  }
}