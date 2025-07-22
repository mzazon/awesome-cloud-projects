# Project and Resource Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
  sensitive   = false
}

# Document AI Resources
output "document_ai_processor_id" {
  description = "The ID of the Document AI processor"
  value       = google_document_ai_processor.form_parser.name
}

output "document_ai_processor_display_name" {
  description = "The display name of the Document AI processor"
  value       = google_document_ai_processor.form_parser.display_name
}

output "document_ai_processor_type" {
  description = "The type of the Document AI processor"
  value       = google_document_ai_processor.form_parser.type
}

output "document_ai_processor_location" {
  description = "The location of the Document AI processor"
  value       = google_document_ai_processor.form_parser.location
}

# Cloud Storage Resources
output "documents_bucket_name" {
  description = "Name of the Cloud Storage bucket for document uploads"
  value       = google_storage_bucket.documents.name
}

output "documents_bucket_url" {
  description = "URL of the Cloud Storage bucket for document uploads"
  value       = google_storage_bucket.documents.url
}

output "documents_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.documents.self_link
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

# Pub/Sub Resources
output "document_events_topic_name" {
  description = "Name of the Pub/Sub topic for document events"
  value       = google_pubsub_topic.document_events.name
}

output "document_events_topic_id" {
  description = "ID of the Pub/Sub topic for document events"
  value       = google_pubsub_topic.document_events.id
}

output "document_results_topic_name" {
  description = "Name of the Pub/Sub topic for processing results"
  value       = google_pubsub_topic.document_results.name
}

output "document_results_topic_id" {
  description = "ID of the Pub/Sub topic for processing results"
  value       = google_pubsub_topic.document_results.id
}

output "processing_subscription_name" {
  description = "Name of the Pub/Sub subscription for document processing"
  value       = google_pubsub_subscription.process_documents.name
}

output "results_subscription_name" {
  description = "Name of the Pub/Sub subscription for consuming results"
  value       = google_pubsub_subscription.consume_results.name
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed processing"
  value       = google_pubsub_topic.document_events_dlq.name
}

# Cloud Functions Resources
output "process_document_function_name" {
  description = "Name of the document processing Cloud Function"
  value       = google_cloudfunctions2_function.process_document.name
}

output "process_document_function_url" {
  description = "URL of the document processing Cloud Function"
  value       = google_cloudfunctions2_function.process_document.service_config[0].uri
}

output "consume_results_function_name" {
  description = "Name of the results consumer Cloud Function"
  value       = google_cloudfunctions2_function.consume_results.name
}

output "consume_results_function_url" {
  description = "URL of the results consumer Cloud Function"
  value       = google_cloudfunctions2_function.consume_results.service_config[0].uri
}

# Service Account Information
output "function_service_account_email" {
  description = "Email of the service account used by Cloud Functions"
  value       = google_service_account.function_service_account.email
}

output "function_service_account_id" {
  description = "ID of the service account used by Cloud Functions"
  value       = google_service_account.function_service_account.account_id
}

# Firestore Database Information
output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.processed_documents.name
}

output "firestore_database_type" {
  description = "Type of the Firestore database"
  value       = google_firestore_database.processed_documents.type
}

output "firestore_location_id" {
  description = "Location ID of the Firestore database"
  value       = google_firestore_database.processed_documents.location_id
}

# Testing and Usage Information
output "upload_command" {
  description = "Command to upload a test document to the bucket"
  value       = "gsutil cp <your-document> gs://${google_storage_bucket.documents.name}/"
}

output "list_documents_command" {
  description = "Command to list documents in the bucket"
  value       = "gsutil ls gs://${google_storage_bucket.documents.name}/"
}

output "view_processing_logs_command" {
  description = "Command to view document processing function logs"
  value       = "gcloud functions logs read ${google_cloudfunctions2_function.process_document.name} --region=${var.region} --limit=10"
}

output "view_consumer_logs_command" {
  description = "Command to view results consumer function logs"
  value       = "gcloud functions logs read ${google_cloudfunctions2_function.consume_results.name} --region=${var.region} --limit=10"
}

output "pull_results_command" {
  description = "Command to manually pull results from the subscription"
  value       = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.consume_results.name} --auto-ack --limit=5"
}

# Monitoring and Management URLs
output "cloud_console_storage_url" {
  description = "URL to view the Cloud Storage bucket in the console"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.documents.name}?project=${var.project_id}"
}

output "cloud_console_pubsub_url" {
  description = "URL to view Pub/Sub topics in the console"
  value       = "https://console.cloud.google.com/cloudpubsub/topic/list?project=${var.project_id}"
}

output "cloud_console_functions_url" {
  description = "URL to view Cloud Functions in the console"
  value       = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
}

output "cloud_console_documentai_url" {
  description = "URL to view Document AI processors in the console"
  value       = "https://console.cloud.google.com/ai/document-ai/processors?project=${var.project_id}"
}

output "cloud_console_firestore_url" {
  description = "URL to view Firestore database in the console"
  value       = "https://console.cloud.google.com/firestore/data?project=${var.project_id}"
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    project_id                    = var.project_id
    region                       = var.region
    location                     = var.location
    documents_bucket             = google_storage_bucket.documents.name
    document_events_topic        = google_pubsub_topic.document_events.name
    document_results_topic       = google_pubsub_topic.document_results.name
    processing_function          = google_cloudfunctions2_function.process_document.name
    consumer_function            = google_cloudfunctions2_function.consume_results.name
    document_ai_processor        = google_document_ai_processor.form_parser.name
    firestore_database          = google_firestore_database.processed_documents.name
    service_account             = google_service_account.function_service_account.email
    function_memory_mb          = var.processing_function_memory
    function_timeout_seconds    = var.processing_function_timeout
    max_function_instances      = var.function_max_instances
    bucket_versioning_enabled   = var.enable_bucket_versioning
    bucket_lifecycle_age_days   = var.bucket_lifecycle_age
  }
}

# Cost Estimation Information
output "cost_estimation_notes" {
  description = "Notes about potential costs for this deployment"
  value = <<-EOT
    Estimated monthly costs (assuming moderate usage):
    - Document AI: $0.50-2.00 per 1000 pages processed
    - Cloud Storage: $0.02 per GB stored (${var.storage_class} class)
    - Pub/Sub: $0.04 per million messages
    - Cloud Functions: $0.0000024 per 100ms of execution time
    - Firestore: $0.108 per 100k reads, $0.108 per 100k writes
    
    Actual costs depend on usage patterns and data volumes.
    Monitor usage through Cloud Billing for accurate cost tracking.
  EOT
}

# Security and Access Information
output "security_notes" {
  description = "Important security configuration notes"
  value = <<-EOT
    Security Configuration:
    - Uniform bucket-level access: ${var.enable_uniform_bucket_level_access}
    - Public access prevention: ${var.enable_public_access_prevention}
    - Service account with least privilege principles
    - Firestore with native mode for enhanced security
    - Point-in-time recovery enabled for Firestore
    
    Recommended additional security measures:
    - Enable VPC Service Controls for network isolation
    - Configure Cloud DLP for sensitive data detection
    - Implement custom IAM roles for fine-grained access
    - Enable audit logging for compliance tracking
  EOT
}