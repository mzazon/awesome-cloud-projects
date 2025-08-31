# Outputs for Social Media Video Creation with Veo 3 and Vertex AI

# Project and Resource Information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Storage Resources
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for video files"
  value       = google_storage_bucket.video_storage.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.video_storage.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.video_storage.self_link
}

# Cloud Functions Information
output "video_generator_function_name" {
  description = "Name of the video generator Cloud Function"
  value       = google_cloudfunctions2_function.video_generator.name
}

output "video_generator_function_url" {
  description = "HTTPS URL of the video generator Cloud Function"
  value       = google_cloudfunctions2_function.video_generator.service_config[0].uri
}

output "quality_validator_function_name" {
  description = "Name of the quality validator Cloud Function"
  value       = google_cloudfunctions2_function.quality_validator.name
}

output "quality_validator_function_url" {
  description = "HTTPS URL of the quality validator Cloud Function"
  value       = google_cloudfunctions2_function.quality_validator.service_config[0].uri
}

output "operation_monitor_function_name" {
  description = "Name of the operation monitor Cloud Function"
  value       = google_cloudfunctions2_function.operation_monitor.name
}

output "operation_monitor_function_url" {
  description = "HTTPS URL of the operation monitor Cloud Function"
  value       = google_cloudfunctions2_function.operation_monitor.service_config[0].uri
}

# Service Account Information
output "service_account_email" {
  description = "Email address of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.email
}

output "service_account_id" {
  description = "ID of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.account_id
}

# API Status
output "enabled_apis" {
  description = "List of Google Cloud APIs that have been enabled"
  value       = [for api in google_project_service.required_apis : api.service]
}

# Function Configuration Details
output "function_runtime" {
  description = "Runtime version used for Cloud Functions"
  value       = "python311"
}

output "max_instances_per_function" {
  description = "Maximum number of instances configured for each function"
  value       = var.max_instances
}

output "unauthenticated_access_enabled" {
  description = "Whether unauthenticated access is enabled for the functions"
  value       = var.allow_unauthenticated_invocation
}

# Video Configuration
output "default_video_settings" {
  description = "Default video generation settings"
  value = {
    duration      = var.default_video_duration
    aspect_ratio  = var.default_aspect_ratio
    resolution    = var.video_resolution
    veo_model     = var.veo_model_version
    gemini_model  = var.gemini_model_version
  }
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the video generation pipeline"
  value = <<-EOT
    Video Generation Pipeline is now deployed! Here's how to use it:

    1. Generate a video:
       curl -X POST ${google_cloudfunctions2_function.video_generator.service_config[0].uri} \
         -H "Content-Type: application/json" \
         -d '{
           "prompt": "A beautiful sunset over mountains",
           "duration": ${var.default_video_duration},
           "aspect_ratio": "${var.default_aspect_ratio}"
         }'

    2. Monitor operation status:
       curl -X POST ${google_cloudfunctions2_function.operation_monitor.service_config[0].uri} \
         -H "Content-Type: application/json" \
         -d '{"operation_name": "OPERATION_NAME_FROM_STEP_1"}'

    3. Validate video quality:
       curl -X POST ${google_cloudfunctions2_function.quality_validator.service_config[0].uri} \
         -H "Content-Type: application/json" \
         -d '{"video_uri": "gs://${google_storage_bucket.video_storage.name}/raw-videos/VIDEO_FILE.mp4"}'

    4. Access your videos:
       gsutil ls gs://${google_storage_bucket.video_storage.name}/raw-videos/
       gsutil ls gs://${google_storage_bucket.video_storage.name}/processed-videos/

    Note: Replace OPERATION_NAME_FROM_STEP_1 with the actual operation name returned from the video generation request.
    ${var.allow_unauthenticated_invocation ? "" : "Authentication is required for function invocation."}
  EOT
}

# Cost and Management Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    cloud_functions_executions = "Variable based on usage (first 2M invocations free)"
    cloud_storage             = "~$0.02-0.04 per GB stored (Standard class)"
    vertex_ai_veo            = "Variable based on video generation requests"
    vertex_ai_gemini         = "Variable based on content analysis requests"
    cloud_logging            = "First 50GB free, then $0.50 per GB"
    note                     = "Actual costs depend on usage patterns and video generation frequency"
  }
}

output "management_urls" {
  description = "Useful Google Cloud Console URLs for managing the deployment"
  value = {
    cloud_functions_console = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
    cloud_storage_console   = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.video_storage.name}?project=${var.project_id}"
    cloud_logging_console   = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
    vertex_ai_console      = "https://console.cloud.google.com/vertex-ai?project=${var.project_id}"
    cloud_monitoring_console = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
  }
}

# Security and Access Information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    uniform_bucket_level_access = google_storage_bucket.video_storage.uniform_bucket_level_access
    service_account_permissions = [
      "roles/storage.objectAdmin",
      "roles/aiplatform.user", 
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
      "roles/cloudfunctions.invoker"
    ]
    encryption = var.encryption_key_name != "" ? "Customer-managed" : "Google-managed"
    public_access = var.allow_unauthenticated_invocation ? "Enabled" : "Disabled"
  }
}

# Lifecycle and Backup Information  
output "lifecycle_configuration" {
  description = "Bucket lifecycle management configuration"
  value = {
    delete_after_days    = var.lifecycle_delete_age_days
    nearline_after_days  = var.lifecycle_nearline_age_days
    versioning_enabled   = google_storage_bucket.video_storage.versioning[0].enabled
    soft_delete_retention = "7 days"
  }
}

# Monitoring and Alerting
output "monitoring_configuration" {
  description = "Monitoring and alerting configuration"
  value = {
    cloud_monitoring_enabled = var.enable_monitoring
    audit_logging_enabled   = var.enable_audit_logs
    debug_logging_enabled   = var.enable_debug_logging
    notification_email      = var.notification_email != "" ? var.notification_email : "Not configured"
    budget_limit            = var.budget_amount > 0 ? "$${var.budget_amount} USD" : "No budget limit set"
  }
}

# Network Configuration
output "network_configuration" {
  description = "Network configuration details"
  value = {
    vpc_network     = var.vpc_network != "" ? var.vpc_network : "Default network"
    vpc_subnet      = var.vpc_subnet != "" ? var.vpc_subnet : "Default subnet"
    vpc_connector   = var.vpc_connector != "" ? var.vpc_connector : "No VPC connector"
    ingress_settings = "ALLOW_ALL"
  }
}

# Resource Labels
output "applied_labels" {
  description = "Labels applied to resources"
  value = merge(var.labels, {
    component   = "video-generation-pipeline"
    deployed_by = "terraform"
    region      = var.region
  })
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Quick start commands for testing the deployment"
  value = {
    test_video_generation = "curl -X POST ${google_cloudfunctions2_function.video_generator.service_config[0].uri} -H 'Content-Type: application/json' -d '{\"prompt\": \"A calm ocean wave at sunset\", \"duration\": 8, \"aspect_ratio\": \"9:16\"}'"
    list_generated_videos = "gsutil ls gs://${google_storage_bucket.video_storage.name}/raw-videos/"
    check_function_logs   = "gcloud functions logs read ${google_cloudfunctions2_function.video_generator.name} --region=${var.region} --project=${var.project_id}"
    view_bucket_contents  = "gsutil ls -la gs://${google_storage_bucket.video_storage.name}/"
  }
}