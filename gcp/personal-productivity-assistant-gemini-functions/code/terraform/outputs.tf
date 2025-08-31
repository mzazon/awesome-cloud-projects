# Outputs for GCP Personal Productivity Assistant with Gemini and Functions
# These outputs provide essential information for connecting to and using the deployed infrastructure

# Project Information
output "project_id" {
  description = "The Google Cloud Project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

# Cloud Functions
output "email_processor_function_name" {
  description = "Name of the email processing Cloud Function"
  value       = google_cloudfunctions_function.email_processor.name
}

output "email_processor_function_url" {
  description = "HTTPS URL of the email processing Cloud Function"
  value       = google_cloudfunctions_function.email_processor.https_trigger_url
  sensitive   = false
}

output "email_processor_function_source_bucket" {
  description = "Cloud Storage bucket containing the email processor function source"
  value       = google_storage_bucket.function_source.name
}

output "scheduled_processor_function_name" {
  description = "Name of the scheduled email processing Cloud Function"
  value       = google_cloudfunctions_function.scheduled_processor.name
}

# Service Account
output "function_service_account_email" {
  description = "Email address of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.email
}

output "function_service_account_id" {
  description = "Unique ID of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.unique_id
}

# Pub/Sub Resources
output "email_processing_topic_name" {
  description = "Name of the Pub/Sub topic for email processing"
  value       = google_pubsub_topic.email_processing.name
}

output "email_processing_topic_id" {
  description = "Full resource ID of the email processing Pub/Sub topic"
  value       = google_pubsub_topic.email_processing.id
}

output "email_processing_subscription_name" {
  description = "Name of the Pub/Sub subscription for email processing"
  value       = google_pubsub_subscription.email_processing.name
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter Pub/Sub topic"
  value       = google_pubsub_topic.dead_letter.name
}

# Cloud Scheduler
output "email_processing_schedule_name" {
  description = "Name of the Cloud Scheduler job for automated email processing"
  value       = google_cloud_scheduler_job.email_processing_schedule.name
}

output "email_processing_schedule_cron" {
  description = "Cron expression for the automated email processing schedule"
  value       = google_cloud_scheduler_job.email_processing_schedule.schedule
}

output "email_processing_schedule_timezone" {
  description = "Timezone for the automated email processing schedule"
  value       = google_cloud_scheduler_job.email_processing_schedule.time_zone
}

# Firestore Database
output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.productivity_db.name
}

output "firestore_database_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.productivity_db.location_id
}

output "firestore_database_type" {
  description = "Type of the Firestore database"
  value       = google_firestore_database.productivity_db.type
}

# Cloud Storage
output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.url
}

# Monitoring (if enabled)
output "monitoring_dashboard_url" {
  description = "URL to the Cloud Monitoring dashboard (if monitoring is enabled)"
  value = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.productivity_dashboard[0].id}?project=${var.project_id}" : null
}

output "alert_policy_name" {
  description = "Name of the monitoring alert policy (if monitoring is enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_error_rate[0].display_name : null
}

# Security Policy (if enabled)
output "security_policy_name" {
  description = "Name of the Cloud Armor security policy (if enabled)"
  value       = var.enable_security_policy ? google_compute_security_policy.productivity_security_policy[0].name : null
}

# API Configuration
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this project"
  value       = [for api in google_project_service.apis : api.service]
}

# Gmail API Integration Information
output "gmail_api_scopes" {
  description = "OAuth scopes required for Gmail API integration"
  value       = var.gmail_api_scopes
}

output "oauth_consent_screen_url" {
  description = "URL to configure OAuth consent screen for Gmail API access"
  value       = "https://console.cloud.google.com/apis/credentials/consent?project=${var.project_id}"
}

output "oauth_credentials_url" {
  description = "URL to create OAuth 2.0 credentials for Gmail API access"
  value       = "https://console.cloud.google.com/apis/credentials?project=${var.project_id}"
}

# Function Configuration Details
output "email_processor_memory_allocation" {
  description = "Memory allocation for the email processing function (MB)"
  value       = google_cloudfunctions_function.email_processor.available_memory_mb
}

