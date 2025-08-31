# Output definitions for the Automated Code Review Pipeline
# This file defines all outputs that provide important information about deployed resources

# Source Control Outputs
output "repository_url" {
  description = "Clone URL for the Cloud Source Repository"
  value       = google_sourcerepo_repository.code_review_repo.url
  sensitive   = false
}

output "repository_name" {
  description = "Name of the Cloud Source Repository"
  value       = google_sourcerepo_repository.code_review_repo.name
  sensitive   = false
}

output "repository_project_id" {
  description = "Project ID where the repository is hosted"
  value       = google_sourcerepo_repository.code_review_repo.project
  sensitive   = false
}

# Cloud Functions Outputs
output "code_review_function_name" {
  description = "Name of the code review Cloud Function"
  value       = google_cloudfunctions2_function.code_review_function.name
  sensitive   = false
}

output "code_review_function_url" {
  description = "HTTP trigger URL for the code review Cloud Function"
  value       = google_cloudfunctions2_function.code_review_function.service_config[0].uri
  sensitive   = false
}

output "code_review_function_service_account" {
  description = "Service account email used by the code review function"
  value       = google_service_account.function_service_account.email
  sensitive   = false
}

output "metrics_function_name" {
  description = "Name of the metrics collection Cloud Function"
  value       = google_cloudfunctions2_function.metrics_function.name
  sensitive   = false
}

output "metrics_function_url" {
  description = "HTTP trigger URL for the metrics collection Cloud Function"
  value       = google_cloudfunctions2_function.metrics_function.service_config[0].uri
  sensitive   = false
}

# Cloud Build Outputs
output "main_build_trigger_name" {
  description = "Name of the main branch Cloud Build trigger"
  value       = google_cloudbuild_trigger.main_branch_trigger.name
  sensitive   = false
}

output "main_build_trigger_id" {
  description = "ID of the main branch Cloud Build trigger"
  value       = google_cloudbuild_trigger.main_branch_trigger.trigger_id
  sensitive   = false
}

output "feature_build_trigger_name" {
  description = "Name of the feature branch Cloud Build trigger (if created)"
  value       = length(google_cloudbuild_trigger.feature_branch_trigger) > 0 ? google_cloudbuild_trigger.feature_branch_trigger[0].name : null
  sensitive   = false
}

output "feature_build_trigger_id" {
  description = "ID of the feature branch Cloud Build trigger (if created)"
  value       = length(google_cloudbuild_trigger.feature_branch_trigger) > 0 ? google_cloudbuild_trigger.feature_branch_trigger[0].trigger_id : null
  sensitive   = false
}

output "build_triggers_list" {
  description = "List of all Cloud Build trigger names"
  value = concat(
    [google_cloudbuild_trigger.main_branch_trigger.name],
    length(google_cloudbuild_trigger.feature_branch_trigger) > 0 ? [google_cloudbuild_trigger.feature_branch_trigger[0].name] : []
  )
  sensitive = false
}

# Cloud Tasks Outputs
output "task_queue_name" {
  description = "Name of the Cloud Tasks queue for asynchronous processing"
  value       = google_cloud_tasks_queue.code_review_queue.name
  sensitive   = false
}

output "task_queue_location" {
  description = "Location of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.code_review_queue.location
  sensitive   = false
}

output "task_queue_full_name" {
  description = "Full resource name of the Cloud Tasks queue"
  value       = "projects/${var.project_id}/locations/${var.region}/queues/${google_cloud_tasks_queue.code_review_queue.name}"
  sensitive   = false
}

# Cloud Storage Outputs
output "build_artifacts_bucket_name" {
  description = "Name of the Cloud Storage bucket for build artifacts"
  value       = google_storage_bucket.build_artifacts.name
  sensitive   = false
}

output "build_artifacts_bucket_url" {
  description = "URL of the build artifacts bucket"
  value       = "gs://${google_storage_bucket.build_artifacts.name}"
  sensitive   = false
}

output "metrics_storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for metrics data"
  value       = google_storage_bucket.metrics_storage.name
  sensitive   = false
}

output "metrics_storage_bucket_url" {
  description = "URL of the metrics storage bucket"
  value       = "gs://${google_storage_bucket.metrics_storage.name}"
  sensitive   = false
}

# Firebase Outputs
output "firebase_project_id" {
  description = "Firebase project ID for Studio integration"
  value       = local.firebase_project
  sensitive   = false
}

output "firebase_studio_enabled" {
  description = "Whether Firebase Studio integration is enabled"
  value       = var.enable_firebase_studio
  sensitive   = false
}

output "firebase_studio_workspace_url" {
  description = "URL to create Firebase Studio workspace (if enabled)"
  value       = var.enable_firebase_studio ? "https://studio.firebase.google.com/project/${local.firebase_project}/workspace/import" : null
  sensitive   = false
}

# AI/ML Integration Outputs
output "gemini_integration_enabled" {
  description = "Whether Gemini AI integration is enabled"
  value       = var.enable_gemini_integration
  sensitive   = false
}

