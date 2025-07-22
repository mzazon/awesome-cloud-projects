# Project and deployment information
output "project_id" {
  description = "The Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "deployment_id" {
  description = "Unique deployment identifier"
  value       = random_string.deployment_id.result
}

# Cloud Functions outputs
output "error_processor_function_name" {
  description = "Name of the error processor Cloud Function"
  value       = google_cloudfunctions_function.error_processor.name
}

output "error_processor_function_url" {
  description = "URL of the error processor Cloud Function"
  value       = google_cloudfunctions_function.error_processor.https_trigger_url
}

output "alert_router_function_name" {
  description = "Name of the alert router Cloud Function"
  value       = google_cloudfunctions_function.alert_router.name
}

output "debug_automation_function_name" {
  description = "Name of the debug automation Cloud Function"
  value       = google_cloudfunctions_function.debug_automation.name
}

output "sample_app_function_name" {
  description = "Name of the sample application Cloud Function"
  value       = var.deploy_sample_app ? google_cloudfunctions_function.sample_app[0].name : null
}

output "sample_app_function_url" {
  description = "URL of the sample application Cloud Function for testing"
  value       = var.deploy_sample_app ? google_cloudfunctions_function.sample_app[0].https_trigger_url : null
}

# Pub/Sub topics
output "error_notifications_topic" {
  description = "Name of the error notifications Pub/Sub topic"
  value       = google_pubsub_topic.error_notifications.name
}

output "alert_notifications_topic" {
  description = "Name of the alert notifications Pub/Sub topic"
  value       = google_pubsub_topic.alert_notifications.name
}

output "debug_automation_topic" {
  description = "Name of the debug automation Pub/Sub topic"
  value       = google_pubsub_topic.debug_automation.name
}

# Storage resources
output "debug_data_bucket_name" {
  description = "Name of the Cloud Storage bucket for debug data"
  value       = google_storage_bucket.debug_data.name
}

output "debug_data_bucket_url" {
  description = "URL of the Cloud Storage bucket for debug data"
  value       = google_storage_bucket.debug_data.url
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

# Firestore database
output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.error_tracking.name
}

output "firestore_database_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.error_tracking.location_id
}

# Monitoring resources
output "monitoring_dashboard_url" {
  description = "URL of the Cloud Monitoring dashboard"
  value       = var.enable_monitoring_dashboard ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.error_monitoring[0].id}?project=${var.project_id}" : null
}

output "log_sink_name" {
  description = "Name of the log sink for error events"
  value       = var.enable_error_log_sink ? google_logging_project_sink.error_sink[0].name : null
}

# Service accounts
output "error_processor_service_account" {
  description = "Email of the error processor service account"
  value       = var.create_service_accounts ? google_service_account.error_processor[0].email : null
}

output "alert_router_service_account" {
  description = "Email of the alert router service account"
  value       = var.create_service_accounts ? google_service_account.alert_router[0].email : null
}

output "debug_automation_service_account" {
  description = "Email of the debug automation service account"
  value       = var.create_service_accounts ? google_service_account.debug_automation[0].email : null
}

# Testing and validation outputs
output "test_commands" {
  description = "Commands to test the error monitoring system"
  value = {
    generate_critical_error = var.deploy_sample_app ? "curl -X POST '${google_cloudfunctions_function.sample_app[0].https_trigger_url}' -H 'Content-Type: application/json' -d '{\"error_type\": \"critical\"}'" : "Sample app not deployed"
    generate_database_error = var.deploy_sample_app ? "curl -X POST '${google_cloudfunctions_function.sample_app[0].https_trigger_url}' -H 'Content-Type: application/json' -d '{\"error_type\": \"database\"}'" : "Sample app not deployed"
    generate_random_errors  = var.deploy_sample_app ? "for i in {1..6}; do curl -X POST '${google_cloudfunctions_function.sample_app[0].https_trigger_url}' -H 'Content-Type: application/json' -d '{\"error_type\": \"random\"}'; sleep 2; done" : "Sample app not deployed"
  }
}

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_error_reporting    = "gcloud logging read 'resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions_function.error_processor.name}\"' --limit=10 --project=${var.project_id}"
    check_firestore_errors   = "gcloud firestore documents list errors --project=${var.project_id} --limit=5"
    check_debug_reports      = "gsutil ls gs://${google_storage_bucket.debug_data.name}/debug_reports/"
    view_monitoring_dashboard = var.enable_monitoring_dashboard ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.error_monitoring[0].id}?project=${var.project_id}" : "Dashboard not enabled"
  }
}

# Resource URLs for console access
output "console_urls" {
  description = "Google Cloud Console URLs for managing resources"
  value = {
    error_reporting      = "https://console.cloud.google.com/errors?project=${var.project_id}"
    cloud_functions      = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
    firestore           = "https://console.cloud.google.com/firestore/data?project=${var.project_id}"
    cloud_storage       = "https://console.cloud.google.com/storage/browser?project=${var.project_id}"
    cloud_monitoring    = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    cloud_logging       = "https://console.cloud.google.com/logs?project=${var.project_id}"
    pubsub             = "https://console.cloud.google.com/cloudpubsub?project=${var.project_id}"
  }
}

# Configuration summary
output "deployment_summary" {
  description = "Summary of deployed resources and configuration"
  value = {
    environment                    = var.environment
    resource_prefix               = var.resource_prefix
    deployment_id                 = random_string.deployment_id.result
    error_processor_memory        = var.error_processor_memory
    alert_router_memory           = var.alert_router_memory
    debug_automation_memory       = var.debug_automation_memory
    monitoring_dashboard_enabled  = var.enable_monitoring_dashboard
    sample_app_deployed          = var.deploy_sample_app
    service_accounts_created     = var.create_service_accounts
    log_sink_enabled            = var.enable_error_log_sink
    firestore_location          = var.firestore_location
    storage_bucket_location     = var.storage_bucket_location
  }
}