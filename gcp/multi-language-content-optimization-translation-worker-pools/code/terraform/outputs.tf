# Outputs for multi-language content optimization infrastructure

# Project and Region Information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were created"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource names to ensure uniqueness"
  value       = local.resource_suffix
}

# Storage Resources
output "source_bucket_name" {
  description = "Name of the Cloud Storage bucket for source content"
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

output "models_bucket_name" {
  description = "Name of the Cloud Storage bucket for custom translation models"
  value       = google_storage_bucket.custom_models.name
}

output "models_bucket_url" {
  description = "URL of the custom models bucket"
  value       = google_storage_bucket.custom_models.url
}

# Pub/Sub Resources
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for content processing events"
  value       = google_pubsub_topic.content_processing.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.content_processing.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for worker pool"
  value       = google_pubsub_subscription.worker_subscription.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.worker_subscription.id
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed messages"
  value       = google_pubsub_topic.dead_letter.name
}

output "dead_letter_subscription_name" {
  description = "Name of the dead letter subscription"
  value       = google_pubsub_subscription.dead_letter_subscription.name
}

# BigQuery Resources
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for analytics"
  value       = google_bigquery_dataset.content_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.content_analytics.location
}

output "engagement_metrics_table_id" {
  description = "Full table ID for engagement metrics table"
  value       = "${google_bigquery_dataset.content_analytics.project}.${google_bigquery_dataset.content_analytics.dataset_id}.${google_bigquery_table.engagement_metrics.table_id}"
}

output "translation_performance_table_id" {
  description = "Full table ID for translation performance table"
  value       = "${google_bigquery_dataset.content_analytics.project}.${google_bigquery_dataset.content_analytics.dataset_id}.${google_bigquery_table.translation_performance.table_id}"
}

# IAM Resources
output "service_account_email" {
  description = "Email address of the translation worker service account"
  value       = google_service_account.translation_worker.email
}

output "service_account_id" {
  description = "Unique ID of the translation worker service account"
  value       = google_service_account.translation_worker.unique_id
}

# Cloud Run Worker Pool
output "worker_pool_name" {
  description = "Name of the Cloud Run worker pool job"
  value       = google_cloud_run_v2_job.translation_worker_pool.name
}

output "worker_pool_id" {
  description = "Full resource ID of the Cloud Run worker pool"
  value       = google_cloud_run_v2_job.translation_worker_pool.id
}

output "worker_pool_location" {
  description = "Location of the Cloud Run worker pool"
  value       = google_cloud_run_v2_job.translation_worker_pool.location
}

# Cloud Scheduler
output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job that triggers the worker pool"
  value       = google_cloud_scheduler_job.worker_trigger.name
}

output "scheduler_job_id" {
  description = "Full resource ID of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.worker_trigger.id
}

# Network Resources
output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.translation_network.name
}

output "vpc_network_id" {
  description = "Full resource ID of the VPC network"
  value       = google_compute_network.translation_network.id
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = google_compute_subnetwork.translation_subnet.name
}

output "subnet_id" {
  description = "Full resource ID of the subnet"
  value       = google_compute_subnetwork.translation_subnet.id
}

output "subnet_cidr" {
  description = "CIDR range of the subnet"
  value       = google_compute_subnetwork.translation_subnet.ip_cidr_range
}

# Monitoring and Logging
output "monitoring_alert_policy_id" {
  description = "ID of the monitoring alert policy (if monitoring is enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.worker_pool_errors[0].name : null
}

output "log_sink_name" {
  description = "Name of the log sink for BigQuery analytics (if logging is enabled)"
  value       = var.enable_logging ? google_logging_project_sink.translation_logs[0].name : null
}

output "log_sink_writer_identity" {
  description = "Writer identity of the log sink (if logging is enabled)"
  value       = var.enable_logging ? google_logging_project_sink.translation_logs[0].writer_identity : null
}

# Cloud Build
output "build_trigger_id" {
  description = "ID of the Cloud Build trigger (if container image is not provided)"
  value       = var.container_image == "" ? google_cloudbuild_trigger.worker_build[0].trigger_id : null
}

output "container_image" {
  description = "Container image used for the worker pool"
  value       = var.container_image != "" ? var.container_image : "gcr.io/${var.project_id}/translation-worker:latest"
}

# API Endpoints and URLs
output "translation_api_endpoint" {
  description = "Google Cloud Translation API endpoint"
  value       = "https://translation.googleapis.com"
}