output "gemini_model" {
  description = "Gemini model configured for code analysis"
  value       = var.gemini_model
  sensitive   = false
}

# Monitoring and Observability Outputs
output "cloud_monitoring_enabled" {
  description = "Whether Cloud Monitoring is enabled"
  value       = var.enable_cloud_monitoring
  sensitive   = false
}

output "cloud_logging_enabled" {
  description = "Whether Cloud Logging is enabled"
  value       = var.enable_cloud_logging
  sensitive   = false
}

output "log_sink_name" {
  description = "Name of the Cloud Logging sink (if enabled)"
  value       = var.enable_cloud_logging ? google_logging_project_sink.code_review_logs[0].name : null
  sensitive   = false
}

output "alert_policy_name" {
  description = "Name of the Cloud Monitoring alert policy (if enabled)"
  value       = var.enable_cloud_monitoring ? google_monitoring_alert_policy.function_error_rate[0].display_name : null
  sensitive   = false
}

# Budget and Cost Management Outputs
output "budget_alert_enabled" {
  description = "Whether budget alerts are enabled"
  value       = var.enable_budget_alerts
  sensitive   = false
}

output "monthly_budget_amount" {
  description = "Monthly budget amount in USD"
  value       = var.monthly_budget_amount
  sensitive   = false
}

# Resource Summary Outputs
output "deployment_summary" {
  description = "Summary of all deployed resources"
  value = {
    project_id          = var.project_id
    region              = var.region
    environment         = var.environment
    repository_name     = google_sourcerepo_repository.code_review_repo.name
    function_count      = 2
    build_triggers      = length(local.build_triggers_list)
    storage_buckets     = 2
    task_queues         = 1
    firebase_enabled    = var.enable_firebase_studio
    monitoring_enabled  = var.enable_cloud_monitoring
    budget_enabled      = var.enable_budget_alerts
  }
  sensitive = false
}

# Quick Start Commands Output
output "quick_start_commands" {
  description = "Commands to get started with the deployed infrastructure"
  value = {
    clone_repository = "gcloud source repos clone ${google_sourcerepo_repository.code_review_repo.name} --project=${var.project_id}"
    test_function = "curl -X POST ${google_cloudfunctions2_function.code_review_function.service_config[0].uri} -H 'Content-Type: application/json' -d '{\"test\": true}'"
    check_builds = "gcloud builds list --project=${var.project_id} --limit=5"
    view_logs = "gcloud logging read 'resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.code_review_function.name}\"' --project=${var.project_id} --limit=20"
    manage_queue = "gcloud tasks queues describe ${google_cloud_tasks_queue.code_review_queue.name} --location=${var.region} --project=${var.project_id}"
  }
  sensitive = false
}

# Configuration URLs Output
output "configuration_urls" {
  description = "Important URLs for configuration and monitoring"
  value = {
    cloud_build_console     = "https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}"
    cloud_functions_console = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
    source_repos_console    = "https://console.cloud.google.com/source/repos?project=${var.project_id}"
    cloud_tasks_console     = "https://console.cloud.google.com/cloudtasks/queues?project=${var.project_id}"
    storage_console         = "https://console.cloud.google.com/storage/browser?project=${var.project_id}"
    firebase_console        = var.enable_firebase_studio ? "https://console.firebase.google.com/project/${local.firebase_project}" : null
    monitoring_console      = var.enable_cloud_monitoring ? "https://console.cloud.google.com/monitoring?project=${var.project_id}" : null
  }
  sensitive = false
}

# Local values for computed outputs
locals {
  build_triggers_list = concat(
    [google_cloudbuild_trigger.main_branch_trigger.name],
    length(google_cloudbuild_trigger.feature_branch_trigger) > 0 ? [google_cloudbuild_trigger.feature_branch_trigger[0].name] : []
  )
}

# Next Steps Output
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Clone the repository: gcloud source repos clone ${google_sourcerepo_repository.code_review_repo.name} --project=${var.project_id}",
    "2. Set up Firebase Studio workspace: ${var.enable_firebase_studio ? "https://studio.firebase.google.com/project/${local.firebase_project}/workspace/import" : "Firebase Studio not enabled"}",
    "3. Configure your development environment with the cloned repository",
    "4. Add your application code and cloudbuild.yaml configuration",
    "5. Push code to trigger the automated review pipeline",
    "6. Monitor builds: https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}",
    "7. Review function logs for code analysis results",
    "8. Configure budget alerts if needed: Monthly budget set to $${var.monthly_budget_amount}"
  ]
  sensitive = false
}

# Resource Tags Output
output "resource_labels" {
  description = "Labels applied to all resources"
  value       = local.default_labels
  sensitive   = false
}

# Security Information Output
output "security_summary" {
  description = "Security configuration summary"
  value = {
    service_account_email       = google_service_account.function_service_account.email
    private_google_access      = var.enable_private_google_access
    uniform_bucket_access      = true
    public_access_prevention   = "enforced"
    function_ingress_settings  = "ALLOW_ALL"
    cloud_armor_enabled        = var.enable_cloud_armor
  }
  sensitive = false
}