output "email_processor_timeout" {
  description = "Timeout configuration for the email processing function (seconds)"
  value       = google_cloudfunctions_function.email_processor.timeout
}

output "email_processor_max_instances" {
  description = "Maximum instances configuration for the email processing function"
  value       = google_cloudfunctions_function.email_processor.max_instances
}

# Vertex AI Configuration
output "vertex_ai_region" {
  description = "Region configured for Vertex AI services"
  value       = var.vertex_ai_region != "" ? var.vertex_ai_region : var.region
}

output "gemini_model_configuration" {
  description = "Configuration details for the Gemini model"
  value = {
    model_name        = var.gemini_model_name
    temperature       = var.gemini_temperature
    top_p            = var.gemini_top_p
    max_output_tokens = var.gemini_max_output_tokens
  }
}

# Network and Security Information
output "function_ingress_settings" {
  description = "Ingress settings for the Cloud Functions"
  value       = google_cloudfunctions_function.email_processor.ingress_settings
}

output "https_trigger_security_level" {
  description = "Security level for HTTPS triggers"
  value       = "SECURE_ALWAYS"
}

# Cost Information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (approximate, based on moderate usage)"
  value = {
    cloud_functions = "5-15"
    vertex_ai      = "10-30"
    firestore      = "1-5"
    pubsub         = "1-3"
    storage        = "1-2"
    monitoring     = "0-2"
    total_range    = "18-57"
    note          = "Actual costs depend on usage patterns, API call frequency, and data volume"
  }
}

# Testing and Validation
output "function_test_command" {
  description = "curl command to test the email processing function"
  value = "curl -X POST ${google_cloudfunctions_function.email_processor.https_trigger_url} -H 'Content-Type: application/json' -d '{\"email_id\":\"test-123\",\"subject\":\"Test Email\",\"sender\":\"test@example.com\",\"body\":\"This is a test email for the productivity assistant.\"}'"
}

output "firestore_collections" {
  description = "Expected Firestore collections created by the application"
  value = [
    "email_analysis",
    "scheduled_runs"
  ]
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp of when this infrastructure was deployed"
  value       = timestamp()
}

output "terraform_workspace" {
  description = "Terraform workspace used for this deployment"
  value       = terraform.workspace
}

# Resource Naming Information
output "resource_name_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "common_resource_labels" {
  description = "Common labels applied to all resources"
  value = {
    project     = "personal-productivity-assistant"
    environment = var.environment
    managed-by  = "terraform"
    recipe-id   = "b4f7e2a8"
  }
}

# Troubleshooting Information
output "function_logs_command" {
  description = "gcloud command to view function logs"
  value       = "gcloud functions logs read ${google_cloudfunctions_function.email_processor.name} --region=${var.region} --limit=50"
}

output "scheduler_logs_command" {
  description = "gcloud command to view scheduler logs"
  value       = "gcloud logging read 'resource.type=\"cloud_scheduler_job\" AND resource.labels.job_id=\"${google_cloud_scheduler_job.email_processing_schedule.name}\"' --limit=50"
}

output "pubsub_monitoring_command" {
  description = "gcloud command to monitor Pub/Sub topic"
  value       = "gcloud pubsub topics describe ${google_pubsub_topic.email_processing.name}"
}

# Integration Endpoints
output "integration_endpoints" {
  description = "Key endpoints and URIs for system integration"
  value = {
    email_processor_url = google_cloudfunctions_function.email_processor.https_trigger_url
    pubsub_topic_uri   = google_pubsub_topic.email_processing.id
    firestore_database = "(default)"
    storage_bucket_uri = google_storage_bucket.function_source.url
  }
}

# Quick Start Information
output "quick_start_guide" {
  description = "Quick start information for using the deployed system"
  value = {
    step_1 = "Configure OAuth 2.0 credentials at: https://console.cloud.google.com/apis/credentials?project=${var.project_id}"
    step_2 = "Test the function using the provided curl command in 'function_test_command' output"
    step_3 = "Monitor function execution using Cloud Monitoring at: https://console.cloud.google.com/monitoring?project=${var.project_id}"
    step_4 = "View processed emails in Firestore at: https://console.cloud.google.com/firestore?project=${var.project_id}"
    step_5 = "Check scheduled job status at: https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
  }
}