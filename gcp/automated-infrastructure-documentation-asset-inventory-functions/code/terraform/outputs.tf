# Outputs for GCP Asset Inventory Documentation Infrastructure

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "documentation_bucket_name" {
  description = "Name of the Cloud Storage bucket containing documentation"
  value       = google_storage_bucket.documentation_bucket.name
}

output "documentation_bucket_url" {
  description = "URL of the Cloud Storage bucket containing documentation"
  value       = "gs://${google_storage_bucket.documentation_bucket.name}"
}

output "documentation_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.documentation_bucket.self_link
}

output "cloud_function_name" {
  description = "Name of the Cloud Function that generates documentation"
  value       = google_cloudfunctions2_function.asset_doc_generator.name
}

output "cloud_function_url" {
  description = "URL of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.asset_doc_generator.service_config[0].uri
}

output "cloud_function_trigger_url" {
  description = "HTTP trigger URL for the Cloud Function"
  value       = "https://${var.region}-${var.project_id}.cloudfunctions.net/${google_cloudfunctions2_function.asset_doc_generator.name}"
}

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic that triggers documentation generation"
  value       = google_pubsub_topic.asset_inventory_trigger.name
}

output "pubsub_topic_id" {
  description = "ID of the Pub/Sub topic"
  value       = google_pubsub_topic.asset_inventory_trigger.id
}

output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for automated execution"
  value       = google_cloud_scheduler_job.daily_documentation.name
}

output "scheduler_job_schedule" {
  description = "Cron schedule for the automated documentation generation"
  value       = google_cloud_scheduler_job.daily_documentation.schedule
}

output "service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "service_account_id" {
  description = "ID of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.id
}

output "function_memory_allocation" {
  description = "Memory allocation for the Cloud Function (MB)"
  value       = var.function_memory
}

output "function_timeout" {
  description = "Timeout configuration for the Cloud Function (seconds)"
  value       = var.function_timeout
}

output "storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.documentation_bucket.location
}

output "storage_bucket_storage_class" {
  description = "Storage class of the documentation bucket"
  value       = google_storage_bucket.documentation_bucket.storage_class
}

output "log_sink_destination" {
  description = "Destination for Cloud Function logs"
  value       = google_logging_project_sink.function_logs.destination
}

output "log_sink_writer_identity" {
  description = "Writer identity for the log sink"
  value       = google_logging_project_sink.function_logs.writer_identity
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Output URLs for accessing generated documentation
output "html_report_url" {
  description = "URL to access the HTML infrastructure report"
  value       = "gs://${google_storage_bucket.documentation_bucket.name}/reports/infrastructure-report.html"
}

output "markdown_docs_url" {
  description = "URL to access the markdown documentation"
  value       = "gs://${google_storage_bucket.documentation_bucket.name}/reports/infrastructure-docs.md"
}

output "json_export_url" {
  description = "URL to access the JSON asset inventory export"
  value       = "gs://${google_storage_bucket.documentation_bucket.name}/exports/asset-inventory.json"
}

# Commands for manual testing and verification
output "manual_trigger_command" {
  description = "Command to manually trigger documentation generation"
  value       = "gcloud pubsub topics publish ${google_pubsub_topic.asset_inventory_trigger.name} --message='{\"trigger\":\"manual_test\"}'"
}

output "view_function_logs_command" {
  description = "Command to view Cloud Function logs"
  value       = "gcloud functions logs read ${google_cloudfunctions2_function.asset_doc_generator.name} --region=${var.region} --limit=10"
}

output "download_html_report_command" {
  description = "Command to download the HTML report locally"
  value       = "gsutil cp gs://${google_storage_bucket.documentation_bucket.name}/reports/infrastructure-report.html ./"
}

output "list_bucket_contents_command" {
  description = "Command to list all generated documentation files"
  value       = "gsutil ls -la gs://${google_storage_bucket.documentation_bucket.name}/**"
}

output "scheduler_job_status_command" {
  description = "Command to check the status of the scheduled job"
  value       = "gcloud scheduler jobs describe ${google_cloud_scheduler_job.daily_documentation.name} --location=${var.region}"
}