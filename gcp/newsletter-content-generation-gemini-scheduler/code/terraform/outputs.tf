# Output values for newsletter content generation infrastructure
# These outputs provide essential information for managing and using the deployed resources

# Cloud Storage outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for newsletter content"
  value       = google_storage_bucket.newsletter_content.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.newsletter_content.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.newsletter_content.self_link
}

output "content_template_path" {
  description = "Path to the content template in Cloud Storage"
  value       = "gs://${google_storage_bucket.newsletter_content.name}/${google_storage_bucket_object.content_template.name}"
}

# Cloud Function outputs
output "function_name" {
  description = "Name of the newsletter generation Cloud Function"
  value       = google_cloudfunctions2_function.newsletter_generator.name
}

output "function_url" {
  description = "HTTP trigger URL for the Cloud Function"
  value       = google_cloudfunctions2_function.newsletter_generator.service_config[0].uri
  sensitive   = false
}

output "function_location" {
  description = "Location where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.newsletter_generator.location
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

# Cloud Scheduler outputs
output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.newsletter_schedule.name
}

output "scheduler_job_schedule" {
  description = "Cron schedule for the newsletter generation job"
  value       = google_cloud_scheduler_job.newsletter_schedule.schedule
}

output "scheduler_job_timezone" {
  description = "Timezone for the scheduler job"
  value       = google_cloud_scheduler_job.newsletter_schedule.time_zone
}

output "scheduler_service_account_email" {
  description = "Email of the service account used by Cloud Scheduler"
  value       = google_service_account.scheduler_sa.email
}

# Project and configuration outputs
output "project_id" {
  description = "Google Cloud project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

output "vertex_ai_location" {
  description = "Location for Vertex AI resources"
  value       = var.vertex_ai_location
}

# Resource identifiers
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Monitoring outputs (conditional)
output "monitoring_notification_channel_id" {
  description = "ID of the monitoring notification channel (if created)"
  value       = var.enable_monitoring && var.alert_email != "" ? google_monitoring_notification_channel.email_alert[0].id : null
}

output "alert_policy_id" {
  description = "ID of the function failure alert policy (if created)"
  value       = var.enable_monitoring && var.alert_email != "" ? google_monitoring_alert_policy.function_failure_alert[0].id : null
}

# API endpoints and URLs for testing and integration
output "test_curl_command" {
  description = "Example curl command to test the function manually"
  value = var.enable_public_access ? "curl -X POST '${google_cloudfunctions2_function.newsletter_generator.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"topic\":\"AI in Email Marketing\"}'" : "Function requires authentication - use gcloud auth or service account"
}

output "gcloud_test_command" {
  description = "Example gcloud command to test the function"
  value       = "gcloud functions call ${google_cloudfunctions2_function.newsletter_generator.name} --region=${var.region} --data='{\"topic\":\"AI in Email Marketing\"}'"
}

# Cloud Console URLs for easy access
output "function_console_url" {
  description = "URL to view the Cloud Function in the Google Cloud Console"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.newsletter_generator.name}?project=${var.project_id}"
}

output "storage_console_url" {
  description = "URL to view the Cloud Storage bucket in the Google Cloud Console"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.newsletter_content.name}?project=${var.project_id}"
}

output "scheduler_console_url" {
  description = "URL to view the Cloud Scheduler job in the Google Cloud Console"
  value       = "https://console.cloud.google.com/cloudscheduler/jobs/edit/${var.region}/${google_cloud_scheduler_job.newsletter_schedule.name}?project=${var.project_id}"
}

output "vertex_ai_console_url" {
  description = "URL to view Vertex AI in the Google Cloud Console"
  value       = "https://console.cloud.google.com/vertex-ai?project=${var.project_id}"
}

# Cost and resource information
output "estimated_monthly_cost_info" {
  description = "Information about estimated monthly costs"
  value = {
    cloud_function = "Pay per invocation + compute time (first 2M invocations free)"
    cloud_storage  = "Pay per GB stored + operations (first 5GB free)"
    cloud_scheduler = "Pay per job execution (first 3 jobs free)"
    vertex_ai      = "Pay per API call and token usage"
    note          = "Actual costs depend on usage patterns. Monitor in Cloud Billing."
  }
}

# Deployment status and next steps
output "deployment_summary" {
  description = "Summary of deployed resources and next steps"
  value = {
    status = "Deployment complete"
    resources_created = [
      "Cloud Storage bucket: ${google_storage_bucket.newsletter_content.name}",
      "Cloud Function: ${google_cloudfunctions2_function.newsletter_generator.name}",
      "Cloud Scheduler job: ${google_cloud_scheduler_job.newsletter_schedule.name}",
      "Service accounts: 2",
      "IAM bindings: Configured"
    ]
    next_steps = [
      "Test the function using the provided commands",
      "Review the generated content in Cloud Storage",
      "Customize the content template as needed",
      "Monitor costs in Cloud Billing",
      "Set up additional monitoring if required"
    ]
    documentation = "See the recipe documentation for detailed usage instructions"
  }
}