output "bigquery_console_url" {
  description = "URL to access BigQuery dataset in Google Cloud Console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.content_analytics.dataset_id}"
}

output "cloud_run_console_url" {
  description = "URL to access Cloud Run job in Google Cloud Console"
  value       = "https://console.cloud.google.com/run/jobs/details/${var.region}/${google_cloud_run_v2_job.translation_worker_pool.name}?project=${var.project_id}"
}

output "storage_console_url" {
  description = "URL to access Cloud Storage buckets in Google Cloud Console"
  value       = "https://console.cloud.google.com/storage/browser?project=${var.project_id}"
}

output "pubsub_console_url" {
  description = "URL to access Pub/Sub topics in Google Cloud Console"
  value       = "https://console.cloud.google.com/cloudpubsub/topic/list?project=${var.project_id}"
}

# Sample Configuration for Testing
output "sample_translation_request" {
  description = "Sample JSON for testing the translation pipeline"
  value = jsonencode({
    content_id       = "sample-content-001"
    batch_id        = "batch-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
    source_language = "en"
    target_languages = ["es", "fr", "de", "ja"]
    source_uri      = "gs://${google_storage_bucket.source_content.name}/sample-content.txt"
    output_uri_prefix = "gs://${google_storage_bucket.translated_content.name}/sample-output/"
    content_type    = "marketing"
    mime_type       = "text/plain"
  })
}

# CLI Commands for Quick Operations
output "upload_sample_content_command" {
  description = "CLI command to upload sample content to source bucket"
  value       = "gsutil cp sample-content.txt gs://${google_storage_bucket.source_content.name}/"
}

output "publish_translation_request_command" {
  description = "CLI command to publish a translation request"
  value       = "echo '${jsonencode({
    content_id       = "sample-content-001"
    batch_id        = "batch-test"
    source_language = "en"
    target_languages = ["es", "fr"]
    source_uri      = "gs://${google_storage_bucket.source_content.name}/sample-content.txt"
    output_uri_prefix = "gs://${google_storage_bucket.translated_content.name}/output/"
    content_type    = "general"
    mime_type       = "text/plain"
  })}' | gcloud pubsub topics publish ${google_pubsub_topic.content_processing.name} --message=-"
}

output "run_worker_job_command" {
  description = "CLI command to manually trigger the worker job"
  value       = "gcloud run jobs execute ${google_cloud_run_v2_job.translation_worker_pool.name} --region=${var.region}"
}

output "view_logs_command" {
  description = "CLI command to view worker job logs"
  value       = "gcloud logging read 'resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${google_cloud_run_v2_job.translation_worker_pool.name}\"' --limit=50 --format='table(timestamp,textPayload)'"
}

output "query_engagement_metrics_command" {
  description = "CLI command to query engagement metrics from BigQuery"
  value       = "bq query --use_legacy_sql=false 'SELECT language, AVG(engagement_score) as avg_engagement FROM \\`${var.project_id}.${google_bigquery_dataset.content_analytics.dataset_id}.${google_bigquery_table.engagement_metrics.table_id}\\` GROUP BY language ORDER BY avg_engagement DESC'"
}

# Cost Estimation Information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the infrastructure (USD, approximate)"
  value = {
    cloud_storage_standard = "~$5-15 per month (depends on data volume)"
    pubsub_messages       = "~$1-5 per month (depends on message volume)"
    cloud_run_jobs        = "~$10-50 per month (depends on execution time)"
    bigquery_storage      = "~$1-10 per month (depends on data volume)"
    translation_api       = "~$20-200 per month (depends on translation volume)"
    networking           = "~$1-5 per month"
    total_estimate       = "~$38-285 per month (highly variable based on usage)"
  }
}

# Security and Compliance Information
output "security_features" {
  description = "Security features implemented in this infrastructure"
  value = {
    iam_least_privilege     = "Service accounts with minimal required permissions"
    bucket_uniform_access   = "Uniform bucket-level access enabled on all buckets"
    private_google_access   = "Private Google access enabled for secure API communication"
    vpc_network            = "Dedicated VPC network for workload isolation"
    encryption_at_rest     = "Google-managed encryption for all storage"
    encryption_in_transit  = "TLS encryption for all API communications"
    audit_logging          = "Cloud Audit Logs enabled for all operations"
    dead_letter_queue      = "Dead letter queue for failed message handling"
  }
}