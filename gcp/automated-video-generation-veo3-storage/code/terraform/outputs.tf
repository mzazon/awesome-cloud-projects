# Project and region information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# Storage bucket information
output "input_bucket_name" {
  description = "Name of the Cloud Storage bucket for creative briefs"
  value       = google_storage_bucket.input_bucket.name
}

output "input_bucket_url" {
  description = "URL of the input storage bucket"
  value       = google_storage_bucket.input_bucket.url
}

output "output_bucket_name" {
  description = "Name of the Cloud Storage bucket for generated videos"
  value       = google_storage_bucket.output_bucket.name
}

output "output_bucket_url" {
  description = "URL of the output storage bucket"
  value       = google_storage_bucket.output_bucket.url
}

# Service account information
output "service_account_email" {
  description = "Email address of the video generation service account"
  value       = google_service_account.video_generation_sa.email
}

output "service_account_id" {
  description = "ID of the video generation service account"
  value       = google_service_account.video_generation_sa.account_id
}

# Cloud Functions information
output "video_generation_function_name" {
  description = "Name of the video generation Cloud Function"
  value       = google_cloudfunctions2_function.video_generation.name
}

output "video_generation_function_url" {
  description = "URL of the video generation Cloud Function"
  value       = google_cloudfunctions2_function.video_generation.service_config[0].uri
}

output "orchestrator_function_name" {
  description = "Name of the orchestrator Cloud Function"
  value       = google_cloudfunctions2_function.orchestrator.name
}

output "orchestrator_function_url" {
  description = "URL of the orchestrator Cloud Function"
  value       = google_cloudfunctions2_function.orchestrator.service_config[0].uri
}

# Cloud Scheduler information
output "automated_scheduler_job_name" {
  description = "Name of the automated video generation scheduler job"
  value       = google_cloud_scheduler_job.automated_video_generation.name
}

output "automated_scheduler_schedule" {
  description = "Schedule for automated video generation"
  value       = google_cloud_scheduler_job.automated_video_generation.schedule
}

output "on_demand_scheduler_job_name" {
  description = "Name of the on-demand video generation scheduler job"
  value       = google_cloud_scheduler_job.on_demand_video_generation.name
}

# Monitoring information
output "monitoring_enabled" {
  description = "Whether monitoring and alerting is enabled"
  value       = var.enable_monitoring
}

output "alert_policy_id" {
  description = "ID of the monitoring alert policy (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_error_rate[0].name : null
}

# Configuration information
output "veo_model_name" {
  description = "Name of the Veo 3 model used for video generation"
  value       = var.veo_model_name
}

output "default_video_resolution" {
  description = "Default resolution for generated videos"
  value       = var.default_video_resolution
}

output "default_video_duration" {
  description = "Default duration for generated videos in seconds"
  value       = var.default_video_duration
}

# Usage instructions
output "sample_curl_command_video_generation" {
  description = "Sample curl command to test video generation function"
  value = "curl -X POST '${google_cloudfunctions2_function.video_generation.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"prompt\": \"A peaceful lake at sunset with mountains in the background\", \"output_bucket\": \"${google_storage_bucket.output_bucket.name}\", \"resolution\": \"1080p\"}'"
}

output "sample_curl_command_orchestrator" {
  description = "Sample curl command to test orchestrator function"
  value = "curl -X POST '${google_cloudfunctions2_function.orchestrator.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"trigger\": \"manual\", \"batch_size\": 5}'"
}

output "gsutil_upload_brief_command" {
  description = "Sample gsutil command to upload a creative brief"
  value = "gsutil cp your_brief.json gs://${google_storage_bucket.input_bucket.name}/briefs/"
}

output "gsutil_list_videos_command" {
  description = "Sample gsutil command to list generated videos"
  value = "gsutil ls gs://${google_storage_bucket.output_bucket.name}/videos/"
}

output "gsutil_list_metadata_command" {
  description = "Sample gsutil command to list video metadata"
  value = "gsutil ls gs://${google_storage_bucket.output_bucket.name}/metadata/"
}

output "gsutil_list_reports_command" {
  description = "Sample gsutil command to list batch processing reports"
  value = "gsutil ls gs://${google_storage_bucket.output_bucket.name}/reports/"
}

# Cloud Console URLs for management
output "storage_console_url" {
  description = "URL to view storage buckets in Google Cloud Console"
  value = "https://console.cloud.google.com/storage/browser?project=${var.project_id}"
}

output "functions_console_url" {
  description = "URL to view Cloud Functions in Google Cloud Console"
  value = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
}

output "scheduler_console_url" {
  description = "URL to view Cloud Scheduler jobs in Google Cloud Console"
  value = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
}

output "monitoring_console_url" {
  description = "URL to view monitoring dashboards in Google Cloud Console"
  value = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
}

output "vertex_ai_console_url" {
  description = "URL to view Vertex AI in Google Cloud Console"
  value = "https://console.cloud.google.com/vertex-ai?project=${var.project_id}"
}

# Cost estimation information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the video generation infrastructure"
  value = {
    storage_standard_gb = "Storage costs depend on usage: ~$0.02/GB/month for STANDARD class"
    cloud_functions     = "Functions: $0.40/million invocations + $0.0000025/GB-second"
    cloud_scheduler     = "Scheduler: $0.10/job/month for scheduled jobs"
    vertex_ai_veo3     = "Veo 3 generation: $0.75 per second of generated video content"
    total_note         = "Total costs vary significantly based on video generation volume"
  }
}

# Security and compliance information
output "iam_roles_assigned" {
  description = "IAM roles assigned to the service account"
  value = [
    "roles/aiplatform.user",
    "roles/storage.admin", 
    "roles/logging.logWriter"
  ]
}

output "security_features_enabled" {
  description = "Security features enabled in the deployment"
  value = {
    bucket_versioning              = var.enable_versioning
    uniform_bucket_level_access   = true
    service_account_isolation     = true
    function_timeout_limits       = true
    cors_configured              = true
  }
}