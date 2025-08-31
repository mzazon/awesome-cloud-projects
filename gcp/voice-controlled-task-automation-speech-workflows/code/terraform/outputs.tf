# Output values for voice-controlled task automation infrastructure

# Project and Region Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.resource_suffix
}

# Cloud Storage Outputs
output "audio_bucket_name" {
  description = "Name of the Cloud Storage bucket for audio files"
  value       = google_storage_bucket.audio_files.name
}

output "audio_bucket_url" {
  description = "URL of the Cloud Storage bucket for audio files"
  value       = google_storage_bucket.audio_files.url
}

output "functions_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.functions_source.name
}

# Cloud Functions Outputs
output "voice_processor_function_name" {
  description = "Name of the voice processing Cloud Function"
  value       = google_cloudfunctions_function.voice_processor.name
}

output "voice_processor_function_url" {
  description = "HTTP trigger URL for the voice processing function"
  value       = google_cloudfunctions_function.voice_processor.https_trigger_url
  sensitive   = false
}

output "task_processor_function_name" {
  description = "Name of the task processing Cloud Function"
  value       = google_cloudfunctions_function.task_processor.name
}

output "task_processor_function_url" {
  description = "HTTP trigger URL for the task processing function"
  value       = google_cloudfunctions_function.task_processor.https_trigger_url
  sensitive   = false
}

# Cloud Workflows Outputs
output "workflow_name" {
  description = "Name of the Cloud Workflow for task automation"
  value       = google_workflows_workflow.task_automation.name
}

output "workflow_id" {
  description = "Full resource ID of the Cloud Workflow"
  value       = google_workflows_workflow.task_automation.id
}

# Cloud Tasks Outputs
output "task_queue_name" {
  description = "Name of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.task_queue.name
}

output "task_queue_id" {
  description = "Full resource ID of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.task_queue.id
}

# Service Account Outputs
output "voice_processor_service_account_email" {
  description = "Email of the voice processor service account"
  value       = google_service_account.voice_processor_sa.email
}

output "task_processor_service_account_email" {
  description = "Email of the task processor service account"
  value       = google_service_account.task_processor_sa.email
}

# API Configuration Outputs
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value = [
    for api in google_project_service.required_apis : api.service
  ]
}

# Testing and Integration Outputs
output "speech_language_code" {
  description = "Configured language code for speech recognition"
  value       = var.speech_language_code
}

output "speech_model" {
  description = "Configured speech recognition model"
  value       = var.speech_model
}

# Monitoring Outputs
output "monitoring_dashboard_id" {
  description = "ID of the monitoring dashboard (if enabled)"
  value       = var.enable_detailed_monitoring ? google_monitoring_dashboard.voice_automation_dashboard[0].id : null
}

output "logging_sink_name" {
  description = "Name of the centralized logging sink (if enabled)"
  value       = var.enable_detailed_monitoring ? google_logging_project_sink.voice_automation_logs[0].name : null
}

# Configuration Information for Usage
output "usage_instructions" {
  description = "Instructions for testing the voice automation system"
  value = <<-EOT
    Voice Automation System Deployed Successfully!
    
    ## Testing the System:
    
    1. **Upload an audio file to test voice processing:**
       curl -X POST "${google_cloudfunctions_function.voice_processor.https_trigger_url}" \
         -H "Content-Type: application/json" \
         -d '{"audio_uri": "gs://${google_storage_bucket.audio_files.name}/test-audio.wav"}'
    
    2. **Test with a text command (for testing without audio):**
       curl -X POST "${google_cloudfunctions_function.voice_processor.https_trigger_url}" \
         -H "Content-Type: application/json" \
         -d '{"text_command": "create task urgent meeting preparation", "test_mode": true}'
    
    3. **Monitor workflow executions:**
       gcloud workflows executions list --workflow="${google_workflows_workflow.task_automation.name}" --location="${var.region}"
    
    4. **Check task queue status:**
       gcloud tasks queues describe "${google_cloud_tasks_queue.task_queue.name}" --location="${var.region}"
    
    5. **View logs:**
       gcloud logging read 'resource.type="cloud_function" AND resource.labels.function_name="${google_cloudfunctions_function.voice_processor.name}"' --limit=10
    
    ## Resources Created:
    - Audio Storage Bucket: ${google_storage_bucket.audio_files.name}
    - Voice Processor Function: ${google_cloudfunctions_function.voice_processor.name}
    - Task Processor Function: ${google_cloudfunctions_function.task_processor.name}
    - Workflow: ${google_workflows_workflow.task_automation.name}
    - Task Queue: ${google_cloud_tasks_queue.task_queue.name}
    
    ## Important Notes:
    - Audio files are automatically deleted after ${var.audio_file_retention_days} days
    - Functions are configured for ${var.speech_language_code} language
    - ${var.allow_unauthenticated_functions ? "Functions allow unauthenticated access (testing only)" : "Functions require authentication"}
  EOT
}

# Security Configuration Outputs
output "security_configuration" {
  description = "Security settings and recommendations"
  value = {
    allow_unauthenticated_functions = var.allow_unauthenticated_functions
    uniform_bucket_level_access     = google_storage_bucket.audio_files.uniform_bucket_level_access
    audio_file_retention_days       = var.audio_file_retention_days
    
    recommendations = var.allow_unauthenticated_functions ? [
      "⚠️  WARNING: Functions allow unauthenticated access",
      "🔒 For production, set allow_unauthenticated_functions = false",
      "🔑 Implement proper authentication and authorization",
      "🛡️  Consider using API Gateway for additional security layers"
    ] : [
      "✅ Functions require authentication",
      "🔒 Bucket has uniform access control enabled",
      "📝 Review IAM permissions for least privilege access"
    ]
  }
}

# Cost Optimization Information
output "cost_optimization_info" {
  description = "Information about cost optimization features"
  value = {
    audio_file_lifecycle_enabled = true
    retention_period_days        = var.audio_file_retention_days
    storage_class               = var.bucket_storage_class
    function_memory_allocation = {
      voice_processor = "${var.voice_processor_memory}MB"
      task_processor  = "${var.task_processor_memory}MB"
    }
    queue_rate_limits = {
      max_dispatches_per_second = var.task_queue_max_dispatches_per_second
      max_concurrent_dispatches = var.task_queue_max_concurrent_dispatches
    }
  }
}