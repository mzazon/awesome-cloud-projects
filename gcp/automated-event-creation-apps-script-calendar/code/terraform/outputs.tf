# Output Values for Apps Script Calendar Automation Infrastructure
# This file defines output values that provide important information
# about the created resources for verification and integration

# Project and Resource Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "resource_prefix" {
  description = "The prefix used for resource naming"
  value       = var.resource_prefix
}

output "random_suffix" {
  description = "The random suffix added to resource names for uniqueness"
  value       = random_id.suffix.hex
}

output "environment" {
  description = "The deployment environment"
  value       = var.environment
}

# Service Account Information
output "service_account_email" {
  description = "Email address of the service account created for automation"
  value       = google_service_account.apps_script_automation.email
}

output "service_account_id" {
  description = "The ID of the service account created for automation"
  value       = google_service_account.apps_script_automation.account_id
}

output "service_account_unique_id" {
  description = "The unique ID of the service account"
  value       = google_service_account.apps_script_automation.unique_id
}

# Storage and Automation Resources Information
output "automation_bucket_name" {
  description = "Name of the storage bucket containing automation resources"
  value       = google_storage_bucket.automation_resources.name
}

output "automation_bucket_url" {
  description = "URL of the storage bucket containing automation resources"
  value       = google_storage_bucket.automation_resources.url
}

output "automation_script_location" {
  description = "Location of the Apps Script automation code in storage"
  value       = "gs://${google_storage_bucket.automation_resources.name}/${google_storage_bucket_object.automation_script.name}"
}

output "deployment_instructions_file" {
  description = "Path to the local deployment instructions file"
  value       = local_file.deployment_instructions.filename
}

# Manual Setup Information (since these resources require manual creation)
output "manual_setup_required" {
  description = "Information about manual setup steps required"
  value = {
    google_sheet_required    = "Create manually at sheets.google.com with name: ${var.sheet_name}"
    apps_script_required     = "Create manually at script.google.com with name: ${var.apps_script_title}"
    sheet_headers_required   = "Title, Date, Start Time, End Time, Description, Location, Attendees"
    trigger_setup_required   = "Run createDailyTrigger() function in Apps Script"
  }
}

output "automation_configuration" {
  description = "Configuration settings for the automation"
  value = {
    trigger_execution_hour    = var.trigger_hour
    max_events_per_execution  = var.max_events_per_execution
    execution_timeout_seconds = var.execution_timeout_seconds
    enable_debug_logging      = var.enable_debug_logging
    dry_run_mode             = var.dry_run_mode
    apps_script_timezone     = var.apps_script_timezone
  }
}

# API Configuration
output "enabled_apis" {
  description = "List of Google APIs enabled for the project"
  value       = var.enable_apis
}

output "oauth_scopes" {
  description = "OAuth scopes configured for the Apps Script project"
  value       = var.oauth_scopes
}

# Monitoring and Logging Information
output "monitoring_alert_policy_id" {
  description = "ID of the monitoring alert policy for Apps Script failures"
  value       = google_monitoring_alert_policy.apps_script_failures.id
}

output "logging_sink_name" {
  description = "Name of the Cloud Logging sink for Apps Script logs"
  value       = google_logging_project_sink.apps_script_logs.name
}

output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for automation analytics"
  value       = google_bigquery_dataset.automation_analytics.dataset_id
}

output "monitoring_dashboard_url" {
  description = "URL to access the monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.automation_dashboard.id}?project=${var.project_id}"
}

# Notification Configuration
output "notification_email" {
  description = "Email address configured for notifications (if provided)"
  value       = var.notification_email != "" ? var.notification_email : "Using default user email"
  sensitive   = true
}

output "notification_channel_id" {
  description = "ID of the monitoring notification channel (if created)"
  value       = var.notification_email != "" ? google_monitoring_notification_channel.email_alerts[0].id : null
}

# Pub/Sub Information
output "monitoring_topic_name" {
  description = "Name of the Pub/Sub topic for monitoring events"
  value       = google_pubsub_topic.monitoring_events.name
}

output "monitoring_topic_id" {
  description = "Full resource ID of the monitoring Pub/Sub topic"
  value       = google_pubsub_topic.monitoring_events.id
}

# Configuration Summary
output "automation_configuration" {
  description = "Summary of automation configuration settings"
  value = {
    max_events_per_execution  = var.max_events_per_execution
    execution_timeout_seconds = var.execution_timeout_seconds
    enable_debug_logging      = var.enable_debug_logging
    create_sample_data        = var.create_sample_data
    dry_run_mode             = var.dry_run_mode
  }
}

# Quick Access URLs
output "quick_access_urls" {
  description = "Important URLs for quick access to resources"
  value = {
    google_sheets_create = "https://sheets.google.com"
    apps_script_create   = "https://script.google.com"
    storage_bucket      = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.automation_resources.name}?project=${var.project_id}"
    monitoring_dashboard = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.automation_dashboard.id}?project=${var.project_id}"
    logs               = "https://console.cloud.google.com/logs/query?project=${var.project_id}&query=resource.type%3D%22app_script_function%22"
    bigquery_dataset   = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.automation_analytics.dataset_id}"
  }
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployment"
  value = {
    terraform_version = ">=1.0"
    google_provider_version = "~>5.0"
    deployment_time = timestamp()
    resource_count = "15+ resources created"
  }
}

# Security Information
output "security_info" {
  description = "Security-related configuration information"
  value = {
    service_account_roles = var.service_account_roles
    oauth_scopes_count    = length(var.oauth_scopes)
    api_count            = length(var.enable_apis)
  }
  sensitive = true
}

# Cost Information
output "cost_estimate" {
  description = "Estimated monthly cost information"
  value = {
    apps_script_executions = "Free tier: 6 minutes per execution, 90 minutes per day"
    google_sheets         = "Free for personal use, included in Workspace"
    storage_bucket        = "Minimal cost for small files (<$1/month)"
    monitoring_alerts     = "Free tier: First 150 alert policies"
    bigquery_dataset      = "Free tier: 1 TB queries per month, 10 GB storage"
    pubsub_topic         = "Free tier: 10 GB messages per month"
    estimated_total       = "Typically free or <$2/month for small-scale usage"
  }
}

# Important Notes
output "important_notes" {
  description = "Important information about this deployment"
  value = {
    manual_setup_required = "Google Apps Script, Sheets, and Drive resources must be created manually due to OAuth requirements"
    automation_script_location = "Apps Script code is stored in the Cloud Storage bucket for reference"
    deployment_instructions = "Check the generated DEPLOYMENT_INSTRUCTIONS.md file for complete setup steps"
    monitoring_ready = "Monitoring infrastructure is created and ready for Apps Script integration"
  }
}