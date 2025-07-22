# Outputs for GCP Domain Health Monitoring Infrastructure

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "function_name" {
  description = "Name of the Cloud Function performing domain health monitoring"
  value       = google_cloudfunctions2_function.domain_monitor.name
}

output "function_url" {
  description = "HTTPS trigger URL for the domain monitoring Cloud Function"
  value       = google_cloudfunctions2_function.domain_monitor.service_config[0].uri
  sensitive   = false
}

output "function_service_account" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for function code and monitoring data"
  value       = google_storage_bucket.function_storage.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.function_storage.url
}

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for domain health alerts"
  value       = google_pubsub_topic.domain_alerts.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.domain_alerts.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for alert processing"
  value       = google_pubsub_subscription.domain_alerts_sub.name
}

output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job (if enabled)"
  value       = var.enable_cloud_scheduler ? google_cloud_scheduler_job.domain_monitor_schedule[0].name : null
}

output "scheduler_job_schedule" {
  description = "Cron schedule for the monitoring job"
  value       = var.monitoring_schedule
}

output "notification_channel_id" {
  description = "ID of the email notification channel (if configured)"
  value       = var.notification_email != "" ? google_monitoring_notification_channel.email_alerts[0].id : null
  sensitive   = false
}

output "notification_email" {
  description = "Email address configured for notifications"
  value       = var.notification_email != "" ? var.notification_email : "Not configured"
  sensitive   = true
}

output "alert_policies" {
  description = "Map of alert policy names and their IDs"
  value = {
    ssl_expiry    = google_monitoring_alert_policy.ssl_expiry_alert.name
    dns_failure   = google_monitoring_alert_policy.dns_failure_alert.name
    http_failure  = google_monitoring_alert_policy.http_failure_alert.name
  }
}

output "domains_monitored" {
  description = "List of domains configured for monitoring"
  value       = var.domains_to_monitor
}

output "ssl_expiry_warning_days" {
  description = "Number of days before SSL expiry to trigger warnings"
  value       = var.ssl_expiry_warning_days
}

output "function_timeout" {
  description = "Timeout configuration for the Cloud Function in seconds"
  value       = var.function_timeout
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function"
  value       = var.function_memory
}

output "monitoring_metrics" {
  description = "Custom monitoring metrics created for domain health"
  value = [
    "custom.googleapis.com/domain/ssl_valid",
    "custom.googleapis.com/domain/dns_resolves",
    "custom.googleapis.com/domain/http_responds"
  ]
}

output "log_sink_name" {
  description = "Name of the Cloud Logging sink for function logs"
  value       = google_logging_project_sink.function_logs.name
}

output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed alert messages"
  value       = google_pubsub_topic.domain_alerts_dlq.name
}

# Deployment verification outputs
output "deployment_status" {
  description = "Status information for deployment verification"
  value = {
    apis_enabled         = length(google_project_service.required_apis)
    function_deployed    = google_cloudfunctions2_function.domain_monitor.name != ""
    storage_created      = google_storage_bucket.function_storage.name != ""
    alerts_configured    = length([
      google_monitoring_alert_policy.ssl_expiry_alert.name,
      google_monitoring_alert_policy.dns_failure_alert.name,
      google_monitoring_alert_policy.http_failure_alert.name
    ])
    scheduler_enabled    = var.enable_cloud_scheduler
    notifications_setup  = var.notification_email != ""
  }
}

# Manual testing commands
output "manual_test_commands" {
  description = "Commands to manually test the domain monitoring function"
  value = {
    curl_function = "curl -X POST '${google_cloudfunctions2_function.domain_monitor.service_config[0].uri}' -H 'Authorization: Bearer $(gcloud auth print-identity-token)' -H 'Content-Type: application/json' -d '{\"trigger\":\"manual\"}'"
    
    view_logs = "gcloud functions logs read ${google_cloudfunctions2_function.domain_monitor.name} --region=${var.region} --limit=10"
    
    check_storage = "gsutil ls gs://${google_storage_bucket.function_storage.name}/monitoring-results/"
    
    view_metrics = "gcloud logging read 'resource.type=cloud_function AND resource.labels.function_name=${google_cloudfunctions2_function.domain_monitor.name}' --limit=10"
    
    list_alerts = "gcloud alpha monitoring policies list --filter='displayName:(SSL OR DNS OR HTTP)'"
  }
}

# Cost estimation information
output "cost_estimation" {
  description = "Estimated monthly costs for the domain monitoring infrastructure"
  value = {
    note = "Costs depend on monitoring frequency, number of domains, and usage patterns"
    components = {
      cloud_functions = "~$0.01-5.00/month (depends on execution frequency)"
      cloud_storage   = "~$0.50-2.00/month (depends on data volume)"
      cloud_monitoring = "Free tier should cover most monitoring needs"
      pub_sub         = "~$0.10-1.00/month (depends on message volume)"
      cloud_scheduler = "Free tier covers up to 3 jobs"
    }
    total_estimate = "$1-10/month for typical usage patterns"
  }
}

# Security and compliance outputs
output "security_features" {
  description = "Security features implemented in the infrastructure"
  value = {
    service_account        = "Dedicated service account with least privilege permissions"
    private_bucket        = "Uniform bucket-level access with public access prevention"
    encryption           = "Google-managed encryption for all data at rest"
    vpc_support          = "Optional VPC connector for private network access"
    dead_letter_queue    = "Dead letter queue for failed alert message handling"
    retention_policy     = "Configurable data retention policies"
    logging_integration  = "Comprehensive logging and audit trails"
  }
}