# ============================================================================
# OUTPUT VALUES
# ============================================================================
# These outputs provide essential information about the deployed infrastructure
# for verification, integration, and operational purposes.
# ============================================================================

# Storage Outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for video processing"
  value       = google_storage_bucket.video_bucket.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.video_bucket.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.video_bucket.self_link
}

output "processing_folder_path" {
  description = "Path to the processing folder for video uploads"
  value       = "gs://${google_storage_bucket.video_bucket.name}/processing/"
}

output "approved_folder_path" {
  description = "Path to the approved videos folder"
  value       = "gs://${google_storage_bucket.video_bucket.name}/approved/"
}

output "flagged_folder_path" {
  description = "Path to the flagged videos folder"
  value       = "gs://${google_storage_bucket.video_bucket.name}/flagged/"
}

# Messaging Outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for video moderation events"
  value       = google_pubsub_topic.video_moderation.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.video_moderation.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription"
  value       = google_pubsub_subscription.video_moderation_sub.name
}

output "pubsub_dead_letter_topic" {
  description = "Name of the dead letter queue topic"
  value       = google_pubsub_topic.video_moderation_dlq.name
}

# Function Outputs
output "function_name" {
  description = "Name of the Cloud Function for video moderation"
  value       = google_cloudfunctions2_function.video_moderator.name
}

output "function_url" {
  description = "URL of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.video_moderator.service_config[0].uri
}

output "function_trigger_topic" {
  description = "Pub/Sub topic that triggers the function"
  value       = google_cloudfunctions2_function.video_moderator.event_trigger[0].pubsub_topic
}

output "function_service_account" {
  description = "Service account used by the Cloud Function"
  value       = google_cloudfunctions2_function.video_moderator.service_config[0].service_account_email
}

# Scheduler Outputs
output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.video_moderation_scheduler.name
}

output "scheduler_job_schedule" {
  description = "Cron schedule of the scheduler job"
  value       = google_cloud_scheduler_job.video_moderation_scheduler.schedule
}

output "scheduler_job_timezone" {
  description = "Timezone of the scheduler job"
  value       = google_cloud_scheduler_job.video_moderation_scheduler.time_zone
}

output "scheduler_service_account" {
  description = "Service account used by the Cloud Scheduler"
  value       = google_service_account.scheduler_sa.email
}

# Security and IAM Outputs
output "service_account_email" {
  description = "Email of the dedicated scheduler service account"
  value       = google_service_account.scheduler_sa.email
}

output "service_account_unique_id" {
  description = "Unique ID of the scheduler service account"
  value       = google_service_account.scheduler_sa.unique_id
}

# Configuration Outputs
output "video_processing_config" {
  description = "Configuration parameters for video processing"
  value = {
    function_timeout                     = var.function_timeout
    function_memory                     = var.function_memory
    function_max_instances              = var.function_max_instances
    explicit_content_threshold          = var.explicit_content_threshold
    explicit_content_ratio_threshold    = var.explicit_content_ratio_threshold
    schedule_expression                 = var.schedule_expression
    message_retention_duration          = var.message_retention_duration
    ack_deadline_seconds               = var.ack_deadline_seconds
  }
  sensitive = false
}

# Project and Regional Information
output "project_id" {
  description = "GCP Project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "GCP region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "GCP zone for zonal resources"
  value       = var.zone
}

# Monitoring and Operations
output "log_sink_name" {
  description = "Name of the logging sink for function logs"
  value       = google_logging_project_sink.video_moderation_logs.name
}

output "log_sink_destination" {
  description = "Destination of the logging sink"
  value       = google_logging_project_sink.video_moderation_logs.destination
}

# Testing and Validation Commands
output "test_commands" {
  description = "Commands for testing the video moderation workflow"
  value = {
    upload_test_video = "gsutil cp test-video.mp4 gs://${google_storage_bucket.video_bucket.name}/processing/"
    trigger_manual_run = "gcloud scheduler jobs run ${google_cloud_scheduler_job.video_moderation_scheduler.name} --location=${var.region}"
    check_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.video_moderator.name} --region=${var.region} --limit=50"
    list_processed_videos = "gsutil ls -r gs://${google_storage_bucket.video_bucket.name}/"
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the video moderation infrastructure"
  value = {
    storage_class = "Consider using NEARLINE or COLDLINE storage for long-term video archival"
    function_memory = "Monitor function memory usage and adjust if needed (current: ${var.function_memory})"
    schedule_frequency = "Adjust scheduler frequency based on video upload patterns (current: ${var.schedule_expression})"
    lifecycle_management = "Bucket lifecycle is set to delete objects after ${var.bucket_lifecycle_age} days"
  }
}

# Integration Information
output "integration_endpoints" {
  description = "Endpoints and identifiers for integrating with external systems"
  value = {
    bucket_name = google_storage_bucket.video_bucket.name
    pubsub_topic = google_pubsub_topic.video_moderation.name
    function_trigger_url = google_cloudfunctions2_function.video_moderator.service_config[0].uri
    scheduler_job_resource = google_cloud_scheduler_job.video_moderation_scheduler.id
  }
  sensitive = false
}

# Deployment Status
output "deployment_summary" {
  description = "Summary of the deployed video moderation infrastructure"
  value = {
    status = "Video moderation infrastructure deployed successfully"
    components = [
      "Cloud Storage bucket with organized folder structure",
      "Pub/Sub topic and subscription for event-driven processing",
      "Cloud Function (Gen2) for video analysis using Video Intelligence API",
      "Cloud Scheduler for automated batch processing",
      "IAM service accounts and permissions",
      "Monitoring and logging configuration"
    ]
    next_steps = [
      "Upload test videos to the processing folder",
      "Monitor function logs for processing results",
      "Adjust moderation thresholds based on business requirements",
      "Set up alerting for failed processing events"
    ]
  }
}