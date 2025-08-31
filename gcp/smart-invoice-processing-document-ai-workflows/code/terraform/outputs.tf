# Outputs for GCP Smart Invoice Processing Infrastructure
# These outputs provide essential information for system integration and verification

# Project and resource identification outputs
output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
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

output "resource_suffix" {
  description = "The unique suffix applied to resource names"
  value       = local.resource_suffix
}

# Cloud Storage bucket outputs
output "invoice_storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for invoice documents"
  value       = google_storage_bucket.invoice_storage.name
}

output "invoice_storage_bucket_url" {
  description = "URL of the Cloud Storage bucket for invoice documents"
  value       = google_storage_bucket.invoice_storage.url
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for Cloud Function source code"
  value       = google_storage_bucket.function_source.name
}

# Document AI processor outputs
output "document_ai_processor_id" {
  description = "ID of the Document AI processor for invoice parsing"
  value       = google_document_ai_processor.invoice_parser.name
}

output "document_ai_processor_display_name" {
  description = "Display name of the Document AI processor"
  value       = google_document_ai_processor.invoice_parser.display_name
}

output "document_ai_processor_type" {
  description = "Type of Document AI processor created"
  value       = google_document_ai_processor.invoice_parser.type
}

# Service account outputs
output "service_account_email" {
  description = "Email of the service account used for invoice processing"
  value       = google_service_account.invoice_processor.email
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.invoice_processor.unique_id
}

# Cloud Workflows outputs
output "workflow_name" {
  description = "Name of the Cloud Workflow for invoice processing"
  value       = google_workflows_workflow.invoice_processing.name
}

output "workflow_id" {
  description = "ID of the Cloud Workflow"
  value       = google_workflows_workflow.invoice_processing.id
}

output "workflow_revision_id" {
  description = "Revision ID of the deployed workflow"
  value       = google_workflows_workflow.invoice_processing.revision_id
}

# Cloud Tasks queue outputs
output "cloud_tasks_queue_name" {
  description = "Name of the Cloud Tasks queue for approval management"
  value       = google_cloud_tasks_queue.approval_queue.name
}

output "cloud_tasks_queue_id" {
  description = "ID of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.approval_queue.id
}

# Cloud Function outputs
output "notification_function_name" {
  description = "Name of the Cloud Function for email notifications"
  value       = google_cloudfunctions_function.notification_function.name
}

output "notification_function_url" {
  description = "HTTP trigger URL for the notification function"
  value       = google_cloudfunctions_function.notification_function.https_trigger_url
}

output "notification_function_source_archive" {
  description = "Cloud Storage location of the function source archive"
  value       = "${google_storage_bucket.function_source.name}/${google_storage_bucket_object.notification_function_zip.name}"
}

# Pub/Sub topic and subscription outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for invoice upload notifications"
  value       = google_pubsub_topic.invoice_uploads.name
}

output "pubsub_topic_id" {
  description = "ID of the Pub/Sub topic"
  value       = google_pubsub_topic.invoice_uploads.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for workflow triggering"
  value       = google_pubsub_subscription.invoice_processing.name
}

output "pubsub_subscription_id" {
  description = "ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.invoice_processing.id
}

output "pubsub_dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed message processing"
  value       = google_pubsub_topic.invoice_uploads_dead_letter.name
}

# Eventarc trigger outputs
output "eventarc_trigger_name" {
  description = "Name of the Eventarc trigger for automated workflow execution"
  value       = google_eventarc_trigger.invoice_upload_trigger.name
}

output "eventarc_trigger_id" {
  description = "ID of the Eventarc trigger"
  value       = google_eventarc_trigger.invoice_upload_trigger.id
}

# Configuration and settings outputs
output "approval_thresholds" {
  description = "Invoice amount thresholds for different approval levels"
  value = {
    manager   = var.approval_amount_thresholds.manager_threshold
    director  = var.approval_amount_thresholds.director_threshold
    executive = var.approval_amount_thresholds.executive_threshold
  }
}

output "notification_emails" {
  description = "Configured email addresses for approval notifications"
  value       = var.notification_emails
  sensitive   = true
}

# Monitoring outputs (conditional)
output "monitoring_dashboard_id" {
  description = "ID of the monitoring dashboard (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_dashboard.invoice_processing_dashboard[0].id : null
}

output "workflow_failure_alert_policy_id" {
  description = "ID of the workflow failure alert policy (if monitoring enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.workflow_failure_alert[0].name : null
}

output "workflow_failure_metric_name" {
  description = "Name of the log-based metric for workflow failures (if monitoring enabled)"
  value       = var.enable_monitoring ? google_logging_metric.workflow_failures[0].name : null
}

# API endpoints and URLs for integration
output "document_ai_endpoint" {
  description = "Document AI API endpoint for the processor"
  value       = "https://${var.region}-documentai.googleapis.com/v1/${google_document_ai_processor.invoice_parser.name}:process"
}

output "workflow_execution_endpoint" {
  description = "Cloud Workflows execution endpoint"
  value       = "https://workflowexecutions.googleapis.com/v1/${google_workflows_workflow.invoice_processing.id}/executions"
}

output "cloud_tasks_queue_path" {
  description = "Full resource path for the Cloud Tasks queue"
  value       = "projects/${var.project_id}/locations/${var.region}/queues/${local.task_queue_name}"
}

# Upload instructions and usage information
output "upload_instructions" {
  description = "Instructions for uploading invoices to trigger processing"
  value = {
    bucket_name    = google_storage_bucket.invoice_storage.name
    upload_folder  = "incoming/"
    upload_command = "gsutil cp your-invoice.pdf gs://${google_storage_bucket.invoice_storage.name}/incoming/"
    console_url    = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.invoice_storage.name}/incoming"
  }
}

# System status and health check URLs
output "system_health_check_urls" {
  description = "URLs for checking system component health and status"
  value = {
    workflow_console     = "https://console.cloud.google.com/workflows/workflow/${var.region}/${local.workflow_name}"
    function_console     = "https://console.cloud.google.com/functions/details/${var.region}/${local.function_name}"
    storage_console      = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.invoice_storage.name}"
    document_ai_console  = "https://console.cloud.google.com/ai/document-ai/processors"
    cloud_tasks_console  = "https://console.cloud.google.com/cloudtasks/queue/${var.region}/${local.task_queue_name}"
    pubsub_console       = "https://console.cloud.google.com/cloudpubsub/topic/list"
    logs_console         = "https://console.cloud.google.com/logs/query"
  }
}

# Cost optimization information
output "cost_optimization_info" {
  description = "Information about cost optimization features enabled"
  value = {
    bucket_storage_class    = var.bucket_storage_class
    lifecycle_age_days      = var.bucket_lifecycle_age_days
    function_memory_mb      = var.cloud_function_memory_mb
    function_timeout_seconds = var.cloud_function_timeout_seconds
    bucket_versioning       = var.enable_bucket_versioning
  }
}

# Security configuration summary
output "security_configuration" {
  description = "Summary of security configuration applied"
  value = {
    uniform_bucket_access = true
    service_account_email = google_service_account.invoice_processor.email
    audit_logging_enabled = var.enable_audit_logging
    iam_roles_assigned = [
      "roles/documentai.apiUser",
      "roles/storage.objectAdmin", 
      "roles/cloudtasks.enqueuer",
      "roles/workflows.invoker",
      "roles/cloudfunctions.invoker",
      "roles/pubsub.publisher",
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter"
    ]
  }
}