# Output Values for Workflow Automation Infrastructure
# This file defines the outputs that will be displayed after successful deployment

output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Storage Resources
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for document processing"
  value       = google_storage_bucket.workflow_documents.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket for document processing"
  value       = google_storage_bucket.workflow_documents.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.workflow_documents.self_link
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

# Pub/Sub Resources
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for document events"
  value       = google_pubsub_topic.document_events.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.document_events.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for document processing"
  value       = google_pubsub_subscription.document_processing.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.document_processing.id
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic (if enabled)"
  value       = var.enable_dead_letter ? google_pubsub_topic.dead_letter[0].name : null
}

output "dead_letter_subscription_name" {
  description = "Name of the dead letter subscription (if enabled)"
  value       = var.enable_dead_letter ? google_pubsub_subscription.dead_letter_subscription[0].name : null
}

# Cloud Function Resources
output "document_processor_function_name" {
  description = "Name of the document processing Cloud Function"
  value       = google_cloudfunctions_function.document_processor.name
}

output "document_processor_function_url" {
  description = "HTTPS trigger URL for the document processing function"
  value       = google_cloudfunctions_function.document_processor.https_trigger_url
}

output "document_processor_function_source_archive_url" {
  description = "Source archive URL for the document processing function"
  value       = google_cloudfunctions_function.document_processor.source_archive_url
}

output "approval_webhook_function_name" {
  description = "Name of the approval webhook Cloud Function"
  value       = google_cloudfunctions_function.approval_webhook.name
}

output "approval_webhook_function_url" {
  description = "HTTPS trigger URL for the approval webhook function"
  value       = google_cloudfunctions_function.approval_webhook.https_trigger_url
}

output "chat_notifications_function_name" {
  description = "Name of the chat notifications Cloud Function"
  value       = google_cloudfunctions_function.chat_notifications.name
}

output "chat_notifications_function_url" {
  description = "HTTPS trigger URL for the chat notifications function"
  value       = google_cloudfunctions_function.chat_notifications.https_trigger_url
}

output "analytics_collector_function_name" {
  description = "Name of the analytics collector Cloud Function"
  value       = google_cloudfunctions_function.analytics_collector.name
}

# Service Account Resources
output "service_account_email" {
  description = "Email address of the workflow service account"
  value       = google_service_account.workflow_service_account.email
}

output "service_account_name" {
  description = "Name of the workflow service account"
  value       = google_service_account.workflow_service_account.name
}

output "service_account_unique_id" {
  description = "Unique ID of the workflow service account"
  value       = google_service_account.workflow_service_account.unique_id
}

# Monitoring and Logging Resources
output "monitoring_dashboard_id" {
  description = "ID of the monitoring dashboard (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_dashboard.workflow_dashboard[0].id : null
}

output "log_sink_name" {
  description = "Name of the log sink (if enabled)"
  value       = var.enable_logging ? google_logging_project_sink.workflow_logs[0].name : null
}

output "log_sink_writer_identity" {
  description = "Writer identity for the log sink (if enabled)"
  value       = var.enable_logging ? google_logging_project_sink.workflow_logs[0].writer_identity : null
}

# Configuration Values for Integration
output "environment_variables" {
  description = "Environment variables for manual function configuration"
  value = {
    TOPIC_NAME   = local.topic_name
    BUCKET_NAME  = local.bucket_name
    PROJECT_ID   = var.project_id
    ENVIRONMENT  = var.environment
    REGION       = var.region
  }
}

output "workspace_flows_configuration" {
  description = "Configuration template for Google Workspace Flows integration"
  value = {
    http_endpoint_url = google_cloudfunctions_function.document_processor.https_trigger_url
    webhook_url       = google_cloudfunctions_function.approval_webhook.https_trigger_url
    notification_url  = google_cloudfunctions_function.chat_notifications.https_trigger_url
    bucket_name       = google_storage_bucket.workflow_documents.name
    topic_name        = google_pubsub_topic.document_events.name
  }
}

# curl commands for testing
output "test_commands" {
  description = "Sample curl commands for testing the deployed functions"
  value = {
    test_document_processor = "curl -X POST '${google_cloudfunctions_function.document_processor.https_trigger_url}' -H 'Content-Type: application/json' -d '{\"fileName\":\"test-document.pdf\",\"bucketName\":\"${google_storage_bucket.workflow_documents.name}\",\"metadata\":{\"document_type\":\"invoice\",\"department\":\"finance\",\"priority\":\"high\"}}'"
    
    test_approval_webhook = "curl -X POST '${google_cloudfunctions_function.approval_webhook.https_trigger_url}' -H 'Content-Type: application/json' -d '{\"workflowId\":\"test-workflow-123\",\"approverEmail\":\"test@company.com\",\"decision\":\"approved\",\"comments\":\"Document reviewed and approved\"}'"
    
    test_chat_notifications = "curl -X POST '${google_cloudfunctions_function.chat_notifications.https_trigger_url}' -H 'Content-Type: application/json' -d '{\"message\":\"Test workflow notification\",\"spaceId\":\"SPACE_ID\",\"threadKey\":\"thread-123\"}'"
  }
}

# Summary of deployed resources
output "deployment_summary" {
  description = "Summary of all deployed resources"
  value = {
    storage_buckets = [
      google_storage_bucket.workflow_documents.name,
      google_storage_bucket.function_source.name
    ]
    cloud_functions = [
      google_cloudfunctions_function.document_processor.name,
      google_cloudfunctions_function.approval_webhook.name,
      google_cloudfunctions_function.chat_notifications.name,
      google_cloudfunctions_function.analytics_collector.name
    ]
    pubsub_topics = concat(
      [google_pubsub_topic.document_events.name],
      var.enable_dead_letter ? [google_pubsub_topic.dead_letter[0].name] : []
    )
    pubsub_subscriptions = concat(
      [google_pubsub_subscription.document_processing.name],
      var.enable_dead_letter ? [google_pubsub_subscription.dead_letter_subscription[0].name] : []
    )
    service_accounts = [google_service_account.workflow_service_account.email]
    apis_enabled = var.enable_apis
  }
}

# Next steps for configuration
output "next_steps" {
  description = "Next steps to complete the workflow automation setup"
  value = [
    "1. Configure Google Workspace Flows using the provided HTTP endpoint URLs",
    "2. Set up authentication for Google Workspace APIs in the service account",
    "3. Create Google Sheets for workflow tracking and update spreadsheet IDs in functions",
    "4. Configure Google Chat spaces and update space IDs for notifications",
    "5. Test document upload to the storage bucket to trigger the workflow",
    "6. Monitor function logs and metrics using Cloud Monitoring dashboard",
    "7. Customize business rules in the WebAssembly plugins as needed",
    "8. Set up alerting policies for workflow failures and performance issues"
  ]
}

# Cost optimization recommendations
output "cost_optimization_tips" {
  description = "Recommendations for optimizing costs"
  value = [
    "Monitor Cloud Function execution time and memory usage to optimize allocations",
    "Review storage lifecycle policies and adjust retention periods as needed",
    "Use Pub/Sub dead letter queues to handle failed messages efficiently",
    "Consider using Cloud Run for longer-running processing workloads",
    "Monitor API usage and implement rate limiting if necessary",
    "Use Cloud Monitoring to identify unused or underutilized resources"
  ]
}