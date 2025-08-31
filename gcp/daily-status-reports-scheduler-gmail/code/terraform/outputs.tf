# ==============================================================================
# TERRAFORM OUTPUTS FOR DAILY STATUS REPORTS INFRASTRUCTURE
# ==============================================================================
# This file defines all output values that will be displayed after successful
# infrastructure deployment. These outputs provide essential information for
# verification, monitoring, and integration with other systems.

# ==============================================================================
# CORE INFRASTRUCTURE OUTPUTS
# ==============================================================================

output "project_id" {
  description = "The GCP project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

# ==============================================================================
# CLOUD FUNCTION OUTPUTS
# ==============================================================================

output "function_name" {
  description = "The name of the deployed Cloud Function"
  value       = google_cloudfunctions_function.status_report_generator.name
}

output "function_url" {
  description = "The HTTPS trigger URL for the Cloud Function"
  value       = google_cloudfunctions_function.status_report_generator.https_trigger_url
  sensitive   = false
}

output "function_runtime" {
  description = "The runtime environment for the Cloud Function"
  value       = google_cloudfunctions_function.status_report_generator.runtime
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  value       = google_cloudfunctions_function.status_report_generator.available_memory_mb
}

output "function_timeout" {
  description = "Timeout setting for the Cloud Function in seconds"
  value       = google_cloudfunctions_function.status_report_generator.timeout
}

output "function_service_account" {
  description = "Email address of the service account used by the Cloud Function"
  value       = google_service_account.status_reporter.email
}

# ==============================================================================
# CLOUD SCHEDULER OUTPUTS
# ==============================================================================

output "scheduler_job_name" {
  description = "The name of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.daily_report_trigger.name
}

output "scheduler_job_schedule" {
  description = "The cron schedule for the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.daily_report_trigger.schedule
}

output "scheduler_job_timezone" {
  description = "The timezone setting for the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.daily_report_trigger.time_zone
}

output "scheduler_job_region" {
  description = "The region where the Cloud Scheduler job is deployed"
  value       = google_cloud_scheduler_job.daily_report_trigger.region
}

# ==============================================================================
# SERVICE ACCOUNT OUTPUTS
# ==============================================================================

output "service_account_id" {
  description = "The unique ID of the service account"
  value       = google_service_account.status_reporter.unique_id
}

output "service_account_email" {
  description = "The email address of the service account"
  value       = google_service_account.status_reporter.email
}

output "service_account_name" {
  description = "The display name of the service account"
  value       = google_service_account.status_reporter.display_name
}

# ==============================================================================
# STORAGE OUTPUTS
# ==============================================================================

output "source_bucket_name" {
  description = "The name of the storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "source_bucket_url" {
  description = "The URL of the storage bucket containing function source code"
  value       = google_storage_bucket.function_source.url
}

# ==============================================================================
# CONFIGURATION OUTPUTS
# ==============================================================================

output "email_configuration" {
  description = "Email configuration details (sensitive values masked)"
  value = {
    sender_email    = var.sender_email
    recipient_email = var.recipient_email
    password_set    = var.sender_password != "" ? "Yes" : "No"
  }
}

output "monitoring_configuration" {
  description = "Monitoring and reporting configuration"
  value = {
    monitoring_period_hours    = var.monitoring_period_hours
    include_cost_analysis     = var.include_cost_analysis
    include_security_insights = var.include_security_insights
  }
}

# ==============================================================================
# RESOURCE IDENTIFIERS FOR MANAGEMENT
# ==============================================================================

output "resource_names" {
  description = "Names of all created resources for easy identification and management"
  value = {
    function_name        = google_cloudfunctions_function.status_report_generator.name
    scheduler_job_name   = google_cloud_scheduler_job.daily_report_trigger.name
    service_account_name = google_service_account.status_reporter.account_id
    storage_bucket_name  = google_storage_bucket.function_source.name
  }
}

output "resource_urls" {
  description = "Direct URLs for accessing resources in Google Cloud Console"
  value = {
    function_console_url = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.status_report_generator.name}?project=${var.project_id}"
    scheduler_console_url = "https://console.cloud.google.com/cloudscheduler/jobs/edit/${var.region}/${google_cloud_scheduler_job.daily_report_trigger.name}?project=${var.project_id}"
    monitoring_console_url = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    service_account_console_url = "https://console.cloud.google.com/iam-admin/serviceaccounts/details/${google_service_account.status_reporter.unique_id}?project=${var.project_id}"
  }
}

# ==============================================================================
# VERIFICATION AND TESTING OUTPUTS
# ==============================================================================

output "test_function_command" {
  description = "gcloud command to manually test the Cloud Function"
  value       = "gcloud functions call ${google_cloudfunctions_function.status_report_generator.name} --region=${var.region}"
}

output "view_function_logs_command" {
  description = "gcloud command to view Cloud Function logs"
  value       = "gcloud functions logs read ${google_cloudfunctions_function.status_report_generator.name} --region=${var.region} --limit=10"
}

output "trigger_scheduler_job_command" {
  description = "gcloud command to manually trigger the scheduler job"
  value       = "gcloud scheduler jobs run ${google_cloud_scheduler_job.daily_report_trigger.name} --location=${var.region}"
}

output "view_scheduler_status_command" {
  description = "gcloud command to check scheduler job status"
  value       = "gcloud scheduler jobs describe ${google_cloud_scheduler_job.daily_report_trigger.name} --location=${var.region}"
}

# ==============================================================================
# COST AND BILLING OUTPUTS
# ==============================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the deployed resources"
  value = {
    cloud_function_invocations = "~$0.0000004 per invocation (daily = ~$0.012/month)"
    cloud_scheduler_jobs       = "~$0.10 per job per month"
    storage_bucket            = "~$0.020 per GB per month (minimal usage)"
    total_estimated           = "~$0.13-$2.00 per month depending on usage"
    note                      = "Costs may vary based on actual usage, region, and GCP pricing changes"
  }
}

# ==============================================================================
# OPERATIONAL OUTPUTS
# ==============================================================================

output "next_scheduled_execution" {
  description = "Information about the next scheduled report execution"
  value = {
    schedule_expression = var.cron_schedule
    timezone           = var.timezone
    frequency          = "Daily at 9:00 AM (default schedule)"
    note              = "Use 'gcloud scheduler jobs describe' command for precise next execution time"
  }
}

output "troubleshooting_info" {
  description = "Common troubleshooting commands and information"
  value = {
    check_function_status    = "gcloud functions describe ${google_cloudfunctions_function.status_report_generator.name} --region=${var.region}"
    check_scheduler_status   = "gcloud scheduler jobs describe ${google_cloud_scheduler_job.daily_report_trigger.name} --location=${var.region}"
    view_recent_executions  = "gcloud logging read 'resource.type=\"cloud_function\" resource.labels.function_name=\"${google_cloudfunctions_function.status_report_generator.name}\"' --limit=20"
    test_email_connectivity = "Check Gmail app password and ensure sender email has 'Less secure app access' or app-specific password configured"
  }
}

# ==============================================================================
# INTEGRATION OUTPUTS
# ==============================================================================

output "integration_endpoints" {
  description = "Endpoints and identifiers for integrating with other services"
  value = {
    function_trigger_url    = google_cloudfunctions_function.status_report_generator.https_trigger_url
    service_account_email  = google_service_account.status_reporter.email
    monitoring_project_id  = var.project_id
    scheduler_job_resource = "projects/${var.project_id}/locations/${var.region}/jobs/${google_cloud_scheduler_job.daily_report_trigger.name}"
  }
}