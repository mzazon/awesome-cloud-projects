# Outputs for Multi-Language Content Localization Pipeline
# These outputs provide essential information for integration and monitoring

# Project and Regional Information
output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming to ensure uniqueness"
  value       = random_id.suffix.hex
}

# Storage Configuration
output "source_bucket_name" {
  description = "Name of the Cloud Storage bucket for source content uploads"
  value       = google_storage_bucket.source_content.name
}

output "source_bucket_url" {
  description = "URL of the source content bucket"
  value       = google_storage_bucket.source_content.url
}

output "translated_bucket_name" {
  description = "Name of the Cloud Storage bucket for translated content"
  value       = google_storage_bucket.translated_content.name
}

output "translated_bucket_url" {
  description = "URL of the translated content bucket"
  value       = google_storage_bucket.translated_content.url
}

# Pub/Sub Configuration
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for translation workflow events"
  value       = google_pubsub_topic.translation_workflow.name
}

output "pubsub_topic_id" {
  description = "Full ID of the Pub/Sub topic"
  value       = google_pubsub_topic.translation_workflow.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for the translation processor"
  value       = google_pubsub_subscription.translation_processor.name
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter queue topic for failed messages"
  value       = google_pubsub_topic.translation_dlq.name
}

# Cloud Function Configuration
output "function_name" {
  description = "Name of the Cloud Function handling translation processing"
  value       = google_cloudfunctions2_function.translation_processor.name
}

output "function_url" {
  description = "URL of the Cloud Function (for HTTP triggers if configured)"
  value       = google_cloudfunctions2_function.translation_processor.service_config[0].uri
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.translation_pipeline.email
}

# Cloud Scheduler Configuration
output "batch_scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for batch processing"
  value       = google_cloud_scheduler_job.batch_translation.name
}

output "health_monitor_job_name" {
  description = "Name of the Cloud Scheduler job for health monitoring"
  value       = google_cloud_scheduler_job.health_monitor.name
}

output "batch_schedule" {
  description = "Cron schedule for batch translation processing"
  value       = var.batch_schedule
}

# Service Account Information
output "service_account_name" {
  description = "Name of the service account for the translation pipeline"
  value       = google_service_account.translation_pipeline.name
}

output "service_account_email" {
  description = "Email address of the translation pipeline service account"
  value       = google_service_account.translation_pipeline.email
}

output "service_account_unique_id" {
  description = "Unique ID of the translation pipeline service account"
  value       = google_service_account.translation_pipeline.unique_id
}

# Translation Configuration
output "target_languages" {
  description = "List of target languages configured for translation"
  value       = local.target_languages
}

output "supported_file_types" {
  description = "List of supported file types for translation"
  value       = var.supported_file_types
}

# Logging and Monitoring
output "audit_log_sink_name" {
  description = "Name of the Cloud Logging sink for audit trail"
  value       = google_logging_project_sink.translation_audit.name
}

output "audit_log_destination" {
  description = "Destination for audit logs"
  value       = google_logging_project_sink.translation_audit.destination
}

output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard (if enabled)"
  value       = var.enable_monitoring_dashboard ? google_monitoring_dashboard.translation_pipeline[0].id : null
}

# API Configuration
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this project"
  value = [
    for api in google_project_service.required_apis : api.service
  ]
}

# Network Configuration
output "vpc_connector" {
  description = "VPC Connector used by Cloud Functions (if configured)"
  value       = var.vpc_connector
}

# Security Information
output "bucket_encryption_type" {
  description = "Encryption type used for storage buckets"
  value       = var.bucket_encryption_key != null ? "Customer-managed" : "Google-managed"
}

output "uniform_bucket_level_access" {
  description = "Whether uniform bucket-level access is enabled"
  value       = var.enable_uniform_bucket_access
}

output "public_access_prevention" {
  description = "Whether public access prevention is enabled"
  value       = var.enable_public_access_prevention
}

# Cost and Performance Information
output "function_memory_allocation" {
  description = "Memory allocation for the Cloud Function"
  value       = var.function_memory
}

output "function_cpu_allocation" {
  description = "CPU allocation for the Cloud Function"
  value       = var.function_cpu
}

output "function_timeout_seconds" {
  description = "Timeout configuration for the Cloud Function"
  value       = var.function_timeout_seconds
}

output "function_max_instances" {
  description = "Maximum number of Cloud Function instances"
  value       = var.function_max_instances
}

output "function_min_instances" {
  description = "Minimum number of Cloud Function instances"
  value       = var.function_min_instances
}

# Storage Lifecycle Information
output "storage_lifecycle_coldline_age" {
  description = "Age in days for transitioning objects to Coldline storage"
  value       = var.storage_lifecycle_age_coldline
}

output "storage_lifecycle_delete_age" {
  description = "Age in days for deleting objects (0 if deletion is disabled)"
  value       = var.storage_lifecycle_age_delete
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Instructions for using the deployed translation pipeline"
  value = {
    upload_content = "Upload content files to: gs://${google_storage_bucket.source_content.name}/"
    view_translations = "View translated content at: gs://${google_storage_bucket.translated_content.name}/"
    monitor_logs = "View function logs: gcloud functions logs read ${google_cloudfunctions2_function.translation_processor.name} --region=${var.region}"
    manual_trigger = "Manually trigger batch processing: gcloud scheduler jobs run ${google_cloud_scheduler_job.batch_translation.name} --location=${var.region}"
    health_check = "Check system health: gcloud scheduler jobs run ${google_cloud_scheduler_job.health_monitor.name} --location=${var.region}"
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Useful commands for getting started with the translation pipeline"
  value = {
    test_upload = "echo 'Hello, world!' | gsutil cp - gs://${google_storage_bucket.source_content.name}/test.txt"
    list_translations = "gsutil ls -r gs://${google_storage_bucket.translated_content.name}/"
    view_pubsub_messages = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.translation_processor.name} --auto-ack --limit=10"
    check_function_status = "gcloud functions describe ${google_cloudfunctions2_function.translation_processor.name} --region=${var.region}"
    view_scheduler_jobs = "gcloud scheduler jobs list --location=${var.region}"
  }
}

# Resource URLs for Console Access
output "console_urls" {
  description = "Google Cloud Console URLs for monitoring and management"
  value = {
    source_bucket = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.source_content.name}"
    translated_bucket = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.translated_content.name}"
    cloud_function = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.translation_processor.name}"
    pubsub_topic = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.translation_workflow.name}"
    scheduler_jobs = "https://console.cloud.google.com/cloudscheduler"
    logs = "https://console.cloud.google.com/logs/query"
    monitoring = var.enable_monitoring_dashboard ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.translation_pipeline[0].id}" : null
  }
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    environment = var.environment
    region = var.region
    target_languages = length(var.custom_target_languages) > 0 ? var.custom_target_languages : local.target_languages
    batch_schedule = var.batch_schedule
    monitoring_enabled = var.enable_monitoring_dashboard
    alerting_enabled = var.enable_alerting
    vpc_connector_enabled = var.vpc_connector != null
    custom_encryption_enabled = var.bucket_encryption_key != null
    autoclass_enabled = var.enable_autoclass
  }
}