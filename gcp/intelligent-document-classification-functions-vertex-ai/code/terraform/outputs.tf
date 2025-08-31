# Outputs for GCP Intelligent Document Classification Infrastructure
# These outputs provide important information for verification and integration

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "resource_prefix" {
  description = "The prefix used for resource naming"
  value       = local.resource_name
}

# Cloud Storage Bucket Outputs
output "inbox_bucket_name" {
  description = "Name of the Cloud Storage bucket for document uploads"
  value       = google_storage_bucket.inbox_bucket.name
}

output "inbox_bucket_url" {
  description = "URL of the inbox bucket for document uploads"
  value       = google_storage_bucket.inbox_bucket.url
}

output "classified_bucket_name" {
  description = "Name of the Cloud Storage bucket for classified documents"
  value       = google_storage_bucket.classified_bucket.name
}

output "classified_bucket_url" {
  description = "URL of the classified bucket for organized documents"
  value       = google_storage_bucket.classified_bucket.url
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source_bucket.name
}

# Document Category Folders
output "document_categories" {
  description = "List of document categories configured for classification"
  value       = var.document_categories
}

output "classified_folder_urls" {
  description = "URLs for each document category folder in the classified bucket"
  value = {
    for category in var.document_categories :
    category => "gs://${google_storage_bucket.classified_bucket.name}/${category}/"
  }
}

# Cloud Function Outputs
output "function_name" {
  description = "Name of the Cloud Function handling document classification"
  value       = google_cloudfunctions2_function.document_classifier.name
}

output "function_url" {
  description = "URL of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.document_classifier.service_config[0].uri
}

output "function_trigger_bucket" {
  description = "Cloud Storage bucket that triggers the function"
  value       = google_storage_bucket.inbox_bucket.name
}

output "function_runtime" {
  description = "Runtime environment of the Cloud Function"
  value       = "python312"
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function"
  value       = "${var.function_memory}Mi"
}

output "function_timeout" {
  description = "Timeout setting for the Cloud Function"
  value       = "${var.function_timeout}s"
}

# Service Account Outputs
output "service_account_email" {
  description = "Email address of the service account used by Cloud Function"
  value       = google_service_account.function_sa.email
}

output "service_account_id" {
  description = "ID of the service account used by Cloud Function"
  value       = google_service_account.function_sa.account_id
}

# Vertex AI Configuration
output "vertex_ai_location" {
  description = "Location configured for Vertex AI operations"
  value       = var.vertex_ai_location
}

output "vertex_ai_model" {
  description = "Vertex AI model used for document classification"
  value       = "gemini-1.5-flash"
}

# Monitoring and Logging Outputs
output "logging_enabled" {
  description = "Whether Cloud Logging is enabled for the function"
  value       = var.enable_logging
}

output "monitoring_enabled" {
  description = "Whether Cloud Monitoring is enabled for the function"
  value       = var.enable_monitoring
}

output "log_retention_days" {
  description = "Number of days logs are retained"
  value       = var.log_retention_days
}

output "monitoring_dashboard_url" {
  description = "URL to the Cloud Monitoring dashboard (if enabled)"
  value = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.document_classification[0].id}?project=${var.project_id}" : null
}

# Pub/Sub Outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for classification events"
  value       = google_pubsub_topic.classification_events.name
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for classification events"
  value       = google_pubsub_subscription.classification_events.name
}

# Security and Configuration Outputs
output "uniform_bucket_level_access" {
  description = "Whether uniform bucket-level access is enabled"
  value       = var.enable_uniform_bucket_level_access
}

output "storage_class" {
  description = "Storage class used for Cloud Storage buckets"
  value       = var.storage_class
}

output "versioning_enabled" {
  description = "Whether versioning is enabled for Cloud Storage buckets"
  value       = var.enable_versioning
}

output "lifecycle_enabled" {
  description = "Whether lifecycle management is enabled for Cloud Storage buckets"
  value       = var.enable_lifecycle
}

# Resource Labels
output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# API Endpoints
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value = [
    "cloudfunctions.googleapis.com",
    "aiplatform.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "pubsub.googleapis.com"
  ]
}

# Cost Estimation Information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (approximation based on typical usage)"
  value = {
    cloud_function_invocations = "~$0.40 per 1M invocations"
    cloud_function_memory      = "~$0.25 per GB-second"
    vertex_ai_gemini_requests  = "~$0.50 per 1K requests"
    cloud_storage_standard     = "~$0.020 per GB per month"
    cloud_logging              = "~$0.50 per GB ingested"
    total_estimated_range      = "$8-15 per month for moderate usage"
  }
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the deployed document classification system"
  value = {
    upload_documents = "Upload documents to gs://${google_storage_bucket.inbox_bucket.name}/"
    view_classified  = "View classified documents at gs://${google_storage_bucket.classified_bucket.name}/"
    monitor_function = "Monitor function execution in Cloud Console Functions section"
    view_logs       = "View logs in Cloud Console Logging section with filter: resource.type=\"cloud_function\""
    testing_command = "gsutil cp your-document.txt gs://${google_storage_bucket.inbox_bucket.name}/"
  }
}

# Integration Information
output "integration_endpoints" {
  description = "Endpoints for integrating with external systems"
  value = {
    webhook_url        = google_cloudfunctions2_function.document_classifier.service_config[0].uri
    pubsub_topic       = "projects/${var.project_id}/topics/${google_pubsub_topic.classification_events.name}"
    pubsub_subscription = "projects/${var.project_id}/subscriptions/${google_pubsub_subscription.classification_events.name}"
    storage_notification_config = "Cloud Storage notifications configured for bucket: ${google_storage_bucket.inbox_bucket.name}"
  }
}

# Deployment Validation
output "deployment_status" {
  description = "Status of key deployment components"
  value = {
    inbox_bucket_created      = google_storage_bucket.inbox_bucket.name != "" ? "✅ Created" : "❌ Failed"
    classified_bucket_created = google_storage_bucket.classified_bucket.name != "" ? "✅ Created" : "❌ Failed"
    function_deployed        = google_cloudfunctions2_function.document_classifier.name != "" ? "✅ Deployed" : "❌ Failed"
    service_account_created  = google_service_account.function_sa.email != "" ? "✅ Created" : "❌ Failed"
    apis_enabled            = "✅ All required APIs enabled"
    trigger_configured      = "✅ Storage trigger configured"
  }
}